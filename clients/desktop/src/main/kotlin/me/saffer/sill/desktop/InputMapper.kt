package me.saffer.sill.desktop

import me.saffer.sill.core.DesktopModifiers
import me.saffer.sill.core.FrameMapping
import me.saffer.sill.core.HidKeys
import me.saffer.sill.core.InputEvent
import me.saffer.sill.core.PointerAction
import me.saffer.sill.core.ScrollPhase
import java.awt.event.InputEvent as AwtInputEvent
import java.awt.event.KeyEvent
import java.awt.event.MouseEvent
import java.awt.event.MouseWheelEvent

/**
 * The PC's mouse, wheel and keyboard as the Mac's input (InputOverlay.swift's rules, for a mouse and
 * a keyboard): clicks at frame fractions (none in the letterbox), drags and moves clamped to the
 * edge, the wheel as a trackpad-like scroll gesture (began, deltas, ended after a pause, so the Mac's
 * apps rubber-band), keys as keys or as text by [HidKeys]' rule. Pure: it returns what to send.
 */
class InputMapper(val modifiers: DesktopModifiers = DesktopModifiers()) {
    /** Where the frame is drawn in the view, in the view's coordinates. */
    var frameRect = FrameMapping.Rect(0.0, 0.0, 1.0, 1.0)
    /** Keys sent down, by AWT key code and side, with the usage sent: each up names what its down did. */
    private val keysDown = HashMap<Pair<Int, Int>, Int>()
    private var scrolling = false
    private var lastWheelAt = 0L
    private var lastScrollPoint = 0.5 to 0.5
    /** Points per wheel notch, as a mouse moves content on the Mac. */
    var pointsPerNotch = 40.0

    fun mouse(e: MouseEvent): List<InputEvent> {
        val clampedPoint = FrameMapping.toFrame(e.x.toDouble(), e.y.toDouble(), frameRect, clamped = true)!!
        val (x, y) = clampedPoint
        return when (e.id) {
            MouseEvent.MOUSE_MOVED, MouseEvent.MOUSE_DRAGGED -> listOf(InputEvent.Pointer(PointerAction.MOVE, x, y))
            MouseEvent.MOUSE_PRESSED -> {
                val p = FrameMapping.toFrame(e.x.toDouble(), e.y.toDouble(), frameRect, clamped = false) ?: return emptyList()
                when (e.button) {
                    MouseEvent.BUTTON1 -> listOf(InputEvent.Pointer(PointerAction.MOVE, p.first, p.second), InputEvent.Pointer(PointerAction.LEFT_DOWN, p.first, p.second))
                    MouseEvent.BUTTON3 -> listOf(InputEvent.Pointer(PointerAction.MOVE, p.first, p.second), InputEvent.Pointer(PointerAction.RIGHT_DOWN, p.first, p.second))
                    else -> emptyList()
                }
            }
            // A release always goes (clamped), so no button stays down on the Mac.
            MouseEvent.MOUSE_RELEASED -> when (e.button) {
                MouseEvent.BUTTON1 -> listOf(InputEvent.Pointer(PointerAction.LEFT_UP, x, y))
                MouseEvent.BUTTON3 -> listOf(InputEvent.Pointer(PointerAction.RIGHT_UP, x, y))
                else -> emptyList()
            }
            else -> emptyList()
        }
    }

    /** A wheel event: the gesture begins with the first, then deltas (natural sign: away from you moves content down). */
    fun wheel(e: MouseWheelEvent, nowMs: Long = System.currentTimeMillis()): List<InputEvent> {
        val (x, y) = FrameMapping.toFrame(e.x.toDouble(), e.y.toDouble(), frameRect, clamped = true)!!
        val out = ArrayList<InputEvent>()
        if (!scrolling) { out.add(InputEvent.ScrollGesture(ScrollPhase.BEGAN, x, y)); scrolling = true }
        lastWheelAt = nowMs
        lastScrollPoint = x to y
        val points = -e.preciseWheelRotation * pointsPerNotch
        val horizontal = e.isShiftDown || e.modifiersEx and AwtInputEvent.SHIFT_DOWN_MASK != 0
        val dx = if (horizontal) points / frameRect.w else 0.0
        val dy = if (horizontal) 0.0 else points / frameRect.h
        out.add(InputEvent.Scroll(x, y, dx, dy))
        return out
    }

    /** The scroll gesture's end, once the wheel has been still for [WHEEL_END_MS]; call on a timer. */
    fun wheelIdle(nowMs: Long = System.currentTimeMillis()): List<InputEvent> {
        if (!scrolling || nowMs - lastWheelAt < WHEEL_END_MS) return emptyList()
        scrolling = false
        return listOf(InputEvent.ScrollGesture(ScrollPhase.ENDED, lastScrollPoint.first, lastScrollPoint.second))
    }

    fun keyPressed(e: KeyEvent): List<InputEvent> {
        val bits = modifiers.bits(e.modifiersEx)
        val side = e.keyCode to e.keyLocation
        modifiers.usage(e.keyCode, e.keyLocation == KeyEvent.KEY_LOCATION_RIGHT)?.let { usage ->
            keysDown[side] = usage
            return listOf(InputEvent.Key(usage, true, bits))
        }
        val usage = HidKeys.awt[e.keyCode] ?: return emptyList()
        val altGr = altGr(e)
        // Return, Tab and Delete with a modifier (⇧Return in Messages, ⇧Tab) go as keys, so the Mac sees
        // the modifier: as text the Mac types them with its modifiers cleared.
        if (HidKeys.isRaw(usage) || (HidKeys.isShortcut(bits) && !altGr) || (usage in EDIT_KEYS && bits != 0L && !altGr)) {
            keysDown[side] = usage
            return listOf(InputEvent.Key(usage, true, bits))
        }
        return emptyList()
    }

    fun keyReleased(e: KeyEvent): List<InputEvent> {
        val usage = keysDown.remove(e.keyCode to e.keyLocation) ?: return emptyList()
        return listOf(InputEvent.Key(usage, false, modifiers.bits(e.modifiersEx)))
    }

    // Ctrl and Alt together is Windows' AltGr: the character it types goes as text.
    private fun altGr(e: KeyEvent) = e.modifiersEx and (AwtInputEvent.CTRL_DOWN_MASK or AwtInputEvent.ALT_DOWN_MASK) == (AwtInputEvent.CTRL_DOWN_MASK or AwtInputEvent.ALT_DOWN_MASK) ||
        e.modifiersEx and AwtInputEvent.ALT_GRAPH_DOWN_MASK != 0

    fun keyTyped(e: KeyEvent): List<InputEvent> {
        val c = e.keyChar
        if (c == KeyEvent.CHAR_UNDEFINED) return emptyList()
        val bits = modifiers.bits(e.modifiersEx)
        val altGr = altGr(e)
        if (HidKeys.isShortcut(bits) && !altGr) return emptyList()       // went as a key
        if (c in "\n\r\t\b" && bits != 0L && !altGr) return emptyList()  // went as a key with its modifier
        return when (c) {
            '\n', '\r' -> listOf(InputEvent.Text("\n"))
            '\t' -> listOf(InputEvent.Text("\t"))
            '\b' -> listOf(InputEvent.Text("\u0008"))
            else -> if (c < ' ' || c == '\u007F') emptyList() else listOf(InputEvent.Text(c.toString()))
        }
    }

    /** Every key this mapper sent down, let go: the window lost focus, so no key stays down on the Mac. */
    fun releaseAll(): List<InputEvent> {
        val out = keysDown.values.map { InputEvent.Key(it, false, 0) }
        keysDown.clear()
        return out
    }

    companion object {
        const val WHEEL_END_MS = 120L
        private val EDIT_KEYS = setOf(HidKeys.ENTER, HidKeys.TAB, HidKeys.BACKSPACE)
    }
}
