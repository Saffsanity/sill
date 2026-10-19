package me.saffer.sill.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertTrue

/** Fingers as the Mac's input: tap, long press, scroll, the coast, two fingers, the letterbox. */
class TouchGesturesTest {
    private val out = ArrayList<InputEvent>()
    private val g = TouchGestures(density = 2.0) { out.add(it) }.apply { frameRect = FrameMapping.Rect(0.0, 100.0, 1000.0, 600.0) }

    @Test
    fun aTapClicksWhereItLands() {
        g.down(0, 500.0, 400.0, 0.0); g.move(0, 504.0, 402.0, 0.05); g.up(0, 504.0, 402.0, 0.1)
        assertEquals(listOf<InputEvent>(InputEvent.Pointer(PointerAction.MOVE, 0.5, 0.5), InputEvent.Pointer(PointerAction.LEFT_DOWN, 0.5, 0.5),
            InputEvent.Pointer(PointerAction.LEFT_UP, 0.5, 0.5)), out)
        out.clear()
        g.down(0, 500.0, 50.0, 1.0); g.up(0, 500.0, 50.0, 1.1)
        assertEquals(emptyList<InputEvent>(), out, "a tap in the letterbox clicks nothing")
    }

    @Test
    fun aLongPressRightClicksOnce() {
        g.down(0, 250.0, 250.0, 0.0)
        g.tick(0.3)
        assertEquals(emptyList<InputEvent>(), out)
        g.tick(0.46)
        assertEquals(listOf(PointerAction.MOVE, PointerAction.RIGHT_DOWN, PointerAction.RIGHT_UP), out.map { (it as InputEvent.Pointer).action })
        g.move(0, 400.0, 400.0, 0.6); g.up(0, 400.0, 400.0, 0.7)
        assertEquals(3, out.size, "nothing more for that finger")
    }

    @Test
    fun aDragScrollsAndCoasts() {
        g.down(0, 500.0, 400.0, 0.0)
        var t = 0.0
        var y = 400.0
        repeat(10) { t += 0.016; y += 30.0; g.move(0, 500.0, y, t) }
        assertEquals(InputEvent.ScrollGesture(ScrollPhase.BEGAN, 0.5, (430.0 - 100) / 600), out[0])
        val scrolls = out.filterIsInstance<InputEvent.Scroll>()
        assertTrue(scrolls.all { it.dy > 0 && it.dx == 0.0 }, "finger down: content moves down (natural sign)")
        assertEquals((y - 430.0) / 600, scrolls.sumOf { it.dy }, 1e-9)
        out.clear()
        g.up(0, 500.0, y, t)
        assertIs<InputEvent.ScrollGesture>(out[0]).also { assertEquals(ScrollPhase.ENDED, it.phase) }
        assertEquals(ScrollPhase.MOMENTUM_BEGAN, (out[1] as InputEvent.ScrollGesture).phase)
        assertTrue(g.needsTicks)
        var n = 0
        while (g.needsTicks && n < 1000) { t += 1.0 / 60; g.tick(t); n++ }
        assertEquals(ScrollPhase.MOMENTUM_ENDED, (out.last() as InputEvent.ScrollGesture).phase)
        val coast = out.filterIsInstance<InputEvent.Scroll>()
        assertTrue(coast.size > 20 && coast.zipWithNext().all { (a, b) -> b.dy <= a.dy }, "a decaying coast of ${coast.size} steps")
    }

    @Test
    fun aSlowLiftHasNoCoastAndANewTouchStopsOne() {
        g.down(0, 500.0, 400.0, 0.0); g.move(0, 500.0, 460.0, 0.5); g.up(0, 500.0, 460.0, 1.5)
        assertEquals(ScrollPhase.ENDED, (out.last() as InputEvent.ScrollGesture).phase)
        out.clear()
        g.down(0, 500.0, 400.0, 2.0)
        var t = 2.0
        repeat(5) { t += 0.016; g.move(0, 500.0, 400.0 + 40.0 * (it + 1), t) }
        g.up(0, 500.0, 600.0, t)
        assertTrue(out.any { it is InputEvent.ScrollGesture && it.phase == ScrollPhase.MOMENTUM_BEGAN })
        g.down(1, 100.0, 100.0, t + 0.05)
        assertEquals(ScrollPhase.MOMENTUM_ENDED, (out.last() as InputEvent.ScrollGesture).phase)
    }

    @Test
    fun twoFingersScrollAtTheirCentroid() {
        g.down(0, 400.0, 400.0, 0.0); g.down(1, 600.0, 400.0, 0.01)
        assertEquals(InputEvent.ScrollGesture(ScrollPhase.BEGAN, 0.5, 0.5), out[0])
        g.move(0, 400.0, 340.0, 0.03); g.move(1, 600.0, 340.0, 0.03)
        val s = out.filterIsInstance<InputEvent.Scroll>()
        assertEquals(-60.0 / 600, s.sumOf { it.dy }, 1e-9)
        g.up(0, 400.0, 340.0, 0.5); g.up(1, 600.0, 340.0, 0.6)
        assertEquals(ScrollPhase.ENDED, (out.last() as InputEvent.ScrollGesture).phase)
        assertTrue(out.none { it is InputEvent.Pointer }, "two fingers never click")
    }
}
