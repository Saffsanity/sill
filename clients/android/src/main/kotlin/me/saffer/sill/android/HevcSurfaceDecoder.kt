package me.saffer.sill.android

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.view.Surface
import me.saffer.sill.core.HevcSps
import me.saffer.sill.core.ParameterSets
import java.util.ArrayDeque

/**
 * The Mac's HEVC on a Surface with MediaCodec (the device's hardware decoder): the parameter sets
 * as codec-specific data, each Annex B access unit queued as it arrives, every output buffer
 * rendered at once. Latency first: the low-latency hint where the platform has it (Android 11),
 * real-time priority, and nothing held for presentation timing. A new format starts a new codec;
 * an error waits for the next keyframe in a fresh one, as the iPad's display layer does.
 */
class HevcSurfaceDecoder(private val onSize: (Int, Int) -> Unit) {
    private val thread = HandlerThread("sill-decoder").apply { start() }
    private val handler = Handler(thread.looper)
    private var codec: MediaCodec? = null
    private var surface: Surface? = null
    private var sets: ParameterSets? = null
    private val pending = ArrayDeque<Pair<ByteArray, Boolean>>()
    private val freeInputs = ArrayDeque<Int>()
    private var waitForKey = true
    private var pts = 0L

    fun setSurface(s: Surface?) = handler.post {
        surface = s
        if (s == null) stopCodec() else sets?.let(::startCodec)
    }

    fun format(sets: ParameterSets) = handler.post {
        this.sets = sets
        HevcSps.size(sets)?.let { onSize(it.width, it.height) }
        if (surface != null) startCodec(sets)
    }

    fun frame(annexB: ByteArray, keyframe: Boolean) = handler.post {
        if (waitForKey && !keyframe) return@post
        if (keyframe) { pending.clear(); waitForKey = false }
        pending.add(annexB to keyframe)
        // A backlog that grows means the decoder fell behind: start again at the next keyframe.
        if (pending.size > 120) { pending.clear(); waitForKey = true }
        feed()
    }

    private fun startCodec(sets: ParameterSets) {
        stopCodec()
        val s = surface ?: return
        val size = HevcSps.size(sets) ?: HevcSps.Size(1920, 1080)
        val f = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_HEVC, size.width, size.height)
        f.setByteBuffer("csd-0", java.nio.ByteBuffer.wrap(sets.annexB()))
        f.setInteger(MediaFormat.KEY_PRIORITY, 0)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) f.setInteger(MediaFormat.KEY_LOW_LATENCY, 1)
        f.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
        try {
            val c = MediaCodec.createDecoderByType(MediaFormat.MIMETYPE_VIDEO_HEVC)
            c.setCallback(object : MediaCodec.Callback() {
                override fun onInputBufferAvailable(mc: MediaCodec, index: Int) { if (mc === codec) { freeInputs.add(index); feed() } }
                override fun onOutputBufferAvailable(mc: MediaCodec, index: Int, info: MediaCodec.BufferInfo) {
                    if (mc === codec) try { mc.releaseOutputBuffer(index, true) } catch (_: IllegalStateException) {}
                }
                override fun onOutputFormatChanged(mc: MediaCodec, format: MediaFormat) {
                    val w = format.getInteger(MediaFormat.KEY_WIDTH); val h = format.getInteger(MediaFormat.KEY_HEIGHT)
                    val cw = if (format.containsKey("crop-right")) format.getInteger("crop-right") - format.getInteger("crop-left") + 1 else w
                    val ch = if (format.containsKey("crop-bottom")) format.getInteger("crop-bottom") - format.getInteger("crop-top") + 1 else h
                    onSize(cw, ch)
                }
                override fun onError(mc: MediaCodec, e: MediaCodec.CodecException) {
                    Log.w("Sill", "decoder: ${e.diagnosticInfo}; waiting for a keyframe")
                    if (mc === codec) handler.post { this@HevcSurfaceDecoder.sets?.let(::startCodec) }
                }
            }, handler)
            c.configure(f, s, null, 0)
            c.start()
            codec = c
        } catch (e: Exception) {
            Log.w("Sill", "decoder: could not start HEVC: $e")
            codec = null
        }
        pending.clear()
        waitForKey = true
    }

    private fun feed() {
        val c = codec ?: return
        while (pending.isNotEmpty() && freeInputs.isNotEmpty()) {
            val (au, key) = pending.poll()!!
            val index = freeInputs.poll()!!
            try {
                val buf = c.getInputBuffer(index) ?: continue
                buf.clear()
                if (au.size > buf.capacity()) { waitForKey = true; pending.clear(); c.queueInputBuffer(index, 0, 0, pts, 0); return }
                buf.put(au)
                pts += 16_666
                c.queueInputBuffer(index, 0, au.size, pts, if (key) MediaCodec.BUFFER_FLAG_KEY_FRAME else 0)
            } catch (e: IllegalStateException) {
                return
            }
        }
    }

    private fun stopCodec() {
        codec?.let { c -> try { c.stop() } catch (_: Exception) {}; try { c.release() } catch (_: Exception) {} }
        codec = null
        freeInputs.clear()
    }

    fun release() = handler.post { stopCodec(); thread.quitSafely() }
}
