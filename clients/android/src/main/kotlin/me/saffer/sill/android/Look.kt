package me.saffer.sill.android

import android.animation.TimeInterpolator
import android.animation.ValueAnimator
import android.content.Context
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.view.HapticFeedbackConstants
import android.view.View
import me.saffer.sill.core.ui.Curve
import me.saffer.sill.core.ui.Glyph
import me.saffer.sill.core.ui.Rect
import me.saffer.sill.core.ui.Rgba
import me.saffer.sill.core.ui.Symbol
import me.saffer.sill.core.ui.TextStyle
import me.saffer.sill.core.ui.Type

/*
 * How the Android app draws the shared design layer (clients/core's ui package, docs/ui-parity.md):
 * one point of the iOS app is one dp here, text is in dp times the person's font scale capped where
 * the iOS app caps it (Type.scaled), the SF Symbols are core's vector glyphs, and every animation
 * runs on core's curves. Nothing here decides where anything goes: the layouts are core's.
 */

/** dp ↔ pixels for one screen; the pure arithmetic is [Px], tested on the JVM. */
class Dp(context: Context) {
    val density = context.resources.displayMetrics.density.toDouble()
    val fontScale = context.resources.configuration.fontScale.toDouble()
    val px = Px(density)
    operator fun invoke(v: Double) = (v * density).toFloat()
    fun rectF(r: Rect) = RectF((r.x * density).toFloat(), (r.y * density).toFloat(), (r.maxX * density).toFloat(), (r.maxY * density).toFloat())
    /** A text style's size in pixels, following the font scale up to iOS's xxLarge, never below Large. */
    fun text(style: TextStyle) = (Type.scaled(style, fontScale).size * density).toFloat()
}

object Look {
    private val faces = HashMap<Int, Typeface>()

    /** The system's sans serif at the iOS weight (Roboto on most devices, the nearest to SF here). */
    fun typeface(weight: TextStyle.Weight): Typeface = synchronized(faces) {
        faces.getOrPut(weight.css) { Typeface.create(Typeface.SANS_SERIF, weight.css, false) }
    }

    fun textPaint(dp: Dp, style: TextStyle, color: Rgba, capped: Boolean = true) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        typeface = typeface(style.weight)
        textSize = if (capped) dp.text(style) else (style.size * dp.density).toFloat()
        this.color = color.argb
    }

    fun fill(color: Rgba) = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.color = color.argb; style = Paint.Style.FILL }

    fun stroke(color: Rgba, width: Float) = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        this.color = color.argb; style = Paint.Style.STROKE; strokeWidth = width
    }

    /** A hairline inside `r` (SwiftUI's strokeBorder: the line's outer edge on the shape's edge). */
    fun strokeBorder(c: Canvas, r: RectF, radius: Float, paint: Paint) {
        val h = paint.strokeWidth / 2
        c.drawRoundRect(r.left + h, r.top + h, r.right - h, r.bottom - h, radius - h, radius - h, paint)
    }

    /** Text truncated with an ellipsis to `max` pixels. */
    fun fit(text: String, paint: Paint, max: Float): String {
        if (paint.measureText(text) <= max) return text
        var n = text.length
        while (n > 0 && paint.measureText(text, 0, n) + paint.measureText("…") > max) n--
        return text.substring(0, n).trimEnd() + "…"
    }

    /** Draws `text` with its baseline placed so the line's middle is at `cy`. */
    fun textCentred(c: Canvas, text: String, cx: Float, cy: Float, paint: Paint) {
        val fm = paint.fontMetrics
        c.drawText(text, cx - paint.measureText(text) / 2, cy - (fm.ascent + fm.descent) / 2, paint)
    }

    fun textLeft(c: Canvas, text: String, x: Float, cy: Float, paint: Paint) {
        val fm = paint.fontMetrics
        c.drawText(text, x, cy - (fm.ascent + fm.descent) / 2, paint)
    }

    private val glyphPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND }
    private val path = Path()

    /**
     * Core's glyph for an SF Symbol, centred on (cx, cy), as the iOS app sets it at `pointSize`
     * points; cutouts in `background`. Main thread only (one shared paint and path).
     */
    fun symbol(c: Canvas, dp: Dp, symbol: Symbol, cx: Float, cy: Float, pointSize: Double, color: Rgba, background: Rgba) {
        val box = dp(Symbol.boxFor(pointSize))
        val s = box / 24f
        c.save()
        c.translate(cx - box / 2, cy - box / 2)
        c.scale(s, s)
        for (g in symbol.shapes) {
            val p = glyphPaint
            p.color = (if (g.cutout) background else color).argb
            val sw = g.stroke
            if (sw != null) { p.style = Paint.Style.STROKE; p.strokeWidth = sw.toFloat() } else p.style = Paint.Style.FILL
            when (g) {
                is Glyph.Circle -> c.drawCircle(g.cx.toFloat(), g.cy.toFloat(), g.r.toFloat(), p)
                is Glyph.Line -> c.drawLine(g.x1.toFloat(), g.y1.toFloat(), g.x2.toFloat(), g.y2.toFloat(), p)
                is Glyph.RoundRect -> c.drawRoundRect(g.x.toFloat(), g.y.toFloat(), (g.x + g.w).toFloat(), (g.y + g.h).toFloat(), g.r.toFloat(), g.r.toFloat(), p)
                is Glyph.Polygon -> { poly(g.points, true); c.drawPath(path, p) }
                is Glyph.Polyline -> { poly(g.points, false); c.drawPath(path, p) }
            }
        }
        c.restore()
    }

    private fun poly(points: List<Pair<Double, Double>>, close: Boolean) {
        path.reset()
        points.forEachIndexed { i, (x, y) -> if (i == 0) path.moveTo(x.toFloat(), y.toFloat()) else path.lineTo(x.toFloat(), y.toFloat()) }
        if (close) path.close()
    }

    /** Draws under the system bars and the cutout; each screen keeps its contents inside the insets itself. */
    @Suppress("DEPRECATION")
    fun edgeToEdge(activity: android.app.Activity) {
        val w = activity.window
        w.statusBarColor = android.graphics.Color.TRANSPARENT
        w.navigationBarColor = android.graphics.Color.TRANSPARENT
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
            // The decor first: before setContentView there is none, and PhoneWindow's
            // getInsetsController then throws (a crash at every launch on Android 11 and later,
            // found by rendering the activities with Robolectric's native graphics).
            w.decorView
            w.setDecorFitsSystemWindows(false)
            w.insetsController?.systemBarsBehavior = android.view.WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        } else {
            w.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_LAYOUT_STABLE or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
        }
        w.attributes = w.attributes.apply {
            layoutInDisplayCutoutMode = android.view.WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
    }

    /** The iOS app's app icon fallback: its first two letters on iconFallback. */
    fun initials(name: String) = name.take(2)
}

/** Core's curves as Android interpolators, and the person's Reduce Motion (Remove animations). */
object Motions {
    fun interpolator(curve: Curve) = TimeInterpolator { f -> curve.atFraction(f.toDouble()).toFloat() }

    /** Animations off in the system's settings: what moves only fades (the iOS app's Reduce Motion). */
    val reduced get() = !ValueAnimator.areAnimatorsEnabled()

    /** Runs `curve` from 0 to 1 (a spring past 1 and back), calling `update` with its progress. */
    fun run(curve: Curve, update: (Float) -> Unit, end: () -> Unit = {}): ValueAnimator =
        ValueAnimator.ofFloat(0f, 1f).apply {
            duration = (curve.seconds * 1000).toLong()
            interpolator = interpolator(curve)
            addUpdateListener { update(it.animatedValue as Float) }
            addListener(object : android.animation.AnimatorListenerAdapter() {
                private var cancelled = false
                override fun onAnimationCancel(animation: android.animation.Animator) { cancelled = true }
                override fun onAnimationEnd(animation: android.animation.Animator) { if (!cancelled) end() }
            })
            start()
        }
}

/** The haptics the iOS app plays, as Android's feedback constants (a phone's vibrator; tablets often none). */
object Haptics {
    fun detent(v: View) = v.performHapticFeedback(HapticFeedbackConstants.CLOCK_TICK)
    fun hold(v: View) = v.performHapticFeedback(HapticFeedbackConstants.LONG_PRESS)
    fun click(v: View) = v.performHapticFeedback(HapticFeedbackConstants.CONTEXT_CLICK)
    fun key(v: View) = v.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
    fun refused(v: View) = v.performHapticFeedback(
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) HapticFeedbackConstants.REJECT else HapticFeedbackConstants.LONG_PRESS)
}
