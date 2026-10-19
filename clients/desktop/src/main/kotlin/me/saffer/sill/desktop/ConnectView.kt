package me.saffer.sill.desktop

import me.saffer.sill.core.PairingPrompt
import me.saffer.sill.core.ui.ConnectLayout
import me.saffer.sill.core.ui.Copy
import me.saffer.sill.core.ui.PlatformCopy
import me.saffer.sill.core.ui.Palette
import me.saffer.sill.core.ui.Size
import me.saffer.sill.core.ui.Type
import me.saffer.sill.core.ui.Ui
import me.saffer.sill.swingui.FilledButton
import me.saffer.sill.swingui.HeightForWidth
import me.saffer.sill.swingui.LinkButton
import me.saffer.sill.swingui.RowList
import me.saffer.sill.swingui.SillTextField
import me.saffer.sill.swingui.StackPanel
import me.saffer.sill.swingui.WrapLabel
import me.saffer.sill.swingui.darkScroll
import me.saffer.sill.swingui.heightAt
import me.saffer.sill.swingui.later
import java.awt.Component
import java.awt.Dimension
import java.awt.Graphics
import java.awt.Insets
import java.awt.event.KeyEvent
import javax.swing.AbstractAction
import javax.swing.JComponent
import javax.swing.JPanel
import javax.swing.KeyStroke
import javax.swing.event.DocumentEvent
import javax.swing.event.DocumentListener
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/**
 * The connect screen's view (ConnectScreen, AddMacCard): black, the column 380 wide centred
 * (ConnectLayout), rising only to keep 24 clear of the footer and scrolling above it when even that
 * does not fit; the footer along the bottom under the column's own edge.
 */
class ConnectView : JPanel() {
    enum class Card { None, Address, Link, Code }

    val title = WrapLabel(Copy.connectTitle, Type.connectTitle, Palette.text, Insets(0, 10, 0, 10))
    val status = WrapLabel("", Type.connectStatus, Palette.muted, Insets(0, 10, 4, 10))
    val rows = RowList()
    val addMac = LinkButton(Copy.addMac).apply { accessibleName = Copy.addMac }

    // Add a Mac's card, and the card a Mac's code asks for.
    private val words = WrapLabel(Copy.addMacPairOnce, Type.connectStatus, Palette.muted, Insets(4, 10, 0, 10))
    private val how = WrapLabel("", Type.connectStatus, Palette.text, Insets(0, 10, 2, 10))
    val address = SillTextField("100.101.102.103 or mac.example.net", style = Type.subheadline).apply { getAccessibleContext().accessibleName = "Address" }
    val code = SillTextField("0000 0000 0000", style = Type.subheadline).apply { getAccessibleContext().accessibleName = "Code" }
    val link = SillTextField("sill://pair…", style = Type.subheadline).apply { getAccessibleContext().accessibleName = "Pairing link" }
    val pair = FilledButton(Copy.pair).apply { accessibleName = Copy.pair }
    private val progress = WrapLabel("", Type.connectStatus, Palette.muted, Insets(0, 10, 0, 10))
    private val pathToggle = LinkButton(PlatformCopy.usePairingLink, inset = 0.0)
    private val cancel = LinkButton(Copy.cancel, inset = 0.0).apply { accessibleName = Copy.cancel }

    var onPairAddress: (String, String) -> Unit = { _, _ -> }
    var onPairLink: (String) -> Unit = {}
    var onPairCode: (PairingPrompt, String) -> Unit = { _, _ -> }
    var onCancelPrompt: (PairingPrompt) -> Unit = {}

    var card = Card.None
        private set
    private var prompt: PairingPrompt? = null
    private var working = false

    private val column = StackPanel(spacing = 6)
    private val scroll = darkScroll(column)
    private val footer = Footer()

    init {
        layout = null
        background = java.awt.Color.BLACK
        isOpaque = true
        add(scroll); add(footer)
        title.getAccessibleContext().accessibleName = Copy.connectTitle
        code.document.addDocumentListener(object : DocumentListener {
            override fun insertUpdate(e: DocumentEvent) = group()
            override fun removeUpdate(e: DocumentEvent) {}
            override fun changedUpdate(e: DocumentEvent) {}
        })
        address.addActionListener { code.requestFocusInWindow() }
        code.addActionListener { submit() }
        link.addActionListener { submit() }
        pair.onAction = { submit() }
        pathToggle.onAction = { showCard(if (card == Card.Link) Card.Address else Card.Link) }
        cancel.onAction = { cancelCard() }
        getInputMap(WHEN_IN_FOCUSED_WINDOW).put(KeyStroke.getKeyStroke(KeyEvent.VK_ESCAPE, 0), "sill.cancel")
        actionMap.put("sill.cancel", object : AbstractAction() { override fun actionPerformed(e: java.awt.event.ActionEvent) { if (card != Card.None) cancelCard() } })
        showRows()
    }

    /** "4829 1355 7208" as it is typed or pasted: digits only, at most 12, in groups of 4 (PairingField.grouped). */
    private fun group() = later {
        val digits = code.text.filter { it.isDigit() }.take(12)
        val g = digits.chunked(4).joinToString(" ")
        if (g != code.text) code.text = g
    }

    fun showRows() {
        card = Card.None; prompt = null; working = false
        title.text = Copy.connectTitle
        rebuild(listOf(title, status, rows, addMac))
    }

    fun showCard(c: Card) {
        card = c; working = false
        progress.text = ""; progress.warning = false
        title.text = if (c == Card.Code) "Pair with ${prompt?.macName ?: "Host"}" else Copy.addMacTitle
        when (c) {
            Card.Address -> {
                how.text = Copy.addMacTyped
                pathToggle.text = PlatformCopy.usePairingLink
                rebuild(listOf(title, words, how, address, code, leading(pair), progress, links()))
                later { address.requestFocusInWindow() }
            }
            Card.Link -> {
                how.text = PlatformCopy.pastePairingLink
                pathToggle.text = Copy.enterCodeInstead
                rebuild(listOf(title, words, how, link, leading(pair), progress, links()))
                later { link.requestFocusInWindow() }
            }
            Card.Code -> {
                how.text = prompt?.words ?: ""
                rebuild(listOf(title, how, code, leading(pair), progress, links(toggle = false)))
                later { code.requestFocusInWindow() }
            }
            Card.None -> showRows()
        }
    }

    fun showPrompt(p: PairingPrompt) { prompt = p; code.text = ""; showCard(Card.Code) }

    fun working(text: String) { working = true; progress.warning = false; progress.color = Palette.muted; progress.text = text; setFieldsEnabled(false); relayout() }
    fun problem(text: String) { working = false; progress.warning = true; progress.text = text; setFieldsEnabled(true); relayout() }
    fun paired(text: String) { working = false; setFieldsEnabled(true); status.text = text }

    private fun setFieldsEnabled(on: Boolean) { for (c in listOf(address, code, link, pair, pathToggle)) c.isEnabled = on }

    private fun submit() {
        if (working) return
        when (card) {
            Card.Address -> onPairAddress(address.text.trim(), code.text)
            Card.Link -> onPairLink(link.text)
            Card.Code -> prompt?.let { onPairCode(it, code.text) }
            Card.None -> {}
        }
    }

    private fun cancelCard() {
        if (card == Card.Code) prompt?.let(onCancelPrompt)
        showRows()
    }

    /** One component at its own width on the card's 10 pt inset, as a SwiftUI button in a leading VStack. */
    private fun leading(c: JComponent, top: Int = 4) = object : JPanel(null), HeightForWidth {
        init { isOpaque = false; add(c) }
        override fun heightFor(width: Int) = c.preferredSize.height + top
        override fun doLayout() { c.setBounds(10, top, c.preferredSize.width, c.preferredSize.height) }
    }

    /** The card's links side by side, 18 apart (AddMacCard.links). */
    private fun links(toggle: Boolean = true) = object : JPanel(null), HeightForWidth {
        val items = if (toggle) listOf(pathToggle, cancel) else listOf(cancel)
        init { isOpaque = false; items.forEach { add(it) } }
        override fun heightFor(width: Int) = 44
        override fun doLayout() { var x = 10; for (c in items) { val w = c.preferredSize.width; c.setBounds(x, 0, w, 44); x += w + 18 } }
    }

    private fun rebuild(parts: List<Component>) {
        column.removeAll()
        // The fields and the Pair button sit on the card's 10 pt inset.
        for (p in parts) column.add(if (p is SillTextField) inset(p) else p)
        relayout()
    }

    private fun inset(f: SillTextField) = object : JPanel(null), HeightForWidth {
        init { isOpaque = false; add(f) }
        override fun heightFor(width: Int) = Ui.searchHeight.toInt() + 2
        override fun doLayout() { f.setBounds(10, 2, width - 20, Ui.searchHeight.toInt()) }
    }

    private fun relayout() { revalidate(); doLayout(); repaint() }

    override fun doLayout() {
        val l = ConnectLayout(Size(width.toDouble(), height.toDouble()))
        val cw = l.columnWidth.roundToInt()
        val cx = l.columnX.roundToInt()
        val fh = footer.heightAt(cw)
        val bottom = 14
        footer.setBounds(cx, height - bottom - fh, cw, fh)
        val ch = column.heightFor(cw)
        val roomBottom = height - bottom - fh - Ui.connectFooterGap.toInt()
        val avail = max(0, roomBottom - 16)
        val y = if (ch <= avail) min((height - ch) / 2, roomBottom - ch).coerceAtLeast(16) else 16
        scroll.setBounds(cx, y, cw, min(ch, avail))
        scroll.revalidate()
    }

    override fun paintComponent(g: Graphics) { g.color = java.awt.Color.BLACK; g.fillRect(0, 0, width, height) }

    /** "Needs the free Sill app on your Mac." and the site's links (ConnectScreen.footer). */
    private inner class Footer : JPanel(null), HeightForWidth {
        private val needs = WrapLabel(Copy.needsMacApp, Type.footnote, Palette.muted, Insets(0, 10, 0, 10))
        private val get = LinkButton(Copy.getItAt("getsill.app"), Type.footnote, inset = 0.0).apply { onAction = { open("https://getsill.app/download") } }
        private val support = LinkButton(Copy.support, Type.footnote, inset = 0.0).apply { onAction = { open("https://getsill.app/support") } }
        private val privacy = LinkButton(Copy.privacyPolicy, Type.footnote, inset = 0.0).apply { onAction = { open("https://getsill.app/privacy") } }
        private val links = listOf(get, support, privacy)
        private val dot = " · "
        init { isOpaque = false; add(needs); links.forEach { add(it) } }
        private fun lineH() = getFontMetrics(me.saffer.sill.swingui.SillSwing.font(Type.footnote)).height
        private fun oneLine(width: Int) = links.sumOf { it.preferredSize.width } + 2 * getFontMetrics(me.saffer.sill.swingui.SillSwing.font(Type.footnote)).stringWidth(dot) <= width - 20
        override fun heightFor(width: Int) = needs.heightFor(width) + 8 + if (oneLine(width)) lineH() else lineH() * 2 + 8
        override fun doLayout() {
            val nh = needs.heightFor(width)
            needs.setBounds(0, 0, width, nh)
            val dw = getFontMetrics(me.saffer.sill.swingui.SillSwing.font(Type.footnote)).stringWidth(dot)
            var x = 10; var y = nh + 8
            val lh = lineH()
            if (oneLine(width)) for (c in links) { c.setBounds(x, y, c.preferredSize.width, lh); x += c.preferredSize.width + dw }
            else {
                get.setBounds(10, y, get.preferredSize.width, lh); y += lh + 8
                support.setBounds(10, y, support.preferredSize.width, lh)
                privacy.setBounds(10 + support.preferredSize.width + dw, y, privacy.preferredSize.width, lh)
            }
        }
        override fun paintComponent(g0: Graphics) {
            val g = me.saffer.sill.swingui.SillSwing.smooth(g0)
            val f = me.saffer.sill.swingui.SillSwing.font(Type.footnote)
            val fm = g.getFontMetrics(f)
            for ((a, b) in links.zipWithNext()) if (a.y == b.y) me.saffer.sill.swingui.SillSwing.text(g, dot, a.x + a.width.toDouble(), a.y + (a.height - fm.ascent - fm.descent) / 2.0, f, Palette.muted)
            g.dispose()
        }
        private fun open(url: String) {
            try { if (java.awt.Desktop.isDesktopSupported()) java.awt.Desktop.getDesktop().browse(java.net.URI(url)) } catch (_: Exception) {}
        }
    }
}

