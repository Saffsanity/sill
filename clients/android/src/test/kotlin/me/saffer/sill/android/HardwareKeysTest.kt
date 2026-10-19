package me.saffer.sill.android

import me.saffer.sill.core.HidKeys
import me.saffer.sill.core.InputEvent
import me.saffer.sill.core.Modifiers
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** A hardware keyboard on Android (the review's findings 8 and 10). */
class HardwareKeysTest {
    private val sent = ArrayList<InputEvent>()
    private val typed = ArrayList<String>()
    private val keys = HardwareKeys { sent.add(it) }
    // Android key codes, as KeyEvent's constants.
    private val CTRL_LEFT = 113; private val CTRL_RIGHT = 114; private val ENTER = 66; private val TAB = 61; private val A = 29

    @Test fun ctrlIsCommandEitherSideAndComesUpAsItself() {
        keys.down(CTRL_RIGHT, HidKeys.RIGHT_CONTROL, Modifiers.COMMAND, 0) { typed.add(it) }
        keys.down(CTRL_LEFT, HidKeys.LEFT_CONTROL, Modifiers.COMMAND, 0) { typed.add(it) }
        assertTrue(keys.up(CTRL_LEFT, Modifiers.COMMAND))
        assertEquals(listOf(InputEvent.Key(HidKeys.RIGHT_COMMAND, true, Modifiers.COMMAND), InputEvent.Key(HidKeys.LEFT_COMMAND, true, Modifiers.COMMAND),
            InputEvent.Key(HidKeys.LEFT_COMMAND, false, Modifiers.COMMAND)), sent)
    }

    @Test fun keysStillDownAreLetGo() {
        keys.down(CTRL_LEFT, HidKeys.LEFT_CONTROL, Modifiers.COMMAND, 0) { typed.add(it) }
        sent.clear()
        keys.releaseAll()
        assertEquals(listOf(InputEvent.Key(HidKeys.LEFT_COMMAND, false, 0)), sent)
        assertFalse("nothing more comes up", keys.up(CTRL_LEFT, 0))
    }

    @Test fun modifiedReturnAndTabGoAsKeysPlainOnesAsText() {
        keys.down(ENTER, HidKeys.ENTER, Modifiers.SHIFT, '\n'.code) { typed.add(it) }
        keys.up(ENTER, Modifiers.SHIFT)
        keys.down(TAB, HidKeys.TAB, Modifiers.SHIFT, '\t'.code) { typed.add(it) }
        keys.down(ENTER, HidKeys.ENTER, 0, '\n'.code) { typed.add(it) }
        keys.down(A, 0x04, Modifiers.SHIFT, 'A'.code) { typed.add(it) }
        assertEquals(listOf(InputEvent.Key(HidKeys.ENTER, true, Modifiers.SHIFT), InputEvent.Key(HidKeys.ENTER, false, Modifiers.SHIFT),
            InputEvent.Key(HidKeys.TAB, true, Modifiers.SHIFT), InputEvent.Text("\n")), sent)
        assertEquals(listOf("A"), typed)
    }
}
