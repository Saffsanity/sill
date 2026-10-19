package me.saffer.sill.android

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.graphics.Shader
import android.view.MotionEvent
import android.view.View
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import me.saffer.sill.core.ui.Copy
import me.saffer.sill.core.ui.KeyRow
import me.saffer.sill.core.ui.Motion
import me.saffer.sill.core.ui.Palette
import me.saffer.sill.core.ui.Rgba
import me.saffer.sill.core.ui.Symbol
import me.saffer.sill.core.ui.TextScale
import me.saffer.sill.core.ui.Type
import me.saffer.sill.core.ui.Ui

/**
 * A bar button (TopBar's and the portrait rows' `button`): a rounded square on the control colour,
 * the symbol over its 11 pt label, both in the accent while what it opens shows. `iconBox` is the
 * phone's row 1, whose symbols sit in a 24 pt box so their labels share one line.
 */
@SuppressLint("ViewConstructor")
open class BarButton(context: Context, protected val dp: Dp, var symbol: Symbol?, var label: String) : View(context) {
    var radius = Ui.barButtonRadius
    var iconSize = Ui.barIconSize
    var iconBox: Double? = null
    var spacing = 4.0
    var open = false
        set(v) { if (field != v) { field = v; invalidate() } }
    var onTap: () -> Unit = {}
    protected val bg = Look.fill(Palette.control)
    protected val labelPaint = Look.textPaint(dp, Type.barLabel, Palette.barLabel)

    init {
        isClickable = true
        isFocusable = true
        setOnClickListener { onTap() }
    }

    override fun drawableStateChanged() { super.drawableStateChanged(); invalidate() }

    private val box = RectF()

    override fun onDraw(c: Canvas) {
        val r = box.apply { set(0f, 0f, width.toFloat(), height.toFloat()) }
        bg.color = (if (open) Palette.controlOpen else Palette.control).argb
        c.drawRoundRect(r, dp(radius), dp(radius), bg)
        val tint = if (open) Palette.accent else Palette.text
        labelPaint.color = (if (open) Palette.accent else Palette.barLabel).argb
        val box = dp(iconBox ?: Symbol.boxFor(iconSize))
        val fm = labelPaint.fontMetrics
        val labelH = fm.descent - fm.ascent
        val block = box + dp(spacing) + labelH
        val top = (height - block) / 2
        drawIcon(c, width / 2f, top + box / 2, tint)
        val text = Look.fit(label, labelPaint, width - dp(4.0))
        c.drawText(text, (width - labelPaint.measureText(text)) / 2, top + box + dp(spacing) - fm.ascent, labelPaint)
        if (isPressed) c.drawRoundRect(r, dp(radius), dp(radius), pressed)
    }

    protected open fun drawIcon(c: Canvas, cx: Float, cy: Float, tint: Rgba) {
        symbol?.let { Look.symbol(c, dp, it, cx, cy, iconSize, tint, if (open) Palette.controlOpen else Palette.control) }
    }

    override fun onInitializeAccessibilityNodeInfo(info: AccessibilityNodeInfo) {
        super.onInitializeAccessibilityNodeInfo(info)
        info.className = "android.widget.Button"
    }

    companion object { val pressed = Look.fill(Rgba.white.opacity(0.08)) }
}

/**
 * The Aa control (TextScaleControl): a bar button that unfolds into the ruler while a finger holds
 * it. The view is laid out at the ruler's frame; `button` is the button's frame inside it, and a
 * touch that starts outside the button falls through to what is under it.
 */
@SuppressLint("ViewConstructor")
class TextSizeButton(context: Context, dp: Dp, private val step: () -> Double) : BarButton(context, dp, null, "Text size") {
    /** The button's frame in this view. */
    var button = RectF()
    var scale: Double? = null
        set(v) { field = v; contentDescription = Copy.textSize; invalidate() }
    var onDown: () -> Unit = {}
    var onMoved: (Double) -> Boolean = { false }
    var onUp: () -> Unit = {}
    /** The live value under the thumb while the ruler is open. */
    var live = 1.0
        set(v) {
            if (field == v) return
            val from = shownLive
            field = v
            liveAnim?.cancel()
            liveAnim = if (Motions.reduced) { shownLive = v; invalidate(); null } else
                Motions.run(Motion.rulerDetent, { p -> shownLive = from + (v - from) * p; invalidate() })
        }
    private var shownLive = 1.0
    private var liveAnim: ValueAnimator? = null
    private var progress = 0f
    private var openAnim: ValueAnimator? = null
    private var startX = 0f
    private var tracking = false

    private val aaPaint = Look.textPaint(dp, Type.aaTall, Palette.text)
    private val track = Look.fill(Palette.barLabel.opacity(0.35))
    private val tick = Look.fill(Palette.barLabel.opacity(0.6))
    private val tickLabel = Look.textPaint(dp, Type.rulerTick, Palette.barLabel, capped = false)
    private val valuePaint = Look.textPaint(dp, Type.rulerValue, Palette.text, capped = false)
    private val thumb = Look.fill(Palette.accent).apply { setShadowLayer(dp(3.0), 0f, dp(1.0), Rgba.black.opacity(0.35).argb) }
    private val fadeMask = Paint().apply { xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_IN) }
    private val fullRect = RectF()
    private var maskWidth = -1

    init {
        contentDescription = Copy.textSize
        setOnClickListener(null)
        isClickable = false
        setLayerType(LAYER_TYPE_SOFTWARE, null)   // the thumb's shadow
    }

    /** The ruler's live value without the slide (as it opens). */
    fun snap(v: Double) { liveAnim?.cancel(); live = v; liveAnim?.cancel(); shownLive = v }

    fun unfold(isOpen: Boolean) {
        if (isOpen) { shownLive = live }
        val target = if (isOpen) 1f else 0f
        if (progress == target) return
        openAnim?.cancel()
        val from = progress
        if (Motions.reduced) { progress = target; invalidate(); return }
        openAnim = Motions.run(if (isOpen) Motion.rulerOpen else Motion.rulerClose, { p -> progress = from + (target - from) * p; invalidate() })
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                if (!button.contains(e.x, e.y)) return false
                tracking = true; startX = e.x
                parent?.requestDisallowInterceptTouchEvent(true)
                onDown()
            }
            MotionEvent.ACTION_MOVE -> if (tracking && onMoved(dp.px.dp(e.x - startX))) Haptics.detent(this)
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> if (tracking) {
                tracking = false
                if (e.actionMasked == MotionEvent.ACTION_UP) performClick()
                onUp()
            }
        }
        return tracking
    }

    override fun performClick(): Boolean { super.performClick(); return true }

    override fun onDraw(c: Canvas) {
        val r = dp(radius)
        // The button, fading as the ruler unfolds over it.
        if (progress < 1f) {
            c.saveLayerAlpha(button, ((1 - progress.coerceIn(0f, 1f)) * 255).toInt())
            bg.color = Palette.control.argb
            c.drawRoundRect(button, r, r, bg)
            aaPaint.textSize = dp.text(if (button.height() >= dp(60.0)) Type.aaTall else Type.aaShort)
            // "Aa" over the scale ("1×"), 2 pt apart, or in the phone's 24 pt icon box (TextScaleControl).
            val fm = labelPaint.fontMetrics
            val labelH = fm.descent - fm.ascent
            val am = aaPaint.fontMetrics
            val box = iconBox?.let { dp(it) } ?: (am.descent - am.ascent)
            val gap = if (iconBox == null) dp(2.0) else dp(spacing)
            val block = box + gap + labelH
            val top = button.top + (button.height() - block) / 2
            Look.textCentred(c, "Aa", button.centerX(), top + box / 2, aaPaint)
            labelPaint.color = Palette.barLabel.argb
            val text = TextScale.label(scale ?: 1.0) + "×"
            c.drawText(text, button.centerX() - labelPaint.measureText(text) / 2, top + box + gap - fm.ascent, labelPaint)
            c.restore()
        }
        if (progress <= 0f) return
        // The ruler: a track with five ticks that slides so the live value sits under the fixed thumb.
        val p = progress.coerceIn(0f, 1.2f)
        c.save()
        if (!Motions.reduced) { val s = 0.6f + 0.4f * p; c.scale(s, s, button.centerX(), button.centerY()) }
        val alpha = (p.coerceAtMost(1f) * 255).toInt()
        val full = fullRect.apply { set(0f, button.top, width.toFloat(), button.bottom) }
        c.saveLayerAlpha(full, alpha)
        bg.color = Palette.controlOpen.argb
        c.drawRoundRect(full, r, r, bg)
        val stepPx = dp(step())
        val midX = full.centerX()
        val midY = full.centerY() + dp(4.0)
        fun x(v: Double) = midX + ((v - shownLive) / 0.25).toFloat() * stepPx
        c.saveLayer(full, null)
        c.drawRoundRect(x(TextScale.steps.first()), midY - dp(1.5), x(TextScale.steps.last()), midY + dp(1.5), dp(1.5), dp(1.5), track)
        for (v in TextScale.steps) {
            c.drawRect(x(v) - dp(1.0), midY - dp(4.5), x(v) + dp(1.0), midY + dp(4.5), tick)
            tickLabel.color = (if (v == live) Palette.text else Palette.barLabel).argb
            val t = TextScale.label(v)
            c.drawText(t, x(v) - tickLabel.measureText(t) / 2, midY + dp(9.0) - tickLabel.fontMetrics.ascent, tickLabel)
        }
        if (maskWidth != width) { maskWidth = width; fadeMask.shader = LinearGradient(full.left, 0f, full.right, 0f, intArrayOf(0, -0x1000000, -0x1000000, 0),
            floatArrayOf(0f, 0.12f, 0.88f, 1f), Shader.TileMode.CLAMP) }
        c.drawRect(full, fadeMask)
        c.restore()
        c.drawCircle(midX, midY, dp(Ui.rulerThumb / 2), thumb)
        Look.textCentred(c, "${TextScale.label(live)}×", midX, full.top + dp(13.0), valuePaint)
        c.restore()
        c.restore()
    }

    override fun onInitializeAccessibilityNodeInfo(info: AccessibilityNodeInfo) {
        super.onInitializeAccessibilityNodeInfo(info)
        info.className = "android.widget.SeekBar"
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) info.stateDescription = Copy.textSizeValue(scale)
        else info.text = Copy.textSizeValue(scale)
        info.addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_FORWARD)
        info.addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SCROLL_BACKWARD)
    }

    /** TalkBack's adjustable action: one detent up or down (VoiceOver's adjustable action). */
    var onStep: (Boolean) -> Unit = {}

    override fun performAccessibilityAction(action: Int, arguments: android.os.Bundle?): Boolean = when (action) {
        AccessibilityNodeInfo.ACTION_SCROLL_FORWARD -> { onStep(true); sendAccessibilityEvent(AccessibilityEvent.TYPE_VIEW_SELECTED); true }
        AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD -> { onStep(false); sendAccessibilityEvent(AccessibilityEvent.TYPE_VIEW_SELECTED); true }
        else -> super.performAccessibilityAction(action, arguments)
    }
}

/**
 * One cap of the portrait key row (KeyRow's `cap`): its word or glyph on the control colour, a
 * latched modifier lit. The view is the cap's touch area (at least 48 dp: a 44 dp cap grows into the
 * gap beside it); `drawn` is the cap itself inside it.
 */
@SuppressLint("ViewConstructor")
class KeyCapView(context: Context, private val dp: Dp, val key: KeyRow.Key) : View(context) {
    var drawn = RectF()
    var lit = false
        set(v) { if (field != v) { field = v; invalidate() } }
    var onTap: (KeyRow.Key) -> Unit = {}
    private val bg = Look.fill(Palette.control)
    private val text = Look.textPaint(dp, Type.cap, Palette.text)

    init {
        isClickable = true
        isFocusable = true
        contentDescription = key.label
        setOnClickListener { Haptics.key(this); onTap(key) }
    }

    override fun drawableStateChanged() { super.drawableStateChanged(); invalidate() }

    override fun onDraw(c: Canvas) {
        val r = dp(Ui.capRadius)
        bg.color = (if (lit) Palette.controlOpen else Palette.control).argb
        c.drawRoundRect(drawn, r, r, bg)
        val tint = if (lit) Palette.accent else Palette.text
        val bgc = if (lit) Palette.controlOpen else Palette.control
        val cx = drawn.centerX(); val cy = drawn.centerY()
        when (val k = key) {
            is KeyRow.Key.Press -> { text.color = tint.argb; Look.textCentred(c, Look.fit(k.title, text, drawn.width() - dp(4.0)), cx, cy, text) }
            is KeyRow.Key.Modifier -> { text.color = tint.argb; Look.textCentred(c, Look.fit(k.title, text, drawn.width() - dp(4.0)), cx, cy, text) }
            is KeyRow.Key.Arrow -> Look.symbol(c, dp, when (k.direction) {
                KeyRow.Direction.Left -> Symbol.ChevronLeft; KeyRow.Direction.Right -> Symbol.ChevronRight
                KeyRow.Direction.Up -> Symbol.ChevronUp; KeyRow.Direction.Down -> Symbol.ChevronDown
            }, cx, cy, 15.0, tint, bgc)
            KeyRow.Key.Keyboard -> Look.symbol(c, dp, Symbol.Keyboard, cx, cy, 17.0, tint, bgc)
            KeyRow.Key.Spotlight -> Look.symbol(c, dp, Symbol.Spotlight, cx, cy, 16.0, tint, bgc)
        }
        if (isPressed) c.drawRoundRect(drawn, r, r, BarButton.pressed)
    }

    override fun onInitializeAccessibilityNodeInfo(info: AccessibilityNodeInfo) {
        super.onInitializeAccessibilityNodeInfo(info)
        info.className = if (key is KeyRow.Key.Modifier) "android.widget.ToggleButton" else "android.widget.Button"
        if (key is KeyRow.Key.Modifier) { info.isCheckable = true; info.isChecked = lit }
    }
}

/** The stream panel behind the video: its colour, its corners and its white hairline. */
class PanelBackdrop(context: Context, private val dp: Dp) : View(context) {
    private val fill = Look.fill(Palette.panel)
    private val line = Look.stroke(Rgba.white.opacity(Ui.panelStrokeAlpha), dp(1.0))
    private val box = RectF()
    override fun onDraw(c: Canvas) {
        val r = box.apply { set(0f, 0f, width.toFloat(), height.toFloat()) }
        c.drawRoundRect(r, dp(Ui.panelRadius), dp(Ui.panelRadius), fill)
        Look.strokeBorder(c, r, dp(Ui.panelRadius), line)
    }
}

/** The panel's hairline drawn over the video (the SurfaceView punches through the backdrop). */
class PanelOutline(context: Context, private val dp: Dp) : View(context) {
    private val line = Look.stroke(Rgba.white.opacity(Ui.panelStrokeAlpha), dp(1.0))
    private val corner = Look.fill(Rgba.black)
    private val path = Path()
    private val box = RectF()
    override fun onDraw(c: Canvas) {
        val r = box.apply { set(0f, 0f, width.toFloat(), height.toFloat()) }
        val rad = dp(Ui.panelRadius)
        // The corners outside the rounded rectangle, in the screen's black, so the video's corners are round too.
        path.reset()
        path.fillType = Path.FillType.EVEN_ODD
        path.addRect(r, Path.Direction.CW)
        path.addRoundRect(r, rad, rad, Path.Direction.CW)
        c.drawPath(path, corner)
        Look.strokeBorder(c, r, rad, line)
    }
}

/** The landscape bar's background, run up under the status bar and the cutout. */
class BarBackground(context: Context) : View(context) {
    init { setBackgroundColor(Palette.bar.argb) }
}

/** The arrow the device draws for the pointer (HEVCDisplayView's sprite): this device's own while its
 *  trackpad moves it, the Mac's while the Mac moves it. Takes no touch. */
class PointerOverlay(context: Context, private val dp: Dp) : View(context) {
    /** The video's frame in this view, and where the pointer is in it (frame fractions), or null. */
    var frame = RectF()
    var at: Pair<Double, Double>? = null
        set(v) { if (field != v) { field = v; invalidate() } }
    private val fill = Look.fill(Rgba.white)
    private val edge = Look.stroke(Rgba.black, dp(1.2)).apply { strokeJoin = Paint.Join.ROUND }
    private val arrow = Path()

    init { isClickable = false; isFocusable = false; importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO }

    override fun onDraw(c: Canvas) {
        val (fx, fy) = at ?: return
        val x = frame.left + fx.toFloat() * frame.width()
        val y = frame.top + fy.toFloat() * frame.height()
        val u = dp(1.0)
        arrow.reset()
        arrow.moveTo(x, y)
        arrow.lineTo(x, y + 17 * u); arrow.lineTo(x + 4.2f * u, y + 13 * u); arrow.lineTo(x + 7 * u, y + 19.5f * u)
        arrow.lineTo(x + 9.6f * u, y + 18.4f * u); arrow.lineTo(x + 6.9f * u, y + 12 * u); arrow.lineTo(x + 12.4f * u, y + 12 * u)
        arrow.close()
        c.drawPath(arrow, fill)
        c.drawPath(arrow, edge)
    }
}

/** The drawer's dim (black at 0.58) or the Settings panel's clear catcher: a tap closes what is open
 *  and never reaches the Mac. */
class Catcher(context: Context) : View(context) {
    var onTap: () -> Unit = {}
    var dim = 0f
        set(v) { field = v; setBackgroundColor(Rgba.black.opacity(Ui.dimAlpha * v).argb) }

    init { importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        if (e.actionMasked == MotionEvent.ACTION_UP) onTap()
        return true
    }
}
