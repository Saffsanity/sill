package me.saffer.sill.host

import me.saffer.sill.core.AppInfo
import me.saffer.sill.core.ParameterSets

/** A rectangle in the host's screen pixels. */
data class Rect(val x: Int, val y: Int, val w: Int, val h: Int) {
    val area get() = w.toLong() * h
}

/**
 * The rectangle a screen grab takes for a window (x11grab, gdigrab): kept on the screen, at even
 * sizes for the encoder. Input and the pointer's fractions are mapped against this same rectangle,
 * so a window partly off the screen is clicked where its picture shows.
 */
object CaptureRect {
    fun clip(r: Rect, screen: Rect): Rect {
        val x = r.x.coerceIn(screen.x, screen.x + screen.w - 2); val y = r.y.coerceIn(screen.y, screen.y + screen.h - 2)
        val w = maxOf(2, minOf(r.x + r.w, screen.x + screen.w) - x) and 1.inv()
        val h = maxOf(2, minOf(r.y + r.h, screen.y + screen.h) - y) and 1.inv()
        return Rect(x, y, w, h)
    }
}

/** One window on the host, as its platform lists it. */
data class PlatformWindow(
    /** The platform's handle (an HWND on Windows, an X11 window ID on Linux); stable for the window's life. */
    val id: Long,
    val title: String,
    /** "Notepad", "Firefox": what the device shows as the app's name. */
    val app: String,
    /** What identifies the app across windows and for its icon and launch ("notepad.exe", "firefox"). */
    val appId: String,
    val bounds: Rect,
    val minimized: Boolean = false,
)

/**
 * Input as the PC takes it: positions in screen pixels, keys as USB HID usages with the PC's meaning
 * (0xE3, Left GUI, is the Windows or Super key), the wheel in notches (one notch is 120 Windows
 * units, one X11 button 4 or 5 press; fractions accumulate), positive `dy` scrolling up (the content
 * moves down).
 */
interface InputSink {
    fun move(x: Int, y: Int)
    /** 1 the left button, 3 the right. */
    fun button(button: Int, down: Boolean)
    fun wheel(dx: Double, dy: Double)
    fun key(usage: Int, down: Boolean)
    /** Text typed as Unicode, whatever the keyboard layout. Never contains "\n", "\t" or backspace (those arrive as keys). */
    fun text(s: String)
}

/** The stream of one source, encoded: the parameter sets when they change, then access units. */
interface EncodedVideo : AutoCloseable {
    /** The picture size the encoder makes, after scaling. */
    val width: Int
    val height: Int
    /** The next keyframe as soon as possible (a device joined, or one dropped a frame). */
    fun requestKeyframe()
}

/** What an [EncodedVideo] delivers, on its own thread. */
interface VideoSink {
    fun parameterSets(sets: ParameterSets)
    /** One access unit, its NAL units after 4-byte big-endian lengths (VideoToolbox's shape), parameter sets left out. */
    fun frame(au: ByteArray, keyframe: Boolean, timestamp: Double)
    /** The capture or the encoder stopped for good (the window closed, the device was lost). */
    fun failed(reason: String)
}

/** How the stream is made: its rate, its bitrate per 60 fps, and its scale (2 the native pixels, 1 half). */
data class StreamParams(val fps: Int, val bitratePer60: Int, val captureScale: Double) {
    val bitrate get() = (bitratePer60.toLong() * fps / 60).coerceAtMost(Int.MAX_VALUE.toLong()).toInt()
}

/** What streams: the whole screen, or one window. */
sealed class Source {
    object Desktop : Source() { override fun toString() = "the desktop" }
    data class Window(val window: PlatformWindow) : Source()
}

/**
 * Everything a host does that depends on the operating system: listing and moving windows, the
 * screen, capture and encoding, input, the clipboard and the installed apps. Linux (X11) and Windows
 * implement it in the host module; tests use a fake.
 */
interface HostPlatform {
    /** "Windows", "Linux": for logs and the device's words. */
    val osName: String
    /** This computer's name, as devices list it. */
    val hostName: String
    val input: InputSink

    /** The windows a person would pick from, front to back, without the host's own. */
    fun windows(): List<PlatformWindow>
    /** The primary screen. */
    fun desktopBounds(): Rect
    /** A small JPEG of the window (at most `maxWidth` pixels wide), or null. */
    fun thumbnail(window: PlatformWindow, maxWidth: Int): ByteArray?
    /** The window's frame now, or null when it is gone. */
    fun bounds(id: Long): Rect?
    fun raise(id: Long)
    fun close(id: Long)
    fun minimize(id: Long)
    fun toggleFullScreen(id: Long)
    /** Moves and sizes a window; returns the frame it took, or null when it refused. */
    fun setBounds(id: Long, r: Rect): Rect?

    fun apps(): List<AppInfo>
    fun launch(appId: String)

    fun clipboardText(): String?
    fun setClipboardText(text: String)

    /** Starts capturing and encoding `source`; frames go to `sink` until [EncodedVideo.close]. */
    fun startVideo(source: Source, params: StreamParams, sink: VideoSink): EncodedVideo

    /** The keyboard shortcut for a trackpad gesture (TrackpadGesture's names), as PC HID usages pressed together; null for none. */
    fun gestureChord(gesture: String): List<Int>?

    /** An app's icon as a PNG (kind 4), or null. */
    fun appIcon(appId: String): ByteArray? = null
    /** The window in front, when the platform can tell. */
    fun foregroundWindow(): Long? = null
    /** Where the PC's pointer is, in screen pixels (the device draws it while the PC moves it, kind 26). */
    fun cursorPosition(): Pair<Int, Int>? = null
    /** Whether this computer is locked (a device's ask then gets "locked"). */
    fun isLocked(): Boolean = false
    /** Whether a window's capture follows the window when it moves; if not, the host restarts it at the new place. */
    val captureFollowsWindow: Boolean get() = false
}
