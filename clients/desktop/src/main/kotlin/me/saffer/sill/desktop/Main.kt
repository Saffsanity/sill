package me.saffer.sill.desktop

import me.saffer.sill.core.ClientInfo
import me.saffer.sill.core.ClientListener
import me.saffer.sill.core.GoodbyePolicy
import me.saffer.sill.core.IdentityStore
import me.saffer.sill.core.MacRow
import me.saffer.sill.core.PairOutcome
import me.saffer.sill.core.PairingPrompt
import me.saffer.sill.core.SessionListener
import me.saffer.sill.core.SillClient
import me.saffer.sill.core.SillSession
import me.saffer.sill.core.ui.Symbol
import me.saffer.sill.core.ui.Ui
import me.saffer.sill.swingui.ListItem
import me.saffer.sill.swingui.SillSwing
import java.awt.Dimension
import java.net.InetAddress
import javax.swing.JFrame
import javax.swing.JMenuItem
import javax.swing.JPopupMenu
import javax.swing.SwingUtilities

/** Who this PC is, for its hello, its stats and its pairing requests. */
fun desktopInfo(): ClientInfo {
    val host = try { InetAddress.getLocalHost().hostName } catch (_: Exception) { null } ?: System.getenv("COMPUTERNAME") ?: "PC"
    val os = System.getProperty("os.name")
    val version = Main::class.java.`package`?.implementationVersion ?: "0.6.0"
    val platform = if (os.lowercase().startsWith("windows")) "Windows" else os
    return ClientInfo(appVersion = version, build = "1", device = "$platform ($host)", noun = "PC", model = os, name = host)
}

/** Routes the session's stream callbacks to the open stream window. */
class StreamRouter : SessionListener {
    @Volatile var target: SessionListener? = null
    private fun t() = target
    override fun onWindowList(list: me.saffer.sill.core.WindowList) { t()?.onWindowList(list) }
    override fun onThumbnail(windowID: Long, jpeg: ByteArray) { t()?.onThumbnail(windowID, jpeg) }
    override fun onAppList(apps: List<me.saffer.sill.core.AppInfo>) { t()?.onAppList(apps) }
    override fun onVideoFormat(sets: me.saffer.sill.core.ParameterSets) { t()?.onVideoFormat(sets) }
    override fun onFrame(annexB: ByteArray, keyframe: Boolean, timestamp: Double) { t()?.onFrame(annexB, keyframe, timestamp) }
    override fun onCursorShape(shape: me.saffer.sill.core.CursorShape) { t()?.onCursorShape(shape) }
    override fun onMacPointer(position: Pair<Double, Double>?) { t()?.onMacPointer(position) }
    override fun onHostSettings(state: me.saffer.sill.core.HostSettingsState) { t()?.onHostSettings(state) }
    override fun onClipboard(text: String) { t()?.onClipboard(text) }
    override fun onAppIcon(bundleID: String, png: ByteArray) { t()?.onAppIcon(bundleID, png) }
    override fun onStats(stats: me.saffer.sill.core.ClientStats) { t()?.onStats(stats) }
    override fun onMacMenu(menu: me.saffer.sill.core.MacMenu) { t()?.onMacMenu(menu) }
}

/**
 * The connect window and the app's life (ConnectScreen in ContentView.swift, drawn from the shared
 * design layer): the column (ConnectLayout) with "Connect to a Mac", the status line, the Macs on
 * the network and the saved ones as rows, and Add a Mac…; Add a Mac's card in the column's place
 * (an address and a code, or a pairing link), and the card a Mac's pairing code asks for; the
 * footer; and the stream window while a session runs.
 */
class Main(private val store: me.saffer.sill.core.KeyValueStore = DesktopStore()) : ClientListener {
    private val router = StreamRouter()
    val client = SillClient(desktopInfo(), store, IdentityStore.InKeyValue(store), this, router,
        allowPlain = System.getenv("SILL_DEV_PLAIN") == "1")
    val frame = JFrame("Sill")
    val connect = ConnectView()
    /** The Macs' rows (their keys are the rows' ids). */
    val rows get() = connect.rows
    private var macRows: List<MacRow> = emptyList()
    private var status = ""
    @Volatile var stream: StreamFrame? = null
        private set

    init {
        connect.rows.onPick = { id -> macRows.firstOrNull { it.id == id }?.let(client::connect) }
        connect.rows.onMenu = { id, e -> macRows.firstOrNull { it.id == id }?.saved?.let { s ->
            JPopupMenu().apply { add(JMenuItem("Forget ${s.name}").apply { addActionListener { client.forget(s.macID) } }) }.show(connect.rows, e.x, e.y)
        } }
        connect.addMac.onAction = { connect.showCard(ConnectView.Card.Address) }
        connect.onPairAddress = { address, code -> connect.working("Pairing…"); client.addByAddress(address, code) { report(it) } }
        connect.onPairLink = { link -> connect.working("Pairing…"); client.pairWithLink(link.trim()) { report(it) } }
        connect.onPairCode = { prompt, code -> connect.working("Pairing…"); client.submitCode(prompt, code) { report(it) } }
        connect.onCancelPrompt = { prompt -> client.cancelPrompt(prompt) }
        frame.contentPane = connect
        frame.defaultCloseOperation = JFrame.EXIT_ON_CLOSE
        frame.size = Dimension(560, 640)
        frame.minimumSize = Dimension(380, 440)
        frame.setLocationRelativeTo(null)
    }

    fun start() { client.start(); frame.isVisible = true }

    private fun report(out: PairOutcome) = SwingUtilities.invokeLater {
        when (out) {
            is PairOutcome.Paired -> { connect.paired("Paired with ${out.mac.name}."); connect.showRows() }
            is PairOutcome.Refused -> connect.problem(out.words)
            is PairOutcome.Failed -> connect.problem(out.words)
        }
    }

    private fun publishRows() {
        connect.rows.items = macRows.map { r ->
            ListItem.Row(r.id, r.name, r.word, Ui.connectRowHeight, highlighted = false, badge = Symbol.Desktop,
                tooltip = r.word?.let { "${r.name}, $it" } ?: r.name)
        }
        connect.revalidate(); connect.repaint()
    }

    // MARK: ClientListener (worker threads)

    override fun onRows(rows: List<MacRow>) = SwingUtilities.invokeLater { macRows = rows; publishRows() }

    override fun onStatus(text: String?) = SwingUtilities.invokeLater { status = text ?: ""; connect.status.text = status; connect.revalidate() }

    override fun onPairingPrompt(prompt: PairingPrompt) = SwingUtilities.invokeLater { connect.showPrompt(prompt) }

    /** Synchronous: the window must be listening before the session's first message arrives. */
    override fun onSessionStarted(session: SillSession, mac: String) = onUi {
        stream?.close()
        val s = StreamFrame(session, mac, store) { client.disconnect() }
        router.target = s
        stream = s
        s.isVisible = true
        frame.isVisible = false
        connect.showRows()
    }

    override fun onSessionEnded(outcome: GoodbyePolicy.Outcome) = SwingUtilities.invokeLater {
        router.target = null
        stream?.close()
        stream = null
        status = outcome.text
        connect.status.text = status
        frame.isVisible = true
    }
}

private fun onUi(f: () -> Unit) { if (SwingUtilities.isEventDispatchThread()) f() else SwingUtilities.invokeAndWait(f) }

/**
 * `Sill --self-test`: what the packaged runtime needs, without a Mac or a window: FFmpeg's HEVC
 * decoder loads, a P-256 identity and its certificate are made, a TLS 1.3 context builds. Exits 0
 * when all three do; for a packaged build's check and for support.
 */
fun selfTest(): Int {
    return try {
        val codec = org.bytedeco.ffmpeg.global.avcodec.avcodec_find_decoder(org.bytedeco.ffmpeg.global.avcodec.AV_CODEC_ID_HEVC)
        check(codec != null && !codec.isNull) { "no HEVC decoder" }
        println("FFmpeg: ${codec.long_name().string}")
        val id = me.saffer.sill.core.Identity.generate()
        println("Identity: ${me.saffer.sill.core.MacId.shortName(id.fingerprint)}, certificate ${id.certificateDER.size} bytes")
        javax.net.ssl.SSLContext.getInstance("TLSv1.3").init(null, null, null)
        println("TLS 1.3: available")
        println("Self-test passed on ${System.getProperty("os.name")} ${System.getProperty("os.arch")}, Java ${System.getProperty("java.version")}")
        0
    } catch (e: Throwable) {
        System.err.println("Self-test failed: $e")
        1
    }
}

fun main(args: Array<String>) {
    if ("--self-test" in args) kotlin.system.exitProcess(selfTest())
    System.setProperty("sun.java2d.uiScale.enabled", "true")
    SwingUtilities.invokeLater { SillSwing.install(); Main().start() }
}
