package me.saffer.sill.desktop

import me.saffer.sill.core.ParameterSets
import org.bytedeco.ffmpeg.avcodec.AVCodecContext
import org.bytedeco.ffmpeg.avcodec.AVPacket
import org.bytedeco.ffmpeg.avutil.AVBufferRef
import org.bytedeco.ffmpeg.avutil.AVDictionary
import org.bytedeco.ffmpeg.avutil.AVFrame
import org.bytedeco.ffmpeg.global.avcodec.*
import org.bytedeco.ffmpeg.global.avutil.*
import org.bytedeco.ffmpeg.global.swscale.*
import org.bytedeco.ffmpeg.swscale.SwsContext
import org.bytedeco.javacpp.BytePointer
import org.bytedeco.javacpp.DoublePointer
import org.bytedeco.javacpp.IntPointer
import org.bytedeco.javacpp.PointerPointer
import java.nio.ByteOrder

/**
 * HEVC to pixels with FFmpeg's decoder (HEVCDisplayView's job on the iPad): the Mac's parameter
 * sets configure a decoder, each Annex B access unit gives at most one picture, scaled straight to
 * the size the window draws it at (one copy, no second scale in Java2D), as 0x00RRGGBB ints.
 *
 * Latency first: no frame threading (each thread would hold a frame back), the low-delay flag, and
 * on Windows Direct3D 11 decoding (the GPU) when the device has it, else the CPU. Not thread safe:
 * one decoding thread calls it.
 */
class HevcDecoder(private val preferHardware: Boolean = defaultHardware()) : AutoCloseable {
    private var ctx: AVCodecContext? = null
    private var hwDevice: AVBufferRef? = null
    private val packet: AVPacket = av_packet_alloc()
    private val frame: AVFrame = av_frame_alloc()
    private val transfer: AVFrame = av_frame_alloc()
    private var sws: SwsContext? = null
    private var out: BytePointer? = null
    private var outSize = 0
    /** Whether the open decoder runs on the GPU. */
    var hardware = false
        private set
    /** The stream's picture size, from the last picture. */
    var videoWidth = 0
        private set
    var videoHeight = 0
        private set

    /** One picture, `width`×`height` 0x00RRGGBB ints, row by row. */
    class Picture(val pixels: IntArray, val width: Int, val height: Int)

    /** A new format: a fresh decoder, primed with the parameter sets. */
    fun configure(sets: ParameterSets) {
        closeCodec()
        val codec = avcodec_find_decoder(AV_CODEC_ID_HEVC) ?: throw IllegalStateException("FFmpeg has no HEVC decoder")
        val c = avcodec_alloc_context3(codec)
        c.flags(c.flags() or AV_CODEC_FLAG_LOW_DELAY)
        c.thread_type(FF_THREAD_SLICE_TYPE)
        c.thread_count(0)
        hardware = false
        if (preferHardware) {
            val dev = AVBufferRef()
            if (av_hwdevice_ctx_create(dev, AV_HWDEVICE_TYPE_D3D11VA, null as String?, null as AVDictionary?, 0) >= 0) {
                hwDevice = dev
                // FFmpeg's default format choice picks the device's format once hw_device_ctx is set.
                c.hw_device_ctx(av_buffer_ref(dev))
                hardware = true
            }
        }
        if (avcodec_open2(c, codec, null as AVDictionary?) < 0) {
            avcodec_free_context(c)
            throw IllegalStateException("FFmpeg would not open its HEVC decoder")
        }
        ctx = c
        send(sets.annexB())
        drain(0, 0)
    }

    /**
     * One access unit; the picture it completes, scaled to `outW`×`outH` (0: the picture's own
     * size), or null when it completes none. False-y `ok` (an exception) means the decoder failed:
     * ask the Mac for a keyframe and configure again.
     */
    fun decode(annexB: ByteArray, outW: Int = 0, outH: Int = 0): Picture? {
        if (ctx == null) throw IllegalStateException("not configured")
        val r = send(annexB)
        if (r < 0 && r != AVERROR_EAGAIN()) throw IllegalStateException("decode failed (${err(r)})")
        return drain(outW, outH)
    }

    private fun send(data: ByteArray): Int {
        if (av_new_packet(packet, data.size) < 0) throw OutOfMemoryError("packet")
        packet.data().put(data, 0, data.size)
        val r = avcodec_send_packet(ctx, packet)
        av_packet_unref(packet)
        return r
    }

    private fun drain(outW: Int, outH: Int): Picture? {
        var last: Picture? = null
        while (true) {
            val r = avcodec_receive_frame(ctx, frame)
            if (r == AVERROR_EAGAIN() || r == AVERROR_EOF()) break
            if (r < 0) throw IllegalStateException("decode failed (${err(r)})")
            var src = frame
            if (frame.format() == AV_PIX_FMT_D3D11) {
                av_frame_unref(transfer)
                if (av_hwframe_transfer_data(transfer, frame, 0) < 0) { av_frame_unref(frame); throw IllegalStateException("GPU frame transfer failed") }
                src = transfer
            }
            videoWidth = src.width(); videoHeight = src.height()
            last = convert(src, if (outW > 0) outW else src.width(), if (outH > 0) outH else src.height())
            av_frame_unref(frame)
        }
        return last
    }

    private fun convert(f: AVFrame, w: Int, h: Int): Picture {
        sws = sws_getCachedContext(sws, f.width(), f.height(), f.format(), w, h, AV_PIX_FMT_BGR0, SWS_BILINEAR, null, null, null as DoublePointer?)
            ?: throw IllegalStateException("no scaler for format ${f.format()}")
        val size = w * h * 4
        if (out == null || outSize < size) { out?.let { av_free(it) }; out = BytePointer(av_malloc(size.toLong())); outSize = size }
        val dst = out!!
        // Four planes' pointers and strides, as swscale reads them; BGR0 has one.
        sws_scale(sws, f.data(), f.linesize(), 0, f.height(), PointerPointer<BytePointer>(dst, null, null, null), IntPointer(*intArrayOf(w * 4, 0, 0, 0)))
        val pixels = IntArray(w * h)
        dst.capacity(size.toLong()).asByteBuffer().order(ByteOrder.LITTLE_ENDIAN).asIntBuffer().get(pixels)
        return Picture(pixels, w, h)
    }

    private fun err(code: Int): String {
        val buf = BytePointer(256)
        av_strerror(code, buf, 256)
        return buf.string
    }

    private fun closeCodec() {
        ctx?.let { avcodec_free_context(it) }
        ctx = null
        hwDevice?.let { av_buffer_unref(it) }
        hwDevice = null
    }

    override fun close() {
        closeCodec()
        av_packet_free(packet)
        av_frame_free(frame)
        av_frame_free(transfer)
        sws?.let { sws_freeContext(it) }
        out?.let { av_free(it) }
    }

    companion object {
        /** FFmpeg's FF_THREAD_SLICE (avcodec.h), which the bindings leave out. */
        private const val FF_THREAD_SLICE_TYPE = 2

        /** Direct3D 11 on Windows unless SILL_DECODER=software says otherwise. */
        fun defaultHardware() = System.getProperty("os.name").lowercase().startsWith("windows") && System.getenv("SILL_DECODER") != "software"
    }
}
