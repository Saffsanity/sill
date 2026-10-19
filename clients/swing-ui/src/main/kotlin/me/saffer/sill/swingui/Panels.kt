package me.saffer.sill.swingui

import me.saffer.sill.core.ui.Curve
import me.saffer.sill.core.ui.Motion
import me.saffer.sill.core.ui.Palette
import me.saffer.sill.core.ui.Rect
import me.saffer.sill.core.ui.Rgba
import me.saffer.sill.core.ui.Symbol
import me.saffer.sill.core.ui.TextStyle
import me.saffer.sill.core.ui.Type
import me.saffer.sill.core.ui.Ui
import java.awt.AlphaComposite
import java.awt.BasicStroke
import java.awt.Component
import java.awt.Container
import java.awt.Dimension
import java.awt.FontMetrics
import java.awt.Graphics
import java.awt.Graphics2D
import java.awt.LayoutManager
import java.awt.event.MouseAdapter
import java.awt.event.MouseEvent
import java.awt.geom.Arc2D
import java.awt.geom.Ellipse2D
import javax.swing.BorderFactory
import javax.swing.JComponent
import javax.swing.JPanel
import javax.swing.JPopupMenu
import javax.swing.JScrollPane
import javax.swing.JTextField
import javax.swing.ScrollPaneConstants
import javax.swing.SwingUtilities
import javax.swing.Timer
import javax.swing.event.DocumentEvent
import javax.swing.event.DocumentListener
import kotlin.math.max

/** A component whose height follows its width (wrapped words), for [VStack]. */
interface HeightForWidth { fun heightFor(width: Int): Int }

fun Component.heightAt(width: Int): Int = if (this is HeightForWidth) heightFor(width) else preferredSize.height

/**
 * SwiftUI's VStack(alignment: .leading, spacing:) for Swing: each child as wide as the container
 * (less `inset` each side), at its height for that width, one under the other.
 */
class VStack(private val spacing: Int = 0, private val inset: Int = 0) : LayoutManager {
    override fun addLayoutComponent(name: String?, comp: Component?) {}
    override fun removeLayoutComponent(comp: Component?) {}
    fun heightFor(parent: Container, width: Int): Int {
        val shown = parent.components.filter { it.isVisible }
        return shown.sumOf { it.heightAt(width - 2 * inset) } + max(0, shown.size - 1) * spacing + parent.insets.top + parent.insets.bottom
    }
    override fun preferredLayoutSize(parent: Container) = Dimension(parent.width.coerceAtLeast(1), heightFor(parent, parent.width.coerceAtLeast(1)))
    override fun minimumLayoutSize(parent: Container) = Dimension(0, 0)
    override fun layoutContainer(parent: Container) {
        var y = parent.insets.top
        val w = parent.width - 2 * inset
        for (c in parent.components) {
            if (!c.isVisible) continue
            val h = c.heightAt(w)
            c.setBounds(inset, y, w, h)
            y += h + spacing
        }
    }
}

/** A see-through panel stacked with [VStack] whose preferred height follows its width. */
open class StackPanel(spacing: Int = 0, inset: Int = 0) : JPanel(), HeightForWidth, javax.swing.Scrollable {
    private val stack = VStack(spacing, inset)
    init { layout = stack; isOpaque = false }
    override fun heightFor(width: Int) = stack.heightFor(this, width)
    override fun getPreferredSize() = Dimension(max(1, width), heightFor(max(1, parent?.width ?: width)))
    override fun getPreferredScrollableViewportSize(): Dimension = preferredSize
    override fun getScrollableUnitIncrement(visibleRect: java.awt.Rectangle, orientation: Int, direction: Int) = 24
    override fun getScrollableBlockIncrement(visibleRect: java.awt.Rectangle, orientation: Int, direction: Int) = visibleRect.height - 24
    override fun getScrollableTracksViewportWidth() = true
    override fun getScrollableTracksViewportHeight() = false
}

/** A dark scroll pane with no border and a see-through viewport, scrolling vertically only. */
fun darkScroll(view: Component): JScrollPane = JScrollPane(view, ScrollPaneConstants.VERTICAL_SCROLLBAR_AS_NEEDED, ScrollPaneConstants.HORIZONTAL_SCROLLBAR_NEVER).apply {
    border = BorderFactory.createEmptyBorder()
    viewportBorder = null
    isOpaque = false
    viewport.isOpaque = false
    verticalScrollBar.unitIncrement = 24
    verticalScrollBar.isOpaque = false
}

/** Words wrapped to a width, as SwiftUI's Text with `.fixedSize(horizontal: false, vertical: true)`. */
object Wrap {
    fun lines(fm: FontMetrics, text: String, width: Double): List<String> {
        val out = ArrayList<String>()
        for (para in text.split('\n')) {
            var line = StringBuilder()
            for (word in para.split(' ')) {
                val trial = if (line.isEmpty()) word else "$line $word"
                if (fm.stringWidth(trial) <= width || line.isEmpty()) {
                    if (line.isEmpty() && fm.stringWidth(word) > width) {
                        // A word longer than the line breaks where it must.
                        var rest = word
                        while (fm.stringWidth(rest) > width && rest.length > 1) {
                            var n = rest.length
                            while (n > 1 && fm.stringWidth(rest.take(n)) > width) n--
                            out.add(rest.take(n)); rest = rest.drop(n)
                        }
                        line = StringBuilder(rest)
                    } else line = StringBuilder(trial)
                } else { out.add(line.toString()); line = StringBuilder(word) }
            }
            out.add(line.toString())
        }
        return out
    }
}

/**
 * A wrapped line of words: a status line, a footnote, a card's words. `warning` puts the orange
 * warning sign before it and colours it orange (a Footnote's or a ProblemLine's).
 */
class WrapLabel(text: String, var style: TextStyle = Type.footnote, var color: Rgba = Palette.muted,
                var pad: java.awt.Insets = java.awt.Insets(0, 0, 0, 0), var warning: Boolean = false) : SillComponent(), HeightForWidth {
    var text = text; set(v) { if (field != v) { field = v; getAccessibleContext().accessibleName = v; revalidate(); repaint() } }
    init { isOpaque = false; getAccessibleContext().accessibleName = text }
    private val iconW get() = if (warning) Symbol.boxFor(style.size) * 0.85 + 6 else 0.0
    private fun fm() = getFontMetrics(SillSwing.font(style))
    override fun heightFor(width: Int): Int {
        if (text.isEmpty()) return pad.top + pad.bottom
        val fm = fm()
        val n = Wrap.lines(fm, text, width - pad.left - pad.right - iconW).size
        return pad.top + pad.bottom + n * fm.height
    }
    override fun getPreferredSize() = Dimension(width.coerceAtLeast(1), heightFor(width.coerceAtLeast(240)))
    override fun paintComponent(g0: Graphics) {
        if (text.isEmpty()) return
        val g = SillSwing.smooth(g0)
        val font = SillSwing.font(style)
        g.font = font
        val fm = g.fontMetrics
        val c = if (warning) Rgba.orange else color
        val x = pad.left + iconW
        if (warning) {
            val box = Symbol.boxFor(style.size) * 0.85
            SillSwing.glyph(g, Symbol.Warning, pad.left.toDouble(), pad.top + (fm.height - box) / 2, box, Rgba.orange, Palette.bar)
        }
        Wrap.lines(fm, text, width - pad.left - pad.right - iconW).forEachIndexed { i, line ->
            SillSwing.text(g, line, x, pad.top + i * fm.height.toDouble() + (fm.height - fm.ascent - fm.descent) / 2.0, font, c)
        }
        g.dispose()
    }
}

/**
 * A field on the control colour, 48 tall, corners 12, its prompt muted while empty and an optional
 * symbol before it (the drawer's search field, the pairing fields).
 */
class SillTextField(var prompt: String, val symbol: Symbol? = null, val style: TextStyle = Type.search) : JTextField() {
    init {
        isOpaque = false
        font = SillSwing.font(style)
        foreground = SillSwing.color(Palette.text)
        caretColor = SillSwing.color(Palette.accent)
        selectionColor = SillSwing.color(Palette.controlOpen)
        selectedTextColor = SillSwing.color(Palette.text)
        val left = 14 + if (symbol != null) (Symbol.boxFor(Ui.searchIconSize).toInt() + 10) else 0
        border = BorderFactory.createEmptyBorder(0, left, 0, 14)
        getAccessibleContext().accessibleName = prompt
        document.addDocumentListener(object : DocumentListener {
            override fun insertUpdate(e: DocumentEvent) = repaint()
            override fun removeUpdate(e: DocumentEvent) = repaint()
            override fun changedUpdate(e: DocumentEvent) = repaint()
        })
    }
    override fun getPreferredSize() = Dimension(super.getPreferredSize().width, Ui.searchHeight.toInt())
    override fun paintComponent(g0: Graphics) {
        val g = SillSwing.smooth(g0)
        val r = Rect(0.0, 0.0, width.toDouble(), height.toDouble())
        SillSwing.fill(g, r, Ui.fieldRadius, Palette.control)
        if (isFocusOwner) SillSwing.strokeBorder(g, r, Ui.fieldRadius, Palette.accent.opacity(0.55), 1.5)
        symbol?.let {
            val box = Symbol.boxFor(Ui.searchIconSize)
            SillSwing.glyph(g, it, 14.0, (height - box) / 2, box, Palette.muted, Palette.control)
        }
        if (text.isEmpty()) {
            val fm = g.getFontMetrics(font)
            val x = insets.left.toDouble()
            SillSwing.text(g, SillSwing.fit(fm, prompt, width - x - 14.0), x, (height - fm.ascent - fm.descent) / 2.0, font, Palette.muted)
        }
        g.dispose()
        super.paintComponent(g0)
    }
}

/**
 * A rounded sheet (the Apps drawer, the Settings panel): the bar colour, corners 20, the white 10 %
 * hairline, inside 14. It appears by [present]: the drawer fades (Motion.drawer), the panel also grows
 * from Motion.settingsScale around its anchor (Motion.settingsOpen, closing with
 * Motion.settingsClose), a fade alone with Reduce Motion. Its shadow is the [Scrim]'s to draw,
 * since it falls outside the sheet.
 */
open class Sheet : JPanel() {
    val shown = Animated(0.0, this)
    var scaleFrom = 1.0
    /** Where it grows from, as fractions of its own size (1, 0: the top trailing corner). */
    var anchorX = 1.0
    var anchorY = 0.0
    var openCurve: Curve = Motion.drawer
    var closeCurve: Curve = Motion.drawer
    private var hideTimer: Timer? = null
    var onHidden: () -> Unit = {}

    init { isOpaque = false; isVisible = false; layout = null }

    override fun setBounds(x: Int, y: Int, width: Int, height: Int) { super.setBounds(x, y, width, height); doLayout() }

    fun present(open: Boolean) {
        hideTimer?.stop()
        if (open) {
            if (!isVisible) { shown.snap(0.0); isVisible = true }
            shown.animate(1.0, openCurve)
        } else if (isVisible) {
            shown.animate(0.0, closeCurve)
            hideTimer = Timer((closeCurve.seconds * 1000).toInt() + 20) { if (shown.target == 0.0) { isVisible = false; onHidden() } }.apply { isRepeats = false; start() }
        }
    }

    val isOpen get() = isVisible && shown.target == 1.0

    override fun paint(g0: Graphics) {
        val p = shown.value.coerceIn(0.0, 1.2)
        if (p <= 0.003) return
        val g = g0.create() as Graphics2D
        g.composite = AlphaComposite.getInstance(AlphaComposite.SRC_OVER, p.coerceIn(0.0, 1.0).toFloat())
        if (scaleFrom != 1.0 && !SillSwing.reduceMotion) {
            val s = scaleFrom + (1 - scaleFrom) * p
            val ax = width * anchorX; val ay = height * anchorY
            g.translate(ax, ay); g.scale(s, s); g.translate(-ax, -ay)
        }
        super.paint(g)
        g.dispose()
    }

    override fun paintComponent(g0: Graphics) {
        val g = SillSwing.smooth(g0)
        val r = Rect(0.0, 0.0, width.toDouble(), height.toDouble())
        SillSwing.fill(g, r, Ui.sheetRadius, Palette.bar)
        SillSwing.strokeBorder(g, r, Ui.sheetRadius, Rgba.white.opacity(Ui.sheetStrokeAlpha))
        g.dispose()
    }
}

/**
 * What is under an open sheet: the 0.58 black over the stream while the drawer is open (clear under
 * the Settings panel, which keeps the stream in view), a click on it closing the sheet without
 * reaching the Mac, and the sheet's shadow.
 */
class Scrim : SillComponent() {
    val dim = Animated(0.0, this)
    var onClick: () -> Unit = {}
    /** The sheet whose shadow this draws, in this component's parent's coordinates. */
    var sheet: Sheet? = null
    init {
        isOpaque = false; isVisible = false
        addMouseListener(object : MouseAdapter() { override fun mousePressed(e: MouseEvent) { onClick() } })
        addMouseWheelListener { }        // the wheel stops here too
    }
    override fun paintComponent(g0: Graphics) {
        val g = SillSwing.smooth(g0)
        if (dim.value > 0.003) { g.color = SillSwing.color(Rgba.black.opacity(dim.value)); g.fillRect(0, 0, width, height) }
        val s = sheet
        if (s != null && s.isVisible) {
            val p = s.shown.value.coerceIn(0.0, 1.0)
            val r = Rect((s.x - x).toDouble(), (s.y - y).toDouble(), s.width.toDouble(), s.height.toDouble())
            SillSwing.shadow(g, r, Ui.sheetRadius, Ui.sheetShadowAlpha * p, Ui.sheetShadowRadius, Ui.sheetShadowY)
        }
        g.dispose()
    }
}

// MARK: The Settings panel's pieces (HostSettingsPanel.swift)

/** A group of rows (Rows): the control colour, corners 12, a hairline between rows inset 14. */
class RowGroup(rows: List<JComponent>) : JPanel(), HeightForWidth {
    init {
        isOpaque = false
        layout = VStack()
        rows.forEach { add(it) }
    }
    override fun heightFor(width: Int) = (layout as VStack).heightFor(this, width)
    override fun getPreferredSize() = Dimension(width.coerceAtLeast(1), heightFor(width.coerceAtLeast(300)))
    override fun paintComponent(g0: Graphics) {
        val g = SillSwing.smooth(g0)
        SillSwing.fill(g, Rect(0.0, 0.0, width.toDouble(), height.toDouble()), Ui.fieldRadius, Palette.control)
        g.color = SillSwing.color(Rgba.white.opacity(Ui.dividerAlpha))
        val shown = components.filter { it.isVisible }
        for (c in shown.dropLast(1)) g.fill(java.awt.geom.Rectangle2D.Double(Ui.rowInset, c.y + c.height - Ui.dividerHeight, width - Ui.rowInset, Ui.dividerHeight))
        g.dispose()
    }
}

/** A row's base: at least 44 tall, its title in body text with the pending spinner beside it. */
abstract class PanelRow(val title: String) : SillComponent(), HeightForWidth {
    /** When a pick on this row was sent, in [Clock] seconds; the spinner shows 0.3 s after it. */
    var pendingSince: Double? = null; set(v) { if (v == field) return; field = v; spinning?.stop(); spinning = null; if (v != null) spinning = Timer(33) { repaint() }.apply { start() }; repaint() }
    private var spinning: Timer? = null
    init { isOpaque = false; isFocusable = true; isRequestFocusEnabled = false; getAccessibleContext().accessibleName = title }
    override fun heightFor(width: Int) = Ui.touchTarget.toInt()
    override fun getPreferredSize() = Dimension(width.coerceAtLeast(1), heightFor(width))
    override fun removeNotify() { spinning?.stop(); spinning = null; super.removeNotify() }

    protected fun paintTitle(g: Graphics2D, enabled: Boolean = true): Double {
        val font = SillSwing.font(Type.body)
        g.font = font
        val fm = g.fontMetrics
        val y = (height - fm.ascent - fm.descent) / 2.0
        SillSwing.text(g, title, Ui.rowInset, y, font, if (enabled) Palette.text else Palette.muted)
        var end = Ui.rowInset + fm.stringWidth(title)
        val since = pendingSince
        if (since != null && Clock.now() - since >= Ui.pendingDelay) {
            end += 6
            Spinner.draw(g, end, height / 2.0 - 8, 16.0)
            end += 16
        }
        if (isFocusOwner) SillSwing.strokeBorder(g, Rect(1.0, 1.0, width - 2.0, height - 2.0), Ui.fieldRadius - 1, Palette.accent, 2.0)
        return end
    }
}

/** A monotonic clock in seconds (the ledger's and the spinner's). */
object Clock { fun now() = System.nanoTime() / 1e9 }

/** The system's small activity spinner, in the muted colour. */
object Spinner {
    fun draw(g: Graphics2D, x: Double, y: Double, d: Double) {
        val t = (System.nanoTime() / 1e9) % 1.0
        val g2 = g.create() as Graphics2D
        g2.stroke = BasicStroke((d / 8).toFloat(), BasicStroke.CAP_ROUND, BasicStroke.JOIN_ROUND)
        for (i in 0 until 8) {
            val a = i * Math.PI / 4
            val phase = ((i / 8.0 - t) % 1.0 + 1.0) % 1.0
            g2.color = SillSwing.color(Palette.muted.opacity(0.25 + 0.75 * phase))
            val cx = x + d / 2; val cy = y + d / 2
            g2.draw(java.awt.geom.Line2D.Double(cx + Math.cos(a) * d * 0.25, cy + Math.sin(a) * d * 0.25, cx + Math.cos(a) * d * 0.45, cy + Math.sin(a) * d * 0.45))
        }
        g2.dispose()
    }
}

/**
 * A menu picker row (Quality): the value in the accent with the up-and-down chevrons, a click
 * opening the choices with a check beside the current one, as SwiftUI's `.pickerStyle(.menu)`.
 */
class MenuRow(title: String, var choices: List<Pair<String, Int>>, var selected: Int, val onPick: (Int) -> Unit) : PanelRow(title) {
    var enabledRow = true
    init {
        addMouseListener(object : MouseAdapter() { override fun mousePressed(e: MouseEvent) { if (enabledRow) popup() } })
        inputMap.put(javax.swing.KeyStroke.getKeyStroke("SPACE"), "open"); inputMap.put(javax.swing.KeyStroke.getKeyStroke("ENTER"), "open")
        actionMap.put("open", object : javax.swing.AbstractAction() { override fun actionPerformed(e: java.awt.event.ActionEvent) { if (enabledRow) popup() } })
    }
    private fun valueText() = choices.firstOrNull { it.second == selected }?.first ?: ""
    fun popup() {
        val menu = JPopupMenu()
        for ((label, v) in choices) menu.add(javax.swing.JMenuItem((if (v == selected) "✓  " else "     ") + label).apply {
            addActionListener { if (v != selected) onPick(v) }
        })
        val fm = getFontMetrics(SillSwing.font(Type.body))
        menu.show(this, (width - Ui.rowInset - fm.stringWidth(valueText()) - 24).toInt(), height)
    }
    override fun paintComponent(g0: Graphics) {
        val g = SillSwing.smooth(g0)
        paintTitle(g)
        val font = SillSwing.font(Type.body)
        g.font = font
        val fm = g.fontMetrics
        val v = valueText()
        val chev = Symbol.boxFor(11.0)
        val x = width - Ui.rowInset - chev - 4 - fm.stringWidth(v)
        val c = if (enabledRow) Palette.accent else Palette.muted
        SillSwing.text(g, v, x, (height - fm.ascent - fm.descent) / 2.0, font, c)
        SillSwing.glyph(g, Symbol.ChevronUp, width - Ui.rowInset - chev, height / 2.0 - chev * 0.78, chev, c)
        SillSwing.glyph(g, Symbol.ChevronDown, width - Ui.rowInset - chev, height / 2.0 - chev * 0.22, chev, c)
        g.dispose()
    }
}

/**
 * A segmented row (Resolution, Frame Rate): SwiftUI's `.pickerStyle(.segmented)` in the dark
 * appearance, beside the title; a value no segment holds (a Mac-held 90 fps) selects none.
 */
class SegmentedRow(title: String, val options: List<String>, var selectedIndex: Int, val onPick: (Int) -> Unit) : PanelRow(title) {
    var enabledRow = true
    private val sel = Animated(selectedIndex.toDouble(), this)
    init {
        addMouseListener(object : MouseAdapter() {
            override fun mousePressed(e: MouseEvent) {
                if (!enabledRow) return
                val i = segments().indexOfFirst { it.contains(e.x.toDouble(), e.y.toDouble()) }
                if (i >= 0 && i != selectedIndex) onPick(i)
            }
        })
        for ((k, d) in listOf("LEFT" to -1, "RIGHT" to 1)) {
            inputMap.put(javax.swing.KeyStroke.getKeyStroke(k), k)
            actionMap.put(k, object : javax.swing.AbstractAction() {
                override fun actionPerformed(e: java.awt.event.ActionEvent) { val i = (selectedIndex + d).coerceIn(0, options.size - 1); if (enabledRow && i != selectedIndex) onPick(i) }
            })
        }
    }
    fun select(i: Int) { if (i != selectedIndex) { val from = selectedIndex; selectedIndex = i; if (from < 0 || i < 0) sel.snap(i.toDouble()) else sel.animate(i.toDouble(), Curve.EaseOut(0.2)) } }
    private fun segW(): Double {
        val fm = getFontMetrics(SillSwing.font(SEG))
        return options.maxOf { fm.stringWidth(it) } + 24.0
    }
    private fun segments(): List<Rect> {
        val w = segW(); val h = 28.0
        val total = w * options.size + 4
        val x0 = width - Ui.rowInset - total
        return options.indices.map { Rect(x0 + 2 + it * w, (height - h) / 2 + 2, w, h - 4) }
    }
    override fun paintComponent(g0: Graphics) {
        val g = SillSwing.smooth(g0)
        paintTitle(g)
        val segs = segments()
        if (segs.isEmpty()) return
        val track = Rect(segs.first().x - 2, segs.first().y - 2, segs.last().maxX - segs.first().x + 4, segs.first().height + 4)
        SillSwing.fill(g, track, 9.0, Rgba(0x767680, 0.24))
        if (selectedIndex >= 0) {
            val k = sel.value
            val r = segs.first().offset(segs.first().width * k, 0.0)
            SillSwing.fill(g, r, 7.0, Rgba(0x636366))
        }
        val font = SillSwing.font(SEG)
        g.font = font
        val fm = g.fontMetrics
        segs.forEachIndexed { i, r ->
            if (i > 0 && selectedIndex != i && selectedIndex != i - 1) {
                g.color = SillSwing.color(Rgba.white.opacity(0.12)); g.fill(java.awt.geom.Rectangle2D.Double(r.x - 0.5, r.y + 6, 1.0, r.height - 12))
            }
            SillSwing.centred(g, options[i], r, r.midY - (fm.ascent + fm.descent) / 2.0, font, if (enabledRow) Palette.text else Palette.muted)
        }
        g.dispose()
    }
    companion object { val SEG = TextStyle(13.0, TextStyle.Weight.Medium) }
}

/** A switch row (Toggle): the system's switch, on in the accent, its knob sliding with an ease out. */
class SwitchRow(title: String, var on: Boolean, val onToggle: (Boolean) -> Unit) : PanelRow(title) {
    var enabledRow = true
    private val knob = Animated(if (on) 1.0 else 0.0, this)
    init {
        addMouseListener(object : MouseAdapter() { override fun mousePressed(e: MouseEvent) { if (enabledRow) onToggle(!on) } })
        inputMap.put(javax.swing.KeyStroke.getKeyStroke("SPACE"), "toggle")
        actionMap.put("toggle", object : javax.swing.AbstractAction() { override fun actionPerformed(e: java.awt.event.ActionEvent) { if (enabledRow) onToggle(!on) } })
    }
    fun set(v: Boolean) { if (v != on) { on = v; knob.animate(if (v) 1.0 else 0.0, Curve.EaseOut(0.2)) } }
    override fun paintComponent(g0: Graphics) {
        val g = SillSwing.smooth(g0)
        paintTitle(g, enabledRow)
        val w = 51.0; val h = 31.0
        val r = Rect(width - Ui.rowInset - w, (height - h) / 2, w, h)
        val k = knob.value.coerceIn(0.0, 1.0)
        val off = Rgba(0x787880, 0.32)
        g.composite = AlphaComposite.getInstance(AlphaComposite.SRC_OVER, if (enabledRow) 1f else 0.45f)
        SillSwing.fill(g, r, h / 2, off)
        if (k > 0) SillSwing.fill(g, r, h / 2, Palette.accent.opacity(k))
        val d = 27.0
        val kx = r.x + 2 + (w - d - 4) * k
        g.color = java.awt.Color(0, 0, 0, 40); g.fill(Ellipse2D.Double(kx - 0.5, r.y + 2.5, d + 1, d + 1))
        g.color = java.awt.Color.WHITE; g.fill(Ellipse2D.Double(kx, r.y + 2, d, d))
        g.dispose()
    }
}

/** A row that is one accent action (the panel's Take the Tour), or a plain line (Loading settings…). */
class ActionRow(title: String, val accent: Boolean, val symbol: Symbol? = null, val onClick: (() -> Unit)?) : PanelRow(title) {
    init {
        if (onClick != null) {
            addMouseListener(object : MouseAdapter() { override fun mouseClicked(e: MouseEvent) { onClick.invoke() } })
            inputMap.put(javax.swing.KeyStroke.getKeyStroke("SPACE"), "go"); inputMap.put(javax.swing.KeyStroke.getKeyStroke("ENTER"), "go")
            actionMap.put("go", object : javax.swing.AbstractAction() { override fun actionPerformed(e: java.awt.event.ActionEvent) { onClick.invoke() } })
        } else isFocusable = false
    }
    override fun paintComponent(g0: Graphics) {
        val g = SillSwing.smooth(g0)
        val font = SillSwing.font(Type.body)
        g.font = font
        val fm = g.fontMetrics
        var x = Ui.rowInset
        val c = if (accent) Palette.accent else Palette.text
        if (symbol != null) {
            val box = Symbol.boxFor(17.0)
            SillSwing.glyph(g, symbol, x, (height - box) / 2, box, c, Palette.control)
            x += box + 8
        }
        SillSwing.text(g, SillSwing.fit(fm, title, width - x - Ui.rowInset), x, (height - fm.ascent - fm.descent) / 2.0, font, c)
        if (isFocusOwner) SillSwing.strokeBorder(g, Rect(1.0, 1.0, width - 2.0, height - 2.0), Ui.fieldRadius - 1, Palette.accent, 2.0)
        g.dispose()
    }
}

/**
 * A callout above the groups (Callout): the orange sign and the words on orange 14 %, corners 12,
 * and, when the Mac recommends something, a 44 tall accent button on the control colour.
 */
class Callout(val text: String, val button: String? = null, val onButton: () -> Unit = {}) : SillComponent(), HeightForWidth {
    init {
        isOpaque = false
        getAccessibleContext().accessibleName = text
        if (button != null) addMouseListener(object : MouseAdapter() {
            override fun mouseClicked(e: MouseEvent) { if (buttonRect().contains(e.x.toDouble(), e.y.toDouble())) onButton() }
        })
    }
    private fun fm() = getFontMetrics(SillSwing.font(Type.footnote))
    private val icon get() = Symbol.boxFor(13.0) * 0.85
    private fun textLines(w: Int) = Wrap.lines(fm(), text, w - 24 - icon - 8)
    private fun bodyH(w: Int) = textLines(w).size * fm().height
    override fun heightFor(width: Int) = 12 + bodyH(width) + (if (button != null) 10 + 44 else 0) + 12 + 10
    override fun getPreferredSize() = Dimension(width.coerceAtLeast(1), heightFor(width.coerceAtLeast(300)))
    private fun buttonRect() = Rect(12.0, 12.0 + bodyH(width) + 10, width - 24.0, 44.0)
    override fun paintComponent(g0: Graphics) {
        val g = SillSwing.smooth(g0)
        val box = Rect(0.0, 0.0, width.toDouble(), height - 10.0)
        SillSwing.fill(g, box, Ui.fieldRadius, Rgba.orange.opacity(0.14))
        val font = SillSwing.font(Type.footnote)
        val fm = fm()
        SillSwing.glyph(g, Symbol.Warning, 12.0, 12.0 + (fm.height - icon) / 2, icon, Rgba.orange, Palette.bar)
        textLines(width).forEachIndexed { i, l -> SillSwing.text(g, l, 12 + icon + 8, 12.0 + i * fm.height, font, Palette.text) }
        if (button != null) {
            val b = buttonRect()
            SillSwing.fill(g, b, Ui.rowRadius, Palette.control)
            val bf = SillSwing.font(Type.footnote.copy(weight = TextStyle.Weight.Semibold))
            g.font = bf
            SillSwing.text(g, SillSwing.fit(g.fontMetrics, button, b.width - 24), b.x + 12, b.midY - (g.fontMetrics.ascent + g.fontMetrics.descent) / 2.0, bf, Palette.accent)
        }
        g.dispose()
    }
}

/**
 * A rounded sheet's pinned foot button (the panel's Disconnect): its symbol and words in the accent
 * on the control colour, 44 tall, corners 12; the words shorten to [short] when the long ones do not fit.
 */
class FootButton(val symbol: Symbol, long: String, val short: String) : SillControl() {
    var long = long; set(v) { field = v; accessibleName = v; repaint() }
    override val cornerRadius get() = Ui.fieldRadius
    init { accessibleName = long }
    override fun paintControl(g: Graphics2D, r: Rect) {
        SillSwing.fill(g, r, Ui.fieldRadius, Palette.control)
        if (hover) SillSwing.fill(g, r, Ui.fieldRadius, Rgba.white.opacity(if (pressed) 0.08 else 0.04))
        val font = SillSwing.font(Type.body)
        g.font = font
        val fm = g.fontMetrics
        val box = Symbol.boxFor(17.0)
        val room = r.width - Ui.rowInset * 2 - box - 8
        val words = if (fm.stringWidth(long) <= room) long else SillSwing.fit(fm, short, room)
        SillSwing.glyph(g, symbol, Ui.rowInset, r.midY - box / 2, box, Palette.accent, Palette.control)
        SillSwing.text(g, words, Ui.rowInset + box + 8, r.midY - (fm.ascent + fm.descent) / 2.0, font, Palette.accent)
    }
}

/** Runs `f` once the current events are handled (a layout settles before a measure). */
fun later(f: () -> Unit) = SwingUtilities.invokeLater(f)
