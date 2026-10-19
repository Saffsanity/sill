package me.saffer.sill.core

/**
 * The picture size an HEVC sequence parameter set declares (ITU-T H.265 §7.3.2.2), after its
 * conformance window: what a decoder that wants the size before the first picture (Android's
 * MediaCodec) is told, and what a view sizes itself to. Null for anything that does not parse.
 */
object HevcSps {
    data class Size(val width: Int, val height: Int)

    /** The SPS among a kind 0's sets (NAL unit type 33). */
    fun size(sets: ParameterSets): Size? = sets.sets.firstOrNull { it.isNotEmpty() && (it[0].toInt() shr 1) and 0x3F == 33 }?.let(::size)

    fun size(nal: ByteArray): Size? = try { parse(rbsp(nal, 2)) } catch (_: IndexOutOfBoundsException) { null }

    /** The payload without its emulation prevention bytes (00 00 03 → 00 00). */
    private fun rbsp(nal: ByteArray, skip: Int): ByteArray {
        val out = java.io.ByteArrayOutputStream(nal.size)
        var zeros = 0
        for (i in skip until nal.size) {
            val b = nal[i].toInt() and 0xFF
            if (zeros >= 2 && b == 3) { zeros = 0; continue }
            out.write(b)
            zeros = if (b == 0) zeros + 1 else 0
        }
        return out.toByteArray()
    }

    private class Bits(val d: ByteArray) {
        var pos = 0
        fun bit(): Int { val v = (d[pos ushr 3].toInt() shr (7 - (pos and 7))) and 1; pos++; return v }
        fun bits(n: Int): Int { var v = 0; repeat(n) { v = (v shl 1) or bit() }; return v }
        fun skip(n: Int) { pos += n; if (pos > d.size * 8) throw IndexOutOfBoundsException() }
        fun ue(): Int {
            var zeros = 0
            while (bit() == 0) { zeros++; if (zeros > 31) throw IndexOutOfBoundsException() }
            return ((1 shl zeros) - 1) + bits(zeros)
        }
    }

    private fun parse(d: ByteArray): Size? {
        val b = Bits(d)
        b.skip(4)                                   // sps_video_parameter_set_id
        val maxSubLayersMinus1 = b.bits(3)
        b.skip(1)                                   // temporal_id_nesting
        // profile_tier_level(1, maxSubLayersMinus1)
        b.skip(2 + 1 + 5 + 32 + 4 + 43 + 1 + 8)     // general profile, flags, level
        val subProfile = BooleanArray(maxSubLayersMinus1)
        val subLevel = BooleanArray(maxSubLayersMinus1)
        for (i in 0 until maxSubLayersMinus1) { subProfile[i] = b.bit() == 1; subLevel[i] = b.bit() == 1 }
        if (maxSubLayersMinus1 > 0) for (i in maxSubLayersMinus1 until 8) b.skip(2)
        for (i in 0 until maxSubLayersMinus1) {
            if (subProfile[i]) b.skip(2 + 1 + 5 + 32 + 4 + 43 + 1)
            if (subLevel[i]) b.skip(8)
        }
        b.ue()                                      // sps_seq_parameter_set_id
        val chroma = b.ue()
        if (chroma == 3) b.skip(1)                  // separate_colour_plane_flag
        val w = b.ue()
        val h = b.ue()
        if (w <= 0 || h <= 0 || w > 16384 || h > 16384) return null
        var cropW = 0; var cropH = 0
        if (b.bit() == 1) {                         // conformance_window_flag
            val left = b.ue(); val right = b.ue(); val top = b.ue(); val bottom = b.ue()
            // The window is in chroma units: 2 across for 4:2:0 and 4:2:2, 2 down for 4:2:0.
            val subW = if (chroma == 1 || chroma == 2) 2 else 1
            val subH = if (chroma == 1) 2 else 1
            cropW = subW * (left + right); cropH = subH * (top + bottom)
        }
        return Size(w - cropW, h - cropH).takeIf { it.width > 0 && it.height > 0 }
    }
}
