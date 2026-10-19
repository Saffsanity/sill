package me.saffer.sill.host

import me.saffer.sill.core.AppListPayload
import me.saffer.sill.core.Base64Url
import me.saffer.sill.core.ClientStats
import me.saffer.sill.core.Clipboard
import me.saffer.sill.core.Goodbye
import me.saffer.sill.core.Hello
import me.saffer.sill.core.HomeDoorTxt
import me.saffer.sill.core.HostSettingsChange
import me.saffer.sill.core.HostSettingsState
import me.saffer.sill.core.ImageBlob
import me.saffer.sill.core.InputEvent
import me.saffer.sill.core.Json
import me.saffer.sill.core.JsonObj
import me.saffer.sill.core.Kind
import me.saffer.sill.core.KeyValueStore
import me.saffer.sill.core.LaunchApp
import me.saffer.sill.core.MacAddress
import me.saffer.sill.core.MacInfo
import me.saffer.sill.core.MacInfoSignature
import me.saffer.sill.core.MacPointer
import me.saffer.sill.core.MessageReader
import me.saffer.sill.core.PairLink
import me.saffer.sill.core.PairRequest
import me.saffer.sill.core.PairResult
import me.saffer.sill.core.PairingProof
import me.saffer.sill.core.ParameterSets
import me.saffer.sill.core.ParsedAddress
import me.saffer.sill.core.PointerAction
import me.saffer.sill.core.QualityPreset
import me.saffer.sill.core.RecognitionTag
import me.saffer.sill.core.RunningStream
import me.saffer.sill.core.SafeText
import me.saffer.sill.core.SettingsChoices
import me.saffer.sill.core.SillProtocol
import me.saffer.sill.core.StreamMessage
import me.saffer.sill.core.StreamSettings
import me.saffer.sill.core.StreamSource
import me.saffer.sill.core.TrackpadGesture
import me.saffer.sill.core.WindowCommand
import me.saffer.sill.core.WindowInfo
import me.saffer.sill.core.WindowList
import me.saffer.sill.core.Viewport
import java.io.IOException
import java.net.Inet4Address
import java.net.InetAddress
import java.net.NetworkInterface
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLSocket
import kotlin.math.abs
import kotlin.math.roundToInt

/** The streaming settings a host keeps (HostConfig's four a device sets), saved in its store. */
data class HostConfig(val maxFPS: Int = 60, val bitrate: Int = QualityPreset.BALANCED.bitrate, val captureScale: Double = 2.0, val prioritizeSpeed: Boolean = false) {
    fun save(s: KeyValueStore) {
        s.put("Host.maxFPS", maxFPS.toString()); s.put("Host.bitrate", bitrate.toString())
        s.put("Host.captureScale", captureScale.toString()); s.put("Host.prioritizeSpeed", if (prioritizeSpeed) "1" else "0")
    }

    companion object {
        fun load(s: KeyValueStore) = HostConfig(
            s.get("Host.maxFPS")?.toIntOrNull()?.takeIf { it in SettingsChoices.maxFPS } ?: 60,
            s.get("Host.bitrate")?.toIntOrNull()?.takeIf { it in 1_000_000..200_000_000 } ?: QualityPreset.BALANCED.bitrate,
            s.get("Host.captureScale")?.toDoubleOrNull()?.takeIf { it in SettingsChoices.captureScale } ?: 2.0,
            s.get("Host.prioritizeSpeed") == "1")
    }
}

/**
 * A Sill host on any computer that is not a Mac: what the Mac's StreamCoordinator and StreamServer
 * do, over a [HostPlatform]. It serves the same wire to the same devices (the iPhone and iPad app,
 * Android, the Windows client): the door with pairing, the catalog in the Mac's order, one stream
 * at a time at the highest rate a device asks for, kinds 16 and 17 with the Mac menu's values, the
 * signed kind 18, the clipboard, three-finger gestures as the PC's shortcuts, and the Mac's input
 * made the PC's. Everything that changes state runs on one thread ([exec]), as the Mac's main
 * actor; each device's reading and writing on threads of their own.
 */
class StreamHost(
    val platform: HostPlatform,
    private val store: KeyValueStore,
    val hostVersion: String,
    /** Saved across launches (the app) or not (a test). */
    private val persistent: Boolean = true,
    private val port: Int = DEFAULT_PORT,
    private val bind: InetAddress? = null,
    /** Bonjour: off for tests that dial by address. */
    private val advertise: Boolean = true,
    private val serviceType: String = "_sill._tcp.local.",
    val log: (String) -> Unit = { println(it) },
) : AutoCloseable {
    val hostIdentity = HostIdentity(store)
    val trust = TrustList(store)
    val pairing = PairingWindow(hostIdentity.identity.fingerprint)
    private val asks = AskLimits()
    private val launchID = UUID.randomUUID().toString()
    private val exec: ScheduledExecutorService = Executors.newSingleThreadScheduledExecutor { r -> Thread(r, "sill-host").apply { isDaemon = true } }
    private val background: ScheduledExecutorService = Executors.newScheduledThreadPool(2) { r -> Thread(r, "sill-catalog").apply { isDaemon = true } }
    private val clock: () -> Double = { System.nanoTime() / 1e9 }
    private fun wall() = System.currentTimeMillis() / 1e3

    private lateinit var door: HostDoor
    private var mdns: MdnsResponder? = null
    @Volatile private var stopped = false

    // State, on exec.
    @Volatile var config = HostConfig.load(store); private set

    /** Settings › General's "Share clipboard with devices" (Sill.app's `shareClipboard`, on by default): off, the window list
     *  says nothing of the clipboard, so no device offers it, and any kind 32 that still comes is dropped. */
    @Volatile var shareClipboard = store.get("Host.shareClipboard") != "0"; private set
    private val sessions = ArrayList<Session>()
    private var windows: List<PlatformWindow> = emptyList()
    private var active: StreamSource = StreamSource.None
    private var activeWindow: PlatformWindow? = null
    private var sourceRect: Rect? = null
    /** What the picture shows, where input lands and the pointer is measured: the grab's rectangle. */
    private val frameRect: Rect? get() {
        val src = sourceRect ?: return null
        frameCache?.let { (key, frame) -> if (key == src) return frame }
        val frame = if (platform.captureFollowsWindow) src else CaptureRect.clip(src, platform.desktopBounds())
        frameCache = src to frame
        return frame
    }
    private var frameCache: Pair<Rect, Rect>? = null
    private fun applySource() { val r = frameRect ?: platform.desktopBounds(); for (s in sessions) s.input.source = r }
    @Volatile private var video: EncodedVideo? = null
    private var videoGeneration = 0
    private var videoFailures = 0
    @Volatile private var sets: ParameterSets? = null
    private var lastInputAt = Double.NEGATIVE_INFINITY
    private var lastList: ByteArray? = null
    private var sentIcons = HashSet<String>()
    private var thumbnailsAt = HashMap<Long, Pair<Rect, Double>>()
    private var catalogBusy = false
    // The clipboard: the last text seen on the PC, and what a device last wrote there.
    private var clipLast: String? = null
    private var clipWritten: String? = null
    private var clipBusy = false
    // The PC's pointer (kind 26): who moved it last, the PC or a device, and Sill's own moves.
    private var pointerController: Session? = null
    private var pointerCounted: Pair<Int, Int>? = null
    private var lastPostAt = Double.NEGATIVE_INFINITY
    // Counters for the 1 s line.
    private val framesIn = java.util.concurrent.atomic.AtomicInteger()

    /** Told whenever what a UI shows changes: sessions, the pairing window, the trust list. */
    @Volatile var onStatusChange: () -> Unit = {}

    /** One device's session. */
    inner class Session(val socket: SSLSocket, val fingerprint: ByteArray, val address: InetAddress) {
        val client = HostClient(socket.outputStream, address.hostAddress, Base64Url.encode(fingerprint), clock,
            onKeyframeNeeded = { video?.requestKeyframe() }, onWriteFailed = { post { end(this, "write failed") } })
        val input = InputTranslator(platform.input, frameRect ?: platform.desktopBounds())
        var hello: Hello? = null
        var fps: Int? = null
        var viewport: Viewport? = null
        var clipboard = false
        val changeTimes = ArrayDeque<Double>()
        val gestureTimes = ArrayDeque<Double>()
        val clipTimes = ArrayDeque<Double>()
        var lastSettings: ByteArray? = null
        var lastPointer: MacPointer? = null
        var leaving = false
        var lastStatsLogAt = Double.NEGATIVE_INFINITY
        var stats: ClientStats? = null
        val name get() = hello?.device?.let { SafeText.label(it) }?.ifEmpty { null } ?: address.hostAddress
    }

    /** What the UI lists: each device and its last stats. */
    data class DeviceStatus(val name: String, val address: String, val stats: ClientStats?)

    val devices: List<DeviceStatus> get() = onExec { sessions.map { DeviceStatus(it.name, it.address.hostAddress, it.stats) } }
    val streaming: String get() = onExec { when (val a = active) { StreamSource.None -> "nothing"; StreamSource.Desktop -> "the desktop"; is StreamSource.Window -> activeWindow?.title ?: "a window" } }
    val boundPort: Int get() = door.port

    // What the UI shows (HostStatus.kt): the encoder's last second, Bonjour, and the pairing window's asker.
    @Volatile private var encodedFps = 0
    @Volatile private var advertised: Boolean? = null
    /** The name of the device whose ask opened the window that shows now, and of the last one paired. */
    @Volatile private var askedBy: Pair<String, String>? = null
    /** The address of the device whose ask opened the window, quieted with its key at the host's Cancel. */
    @Volatile private var askedFrom: String? = null
    @Volatile private var pairedName: String? = null

    /** A snapshot for the tray's card and menu (Sill.app's HostStatusSnapshot). */
    fun status(): HostStatusSnapshot = onExec {
        val network = when (advertised) {
            null -> if (advertise) HostStatusSnapshot.Network.Starting else HostStatusSnapshot.Network.NotAdvertised(door.port)
            true -> HostStatusSnapshot.Network.Advertising(platform.hostName)
            false -> HostStatusSnapshot.Network.Failed("Bonjour couldn’t start on this network")
        }
        val v = video
        val stream = if (v != null && active != StreamSource.None && v.width > 0) {
            val f = wantedFps()
            HostStatusSnapshot.Stream(if (active == StreamSource.Desktop) HostStatusSnapshot.Stream.Kind.DESKTOP else HostStatusSnapshot.Stream.Kind.WINDOW,
                activeWindow?.let { "${it.app} — ${it.title}" } ?: "", v.width, v.height, f,
                StreamParams(f, config.bitrate, config.captureScale).bitrate / 1_000_000, (v as? SoftwareAware)?.software ?: false)
        } else null
        val devices = sessions.map { val st = it.stats
            HostStatusSnapshot.Device(it.client.fingerprint + "@" + it.address.hostAddress, it.hello?.device?.let { d -> SafeText.label(d) }?.ifEmpty { null },
                it.address.hostAddress, st?.fps, st?.frameAgeMs, st?.rttMs) }
        val asked = askedBy?.takeIf { a -> pairing.current?.byDevice == a.first }
        HostStatusSnapshot(network, devices, stream, if (stream != null) encodedFps else 0, asked?.let { HostStatusSnapshot.PairingRequest(it.second) })
    }

    /** The pairing window's state for its view: waiting with tries left, or how the last one ended. */
    fun pairingPhase(): PairingCopy.Phase? {
        if (pairing.current != null) return PairingCopy.Phase.Waiting(pairing.triesLeft, pairing.wrongFrom)
        return when (pairing.lastEnd) {
            PairingWindow.End.PAIRED -> PairingCopy.Phase.Paired(pairedName ?: "the device")
            PairingWindow.End.STOPPED -> PairingCopy.Phase.Stopped
            PairingWindow.End.EXPIRED -> PairingCopy.Phase.Expired
            PairingWindow.End.CLOSED -> PairingCopy.Phase.Closed
            null -> null
        }
    }

    /** The name of the device whose ask opened the open window, for its first line. */
    fun pairingAskedBy(): String? = askedBy?.takeIf { pairing.current?.byDevice == it.first }?.second

    /** What to type on a device that can't scan (PairingCopy.address). */
    fun pairingAddress(): PairingCopy.Address? {
        val all = macAddresses()
        return PairingCopy.address(all.filter { it.kind == "lan" }.map { it.host }, all.filter { it.kind == "vpn" }.map { it.host }, door.port)
    }

    fun start() {
        door = HostDoor(hostIdentity.identity, trust, port, bind, log, clock,
            onPairRequest = { req, fp, src -> onExec { pairRequest(req, fp, src) } },
            onSession = { s, fp, src -> post { admit(s, fp, src) } })
        door.start()
        trust.onChange = { post { trustChanged() } }
        pairing.onChange = { onStatusChange() }
        log("Sill host ${hostVersion} on ${platform.osName}: \"${platform.hostName}\", Mac ID ${hostIdentity.macID}, port ${door.port}; " +
            if (trust.requirePairing) "pairing required (${trust.devices.size} paired)." else "any device's key (Require pairing off).")
        if (advertise) {
            mdns = MdnsResponder(platform.hostName, "sill-" + hostIdentity.macID.take(8), door.port, txt(), serviceType, log).also {
                advertised = it.start()
                if (advertised == true) log("Advertising ${serviceType.removeSuffix(".local.")} as \"${platform.hostName}\".")
            }
        }
        exec.scheduleAtFixedRate({ guard { tick() } }, 30, 30, TimeUnit.MILLISECONDS)
        exec.scheduleAtFixedRate({ guard { second() } }, 1, 1, TimeUnit.SECONDS)
        background.scheduleWithFixedDelay({ guard { pollCatalog() } }, 0, CATALOG_SECONDS, TimeUnit.MILLISECONDS)
        background.scheduleWithFixedDelay({ guard { pollClipboard() } }, 250, 250, TimeUnit.MILLISECONDS)
    }

    private fun txt(): Map<String, String?> = mapOf(RecognitionTag.TXT_KEY to hostIdentity.tag(), HomeDoorTxt.KEY to if (trust.requirePairing) "1" else "0")

    // MARK: Pairing

    /** The QR code's link for the open window, with this computer's addresses. */
    fun pairingLink(w: PairingWindow.Shown): String =
        PairLink(hostIdentity.identity.fingerprint, w.secret, platform.hostName, door.port, lanAddresses().take(4).map { ParsedAddress(it.hostAddress, door.port, ParsedAddress.Kind.IPV4) }).url

    /** Pair a device… on the host: opens the window (or shows the open one). */
    fun openPairing(): PairingWindow.Shown = pairing.open()

    /** The host's Cancel. A window a device's ask opened quiets that device for 10 minutes. */
    fun cancelPairing() {
        pairing.current?.byDevice?.let { asks.quiet(it, askedFrom ?: it) }
        pairing.close()
    }

    private fun pairRequest(req: PairRequest, fp: ByteArray, source: InetAddress): PairResult {
        val key = Base64Url.encode(fp)
        val name = SafeText.label(req.name).ifEmpty { "Device" }
        return when (req.method) {
            // A key already paired asks too (its record lost on the device, or marked revoked): it gets a
            // code like any other, never an ok without a proof, which only the cable may send.
            PairRequest.ASK -> deviceAsk(key, name + (req.model?.let { " ($it)" } ?: ""), source, "asks to pair")
            PairRequest.CANCEL -> {
                // Closes only a window this key's ask opened.
                if (pairing.current?.byDevice == key) pairing.close()
                PairResult(ok = false, reason = PairResult.CLOSED)
            }
            PairRequest.QR, PairRequest.CODE -> when (val o = pairing.check(req.method, req.proof, fp, source.hostAddress)) {
                is PairingWindow.Outcome.Paired -> {
                    trust.add(fp, name, req.model, req.method, wall())
                    pairedName = name
                    log("Pairing: paired $name${req.model?.let { " ($it)" } ?: ""} by ${if (req.method == PairRequest.QR) "the QR code" else "the code"}.")
                    onStatusChange()
                    okResult(o.key, fp)
                }
                is PairingWindow.Outcome.Refused -> {
                    if (o.result.reason == PairResult.STOPPED) asks.quiet(key, source.hostAddress)
                    log("Pairing: $name's proof refused (${o.result.reason}${o.result.triesLeft?.let { ", $it tries left" } ?: ""}).")
                    o.result
                }
            }
            else -> PairResult(ok = false, reason = PairResult.CLOSED)
        }
    }

    /**
     * A device asking the host to show its code, by an ask (kind 19) or Pair This iPad… (kind 21):
     * the ask rule's limits either way (locked, a window already open, the quiet after the host's
     * Cancel or a stop, three device-opened windows in 10 minutes).
     */
    private fun deviceAsk(key: String, label: String, source: InetAddress, what: String): PairResult =
        when (val d = asks.decide(platform.isLocked(), pairing.current != null, key, source.hostAddress)) {
            is AskLimits.Decision.Answer -> PairResult(ok = false, reason = d.reason)
            AskLimits.Decision.Open -> {
                pairing.open(byDevice = key)
                askedBy = key to label
                askedFrom = source.hostAddress
                // Never the code itself, as Sill.app's log never holds one: a log is read by more than its owner.
                log("Pairing: $label (${source.hostAddress}) $what; showing a code for ${(PairingWindow.TTL / 60).toInt()} minutes.")
                onStatusChange()
                PairResult(ok = false, reason = PairResult.SHOWN)
            }
        }

    private fun okResult(key: ByteArray?, fp: ByteArray) = PairResult(ok = true,
        proof = key?.let { Base64Url.encode(PairingProof.macProof(it, hostIdentity.identity.fingerprint, fp)) },
        macID = hostIdentity.macID, name = SafeText.label(platform.hostName).ifEmpty { "PC" }, recognitionKey = Base64Url.encode(hostIdentity.recognitionKey))

    /** Remove: forgets the device and ends its sessions. */
    fun removeDevice(fingerprint: String) {
        post { for (s in sessions.filter { it.client.fingerprint == fingerprint }) goodbye(s, Goodbye(Goodbye.REMOVED)) }
        trust.remove(fingerprint)
    }

    fun setRequirePairing(on: Boolean) = trust.setRequirePairing(on)

    private fun trustChanged() {
        mdns?.updateTxt(txt())
        for (s in sessions.toList()) if (!trust.admits(s.fingerprint)) goodbye(s, Goodbye(Goodbye.PAIRING_REQUIRED))
        onStatusChange()
    }

    // MARK: Sessions

    private fun admit(socket: SSLSocket, fp: ByteArray, address: InetAddress) {
        if (stopped) { socket.close(); return }
        val s = Session(socket, fp, address)
        if (sessions.size >= MAX_SESSIONS) { goodbye(s, Goodbye(Goodbye.BUSY), registered = false); return }
        sessions.add(s)
        snapshot()
        trust.connected(fp, wall())
        log("Client connected: ${address.hostAddress} (${sessions.size} connected)")
        Thread({ readLoop(s) }, "sill-read ${address.hostAddress}").apply { isDaemon = true }.start()
        // The catalog is polled only while a device is connected: the first one gets a fresh look.
        try { windows = platform.windows().filter { it.bounds.w > 0 && it.bounds.h > 0 }; lastList = null } catch (e: Exception) { log("Windows: ${e.message}") }
        sendCatalog(s)
        video?.requestKeyframe()
        catalogSoon()
        onStatusChange()
    }

    private fun readLoop(s: Session) {
        val reader = MessageReader(s.socket.inputStream, cap = { StreamMessage.MAX_CLIENT_PAYLOAD.toLong() })
        try {
            while (true) {
                val m = reader.next() ?: break
                post { guard { handle(s, m) } }
            }
            post { end(s, "closed") }
        } catch (e: MessageReader.TooBig) {
            post { log("Client ${s.name}: a message of kind ${e.kind} announced ${e.length} bytes; closing."); end(s, "too big") }
        } catch (_: IOException) {
            post { end(s, "lost") }
        }
    }

    private fun end(s: Session, why: String) {
        if (!sessions.remove(s)) return
        snapshot()
        s.client.close()
        try { s.socket.close() } catch (_: IOException) {}
        s.input.releaseAll()
        if (pointerController === s) pointerController = null
        log("Client left: ${s.name} ($why; ${sessions.size} connected)")
        if (sessions.isEmpty()) select(StreamSource.None, pick = false)
        else applyFps()
        onStatusChange()
    }

    private fun goodbye(s: Session, g: Goodbye, registered: Boolean = true) {
        if (s.leaving) return
        s.leaving = true
        s.client.send(StreamMessage.json(Kind.GOODBYE, g.toJson()))
        log("Goodbye to ${s.name}: ${g.reason}")
        // Closed once the goodbye is sent, or after 250 ms.
        postLater({ if (registered) end(s, g.reason) else { s.client.close(); try { s.socket.close() } catch (_: IOException) {} } }, 250, TimeUnit.MILLISECONDS)
    }

    private fun sendCatalog(s: Session) {
        s.client.send(StreamMessage.json(Kind.WINDOW_LIST, windowList().toJson()))
        sendSettings(s, answering = null, force = true)
        s.client.send(StreamMessage.json(Kind.MAC_INFO, macInfo().toJson()))
        val apps = platform.apps()
        for (a in apps) platform.appIcon(a.bundleID)?.let { s.client.send(StreamMessage(Kind.APP_ICON, 0.0, false, ImageBlob.encodeIcon(a.bundleID, it))) }
        for (w in windows.map { it.appId }.distinct()) if (apps.none { it.bundleID == w }) platform.appIcon(w)?.let { s.client.send(StreamMessage(Kind.APP_ICON, 0.0, false, ImageBlob.encodeIcon(w, it))) }
        s.client.send(StreamMessage.json(Kind.APP_LIST, AppListPayload(apps).toJson()))
        thumbnailsAt.clear()
    }

    private fun windowList() = WindowList(SafeText.label(platform.hostName).ifEmpty { "PC" },
        windows.map { WindowInfo(wireId(it.id), it.title, it.app, it.appId, it.bounds.w, it.bounds.h) }, active, launchID, hostVersion, SillProtocol.CURRENT,
        gestures = if (platform.gestureChord("swipeUp") != null) TrackpadGesture.GENERATION else null,
        clipboard = if (shareClipboard) Clipboard.GENERATION else null)

    private fun broadcastList() {
        val l = windowList()
        val b = Json.bytes(l.toJson())
        lastList = b
        for (s in sessions) s.client.send(StreamMessage(Kind.WINDOW_LIST, 0.0, false, b))
    }

    private fun macInfo() = MacInfoSignature.sign(MacInfo(macID = hostIdentity.macID, name = SafeText.label(platform.hostName).ifEmpty { "PC" },
        issuedAt = wall(), remoteAccess = true, remotePort = door.port, internet = false, addresses = macAddresses()), hostIdentity.identity.keyPair)

    /** Where a paired device can reach this door from elsewhere: a VPN's address (Tailscale's 100.64/10) first, then the LAN's. */
    private fun macAddresses(): List<MacAddress> {
        val out = ArrayList<MacAddress>()
        for (ni in try { NetworkInterface.getNetworkInterfaces().toList() } catch (_: Exception) { emptyList() }) {
            if (!ni.isUp || ni.isLoopback) continue
            for (a in ni.inetAddresses.toList().filterIsInstance<Inet4Address>()) {
                val b = a.address
                val cgnat = (b[0].toInt() and 0xFF) == 100 && (b[1].toInt() and 0xC0) == 64
                out += MacAddress(a.hostAddress, door.port, if (cgnat || ni.isPointToPoint) "vpn" else "lan", ni.displayName ?: ni.name)
            }
        }
        return out.sortedBy { if (it.kind == "vpn") 0 else 1 }.take(12)
    }

    private fun lanAddresses(): List<InetAddress> = try {
        NetworkInterface.getNetworkInterfaces().toList().filter { it.isUp && !it.isLoopback }.flatMap { it.inetAddresses.toList() }.filterIsInstance<Inet4Address>()
    } catch (_: Exception) { emptyList() }

    // MARK: Messages

    private fun handle(s: Session, m: StreamMessage) {
        if (s !in sessions) return
        when (m.kind) {
            Kind.HELLO -> if (s.hello == null) {
                val h = Hello.fromJson(JsonObj.parse(m.payload))
                s.hello = h; s.client.name = s.name
                log("Client hello: ${s.name}, Sill ${h.appVersion ?: "?"}${h.build?.let { " ($it)" } ?: ""}, protocol ${h.protocol ?: "?"}")
                onStatusChange()
            }
            Kind.PING -> s.client.send(StreamMessage(Kind.PONG, m.timestamp, false, m.payload))
            Kind.SELECT_SOURCE -> select(StreamSource.fromJson(JsonObj.parse(m.payload)), pick = true)
            Kind.VIEWPORT -> viewport(s, Viewport.fromJson(JsonObj.parse(m.payload)))
            Kind.INPUT -> { s.client.inputsRead++; input(s, InputEvent.fromJson(JsonObj.parse(m.payload))) }
            Kind.CLIENT_STATS -> {
                val st = ClientStats.fromJson(JsonObj.parse(m.payload))
                s.stats = st
                val now = clock()
                if (now - s.lastStatsLogAt >= 1.5) {
                    s.lastStatsLogAt = now
                    log("client ${s.name}: ${st.fps} fps, frame age ${ms(st.frameAgeMs)}/${st.frameAgeMaxMs?.let(::ms) ?: "–"} ms, rtt ${ms(st.rttMs)}/${st.rttMaxMs?.let(::ms) ?: "–"} ms")
                }
            }
            Kind.LAUNCH_APP -> {
                val a = LaunchApp.fromJson(JsonObj.parse(m.payload))
                val running = windows.map { it.appId }
                runInBackground {
                    guard {
                        // Only an app this host listed (its apps, or a listed window's): a device's id
                        // is never a path to run, which on Windows could be any file or a UNC share.
                        if (a.bundleID !in running && platform.apps().none { it.bundleID == a.bundleID }) log("Launch refused for ${s.name}: not an app this computer listed")
                        else { log("Launching ${a.bundleID} for ${s.name}"); platform.launch(a.bundleID) }
                    }
                }
                catalogSoon(1500)
            }
            Kind.WINDOW_COMMAND -> windowCommand(WindowCommand.fromJson(JsonObj.parse(m.payload)))
            Kind.CHANGE_SETTINGS -> changeSettings(s, HostSettingsChange.fromJson(JsonObj.parse(m.payload)))
            Kind.GESTURE -> gesture(s, TrackpadGesture.fromJson(JsonObj.parse(m.payload)))
            Kind.CLIPBOARD -> clipboard(s, Clipboard.fromJson(JsonObj.parse(m.payload)))
            Kind.PAIRING_WANTED -> {
                // Pair This iPad… from a session: honoured only from a device without a paired key.
                if (!trust.isPaired(s.fingerprint)) {
                    val r = deviceAsk(s.client.fingerprint, s.name, s.address, "asks to pair from its session")
                    if (r.reason != PairResult.SHOWN) log("Pairing: ${s.name} asked to pair from its session; not shown (${r.reason}).")
                }
            }
            else -> {}                                       // kinds this host does not serve (the Mac's menus) are skipped
        }
    }

    private fun ms(v: Int) = if (v < 0) "–" else v.toString()

    private fun rate(times: ArrayDeque<Double>, perSecond: Int): Boolean {
        val now = clock()
        while (times.isNotEmpty() && now - times.first() > 1.0) times.removeFirst()
        if (times.size >= perSecond) return false
        times.addLast(now); return true
    }

    // MARK: Sources and video

    private fun select(src: StreamSource, pick: Boolean) {
        val window = (src as? StreamSource.Window)?.let { w -> windows.firstOrNull { wireId(it.id) == w.id } }
        val target = if (src is StreamSource.Window && window == null) StreamSource.None else src
        if (target == active && video != null && (target !is StreamSource.Window || window?.id == activeWindow?.id)) { broadcastList(); return }
        stopVideo()
        active = target
        activeWindow = window
        videoFailures = 0
        when (target) {
            StreamSource.None -> { sourceRect = null }
            StreamSource.Desktop -> { sourceRect = platform.desktopBounds(); startVideo() }
            is StreamSource.Window -> {
                if (pick) try { platform.raise(window!!.id) } catch (_: Exception) {}
                sourceRect = platform.bounds(window!!.id) ?: window.bounds
                startVideo()
            }
        }
        applySource()
        broadcastList()
        broadcastSettings()
    }

    private fun startVideo() {
        val src = when (val a = active) {
            StreamSource.Desktop -> Source.Desktop
            is StreamSource.Window -> Source.Window(activeWindow?.copy(bounds = sourceRect ?: activeWindow!!.bounds) ?: return)
            else -> return
        }
        for (s in sessions) s.client.resetForNewStream()
        sets = null
        val gen = ++videoGeneration
        val params = StreamParams(wantedFps(), config.bitrate, config.captureScale)
        runningFps = params.fps
        val sink = object : VideoSink {
            override fun parameterSets(sets: ParameterSets) { if (gen == videoGeneration) this@StreamHost.sets = sets }
            override fun frame(au: ByteArray, keyframe: Boolean, timestamp: Double) {
                if (gen != videoGeneration) return
                val m = StreamMessage(Kind.FRAME, timestamp, keyframe, au)
                val sNow = sets
                val targets = synchronized(sessionsSnapshotLock) { sessionsSnapshot }
                framesIn.incrementAndGet()
                for (c in targets) c.sendFrame(m, sNow)
            }
            override fun failed(reason: String) { post { if (gen == videoGeneration) videoFailed(reason) } }
        }
        try {
            video = platform.startVideo(src, params, sink)
        } catch (e: Exception) {
            video = null
            videoFailed(e.message ?: e.toString())
        }
    }

    private val sessionsSnapshotLock = Object()
    @Volatile private var sessionsSnapshot: List<HostClient> = emptyList()

    private fun stopVideo() {
        videoGeneration++
        val v = video ?: return
        video = null
        try { v.close() } catch (_: Exception) {}
    }

    private fun videoFailed(reason: String) {
        log("Stream stopped: $reason")
        stopVideo()
        videoFailures++
        val w = activeWindow
        val stillThere = active == StreamSource.Desktop || (w != null && platform.bounds(w.id) != null)
        if (stillThere && videoFailures < 3) {
            sourceRect = if (w != null) platform.bounds(w.id) else platform.desktopBounds()
            applySource()
            postLater({ guard { if (video == null && active != StreamSource.None) startVideo(); broadcastSettings() } }, 300, TimeUnit.MILLISECONDS)
        } else {
            active = StreamSource.None; activeWindow = null; sourceRect = null
            broadcastList(); broadcastSettings()
        }
    }

    private fun restartVideo() { if (active == StreamSource.None) return; stopVideo(); startVideo(); broadcastSettings() }

    private fun wantedFps(): Int {
        val asked = sessions.mapNotNull { it.fps }.maxOrNull() ?: 60
        return minOf(config.maxFPS, maxOf(24, asked))
    }

    private var runningFps = 0

    private fun applyFps() {
        val f = wantedFps()
        if (video != null && f != runningFps) { log("Frame rate: $runningFps → $f fps"); restartVideo() }
    }

    private fun viewport(s: Session, v: Viewport) {
        s.viewport = v
        s.fps = v.fps ?: 60
        applyFps()
        // Aa: the window resized to the panel's size at that scale (the Desktop ignores viewports).
        val w = activeWindow ?: return
        val scale = v.scale ?: return
        if (scale <= 0 || v.width <= 0 || v.height <= 0) return
        val want = Rect(0, 0, (v.width / scale).roundToInt(), (v.height / scale).roundToInt())
        val now = platform.bounds(w.id) ?: return
        if (abs(now.w - want.w) <= 2 && abs(now.h - want.h) <= 2) return
        val got = platform.setBounds(w.id, Rect(now.x, now.y, want.w, want.h)) ?: return
        log("Resized ${w.app} — ${w.title} to ${got.w}×${got.h} for a ${v.width.roundToInt()}×${v.height.roundToInt()} panel")
        sourceRect = got
        applySource()
        restartVideo()
    }

    private fun input(s: Session, e: InputEvent) {
        val now = clock()
        lastInputAt = now
        lastPostAt = now
        pointerController = s
        val w = activeWindow
        if (w != null && ((e is InputEvent.Pointer && (e.action == PointerAction.LEFT_DOWN || e.action == PointerAction.RIGHT_DOWN)) || (e is InputEvent.Key && e.down) || e is InputEvent.Text)) {
            // A click or a key raises the streamed window, as on the Mac.
            val front = platform.foregroundWindow()
            if (front != null && front != w.id) try { platform.raise(w.id) } catch (_: Exception) {}
        }
        if (active == StreamSource.None) return s.input.handleDropped(e)
        s.input.source = frameRect ?: platform.desktopBounds()
        s.input.handle(e)
    }

    private fun windowCommand(c: WindowCommand) {
        val w = windows.firstOrNull { wireId(it.id) == c.id } ?: return
        log("Window command: ${c.action} ${w.app} — ${w.title}")
        runInBackground {
            guard {
                when (c.action) {
                    WindowCommand.CLOSE -> platform.close(w.id)
                    WindowCommand.MINIMIZE -> platform.minimize(w.id)
                    WindowCommand.FULL_SCREEN -> platform.toggleFullScreen(w.id)
                }
            }
        }
        catalogSoon(400)
    }

    private fun gesture(s: Session, g: TrackpadGesture) {
        if (!rate(s.gestureTimes, 4)) return
        val chord = platform.gestureChord(g.gesture) ?: return
        log("Gesture from ${s.name}: ${g.gesture} → keys ${chord.joinToString("+") { "0x%02X".format(it) }}")
        for (k in chord) platform.input.key(k, true)
        for (k in chord.asReversed()) platform.input.key(k, false)
    }

    // MARK: Settings (kinds 16 and 17)

    private fun settingsState(answering: Int?): HostSettingsState {
        val v = video
        val running = if (v != null && active != StreamSource.None && v.width > 0) {
            val f = wantedFps()
            RunningStream(v.width, v.height, f, StreamParams(f, config.bitrate, config.captureScale).bitrate / 1_000_000, false)
        } else null
        return HostSettingsState(StreamSettings(config.maxFPS, config.bitrate, config.captureScale, config.prioritizeSpeed, false, null),
            persistent = persistent, virtualDisplayAvailable = false, virtualDisplayNote = "Not on ${platform.osName}.",
            softwareEncoder = (v as? SoftwareAware)?.software ?: false, stream = running, answering = answering)
    }

    /** Implemented by a platform's video when it can say whether it fell back to software. */
    interface SoftwareAware { val software: Boolean }

    private fun sendSettings(s: Session, answering: Int?, force: Boolean = false) {
        val b = Json.bytes(settingsState(answering).toJson())
        if (!force && answering == null && b.contentEquals(s.lastSettings)) return
        if (answering == null) s.lastSettings = b
        s.client.send(StreamMessage(Kind.HOST_SETTINGS, 0.0, false, b))
    }

    private fun broadcastSettings() { for (s in sessions) sendSettings(s, null) }

    private fun changeSettings(s: Session, c: HostSettingsChange) {
        if (!rate(s.changeTimes, 4)) { log("Settings from ${s.name} ignored: more than 4 a second"); sendSettings(s, c.token); return }
        var n = config
        val refused = ArrayList<String>()
        c.maxFPS?.let { if (it in SettingsChoices.maxFPS) n = n.copy(maxFPS = it) else refused += "maxFPS $it" }
        c.bitrate?.let { if (QualityPreset.of(it) != null) n = n.copy(bitrate = it) else refused += "bitrate $it" }
        c.captureScale?.let { if (it in SettingsChoices.captureScale) n = n.copy(captureScale = it) else refused += "captureScale $it" }
        c.prioritizeSpeed?.let { n = n.copy(prioritizeSpeed = it) }
        c.virtualDisplay?.let { if (it) refused += "virtualDisplay (not on ${platform.osName})" }
        c.directWireless?.let { refused += "directWireless" }
        if (refused.isNotEmpty()) log("Settings from ${s.name} refused: ${refused.joinToString(", ")}")
        if (n != config) {
            val old = config
            config = n
            if (persistent) n.save(store)
            log("Settings from ${s.name}: ${describe(old, n)}")
            if (old.bitrate != n.bitrate || old.captureScale != n.captureScale || old.maxFPS != n.maxFPS) restartVideo()
        }
        sendSettings(s, c.token)
        for (o in sessions) if (o !== s) sendSettings(o, null)
        s.lastSettings = Json.bytes(settingsState(null).toJson())
        onStatusChange()
    }

    /** Settings › General's switch, applied at once (as Sill.app's `setTarget` does): off, every device's subscription ends. */
    fun setShareClipboard(on: Boolean) = post {
        if (on == shareClipboard) return@post
        shareClipboard = on
        if (persistent) store.put("Host.shareClipboard", if (on) "1" else "0")
        log("Settings: share clipboard ${if (on) "on" else "off"}")
        if (!on) for (s in sessions) s.clipboard = false
        broadcastList(); onStatusChange()
    }

    /** The host's own controls (its window or tray), as a device's change. */
    fun setConfig(n: HostConfig) = post {
        if (n == config) return@post
        val old = config; config = n
        if (persistent) n.save(store)
        log("Settings: ${describe(old, n)}")
        restartVideo(); broadcastSettings(); onStatusChange()
    }

    private fun describe(a: HostConfig, b: HostConfig) = buildList {
        if (a.maxFPS != b.maxFPS) add("frame rate ${a.maxFPS} → ${b.maxFPS} fps")
        if (a.bitrate != b.bitrate) add("bitrate ${a.bitrate / 1_000_000} → ${b.bitrate / 1_000_000} Mbps per 60 fps")
        if (a.captureScale != b.captureScale) add("resolution ${if (a.captureScale == 2.0) "Retina" else "Standard"} → ${if (b.captureScale == 2.0) "Retina" else "Standard"}")
        if (a.prioritizeSpeed != b.prioritizeSpeed) add("prioritize speed ${b.prioritizeSpeed}")
    }.joinToString(", ")

    // MARK: Clipboard (kind 32)

    private fun clipboard(s: Session, c: Clipboard) {
        if (c.stop == true) {
            if (s.clipboard) log("Clipboard: ${s.name} stops sharing the clipboard.")
            s.clipboard = false; return
        }
        if (!shareClipboard) return
        if (!rate(s.clipTimes, 4)) return
        if (!s.clipboard) {
            s.clipboard = true
            log("Clipboard: ${s.name} shares the clipboard.")
            if (clipLast == null) runInBackground { guard { val t = platform.clipboardText(); post { if (clipLast == null) clipLast = t ?: "" } } }
        }
        val text = c.text ?: return
        if (text.encodeToByteArray().size > Clipboard.MAX_TEXT_BYTES) return
        clipWritten = text; clipLast = text
        runInBackground { guard { platform.setClipboardText(text) } }
        for (o in sessions) if (o !== s && o.clipboard) o.client.send(StreamMessage.json(Kind.CLIPBOARD, Clipboard(text = text).toJson()))
    }

    private fun pollClipboard() {
        val wanted = onExec { shareClipboard && !clipBusy && sessions.any { it.clipboard } }
        if (!wanted) return
        onExec { clipBusy = true }
        val t = try { platform.clipboardText() } finally { onExec { clipBusy = false } }
        post {
            val last = clipLast
            if (t == null || t == last) return@post
            clipLast = t
            if (last == null) return@post                  // what was there when the first device subscribed is never sent
            if (t == clipWritten) return@post              // a device's own text, already passed on
            if (t.encodeToByteArray().size > Clipboard.MAX_TEXT_BYTES) return@post
            for (s in sessions) if (s.clipboard) s.client.send(StreamMessage.json(Kind.CLIPBOARD, Clipboard(text = t).toJson()))
        }
    }

    // MARK: The catalog

    private fun catalogSoon(delayMs: Long = 0) { try { background.schedule({ guard { pollCatalog() } }, delayMs, TimeUnit.MILLISECONDS) } catch (_: java.util.concurrent.RejectedExecutionException) {} }

    private fun pollCatalog() {
        val go = onExec { if (catalogBusy || sessions.isEmpty()) false else { catalogBusy = true; true } }
        if (!go) return
        try {
            val list = platform.windows().filter { it.bounds.w > 0 && it.bounds.h > 0 }
            val activeId = onExec { activeWindow?.id }
            val activeBounds = activeId?.let { platform.bounds(it) }
            onExec { catalogChanged(list, activeBounds) }
            // Thumbnails: a window new or changed since its last, at most every 3 s each.
            val now = clock()
            for (w in list) {
                val prev = onExec { thumbnailsAt[w.id] }
                if (prev != null && (prev.first == w.bounds && now - prev.second < 30 || now - prev.second < 3)) continue
                val jpeg = try { platform.thumbnail(w, THUMBNAIL_WIDTH) } catch (_: Exception) { null } ?: continue
                onExec {
                    thumbnailsAt[w.id] = w.bounds to now
                    val m = StreamMessage(Kind.THUMBNAIL, 0.0, false, ImageBlob.encodeThumbnail(wireId(w.id), jpeg))
                    for (s in sessions) s.client.send(m)
                }
            }
        } finally {
            onExec { catalogBusy = false }
        }
    }

    private fun catalogChanged(list: List<PlatformWindow>, activeBounds: Rect?) {
        windows = list
        val w = activeWindow
        if (w != null) {
            if (activeBounds == null || list.none { it.id == w.id }) {
                log("The streamed window closed: ${w.app} — ${w.title}")
                stopVideo()
                active = StreamSource.None; activeWindow = null; sourceRect = null
                broadcastSettings()
            } else if (activeBounds != sourceRect) {
                val old = sourceRect
                sourceRect = activeBounds
                applySource()
                val resized = old == null || old.w != activeBounds.w || old.h != activeBounds.h
                if (resized || !platform.captureFollowsWindow) restartVideo()
            }
            activeWindow = list.firstOrNull { it.id == w.id } ?: activeWindow
        }
        for (a in list.map { it.appId }.distinct()) if (sentIcons.add(a)) platform.appIcon(a)?.let { png ->
            val m = StreamMessage(Kind.APP_ICON, 0.0, false, ImageBlob.encodeIcon(a, png)); for (s in sessions) s.client.send(m)
        }
        val b = Json.bytes(windowList().toJson())
        if (!b.contentEquals(lastList)) { lastList = b; for (s in sessions) s.client.send(StreamMessage(Kind.WINDOW_LIST, 0.0, false, b)) }
    }

    // MARK: Timers

    private fun snapshot() = synchronized(sessionsSnapshotLock) { sessionsSnapshot = sessions.map { it.client } }

    private fun tick() {
        if (sessions.isEmpty()) return
        val now = clock()
        pointer(now)
        // Keep the device's radio awake while something streams or input just came (the Mac's 30 ms tick).
        if (active == StreamSource.None && now - lastInputAt > 3) return
        for (s in sessions) if (now - s.client.lastSentAt >= 0.03) s.client.send(StreamMessage.empty(Kind.TICK, wall()))
    }

    /**
     * Kind 26: where the PC's own pointer is, to every device but the one moving it (the Mac's
     * PointerControl): a device's input gives it the pointer, Sill's own moves settle for 0.25 s,
     * and a move of the pointer after that is the PC's own, which every device is then shown.
     */
    private fun pointer(now: Double) {
        val rect = frameRect ?: return
        val pos = try { platform.cursorPosition() } catch (_: Exception) { null } ?: return
        val counted = pointerCounted
        if (counted == null || now - lastPostAt <= SETTLE) pointerCounted = pos
        else if (abs(pos.first - counted.first) + abs(pos.second - counted.second) >= 1) { pointerController = null; pointerCounted = pos }
        val controller = pointerController
        val fx = (pos.first - rect.x).toDouble() / rect.w
        val fy = (pos.second - rect.y).toDouble() / rect.h
        val inside = fx >= 0 && fx < 1 && fy >= 0 && fy < 1
        for (s in sessions) {
            if (s === controller) continue
            val p = if (inside) MacPointer(round4(fx), round4(fy), true, s.client.inputsRead) else MacPointer(inside = false, seen = s.client.inputsRead)
            val last = s.lastPointer
            if (last != null && last.x == p.x && last.y == p.y && last.inside == p.inside && last.seen == p.seen) continue
            s.lastPointer = p
            s.client.send(StreamMessage.json(Kind.MAC_POINTER, p.toJson()))
        }
    }

    private fun round4(v: Double) = (v * 10000).roundToInt() / 10000.0

    private fun second() {
        val now = clock()
        for (s in sessions.toList()) if (s.client.stalled(now)) { log("Client ${s.name}: nothing taken for ${HostClient.STALL.toInt()} s; disconnecting"); end(s, "stalled") }
        val out = framesIn.getAndSet(0)
        encodedFps = if (video != null) out else 0
        if (video != null && out > 0) {
            val dropped = sessions.sumOf { it.client.droppedFrames.also { _ -> it.client.droppedFrames = 0 } }
            log("[1s] enc.out $out${if (dropped > 0) " net.dropped $dropped" else ""} clients ${sessions.size}")
        }
        broadcastSettings()
    }

    // MARK: Plumbing

    /** Runs `f` on [exec] later; nothing once the host has stopped. */
    private fun post(f: () -> Unit) { try { exec.execute(f) } catch (_: java.util.concurrent.RejectedExecutionException) {} }
    private fun postLater(f: () -> Unit, delay: Long, unit: TimeUnit) { try { exec.schedule(f, delay, unit) } catch (_: java.util.concurrent.RejectedExecutionException) {} }
    private fun runInBackground(f: () -> Unit) { try { background.execute(f) } catch (_: java.util.concurrent.RejectedExecutionException) {} }

    /** Runs `f` on [exec] and waits for it (from any thread but exec itself). */
    private fun <T> onExec(f: () -> T): T {
        if (Thread.currentThread().name == "sill-host") return f()
        return exec.submit(f).get()
    }

    private inline fun guard(f: () -> Unit) {
        try { f() } catch (e: Exception) { if (!stopped) log("Host: ${e.javaClass.simpleName}: ${e.message}") }
    }

    /** The wire's window ID: a UInt32 (an X11 ID is one; a Windows handle's significant bits are 32). */
    private fun wireId(id: Long) = id and 0xFFFFFFFFL

    /** Says goodbye ("quit") to every device, stops the stream and the door. */
    override fun close() {
        if (stopped) return
        try {
            onExec {
                for (s in sessions) s.client.send(StreamMessage.json(Kind.GOODBYE, Goodbye(Goodbye.QUIT).toJson()))
            }
            Thread.sleep(100)
            onExec {
                stopped = true
                stopVideo()
                for (s in sessions.toList()) { s.input.releaseAll(); s.client.close(); try { s.socket.close() } catch (_: IOException) {} }
                sessions.clear()
            }
        } catch (_: Exception) {}
        stopped = true
        door.close()
        mdns?.close()
        exec.shutdownNow(); background.shutdownNow()
    }

    companion object {
        const val DEFAULT_PORT = 7455
        const val MAX_SESSIONS = 8
        const val CATALOG_SECONDS = 1000L
        const val THUMBNAIL_WIDTH = 320
        const val SETTLE = 0.25
    }
}
