package me.saffer.sill.core

import java.io.EOFException
import java.io.IOException
import java.io.InputStream
import java.nio.ByteBuffer
import java.util.concurrent.Executors
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/** Time, injectable for tests: a monotonic clock and the wall clock, both in seconds. */
interface Clock {
    fun mono(): Double
    fun wall(): Double

    object System : Clock {
        override fun mono() = java.lang.System.nanoTime() / 1e9
        override fun wall() = java.lang.System.currentTimeMillis() / 1e3
    }
}

/**
 * Reads the Mac's messages (iOSClient/MessageReader.swift): each header, then the payload in pieces
 * of at most 256 KiB, every piece a sign of life; a header announcing more than a device accepts of
 * its kind ends the session before any payload is read. Null at a clean end between messages.
 */
class MessageReader(private val input: InputStream, private val cap: (Int) -> Long = StreamMessage::hostPayloadCap,
                    private val onBytes: () -> Unit = {}) {
    class TooBig(val kind: Int, val length: Long) : IOException("kind $kind announced $length bytes")

    fun next(): StreamMessage? {
        val header = ByteArray(StreamMessage.HEADER_LENGTH)
        val first = input.read(header, 0, header.size)
        if (first < 0) return null
        readFully(header, first, header.size - first)
        onBytes()
        val h = StreamMessage.parseHeader(header)!!
        if (h.payloadLength > cap(h.kind)) throw TooBig(h.kind, h.payloadLength)
        val payload = ByteArray(h.payloadLength.toInt())
        var off = 0
        while (off < payload.size) {
            val n = minOf(PIECE, payload.size - off)
            readFully(payload, off, n)
            off += n
            onBytes()
        }
        return StreamMessage(h.kind, h.timestamp, h.isKeyframe, payload)
    }

    private fun readFully(b: ByteArray, off: Int, len: Int) {
        var o = off
        val end = off + len
        while (o < end) {
            val n = input.read(b, o, end - o)
            if (n < 0) throw EOFException("the connection ended inside a message")
            o += n
        }
    }

    companion object { const val PIECE = 256 * 1024 }
}

/**
 * Keyframe gating (HEVCDisplayView.swift): a repeat of the same parameter sets changes nothing; new
 * ones start a new format, and frames are dropped until a keyframe arrives in it.
 */
class VideoGate {
    sealed class Out {
        data class Format(val sets: ParameterSets) : Out()
        class Decode(val annexB: ByteArray, val keyframe: Boolean, val timestamp: Double) : Out()
        object Drop : Out()
    }

    var sets: ParameterSets? = null
        private set
    private var waitingForKeyframe = true

    fun parameterSets(payload: ByteArray): Out? {
        val p = ParameterSets.decode(payload) ?: return null
        if (p == sets) return null
        sets = p
        waitingForKeyframe = true
        return Out.Format(p)
    }

    fun frame(payload: ByteArray, keyframe: Boolean, timestamp: Double): Out {
        val p = sets ?: return Out.Drop
        if (waitingForKeyframe && !keyframe) return Out.Drop
        val annexB = AccessUnit.toAnnexB(payload, p.nalUnitHeaderLength) ?: return Out.Drop
        waitingForKeyframe = false
        return Out.Decode(annexB, keyframe, timestamp)
    }

    /** The decoder failed: wait for the next keyframe (and ask for one: the caller's job). */
    fun decoderFailed() { waitingForKeyframe = true }
}

/**
 * One second's client stats (Viewport.swift's ClientStats): the frames counted, the median frame
 * age and round trip, -1 for a second without a sample, and their maxima.
 */
class StatsWindow(private val clock: Clock) {
    private var start = clock.mono()
    private var frames = 0
    private val ages = ArrayList<Int>()
    private val rtts = ArrayList<Int>()
    /** The worst round trip of the last second that measured one, kept through seconds without a pong. */
    var lastRttMaxMs = -1
        private set

    @Synchronized fun frame(hostTimestamp: Double) {
        frames++
        ages.add(((clock.wall() - hostTimestamp) * 1000).coerceIn(0.0, 86_400_000.0).toInt())
    }

    @Synchronized fun rtt(ms: Int) { rtts.add(ms.coerceAtLeast(0)) }

    @Synchronized fun close(device: String): ClientStats {
        val now = clock.mono()
        val length = (now - start).coerceAtLeast(0.001)
        fun median(l: List<Int>) = if (l.isEmpty()) -1 else l.sorted()[l.size / 2]
        val s = ClientStats(fps = Math.round(frames / length).toInt(), frameAgeMs = median(ages), rttMs = median(rtts), device = device,
            frameAgeMaxMs = ages.maxOrNull() ?: -1, rttMaxMs = rtts.maxOrNull() ?: -1)
        if (rtts.isNotEmpty()) lastRttMaxMs = rtts.max()
        start = now; frames = 0; ages.clear(); rtts.clear()
        return s
    }
}

/**
 * When the device asks for the Desktop by itself (DiscoveryPolicy.autoDesktop): whenever a window
 * list says nothing streams, unless the last such pick was under 10 s ago. After the Desktop or
 * nothing, at once; after a window the list no longer has (it closed), 2 s plus the worst round trip
 * later, and only if nothing changed meanwhile; after a window still listed, never (the Mac stops a
 * stream for its own reasons and the person picks again).
 */
object AutoDesktop {
    const val SPACING = 10.0

    sealed class Decision {
        object None : Decision()
        object Now : Decision()
        data class After(val seconds: Double, val window: Long) : Decision()
    }

    fun decide(previous: StreamSource, list: WindowList, lastAutoAt: Double?, now: Double, rttMaxMs: Int): Decision {
        if (list.active != StreamSource.None) return Decision.None
        if (lastAutoAt != null && now - lastAutoAt < SPACING) return Decision.None
        return when (previous) {
            StreamSource.None, StreamSource.Desktop -> Decision.Now
            is StreamSource.Window ->
                if (list.windows.any { it.id == previous.id }) Decision.None
                else Decision.After(2.0 + rttMaxMs.coerceAtLeast(0) / 1000.0, previous.id)
        }
    }
}

/** How a session ended, and what the Mac said if it said goodbye. */
sealed class SessionEnd {
    abstract val goodbye: Goodbye?
    /** The Mac closed the connection (after its goodbye, if any). */
    data class Closed(override val goodbye: Goodbye?) : SessionEnd()
    /** Nothing arrived for max(6 s, 4 × the worst round trip). */
    data class Lost(override val goodbye: Goodbye? = null) : SessionEnd()
    /** No window list within 10 s of a TLS session's start. */
    data class NoWindowList(override val goodbye: Goodbye? = null) : SessionEnd()
    data class Failed(val error: IOException, override val goodbye: Goodbye?) : SessionEnd()
    /** This client ended it. */
    data class ByUs(override val goodbye: Goodbye? = null) : SessionEnd()
}

/** What a session tells its UI. Every call is on one of the session's threads, never the UI's. */
interface SessionListener {
    fun onConnected(list: WindowList) {}
    fun onWindowList(list: WindowList) {}
    fun onThumbnail(windowID: Long, jpeg: ByteArray) {}
    fun onAppIcon(bundleID: String, png: ByteArray) {}
    fun onAppList(apps: List<AppInfo>) {}
    /** New parameter sets: (re)configure the decoder. */
    fun onVideoFormat(sets: ParameterSets) {}
    /** One access unit, Annex B, in a format announced before, starting at a keyframe. */
    fun onFrame(annexB: ByteArray, keyframe: Boolean, timestamp: Double) {}
    fun onCursorShape(shape: CursorShape) {}
    /** Where to draw the Mac's pointer (frame fractions), or null to hide it. */
    fun onMacPointer(position: Pair<Double, Double>?) {}
    fun onHostSettings(state: HostSettingsState) {}
    /** A kind 18 that verified and whose signer is this connection's Mac. */
    fun onMacInfo(info: MacInfo, fingerprint: ByteArray) {}
    fun onMacMenu(menu: MacMenu) {}
    fun onClipboard(text: String) {}
    fun onStats(stats: ClientStats) {}
    fun onEnded(end: SessionEnd) {}
}

/** Who this client is, for its hello and its stats. */
data class ClientInfo(
    val appVersion: String,
    val build: String,
    /** "Windows (DESKTOP-1)", "Android (Pixel 9)": what the Mac shows for this device. */
    val device: String,
    /** "PC", "phone", "tablet": the words' "this ‹device›". */
    val noun: String,
    /** The model, for a pairing request ("Pixel 9"). */
    val model: String?,
    /** The name a pairing request gives ("DESKTOP-1"). */
    val name: String,
)

/**
 * One session with a Mac over an already connected [Connection] (StreamClient.swift's session):
 * the hello first, then the catalog, video and input. Counts as connected at its first window list.
 *
 * Threads: a reader, a writer (so a caller, the UI's thread included, never waits on the network),
 * and a timer for pings (every 0.25 s), liveness, stats (every second) and coalesced pointer moves.
 */
class SillSession(
    val connection: Connection,
    private val client: ClientInfo,
    private val listener: SessionListener,
    private val clock: Clock = Clock.System,
    /** A TLS session must show its first window list within this many seconds. */
    private val firstListDeadline: Double = if (connection.alpn != null) 10.0 else Double.MAX_VALUE,
    /** Whether to subscribe to the Mac's clipboard when it offers one. */
    @Volatile var shareClipboard: Boolean = true,
) {
    private val outbox = LinkedBlockingQueue<StreamMessage>()
    private val timer: ScheduledExecutorService = Executors.newSingleThreadScheduledExecutor { r -> Thread(r, "sill-timer").apply { isDaemon = true } }
    private val ended = AtomicBoolean(false)
    private val gate = VideoGate()
    private val stats = StatsWindow(clock)
    @Volatile private var lastReceivedAt = clock.mono()
    private val startedAt = clock.mono()
    @Volatile private var goodbye: Goodbye? = null

    @Volatile var windowList: WindowList? = null
        private set
    val connected get() = windowList != null
    @Volatile var hostSettings: HostSettingsState? = null
        private set

    // Input bookkeeping: one coalesced pointer move at most every 8 ms, and the count of input
    // messages sent on this connection, which a kind 26's `seen` is judged against.
    private val inputLock = Any()
    private var pendingMove: InputEvent.Pointer? = null
    private var moveFlush: ScheduledFuture<*>? = null
    private var lastMoveSentAt = 0.0
    @Volatile var inputsSent = 0
        private set

    private var lastAutoDesktopAt: Double? = null
    private var previousActive: StreamSource = StreamSource.None
    private var userChoices = 0
    private var settingsToken = 0
    @Volatile private var viewport: Viewport? = null
    private var clipboardSubscribed = false

    fun start(viewport: Viewport?) {
        this.viewport = viewport
        // The hello goes first, before anything any caller sends (Compatibility.swift).
        outbox.add(StreamMessage.json(Kind.HELLO, Hello(client.appVersion, client.build, SillProtocol.CURRENT, client.device).toJson()))
        viewport?.let { outbox.add(StreamMessage.json(Kind.VIEWPORT, it.toJson())) }
        // The timers first: a Mac that refuses at once can end the session before start returns.
        later { timer.scheduleAtFixedRate(::tick, 250, 250, TimeUnit.MILLISECONDS) }
        later {
            timer.scheduleAtFixedRate({ if (connected) { val s = stats.close(client.device); send(StreamMessage.json(Kind.CLIENT_STATS, s.toJson())); listener.onStats(s) } },
                1000, 1000, TimeUnit.MILLISECONDS)
        }
        Thread(::writeLoop, "sill-writer").apply { isDaemon = true }.start()
        Thread(::readLoop, "sill-reader").apply { isDaemon = true }.start()
    }

    /** Schedules on the session's timer, unless the session has ended (its timer is shut down). */
    private fun <T> later(f: () -> T): T? = try { f() } catch (_: java.util.concurrent.RejectedExecutionException) { null }

    // MARK: Sending

    private fun send(m: StreamMessage) { if (!ended.get()) outbox.add(m) }

    fun select(source: StreamSource) { synchronized(inputLock) { userChoices++ }; send(StreamMessage.json(Kind.SELECT_SOURCE, source.toJson())) }
    fun launch(bundleID: String) { synchronized(inputLock) { userChoices++ }; send(StreamMessage.json(Kind.LAUNCH_APP, LaunchApp(bundleID).toJson())) }
    fun windowCommand(id: Long, action: String) = send(StreamMessage.json(Kind.WINDOW_COMMAND, WindowCommand(id, action).toJson()))

    fun setViewport(v: Viewport) {
        if (v == viewport) return
        viewport = v
        send(StreamMessage.json(Kind.VIEWPORT, v.toJson()))
    }

    /** Kind 17: only what one control changed; the answer is a kind 16 with this token. */
    fun changeSettings(change: HostSettingsChange): Int = changeSettings { change }!!

    /**
     * Kind 17 under this session's next token: `build` makes the change to send with it (the
     * settings ledger's pick, which records the token beside the pick), or null to send nothing,
     * and then the token is not spent. The one place a token is allocated, so what the ledger waits
     * for and what the Mac answers can never disagree, whoever else sends a change.
     */
    fun changeSettings(build: (token: Int) -> HostSettingsChange?): Int? = synchronized(inputLock) {
        val token = settingsToken + 1
        val change = build(token) ?: return@synchronized null
        settingsToken = token
        send(StreamMessage.json(Kind.CHANGE_SETTINGS, change.copy(token = token).toJson()))
        token
    }

    /** Kind 28, only to a Mac that takes gestures. */
    fun gesture(name: String, fingers: Int) {
        if ((windowList?.gestures ?: 0) >= TrackpadGesture.GENERATION) send(StreamMessage.json(Kind.GESTURE, TrackpadGesture(name, fingers).toJson()))
    }

    /** This device's clipboard text to the Mac (kind 32), only to a Mac that shares it. */
    fun sendClipboard(text: String): Boolean {
        if ((windowList?.clipboard ?: 0) < Clipboard.GENERATION || text.isEmpty() || text.encodeToByteArray().size > Clipboard.MAX_TEXT_BYTES) return false
        val m = StreamMessage.json(Kind.CLIPBOARD, Clipboard(text = text).toJson())
        if (m.payload.size > StreamMessage.MAX_CLIENT_PAYLOAD) return false
        send(m)
        return true
    }

    fun updateShareClipboard(on: Boolean) {
        shareClipboard = on
        if ((windowList?.clipboard ?: 0) < Clipboard.GENERATION) return
        if (on && !clipboardSubscribed) { clipboardSubscribed = true; send(StreamMessage.json(Kind.CLIPBOARD, Clipboard().toJson())) }
        if (!on && clipboardSubscribed) { clipboardSubscribed = false; send(StreamMessage.json(Kind.CLIPBOARD, Clipboard(stop = true).toJson())) }
    }

    /** The worst round trip of the last second that measured one, in seconds (the menus' timeout). */
    val worstRtt: Double? get() = stats.lastRttMaxMs.takeIf { it >= 0 }?.let { it / 1000.0 }

    fun fetchMenu(f: FetchMenu) = send(StreamMessage.json(Kind.FETCH_MENU, f.toJson()))
    fun pressMenuItem(p: PressMenuItem) = send(StreamMessage.json(Kind.PRESS_MENU_ITEM, p.toJson()))

    /** Input aimed at the stream. Pointer moves are coalesced to one per 8 ms; anything else flushes a waiting move first. */
    fun input(e: InputEvent) {
        synchronized(inputLock) {
            if (e is InputEvent.Pointer && e.action == PointerAction.MOVE) {
                pendingMove = e
                if (moveFlush == null) {
                    val wait = (lastMoveSentAt + MOVE_INTERVAL - clock.mono()).coerceAtLeast(0.0)
                    moveFlush = later { timer.schedule({ synchronized(inputLock) { flushMove() } }, (wait * 1e6).toLong(), TimeUnit.MICROSECONDS) }
                }
                return
            }
            flushMove()
            sendInput(e)
        }
    }

    private fun flushMove() {
        moveFlush?.cancel(false)
        moveFlush = null
        pendingMove?.let { sendInput(it); lastMoveSentAt = clock.mono() }
        pendingMove = null
    }

    private fun sendInput(e: InputEvent) {
        inputsSent++
        send(StreamMessage.json(Kind.INPUT, e.toJson()))
    }

    fun close() = end(SessionEnd.ByUs())

    // MARK: Loops

    private fun writeLoop() {
        val out = connection.output
        try {
            while (!ended.get()) {
                val m = outbox.poll(500, TimeUnit.MILLISECONDS) ?: continue
                out.write(m.serialized())
                // Write what is waiting together, then flush once.
                while (true) { val n = outbox.poll() ?: break; out.write(n.serialized()) }
                out.flush()
            }
        } catch (e: IOException) {
            // The reader says how the session ended (the Mac's goodbye, then its close); a write
            // that fails first only waits a moment for it.
            val until = clock.mono() + 1.0
            while (!ended.get() && clock.mono() < until) Thread.sleep(20)
            end(SessionEnd.Failed(classify(e), goodbye))
        }
    }

    private fun readLoop() {
        val reader = MessageReader(connection.input, onBytes = { lastReceivedAt = clock.mono() })
        try {
            while (!ended.get()) {
                val m = reader.next() ?: return end(SessionEnd.Closed(goodbye))
                handle(m)
            }
        } catch (e: IOException) {
            if (ended.get()) return
            // The Mac's goodbye comes just before it closes; a reset after it is still its close.
            if (goodbye != null) end(SessionEnd.Closed(goodbye)) else end(SessionEnd.Failed(classify(e), null))
        } catch (e: JsonException) {
            end(SessionEnd.Failed(IOException("a message from the Mac did not decode: ${e.message}"), goodbye))
        }
    }

    private fun handle(m: StreamMessage) {
        when (m.kind) {
            Kind.PARAMETER_SETS -> (gate.parameterSets(m.payload) as? VideoGate.Out.Format)?.let { listener.onVideoFormat(it.sets) }
            Kind.FRAME -> {
                stats.frame(m.timestamp)
                when (val o = gate.frame(m.payload, m.isKeyframe, m.timestamp)) {
                    is VideoGate.Out.Decode -> listener.onFrame(o.annexB, o.keyframe, o.timestamp)
                    else -> {}
                }
            }
            Kind.WINDOW_LIST -> windowList(WindowList.fromJson(JsonObj.parse(m.payload)))
            Kind.THUMBNAIL -> ImageBlob.decodeThumbnail(m.payload)?.let { listener.onThumbnail(it.windowID, it.jpeg) }
            Kind.APP_ICON -> ImageBlob.decodeIcon(m.payload)?.let { listener.onAppIcon(it.bundleID, it.png) }
            Kind.APP_LIST -> listener.onAppList(AppInfo.listFromJson(Json.parse(m.payload)))
            Kind.PONG -> if (m.payload.size == 8) {
                val sent = Double.fromBits(ByteBuffer.wrap(m.payload).long)
                stats.rtt(((clock.mono() - sent) * 1000).toInt())
            }
            Kind.CURSOR_SHAPE -> CursorShape.decode(m.payload)?.let(listener::onCursorShape)
            Kind.MAC_POINTER -> {
                val p = MacPointer.fromJson(JsonObj.parse(m.payload))
                // Built before the Mac read this device's latest input, or a move of ours waits: stale.
                val stale = (p.seen ?: 0) < inputsSent || synchronized(inputLock) { pendingMove != null }
                if (!stale) listener.onMacPointer(p.position)
            }
            Kind.HOST_SETTINGS -> HostSettingsState.fromJson(JsonObj.parse(m.payload)).also { hostSettings = it; listener.onHostSettings(it) }
            Kind.MAC_INFO -> {
                val signed = SignedMacInfo.fromJson(JsonObj.parse(m.payload))
                val v = signed.verified()
                // Only the Mac this connection's TLS key belongs to names itself (macInfoNamesSession).
                if (v != null && connection.peerFingerprint?.contentEquals(v.second) == true) listener.onMacInfo(v.first, v.second)
            }
            Kind.MAC_MENU -> listener.onMacMenu(MacMenu.fromJson(JsonObj.parse(m.payload)))
            Kind.CLIPBOARD -> Clipboard.fromJson(JsonObj.parse(m.payload)).text?.let { if (shareClipboard) listener.onClipboard(it) }
            Kind.GOODBYE -> goodbye = try { Goodbye.fromJson(JsonObj.parse(m.payload)) } catch (_: JsonException) { Goodbye("") }
            else -> {}   // the tick, and kinds this build does not know
        }
    }

    private fun windowList(list: WindowList) {
        val first = windowList == null
        windowList = list
        if (first) {
            listener.onConnected(list)
            if (shareClipboard && (list.clipboard ?: 0) >= Clipboard.GENERATION) updateShareClipboard(true)
            // The Mac's menus: the subscription (a kind 27 without an id), as the iOS app sends at its first
            // window list. An older Mac skips the kind; only a subscriber is ever sent a top level.
            send(StreamMessage.json(Kind.FETCH_MENU, FetchMenu().toJson()))
        }
        listener.onWindowList(list)
        val now = clock.mono()
        val choicesBefore = synchronized(inputLock) { userChoices }
        when (val d = AutoDesktop.decide(previousActive, list, lastAutoDesktopAt, now, stats.lastRttMaxMs)) {
            AutoDesktop.Decision.Now -> { lastAutoDesktopAt = now; send(StreamMessage.json(Kind.SELECT_SOURCE, StreamSource.Desktop.toJson())) }
            is AutoDesktop.Decision.After -> later { timer.schedule({
                val l = windowList
                if (!ended.get() && l != null && l.active == StreamSource.None && synchronized(inputLock) { userChoices } == choicesBefore &&
                    l.windows.none { it.id == d.window }) {
                    lastAutoDesktopAt = clock.mono()
                    send(StreamMessage.json(Kind.SELECT_SOURCE, StreamSource.Desktop.toJson()))
                }
            }, (d.seconds * 1000).toLong(), TimeUnit.MILLISECONDS) }
            AutoDesktop.Decision.None -> {}
        }
        previousActive = list.active
    }

    private fun tick() {
        if (ended.get()) return
        val now = clock.mono()
        send(StreamMessage(Kind.PING, 0.0, false, ByteBuffer.allocate(8).putLong(now.toRawBits()).array()))
        val limit = maxOf(6.0, 4 * stats.lastRttMaxMs / 1000.0)
        if (now - lastReceivedAt > limit) end(SessionEnd.Lost(goodbye))
        else if (!connected && now - startedAt > firstListDeadline) end(SessionEnd.NoWindowList(goodbye))
    }

    /**
     * A TLS session's failure as what it means: a Mac that refuses this device's key does so after
     * the client's TLS 1.3 handshake is done, as an alert on the first read (-9825 on the iPad), so
     * the client can tell "removed, pair again" from a lost link.
     */
    private fun classify(e: IOException): IOException =
        if (connection.alpn == null || e is MessageReader.TooBig) e
        else SillTls.classifyAfterHandshake(e).takeIf { it is DialFailure.KeyRefused } ?: e

    private fun end(e: SessionEnd) {
        if (!ended.compareAndSet(false, true)) return
        timer.shutdownNow()
        connection.close()
        listener.onEnded(e)
    }

    companion object { const val MOVE_INTERVAL = 0.008 }
}
