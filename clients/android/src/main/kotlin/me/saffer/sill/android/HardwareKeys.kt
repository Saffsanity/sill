package me.saffer.sill.android

import me.saffer.sill.core.HidKeys
import me.saffer.sill.core.InputEvent

/**
 * A hardware keyboard's keys as the Mac's input (pure, so the JVM tests run it): keys with no text,
 * shortcuts, and Return, Tab and Delete with a modifier go as keys (as text the Mac types them with
 * its modifiers cleared, so ⇧Return would send a message); the rest as the text they type. Ctrl is
 * ⌘ and the Meta key ⌃, either side. Each up names the usage its down sent, and [releaseAll] lets go
 * of every key still down, for when the ups can no longer reach the stream.
 */
class HardwareKeys(private val send: (InputEvent) -> Unit) {
    /** Keys sent down, by Android key code, with the usage sent. */
    private val down = HashMap<Int, Int>()

    fun isDown(keyCode: Int) = keyCode in down

    /** A key's down; false when it is not the stream's (the caller hands it to the platform). */
    fun down(keyCode: Int, usage: Int, bits: Long, unicodeChar: Int, typed: (String) -> Unit): Boolean {
        val mapped = when (usage) {
            HidKeys.LEFT_CONTROL -> HidKeys.LEFT_COMMAND; HidKeys.LEFT_COMMAND -> HidKeys.LEFT_CONTROL
            HidKeys.RIGHT_CONTROL -> HidKeys.RIGHT_COMMAND; HidKeys.RIGHT_COMMAND -> HidKeys.RIGHT_CONTROL
            else -> usage
        }
        val editKey = usage == HidKeys.ENTER || usage == HidKeys.TAB || usage == HidKeys.BACKSPACE
        if (HidKeys.isModifier(usage) || HidKeys.isRaw(usage) || HidKeys.isShortcut(bits) || (editKey && bits != 0L)) {
            down[keyCode] = mapped
            send(InputEvent.Key(mapped, true, bits))
            return true
        }
        when {
            usage == HidKeys.ENTER -> send(InputEvent.Text("\n"))
            usage == HidKeys.TAB -> send(InputEvent.Text("\t"))
            usage == HidKeys.BACKSPACE -> send(InputEvent.Text("\u0008"))
            unicodeChar != 0 -> typed(String(Character.toChars(unicodeChar)))
            else -> return false
        }
        return true
    }

    /** A key's up: sent when its down was; true when it was. */
    fun up(keyCode: Int, bits: Long): Boolean {
        val usage = down.remove(keyCode) ?: return false
        send(InputEvent.Key(usage, false, bits))
        return true
    }

    fun releaseAll() {
        for (u in down.values) send(InputEvent.Key(u, false, 0))
        down.clear()
    }
}
