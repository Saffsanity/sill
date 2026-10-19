package me.saffer.sill.core.ui

import me.saffer.sill.core.HidKeys
import me.saffer.sill.core.InputEvent
import me.saffer.sill.core.Modifiers

/**
 * The portrait key row (KeyRow in PortraitStreamScreen.swift) and the shortcuts it sends
 * (KeyChords.swift): which caps, in which rows, and the events a tap sends, as a keyboard sends
 * them, each modifier's own key around the key.
 */
object KeyRow {
    sealed class Key {
        abstract val label: String
        /** A key that types itself: the cap's word and its HID usage. */
        data class Press(val title: String, val usage: Int, override val label: String) : Key()
        /** An arrow: which way, and its usage. */
        data class Arrow(val direction: Direction, val usage: Int, override val label: String) : Key()
        /** A latching modifier: the cap's word and the bit it holds. */
        data class Modifier(val title: String, val bit: Long, override val label: String) : Key()
        data object Keyboard : Key() { override val label = "Show the keyboard" }
        data object Spotlight : Key() { override val label = "Open Spotlight on the Mac" }
    }

    enum class Direction { Left, Down, Up, Right }

    val all: List<Key> = listOf(
        Key.Press("esc", HidKeys.ESCAPE, "Escape"),
        Key.Press("tab", HidKeys.TAB, "Tab"),
        Key.Modifier("ctrl", Modifiers.CONTROL, "Control"),
        Key.Modifier("opt", Modifiers.OPTION, "Option"),
        Key.Modifier("cmd", Modifiers.COMMAND, "Command"),
        Key.Modifier("shift", Modifiers.SHIFT, "Shift"),
        Key.Arrow(Direction.Left, HidKeys.LEFT, "Left arrow"),
        Key.Arrow(Direction.Down, HidKeys.DOWN, "Down arrow"),
        Key.Arrow(Direction.Up, HidKeys.UP, "Up arrow"),
        Key.Arrow(Direction.Right, HidKeys.RIGHT, "Right arrow"),
        Key.Keyboard,
        Key.Spotlight,
    )

    /** A phone's six: the keys that name a key. */
    val phone: List<Key> = all.take(6)

    /** The halves' twelve, Spotlight only while the Desktop streams (its panel is its own window). */
    fun full(spotlight: Boolean) = if (spotlight) all else all.filter { it != Key.Spotlight }

    /** One row, or the compact halves' two: the six that name a key, then the rest. */
    fun rows(keys: List<Key>, split: Boolean) = if (split) listOf(keys.take(6), keys.drop(6)) else listOf(keys)

    /** The latch after a tap on a modifier cap. */
    fun toggle(latched: Long, key: Key.Modifier) = latched xor key.bit

    /** A key with `modifiers`, as a keyboard sends it (KeyChord.press). */
    fun press(usage: Int, modifiers: Long): List<InputEvent> =
        down(modifiers) + listOf(InputEvent.Key(usage, true, modifiers), InputEvent.Key(usage, false, modifiers)) + up(modifiers)

    /** Spotlight: exactly ⌘Space, whatever is latched. */
    val spotlight: List<InputEvent> get() = press(HidKeys.SPACE, Modifiers.COMMAND)

    private val order = listOf(Modifiers.CONTROL to HidKeys.LEFT_CONTROL, Modifiers.SHIFT to HidKeys.LEFT_SHIFT,
        Modifiers.OPTION to HidKeys.LEFT_OPTION, Modifiers.COMMAND to HidKeys.LEFT_COMMAND)

    fun down(modifiers: Long): List<InputEvent> {
        var held = 0L
        return order.filter { modifiers and it.first != 0L }.map { (bit, usage) -> held = held or bit; InputEvent.Key(usage, true, held) }
    }

    fun up(modifiers: Long): List<InputEvent> {
        var held = modifiers
        return order.filter { modifiers and it.first != 0L }.reversed().map { (bit, usage) -> held = held and bit.inv(); InputEvent.Key(usage, false, held) }
    }

    /** What a tap on `key` sends, with `latched` held, and the latch after it. */
    fun tap(key: Key, latched: Long): Pair<List<InputEvent>, Long> = when (key) {
        is Key.Press -> press(key.usage, latched) to 0L
        is Key.Arrow -> press(key.usage, latched) to 0L
        is Key.Modifier -> emptyList<InputEvent>() to toggle(latched, key)
        Key.Keyboard -> emptyList<InputEvent>() to latched
        Key.Spotlight -> spotlight to 0L
    }
}
