package me.saffer.sill.host

import me.saffer.sill.core.Base64Url
import me.saffer.sill.core.Clock
import me.saffer.sill.core.Dns
import me.saffer.sill.core.HidKeys
import me.saffer.sill.core.Identity
import me.saffer.sill.core.InputEvent
import me.saffer.sill.core.KeyValueStore
import me.saffer.sill.core.MdnsBrowser
import me.saffer.sill.core.Modifiers
import me.saffer.sill.core.PairRequest
import me.saffer.sill.core.PairResult
import me.saffer.sill.core.PairingProof
import me.saffer.sill.core.PointerAction
import me.saffer.sill.core.RecognitionTag
import java.net.InetAddress
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** The pairing window's and the ask's rules, the Mac's input made the PC's, the trust list, and the Bonjour answers. */
class HostRulesTest {
    private val mac = Identity.generate().fingerprint
    private val dev = Identity.generate().fingerprint

    private fun window(t: DoubleArray) = PairingWindow(mac, { t[0] })
    private fun waitKey(w: PairingWindow, code: String) {
        // The code's key is derived off the caller's thread (PBKDF2, 600,000 rounds).
        repeat(200) {
            val r = w.check(PairRequest.CODE, "AAAA", Identity.generate().fingerprint, "probe-$it")
            if (r is PairingWindow.Outcome.Refused && r.result.reason != PairResult.BUSY) return
            Thread.sleep(50)
        }
    }

    @Test
    fun pairingWindowRules() {
        val t = doubleArrayOf(0.0)
        val w = window(t)
        assertIs<PairingWindow.Outcome.Refused>(w.check(PairRequest.QR, "x", dev, "a")).also { assertEquals(PairResult.CLOSED, it.result.reason) }
        val s = w.open()
        assertEquals(s.code, w.open().code, "opening again keeps the code")
        // The link's secret pairs at once.
        val proof = Base64Url.encode(PairingProof.deviceProof(s.secret, dev, mac))
        val ok = assertIs<PairingWindow.Outcome.Paired>(w.check(PairRequest.QR, proof, dev, "a"))
        assertEquals(PairRequest.QR, ok.method)
        assertNull(w.current, "single use")

        // Wrong codes: tries left, slower each time, stopped at five; the same source once per 5 s.
        val s2 = w.open()
        assertTrue(s2.code != s.code)
        waitKey(w, s2.code)
        t[0] += 10
        var r = assertIs<PairingWindow.Outcome.Refused>(w.check(PairRequest.CODE, "AAAA", dev, "b")).result
        assertEquals(PairResult.CODE, r.reason); assertEquals(3, r.triesLeft)   // waitKey's probe spent one
        r = assertIs<PairingWindow.Outcome.Refused>(w.check(PairRequest.CODE, "AAAA", dev, "c")).result
        assertEquals(PairResult.BUSY, r.reason); assertTrue(r.retryAfter!! in 0.1..2.0, "${r.retryAfter}")
        t[0] += 2.0
        r = assertIs<PairingWindow.Outcome.Refused>(w.check(PairRequest.CODE, "AAAA", dev, "b")).result
        assertEquals(PairResult.BUSY, r.reason, "the same source within 5 s")
        t[0] += 10
        r = assertIs<PairingWindow.Outcome.Refused>(w.check(PairRequest.CODE, "AAAA", dev, "c")).result
        assertEquals(2, r.triesLeft)
        t[0] += 10; w.check(PairRequest.CODE, "AAAA", dev, "d")
        t[0] += 10
        r = assertIs<PairingWindow.Outcome.Refused>(w.check(PairRequest.CODE, "AAAA", dev, "e")).result
        assertEquals(PairResult.STOPPED, r.reason)
        t[0] += 10
        assertEquals(PairResult.CLOSED, assertIs<PairingWindow.Outcome.Refused>(w.check(PairRequest.CODE, "AAAA", dev, "f")).result.reason)

        // The right code pairs; an expired window says so.
        val s3 = w.open()
        waitKey(w, s3.code)
        t[0] += 10
        val key = assertNotNull(PairingProof.codeKey(s3.code, mac))
        assertIs<PairingWindow.Outcome.Paired>(w.check(PairRequest.CODE, Base64Url.encode(PairingProof.deviceProof(key, dev, mac)), dev, "g"))
        w.open(); t[0] += 301
        assertEquals(PairResult.EXPIRED, assertIs<PairingWindow.Outcome.Refused>(w.check(PairRequest.QR, "x", dev, "h")).result.reason)
    }

    @Test
    fun askRule() {
        val t = doubleArrayOf(0.0)
        val a = AskLimits({ t[0] })
        assertEquals(AskLimits.Decision.Answer(PairResult.LOCKED), a.decide(true, false, "k", "1"))
        assertEquals(AskLimits.Decision.Answer(PairResult.SHOWN), a.decide(false, true, "k", "1"))
        repeat(3) { assertEquals(AskLimits.Decision.Open, a.decide(false, false, "k$it", "a$it")) }
        assertEquals(AskLimits.Decision.Answer(PairResult.OPEN_ON_MAC), a.decide(false, false, "k9", "a9"), "three in 10 minutes")
        t[0] += 601
        a.quiet("k", "1")
        assertEquals(AskLimits.Decision.Answer(PairResult.OPEN_ON_MAC), a.decide(false, false, "k", "2"))
        assertEquals(AskLimits.Decision.Answer(PairResult.OPEN_ON_MAC), a.decide(false, false, "other", "1"))
        assertEquals(AskLimits.Decision.Open, a.decide(false, false, "other", "2"))
    }

    private class Sink : InputSink {
        val e = ArrayList<String>()
        override fun move(x: Int, y: Int) { e += "move $x,$y" }
        override fun button(button: Int, down: Boolean) { e += "button $button $down" }
        override fun wheel(dx: Double, dy: Double) { e += "wheel %.1f,%.1f".format(dx, dy) }
        override fun key(usage: Int, down: Boolean) { e += "key %02X $down".format(usage) }
        override fun text(s: String) { e += "text $s" }
    }

    @Test
    fun macInputAsThePCs() {
        val sink = Sink()
        val t = InputTranslator(sink, Rect(100, 100, 401, 201))
        t.handle(InputEvent.Pointer(PointerAction.RIGHT_DOWN, 1.0, 0.0))
        assertEquals(listOf("move 500,100", "button 3 true"), sink.e); sink.e.clear()
        // Scrolling a tenth of the frame down (content moving down) is the wheel's up, in notches of 40 px.
        t.handle(InputEvent.Scroll(0.5, 0.5, 0.0, 0.2))
        assertEquals("wheel 0.0,1.0", sink.e.last().replace("-0.0", "0.0")); sink.e.clear()
        // ⌘Space is the Windows key; ⌘Q is Alt+F4; ⌥← is Ctrl+←; ⌘⇧Z is Ctrl+Shift+Z.
        t.handle(InputEvent.Key(HidKeys.SPACE, true, Modifiers.COMMAND)); t.handle(InputEvent.Key(HidKeys.SPACE, false, Modifiers.COMMAND))
        assertEquals(listOf("key E3 true", "key E3 false"), sink.e); sink.e.clear()
        t.handle(InputEvent.Key(0x14, true, Modifiers.COMMAND)); t.handle(InputEvent.Key(0x14, false, Modifiers.COMMAND))
        assertEquals(listOf("key E2 true", "key 3D true", "key 3D false", "key E2 false"), sink.e); sink.e.clear()
        t.handle(InputEvent.Key(HidKeys.LEFT, true, Modifiers.OPTION))
        assertEquals(listOf("key E0 true", "key 50 true"), sink.e); sink.e.clear()
        t.handle(InputEvent.Key(HidKeys.LEFT, false, Modifiers.OPTION))
        t.handle(InputEvent.Key(0x1D, true, Modifiers.COMMAND or Modifiers.SHIFT))
        assertEquals(listOf("key 50 false", "key E0 false", "key E0 true", "key E1 true", "key 1D true"), sink.e); sink.e.clear()
        t.handle(InputEvent.Key(0x1D, false, Modifiers.COMMAND or Modifiers.SHIFT))
        // Typing with no modifier lets go of the ones a shortcut pressed.
        t.handle(InputEvent.Text("a\tb"))
        assertEquals(listOf("key 1D false", "key E0 false", "key E1 false", "text a", "key 2B true", "key 2B false", "text b"), sink.e); sink.e.clear()
        // A held modifier key of the device's own is held on the PC until its up; the device leaving lets everything go.
        t.handle(InputEvent.Key(HidKeys.LEFT_SHIFT, true, Modifiers.SHIFT))
        t.handle(InputEvent.Key(0x04, true, Modifiers.SHIFT))
        assertEquals(listOf("key E1 true", "key 04 true"), sink.e); sink.e.clear()
        t.releaseAll()
        assertEquals(listOf("key 04 false", "key E1 false", "button 1 false", "button 3 false"), sink.e)
    }

    @Test
    fun trustList() {
        val store = KeyValueStore.Memory()
        val tl = TrustList(store)
        assertTrue(tl.requirePairing)
        assertTrue(!tl.admits(dev))
        tl.add(dev, "iPad\u0000 mini", "iPad14,1", "code", 1.0)
        assertTrue(tl.admits(dev))
        tl.add(dev, "iPad", null, "qr", 2.0)
        assertEquals(1, tl.devices.size, "re-pairing a key replaces its record")
        assertEquals("qr", TrustList(store).devices.single().method)
        tl.setRequirePairing(false)
        assertTrue(TrustList(store).admits(Identity.generate().fingerprint))
        tl.remove(Base64Url.encode(dev))
        assertTrue(TrustList(store).devices.isEmpty())
        val id = HostIdentity(store)
        assertEquals(id.macID, HostIdentity(store).macID)
        assertTrue(RecognitionTag.matches(id.tag(), id.recognitionKey))
    }

    @Test
    fun bonjourAnswersAsTheClientsBrowse() {
        val r = MdnsResponder("Noah's PC", "sill-abcd", 7455, mapOf("r" to "tag", "p" to "1"), addresses = { listOf(InetAddress.getByName("192.168.1.20")) })
        val found = ArrayList<List<me.saffer.sill.core.FoundService>>()
        val b = MdnsBrowser(clock = Clock.System) { found.add(it) }
        // A browse (PTR), then the follow-ups the browser would send, answered as on the group.
        val ptr = assertNotNull(r.answer(Dns.query(listOf("_sill._tcp.local." to Dns.PTR)), 5353))
        assertTrue(ptr.second, "a QU question is answered by unicast")
        b.handlePacket(ptr.first, "eth0")
        val svc = b.current().single()
        assertEquals("Noah's PC", svc.name); assertEquals(7455, svc.port)
        assertEquals("tag", svc.tag); assertEquals(listOf(InetAddress.getByName("192.168.1.20")), svc.addresses)
        // A one-shot query (not from 5353) gets its ID and question back.
        val legacy = assertNotNull(r.answer(Dns.query(listOf("sill-abcd.local." to Dns.A), id = 0x1234), 50000))
        assertEquals(0x12, legacy.first[0].toInt() and 0xFF); assertEquals(1, legacy.first[5].toInt())
        assertNull(r.answer(Dns.query(listOf("_other._tcp.local." to Dns.PTR)), 5353))
        // A name with a dot survives the trip.
        val r2 = MdnsResponder("v1.2 PC", "sill-x", 1, emptyMap(), addresses = { listOf(InetAddress.getByName("10.0.0.2")) })
        val b2 = MdnsBrowser(clock = Clock.System) {}
        b2.handlePacket(r2.answer(Dns.query(listOf("_sill._tcp.local." to Dns.PTR)), 5353)!!.first, "eth0")
        assertEquals("v1.2 PC", b2.current().single().name)
    }
}
