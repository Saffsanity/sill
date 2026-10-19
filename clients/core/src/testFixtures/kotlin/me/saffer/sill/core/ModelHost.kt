package me.saffer.sill.core

import java.io.IOException
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.security.SecureRandom
import java.util.Collections
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLSocket

/**
 * TEST ONLY. A model of the Mac's TLS home door (docs/home-pairing-plan.md, the host's Door and
 * RemoteAccess), on 127.0.0.1, for the clients' tests: both ALPNs, pairing by ask, code and link with
 * the host's proofs and answers, a session that requires the device's hello first, and a catalog,
 * video, pongs and goodbyes on cue. It holds the rules this repository's Swift host holds the real
 * clients to, as far as a client can see them; it is not the host, and docs/clients-plan.md says
 * what only a real Mac can show.
 */
class ModelHost(
    val macName: String = "Model Mac",
    /** Frames to stream once a source is picked: the parameter sets, then (keyframe, access unit) pairs. */
    @Volatile var video: Pair<ParameterSets, List<Pair<Boolean, ByteArray>>>? = defaultVideo(),
    val frameIntervalMs: Long = 16,
) : AutoCloseable {
    val identity = Identity.generate()
    val fingerprint get() = identity.fingerprint
    val macID = MacId.make(identity.fingerprint)
    val recognitionKey = ByteArray(32).also(SecureRandom()::nextBytes)
    val launchID = java.util.UUID.randomUUID().toString()
    @Volatile var requirePairing = true
    val paired: MutableSet<String> = Collections.synchronizedSet(HashSet())       // base64url fingerprints
    private val server = ServerSocket(0, 50, InetAddress.getLoopbackAddress())
    val port get() = server.localPort
    val address get() = InetSocketAddress(InetAddress.getLoopbackAddress(), port)
    @Volatile private var running = true

    // The pairing window: a code (typed path) and a secret (link path), five wrong tries.
    @Volatile var code: String? = null
        private set
    @Volatile var secret: ByteArray? = null
        private set
    @Volatile private var triesLeft = 5
    val pairRequests = CopyOnWriteArrayList<PairRequest>()

    // What sessions sent, for the tests to look at.
    val sessions = CopyOnWriteArrayList<HostSession>()
    val violations = CopyOnWriteArrayList<String>()

    var windows = listOf(WindowInfo(101, "Notes", "Notes", "com.apple.Notes", 1200, 800), WindowInfo(102, "Terminal — zsh", "Terminal", "com.apple.Terminal", 800, 500))

    init {
        Thread({ while (running) { val s = try { server.accept() } catch (_: IOException) { break }; Thread { serve(s) }.apply { isDaemon = true }.start() } }, "model-host").apply { isDaemon = true }.start()
    }

    /** Pair a Device… on the Mac: a fresh code and secret, five tries. */
    fun openWindow(): String {
        code = PairingCode.generate()
        secret = ByteArray(16).also(SecureRandom()::nextBytes)
        triesLeft = 5
        return code!!
    }

    fun closeWindow() { code = null; secret = null }

    /** The window's QR code: its link, with this door's address. */
    fun link(): String {
        if (secret == null) openWindow()
        return PairLink(fingerprint, secret!!, macName, port, listOf(ParsedAddress("127.0.0.1", port, ParsedAddress.Kind.IPV4))).url
    }

    /** The TXT record this door would advertise. */
    fun txt(): Map<String, String?> = mapOf(RecognitionTag.TXT_KEY to RecognitionTag.make(recognitionKey), HomeDoorTxt.KEY to if (requirePairing) "1" else "0")

    fun found(name: String = macName) = FoundService(name, "model.local.", port, listOf(InetAddress.getLoopbackAddress()), txt(), "lo")

    fun remove(fp: ByteArray) {
        paired.remove(Base64Url.encode(fp))
        for (s in sessions) if (s.deviceFingerprint?.contentEquals(fp) == true) s.goodbye(Goodbye(Goodbye.REMOVED))
    }

    fun macInfo(addresses: List<MacAddress> = listOf(MacAddress("127.0.0.1", port, "vpn", "This Mac"))) =
        MacInfoSignature.sign(MacInfo(macID = macID, name = macName, issuedAt = System.currentTimeMillis() / 1e3, remoteAccess = true,
            remotePort = port, internet = false, addresses = addresses), identity.keyPair)

    private fun serve(raw: java.net.Socket) {
        val ctx = SillTlsServer.context(identity) { fp, alpn ->
            fp != null && (alpn == SillTls.PAIRING_ALPN || !requirePairing || paired.contains(Base64Url.encode(fp)))
        }
        val s = ctx.socketFactory.let { (it as javax.net.ssl.SSLSocketFactory).createSocket(raw, null, raw.port, true) } as SSLSocket
        SillTlsServer.configure(s)
        try {
            s.startHandshake()
            s.soTimeout = 15_000
            // The client's certificate is judged after its handshake: read once so a refusal reaches it.
            if (s.applicationProtocol == SillTls.PAIRING_ALPN) pair(s) else HostSession(s).also { sessions.add(it) }.run()
        } catch (_: IOException) {
            try { s.close() } catch (_: IOException) {}
        }
    }

    private fun pair(s: SSLSocket) {
        s.use {
            val m = MessageReader(s.inputStream, cap = { StreamMessage.MAX_PAIRING_PAYLOAD.toLong() }).next() ?: return
            if (m.kind != Kind.PAIR_REQUEST) { violations.add("pairing connection's first message was kind ${m.kind}"); return }
            val req = PairRequest.fromJson(JsonObj.parse(m.payload))
            pairRequests.add(req)
            val devFp = (s.session.peerCertificates[0] as java.security.cert.X509Certificate).let { Spki.fingerprint(it.publicKey)!! }
            fun answer(r: PairResult) { s.outputStream.write(StreamMessage.json(Kind.PAIR_RESULT, r.toJson()).serialized()); s.outputStream.flush() }
            if (req.v != PairRequest.VERSION) return answer(PairResult(ok = false, reason = PairResult.CLOSED))
            when (req.method) {
                PairRequest.ASK -> {
                    if (paired.contains(Base64Url.encode(devFp))) return answer(okResult(null, devFp))
                    if (code == null) openWindow()
                    answer(PairResult(ok = false, reason = PairResult.SHOWN))
                }
                PairRequest.CANCEL -> { closeWindow(); answer(PairResult(ok = false, reason = PairResult.CLOSED)) }
                PairRequest.CODE, PairRequest.QR -> {
                    val key = when {
                        req.method == PairRequest.CODE -> code?.let { PairingProof.codeKey(it, fingerprint) }
                        else -> secret
                    } ?: return answer(PairResult(ok = false, reason = PairResult.CLOSED))
                    val proof = Base64Url.decode(req.proof)
                    if (proof == null || !PairingProof.isValidDeviceProof(proof, key, devFp, fingerprint)) {
                        triesLeft--
                        if (triesLeft <= 0) { closeWindow(); return answer(PairResult(ok = false, reason = PairResult.STOPPED)) }
                        return answer(PairResult(ok = false, reason = PairResult.CODE, triesLeft = triesLeft))
                    }
                    paired.add(Base64Url.encode(devFp))
                    closeWindow()
                    answer(okResult(key, devFp))
                }
                else -> answer(PairResult(ok = false, reason = PairResult.CLOSED))
            }
        }
    }

    private fun okResult(key: ByteArray?, devFp: ByteArray) = PairResult(ok = true,
        proof = key?.let { Base64Url.encode(PairingProof.macProof(it, fingerprint, devFp)) }, macID = macID, name = macName,
        recognitionKey = Base64Url.encode(recognitionKey))

    /** One session connection, as the host serves it. */
    inner class HostSession(private val s: SSLSocket) {
        val deviceFingerprint: ByteArray? = (s.session.peerCertificates.firstOrNull() as? java.security.cert.X509Certificate)?.let { Spki.fingerprint(it.publicKey) }
        val received = LinkedBlockingQueue<StreamMessage>()
        val all = CopyOnWriteArrayList<StreamMessage>()
        @Volatile var hello: Hello? = null
        @Volatile var active: StreamSource = StreamSource.None
        @Volatile var silent = false
        @Volatile var answerPings = true
        private val out = s.outputStream
        @Volatile private var streaming: Thread? = null

        @Synchronized fun send(m: StreamMessage) { if (!silent) { out.write(m.serialized()); out.flush() } }

        /** The Mac's menus as a subscriber is sent them: the top level, and each menu's items by its id (TEST ONLY: a VS Code-like app). */
        @Volatile var menuApp = "Code"
        @Volatile var menuItems: Map<String, List<MacMenuItem>> = demoMenus
        val presses = java.util.concurrent.LinkedBlockingQueue<PressMenuItem>()
        @Volatile private var subscribed = false

        private fun menus(m: StreamMessage) {
            if (m.kind == Kind.FETCH_MENU) {
                val f = FetchMenu.fromJson(JsonObj.parse(m.payload))
                if (f.id == null) {
                    subscribed = true
                    val top = demoTop
                    send(StreamMessage.json(Kind.MAC_MENU, MacMenu(version = 1, app = menuApp, menus = top).toJson()))
                    return
                }
                if (!subscribed) { violations.add("a fetch before the subscription"); return }
                val title = (demoTop + menuItems.values.flatten()).firstOrNull { it.id == f.id }?.title
                if (f.version != 1 || title != f.title) {
                    send(StreamMessage.json(Kind.MAC_MENU, MacMenu(version = 1, answering = f.token, menu = f.id, note = "The menus changed. Open the menu again.").toJson())); return
                }
                send(StreamMessage.json(Kind.MAC_MENU, MacMenu(version = 1, answering = f.token, menu = f.id, items = menuItems[f.id] ?: emptyList()).toJson()))
            } else {
                val p = PressMenuItem.fromJson(JsonObj.parse(m.payload))
                presses.add(p)
                send(StreamMessage.json(Kind.MAC_MENU, MacMenu(version = 1, answering = p.token, pressed = true).toJson()))
            }
        }

        fun list() = WindowList(macName, windows, active, launchID, "0.6.0", SillProtocol.CURRENT, gestures = 1, clipboard = 1)

        fun run() {
            val reader = MessageReader(s.inputStream, cap = { StreamMessage.MAX_CLIENT_PAYLOAD.toLong() })
            s.soTimeout = 0
            try {
                val first = reader.next() ?: return
                if (first.kind != Kind.HELLO) violations.add("a session's first message was kind ${first.kind}, not the hello")
                else hello = Hello.fromJson(JsonObj.parse(first.payload))
                record(first)
                send(StreamMessage.json(Kind.WINDOW_LIST, list().toJson()))
                send(StreamMessage.json(Kind.HOST_SETTINGS, HostSettingsState(StreamSettings(60, 15_000_000, 2.0, false, false, false), true, true,
                    softwareEncoder = false).toJson()))
                send(StreamMessage.json(Kind.MAC_INFO, macInfo().toJson()))
                while (true) {
                    val m = reader.next() ?: break
                    record(m)
                    when (m.kind) {
                        Kind.PING -> if (answerPings) send(StreamMessage(Kind.PONG, 0.0, false, m.payload))
                        Kind.SELECT_SOURCE -> select(StreamSource.fromJson(JsonObj.parse(m.payload)))
                        Kind.HELLO -> violations.add("a second hello")
                        Kind.FETCH_MENU, Kind.PRESS_MENU_ITEM -> menus(m)
                    }
                }
            } catch (_: IOException) {
            } finally {
                streaming?.interrupt()
                try { s.close() } catch (_: IOException) {}
            }
        }

        private fun record(m: StreamMessage) { all.add(m); received.add(m) }

        private fun select(src: StreamSource) {
            active = src
            send(StreamMessage.json(Kind.WINDOW_LIST, list().toJson()))
            streaming?.interrupt()
            val v = video ?: return
            if (src == StreamSource.None) return
            streaming = Thread {
                try {
                    send(StreamMessage(Kind.PARAMETER_SETS, now(), false, v.first.encoded()))
                    for ((key, au) in v.second) {
                        send(StreamMessage(Kind.FRAME, now(), key, au))
                        Thread.sleep(frameIntervalMs)
                    }
                } catch (_: Exception) {}
            }.apply { isDaemon = true; start() }
        }

        fun goodbye(g: Goodbye) {
            try { send(StreamMessage.json(Kind.GOODBYE, g.toJson())) } catch (_: IOException) {}
            close()
        }

        fun close() = try { s.close() } catch (_: IOException) {}

        /** The next message of `kind` the device sends within `seconds`. */
        fun await(kind: Int, seconds: Double = 5.0): StreamMessage? {
            val end = System.nanoTime() + (seconds * 1e9).toLong()
            while (true) {
                val left = end - System.nanoTime()
                if (left <= 0) return null
                val m = received.poll(left, TimeUnit.NANOSECONDS) ?: return null
                if (m.kind == kind) return m
            }
        }
    }

    fun latestSession(seconds: Double = 5.0): HostSession? {
        val end = System.nanoTime() + (seconds * 1e9).toLong()
        val before = sessions.size
        while (System.nanoTime() < end) { if (sessions.isNotEmpty()) return sessions.last(); Thread.sleep(10) }
        return sessions.lastOrNull().takeIf { sessions.size > before || it != null }
    }

    override fun close() {
        running = false
        server.close()
        sessions.forEach { it.close() }
    }

    private fun now() = System.currentTimeMillis() / 1e3

    companion object {
        /** Stand-in HEVC: the shape of VideoToolbox's output (VPS, SPS, PPS; IDR then TRAIL units), not decodable pictures. */
        fun defaultVideo(): Pair<ParameterSets, List<Pair<Boolean, ByteArray>>> {
            val sets = ParameterSets(4, listOf(byteArrayOf(0x40, 0x01, 0x0C), byteArrayOf(0x42, 0x01, 0x01), byteArrayOf(0x44, 0x01, 0xC1.toByte())))
            fun au(type: Int, n: Int): ByteArray {
                val nal = byteArrayOf((type shl 1).toByte(), 0x01) + ByteArray(n) { (it * 7).toByte() }
                return java.nio.ByteBuffer.allocate(4 + nal.size).putInt(nal.size).put(nal).array()
            }
            return sets to (listOf(true to au(19, 40)) + (1..5).map { false to au(1, 20) })
        }
    }
}


/** TEST ONLY: the model Mac's menus, after the iOS harness's `-SillMacMenu code` (VS Code's). */
val demoTop = listOf("Code", "File", "Edit", "Selection", "View", "Go", "Run", "Terminal", "Window", "Help")
    .mapIndexed { i, t -> MacMenuItem(id = "${i + 1}", title = t, submenu = true) }

val demoMenus: Map<String, List<MacMenuItem>> = mapOf(
    "1" to listOf(MacMenuItem("1.0", "About Visual Studio Code"), MacMenuItem("1.1", separator = true), MacMenuItem("1.2", "Settings", submenu = true),
        MacMenuItem("1.3", separator = true), MacMenuItem("1.4", "Hide Visual Studio Code", key = "⌘H"), MacMenuItem("1.5", "Quit Visual Studio Code", key = "⌘Q")),
    "1.2" to listOf(MacMenuItem("1.2.0", "Settings", key = "⌘,"), MacMenuItem("1.2.1", "Themes")),
    "2" to listOf(MacMenuItem("2.0", "New Text File", key = "⌘N"), MacMenuItem("2.1", "New Window", key = "⇧⌘N"), MacMenuItem("2.2", separator = true),
        MacMenuItem("2.3", "Open…", key = "⌘O"), MacMenuItem("2.4", "Open Recent", submenu = true), MacMenuItem("2.5", separator = true),
        MacMenuItem("2.6", "Save", key = "⌘S"), MacMenuItem("2.7", "Save As…", key = "⇧⌘S"), MacMenuItem("2.8", "Auto Save", mark = "✓"),
        MacMenuItem("2.9", separator = true), MacMenuItem("2.10", "Revert File", enabled = false), MacMenuItem("2.11", "Close Editor", key = "⌘W")),
    "2.4" to listOf(MacMenuItem("2.4.0", "~/sill"), MacMenuItem("2.4.1", "~/notes.md")),
    "3" to listOf(MacMenuItem("3.0", "Undo", key = "⌘Z"), MacMenuItem("3.1", "Redo", key = "⇧⌘Z"), MacMenuItem("3.2", separator = true),
        MacMenuItem("3.3", "Cut", key = "⌘X"), MacMenuItem("3.4", "Copy", key = "⌘C"), MacMenuItem("3.5", "Paste", key = "⌘V")),
    "5" to listOf(MacMenuItem("5.0", "Command Palette…", key = "⇧⌘P"), MacMenuItem("5.1", "Word Wrap", key = "⌥Z", mark = "✓")),
    "9" to listOf(MacMenuItem("9.0", "Minimize", key = "⌘M"), MacMenuItem("9.1", "Zoom")),
    "10" to listOf(MacMenuItem("10.0", "Welcome"), MacMenuItem("10.1", "Documentation")),
)
