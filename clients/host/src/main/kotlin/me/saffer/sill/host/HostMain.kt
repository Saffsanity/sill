package me.saffer.sill.host

import me.saffer.sill.core.Identity
import me.saffer.sill.core.Kind
import me.saffer.sill.core.KeyValueStore
import me.saffer.sill.core.MessageReader
import me.saffer.sill.core.ParameterSets
import me.saffer.sill.core.SillTls
import me.saffer.sill.core.Trust
import java.awt.BorderLayout
import java.io.File
import java.io.PrintStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import javax.swing.JFrame
import javax.swing.JPanel
import javax.swing.JTextField
import javax.swing.SwingUtilities

const val HOST_VERSION = "0.6.0"

private fun isWindows() = System.getProperty("os.name").lowercase().startsWith("windows")

/** This operating system's platform: Windows, or Linux with X11. */
fun platform(log: (String) -> Unit): HostPlatform = if (isWindows()) WindowsPlatform(log) else LinuxPlatform(log)

/** The log: stdout, the window's log, and host.log beside the settings (started afresh past 10 MB). */
class HostLog(dir: File = HostStore.defaultDir()) {
    val file = File(dir, "host.log")
    private val ring = ArrayDeque<String>()
    private val out: PrintStream? = try {
        dir.mkdirs()
        if (file.length() > 10L shl 20) file.renameTo(File(dir, "host.1.log"))
        PrintStream(java.io.FileOutputStream(file, true), true, Charsets.UTF_8)
    } catch (_: Exception) { null }
    @Volatile var sink: (String) -> Unit = {}

    fun line(s: String) {
        val stamped = "${java.time.LocalTime.now().withNano(0)} $s"
        println(s)
        out?.println(stamped)
        synchronized(ring) { ring.addLast(stamped); while (ring.size > RECENT) ring.removeFirst() }
        sink(stamped)
    }

    /** The last lines, for the Log window (Sill.app's HostLog keeps 5,000). */
    fun recent(): List<String> = synchronized(ring) { ring.toList() }

    companion object { const val RECENT = 5000 }
}

/**
 * `SillHost --self-test`: what a packaged host needs, without a device: FFmpeg's GPL build with an
 * HEVC encoder (a GPU's or x265) encoding a test picture to parameter sets and a keyframe, the
 * platform (windows, the screen, the pointer), the store, the door's TLS with a client of Sill's own,
 * and a capture of the screen (reported, not required: a CI runner may have no desktop to capture).
 */
fun selfTest(): Int {
    fun ok(s: String) = println("ok    $s")
    try {
        // The encoder, on a test pattern (FFmpeg's lavfi source).
        val sets = arrayOfNulls<ParameterSets>(1); val frames = AtomicInteger(); val keys = AtomicInteger(); val done = CountDownLatch(1)
        val sink = object : VideoSink {
            override fun parameterSets(sets0: ParameterSets) { sets[0] = sets0 }
            override fun frame(au: ByteArray, keyframe: Boolean, timestamp: Double) { frames.incrementAndGet(); if (keyframe) keys.incrementAndGet(); if (frames.get() >= 10) done.countDown() }
            override fun failed(reason: String) { println("      encoder: $reason"); done.countDown() }
        }
        val v = FfmpegVideo.open(CaptureSpec("lavfi", "testsrc2=size=640x360:rate=30", emptyMap(), "a test pattern"), StreamParams(30, 4_000_000, 2.0), null, sink) { println("      $it") }
        done.await(15, TimeUnit.SECONDS); v.close()
        check(sets[0] != null && sets[0]!!.sets.size == 3) { "no HEVC parameter sets" }
        check(frames.get() >= 10 && keys.get() >= 1) { "${frames.get()} frames, ${keys.get()} keyframes" }
        ok("HEVC encoder ${v.encoderName}: ${frames.get()} frames, the first a keyframe")

        // The platform.
        val p = platform { println("      $it") }
        val screen = p.desktopBounds()
        check(screen.w > 0 && screen.h > 0) { "no screen" }
        val ws = p.windows()
        ok("${p.osName} \"${p.hostName}\": screen ${screen.w}×${screen.h}, ${ws.size} windows, pointer at ${p.cursorPosition()}, ${p.apps().size} apps")
        for (w in ws.take(5)) println("      window ${w.id}: ${w.app} — ${w.title} ${w.bounds}")

        // A capture of the screen: reported only.
        try {
            val cf = AtomicInteger(); val cd = CountDownLatch(1)
            val cv = p.startVideo(Source.Desktop, StreamParams(30, 8_000_000, 1.0), object : VideoSink {
                override fun parameterSets(sets: ParameterSets) {}
                override fun frame(au: ByteArray, keyframe: Boolean, timestamp: Double) { if (cf.incrementAndGet() >= 5) cd.countDown() }
                override fun failed(reason: String) { cd.countDown() }
            })
            cd.await(10, TimeUnit.SECONDS); cv.close()
            println((if (cf.get() >= 5) "ok    " else "note  ") + "Screen capture: ${cf.get()} frames at ${cv.width}×${cv.height}")
        } catch (e: Exception) { println("note  Screen capture: ${e.message}") }
        // The store and the identity, kept across launches.
        val dir = java.nio.file.Files.createTempDirectory("sill-host-selftest").toFile()
        val id1 = HostIdentity(HostStore(File(dir, "host.json"))).macID
        check(HostIdentity(HostStore(File(dir, "host.json"))).macID == id1) { "the identity did not persist" }
        dir.deleteRecursively()
        ok("Store: Mac ID $id1 kept across launches")

        // The door: a session over TLS 1.3 with a key of Sill's own (Require pairing off here).
        val host = StreamHost(p, KeyValueStore.Memory(), HOST_VERSION, persistent = false, port = 0, bind = InetAddress.getLoopbackAddress(), advertise = false, log = { println("      $it") })
        host.start(); host.setRequirePairing(false); Thread.sleep(100)
        val c = SillTls.dial(InetSocketAddress(InetAddress.getLoopbackAddress(), host.boundPort), Identity.generate(), SillTls.SESSION_ALPN, Trust.Pinned(host.hostIdentity.identity.fingerprint))
        val first = MessageReader(c.input).next()
        check(first?.kind == Kind.WINDOW_LIST) { "no window list from the door" }
        c.close(); host.close()
        ok("Door: TLS 1.3 session, window list first")

        println("Self-test passed on ${System.getProperty("os.name")} ${System.getProperty("os.arch")}, Java ${System.getProperty("java.version")}")
        return 0
    } catch (e: Throwable) {
        System.err.println("Self-test failed: $e")
        e.printStackTrace()
        return 1
    }
}

/**
 * `SillHost --input-probe`: the platform's input path into a window of its own. A text field is
 * focused, clicked, then typed into as a device would: Unicode text, keys by position (a, ⇧B),
 * Backspace; the field must read back exactly what was sent. Exits 0 when it does. Touches no
 * other window (the pointer is put back where it was).
 */
fun inputProbe(): Int {
    val p = platform { println("      $it") }
    val field = JTextField(30)
    val frame = JFrame("Sill input probe")
    SwingUtilities.invokeAndWait {
        frame.contentPane = JPanel(BorderLayout()).apply { add(field) }
        frame.setSize(420, 120); frame.setLocation(200, 200); frame.isVisible = true
    }
    Thread.sleep(1500)
    val before = p.cursorPosition()
    val loc = field.locationOnScreen
    val win = p.windows().firstOrNull { it.title == "Sill input probe" }
    println("      probe window: $win; field at $loc")
    win?.let { p.raise(it.id) }
    Thread.sleep(500)
    p.input.move(loc.x + 20, loc.y + field.height / 2)
    p.input.button(1, true); p.input.button(1, false)
    Thread.sleep(300)
    val moved = p.cursorPosition()
    p.input.text("Sill é✓ ")
    p.input.key(0x04, true); p.input.key(0x04, false)                     // a
    p.input.key(0xE1, true); p.input.key(0x05, true); p.input.key(0x05, false); p.input.key(0xE1, false)   // ⇧B
    p.input.key(0x1B, true); p.input.key(0x1B, false)                     // x
    p.input.key(0x2A, true); p.input.key(0x2A, false)                     // Backspace
    Thread.sleep(1000)
    val got = arrayOfNulls<String>(1)
    SwingUtilities.invokeAndWait { got[0] = field.text; frame.dispose() }
    before?.let { p.input.move(it.first, it.second) }
    val want = "Sill é✓ aB"
    println("      pointer moved to $moved (asked ${loc.x + 20},${loc.y + field.height / 2})")
    println("      typed \"${got[0]}\", wanted \"$want\"")
    return if (got[0] == want && moved == (loc.x + 20 to loc.y + field.height / 2)) { println("Input probe passed"); 0 } else { println("Input probe failed"); 1 }
}

fun main(args: Array<String>) {
    if ("--self-test" in args) kotlin.system.exitProcess(selfTest())
    if ("--input-probe" in args) kotlin.system.exitProcess(inputProbe())
    val headless = "--headless" in args || java.awt.GraphicsEnvironment.isHeadless()
    val port = args.indexOf("--port").takeIf { it >= 0 }?.let { args.getOrNull(it + 1)?.toIntOrNull() } ?: StreamHost.DEFAULT_PORT
    val log = HostLog()
    val p = try { platform(log::line) } catch (e: Throwable) {
        System.err.println("Sill Host cannot start: ${e.message}")
        if (!isWindows()) System.err.println("It needs an X11 session (Xorg, or XWayland with DISPLAY set) and libX11 and libXtst.")
        kotlin.system.exitProcess(1)
    }
    val host = StreamHost(p, HostStore(), HOST_VERSION, persistent = true, port = port, log = log::line)
    try { host.start() } catch (e: java.net.BindException) {
        System.err.println("Sill Host cannot listen on port $port (${e.message}). Is another Sill Host running? --port chooses another.")
        kotlin.system.exitProcess(1)
    }
    Runtime.getRuntime().addShutdownHook(Thread { host.close() })
    if (headless) {
        // Headless: the code and the link on stdout whenever a window opens.
        var shown: String? = null
        host.pairing.onChange = { w ->
            if (w != null && w.code != shown) {
                shown = w.code
                log.line("Pairing code: ${w.code.chunked(4).joinToString(" ")} (open for ${PairingWindow.TTL.toInt() / 60} minutes)")
                log.line("Pairing link: ${host.pairingLink(w)}")
            } else if (w == null) shown = null
        }
        if ("--pair" in args) host.openPairing()
        log.line("Running headless; Ctrl-C quits.")
        Thread.currentThread().join()
    } else {
        SwingUtilities.invokeLater {
            me.saffer.sill.swingui.SillSwing.install()
            val model = me.saffer.sill.host.ui.LiveModel(host, log, HOST_VERSION) { Thread { host.close(); kotlin.system.exitProcess(0) }.start() }
            val ui = me.saffer.sill.host.ui.HostUi(model)
            model.onShowLog = { ui.log.show() }
            log.sink = { line -> SwingUtilities.invokeLater { ui.log.append(line) } }
            host.onStatusChange = { SwingUtilities.invokeLater { ui.refresh() } }
            ui.start()
            if ("--pair" in args) ui.act(me.saffer.sill.host.MenuAction.ShowPairing)
        }
    }
}

