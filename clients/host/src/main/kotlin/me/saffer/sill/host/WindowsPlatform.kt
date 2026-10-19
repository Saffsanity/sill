package me.saffer.sill.host

import me.saffer.sill.core.AppInfo
import me.saffer.sill.core.HidKeys
import java.io.File
import java.lang.foreign.Arena
import java.lang.foreign.MemorySegment
import java.lang.foreign.ValueLayout
import me.saffer.sill.host.NativeLibrary.Companion.ADDR
import me.saffer.sill.host.NativeLibrary.Companion.INT
import me.saffer.sill.host.NativeLibrary.Companion.LONG
import me.saffer.sill.host.NativeLibrary.Companion.SHORT

/**
 * Windows 10 and 11: the top-level windows in z-order (user32), without tool windows, owned ones
 * and the cloaked (another virtual desktop's, or a suspended app's); input through SendInput, keys
 * by scan code (their physical position, as the device's) and text as Unicode; capture with
 * FFmpeg's gdigrab of the window's rectangle; the apps from the Start menu's shortcuts. The process
 * is per-monitor DPI aware, so every coordinate is a physical pixel, as gdigrab's are.
 */
class WindowsPlatform(private val log: (String) -> Unit = {}) : HostPlatform {
    private val user32 = NativeLibrary("user32")
    private val kernel32 = NativeLibrary("kernel32")
    private val dwmapi = runCatching { NativeLibrary("dwmapi") }.getOrNull()
    private val shell32 = NativeLibrary("shell32")
    private val ole32 = NativeLibrary("ole32")

    private val SetProcessDpiAwarenessContext = user32.fn("SetProcessDpiAwarenessContext", INT, ADDR)
    private val GetTopWindow = user32.need("GetTopWindow", ADDR, ADDR)
    private val GetWindow = user32.need("GetWindow", ADDR, ADDR, INT)
    private val IsWindowVisible = user32.need("IsWindowVisible", INT, ADDR)
    private val IsWindow = user32.need("IsWindow", INT, ADDR)
    private val IsIconic = user32.need("IsIconic", INT, ADDR)
    private val IsZoomed = user32.need("IsZoomed", INT, ADDR)
    private val GetWindowTextLengthW = user32.need("GetWindowTextLengthW", INT, ADDR)
    private val GetWindowTextW = user32.need("GetWindowTextW", INT, ADDR, ADDR, INT)
    private val GetWindowLongPtrW = user32.need("GetWindowLongPtrW", LONG, ADDR, INT)
    private val GetWindowRect = user32.need("GetWindowRect", INT, ADDR, ADDR)
    private val GetWindowThreadProcessId = user32.need("GetWindowThreadProcessId", INT, ADDR, ADDR)
    private val GetForegroundWindow = user32.need("GetForegroundWindow", ADDR)
    private val SetForegroundWindow = user32.need("SetForegroundWindow", INT, ADDR)
    private val ShowWindow = user32.need("ShowWindow", INT, ADDR, INT)
    private val PostMessageW = user32.need("PostMessageW", INT, ADDR, INT, LONG, LONG)
    private val SetWindowPos = user32.need("SetWindowPos", INT, ADDR, ADDR, INT, INT, INT, INT, INT)
    private val GetSystemMetrics = user32.need("GetSystemMetrics", INT, INT)
    private val GetCursorPos = user32.need("GetCursorPos", INT, ADDR)
    private val SetCursorPos = user32.need("SetCursorPos", INT, INT, INT)
    private val SendInput = user32.need("SendInput", INT, INT, ADDR, INT)
    private val MapVirtualKeyW = user32.need("MapVirtualKeyW", INT, INT, INT)
    private val OpenInputDesktop = user32.need("OpenInputDesktop", ADDR, INT, INT, INT)
    private val CloseDesktop = user32.need("CloseDesktop", INT, ADDR)
    private val OpenProcess = kernel32.need("OpenProcess", ADDR, INT, INT, INT)
    private val CloseHandle = kernel32.need("CloseHandle", INT, ADDR)
    private val QueryFullProcessImageNameW = kernel32.need("QueryFullProcessImageNameW", INT, ADDR, INT, ADDR, ADDR)
    private val ShellExecuteW = shell32.need("ShellExecuteW", ADDR, ADDR, ADDR, ADDR, ADDR, ADDR, INT)
    private val CoInitializeEx = ole32.need("CoInitializeEx", INT, ADDR, INT)
    private val DwmGetWindowAttribute = dwmapi?.fn("DwmGetWindowAttribute", INT, ADDR, INT, ADDR, INT)
    private val pid = ProcessHandle.current().pid().toInt()

    init {
        // Per-monitor DPI aware (v2): physical pixels everywhere.
        SetProcessDpiAwarenessContext?.int(MemorySegment.ofAddress(-4L))
    }

    override val osName = "Windows"
    override val hostName: String = System.getenv("COMPUTERNAME")?.let { n -> n.lowercase().replaceFirstChar { it.uppercase() } } ?: "Windows PC"

    private fun hwnd(id: Long) = MemorySegment.ofAddress(id)

    // MARK: Windows

    override fun windows(): List<PlatformWindow> {
        val out = ArrayList<PlatformWindow>()
        var h = GetTopWindow.ptr(MemorySegment.NULL)
        var guard = 0
        while (!h.isNull() && guard++ < 4096) {
            describe(h)?.let(out::add)
            h = GetWindow.ptr(h, GW_HWNDNEXT)
        }
        return out
    }

    private fun describe(h: MemorySegment): PlatformWindow? {
        if (IsWindowVisible.int(h) == 0) return null
        if (!GetWindow.ptr(h, GW_OWNER).isNull()) return null
        val ex = GetWindowLongPtrW.long(h, GWL_EXSTYLE)
        if (ex and WS_EX_TOOLWINDOW != 0L && ex and WS_EX_APPWINDOW == 0L) return null
        if (cloaked(h)) return null
        val title = title(h).ifEmpty { return null }
        val exe = processImage(h) ?: return null
        if (exe.second == pid) return null
        val b = bounds(h.address()) ?: return null
        val file = File(exe.first)
        return PlatformWindow(h.address(), title, file.nameWithoutExtension.replaceFirstChar { it.uppercase() }, file.path.lowercase(), b, IsIconic.int(h) != 0)
    }

    private fun cloaked(h: MemorySegment): Boolean {
        val f = DwmGetWindowAttribute ?: return false
        return Arena.ofConfined().use { a -> val v = a.allocate(INT); f.int(h, DWMWA_CLOAKED, v, 4) == 0 && v.get(INT, 0) != 0 }
    }

    private fun title(h: MemorySegment): String = Arena.ofConfined().use { a ->
        val n = GetWindowTextLengthW.int(h)
        if (n <= 0) return ""
        val buf = a.allocate(2L * (n + 1))
        val got = GetWindowTextW.int(h, buf, n + 1)
        String(buf.asSlice(0, 2L * got).toArray(ValueLayout.JAVA_CHAR))
    }

    /** The window's program and its process ID. */
    private fun processImage(h: MemorySegment): Pair<String, Int>? = Arena.ofConfined().use { a ->
        val p = a.allocate(INT)
        GetWindowThreadProcessId.int(h, p)
        val id = p.get(INT, 0)
        val proc = OpenProcess.ptr(PROCESS_QUERY_LIMITED_INFORMATION, 0, id)
        if (proc.isNull()) return ("unknown.exe" to id)
        try {
            val buf = a.allocate(2L * 1024); val size = a.allocate(INT).also { it.set(INT, 0, 1024) }
            if (QueryFullProcessImageNameW.int(proc, 0, buf, size) == 0) return ("unknown.exe" to id)
            String(buf.asSlice(0, 2L * size.get(INT, 0)).toArray(ValueLayout.JAVA_CHAR)) to id
        } finally { CloseHandle.int(proc) }
    }

    override fun bounds(id: Long): Rect? = Arena.ofConfined().use { a ->
        val h = hwnd(id)
        if (IsWindow.int(h) == 0) return null
        val r = a.allocate(16)
        // The frame without its invisible resize border (DWM's extended frame bounds), else the window rectangle.
        val ok = DwmGetWindowAttribute?.int(h, DWMWA_EXTENDED_FRAME_BOUNDS, r, 16) == 0 || GetWindowRect.int(h, r) != 0
        if (!ok) return null
        val l = r.get(INT, 0); val t = r.get(INT, 4); val rr = r.get(INT, 8); val b = r.get(INT, 12)
        if (rr <= l || b <= t) null else Rect(l, t, rr - l, b - t)
    }

    override fun desktopBounds() = Rect(0, 0, GetSystemMetrics.int(SM_CXSCREEN), GetSystemMetrics.int(SM_CYSCREEN))

    override fun raise(id: Long) {
        val h = hwnd(id)
        if (IsIconic.int(h) != 0) ShowWindow.int(h, SW_RESTORE)
        // Windows lets a background process take the foreground only right after input of its own: an Alt tap first.
        sendKeys(listOf(Key(VK_MENU, 0, false), Key(VK_MENU, 0, true)), virtual = true)
        SetForegroundWindow.int(h)
    }

    override fun close(id: Long) { PostMessageW.int(hwnd(id), WM_CLOSE, 0L, 0L) }
    override fun minimize(id: Long) { ShowWindow.int(hwnd(id), SW_MINIMIZE) }
    override fun toggleFullScreen(id: Long) { val h = hwnd(id); ShowWindow.int(h, if (IsZoomed.int(h) != 0) SW_RESTORE else SW_MAXIMIZE) }

    override fun setBounds(id: Long, r: Rect): Rect? {
        if (SetWindowPos.int(hwnd(id), MemorySegment.NULL, 0, 0, r.w, r.h, SWP_NOMOVE or SWP_NOZORDER or SWP_NOACTIVATE) == 0) return null
        Thread.sleep(50)
        return bounds(id)
    }

    override fun foregroundWindow(): Long? = GetForegroundWindow.ptr().address().takeIf { it != 0L }

    override fun cursorPosition(): Pair<Int, Int>? = Arena.ofConfined().use { a ->
        val p = a.allocate(8)
        if (GetCursorPos.int(p) == 0) null else p.get(INT, 0) to p.get(INT, 4)
    }

    /** Locked: the input desktop is the secure one, which this process cannot open. */
    override fun isLocked(): Boolean {
        val d = OpenInputDesktop.ptr(0, 0, DESKTOP_SWITCHDESKTOP)
        if (d.isNull()) return true
        CloseDesktop.int(d)
        return false
    }

    override val captureFollowsWindow = false

    // MARK: Capture

    override fun startVideo(source: Source, params: StreamParams, sink: VideoSink): EncodedVideo {
        val screen = desktopBounds()
        val r = when (source) { Source.Desktop -> screen; is Source.Window -> source.window.bounds }
        val (x, y, w, h) = CaptureRect.clip(r, screen)
        val spec = CaptureSpec("gdigrab", "desktop", mapOf("offset_x" to "$x", "offset_y" to "$y", "video_size" to "${w}x$h",
            "framerate" to params.fps.toString(), "draw_mouse" to "0"),
            if (source is Source.Window) "\"${source.window.title}\" at $x,$y" else "the screen")
        return FfmpegVideo.open(spec, params, null, sink, log)
    }

    override fun thumbnail(window: PlatformWindow, maxWidth: Int): ByteArray? = if (window.minimized) null else Thumbnails.ofScreen(window.bounds, desktopBounds(), maxWidth)

    // MARK: Input

    private class Key(val code: Int, val unicodeOrScan: Int, val up: Boolean)

    /** SendInput with keyboard INPUTs (40 bytes each on 64-bit Windows): virtual keys, scan codes or UTF-16 units. */
    private fun sendKeys(keys: List<Key>, virtual: Boolean = false, unicode: Boolean = false) = Arena.ofConfined().use { a ->
        val buf = a.allocate(INPUT_SIZE * keys.size)
        for ((i, k) in keys.withIndex()) {
            val o = INPUT_SIZE * i
            buf.set(INT, o, INPUT_KEYBOARD)
            var flags = if (k.up) KEYEVENTF_KEYUP else 0
            when {
                unicode -> { buf.set(SHORT, o + 8, 0); buf.set(SHORT, o + 10, k.unicodeOrScan.toShort()); flags = flags or KEYEVENTF_UNICODE }
                virtual -> { buf.set(SHORT, o + 8, k.code.toShort()); buf.set(SHORT, o + 10, 0) }
                else -> {
                    // The scan code is what counts; the virtual key beside it is for code that reads only that (Wine, some games).
                    val vk = MapVirtualKeyW.int(if (k.unicodeOrScan and 0xE000 == 0xE000) 0xE000 or (k.unicodeOrScan and 0xFF) else k.unicodeOrScan and 0xFF, MAPVK_VSC_TO_VK_EX)
                    buf.set(SHORT, o + 8, vk.toShort()); buf.set(SHORT, o + 10, (k.unicodeOrScan and 0xFF).toShort())
                    flags = flags or KEYEVENTF_SCANCODE or (if (k.unicodeOrScan and 0xE000 == 0xE000) KEYEVENTF_EXTENDEDKEY else 0)
                }
            }
            buf.set(INT, o + 12, flags)
        }
        SendInput.int(keys.size, buf, INPUT_SIZE.toInt())
    }

    private fun mouse(flags: Int, data: Int = 0) = Arena.ofConfined().use { a ->
        val buf = a.allocate(INPUT_SIZE)
        buf.set(INT, 0, INPUT_MOUSE)
        buf.set(INT, 16, data)                              // mouseData
        buf.set(INT, 20, flags)                             // dwFlags
        SendInput.int(1, buf, INPUT_SIZE.toInt())
    }

    override val input: InputSink = object : InputSink {
        private var wheelX = 0.0
        private var wheelY = 0.0
        override fun move(x: Int, y: Int) { SetCursorPos.int(x, y) }
        override fun button(button: Int, down: Boolean) = mouse(when {
            button == 3 && down -> MOUSEEVENTF_RIGHTDOWN; button == 3 -> MOUSEEVENTF_RIGHTUP
            down -> MOUSEEVENTF_LEFTDOWN; else -> MOUSEEVENTF_LEFTUP
        }).let {}

        override fun wheel(dx: Double, dy: Double) {
            // Windows takes fractions of a notch (WHEEL_DELTA 120); positive is up, and right for the tilt wheel.
            wheelY += dy * 120; wheelX += dx * 120
            val y = wheelY.toInt(); val x = wheelX.toInt()
            wheelY -= y; wheelX -= x
            if (y != 0) mouse(MOUSEEVENTF_WHEEL, y)
            if (x != 0) mouse(MOUSEEVENTF_HWHEEL, x)
        }

        override fun key(usage: Int, down: Boolean) { val sc = SCAN[usage] ?: return; sendKeys(listOf(Key(0, sc, !down))) }

        override fun text(s: String) {
            val keys = ArrayList<Key>()
            for (c in s) { keys += Key(0, c.code, false); keys += Key(0, c.code, true) }
            if (keys.isNotEmpty()) sendKeys(keys, unicode = true)
        }
    }

    // MARK: Apps, clipboard, gestures

    private val startMenu by lazy { StartMenu.load() }

    override fun apps(): List<AppInfo> = startMenu.map { AppInfo(it.nameWithoutExtension, it.path) }

    override fun launch(appId: String) {
        // Only a Start menu shortcut, never another path (StreamHost checks too): no file a device names
        // is opened, and no UNC path is touched.
        val f = startMenu.firstOrNull { it.path == appId } ?: return log("Launch: no app $appId")
        // ShellExecute, as a double click starts it, with no command line to parse (cmd's start split a
        // path at "&"). COM on this thread first, as ShellExecute asks.
        CoInitializeEx.int(MemorySegment.NULL, COINIT_APARTMENTTHREADED or COINIT_DISABLE_OLE1DDE)
        Arena.ofConfined().use { a ->
            val r = ShellExecuteW.ptr(MemorySegment.NULL, a.wide("open"), a.wide(f.path), MemorySegment.NULL, MemorySegment.NULL, SW_SHOWNORMAL)
            if (r.address() <= 32) log("Launch: ${f.nameWithoutExtension} did not start (ShellExecute ${r.address()})")
        }
    }

    private fun Arena.wide(s: String): MemorySegment {
        val b = (s + "\u0000").toByteArray(Charsets.UTF_16LE)
        return allocate(b.size.toLong(), 2).also { it.copyFrom(MemorySegment.ofArray(b)) }
    }

    override fun appIcon(appId: String): ByteArray? = try {
        val f = File(appId)
        if (!f.exists()) null else {
            val icon = javax.swing.filechooser.FileSystemView.getFileSystemView().getSystemIcon(f, 64, 64) ?: return null
            val img = java.awt.image.BufferedImage(icon.iconWidth, icon.iconHeight, java.awt.image.BufferedImage.TYPE_INT_ARGB)
            img.createGraphics().apply { icon.paintIcon(null, this, 0, 0); dispose() }
            Thumbnails.png(img)
        }
    } catch (_: Exception) { null }

    override fun clipboardText(): String? = Clipboards.text()
    override fun setClipboardText(text: String) = Clipboards.setText(text)

    override fun gestureChord(gesture: String): List<Int>? = when (gesture) {
        "swipeUp", "swipeDown" -> listOf(HidKeys.LEFT_COMMAND, HidKeys.TAB)                         // Task View
        "swipeLeft" -> listOf(HidKeys.LEFT_CONTROL, HidKeys.LEFT_COMMAND, HidKeys.RIGHT)           // the next virtual desktop
        "swipeRight" -> listOf(HidKeys.LEFT_CONTROL, HidKeys.LEFT_COMMAND, HidKeys.LEFT)
        "pinch" -> listOf(HidKeys.LEFT_COMMAND)                                                    // Start
        "spread" -> listOf(HidKeys.LEFT_COMMAND, 0x07)                                             // Win+D, the desktop
        else -> null
    }

    companion object {
        const val GW_HWNDNEXT = 2; const val GW_OWNER = 4
        const val GWL_EXSTYLE = -20
        const val WS_EX_TOOLWINDOW = 0x80L; const val WS_EX_APPWINDOW = 0x40000L
        const val DWMWA_EXTENDED_FRAME_BOUNDS = 9; const val DWMWA_CLOAKED = 14
        const val PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
        const val SM_CXSCREEN = 0; const val SM_CYSCREEN = 1
        const val SW_MAXIMIZE = 3; const val SW_MINIMIZE = 6; const val SW_RESTORE = 9; const val SW_SHOWNORMAL = 1
        const val COINIT_APARTMENTTHREADED = 0x2; const val COINIT_DISABLE_OLE1DDE = 0x4
        const val WM_CLOSE = 0x10
        const val SWP_NOMOVE = 0x2; const val SWP_NOZORDER = 0x4; const val SWP_NOACTIVATE = 0x10
        const val DESKTOP_SWITCHDESKTOP = 0x100
        const val INPUT_MOUSE = 0; const val INPUT_KEYBOARD = 1
        const val INPUT_SIZE = 40L
        const val KEYEVENTF_EXTENDEDKEY = 0x1; const val KEYEVENTF_KEYUP = 0x2; const val KEYEVENTF_UNICODE = 0x4; const val KEYEVENTF_SCANCODE = 0x8
        const val MOUSEEVENTF_LEFTDOWN = 0x2; const val MOUSEEVENTF_LEFTUP = 0x4; const val MOUSEEVENTF_RIGHTDOWN = 0x8; const val MOUSEEVENTF_RIGHTUP = 0x10
        const val MOUSEEVENTF_WHEEL = 0x800; const val MOUSEEVENTF_HWHEEL = 0x1000
        const val VK_MENU = 0x12
        const val MAPVK_VSC_TO_VK_EX = 3

        /** USB HID usages as PC set-1 scan codes; 0xE0xx are the extended keys. */
        val SCAN: Map<Int, Int> = buildMap {
            val letters = intArrayOf(0x1E, 0x30, 0x2E, 0x20, 0x12, 0x21, 0x22, 0x23, 0x17, 0x24, 0x25, 0x26, 0x32, 0x31, 0x18, 0x19, 0x10, 0x13, 0x1F, 0x14, 0x16, 0x2F, 0x11, 0x2D, 0x15, 0x2C)
            for (i in letters.indices) put(0x04 + i, letters[i])
            for (i in 0 until 9) put(0x1E + i, 0x02 + i)
            put(0x27, 0x0B)
            putAll(mapOf(0x28 to 0x1C, 0x29 to 0x01, 0x2A to 0x0E, 0x2B to 0x0F, 0x2C to 0x39, 0x2D to 0x0C, 0x2E to 0x0D, 0x2F to 0x1A, 0x30 to 0x1B,
                0x31 to 0x2B, 0x32 to 0x2B, 0x33 to 0x27, 0x34 to 0x28, 0x35 to 0x29, 0x36 to 0x33, 0x37 to 0x34, 0x38 to 0x35, 0x39 to 0x3A))
            for (i in 0 until 10) put(0x3A + i, 0x3B + i)
            putAll(mapOf(0x44 to 0x57, 0x45 to 0x58, 0x46 to 0xE037, 0x47 to 0x46, 0x49 to 0xE052, 0x4A to 0xE047, 0x4B to 0xE049, 0x4C to 0xE053,
                0x4D to 0xE04F, 0x4E to 0xE051, 0x4F to 0xE04D, 0x50 to 0xE04B, 0x51 to 0xE050, 0x52 to 0xE048, 0x53 to 0x45, 0x54 to 0xE035,
                0x55 to 0x37, 0x56 to 0x4A, 0x57 to 0x4E, 0x58 to 0xE01C, 0x59 to 0x4F, 0x5A to 0x50, 0x5B to 0x51, 0x5C to 0x4B, 0x5D to 0x4C,
                0x5E to 0x4D, 0x5F to 0x47, 0x60 to 0x48, 0x61 to 0x49, 0x62 to 0x52, 0x63 to 0x53, 0x64 to 0x56, 0x65 to 0xE05D,
                0xE0 to 0x1D, 0xE1 to 0x2A, 0xE2 to 0x38, 0xE3 to 0xE05B, 0xE4 to 0xE01D, 0xE5 to 0x36, 0xE6 to 0xE038, 0xE7 to 0xE05C))
        }
    }
}

/** The Start menu's shortcuts (all users' and this user's), the apps a device can launch. */
internal object StartMenu {
    fun load(): List<File> {
        val roots = listOfNotNull(System.getenv("ProgramData")?.let { "$it\\Microsoft\\Windows\\Start Menu\\Programs" },
            System.getenv("APPDATA")?.let { "$it\\Microsoft\\Windows\\Start Menu\\Programs" }).map(::File)
        return roots.flatMap { r -> r.walkTopDown().maxDepth(3).filter { it.isFile && it.name.endsWith(".lnk", true) }.toList() }
            .filter { f -> listOf("uninstall", "readme", "help", "documentation", "website").none { f.name.lowercase().contains(it) } }
            .distinctBy { it.nameWithoutExtension.lowercase() }.sortedBy { it.nameWithoutExtension.lowercase() }
    }
}
