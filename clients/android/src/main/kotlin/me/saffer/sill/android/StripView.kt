package me.saffer.sill.android

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.Rect as PxRect
import android.graphics.RectF
import android.graphics.Shader
import android.os.Bundle
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityNodeProvider
import android.widget.OverScroller
import me.saffer.sill.core.WindowCommand
import me.saffer.sill.core.WindowInfo
import me.saffer.sill.core.ui.Copy
import me.saffer.sill.core.ui.DuoPosture
import me.saffer.sill.core.ui.FoldInfo
import me.saffer.sill.core.ui.LightColors
import me.saffer.sill.core.ui.Motion
import me.saffer.sill.core.ui.Palette
import me.saffer.sill.core.ui.Rect
import me.saffer.sill.core.ui.Rgba
import me.saffer.sill.core.ui.Size
import me.saffer.sill.core.ui.Symbol
import me.saffer.sill.core.ui.TextStyle
import me.saffer.sill.core.ui.Type
import me.saffer.sill.core.ui.Ui
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/** What a thumbnail shows: its window, its picture and its app's icon. */
class Thumb(val window: WindowInfo, val image: Bitmap?, val icon: Bitmap?, val active: Boolean)

/**
 * The window strip (WindowStrip): the Mac's windows as thumbnails, scrolling sideways under a fade.
 * A tap picks one; a 1.5 s hold opens its lights; keeping the finger down and moving it lifts the
 * thumbnail and drags it to another slot, the others making room on core's springs.
 */
@SuppressLint("ViewConstructor")
class StripView(context: Context, private val dp: Dp) : View(context) {
    var thumbWidth = 104.0; var thumbHeight = 66.0; var radius = 10.0; var spacing = 16.0; var pad = 10.0
    var fade = 0.86; var badge = 24.0
    var thumbs: List<Thumb> = emptyList()
        set(v) { field = v; clampScroll(); invalidate(); provider.invalidateAll() }
    /** The thumbnail whose lights are open (StreamUi.State.windowMenu). */
    var menuFor: Long? = null
        set(v) { if (field != v) { field = v; wiggle(v != null); invalidate() } }
    var onSelect: (Long) -> Unit = {}
    var onHold: (Long) -> Unit = {}
    var onCloseMenu: () -> Unit = {}
    var onCommand: (Long, String) -> Unit = { _, _ -> }
    var onReorder: (List<Long>) -> Unit = {}

    private val slop = ViewConfiguration.get(context).scaledTouchSlop
    private val scroller = OverScroller(context)
    private var tracker: android.view.VelocityTracker? = null
    private var scroll = 0f
    private var downX = 0f; private var downY = 0f; private var lastX = 0f
    private var downIndex = -1
    private var scrolling = false
    private var held = false
    private var lifted = -1
    private var liftDx = 0f
    private var target = -1
    private val shifts = HashMap<Long, Float>()
    private val shiftAnims = HashMap<Long, ValueAnimator>()
    private var dropAnim: ValueAnimator? = null
    private var dropOffset = 0f
    private var wiggleAngle = 0f
    private var wiggleAnim: ValueAnimator? = null
    private val holdRunnable = Runnable {
        val i = downIndex
        if (i in thumbs.indices && !scrolling) { held = true; Haptics.hold(this); onHold(thumbs[i].window.id) }
    }

    private val body = Look.fill(Palette.thumbBody)
    private val titleBar = Look.fill(Palette.thumbTitleBar)
    private val hairline = Look.stroke(Rgba.white.opacity(Ui.thumbStrokeAlpha), dp(1.0))
    private val halo = Look.stroke(Palette.accent, dp(Ui.haloWidth))
    private val ring = Look.fill(Palette.bar)
    private val iconBg = Look.fill(Palette.iconFallback)
    private val initials = Look.textPaint(dp, TextStyle(10.0, TextStyle.Weight.Semibold), Rgba.white, capped = false)
    private val bitmapPaint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)
    private val shadow = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = 0; setShadowLayer(dp(10.0), 0f, dp(4.0), Rgba.black.opacity(0.45).argb) }
    private val mask = Paint().apply { xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_IN) }
    private var maskFor: Pair<Int, Double>? = null
    private val clip = android.graphics.Path()
    private val frame = RectF()
    private val badgeRect = RectF()

    init {
        isFocusable = false
        setLayerType(LAYER_TYPE_SOFTWARE, null)   // the lifted thumbnail's shadow and the fade
    }

    private val slot get() = dp(thumbWidth + spacing)
    private val contentWidth get() = if (thumbs.isEmpty()) 0f else dp(8.0) * 2 + thumbs.size * dp(thumbWidth) + (thumbs.size - 1) * dp(spacing)
    private val maxScroll get() = max(0f, contentWidth - width)
    private fun clampScroll() { scroll = scroll.coerceIn(0f, maxScroll) }

    /** A thumbnail's frame in this view, before the lift's and the reorder's offsets. */
    fun frameOf(index: Int): RectF {
        val x = dp(8.0) + index * slot - scroll
        val y = dp(pad)
        return RectF(x, y, x + dp(thumbWidth), y + dp(thumbHeight))
    }

    fun frameOf(id: Long): RectF? = thumbs.indexOfFirst { it.window.id == id }.takeIf { it >= 0 }?.let(::frameOf)

    private fun indexAt(x: Float, y: Float) = thumbs.indices.firstOrNull { frameOf(it).let { r -> x >= r.left - dp(spacing / 2) && x < r.right + dp(spacing / 2) && y >= 0 && y <= height } } ?: -1

    override fun computeScroll() {
        if (scroller.computeScrollOffset()) { scroll = scroller.currX.toFloat(); clampScroll(); postInvalidateOnAnimation() }
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        if (tracker == null) tracker = android.view.VelocityTracker.obtain()
        tracker?.addMovement(e)
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                scroller.forceFinished(true)
                downX = e.x; downY = e.y; lastX = e.x
                downIndex = indexAt(e.x, e.y)
                scrolling = false; held = false; lifted = -1
                if (downIndex >= 0) postDelayed(holdRunnable, (Ui.holdToOpen * 1000).toLong())
                parent?.requestDisallowInterceptTouchEvent(true)
            }
            MotionEvent.ACTION_MOVE -> {
                val dx = e.x - downX
                if (lifted >= 0) {
                    liftDx = dx
                    val t = Reorder.target(lifted, dp.px.dp(dx), thumbWidth + spacing, thumbs.size)
                    if (t != target) { target = t; Haptics.detent(this); settleShifts() }
                    invalidate()
                } else if (held) {
                    if (abs(dx) > slop || abs(e.y - downY) > slop) {
                        // Keep holding and move: the lights go, the thumbnail lifts.
                        onCloseMenu()
                        lifted = downIndex; target = downIndex; liftDx = dx
                        invalidate()
                    }
                } else if (scrolling || abs(dx) > slop) {
                    if (!scrolling) { scrolling = true; removeCallbacks(holdRunnable) }
                    scroll -= e.x - lastX; clampScroll(); invalidate()
                }
                lastX = e.x
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                removeCallbacks(holdRunnable)
                val up = e.actionMasked == MotionEvent.ACTION_UP
                when {
                    lifted >= 0 -> drop()
                    held -> {}                                  // the lights stay until dismissed
                    scrolling -> if (up) {
                        tracker?.computeCurrentVelocity(1000)
                        val v = -(tracker?.xVelocity ?: 0f)
                        scroller.fling(scroll.toInt(), 0, v.toInt(), 0, 0, maxScroll.toInt(), 0, 0)
                        postInvalidateOnAnimation()
                    }
                    up && downIndex >= 0 && downIndex == indexAt(e.x, e.y) -> { performClick(); onSelect(thumbs[downIndex].window.id) }
                }
                tracker?.recycle(); tracker = null
                downIndex = -1
            }
        }
        return true
    }

    override fun performClick(): Boolean { super.performClick(); return true }

    private fun settleShifts() {
        for ((i, t) in thumbs.withIndex()) {
            val id = t.window.id
            val goal = Reorder.shift(i, lifted, target) * slot
            val from = shifts[id] ?: 0f
            if (from == goal) continue
            shiftAnims.remove(id)?.cancel()
            if (Motions.reduced) { shifts[id] = goal; continue }
            shiftAnims[id] = Motions.run(Motion.reorder, { p -> shifts[id] = from + (goal - from) * p; invalidate() })
        }
    }

    private fun drop() {
        val from = lifted; val to = target
        val ids = thumbs.map { it.window.id }
        val order = Reorder.moved(ids, from, to)
        // Where the lifted one is now, relative to its new slot: it springs home from there.
        dropOffset = liftDx - (to - from) * slot
        lifted = -1; target = -1
        shiftAnims.values.forEach { it.cancel() }; shiftAnims.clear(); shifts.clear()
        if (order != ids) {
            thumbs = order.map { id -> thumbs.first { it.window.id == id } }
            onReorder(order)
        }
        val droppedId = order.getOrNull(to)
        dropAnim?.cancel()
        if (Motions.reduced || droppedId == null) { dropOffset = 0f; invalidate(); return }
        val start = dropOffset
        dropAnim = Motions.run(Motion.drop, { p -> dropOffset = start * (1 - p); invalidate() }, { dropOffset = 0f; dropped = null })
        dropped = droppedId
    }
    private var dropped: Long? = null

    private fun wiggle(on: Boolean) {
        wiggleAnim?.cancel(); wiggleAnim = null; wiggleAngle = 0f
        if (!on || Motions.reduced) return
        wiggleAnim = ValueAnimator.ofFloat(-1f, 1f).apply {
            duration = (Motion.wiggle.seconds * 1000).toLong()
            interpolator = Motions.interpolator(Motion.wiggle)
            repeatMode = ValueAnimator.REVERSE
            repeatCount = ValueAnimator.INFINITE
            addUpdateListener { wiggleAngle = (it.animatedValue as Float) * Ui.wiggleDegrees.toFloat(); invalidate() }
            start()
        }
    }

    override fun onDetachedFromWindow() {
        wiggleAnim?.cancel(); dropAnim?.cancel(); shiftAnims.values.forEach { it.cancel() }
        removeCallbacks(holdRunnable)
        super.onDetachedFromWindow()
    }

    override fun onDraw(c: Canvas) {
        val layer = c.saveLayer(0f, 0f, width.toFloat(), height.toFloat(), null)
        var liftedDraw: Pair<Int, RectF>? = null
        for ((i, t) in thumbs.withIndex()) {
            val r = frameOf(i)
            r.offset(shifts[t.window.id] ?: 0f, 0f)
            if (i == lifted) { r.offset(liftDx, 0f); liftedDraw = i to r; continue }
            if (t.window.id == dropped) r.offset(dropOffset, 0f)
            drawThumb(c, t, r, lifted = false)
        }
        liftedDraw?.let { (i, r) -> drawThumb(c, thumbs[i], r, lifted = true) }
        // The fade at the trailing end (the strip's mask).
        if (maskFor != width to fade) { maskFor = width to fade; mask.shader = LinearGradient(0f, 0f, width.toFloat(), 0f, intArrayOf(-0x1000000, -0x1000000, 0),
            floatArrayOf(0f, fade.toFloat(), 1f), Shader.TileMode.CLAMP) }
        c.drawRect(0f, 0f, width.toFloat(), height.toFloat(), mask)
        c.restoreToCount(layer)
    }

    private fun drawThumb(c: Canvas, t: Thumb, r: RectF, lifted: Boolean) {
        val rad = dp(radius)
        val menu = t.window.id == menuFor
        c.save()
        val s = if (lifted) Ui.liftedScale.toFloat() else if (menu) 1.04f else 1f
        c.scale(s, s, r.centerX(), r.centerY())
        if (menu) { c.rotate(wiggleAngle, r.centerX(), r.centerY()); c.translate(0f, -dp(1.0)) }
        if (lifted) c.drawRoundRect(r, rad, rad, shadow)
        c.save()
        clip.reset(); clip.addRoundRect(r, rad, rad, android.graphics.Path.Direction.CW)
        c.clipPath(clip)
        val img = t.image
        if (img != null) {
            // Aspect fill.
            val sc = max(r.width() / img.width, r.height() / img.height)
            val w = img.width * sc; val h = img.height * sc
            frame.set(r.centerX() - w / 2, r.centerY() - h / 2, r.centerX() + w / 2, r.centerY() + h / 2)
            c.drawBitmap(img, null, frame, bitmapPaint)
        } else {
            c.drawRect(r, body)
            c.drawRect(r.left, r.top, r.right, r.top + dp(Ui.thumbTitleBar), titleBar)
        }
        c.restore()
        Look.strokeBorder(c, r, rad, hairline)
        if (t.active) {
            val o = dp(Ui.haloOutset)
            Look.strokeBorder(c, RectF(r.left - o, r.top - o, r.right + o, r.bottom + o), rad + o, halo)
        }
        // The app badge past the bottom-leading corner, in a ring of the bar's colour.
        val b = dp(badge)
        val corner = DuoPostureRound.rounded(badge * 0.29).toFloat()
        val bx = r.left - dp(Ui.badgeOffset); val by = r.bottom + dp(Ui.badgeOffset) - b
        c.drawRoundRect(bx - dp(2.0), by - dp(2.0), bx + b + dp(2.0), by + b + dp(2.0), dp(corner + 2.0), dp(corner + 2.0), ring)
        val icon = t.icon
        val br = badgeRect.apply { set(bx, by, bx + b, by + b) }
        if (icon != null) {
            clip.reset(); clip.addRoundRect(br, dp(corner.toDouble()), dp(corner.toDouble()), android.graphics.Path.Direction.CW)
            c.save(); c.clipPath(clip)
            c.drawBitmap(icon, null, br, bitmapPaint); c.restore()
        } else {
            c.drawRoundRect(br, dp(corner.toDouble()), dp(corner.toDouble()), iconBg)
            initials.textSize = dp(DuoPostureRound.rounded(badge * 0.42))
            Look.textCentred(c, Look.initials(t.window.appName), br.centerX(), br.centerY(), initials)
        }
        c.restore()
    }

    // Accessibility: each thumbnail a node of its own, with the lights and the moves as actions
    // (WindowThumbnail's VoiceOver actions).
    private val provider = ThumbNodes()
    override fun getAccessibilityNodeProvider(): AccessibilityNodeProvider = provider

    private inner class ThumbNodes : AccessibilityNodeProvider() {
        private val actClose = AccessibilityNodeInfo.AccessibilityAction(1 shl 24 or 1, "Close window")
        private val actMin = AccessibilityNodeInfo.AccessibilityAction(1 shl 24 or 2, "Minimize window")
        private val actFull = AccessibilityNodeInfo.AccessibilityAction(1 shl 24 or 3, "Full screen")
        private val actLeft = AccessibilityNodeInfo.AccessibilityAction(1 shl 24 or 4, "Move left")
        private val actRight = AccessibilityNodeInfo.AccessibilityAction(1 shl 24 or 5, "Move right")

        fun invalidateAll() { if (isAttachedToWindow) sendAccessibilityEvent(android.view.accessibility.AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) }

        override fun createAccessibilityNodeInfo(virtualViewId: Int): AccessibilityNodeInfo? {
            if (virtualViewId == View.NO_ID) {
                val info = AccessibilityNodeInfo.obtain(this@StripView)
                onInitializeAccessibilityNodeInfo(info)
                thumbs.indices.forEach { info.addChild(this@StripView, it) }
                return info
            }
            val t = thumbs.getOrNull(virtualViewId) ?: return null
            val info = AccessibilityNodeInfo.obtain(this@StripView, virtualViewId)
            info.setParent(this@StripView)
            info.packageName = context.packageName
            info.className = "android.widget.Button"
            info.contentDescription = Copy.thumbnail(t.window.appName, t.window.title, t.active)
            val r = frameOf(virtualViewId)
            val local = PxRect(r.left.toInt(), r.top.toInt(), r.right.toInt(), r.bottom.toInt())
            @Suppress("DEPRECATION") info.setBoundsInParent(local)
            val loc = IntArray(2); getLocationOnScreen(loc)
            local.offset(loc[0], loc[1])
            info.setBoundsInScreen(local)
            info.isVisibleToUser = r.right > 0 && r.left < width
            info.isEnabled = true
            info.isClickable = true
            info.addAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_CLICK)
            listOf(actClose, actMin, actFull, actLeft, actRight).forEach(info::addAction)
            return info
        }

        override fun performAction(virtualViewId: Int, action: Int, arguments: Bundle?): Boolean {
            val t = thumbs.getOrNull(virtualViewId) ?: return if (virtualViewId == View.NO_ID) performAccessibilityAction(action, arguments) else false
            val id = t.window.id
            when (action) {
                AccessibilityNodeInfo.ACTION_CLICK -> onSelect(id)
                actClose.id -> onCommand(id, WindowCommand.CLOSE)
                actMin.id -> onCommand(id, WindowCommand.MINIMIZE)
                actFull.id -> onCommand(id, WindowCommand.FULL_SCREEN)
                actLeft.id, actRight.id -> {
                    val ids = thumbs.map { it.window.id }
                    val to = (virtualViewId + if (action == actLeft.id) -1 else 1).coerceIn(0, ids.size - 1)
                    val order = Reorder.moved(ids, virtualViewId, to)
                    if (order != ids) { thumbs = order.map { o -> thumbs.first { it.window.id == o } }; onReorder(order) }
                }
                else -> return false
            }
            return true
        }
    }
}

/** Swift's `rounded()`, for the few sizes the iOS app rounds. */
object DuoPostureRound {
    fun rounded(v: Double) = if (v >= 0) kotlin.math.floor(v + 0.5) else kotlin.math.ceil(v - 0.5)
}

/**
 * A held thumbnail's lights (WindowLightsMenu): close, minimize and full screen in macOS's colours,
 * on a 214×62 card beside the thumbnail, off any fold (DuoPosture.lightsMenu). Laid over the whole
 * screen while open: a tap anywhere else closes it.
 */
@SuppressLint("ViewConstructor")
class LightsView(context: Context, private val dp: Dp) : View(context) {
    /** The thumbnail's frame in this view (dp), the window, whether the lights go below, the fold. */
    var anchor: Rect? = null
    var window: WindowInfo? = null
    var below = true
    var fold: FoldInfo = FoldInfo.Inferred
    var onCommand: (String) -> Unit = {}
    var onDismiss: () -> Unit = {}
    private var progress = 0f
    private var anim: ValueAnimator? = null
    private var card = RectF()
    private var down = true

    private val bg = Look.fill(Palette.control).apply { setShadowLayer(dp(16.0), 0f, dp(6.0), Rgba.black.opacity(0.5).argb) }
    private val line = Look.stroke(Rgba.white.opacity(0.1), dp(1.0))
    private val light = Look.fill(LightColors.close)
    private val label = Look.textPaint(dp, Type.lightLabel, Palette.barLabel, capped = false)
    private val lights = listOf(
        Triple(WindowCommand.CLOSE, LightColors.close, Symbol.Xmark to Copy.close),
        Triple(WindowCommand.MINIMIZE, LightColors.minimize, Symbol.Minus to Copy.minimize),
        Triple(WindowCommand.FULL_SCREEN, LightColors.fullScreen, Symbol.FullScreen to Copy.fullScreen))

    init { setLayerType(LAYER_TYPE_SOFTWARE, null); visibility = GONE }

    fun show(open: Boolean) {
        if (open) { visibility = VISIBLE; contentDescription = window?.let { Copy.windowActions(it.appName) } }
        anim?.cancel()
        val from = progress; val to = if (open) 1f else 0f
        if (Motions.reduced) { progress = to; if (!open) visibility = GONE; invalidate(); return }
        anim = Motions.run(if (open) Motion.windowMenu else Motion.windowMenu, { p -> progress = from + (to - from) * p; invalidate() },
            { if (!open) visibility = GONE })
    }

    private fun place() {
        val a = anchor ?: return
        val w = Ui.lightsWidth; val h = Ui.lightsHeight
        val screenW = dp.px.dp(width)
        val x = min(max(a.midX, w / 2 + 8), screenW - w / 2 - 8)
        val at = DuoPosture.lightsMenu(x, below, a, Size(w, h), 8.0, screenW, fold)
        down = at.below
        card = RectF(dp(at.x - w / 2), dp(at.y - h / 2), dp(at.x + w / 2), dp(at.y + h / 2))
    }

    override fun onDraw(c: Canvas) {
        place()
        val p = progress.coerceAtLeast(0f)
        c.save()
        val s = if (Motions.reduced) 1f else 0.8f + 0.2f * p
        c.scale(s, s, card.centerX(), if (down) card.top else card.bottom)
        val alpha = (p.coerceAtMost(1f) * 255).toInt()
        c.saveLayerAlpha(card.left - dp(40.0), card.top - dp(40.0), card.right + dp(40.0), card.bottom + dp(40.0), alpha)
        val r = dp(Ui.lightsRadius)
        c.drawRoundRect(card, r, r, bg)
        Look.strokeBorder(c, card, r, line)
        val colW = (card.width() - dp(20.0) - dp(12.0)) / 3
        val fm = label.fontMetrics
        val block = dp(Ui.lightDiameter) + dp(5.0) + (fm.descent - fm.ascent)
        val top = card.top + (card.height() - block) / 2
        lights.forEachIndexed { i, (_, color, sl) ->
            val cx = card.left + dp(10.0) + i * (colW + dp(6.0)) + colW / 2
            val cy = top + dp(Ui.lightDiameter / 2)
            light.color = color.argb
            c.drawCircle(cx, cy, dp(Ui.lightDiameter / 2), light)
            Look.symbol(c, dp, sl.first, cx, cy, 10.0, Rgba.black.opacity(0.65), color)
            val t = Look.fit(sl.second, label, colW)
            c.drawText(t, cx - label.measureText(t) / 2, top + dp(Ui.lightDiameter) + dp(5.0) - fm.ascent, label)
        }
        c.restore()
        c.restore()
    }

    @SuppressLint("ClickableViewAccessibility")
    override fun onTouchEvent(e: MotionEvent): Boolean {
        if (e.actionMasked != MotionEvent.ACTION_UP) return true
        if (card.contains(e.x, e.y)) {
            val colW = (card.width() - dp(20.0) - dp(12.0)) / 3
            val i = ((e.x - card.left - dp(10.0)) / (colW + dp(6.0))).toInt().coerceIn(0, 2)
            onCommand(lights[i].first)
        } else onDismiss()
        return true
    }
}
