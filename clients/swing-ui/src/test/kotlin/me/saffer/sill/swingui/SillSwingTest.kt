package me.saffer.sill.swingui

import me.saffer.sill.core.ui.Palette
import me.saffer.sill.core.ui.Symbol
import me.saffer.sill.core.ui.Type
import java.awt.image.BufferedImage
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class SillSwingTest {
    @Test fun colorsAreThePalette() {
        assertEquals(0x16181C, SillSwing.color(Palette.bar).rgb and 0xFFFFFF)
        assertEquals(255, SillSwing.color(Palette.accent).alpha)
        assertEquals(148, SillSwing.color(Palette.bar.opacity(0.58)).alpha)
    }

    @Test fun fontsFollowTheStylesSizes() {
        assertEquals(11f, SillSwing.font(Type.barLabel, 1.0).size2D)
        assertEquals(17f * (23f / 17f), SillSwing.font(Type.headline, 5.0).size2D, 0.01f)   // capped at xxLarge
    }

    @Test fun everyGlyphDrawsInItsBox() {
        for (s in Symbol.entries) {
            val img = BufferedImage(48, 48, BufferedImage.TYPE_INT_ARGB)
            val g = SillSwing.smooth(img.graphics)
            SillSwing.glyph(g, s, 0.0, 0.0, 48.0, Palette.text)
            g.dispose()
            var ink = 0
            for (y in 0 until 48) for (x in 0 until 48) if ((img.getRGB(x, y) ushr 24) > 0) ink++
            assertTrue(ink in 20..48 * 48 * 3 / 4, "$s: $ink pixels")
        }
    }

    @Test fun ellipsisCutsAsTextDoes() {
        val img = BufferedImage(1, 1, BufferedImage.TYPE_INT_ARGB)
        val g = img.createGraphics(); g.font = SillSwing.font(Type.rowTitle, 1.0)
        val fm = g.fontMetrics
        assertEquals("Short", SillSwing.fit(fm, "Short", 500.0))
        val cut = SillSwing.fit(fm, "A rather long window title that will not fit", 80.0)
        assertTrue(cut.endsWith("…") && fm.stringWidth(cut) <= 80)
        val mid = SillSwing.fit(fm, "Noah's MacBook Pro on the desk", 80.0, middle = true)
        assertTrue(mid.contains("…") && fm.stringWidth(mid) <= 80)
    }
}
