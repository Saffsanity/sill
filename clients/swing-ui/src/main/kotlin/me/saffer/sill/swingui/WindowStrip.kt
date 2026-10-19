package me.saffer.sill.swingui

import me.saffer.sill.core.ui.Curve
import me.saffer.sill.core.ui.LightColors
import me.saffer.sill.core.ui.Motion
import me.saffer.sill.core.ui.Palette
import me.saffer.sill.core.ui.Rect
import me.saffer.sill.core.ui.Rgba
import me.saffer.sill.core.ui.Symbol
import me.saffer.sill.core.ui.TextStyle
import me.saffer.sill.core.ui.Type
import me.saffer.sill.core.ui.Ui
import java.awt.AlphaComposite
import java.awt.Color
import java.awt.GradientPaint
import java.awt.Graphics
import java.awt.Graphics2D
import java.awt.Image
import java.awt.RenderingHints
import java.awt.event.KeyEvent
import java.awt.event.MouseAdapter
import java.awt.event.MouseEvent
import java.awt.geom.AffineTransform
import java.awt.geom.Ellipse2D
import java.awt.image.BufferedImage
import javax.accessibility.AccessibleRole
import javax.swing.AbstractAction
import javax.swing.JComponent
import javax.swing.KeyStroke
import javax.swing.Timer
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** One thumbnail: a window, its picture (null: the placeholder), its app's icon, and whether it streams. */
data class StripItem(val id: Long, val title: String, val app: String, val image: BufferedImage?, val icon: BufferedImage?, val active: Boolean)

/** The thumbnails' numbers, from the layout (BarMetrics or PortraitMetrics). */
data class StripMetrics(val width: Double, val height: Double, val radius: Double, val spacing: Double, val pad: Double, val fade: Double, val badge: Double)

/**
 * The live window thumbnails (WindowStrip and WindowThumbnail in StreamScreen.swift), drawn as the
 * iOS app draws them: the white 12 % hairline, the accent halo 2 pt wide standing 5 out on the
 * window that streams, the app's badge with its bar-coloured ring 6 out past the bottom-left
 * corner, the placeholder's title bar, and the strip fading out from `fade` of its width.
 *
 * A click selects; the wheel (or a drag) scrolls; a hold of 1.5 s (or a right-click) opens the
 * window's lights; holding on and moving lifts the thumbnail and drags it to a new slot, its
 * neighbours making room with Motion.reorder and the drop settling with Motion.drop. Arrow keys
 * move between thumbnails and Enter picks one, the menu key opens its lights.
 */
class WindowStrip : SillComponent() {
    var metrics = StripMetrics(104.0, 66.0, 10.0, 16.0, 10.0, 0.86, 24.0); set(v) { field = v; clampScroll(); repaint() }
    var onSelect: (Long) -> Unit = {}
    var onHold: (Long) -> Unit = {}
    var onCloseMenu: () -> Unit = {}
    /** A drag ended: the new order of every window, the device's own arrangement. */
    var onReorder: (List<Long>) -> Unit = {}
    val fade = Animated(1.0, this)

    private var items: List<StripItem> = emptyList()
    private var order: List<Long> = emptyList()
    private var menuFor: Long? = null
    private var scroll = 0.0
    private var focusIndex = -1

    // Where each thumbnail is drawn while the others make room: from its old slot to its new one.
    private val slotAnim = Animator()
    private var slotFrom = HashMap<Long, Double>()
    private var slotProgress = 1.0

    // A press: what it hit, where, and what it became.
    private enum class Mode { None, Pressing, Scrolling, Held, Lifted }
    private var mode = Mode.None
    private var pressId: Long? = null
    private var pressX = 0.0
    private var pressScroll = 0.0
    private var holdTimer: Timer? = null
    private var liftStart = 0
    private var liftOffset = 0.0
    private val lift = Animated(0.0, this)          // 1 lifted, 0 resting (the drop springs it back)

    // The held thumbnail's wiggle while its lights are open.
    private var wiggle: Timer? = null
    private var wiggleStart = 0L

    private val scaled = HashMap<Long, Pair<Image, Image?>>()     // the picture at device pixels, keyed by the item's image
    /** The layer the strip is drawn into before its fade, kept while its size stays (a wiggle repaints 60 times a second). */
    private var layerCache: BufferedImage? = null

    init {
        isOpaque = false
        isFocusable = true
        isRequestFocusEnabled = false
        val m = object : MouseAdapter() {
            override fun mousePressed(e: MouseEvent) = pressed(e)
            override fun mouseDragged(e: MouseEvent) = dragged(e)
            override fun mouseReleased(e: MouseEvent) = released(e)
            override fun mouseMoved(e: MouseEvent) { toolTipText = hit(e.x.toDouble(), e.y.toDouble())?.let { tooltip(it) } }
        }
        addMouseListener(m); addMouseMotionListener(m)
        addMouseWheelListener { e ->
            if (mode == Mode.Lifted) return@addMouseWheelListener
            scroll += e.preciseWheelRotation * 40
            clampScroll(); repaint()
        }
        fun key(k: Int, name: String, f: () -> Unit) {
            inputMap.put(KeyStroke.getKeyStroke(k, 0), name)
            actionMap.put(name, object : AbstractAction() { override fun actionPerformed(e: java.awt.event.ActionEvent) = f() })
        }
        key(KeyEvent.VK_LEFT, "sill.prev") { moveFocus(-1) }
        key(KeyEvent.VK_RIGHT, "sill.next") { moveFocus(1) }
        key(KeyEvent.VK_ENTER, "sill.pick") { order.getOrNull(focusIndex)?.let(onSelect) }
        key(KeyEvent.VK_SPACE, "sill.pick2") { order.getOrNull(focusIndex)?.let(onSelect) }
        key(KeyEvent.VK_CONTEXT_MENU, "sill.menu") { order.getOrNull(focusIndex)?.let(onHold) }
        addFocusListener(object : java.awt.event.FocusAdapter() {
            override fun focusGained(e: java.awt.event.FocusEvent) { if (focusIndex < 0 && order.isNotEmpty()) focusIndex = 0; repaint() }
            override fun focusLost(e: java.awt.event.FocusEvent) = repaint()
        })
    }

    /** The windows, in the device's order. A thumbnail that went takes its lights and any drag with it. */
    fun setItems(list: List<StripItem>) {
        val ids = list.map { it.id }
        if (ids != order && mode != Mode.Lifted) animateSlots { order = ids }
        else if (mode == Mode.Lifted && ids.toSet() != order.toSet()) { cancelPress(); order = ids }
        items = list
        val keep = list.mapNotNull { it.image }.toSet()
        scaled.entries.removeIf { (_, v) -> v.second !in keep }
        if (focusIndex >= order.size) focusIndex = order.size - 1
        clampScroll(); repaint()
    }

    fun setMenu(id: Long?) {
        if (menuFor == id) return
        menuFor = id
        if (id != null && wiggle == null && !SillSwing.reduceMotion) {
            wiggleStart = System.nanoTime()
            wiggle = Timer(16) { repaint() }.apply { start() }
        } else if (id == null) { wiggle?.stop(); wiggle = null }
        repaint()
    }

    /** Where a thumbnail is, in this component's coordinates (the lights hang from it). */
    fun thumbBounds(id: Long): Rect? {
        val i = order.indexOf(id)
        if (i < 0) return null
        return Rect(slotX(id, i), metrics.pad, metrics.width, metrics.height)
    }

    fun itemAt(x: Double, y: Double): Long? = hit(x, y)

    /** Faded under the Aa ruler it takes no click (`allowsHitTesting(!scaleOpen)`). */
    override fun contains(x: Int, y: Int) = fade.target > 0.5 && super.contains(x, y)

    private val slot get() = metrics.width + metrics.spacing
    private fun restX(i: Int) = 8 + i * slot - scroll
    private fun slotX(id: Long, i: Int): Double {
        if (mode == Mode.Lifted && id == pressId) return restX(liftStart) + liftOffset
        val to = restX(i)
        val from = slotFrom[id] ?: return to
        return from + (to - from) * slotProgress
    }

    private fun contentWidth() = 16 + order.size * metrics.width + max(0, order.size - 1) * metrics.spacing
    private fun clampScroll() { scroll = scroll.coerceIn(0.0, max(0.0, contentWidth() - width)) }

    private fun animateSlots(change: () -> Unit) {
        val before = order.withIndex().associate { (i, id) -> id to slotX(id, i) }
        change()
        slotFrom = HashMap(before.mapValues { it.value })
        slotAnim.run(Motion.reorder) { p -> slotProgress = p; if (p >= 1.0) slotFrom.clear(); repaint() }
    }

    private fun hit(x: Double, y: Double): Long? {
        if (y < metrics.pad - Ui.haloOutset || y > metrics.pad + metrics.height + Ui.badgeOffset) return null
        order.forEachIndexed { i, id -> val sx = slotX(id, i); if (x >= sx && x < sx + metrics.width) return id }
        return null
    }

    private fun tooltip(id: Long) = items.firstOrNull { it.id == id }?.let { me.saffer.sill.core.ui.Copy.thumbnail(it.app, it.title, it.active) }

    private fun moveFocus(d: Int) {
        if (order.isEmpty()) return
        focusIndex = (focusIndex + d).coerceIn(0, order.size - 1)
        val x = restX(focusIndex) + scroll
        if (x - 8 < scroll) scroll = x - 8 else if (x + metrics.width + 8 > scroll + width) scroll = x + metrics.width + 8 - width
        clampScroll(); repaint()
    }

    // MARK: The press

    private fun pressed(e: MouseEvent) {
        if (fade.target < 0.5) return
        val id = hit(e.x.toDouble(), e.y.toDouble())
        if (e.button == MouseEvent.BUTTON3) { id?.let(onHold); return }
        if (e.button != MouseEvent.BUTTON1) return
        mode = Mode.Pressing; pressId = id; pressX = e.x.toDouble(); pressScroll = scroll
        holdTimer?.stop()
        if (id != null) holdTimer = Timer((Ui.holdToOpen * 1000).toInt()) {
            if (mode == Mode.Pressing && pressId == id) { mode = Mode.Held; onHold(id) }
        }.apply { isRepeats = false; start() }
    }

    private fun dragged(e: MouseEvent) {
        val dx = e.x - pressX
        when (mode) {
            Mode.Pressing -> if (abs(dx) > 8) { holdTimer?.stop(); mode = Mode.Scrolling }
            Mode.Held -> if (abs(dx) > 8 || abs(e.y - (metrics.pad + metrics.height / 2)) > metrics.height) {
                val id = pressId ?: return
                onCloseMenu()
                mode = Mode.Lifted
                liftStart = order.indexOf(id)
                lift.animate(1.0, Curve.EaseOut(0.15))
            }
            else -> {}
        }
        when (mode) {
            Mode.Scrolling -> { scroll = pressScroll - dx; clampScroll(); repaint() }
            Mode.Lifted -> {
                val id = pressId ?: return
                val shift = (dx / slot).roundToInt()
                val target = (liftStart + shift).coerceIn(0, order.size - 1)
                val current = order.indexOf(id)
                if (current != target) animateSlots { order = order.toMutableList().apply { remove(id); add(target, id) } }
                liftOffset = dx - (target - liftStart) * slot
                repaint()
            }
            else -> {}
        }
    }

    private fun released(e: MouseEvent) {
        if (e.button != MouseEvent.BUTTON1) return
        holdTimer?.stop()
        when (mode) {
            Mode.Pressing -> pressId?.let { id -> if (menuFor != null) onCloseMenu() else onSelect(id) }
            Mode.Lifted -> {
                val id = pressId ?: return
                // The drop: from under the pointer to its slot, with Motion.drop.
                val from = restX(liftStart) + liftOffset
                mode = Mode.None
                slotFrom = hashMapOf(id to from)
                slotProgress = 0.0
                slotAnim.run(Motion.drop) { p -> slotProgress = p; if (p >= 1.0) slotFrom.clear(); repaint() }
                lift.animate(0.0, Motion.drop)
                onReorder(order)
            }
            else -> {}
        }
        mode = Mode.None
    }

    private fun cancelPress() { holdTimer?.stop(); mode = Mode.None; lift.snap(0.0) }

    // MARK: Drawing

    override fun paintComponent(g0: Graphics) {
        val a = fade.value.coerceIn(0.0, 1.0)
        if (a <= 0.003 || width <= 0 || height <= 0) return
        val s = SillSwing.deviceScale(this)
        // Drawn into a layer at device pixels, then masked: the trailing fade, as the iOS LinearGradient mask.
        val lw = max(1, (width * s).toInt()); val lh = max(1, (height * s).toInt())
        val layer = layerCache?.takeIf { it.width == lw && it.height == lh } ?: BufferedImage(lw, lh, BufferedImage.TYPE_INT_ARGB).also { layerCache = it }
        val g = SillSwing.smooth(layer.graphics)
        g.composite = AlphaComposite.Clear; g.fillRect(0, 0, lw, lh); g.composite = AlphaComposite.SrcOver
        g.scale(s, s)
        var lifted: Pair<Long, Int>? = null
        order.forEachIndexed { i, id ->
            if (id == pressId && (mode == Mode.Lifted || lift.value > 0.001)) lifted = id to i else drawThumb(g, id, i, s)
        }
        lifted?.let { (id, i) -> drawThumb(g, id, i, s) }
        g.composite = AlphaComposite.DstIn
        val w = width.toDouble()
        g.paint = GradientPaint((w * metrics.fade).toFloat(), 0f, Color.BLACK, w.toFloat(), 0f, Color(0, 0, 0, 0))
        g.fill(java.awt.geom.Rectangle2D.Double(w * metrics.fade, 0.0, w * (1 - metrics.fade) + 1, height.toDouble()))
        g.dispose()
        val out = SillSwing.smooth(g0)
        if (a < 1) out.composite = AlphaComposite.getInstance(AlphaComposite.SRC_OVER, a.toFloat())
        out.drawImage(layer, 0, 0, width, height, null)
        out.dispose()
    }

    private fun drawThumb(g0: Graphics2D, id: Long, i: Int, scale: Double) {
        val item = items.firstOrNull { it.id == id } ?: return
        val m = metrics
        val x = slotX(id, i); val y = m.pad
        if (x > width + 20 || x + m.width < -20) return
        val g = g0.create() as Graphics2D
        val cx = x + m.width / 2; val cy = y + m.height / 2
        // Held: the wiggle (±1.8° on a 0.13 s ease in and out, a point up), a little bigger. Lifted: bigger still, with a shadow.
        val held = menuFor == id
        val liftP = if (id == pressId) lift.value else 0.0
        val sc = 1 + (if (held) 0.04 else 0.0) + (Ui.liftedScale - 1) * liftP
        val angle = if (held && wiggle != null) {
            val t = (System.nanoTime() - wiggleStart) / 1e9
            val phase = (t / Motion.wiggle.duration)
            val up = phase.toInt() % 2 == 0
            val f = Motion.wiggle.value((phase - phase.toInt()) * Motion.wiggle.duration)
            Ui.wiggleDegrees * (if (up) f else 1 - f)
        } else if (held) Ui.wiggleDegrees else 0.0
        g.transform(AffineTransform().apply { translate(cx, cy + if (held) -1.0 else 0.0); rotate(Math.toRadians(angle)); scale(sc, sc); translate(-cx, -cy) })
        val r = Rect(x, y, m.width, m.height)
        if (liftP > 0.001) SillSwing.shadow(g, r, m.radius, 0.45 * liftP, 20.0, 4.0)
        // The picture, filling the frame (aspect fill), clipped to its corners.
        val clip = g.clip
        g.clip(SillSwing.round(r, m.radius))
        val img = item.image
        if (img != null) {
            val pic = scaledPicture(id, img, (m.width * scale).roundToInt(), (m.height * scale).roundToInt())
            val t = g.transform
            g.translate(x, y); g.scale(1 / scale, 1 / scale)
            g.drawImage(pic, 0, 0, null)
            g.transform = t
        } else {
            SillSwing.fill(g, r, 0.0, Palette.thumbBody)
            SillSwing.fill(g, Rect(x, y, m.width, Ui.thumbTitleBar), 0.0, Palette.thumbTitleBar)
        }
        g.clip = clip
        SillSwing.strokeBorder(g, r, m.radius, Rgba.white.opacity(Ui.thumbStrokeAlpha))
        if (item.active) {
            val o = Ui.haloOutset
            SillSwing.strokeBorder(g, Rect(x - o, y - o, m.width + 2 * o, m.height + 2 * o), m.radius + o, Palette.accent, Ui.haloWidth)
        }
        // The keyboard's focus: a ring like the bar buttons'.
        if (isFocusOwner && order.getOrNull(focusIndex) == id) {
            val o = Ui.haloOutset - 2
            SillSwing.strokeBorder(g, Rect(x - o, y - o, m.width + 2 * o, m.height + 2 * o), m.radius + o, Palette.text.opacity(0.9), 1.5)
        }
        // The app's badge, its bar-coloured ring cutting through the edge and the halo.
        val b = m.badge
        val corner = Math.round(b * 0.29).toDouble()
        val bx = x - Ui.badgeOffset; val by = y + m.height + Ui.badgeOffset - b
        SillSwing.fill(g, Rect(bx - 2, by - 2, b + 4, b + 4), corner + 2, Palette.bar)
        AppIcons.draw(g, Rect(bx, by, b, b), corner, item.icon, item.app, Math.round(b * 0.42).toDouble(), scale)
        g.dispose()
    }

    private fun scaledPicture(id: Long, img: BufferedImage, w: Int, h: Int): Image {
        val have = scaled[id]
        if (have != null && have.second === img && have.first.getWidth(null) == w && have.first.getHeight(null) == h) return have.first
        val out = AppIcons.fill(img, w, h)
        scaled[id] = out to img
        return out
    }

    override fun getAccessibleContext(): javax.accessibility.AccessibleContext {
        if (accessibleContext == null) accessibleContext = object : AccessibleJComponent() {
            override fun getAccessibleRole() = AccessibleRole.PAGE_TAB_LIST
            override fun getAccessibleName() = items.joinToString("; ") { me.saffer.sill.core.ui.Copy.thumbnail(it.app, it.title, it.active) }.ifEmpty { "Windows" }
        }
        return accessibleContext
    }
}

/** App icons as the iOS app's AppIcon draws them: the picture, or its first two letters on iconFallback. */
object AppIcons {
    fun draw(g: Graphics2D, r: Rect, radius: Double, icon: BufferedImage?, name: String, fontSize: Double, scale: Double) {
        val clip = g.clip
        g.clip(SillSwing.round(r, radius))
        if (icon != null) {
            val px = fill(icon, (r.width * scale).roundToInt().coerceAtLeast(1), (r.height * scale).roundToInt().coerceAtLeast(1))
            val t = g.transform
            g.translate(r.x, r.y); g.scale(1 / scale, 1 / scale)
            g.drawImage(px, 0, 0, null)
            g.transform = t
        } else {
            SillSwing.fill(g, r, 0.0, Palette.iconFallback)
            val f = SillSwing.font(TextStyle(fontSize, TextStyle.Weight.Semibold), 1.0)
            g.font = f
            val fm = g.fontMetrics
            SillSwing.centred(g, name.take(2), r, r.midY - (fm.ascent + fm.descent) / 2.0, f, Rgba.white)
        }
        g.clip = clip
    }

    /** `img` scaled to fill w×h (aspect fill, centred), in steps of halves for a smooth result. */
    fun fill(img: BufferedImage, w: Int, h: Int): BufferedImage {
        val k = max(w.toDouble() / img.width, h.toDouble() / img.height)
        var src = img
        var cw = img.width; var ch = img.height
        while (cw * k < cw / 2.0 && cw > 2) {
            cw = max(1, cw / 2); ch = max(1, ch / 2)
            val half = BufferedImage(cw, ch, BufferedImage.TYPE_INT_ARGB)
            half.createGraphics().apply { setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BILINEAR); drawImage(src, 0, 0, cw, ch, null); dispose() }
            src = half
        }
        val out = BufferedImage(max(1, w), max(1, h), BufferedImage.TYPE_INT_ARGB)
        val dw = img.width * k; val dh = img.height * k
        out.createGraphics().apply {
            setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BICUBIC)
            setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY)
            drawImage(src, ((w - dw) / 2).roundToInt(), ((h - dh) / 2).roundToInt(), dw.roundToInt(), dh.roundToInt(), null)
            dispose()
        }
        return out
    }
}

/**
 * A held thumbnail's lights (WindowLightsMenu): close, minimize and full screen in macOS's colours
 * with their glyphs and words, on the control colour with a 10 % hairline and its shadow. The
 * component is the menu plus room for the shadow; only the menu takes clicks. It springs in with
 * Motion.windowMenu, from 0.8, from its edge nearest the thumbnail.
 */
class LightsMenu : SillComponent() {
    companion object {
        const val margin = 22.0
        val actions = listOf("close", "minimize", "fullScreen")
    }
    var onCommand: (String) -> Unit = {}
    var below = true
    var windowName = ""
        set(v) { field = v; getAccessibleContext().accessibleName = me.saffer.sill.core.ui.Copy.windowActions(v) }
    private val shown = Animated(0.0, this)
    private var hoverIndex = -1

    init {
        isOpaque = false
        isVisible = false
        val m = object : MouseAdapter() {
            override fun mouseMoved(e: MouseEvent) { val i = light(e.x.toDouble(), e.y.toDouble()); if (i != hoverIndex) { hoverIndex = i; repaint() } }
            override fun mouseExited(e: MouseEvent) { hoverIndex = -1; repaint() }
            override fun mouseClicked(e: MouseEvent) { light(e.x.toDouble(), e.y.toDouble()).takeIf { it >= 0 }?.let { onCommand(actions[it]) } }
        }
        addMouseListener(m); addMouseMotionListener(m)
    }

    val menu get() = Rect(margin, margin, Ui.lightsWidth, Ui.lightsHeight)

    /** Places the menu (not the shadow's room) with its centre at (x, y) in the parent's coordinates. */
    fun place(cx: Double, cy: Double) {
        setBounds((cx - Ui.lightsWidth / 2 - margin).toInt(), (cy - Ui.lightsHeight / 2 - margin).toInt(),
            (Ui.lightsWidth + 2 * margin).toInt(), (Ui.lightsHeight + 2 * margin).toInt())
    }

    fun open() { shown.snap(0.0); shown.animate(1.0, Motion.windowMenu) }

    override fun contains(x: Int, y: Int) = menu.contains(x.toDouble(), y.toDouble())

    private fun columns(): List<Rect> {
        val m = menu
        val w = 60.0; val gap = 6.0
        val start = m.midX - (3 * w + 2 * gap) / 2
        return (0..2).map { Rect(start + it * (w + gap), m.y, w, m.height) }
    }

    private fun light(x: Double, y: Double) = columns().indexOfFirst { it.contains(x, y) }

    override fun paintComponent(g0: Graphics) {
        val p = shown.value
        val g = SillSwing.smooth(g0)
        g.composite = AlphaComposite.getInstance(AlphaComposite.SRC_OVER, p.coerceIn(0.0, 1.0).toFloat())
        val m = menu
        val s = 0.8 + 0.2 * p
        val ay = if (below) m.y else m.maxY
        g.translate(m.midX, ay); g.scale(s, s); g.translate(-m.midX, -ay)
        SillSwing.shadow(g, m, Ui.lightsRadius, 0.5, 16.0, 6.0)
        SillSwing.fill(g, m, Ui.lightsRadius, Palette.control)
        SillSwing.strokeBorder(g, m, Ui.lightsRadius, Rgba.white.opacity(0.1))
        val colours = listOf(LightColors.close, LightColors.minimize, LightColors.fullScreen)
        val glyphs = listOf(Symbol.Xmark, Symbol.Minus, Symbol.FullScreen)
        val words = listOf(me.saffer.sill.core.ui.Copy.close, me.saffer.sill.core.ui.Copy.minimize, me.saffer.sill.core.ui.Copy.fullScreen)
        val label = SillSwing.font(Type.lightLabel)
        val labelH = g.getFontMetrics(label).let { it.ascent + it.descent }.toDouble()
        columns().forEachIndexed { i, c ->
            if (i == hoverIndex) SillSwing.fill(g, c.inset(0.0, 6.0), 10.0, Rgba.white.opacity(0.05))
            val d = Ui.lightDiameter
            val top = c.y + (c.height - d - 5 - labelH) / 2
            g.color = SillSwing.color(colours[i])
            g.fill(Ellipse2D.Double(c.midX - d / 2, top, d, d))
            val box = Symbol.boxFor(10.0)
            SillSwing.glyph(g, glyphs[i], c.midX - box / 2, top + d / 2 - box / 2, box, Rgba.black.opacity(0.65), colours[i])
            SillSwing.centred(g, words[i], c, top + d + 5, label, Palette.barLabel)
        }
        g.dispose()
    }
}
