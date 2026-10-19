package me.saffer.sill.host.ui

import me.saffer.sill.core.ui.Curve
import me.saffer.sill.core.ui.Rgba
import me.saffer.sill.core.ui.Symbol
import me.saffer.sill.host.MenuAction
import me.saffer.sill.host.MenuEntry
import me.saffer.sill.swingui.Animated
import me.saffer.sill.swingui.SillSwing
import java.awt.Cursor
import java.awt.Dimension
import java.awt.Font
import java.awt.Graphics
import java.awt.Graphics2D
import java.awt.Point
import java.awt.event.FocusAdapter
import java.awt.event.FocusEvent
import java.awt.event.KeyAdapter
import java.awt.event.KeyEvent
import java.awt.event.MouseAdapter
import java.awt.event.MouseEvent
import java.awt.geom.Ellipse2D
import java.awt.geom.Rectangle2D
import java.awt.geom.RoundRectangle2D
import javax.swing.JComponent
import javax.swing.SwingUtilities

/*
 * A grouped Form as SwiftUI draws one on macOS (`.formStyle(.grouped)`, Sill.app's Settings panes):
 * sections of rounded boxes, a label at the leading edge of each row and its control at the trailing
 * one, a hairline between rows, a header above and a footnote under. Laid out at a fixed width, as
 * Sill.app's panes are 520 pt wide, so every height is known without a layout pass. Metrics are
 * AppKit's grouped Form's: 20 pt margins, 8 pt corners, rows at least 36 pt with 10 pt in from the
 * sides, 6 pt between a box and its header or footnote.
 */
object FormMetrics {
    const val MARGIN = 20
    const val RADIUS = 10.0
    const val ROW_MIN = 36
    const val ROW_PAD_H = 10
    const val ROW_PAD_V = 9
    const val GAP = 6
    const val SECTION_GAP = 20
}

/** Something a box holds: it says its height for a width. */
abstract class FormRow : JComponent() {
    abstract fun heightFor(width: Int): Int
    init { isOpaque = false }
}

/** Wrapped text in one style and colour (a Footnote, a Warning with its sign, a plain Text). */
class WrapText(text: String, private val font: Font, private var color: () -> Rgba, private val warning: Boolean = false) : JComponent() {
    var text = text; set(v) { field = v; revalidate(); repaint() }
    private val sign = if (warning) TextMeasure.lineHeight(font) * 0.8 + 6 else 0.0
    fun lines(width: Int) = TextMeasure.wrap(text, font, width - sign)
    fun heightFor(width: Int) = kotlin.math.ceil(lines(width).size * TextMeasure.lineHeight(font)).toInt()
    init { isOpaque = false }
    override fun paintComponent(g0: Graphics) {
        val g = SillSwing.smooth(g0)
        val lh = TextMeasure.lineHeight(font)
        if (warning) HostGlyphs.paint(g, Symbol.Warning, 0.0, (lh - lh * 0.8) / 2, lh * 0.8, HostTheme.c.orange, HostTheme.c.window)
        lines(width).forEachIndexed { i, l -> SillSwing.text(g, l, sign, i * lh, font, color()) }
        g.dispose()
    }
}

/**
 * A row: its label (and a secondary line under it) at the leading edge, a control at the trailing
 * one, centred on the row (LabeledContent, Toggle, Picker). A label that would run into the control
 * is cut in the middle, as "Running from" is.
 */
class LabeledRow(var label: String, val trailing: JComponent? = null, var detail: String? = null) : FormRow() {
    private val font = MacType.font(MacType.body)
    private val detailFont = MacType.font(MacType.subheadline)
    var labelColor: () -> Rgba = { HostTheme.c.label }
    init { trailing?.let { add(it) } }
    override fun heightFor(width: Int): Int {
        val text = TextMeasure.lineHeight(font) + (detail?.let { TextMeasure.lineHeight(detailFont) + 1 } ?: 0.0)
        val control = trailing?.preferredSize?.height ?: 0
        return maxOf(FormMetrics.ROW_MIN, kotlin.math.ceil(maxOf(text, control.toDouble())).toInt() + 2 * FormMetrics.ROW_PAD_V)
    }
    override fun doLayout() {
        val t = trailing ?: return
        val d = t.preferredSize
        t.setBounds(width - FormMetrics.ROW_PAD_H - d.width, (height - d.height) / 2, d.width, d.height)
    }
    override fun paintComponent(g0: Graphics) {
        val g = SillSwing.smooth(g0)
        val c = HostTheme.c
        val room = (trailing?.let { it.x - 12 } ?: (width - FormMetrics.ROW_PAD_H)) - FormMetrics.ROW_PAD_H.toDouble()
        val lh = TextMeasure.lineHeight(font)
        val total = lh + (detail?.let { TextMeasure.lineHeight(detailFont) + 1 } ?: 0.0)
        var y = (height - total) / 2
        SillSwing.text(g, TextMeasure.fit(label, font, room, middle = true), FormMetrics.ROW_PAD_H.toDouble(), y, font, labelColor())
        y += lh + 1
        detail?.let { SillSwing.text(g, TextMeasure.fit(it, detailFont, room, middle = true), FormMetrics.ROW_PAD_H.toDouble(), y, detailFont, c.secondary) }
        g.dispose()
    }
}

/** Text that fills a row (a paired device's removal note, "No paired devices yet."). */
class TextRow(text: String, secondary: Boolean = false, warning: Boolean = false) : FormRow() {
    val content = WrapText(text, MacType.font(MacType.body), { if (secondary) HostTheme.c.secondary else if (warning) HostTheme.c.orange else HostTheme.c.label }, warning)
    init { add(content) }
    override fun heightFor(width: Int) = content.heightFor(width - 2 * FormMetrics.ROW_PAD_H) + 2 * FormMetrics.ROW_PAD_V + 2
    override fun doLayout() { content.setBounds(FormMetrics.ROW_PAD_H, FormMetrics.ROW_PAD_V + 1, width - 2 * FormMetrics.ROW_PAD_H, height - 2 * FormMetrics.ROW_PAD_V) }
}

/** Buttons side by side from the leading edge (the log's pair, Quit, Pair a Device…). */
class ButtonsRow(vararg val buttons: PushButton) : FormRow() {
    init { buttons.forEach { add(it) } }
    override fun heightFor(width: Int) = maxOf(FormMetrics.ROW_MIN, buttons.maxOf { it.preferredSize.height } + 2 * FormMetrics.ROW_PAD_V)
    override fun doLayout() {
        var x = FormMetrics.ROW_PAD_H
        for (b in buttons) { val d = b.preferredSize; b.setBounds(x, (height - d.height) / 2, d.width, d.height); x += d.width + 8 }
    }
}

/** One Section: an optional header, its box of rows, an optional footnote (or warning). */
class FormSection(val header: String?, val rows: List<FormRow>, val footer: WrapText? = null) : JComponent() {
    private val headerFont = MacType.font(MacType.headline)
    init { isOpaque = false; rows.forEach { add(it) }; footer?.let { add(it) } }
    private fun headerHeight() = header?.let { kotlin.math.ceil(TextMeasure.lineHeight(headerFont)).toInt() + FormMetrics.GAP } ?: 0
    fun heightFor(width: Int): Int {
        var h = headerHeight() + rows.sumOf { it.heightFor(width) }
        if (rows.isEmpty()) h += 0
        footer?.let { h += FormMetrics.GAP + it.heightFor(width - 2 * FormMetrics.ROW_PAD_H) }
        return h
    }
    override fun doLayout() {
        var y = headerHeight()
        for (r in rows) { val h = r.heightFor(width); r.setBounds(0, y, width, h); y += h }
        footer?.let { val h = it.heightFor(width - 2 * FormMetrics.ROW_PAD_H); it.setBounds(FormMetrics.ROW_PAD_H, y + FormMetrics.GAP, width - 2 * FormMetrics.ROW_PAD_H, h) }
    }
    override fun paintComponent(g0: Graphics) {
        val g = SillSwing.smooth(g0)
        val c = HostTheme.c
        header?.let { SillSwing.text(g, it, FormMetrics.ROW_PAD_H.toDouble(), 0.0, headerFont, c.label) }
        if (rows.isNotEmpty()) {
            val top = headerHeight().toDouble()
            val bottom = rows.last().let { it.y + it.height }.toDouble()
            val box = RoundRectangle2D.Double(0.5, top + 0.5, width - 1.0, bottom - top - 1.0, FormMetrics.RADIUS * 2, FormMetrics.RADIUS * 2)
            g.color = c.groupBox.awt(); g.fill(box)
            if (c.groupStroke.alpha > 0) { g.color = c.groupStroke.awt(); g.draw(box) }
            g.color = c.separator.awt()
            for (r in rows.dropLast(1)) g.fill(Rectangle2D.Double(FormMetrics.ROW_PAD_H.toDouble(), (r.y + r.height).toDouble() - 0.5, width - 2.0 * FormMetrics.ROW_PAD_H, 1.0))
        }
        g.dispose()
    }
}

/** A pane: its sections down a fixed width, 20 pt from the edges and between sections. */
class FormPage(val pageWidth: Int = 520) : JComponent() {
    val sections = ArrayList<FormSection>()
    init { isOpaque = true; layout = null }
    fun section(header: String? = null, footer: WrapText? = null, vararg rows: FormRow): FormSection =
        FormSection(header, rows.toList(), footer).also { sections += it; add(it) }
    fun clear() { sections.clear(); removeAll() }
    private val inner get() = pageWidth - 2 * FormMetrics.MARGIN
    fun pageHeight() = FormMetrics.MARGIN * 2 + sections.sumOf { it.heightFor(inner) } + FormMetrics.SECTION_GAP * maxOf(0, sections.size - 1)
    override fun getPreferredSize() = Dimension(pageWidth, pageHeight())
    override fun doLayout() {
        var y = FormMetrics.MARGIN
        for (s in sections) { val h = s.heightFor(inner); s.setBounds(FormMetrics.MARGIN, y, inner, h); y += h + FormMetrics.SECTION_GAP }
    }
    override fun paintComponent(g: Graphics) { g.color = HostTheme.c.window.awt(); g.fillRect(0, 0, width, height) }
}

fun footnote(text: String) = WrapText(text, MacType.font(MacType.footnote), { HostTheme.c.secondary })
fun footWarning(text: String) = WrapText(text, MacType.font(MacType.footnote), { HostTheme.c.orange }, warning = true)

/** Shared focus ring and keyboard activation of the custom controls. */
abstract class MacControl : JComponent() {
    var enabledState = true; set(v) { field = v; isEnabled = v; cursor = if (v) Cursor.getPredefinedCursor(Cursor.HAND_CURSOR) else Cursor.getDefaultCursor(); repaint() }
    protected var pressed = false
    init {
        isOpaque = false; isFocusable = true
        cursor = Cursor.getPredefinedCursor(Cursor.HAND_CURSOR)
        val m = object : MouseAdapter() {
            override fun mousePressed(e: MouseEvent) { if (enabledState) { pressed = true; requestFocusInWindow(); repaint() } }
            override fun mouseReleased(e: MouseEvent) { if (pressed) { pressed = false; repaint(); if (contains(e.point)) press(e.point) } }
        }
        addMouseListener(m)
        addKeyListener(object : KeyAdapter() { override fun keyPressed(e: KeyEvent) { if (enabledState && (e.keyCode == KeyEvent.VK_SPACE || e.keyCode == KeyEvent.VK_ENTER)) press(null) } })
        addFocusListener(object : FocusAdapter() { override fun focusGained(e: FocusEvent) = repaint(); override fun focusLost(e: FocusEvent) = repaint() })
    }
    abstract fun press(at: Point?)
    protected fun focusRing(g: Graphics2D, shape: java.awt.Shape) {
        if (!isFocusOwner) return
        g.color = HostTheme.c.accent.opacity(0.5).awt(); g.stroke = java.awt.BasicStroke(3f); g.draw(shape)
    }
}

/** A Toggle in a grouped Form: a switch, the accent colour when on, its knob sliding (0.15 s ease-out). */
class MacSwitch(on: Boolean, private val onChange: (Boolean) -> Unit) : MacControl() {
    companion object { const val W = 32; const val H = 18 }
    var on = on; private set
    private val knob = Animated(if (on) 1.0 else 0.0, this)
    init { preferredSize = Dimension(W + 4, H + 4) }
    fun set(value: Boolean) { if (value != on) { on = value; knob.animate(if (on) 1.0 else 0.0, Curve.EaseOut(0.15)) } }
    override fun press(at: Point?) { set(!on); onChange(on) }
    override fun paintComponent(g0: Graphics) {
        val g = SillSwing.smooth(g0)
        val c = HostTheme.c
        val track = RoundRectangle2D.Double(2.0, 2.0, W.toDouble(), H.toDouble(), H.toDouble(), H.toDouble())
        val k = knob.value
        g.color = if (k > 0.5) c.accent.awt() else c.switchOff.awt()
        if (!enabledState) g.composite = java.awt.AlphaComposite.getInstance(java.awt.AlphaComposite.SRC_OVER, 0.45f)
        g.fill(track)
        val d = H - 2.0
        val x = 3.0 + (W - d - 2) * k
        g.color = Rgba.black.opacity(0.2).awt(); g.fill(Ellipse2D.Double(x, 3.5, d, d))
        g.color = c.knob.awt(); g.fill(Ellipse2D.Double(x, 3.0, d, d))
        focusRing(g, track)
        g.dispose()
    }
}

/** A push button (Button in a Form): macOS 26's filled rounded rectangle, no hairline, 13 pt text, 24 pt tall. */
class PushButton(var title: String, private val action: () -> Unit) : MacControl() {
    private val font = MacType.font(MacType.body)
    var isDefault = false
    init { preferredSize = Dimension(kotlin.math.ceil(TextMeasure.width(title, font)).toInt() + 24, 24) }
    override fun press(at: Point?) = action()
    override fun paintComponent(g0: Graphics) {
        val g = SillSwing.smooth(g0)
        val c = HostTheme.c
        val r = RoundRectangle2D.Double(1.0, 1.0, width - 2.0, height - 2.0, 11.0, 11.0)
        g.color = (if (isDefault) c.accent else if (pressed) c.control.opacity(minOf(1.0, c.control.alpha * 1.8)) else c.control).awt(); g.fill(r)
        if (!isDefault && c.controlStroke.alpha > 0) { g.color = c.controlStroke.awt(); g.draw(r) }
        val col = if (!enabledState) c.tertiary else if (isDefault) c.onAccent else c.label
        SillSwing.centred(g, title, me.saffer.sill.core.ui.Rect(0.0, 0.0, width.toDouble(), height.toDouble()), (height - TextMeasure.lineHeight(font)) / 2, font, col)
        focusRing(g, r)
        g.dispose()
    }
}

/** A Picker in a Form (`.menu` style): its value and the up-down chevrons, opening a menu of its choices with the current one checked. */
class PopUpButton(private var choices: List<Pair<String, Any>>, var selected: Any, private val onPick: (Any) -> Unit) : MacControl() {
    private val font = MacType.font(MacType.body)
    init { resize() }
    private fun title() = choices.firstOrNull { it.second == selected }?.first ?: ""
    private fun resize() { preferredSize = Dimension(kotlin.math.ceil(choices.maxOf { TextMeasure.width(it.first, font) }).toInt() + 30, 22) }
    fun update(choices: List<Pair<String, Any>>, selected: Any) { this.choices = choices; this.selected = selected; resize(); revalidate(); repaint() }
    override fun press(at: Point?) {
        val entries = choices.mapIndexed { i, (t, v) -> MenuEntry(MenuEntry.Kind.ITEM, t, checked = v == selected, action = MenuAction.Choose(i)) }
        val pop = MenuPopup(entries, null, { a -> (a as? MenuAction.Choose)?.let { val v = choices[it.index].second; selected = v; repaint(); onPick(v) } })
        val p = Point(0, 0); SwingUtilities.convertPointToScreen(p, this)
        val i = choices.indexOfFirst { it.second == selected }.coerceAtLeast(0)
        pop.fit()
        // Over the button, the current choice on top of its title, as an NSPopUpButton's menu opens.
        pop.setLocation(p.x - MenuView.INSET.toInt() - MenuView.GUTTER.toInt() + 6, p.y - MenuView.INSET.toInt() - i * MenuView.ROW.toInt())
        pop.isVisible = true; pop.view.requestFocusInWindow()
    }
    override fun paintComponent(g0: Graphics) {
        val g = SillSwing.smooth(g0)
        val c = HostTheme.c
        val t = title()
        val w = TextMeasure.width(t, font)
        val x = width - 18 - w
        SillSwing.text(g, t, x, (height - TextMeasure.lineHeight(font)) / 2, font, if (enabledState) c.label else c.tertiary)
        HostGlyphs.paint(g, Symbol.ChevronUp, width - 13.0, height / 2.0 - 7.5, 8.0, c.secondary)
        HostGlyphs.paint(g, Symbol.ChevronDown, width - 13.0, height / 2.0 - 0.5, 8.0, c.secondary)
        focusRing(g, RoundRectangle2D.Double(x - 4, 1.0, width - x + 3, height - 2.0, 8.0, 8.0))
        g.dispose()
    }
}

/** A segmented Picker (Frame rate limit: 60 fps | 120 fps). */
class Segmented(private val choices: List<Pair<String, Any>>, var selected: Any, private val onPick: (Any) -> Unit) : MacControl() {
    private val font = MacType.font(MacType.body)
    private val seg = kotlin.math.ceil(choices.maxOf { TextMeasure.width(it.first, font) }).toInt() + 22
    init { preferredSize = Dimension(seg * choices.size + 2, 24) }
    fun select(v: Any) { selected = v; repaint() }
    override fun press(at: Point?) {
        val i = if (at != null) ((at.x - 1) / seg).coerceIn(0, choices.size - 1) else (choices.indexOfFirst { it.second == selected } + 1) % choices.size
        selected = choices[i].second; repaint(); onPick(selected)
    }
    override fun paintComponent(g0: Graphics) {
        val g = SillSwing.smooth(g0)
        val c = HostTheme.c
        val r = RoundRectangle2D.Double(1.0, 1.0, width - 2.0, height - 2.0, 12.0, 12.0)
        g.color = c.switchOff.awt(); g.fill(r)
        choices.forEachIndexed { i, (t, v) ->
            val sr = me.saffer.sill.core.ui.Rect(1.0 + i * seg, 1.0, seg.toDouble(), height - 2.0)
            if (v == selected) {
                g.color = (if (c.dark) Rgba.white.opacity(0.3) else Rgba.white).awt()
                g.fill(RoundRectangle2D.Double(sr.x + 1.5, sr.y + 1.5, sr.width - 3, sr.height - 3, 9.0, 9.0))
            } else if (i > 0 && choices[i - 1].second != selected) {
                g.color = c.separator.awt(); g.fill(Rectangle2D.Double(sr.x - 0.5, 6.0, 1.0, height - 12.0))
            }
            SillSwing.centred(g, t, sr, (height - TextMeasure.lineHeight(font)) / 2, font, c.label)
        }
        focusRing(g, r)
        g.dispose()
    }
}

/** Plain or secondary text at a row's trailing edge (LabeledContent's value), cut in the middle. */
class ValueText(var text: String, private val maxWidth: Int = 300) : JComponent() {
    private val font = MacType.font(MacType.body)
    init { isOpaque = false; preferredSize = Dimension(minOf(maxWidth, kotlin.math.ceil(TextMeasure.width(text, font)).toInt() + 2), 18) }
    override fun paintComponent(g0: Graphics) {
        val g = SillSwing.smooth(g0)
        val t = TextMeasure.fit(text, font, width.toDouble(), middle = true)
        SillSwing.text(g, t, width - TextMeasure.width(t, font), (height - TextMeasure.lineHeight(font)) / 2, font, HostTheme.c.secondary)
        g.dispose()
    }
}
