package me.saffer.sill.core

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer

/**
 * The wire's framing, as Sources/StreamProtocol/StreamMessage.swift has it: a 14-byte big-endian
 * header (kind 1, timestamp 8 as a Double, isKeyframe 1, payload length 4), then the payload.
 * Kinds are plain numbers here: a kind this build does not know is skipped, never a reason to stop
 * reading (an older client keeps working against a newer Mac). Their meanings are StreamMessage.swift's.
 */
object Kind {
    const val PARAMETER_SETS = 0
    const val FRAME = 1
    const val WINDOW_LIST = 2
    const val THUMBNAIL = 3
    const val APP_ICON = 4
    const val APP_LIST = 5
    const val SELECT_SOURCE = 6
    const val LAUNCH_APP = 7
    const val INPUT = 8
    const val VIEWPORT = 9
    const val PING = 10
    const val PONG = 11
    const val CLIENT_STATS = 12
    const val TICK = 13
    const val CURSOR_SHAPE = 14
    const val WINDOW_COMMAND = 15
    const val HOST_SETTINGS = 16
    const val CHANGE_SETTINGS = 17
    const val MAC_INFO = 18
    const val PAIR_REQUEST = 19
    const val PAIR_RESULT = 20
    const val PAIRING_WANTED = 21
    const val GOODBYE = 22
    const val HELLO = 23
    const val MAC_MENU = 24
    const val PRESS_MENU_ITEM = 25
    const val MAC_POINTER = 26
    const val FETCH_MENU = 27
    const val GESTURE = 28
    const val CLIPBOARD = 32

    /** Every kind this build knows, by its name in StreamMessage.swift (the vectors' `kinds`). */
    val names: Map<Int, String> = mapOf(
        0 to "parameterSets", 1 to "frame", 2 to "windowList", 3 to "thumbnail", 4 to "appIcon", 5 to "appList",
        6 to "selectSource", 7 to "launchApp", 8 to "input", 9 to "viewport", 10 to "ping", 11 to "pong",
        12 to "clientStats", 13 to "tick", 14 to "cursorShape", 15 to "windowCommand", 16 to "hostSettings",
        17 to "changeSettings", 18 to "macInfo", 19 to "pairRequest", 20 to "pairResult", 21 to "pairingWanted",
        22 to "goodbye", 23 to "hello", 24 to "macMenu", 25 to "pressMenuItem", 26 to "macPointer",
        27 to "fetchMenu", 28 to "gesture", 32 to "clipboard",
    )
}

class StreamHeader(val kind: Int, val timestamp: Double, val isKeyframe: Boolean, val payloadLength: Long)

class StreamMessage(val kind: Int, val timestamp: Double, val isKeyframe: Boolean, val payload: ByteArray) {
    fun serialized(): ByteArray {
        val b = ByteBuffer.allocate(HEADER_LENGTH + payload.size)
        b.put(kind.toByte())
        b.putLong(timestamp.toRawBits())
        b.put(if (isKeyframe) 1 else 0)
        b.putInt(payload.size)
        b.put(payload)
        return b.array()
    }

    companion object {
        const val HEADER_LENGTH = 14
        /** Any client → host message, on both doors. */
        const val MAX_CLIENT_PAYLOAD = 1 shl 20
        /** The one message of a pairing connection (kind 19), and the answer the device reads (20). */
        const val MAX_PAIRING_PAYLOAD = 4096
        /** A video frame, as a device accepts it. */
        const val MAX_FRAME_PAYLOAD = 32 shl 20
        /** Any other host → device message. */
        const val MAX_OTHER_HOST_PAYLOAD = 4 shl 20

        fun parseHeader(d: ByteArray): StreamHeader? {
            if (d.size < HEADER_LENGTH) return null
            val b = ByteBuffer.wrap(d, 0, HEADER_LENGTH)
            val kind = b.get().toInt() and 0xFF
            val ts = Double.fromBits(b.long)
            val key = b.get().toInt() == 1
            val len = b.int.toLong() and 0xFFFFFFFFL
            return StreamHeader(kind, ts, key, len)
        }

        /** What a device accepts in one message of `kind` from a Mac (MessageReader.swift's caps). */
        fun hostPayloadCap(kind: Int): Long =
            if (kind == Kind.FRAME) MAX_FRAME_PAYLOAD.toLong() else MAX_OTHER_HOST_PAYLOAD.toLong()

        fun json(kind: Int, value: Any?, timestamp: Double = 0.0) = StreamMessage(kind, timestamp, false, Json.bytes(value))
        fun empty(kind: Int, timestamp: Double = 0.0) = StreamMessage(kind, timestamp, false, ByteArray(0))
    }
}

/** HEVC VPS/SPS/PPS as VideoToolbox delivers them: `nalLen(1) count(1)` then per set `length(2) bytes`. */
class ParameterSets(val nalUnitHeaderLength: Int, val sets: List<ByteArray>) {
    fun encoded(): ByteArray {
        val o = ByteArrayOutputStream()
        o.write(nalUnitHeaderLength)
        o.write(sets.size)
        for (s in sets) { o.write(s.size ushr 8); o.write(s.size and 0xFF); o.write(s) }
        return o.toByteArray()
    }

    /** The sets as an Annex B stream (a start code before each): a decoder's codec-specific data. */
    fun annexB(): ByteArray {
        val o = ByteArrayOutputStream()
        for (s in sets) { o.write(START_CODE); o.write(s) }
        return o.toByteArray()
    }

    override fun equals(other: Any?) = other is ParameterSets && other.nalUnitHeaderLength == nalUnitHeaderLength &&
        other.sets.size == sets.size && other.sets.indices.all { other.sets[it].contentEquals(sets[it]) }

    override fun hashCode() = sets.fold(nalUnitHeaderLength) { h, s -> 31 * h + s.contentHashCode() }

    companion object {
        val START_CODE = byteArrayOf(0, 0, 0, 1)

        fun decode(d: ByteArray): ParameterSets? {
            if (d.size < 2) return null
            val nal = d[0].toInt() and 0xFF
            val count = d[1].toInt() and 0xFF
            var off = 2
            val out = ArrayList<ByteArray>()
            repeat(count) {
                if (d.size < off + 2) return null
                val len = ((d[off].toInt() and 0xFF) shl 8) or (d[off + 1].toInt() and 0xFF)
                off += 2
                if (d.size < off + len) return null
                out.add(d.copyOfRange(off, off + len))
                off += len
            }
            return ParameterSets(nal, out)
        }
    }
}

/**
 * A frame (kind 1) is one HEVC access unit of NAL units, each after a big-endian length of
 * `nalLength` bytes (hvcC style). Decoders on Android (MediaCodec) and FFmpeg take Annex B: the same
 * units after start codes. Null for a frame whose lengths do not add up.
 */
object AccessUnit {
    fun toAnnexB(frame: ByteArray, nalLength: Int): ByteArray? {
        if (nalLength !in 1..4) return null
        val o = ByteArrayOutputStream(frame.size + 16)
        var off = 0
        while (off < frame.size) {
            if (off + nalLength > frame.size) return null
            var len = 0L
            for (i in 0 until nalLength) len = (len shl 8) or (frame[off + i].toLong() and 0xFF)
            off += nalLength
            if (len <= 0 || off + len > frame.size) return null
            o.write(ParameterSets.START_CODE)
            o.write(frame, off, len.toInt())
            off += len.toInt()
        }
        return o.toByteArray()
    }

    /** The NAL unit types (HEVC: bits 1–6 of the first header byte) in a length-prefixed frame. */
    fun nalTypes(frame: ByteArray, nalLength: Int): List<Int> {
        val types = ArrayList<Int>()
        var off = 0
        while (off + nalLength < frame.size) {
            var len = 0L
            for (i in 0 until nalLength) len = (len shl 8) or (frame[off + i].toLong() and 0xFF)
            off += nalLength
            if (len <= 0 || off + len > frame.size) break
            types.add((frame[off].toInt() shr 1) and 0x3F)
            off += len.toInt()
        }
        return types
    }
}

/** Binary image payloads: a key, then the image bytes (Switcher.swift's ImageBlob). */
object ImageBlob {
    class Thumbnail(val windowID: Long, val jpeg: ByteArray)
    class Icon(val bundleID: String, val png: ByteArray)

    fun encodeThumbnail(windowID: Long, jpeg: ByteArray): ByteArray =
        ByteBuffer.allocate(4 + jpeg.size).putInt(windowID.toInt()).put(jpeg).array()

    fun decodeThumbnail(d: ByteArray): Thumbnail? {
        if (d.size <= 4) return null
        return Thumbnail(ByteBuffer.wrap(d).int.toLong() and 0xFFFFFFFFL, d.copyOfRange(4, d.size))
    }

    fun encodeIcon(bundleID: String, png: ByteArray): ByteArray {
        val id = bundleID.encodeToByteArray()
        return ByteBuffer.allocate(2 + id.size + png.size).putShort(id.size.toShort()).put(id).put(png).array()
    }

    fun decodeIcon(d: ByteArray): Icon? {
        if (d.size <= 2) return null
        val len = ((d[0].toInt() and 0xFF) shl 8) or (d[1].toInt() and 0xFF)
        if (d.size <= 2 + len) return null
        val id = try { d.copyOfRange(2, 2 + len).decodeToString(throwOnInvalidSequence = true) } catch (_: CharacterCodingException) { return null }
        return Icon(id, d.copyOfRange(2 + len, d.size))
    }
}

/** The Mac's cursor (kind 14): hotX, hotY, width, height as big-endian Float32 in Mac points, then a PNG. */
class CursorShape(val hotX: Float, val hotY: Float, val width: Float, val height: Float, val png: ByteArray) {
    fun encoded(): ByteArray = ByteBuffer.allocate(16 + png.size).putFloat(hotX).putFloat(hotY)
        .putFloat(width).putFloat(height).put(png).array()

    companion object {
        fun decode(d: ByteArray): CursorShape? {
            if (d.size <= 16) return null
            val b = ByteBuffer.wrap(d)
            return CursorShape(b.float, b.float, b.float, b.float, d.copyOfRange(16, d.size))
        }
    }
}
