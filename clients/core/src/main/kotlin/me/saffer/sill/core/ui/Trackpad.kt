package me.saffer.sill.core.ui

import me.saffer.sill.core.InputEvent
import me.saffer.sill.core.PointerAction
import me.saffer.sill.core.ScrollMomentum
import me.saffer.sill.core.ScrollPhase
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

/**
 * The portrait trackpad's input (TrackpadSurface in TrackpadView.swift, with PadCursor from
 * PointerPresence.swift), written as one state machine over raw touches so the Android app and the
 * Windows client move the Mac's pointer exactly as the iPhone's pad does: relative, 1.25 frames per
 * full swipe across (the vertical measured against [verticalSpan]: a phone's width ÷ 1.6), 2 points
 * of slop before the pointer follows, a tap for a click, two fingers' tap for the right button, a
 * hold of 0.45 s then drag with the button down, two fingers to scroll with the coast, and the key
 * row's latched modifiers pressed around a click or a drag with their own keys.
 *
 * Positions are in points (the platform divides its pixels by its density), times in seconds. Call
 * [tick] at the display's rate while [needsTicks]. Not yet ported: three- and four-finger gestures
 * (TrackpadGestures.swift); a stroke of three fingers sends nothing.
 */
class PadTracker(private val send: (InputEvent) -> Unit) {
    enum class Haptic { Click, DragStart, DragEnd }

    /** The pad's size in points, and what its vertical motion is measured against (null: its height). */
    var width = 1.0
    var height = 1.0
    var verticalSpan: Double? = null
    /** The key row's latched modifiers, read at a click or a drag; [onLatchSpent] clears them. */
    var latched: () -> Long = { 0L }
    var onLatchSpent: () -> Unit = {}
    /** Where the pointer is now (the Mac's arrow, or where this device left it) and a count that
     *  moves whenever something else moved it (PointerPresence's feed). */
    var feed: () -> Pair<Pair<Double, Double>?, Int> = { null to 0 }
    /** This device's own pointer, for the sprite: called with the cursor at every move and click. */
    var onPointer: (Double, Double) -> Unit = { _, _ -> }
    var onHaptic: (Haptic) -> Unit = {}

    /** The virtual cursor, frame fractions 0…1 (PadCursor). */
    var cursorX = 0.5
        private set
    var cursorY = 0.5
        private set
    private var reseedsSeen = 0

    private class Finger(var x: Double, var y: Double, val downX: Double, val downY: Double)
    private val fingers = LinkedHashMap<Int, Finger>()
    private var strokeFingers = 0
    private var strokeAt = 0.0
    private var trackLive = false
    private var trackX = 0.0; private var trackY = 0.0
    private var tapCandidate = false
    private var holdArmed = false
    private var dragging = false
    private var held = 0L
    private var scrolling = false
    private var panLive = false
    private var centroid = 0.0 to 0.0
    private var panTravel = 0.0
    private var vx = 0.0; private var vy = 0.0; private var lastMoveAt = 0.0
    private var momentum: ScrollMomentum? = null
    private var momentumAt = 0.5 to 0.5
    private var lastTick = 0.0
    private var silent = false

    val needsTicks get() = holdArmed || momentum != null
    val isDragging get() = dragging

    private val ySpan get() = verticalSpan?.takeIf { it > 0 } ?: height

    fun down(id: Int, x: Double, y: Double, t: Double) {
        val first = fingers.isEmpty()
        fingers[id] = Finger(x, y, x, y)
        if (first) {
            adopt()
            strokeFingers = 1; strokeAt = t
            trackLive = false; trackX = x; trackY = y
            tapCandidate = true; holdArmed = true
            panLive = false; panTravel = 0.0; silent = false
            centroid = x to y
            vx = 0.0; vy = 0.0; lastMoveAt = t
        } else {
            strokeFingers = max(strokeFingers, fingers.size)
            if (!dragging) holdArmed = false
            if (fingers.size >= 2) stopMomentum()
            if (fingers.size >= 3 && !dragging) { silent = true; if (scrolling) endScroll(null); tapCandidate = false }
            centroid = centre()
            panTravel = 0.0
        }
    }

    fun move(id: Int, x: Double, y: Double, t: Double) {
        val f = fingers[id] ?: return
        val px = f.x; val py = f.y
        f.x = x; f.y = y
        if (hypot(x - f.downX, y - f.downY) > TAP_SLOP) { tapCandidate = false; if (!dragging) holdArmed = false }
        if (silent) return
        if (fingers.size == 1) {
            if (scrolling) endScroll(vx to vy)
            if (!trackLive) {
                if (hypot(x - trackX, y - trackY) <= TRACK_SLOP && strokeFingers == 1) return
                trackLive = true
                if (strokeFingers == 1) { moveCursor(x - trackX, y - trackY); return }
            }
            moveCursor(x - px, y - py)
        } else if (fingers.size == 2) {
            val c = centre()
            val dx = c.first - centroid.first; val dy = c.second - centroid.second
            centroid = c
            panTravel += hypot(dx, dy)
            val dt = t - lastMoveAt
            if (dt > 0) { val a = min(1.0, dt / 0.05); vx += (dx / dt - vx) * a; vy += (dy / dt - vy) * a }
            lastMoveAt = t
            if (!scrolling) { if (panTravel > PAN_SLOP) beginScroll() else return }
            if (dx != 0.0 || dy != 0.0) { catchUp(); send(InputEvent.Scroll(cursorX, cursorY, dx / width, dy / ySpan)) }
        }
    }

    fun up(id: Int, x: Double, y: Double, t: Double) {
        if (fingers[id] == null) return
        move(id, x, y, t)
        fingers.remove(id)
        centroid = if (fingers.isEmpty()) centroid else centre()
        if (scrolling && fingers.size < 2) endScroll(vx to vy)
        if (fingers.isNotEmpty()) { trackLive = true; return }
        holdArmed = false
        if (dragging) {
            dragging = false
            onHaptic(Haptic.DragEnd)
            catchUp(); onPointer(cursorX, cursorY)
            send(InputEvent.Pointer(PointerAction.LEFT_UP, cursorX, cursorY))
            releaseModifiers(); spendLatch()
            return
        }
        if (!silent && tapCandidate && t - strokeAt <= TAP_TIME) {
            when (strokeFingers) {
                1 -> click(PointerAction.LEFT_DOWN, PointerAction.LEFT_UP)
                2 -> click(PointerAction.RIGHT_DOWN, PointerAction.RIGHT_UP)
            }
        }
    }

    /** The system took the touches (a gesture of its own, the view going): no click, no coast. */
    fun cancel() {
        if (scrolling) endScroll(null)
        if (dragging) {
            dragging = false
            send(InputEvent.Pointer(PointerAction.LEFT_UP, cursorX, cursorY))
            releaseModifiers(); spendLatch()
        }
        fingers.clear(); holdArmed = false; tapCandidate = false
    }

    fun tick(t: Double) {
        if (holdArmed && fingers.size == 1 && t - strokeAt >= HOLD) {
            holdArmed = false; tapCandidate = false
            dragging = true
            onHaptic(Haptic.DragStart)
            catchUp(); onPointer(cursorX, cursorY)
            pressModifiers()
            send(InputEvent.Pointer(PointerAction.LEFT_DOWN, cursorX, cursorY))
        }
        val m = momentum
        if (m != null) {
            val step = m.step(if (lastTick == 0.0) 1.0 / 60 else t - lastTick)
            if (step == null) stopMomentum()
            else send(InputEvent.Scroll(momentumAt.first, momentumAt.second, step.first / width, step.second / ySpan))
        }
        lastTick = t
    }

    private fun moveCursor(dx: Double, dy: Double) {
        if (width <= 0 || height <= 0 || (dx == 0.0 && dy == 0.0)) return
        catchUp()
        cursorX = (cursorX + dx / width * TRAVEL).coerceIn(0.0, 1.0)
        cursorY = (cursorY + dy / ySpan * TRAVEL).coerceIn(0.0, 1.0)
        onPointer(cursorX, cursorY)
        send(InputEvent.Pointer(PointerAction.MOVE, cursorX, cursorY))
    }

    private fun click(down: PointerAction, up: PointerAction) {
        onHaptic(Haptic.Click)
        catchUp(); onPointer(cursorX, cursorY)
        pressModifiers()
        send(InputEvent.Pointer(down, cursorX, cursorY))
        send(InputEvent.Pointer(up, cursorX, cursorY))
        releaseModifiers(); spendLatch()
    }

    private fun beginScroll() {
        stopMomentum()
        scrolling = true
        catchUp(); onPointer(cursorX, cursorY)
        send(InputEvent.ScrollGesture(ScrollPhase.BEGAN, cursorX, cursorY))
    }

    private fun endScroll(velocity: Pair<Double, Double>?) {
        scrolling = false
        val at = cursorX to cursorY
        send(InputEvent.ScrollGesture(ScrollPhase.ENDED, at.first, at.second))
        val v = velocity ?: return
        val m = ScrollMomentum.startIfFast(v.first, v.second) ?: return
        momentum = m; momentumAt = at; lastTick = 0.0
        send(InputEvent.ScrollGesture(ScrollPhase.MOMENTUM_BEGAN, at.first, at.second))
        send(InputEvent.Scroll(at.first, at.second, v.first / 60 / width, v.second / 60 / ySpan))
    }

    private fun stopMomentum() {
        if (momentum == null) return
        momentum = null
        send(InputEvent.ScrollGesture(ScrollPhase.MOMENTUM_ENDED, momentumAt.first, momentumAt.second))
    }

    private fun pressModifiers() { held = latched(); KeyRow.down(held).forEach(send) }
    private fun releaseModifiers() { KeyRow.up(held).forEach(send); held = 0L }
    private fun spendLatch() { if (latched() != 0L) onLatchSpent() }

    private fun adopt() {
        val (anchor, reseeds) = feed()
        if (anchor != null) { cursorX = anchor.first.coerceIn(0.0, 1.0); cursorY = anchor.second.coerceIn(0.0, 1.0) }
        reseedsSeen = reseeds
    }

    private fun catchUp() { if (feed().second != reseedsSeen) adopt() }

    private fun centre(): Pair<Double, Double> {
        var x = 0.0; var y = 0.0
        for (f in fingers.values) { x += f.x; y += f.y }
        return (x / fingers.size) to (y / fingers.size)
    }

    companion object {
        /** Frames of travel for a full swipe across the pad (TrackpadSurface.travel). */
        const val TRAVEL = Ui.padTravel
        /** Points a finger travels before the pointer follows (TrackpadSurface.trackSlop). */
        const val TRACK_SLOP = Ui.padTrackSlop
        /** UIKit's tap: the finger within about 10 points of where it landed, up within about a third of a second. */
        const val TAP_SLOP = 10.0
        const val TAP_TIME = 0.35
        /** UIKit's pan hysteresis: two fingers scroll once they have moved about 10 points. */
        const val PAN_SLOP = 10.0
        /** The press-and-hold drag (TrackpadSurface: minimumPressDuration 0.45). */
        const val HOLD = Ui.padHold
    }
}
