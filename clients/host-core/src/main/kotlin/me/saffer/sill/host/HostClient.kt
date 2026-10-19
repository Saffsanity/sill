package me.saffer.sill.host

import me.saffer.sill.core.Kind
import me.saffer.sill.core.ParameterSets
import me.saffer.sill.core.StreamMessage
import java.io.IOException
import java.io.OutputStream
import java.util.ArrayDeque

/**
 * One device's session, as the Mac's StreamServer sends to it (docs: its broadcast, eviction and
 * tick rules), behind a writer thread of its own so a slow device never holds up another:
 *
 * - Every message but ticks and kind 26 counts as in flight until the socket has taken it.
 * - A device waiting for a keyframe (at admission, after a new stream, after a dropped frame) gets
 *   no frame until a keyframe comes; the stream's parameter sets go first.
 * - With more than two messages in flight, a frame that is not a keyframe is dropped, and the
 *   device then waits for the keyframe [onKeyframeNeeded] asks for. Keyframes are never dropped.
 * - The oldest frame the socket has not taken, once older than 4 s with the device connected for
 *   more than 8 s, ends the session (a device that stopped reading).
 */
class HostClient(
    private val output: OutputStream,
    val description: String,
    /** base64url of the device's key, the trust list's name for it. */
    val fingerprint: String,
    private val clock: () -> Double,
    private val onKeyframeNeeded: () -> Unit,
    private val onWriteFailed: (HostClient) -> Unit,
) {
    private class Out(val bytes: ByteArray, val counted: Boolean, val frame: Boolean)

    private val lock = Object()
    private val queue = ArrayDeque<Out>()
    private var writing: Out? = null
    private var framesInFlight = 0
    private var frameClock: Double? = null
    @Volatile var needsKeyframe = true; private set
    @Volatile var closed = false; private set
    @Volatile var lastSentAt = 0.0; private set
    val connectedAt = clock()
    /** The device's name from its hello, or its address until then. */
    @Volatile var name: String = description
    /** Kind 8 messages read on this connection (kind 26's `seen`). */
    @Volatile var inputsRead = 0
    var stats: StatsLine? = null

    data class StatsLine(val fps: Int, val frameAgeMs: Int, val rttMs: Int)

    private val writer = Thread(::writeLoop, "sill-send ${description}").apply { isDaemon = true; start() }

    /** Messages queued and not yet taken by the socket, but ticks and kind 26. */
    val inflight: Int get() = synchronized(lock) { queue.count { it.counted } + if (writing?.counted == true) 1 else 0 }

    /** Any message; counted unless it is a tick or the pointer. */
    fun send(m: StreamMessage) = enqueue(Out(m.serialized(), m.kind != Kind.TICK && m.kind != Kind.MAC_POINTER, false))

    /** One frame of the stream, by the rules above; `sets` are the stream's current parameter sets. */
    fun sendFrame(m: StreamMessage, sets: ParameterSets?) {
        synchronized(lock) {
            if (closed) return
            if (needsKeyframe) {
                if (!m.isKeyframe || sets == null) return
                enqueueLocked(Out(StreamMessage(Kind.PARAMETER_SETS, m.timestamp, false, sets.encoded()).serialized(), true, false))
                enqueueLocked(Out(m.serialized(), true, true))
                needsKeyframe = false
                return
            }
            if (!m.isKeyframe && inflightLocked() > MAX_INFLIGHT) {
                needsKeyframe = true
                droppedFrames++
            } else {
                enqueueLocked(Out(m.serialized(), true, true))
                return
            }
        }
        onKeyframeNeeded()
    }

    @Volatile var droppedFrames = 0

    /** A new stream begins: wait for its first keyframe. */
    fun resetForNewStream() { synchronized(lock) { needsKeyframe = true } }

    /** Whether the device stopped reading: its oldest frame waiting over 4 s, connected over 8 s. */
    fun stalled(now: Double): Boolean = synchronized(lock) {
        val c = frameClock ?: return false
        now - c > STALL && now - connectedAt > GRACE
    }

    fun close() {
        synchronized(lock) { if (closed) return; closed = true; queue.clear(); lock.notifyAll() }
        try { output.close() } catch (_: IOException) {}
    }

    private fun inflightLocked() = queue.count { it.counted } + if (writing?.counted == true) 1 else 0

    private fun enqueue(o: Out) = synchronized(lock) { enqueueLocked(o) }

    private fun enqueueLocked(o: Out) {
        if (closed) return
        if (o.frame) { if (framesInFlight == 0) frameClock = clock(); framesInFlight++ }
        queue.addLast(o)
        lock.notifyAll()
    }

    private fun writeLoop() {
        while (true) {
            val o: Out
            synchronized(lock) {
                while (queue.isEmpty() && !closed) lock.wait()
                if (closed) return
                o = queue.removeFirst()
                writing = o
            }
            try {
                output.write(o.bytes)
                output.flush()
            } catch (_: IOException) {
                synchronized(lock) { writing = null }
                if (!closed) onWriteFailed(this)
                return
            }
            synchronized(lock) {
                writing = null
                lastSentAt = clock()
                if (o.frame) {
                    framesInFlight--
                    frameClock = if (framesInFlight > 0) clock() else null
                }
            }
        }
    }

    override fun toString() = name

    companion object {
        const val MAX_INFLIGHT = 2
        const val STALL = 4.0
        const val GRACE = 8.0
    }
}
