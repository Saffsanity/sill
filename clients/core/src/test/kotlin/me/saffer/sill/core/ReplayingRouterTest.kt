package me.saffer.sill.core

import kotlin.test.Test
import kotlin.test.assertEquals

/** A screen that attaches late gets the latest catalog and the video since the last keyframe, in order. */
class ReplayingRouterTest {
    @Test
    fun replayOnAttach() {
        val r = ReplayingRouter(maxFrames = 3)
        val sets = ModelHost.defaultVideo().first
        r.onWindowList(WindowList("Mac", listOf(WindowInfo(1, "a", "A", "a", 1, 1)), StreamSource.Desktop))
        r.onThumbnail(1, byteArrayOf(1)); r.onThumbnail(2, byteArrayOf(2))
        r.onWindowList(WindowList("Mac", listOf(WindowInfo(1, "a", "A", "a", 1, 1)), StreamSource.Desktop))   // window 2 went
        r.onVideoFormat(sets)
        r.onFrame(byteArrayOf(10), true, 0.0); r.onFrame(byteArrayOf(11), false, 0.0)
        r.onFrame(byteArrayOf(20), true, 0.0); r.onFrame(byteArrayOf(21), false, 0.0); r.onFrame(byteArrayOf(22), false, 0.0); r.onFrame(byteArrayOf(23), false, 0.0)
        val seen = ArrayList<String>()
        r.attach(object : SessionListener {
            override fun onWindowList(list: WindowList) { seen.add("list") }
            override fun onThumbnail(windowID: Long, jpeg: ByteArray) { seen.add("thumb $windowID") }
            override fun onVideoFormat(sets: ParameterSets) { seen.add("format") }
            override fun onFrame(annexB: ByteArray, keyframe: Boolean, timestamp: Double) { seen.add("frame ${annexB[0]}") }
            override fun onMacPointer(position: Pair<Double, Double>?) { seen.add("pointer") }
        })
        assertEquals(listOf("list", "thumb 1", "format", "frame 20", "frame 21", "frame 22", "pointer"), seen)
        r.onFrame(byteArrayOf(24), false, 0.0)
        assertEquals("frame 24", seen.last())
        r.reset()
        val again = ArrayList<String>()
        r.attach(object : SessionListener { override fun onFrame(annexB: ByteArray, keyframe: Boolean, timestamp: Double) { again.add("x") } })
        assertEquals(emptyList<String>(), again)
    }
}
