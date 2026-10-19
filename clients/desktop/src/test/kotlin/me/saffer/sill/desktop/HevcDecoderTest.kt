package me.saffer.sill.desktop

import me.saffer.sill.core.AccessUnit
import me.saffer.sill.core.HevcSample
import me.saffer.sill.core.StreamMessage
import me.saffer.sill.core.VideoGate
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

/** The decoder against real HEVC from libx265, delivered as the Mac delivers VideoToolbox's (the wire's shape). */
class HevcDecoderTest {
    @Test
    fun aFlatColourDecodesToThatColour() {
        val (sets, aus) = HevcSample.load("sample-color.hevc")
        assertEquals(3, sets.sets.size)
        assertEquals(listOf(32, 33, 34), sets.sets.map { (it[0].toInt() shr 1) and 0x3F })
        assertTrue(aus.first().first, "the first access unit is the keyframe")
        HevcDecoder(preferHardware = false).use { d ->
            d.configure(sets)
            var pictures = 0
            for ((_, au) in aus) {
                val p = d.decode(AccessUnit.toAnnexB(au, 4)!!) ?: continue
                pictures++
                assertEquals(320, p.width); assertEquals(240, p.height)
                val c = p.pixels[p.width * 120 + 160]
                val (r, g, b) = Triple(c shr 16 and 0xFF, c shr 8 and 0xFF, c and 0xFF)
                // 0x3366CC through 4:2:0 and back: within a few steps.
                assertTrue(abs(r - 0x33) <= 6 && abs(g - 0x66) <= 6 && abs(b - 0xCC) <= 6, "pixel %02x%02x%02x".format(r, g, b))
            }
            assertEquals(aus.size, pictures, "one picture per access unit, none held back")
        }
    }

    @Test
    fun aMovingPictureAtAWindowsOddSizeScaledToTheView() {
        val (sets, aus) = HevcSample.load("sample-motion.hevc")
        assertEquals(30, aus.size)
        HevcDecoder(preferHardware = false).use { d ->
            d.configure(sets)
            val sums = ArrayList<Long>()
            for ((_, au) in aus) {
                val p = assertNotNull(d.decode(AccessUnit.toAnnexB(au, 4)!!, 400, 260), "every access unit gives its picture at once")
                assertEquals(400 * 260, p.pixels.size)
                sums.add(p.pixels.fold(0L) { s, v -> s + (v and 0xFFFFFF) })
            }
            assertEquals(642, d.videoWidth); assertEquals(418, d.videoHeight)
            assertTrue(sums.toSet().size > 25, "the frames differ")
        }
    }

    @Test
    fun throughTheWireAndTheGate() {
        // As the session delivers it: kind 0's payload, kind 1's payloads, the gate's Annex B.
        val (sets, aus) = HevcSample.load("sample-motion.hevc")
        val gate = VideoGate()
        val format = gate.parameterSets(sets.encoded()) as VideoGate.Out.Format
        HevcDecoder(preferHardware = false).use { d ->
            d.configure(format.sets)
            var n = 0
            for ((key, au) in aus) {
                val o = gate.frame(StreamMessage(1, 0.0, key, au).payload, key, 0.0) as VideoGate.Out.Decode
                if (d.decode(o.annexB) != null) n++
            }
            assertEquals(aus.size, n)
        }
    }
}
