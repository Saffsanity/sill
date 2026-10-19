package me.saffer.sill.host

import me.saffer.sill.core.AccessUnit
import me.saffer.sill.core.ClientInfo
import me.saffer.sill.core.ClientListener
import me.saffer.sill.core.FoundService
import me.saffer.sill.core.GoodbyePolicy
import me.saffer.sill.core.HidKeys
import me.saffer.sill.core.IdentityStore
import me.saffer.sill.core.InputEvent
import me.saffer.sill.core.KeyValueStore
import me.saffer.sill.core.MacRow
import me.saffer.sill.core.MdnsBrowser
import me.saffer.sill.core.Modifiers
import me.saffer.sill.core.PairingPrompt
import me.saffer.sill.core.ParameterSets
import me.saffer.sill.core.PointerAction
import me.saffer.sill.core.SessionListener
import me.saffer.sill.core.SillClient
import me.saffer.sill.core.SillSession
import me.saffer.sill.core.StreamSource
import me.saffer.sill.core.Viewport
import me.saffer.sill.core.WindowList
import me.saffer.sill.desktop.HevcDecoder
import org.junit.jupiter.api.Assumptions.assumeTrue
import java.io.File
import java.net.InetAddress
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import kotlin.test.fail

/**
 * The Linux host end to end, on a real X server (Xvfb, under xvfb-run) with a real window manager
 * (openbox) and a terminal (xterm): the Kotlin client pairs with the code, sees the terminal in the
 * list, picks it, decodes the host's x11grab and HEVC to the terminal's own colour, types a command
 * into it as text and as keys (the command's files appear), clicks, resizes the window with Aa and
 * closes it. Skipped without a display, openbox or xterm.
 */
class LinuxHostEndToEndTest {
    private val display = System.getenv("SILL_TEST_DISPLAY")?.ifEmpty { null } ?: System.getenv("DISPLAY")
    private fun which(cmd: String) = System.getenv("PATH").split(':').any { File(it, cmd).canExecute() }

    private fun waitFor(what: String, seconds: Double = 15.0, f: () -> Boolean) {
        val end = System.nanoTime() + (seconds * 1e9).toLong()
        while (System.nanoTime() < end) { if (f()) return; Thread.sleep(50) }
        fail("timed out waiting for $what")
    }

    class UI : ClientListener {
        val prompts = LinkedBlockingQueue<PairingPrompt>()
        val started = LinkedBlockingQueue<SillSession>()
        @Volatile var rows: List<MacRow> = emptyList()
        override fun onRows(rows: List<MacRow>) { this.rows = rows }
        override fun onPairingPrompt(prompt: PairingPrompt) { prompts.add(prompt) }
        override fun onSessionStarted(session: SillSession, mac: String) { started.add(session) }
        override fun onSessionEnded(outcome: GoodbyePolicy.Outcome) {}
    }

    class Stream : SessionListener {
        @Volatile var list: WindowList? = null
        val decoder = HevcDecoder(preferHardware = false)
        @Volatile var picture: HevcDecoder.Picture? = null
        @Volatile var pictures = 0
        val thumbnails = CopyOnWriteArrayList<Long>()
        override fun onConnected(list: WindowList) { this.list = list }
        override fun onWindowList(list: WindowList) { this.list = list }
        override fun onThumbnail(windowID: Long, jpeg: ByteArray) { thumbnails.add(windowID) }
        override fun onVideoFormat(sets: ParameterSets) { synchronized(decoder) { decoder.configure(sets) } }
        override fun onFrame(annexB: ByteArray, keyframe: Boolean, timestamp: Double) {
            synchronized(decoder) { decoder.decode(annexB)?.let { picture = it; pictures++ } }
        }
    }

    @Test
    fun pairPickDecodeTypeClickResizeClose() {
        assumeTrue(display != null && which("openbox") && which("xterm"), "needs a display (xvfb-run), openbox and xterm")
        val env = mapOf("DISPLAY" to display!!, "LC_ALL" to "C.UTF-8", "LANG" to "C.UTF-8")
        val dir = java.nio.file.Files.createTempDirectory("sill-e2e").toFile()
        val procs = ArrayList<Process>()
        fun spawn(vararg cmd: String) = ProcessBuilder(*cmd).apply { environment().putAll(env); redirectErrorStream(true); redirectOutput(ProcessBuilder.Redirect.DISCARD) }.start().also { procs.add(it) }
        try {
            val p = LinuxPlatform { println(it) }
            if (p.windows().isEmpty() && !hasWm(p)) { spawn("openbox"); Thread.sleep(800) }
            spawn("xterm", "-u8", "-T", "SillE2E", "-bg", "#3366cc", "-fg", "#3366cc", "-geometry", "80x24+120+90", "-e", "sh", "-c", "cd '${dir.path}' && PS1='' exec sh")
            waitFor("the terminal") { p.windows().any { it.title == "SillE2E" } }
            val term = p.windows().first { it.title == "SillE2E" }
            println("Terminal: $term")

            val log = CopyOnWriteArrayList<String>()
            StreamHost(p, KeyValueStore.Memory(), "0.6.0", persistent = false, port = 0, bind = InetAddress.getLoopbackAddress(), advertise = false,
                log = { log.add(it); println(it) }).use { h ->
                h.start()
                val ui = UI(); val stream = Stream()
                val store = KeyValueStore.Memory()
                val c = SillClient(ClientInfo("0.6.0", "7", "E2E (JVM)", "PC", "JVM", "e2e"), store, IdentityStore.InKeyValue(store), ui, stream)
                c.setFound(listOf(FoundService(p.hostName, "sill-e2e.local.", h.boundPort, listOf(InetAddress.getLoopbackAddress()),
                    mapOf("r" to h.hostIdentity.tag(), "p" to "1"), "lo")))
                c.connect(ui.rows.single())
                val prompt = assertNotNull(ui.prompts.poll(10, TimeUnit.SECONDS))
                c.submitCode(prompt, assertNotNull(h.pairing.current).code)
                val session = assertNotNull(ui.started.poll(30, TimeUnit.SECONDS))

                // The terminal in the list, with its thumbnail; picked, it streams at its own size in its own colour.
                waitFor("the list") { stream.list?.windows?.any { it.title == "SillE2E" } == true }
                val info = stream.list!!.windows.first { it.title == "SillE2E" }
                assertEquals(term.id and 0xFFFFFFFFL, info.id)
                waitFor("its thumbnail") { info.id in stream.thumbnails }
                session.setViewport(Viewport(1000.0, 700.0, null, fps = 30))
                session.select(StreamSource.Window(info.id))
                waitFor("pictures", 20.0) { stream.pictures >= 10 && stream.picture?.width == term.bounds.w and 1.inv() }
                val pic = stream.picture!!
                assertEquals(term.bounds.h and 1.inv(), pic.height)
                val px = pic.pixels[pic.width * (pic.height / 2) + pic.width / 2]
                val (r, g, b) = Triple(px shr 16 and 0xFF, px shr 8 and 0xFF, px and 0xFF)
                assertTrue(abs(r - 0x33) <= 12 && abs(g - 0x66) <= 12 && abs(b - 0xCC) <= 12, "the terminal's colour, got %02x%02x%02x".format(r, g, b))

                // Typing: a command as text (with a character no US key has), then one as keys.
                session.input(InputEvent.Pointer(PointerAction.LEFT_DOWN, 0.5, 0.5))
                session.input(InputEvent.Pointer(PointerAction.LEFT_UP, 0.5, 0.5))
                session.input(InputEvent.Text("echo sill-é-ok > typed.txt\n"))
                try { waitFor("the typed file") { File(dir, "typed.txt").let { it.exists() && it.readText() == "sill-é-ok\n" } } }
                catch (e: AssertionError) { println("In ${dir}: ${dir.listFiles()?.map { "${it.name}=${runCatching { it.readText() }.getOrNull()}" }}"); throw e }
                fun key(u: Int, mods: Long = 0) { session.input(InputEvent.Key(u, true, mods)); session.input(InputEvent.Key(u, false, mods)) }
                // "touch Keys" with ⇧K, by physical keys.
                for (u in listOf(0x17, 0x12, 0x18, 0x06, 0x0B, HidKeys.SPACE)) key(u)
                key(0x0E, Modifiers.SHIFT)
                for (u in listOf(0x08, 0x1C, 0x16)) key(u)
                key(HidKeys.ENTER)
                waitFor("the keys' file") { File(dir, "Keys").exists() }

                // The pointer where the device put it.
                val (cx, cy) = assertNotNull(p.cursorPosition())
                val tb = assertNotNull(p.bounds(term.id))
                assertEquals(tb.x + (0.5 * (tb.w - 1)).toInt(), cx); assertEquals(tb.y + (0.5 * (tb.h - 1)).toInt(), cy)

                // Aa: the window sized to the panel at 1.25×; the stream follows its new size.
                session.setViewport(Viewport(1000.0, 700.0, 1.25, fps = 30))
                waitFor("the resize") { log.any { it.startsWith("Resized") } }
                val resized = assertNotNull(p.bounds(term.id))
                assertTrue(abs(resized.w - 800) < 20 && abs(resized.h - 560) < 30, "xterm sizes in character cells: $resized")
                waitFor("pictures at the new size", 20.0) { stream.picture?.width == resized.w and 1.inv() }

                // The clipboard through AWT on X11.
                p.setClipboardText("sill clipboard")
                assertEquals("sill clipboard", p.clipboardText())

                // Close from the device: the window goes, and the list says nothing streams.
                session.windowCommand(info.id, "close")
                waitFor("the window closed") { p.windows().none { it.title == "SillE2E" } }
                waitFor("nothing streaming") { stream.list?.active == StreamSource.None }
                c.stop()
            }
            p.close()
        } finally {
            procs.forEach { it.destroy() }
            dir.deleteRecursively()
        }
    }

    private fun hasWm(p: LinuxPlatform) = runCatching { p.foregroundWindow() != null || p.windows().isNotEmpty() }.getOrDefault(false)

    @Test
    fun bonjourOnTheNetwork() {
        // The responder on the machine's interfaces and the clients' browser: only where multicast works (not on every CI runner).
        val found = LinkedBlockingQueue<List<FoundService>>()
        val r = MdnsResponder("Sill E2E ${ProcessHandle.current().pid()}", "sill-e2e", 7455, mapOf("r" to "tag", "p" to "1"), serviceType = "_silltest._tcp.local.")
        assumeTrue(r.start(), "no interface takes multicast")
        val b = MdnsBrowser(serviceType = "_silltest._tcp.local.") { found.add(it) }
        try {
            b.start()
            val end = System.nanoTime() + 8_000_000_000L
            var seen: FoundService? = null
            while (System.nanoTime() < end && seen == null) {
                seen = found.poll(500, TimeUnit.MILLISECONDS)?.firstOrNull { it.name.startsWith("Sill E2E") }
            }
            assumeTrue(seen != null, "multicast does not loop back here")
            assertEquals(7455, seen!!.port)
            assertEquals("tag", seen.tag)
        } finally { b.stop(); r.close() }
    }
}
