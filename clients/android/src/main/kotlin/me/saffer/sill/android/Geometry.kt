package me.saffer.sill.android

import me.saffer.sill.core.ui.DuoPosture
import me.saffer.sill.core.ui.FoldInfo
import me.saffer.sill.core.ui.Rect
import me.saffer.sill.core.ui.Size
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/*
 * The Android app's own arithmetic around core's layouts, kept free of android.* so the JVM tests
 * (src/test) hold it: dp to pixels, the safe area a layout is computed in, the touch target a small
 * control is given, what Back closes first, the thumbnails' reordering, the code field's grouping.
 */

/** A rectangle in whole pixels. */
data class PxBox(val left: Int, val top: Int, val right: Int, val bottom: Int) {
    val width get() = right - left
    val height get() = bottom - top
}

/** dp ↔ px for one density. Edges round on their own, so rectangles that touch in dp touch in px. */
class Px(val density: Double) {
    fun of(v: Double) = (v * density).roundToInt()
    fun box(r: Rect, dx: Double = 0.0, dy: Double = 0.0) =
        PxBox(of(r.x + dx), of(r.y + dy), of(r.maxX + dx), of(r.maxY + dy))
    fun dp(px: Int) = px / density
    fun dp(px: Float) = px / density
}

/** The system's insets in dp, for the safe area the layouts are computed in. */
data class Insets(val left: Double, val top: Double, val right: Double, val bottom: Double) {
    /**
     * The room the layout gets inside a window of `window` dp: every edge's bars and cutout taken
     * off (the iOS app's safe area), the keyboard never (nothing moves when it comes up).
     */
    fun safe(window: Size) = Size(max(0.0, window.width - left - right), max(0.0, window.height - top - bottom))

    companion object { val zero = Insets(0.0, 0.0, 0.0, 0.0) }
}

object Targets {
    /** Android's least touch target (Material, and the accessibility scanner): 48 dp. */
    const val MIN = 48.0

    /**
     * A control drawn at `r` given a touch area of at least [MIN] each way, centred on it, and no
     * more than `room` each side, so two neighbours' areas never overlap (a cap's 44 dp grows by 2
     * above and below into the 8 dp between rows).
     */
    fun expand(r: Rect, room: Double = Double.MAX_VALUE): Rect {
        val dx = min(room, max(0.0, (MIN - r.width) / 2))
        val dy = min(room, max(0.0, (MIN - r.height) / 2))
        return Rect(r.x - dx, r.y - dy, r.width + 2 * dx, r.height + 2 * dy)
    }
}

/** What Back (and Esc on a hardware keyboard) closes, one thing per press, before it leaves the stream. */
object BackPlan {
    enum class Step { Ruler, Lights, Drawer, Settings, Leave }

    fun next(rulerOpen: Boolean, lightsOpen: Boolean, drawerOpen: Boolean, settingsOpen: Boolean) = when {
        rulerOpen -> Step.Ruler
        lightsOpen -> Step.Lights
        drawerOpen -> Step.Drawer
        settingsOpen -> Step.Settings
        else -> Step.Leave
    }
}

/** The thumbnails' order and a drag through it (WindowStrip: the Home Screen's reordering). */
object Reorder {
    /** This device's arrangement: the saved order for the windows still listed, then the rest in the host's. */
    fun arrange(host: List<Long>, saved: List<Long>): List<Long> {
        val listed = host.toSet()
        val kept = saved.filter { it in listed }.distinct()
        return kept + host.filter { it !in kept }
    }

    /** The slot a thumbnail lifted from `from` lands in after a drag of `dx`, slots `slot` apart. */
    fun target(from: Int, dx: Double, slot: Double, count: Int): Int {
        if (count <= 0 || slot <= 0) return from
        return (from + (dx / slot).roundToInt()).coerceIn(0, count - 1)
    }

    /** `ids` with the one at `from` moved to `to`. */
    fun moved(ids: List<Long>, from: Int, to: Int): List<Long> {
        if (from !in ids.indices || to !in ids.indices || from == to) return ids
        val m = ids.toMutableList()
        val id = m.removeAt(from)
        m.add(to, id)
        return m
    }

    /** How far, in slots, the thumbnail at `index` stands aside while the one at `from` hovers over `to`. */
    fun shift(index: Int, from: Int, to: Int) = when {
        index == from -> 0
        from < to && index in (from + 1)..to -> -1
        to < from && index in to until from -> 1
        else -> 0
    }
}

/** The pairing code as the iOS field shows it, "0000 0000 0000" (PairingField.grouped). */
object CodeText {
    fun grouped(text: String): String = text.filter { it in '0'..'9' }.take(12).chunked(4).joinToString(" ")
}

/** Where the connect screen's column goes (ContentView's ColumnOverFooter): centred on the screen,
 *  rising only to keep [gap] above the footer, never above `top`; past that it scrolls. */
object ColumnPlace {
    data class Place(val y: Double, val height: Double, val scrolls: Boolean)

    fun of(screen: Double, column: Double, footer: Double, gap: Double, top: Double = 16.0): Place {
        val room = max(0.0, screen - footer - gap)
        val centred = (screen - column) / 2
        if (centred + column <= room) return Place(max(top, centred), column, false)
        val y = max(top, room - column)
        return if (y + column <= room) Place(y, column, false) else Place(top, max(0.0, room - top), true)
    }
}

/**
 * A fold as the platform reports it, mapped into a view's dp (the pure half of FoldReader, tested
 * on the JVM): the folding feature's bounds in window pixels and its state, or the hinge angle.
 */
object FoldMapping {
    /** One folding feature: its bounds in window pixels, half-opened or flat, and whether it
     *  separates the display (a hinge with a gap, as Jetpack's `isSeparating`). */
    data class Feature(val bounds: PxBox, val halfOpened: Boolean, val separating: Boolean)

    /** What the device has told: a folding feature (null: none folded across this window) from
     *  the window extensions, a hinge angle (degrees) from the sensor, or nothing at all. */
    sealed class Reading {
        data class Extensions(val feature: Feature?) : Reading()
        data class HingeAngle(val degrees: Float) : Reading()
        data object Nothing : Reading()
    }

    /** The least band a fold is given (the Duo's 40 points): Samsung's report a fold of no thickness. */
    const val minBand = DuoPosture.standInThickness

    /** Half-open counts between these angles (the window extensions' own HALF_OPENED range). */
    const val halfOpenFrom = 30f
    const val halfOpenTo = 150f

    /**
     * The FoldInfo a view sees: `viewLeft`/`viewTop` its origin in window pixels, `view` its size in
     * dp. A band only while the fold is half-open or separating, as iOS reports the Duo's only half-
     * folded; at least [minBand] thick, centred on the crease; clipped to the view. A foldable that
     * says it is open flat is `none`, as the Duo open flat is on iOS (the picture takes its own shape).
     * A device with no fold to report (an ordinary phone or tablet, a Fold on its cover screen, a
     * closed hinge) is `Inferred`, exactly what iOS gives every iPhone and iPad: the iPad's halves
     * split at the middle, as on main.
     */
    fun info(reading: Reading, viewLeft: Int, viewTop: Int, density: Double, view: Size): FoldInfo {
        return when (reading) {
            Reading.Nothing -> FoldInfo.Inferred
            is Reading.HingeAngle -> when {
                reading.degrees in halfOpenFrom..halfOpenTo -> FoldInfo.known(DuoPosture.standInFold(view))
                reading.degrees > halfOpenTo -> FoldInfo.none
                else -> FoldInfo.Inferred                                                   // closed: the cover screen
            }
            is Reading.Extensions -> {
                val f = reading.feature ?: return FoldInfo.Inferred
                if (!f.halfOpened && !f.separating) return FoldInfo.none
                val b = f.bounds
                if (b.width < 0 || b.height < 0 || (b.width == 0 && b.height == 0)) return FoldInfo.none
                var x = (b.left - viewLeft) / density
                var y = (b.top - viewTop) / density
                var w = b.width / density
                var h = b.height / density
                if (h >= w) { if (w < minBand) { x -= (minBand - w) / 2; w = minBand } }       // down the screen
                else { if (h < minBand) { y -= (minBand - h) / 2; h = minBand } }               // across it
                FoldInfo.known(DuoPosture.clip(Rect(x, y, w, h), view))
            }
        }
    }
}

/** A typed character as the key that types it on a US layout (the key row's latch over a letter:
 *  ⌘ latched, then "c" on the software keyboard, is ⌘C), or null for anything else. */
object CharKeys {
    fun usage(c: Char): Int? = when (c) {
        in 'a'..'z' -> 0x04 + (c - 'a')
        in 'A'..'Z' -> 0x04 + (c - 'A')
        in '1'..'9' -> 0x1E + (c - '1')
        '0' -> 0x27
        ' ' -> 0x2C
        '-' -> 0x2D; '=' -> 0x2E; '[' -> 0x2F; ']' -> 0x30; '\\' -> 0x31
        ';' -> 0x33; '\'' -> 0x34; '`' -> 0x35; ',' -> 0x36; '.' -> 0x37; '/' -> 0x38
        '\n' -> 0x28; '\t' -> 0x2B
        else -> null
    }
}
