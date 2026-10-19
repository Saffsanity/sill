package me.saffer.sill.swingui

import me.saffer.sill.core.ui.PadTracker
import me.saffer.sill.core.ui.Palette
import me.saffer.sill.core.ui.Symbol
import me.saffer.sill.core.ui.Type
import me.saffer.sill.core.ui.Ui
import java.awt.image.BufferedImage
import javax.swing.JPanel
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/** The Swing primitives' geometry and colours, headless (no display: drawn into images). */
class ComponentsTest {
    private fun paint(c: javax.swing.JComponent): BufferedImage {
        val img = BufferedImage(c.width, c.height, BufferedImage.TYPE_INT_ARGB)
        val g = img.createGraphics(); c.paint(g); g.dispose()
        return img
    }
    private fun rgb(img: BufferedImage, x: Int, y: Int) = img.getRGB(x, y) and 0xFFFFFF

    @Test fun barButtonDrawsTheControlColourAndOpenTheOpenOne() {
        val b = BarButton(Symbol.Keyboard, "Keyboard").apply { setSize(66, 66) }
        assertEquals(Palette.control.rgb, rgb(paint(b), 33, 3))
        b.open = true
        assertEquals(Palette.controlOpen.rgb, rgb(paint(b), 33, 3))
    }

    @Test fun aFadedControlTakesNoClickAndNoFocus() {
        val b = BarButton(Symbol.Gear, "Settings").apply { setSize(66, 66) }
        assertTrue(b.contains(10, 10))
        b.fade.snap(0.0); b.fadeTo(0.0)
        assertFalse(b.contains(10, 10)); assertFalse(b.isFocusable)
    }

    @Test fun stackPlacesEachChildAtItsHeightForTheWidth() {
        val p = JPanel(VStack(spacing = 6)).apply { setSize(300, 1000) }
        val a = WrapLabel("A line of words long enough to wrap onto more than one line at this width, surely.", Type.footnote)
        val b = WrapLabel("Short", Type.footnote)
        p.add(a); p.add(b)
        p.doLayout()
        assertEquals(0, a.y); assertEquals(a.height + 6, b.y)
        assertTrue(a.height > b.height, "the long words wrap: ${a.height} against ${b.height}")
        assertEquals(a.height + 6 + b.height, (p.layout as VStack).heightFor(p, 300))
    }

    @Test fun wrappedLinesKeepToTheWidth() {
        val img = BufferedImage(1, 1, BufferedImage.TYPE_INT_ARGB)
        val fm = img.createGraphics().getFontMetrics(SillSwing.font(Type.footnote))
        val lines = Wrap.lines(fm, "Lets devices reach the host without a shared Wi‑Fi network, the way AirDrop does.", 150.0)
        assertTrue(lines.size > 1 && lines.all { fm.stringWidth(it) <= 150 }, "$lines")
        assertEquals("Lets devices reach the host without a shared Wi‑Fi network, the way AirDrop does.", lines.joinToString(" "))
    }

    @Test fun rowsAreTheirHeightsSixApart() {
        val list = RowList().apply { setSize(352, 400) }
        list.items = listOf(ListItem.Header("Open now"), ListItem.Row("a", "Notes", "1 window", Ui.openRowHeight, true),
            ListItem.Row("b", "Terminal", null, Ui.closedRowHeight, false))
        val a = assertNotNull(list.rowBounds("a")); val b = assertNotNull(list.rowBounds("b"))
        assertEquals(Ui.openRowHeight, a.height); assertEquals(a.maxY + 6, b.y)
        assertEquals(Math.ceil(b.maxY).toInt(), list.heightFor(352))
        // The highlighted row on the control colour, corners 10.
        assertEquals(Palette.control.rgb, rgb(paint(list), 347, a.midY.toInt()))
    }

    @Test fun theSettingsSheetIsAsTallAsItsContentAtMostItsRoom() {
        val sheet = SettingsSheet().apply { title = "Studio"; lines = listOf("Not streaming") }
        sheet.body.add(RowGroup(listOf(SwitchRow("Virtual Display", false) {})))
        val short = sheet.heightAt(360)
        assertTrue(short in 150..260, "one row: $short")
        repeat(20) { sheet.body.add(WrapLabel("Footnote $it", Type.footnote, Palette.muted, java.awt.Insets(6, 14, 12, 14))) }
        sheet.maxHeight = 500
        assertEquals(500, sheet.heightAt(360))
    }

    @Test fun thumbnailsSitInTheirSlotsAndAFadedStripTakesNoClick() {
        val strip = WindowStrip().apply { setSize(566, 86) }
        strip.metrics = StripMetrics(104.0, 66.0, 10.0, 16.0, 10.0, 0.86, 24.0)
        strip.setItems(listOf(StripItem(1, "Notes", "Notes", null, null, true), StripItem(2, "zsh", "Terminal", null, null, false)))
        Thread.sleep(500)     // the slots' spring
        val b = assertNotNull(strip.thumbBounds(2))
        assertEquals(8.0 + 104 + 16, b.x, 0.5); assertEquals(10.0, b.y)
        assertEquals(2L, strip.itemAt(b.midX, b.midY))
        assertTrue(strip.contains(10, 40))
        strip.fade.snap(0.2); strip.fade.animate(0.2, me.saffer.sill.core.ui.Motion.scaleFade)
        assertFalse(strip.contains(10, 40))
    }

    @Test fun theTrackpadKnowsItsSizeAndMovesTheCursorRelative() {
        val sent = ArrayList<me.saffer.sill.core.InputEvent>()
        val t = PadTracker { sent.add(it) }
        val well = TrackpadWell(t)
        well.setBounds(0, 0, 400, 300)
        assertEquals(400.0, t.width); assertEquals(300.0, t.height)
        t.down(0, 100.0, 100.0, 0.0); t.move(0, 140.0, 100.0, 0.05); t.up(0, 140.0, 100.0, 0.1)
        val last = sent.filterIsInstance<me.saffer.sill.core.InputEvent.Pointer>().last()
        assertEquals(0.5 + 40.0 / 400 * PadTracker.TRAVEL, last.x, 1e-9)
        // The well: Palette.trackpad between its dots.
        assertEquals(Palette.trackpad.rgb, rgb(paint(well), 13, 13))
    }
}
