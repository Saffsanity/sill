package me.saffer.sill.core

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer

/**
 * TEST ONLY. A real HEVC stream (sample-*.hevc, clients/wire-vectors/hevc_sample.sh) as the Mac sends
 * it: VPS, SPS and PPS as kind 0's parameter sets, then each access unit's NAL units after 4-byte
 * lengths as kind 1 frames, the keyframe marked.
 */
object HevcSample {
    fun load(name: String): Pair<ParameterSets, List<Pair<Boolean, ByteArray>>> =
        split(HevcSample::class.java.getResource("/sill/$name")!!.readBytes())

    /** NAL units of an Annex B stream, without their start codes. */
    fun nalUnits(b: ByteArray): List<ByteArray> {
        val starts = ArrayList<Pair<Int, Int>>()          // (start code offset, payload offset)
        var i = 0
        while (i + 3 <= b.size) {
            if (b[i] == 0.toByte() && b[i + 1] == 0.toByte() && b[i + 2] == 1.toByte()) {
                val at = if (i > 0 && b[i - 1] == 0.toByte()) i - 1 else i
                starts.add(at to i + 3); i += 3
            } else i++
        }
        return starts.mapIndexed { k, (_, p) -> b.copyOfRange(p, if (k + 1 < starts.size) starts[k + 1].first else b.size) }
    }

    fun split(annexB: ByteArray): Pair<ParameterSets, List<Pair<Boolean, ByteArray>>> {
        val sets = ArrayList<ByteArray>()
        val aus = ArrayList<Pair<Boolean, ByteArray>>()
        var cur = ByteArrayOutputStream()
        var curKey = false
        var curHasSlice = false
        var pendingPrefix = ArrayList<ByteArray>()
        fun flush() { if (curHasSlice) aus.add(curKey to cur.toByteArray()); cur = ByteArrayOutputStream(); curKey = false; curHasSlice = false }
        for (nal in nalUnits(annexB)) {
            val type = (nal[0].toInt() shr 1) and 0x3F
            when {
                type in 32..34 -> { if (aus.isEmpty() && !curHasSlice) sets.add(nal) }            // in-band repeats are dropped, as VideoToolbox sends none
                type == 35 -> {}                                                                // access unit delimiters
                type == 39 -> pendingPrefix.add(nal)                                            // prefix SEI: belongs to the next picture
                type < 32 -> {
                    val firstSlice = (nal[2].toInt() and 0x80) != 0
                    if (firstSlice) flush()
                    for (p in pendingPrefix) cur.write(ByteBuffer.allocate(4).putInt(p.size).array()).also { cur.write(p) }
                    pendingPrefix = ArrayList()
                    cur.write(ByteBuffer.allocate(4).putInt(nal.size).array()); cur.write(nal)
                    curHasSlice = true
                    if (type in 16..21) curKey = true
                }
                else -> { cur.write(ByteBuffer.allocate(4).putInt(nal.size).array()); cur.write(nal) }
            }
        }
        flush()
        return ParameterSets(4, sets) to aus
    }
}
