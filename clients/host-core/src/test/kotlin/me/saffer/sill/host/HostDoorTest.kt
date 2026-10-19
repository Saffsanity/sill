package me.saffer.sill.host

import me.saffer.sill.core.Identity
import me.saffer.sill.core.Kind
import me.saffer.sill.core.KeyValueStore
import me.saffer.sill.core.PairRequest
import me.saffer.sill.core.PairResult
import me.saffer.sill.core.SillTls
import me.saffer.sill.core.StreamMessage
import java.io.IOException
import java.net.InetAddress
import java.net.Socket
import java.security.KeyStore
import java.security.SecureRandom
import java.security.cert.X509Certificate
import java.util.concurrent.atomic.AtomicInteger
import javax.net.ssl.KeyManagerFactory
import javax.net.ssl.SSLContext
import javax.net.ssl.SSLSocket
import javax.net.ssl.X509TrustManager
import kotlin.test.Test
import kotlin.test.assertEquals

/** The door's TLS: nothing a handshake skips lets an unpaired key in (the review's finding 1). */
class HostDoorTest {
    /**
     * One client context for both dials, so JSSE offers the first connection's ticket on the second:
     * a pairing connection (any key is let in there), then a session from the same unpaired key.
     */
    @Test fun aTicketFromAPairingConnectionIsNoSession() {
        val trust = TrustList(KeyValueStore.Memory())
        val sessions = AtomicInteger()
        val door = HostDoor(Identity.generate(), trust, 0, InetAddress.getLoopbackAddress(), log = {},
            onPairRequest = { _, _, _ -> PairResult(ok = false, reason = PairResult.CLOSED) },
            onSession = { s, _, _ -> sessions.incrementAndGet(); s.close() })
        door.start()
        try {
            val me = Identity.generate()
            val ks = KeyStore.getInstance("PKCS12").apply { load(null, null); setKeyEntry("sill", me.keyPair.private, CharArray(0), arrayOf(me.certificate)) }
            val kmf = KeyManagerFactory.getInstance("PKIX").apply { init(ks, CharArray(0)) }
            val anyServer = object : X509TrustManager {
                override fun checkClientTrusted(c: Array<out X509Certificate>?, a: String?) {}
                override fun checkServerTrusted(c: Array<out X509Certificate>?, a: String?) {}
                override fun getAcceptedIssuers(): Array<X509Certificate> = emptyArray()
            }
            val ctx = SSLContext.getInstance("TLSv1.3").apply { init(kmf.keyManagers, arrayOf(anyServer), SecureRandom()) }
            fun dial(alpn: String): SSLSocket {
                val s = ctx.socketFactory.createSocket(Socket(InetAddress.getLoopbackAddress(), door.port), "127.0.0.1", door.port, true) as SSLSocket
                s.sslParameters = s.sslParameters.apply { protocols = arrayOf("TLSv1.3"); applicationProtocols = arrayOf(alpn) }
                s.soTimeout = 5000
                s.startHandshake()
                return s
            }
            dial(SillTls.PAIRING_ALPN).use { s ->
                s.outputStream.write(StreamMessage.json(Kind.PAIR_REQUEST, PairRequest(method = "code", proof = "x", name = "t", model = null).toJson()).serialized())
                try { while (s.inputStream.read() >= 0) {} } catch (_: IOException) {}
            }
            repeat(3) {
                try { dial(SillTls.SESSION_ALPN).use { s -> s.inputStream.read() } } catch (_: IOException) {}
            }
            Thread.sleep(300)
            assertEquals(0, sessions.get(), "an unpaired key became a session")
        } finally { door.close() }
    }
}
