package me.saffer.sill.host

import me.saffer.sill.core.QualityPreset
import me.saffer.sill.core.ui.PanelCopy
import me.saffer.sill.host.ui.ButtonsRow
import me.saffer.sill.host.ui.FormPage
import me.saffer.sill.host.ui.FormSection
import me.saffer.sill.host.ui.HostModel
import me.saffer.sill.host.ui.HostTheme
import me.saffer.sill.host.ui.HostUi
import me.saffer.sill.host.ui.LabeledRow
import me.saffer.sill.host.ui.MacSwitch
import me.saffer.sill.host.ui.MenuView
import me.saffer.sill.host.ui.PairView
import me.saffer.sill.host.ui.PairingView
import me.saffer.sill.host.ui.PushButton
import me.saffer.sill.host.ui.Segmented
import me.saffer.sill.host.ui.SettingsTab
import me.saffer.sill.host.ui.SettingsWindow
import me.saffer.sill.host.ui.StatusCardLayout
import me.saffer.sill.host.ui.TextRow
import me.saffer.sill.host.ui.ValueText
import me.saffer.sill.host.ui.WrapText
import me.saffer.sill.swingui.SillSwing
import org.junit.jupiter.api.Assumptions.assumeTrue
import org.junit.jupiter.api.BeforeEach
import java.awt.Component
import java.awt.Container
import java.awt.GraphicsEnvironment
import java.awt.image.BufferedImage
import java.io.File
import javax.imageio.ImageIO
import javax.swing.JComponent
import javax.swing.SwingUtilities
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotEquals
import kotlin.test.assertTrue

/**
 * The host's UI against Sill.app's (StatusCard, MenuBuilder's menu, Settings' panes, the pairing
 * window): sizes, words and behaviour, drawn off screen at 1x and 2x in both appearances, with
 * screenshots in build/ui-shots/. Needs a display (xvfb-run, as CI runs it); skipped without one.
 */
class HostUiTest {
    private val shots = File("build/ui-shots").apply { mkdirs() }

    class FakeModel : HostModel {
        override val version = "0.6.0"
        override val runningFrom = "/opt/sillhost/lib/app"
        var snapshot = HostStatusSnapshot(HostStatusSnapshot.Network.Advertising("DESKTOP-4K2Q"))
        override fun status() = snapshot
        private var cfg = HostConfig()
        override val config get() = cfg
        override fun setConfig(c: HostConfig) { cfg = c }
        var devices = listOf(
            PairedDevice("fp1", "iPad (iPad14,1)", "iPad14,1", "code", 1_791_000_000.0, System.currentTimeMillis() / 1e3 - 120),
            PairedDevice("fp2", "Pixel 9 Pro", null, "qr", 1_791_100_000.0, null))
        override fun paired() = devices
        private var require = true
        override val requirePairing get() = require
        override fun setRequirePairing(on: Boolean) { require = on }
        private var clip = true
        override val shareClipboard get() = clip
        override fun setShareClipboard(on: Boolean) { clip = on }
        override fun removeDevice(fingerprint: String) { devices = devices.filter { it.fingerprint != fingerprint } }
        var pairingView: PairingView? = null
        var opened = 0; var cancelled = 0; var quits = 0
        override fun openPairing() { opened++; pairingView = PairingView("123456789012", "sill://pair?v=1&m=ABCDEFGHIJ&k=" + "k".repeat(43) + "&s=" + "s".repeat(22) + "&n=DESKTOP-4K2Q&p=7455&a=192.168.1.20",
            298.0, PairingCopy.Phase.Waiting(5, null), null, PairingCopy.Address("192.168.1.20", null)) }
        override fun cancelPairing() { cancelled++; pairingView = pairingView?.copy(phase = PairingCopy.Phase.Closed) }
        override fun pairing() = pairingView
        var loginOn = false
        override fun login() = LoginState(true, loginOn)
        override fun setLogin(on: Boolean) { loginOn = on }
        override val logFile: File? = null
        override fun recentLog() = listOf("12:00:00 Sill host 0.6.0 on Linux", "12:00:01 [1s] enc.out 60 clients 1")
        override fun showLog() {}
        override fun revealLog() {}
        override fun quit() { quits++ }
    }

    private val streaming = HostStatusSnapshot(HostStatusSnapshot.Network.Advertising("DESKTOP-4K2Q"),
        listOf(HostStatusSnapshot.Device("a", "iPad (iPad14,1)", "192.168.1.30", 58, 9, 7), HostStatusSnapshot.Device("b", "Pixel 9 Pro", "192.168.1.31", 60, 14, 11)),
        HostStatusSnapshot.Stream(HostStatusSnapshot.Stream.Kind.WINDOW, "Notepad — notes.txt", 2560, 1440, 60, 15), encodedFps = 58)

    @BeforeEach fun display() { assumeTrue(!GraphicsEnvironment.isHeadless(), "no display: run under xvfb-run"); System.setProperty("sill.textScale", "1") }

    private fun onEdt(f: () -> Unit) { var err: Throwable? = null; SwingUtilities.invokeAndWait { try { f() } catch (t: Throwable) { err = t } }; err?.let { throw it } }

    private fun layoutAll(c: Component) { if (c is Container) { c.doLayout(); c.components.forEach(::layoutAll) } }

    /** `c` drawn at `scale` (2: a 200 % display), saved as build/ui-shots/`name`.png. */
    private fun shot(c: JComponent, name: String, scale: Int): BufferedImage {
        if (c.width == 0) c.size = c.preferredSize
        layoutAll(c)
        val img = BufferedImage(c.width * scale, c.height * scale, BufferedImage.TYPE_INT_ARGB)
        val g = img.createGraphics()
        g.scale(scale.toDouble(), scale.toDouble())
        c.printAll(g)
        g.dispose()
        ImageIO.write(img, "png", File(shots, "$name@${scale}x.png"))
        return img
    }

    private fun texts(c: Component): List<String> = buildList {
        when (c) {
            is FormSection -> c.header?.let(::add)
            is LabeledRow -> { add(c.label); c.detail?.let(::add) }
            is WrapText -> add(c.text)
            is PushButton -> add(c.title)
            is ValueText -> add(c.text)
        }
        if (c is Container) c.components.forEach { addAll(texts(it)) }
    }

    private fun <T> find(c: Component, type: Class<T>): List<T> = buildList {
        if (type.isInstance(c)) add(type.cast(c))
        if (c is Container) c.components.forEach { addAll(find(it, type)) }
    }

    @Test fun statusMenuIsSillAppsMenu() = onEdt {
        for (dark in listOf(true, false)) {
            HostTheme.override = if (dark) HostTheme.darkColors else HostTheme.lightColors
            val p = HostStatusText.present(streaming)
            val view = MenuView(HostMenu.entries(p, HostConfig(), LoginState(true, false)), p) {}.apply { material = true }
            // The card: 300 pt wide, header, the window's row, both devices' rows.
            val card = StatusCardLayout(p)
            assertEquals(300.0, StatusCardLayout.WIDTH)
            assertEquals(3, card.rows.size)
            assertTrue(view.preferredSize.width >= 300)
            val cardRect = view.rowRect(0)
            assertEquals(card.height.toInt(), cardRect.height, "the card's height")
            // Rows: 22 pt, 36 with a subtitle, 11 pt separators; the order is MenuBuilder's.
            assertEquals(MenuView.ROW.toInt(), view.rowRect(view.indexOfTitle("Frame Rate")).height)
            assertEquals(MenuView.ROW_SUBTITLED.toInt(), view.rowRect(view.indexOfTitle("Quality")).height)
            assertEquals(MenuView.SEPARATOR.toInt(), view.rowRect(1).height)
            assertEquals(listOf("Frame Rate", "Quality", "Resolution", "Launch at Login", "Pair a Device…", "Show Log…", "Settings…", "Quit Sill Host"),
                view.entries.filter { it.kind == MenuEntry.Kind.ITEM }.map { it.title })
            val name = if (dark) "menu-dark" else "menu-light"
            val plain = shot(view, name, 1)
            // The hovered row in the accent colour.
            val q = view.indexOfTitle("Settings…")
            view.hover(q, fromMouse = false)
            val lit = shot(view, "$name-hover", 2)
            val r = view.rowRect(q)
            val px = lit.getRGB((MenuView.INSET.toInt() + 3) * 2, (r.y + r.height / 2) * 2)
            assertEquals(SillSwing.color(HostTheme.c.accent).rgb and 0xFFFFFF, px and 0xFFFFFF, "the accent under the hovered row")
            assertNotEquals(plain.getRGB(MenuView.INSET.toInt() + 3, r.y + r.height / 2), lit.getRGB((MenuView.INSET.toInt() + 3) * 2, (r.y + r.height / 2) * 2))
            shot(view, name, 2)
        }
        HostTheme.override = null
    }

    @Test fun settingsPanesAreSillApps() = onEdt {
        val model = FakeModel()
        model.snapshot = streaming
        for (dark in listOf(true, false)) {
            HostTheme.override = if (dark) HostTheme.darkColors else HostTheme.lightColors
            val s = SettingsWindow(model)
            for (t in SettingsTab.entries) {
                s.select(t)
                assertEquals(t.title, s.frame.title)
                val page = (s.frame.contentPane.getComponent(1) as javax.swing.JScrollPane).viewport.view as FormPage
                assertEquals(520, page.preferredSize.width, "Settings' panes are 520 pt wide")
                page.size = page.preferredSize
                val words = texts(page)
                when (t) {
                    SettingsTab.GENERAL -> assertTrue(words.containsAll(listOf("Launch at login", "Running from", "Visible on your network as", "“DESKTOP-4K2Q”",
                        SettingsCopy.NAME_FOOTER, "Show Log…", "Reveal Log File", "Quit Sill Host", "Sill Host 0.6.0. Free and open source.")), "$words")
                    SettingsTab.DEVICES -> assertTrue(words.containsAll(listOf("Require pairing", SettingsCopy.REQUIRE_ON, "Paired Devices", "iPad (iPad14,1)", "Pixel 9 Pro",
                        "Remove", "Pair a Device…", SettingsCopy.PAIRED_FOOTER)), "$words")
                    SettingsTab.STREAMING -> assertTrue(words.containsAll(listOf("Frame rate limit", "Quality", "Resolution", "Prioritize encoding speed",
                        SettingsCopy.streamingFooter(PanelCopy.fastLinkNote), SettingsCopy.SPEED_FOOTER)), "$words")
                }
                val name = "settings-${t.name.lowercase()}-${if (dark) "dark" else "light"}"
                shot(page, name, 1); shot(page, name, 2)
                shot(SettingsWindow.Toolbar {}.apply { selected = t; setSize(520, SettingsWindow.Toolbar.HEIGHT) }, "toolbar-${t.name.lowercase()}-${if (dark) "dark" else "light"}", 2)
            }
        }
        HostTheme.override = null
    }

    @Test fun settingsControlsSetTheHost() = onEdt {
        val model = FakeModel()
        val s = SettingsWindow(model)
        // Devices: Require pairing off swaps the footnote for the orange warning; Remove says what it did.
        s.select(SettingsTab.DEVICES)
        var page = (s.frame.contentPane.getComponent(1) as javax.swing.JScrollPane).viewport.view as FormPage
        find(page, MacSwitch::class.java).single().press(null)
        assertEquals(false, model.requirePairing)
        s.refresh()
        assertTrue(SettingsCopy.REQUIRE_OFF in texts(page))
        find(page, LabeledRow::class.java).first { it.label == "Pixel 9 Pro" }.trailing.let { (it as PushButton).press(null) }
        s.refresh()
        assertTrue(SettingsCopy.removed("Pixel 9 Pro") in texts(page))
        assertEquals(listOf("fp1"), model.devices.map { it.fingerprint })
        // Streaming: 120 fps from the segmented control, Prioritize encoding speed from its switch.
        s.select(SettingsTab.STREAMING)
        page = (s.frame.contentPane.getComponent(1) as javax.swing.JScrollPane).viewport.view as FormPage
        find(page, Segmented::class.java).single().press(java.awt.Point(100, 10))
        assertEquals(120, model.config.maxFPS)
        find(page, MacSwitch::class.java).single().press(null)
        assertTrue(model.config.prioritizeSpeed)
        // A bitrate set by hand shows as Sill.app's Custom choice.
        model.setConfig(model.config.copy(bitrate = 12_000_000))
        s.refresh()
        // General: Launch at login.
        s.select(SettingsTab.GENERAL)
        page = (s.frame.contentPane.getComponent(1) as javax.swing.JScrollPane).viewport.view as FormPage
        val switches = find(page, MacSwitch::class.java)
        assertEquals(2, switches.size, "Launch at login and Share clipboard with devices")
        switches[0].press(null)
        assertTrue(model.loginOn)
        // Share clipboard with devices: on by default, as Sill.app's.
        assertTrue(model.shareClipboard)
        switches[1].press(null)
        assertTrue(!model.shareClipboard)
        // Never taller than the screen.
        val screen = GraphicsEnvironment.getLocalGraphicsEnvironment().defaultScreenDevice.defaultConfiguration.bounds
        assertTrue(s.frame.height <= screen.height)
    }

    @Test fun pairingWindowIsSillApps() = onEdt {
        val link = "sill://pair?v=1&m=ABCDEFGHIJ&k=" + "k".repeat(43) + "&s=" + "s".repeat(22) + "&n=DESKTOP-4K2Q&p=7455&a=192.168.1.20"
        val actions = object : PairView.Actions { var cancels = 0; var codes = 0; var dones = 0
            override fun cancel() { cancels++ }; override fun newCode() { codes++ }; override fun done() { dones++ } }
        val cases = listOf(
            "pair-menu" to PairingView("123456789012", link, 298.0, PairingCopy.Phase.Waiting(5, null), null, PairingCopy.Address("100.101.102.103", "192.168.1.20")),
            "pair-asked" to PairingView("123456789012", link, 271.4, PairingCopy.Phase.Waiting(3, "192.168.1.30"), "iPad (iPad14,1)", null),
            "pair-expired" to PairingView("123456789012", link, 0.0, PairingCopy.Phase.Expired, null, null),
            "pair-paired" to PairingView("123456789012", link, 0.0, PairingCopy.Phase.Paired("iPad"), null, null),
        )
        for (dark in listOf(true, false)) {
            HostTheme.override = if (dark) HostTheme.darkColors else HostTheme.lightColors
            for ((name, v) in cases) {
                val view = PairView(actions)
                view.view = v
                assertEquals(PairView.WIDTH, view.preferredSize.width, "the pairing window is 440 pt wide")
                view.size = view.preferredSize
                val buttons = find(view, PushButton::class.java).map { it.title }
                assertEquals(PairingCopy.buttons(v.phase), buttons)
                val img1 = shot(view, "$name-${if (dark) "dark" else "light"}", 1)
                val img2 = shot(view, "$name-${if (dark) "dark" else "light"}", 2)
                if (v.phase is PairingCopy.Phase.Waiting) {
                    // The QR code: whole device pixels per module, the matrix as QrCode made it, at 1x and 2x.
                    val qr = QrCode.encode(v.link)
                    for ((img, scale) in listOf(img1 to 1, img2 to 2)) {
                        val q = view.qr
                        val per = maxOf(1, (220.0 * scale / qr.size).toInt())
                        val side = q.side(scale.toDouble())
                        val x0 = (q.x + (q.width - side) / 2) * scale
                        val y0 = q.y * scale
                        for (r in 0 until qr.size) for (c in 0 until qr.size) {
                            val px = img.getRGB(x0 + (c + 4) * per + per / 2, y0 + (r + 4) * per + per / 2) and 0xFFFFFF
                            assertEquals(if (qr.modules[r][c]) 0x000000 else 0xFFFFFF, px, "module $r,$c at ${scale}x")
                        }
                        assertTrue(per * qr.size in (180 * scale)..(220 * scale), "about 220 pt for the symbol")
                    }
                }
            }
        }
        HostTheme.override = null
    }

    @Test fun trayAndFallbackWindow() {
        val images = HostGlyph.entries.map { g -> HostUi.trayImage(g, 32).let { img -> (0 until 32 * 32).map { img.getRGB(it % 32, it / 32) } } }
        assertEquals(4, images.toSet().size, "each state its own glyph")
        val model = FakeModel()
        lateinit var ui: HostUi
        onEdt { ui = HostUi(model); ui.start() }
        onEdt {
            // Under Xvfb there is no tray: the menu lives in the "Sill Host" window.
            if (!java.awt.SystemTray.isSupported()) {
                val f = java.awt.Frame.getFrames().first { it.title == "Sill Host" && it.isVisible }
                assertTrue(find(f, MenuView::class.java).isNotEmpty())
                shot((f as javax.swing.JFrame).contentPane as JComponent, "fallback-window", 1)
            }
            ui.act(MenuAction.SetMaxFPS(120)); assertEquals(120, model.config.maxFPS)
            ui.act(MenuAction.SetBitrate(QualityPreset.PRO.bitrate)); assertEquals(QualityPreset.PRO.bitrate, model.config.bitrate)
            ui.act(MenuAction.SetCaptureScale(1.0)); assertEquals(1.0, model.config.captureScale)
            ui.act(MenuAction.ToggleLaunchAtLogin); assertTrue(model.loginOn)
            ui.act(MenuAction.ShowSettings); assertTrue(ui.settings.frame.isVisible)
            ui.act(MenuAction.ShowPairing); assertEquals(1, model.opened); assertTrue(ui.pair.isShowing)
            // Esc in the pairing window is Cancel: the host's window closes.
            ui.pair.cancel(); assertEquals(1, model.cancelled); assertTrue(!ui.pair.isShowing)
            ui.act(MenuAction.ShowLog); assertTrue(ui.log.frame.isVisible)
            ui.act(MenuAction.Quit); assertEquals(1, model.quits)
            for (f in java.awt.Window.getWindows()) f.dispose()
        }
    }

    @Test fun aDevicesAskBringsTheCodeForward() {
        val model = FakeModel()
        lateinit var ui: HostUi
        onEdt { ui = HostUi(model) }
        onEdt {
            assertTrue(!ui.pair.isShowing)
            model.openPairing(); model.pairingView = model.pairingView!!.copy(askedBy = "iPad (iPad14,1)")
            model.snapshot = model.snapshot.copy(pairingRequest = HostStatusSnapshot.PairingRequest("iPad (iPad14,1)"))
            ui.refresh()
            assertTrue(ui.pair.isShowing, "a device's ask shows the code")
            assertEquals("iPad Wants to Pair", ui.entries()[1].title)
            for (f in java.awt.Window.getWindows()) f.dispose()
        }
    }
}
