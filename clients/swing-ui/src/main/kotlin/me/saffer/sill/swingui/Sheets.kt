package me.saffer.sill.swingui

import me.saffer.sill.core.ui.Copy
import me.saffer.sill.core.ui.Motion
import me.saffer.sill.core.ui.Palette
import me.saffer.sill.core.ui.Rect
import me.saffer.sill.core.ui.Rgba
import me.saffer.sill.core.ui.Symbol
import me.saffer.sill.core.ui.Type
import me.saffer.sill.core.ui.Ui
import java.awt.Dimension
import java.awt.Graphics
import java.awt.Graphics2D
import java.awt.event.KeyEvent
import java.awt.event.MouseAdapter
import java.awt.event.MouseEvent
import java.awt.image.BufferedImage
import javax.accessibility.AccessibleRole
import javax.swing.AbstractAction
import javax.swing.JComponent
import javax.swing.KeyStroke
import javax.swing.event.DocumentEvent
import javax.swing.event.DocumentListener

/** One line of a [RowList]: a section header, or a row (DrawerRow in StreamScreen.swift). */
sealed class ListItem {
    data class Header(val title: String, val extraTop: Double = 0.0) : ListItem()
    /**
     * `key` names it to the owner; `icon` the app's picture, else `badge` (a symbol on iconFallback,
     * the connect screen's Macs) or the name's first two letters.
     */
    data class Row(val key: String, val title: String, val trailing: String?, val height: Double, val highlighted: Boolean,
                   val icon: BufferedImage? = null, val badge: Symbol? = null, val tooltip: String? = null) : ListItem()
}

/**
 * Rows as the iOS app's drawer and connect screen draw them (DrawerRow): a 32 pt icon with corners
 * 9, the title in 15 pt, a trailing word in 13 pt muted that never truncates (the title does), rows
 * 6 apart, the highlighted one (and the one under the pointer, the desktop's own) on the control
 * colour with corners 10; headers in 13 pt medium muted. A click picks, a right-click asks for the
 * row's menu; Up and Down move a keyboard focus, Enter picks.
 */
class RowList : SillComponent(), HeightForWidth, javax.swing.Scrollable {
    var items: List<ListItem> = emptyList()
        set(v) { field = v; if (focus >= rows().size) focus = rows().size - 1; revalidate(); repaint() }
    var onPick: (String) -> Unit = {}
    var onMenu: (String, MouseEvent) -> Unit = { _, _ -> }
    var spacing = 6.0
    private var hover: String? = null
    private var focus = -1

    init {
        isOpaque = false
        isFocusable = true
        isRequestFocusEnabled = false
        val m = object : MouseAdapter() {
            override fun mouseMoved(e: MouseEvent) {
                val k = rowAt(e.y.toDouble())?.key
                if (k != hover) { hover = k; repaint() }
                toolTipText = rowAt(e.y.toDouble())?.tooltip
            }
            override fun mouseExited(e: MouseEvent) { hover = null; repaint() }
            override fun mouseReleased(e: MouseEvent) {
                val r = rowAt(e.y.toDouble()) ?: return
                if (e.isPopupTrigger || e.button == MouseEvent.BUTTON3) onMenu(r.key, e)
                else if (e.button == MouseEvent.BUTTON1 && contains(e.x, e.y)) onPick(r.key)
            }
            override fun mousePressed(e: MouseEvent) { if (e.isPopupTrigger) rowAt(e.y.toDouble())?.let { onMenu(it.key, e) } }
        }
        addMouseListener(m); addMouseMotionListener(m)
        fun key(k: Int, n: String, f: () -> Unit) { inputMap.put(KeyStroke.getKeyStroke(k, 0), n); actionMap.put(n, object : AbstractAction() { override fun actionPerformed(e: java.awt.event.ActionEvent) = f() }) }
        key(KeyEvent.VK_UP, "up") { moveFocus(-1) }
        key(KeyEvent.VK_DOWN, "down") { moveFocus(1) }
        key(KeyEvent.VK_ENTER, "pick") { rows().getOrNull(focus)?.let { onPick(it.key) } }
        key(KeyEvent.VK_SPACE, "pick2") { rows().getOrNull(focus)?.let { onPick(it.key) } }
        addFocusListener(object : java.awt.event.FocusAdapter() {
            override fun focusGained(e: java.awt.event.FocusEvent) { keyboardFocus = e.cause.name.startsWith("TRAVERSAL"); if (focus < 0 && rows().isNotEmpty()) focus = 0; repaint() }
            override fun focusLost(e: java.awt.event.FocusEvent) { keyboardFocus = false; repaint() }
        })
    }

    /** The focus ring shows only when the keyboard brought the focus here, or moves in the list. */
    private var keyboardFocus = false

    private fun rows() = items.filterIsInstance<ListItem.Row>()
    private fun moveFocus(d: Int) {
        val n = rows().size
        if (n == 0) return
        focus = (focus + d).coerceIn(0, n - 1)
        keyboardFocus = true
        frames().firstOrNull { it.first == rows()[focus] }?.second?.let { scrollRectToVisible(java.awt.Rectangle(0, it.y.toInt(), width, it.height.toInt())) }
        repaint()
    }

    private fun headerHeight(h: ListItem.Header): Double {
        val fm = getFontMetrics(SillSwing.font(Type.sectionHeader))
        return 10 + h.extraTop + fm.ascent + fm.descent + 2.0
    }

    /** Each line and its frame. */
    fun frames(): List<Pair<ListItem, Rect>> {
        var y = 0.0
        return items.mapIndexed { i, it ->
            val h = when (it) { is ListItem.Header -> headerHeight(it); is ListItem.Row -> it.height }
            val r = Rect(0.0, y, width.toDouble(), h)
            y += h + if (i < items.size - 1) spacing else 0.0
            it to r
        }
    }

    /** A row's frame by its key (tests, and the owner's menus). */
    fun rowBounds(key: String) = frames().firstOrNull { (it.first as? ListItem.Row)?.key == key }?.second

    private fun rowAt(y: Double) = frames().firstOrNull { it.first is ListItem.Row && y >= it.second.y && y < it.second.maxY }?.first as ListItem.Row?

    override fun heightFor(width: Int): Int {
        var h = 0.0
        items.forEachIndexed { i, it -> h += (when (it) { is ListItem.Header -> headerHeight(it); is ListItem.Row -> it.height }) + if (i < items.size - 1) spacing else 0.0 }
        return Math.ceil(h).toInt()
    }
    override fun getPreferredSize() = Dimension(width.coerceAtLeast(1), heightFor(width))
    override fun getPreferredScrollableViewportSize(): Dimension = preferredSize
    override fun getScrollableUnitIncrement(visibleRect: java.awt.Rectangle, orientation: Int, direction: Int) = 24
    override fun getScrollableBlockIncrement(visibleRect: java.awt.Rectangle, orientation: Int, direction: Int) = visibleRect.height - 24
    override fun getScrollableTracksViewportWidth() = true
    override fun getScrollableTracksViewportHeight() = false

    override fun paintComponent(g0: Graphics) {
        val g = SillSwing.smooth(g0)
        val scale = SillSwing.deviceScale(this)
        val title = SillSwing.font(Type.rowTitle)
        val trail = SillSwing.font(Type.rowTrailing)
        val head = SillSwing.font(Type.sectionHeader)
        val focused = if (isFocusOwner && keyboardFocus) rows().getOrNull(focus) else null
        for ((item, r) in frames()) {
            if (!g.clipBounds.let { it == null || it.intersects(r.x, r.y, r.width, r.height) }) continue
            when (item) {
                is ListItem.Header -> SillSwing.text(g, item.title, 10.0, r.y + 10 + item.extraTop, head, Palette.muted)
                is ListItem.Row -> {
                    val lit = item.highlighted || item.key == hover
                    if (lit) SillSwing.fill(g, r, Ui.rowRadius, if (item.highlighted) Palette.control else Palette.control.opacity(0.6))
                    if (item == focused) SillSwing.strokeBorder(g, r, Ui.rowRadius, Palette.accent, 2.0)
                    val icon = Rect(10.0, r.midY - Ui.rowIcon / 2, Ui.rowIcon, Ui.rowIcon)
                    if (item.badge != null && item.icon == null) {
                        SillSwing.fill(g, icon, Ui.rowIconRadius, Palette.iconFallback)
                        val box = Symbol.boxFor(Ui.connectRowSymbolSize)
                        SillSwing.glyph(g, item.badge, icon.midX - box / 2, icon.midY - box / 2, box, Rgba.white, Palette.iconFallback)
                    } else AppIcons.draw(g, icon, Ui.rowIconRadius, item.icon, item.title, 12.0, scale)
                    g.font = trail
                    val tw = item.trailing?.let { g.fontMetrics.stringWidth(it) + 12.0 } ?: 0.0
                    val x = icon.maxX + 12
                    g.font = title
                    val fm = g.fontMetrics
                    SillSwing.text(g, SillSwing.fit(fm, item.title, r.maxX - 10 - tw - x), x, r.midY - (fm.ascent + fm.descent) / 2.0, title, Palette.text)
                    item.trailing?.let {
                        g.font = trail
                        val tfm = g.fontMetrics
                        SillSwing.text(g, it, r.maxX - 10 - tfm.stringWidth(it), r.midY - (tfm.ascent + tfm.descent) / 2.0, trail, Palette.muted)
                    }
                }
            }
        }
        g.dispose()
    }

    override fun getAccessibleContext(): javax.accessibility.AccessibleContext {
        if (accessibleContext == null) accessibleContext = object : AccessibleJComponent() {
            override fun getAccessibleRole() = AccessibleRole.LIST
            override fun getAccessibleDescription() = rows().joinToString(", ") { r -> r.title + (r.trailing?.let { ", $it" } ?: "") }
        }
        return accessibleContext
    }
}

/**
 * The Apps drawer (AppDrawer in StreamScreen.swift): the 48 pt search field with its magnifier and
 * prompt, then the rows (the owner's [sections], filtered by the search), on a [Sheet]. Typing goes
 * to the field while it is open; Enter picks the first row, Down moves into the list.
 */
class AppDrawer : Sheet() {
    val search = SillTextField("", Symbol.Magnifier)
    val list = RowList()
    private val scroll = darkScroll(list)
    /** The rows for a search (empty: everything). */
    var sections: (String) -> List<ListItem> = { emptyList() }
    var onPick: (String) -> Unit = {}

    init {
        openCurve = Motion.drawer; closeCurve = Motion.drawer
        add(search); add(scroll)
        list.onPick = { onPick(it) }
        search.document.addDocumentListener(object : DocumentListener {
            override fun insertUpdate(e: DocumentEvent) = refresh()
            override fun removeUpdate(e: DocumentEvent) = refresh()
            override fun changedUpdate(e: DocumentEvent) = refresh()
        })
        search.addActionListener { (list.items.firstOrNull { it is ListItem.Row } as? ListItem.Row)?.let { onPick(it.key) } }
        search.inputMap.put(KeyStroke.getKeyStroke(KeyEvent.VK_DOWN, 0), "sill.intoList")
        search.actionMap.put("sill.intoList", object : AbstractAction() { override fun actionPerformed(e: java.awt.event.ActionEvent) { list.requestFocusInWindow() } })
    }

    fun setMac(mac: String) { search.prompt = Copy.searchApps(mac); search.getAccessibleContext().accessibleName = "Search apps on this host"; search.repaint() }

    fun refresh() { list.items = sections(search.text.trim()) ; scroll.revalidate() }

    /** Opens empty (a fresh search each time, as the iOS drawer's @State), the field focused. */
    fun open() { search.text = ""; refresh(); present(true); later { search.requestFocusInWindow() } }

    override fun doLayout() {
        val p = Ui.sheetPadding.toInt()
        search.setBounds(p, p, width - 2 * p, Ui.searchHeight.toInt())
        val top = p + Ui.searchHeight.toInt() + 6
        scroll.setBounds(p, top, width - 2 * p, (height - top - p).coerceAtLeast(0))
    }
}

/**
 * The Settings panel's frame (HostSettingsPanel.swift): the pinned header (the Mac's name in the
 * headline, its readout lines in 13 pt muted, Done), the rows (the owner's) scrolling when the room
 * is short, and the pinned foot (Disconnect). As tall as its content, at most [maxHeight].
 */
class SettingsSheet : Sheet() {
    var title = ""; set(v) { field = v; header.repaint() }
    var lines: List<String> = emptyList(); set(v) { field = v; header.revalidate(); header.repaint() }
    val body = StackPanel()
    private val scroll = darkScroll(body)
    val done = LinkButton(me.saffer.sill.core.ui.PanelCopy.done, Type.bodySemibold, inset = 4.0)
    val foot = FootButton(Symbol.XmarkCircle, "", me.saffer.sill.core.ui.PanelCopy.disconnectShort)
    private val header = object : JComponent() {
        init { isOpaque = false }
        override fun paintComponent(g0: Graphics) {
            val g = SillSwing.smooth(g0)
            val t = SillSwing.font(Type.headline)
            g.font = t
            val fm = g.fontMetrics
            SillSwing.text(g, SillSwing.fit(fm, title, width - 4.0 - done.width - 12, middle = true), 4.0, 0.0, t, Palette.text)
            val f = SillSwing.font(Type.footnote)
            val lfm = g.getFontMetrics(f)
            var y = fm.ascent + fm.descent + 2.0
            for (l in lines) for (w in Wrap.lines(lfm, l, width - 4.0 - done.width - 12)) { SillSwing.text(g, w, 4.0, y, f, Palette.muted); y += lfm.height }
            g.dispose()
        }
    }
    var maxHeight = 600

    init {
        scaleFrom = Motion.settingsScale
        openCurve = Motion.settingsOpen; closeCurve = Motion.settingsClose
        add(header); add(done); add(scroll); add(foot)
        getAccessibleContext().accessibleName = me.saffer.sill.core.ui.Copy.settings
    }

    private fun headerHeight(width: Int): Int {
        val t = getFontMetrics(SillSwing.font(Type.headline))
        val f = getFontMetrics(SillSwing.font(Type.footnote))
        val room = width - 2 * Ui.sheetPadding - 4 - (done.preferredSize.width) - 12
        val n = lines.sumOf { Wrap.lines(f, it, room).size }
        return t.ascent + t.descent + (if (n > 0) 2 + n * f.height else 0) + 12
    }

    /** The height it takes at `width`: its content, at most [maxHeight]. */
    fun heightAt(width: Int): Int {
        val p = Ui.sheetPadding.toInt()
        val content = p + headerHeight(width) + body.heightFor(width - 2 * p) + 10 + Ui.footHeight.toInt() + p
        return content.coerceAtMost(maxHeight)
    }

    override fun doLayout() {
        val p = Ui.sheetPadding.toInt()
        val hh = headerHeight(width)
        val dw = done.preferredSize.width
        header.setBounds(p, p, width - 2 * p, hh)
        done.setBounds(width - p - dw, p - 11 + 2, dw, 44)
        val footY = height - p - Ui.footHeight.toInt()
        foot.setBounds(p, footY, width - 2 * p, Ui.footHeight.toInt())
        scroll.setBounds(p, p + hh, width - 2 * p, (footY - 10 - p - hh).coerceAtLeast(0))
        scroll.revalidate()
    }
}
