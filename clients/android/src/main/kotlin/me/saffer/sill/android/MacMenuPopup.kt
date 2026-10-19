package me.saffer.sill.android

import android.content.Context
import android.graphics.Color
import android.text.SpannableString
import android.text.Spanned
import android.text.style.ForegroundColorSpan
import android.view.Gravity
import android.view.Menu
import android.view.View
import android.widget.PopupMenu
import me.saffer.sill.core.ui.MacMenuState
import me.saffer.sill.core.ui.MacMenuState.Content
import me.saffer.sill.core.ui.MacMenuState.Row
import me.saffer.sill.core.ui.MacMenus

/**
 * The Menus button's menu on Android (the iOS app's MacMenuButton and MacMenuElements): the Mac's
 * top-level menus, each read from the Mac when it opens (never cached), rows in sections (Android's
 * group dividers), the Mac's shortcut as text after the title in the secondary colour (never a key
 * command), a check for a mark on and "–" for mixed. A submenu replaces the menu with its own,
 * headed by its title, as Android's own popup submenus do.
 */
class MacMenuPopup(private val context: Context, private val anchor: View, private val menus: MacMenus) {
    /** The popup showing, if any: only the newest one may show what arrives. */
    private var showing: PopupMenu? = null
    private var generation = 0

    fun showTop() {
        val top = menus.state.top
        popup(null) { m ->
            var order = 0
            top.note?.let { m.add(0, Menu.NONE, order++, it).isEnabled = false }
            for (row in top.menus) m.add(1, Menu.NONE, order++, "${row.title}  ›").apply {
                isEnabled = row.enabled
                setOnMenuItemClickListener { open(row); true }
            }
            if (m.size() == 0) m.add(MacMenuState.NO_ITEMS).isEnabled = false
        }
    }

    private fun open(row: Row) {
        val mine = ++generation
        menus.open(row) { content -> if (mine == generation) show(row.title, content) }
    }

    private fun show(title: String, content: Content) = popup(title) { m ->
        var order = 1
        when (content) {
            is Content.Message -> m.add(0, Menu.NONE, order, content.text).isEnabled = false
            is Content.Sections -> content.sections.forEachIndexed { i, section ->
                for (r in section) m.add(i + 1, Menu.NONE, order++, label(r)).apply {
                    isEnabled = r.enabled
                    when (r.kind) {
                        Row.Kind.Item -> {
                            if (r.mark == Row.Mark.On) { isCheckable = true; isChecked = true }
                            contentDescription = listOfNotNull(r.title, r.key).joinToString(", ")
                            setOnMenuItemClickListener { menus.choose(r); true }
                        }
                        Row.Kind.Submenu -> setOnMenuItemClickListener { open(r); true }
                        Row.Kind.Note -> {}
                    }
                }
            }
        }
    }

    private fun popup(header: String?, fill: (Menu) -> Unit) {
        showing?.dismiss()
        val p = PopupMenu(context, anchor, Gravity.END)
        val m = p.menu
        header?.let { m.add(0, Menu.NONE, 0, SpannableString(it).apply { setSpan(android.text.style.StyleSpan(android.graphics.Typeface.BOLD), 0, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE) }).isEnabled = false }
        fill(m)
        m.setGroupDividerEnabled(true)
        p.setOnDismissListener { if (showing === p) showing = null }
        showing = p
        p.show()
    }

    /** The row's words: "– " for mixed, the title, "  ›" for a submenu, the shortcut after it in the secondary colour. */
    private fun label(r: Row): CharSequence {
        val head = (if (r.mark == Row.Mark.Mixed) "– " else "") + r.title + (if (r.kind == Row.Kind.Submenu) "  ›" else "")
        val key = r.key ?: return head
        return SpannableString("$head    $key").apply {
            setSpan(ForegroundColorSpan(Color.argb(150, 255, 255, 255)), head.length, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
        }
    }

    fun dismiss() { generation++; showing?.dismiss(); showing = null }
}
