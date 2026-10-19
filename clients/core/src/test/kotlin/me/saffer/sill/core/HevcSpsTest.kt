package me.saffer.sill.core

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/** The SPS's picture size, from libx265's streams (one with a conformance window: 642×418 is coded as 648×424). */
class HevcSpsTest {
    @Test
    fun sizesFromRealStreams() {
        assertEquals(HevcSps.Size(320, 240), HevcSps.size(HevcSample.load("sample-color.hevc").first))
        assertEquals(HevcSps.Size(642, 418), HevcSps.size(HevcSample.load("sample-motion.hevc").first))
    }

    @Test
    fun garbageIsNoSize() {
        assertNull(HevcSps.size(byteArrayOf(0x42, 0x01)))
        assertNull(HevcSps.size(byteArrayOf(0x42, 0x01, 0, 0, 0, 0, 0, 0, 0, 0)))
        assertNull(HevcSps.size(ParameterSets(4, listOf(byteArrayOf(0x40, 0x01)))))
    }
}
