package me.saffer.sill.core

import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** A session against the model Mac: the order of messages, video, input, stats, liveness and goodbyes. */
class SessionTest {
    private val device = Identity.generate()
    private val info = ClientInfo("0.6.0", "7", "Test (JVM)", "PC", "JVM", "test-pc")

    /** A wall and monotonic clock that can be pushed forward. */
    class ShiftClock : Clock {
        @Volatile var offset = 0.0
        override fun mono() = Clock.System.mono() + offset
        override fun wall() = Clock.System.wall()
    }

    class Recorder : SessionListener {
        val events = CopyOnWriteArrayList<String>()
        val connected = CountDownLatch(1)
        val ended = CountDownLatch(1)
        val frames = CopyOnWriteArrayList<ByteArray>()
        var end: SessionEnd? = null
        var info: MacInfo? = null
        var stats = CopyOnWriteArrayList<ClientStats>()
        val pointer = CopyOnWriteArrayList<Pair<Double, Double>?>()
        override fun onConnected(list: WindowList) { events.add("connected ${list.macName}"); connected.countDown() }
        override fun onVideoFormat(sets: ParameterSets) { events.add("format ${sets.sets.size}") }
        override fun onFrame(annexB: ByteArray, keyframe: Boolean, timestamp: Double) { frames.add(annexB); events.add("frame $keyframe") }
        override fun onMacInfo(info: MacInfo, fingerprint: ByteArray) { this.info = info }
        override fun onStats(stats: ClientStats) { this.stats.add(stats) }
        override fun onMacPointer(position: Pair<Double, Double>?) { pointer.add(position) }
        override fun onEnded(end: SessionEnd) { this.end = end; ended.countDown() }
    }

    private fun start(host: ModelHost, clock: Clock = Clock.System, r: Recorder = Recorder()): Pair<SillSession, Recorder> {
        host.requirePairing = false
        val c = SillTls.dial(host.address, device, SillTls.SESSION_ALPN, Trust.Pinned(host.fingerprint))
        val s = SillSession(c, info, r, clock)
        s.start(Viewport(800.0, 600.0, null, fps = 60))
        assertTrue(r.connected.await(5, TimeUnit.SECONDS), "connected")
        return s to r
    }

    @Test
    fun helloFirstThenTheDesktopAndVideo() {
        ModelHost().use { host ->
            val (s, r) = start(host)
            val hs = host.latestSession()!!
            assertTrue(host.violations.isEmpty(), "${host.violations}")
            assertEquals(Hello("0.6.0", "7", 1, "Test (JVM)"), hs.hello)
            val until = System.nanoTime() + 3_000_000_000
            while (hs.all.size < 2 && System.nanoTime() < until) Thread.sleep(10)
            assertEquals(Kind.HELLO, hs.all[0].kind)
            assertEquals(Viewport(800.0, 600.0, null, fps = 60), Viewport.fromJson(JsonObj.parse(hs.all[1].payload)))
            // Nothing streams: the device asks for the Desktop by itself.
            val pick = assertNotNull(hs.await(Kind.SELECT_SOURCE))
            assertEquals(StreamSource.Desktop, StreamSource.fromJson(JsonObj.parse(pick.payload)))
            // The video: the format, then the keyframe and the deltas, each as Annex B.
            val deadline = System.nanoTime() + 3_000_000_000
            while (r.frames.size < 6 && System.nanoTime() < deadline) Thread.sleep(20)
            assertEquals(6, r.frames.size, "${r.events}")
            assertEquals("format 3", r.events[1])
            assertContentEquals(byteArrayOf(0, 0, 0, 1, 38, 1), r.frames[0].copyOfRange(0, 6))
            // Kind 18 from this connection's Mac.
            assertEquals(host.macID, r.info?.macID)
            s.close()
        }
    }

    @Test
    fun framesBeforeAKeyframeAreDropped() {
        val g = VideoGate()
        val sets = ModelHost.defaultVideo().first
        val (key, delta) = ModelHost.defaultVideo().second.let { it[0].second to it[1].second }
        assertIs<VideoGate.Out.Drop>(g.frame(delta, false, 0.0))
        assertIs<VideoGate.Out.Format>(g.parameterSets(sets.encoded()))
        assertNull(g.parameterSets(sets.encoded()))                 // a repeat changes nothing
        assertIs<VideoGate.Out.Drop>(g.frame(delta, false, 0.0))
        assertIs<VideoGate.Out.Decode>(g.frame(key, true, 0.0))
        assertIs<VideoGate.Out.Decode>(g.frame(delta, false, 0.0))
        g.decoderFailed()
        assertIs<VideoGate.Out.Drop>(g.frame(delta, false, 0.0))
        assertIs<VideoGate.Out.Drop>(g.frame(byteArrayOf(0, 0, 0, 9, 1), true, 0.0))   // lengths that do not add up
        assertEquals(listOf(19), AccessUnit.nalTypes(key, 4))
    }

    @Test
    fun inputIsCoalescedAndCounted() {
        ModelHost().use { host ->
            val (s, _) = start(host)
            val hs = host.latestSession()!!
            repeat(200) { s.input(InputEvent.Pointer(PointerAction.MOVE, it / 200.0, 0.5)) }
            s.input(InputEvent.Pointer(PointerAction.LEFT_DOWN, 0.9, 0.5))
            s.input(InputEvent.Pointer(PointerAction.LEFT_UP, 0.9, 0.5))
            s.input(InputEvent.Text("hé\n"))
            s.input(InputEvent.Key(0x2C, true, Modifiers.COMMAND))
            Thread.sleep(400)
            val inputs = hs.all.filter { it.kind == Kind.INPUT }.map { InputEvent.fromJson(JsonObj.parse(it.payload)) }
            val moves = inputs.filterIsInstance<InputEvent.Pointer>().filter { it.action == PointerAction.MOVE }
            assertTrue(moves.size in 1..3, "${moves.size} moves sent for 200")
            assertEquals(0.995, moves.last().x)                    // the last position, before the press
            val i = inputs.indexOfFirst { it is InputEvent.Pointer && it.action == PointerAction.LEFT_DOWN }
            assertIs<InputEvent.Pointer>(inputs[i - 1])
            assertEquals(listOf(InputEvent.Pointer(PointerAction.LEFT_UP, 0.9, 0.5), InputEvent.Text("hé\n"), InputEvent.Key(0x2C, true, Modifiers.COMMAND)), inputs.takeLast(3))
            assertEquals(inputs.size, s.inputsSent)
            s.close()
        }
    }

    @Test
    fun aStaleMacPointerIsDropped() {
        ModelHost().use { host ->
            val (s, r) = start(host)
            val hs = host.latestSession()!!
            s.input(InputEvent.Pointer(PointerAction.LEFT_DOWN, 0.1, 0.1))
            Thread.sleep(150)
            hs.send(StreamMessage.json(Kind.MAC_POINTER, MacPointer(0.5, 0.5, true, seen = 0).toJson()))      // before our press
            hs.send(StreamMessage.json(Kind.MAC_POINTER, MacPointer(0.25, 0.75, true, seen = s.inputsSent).toJson()))
            hs.send(StreamMessage.json(Kind.MAC_POINTER, MacPointer(inside = false, seen = s.inputsSent).toJson()))
            Thread.sleep(300)
            assertEquals(listOf(0.25 to 0.75, null), r.pointer.toList())
            s.close()
        }
    }

    @Test
    fun statsPingsAndAMacInfoFromAnotherKeyIgnored() {
        ModelHost().use { host ->
            val (s, r) = start(host)
            val hs = host.latestSession()!!
            val stats = assertNotNull(hs.await(Kind.CLIENT_STATS, 3.0))
            val st = ClientStats.fromJson(JsonObj.parse(stats.payload))
            assertEquals("Test (JVM)", st.device)
            assertTrue(hs.all.count { it.kind == Kind.PING } >= 3)
            val r2 = r.stats.lastOrNull { it.rttMs >= 0 }
            assertNotNull(r2, "a second with a round trip: ${r.stats}")
            // A kind 18 signed by another Mac's key never names this session.
            r.info = null
            hs.send(StreamMessage.json(Kind.MAC_INFO, MacInfoSignature.sign(MacInfo(macID = MacId.make(Identity.generate().fingerprint), name = "x",
                issuedAt = 1.0, remoteAccess = true, remotePort = 1, internet = false, addresses = emptyList()), Identity.generate().keyPair).toJson()))
            Thread.sleep(200)
            assertNull(r.info)
            s.close()
        }
    }

    @Test
    fun aGoodbyeThenTheClose() {
        ModelHost().use { host ->
            val (_, r) = start(host)
            host.latestSession()!!.goodbye(Goodbye(Goodbye.QUIT))
            assertTrue(r.ended.await(5, TimeUnit.SECONDS))
            assertEquals(Goodbye(Goodbye.QUIT), r.end?.goodbye)
            assertIs<SessionEnd.Closed>(r.end)
        }
    }

    @Test
    fun silenceEndsTheSession() {
        ModelHost().use { host ->
            val clock = ShiftClock()
            val (_, r) = start(host, clock)
            host.latestSession()!!.silent = true
            Thread.sleep(500)                       // what was already on its way arrives first
            clock.offset = 7.0
            assertTrue(r.ended.await(3, TimeUnit.SECONDS))
            assertIs<SessionEnd.Lost>(r.end)
        }
    }

    @Test
    fun aMessageTooBigEndsTheSession() {
        ModelHost().use { host ->
            val (_, r) = start(host)
            // A header announcing 5 MiB of window list (the cap is 4 MiB): closed before any payload.
            val hs = host.latestSession()!!
            val f = hs.javaClass.getDeclaredField("out").apply { isAccessible = true }.get(hs) as java.io.OutputStream
            f.write(java.nio.ByteBuffer.allocate(14).put(Kind.WINDOW_LIST.toByte()).putLong(0).put(0).putInt(5 shl 20).array()); f.flush()
            assertTrue(r.ended.await(5, TimeUnit.SECONDS))
            val e = assertIs<SessionEnd.Failed>(r.end)
            assertIs<MessageReader.TooBig>(e.error)
        }
    }

    @Test
    fun aRefusedKeyEndsAsRefused() {
        // Paired devices only, and this one is not: the session ends as "the Mac refused this device's key",
        // however the timing falls (the writer's hello or the reader first), so the client can mark it removed.
        repeat(5) {
            ModelHost().use { host ->
                val r = Recorder()
                val c = try { SillTls.dial(host.address, device, SillTls.SESSION_ALPN, Trust.Pinned(host.fingerprint)) }
                    catch (e: DialFailure.KeyRefused) { return@use }
                SillSession(c, info, r).start(Viewport(800.0, 600.0, null))
                assertTrue(r.ended.await(5, TimeUnit.SECONDS))
                val f = assertIs<SessionEnd.Failed>(r.end)
                assertIs<DialFailure.KeyRefused>(f.error, "${f.error::class.simpleName}: ${f.error.message}")
            }
        }
    }

    @Test
    fun autoDesktopRule() {
        val list = WindowList("Mac", listOf(WindowInfo(5, "a", "A", "a", 1, 1)), StreamSource.None)
        assertEquals(AutoDesktop.Decision.Now, AutoDesktop.decide(StreamSource.None, list, null, 100.0, -1))
        assertEquals(AutoDesktop.Decision.Now, AutoDesktop.decide(StreamSource.Desktop, list, 80.0, 100.0, -1))
        assertEquals(AutoDesktop.Decision.None, AutoDesktop.decide(StreamSource.Desktop, list, 95.0, 100.0, -1))
        assertEquals(AutoDesktop.Decision.None, AutoDesktop.decide(StreamSource.Window(5), list, null, 100.0, -1))
        assertEquals(AutoDesktop.Decision.After(2.25, 6), AutoDesktop.decide(StreamSource.Window(6), list, null, 100.0, 250))
        assertEquals(AutoDesktop.Decision.None, AutoDesktop.decide(StreamSource.None, list.copy(active = StreamSource.Desktop), null, 100.0, -1))
    }

    @Test
    fun statsWindow() {
        val clock = ShiftClock()
        val w = StatsWindow(clock)
        val empty = w.close("d")
        assertEquals(listOf(-1, -1, -1, -1), listOf(empty.frameAgeMs, empty.rttMs, empty.frameAgeMaxMs, empty.rttMaxMs))
        listOf(9, 7, 30).forEach(w::rtt)
        val s = w.close("d")
        assertEquals(9, s.rttMs); assertEquals(30, s.rttMaxMs); assertEquals(30, w.lastRttMaxMs)
        assertEquals(30, w.close("d").let { w.lastRttMaxMs })     // kept through a second without a pong
    }
}
