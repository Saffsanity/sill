package me.saffer.sill.swingui

import me.saffer.sill.core.ui.MacMenuState
import me.saffer.sill.core.ui.MacMenuState.Content
import me.saffer.sill.core.ui.MacMenuState.Row
import me.saffer.sill.core.ui.MacMenus
import me.saffer.sill.core.ui.Palette
import java.awt.Component
import java.awt.Dimension
import java.awt.Graphics
import javax.swing.JMenu
import javax.swing.JMenuItem
import javax.swing.JPopupMenu
import javax.swing.event.MenuEvent
import javax.swing.event.MenuListener

/**
 * The Menus button's menu (the iOS app's MacMenuElements and MacMenuButton): the Mac's top-level
 * menus, each read from the Mac when it opens (never cached, as UIKit's uncached deferred elements),
 * "Loading…" until the answer, rows in sections, the Mac's shortcut as text at the right (never a key
 * command: ⌘S typed still reaches the Mac as a key), ✓ for a mark on and – for mixed. A cascading
 * Swing menu stands for the iPad's pull-down, as a Windows app's menus cascade.
 */
object MacMenuPopup {
    fun show(menus: MacMenus, invoker: Component, x: Int, y: Int) {
        val popup = JPopupMenu()
        val top = menus.state.top
        top.note?.let { popup.add(note(it)) }
        if (top.note != null && top.menus.isNotEmpty()) popup.addSeparator()
        for (row in top.menus) popup.add(LazyMenu(menus, row))
        if (popup.componentCount == 0) popup.add(note(MacMenuState.NO_ITEMS))
        popup.show(invoker, x, y)
    }

    private fun note(text: String) = object : JMenuItem(text) {
        override fun getPreferredSize(): Dimension = super.getPreferredSize().let { Dimension(it.width, maxOf(it.height, ROW_HEIGHT)) }
    }.apply { isEnabled = false; border = javax.swing.BorderFactory.createEmptyBorder(0, 6, 0, 6) }

    /** The iPad pull-down's rows, at the pointer's density (UIMenu's compact rows are 32 pt tall with a pointer). */
    const val ROW_HEIGHT = 32

    /** A menu whose items are asked for each time it opens. */
    private class LazyMenu(private val menus: MacMenus, private val row: Row, nested: Boolean = false) : JMenu((if (nested) "     " else "") + row.title) {
        private var generation = 0
        override fun getPreferredSize(): Dimension = super.getPreferredSize().let { Dimension(it.width + 8, maxOf(it.height, ROW_HEIGHT)) }
        init {
            isEnabled = row.enabled
            border = javax.swing.BorderFactory.createEmptyBorder(0, 6, 0, 6)
            add(note(LOADING))
            addMenuListener(object : MenuListener {
                override fun menuSelected(e: MenuEvent) {
                    val mine = ++generation
                    removeAll(); add(note(LOADING)); refresh()
                    menus.open(row) { content -> if (mine == generation) fill(content) }
                }
                override fun menuDeselected(e: MenuEvent) { generation++ }
                override fun menuCanceled(e: MenuEvent) { generation++ }
            })
        }

        private fun fill(content: Content) {
            removeAll()
            when (content) {
                is Content.Message -> add(note(content.text))
                is Content.Sections -> content.sections.forEachIndexed { i, section ->
                    if (i > 0) addSeparator()
                    for (r in section) add(when (r.kind) {
                        Row.Kind.Note -> note(r.title)
                        Row.Kind.Submenu -> LazyMenu(menus, r, nested = true)
                        Row.Kind.Item -> ItemRow(r).apply { addActionListener { menus.choose(r) } }
                    })
                }
            }
            refresh()
        }

        /** A popup already showing takes its new size only when shown again. */
        private fun refresh() {
            if (!isPopupMenuVisible) return
            popupMenu.pack()
            isPopupMenuVisible = false; isPopupMenuVisible = true
        }
    }

    /** One item: its mark, its title, and the Mac's shortcut at the right in the secondary colour. */
    private class ItemRow(private val row: Row) : JMenuItem(markPrefix(row.mark) + row.title) {
        init { border = javax.swing.BorderFactory.createEmptyBorder(0, 6, 0, 6) }
        init { isEnabled = row.enabled; getAccessibleContext().accessibleName = listOfNotNull(row.title, row.key).joinToString(", ") }
        override fun getPreferredSize(): Dimension {
            val d = super.getPreferredSize()
            val k = row.key ?: return Dimension(d.width, maxOf(d.height, ROW_HEIGHT))
            return Dimension(d.width + getFontMetrics(font).stringWidth(k) + 24, maxOf(d.height, ROW_HEIGHT))
        }
        override fun paintComponent(g: Graphics) {
            super.paintComponent(g)
            val k = row.key ?: return
            val fm = g.getFontMetrics(font)
            g.color = SillSwing.color(if (isEnabled) Palette.muted else Palette.muted.opacity(0.5))
            g.font = font
            g.drawString(k, width - insets.right - fm.stringWidth(k) - 8, (height - fm.height) / 2 + fm.ascent)
        }
    }

    private fun markPrefix(m: Row.Mark) = when (m) { Row.Mark.On -> "✓  "; Row.Mark.Mixed -> "–  "; Row.Mark.Off -> "     " }

    const val LOADING = "Loading…"
}
