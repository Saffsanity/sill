package me.saffer.sill.swingui

import me.saffer.sill.core.ui.Motion
import me.saffer.sill.core.ui.Palette
import me.saffer.sill.core.ui.Rect
import me.saffer.sill.core.ui.Rgba
import me.saffer.sill.core.ui.TextScale
import me.saffer.sill.core.ui.TextStyle
import me.saffer.sill.core.ui.Type
import me.saffer.sill.core.ui.Ui
import java.awt.AlphaComposite
import java.awt.Color
import java.awt.GradientPaint
import java.awt.Graphics
import java.awt.Graphics2D
import java.awt.event.KeyEvent
import java.awt.event.MouseEvent
import java.awt.geom.Ellipse2D
import java.awt.geom.RoundRectangle2D
import java.awt.image.BufferedImage
import javax.accessibility.AccessibleRole
import javax.swing.AbstractAction
import javax.swing.JComponent
import javax.swing.KeyStroke

/**
 * The Aa control's face (TextScaleControl in StreamScreen.swift): "Aa" over the scale ("1×"), on
 * the control colour. A press unfolds the ruler ([TextScaleRuler]) under the pointer, a drag follows
 * it, the release applies; the wheel and the arrow keys step it a detent (VoiceOver's adjustable
 * action on iOS). The owner wires those to its state ([onDown], [onDrag], [onUp], [onStep]).
 */
class TextScaleButton : SillControl() {
    var scale: Double? = null; set(v) { field = v; repaint() }
    var radius = Ui.barButtonRadius; set(v) { field = v; repaint() }
    /** Hidden while the ruler shows in its place (`.opacity(open ? 0 : 1)`). */
    var hiddenForRuler = false; set(v) { field = v; repaint() }
    var onDown: () -> Unit = {}
    var onDrag: (Double) -> Unit = {}
    var onUp: () -> Unit = {}
    var onStep: (Boolean) -> Unit = {}
    override val cornerRadius get() = radius
    override val clicks = false
    private var downX = 0.0
    private var down = false

    init {
        addMouseWheelListener { e -> if (live && e.preciseWheelRotation != 0.0) onStep(e.preciseWheelRotation < 0) }
        for ((k, up) in listOf(KeyEvent.VK_UP to true, KeyEvent.VK_RIGHT to true, KeyEvent.VK_DOWN to false, KeyEvent.VK_LEFT to false)) {
            inputMap.put(KeyStroke.getKeyStroke(k, 0), "sill.step.$up")
            actionMap.put("sill.step.$up", object : AbstractAction() { override fun actionPerformed(e: java.awt.event.ActionEvent) { if (live) onStep(up) } })
        }
        // Space and Enter step up, wrapping round, so the keyboard alone can reach every detent.
        actionMap.put("sill.activate", object : AbstractAction() { override fun actionPerformed(e: java.awt.event.ActionEvent) { if (live) onStep(true) } })
    }

    override fun pressedAt(e: MouseEvent) { down = true; downX = e.xOnScreen.toDouble(); onDown() }
    override fun draggedAt(e: MouseEvent) { if (down) onDrag(e.xOnScreen - downX) }
    override fun releasedAt(e: MouseEvent) { if (down) { down = false; onUp() } }

    override fun paintControl(g: Graphics2D, r: Rect) {
        if (hiddenForRuler) return
        SillSwing.fill(g, r, radius, Palette.control)
        if (hover) SillSwing.fill(g, r, radius, Rgba.white.opacity(0.04))
        val aa = SillSwing.font(if (r.height >= 60) Type.aaTall else Type.aaShort)
        val lab = SillSwing.font(Type.barLabel)
        val aaH = getFontMetrics(aa).let { it.ascent + it.descent }.toDouble()
        val labH = getFontMetrics(lab).let { it.ascent + it.descent }.toDouble()
        val top = r.y + (r.height - aaH - 2 - labH) / 2
        SillSwing.centred(g, "Aa", r, top, aa, Palette.text)
        SillSwing.centred(g, TextScale.label(scale ?: 1.0) + "×", r, top + aaH + 2, lab, Palette.barLabel)
    }

    override fun getAccessibleContext(): javax.accessibility.AccessibleContext {
        if (accessibleContext == null) accessibleContext = object : AccessibleJComponent() {
            override fun getAccessibleRole() = AccessibleRole.SLIDER
            override fun getAccessibleDescription() = "${TextScale.label(scale ?: 1.0)} times"
        }
        return accessibleContext
    }
}

/**
 * The unfolded Aa ruler (TextScaleControl.slider): a track with five ticks and their labels that
 * slides under the fixed accent thumb so the live value sits under it, the ends fading, the live
 * value over the thumb. It unfolds with Motion.rulerOpen (scale 0.6 to 1, fading in) and folds with
 * Motion.rulerClose; a new detent slides in with Motion.rulerDetent. It takes no clicks: the Aa
 * control under the pointer drives it.
 */
class TextScaleRuler : SillComponent() {
    var pointsPerStep = Ui.rulerStepRegular; set(v) { field = v; repaint() }
    var radius = Ui.barButtonRadius; set(v) { field = v; repaint() }
    private val shown = Animated(0.0, this)
    private val live = Animated(1.0, this)
    /** The value under the thumb, as a detent (what a release applies). */
    var value = 1.0
        private set

    init { isOpaque = false; isVisible = false }

    override fun contains(x: Int, y: Int) = false

    fun open(start: Double) {
        value = start; live.snap(start)
        isVisible = true
        shown.animate(1.0, Motion.rulerOpen)
    }

    fun moveTo(v: Double) {
        if (v == value) return
        value = v
        live.animate(v, Motion.rulerDetent)
    }

    fun close() {
        if (shown.target == 0.0) return
        shown.animate(0.0, Motion.rulerClose)
        // Hidden once folded, so it costs nothing while away.
        javax.swing.Timer((Motion.rulerClose.seconds * 1000).toInt() + 30) { if (shown.target == 0.0) isVisible = false }.apply { isRepeats = false; start() }
    }

    val isOpen get() = shown.target == 1.0

    override fun paintComponent(g0: Graphics) {
        val p = shown.value
        if (p <= 0.003) return
        val g = SillSwing.smooth(g0)
        val w = width.toDouble(); val h = height.toDouble()
        g.composite = AlphaComposite.getInstance(AlphaComposite.SRC_OVER, p.coerceIn(0.0, 1.0).toFloat())
        val s = 0.6 + 0.4 * p
        g.translate(w / 2, h / 2); g.scale(s, s); g.translate(-w / 2, -h / 2)
        g.clip(RoundRectangle2D.Double(0.0, 0.0, w, h, radius * 2, radius * 2))
        SillSwing.fill(g, Rect(0.0, 0.0, w, h), radius, Palette.controlOpen)

        // The track, ticks and labels, faded at both ends (the iOS mask's 12 % each side).
        val step = pointsPerStep
        val midX = w / 2
        val midY = h / 2 + 4
        val cur = live.value
        fun x(v: Double) = midX + (v - cur) / 0.25 * step
        val scale = SillSwing.deviceScale(this)
        val iw = maxOf(1, (w * scale).toInt()); val ih = maxOf(1, (h * scale).toInt())
        val layer = BufferedImage(iw, ih, BufferedImage.TYPE_INT_ARGB)
        val lg = SillSwing.smooth(layer.graphics)
        lg.scale(scale, scale)
        SillSwing.fill(lg, Rect(x(TextScale.steps.first()), midY - 1.5, step * (TextScale.steps.size - 1), 3.0), 1.5, Palette.barLabel.opacity(0.35))
        val tick = SillSwing.font(Type.rulerTick)
        lg.font = tick
        for (v in TextScale.steps) {
            lg.color = SillSwing.color(Palette.barLabel.opacity(0.6))
            lg.fill(java.awt.geom.Rectangle2D.Double(x(v) - 1, midY - 4.5, 2.0, 9.0))
            SillSwing.centred(lg, TextScale.label(v), Rect(x(v) - step / 2, 0.0, step, 0.0), midY + 9, tick, if (v == value) Palette.text else Palette.barLabel)
        }
        lg.composite = AlphaComposite.DstIn
        lg.paint = GradientPaint(0f, 0f, Color(0, 0, 0, 0), (w * 0.12).toFloat(), 0f, Color.BLACK)
        lg.fill(java.awt.geom.Rectangle2D.Double(0.0, 0.0, w * 0.12, h))
        lg.paint = GradientPaint((w * 0.88).toFloat(), 0f, Color.BLACK, w.toFloat(), 0f, Color(0, 0, 0, 0))
        lg.fill(java.awt.geom.Rectangle2D.Double(w * 0.88, 0.0, w * 0.12 + 1, h))
        lg.dispose()
        g.drawImage(layer, 0, 0, w.toInt(), h.toInt(), null)

        // The thumb, with its little shadow, and the live value over it.
        g.color = Color(0, 0, 0, (0.35 * 255 / 3).toInt())
        for (i in 1..3) g.fill(Ellipse2D.Double(midX - 11 - i / 2.0, midY - 11 + 1 - i / 2.0 + 0.5, 22.0 + i, 22.0 + i))
        g.color = SillSwing.color(Palette.accent)
        g.fill(Ellipse2D.Double(midX - Ui.rulerThumb / 2, midY - Ui.rulerThumb / 2, Ui.rulerThumb, Ui.rulerThumb))
        val vf = SillSwing.font(Type.rulerValue)
        SillSwing.centred(g, TextScale.label(value) + "×", Rect(midX - 30, 0.0, 60.0, 0.0), maxOf(midY - 34, -1.0), vf, Palette.text)
        g.dispose()
    }
}

/** A text style's line height in a component's metrics. */
internal fun JComponent.lineHeight(style: TextStyle) = getFontMetrics(SillSwing.font(style)).let { it.ascent + it.descent }.toDouble()
