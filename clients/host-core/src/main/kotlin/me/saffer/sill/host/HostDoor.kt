package me.saffer.sill.host

import me.saffer.sill.core.Identity
import me.saffer.sill.core.JsonObj
import me.saffer.sill.core.Kind
import me.saffer.sill.core.MessageReader
import me.saffer.sill.core.PairRequest
import me.saffer.sill.core.PairResult
import me.saffer.sill.core.SillTls
import me.saffer.sill.core.SillTlsServer
import me.saffer.sill.core.Spki
import me.saffer.sill.core.StreamMessage
import java.io.IOException
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import java.security.cert.X509Certificate
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
import javax.net.ssl.SSLSocket
import javax.net.ssl.SSLSocketFactory

/**
 * The host's door: the Mac's TLS home door and its admission (Door.swift, DoorPolicy.swift). TLS
 * 1.3 with a client certificate always; ALPN `sill/1` for a session from a key the trust list
 * admits (a paired one, or any while Require pairing is off), `sill-pair/1` for exactly one
 * pairing request (kind 19, 1 to 4096 bytes) and its answer; anything else refused in the
 * handshake. At most 8 connections between accept and admission, 2 from one address, 10 s each;
 * an address refused 5 times in 60 s is turned away at accept for 300 s, and a paired key clears it.
 * Devices find the door by Bonjour ([MdnsResponder]) or by address.
 */
class HostDoor(
    private val identity: Identity,
    private val trust: TrustList,
    port: Int,
    bind: InetAddress? = null,
    private val log: (String) -> Unit,
    private val clock: () -> Double = { System.nanoTime() / 1e9 },
    /** One pairing request; returns the answer (the door sends it and closes). */
    private val onPairRequest: (PairRequest, ByteArray, InetAddress) -> PairResult,
    /** An admitted session; the callee owns the socket from here. */
    private val onSession: (SSLSocket, ByteArray, InetAddress) -> Unit,
) : AutoCloseable {
    private val server = ServerSocket().apply { reuseAddress = true; bind(InetSocketAddress(bind, port), 50) }
    val port: Int get() = server.localPort
    @Volatile private var running = true
    private val pending = AtomicInteger()
    private val pendingBySource = ConcurrentHashMap<InetAddress, AtomicInteger>()
    private val refusals = ConcurrentHashMap<InetAddress, MutableList<Double>>()
    private val bannedUntil = ConcurrentHashMap<InetAddress, Double>()
    private var lastSummaryAt = 0.0
    private val refusedSinceSummary = AtomicInteger()
    /**
     * A context of its own for every connection, as the clients' dials have: a JSSE server context
     * keeps a session cache and issues TLS 1.3 tickets, and a resumed handshake never calls the trust
     * manager, so with one shared context a key admitted once on `sill-pair/1` (any key is) could
     * resume on `sill/1` unpaired, and a removed device with a ticket it kept. A ticket from another
     * context does not decrypt, so every handshake here is a full one.
     */
    private fun newContext() = SillTlsServer.context(identity) { fp, alpn ->
        fp != null && (alpn == SillTls.PAIRING_ALPN || (alpn == SillTls.SESSION_ALPN && trust.admits(fp)))
    }

    fun start() {
        Thread({
            while (running) {
                val s = try { server.accept() } catch (_: IOException) { break }
                admit(s)
            }
        }, "sill-door").apply { isDaemon = true }.start()
    }

    private fun admit(raw: Socket) {
        val source = raw.inetAddress
        val now = clock()
        if ((bannedUntil[source] ?: 0.0) > now) { raw.close(); return }
        val bySource = pendingBySource.computeIfAbsent(source) { AtomicInteger() }
        if (pending.get() >= MAX_PENDING || bySource.get() >= MAX_PENDING_PER_SOURCE) { raw.close(); return }
        pending.incrementAndGet(); bySource.incrementAndGet()
        Thread({
            var admitted = false
            val deadline = Thread({ try { Thread.sleep((ADMISSION * 1000).toLong()); if (!admittedFlag(raw)) raw.close() } catch (_: InterruptedException) {} }, "sill-door-deadline")
                .apply { isDaemon = true; start() }
            try {
                SillTls.tune(raw)
                raw.soTimeout = (ADMISSION * 1000).toInt()
                val s = (newContext().socketFactory as SSLSocketFactory).createSocket(raw, null, raw.port, true) as SSLSocket
                SillTlsServer.configure(s)
                try { s.startHandshake() } catch (e: IOException) {
                    refused(source, "handshake: ${e.message}")
                    s.close(); return@Thread
                }
                val fp = (s.session.peerCertificates.firstOrNull() as? X509Certificate)?.let { Spki.fingerprint(it.publicKey) }
                if (fp == null) { refused(source, "no key"); s.close(); return@Thread }
                when (s.applicationProtocol) {
                    SillTls.PAIRING_ALPN -> { pair(s, fp, source); return@Thread }
                    SillTls.SESSION_ALPN -> {
                        // Judged again here, whatever the handshake did: the trust manager is not
                        // called on a resumed session, and the list may have changed since it ran.
                        if (!trust.admits(fp)) { refused(source, "a key the trust list does not admit"); s.close(); return@Thread }
                        if (trust.isPaired(fp)) refusals.remove(source)
                        markAdmitted(raw); admitted = true
                        s.soTimeout = 0
                        onSession(s, fp, source)
                    }
                    else -> { refused(source, "ALPN ${s.applicationProtocol}"); s.close() }
                }
            } catch (_: IOException) {
                try { raw.close() } catch (_: IOException) {}
            } finally {
                deadline.interrupt()
                if (!admitted) markAdmitted(raw)
                pending.decrementAndGet(); bySource.decrementAndGet()
            }
        }, "sill-admit").apply { isDaemon = true }.start()
    }

    // A connection the deadline must leave alone once it is a session.
    private val admittedSockets = java.util.Collections.newSetFromMap(ConcurrentHashMap<Socket, Boolean>())
    private fun markAdmitted(s: Socket) { admittedSockets.add(s); if (admittedSockets.size > 64) admittedSockets.retainAll { !it.isClosed } }
    private fun admittedFlag(s: Socket) = s in admittedSockets

    private fun pair(s: SSLSocket, fp: ByteArray, source: InetAddress) {
        try {
            val m = try {
                MessageReader(s.inputStream, cap = { StreamMessage.MAX_PAIRING_PAYLOAD.toLong() }).next()
            } catch (e: MessageReader.TooBig) { null }
            if (m == null || m.kind != Kind.PAIR_REQUEST || m.payload.isEmpty()) { refused(source, "a pairing connection without its request"); return }
            val req = try { PairRequest.fromJson(JsonObj.parse(m.payload)) } catch (_: Exception) { refused(source, "a pairing request that does not parse"); return }
            val answer = if (req.v != PairRequest.VERSION) PairResult(ok = false, reason = PairResult.CLOSED) else onPairRequest(req, fp, source)
            s.outputStream.write(StreamMessage.json(Kind.PAIR_RESULT, answer.toJson()).serialized())
            s.outputStream.flush()
            // The Mac closes once the answer is sent, or after 250 ms.
            s.soTimeout = 250
            try { s.inputStream.read() } catch (_: IOException) {}
        } catch (_: IOException) {
        } finally {
            try { s.close() } catch (_: IOException) {}
        }
    }

    private fun refused(source: InetAddress, why: String) {
        val now = clock()
        val list = refusals.computeIfAbsent(source) { ArrayList() }
        val count = synchronized(list) { list.removeAll { now - it > REFUSAL_WINDOW }; list.add(now); list.size }
        if (count >= MAX_REFUSALS) { bannedUntil[source] = now + BAN; refusals.remove(source); log("Door: ${source.hostAddress} refused $count times in a minute; turned away for ${BAN.toInt()} s") }
        refusedSinceSummary.incrementAndGet()
        synchronized(this) {
            if (now - lastSummaryAt >= 60) { lastSummaryAt = now; log("Door: refused ${source.hostAddress} ($why); ${refusedSinceSummary.getAndSet(0)} refused in the last minute") }
        }
    }

    override fun close() {
        running = false
        try { server.close() } catch (_: IOException) {}
    }

    companion object {
        const val MAX_PENDING = 8
        const val MAX_PENDING_PER_SOURCE = 2
        const val ADMISSION = 10.0
        const val MAX_REFUSALS = 5
        const val REFUSAL_WINDOW = 60.0
        const val BAN = 300.0
    }
}
