package me.saffer.sill.host

import kotlin.test.Test
import kotlin.test.assertEquals

/** The grab's rectangle, which input and the pointer share (the review's finding 6). */
class CaptureRectTest {
    private val screen = Rect(0, 0, 1920, 1080)

    @Test fun aWindowOnTheScreenKeepsItsFrameAtEvenSizes() =
        assertEquals(Rect(100, 50, 800, 600), CaptureRect.clip(Rect(100, 50, 801, 601), screen))

    @Test fun aWindowPartlyOffTheLeftIsCutToWhatShows() =
        assertEquals(Rect(0, 100, 900, 700), CaptureRect.clip(Rect(-300, 100, 1200, 700), screen))

    @Test fun aWindowPastTheRightAndBottomEdges() =
        assertEquals(Rect(1500, 800, 420, 280), CaptureRect.clip(Rect(1500, 800, 1000, 1000), screen))

    @Test fun aTapAtTheMiddleOfThePictureLandsAtTheMiddleOfWhatShows() {
        val sink = object : InputSink {
            var at: Pair<Int, Int>? = null
            override fun move(x: Int, y: Int) { at = x to y }
            override fun button(button: Int, down: Boolean) {}
            override fun wheel(dx: Double, dy: Double) {}
            override fun key(usage: Int, down: Boolean) {}
            override fun text(s: String) {}
        }
        val t = InputTranslator(sink, CaptureRect.clip(Rect(-300, 0, 1200, 800), screen))
        assertEquals(449 to 399, t.point(0.5, 0.5))
    }
}
