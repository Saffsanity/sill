package me.saffer.sill.swingui

import me.saffer.sill.core.ui.Motion
import me.saffer.sill.core.ui.Palette
import me.saffer.sill.core.ui.Rect
import me.saffer.sill.core.ui.Rgba
import me.saffer.sill.core.ui.Symbol
import me.saffer.sill.core.ui.TextStyle
import me.saffer.sill.core.ui.Type
import me.saffer.sill.core.ui.Ui
import java.awt.AlphaComposite
import java.awt.Graphics
import java.awt.Graphics2D
import java.awt.event.FocusAdapter
import java.awt.event.FocusEvent
import java.awt.event.KeyEvent
import java.awt.event.MouseAdapter
import java.awt.event.MouseEvent
import javax.accessibility.AccessibleContext
import javax.accessibility.AccessibleRole
import javax.swing.AbstractAction
import javax.swing.JComponent
import javax.swing.KeyStroke

/** A lightweight component with an accessible context of its own (JComponent has none), so a
 *  screen reader can read the name every custom view sets. */
open class SillComponent : JComponent() {
    override fun getAccessibleContext(): AccessibleContext {
        if (accessibleContext == null) accessibleContext = object : AccessibleJComponent() {}
        return accessibleContext
    }
}

/**
 * The base of the iOS app's custom controls in Swing: a lightweight, see-through component that
 * fades (and takes no click while faded, as SwiftUI's `allowsHitTesting(false)` beside
 * `.opacity(0)`), fires its action on a click or on Space and Enter, and draws the accent focus
 * ring only when the keyboard brought focus to it (Tab), never after a click. A click never takes
 * the focus, so the stream keeps the keyboard.
 */
abstract class SillControl : SillComponent() {
    /** The control's opacity, animated by [fadeTo]. */
    val fade = Animated(1.0, this)
    var onAction: () -> Unit = {}
    var hover = false
        private set
    var pressed = false
        private set
    private var keyboardFocus = false
    /** The focus ring's and the hover wash's corner radius. */
    open val cornerRadius: Double get() = Ui.barButtonRadius
    /** The accessible role and name a screen reader announces (the iOS app's accessibility label). */
    var accessibleName: String = ""
        set(v) { field = v; getAccessibleContext().accessibleName = v; toolTipText = v.ifEmpty { null } }

    init {
        isOpaque = false
        isFocusable = true
        isRequestFocusEnabled = false
        addFocusListener(object : FocusAdapter() {
            override fun focusGained(e: FocusEvent) {
                keyboardFocus = e.cause.name.startsWith("TRAVERSAL")
                repaint()
            }
            override fun focusLost(e: FocusEvent) { keyboardFocus = false; repaint() }
        })
        val m = object : MouseAdapter() {
            override fun mouseEntered(e: MouseEvent) { hover = true; repaint() }
            override fun mouseExited(e: MouseEvent) { hover = false; pressed = false; repaint() }
            override fun mousePressed(e: MouseEvent) { if (e.button == MouseEvent.BUTTON1 && live) { pressed = true; repaint(); pressedAt(e) } }
            override fun mouseReleased(e: MouseEvent) {
                if (e.button != MouseEvent.BUTTON1) return
                val was = pressed
                pressed = false; repaint()
                releasedAt(e)
                if (was && contains(e.x, e.y) && live && clicks) onAction()
            }
            override fun mouseDragged(e: MouseEvent) { draggedAt(e) }
        }
        addMouseListener(m); addMouseMotionListener(m)
        for (k in listOf(KeyEvent.VK_SPACE, KeyEvent.VK_ENTER)) {
            inputMap.put(KeyStroke.getKeyStroke(k, 0), "sill.activate")
        }
        actionMap.put("sill.activate", object : AbstractAction() { override fun actionPerformed(e: java.awt.event.ActionEvent) { if (live) onAction() } })
    }

    /** False while faded out: it neither draws nor takes a click. */
    val live get() = isEnabled && fade.target > 0.5
    /** Whether a click fires [onAction] (the Aa control drives itself from the press and drag). */
    protected open val clicks = true
    protected open fun pressedAt(e: MouseEvent) {}
    protected open fun releasedAt(e: MouseEvent) {}
    protected open fun draggedAt(e: MouseEvent) {}

    fun fadeTo(alpha: Double, curve: me.saffer.sill.core.ui.Curve = Motion.scaleFade) {
        if (fade.target != alpha) fade.animate(alpha, curve)
        isFocusable = alpha > 0.5
    }

    override fun contains(x: Int, y: Int) = fade.target > 0.05 && super.contains(x, y)

    val showsFocusRing get() = keyboardFocus && isFocusOwner

    final override fun paintComponent(g: Graphics) {
        val a = fade.value.coerceIn(0.0, 1.0)
        if (a <= 0.003) return
        val g2 = SillSwing.smooth(g)
        if (a < 1) g2.composite = AlphaComposite.getInstance(AlphaComposite.SRC_OVER, a.toFloat())
        paintControl(g2, Rect(0.0, 0.0, width.toDouble(), height.toDouble()))
        if (showsFocusRing) SillSwing.strokeBorder(g2, Rect(0.0, 0.0, width.toDouble(), height.toDouble()), cornerRadius, Palette.accent, 2.0)
        g2.dispose()
    }

    protected abstract fun paintControl(g: Graphics2D, r: Rect)

    override fun getAccessibleContext(): AccessibleContext {
        if (accessibleContext == null) accessibleContext = object : AccessibleJComponent() {
            override fun getAccessibleRole() = AccessibleRole.PUSH_BUTTON
        }
        return accessibleContext
    }
}

/**
 * A bar button (BarButton and TopBar.button in StreamScreen.swift): the symbol over its 11 pt
 * label, on the control colour (controlOpen while what it opens shows, and then in the accent).
 * Its size and corners are the layout's (66×66 in the roomy bar, 64×58 in the compact ones).
 */
class BarButton(symbol: Symbol, label: String) : SillControl() {
    var symbol = symbol; set(v) { field = v; repaint() }
    var label = label; set(v) { field = v; repaint() }
    var open = false; set(v) { if (field != v) { field = v; repaint() } }
    var radius = Ui.barButtonRadius; set(v) { field = v; repaint() }
    var iconSize = Ui.barIconSize; set(v) { field = v; repaint() }
    var spacing = 4.0; set(v) { field = v; repaint() }
    override val cornerRadius get() = radius

    override fun paintControl(g: Graphics2D, r: Rect) {
        val fill = if (open) Palette.controlOpen else Palette.control
        SillSwing.fill(g, r, radius, fill)
        if (hover && !open) SillSwing.fill(g, r, radius, Rgba.white.opacity(if (pressed) 0.08 else 0.04))
        BarFace.symbolOverLabel(g, r, symbol, iconSize, label, spacing, open, fill)
    }
}

/** How a bar button lays out its symbol over its label, shared by the bar's buttons and the caps. */
object BarFace {
    fun symbolOverLabel(g: Graphics2D, r: Rect, symbol: Symbol, iconSize: Double, label: String, spacing: Double, open: Boolean, background: Rgba) {
        val box = Symbol.boxFor(iconSize)
        val font = SillSwing.font(Type.barLabel)
        g.font = font
        val fm = g.fontMetrics
        val labelH = fm.ascent + fm.descent.toDouble()
        val total = box + spacing + labelH
        val top = r.y + (r.height - total) / 2
        SillSwing.glyph(g, symbol, r.midX - box / 2, top, box, if (open) Palette.accent else Palette.text, background)
        SillSwing.centred(g, label, r, top + box + spacing, font, if (open) Palette.accent else Palette.barLabel)
    }
}

/**
 * A key cap of the portrait key row (KeyRow.cap in PortraitStreamScreen.swift): its word in 13 pt
 * medium, or its symbol, on the control colour; a latched modifier lit (controlOpen, the accent).
 */
class KeyCap(val title: String?, val symbol: Symbol?) : SillControl() {
    var open = false; set(v) { if (field != v) { field = v; repaint() } }
    override val cornerRadius get() = Ui.capRadius

    override fun paintControl(g: Graphics2D, r: Rect) {
        val fill = if (open) Palette.controlOpen else Palette.control
        SillSwing.fill(g, r, Ui.capRadius, fill)
        if (pressed) SillSwing.fill(g, r, Ui.capRadius, Rgba.white.opacity(0.08)) else if (hover) SillSwing.fill(g, r, Ui.capRadius, Rgba.white.opacity(0.04))
        val c = if (open) Palette.accent else Palette.text
        if (symbol != null) {
            val box = Symbol.boxFor(17.0)
            SillSwing.glyph(g, symbol, r.midX - box / 2, r.midY - box / 2, box, c, fill)
        } else if (title != null) {
            val font = SillSwing.font(Type.cap)
            g.font = font
            val fm = g.fontMetrics
            SillSwing.centred(g, title, r, r.midY - (fm.ascent + fm.descent) / 2.0, font, c)
        }
    }
}

/**
 * An accent text button (Add a Mac…, Cancel, Search Nearby): 15 pt semibold in the accent, at least
 * 44 tall, leading-aligned with the column's 10 pt inset, as the iOS app's plain buttons.
 */
class LinkButton(text: String, val style: TextStyle = Type.connectLink, val inset: Double = 10.0) : SillControl() {
    var text = text; set(v) { field = v; revalidate(); repaint() }
    override val cornerRadius get() = Ui.rowRadius

    override fun getPreferredSize(): java.awt.Dimension {
        val fm = getFontMetrics(SillSwing.font(style))
        return java.awt.Dimension(Math.ceil(textWidth(text) + inset * 2).toInt() + 2, Ui.touchTarget.toInt())
    }

    /** The words' width as they are drawn (antialiased, fractional metrics). */
    private fun textWidth(s: String) = SillSwing.font(style).getStringBounds(s, java.awt.font.FontRenderContext(null, true, true)).width

    override fun paintControl(g: Graphics2D, r: Rect) {
        if (hover) SillSwing.fill(g, r, Ui.rowRadius, Rgba.white.opacity(0.04))
        val font = SillSwing.font(style)
        g.font = font
        val fm = g.fontMetrics
        val c = if (isEnabled) Palette.accent else Palette.accent.opacity(0.4)
        SillSwing.text(g, SillSwing.fit(fm, text, r.width - inset * 2), r.x + inset, r.midY - (fm.ascent + fm.descent) / 2.0, font, c)
    }
}

/**
 * The filled accent button (Pair): 15 pt semibold black on the accent, at least 88×44, corners 12.
 */
class FilledButton(text: String) : SillControl() {
    var text = text; set(v) { field = v; repaint() }
    override val cornerRadius get() = Ui.fieldRadius
    override fun getPreferredSize(): java.awt.Dimension {
        val fm = getFontMetrics(SillSwing.font(Type.connectLink))
        return java.awt.Dimension(maxOf(88, fm.stringWidth(text) + 24), 44)
    }
    override fun getMaximumSize() = preferredSize

    override fun paintControl(g: Graphics2D, r: Rect) {
        SillSwing.fill(g, r, Ui.fieldRadius, Palette.accent.opacity(if (isEnabled) (if (pressed) 0.8 else 1.0) else 0.4))
        val font = SillSwing.font(Type.connectLink)
        g.font = font
        val fm = g.fontMetrics
        SillSwing.centred(g, text, r, r.midY - (fm.ascent + fm.descent) / 2.0, font, Rgba.black)
    }
}
