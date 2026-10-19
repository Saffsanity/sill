package me.saffer.sill.core

import java.io.File
import java.net.Inet4Address
import java.net.Inet6Address
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * Discovery: a response python-zeroconf built (mdns-response.hex, clients/wire-vectors/mdns_fixture.py),
 * this core's queries as zeroconf reads them, TTLs, and, with SILL_LIVE_MDNS=1, a live zeroconf
 * responder on this machine's network found by the browser.
 */
class MdnsTest {
    private val fixture = javaClass.getResource("/sill/mdns-response.hex")!!.readText().trim().unhex()

    class ShiftClock : Clock {
        @Volatile var offset = 0.0
        override fun mono() = Clock.System.mono() + offset
        override fun wall() = Clock.System.wall()
    }

    @Test
    fun zeroconfsResponse() {
        val records = assertNotNull(Dns.parseResponse(fixture))
        assertEquals(listOf(Dns.PTR, Dns.SRV, Dns.TXT, Dns.A, Dns.AAAA), records.map { it.type })
        val clock = ShiftClock()
        var seen: List<FoundService> = emptyList()
        val b = MdnsBrowser(clock = clock) { seen = it }
        b.handlePacket(fixture, "en0")
        val f = seen.single()
        assertEquals("Noah’s Mac mini", f.name)
        assertEquals(52144, f.port)
        assertEquals("Noahs-Mac-mini.local.", f.host)
        assertTrue(f.addresses[0] is Inet4Address && f.addresses[0].hostAddress == "192.168.1.20")
        assertTrue(f.addresses[1] is Inet6Address)
        assertEquals(mapOf("r" to "oaKjpKWmL4V47Ctm", "p" to "1", "n" to "café", "flag" to null), f.txt)
        assertEquals("oaKjpKWmL4V47Ctm", f.tag)
        assertEquals(HomeDoorTxt.Door.PAIRING_REQUIRED, f.door)
        // Its TTL (10 s) keeps it listed; past it, it is gone until it answers again.
        clock.offset = 9.0
        assertEquals(1, b.current().size)
        clock.offset = 11.0
        assertEquals(0, b.current().size)
    }

    @Test
    fun aGoodbyeRemovesAndBadPacketsAreRefused() {
        val b = MdnsBrowser { }
        b.handlePacket(fixture, "en0")
        assertEquals(1, b.current().size)
        // The same PTR with TTL 0 (RFC 6762 §10.1): gone at once. The TTL is bytes 6–9 of the answer after its name.
        val bye = fixture.copyOf()
        val ptrNameEnd = Dns.readName(bye, 12).second
        for (i in 4..7) bye[ptrNameEnd + i] = 0
        b.handlePacket(bye, "en0")
        assertEquals(0, b.current().size)
        assertNull(Dns.parseResponse(fixture.copyOf(40)))
        assertNull(Dns.parseResponse(Dns.query(listOf("_sill._tcp.local." to Dns.PTR))))   // a query is not a response
        // A compression pointer to itself never loops.
        val loop = byteArrayOf(0, 0, 0x84.toByte(), 0, 0, 0, 0, 1, 0, 0, 0, 0, 0xC0.toByte(), 12, 0, 12, 0, 1, 0, 0, 0, 10, 0, 0)
        assertNull(Dns.parseResponse(loop))
    }

    @Test
    fun namesAndTxt() {
        assertEquals(listOf("Mac\\.mini".replace("\\", ""), "_sill", "_tcp", "local"), Dns.splitName("Mac\\.mini._sill._tcp.local."))
        val enc = Dns.encodeName("Mac\\.mini._sill._tcp.local.")
        assertEquals("Mac\\.mini._sill._tcp.local.", Dns.readName(enc, 0).first)
        val txt = mapOf("r" to "abc", "p" to "0", "b" to null, "e" to "")
        assertEquals(txt, Dns.parseTxt(Dns.encodeTxt(txt)))
        assertEquals(emptyMap(), Dns.parseTxt(byteArrayOf(0)))
        assertEquals(mapOf("p" to "1"), Dns.parseTxt(Dns.encodeTxt(mapOf("p" to "1")) + Dns.encodeTxt(mapOf("P" to "0"))))
    }

    @Test
    fun ourQueryAsZeroconfReadsIt() {
        val python = File("/usr/bin/python3").takeIf { it.canExecute() } ?: return
        val q = Dns.query(listOf("_sill._tcp.local." to Dns.PTR, "Noah’s Mac mini._sill._tcp.local." to Dns.SRV))
        val script = """
            import sys
            try:
                from zeroconf import DNSIncoming
            except ImportError:
                print("SKIP"); sys.exit(0)
            m = DNSIncoming(bytes.fromhex(sys.argv[1]))
            print(m.is_query(), [(q.name, q.type, q.unicast) for q in m.questions])
        """.trimIndent()
        val p = ProcessBuilder(python.path, "-c", script, q.hex()).redirectErrorStream(true).start()
        val out = p.inputStream.readBytes().decodeToString().trim()
        p.waitFor()
        if (out == "SKIP") return
        assertEquals("True [('_sill._tcp.local.', 12, True), ('Noah’s Mac mini._sill._tcp.local.', 33, True)]", out)
    }

    @Test
    fun liveZeroconfResponder() {
        if (System.getenv("SILL_LIVE_MDNS") != "1") return
        val type = "_silltest._tcp.local."
        val script = """
            import socket, time, sys
            from zeroconf import Zeroconf, ServiceInfo
            z = Zeroconf()
            addrs = [socket.inet_aton(a) for a in sys.argv[1:]]
            info = ServiceInfo("$type", "Live Sill Test.$type", addresses=addrs, port=47455,
                               properties={"r": "oaKjpKWmL4V47Ctm", "p": "0"}, server="live-sill-test.local.")
            z.register_service(info)
            print("REGISTERED", flush=True)
            time.sleep(25)
            z.unregister_service(info); z.close()
        """.trimIndent()
        val addrs = java.net.NetworkInterface.getNetworkInterfaces().toList().filter { it.isUp && !it.isLoopback && it.supportsMulticast() }
            .flatMap { it.inetAddresses.toList() }.filterIsInstance<Inet4Address>().map { it.hostAddress }
        val p = ProcessBuilder(listOf("python3", "-c", script) + addrs).redirectErrorStream(true).start()
        try {
            assertTrue(p.inputStream.bufferedReader().readLine()?.contains("REGISTERED") == true)
            val found = LinkedBlockingQueue<FoundService>()
            val b = MdnsBrowser(type) { l -> l.firstOrNull { it.name == "Live Sill Test" }?.let(found::add) }
            b.start()
            val f = assertNotNull(found.poll(15, TimeUnit.SECONDS), "the browser found the live responder")
            assertEquals(47455, f.port)
            assertEquals(HomeDoorTxt.Door.OPEN, f.door)
            assertEquals("oaKjpKWmL4V47Ctm", f.tag)
            assertTrue(f.addresses.isNotEmpty())
            b.stop()
        } finally { p.destroy() }
    }
}
