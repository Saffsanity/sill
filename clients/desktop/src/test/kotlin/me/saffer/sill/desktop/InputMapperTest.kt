package me.saffer.sill.desktop

import me.saffer.sill.core.FrameMapping
import me.saffer.sill.core.HidKeys
import me.saffer.sill.core.InputEvent
import me.saffer.sill.core.Modifiers
import me.saffer.sill.core.PointerAction
import me.saffer.sill.core.ScrollPhase
import java.awt.event.InputEvent as Awt
import java.awt.event.KeyEvent
import java.awt.event.MouseEvent
import java.awt.event.MouseWheelEvent
import javax.swing.JPanel
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** The PC's mouse, wheel and keys as the Mac's input, through real AWT events. */
class InputMapperTest {
    private val view = JPanel()
    private val m = InputMapper().apply { frameRect = FrameMapping.fit(1600.0, 1000.0, 1000.0, 800.0) }   // letterboxed: 1000×625 at y 87.5

    private fun mouse(id: Int, x: Int, y: Int, button: Int = MouseEvent.NOBUTTON) = MouseEvent(view, id, 0, 0, x, y, 1, false, button)
    private fun key(id: Int, code: Int, mods: Int = 0, ch: Char = KeyEvent.CHAR_UNDEFINED, loc: Int = KeyEvent.KEY_LOCATION_STANDARD) =
        KeyEvent(view, id, 0, mods, if (id == KeyEvent.KEY_TYPED) KeyEvent.VK_UNDEFINED else code, ch, if (id == KeyEvent.KEY_TYPED) KeyEvent.KEY_LOCATION_UNKNOWN else loc)

    @Test
    fun clicksAndTheLetterbox() {
        assertEquals(listOf(InputEvent.Pointer(PointerAction.MOVE, 0.5, 0.5), InputEvent.Pointer(PointerAction.LEFT_DOWN, 0.5, 0.5)),
            m.mouse(mouse(MouseEvent.MOUSE_PRESSED, 500, 400, MouseEvent.BUTTON1)))
        assertEquals(emptyList(), m.mouse(mouse(MouseEvent.MOUSE_PRESSED, 500, 20, MouseEvent.BUTTON1)), "a click in the letterbox is no click")
        assertEquals(listOf(InputEvent.Pointer(PointerAction.LEFT_UP, 0.5, 0.0)), m.mouse(mouse(MouseEvent.MOUSE_RELEASED, 500, 20, MouseEvent.BUTTON1)),
            "a release always goes, clamped")
        assertEquals(InputEvent.Pointer(PointerAction.RIGHT_DOWN, 0.0, (712 - 87.5) / 625), m.mouse(mouse(MouseEvent.MOUSE_PRESSED, 0, 712, MouseEvent.BUTTON3)).last())
        assertEquals(listOf(InputEvent.Pointer(PointerAction.MOVE, 1.0, 0.0)), m.mouse(mouse(MouseEvent.MOUSE_DRAGGED, 2000, -50)))
    }

    @Test
    fun theWheelIsAScrollGesture() {
        val w = MouseWheelEvent(view, MouseEvent.MOUSE_WHEEL, 0, 0, 500, 400, 500, 400, 0, false, MouseWheelEvent.WHEEL_UNIT_SCROLL, 3, -1, -1.0)
        val first = m.wheel(w, 1000)
        assertEquals(InputEvent.ScrollGesture(ScrollPhase.BEGAN, 0.5, 0.5), first[0])
        assertEquals(InputEvent.Scroll(0.5, 0.5, 0.0, 40.0 / 625.0), first[1], "away from you: content moves down")
        assertEquals(1, m.wheel(w, 1050).size)
        assertEquals(emptyList(), m.wheelIdle(1100))
        assertEquals(listOf(InputEvent.ScrollGesture(ScrollPhase.ENDED, 0.5, 0.5)), m.wheelIdle(1200))
        val shift = MouseWheelEvent(view, MouseEvent.MOUSE_WHEEL, 0, Awt.SHIFT_DOWN_MASK, 500, 400, 500, 400, 0, false, MouseWheelEvent.WHEEL_UNIT_SCROLL, 3, 1, 1.0)
        val s = m.wheel(shift, 2000)[1] as InputEvent.Scroll
        assertEquals(-40.0 / 1000.0, s.dx); assertEquals(0.0, s.dy)
    }

    @Test
    fun keysAsTextOrKeys() {
        // A letter types as text, whatever the Mac's layout.
        assertEquals(emptyList(), m.keyPressed(key(KeyEvent.KEY_PRESSED, KeyEvent.VK_A)))
        assertEquals(listOf(InputEvent.Text("a")), m.keyTyped(key(KeyEvent.KEY_TYPED, 0, ch = 'a')))
        assertEquals(emptyList(), m.keyReleased(key(KeyEvent.KEY_RELEASED, KeyEvent.VK_A)))
        assertEquals(listOf(InputEvent.Text("\n")), m.keyTyped(key(KeyEvent.KEY_TYPED, 0, ch = '\n')))
        assertEquals(listOf(InputEvent.Text("\u0008")), m.keyTyped(key(KeyEvent.KEY_TYPED, 0, ch = '\b')))
        // Ctrl+C: Ctrl is ⌘ by default; the C goes as a key with ⌘, up as well, and its typed control character is dropped.
        assertEquals(listOf(InputEvent.Key(HidKeys.LEFT_COMMAND, true, Modifiers.COMMAND)), m.keyPressed(key(KeyEvent.KEY_PRESSED, KeyEvent.VK_CONTROL, Awt.CTRL_DOWN_MASK)))
        assertEquals(listOf(InputEvent.Key(0x06, true, Modifiers.COMMAND)), m.keyPressed(key(KeyEvent.KEY_PRESSED, KeyEvent.VK_C, Awt.CTRL_DOWN_MASK)))
        assertEquals(emptyList(), m.keyTyped(key(KeyEvent.KEY_TYPED, 0, Awt.CTRL_DOWN_MASK, '\u0003')))
        assertEquals(listOf(InputEvent.Key(0x06, false, Modifiers.COMMAND)), m.keyReleased(key(KeyEvent.KEY_RELEASED, KeyEvent.VK_C, Awt.CTRL_DOWN_MASK)))
        assertEquals(listOf(InputEvent.Key(HidKeys.LEFT_COMMAND, false, 0)), m.keyReleased(key(KeyEvent.KEY_RELEASED, KeyEvent.VK_CONTROL)))
        // Keys with no text go as keys: arrows, Esc, F5, Delete.
        assertEquals(listOf(InputEvent.Key(HidKeys.LEFT, true, Modifiers.SHIFT)), m.keyPressed(key(KeyEvent.KEY_PRESSED, KeyEvent.VK_LEFT, Awt.SHIFT_DOWN_MASK)))
        assertEquals(listOf(InputEvent.Key(HidKeys.ESCAPE, true, 0)), m.keyPressed(key(KeyEvent.KEY_PRESSED, KeyEvent.VK_ESCAPE)))
        assertEquals(listOf(InputEvent.Key(0x3E, true, 0)), m.keyPressed(key(KeyEvent.KEY_PRESSED, KeyEvent.VK_F5)))
        assertEquals(listOf(InputEvent.Key(HidKeys.DELETE_FORWARD, true, 0)), m.keyPressed(key(KeyEvent.KEY_PRESSED, KeyEvent.VK_DELETE)))
        // AltGr (Ctrl+Alt on Windows) types its character as text: '@' on a German keyboard.
        val altGr = Awt.CTRL_DOWN_MASK or Awt.ALT_DOWN_MASK
        assertEquals(emptyList(), m.keyPressed(key(KeyEvent.KEY_PRESSED, KeyEvent.VK_Q, altGr)))
        assertEquals(listOf(InputEvent.Text("@")), m.keyTyped(key(KeyEvent.KEY_TYPED, 0, altGr, '@')))
        // Focus lost: every key still down comes up.
        val ups = m.releaseAll()
        assertTrue(ups.all { it is InputEvent.Key && !it.down } && ups.size == 4, "$ups")
        // With Ctrl as ⌃, Ctrl+C is a control key.
        val ctrl = InputMapper(me.saffer.sill.core.DesktopModifiers(ctrlIsCommand = false))
        assertEquals(listOf(InputEvent.Key(0x06, true, Modifiers.CONTROL)), ctrl.keyPressed(key(KeyEvent.KEY_PRESSED, KeyEvent.VK_C, Awt.CTRL_DOWN_MASK)))
    }

    /** The review's finding 7: each side's key comes up as itself, both sides held, and on focus lost. */
    @Test
    fun rightSideModifiersComeUpAsThemselves() {
        val right = KeyEvent.KEY_LOCATION_RIGHT; val left = KeyEvent.KEY_LOCATION_LEFT
        assertEquals(listOf(InputEvent.Key(HidKeys.LEFT_COMMAND, true, Modifiers.COMMAND)), m.keyPressed(key(KeyEvent.KEY_PRESSED, KeyEvent.VK_CONTROL, Awt.CTRL_DOWN_MASK, loc = left)))
        assertEquals(listOf(InputEvent.Key(HidKeys.RIGHT_COMMAND, true, Modifiers.COMMAND)), m.keyPressed(key(KeyEvent.KEY_PRESSED, KeyEvent.VK_CONTROL, Awt.CTRL_DOWN_MASK, loc = right)))
        assertEquals(listOf(InputEvent.Key(HidKeys.LEFT_COMMAND, false, Modifiers.COMMAND)), m.keyReleased(key(KeyEvent.KEY_RELEASED, KeyEvent.VK_CONTROL, Awt.CTRL_DOWN_MASK, loc = left)))
        assertEquals(listOf(InputEvent.Key(HidKeys.RIGHT_COMMAND, false, 0)), m.keyReleased(key(KeyEvent.KEY_RELEASED, KeyEvent.VK_CONTROL, loc = right)), "right Ctrl's up after left's")
        m.keyPressed(key(KeyEvent.KEY_PRESSED, KeyEvent.VK_SHIFT, Awt.SHIFT_DOWN_MASK, loc = right))
        assertEquals(listOf(InputEvent.Key(HidKeys.RIGHT_SHIFT, false, 0)), m.releaseAll(), "focus lost lets go of the right Shift, not the left")
    }

    /** The review's finding 10: Return, Tab and Delete with a modifier keep it. */
    @Test
    fun modifiedReturnAndTabGoAsKeys() {
        assertEquals(listOf(InputEvent.Key(HidKeys.ENTER, true, Modifiers.SHIFT)), m.keyPressed(key(KeyEvent.KEY_PRESSED, KeyEvent.VK_ENTER, Awt.SHIFT_DOWN_MASK)))
        assertEquals(emptyList(), m.keyTyped(key(KeyEvent.KEY_TYPED, 0, Awt.SHIFT_DOWN_MASK, '\n')), "no second Return as text")
        assertEquals(listOf(InputEvent.Key(HidKeys.ENTER, false, Modifiers.SHIFT)), m.keyReleased(key(KeyEvent.KEY_RELEASED, KeyEvent.VK_ENTER, Awt.SHIFT_DOWN_MASK)))
        assertEquals(listOf(InputEvent.Key(HidKeys.TAB, true, Modifiers.SHIFT)), m.keyPressed(key(KeyEvent.KEY_PRESSED, KeyEvent.VK_TAB, Awt.SHIFT_DOWN_MASK)))
        assertEquals(emptyList(), m.keyTyped(key(KeyEvent.KEY_TYPED, 0, Awt.SHIFT_DOWN_MASK, '\t')))
        assertEquals(listOf(InputEvent.Key(HidKeys.BACKSPACE, true, Modifiers.OPTION)), m.keyPressed(key(KeyEvent.KEY_PRESSED, KeyEvent.VK_BACK_SPACE, Awt.ALT_DOWN_MASK)))
        // Plain, they stay text, as before.
        assertEquals(emptyList(), m.keyPressed(key(KeyEvent.KEY_PRESSED, KeyEvent.VK_ENTER)))
        assertEquals(listOf(InputEvent.Text("\n")), m.keyTyped(key(KeyEvent.KEY_TYPED, 0, ch = '\n')))
    }

    @Test
    fun everyAwtKeyMapsToAHidUsageOnce() {
        // The table covers what a PC keyboard has, with no two keys on one usage.
        assertEquals(HidKeys.awt.size, HidKeys.awt.values.toSet().size)
        for (vk in listOf(KeyEvent.VK_A, KeyEvent.VK_Z, KeyEvent.VK_0, KeyEvent.VK_9, KeyEvent.VK_MINUS, KeyEvent.VK_EQUALS, KeyEvent.VK_OPEN_BRACKET,
            KeyEvent.VK_CLOSE_BRACKET, KeyEvent.VK_BACK_SLASH, KeyEvent.VK_SEMICOLON, KeyEvent.VK_QUOTE, KeyEvent.VK_BACK_QUOTE, KeyEvent.VK_COMMA,
            KeyEvent.VK_PERIOD, KeyEvent.VK_SLASH, KeyEvent.VK_F1, KeyEvent.VK_F12, KeyEvent.VK_HOME, KeyEvent.VK_END, KeyEvent.VK_PAGE_UP,
            KeyEvent.VK_PAGE_DOWN, KeyEvent.VK_INSERT, KeyEvent.VK_CAPS_LOCK, KeyEvent.VK_ENTER, KeyEvent.VK_BACK_SPACE, KeyEvent.VK_TAB, KeyEvent.VK_SPACE)) {
            assertTrue(HidKeys.awt.containsKey(vk), "VK $vk")
        }
        assertEquals(0x04, HidKeys.awt[KeyEvent.VK_A]); assertEquals(0x27, HidKeys.awt[KeyEvent.VK_0]); assertEquals(0x45, HidKeys.awt[KeyEvent.VK_F12])
    }
}
