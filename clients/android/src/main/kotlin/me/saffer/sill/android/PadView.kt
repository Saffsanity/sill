package me.saffer.sill.android

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.RectF
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.view.Choreographer
import android.view.MotionEvent
import android.view.View
import me.saffer.sill.core.InputEvent
import me.saffer.sill.core.ui.Copy
import me.saffer.sill.core.ui.PadTracker
import me.saffer.sill.core.ui.Palette
import me.saffer.sill.core.ui.Rgba
import me.saffer.sill.core.ui.TextStyle
import me.saffer.sill.core.ui.Ui

/**
 * The portrait trackpad (Trackpad in TrackpadView.swift): its well, dot grid and hint, and core's
 * PadTracker for what the fingers do (relative pointer, taps, two-finger scroll with the coast, the
 * hold-then-drag, the key row's latched modifiers around a click).
 */
@SuppressLint("ViewConstructor")
class PadView(context: Context, private val dp: Dp, send: (InputEvent) -> Unit) : View(context) {
    val tracker = PadTracker(send)
    private val well = Look.fill(Palette.trackpad)
    private val line = Look.stroke(Rgba.white.opacity(Ui.padStrokeAlpha), dp(1.0))
    private val dot = Look.fill(Rgba.white.opacity(Ui.padDotAlpha))
    private val hint = TextPaint(Look.textPaint(dp, TextStyle(Ui.padHintSize), Palette.muted))
    private var hintLayout: StaticLayout? = null
    private var ticking = false
    private val rect = RectF()

    init {
        contentDescription = Copy.trackpadHint
        tracker.onHaptic = { h ->
            when (h) {
                PadTracker.Haptic.Click -> Haptics.click(this)
                PadTracker.Haptic.DragStart -> Haptics.hold(this)
                PadTracker.Haptic.DragEnd -> Haptics.click(this)
            }
        }
    }

    /** The vertical span the pad's motion is measured against (a phone's width ÷ 1.6), or null. */
    fun setSpan(span: Double?) { tracker.verticalSpan = span }

    override fun onSizeChanged(w: Int, h: Int, ow: Int, oh: Int) {
        tracker.width = dp.px.dp(w).coerceAtLeast(1.0)
        tracker.height = dp.px.dp(h).coerceAtLeast(1.0)
        val inset = dp(Ui.padHintInset).toInt()
        hintLayout = StaticLayout.Builder.obtain(Copy.trackpadHint, 0, Copy.trackpadHint.length, hint, (w - 2 * inset).coerceAtLeast(1))
            .setAlignment(Layout.Alignment.ALIGN_CENTER).build()
    }

    override fun onDraw(c: Canvas) {
        val r = rect.apply { set(0f, 0f, width.toFloat(), height.toFloat()) }
        val rad = dp(Ui.padCorner)
        c.drawRoundRect(r, rad, rad, well)
        c.save()
        c.clipRect(rad / 2, rad / 2, width - rad / 2, height - rad / 2)
        val step = dp(Ui.padDotStep)
        var y = step / 2
        while (y < height) { var x = step / 2; while (x < width) { c.drawCircle(x, y, dp(Ui.padDotRadius), dot); x += step }; y += step }
        c.restore()
        Look.strokeBorder(c, r, rad, line)
        hintLayout?.let { l ->
            val inset = dp(Ui.padHintInset)
            c.save(); c.translate(inset, height - inset - l.height); l.draw(c); c.restore()
        }
    }

    private val frame = object : Choreographer.FrameCallback {
        override fun doFrame(t: Long) {
            tracker.tick(t / 1e9)
            if (tracker.needsTicks && isAttachedToWindow) Choreographer.getInstance().postFrameCallback(this) else ticking = false
        }
    }

    private fun ensureTicks() {
        if (!ticking && tracker.needsTicks) { ticking = true; Choreographer.getInstance().postFrameCallback(frame) }
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        val t = e.eventTime / 1000.0
        val i = e.actionIndex
        fun x(k: Int) = dp.px.dp(e.getX(k))
        fun y(k: Int) = dp.px.dp(e.getY(k))
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                parent?.requestDisallowInterceptTouchEvent(true)
                tracker.down(e.getPointerId(i), x(i), y(i), t)
            }
            MotionEvent.ACTION_MOVE -> for (k in 0 until e.pointerCount) tracker.move(e.getPointerId(k), x(k), y(k), t)
            MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP -> tracker.up(e.getPointerId(i), x(i), y(i), t)
            MotionEvent.ACTION_CANCEL -> tracker.cancel()
        }
        ensureTicks()
        return true
    }

    override fun onDetachedFromWindow() {
        Choreographer.getInstance().removeFrameCallback(frame); ticking = false
        tracker.cancel()
        super.onDetachedFromWindow()
    }
}
