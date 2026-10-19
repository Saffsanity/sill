package me.saffer.sill.core

import java.io.IOException
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.SocketAddress
import java.util.Base64
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/** Keeps this client's key across launches. */
interface IdentityStore {
    fun load(): Identity?
    fun save(identity: Identity)

    /** In a [KeyValueStore]: the PKCS#8 private key and the public point, base64. The platform's store keeps it private. */
    class InKeyValue(private val store: KeyValueStore) : IdentityStore {
        override fun load(): Identity? {
            val k = store.get("Sill.deviceKey") ?: return null
            val p = store.get("Sill.devicePoint") ?: return null
            return try { Identity.restore(Base64.getDecoder().decode(k), Base64.getDecoder().decode(p)) } catch (_: IllegalArgumentException) { null }
        }
        override fun save(identity: Identity) {
            store.put("Sill.deviceKey", Base64.getEncoder().encodeToString(identity.exportPrivate()))
            store.put("Sill.devicePoint", Base64.getEncoder().encodeToString(identity.point))
        }
    }

    companion object {
        fun loadOrCreate(store: IdentityStore): Identity = store.load() ?: Identity.generate().also(store::save)
    }
}

/** One row of the connect screen: a Mac on the network, a saved one, or both. */
data class MacRow(
    /** The saved Mac's ID, else "net:" and the Bonjour name. */
    val id: String,
    val name: String,
    val found: FoundService?,
    val saved: SavedMac?,
    /** How a tap dials it, for a row on the network. */
    val decision: HomeDial.Decision?,
) {
    /** What the row ends in: "Not paired", "Remote", "Update Sill"…, or how a paired Mac at home is reached ("Wired", "Wi-Fi", "Direct", or nothing). */
    val word: String? get() = when {
        found == null -> "Remote"
        else -> decision?.let { HomeDial.rowWord(it, found.interfaceName) }
    }
}

/** A pairing this client asked for and the Mac is showing a code for: what the code goes to. */
class PairingPrompt(val row: MacRow?, val address: SocketAddress, val macFingerprint: ByteArray?, val macName: String, val words: String)

/** What a [SillClient] tells its UI. Every call is on a worker thread. */
interface ClientListener {
    fun onRows(rows: List<MacRow>) {}
    /** The connect screen's status line (null: none). */
    fun onStatus(text: String?) {}
    /** A Mac shows its pairing code: ask for it (or a pairing link), then [SillClient.submitCode]. */
    fun onPairingPrompt(prompt: PairingPrompt) {}
    fun onSessionStarted(session: SillSession, mac: String) {}
    /** The session ended; `outcome` says how it reads and whether this client reconnects by itself. */
    fun onSessionEnded(outcome: GoodbyePolicy.Outcome) {}
}

/**
 * Everything a Sill client does but draw: discovery merged with the saved Macs, the dial a row takes
 * (pinned, any key, ask first), pairing, the remote dial of a saved Mac away from home, and the
 * reconnect after a loss (StreamClient.swift's, for these clients). The Windows and Android apps
 * are views over it.
 */
class SillClient(
    val info: ClientInfo,
    private val store: KeyValueStore,
    identityStore: IdentityStore,
    private val listener: ClientListener,
    /** The stream's own callbacks: the UI's renderer, its catalog and its input state. */
    private val streamListener: SessionListener,
    private val clock: Clock = Clock.System,
    /** A development build dials a Mac's plain door (the CLI without --pairing); a release never does. */
    private val allowPlain: Boolean = false,
    private val serviceType: String = "_sill._tcp.local.",
) {
    val identity: Identity = IdentityStore.loadOrCreate(identityStore)
    val saved = SavedMacs(store)
    private val pairing = Pairing(identity, info, clock)
    private val pool = Executors.newScheduledThreadPool(2) { r -> Thread(r, "sill-client").apply { isDaemon = true } }
    private var browser: MdnsBrowser? = null
    @Volatile private var found: List<FoundService> = emptyList()
    private val sessionRef = AtomicReference<SillSession?>()
    val session: SillSession? get() = sessionRef.get()

    // The automatic reconnect: which Mac, its dials that did not connect, and the next look.
    private class Reconnect(val macID: String?, val bonjourName: String?, val name: String, val remoteAllowed: Boolean) {
        var failed = 0
        var lastDialAt: Double? = null
        var task: ScheduledFuture<*>? = null
    }
    @Volatile private var reconnect: Reconnect? = null
    @Volatile var viewport: Viewport? = null
    @Volatile var shareClipboard = true

    /** Work on the client's pool, unless the client has stopped (then nothing). */
    private fun execute(f: () -> Unit) { try { pool.execute(f) } catch (_: java.util.concurrent.RejectedExecutionException) {} }
    private fun schedule(f: () -> Unit, delay: Long, unit: TimeUnit): ScheduledFuture<*>? =
        try { pool.schedule(f, delay, unit) } catch (_: java.util.concurrent.RejectedExecutionException) { null }

    fun start() {
        browser = MdnsBrowser(serviceType, clock) { list -> found = list; publishRows(); pokeReconnect() }.also { it.start() }
        publishRows()
    }

    fun stop() {
        browser?.stop()
        session?.close()
        pool.shutdownNow()
    }

    /** Found services, for tests and hosts without multicast (a model host on loopback). */
    fun setFound(list: List<FoundService>) { found = list; publishRows(); pokeReconnect() }

    fun rows(): List<MacRow> {
        val rows = ArrayList<MacRow>()
        val seen = HashSet<String>()
        for (f in found) {
            // A saved Mac by its recognition tag; a row whose tag names no saved Mac is not one (rowMac),
            // and a row with no tag at all only by the Bonjour name it was saved under.
            val s = saved.recognize(f.tag) ?: if (f.tag == null) saved.all.firstOrNull { it.bonjourName == f.name } else null
            val d = HomeDial.decide(f.door, s, allowPlain)
            val id = s?.macID ?: "net:${f.name}"
            if (!seen.add(id)) continue
            rows.add(MacRow(id, s?.name ?: f.name, f, s, d))
        }
        for (s in saved.all) if (s.macID !in seen && (s.addresses.isNotEmpty() || s.typedAddresses.isNotEmpty() || s.lastWorked != null) && !s.revoked && !s.newKey) {
            rows.add(MacRow(s.macID, s.name, null, s, null))
        }
        return rows
    }

    private fun publishRows() = listener.onRows(rows())

    private fun status(text: String?) = listener.onStatus(text)

    // MARK: Connecting

    /** A tap on a row. */
    fun connect(row: MacRow) {
        cancelReconnect()
        execute { dialRow(row, tapped = true) }
    }

    private fun dialRow(row: MacRow, tapped: Boolean): Boolean {
        val f = row.found
        if (f == null) return row.saved?.let { dialRemote(it, tapped) } ?: false
        val addresses = f.addresses.map { InetSocketAddress(it, f.port) }
        when (val d = row.decision) {
            is HomeDial.Decision.Pinned -> return dialSession(addresses, Trust.Pinned(d.mac.fingerprintBytes), row.name, d.mac, f.name, tapped)
            HomeDial.Decision.AnyKey -> return dialSession(addresses, Trust.AnyKey, row.name, null, f.name, tapped)
            HomeDial.Decision.Plain -> return dialPlain(addresses, row.name, tapped)
            HomeDial.Decision.UpdateSill -> { status("${row.name} runs an older Sill. Update Sill on the Mac to use it with this ${info.noun}."); return false }
            is HomeDial.Decision.Ask -> { if (tapped) ask(row, addresses, d.pin); return false }
            null -> return false
        }
    }

    private fun dialSession(addresses: List<SocketAddress>, trust: Trust, name: String, mac: SavedMac?, bonjourName: String?, tapped: Boolean): Boolean {
        status(if (tapped) "Connecting to $name…" else reconnect?.let { Redial.line(name, it.failed) })
        var last: IOException? = null
        for (a in addresses) {
            try {
                val c = SillTls.dial(a, identity, SillTls.SESSION_ALPN, trust)
                startSession(c, name, mac, bonjourName)
                return true
            } catch (e: DialFailure.PinRefused) {
                // The Mac was set up again (a new key): pair again (SavedMac.newKey).
                mac?.let { m -> saved.update(m.macID) { it.copy(newKey = true) }; publishRows() }
                if (tapped) status("$name has a new key since this ${info.noun} paired. Tap it to pair again.")
                return false
            } catch (e: DialFailure.KeyRefused) {
                // The Mac removed this device, or now requires pairing: pair again (SavedMac.revoked).
                mac?.let { m -> saved.update(m.macID) { it.copy(revoked = true) }; publishRows() }
                status("$name removed this ${info.noun}. Tap it to pair again.")
                cancelReconnect()
                return false
            } catch (e: IOException) { last = e }
        }
        if (tapped) status(last?.let(PairingWords::dialFailure)?.replace("The Mac", name) ?: "$name didn’t answer.")
        return false
    }

    private fun dialPlain(addresses: List<SocketAddress>, name: String, tapped: Boolean): Boolean {
        for (a in addresses) {
            try { startSession(SillTls.dialPlain(a), name, null, null); return true } catch (_: IOException) {}
        }
        if (tapped) status("$name didn’t answer.")
        return false
    }

    /** A saved Mac away from home: its typed addresses, then kind 18's, pinned, each a second after the last (first ready wins). */
    private fun dialRemote(mac: SavedMac, tapped: Boolean): Boolean {
        val targets = remoteTargets(mac)
        if (targets.isEmpty()) { if (tapped) status("${mac.name} has no address to reach it away from home."); return false }
        status(if (tapped) "Connecting to ${mac.name} remotely…" else reconnect?.let { Redial.line(mac.name, it.failed) })
        val winner = AtomicReference<Connection?>()
        // The first ready dial is used at once: a slower one left to time out (10 s) never holds it
        // silent past the remote door's 8 s. A loser that connects later closes itself.
        val settled = java.util.concurrent.CountDownLatch(1)
        val left = java.util.concurrent.atomic.AtomicInteger(targets.size)
        targets.forEachIndexed { i, a ->
            Thread {
                try {
                    try { Thread.sleep(1000L * i) } catch (_: InterruptedException) { return@Thread }
                    if (winner.get() != null) return@Thread
                    try {
                        val c = SillTls.dial(a, identity, SillTls.SESSION_ALPN, Trust.Pinned(mac.fingerprintBytes))
                        if (winner.compareAndSet(null, c)) settled.countDown() else c.close()
                    } catch (_: IOException) {}
                } finally {
                    if (left.decrementAndGet() == 0) settled.countDown()
                }
            }.apply { isDaemon = true; start() }
        }
        settled.await()
        val c = winner.get()
        if (c == null) { if (tapped) status("${mac.name} didn’t answer away from home. Check that its VPN or Remote Access is on."); return false }
        startSession(c, mac.name, mac, null)
        return true
    }

    fun remoteTargets(mac: SavedMac): List<SocketAddress> {
        val out = ArrayList<SocketAddress>()
        for (t in listOfNotNull(mac.lastWorked) + mac.typedAddresses) (AddressParser.parse(t) as? AddressParser.Result.Ok)?.address?.let { out.add(InetSocketAddress.createUnresolved(it.host, it.port ?: mac.remotePort)) }
        for (a in mac.addresses) out.add(InetSocketAddress.createUnresolved(a.host, a.port ?: mac.remotePort))
        return out.distinct().map { u -> u as InetSocketAddress; try { InetSocketAddress(InetAddress.getByName(u.hostString), u.port) } catch (_: Exception) { u } }
    }

    private fun startSession(c: Connection, name: String, mac: SavedMac?, bonjourName: String?) {
        session?.close()
        val self = AtomicReference<SillSession?>()
        val s = SillSession(c, info, object : SessionListener by streamListener {
            override fun onConnected(list: WindowList) {
                reconnect = null
                status(null)
                mac?.let { m -> saved.update(m.macID) { it.copy(lastConnectedAt = clock.wall(), bonjourName = bonjourName ?: it.bonjourName, revoked = false) } }
                streamListener.onConnected(list)
            }
            override fun onMacInfo(info: MacInfo, fingerprint: ByteArray) {
                if (saved.refresh(info, fingerprint)) publishRows()
                streamListener.onMacInfo(info, fingerprint)
            }
            override fun onEnded(end: SessionEnd) {
                sessionRef.compareAndSet(self.get(), null)
                streamListener.onEnded(end)
                ended(end, name, mac, bonjourName)
            }
        }, clock, shareClipboard = shareClipboard)
        self.set(s)
        sessionRef.set(s)
        listener.onSessionStarted(s, name)
        s.start(viewport)
    }

    private fun ended(end: SessionEnd, name: String, mac: SavedMac?, bonjourName: String?) {
        if (end is SessionEnd.ByUs) { listener.onSessionEnded(GoodbyePolicy.Outcome("Disconnected from $name.", false, false, false)); return }
        val outcome = GoodbyePolicy.outcome(end.goodbye, name, info.noun, mac != null)
        if (end.goodbye?.reason == Goodbye.REMOVED || end.goodbye?.reason == Goodbye.PAIRING_REQUIRED ||
            (end is SessionEnd.Failed && end.error is DialFailure.KeyRefused)) {
            mac?.let { m -> saved.update(m.macID) { it.copy(revoked = true) } }
        }
        publishRows()
        listener.onSessionEnded(outcome)
        status(outcome.text)
        if (outcome.reconnect) {
            reconnect = Reconnect(mac?.macID, bonjourName, name, outcome.remoteAllowed)
            pokeReconnect()
        }
    }

    private fun pokeReconnect() {
        val r = reconnect ?: return
        if (session != null) return
        r.task?.cancel(false)
        r.task = schedule({ reconnectStep(r) }, 0, TimeUnit.MILLISECONDS)
    }

    private fun reconnectStep(r: Reconnect) {
        if (reconnect !== r || session != null) return
        val row = rows().firstOrNull { (r.macID != null && it.saved?.macID == r.macID && it.found != null) || (r.macID == null && it.found?.name == r.bonjourName) }
        val now = clock.mono()
        val (dial, recheck) = Redial.next(r.failed, r.lastDialAt, now)
        if (!dial) {
            if (recheck != null) r.task = schedule({ reconnectStep(r) }, ((recheck - now) * 1000).toLong(), TimeUnit.MILLISECONDS)
            else status(Redial.line(r.name, r.failed))
            return
        }
        r.lastDialAt = now
        val ok = when {
            row != null -> dialRow(row, tapped = false)
            r.remoteAllowed && r.macID != null -> saved.byID(r.macID)?.let { dialRemote(it, tapped = false) } ?: false
            else -> false
        }
        if (!ok && reconnect === r) {
            if (row != null || r.remoteAllowed) r.failed++
            status(Redial.line(r.name, r.failed))
            r.task = schedule({ reconnectStep(r) }, 1, TimeUnit.SECONDS)
        }
    }

    fun cancelReconnect() { reconnect?.task?.cancel(false); reconnect = null }

    fun disconnect() { cancelReconnect(); session?.close() }

    // MARK: Pairing

    private fun ask(row: MacRow, addresses: List<SocketAddress>, pin: ByteArray?) {
        status("Asking ${row.name} to pair…")
        for (a in addresses) {
            val ex = try { pairing.ask(a, pin?.let { Trust.Pinned(it) } ?: Trust.AnyKey) } catch (e: IOException) { continue }
            val words = PairingWords.refusal(ex.result, info.noun)
            when (ex.result.reason) {
                PairResult.SHOWN, PairResult.OPEN_ON_MAC, PairResult.CLOSED -> {
                    status(null)
                    listener.onPairingPrompt(PairingPrompt(row, a, ex.macFingerprint, row.name, words))
                }
                else -> status(words)
            }
            return
        }
        status("${row.name} didn’t answer.")
    }

    /** The code the Mac shows, for a prompt this client was given. */
    fun submitCode(prompt: PairingPrompt, code: String, then: (PairOutcome) -> Unit = {}) = execute {
        val bonjour = prompt.row?.found?.name
        val out = pairing.pairWithCode(prompt.address, code, prompt.macFingerprint, bonjour)
        afterPairing(out, prompt.row, typedAddress = null)
        then(out)
    }

    /** The prompt's Cancel: the Mac may close the window it opened for this client. */
    fun cancelPrompt(prompt: PairingPrompt) = execute { prompt.macFingerprint?.let { pairing.cancel(prompt.address, it) } }

    /**
     * Add a Mac by the address its pairing window gives (typed, away from home or not) and its code:
     * pairs at that address (port 7455 when none is given), saves it with that address, connects.
     */
    fun addByAddress(addressText: String, code: String, then: (PairOutcome) -> Unit = {}) = execute {
        val parsed = AddressParser.parse(addressText)
        if (parsed !is AddressParser.Result.Ok) { then(PairOutcome.Failed(IOException("address"), addressWords(parsed as AddressParser.Result.Failed))); return@execute }
        val a = parsed.address
        val target = try { InetSocketAddress(InetAddress.getByName(a.host), a.port ?: SavedMac.DEFAULT_REMOTE_PORT) }
            catch (e: IOException) { then(PairOutcome.Failed(e, "Couldn’t find ${a.host}.")); return@execute }
        val out = pairing.pairWithCode(target, code, null)
        afterPairing(out, null, typedAddress = a.text)
        then(out)
    }

    /** A pairing link (scanned elsewhere, pasted): the home rows first, pinned to the link's key, then its own addresses. */
    fun pairWithLink(url: String, then: (PairOutcome) -> Unit = {}) = execute {
        val parsed = PairLink.parse(url)
        if (parsed !is PairLink.Parsed.Ok) { then(PairOutcome.Failed(IOException("link"), "That isn’t a Sill pairing link.")); return@execute }
        val link = parsed.link
        val home = found.filter { it.door != HomeDoorTxt.Door.PLAIN }.flatMap { f -> f.addresses.map { InetSocketAddress(it, f.port) } }
        val own = link.addresses.mapNotNull { a -> try { InetSocketAddress(InetAddress.getByName(a.host), a.port ?: link.port) } catch (_: Exception) { null } }
        val out = pairing.pairWithLink(link, home + own)
        afterPairing(out, null, typedAddress = null)
        then(out)
    }

    private fun afterPairing(out: PairOutcome, row: MacRow?, typedAddress: String?) {
        when (out) {
            is PairOutcome.Paired -> {
                val old = saved.byID(out.mac.macID)
                val reached = (out.address as? InetSocketAddress)?.let { a ->
                    ParsedAddress(a.address?.hostAddress?.substringBefore('%') ?: a.hostString, a.port,
                        if (a.address is java.net.Inet6Address) ParsedAddress.Kind.IPV6 else ParsedAddress.Kind.IPV4).text
                }
                saved.save(out.mac.copy(typedAddresses = (listOfNotNull(typedAddress) + (old?.typedAddresses ?: emptyList())).distinct(),
                    lastWorked = reached ?: old?.lastWorked,
                    addresses = old?.addresses ?: emptyList(), bonjourName = out.mac.bonjourName ?: old?.bonjourName))
                status("Paired with ${out.mac.name}.")
                publishRows()
                val r = rows().firstOrNull { it.saved?.macID == out.mac.macID }
                if (r != null) dialRow(r, tapped = true)
            }
            is PairOutcome.Refused -> status(out.words)
            is PairOutcome.Failed -> status(out.words)
        }
    }

    fun forget(macID: String) { saved.remove(macID); publishRows() }

    private fun addressWords(f: AddressParser.Result.Failed) = when (f.failure) {
        AddressParser.Failure.EMPTY -> "Enter the address your Mac shows."
        AddressParser.Failure.ZONE -> "Leave out the part after %: it only works on the network it was copied from."
        AddressParser.Failure.IPV4 -> "That isn’t a complete IPv4 address (four numbers 0–255)."
        AddressParser.Failure.PORT -> "A port is a number from 1 to 65535."
        AddressParser.Failure.PAIRING_LINK -> "That’s a pairing link: paste it as a link instead."
        else -> "That isn’t an address. Enter the one your Mac’s pairing window shows."
    }
}
