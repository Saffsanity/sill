package me.saffer.sill.core

import java.io.File
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.nio.file.Files
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue

/**
 * The TLS both doors speak, against the model Mac and against `openssl s_server`, an implementation
 * that shares nothing with the JDK's: TLS 1.3 with this client's certificate, the pin, the ALPN.
 */
class TlsTest {
    private val device = Identity.generate()

    @Test
    fun pinnedAndAnyKeyDials() {
        ModelHost().use { host ->
            host.requirePairing = false
            val c = SillTls.dial(host.address, device, SillTls.SESSION_ALPN, Trust.Pinned(host.fingerprint))
            assertEquals(SillTls.SESSION_ALPN, c.alpn)
            assertContentEquals(host.fingerprint, c.peerFingerprint)
            c.close()
            SillTls.dial(host.address, device, SillTls.PAIRING_ALPN, Trust.AnyKey).use { assertEquals(SillTls.PAIRING_ALPN, it.alpn) }
            val e = assertFailsWith<DialFailure.PinRefused> { SillTls.dial(host.address, device, SillTls.SESSION_ALPN, Trust.Pinned(Identity.generate().fingerprint)) }
            assertContentEquals(host.fingerprint, e.seen)
        }
    }

    @Test
    fun anUnpairedKeyIsRefusedOnTheFirstRead() {
        ModelHost().use { host ->
            // A TLS 1.3 server judges the client's certificate after the client's handshake is done, so the
            // refusal shows at the dial or at the first read, depending on timing; either way it reads as refused.
            val e = assertFailsWith<java.io.IOException> {
                val c = SillTls.dial(host.address, device, SillTls.SESSION_ALPN, Trust.Pinned(host.fingerprint))
                c.input.read()
            }
            val d = e as? DialFailure ?: SillTls.classifyAfterHandshake(e)
            assertTrue(d is DialFailure.KeyRefused, "${e::class.simpleName}: ${e.message}")
        }
    }

    @Test
    fun notADoor() {
        ServerSocket(0, 5, InetAddress.getLoopbackAddress()).use { plain ->
            Thread { plain.accept().use { it.getOutputStream().write("SSH-2.0-OpenSSH_9.6\r\n".encodeToByteArray()); Thread.sleep(500) } }.start()
            assertFailsWith<DialFailure.NotSill> { SillTls.dial(InetSocketAddress(InetAddress.getLoopbackAddress(), plain.localPort), device, SillTls.SESSION_ALPN, Trust.AnyKey, 3000) }
        }
        val closed = ServerSocket(0, 5, InetAddress.getLoopbackAddress()).also { it.close() }.localPort
        assertFailsWith<DialFailure.Unreachable> { SillTls.dial(InetSocketAddress(InetAddress.getLoopbackAddress(), closed), device, SillTls.SESSION_ALPN, Trust.AnyKey, 3000) }
    }

    @Test
    fun againstOpenSSL() {
        val openssl = File("/usr/bin/openssl").takeIf { it.canExecute() } ?: return
        val dir = Files.createTempDirectory("sillssl").toFile()
        // The Mac's side: a P-256 key and a certificate openssl made itself.
        fun run(vararg a: String) = ProcessBuilder(openssl.path, *a).redirectErrorStream(true).start().also { assertEquals(0, it.waitFor(), it.inputStream.readBytes().decodeToString()) }
        run("ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", File(dir, "mac.key").path)
        run("req", "-x509", "-new", "-key", File(dir, "mac.key").path, "-subj", "/CN=mac", "-days", "2", "-out", File(dir, "mac.pem").path)
        run("x509", "-in", File(dir, "mac.pem").path, "-noout", "-pubkey", "-out", File(dir, "pub.pem").path)
        run("pkey", "-pubin", "-in", File(dir, "pub.pem").path, "-outform", "DER", "-out", File(dir, "pub.der").path)
        val macFp = sha256(File(dir, "pub.der").readBytes())

        fun server(alpn: String): Pair<Process, Int> {
            val port = ServerSocket(0).use { it.localPort }
            val p = ProcessBuilder(openssl.path, "s_server", "-accept", "127.0.0.1:$port", "-tls1_3", "-cert", File(dir, "mac.pem").path,
                "-key", File(dir, "mac.key").path, "-Verify", "1", "-alpn", alpn, "-naccept", "2", "-quiet").redirectErrorStream(true).start()
            val end = System.nanoTime() + 5_000_000_000
            while (System.nanoTime() < end) { try { java.net.Socket("127.0.0.1", port).close(); break } catch (_: Exception) { Thread.sleep(50) } }
            return p to port
        }

        // (The probe above is the first of its two accepts.) The handshake, our certificate presented, the pin and the ALPN; then bytes through.
        val (p, port) = server("sill/1,sill-pair/1")
        val c = SillTls.dial(InetSocketAddress("127.0.0.1", port), device, SillTls.SESSION_ALPN, Trust.Pinned(macFp))
        assertEquals("sill/1", c.alpn)
        c.output.write("sill-through-openssl\n".encodeToByteArray()); c.output.flush()
        Thread.sleep(300)
        c.close()
        p.waitFor(5, TimeUnit.SECONDS)
        val log = p.inputStream.readBytes().decodeToString()
        assertTrue("sill-through-openssl" in log, log)
        p.destroy()

        // Another key than the pin: refused before anything is sent.
        val (p2, port2) = server("sill/1")
        assertFailsWith<DialFailure.PinRefused> { SillTls.dial(InetSocketAddress("127.0.0.1", port2), device, SillTls.SESSION_ALPN, Trust.Pinned(Identity.generate().fingerprint)) }
        p2.destroy()

        // A server without Sill's ALPN: not a Sill door.
        val (p3, port3) = server("h2")
        val e = assertFailsWith<DialFailure> { SillTls.dial(InetSocketAddress("127.0.0.1", port3), device, SillTls.SESSION_ALPN, Trust.Pinned(macFp)) }
        assertTrue(e is DialFailure.NotSill, "${e::class.simpleName}: ${e.message}")
        p3.destroy()
        dir.deleteRecursively()
    }

    @Test
    fun openSSLAsTheClientOfTheModelMac() {
        // The other direction: openssl presents an openssl-made certificate to this core's server
        // side, which is what the model Mac uses; it proves the model accepts what a real client sends.
        val openssl = File("/usr/bin/openssl").takeIf { it.canExecute() } ?: return
        ModelHost().use { host ->
            host.requirePairing = false
            val dir = Files.createTempDirectory("sillcli").toFile()
            ProcessBuilder(openssl.path, "req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:prime256v1", "-nodes", "-keyout",
                File(dir, "k.pem").path, "-out", File(dir, "c.pem").path, "-subj", "/CN=dev", "-days", "2").start().waitFor()
            val p = ProcessBuilder(openssl.path, "s_client", "-connect", "127.0.0.1:${host.port}", "-tls1_3", "-alpn", "sill-pair/1",
                "-cert", File(dir, "c.pem").path, "-key", File(dir, "k.pem").path, "-servername", "sill").redirectErrorStream(true).start()
            p.outputStream.close()
            p.waitFor(10, TimeUnit.SECONDS)
            val out = p.inputStream.readBytes().decodeToString()
            assertTrue("ALPN protocol: sill-pair/1" in out && "TLSv1.3" in out, out)
            dir.deleteRecursively()
        }
    }
}
