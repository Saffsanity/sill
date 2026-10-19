package me.saffer.sill.core

/**
 * Keys as the Mac takes them (InputEvent.Key: a USB HID usage on page 7, and UIKeyModifierFlags),
 * from each platform's own codes: Java AWT's virtual keys (the Windows client) and Android's key
 * codes, both plain numbers here so the tables are checked once, in the core.
 *
 * Which keys go as keys and which as text follows the iPad's rule (KeyChords.swift): the keys with
 * no text (arrows, Esc, forward delete, Home, End, Page Up and Down, F1–F12, the modifiers
 * themselves) go as keys, and so does any key held with ⌘, ⌃ or ⌥ (a shortcut); everything else goes
 * as the text it types, so the Mac's own keyboard layout never re-maps what the person typed.
 */
object HidKeys {
    const val ENTER = 0x28; const val ESCAPE = 0x29; const val BACKSPACE = 0x2A; const val TAB = 0x2B; const val SPACE = 0x2C
    const val CAPS_LOCK = 0x39; const val F1 = 0x3A; const val F12 = 0x45
    const val INSERT = 0x49; const val HOME = 0x4A; const val PAGE_UP = 0x4B; const val DELETE_FORWARD = 0x4C
    const val END = 0x4D; const val PAGE_DOWN = 0x4E; const val RIGHT = 0x4F; const val LEFT = 0x50; const val DOWN = 0x51; const val UP = 0x52
    const val LEFT_CONTROL = 0xE0; const val LEFT_SHIFT = 0xE1; const val LEFT_OPTION = 0xE2; const val LEFT_COMMAND = 0xE3
    const val RIGHT_CONTROL = 0xE4; const val RIGHT_SHIFT = 0xE5; const val RIGHT_OPTION = 0xE6; const val RIGHT_COMMAND = 0xE7

    /** A key with no text of its own: always sent as a key (KeyChords.swift's list). */
    fun isRaw(usage: Int) = usage in RIGHT..UP || usage == ESCAPE || usage == DELETE_FORWARD || usage == HOME || usage == END ||
        usage == PAGE_UP || usage == PAGE_DOWN || usage in F1..F12 || isModifier(usage)

    fun isModifier(usage: Int) = usage in LEFT_CONTROL..RIGHT_COMMAND

    /** The modifier bit a modifier key's usage holds, 0 for any other key. */
    fun modifierBit(usage: Int): Long = when (usage) {
        LEFT_SHIFT, RIGHT_SHIFT -> Modifiers.SHIFT
        LEFT_CONTROL, RIGHT_CONTROL -> Modifiers.CONTROL
        LEFT_OPTION, RIGHT_OPTION -> Modifiers.OPTION
        LEFT_COMMAND, RIGHT_COMMAND -> Modifiers.COMMAND
        else -> 0
    }

    /** Whether a key held with `modifiers` goes as a key (a shortcut): ⌘, ⌃ or ⌥ held. */
    fun isShortcut(modifiers: Long) = modifiers and (Modifiers.COMMAND or Modifiers.CONTROL or Modifiers.OPTION) != 0L

    private fun letters(base: Int) = (0 until 26).associate { (base + it) to (0x04 + it) }

    /** Java AWT virtual keys (java.awt.event.KeyEvent.VK_*) to HID usages. The modifier keys are mapped by [DesktopModifiers]. */
    val awt: Map<Int, Int> = letters(0x41) + mapOf(
        0x31 to 0x1E, 0x32 to 0x1F, 0x33 to 0x20, 0x34 to 0x21, 0x35 to 0x22, 0x36 to 0x23, 0x37 to 0x24, 0x38 to 0x25, 0x39 to 0x26, 0x30 to 0x27,
        0x0A to ENTER, 0x1B to ESCAPE, 0x08 to BACKSPACE, 0x09 to TAB, 0x20 to SPACE,
        0x2D to 0x2D /* minus */, 0x3D to 0x2E /* equals */, 0x5B to 0x2F /* [ */, 0x5D to 0x30 /* ] */, 0x5C to 0x31 /* \ */,
        0x3B to 0x33 /* ; */, 0xDE to 0x34 /* quote */, 0xC0 to 0x35 /* back quote */, 0x2C to 0x36 /* , */, 0x2E to 0x37 /* . */, 0x2F to 0x38 /* / */,
        0x14 to CAPS_LOCK, 0x9B to INSERT, 0x24 to HOME, 0x21 to PAGE_UP, 0x7F to DELETE_FORWARD, 0x23 to END, 0x22 to PAGE_DOWN,
        0x27 to RIGHT, 0x25 to LEFT, 0x28 to DOWN, 0x26 to UP,
    ) + (0 until 12).associate { (0x70 + it) to (F1 + it) }

    /** Android key codes (android.view.KeyEvent.KEYCODE_*) to HID usages. */
    val android: Map<Int, Int> = (0 until 26).associate { (29 + it) to (0x04 + it) } + mapOf(
        8 to 0x1E, 9 to 0x1F, 10 to 0x20, 11 to 0x21, 12 to 0x22, 13 to 0x23, 14 to 0x24, 15 to 0x25, 16 to 0x26, 7 to 0x27,
        66 to ENTER, 111 to ESCAPE, 67 to BACKSPACE, 61 to TAB, 62 to SPACE,
        69 to 0x2D, 70 to 0x2E, 71 to 0x2F, 72 to 0x30, 73 to 0x31, 74 to 0x33, 75 to 0x34, 68 to 0x35, 55 to 0x36, 56 to 0x37, 76 to 0x38,
        115 to CAPS_LOCK, 124 to INSERT, 122 to HOME, 92 to PAGE_UP, 112 to DELETE_FORWARD, 123 to END, 93 to PAGE_DOWN,
        22 to RIGHT, 21 to LEFT, 20 to DOWN, 19 to UP,
        113 to LEFT_CONTROL, 114 to RIGHT_CONTROL, 59 to LEFT_SHIFT, 60 to RIGHT_SHIFT, 57 to LEFT_OPTION, 58 to RIGHT_OPTION,
        117 to LEFT_COMMAND, 118 to RIGHT_COMMAND,
    ) + (0 until 12).associate { (131 + it) to (F1 + it) }
}

/**
 * The PC's modifier keys as the Mac's (the Windows client): by default Ctrl is ⌘, so Ctrl+C copies
 * on the Mac as it does on the PC, the Windows key is ⌃, and Alt is ⌥. With `ctrlIsCommand` off,
 * Ctrl is ⌃ and the Windows key ⌘ (which Windows may keep for its Start menu).
 */
class DesktopModifiers(var ctrlIsCommand: Boolean = true) {
    /** AWT's VK_CONTROL, VK_SHIFT, VK_ALT, VK_META, VK_WINDOWS, VK_ALT_GRAPH and their sides to HID usages. */
    fun usage(vk: Int, right: Boolean): Int? = when (vk) {
        0x10 -> if (right) HidKeys.RIGHT_SHIFT else HidKeys.LEFT_SHIFT
        0x11 -> if (ctrlIsCommand) (if (right) HidKeys.RIGHT_COMMAND else HidKeys.LEFT_COMMAND) else (if (right) HidKeys.RIGHT_CONTROL else HidKeys.LEFT_CONTROL)
        0x12 -> if (right) HidKeys.RIGHT_OPTION else HidKeys.LEFT_OPTION
        0xFF7E -> HidKeys.RIGHT_OPTION                                   // Alt Gr
        0x20C, 0x9D -> if (ctrlIsCommand) (if (right) HidKeys.RIGHT_CONTROL else HidKeys.LEFT_CONTROL) else (if (right) HidKeys.RIGHT_COMMAND else HidKeys.LEFT_COMMAND)
        else -> null
    }

    /** AWT's modifier mask (InputEvent.*_DOWN_MASK) as the Mac's bits. */
    fun bits(awtMask: Int): Long {
        var m = 0L
        if (awtMask and 0x40 != 0) m = m or Modifiers.SHIFT                                         // SHIFT_DOWN_MASK
        if (awtMask and 0x80 != 0) m = m or (if (ctrlIsCommand) Modifiers.COMMAND else Modifiers.CONTROL)    // CTRL_DOWN_MASK
        if (awtMask and 0x100 != 0) m = m or (if (ctrlIsCommand) Modifiers.CONTROL else Modifiers.COMMAND)   // META_DOWN_MASK
        if (awtMask and 0x200 != 0) m = m or Modifiers.OPTION                                       // ALT_DOWN_MASK
        return m
    }
}

/**
 * The coast after a finger lifts (InputOverlay.swift's momentum): only above 150 pt/s; each step at
 * 60 Hz multiplies the velocity by 0.96^(dt·60), dt at most 0.1 s; it stops below 0.3 pt a frame.
 * Velocities in points per second; [step] returns the points to scroll, or null when the coast is over.
 */
class ScrollMomentum(private var vx: Double, private var vy: Double) {
    val active get() = kotlin.math.hypot(vx, vy) / 60 >= STOP

    fun step(dt: Double): Pair<Double, Double>? {
        if (!active) return null
        val d = dt.coerceIn(0.0, 0.1)
        val f = Math.pow(DECAY, d * 60)
        vx *= f; vy *= f
        return (vx * d) to (vy * d)
    }

    companion object {
        const val MIN_SPEED = 150.0
        const val DECAY = 0.96
        const val STOP = 0.3
        fun startIfFast(vx: Double, vy: Double) = if (kotlin.math.hypot(vx, vy) > MIN_SPEED) ScrollMomentum(vx, vy) else null
    }
}

/**
 * Where a point on the view lands in the streamed frame (Input.swift: fractions of the frame, 0…1),
 * for a frame of `frameW`×`frameH` drawn aspect-fit in a view of `viewW`×`viewH`. A tap in the
 * letterbox is no click ([clamped] false gives null); moves and drags clamp to the edge.
 */
object FrameMapping {
    data class Rect(val x: Double, val y: Double, val w: Double, val h: Double)

    fun fit(frameW: Double, frameH: Double, viewW: Double, viewH: Double): Rect {
        if (frameW <= 0 || frameH <= 0 || viewW <= 0 || viewH <= 0) return Rect(0.0, 0.0, viewW, viewH)
        val s = minOf(viewW / frameW, viewH / frameH)
        val w = frameW * s; val h = frameH * s
        return Rect((viewW - w) / 2, (viewH - h) / 2, w, h)
    }

    fun toFrame(px: Double, py: Double, r: Rect, clamped: Boolean): Pair<Double, Double>? {
        val fx = (px - r.x) / r.w
        val fy = (py - r.y) / r.h
        if (!clamped && (fx < 0 || fx > 1 || fy < 0 || fy > 1)) return null
        return fx.coerceIn(0.0, 1.0) to fy.coerceIn(0.0, 1.0)
    }

    fun fromFrame(fx: Double, fy: Double, r: Rect) = (r.x + fx * r.w) to (r.y + fy * r.h)
}
