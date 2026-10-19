package me.saffer.sill.host

import me.saffer.sill.core.AppInfo
import me.saffer.sill.core.HidKeys
import java.io.File
import java.lang.foreign.Arena
import java.lang.foreign.MemorySegment
import java.lang.foreign.ValueLayout
import me.saffer.sill.host.NativeLibrary.Companion.ADDR
import me.saffer.sill.host.NativeLibrary.Companion.BYTE
import me.saffer.sill.host.NativeLibrary.Companion.INT
import me.saffer.sill.host.NativeLibrary.Companion.LONG

/**
 * Linux with X11 (an Xorg session, or XWayland's X11 windows): the windows from the window
 * manager's EWMH lists, moved, raised and closed through EWMH messages; input through XTest, keys
 * by their physical position (evdev's codes, X's minus 8) and text by Unicode keysyms on a spare
 * keycode, so any layout types what the device sent; capture with FFmpeg's x11grab of the window's
 * rectangle; the apps from the desktop entries. A Wayland session's own windows are out of X11's
 * reach: the host says so and streams only what X11 sees.
 */
class LinuxPlatform(private val log: (String) -> Unit = {}) : HostPlatform, AutoCloseable {
    private val x11 = NativeLibrary("libX11.so.6")
    private val xtst = NativeLibrary("libXtst.so.6")
    private val displayName = System.getenv("DISPLAY") ?: throw IllegalStateException("no X11 display (DISPLAY is not set)")

    private val XInitThreads = x11.need("XInitThreads", INT)
    private val XOpenDisplay = x11.need("XOpenDisplay", ADDR, ADDR)
    private val XCloseDisplay = x11.need("XCloseDisplay", INT, ADDR)
    private val XDefaultScreen = x11.need("XDefaultScreen", INT, ADDR)
    private val XRootWindow = x11.need("XRootWindow", LONG, ADDR, INT)
    private val XDisplayWidth = x11.need("XDisplayWidth", INT, ADDR, INT)
    private val XDisplayHeight = x11.need("XDisplayHeight", INT, ADDR, INT)
    private val XInternAtom = x11.need("XInternAtom", LONG, ADDR, ADDR, INT)
    private val XGetWindowProperty = x11.need("XGetWindowProperty", INT, ADDR, LONG, LONG, LONG, LONG, INT, LONG, ADDR, ADDR, ADDR, ADDR, ADDR)
    private val XFree = x11.need("XFree", INT, ADDR)
    private val XGetGeometry = x11.need("XGetGeometry", INT, ADDR, LONG, ADDR, ADDR, ADDR, ADDR, ADDR, ADDR, ADDR)
    private val XTranslateCoordinates = x11.need("XTranslateCoordinates", INT, ADDR, LONG, LONG, INT, INT, ADDR, ADDR, ADDR)
    private val XSendEvent = x11.need("XSendEvent", INT, ADDR, LONG, INT, LONG, ADDR)
    private val XRaiseWindow = x11.need("XRaiseWindow", INT, ADDR, LONG)
    private val XSetInputFocus = x11.need("XSetInputFocus", INT, ADDR, LONG, INT, LONG)
    private val XIconifyWindow = x11.need("XIconifyWindow", INT, ADDR, LONG, INT)
    private val XResizeWindow = x11.need("XResizeWindow", INT, ADDR, LONG, INT, INT)
    private val XQueryPointer = x11.need("XQueryPointer", INT, ADDR, LONG, ADDR, ADDR, ADDR, ADDR, ADDR, ADDR, ADDR)
    private val XSync = x11.need("XSync", INT, ADDR, INT)
    private val XFlush = x11.need("XFlush", INT, ADDR)
    private val XDisplayKeycodes = x11.need("XDisplayKeycodes", INT, ADDR, ADDR, ADDR)
    private val XGetKeyboardMapping = x11.need("XGetKeyboardMapping", ADDR, ADDR, BYTE, INT, ADDR)
    private val XChangeKeyboardMapping = x11.need("XChangeKeyboardMapping", INT, ADDR, INT, INT, ADDR, INT)
    private val XSetErrorHandler = x11.need("XSetErrorHandler", ADDR, ADDR)
    private val XTestFakeKeyEvent = xtst.need("XTestFakeKeyEvent", INT, ADDR, INT, INT, LONG)
    private val XTestFakeButtonEvent = xtst.need("XTestFakeButtonEvent", INT, ADDR, INT, INT, LONG)
    private val XTestFakeMotionEvent = xtst.need("XTestFakeMotionEvent", INT, ADDR, INT, INT, INT, LONG)

    private val dpy: MemorySegment
    private val screen: Int
    private val root: Long
    private val atoms = HashMap<String, Long>()
    private val spareKeycode: Int
    private val pid = ProcessHandle.current().pid()

    init {
        XInitThreads.int()
        dpy = Arena.ofConfined().use { a -> XOpenDisplay.ptr(a.allocateFrom(displayName)) }
        if (dpy.isNull()) throw IllegalStateException("could not open the X11 display $displayName")
        // A window that vanishes between two calls makes Xlib report BadWindow; the default handler exits the process.
        XSetErrorHandler.ptr(ignoreErrors())
        screen = XDefaultScreen.int(dpy)
        root = XRootWindow.long(dpy, screen)
        spareKeycode = findSpareKeycode()
        if (System.getenv("WAYLAND_DISPLAY") != null) log("Linux: a Wayland session; only its X11 (XWayland) windows can be listed, streamed and controlled.")
    }

    override val osName = "Linux"
    override val hostName: String = (System.getenv("HOSTNAME") ?: runCatching { File("/etc/hostname").readText().trim() }.getOrNull())
        ?.ifEmpty { null } ?: runCatching { java.net.InetAddress.getLocalHost().hostName }.getOrDefault("Linux PC")

    private fun atom(name: String): Long = synchronized(atoms) {
        atoms.getOrPut(name) { Arena.ofConfined().use { a -> XInternAtom.long(dpy, a.allocateFrom(name), 0) } }
    }

    // MARK: Properties

    private class Prop(val type: Long, val format: Int, val items: Long, val data: ByteArray)

    @Synchronized private fun property(w: Long, name: String, maxLongs: Long = 1 shl 20): Prop? = Arena.ofConfined().use { a ->
        val type = a.allocate(LONG); val format = a.allocate(INT); val n = a.allocate(LONG); val after = a.allocate(LONG); val data = a.allocate(ADDR)
        val r = XGetWindowProperty.int(dpy, w, atom(name), 0L, maxLongs, 0, 0L /* AnyPropertyType */, type, format, n, after, data)
        val p = data.get(ADDR, 0)
        if (r != 0 || p.isNull()) return null
        val fmt = format.get(INT, 0); val items = n.get(LONG, 0)
        // Format 32 comes as C longs (8 bytes each here), 16 as shorts, 8 as bytes.
        val size = items * when (fmt) { 32 -> 8; 16 -> 2; else -> 1 }
        val bytes = p.reinterpret(size).toArray(ValueLayout.JAVA_BYTE)
        XFree.int(p)
        Prop(type.get(LONG, 0), fmt, items, bytes)
    }

    private fun longs(p: Prop?): LongArray {
        if (p == null || p.format != 32) return LongArray(0)
        val b = java.nio.ByteBuffer.wrap(p.data).order(java.nio.ByteOrder.nativeOrder())
        return LongArray(p.items.toInt()) { b.long }
    }

    private fun string(w: Long, name: String): String? = property(w, name)?.takeIf { it.format == 8 && it.data.isNotEmpty() }?.data?.toString(Charsets.UTF_8)?.trimEnd('\u0000')

    // MARK: Windows

    override fun windows(): List<PlatformWindow> {
        val stacking = longs(property(root, "_NET_CLIENT_LIST_STACKING")).let { if (it.isEmpty()) longs(property(root, "_NET_CLIENT_LIST")) else it }
        val skipTypes = setOf("_NET_WM_WINDOW_TYPE_DOCK", "_NET_WM_WINDOW_TYPE_DESKTOP", "_NET_WM_WINDOW_TYPE_TOOLBAR", "_NET_WM_WINDOW_TYPE_MENU",
            "_NET_WM_WINDOW_TYPE_SPLASH", "_NET_WM_WINDOW_TYPE_NOTIFICATION").map(::atom).toSet()
        val skipTaskbar = atom("_NET_WM_STATE_SKIP_TASKBAR"); val hidden = atom("_NET_WM_STATE_HIDDEN")
        return stacking.reversed().mapNotNull { w ->
            if (longs(property(w, "_NET_WM_WINDOW_TYPE")).any { it in skipTypes }) return@mapNotNull null
            val state = longs(property(w, "_NET_WM_STATE"))
            if (skipTaskbar in state) return@mapNotNull null
            if (longs(property(w, "_NET_WM_PID")).firstOrNull() == pid) return@mapNotNull null
            val b = bounds(w) ?: return@mapNotNull null
            val title = string(w, "_NET_WM_NAME") ?: string(w, "WM_NAME") ?: ""
            val cls = property(w, "WM_CLASS")?.data?.toString(Charsets.UTF_8)?.split('\u0000')?.filter { it.isNotEmpty() }.orEmpty()
            val appClass = cls.getOrNull(1) ?: cls.getOrNull(0) ?: "app"
            PlatformWindow(w, title.ifEmpty { appClass }, appName(appClass), appClass, b, minimized = hidden in state)
        }
    }

    override fun desktopBounds() = synchronized(this) { Rect(0, 0, XDisplayWidth.int(dpy, screen), XDisplayHeight.int(dpy, screen)) }

    @Synchronized override fun bounds(id: Long): Rect? = Arena.ofConfined().use { a ->
        val r = a.allocate(LONG); val x = a.allocate(INT); val y = a.allocate(INT); val w = a.allocate(INT); val h = a.allocate(INT); val bw = a.allocate(INT); val d = a.allocate(INT)
        if (XGetGeometry.int(dpy, id, r, x, y, w, h, bw, d) == 0) return null
        val rx = a.allocate(INT); val ry = a.allocate(INT); val child = a.allocate(LONG)
        if (XTranslateCoordinates.int(dpy, id, root, 0, 0, rx, ry, child) == 0) return null
        Rect(rx.get(INT, 0), ry.get(INT, 0), w.get(INT, 0), h.get(INT, 0))
    }

    private val hasWindowManager: Boolean get() = longs(property(root, "_NET_SUPPORTING_WM_CHECK")).isNotEmpty()

    /** An EWMH client message to the root window (the window manager acts on it). */
    @Synchronized private fun message(w: Long, type: String, vararg data: Long): Unit = Arena.ofConfined().use { a ->
        val e = a.allocate(192)
        e.set(INT, 0, 33)                                  // ClientMessage
        e.set(INT, 16, 1)                                  // send_event
        e.set(ADDR, 24, dpy)
        e.set(LONG, 32, w)
        e.set(LONG, 40, atom(type))
        e.set(INT, 48, 32)                                 // format
        for ((i, v) in data.withIndex()) e.set(LONG, 56L + 8 * i, v)
        XSendEvent.int(dpy, root, 0, (1L shl 20) or (1L shl 19), e)
        XFlush.int(dpy)
        Unit
    }

    override fun raise(id: Long) {
        if (hasWindowManager) message(id, "_NET_ACTIVE_WINDOW", 2, 0, 0)
        else synchronized(this) { XRaiseWindow.int(dpy, id); XSetInputFocus.int(dpy, id, 2, 0L); XFlush.int(dpy) }
    }

    override fun close(id: Long) = message(id, "_NET_CLOSE_WINDOW", 0, 2)
    override fun minimize(id: Long) { synchronized(this) { XIconifyWindow.int(dpy, id, screen); XFlush.int(dpy) } }
    override fun toggleFullScreen(id: Long) = message(id, "_NET_WM_STATE", 2, atom("_NET_WM_STATE_FULLSCREEN"), 0, 2)

    override fun setBounds(id: Long, r: Rect): Rect? {
        synchronized(this) { XResizeWindow.int(dpy, id, r.w.coerceAtLeast(64), r.h.coerceAtLeast(64)); XSync.int(dpy, 0) }
        // The window manager answers a moment later; read back what it took.
        var last = bounds(id)
        repeat(15) {
            Thread.sleep(20)
            val b = bounds(id) ?: return null
            if (b.w == r.w && b.h == r.h) return b
            last = b
        }
        return last
    }

    override fun foregroundWindow(): Long? = longs(property(root, "_NET_ACTIVE_WINDOW")).firstOrNull()?.takeIf { it != 0L }

    @Synchronized override fun cursorPosition(): Pair<Int, Int>? = Arena.ofConfined().use { a ->
        val r = a.allocate(LONG); val c = a.allocate(LONG); val x = a.allocate(INT); val y = a.allocate(INT); val wx = a.allocate(INT); val wy = a.allocate(INT); val m = a.allocate(INT)
        if (XQueryPointer.int(dpy, root, r, c, x, y, wx, wy, m) == 0) null else x.get(INT, 0) to y.get(INT, 0)
    }

    override val captureFollowsWindow = false

    // MARK: Capture

    override fun startVideo(source: Source, params: StreamParams, sink: VideoSink): EncodedVideo {
        val screenRect = desktopBounds()
        val r = when (source) { Source.Desktop -> screenRect; is Source.Window -> source.window.bounds }
        // x11grab takes a rectangle on the screen: the window's, kept on the screen, at even sizes.
        val (x, y, w, h) = CaptureRect.clip(r, screenRect)
        val spec = CaptureSpec("x11grab", "$displayName+$x,$y", mapOf("video_size" to "${w}x$h", "framerate" to params.fps.toString(), "draw_mouse" to "0"),
            if (source is Source.Window) "\"${source.window.title}\" at $x,$y" else "the screen")
        return FfmpegVideo.open(spec, params, null, sink, log)
    }

    override fun thumbnail(window: PlatformWindow, maxWidth: Int): ByteArray? = if (window.minimized) null else Thumbnails.ofScreen(window.bounds, desktopBounds(), maxWidth)

    // MARK: Input

    override val input: InputSink = object : InputSink {
        private var wheelX = 0.0
        private var wheelY = 0.0

        override fun move(x: Int, y: Int) { synchronized(this@LinuxPlatform) { XTestFakeMotionEvent.int(dpy, -1, x, y, 0L); XFlush.int(dpy) } }

        override fun button(button: Int, down: Boolean) {
            synchronized(this@LinuxPlatform) { XTestFakeButtonEvent.int(dpy, if (button == 3) 3 else 1, if (down) 1 else 0, 0L); XFlush.int(dpy) }
        }

        override fun wheel(dx: Double, dy: Double) {
            wheelX += dx; wheelY += dy
            val ny = wheelY.toInt(); val nx = wheelX.toInt()
            wheelY -= ny; wheelX -= nx
            synchronized(this@LinuxPlatform) {
                // Buttons 4 and 5 scroll up and down, 6 and 7 left and right.
                repeat(kotlin.math.abs(ny)) { click(if (ny > 0) 4 else 5) }
                repeat(kotlin.math.abs(nx)) { click(if (nx > 0) 7 else 6) }
                XFlush.int(dpy)
            }
        }

        private fun click(b: Int) { XTestFakeButtonEvent.int(dpy, b, 1, 0L); XTestFakeButtonEvent.int(dpy, b, 0, 0L) }

        override fun key(usage: Int, down: Boolean) {
            val code = EVDEV[usage] ?: return
            synchronized(this@LinuxPlatform) { XTestFakeKeyEvent.int(dpy, code + 8, if (down) 1 else 0, 0L); XFlush.int(dpy) }
        }

        override fun text(s: String) = typeUnicode(s)
    }

    /** The keyboard's map now: each keysym's first keycode and level (0 plain, 1 with Shift), and a keycode with none. */
    @Synchronized private fun keymap(): Pair<Map<Long, Pair<Int, Int>>, Int> = Arena.ofConfined().use { a ->
        val min = a.allocate(INT); val max = a.allocate(INT)
        XDisplayKeycodes.int(dpy, min, max)
        val lo = min.get(INT, 0); val hi = max.get(INT, 0)
        val per = a.allocate(INT)
        val map = XGetKeyboardMapping.ptr(dpy, lo.toByte(), hi - lo + 1, per)
        val n = per.get(INT, 0)
        val syms = map.reinterpret(8L * n * (hi - lo + 1))
        val out = HashMap<Long, Pair<Int, Int>>()
        var spare = -1
        for (k in lo..hi) {
            val row = (0 until n).map { syms.getAtIndex(LONG, ((k - lo) * n + it).toLong()) }
            if (row.all { it == 0L }) { if (spare < 0 || k > spare) spare = k; continue }
            for (level in 0 until minOf(2, n)) { val ks = row[level]; if (ks != 0L && ks !in out) out[ks] = k to level }
        }
        XFree.int(map)
        out to (if (spare >= 0) spare else hi)
    }

    private fun findSpareKeycode() = keymap().second

    /**
     * Text, whatever the layout: a character the keyboard has is its key (with Shift where it sits
     * there); any other is its Unicode keysym on the spare keycode, which an app reads only after it
     * has seen the new mapping, so each remapped key waits a little before the next remap.
     */
    @Synchronized private fun typeUnicode(s: String) = Arena.ofConfined().use { a ->
        val (map, _) = keymap()
        val syms = a.allocate(LONG, 2)
        var remapped = false
        val shift = EVDEV.getValue(HidKeys.LEFT_SHIFT) + 8
        var i = 0
        while (i < s.length) {
            val cp = s.codePointAt(i); i += Character.charCount(cp)
            val ks = if (cp in 0x20..0x7E || cp in 0xA0..0xFF) cp.toLong() else 0x01000000L or cp.toLong()
            val known = map[ks]
            if (known != null) {
                val (code, level) = known
                if (level == 1) XTestFakeKeyEvent.int(dpy, shift, 1, 0L)
                XTestFakeKeyEvent.int(dpy, code, 1, 0L); XTestFakeKeyEvent.int(dpy, code, 0, 0L)
                if (level == 1) XTestFakeKeyEvent.int(dpy, shift, 0, 0L)
                XFlush.int(dpy)
                continue
            }
            if (remapped) { XSync.int(dpy, 0); Thread.sleep(REMAP_WAIT_MS) }
            syms.setAtIndex(LONG, 0, ks); syms.setAtIndex(LONG, 1, ks)
            XChangeKeyboardMapping.int(dpy, spareKeycode, 2, syms, 1)
            XSync.int(dpy, 0)
            XTestFakeKeyEvent.int(dpy, spareKeycode, 1, 0L)
            XTestFakeKeyEvent.int(dpy, spareKeycode, 0, 0L)
            XSync.int(dpy, 0)
            remapped = true
        }
        if (remapped) {
            Thread.sleep(REMAP_WAIT_MS)
            syms.setAtIndex(LONG, 0, 0L); syms.setAtIndex(LONG, 1, 0L)
            XChangeKeyboardMapping.int(dpy, spareKeycode, 2, syms, 1)
            XFlush.int(dpy)
        }
    }

    // MARK: Apps, clipboard, gestures

    private val desktop by lazy { DesktopEntries.load() }

    private fun appName(cls: String) = desktop.forClass(cls)?.name ?: cls.replaceFirstChar { it.uppercase() }

    override fun apps(): List<AppInfo> = desktop.entries.map { AppInfo(it.name, it.id) }

    override fun launch(appId: String) {
        val e = desktop.entries.firstOrNull { it.id == appId } ?: desktop.forClass(appId) ?: return log("Launch: no app $appId")
        log("Launching ${e.name}: ${e.command.joinToString(" ")}")
        ProcessBuilder(e.command).redirectErrorStream(true).redirectOutput(ProcessBuilder.Redirect.DISCARD).start()
    }

    override fun appIcon(appId: String): ByteArray? = (desktop.entries.firstOrNull { it.id == appId } ?: desktop.forClass(appId))?.iconPng()

    override fun clipboardText(): String? = Clipboards.text()
    override fun setClipboardText(text: String) = Clipboards.setText(text)

    override fun gestureChord(gesture: String): List<Int>? = when (gesture) {
        "swipeUp", "swipeDown" -> listOf(HidKeys.LEFT_COMMAND)                           // the overview (GNOME, KDE)
        "swipeLeft" -> listOf(HidKeys.LEFT_CONTROL, HidKeys.LEFT_OPTION, HidKeys.RIGHT)  // the next workspace
        "swipeRight" -> listOf(HidKeys.LEFT_CONTROL, HidKeys.LEFT_OPTION, HidKeys.LEFT)
        "pinch" -> listOf(HidKeys.LEFT_COMMAND, 0x04)                                    // Super+A, the apps
        "spread" -> listOf(HidKeys.LEFT_COMMAND, 0x07)                                   // Super+D, the desktop
        else -> null
    }

    override fun close() { synchronized(this) { XCloseDisplay.int(dpy) } }

    companion object {
        private const val REMAP_WAIT_MS = 40L

        /** USB HID usages (keyboard page) as Linux evdev codes; X's keycodes are these plus 8 under XKB's evdev rules. */
        val EVDEV: Map<Int, Int> = buildMap {
            val letters = intArrayOf(30, 48, 46, 32, 18, 33, 34, 35, 23, 36, 37, 38, 50, 49, 24, 25, 16, 19, 31, 20, 22, 47, 17, 45, 21, 44)
            for (i in letters.indices) put(0x04 + i, letters[i])
            for (i in 0 until 9) put(0x1E + i, 2 + i)
            put(0x27, 11)
            putAll(mapOf(0x28 to 28, 0x29 to 1, 0x2A to 14, 0x2B to 15, 0x2C to 57, 0x2D to 12, 0x2E to 13, 0x2F to 26, 0x30 to 27, 0x31 to 43,
                0x32 to 43, 0x33 to 39, 0x34 to 40, 0x35 to 41, 0x36 to 51, 0x37 to 52, 0x38 to 53, 0x39 to 58))
            for (i in 0 until 10) put(0x3A + i, 59 + i)
            putAll(mapOf(0x44 to 87, 0x45 to 88, 0x46 to 99, 0x47 to 70, 0x48 to 119, 0x49 to 110, 0x4A to 102, 0x4B to 104, 0x4C to 111,
                0x4D to 107, 0x4E to 109, 0x4F to 106, 0x50 to 105, 0x51 to 108, 0x52 to 103, 0x53 to 69, 0x54 to 98, 0x55 to 55, 0x56 to 74,
                0x57 to 78, 0x58 to 96, 0x59 to 79, 0x5A to 80, 0x5B to 81, 0x5C to 75, 0x5D to 76, 0x5E to 77, 0x5F to 71, 0x60 to 72,
                0x61 to 73, 0x62 to 82, 0x63 to 83, 0x64 to 86, 0x65 to 127,
                0xE0 to 29, 0xE1 to 42, 0xE2 to 56, 0xE3 to 125, 0xE4 to 97, 0xE5 to 54, 0xE6 to 100, 0xE7 to 126))
        }

        private val handlerArena = Arena.ofShared()
        private fun ignoreErrors(): MemorySegment {
            val mh = java.lang.invoke.MethodHandles.lookup().findStatic(LinuxPlatform::class.java, "onXError",
                java.lang.invoke.MethodType.methodType(Int::class.javaPrimitiveType, MemorySegment::class.java, MemorySegment::class.java))
            return java.lang.foreign.Linker.nativeLinker().upcallStub(mh, java.lang.foreign.FunctionDescriptor.of(INT, ADDR, ADDR), handlerArena)
        }

        @JvmStatic fun onXError(@Suppress("UNUSED_PARAMETER") d: MemorySegment, @Suppress("UNUSED_PARAMETER") e: MemorySegment): Int = 0
    }
}
