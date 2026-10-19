package me.saffer.sill.host.ui

import me.saffer.sill.core.ui.Symbol
import me.saffer.sill.host.HostPresentation
import me.saffer.sill.host.MenuAction
import me.saffer.sill.host.MenuEntry
import me.saffer.sill.swingui.SillSwing
import java.awt.Color
import java.awt.Dimension
import java.awt.Font
import java.awt.FontMetrics
import java.awt.Graphics
import java.awt.Graphics2D
import java.awt.GraphicsEnvironment
import java.awt.Point
import java.awt.Rectangle
import java.awt.Window
import java.awt.event.KeyAdapter
import java.awt.event.KeyEvent
import java.awt.event.MouseAdapter
import java.awt.event.MouseEvent
import java.awt.event.WindowAdapter
import java.awt.event.WindowEvent
import java.awt.geom.RoundRectangle2D
import java.awt.image.BufferedImage
import javax.swing.JComponent
import javax.swing.JDialog
import javax.swing.SwingUtilities
import javax.swing.Timer

/** Text measured and wrapped the same way for layout and for painting. */
object TextMeasure {
    private val scratch: Graphics2D by lazy { SillSwing.smooth(BufferedImage(1, 1, BufferedImage.TYPE_INT_ARGB).graphics) }
    fun metrics(f: Font): FontMetrics = synchronized(scratch) { scratch.getFontMetrics(f) }
    fun width(s: String, f: Font): Double = synchronized(scratch) { f.getStringBounds(s, scratch.fontRenderContext).width }

    /** Words wrapped to `width` (a word longer than the width is cut), as a multi-line Text lays out. */
    fun wrap(text: String, f: Font, width: Double): List<String> {
        val out = ArrayList<String>()
        for (para in text.split("\n")) {
            var line = ""
            for (word in para.split(" ")) {
                val next = if (line.isEmpty()) word else "$line $word"
                if (width(next, f) <= width || line.isEmpty()) line = next
                else { out += line; line = word }
            }
            out += line
        }
        return out
    }

    /** One line, cut in the middle (`.truncationMode(.middle)`) or at the end. */
    fun fit(s: String, f: Font, width: Double, middle: Boolean = false): String = SillSwing.fit(metrics(f), s, width, middle)
    fun lineHeight(f: Font): Double = metrics(f).height.toDouble()
}

/**
 * The status menu's card (StatusCard.swift): the header in headline and its explanation in
 * subheadline, then what streams and each device, each row a symbol in a 16 pt column, its title on
 * one line cut in the middle, and its detail in caption under it. 300 pt wide, 14 pt in from the
 * sides and 6 pt from the top and bottom, 8 pt between blocks.
 */
class StatusCardLayout(val p: HostPresentation) {
    companion object {
        const val WIDTH = 300.0
        const val PAD_H = 14.0
        const val PAD_V = 6.0
        const val SPACING = 8.0
        const val SYMBOL = 16.0
    }
    private val inner = WIDTH - 2 * PAD_H
    val headFont = MacType.font(MacType.headline)
    val subFont = MacType.font(MacType.subheadline)
    val titleFont = MacType.font(MacType.body)
    val detailFont = MacType.font(MacType.caption)
    val subLines = p.subtitle?.let { TextMeasure.wrap(it, subFont, inner) } ?: emptyList()
    val rows = listOfNotNull(p.source) + p.devices
    val detailLines = rows.map { r -> r.detail?.let { TextMeasure.wrap(it, detailFont, inner - SYMBOL - 8) } ?: emptyList() }

    val height: Double get() {
        var h = PAD_V + TextMeasure.lineHeight(headFont)
        if (subLines.isNotEmpty()) h += 2 + subLines.size * TextMeasure.lineHeight(subFont)
        for (d in detailLines) h += SPACING + TextMeasure.lineHeight(titleFont) + if (d.isEmpty()) 0.0 else 1 + d.size * TextMeasure.lineHeight(detailFont)
        return h + PAD_V
    }

    fun paint(g: Graphics2D, x: Double, y0: Double) {
        val c = HostTheme.c
        var y = y0 + PAD_V
        SillSwing.text(g, p.header, x + PAD_H, y, headFont, c.label)
        y += TextMeasure.lineHeight(headFont)
        if (subLines.isNotEmpty()) {
            y += 2
            for (l in subLines) { SillSwing.text(g, l, x + PAD_H, y, subFont, c.secondary); y += TextMeasure.lineHeight(subFont) }
        }
        rows.forEachIndexed { i, r ->
            y += SPACING
            val th = TextMeasure.lineHeight(titleFont)
            // The symbol on the title's first baseline, as `.firstTextBaseline` aligns them.
            val box = 15.0
            HostGlyphs.paint(g, HostGlyphs.row(r.symbol), x + PAD_H + (SYMBOL - box) / 2, y + (th - box) / 2, box, c.secondary)
            val tx = x + PAD_H + SYMBOL + 8
            SillSwing.text(g, TextMeasure.fit(r.title, titleFont, inner - SYMBOL - 8, middle = true), tx, y, titleFont, c.label)
            y += th
            if (detailLines[i].isNotEmpty()) {
                y += 1
                for (l in detailLines[i]) { SillSwing.text(g, l, tx, y, detailFont, c.secondary); y += TextMeasure.lineHeight(detailFont) }
            }
        }
    }
}

/**
 * The status menu (NSMenu, as StatusItemController builds it from MenuBuilder's entries), drawn as
 * macOS draws it: the card on top, 22 pt rows with a checkmark column, subtitles under titles (macOS
 * 14.4's), submenus with their chevron, the shortcut at the trailing edge, 11 pt separators, and the
 * hovered row in the accent colour inset 5 pt with 4 pt corners. Arrow keys move, Return or a click
 * acts, Esc closes.
 */
class MenuView(entries: List<MenuEntry>, private val presentation: HostPresentation?, private val onAction: (MenuAction) -> Unit) : JComponent() {
    companion object {
        const val INSET = 5.0
        const val ROW = 22.0
        const val ROW_SUBTITLED = 36.0
        const val SEPARATOR = 11.0
        const val GUTTER = 22.0
        const val TRAILING = 14.0
    }

    var entries: List<MenuEntry> = entries; private set
    private var card: StatusCardLayout? = presentation?.let(::StatusCardLayout)
    var hovered = -1; private set
    var popup: MenuPopup? = null
    /** The open submenu when this menu is not in a popup (the window shown when there is no tray). */
    private var ownChild: MenuPopup? = null
    private val child get() = popup?.child ?: ownChild
    private val titleFont = MacType.font(MacType.body)
    private val subFont = MacType.font(MacType.subheadline)
    private val keyFont = MacType.font(MacType.body)
    private var rects: List<Rectangle> = emptyList()
    private var openTimer: Timer? = null

    init {
        isOpaque = false
        isFocusable = true
        relayout()
        val mouse = object : MouseAdapter() {
            override fun mouseMoved(e: MouseEvent) = hover(indexAt(e.point), fromMouse = true)
            override fun mouseExited(e: MouseEvent) { if (child == null) hover(-1, fromMouse = true) }
            override fun mouseReleased(e: MouseEvent) { val i = indexAt(e.point); if (i >= 0) activate(i) }
        }
        addMouseListener(mouse); addMouseMotionListener(mouse)
        addKeyListener(object : KeyAdapter() {
            override fun keyPressed(e: KeyEvent) {
                when (e.keyCode) {
                    KeyEvent.VK_DOWN -> step(1)
                    KeyEvent.VK_UP -> step(-1)
                    KeyEvent.VK_RIGHT -> if (hovered >= 0 && this@MenuView.entries[hovered].children.isNotEmpty()) openSubmenu(hovered, focus = true)
                    KeyEvent.VK_LEFT -> popup?.let { p -> if (p.parentPopup != null) p.close() }
                    KeyEvent.VK_ENTER, KeyEvent.VK_SPACE -> if (hovered >= 0) activate(hovered)
                    KeyEvent.VK_ESCAPE -> popup?.closeAll()
                }
            }
        })
    }

    /** New entries and card (the host's status changed while the menu shows), keeping the hovered row. */
    fun update(entries: List<MenuEntry>, presentation: HostPresentation?) {
        this.entries = entries
        card = presentation?.let(::StatusCardLayout)
        relayout(); revalidate(); repaint()
        popup?.fit()
    }

    private fun relayout() {
        val w = width()
        var y = INSET
        val out = ArrayList<Rectangle>()
        for (e in entries) {
            val h = when (e.kind) {
                MenuEntry.Kind.CARD -> card?.height ?: 0.0
                MenuEntry.Kind.SEPARATOR -> SEPARATOR
                MenuEntry.Kind.ITEM -> if (e.subtitle != null) ROW_SUBTITLED else ROW
            }
            out += Rectangle(0, y.toInt(), w.toInt(), h.toInt())
            y += h.toInt()
        }
        rects = out
        preferredSize = Dimension(w.toInt(), (y + INSET).toInt())
        size = preferredSize
    }

    /** As wide as the card, or the widest row: title or subtitle, then the shortcut or the chevron. */
    private fun width(): Double {
        var w = if (entries.any { it.kind == MenuEntry.Kind.CARD }) StatusCardLayout.WIDTH else 160.0
        for (e in entries.filter { it.kind == MenuEntry.Kind.ITEM }) {
            val text = maxOf(TextMeasure.width(e.title, titleFont), e.subtitle?.let { TextMeasure.width(it, subFont) } ?: 0.0)
            val trail = e.shortcut?.let { TextMeasure.width(it, keyFont) + 24 } ?: if (e.children.isNotEmpty()) 24.0 else 0.0
            w = maxOf(w, INSET + GUTTER + text + trail + TRAILING + INSET)
        }
        return kotlin.math.ceil(w)
    }

    fun rowRect(i: Int): Rectangle = rects[i]
    fun indexOfTitle(title: String) = entries.indexOfFirst { it.title == title && it.kind == MenuEntry.Kind.ITEM }
    private fun indexAt(p: Point) = rects.indexOfFirst { it.contains(p) }.takeIf { it >= 0 && selectable(it) } ?: -1
    private fun selectable(i: Int) = entries[i].kind == MenuEntry.Kind.ITEM && entries[i].enabled

    private fun step(d: Int) {
        var i = hovered
        repeat(entries.size) { i = (i + d + entries.size) % entries.size; if (selectable(i)) { hover(i, fromMouse = false); return } }
    }

    fun hover(i: Int, fromMouse: Boolean) {
        if (i == hovered) return
        hovered = i
        repaint()
        openTimer?.stop()
        if (i >= 0 && entries[i].children.isNotEmpty()) {
            // A submenu opens after a moment under the pointer, as AppKit's does.
            if (fromMouse) openTimer = Timer(180) { openSubmenu(i, focus = false) }.apply { isRepeats = false; start() }
        } else if (i >= 0) child?.close()
    }

    fun activate(i: Int) {
        val e = entries[i]
        if (!e.enabled) return
        if (e.children.isNotEmpty()) { openSubmenu(i, focus = true); return }
        child?.close()
        popup?.closeAll()
        onAction(e.action)
    }

    private fun openSubmenu(i: Int, focus: Boolean) {
        val p = popup
        if (child?.anchor == i && child?.isVisible == true) return
        child?.close()
        val r = rects[i]
        val origin = Point(width - INSET.toInt(), r.y - INSET.toInt())
        SwingUtilities.convertPointToScreen(origin, this)
        val sub = MenuPopup(entries[i].children, null, onAction, parentPopup = p, anchor = i)
        if (p != null) p.child = sub else { ownChild = sub; sub.onClosed = { if (ownChild === sub) ownChild = null } }
        val left = Point(0, 0); SwingUtilities.convertPointToScreen(left, this)
        sub.showAt(origin, preferLeftOf = left.x)
        if (focus) sub.view.step(1)
    }

    /** Draw the menu's own material (rounded, with its hairline) under the rows, when no popup does. */
    var material = false

    override fun paintComponent(g0: Graphics) {
        val g = SillSwing.smooth(g0)
        val c = HostTheme.c
        if (material) {
            val shape = RoundRectangle2D.Double(0.5, 0.5, width - 1.0, height - 1.0, 20.0, 20.0)
            g.color = c.menu.awt(); g.fill(shape); g.color = c.menuStroke.awt(); g.draw(shape)
        }
        entries.forEachIndexed { i, e ->
            val r = rects[i]
            when (e.kind) {
                MenuEntry.Kind.CARD -> card?.paint(g, 0.0, r.y.toDouble())
                MenuEntry.Kind.SEPARATOR -> { g.color = c.separator.awt(); g.fill(java.awt.geom.Rectangle2D.Double(10.0, r.y + SEPARATOR / 2 - 0.5, width - 20.0, 1.0)) }
                MenuEntry.Kind.ITEM -> paintItem(g, e, r, i == hovered)
            }
        }
        g.dispose()
    }

    private fun paintItem(g: Graphics2D, e: MenuEntry, r: Rectangle, lit: Boolean) {
        val c = HostTheme.c
        if (lit) { g.color = c.accent.awt(); g.fill(RoundRectangle2D.Double(INSET, r.y.toDouble(), width - 2 * INSET, r.height.toDouble(), 8.0, 8.0)) }
        val text = when { lit -> c.onAccent; e.enabled -> c.label; else -> c.tertiary }
        val sub = when { lit -> c.onAccent.opacity(0.8); e.enabled -> c.secondary; else -> c.tertiary }
        val th = TextMeasure.lineHeight(titleFont)
        val ty = r.y + if (e.subtitle != null) 4.0 else (r.height - th) / 2
        val gutterX = INSET + 4
        when {
            e.attention -> HostGlyphs.paint(g, Symbol.Warning, gutterX, ty + (th - 13) / 2, 13.0, if (lit) c.onAccent else c.orange, if (lit) c.accent else c.menu)
            e.checked -> HostGlyphs.paint(g, HostGlyphs.check, gutterX, ty + (th - 12) / 2, 12.0, text)
        }
        SillSwing.text(g, e.title, INSET + GUTTER, ty, titleFont, text)
        e.subtitle?.let { SillSwing.text(g, it, INSET + GUTTER, ty + th, subFont, sub) }
        val right = width - INSET - 10
        if (e.children.isNotEmpty()) HostGlyphs.paint(g, Symbol.ChevronRight, right - 10, ty + (th - 10) / 2, 10.0, text)
        e.shortcut?.let { s -> val w = TextMeasure.width(s, keyFont); SillSwing.text(g, s, right - w, ty, keyFont, if (lit) c.onAccent else c.secondary) }
    }
}

/**
 * The menu in a window of its own beside the tray icon: borderless, on top, rounded (10 pt, the
 * menu's material with its hairline), closed when it loses focus to anything but its own submenu,
 * by Esc, or when an item acts.
 */
class MenuPopup(entries: List<MenuEntry>, presentation: HostPresentation?, onAction: (MenuAction) -> Unit,
                val parentPopup: MenuPopup? = null, val anchor: Int = -1) : JDialog(parentPopup) {
    val view = MenuView(entries, presentation, onAction)
    var child: MenuPopup? = null
    var onClosed: () -> Unit = {}
    private val translucent = GraphicsEnvironment.getLocalGraphicsEnvironment().defaultScreenDevice
        .isWindowTranslucencySupported(java.awt.GraphicsDevice.WindowTranslucency.PERPIXEL_TRANSLUCENT)

    init {
        view.popup = this
        isUndecorated = true
        focusableWindowState = true
        isAlwaysOnTop = true
        type = Window.Type.POPUP
        if (translucent) background = Color(0, 0, 0, 0)
        contentPane = object : JComponent() {
            override fun paintComponent(g0: Graphics) {
                val g = SillSwing.smooth(g0)
                val c = HostTheme.c
                val shape = RoundRectangle2D.Double(0.5, 0.5, width - 1.0, height - 1.0, 20.0, 20.0)
                g.color = c.menu.awt(); g.fill(shape)
                g.color = c.menuStroke.awt(); g.draw(shape)
                g.dispose()
            }
        }.apply { layout = null; add(view) }
        addWindowFocusListener(object : WindowAdapter() {
            override fun windowLostFocus(e: WindowEvent) {
                val to = e.oppositeWindow
                if (to is MenuPopup && to.root() === root()) return
                SwingUtilities.invokeLater { if (!root().anyFocused()) root().closeAll() }
            }
        })
    }

    private fun root(): MenuPopup = parentPopup?.root() ?: this
    private fun anyFocused(): Boolean = isFocused || child?.anyFocused() == true

    fun fit() {
        val d = view.preferredSize
        view.setBounds(0, 0, d.width, d.height)
        setSize(d.width, d.height)
        if (!translucent) shape = RoundRectangle2D.Double(0.0, 0.0, d.width.toDouble(), d.height.toDouble(), 20.0, 20.0)
    }

    /**
     * Shown with a corner at `p`: above and to the left of a tray icon at the screen's bottom right
     * (Windows' taskbar), below it at the top (GNOME's), always inside the screen's usable area.
     */
    fun showAt(p: Point, preferLeftOf: Int? = null) {
        fit()
        val gc = GraphicsEnvironment.getLocalGraphicsEnvironment().screenDevices.map { it.defaultConfiguration }
            .firstOrNull { it.bounds.contains(p) } ?: graphicsConfiguration
        val insets = java.awt.Toolkit.getDefaultToolkit().getScreenInsets(gc)
        val b = gc.bounds
        val area = Rectangle(b.x + insets.left, b.y + insets.top, b.width - insets.left - insets.right, b.height - insets.top - insets.bottom)
        var x = if (parentPopup != null) p.x else p.x - width / 2
        var y = if (parentPopup != null) p.y else if (p.y > area.centerY) p.y - height else p.y
        if (x + width > area.maxX) x = if (parentPopup != null && preferLeftOf != null) preferLeftOf - width + MenuView.INSET.toInt() else area.maxX.toInt() - width
        x = x.coerceAtLeast(area.x); y = y.coerceIn(area.y, maxOf(area.y, area.maxY.toInt() - height))
        setLocation(x, y)
        isVisible = true
        toFront()
        view.requestFocusInWindow()
    }

    fun close() {
        child?.close(); child = null
        parentPopup?.let { if (it.child === this) it.child = null }
        isVisible = false
        dispose()
        onClosed()
    }

    fun closeAll() = root().close()
}
