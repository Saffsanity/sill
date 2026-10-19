package me.saffer.sill.core

import java.io.Closeable
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.net.SocketAddress
import java.security.Principal
import java.security.PrivateKey
import java.security.SecureRandom
import java.security.cert.CertificateException
import java.security.cert.X509Certificate
import javax.net.ssl.SNIHostName
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLEngine
import javax.net.ssl.SSLException
import javax.net.ssl.SSLSocket
import javax.net.ssl.X509ExtendedKeyManager
import javax.net.ssl.X509ExtendedTrustManager

/** A connection to a Mac, plain or TLS: the stream both ways and what the handshake said. */
interface Connection : Closeable {
    val input: InputStream
    val output: OutputStream
    /** SHA-256 of the Mac's SPKI from the TLS session; null on a plain connection. */
    val peerFingerprint: ByteArray?
    /** The negotiated ALPN; null on a plain connection. */
    val alpn: String?
    /** "192.168.1.20:52144" or the like, for logs. */
    val description: String
}

class PlainConnection(private val socket: Socket) : Connection {
    override val input: InputStream = socket.getInputStream()
    override val output: OutputStream = socket.getOutputStream()
    override val peerFingerprint: ByteArray? = null
    override val alpn: String? = null
    override val description = socket.remoteSocketAddress.toString()
    override fun close() = try { socket.close() } catch (_: IOException) {}
}

class TlsConnection(private val socket: SSLSocket) : Connection {
    override val input: InputStream = socket.inputStream
    override val output: OutputStream = socket.outputStream
    override val peerFingerprint: ByteArray? =
        (socket.session.peerCertificates.firstOrNull() as? X509Certificate)?.let { Spki.fingerprint(it.publicKey) }
    override val alpn: String? = socket.applicationProtocol?.ifEmpty { null }
    override val description = socket.remoteSocketAddress.toString()
    override fun close() = try { socket.close() } catch (_: IOException) {}
}

/** Who this client trusts on one dial: the saved Mac's key, or any P-256 key (an open door, or pairing). */
sealed class Trust {
    class Pinned(val fingerprint: ByteArray) : Trust() { override fun toString() = "pinned ${MacId.shortName(fingerprint)}" }
    object AnyKey : Trust() { override fun toString() = "any key" }
}

/** Why a dial failed, in the words the clients show (RemoteTLS.swift's statuses, by meaning). */
sealed class DialFailure(message: String, cause: Throwable? = null) : IOException(message, cause) {
    /** The Mac presented another key than the pin (-9808): set up again, or not the Mac paired with. */
    class PinRefused(val seen: ByteArray?) : DialFailure("the host presented another key${seen?.let { " (${MacId.shortName(it)})" } ?: ""}")
    /** The Mac refused this client's key (-9825/-9829): it removed this device, or requires pairing. */
    class KeyRefused(cause: Throwable?) : DialFailure("the host refused this device's key", cause)
    /** Not Sill's TLS door: no ALPN in common, or not TLS 1.3 (-9836/-9838). */
    class NotSill(cause: Throwable?) : DialFailure("not a Sill door", cause)
    /** No answer within the dial timeout, refused, unreachable. */
    class Unreachable(cause: Throwable?) : DialFailure(cause?.message ?: "unreachable", cause)
}

/**
 * The TLS both doors speak (RemoteTLS.swift; docs/remote-access-plan.md §3.3): TLS 1.3 only, this
 * client's self-signed P-256 certificate presented, the Mac's key pinned by the trust manager alone
 * (names, dates and chains are never evaluated), one ALPN offered, SNI "sill", and no resumption:
 * every dial builds a fresh context, so no session or ticket outlives it and a removed device can
 * never come back on an old one.
 */
object SillTls {
    const val SESSION_ALPN = "sill/1"
    const val PAIRING_ALPN = "sill-pair/1"
    const val SERVER_NAME = "sill"
    const val DIAL_TIMEOUT_MS = 10_000
    /** DSCP AF41 (interactive video), the service class both Apple ends use. */
    private const val TRAFFIC_CLASS = 0x88

    fun dial(address: SocketAddress, identity: Identity, alpn: String, trust: Trust, timeoutMs: Int = DIAL_TIMEOUT_MS): TlsConnection {
        val raw = Socket()
        try {
            tune(raw)
            raw.connect(address, timeoutMs)
        } catch (e: IOException) {
            raw.close(); throw DialFailure.Unreachable(e)
        }
        val pin = PinTrustManager(trust)
        val ctx = SSLContext.getInstance("TLSv1.3")
        ctx.init(arrayOf(IdentityKeyManager(identity)), arrayOf(pin), SecureRandom())
        val host = (address as? InetSocketAddress)?.hostString ?: SERVER_NAME
        val s = ctx.socketFactory.createSocket(raw, host, (address as? InetSocketAddress)?.port ?: 0, true) as SSLSocket
        s.sslParameters = s.sslParameters.apply {
            protocols = arrayOf("TLSv1.3")
            applicationProtocols = arrayOf(alpn)
            serverNames = listOf(SNIHostName(SERVER_NAME))
            endpointIdentificationAlgorithm = null
        }
        s.soTimeout = timeoutMs
        try {
            s.startHandshake()
        } catch (e: SSLException) {
            s.close()
            throw classify(e, pin)
        } catch (e: IOException) {
            s.close()
            // The Mac's key passed the pin, then it hung up: it refused this client's certificate.
            throw if (pin.seen != null && !pin.refused) DialFailure.KeyRefused(e) else DialFailure.Unreachable(e)
        }
        if (s.applicationProtocol != alpn) { s.close(); throw DialFailure.NotSill(null) }
        s.soTimeout = 0
        return TlsConnection(s)
    }

    fun tune(s: Socket) {
        s.tcpNoDelay = true
        s.keepAlive = true
        try { s.trafficClass = TRAFFIC_CLASS } catch (_: Exception) {}
    }

    /** A plain TCP dial: only a development Mac's plain door (the CLI without --pairing). */
    fun dialPlain(address: SocketAddress, timeoutMs: Int = DIAL_TIMEOUT_MS): PlainConnection {
        val s = Socket()
        try { tune(s); s.connect(address, timeoutMs) } catch (e: IOException) { s.close(); throw DialFailure.Unreachable(e) }
        return PlainConnection(s)
    }

    internal fun classify(e: Throwable, pin: PinTrustManager): DialFailure {
        if (pin.refused) return DialFailure.PinRefused(pin.seen)
        return classifyAfterHandshake(e)
    }

    /**
     * A failure once TLS is up: in TLS 1.3 the client's certificate is judged after the client's
     * handshake is done, so a Mac refusing this device's key shows as an alert on the first read.
     */
    fun classifyAfterHandshake(e: Throwable): DialFailure {
        val m = generateSequence(e) { it.cause }.mapNotNull { it.message }.joinToString(" ").lowercase()
        return when {
            "bad_certificate" in m || "certificate_unknown" in m || "certificate_required" in m || "unsupported_certificate" in m ||
                "access_denied" in m -> DialFailure.KeyRefused(e)
            "no_application_protocol" in m || "protocol_version" in m || "unrecognized ssl message" in m ||
                "plaintext" in m || "handshake_failure" in m -> DialFailure.NotSill(e)
            else -> DialFailure.Unreachable(e)
        }
    }
}

/** Trust is the pin: the leaf's SPKI hash, nothing else about the certificate. */
internal class PinTrustManager(private val trust: Trust) : X509ExtendedTrustManager() {
    @Volatile var seen: ByteArray? = null
    @Volatile var refused = false

    private fun check(chain: Array<out X509Certificate>?) {
        val fp = chain?.firstOrNull()?.let { Spki.fingerprint(it.publicKey) }
        seen = fp
        val ok = fp != null && when (trust) {
            is Trust.Pinned -> java.security.MessageDigest.isEqual(fp, trust.fingerprint)
            Trust.AnyKey -> true
        }
        if (!ok) { refused = true; throw CertificateException("pin refused") }
    }

    override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) = check(chain)
    override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?, socket: Socket?) = check(chain)
    override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?, engine: SSLEngine?) = check(chain)
    override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) = throw CertificateException("client only")
    override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?, socket: Socket?) = throw CertificateException("client only")
    override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?, engine: SSLEngine?) = throw CertificateException("client only")
    override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
}

/** Presents this client's one certificate whatever the server asks for. */
internal class IdentityKeyManager(private val identity: Identity) : X509ExtendedKeyManager() {
    private val alias = "sill"
    override fun chooseClientAlias(keyType: Array<out String>?, issuers: Array<out Principal>?, socket: Socket?) = alias
    override fun chooseEngineClientAlias(keyType: Array<out String>?, issuers: Array<out Principal>?, engine: SSLEngine?) = alias
    override fun getCertificateChain(a: String?): Array<X509Certificate> = arrayOf(identity.certificate)
    override fun getPrivateKey(a: String?): PrivateKey = identity.keyPair.private
    override fun getClientAliases(keyType: String?, issuers: Array<out Principal>?) = arrayOf(alias)
    override fun getServerAliases(keyType: String?, issuers: Array<out Principal>?) = arrayOf(alias)
    override fun chooseServerAlias(keyType: String?, issuers: Array<out Principal>?, socket: Socket?) = alias
    override fun chooseEngineServerAlias(keyType: String?, issuers: Array<out Principal>?, engine: SSLEngine?) = alias
}

/**
 * The server side of the same TLS, for tests and the model host only (the Mac is the server in
 * Sill): offers both ALPNs, requires a client certificate, and records the client's fingerprint.
 */
object SillTlsServer {
    /** `acceptClient` gets the client's fingerprint and the ALPN negotiated so far, as the Mac's verify block does. */
    fun context(identity: Identity, acceptClient: (ByteArray?, String?) -> Boolean): SSLContext {
        val tm = object : X509ExtendedTrustManager() {
            private fun check(chain: Array<out X509Certificate>?, alpn: String?) {
                if (!acceptClient(chain?.firstOrNull()?.let { Spki.fingerprint(it.publicKey) }, alpn)) throw CertificateException("unpaired")
            }
            override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?) = check(chain, null)
            override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?, socket: Socket?) =
                check(chain, (socket as? SSLSocket)?.handshakeApplicationProtocol)
            override fun checkClientTrusted(chain: Array<out X509Certificate>?, authType: String?, engine: SSLEngine?) =
                check(chain, engine?.handshakeApplicationProtocol)
            override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?) = throw CertificateException()
            override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?, socket: Socket?) = throw CertificateException()
            override fun checkServerTrusted(chain: Array<out X509Certificate>?, authType: String?, engine: SSLEngine?) = throw CertificateException()
            override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
        }
        return SSLContext.getInstance("TLSv1.3").apply { init(arrayOf(IdentityKeyManager(identity)), arrayOf(tm), SecureRandom()) }
    }

    fun configure(s: SSLSocket) {
        s.useClientMode = false
        s.sslParameters = s.sslParameters.apply {
            protocols = arrayOf("TLSv1.3")
            applicationProtocols = arrayOf(SillTls.SESSION_ALPN, SillTls.PAIRING_ALPN)
            needClientAuth = true
        }
    }
}
