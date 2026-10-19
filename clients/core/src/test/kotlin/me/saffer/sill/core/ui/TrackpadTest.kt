package me.saffer.sill.core.ui

import me.saffer.sill.core.InputEvent
import me.saffer.sill.core.Modifiers
import me.saffer.sill.core.PointerAction
import me.saffer.sill.core.ScrollPhase
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** The trackpad's port against TrackpadSurface's rules (TrackpadView.swift). */
class TrackpadTest {
    private val sent = ArrayList<InputEvent>()
    private val pad = PadTracker { sent += it }.apply { width = 400.0; height = 300.0; verticalSpan = 250.0 }
    private fun pointers() = sent.filterIsInstance<InputEvent.Pointer>()

    @Test fun aTapClicksWhereThePointerIs() {
        pad.feed = { (0.2 to 0.3) to 1 }
        pad.down(1, 100.0, 100.0, 0.0); pad.up(1, 101.0, 100.0, 0.1)
        assertEquals(listOf(PointerAction.LEFT_DOWN, PointerAction.LEFT_UP), pointers().map { it.action })
        assertEquals(0.2, pointers()[0].x); assertEquals(0.3, pointers()[0].y)
    }

    @Test fun aStrokeMovesRelativelyPastTheSlop() {
        pad.down(1, 100.0, 100.0, 0.0)
        pad.move(1, 101.5, 100.0, 0.01)                   // inside the 2 pt slop: nothing
        assertTrue(sent.isEmpty())
        pad.move(1, 140.0, 150.0, 0.05)                   // past it: the whole distance from touch-down
        val m = pointers().single()
        assertEquals(PointerAction.MOVE, m.action)
        assertEquals(0.5 + 40.0 / 400 * 1.25, m.x, 1e-9)
        assertEquals(0.5 + 50.0 / 250 * 1.25, m.y, 1e-9)  // measured against the vertical span
        pad.up(1, 140.0, 150.0, 0.5)
        assertEquals(1, pointers().size)                   // no click after a stroke
    }

    @Test fun holdThenDragKeepsTheButtonDownWithTheLatch() {
        var latch = Modifiers.COMMAND
        pad.latched = { latch }; pad.onLatchSpent = { latch = 0 }
        pad.down(1, 100.0, 100.0, 0.0)
        pad.tick(0.5)
        assertTrue(pad.isDragging)
        pad.move(1, 160.0, 100.0, 0.6)
        pad.up(1, 160.0, 100.0, 0.7)
        val keys = sent.filterIsInstance<InputEvent.Key>()
        assertEquals(listOf(0xE3, 0xE3), keys.map { it.hidUsage }); assertEquals(listOf(true, false), keys.map { it.down })
        assertEquals(listOf(PointerAction.LEFT_DOWN, PointerAction.MOVE, PointerAction.LEFT_UP), pointers().map { it.action })
        assertEquals(0L, latch)
    }

    @Test fun twoFingersScrollAndCoast() {
        pad.down(1, 100.0, 100.0, 0.0); pad.down(2, 140.0, 100.0, 0.01)
        for (i in 1..10) { pad.move(1, 100.0, 100.0 + i * 8, 0.01 + i * 0.01); pad.move(2, 140.0, 100.0 + i * 8, 0.01 + i * 0.01) }
        pad.up(1, 100.0, 180.0, 0.12); pad.up(2, 140.0, 180.0, 0.12)
        val phases = sent.filterIsInstance<InputEvent.ScrollGesture>().map { it.phase }
        assertEquals(listOf(ScrollPhase.BEGAN, ScrollPhase.ENDED, ScrollPhase.MOMENTUM_BEGAN), phases)
        assertTrue(sent.filterIsInstance<InputEvent.Scroll>().all { it.dy > 0 })
        assertTrue(pointers().isEmpty())                   // no click, no pointer motion
        var t = 0.13
        while (pad.needsTicks && t < 5) { pad.tick(t); t += 1.0 / 60 }
        assertEquals(ScrollPhase.MOMENTUM_ENDED, sent.filterIsInstance<InputEvent.ScrollGesture>().last().phase)
    }

    @Test fun twoFingersTapForTheRightButton() {
        pad.down(1, 100.0, 100.0, 0.0); pad.down(2, 130.0, 100.0, 0.02)
        pad.up(1, 100.0, 100.0, 0.1); pad.up(2, 130.0, 100.0, 0.11)
        assertEquals(listOf(PointerAction.RIGHT_DOWN, PointerAction.RIGHT_UP), pointers().map { it.action })
    }

    @Test fun threeFingersSendNothing() {
        pad.down(1, 100.0, 100.0, 0.0); pad.down(2, 130.0, 100.0, 0.01); pad.down(3, 160.0, 100.0, 0.02)
        for (i in 1..5) for (id in 1..3) pad.move(id, 100.0 + id * 30, 100.0 - i * 20, 0.02 + i * 0.02)
        for (id in 1..3) pad.up(id, 100.0 + id * 30, 0.0, 0.2)
        assertTrue(sent.isEmpty(), "$sent")
    }
}
