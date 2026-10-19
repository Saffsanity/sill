package me.saffer.sill.host.ui

import me.saffer.sill.core.ui.Symbol
import me.saffer.sill.host.PairingCopy
import me.saffer.sill.host.QrCode
import me.saffer.sill.swingui.SillSwing
import java.awt.Color
import java.awt.Dimension
import java.awt.Graphics
import java.awt.Graphics2D
import java.awt.event.KeyEvent
import java.awt.event.WindowAdapter
import java.awt.event.WindowEvent
import java.awt.geom.AffineTransform
import java.awt.geom.RoundRectangle2D
import javax.swing.AbstractAction
import javax.swing.JComponent
import javax.swing.JFrame
import javax.swing.KeyStroke
import javax.swing.Timer

/** What the pairing window shows: the open code and its link, or how it ended, with what the code was. */
data class PairingView(val code: String, val link: String, val secondsLeft: Double, val phase: PairingCopy.Phase,
                       val askedBy: String?, val address: PairingCopy.Address?)

/**
 * The QR code (QRCodeView): dark on white with a 4-module quiet zone, each module a whole number of
 * device pixels, about 220 pt for the symbol, drawn 1:1 at the display's scale so a camera reads crisp
 * edges; a spent code keeps its place as an empty rounded square.
 */
class QrView : JComponent() {
    companion object { const val QUIET = 4; const val SYMBOL_POINTS = 220.0 }
    var text: String? = null; set(v) { if (v != field) { field = v; qr = v?.let(QrCode::encode) }; revalidate(); repaint() }
    var spent = false; set(v) { field = v; repaint() }
    private var qr: QrCode? = null

    init { isOpaque = false }

    /** Points per side at a device scale, the spare pixel more quiet zone (QRCode.screenImage). */
    fun side(scale: Double): Int {
        val n = qr?.size ?: 25
        val perModule = maxOf(1, (SYMBOL_POINTS * scale / n).toInt())
        return kotlin.math.ceil((n + 2 * QUIET) * perModule / scale).toInt()
    }
    override fun getPreferredSize() = Dimension(side(1.0), side(1.0))

    override fun paintComponent(g0: Graphics) {
        val g = g0.create() as Graphics2D
        val scale = g.transform.scaleX
        val s = side(scale)
        val x0 = (width - s) / 2
        val q = qr
        if (spent || q == null) {
            val sg = SillSwing.smooth(g)
            val c = HostTheme.c
            sg.color = c.secondary.opacity(0.12).awt()
            sg.fill(RoundRectangle2D.Double(x0.toDouble(), 0.0, s.toDouble(), s.toDouble(), 16.0, 16.0))
            // "qrcode": three finder squares, light, in the middle.
            val k = 44.0; val ox = x0 + (s - k) / 2; val oy = (s - k) / 2
            sg.color = c.tertiary.awt(); sg.stroke = java.awt.BasicStroke(2f)
            for ((dx, dy) in listOf(0.0 to 0.0, 26.0 to 0.0, 0.0 to 26.0)) sg.draw(RoundRectangle2D.Double(ox + dx, oy + dy, 18.0, 18.0, 4.0, 4.0))
            sg.fill(java.awt.geom.Rectangle2D.Double(ox + 28.0, oy + 28.0, 6.0, 6.0)); sg.fill(java.awt.geom.Rectangle2D.Double(ox + 38.0, oy + 38.0, 6.0, 6.0))
            sg.dispose(); g.dispose(); return
        }
        // In device pixels: whole pixels per module, no smoothing.
        val t = g.transform
        val px = t.translateX + x0 * scale; val py = t.translateY
        g.transform = AffineTransform.getTranslateInstance(Math.round(px).toDouble(), Math.round(py).toDouble())
        val perModule = maxOf(1, (SYMBOL_POINTS * scale / q.size).toInt())
        val sidePx = kotlin.math.ceil(s * scale).toInt()
        g.color = Color.WHITE; g.fillRect(0, 0, sidePx, sidePx)
        g.color = Color.BLACK
        for (r in 0 until q.size) for (c in 0 until q.size) if (q.modules[r][c]) g.fillRect((c + QUIET) * perModule, (r + QUIET) * perModule, perModule, perModule)
        g.dispose()
    }
}

/**
 * Pair a Device (PairDeviceWindow.swift's PairDeviceView): 440 pt wide, 20 pt in, 14 pt between
 * blocks. A window a device opened leads with who asked and has no address (the device dialled it);
 * one opened here says how to find this PC, and both give the code to type and its countdown. Once
 * the code no longer works the QR code keeps its place, empty, and the line under it says why;
 * paired, it closes itself after 3 s.
 */
class PairView(private val actions: Actions) : JComponent() {
    interface Actions { fun cancel(); fun newCode(); fun done() }
    companion object { const val WIDTH = 440; const val PAD = 20; const val SPACING = 14 }

    var view: PairingView? = null; set(v) { field = v; rebuild() }
    val qr = QrView()
    private val buttons = ArrayList<PushButton>()
    private val headFont = MacType.font(MacType.headline)
    private val body = MacType.font(MacType.body)
    private val inner = WIDTH - 2 * PAD

    /** The blocks top to bottom: text in a font and colour, the QR code, a grid row, a warning, a check line. */
    private sealed class Block {
        class Text(val text: String, val headline: Boolean = false, val secondary: Boolean = false) : Block()
        object Qr : Block()
        class Grid(val label: String, val value: String, val code: Boolean, val or: String?) : Block()
        class Warn(val text: String) : Block()
        class Check(val text: String) : Block()
        /** The lower part's 10 pt spacing instead of 14 before the next block. */
        object Tight : Block()
    }
    private var blocks: List<Block> = emptyList()

    init { isOpaque = true; layout = null; add(qr) }

    private fun rebuild() {
        val v = view ?: return
        val waiting = v.phase is PairingCopy.Phase.Waiting
        val b = ArrayList<Block>()
        if (v.askedBy != null) { b += Block.Text(PairingCopy.askedLine(v.askedBy, null), headline = true); b += Block.Text(PairingCopy.ASKED_NEXT) }
        else b += Block.Text(PairingCopy.INTRO)
        b += Block.Qr
        when (val p = v.phase) {
            is PairingCopy.Phase.Waiting -> {
                if (v.askedBy == null) { b += Block.Text(PairingCopy.CANT_SCAN); b += Block.Tight
                    v.address?.let { a -> b += Block.Grid(PairingCopy.ADDRESS, a.primary, false, a.secondary); b += Block.Tight } }
                b += Block.Grid(PairingCopy.CODE, PairingCopy.grouped(v.code), true, null); b += Block.Tight
                b += Block.Text(PairingCopy.countdown(v.secondsLeft)); b += Block.Tight
                p.wrongFrom?.let { b += Block.Warn(PairingCopy.wrongCode(it, p.triesLeft)); b += Block.Tight }
                b += Block.Text(PairingCopy.CONTROL, secondary = true)
                if (v.askedBy != null) { b += Block.Tight; b += Block.Text(PairingCopy.DIDNT_ASK, secondary = true) }
            }
            is PairingCopy.Phase.Paired -> b += Block.Check(PairingCopy.ended(p)!!)
            else -> b += Block.Text(PairingCopy.ended(p)!!)
        }
        blocks = b
        qr.text = v.link; qr.spent = !waiting
        buttons.forEach { remove(it) }; buttons.clear()
        for (t in PairingCopy.buttons(v.phase)) buttons += PushButton(t) {
            when (t) { "Cancel" -> actions.cancel(); "New Code" -> actions.newCode(); else -> actions.done() }
        }.apply { isDefault = t == "New Code" || t == "Done" }
        buttons.forEach { add(it) }
        revalidate(); doLayout(); repaint()
    }

    private val labelWidth get() = kotlin.math.ceil(maxOf(TextMeasure.width(PairingCopy.ADDRESS, body), TextMeasure.width(PairingCopy.CODE, body))).toInt()

    private fun heightOf(bl: Block): Int = when (bl) {
        is Block.Text -> kotlin.math.ceil(TextMeasure.wrap(bl.text, if (bl.headline) headFont else body, inner.toDouble()).size * TextMeasure.lineHeight(if (bl.headline) headFont else body)).toInt()
        Block.Qr -> qr.preferredSize.height
        is Block.Grid -> kotlin.math.ceil(if (bl.code) TextMeasure.lineHeight(MacType.code) else TextMeasure.lineHeight(body) * (if (bl.or != null) 2 else 1) + (if (bl.or != null) 2 else 0)).toInt()
        is Block.Warn, is Block.Check -> kotlin.math.ceil(TextMeasure.wrap((bl as? Block.Warn)?.text ?: (bl as Block.Check).text, body, inner - 22.0).size * TextMeasure.lineHeight(body)).toInt()
        Block.Tight -> 0
    }

    /** The blocks' tops, with 14 pt between (10 pt after a Tight). */
    private fun tops(): List<Int> {
        val out = ArrayList<Int>()
        var y = PAD
        var gap = 0
        for (bl in blocks) {
            if (bl is Block.Tight) { gap = 10; out += y; continue }
            y += gap; out += y; y += heightOf(bl); gap = SPACING
        }
        return out + (y + gap)
    }

    fun contentHeight(): Int = tops().last() + (buttons.firstOrNull()?.preferredSize?.height ?: 0) + PAD
    override fun getPreferredSize() = Dimension(WIDTH, contentHeight())

    override fun doLayout() {
        val t = tops()
        blocks.forEachIndexed { i, bl -> if (bl == Block.Qr) { val d = qr.preferredSize; qr.setBounds(PAD, t[i], inner, d.height) } }
        var x = WIDTH - PAD
        for (b in buttons.asReversed()) { val d = b.preferredSize; x -= d.width; b.setBounds(x, t.last(), d.width, d.height); x -= 12 }
    }

    override fun paintComponent(g0: Graphics) {
        val g = SillSwing.smooth(g0)
        val c = HostTheme.c
        g.color = c.window.awt(); g.fillRect(0, 0, width, height)
        val t = tops()
        blocks.forEachIndexed { i, bl ->
            val y = t[i].toDouble()
            when (bl) {
                is Block.Text -> {
                    val f = if (bl.headline) headFont else body
                    TextMeasure.wrap(bl.text, f, inner.toDouble()).forEachIndexed { k, l -> SillSwing.text(g, l, PAD.toDouble(), y + k * TextMeasure.lineHeight(f), f, if (bl.secondary) c.secondary else c.label) }
                }
                is Block.Grid -> {
                    val vx = PAD + labelWidth + 14.0
                    val vf = if (bl.code) MacType.code else body
                    // First baselines aligned (`.leadingFirstTextBaseline`).
                    val base = y + TextMeasure.metrics(vf).ascent
                    SillSwing.text(g, bl.label, PAD.toDouble(), base - TextMeasure.metrics(body).ascent, body, c.secondary)
                    SillSwing.text(g, bl.value, vx, y, vf, c.label)
                    bl.or?.let {
                        val y2 = y + TextMeasure.lineHeight(body) + 2
                        SillSwing.text(g, "or", vx, y2, body, c.secondary)
                        SillSwing.text(g, it, vx + TextMeasure.width("or", body) + 4, y2, body, c.secondary)
                    }
                }
                is Block.Warn -> {
                    HostGlyphs.paint(g, Symbol.Warning, PAD.toDouble(), y + 1, 14.0, c.orange, c.window)
                    TextMeasure.wrap(bl.text, body, inner - 22.0).forEachIndexed { k, l -> SillSwing.text(g, l, PAD + 22.0, y + k * TextMeasure.lineHeight(body), body, c.orange) }
                }
                is Block.Check -> {
                    HostGlyphs.paint(g, Symbol.CheckCircle, PAD.toDouble(), y + 1, 15.0, c.accent, c.window)
                    SillSwing.text(g, bl.text, PAD + 22.0, y, body, c.label)
                }
                else -> {}
            }
        }
        g.dispose()
    }
}

/** The window round the view: not resizable, titled as Sill.app's; Esc cancels, Return takes the default button. */
class PairWindow(private val model: HostModel) : PairView.Actions {
    val frame = JFrame(PairingCopy.TITLE)
    val view = PairView(this)
    private var closeTimer: Timer? = null
    /** The last open code: a window that ended keeps showing what it was, spent. */
    private var lastCode = ""; private var lastLink = ""

    init {
        frame.isResizable = false
        frame.defaultCloseOperation = JFrame.DO_NOTHING_ON_CLOSE
        frame.contentPane = view
        frame.addWindowListener(object : WindowAdapter() { override fun windowClosing(e: WindowEvent) = cancel() })
        val keys = frame.rootPane.getInputMap(JComponent.WHEN_IN_FOCUSED_WINDOW)
        keys.put(KeyStroke.getKeyStroke(KeyEvent.VK_ESCAPE, 0), "cancel")
        keys.put(KeyStroke.getKeyStroke(KeyEvent.VK_ENTER, 0), "default")
        frame.rootPane.actionMap.put("cancel", object : AbstractAction() { override fun actionPerformed(e: java.awt.event.ActionEvent?) = cancel() })
        frame.rootPane.actionMap.put("default", object : AbstractAction() {
            override fun actionPerformed(e: java.awt.event.ActionEvent?) { when (view.view?.phase) { is PairingCopy.Phase.Paired -> done(); PairingCopy.Phase.Expired, PairingCopy.Phase.Stopped -> newCode(); else -> {} } }
        })
    }

    val isShowing get() = frame.isVisible

    /** Follows the host: shows the window, in front, when a device asked; updates it while it shows. */
    fun refresh(open: Boolean = false) {
        val p = model.pairing() ?: run { if (frame.isVisible && view.view != null) update(view.view!!.copy(phase = PairingCopy.Phase.Closed)); return }
        if (p.code.isNotEmpty()) { lastCode = p.code; lastLink = p.link }
        val v = p.copy(code = p.code.ifEmpty { lastCode }, link = p.link.ifEmpty { lastLink })
        val asked = p.phase is PairingCopy.Phase.Waiting && p.askedBy != null && view.view?.askedBy == null
        if (frame.isVisible || open || asked) update(v)
        if ((open || asked) && v.link.isNotEmpty()) {
            if (!frame.isVisible) frame.setLocationRelativeTo(null)
            frame.isVisible = true; frame.toFront(); frame.state = JFrame.NORMAL
        }
    }

    private fun update(v: PairingView) {
        val before = view.view?.phase
        view.view = v
        frame.pack()
        if (v.phase is PairingCopy.Phase.Paired && before !is PairingCopy.Phase.Paired) {
            closeTimer?.stop(); closeTimer = Timer(3000) { done() }.apply { isRepeats = false; start() }
        }
    }

    override fun cancel() { if (view.view?.phase is PairingCopy.Phase.Waiting) model.cancelPairing(); close() }
    override fun newCode() { model.openPairing(); refresh(open = true) }
    override fun done() = close()
    private fun close() { closeTimer?.stop(); frame.isVisible = false; view.view = null }
}
