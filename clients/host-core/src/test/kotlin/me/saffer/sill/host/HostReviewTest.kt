package me.saffer.sill.host

import me.saffer.sill.core.Identity
import me.saffer.sill.core.InputEvent
import me.saffer.sill.core.JsonObj
import me.saffer.sill.core.KeyValueStore
import me.saffer.sill.core.Kind
import me.saffer.sill.core.LaunchApp
import me.saffer.sill.core.MessageReader
import me.saffer.sill.core.PairRequest
import me.saffer.sill.core.PairResult
import me.saffer.sill.core.PointerAction
import me.saffer.sill.core.SillTls
import me.saffer.sill.core.StreamMessage
import me.saffer.sill.core.StreamSource
import me.saffer.sill.core.TlsConnection
import me.saffer.sill.core.Trust
import me.saffer.sill.core.HidKeys
import java.net.InetAddress
import java.net.InetSocketAddress
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** The review's findings 2 to 5 on the PC host, each against a raw device session. */
class HostReviewTest {
    private fun host(p: FakePlatform, log: MutableList<String>) =
        StreamHost(p, KeyValueStore.Memory(), "0.6.0", persistent = true, port = 0, bind = InetAddress.getLoopbackAddress(), advertise = false,
            log = { log.add(it); println(it) }).also { it.start() }

    private fun waitFor(what: String, seconds: Double = 10.0, f: () -> Boolean) {
        val end = System.nanoTime() + (seconds * 1e9).toLong()
        while (!f()) { if (System.nanoTime() > end) throw AssertionError("timed out waiting for $what"); Thread.sleep(20) }
    }

    private class Device(val c: TlsConnection) {
        val reader = MessageReader(c.input)
        fun send(m: StreamMessage) { c.output.write(m.serialized()); c.output.flush() }
        fun input(e: InputEvent) = send(StreamMessage.json(Kind.INPUT, e.toJson()))
        fun select(s: StreamSource) = send(StreamMessage.json(Kind.SELECT_SOURCE, s.toJson()))
    }

    private fun session(h: StreamHost, me: Identity = Identity.generate()): Device {
        val d = Device(SillTls.dial(InetSocketAddress(InetAddress.getLoopbackAddress(), h.boundPort), me, SillTls.SESSION_ALPN, Trust.AnyKey))
        assertEquals(Kind.WINDOW_LIST, d.reader.next()!!.kind)
        Thread { try { while (d.reader.next() != null) {} } catch (_: Exception) {} }.apply { isDaemon = true }.start()
        return d
    }

    private fun ask(h: StreamHost, me: Identity): PairResult {
        val c = SillTls.dial(InetSocketAddress(InetAddress.getLoopbackAddress(), h.boundPort), me, SillTls.PAIRING_ALPN, Trust.AnyKey)
        c.output.write(StreamMessage.json(Kind.PAIR_REQUEST, PairRequest(method = PairRequest.ASK, proof = "", name = "Phone", model = null).toJson()).serialized())
        c.output.flush()
        val m = assertNotNull(MessageReader(c.input).next())
        c.close()
        return PairResult.fromJson(JsonObj.parse(m.payload))
    }

    /** Finding 3: a button's or a key's up with nowhere to land still reaches the PC. */
    @Test fun upsWithNothingStreamingAreLetGo() {
        val p = FakePlatform(); val log = CopyOnWriteArrayList<String>()
        host(p, log).use { h ->
            h.setRequirePairing(false)
            val d = session(h)
            d.select(StreamSource.Desktop)
            waitFor("the desktop") { p.started.isNotEmpty() }
            d.input(InputEvent.Pointer(PointerAction.LEFT_DOWN, 0.5, 0.5))
            d.input(InputEvent.Key(HidKeys.LEFT_COMMAND, true, 0))
            waitFor("held") { "button 1 down" in p.events && "key 0xE0 down" in p.events }
            d.select(StreamSource.None)
            Thread.sleep(300)
            p.events.clear()
            d.input(InputEvent.Pointer(PointerAction.LEFT_UP, 0.5, 0.5))
            d.input(InputEvent.Key(HidKeys.LEFT_COMMAND, false, 0))
            d.input(InputEvent.Pointer(PointerAction.RIGHT_UP, 0.5, 0.5))
            d.input(InputEvent.Pointer(PointerAction.LEFT_DOWN, 0.2, 0.2))
            waitFor("the ups") { "button 1 up" in p.events && "key 0xE0 up" in p.events }
            Thread.sleep(200)
            assertEquals(listOf("button 1 up", "key 0xE0 up"), p.events.toList(), "only the held ups, no move, no new down, no right button")
            d.c.close()
        }
    }

    /** Finding 2: a device's id is never a path to run. */
    @Test fun onlyListedAppsLaunch() {
        val p = FakePlatform(); val log = CopyOnWriteArrayList<String>()
        host(p, log).use { h ->
            h.setRequirePairing(false)
            val d = session(h)
            d.send(StreamMessage.json(Kind.LAUNCH_APP, LaunchApp("C:\\Users\\x\\Downloads\\evil.bat").toJson()))
            d.send(StreamMessage.json(Kind.LAUNCH_APP, LaunchApp("\\\\attacker\\share\\x.exe").toJson()))
            d.send(StreamMessage.json(Kind.LAUNCH_APP, LaunchApp("editor").toJson()))
            waitFor("the listed app") { "editor" in p.launched }
            Thread.sleep(200)
            assertEquals(listOf("editor"), p.launched.toList())
            assertEquals(2, log.count { "Launch refused" in it })
            d.c.close()
        }
    }

    /** Finding 4: Pair This iPad… from a session keeps the ask rule's limits. */
    @Test fun kind21KeepsTheAskLimits() {
        val p = FakePlatform(); val log = CopyOnWriteArrayList<String>()
        host(p, log).use { h ->
            h.setRequirePairing(false)
            val d = session(h)
            d.send(StreamMessage.empty(Kind.PAIRING_WANTED))
            waitFor("the window") { h.pairing.current != null }
            assertNotNull(h.pairingAskedBy(), "the window says which device opened it")
            h.cancelPairing()
            d.send(StreamMessage.empty(Kind.PAIRING_WANTED))
            Thread.sleep(400)
            assertNull(h.pairing.current, "the host's Cancel quiets that device")
            assertTrue(log.any { "not shown (openOnMac)" in it }, "$log")
            d.c.close()
        }
    }

    /** Finding 5: a key the host already trusts gets a code, never an ok without a proof. */
    @Test fun aPairedKeysAskShowsACode() {
        val p = FakePlatform(); val log = CopyOnWriteArrayList<String>()
        host(p, log).use { h ->
            val me = Identity.generate()
            h.trust.add(me.fingerprint, "Phone", null, "code", 0.0)
            val r = ask(h, me)
            assertFalse(r.ok)
            assertEquals(PairResult.SHOWN, r.reason)
            assertNotNull(h.pairing.current)
        }
    }
}
