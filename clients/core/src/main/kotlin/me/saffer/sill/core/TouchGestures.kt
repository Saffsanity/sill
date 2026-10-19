package me.saffer.sill.core

/**
 * Fingers on the picture as the Mac's input (InputOverlay.swift's direct touch, for Android): a tap
 * clicks where it lands (none in the letterbox); a finger held 0.45 s without moving right-clicks;
 * one or two fingers that move scroll, as a trackpad gesture (began, deltas at the centroid, ended)
 * followed by the coast ([ScrollMomentum]) when they lift fast. A new touch stops a coast.
 *
 * Platform-neutral: positions in the view's pixels, times in seconds, `density` the view's pixels
 * per point (the coast's thresholds are in points). [tick] runs the long press and the coast; call
 * it at the display's rate while [needsTicks].
 */
class TouchGestures(private val density: Double = 1.0, private val send: (InputEvent) -> Unit) {
    var frameRect = FrameMapping.Rect(0.0, 0.0, 1.0, 1.0)

    private enum class Mode { IDLE, PENDING, SCROLLING, DONE }
    private var mode = Mode.IDLE
    private val points = LinkedHashMap<Int, Pair<Double, Double>>()
    private var downAt = 0.0
    private var downPoint = 0.0 to 0.0
    private var lastCentroid = 0.0 to 0.0
    private var momentum: ScrollMomentum? = null
    private var momentumPoint = 0.5 to 0.5
    private var lastTick = 0.0
    // Velocity in view pixels per second, from the last moves (a short exponential average).
    private var vx = 0.0; private var vy = 0.0; private var lastMoveAt = 0.0

    val needsTicks get() = mode == Mode.PENDING || momentum != null

    fun down(id: Int, x: Double, y: Double, t: Double) {
        stopMomentum()
        points[id] = x to y
        if (points.size == 1) {
            mode = Mode.PENDING
            downAt = t; downPoint = x to y
            lastCentroid = x to y
            vx = 0.0; vy = 0.0; lastMoveAt = t
        } else {
            // A second finger: no tap or long press; it can still scroll.
            if (mode == Mode.PENDING) mode = Mode.SCROLLING.also { beginScroll() }
            lastCentroid = centroid()
        }
    }

    fun move(id: Int, x: Double, y: Double, t: Double) {
        if (id !in points) return
        points[id] = x to y
        if (mode == Mode.DONE || mode == Mode.IDLE) return
        val c = centroid()
        if (mode == Mode.PENDING) {
            if (kotlin.math.hypot(x - downPoint.first, y - downPoint.second) < SLOP_POINTS * density) return
            mode = Mode.SCROLLING
            beginScroll()
        }
        val dx = c.first - lastCentroid.first
        val dy = c.second - lastCentroid.second
        val dt = (t - lastMoveAt).coerceAtLeast(1e-3)
        vx = 0.6 * (dx / dt) + 0.4 * vx; vy = 0.6 * (dy / dt) + 0.4 * vy
        lastMoveAt = t
        lastCentroid = c
        val (fx, fy) = FrameMapping.toFrame(c.first, c.second, frameRect, clamped = true)!!
        if (dx != 0.0 || dy != 0.0) send(InputEvent.Scroll(fx, fy, dx / frameRect.w, dy / frameRect.h))
    }

    fun up(id: Int, x: Double, y: Double, t: Double) {
        if (id !in points) return
        points[id] = x to y
        val wasLast = points.size == 1
        if (!wasLast) { points.remove(id); lastCentroid = centroid(); return }
        points.remove(id)
        when (mode) {
            Mode.PENDING -> FrameMapping.toFrame(downPoint.first, downPoint.second, frameRect, clamped = false)?.let { (fx, fy) ->
                send(InputEvent.Pointer(PointerAction.MOVE, fx, fy))
                send(InputEvent.Pointer(PointerAction.LEFT_DOWN, fx, fy))
                send(InputEvent.Pointer(PointerAction.LEFT_UP, fx, fy))
            }
            Mode.SCROLLING -> {
                val (fx, fy) = FrameMapping.toFrame(x, y, frameRect, clamped = true)!!
                send(InputEvent.ScrollGesture(ScrollPhase.ENDED, fx, fy))
                // A finger that stopped before lifting has no coast.
                val stale = t - lastMoveAt > 0.1
                val m = if (stale) null else ScrollMomentum.startIfFast(vx / density, vy / density)
                if (m != null) {
                    momentum = m
                    momentumPoint = fx to fy
                    lastTick = t
                    send(InputEvent.ScrollGesture(ScrollPhase.MOMENTUM_BEGAN, fx, fy))
                    // The coast's first step at once, a frame's worth (InputOverlay.swift).
                    m.step(1.0 / 60)?.let { (sx, sy) -> send(InputEvent.Scroll(fx, fy, sx * density / frameRect.w, sy * density / frameRect.h)) }
                }
            }
            else -> {}
        }
        mode = Mode.IDLE
    }

    /** The system took the touches (a gesture of its own): close what was open, click nothing. */
    fun cancel() {
        if (mode == Mode.SCROLLING) {
            val (fx, fy) = FrameMapping.toFrame(lastCentroid.first, lastCentroid.second, frameRect, clamped = true)!!
            send(InputEvent.ScrollGesture(ScrollPhase.ENDED, fx, fy))
        }
        points.clear()
        mode = Mode.IDLE
    }

    fun tick(t: Double) {
        if (mode == Mode.PENDING && points.size == 1 && t - downAt >= LONG_PRESS) {
            FrameMapping.toFrame(downPoint.first, downPoint.second, frameRect, clamped = false)?.let { (fx, fy) ->
                send(InputEvent.Pointer(PointerAction.MOVE, fx, fy))
                send(InputEvent.Pointer(PointerAction.RIGHT_DOWN, fx, fy))
                send(InputEvent.Pointer(PointerAction.RIGHT_UP, fx, fy))
            }
            mode = Mode.DONE
        }
        val m = momentum ?: return
        val step = m.step(t - lastTick)
        lastTick = t
        if (step == null) { stopMomentum(); return }
        // The coast's points, in view pixels, as fractions of the frame.
        send(InputEvent.Scroll(momentumPoint.first, momentumPoint.second, step.first * density / frameRect.w, step.second * density / frameRect.h))
    }

    private fun beginScroll() {
        val c = centroid()
        val (fx, fy) = FrameMapping.toFrame(c.first, c.second, frameRect, clamped = true)!!
        send(InputEvent.ScrollGesture(ScrollPhase.BEGAN, fx, fy))
        lastCentroid = c
    }

    private fun stopMomentum() {
        if (momentum == null) return
        momentum = null
        send(InputEvent.ScrollGesture(ScrollPhase.MOMENTUM_ENDED, momentumPoint.first, momentumPoint.second))
    }

    private fun centroid(): Pair<Double, Double> {
        if (points.isEmpty()) return lastCentroid
        return points.values.sumOf { it.first } / points.size to points.values.sumOf { it.second } / points.size
    }

    companion object {
        const val LONG_PRESS = 0.45
        /** How far a finger moves, in points, before it scrolls rather than taps. */
        const val SLOP_POINTS = 10.0
    }
}
