package me.saffer.sill.core.ui

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

/*
 * The shared design layer of the clients that are not Swift (docs/ui-parity.md): the iOS app's
 * tokens (Tokens.kt, generated from its Swift), the geometry its layouts compute (PhonePortraitLayout,
 * StreamLayout), its animation curves and its screen state (StreamUi), written once here so the
 * Android app, the Windows client and the Windows and Linux hosts all draw the same thing. Pure
 * Kotlin: no platform type, so every number is checked on the JVM against the Swift that made it.
 */

/** A colour as the iOS app writes it, `Color(hex: 0xRRGGBB)` with an opacity. */
data class Rgba(val rgb: Int, val alpha: Double = 1.0) {
    val red: Int get() = (rgb shr 16) and 0xFF
    val green: Int get() = (rgb shr 8) and 0xFF
    val blue: Int get() = rgb and 0xFF
    /** 0xAARRGGBB, Android's and AWT's packed colour. */
    val argb: Int get() = ((alpha.coerceIn(0.0, 1.0) * 255 + 0.5).toInt() shl 24) or (rgb and 0xFFFFFF)
    fun opacity(a: Double) = Rgba(rgb, a)

    companion object {
        val black = Rgba(0x000000)
        val white = Rgba(0xFFFFFF)
        val clear = Rgba(0x000000, 0.0)
        /** SwiftUI's `.orange` in the dark appearance (the panel's warnings and callouts). */
        val orange = Rgba(0xFF9F0A)
    }
}

/** A size in points (iOS), dp (Android) or logical pixels (the desktop). */
data class Size(val width: Double, val height: Double) {
    companion object { val zero = Size(0.0, 0.0) }
}

/** A rectangle in the same units, origin at the top left, as CGRect is in the iOS app's layouts. */
data class Rect(val x: Double, val y: Double, val width: Double, val height: Double) {
    val minX get() = x
    val minY get() = y
    val maxX get() = x + width
    val maxY get() = y + height
    val midX get() = x + width / 2
    val midY get() = y + height / 2
    val size get() = Size(width, height)
    fun contains(px: Double, py: Double) = px >= x && px < maxX && py >= y && py < maxY
    fun inset(dx: Double, dy: Double) = Rect(x + dx, y + dy, max(0.0, width - 2 * dx), max(0.0, height - 2 * dy))
    fun offset(dx: Double, dy: Double) = Rect(x + dx, y + dy, width, height)

    companion object { val zero = Rect(0.0, 0.0, 0.0, 0.0) }
}

/** A text style as the iOS app sets one: its size in points and its weight. */
data class TextStyle(val size: Double, val weight: Weight = Weight.Regular) {
    enum class Weight(val css: Int) { Regular(400), Medium(500), Semibold(600), Bold(700), Heavy(800), Light(300) }
}

/**
 * The text styles the iOS app uses, at the default text size (Large). The sized ones are its
 * literals (Tokens.kt); the named ones are the system's styles it names (`.footnote`, `.headline`,
 * `.body`, `.subheadline`, `.caption`), whose Large sizes these are (Apple's Human Interface
 * Guidelines, Typography). The iOS app caps the panel and the footer at xxLarge; the clients follow
 * the platform's text size the same way (Type.scaled).
 */
object Type {
    val barLabel = TextStyle(Ui.barLabelSize, TextStyle.Weight.Medium)
    val barIcon = TextStyle(Ui.barIconSize)
    val aaTall = TextStyle(Ui.aaTallSize, TextStyle.Weight.Semibold)
    val aaShort = TextStyle(Ui.aaShortSize, TextStyle.Weight.Semibold)
    val rulerValue = TextStyle(Ui.rulerValueSize, TextStyle.Weight.Semibold)
    val rulerTick = TextStyle(Ui.rulerTickLabelSize, TextStyle.Weight.Medium)
    val rowTitle = TextStyle(Ui.rowTitleSize)
    val rowTrailing = TextStyle(Ui.rowTrailingSize)
    val sectionHeader = TextStyle(Ui.sectionHeaderSize, TextStyle.Weight.Medium)
    val cap = TextStyle(Ui.capTextSize, TextStyle.Weight.Medium)
    val connectTitle = TextStyle(Ui.connectTitleSize, TextStyle.Weight.Semibold)
    val connectStatus = TextStyle(Ui.connectStatusSize)
    val connectLink = TextStyle(Ui.connectLinkSize, TextStyle.Weight.Semibold)
    val search = TextStyle(15.0)
    val lightLabel = TextStyle(10.0, TextStyle.Weight.Medium)

    val footnote = TextStyle(13.0)
    val footnoteMedium = TextStyle(13.0, TextStyle.Weight.Medium)
    val headline = TextStyle(17.0, TextStyle.Weight.Semibold)
    val body = TextStyle(17.0)
    val bodySemibold = TextStyle(17.0, TextStyle.Weight.Semibold)
    val subheadline = TextStyle(15.0)
    val caption = TextStyle(12.0)

    /** The largest text scale the panel and the footer follow: iOS's xxLarge over Large (23/17). */
    const val maxScale = 23.0 / 17.0
    fun scaled(style: TextStyle, platformScale: Double) =
        style.copy(size = style.size * platformScale.coerceIn(1.0, maxScale))
}

/**
 * An animation curve as SwiftUI names it, evaluated the way SwiftUI does, so a panel opening on
 * Android or Windows moves exactly as it does on the iPad: `value(t)` is the progress (0 to 1,
 * past 1 for a spring's bounce) `t` seconds in, `seconds` how long it runs before it rests.
 */
sealed class Curve {
    abstract val seconds: Double
    abstract fun value(t: Double): Double
    /** Progress at a fraction (0–1) of [seconds], for platforms that drive animations by fraction. */
    fun atFraction(f: Double) = value(f.coerceIn(0.0, 1.0) * seconds)

    /** `.easeOut(duration:)`: cubic-bezier(0, 0, 0.58, 1). */
    data class EaseOut(val duration: Double) : Curve() {
        override val seconds get() = duration
        override fun value(t: Double) = bezier(0.0, 0.0, 0.58, 1.0, t / duration)
    }

    /** `.easeInOut(duration:)`: cubic-bezier(0.42, 0, 0.58, 1). */
    data class EaseInOut(val duration: Double) : Curve() {
        override val seconds get() = duration
        override fun value(t: Double) = bezier(0.42, 0.0, 0.58, 1.0, t / duration)
    }

    /**
     * `.spring(duration:bounce:)`: mass 1, stiffness (2π / duration)², damping 4π(1 − bounce) /
     * duration (SwiftUI's Spring(duration:bounce:)), from rest at 0 to 1. It runs until it is within
     * a thousandth of 1 and has stopped moving, which is longer than `duration`, the perceptual one.
     */
    data class Spring(val duration: Double, val bounce: Double) : Curve() {
        private val w0 = 2 * PI / duration
        private val zeta = 1 - bounce
        override val seconds: Double by lazy {
            var t = duration
            val step = duration / 200
            var still = 0.0
            while (t < duration * 6) {
                if (abs(value(t) - 1) < 1e-3) { still += step; if (still >= duration / 10) return@lazy t - still + step } else still = 0.0
                t += step
            }
            t
        }
        override fun value(t: Double): Double {
            if (t <= 0) return 0.0
            if (zeta >= 1) return 1 - exp(-w0 * t) * (1 + w0 * t)
            val wd = w0 * sqrt(1 - zeta * zeta)
            return 1 - exp(-zeta * w0 * t) * (cos(wd * t) + zeta * w0 / wd * sin(wd * t))
        }
    }

    companion object {
        /** A unit cubic Bézier from (0,0) to (1,1) through (x1,y1) and (x2,y2), at x = [x], as CSS
         *  and Core Animation solve it: x for t by Newton's method, bisection where that stalls. */
        fun bezier(x1: Double, y1: Double, x2: Double, y2: Double, x: Double): Double {
            if (x <= 0) return 0.0
            if (x >= 1) return 1.0
            val cx = 3 * x1; val bx = 3 * (x2 - x1) - cx; val ax = 1 - cx - bx
            val cy = 3 * y1; val by = 3 * (y2 - y1) - cy; val ay = 1 - cy - by
            fun sx(t: Double) = ((ax * t + bx) * t + cx) * t
            fun dx(t: Double) = (3 * ax * t + 2 * bx) * t + cx
            var t = x
            repeat(8) {
                val e = sx(t) - x
                if (abs(e) < 1e-9) return ((ay * t + by) * t + cy) * t
                val d = dx(t)
                if (abs(d) < 1e-9) return@repeat
                t -= e / d
            }
            var lo = 0.0; var hi = 1.0; t = x
            while (hi - lo > 1e-9) {
                val v = sx(t)
                if (v < x) lo = t else hi = t
                t = (lo + hi) / 2
            }
            return ((ay * t + by) * t + cy) * t
        }

        fun lerp(a: Double, b: Double, p: Double) = a + (b - a) * p
        fun clamp01(v: Double) = min(1.0, max(0.0, v))
    }
}
