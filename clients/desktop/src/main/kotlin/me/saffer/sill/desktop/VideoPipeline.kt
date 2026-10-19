package me.saffer.sill.desktop

import me.saffer.sill.core.ParameterSets
import java.util.concurrent.LinkedBlockingDeque
import java.util.concurrent.TimeUnit

/**
 * The session's video on a thread of its own: every access unit is decoded in order (a delta needs
 * the one before), but only the newest picture of a backlog is scaled for the screen, so a slow
 * moment costs pictures, never latency. A decoder failure waits for the next keyframe in a fresh
 * decoder (on the CPU if the GPU failed), as the iPad's display layer does.
 */
class VideoPipeline(
    private val newDecoder: (hardware: Boolean) -> HevcDecoder = { HevcDecoder(it) },
    /** The size to scale pictures to (the view's pixels for the frame's rectangle), asked per picture. */
    private val targetSize: (videoW: Int, videoH: Int) -> Pair<Int, Int> = { w, h -> w to h },
    private val onPicture: (HevcDecoder.Picture, videoW: Int, videoH: Int) -> Unit,
    private val log: (String) -> Unit = {},
) : AutoCloseable {
    private sealed class Job {
        class Format(val sets: ParameterSets) : Job()
        class Frame(val annexB: ByteArray, val keyframe: Boolean) : Job()
    }

    private val queue = LinkedBlockingDeque<Job>()
    @Volatile private var running = true
    private var hardwareAllowed = HevcDecoder.defaultHardware()
    private val thread = Thread(::loop, "sill-video").apply { isDaemon = true; start() }
    @Volatile var decoded = 0
        private set
    @Volatile var shown = 0
        private set
    @Volatile var failures = 0
        private set

    fun format(sets: ParameterSets) = queue.add(Job.Format(sets))
    fun frame(annexB: ByteArray, keyframe: Boolean) = queue.add(Job.Frame(annexB, keyframe))

    private fun loop() {
        var decoder: HevcDecoder? = null
        var sets: ParameterSets? = null
        var waitForKey = true
        while (running) {
            val job = queue.poll(200, TimeUnit.MILLISECONDS) ?: continue
            try {
                when (job) {
                    is Job.Format -> {
                        decoder?.close()
                        sets = job.sets
                        decoder = newDecoder(hardwareAllowed).also { it.configure(job.sets) }
                        log("video: decoder on the ${if (decoder.hardware) "GPU" else "CPU"}")
                        waitForKey = true
                    }
                    is Job.Frame -> {
                        val d = decoder ?: continue
                        if (waitForKey && !job.keyframe) continue
                        waitForKey = false
                        // A frame still waiting behind this one: decode it, show the newer one.
                        val behind = queue.peekFirst() is Job.Frame
                        val size = if (behind) 0 to 0 else targetSize(d.videoWidth, d.videoHeight)
                        val p = d.decode(job.annexB, size.first, size.second)
                        decoded++
                        if (p != null && !behind) { shown++; onPicture(p, d.videoWidth, d.videoHeight) }
                    }
                }
            } catch (e: Exception) {
                failures++
                log("video: ${e.message}; waiting for a keyframe")
                if (decoder?.hardware == true) hardwareAllowed = false
                decoder?.close()
                decoder = sets?.let { s -> try { newDecoder(hardwareAllowed).also { it.configure(s) } } catch (_: Exception) { null } }
                waitForKey = true
            }
        }
        decoder?.close()
    }

    override fun close() {
        running = false
        thread.join(1000)
    }
}
