package me.saffer.sill.host

import me.saffer.sill.core.HidKeys
import me.saffer.sill.core.InputEvent
import me.saffer.sill.core.Modifiers
import me.saffer.sill.core.PointerAction

/**
 * A device's input (InputEvent: the Mac's, from the iPhone and iPad app or another client) as the
 * PC's, for one device. Positions are fractions of the streamed frame, mapped onto `source`, the
 * screen rectangle streaming. Keys arrive with the Mac's modifier bits and become the PC's:
 *
 * - ⌘ and ⌃ are Ctrl, ⌥ is Alt, ⇧ is Shift, so ⌘C copies on the PC.
 * - A few Mac shortcuts become the PC's own, with ⌘ alone (and ⇧) held: ⌘Space the Windows/Super
 *   key (Start, the launcher: the iPad's Spotlight key), ⌘Tab Alt+Tab, ⌘Q Alt+F4, ⌘← and ⌘→ Home
 *   and End, ⌘↑ and ⌘↓ Ctrl+Home and Ctrl+End. ⌥← and ⌥→ are Ctrl+← and Ctrl+→ (by word).
 * - A key's down presses the modifiers its bits ask for that are not held, and releases the ones
 *   this translator pressed that are no longer asked for, so a latched modifier on the iPad's key
 *   row works and nothing stays held (the Mac host's KeyStrokes rule).
 * - "\n", "\t" and backspace in text are Enter, Tab and Backspace.
 * - Scrolling: the frame's fraction becomes pixels of the source, then notches of [pixelsPerNotch].
 */
class InputTranslator(private val sink: InputSink, var source: Rect, private val pixelsPerNotch: Double = 40.0) {
    /** Modifier keys held because the device holds the modifier key itself (its own key events). */
    private val physical = HashMap<Int, Int>()          // PC usage → how many Mac keys hold it
    /** Modifier keys this translator pressed for a key's bits. */
    private val synthetic = HashSet<Int>()
    /** Keys down on the PC for a device key, so its up releases what its down pressed. */
    private val downKeys = HashMap<Int, List<Int>>()    // Mac usage → PC usages pressed (in order)
    /** Buttons down on the PC for this device (1 left, 3 right). */
    private val buttons = HashSet<Int>()
    private var wheelX = 0.0
    private var wheelY = 0.0

    fun handle(e: InputEvent) {
        when (e) {
            is InputEvent.Pointer -> pointer(e)
            is InputEvent.Scroll -> scroll(e)
            is InputEvent.ScrollGesture -> {}            // the PC's wheel has no phases
            is InputEvent.Text -> text(e.text)
            is InputEvent.Key -> key(e.hidUsage, e.down, e.modifiers)
        }
    }

    /**
     * Input with nowhere to land (nothing streams): dropped, but for the up of a key or a button this
     * device has down on the PC, which goes where the pointer is (the Mac host's DroppedInput), so a
     * drag or a held ⌘ through a window closing never leaves the PC's button or Ctrl down.
     */
    fun handleDropped(e: InputEvent) {
        when (e) {
            is InputEvent.Pointer -> when (e.action) {
                PointerAction.LEFT_UP -> button(1, false)
                PointerAction.RIGHT_UP -> button(3, false)
                else -> {}
            }
            is InputEvent.Key -> if (!e.down) key(e.hidUsage, false, e.modifiers)
            else -> {}
        }
    }

    private fun button(b: Int, down: Boolean) {
        if (down) { buttons.add(b); sink.button(b, true) } else if (buttons.remove(b)) sink.button(b, false)
    }

    fun point(fx: Double, fy: Double): Pair<Int, Int> =
        (source.x + (fx.coerceIn(0.0, 1.0) * (source.w - 1)).toInt()) to (source.y + (fy.coerceIn(0.0, 1.0) * (source.h - 1)).toInt())

    private fun pointer(e: InputEvent.Pointer) {
        val (x, y) = point(e.x, e.y)
        sink.move(x, y)
        when (e.action) {
            PointerAction.MOVE -> {}
            PointerAction.LEFT_DOWN -> button(1, true)
            PointerAction.LEFT_UP -> sink.button(1, false).also { buttons.remove(1) }
            PointerAction.RIGHT_DOWN -> button(3, true)
            PointerAction.RIGHT_UP -> sink.button(3, false).also { buttons.remove(3) }
        }
    }

    private fun scroll(e: InputEvent.Scroll) {
        val (x, y) = point(e.x, e.y)
        sink.move(x, y)
        // Natural sign: positive dy moves the content down, which is the wheel's up.
        wheelX += -e.dx * source.w / pixelsPerNotch
        wheelY += e.dy * source.h / pixelsPerNotch
        val nx = wheelX; val ny = wheelY
        if (kotlin.math.abs(nx) >= 0.05 || kotlin.math.abs(ny) >= 0.05) {
            sink.wheel(nx, ny)
            wheelX = 0.0; wheelY = 0.0
        }
    }

    private fun text(s: String) {
        val chunk = StringBuilder()
        fun flush() { if (chunk.isNotEmpty()) { releaseSynthetic(); sink.text(chunk.toString()); chunk.clear() } }
        for (c in s) {
            val usage = when (c) { '\n', '\r' -> HidKeys.ENTER; '\t' -> HidKeys.TAB; '\u0008' -> HidKeys.BACKSPACE; else -> null }
            if (usage == null) { chunk.append(c); continue }
            flush()
            releaseSynthetic()
            sink.key(usage, true); sink.key(usage, false)
        }
        flush()
    }

    private fun key(usage: Int, down: Boolean, macBits: Long) {
        if (HidKeys.isModifier(usage)) return modifierKey(usage, down)
        if (!down) {
            val pressed = downKeys.remove(usage) ?: return
            for (u in pressed.asReversed()) sink.key(u, false)
            return
        }
        val special = special(usage, macBits)
        if (special != null) {
            // The PC's own shortcut: only its modifiers held while it is pressed.
            syncModifiers(emptySet(), releasePhysical = true)
            val (mods, key) = special
            for (m in mods) sink.key(m, true)
            sink.key(key, true)
            downKeys[usage] = mods + key
            return
        }
        syncModifiers(pcBits(macBits))
        sink.key(usage, true)
        downKeys[usage] = listOf(usage)
    }

    private fun modifierKey(usage: Int, down: Boolean) {
        val pc = pcModifier(usage) ?: return
        if (down) {
            val n = physical.getOrDefault(pc, 0)
            physical[pc] = n + 1
            if (n == 0 && pc !in synthetic) sink.key(pc, true)
            synthetic.remove(pc)
        } else {
            val n = physical.getOrDefault(pc, 0)
            if (n <= 1) { physical.remove(pc); if (pc !in synthetic) sink.key(pc, false) } else physical[pc] = n - 1
        }
    }

    /** Presses the PC modifiers `want` asks for that are not held; releases this translator's that it no longer asks for. */
    private fun syncModifiers(want: Set<Int>, releasePhysical: Boolean = false) {
        for (m in want) if (m !in physical && m !in synthetic) { sink.key(m, true); synthetic.add(m) }
        for (m in synthetic.toList()) if (m !in want) { sink.key(m, false); synthetic.remove(m) }
        if (releasePhysical) for (m in physical.keys.toList()) { sink.key(m, false); physical.remove(m) }
    }

    private fun releaseSynthetic() = syncModifiers(emptySet())

    /** Every key and button this device has down on the PC, let go (the device left). */
    fun releaseAll() {
        for ((_, pressed) in downKeys) for (u in pressed.asReversed()) sink.key(u, false)
        downKeys.clear()
        for (m in synthetic + physical.keys) sink.key(m, false)
        synthetic.clear(); physical.clear()
        sink.button(1, false)
        sink.button(3, false)
        buttons.clear()
    }

    companion object {
        private const val CTRL = HidKeys.LEFT_CONTROL
        private const val SHIFT = HidKeys.LEFT_SHIFT
        private const val ALT = HidKeys.LEFT_OPTION
        private const val GUI = HidKeys.LEFT_COMMAND          // the Windows or Super key on a PC

        /** A Mac modifier key's usage as the PC modifier it becomes. */
        fun pcModifier(usage: Int): Int? = when (usage) {
            HidKeys.LEFT_COMMAND, HidKeys.RIGHT_COMMAND, HidKeys.LEFT_CONTROL, HidKeys.RIGHT_CONTROL -> CTRL
            HidKeys.LEFT_OPTION, HidKeys.RIGHT_OPTION -> ALT
            HidKeys.LEFT_SHIFT, HidKeys.RIGHT_SHIFT -> SHIFT
            else -> null
        }

        fun pcBits(mac: Long): Set<Int> = buildSet {
            if (mac and (Modifiers.COMMAND or Modifiers.CONTROL) != 0L) add(CTRL)
            if (mac and Modifiers.OPTION != 0L) add(ALT)
            if (mac and Modifiers.SHIFT != 0L) add(SHIFT)
        }

        /** A Mac shortcut that becomes the PC's own: (modifiers, key); null for an ordinary key. */
        fun special(usage: Int, mac: Long): Pair<List<Int>, Int>? {
            val shift = mac and Modifiers.SHIFT != 0L
            val others = mac and (Modifiers.CONTROL or Modifiers.OPTION) != 0L
            val cmdOnly = mac and Modifiers.COMMAND != 0L && !others
            val s = if (shift) listOf(SHIFT) else emptyList()
            if (cmdOnly) when (usage) {
                HidKeys.SPACE -> if (!shift) return emptyList<Int>() to GUI
                HidKeys.TAB -> return (listOf(ALT) + s) to HidKeys.TAB
                0x14 /* q */ -> if (!shift) return listOf(ALT) to 0x3D /* F4 */
                HidKeys.LEFT -> return s to HidKeys.HOME
                HidKeys.RIGHT -> return s to HidKeys.END
                HidKeys.UP -> return (listOf(CTRL) + s) to HidKeys.HOME
                HidKeys.DOWN -> return (listOf(CTRL) + s) to HidKeys.END
            }
            val altOnly = mac and Modifiers.OPTION != 0L && mac and (Modifiers.COMMAND or Modifiers.CONTROL) == 0L
            if (altOnly) when (usage) {
                HidKeys.LEFT -> return (listOf(CTRL) + s) to HidKeys.LEFT
                HidKeys.RIGHT -> return (listOf(CTRL) + s) to HidKeys.RIGHT
                HidKeys.BACKSPACE -> return listOf(CTRL) to HidKeys.BACKSPACE
            }
            return null
        }
    }
}
