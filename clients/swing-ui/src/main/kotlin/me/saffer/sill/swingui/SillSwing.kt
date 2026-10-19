package me.saffer.sill.swingui

import me.saffer.sill.core.ui.Curve
import me.saffer.sill.core.ui.Glyph
import me.saffer.sill.core.ui.Palette
import me.saffer.sill.core.ui.Rect
import me.saffer.sill.core.ui.Rgba
import me.saffer.sill.core.ui.Symbol
import me.saffer.sill.core.ui.TextStyle
import java.awt.AlphaComposite
import java.awt.BasicStroke
import java.awt.Color
import java.awt.Component
import java.awt.Font
import java.awt.FontMetrics
import java.awt.Graphics
import java.awt.Graphics2D
import java.awt.GraphicsEnvironment
import java.awt.RenderingHints
import java.awt.Toolkit
import java.awt.geom.Ellipse2D
import java.awt.geom.Line2D
import java.awt.geom.Path2D
import java.awt.geom.RoundRectangle2D
import javax.swing.JComponent
import javax.swing.JScrollBar
import javax.swing.SwingUtilities
import javax.swing.Timer
import javax.swing.UIManager
import javax.swing.plaf.basic.BasicScrollBarUI

/**
 * The iOS app's look in Swing: its tokens as AWT colours and fonts, set as the look and feel's
 * defaults so every stock component (a text field, a list, a scroll pane) comes up in the same dark
 * scheme the custom ones draw.
 *
 * Units: one iOS point is one logical pixel. Java2D scales logical pixels to the display (per monitor
 * on Windows since JDK 9: 125 %, 150 %, 200 %…; GDK_SCALE or `-Dsun.java2d.uiScale` on Linux), so
 * every size in Tokens.kt is used as it is, and what the iOS app draws at 2x and 3x comes out sharp
 * at the display's own scale (the video and the thumbnails are drawn at device pixels: [deviceScale]).
 */
object SillSwing {
    fun color(c: Rgba): Color = Color(c.red, c.green, c.blue, (c.alpha.coerceIn(0.0, 1.0) * 255 + 0.5).toInt())

    /**
     * The system's UI font, as SF Pro is the iOS app's: Segoe UI Variable (Windows 11), Segoe UI
     * (Windows 10), then the usual Linux UI fonts, then the JDK's Dialog. Weights the font family has
     * as faces of their own ("Segoe UI Semibold") are used as such; otherwise Java's bold stands in
     * for semibold and heavier.
     */
    val family: String by lazy {
        val have = GraphicsEnvironment.getLocalGraphicsEnvironment().availableFontFamilyNames.toSet()
        listOf("SF Pro Text", "Segoe UI Variable Text", "Segoe UI", "Inter", "Cantarell", "Ubuntu", "Noto Sans", "DejaVu Sans")
            .firstOrNull { it in have } ?: Font.DIALOG
    }
    private val families: Set<String> by lazy { GraphicsEnvironment.getLocalGraphicsEnvironment().availableFontFamilyNames.toSet() }

    private val fonts = HashMap<Pair<TextStyle, Double>, Font>()

    /** `style` at the text scale the platform asks for (Windows' Make Text Bigger), capped at
     *  iOS's xxLarge as the panel and the footer are ([me.saffer.sill.core.ui.Type.scaled]). */
    fun font(style: TextStyle, scale: Double = textScale): Font = fonts.getOrPut(style to scale) {
        val size = (style.size * scale.coerceIn(1.0, me.saffer.sill.core.ui.Type.maxScale)).toFloat()
        val face = when (style.weight) {
            TextStyle.Weight.Semibold -> "$family Semibold"
            TextStyle.Weight.Medium -> "$family Medium"
            TextStyle.Weight.Light -> "$family Light"
            else -> null
        }
        if (face != null && face in families) Font(face, Font.PLAIN, 1).deriveFont(size)
        else Font(family, if (style.weight.css >= 600) Font.BOLD else Font.PLAIN, 1).deriveFont(size)
    }

    /** Windows' "Make text bigger" (Settings › Accessibility › Text size), which Java does not
     *  apply by itself; 1 elsewhere. `-Dsill.textScale` overrides it (tests, a user's choice). */
    val textScale: Double by lazy {
        System.getProperty("sill.textScale")?.toDoubleOrNull()
            ?: (Toolkit.getDefaultToolkit().getDesktopProperty("win.defaultGUI.font") as? Font)?.let { (it.size2D / 9.0).coerceIn(1.0, 2.25) }
            ?: 1.0
    }

    /** Reduce Motion: the platform's "Show animations" off (Windows), or `-Dsill.reduceMotion=true`;
     *  the panel then fades without its scale, as the iOS app does. */
    val reduceMotion: Boolean by lazy {
        System.getProperty("sill.reduceMotion")?.toBoolean()
            ?: (Toolkit.getDefaultToolkit().getDesktopProperty("win.animation.minimizeEnabled") == false)
    }

    /** The scale from logical to device pixels where `c` is shown (1.25, 1.5, 2…). */
    fun deviceScale(c: Component): Double = c.graphicsConfiguration?.defaultTransform?.scaleX ?: 1.0

    /** The look and feel's defaults in the iOS app's scheme, before any window is made. */
    fun install() {
        try { UIManager.setLookAndFeel(UIManager.getCrossPlatformLookAndFeelClassName()) } catch (_: Exception) {}
        val bar = color(Palette.bar); val control = color(Palette.control); val text = color(Palette.text)
        val muted = color(Palette.muted); val accent = color(Palette.accent)
        val body = font(TextStyle(15.0))
        for ((k, v) in listOf(
            "Panel.background" to bar, "Panel.foreground" to text, "Label.foreground" to text, "Label.background" to bar,
            "Viewport.background" to bar, "ScrollPane.background" to bar, "ScrollPane.border" to null,
            "List.background" to bar, "List.foreground" to text, "List.selectionBackground" to control, "List.selectionForeground" to text,
            "TextField.background" to control, "TextField.foreground" to text, "TextField.caretForeground" to accent,
            "TextField.selectionBackground" to color(Palette.controlOpen), "TextField.selectionForeground" to text,
            "TextField.inactiveForeground" to muted, "TextField.border" to javax.swing.BorderFactory.createEmptyBorder(0, 14, 0, 14),
            "PasswordField.background" to control, "PasswordField.foreground" to text, "PasswordField.caretForeground" to accent,
            "TextArea.background" to bar, "TextArea.foreground" to text, "OptionPane.background" to bar, "OptionPane.messageForeground" to text,
            "ToolTip.background" to control, "ToolTip.foreground" to text, "ToolTip.border" to javax.swing.BorderFactory.createEmptyBorder(4, 8, 4, 8),
            "PopupMenu.background" to control, "PopupMenu.border" to javax.swing.BorderFactory.createLineBorder(color(Rgba.white.opacity(0.1))),
            "MenuItem.background" to control, "MenuItem.foreground" to text, "MenuItem.selectionBackground" to color(Palette.controlOpen),
            "MenuItem.selectionForeground" to text, "Menu.background" to control, "Menu.foreground" to text,
            "Menu.selectionBackground" to color(Palette.controlOpen), "Menu.selectionForeground" to text, "MenuItem.disabledForeground" to color(Palette.muted.opacity(0.6)),
            "CheckBoxMenuItem.background" to control, "CheckBoxMenuItem.foreground" to text, "CheckBoxMenuItem.selectionBackground" to color(Palette.controlOpen),
            "RadioButtonMenuItem.background" to control, "RadioButtonMenuItem.foreground" to text, "RadioButtonMenuItem.selectionBackground" to color(Palette.controlOpen),
            "Separator.foreground" to color(Rgba.white.opacity(0.08)), "Separator.background" to control,
            "ScrollBar.width" to 10, "ScrollBarUI" to DarkScrollBarUI::class.java.name,
        )) UIManager.put(k, v)
        for (k in listOf("Label.font", "TextField.font", "PasswordField.font", "List.font", "TextArea.font", "ToolTip.font", "MenuItem.font", "Menu.font", "CheckBoxMenuItem.font", "RadioButtonMenuItem.font", "Button.font", "OptionPane.messageFont", "OptionPane.buttonFont"))
            UIManager.put(k, body)
    }

    /** Antialiased shapes and text, and strokes at sub-pixel positions, as Core Graphics draws. */
    fun smooth(g: Graphics): Graphics2D = (g.create() as Graphics2D).apply {
        setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON)
        setRenderingHint(RenderingHints.KEY_TEXT_ANTIALIASING, RenderingHints.VALUE_TEXT_ANTIALIAS_LCD_HRGB)
        setRenderingHint(RenderingHints.KEY_STROKE_CONTROL, RenderingHints.VALUE_STROKE_PURE)
        setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY)
        setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BILINEAR)
        setRenderingHint(RenderingHints.KEY_FRACTIONALMETRICS, RenderingHints.VALUE_FRACTIONALMETRICS_ON)
    }

    /** A rounded rectangle as the iOS app's `RoundedRectangle(cornerRadius:style: .continuous)`:
     *  Java2D's circular corners at the same radius (the continuous curve is a little softer). */
    fun round(r: Rect, radius: Double) = RoundRectangle2D.Double(r.x, r.y, r.width, r.height, radius * 2, radius * 2)

    fun fill(g: Graphics2D, r: Rect, radius: Double, c: Rgba) { g.color = color(c); g.fill(round(r, radius)) }

    /** SwiftUI's `strokeBorder`: the line inside the shape's edge. */
    fun strokeBorder(g: Graphics2D, r: Rect, radius: Double, c: Rgba, width: Double = 1.0) {
        g.color = color(c); g.stroke = BasicStroke(width.toFloat())
        val h = width / 2
        g.draw(round(Rect(r.x + h, r.y + h, r.width - width, r.height - width), (radius - h).coerceAtLeast(0.0)))
    }

    /**
     * SwiftUI's `.shadow(color:radius:x:y:)` under a rounded rectangle: blurred by layering the shape
     * grown step by step at falling opacity (a Gaussian's look, without an image per frame), drawn
     * before the shape itself.
     */
    fun shadow(g: Graphics2D, r: Rect, radius: Double, alpha: Double, blur: Double, dy: Double) {
        val steps = 10
        val old = g.composite
        for (i in steps downTo 1) {
            val grow = blur * i / steps
            val a = alpha / steps * (1.0 - i.toDouble() / (steps + 1)) * 2
            g.composite = AlphaComposite.getInstance(AlphaComposite.SRC_OVER, a.coerceIn(0.0, 1.0).toFloat())
            g.color = Color.BLACK
            g.fill(round(Rect(r.x - grow / 2, r.y + dy - grow / 2, r.width + grow, r.height + grow), radius + grow / 2))
        }
        g.composite = old
    }

    /** A glyph (Symbols.kt) in a `box`-sized square at (x, y), in `c`, cutouts in `background`. */
    fun glyph(g: Graphics2D, s: Symbol, x: Double, y: Double, box: Double, c: Rgba, background: Rgba = Palette.control) {
        val k = box / 24.0
        val g2 = g.create() as Graphics2D
        g2.translate(x, y); g2.scale(k, k)
        for (shape in s.shapes) {
            g2.color = color(if (shape.cutout) background else c)
            val stroke = shape.stroke
            if (stroke != null) g2.stroke = BasicStroke(stroke.toFloat(), BasicStroke.CAP_ROUND, BasicStroke.JOIN_ROUND)
            val awt = when (shape) {
                is Glyph.Circle -> Ellipse2D.Double(shape.cx - shape.r, shape.cy - shape.r, shape.r * 2, shape.r * 2)
                is Glyph.Line -> Line2D.Double(shape.x1, shape.y1, shape.x2, shape.y2)
                is Glyph.RoundRect -> RoundRectangle2D.Double(shape.x, shape.y, shape.w, shape.h, shape.r * 2, shape.r * 2)
                is Glyph.Polygon -> Path2D.Double().apply { shape.points.forEachIndexed { i, p -> if (i == 0) moveTo(p.first, p.second) else lineTo(p.first, p.second) }; closePath() }
                is Glyph.Polyline -> Path2D.Double().apply { shape.points.forEachIndexed { i, p -> if (i == 0) moveTo(p.first, p.second) else lineTo(p.first, p.second) } }
            }
            if (stroke != null) g2.draw(awt) else g2.fill(awt)
        }
        g2.dispose()
    }

    /** Text with its top-left at (x, y) (the iOS layouts place text by its frame, not its baseline). */
    fun text(g: Graphics2D, s: String, x: Double, y: Double, font: Font, c: Rgba): FontMetrics {
        g.font = font; g.color = color(c)
        val fm = g.fontMetrics
        g.drawString(s, x.toFloat(), (y + fm.ascent).toFloat())
        return fm
    }

    /** Text centred in `r` horizontally, at `y`. */
    fun centred(g: Graphics2D, s: String, r: Rect, y: Double, font: Font, c: Rgba) {
        g.font = font
        val w = g.fontMetrics.stringWidth(s)
        text(g, s, r.x + (r.width - w) / 2, y, font, c)
    }

    /** `s` cut to `width` with an ellipsis, as a one-line Text truncates. */
    fun fit(fm: FontMetrics, s: String, width: Double, middle: Boolean = false): String {
        if (fm.stringWidth(s) <= width) return s
        if (middle) {
            var keep = s.length
            while (keep > 1) {
                keep--
                val head = s.take((keep + 1) / 2); val tail = s.takeLast(keep / 2)
                if (fm.stringWidth("$head…$tail") <= width) return "$head…$tail"
            }
            return "…"
        }
        var n = s.length
        while (n > 0 && fm.stringWidth(s.take(n) + "…") > width) n--
        return s.take(n) + "…"
    }
}

/**
 * A SwiftUI animation on Swing's timer: `run(curve) { p -> … }` calls back on the event thread with
 * the curve's progress (0 to 1, past 1 for a spring's bounce) about 120 times a second until the
 * curve rests, then once more with exactly 1. A new run on the same animator cancels the old one, as
 * a new `withAnimation` on the same value retargets it.
 */
class Animator {
    private var timer: Timer? = null
    private var started = 0L

    val running get() = timer != null

    fun run(curve: Curve, reduceMotion: Boolean = false, onFrame: (Double) -> Unit) {
        stop()
        if (reduceMotion && curve is Curve.Spring) { run(Curve.EaseOut(0.18), false, onFrame); return }
        started = System.nanoTime()
        val t = Timer(8) {
            val s = (System.nanoTime() - started) / 1e9
            if (s >= curve.seconds) { stop(); onFrame(1.0) } else onFrame(curve.value(s))
        }
        t.isCoalesce = true
        timer = t
        onFrame(0.0)
        t.start()
    }

    fun stop() { timer?.stop(); timer = null }
}

/** A value that animates toward its target with a curve, repainting `owner` each frame. */
class Animated(initial: Double, private val owner: JComponent) {
    var value = initial
        private set
    var target = initial
        private set
    private val animator = Animator()

    fun animate(to: Double, curve: Curve, reduceMotion: Boolean = SillSwing.reduceMotion) {
        if (to == target && (animator.running || value == to)) return
        val from = value
        target = to
        animator.run(curve, reduceMotion) { p -> value = from + (to - from) * p; owner.repaint() }
    }

    fun snap(to: Double) { animator.stop(); value = to; target = to; owner.repaint() }
}

/** The dark scrollbars of the drawer and the panel: a thin muted thumb, no track, no arrows, as
 *  iOS's scroll indicator; on Windows it stays a scrollbar a mouse can drag. */
class DarkScrollBarUI : BasicScrollBarUI() {
    override fun configureScrollBarColors() {
        thumbColor = SillSwing.color(Palette.muted.opacity(0.55))
        trackColor = SillSwing.color(Rgba.clear)
    }
    override fun createDecreaseButton(orientation: Int) = zero()
    override fun createIncreaseButton(orientation: Int) = zero()
    private fun zero() = javax.swing.JButton().apply { preferredSize = java.awt.Dimension(0, 0); isVisible = false }
    override fun paintTrack(g: Graphics, c: JComponent, r: java.awt.Rectangle) {}
    override fun paintThumb(g: Graphics, c: JComponent, r: java.awt.Rectangle) {
        if (r.isEmpty || !scrollbar.isEnabled) return
        val g2 = SillSwing.smooth(g)
        val w = 4.0
        val rr = if (scrollbar.orientation == JScrollBar.VERTICAL) Rect(r.x + (r.width - w) / 2, r.y + 2.0, w, r.height - 4.0)
        else Rect(r.x + 2.0, r.y + (r.height - w) / 2, r.width - 4.0, w)
        SillSwing.fill(g2, rr, w / 2, if (isThumbRollover) Palette.muted else Palette.muted.opacity(0.55))
        g2.dispose()
    }

    companion object {
        @JvmStatic fun createUI(@Suppress("UNUSED_PARAMETER") c: JComponent) = DarkScrollBarUI()
    }
}

/** Runs `f` on the event thread, now if this is it. */
fun onEdt(f: () -> Unit) = if (SwingUtilities.isEventDispatchThread()) f() else SwingUtilities.invokeLater(f)
