package me.saffer.sill.core.ui

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.sin

/**
 * The iOS app's SF Symbols, drawn as plain vector glyphs: SF Symbols may only be used on Apple's
 * platforms, so Android and the desktop draw these instead, the same shapes at the same sizes on
 * both. Each is a list of shapes in a 24-unit box, stroked or filled in the colour the iOS app gives
 * the symbol; `Symbol.size` scales the box to the point size the iOS app sets (`.font(.system(size:))`
 * sizes the symbol's cap height, about 0.85 of the box, which `boxFor` accounts for).
 */
enum class Symbol(val shapes: List<Glyph>) {
    /** "magnifyingglass": the Apps button, the drawer's search field. */
    Magnifier(listOf(Glyph.Circle(10.0, 10.0, 6.5, 2.0), Glyph.Line(14.9, 14.9, 20.5, 20.5, 2.6))),
    /** "keyboard": the Keyboard button and cap. */
    Keyboard(buildList {
        add(Glyph.RoundRect(2.0, 6.0, 20.0, 13.0, 2.6, 1.8))
        for (row in 0..1) for (i in 0..4) add(Glyph.RoundRect(5.0 + i * 3.0, 8.8 + row * 3.0, 1.6, 1.6, 0.4, null))
        add(Glyph.Line(7.5, 15.8, 16.5, 15.8, 1.8))
    }),
    /** "desktopcomputer": the Desktop button, a Mac's row badge. */
    Desktop(listOf(Glyph.RoundRect(2.0, 3.5, 20.0, 13.5, 2.0, 1.8), Glyph.Line(12.0, 17.0, 12.0, 20.2, 1.8), Glyph.Line(8.0, 20.5, 16.0, 20.5, 1.8))),
    /** "gearshape": the Settings button. */
    Gear(listOf(Glyph.Polygon(GlyphMath.gear(12.0, 12.0, 9.6, 7.4, 8), 1.8), Glyph.Circle(12.0, 12.0, 3.0, 1.8))),
    /** "filemenu.and.selection": the Menus button. */
    Menus(listOf(Glyph.RoundRect(3.0, 3.0, 18.0, 4.5, 1.2, 1.6), Glyph.RoundRect(5.0, 9.5, 12.0, 11.0, 2.0, 1.6),
        Glyph.Line(8.0, 13.0, 14.0, 13.0, 1.6), Glyph.Line(8.0, 16.5, 12.5, 16.5, 1.6))),
    /** "sparkle.magnifyingglass": the Spotlight cap. */
    Spotlight(listOf(Glyph.Circle(10.0, 11.0, 6.0, 2.0), Glyph.Line(14.5, 15.5, 20.0, 21.0, 2.5),
        Glyph.Polygon(GlyphMath.star(18.5, 4.5, 3.4, 1.0), null))),
    /** "chevron.left" … "chevron.right": the key row's arrows. */
    ChevronLeft(listOf(Glyph.Polyline(listOf(15.0 to 5.0, 8.0 to 12.0, 15.0 to 19.0), 2.6))),
    ChevronRight(listOf(Glyph.Polyline(listOf(9.0 to 5.0, 16.0 to 12.0, 9.0 to 19.0), 2.6))),
    ChevronUp(listOf(Glyph.Polyline(listOf(5.0 to 15.0, 12.0 to 8.0, 19.0 to 15.0), 2.6))),
    ChevronDown(listOf(Glyph.Polyline(listOf(5.0 to 9.0, 12.0 to 16.0, 19.0 to 9.0), 2.6))),
    /** "xmark.circle": Disconnect. */
    XmarkCircle(listOf(Glyph.Circle(12.0, 12.0, 9.5, 1.8), Glyph.Line(8.5, 8.5, 15.5, 15.5, 1.8), Glyph.Line(15.5, 8.5, 8.5, 15.5, 1.8))),
    /** "xmark", "minus", "arrow.up.left.and.arrow.down.right": the window lights' glyphs. */
    Xmark(listOf(Glyph.Line(6.0, 6.0, 18.0, 18.0, 3.2), Glyph.Line(18.0, 6.0, 6.0, 18.0, 3.2))),
    Minus(listOf(Glyph.Line(5.0, 12.0, 19.0, 12.0, 3.2))),
    FullScreen(listOf(Glyph.Polygon(listOf(4.0 to 4.0, 13.0 to 4.0, 4.0 to 13.0), null), Glyph.Polygon(listOf(20.0 to 20.0, 11.0 to 20.0, 20.0 to 11.0), null))),
    /** "exclamationmark.triangle.fill": a warning's footnote, a callout. */
    Warning(listOf(Glyph.Polygon(listOf(12.0 to 2.5, 22.5 to 21.0, 1.5 to 21.0), null),
        Glyph.Line(12.0, 9.0, 12.0, 14.5, 2.2, cutout = true), Glyph.Circle(12.0, 17.8, 1.3, null, cutout = true))),
    /** "checkmark.circle.fill": Paired. */
    CheckCircle(listOf(Glyph.Circle(12.0, 12.0, 10.0, null), Glyph.Polyline(listOf(7.5 to 12.5, 10.8 to 15.6, 16.8 to 8.6), 2.2, cutout = true))),
    /** "doc.on.clipboard": the clipboard chip. */
    Clipboard(listOf(Glyph.RoundRect(5.0, 4.0, 14.0, 17.5, 2.2, 1.8), Glyph.RoundRect(8.5, 2.5, 7.0, 3.5, 1.0, null))),
    /** "arrow.down.circle": an older Mac's update line. */
    UpdateCircle(listOf(Glyph.Circle(12.0, 12.0, 9.5, 1.8), Glyph.Line(12.0, 7.0, 12.0, 16.5, 1.8), Glyph.Polyline(listOf(8.0 to 13.0, 12.0 to 17.0, 16.0 to 13.0), 1.8)));

    companion object {
        /** The square a symbol set at `pointSize` (the iOS font size) is drawn in: an SF Symbol at
         *  that size is about 1.15 times as wide and tall as the size for these shapes. */
        fun boxFor(pointSize: Double) = pointSize * 1.15

    }
}

private object GlyphMath {
    fun gear(cx: Double, cy: Double, outer: Double, inner: Double, teeth: Int): List<Pair<Double, Double>> {
        val pts = ArrayList<Pair<Double, Double>>()
        val n = teeth * 4
        for (i in 0 until n) {
            val a = 2 * PI * i / n - PI / 2
            val r = if ((i / 2) % 2 == 0) outer else inner
            val off = (if (i % 2 == 0) -1 else 1) * PI / n * 0.35
            pts += (cx + r * cos(a + off)) to (cy + r * sin(a + off))
        }
        return pts
    }

    fun star(cx: Double, cy: Double, r: Double, inner: Double) = (0 until 8).map { i ->
        val a = PI / 4 * i - PI / 2
        val rr = if (i % 2 == 0) r else inner
        (cx + rr * cos(a)) to (cy + rr * sin(a))
    }
}

/**
 * One shape of a glyph, in a 24-unit box. `stroke`: the line's width (round caps and joins), or
 * null to fill. `cutout`: drawn in the background's colour over what came before (the mark inside a
 * filled triangle or circle).
 */
sealed class Glyph {
    abstract val stroke: Double?
    abstract val cutout: Boolean
    data class Circle(val cx: Double, val cy: Double, val r: Double, override val stroke: Double?, override val cutout: Boolean = false) : Glyph()
    data class Line(val x1: Double, val y1: Double, val x2: Double, val y2: Double, override val stroke: Double, override val cutout: Boolean = false) : Glyph()
    data class RoundRect(val x: Double, val y: Double, val w: Double, val h: Double, val r: Double, override val stroke: Double?, override val cutout: Boolean = false) : Glyph()
    data class Polygon(val points: List<Pair<Double, Double>>, override val stroke: Double?, override val cutout: Boolean = false) : Glyph()
    data class Polyline(val points: List<Pair<Double, Double>>, override val stroke: Double, override val cutout: Boolean = false) : Glyph()
}
