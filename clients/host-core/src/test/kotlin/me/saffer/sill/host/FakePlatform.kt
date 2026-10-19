package me.saffer.sill.host

import me.saffer.sill.core.AppInfo
import me.saffer.sill.core.HevcSample
import me.saffer.sill.core.HidKeys
import java.util.concurrent.CopyOnWriteArrayList

/** TEST ONLY. A host platform with made-up windows, the sample HEVC as its video, and input recorded. */
class FakePlatform : HostPlatform {
    override val osName = "Linux"
    override val hostName = "Test PC"
    val events = CopyOnWriteArrayList<String>()
    @Volatile var clip: String? = "on the PC before"
    @Volatile var cursor: Pair<Int, Int>? = null
    val started = CopyOnWriteArrayList<Pair<Source, StreamParams>>()
    val launched = CopyOnWriteArrayList<String>()
    val commands = CopyOnWriteArrayList<String>()
    @Volatile var list = listOf(
        PlatformWindow(0x1200001, "notes.txt — Editor", "Editor", "editor", Rect(100, 50, 800, 600)),
        PlatformWindow(0x1400002, "Terminal", "Terminal", "terminal", Rect(300, 200, 640, 400)),
    )

    override val input = object : InputSink {
        override fun move(x: Int, y: Int) { events += "move $x,$y" }
        override fun button(button: Int, down: Boolean) { events += "button $button ${if (down) "down" else "up"}" }
        override fun wheel(dx: Double, dy: Double) { events += "wheel %.2f,%.2f".format(dx, dy) }
        override fun key(usage: Int, down: Boolean) { events += "key 0x%02X ${if (down) "down" else "up"}".format(usage) }
        override fun text(s: String) { events += "text $s" }
    }

    override fun windows() = list
    override fun desktopBounds() = Rect(0, 0, 1920, 1080)
    override fun thumbnail(window: PlatformWindow, maxWidth: Int) = byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 1, 2, 3)
    override fun bounds(id: Long) = list.firstOrNull { it.id == id }?.bounds
    override fun raise(id: Long) { commands += "raise $id" }
    override fun close(id: Long) { commands += "close $id"; list = list.filter { it.id != id } }
    override fun minimize(id: Long) { commands += "minimize $id" }
    override fun toggleFullScreen(id: Long) { commands += "fullScreen $id" }
    override fun setBounds(id: Long, r: Rect): Rect? {
        commands += "setBounds $id ${r.w}x${r.h}"
        list = list.map { if (it.id == id) it.copy(bounds = r) else it }
        return r
    }
    override fun apps() = listOf(AppInfo("Editor", "editor"), AppInfo("Terminal", "terminal"))
    override fun launch(appId: String) { launched += appId }
    override fun clipboardText() = clip
    override fun setClipboardText(text: String) { clip = text }
    override fun appIcon(appId: String) = byteArrayOf(0x89.toByte(), 'P'.code.toByte(), 'N'.code.toByte(), 'G'.code.toByte())
    override fun cursorPosition() = cursor
    override fun gestureChord(gesture: String): List<Int>? = when (gesture) {
        "swipeUp" -> listOf(HidKeys.LEFT_COMMAND, HidKeys.TAB)
        else -> null
    }

    /** The sample stream, looped, at the asked rate. */
    override fun startVideo(source: Source, params: StreamParams, sink: VideoSink): EncodedVideo {
        started += source to params
        val (sets, aus) = HevcSample.load("sample-motion.hevc")
        return object : EncodedVideo {
            @Volatile var running = true
            @Volatile var key = true
            override val width = 320
            override val height = 240
            override fun requestKeyframe() { key = true }
            val t = Thread({
                sink.parameterSets(sets)
                var i = 0
                while (running) {
                    if (key) { i = 0; key = false }
                    val (k, au) = aus[i % aus.size]
                    // Past the first loop the sample's keyframe is the only one: each loop starts there.
                    sink.frame(au, k, System.currentTimeMillis() / 1e3)
                    i++
                    if (i % aus.size == 0) key = true
                    Thread.sleep(1000L / params.fps)
                }
            }, "fake-video").apply { isDaemon = true; start() }
            override fun close() { running = false; t.join(1000) }
        }
    }
}
