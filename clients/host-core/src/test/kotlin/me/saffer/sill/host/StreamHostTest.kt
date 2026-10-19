package me.saffer.sill.host

import me.saffer.sill.core.ClientInfo
import me.saffer.sill.core.DialFailure
import me.saffer.sill.core.FoundService
import me.saffer.sill.core.GoodbyePolicy
import me.saffer.sill.core.HidKeys
import me.saffer.sill.core.HomeDial
import me.saffer.sill.core.HostSettingsChange
import me.saffer.sill.core.HostSettingsState
import me.saffer.sill.core.Identity
import me.saffer.sill.core.IdentityStore
import me.saffer.sill.core.InputEvent
import me.saffer.sill.core.KeyValueStore
import me.saffer.sill.core.Kind
import me.saffer.sill.core.MacInfo
import me.saffer.sill.core.MacRow
import me.saffer.sill.core.MessageReader
import me.saffer.sill.core.Modifiers
import me.saffer.sill.core.PairingPrompt
import me.saffer.sill.core.ParameterSets
import me.saffer.sill.core.PointerAction
import me.saffer.sill.core.QualityPreset
import me.saffer.sill.core.SessionListener
import me.saffer.sill.core.SillClient
import me.saffer.sill.core.SillSession
import me.saffer.sill.core.SillTls
import me.saffer.sill.core.StreamSource
import me.saffer.sill.core.Trust
import me.saffer.sill.core.Viewport
import me.saffer.sill.core.WindowList
import me.saffer.sill.core.ClientListener
import java.net.InetAddress
import java.net.InetSocketAddress
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.test.fail

/**
 * A host on a fake platform against the real Kotlin client, which holds hosts to the Mac's rules:
 * the ask, the code, the pinned session, the catalog, a stream that starts at a keyframe with its
 * parameter sets, input made the PC's, kinds 16 and 17, kind 18 signed by the door's key, the
 * clipboard both ways, a gesture, Remove and Quit.
 */
class StreamHostTest {
    private val info = ClientInfo("0.6.0", "7", "Test (JVM)", "PC", "JVM", "test-pc")

    class UI : ClientListener {
        val prompts = LinkedBlockingQueue<PairingPrompt>()
        val started = LinkedBlockingQueue<SillSession>()
        val ended = LinkedBlockingQueue<GoodbyePolicy.Outcome>()
        @Volatile var rows: List<MacRow> = emptyList()
        override fun onRows(rows: List<MacRow>) { this.rows = rows }
        override fun onPairingPrompt(prompt: PairingPrompt) { prompts.add(prompt) }
        override fun onSessionStarted(session: SillSession, mac: String) { started.add(session) }
        override fun onSessionEnded(outcome: GoodbyePolicy.Outcome) { ended.add(outcome) }
    }

    class Stream : SessionListener {
        val lists = LinkedBlockingQueue<WindowList>()
        @Volatile var last: WindowList? = null
        val formats = CopyOnWriteArrayList<ParameterSets>()
        val frames = CopyOnWriteArrayList<Boolean>()
        val settings = LinkedBlockingQueue<HostSettingsState>()
        val macInfo = LinkedBlockingQueue<Pair<MacInfo, ByteArray>>()
        val clipboard = LinkedBlockingQueue<String>()
        val thumbnails = CopyOnWriteArrayList<Long>()
        val icons = CopyOnWriteArrayList<String>()
        val pointers = CopyOnWriteArrayList<Pair<Double, Double>?>()
        override fun onConnected(list: WindowList) { last = list; lists.add(list) }
        override fun onWindowList(list: WindowList) { last = list; lists.add(list) }
        override fun onVideoFormat(sets: ParameterSets) { formats.add(sets) }
        override fun onFrame(annexB: ByteArray, keyframe: Boolean, timestamp: Double) { frames.add(keyframe) }
        override fun onHostSettings(state: HostSettingsState) { settings.add(state) }
        override fun onMacInfo(info: MacInfo, fingerprint: ByteArray) { macInfo.add(info to fingerprint) }
        override fun onClipboard(text: String) { clipboard.add(text) }
        override fun onThumbnail(windowID: Long, jpeg: ByteArray) { thumbnails.add(windowID) }
        override fun onAppIcon(bundleID: String, png: ByteArray) { icons.add(bundleID) }
        override fun onMacPointer(position: Pair<Double, Double>?) { pointers.add(position) }
    }

    private fun <T> LinkedBlockingQueue<T>.next(s: Long = 10): T = assertNotNull(poll(s, TimeUnit.SECONDS), "timed out")
    private fun waitFor(what: String, seconds: Double = 10.0, f: () -> Boolean) {
        val end = System.nanoTime() + (seconds * 1e9).toLong()
        while (System.nanoTime() < end) { if (f()) return; Thread.sleep(20) }
        fail("timed out waiting for $what")
    }

    private fun host(p: FakePlatform, store: KeyValueStore = KeyValueStore.Memory(), log: MutableList<String> = CopyOnWriteArrayList()) =
        StreamHost(p, store, "0.6.0", persistent = true, port = 0, bind = InetAddress.getLoopbackAddress(), advertise = false,
            log = { log.add(it); println(it) }).also { it.start() }

    private fun found(h: StreamHost) = FoundService(h.platform.hostName, "sill-test.local.", h.boundPort, listOf(InetAddress.getLoopbackAddress()),
        mapOf("r" to h.hostIdentity.tag(), "p" to if (h.trust.requirePairing) "1" else "0"), "lo")

    @Test
    fun pairStreamTypeAndLeave() {
        val p = FakePlatform()
        val log = CopyOnWriteArrayList<String>()
        host(p, log = log).use { h ->
            val ui = UI(); val stream = Stream()
            val store = KeyValueStore.Memory()
            val c = SillClient(info, store, IdentityStore.InKeyValue(store), ui, stream)
            c.setFound(listOf(found(h)))
            val row = ui.rows.single()
            assertEquals("Not paired", row.word)
            assertIs<HomeDial.Decision.Ask>(row.decision)

            // The ask opens the host's window; the code pairs; the session starts pinned to the door's key.
            assertEquals("Not Advertised", HostStatusText.present(h.status()).header)
            c.connect(row)
            val prompt = ui.prompts.next()
            val code = assertNotNull(h.pairing.current).code
            // The ask shows as "‹device› Wants to Pair" with its code showing, and the window waits.
            val asking = h.status().pairingRequest
            assertNotNull(asking)
            assertEquals(PairingCopy.Phase.Waiting(5, null), h.pairingPhase())
            assertNotNull(h.pairingAskedBy())
            // The ask is logged, the code never (Sill.app's log holds no code either).
            assertTrue(log.any { "asks to pair" in it })
            assertTrue(log.none { code in it.filter(Char::isDigit) }, "the pairing code is in the log")
            c.submitCode(prompt, code)
            val session = ui.started.next(30)
            assertIs<PairingCopy.Phase.Paired>(h.pairingPhase())
            assertNull(h.status().pairingRequest)
            assertEquals(1, h.trust.devices.size)
            assertEquals("code", h.trust.devices.single().method)
            assertEquals(h.hostIdentity.macID, c.saved.all.single().macID)

            // The catalog in the Mac's order: the window list, kind 16, a signed kind 18, icons, the apps.
            val first = stream.lists.next()
            assertEquals("Test PC", first.macName)
            assertEquals(listOf("notes.txt — Editor", "Terminal"), first.windows.map { it.title })
            assertEquals(1, first.clipboard); assertEquals(1, first.gestures)
            val settings = stream.settings.next()
            assertEquals(false, settings.virtualDisplayAvailable)
            val (mi, fp) = stream.macInfo.next()
            assertEquals(h.hostIdentity.macID, mi.macID)
            assertTrue(fp.contentEquals(h.hostIdentity.identity.fingerprint))
            waitFor("icons") { stream.icons.containsAll(listOf("editor", "terminal")) }
            waitFor("thumbnails") { stream.thumbnails.containsAll(listOf(0x1200001L, 0x1400002L)) }

            // The client asks for the Desktop by itself; then a window. Each stream starts at a keyframe.
            waitFor("the desktop") { p.started.any { it.first == Source.Desktop } }
            session.setViewport(Viewport(1000.0, 700.0, null, fps = 60))
            session.select(StreamSource.Window(0x1400002))
            waitFor("the window's stream") { p.started.any { (it.first as? Source.Window)?.window?.id == 0x1400002L } }
            assertTrue("raise ${0x1400002L}" in p.commands)
            waitFor("frames") { stream.frames.size > 10 }
            assertTrue(stream.formats.isNotEmpty())
            assertTrue(stream.frames.first(), "the first frame a device gets is a keyframe")
            waitFor("the list naming the window") { stream.last?.active == StreamSource.Window(0x1400002) }
            // The card: one device, streaming the window, its size and rate.
            waitFor("the card's stream") { h.status().stream?.kind == HostStatusSnapshot.Stream.Kind.WINDOW }
            val card = HostStatusText.present(h.status())
            assertEquals("Not Advertised", card.header, "Bonjour off comes first, as Sill.app's Test Pattern Mode")
            assertEquals(1, card.devices.size)
            assertEquals(HostGlyph.STREAMING, card.glyph)
            assertEquals(RowSymbol.WINDOW, card.source?.symbol)
            assertTrue(card.source!!.detail!!.matches(Regex("""\d+×\d+ · (\d+ of 60 fps|60 fps, still) · 15 Mbps""")), card.source!!.detail)

            // Input: a click at the frame's middle lands in the window's middle; ⌘C is Ctrl+C; text is typed.
            p.events.clear()
            session.input(InputEvent.Pointer(PointerAction.LEFT_DOWN, 0.5, 0.5))
            session.input(InputEvent.Pointer(PointerAction.LEFT_UP, 0.5, 0.5))
            session.input(InputEvent.Key(0x06, true, Modifiers.COMMAND))
            session.input(InputEvent.Key(0x06, false, Modifiers.COMMAND))
            session.input(InputEvent.Text("hé\n"))
            waitFor("input") { p.events.any { it.startsWith("key 0x28 up") } }
            val ev = p.events.toList()
            assertEquals("move 619,399", ev.first { it.startsWith("move") })
            assertTrue(ev.containsAll(listOf("button 1 down", "button 1 up", "key 0xE0 down", "key 0x06 down", "key 0x06 up", "text hé", "key 0x28 down")), "$ev")
            assertTrue(ev.indexOf("key 0xE0 up") in ev.indexOf("key 0x06 up")..ev.indexOf("text hé"), "Ctrl let go before the text: $ev")

            // Aa: the window sized to the panel at that scale; the stream restarts at its new size.
            val before = p.started.size
            session.setViewport(Viewport(1000.0, 700.0, 1.25, fps = 60))
            waitFor("the resize") { "setBounds ${0x1400002L} 800x560" in p.commands }
            waitFor("a restart") { p.started.size > before }

            // Kind 17: Pro is taken and saved, the stream restarts at its bitrate; 999 fps is refused.
            stream.settings.clear()
            val token = session.changeSettings(HostSettingsChange(bitrate = QualityPreset.PRO.bitrate))
            var answer: HostSettingsState
            do { answer = stream.settings.next() } while (answer.answering != token)
            assertEquals(QualityPreset.PRO.bitrate, answer.settings.bitrate)
            waitFor("a stream at Pro") { p.started.last().second.bitratePer60 == QualityPreset.PRO.bitrate }
            val t2 = session.changeSettings(HostSettingsChange(maxFPS = 999))
            do { answer = stream.settings.next() } while (answer.answering != t2)
            assertEquals(60, answer.settings.maxFPS)

            // The clipboard: subscribed, a copy on the PC goes to the device, the device's text to the PC.
            session.updateShareClipboard(true)
            waitFor("the subscription") { log.any { "shares the clipboard" in it } }
            Thread.sleep(400)
            p.clip = "copied on the PC"
            assertEquals("copied on the PC", stream.clipboard.next())
            assertTrue(session.sendClipboard("pasted from the device"))
            waitFor("the PC's clipboard") { p.clip == "pasted from the device" }
            Thread.sleep(600)
            assertTrue(stream.clipboard.isEmpty(), "the device's own text is not sent back")

            // Settings › General's switch off: the window list stops offering the clipboard and nothing more is sent.
            h.setShareClipboard(false)
            waitFor("the list without the clipboard") { stream.last?.clipboard == null }
            p.clip = "copied while sharing is off"
            Thread.sleep(700)
            assertTrue(stream.clipboard.isEmpty(), "nothing is sent while sharing is off")
            h.setShareClipboard(true)
            waitFor("the clipboard offered again") { stream.last?.clipboard == 1 }

            // A gesture: the platform's chord, pressed and let go.
            p.events.clear()
            session.gesture("swipeUp", 3)
            waitFor("the chord") { p.events.contains("key 0x2B up") }
            assertEquals(listOf("key 0xE3 down", "key 0x2B down", "key 0x2B up", "key 0xE3 up"), p.events.filter { it.startsWith("key") }.takeLast(4))

            // The PC's own pointer moving: the device is shown it.
            Thread.sleep(400)
            val rect = assertNotNull(p.bounds(0x1400002))
            p.cursor = rect.x + rect.w / 4 to rect.y + rect.h / 2
            Thread.sleep(300)
            p.cursor = rect.x + rect.w / 2 to rect.y + rect.h / 2
            waitFor("the pointer") { stream.pointers.lastOrNull()?.let { kotlin.math.abs(it.first - 0.5) < 0.01 } == true }

            // The streamed window closes: the stream stops and the list says nothing streams (the client
            // asks for the Desktop again by itself only 10 s after its last such request).
            session.windowCommand(0x1400002, "close")
            waitFor("the close") { "close ${0x1400002L}" in p.commands }
            waitFor("nothing streaming") { stream.last?.active == StreamSource.None && stream.last?.windows?.size == 1 }
            session.select(StreamSource.Desktop)
            waitFor("the desktop again") { stream.last?.active == StreamSource.Desktop }

            // Remove on the host: the device hears "removed", and its saved PC is marked.
            h.removeDevice(h.trust.devices.single().fingerprint)
            val out = ui.ended.next()
            assertTrue("removed" in out.text, out.text)
            waitFor("no session") { h.devices.isEmpty() }
            assertTrue(p.events.contains("button 1 up"), "the device's input was let go")
            c.stop()
        }
    }

    @Test
    fun unpairedKeyRefusedAndQuit() {
        val p = FakePlatform()
        val store = KeyValueStore.Memory()
        host(p, store).use { h ->
            // A key the trust list does not hold: refused at the session's ALPN (seen on the first read).
            val stranger = Identity.generate()
            val err = runCatching {
                val c = SillTls.dial(InetSocketAddress(InetAddress.getLoopbackAddress(), h.boundPort), stranger, SillTls.SESSION_ALPN, Trust.Pinned(h.hostIdentity.identity.fingerprint))
                c.input.read()
                c.close()
            }.exceptionOrNull()
            assertTrue(err is DialFailure.KeyRefused || err is java.io.IOException, "$err")

            // Require pairing off: any key gets a session, and hears "quit" when the host stops.
            h.setRequirePairing(false)
            Thread.sleep(100)
            val c = SillTls.dial(InetSocketAddress(InetAddress.getLoopbackAddress(), h.boundPort), stranger, SillTls.SESSION_ALPN, Trust.Pinned(h.hostIdentity.identity.fingerprint))
            val r = MessageReader(c.input)
            assertEquals(Kind.WINDOW_LIST, r.next()!!.kind)
            waitFor("the session") { h.devices.size == 1 }
            // Require pairing on again: an unpaired session hears "pairingRequired".
            h.setRequirePairing(true)
            var m = r.next()
            while (m != null && m.kind != Kind.GOODBYE) m = r.next()
            assertNotNull(m)
            assertTrue(String(m.payload).contains("pairingRequired"))
            c.close()
        }
        // The same store: the same identity and Mac ID at the next launch.
        val again = StreamHost(p, store, "0.6.0", port = 0, bind = InetAddress.getLoopbackAddress(), advertise = false, log = {})
        assertEquals(HostIdentity(store).macID, again.hostIdentity.macID)
    }

    @Test
    fun quitSaysGoodbye() {
        val p = FakePlatform()
        val h = host(p)
        h.setRequirePairing(false)
        val c = SillTls.dial(InetSocketAddress(InetAddress.getLoopbackAddress(), h.boundPort), Identity.generate(), SillTls.SESSION_ALPN, Trust.AnyKey)
        val r = MessageReader(c.input)
        assertEquals(Kind.WINDOW_LIST, r.next()!!.kind)
        waitFor("the session") { h.devices.size == 1 }
        Thread { h.close() }.start()
        var m = r.next()
        while (m != null && m.kind != Kind.GOODBYE) m = r.next()
        assertTrue(String(assertNotNull(m).payload).contains("quit"))
        c.close()
    }

    @Test
    fun inflightRuleDropsDeltasNotKeyframes() {
        // A device that stops reading: deltas beyond two in flight are dropped and a keyframe asked for.
        val out = object : java.io.OutputStream() {
            val gate = Object(); @Volatile var open = false
            override fun write(b: Int) { synchronized(gate) { while (!open) gate.wait() } }
            override fun write(b: ByteArray, off: Int, len: Int) { synchronized(gate) { while (!open) gate.wait() } }
        }
        var asked = 0
        val t = doubleArrayOf(0.0)
        val c = HostClient(out, "test", "fp", { t[0] }, { asked++ }, {})
        val sets = ParameterSets(4, listOf(byteArrayOf(0x40, 1), byteArrayOf(0x42, 1), byteArrayOf(0x44, 1)))
        fun frame(key: Boolean) = me.saffer.sill.core.StreamMessage(Kind.FRAME, 0.0, key, byteArrayOf(0, 0, 0, 1, 2))
        c.sendFrame(frame(false), sets)                     // waiting for a keyframe: withheld
        assertEquals(0, c.inflight)
        c.sendFrame(frame(true), sets)                      // the sets, then the keyframe
        Thread.sleep(50)
        assertEquals(2, c.inflight)
        c.sendFrame(frame(false), sets)
        assertEquals(3, c.inflight)
        c.sendFrame(frame(false), sets)                     // more than two in flight: dropped
        assertEquals(3, c.inflight); assertEquals(1, asked); assertTrue(c.needsKeyframe)
        c.sendFrame(frame(true), sets)                      // keyframes are never dropped
        assertEquals(5, c.inflight)
        t[0] = 9.0
        assertTrue(c.stalled(9.0), "a frame waiting over 4 s, connected over 8 s")
        synchronized(out.gate) { out.open = true; out.gate.notifyAll() }
        waitFor("drained") { c.inflight == 0 }
        assertTrue(!c.stalled(9.0))
        c.close()
    }
}
