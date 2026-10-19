package me.saffer.sill.core.ui

import me.saffer.sill.core.HostSettingsChange
import me.saffer.sill.core.HostSettingsState
import me.saffer.sill.core.InputEvent
import me.saffer.sill.core.Json
import me.saffer.sill.core.JsonNumber
import me.saffer.sill.core.Modifiers
import me.saffer.sill.core.StreamSettings
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.fail

/**
 * The shared design layer against the iOS app: ui-vectors.json is what iOSClient's own
 * PhonePortraitLayout.swift and HostSettingsLedger.swift computed (clients/design/generate.sh), and
 * the rest are the iOS layouts' numbers as their doc comments state them.
 */
class UiParityTest {
    @Suppress("UNCHECKED_CAST")
    private val vectors = Json.parse(javaClass.getResource("/sill/ui-vectors.json")!!.readBytes()) as Map<String, Any?>

    private fun d(v: Any?) = (v as JsonNumber).toDouble()
    @Suppress("UNCHECKED_CAST")
    private fun rect(v: Any?) = (v as List<Any?>).map(::d).let { Rect(it[0], it[1], it[2], it[3]) }
    @Suppress("UNCHECKED_CAST")
    private fun rects(v: Any?) = (v as List<Any?>).map(::rect)

    private fun near(a: Double, b: Double) = abs(a - b) < 1e-5
    private fun same(what: String, swift: Rect, kotlin: Rect) {
        if (!(near(swift.x, kotlin.x) && near(swift.y, kotlin.y) && near(swift.width, kotlin.width) && near(swift.height, kotlin.height)))
            fail("$what: Swift $swift, Kotlin $kotlin")
    }

    @Test fun phoneLayoutIsTheSwiftOneAtEverySize() {
        @Suppress("UNCHECKED_CAST")
        val all = vectors["phoneLayouts"] as List<Map<String, Any?>>
        assertTrue(all.size > 100)
        val videos = listOf(Size.zero, Size(1920.0, 1080.0), Size(1600.0, 1000.0), Size(1000.0, 1600.0), Size(3024.0, 1964.0))
        for (v in all) {
            val size = Size(d(v["w"]), d(v["h"]))
            val k = v["k"]?.let(::d)
            val l = PhonePortraitLayout(size, k)
            val at = "${size.width}×${size.height} k=$k"
            same("$at picture", rect(v["picture"]), l.picture)
            same("$at row1", rect(v["row1"]), l.row1)
            rects(v["buttons"]).zip(l.buttons).forEach { (s, kt) -> same("$at button", s, kt) }
            rects(v["buttonsBesideMenus"]).zip(l.buttonsBesideMenus).forEach { (s, kt) -> same("$at buttonBesideMenus", s, kt) }
            assertEquals(rects(v["buttonsBesideMenus"]).size, l.buttonsBesideMenus.size)
            same("$at strip", rect(v["strip"]), l.strip)
            same("$at menus", rect(v["menus"]), l.menus)
            same("$at stripBesideMenus", rect(v["stripBesideMenus"]), l.stripBesideMenus)
            same("$at keys", rect(v["keys"]), l.keys)
            rects(v["caps"]).zip(l.caps).forEach { (s, kt) -> same("$at cap", s, kt) }
            same("$at trackpad", rect(v["trackpad"]), l.trackpad)
            assertTrue(near(d(v["trackpadSpan"]), l.trackpadSpan), at)
            same("$at ruler", rect(v["ruler"]), l.ruler)
            assertTrue(near(d(v["rulerStep"]), l.rulerStep), at)
            same("$at rulerBesideMenus", rect(v["rulerBesideMenus"]), l.rulerBesideMenus)
            assertTrue(near(d(v["rulerStepBesideMenus"]), l.rulerStepBesideMenus), at)
            same("$at drawer", rect(v["drawer"]), l.drawer)
            same("$at settings", rect(v["settings"]), l.settings)
            @Suppress("UNCHECKED_CAST") val anchor = (v["anchor"] as List<Any?>).map(::d)
            assertTrue(near(anchor[0], l.settingsAnchorX) && near(anchor[1], l.settingsAnchorY), at)
            rects(v["dim"]).zip(l.dim).forEach { (s, kt) -> same("$at dim", s, kt) }
            rects(v["panes"]).zip(videos).forEach { (s, video) -> same("$at pane $video", s, l.pane(video)) }
            @Suppress("UNCHECKED_CAST") val spans = (v["spans"] as List<Any?>).map(::d)
            spans.zip(videos).forEach { (s, video) -> assertTrue(near(s, l.trackpadSpan(video)), "$at span $video") }
        }
    }

    @Test fun largerPictureRulesAreTheSwiftOnes() {
        @Suppress("UNCHECKED_CAST")
        val all = vectors["phoneRules"] as List<List<Any?>>
        for (r in all) {
            val s = Size(d(r[0]), d(r[1]))
            assertTrue(near(d(r[2]), PhonePortraitLayout.keyboardHeight(s)), "$s keyboard")
            assertEquals(r[3] as Boolean, PhonePortraitLayout.largerPictureGains(s, PhonePortraitLayout.keyboardHeight(s)), "$s gains")
            assertEquals(r[4] as Boolean, PhonePortraitLayout.offersLargerPicture(s), "$s offers")
        }
    }

    @Test fun ledgerReplaysTheSwiftRunStepForStep() {
        @Suppress("UNCHECKED_CAST")
        val steps = vectors["ledger"] as List<Map<String, Any?>>
        val ledger = SettingsLedger()
        fun i(v: Any?) = v?.let { (it as JsonNumber).toDouble().toInt() }
        fun b(v: Any?) = v as Boolean?
        @Suppress("UNCHECKED_CAST")
        fun change(v: Any?): HostSettingsChange? = (v as List<Any?>?)?.let {
            HostSettingsChange(i(it[0]), i(it[1]), i(it[2]), it[3]?.let(::d), b(it[4]), b(it[5]), b(it[6]))
        }
        @Suppress("UNCHECKED_CAST")
        fun settings(v: Any?): StreamSettings? = (v as List<Any?>?)?.let {
            StreamSettings(i(it[0])!!, i(it[1])!!, d(it[2]), it[3] as Boolean, it[4] as Boolean, b(it[5]))
        }
        for ((n, s) in steps.withIndex()) {
            val t = d(s["t"])
            when (s["op"]) {
                "pick" -> assertEquals(change(s["sent"]), ledger.pick(change(s["change"])!!, i(s["token"])!!, t), "step $n pick")
                "receive" -> {
                    val state = HostSettingsState(settings(s["settings"])!!, true, true, softwareEncoder = false, answering = i(s["answering"]))
                    @Suppress("UNCHECKED_CAST")
                    val refused = (s["refused"] as List<String>).toSet()
                    assertEquals(refused, ledger.receive(state).map { swiftName(it) }.toSet(), "step $n receive")
                }
                "expire" -> assertEquals(s["dropped"] as Boolean, ledger.expire(t, 4.0), "step $n expire")
                "reset" -> ledger.reset()
            }
            assertEquals(settings(s["displayed"]), ledger.displayed, "step $n displayed")
        }
    }

    private fun swiftName(f: SettingsField) = when (f) {
        SettingsField.MaxFPS -> "maxFPS"; SettingsField.Bitrate -> "bitrate"; SettingsField.CaptureScale -> "captureScale"
        SettingsField.PrioritizeSpeed -> "prioritizeSpeed"; SettingsField.VirtualDisplay -> "virtualDisplay"; SettingsField.DirectWireless -> "directWireless"
    }

    @Test fun phoneNumbersAreTheOnesTheIosDocsGive() {
        // PhonePortraitLayout.swift and CLAUDE.md: an 18 Pro Max's stream screen is 440×894 (its
        // picture 424×265, its trackpad 412×389), an 18 Pro's 402×812 (386×241, 374×331).
        val proMax = PhonePortraitLayout(Size(440.0, 894.0))
        assertEquals(Rect(8.0, 8.0, 424.0, 265.0), proMax.picture)
        assertEquals(412.0, proMax.trackpad.width); assertEquals(389.0, proMax.trackpad.height)
        val pro = PhonePortraitLayout(Size(402.0, 812.0))
        assertEquals(386.0, pro.picture.width); assertEquals(241.0, pro.picture.height)
        assertEquals(374.0, pro.trackpad.width); assertEquals(331.0, pro.trackpad.height)
        assertEquals(240.0, PhonePortraitLayout.fixedHeight)
        assertEquals(152.0, PhonePortraitLayout.largerFixedHeight)
        // Larger Picture on the Pro Max: 424×422.
        assertEquals(422.0, PhonePortraitLayout(Size(440.0, 894.0), 320.0).picture.height)
    }

    @Test fun layoutSelectionIsDuoLayouts() {
        assertEquals(ScreenLayout.InnerLandscape, ScreenLayout.of(Size(951.0, 669.0)))
        assertEquals(ScreenLayout.InnerPortrait, ScreenLayout.of(Size(669.0, 951.0)))
        assertEquals(ScreenLayout.OuterLandscape, ScreenLayout.of(Size(594.0, 466.0)))
        assertEquals(ScreenLayout.OuterPortrait, ScreenLayout.of(Size(382.0, 678.0)))
        assertEquals(ScreenLayout.OuterLandscape, ScreenLayout.of(Size(892.0, 412.0)))   // a phone on its side
        assertTrue(StreamLayout.of(Size(412.0, 892.0), phone = true) is StreamLayout.Phone)
        assertTrue(StreamLayout.of(Size(412.0, 892.0), phone = false) is StreamLayout.Halves)
        assertTrue(StreamLayout.of(Size(1280.0, 800.0), phone = false) is StreamLayout.Landscape)
    }

    @Test fun landscapeBarPlacesTheIosButtons() {
        val l = StreamLayout.of(Size(1000.0, 710.0), phone = false) as StreamLayout.Landscape
        val m = BarMetrics.regular
        assertEquals(Rect(22.0, 10.0, 66.0, 66.0), l.items[BarItem.Apps])
        assertEquals(Rect(1000 - 22 - 66.0, 10.0, 66.0, 66.0), l.items[BarItem.Settings])
        // Settings, Desktop, Keyboard, Aa from the trailing edge, 12 apart; the strip between Apps and Aa.
        assertEquals(1000 - 22 - 4 * 66 - 3 * 12.0, l.items.getValue(BarItem.TextSize).x)
        val strip = l.items.getValue(BarItem.Strip)
        assertEquals(22 + 66 + 12.0, strip.x)
        assertEquals(l.items.getValue(BarItem.TextSize).x - 12, strip.maxX)
        assertEquals(m.thumbHeight + 2 * m.thumbPad, strip.height)
        assertEquals(Rect(8.0, 86.0 + 8, 1000 - 16.0, 710 - 86 - 16.0), l.panel)
        assertEquals(Rect(22.0, 86 + 8.0, 380.0, 710 - 86 - 22.0), l.drawer)
        assertEquals(360.0, l.settings.width); assertEquals(1000 - 22.0, l.settings.maxX)
        assertNull(l.items[BarItem.Menus])
        val withMenus = StreamLayout.of(Size(1000.0, 710.0), phone = false, menus = true)
        assertTrue(withMenus.items.containsKey(BarItem.Menus))
        // Aa's ruler: 44 pt a detent in the 66 pt bar, centred on Aa.
        assertEquals(44.0 * 4 + 60, l.ruler.width); assertEquals(l.items.getValue(BarItem.TextSize).midX, l.ruler.midX)
        // A phone on its side: the compact bar, 40 pt a detent; a narrow one has no room for Menus.
        val side = StreamLayout.of(Size(844.0, 390.0), phone = true, menus = true) as StreamLayout.Landscape
        assertEquals(BarMetrics.compact, side.metrics); assertEquals(40.0, side.rulerStep)
        assertTrue(side.menusShown)
        assertFalse((StreamLayout.of(Size(560.0, 400.0), phone = true, menus = true) as StreamLayout.Landscape).menusShown)
    }

    @Test fun halvesSplitAtTheMiddle() {
        val h = StreamLayout.of(Size(710.0, 1000.0), phone = false) as StreamLayout.Halves
        assertEquals(500.0, h.half)
        assertEquals(Rect(8.0, 8.0, 694.0, 484.0), h.panel)
        assertEquals(1, h.caps.size); assertEquals(11, h.caps[0].size)       // no Spotlight off the Desktop
        val desktop = StreamLayout.of(Size(710.0, 1000.0), phone = false, spotlight = true)
        assertEquals(12, desktop.caps[0].size)
        // The compact halves fold the key row into two rows of six (and the rest).
        val compact = StreamLayout.of(Size(500.0, 710.0), phone = false, spotlight = true) as StreamLayout.Halves
        assertEquals(listOf(6, 6), compact.caps.map { it.size })
        assertTrue(compact.caps.flatten().all { it.width >= 44 && it.height >= 44 })
        assertTrue(h.trackpad.height > 200)
    }

    @Test fun textScaleIsTheAaControls() {
        assertEquals(listOf("0.5", "0.75", "1", "1.25", "1.5"), TextScale.steps.map(TextScale::label))
        assertEquals(1.25, TextScale.dragged(1.0, 44.0, 44.0))
        assertEquals(1.5, TextScale.dragged(1.0, 400.0, 44.0))
        assertEquals(0.5, TextScale.dragged(1.0, -400.0, 44.0))
        assertEquals(1.0, TextScale.dragged(1.0, 21.0, 44.0))
        assertEquals(236.0, TextScale.sliderWidth(44.0))
        assertEquals(1.25, TextScale.step(null, up = true))
        assertEquals(1.5, TextScale.step(1.5, up = true))
    }

    @Test fun curvesAreSwiftUIs() {
        val e = Curve.EaseOut(0.2)
        assertEquals(0.0, e.value(0.0)); assertEquals(1.0, e.value(0.2))
        var last = 0.0
        for (i in 1..100) { val v = e.value(0.002 * i); assertTrue(v >= last); last = v }
        // Ease-out is ahead of linear all the way: cubic-bezier(0, 0, 0.58, 1) at a half is 0.6875 by
        // the curve's own arithmetic (x(0.5) = 0.5 · 0.58 · 3/4 … solved for t).
        assertTrue(e.atFraction(0.5) > 0.6 && e.atFraction(0.5) < 0.8)
        val s = Curve.Spring(0.25, 0.2)
        assertTrue(s.value(0.25) > 0.95)                     // about there by its duration
        assertTrue((0 until 300).any { s.value(it * 0.002) > 1.0 })   // it bounces past 1
        assertTrue(abs(s.value(s.seconds) - 1) < 1e-3)
        assertTrue(s.seconds in 0.25..1.0)
        val critical = Curve.Spring(0.3, 0.0)
        assertTrue((0 until 600).none { critical.value(it * 0.002) > 1.0 + 1e-9 })
        assertEquals(0.18, Motion.drawer.seconds)
        assertEquals(Curve.Spring(0.22, 0.15), Motion.rulerOpen)
    }

    @Test fun tokensAreThePalette() {
        assertEquals(0xFF16181C.toInt(), Palette.bar.argb)
        assertEquals(0xFF9BB7FF.toInt(), Palette.accent.argb)
        assertEquals(0x94000000.toInt(), Rgba.black.opacity(Ui.dimAlpha).argb)
        assertEquals(PhonePortraitLayout.stripHeight, PortraitMetrics.phone.barHeight)
        assertEquals(6.0, PortraitMetrics.phone.thumbPad)
        assertEquals(66.0, BarMetrics.regular.buttonWidth)
    }

    @Test fun streamUiOpensAndRestoresAsTheIosScreen() {
        val effects = ArrayList<StreamUi.Effect>()
        val ui = StreamUi { _, e -> effects += e }
        ui.tapKeyboard()
        assertTrue(ui.state.keyboardShown); assertEquals(listOf<StreamUi.Effect>(StreamUi.Effect.Keyboard(true)), effects)
        effects.clear()
        ui.tapApps()
        assertTrue(ui.state.drawerOpen)
        ui.tapSettings()                                      // the panel closes the drawer and takes the keyboard down
        assertTrue(ui.state.settingsOpen); assertFalse(ui.state.drawerOpen); assertFalse(ui.state.keyboardShown)
        assertEquals(StreamUi.Effect.Keyboard(false), effects.last())
        ui.closeSettings()                                    // and puts it back
        assertTrue(ui.state.keyboardShown); assertEquals(StreamUi.Effect.Keyboard(true), effects.last())
        ui.tapSettings(); effects.clear()
        ui.tapApps()                                          // Apps over the panel: closes it, keyboard stays down
        assertFalse(ui.state.settingsOpen); assertTrue(ui.state.drawerOpen); assertFalse(ui.state.keyboardShown)
        assertTrue(effects.isEmpty())
        // The ruler: a plain tap changes nothing; a drag of one detent applies once, on release.
        ui.rulerDown(); assertTrue(ui.state.scaleOpen); ui.rulerUp()
        assertNull(ui.state.textScale)
        ui.rulerDown(); assertTrue(ui.rulerMoved(45.0, 44.0)); assertFalse(ui.rulerMoved(50.0, 44.0)); effects.clear(); ui.rulerUp()
        assertEquals(1.25, ui.state.textScale); assertEquals(listOf<StreamUi.Effect>(StreamUi.Effect.SendViewport), effects)
        // The Menus pull-down over the panel: the keyboard comes back only when it goes.
        ui.closeDrawer(); ui.tapKeyboard(); ui.tapSettings(); ui.menusOpened()
        assertFalse(ui.state.settingsOpen); assertFalse(ui.state.keyboardShown)
        ui.menusClosed(); assertTrue(ui.state.keyboardShown)
        ui.openWindowMenu(7); ui.windowsChanged(setOf(1, 2)); assertNull(ui.state.windowMenu)
    }

    @Test fun keyRowSendsAsAKeyboard() {
        val (events, latch) = KeyRow.tap(KeyRow.all[0], Modifiers.COMMAND or Modifiers.SHIFT)
        assertEquals(0L, latch)
        val keys = events.map { it as InputEvent.Key }
        // ⌃⇧⌥⌘ order down, the key, reverse order up, each carrying what is held.
        assertEquals(listOf(0xE1, 0xE3, 0x29, 0x29, 0xE3, 0xE1), keys.map { it.hidUsage })
        assertEquals(listOf(true, true, true, false, false, false), keys.map { it.down })
        assertEquals(0L, keys.last().modifiers)
        assertEquals(Modifiers.COMMAND, KeyRow.tap(KeyRow.all[4], 0).second)
        assertEquals(listOf(0xE3, 0x2C, 0x2C, 0xE3), KeyRow.spotlight.map { (it as InputEvent.Key).hidUsage })
    }

    @Test fun connectColumnIsTheIosOne() {
        assertEquals(380.0, ConnectLayout(Size(1000.0, 710.0)).columnWidth)
        assertEquals(360.0, ConnectLayout(Size(392.0, 800.0)).columnWidth)
        assertEquals(310.0, ConnectLayout(Size(1000.0, 710.0)).columnX)
    }
}
