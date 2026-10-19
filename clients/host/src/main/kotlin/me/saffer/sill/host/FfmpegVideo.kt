package me.saffer.sill.host

import me.saffer.sill.core.ParameterSets
import org.bytedeco.ffmpeg.avcodec.AVCodec
import org.bytedeco.ffmpeg.avcodec.AVCodecContext
import org.bytedeco.ffmpeg.avcodec.AVPacket
import org.bytedeco.ffmpeg.avformat.AVFormatContext
import org.bytedeco.ffmpeg.avutil.AVBufferRef
import org.bytedeco.ffmpeg.avutil.AVDictionary
import org.bytedeco.ffmpeg.avutil.AVFrame
import org.bytedeco.ffmpeg.avutil.AVHWFramesContext
import org.bytedeco.ffmpeg.avutil.AVRational
import org.bytedeco.ffmpeg.global.avcodec.*
import org.bytedeco.ffmpeg.global.avdevice.avdevice_register_all
import org.bytedeco.ffmpeg.global.avformat.*
import org.bytedeco.ffmpeg.global.avutil.*
import org.bytedeco.ffmpeg.global.swscale.*
import org.bytedeco.ffmpeg.swscale.SwsContext
import org.bytedeco.javacpp.BytePointer
import org.bytedeco.javacpp.DoublePointer
import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer

/** Where FFmpeg captures from: an input format, its URL and options (x11grab, gdigrab, or lavfi in tests). */
data class CaptureSpec(val format: String, val url: String, val options: Map<String, String>, val description: String)

/**
 * The HEVC encoders a host tries, best first, and how each is set up for latency (the Mac's
 * VideoToolbox setup: real time, no B-frames, one frame in flight). Each is opened and fed one probe
 * frame before it is chosen: a missing GPU or driver fails there, not mid-stream.
 */
object Encoders {
    data class Choice(val name: String, val hardware: Boolean, val pixFmt: Int, val options: Map<String, String>, val hwDevice: Int = AV_HWDEVICE_TYPE_NONE)

    fun ladder(windows: Boolean, keyint: Int): List<Choice> {
        val nvenc = Choice("hevc_nvenc", true, AV_PIX_FMT_NV12, mapOf("preset" to "p1", "tune" to "ull", "zerolatency" to "1", "delay" to "0",
            "rc" to "cbr", "forced-idr" to "1", "bf" to "0"))
        val qsv = Choice("hevc_qsv", true, AV_PIX_FMT_NV12, mapOf("preset" to "veryfast", "async_depth" to "1", "bf" to "0", "forced_idr" to "1", "look_ahead_depth" to "0"))
        val vaapi = Choice("hevc_vaapi", true, AV_PIX_FMT_VAAPI, mapOf("bf" to "0", "rc_mode" to "CBR"), AV_HWDEVICE_TYPE_VAAPI)
        val mf = Choice("hevc_mf", true, AV_PIX_FMT_NV12, mapOf("hw_encoding" to "1", "scenario" to "display_remoting", "rate_control" to "cbr"))
        val x265 = Choice("libx265", false, AV_PIX_FMT_YUV420P, mapOf("preset" to "ultrafast", "tune" to "zerolatency", "forced-idr" to "1",
            "x265-params" to "bframes=0:keyint=$keyint:min-keyint=$keyint:scenecut=0:repeat-headers=0:log-level=error:aud=0"))
        val forced = System.getenv("SILL_ENCODER")
        val all = if (windows) listOf(nvenc, qsv, mf, x265) else listOf(nvenc, vaapi, qsv, x265)
        return if (forced != null) all.filter { it.name == forced } else all
    }
}

/**
 * Captures one source with FFmpeg and encodes it to HEVC, as the Mac's capture and VideoToolbox do,
 * on a thread of its own: the parameter sets (VPS, SPS, PPS) when they change, then each access
 * unit with 4-byte lengths, the parameter sets left out, as kind 0 and kind 1 carry them.
 */
class FfmpegVideo(
    private val capture: CaptureSpec,
    private val params: StreamParams,
    /** The picture size to encode at (even), or null for the capture's own size times captureScale / 2. */
    private val outSize: Pair<Int, Int>?,
    private val sink: VideoSink,
    private val log: (String) -> Unit,
    private val windows: Boolean = System.getProperty("os.name").lowercase().startsWith("windows"),
) : EncodedVideo, StreamHost.SoftwareAware {
    @Volatile private var running = true
    @Volatile private var keyframeWanted = true
    @Volatile override var width = 0; private set
    @Volatile override var height = 0; private set
    @Volatile var encoderName = ""; private set
    override val software: Boolean get() = encoderName == "libx265"
    private val thread = Thread(::run, "sill-capture").apply { isDaemon = true }
    private val started = java.util.concurrent.CountDownLatch(1)
    @Volatile private var startError: String? = null

    /** Starts, and waits until the first frame encoded or it failed; null when it runs, else why not. */
    fun start(timeoutSeconds: Long = 10): String? {
        thread.start()
        if (!started.await(timeoutSeconds, java.util.concurrent.TimeUnit.SECONDS)) return "the capture did not start in $timeoutSeconds s"
        return startError
    }

    override fun requestKeyframe() { keyframeWanted = true }

    override fun close() {
        running = false
        thread.join(3000)
    }

    private fun run() {
        avdevice_register_all()
        val fmt = AVFormatContext(null)
        val opts = AVDictionary(null)
        for ((k, v) in capture.options) av_dict_set(opts, k, v, 0)
        var dec: AVCodecContext? = null
        var enc: AVCodecContext? = null
        var hwDevice: AVBufferRef? = null
        var sws: SwsContext? = null
        val pkt = av_packet_alloc(); val raw = av_frame_alloc(); val yuv = av_frame_alloc(); val hw = av_frame_alloc(); val out = av_packet_alloc()
        try {
            val input = av_find_input_format(capture.format) ?: return fail("FFmpeg has no ${capture.format} capture")
            var r = avformat_open_input(fmt, capture.url, input, opts)
            if (r < 0) return fail("could not capture ${capture.description} (${err(r)})")
            if (avformat_find_stream_info(fmt, null as org.bytedeco.javacpp.PointerPointer<*>?) < 0) return fail("no stream from ${capture.description}")
            val st = fmt.streams(0)
            val decoder = avcodec_find_decoder(st.codecpar().codec_id()) ?: return fail("no decoder for the capture")
            dec = avcodec_alloc_context3(decoder)
            avcodec_parameters_to_context(dec, st.codecpar())
            if (avcodec_open2(dec, decoder, null as AVDictionary?) < 0) return fail("the capture's decoder did not open")

            val inW = dec.width(); val inH = dec.height()
            val (w, h) = outSize ?: ((inW * params.captureScale / 2).toInt() to (inH * params.captureScale / 2).toInt())
            width = (w.coerceAtLeast(64) and 1.inv()); height = (h.coerceAtLeast(64) and 1.inv())

            // The encoder: the first of the ladder that opens and encodes a frame.
            var choice: Encoders.Choice? = null
            for (c in Encoders.ladder(windows, params.fps * 4)) {
                val codec = avcodec_find_encoder_by_name(c.name) ?: continue
                val attempt = openEncoder(codec, c) ?: continue
                enc = attempt.first; hwDevice = attempt.second
                choice = c
                break
            }
            if (choice == null || enc == null) return fail("no HEVC encoder opened (a GPU's, or x265)")
            encoderName = choice.name
            log("Encoder: ${choice.name} (${if (choice.hardware) "hardware" else "software"}), ${width}×$height at ${params.fps} fps, ${params.bitrate / 1_000_000} Mbps; capturing ${capture.description} (${inW}×$inH)")
            emitParameterSets(enc.extradata()?.let { p -> ByteArray(enc.extradata_size()).also { p.get(it) } })

            val swFmt = if (choice.pixFmt == AV_PIX_FMT_VAAPI) AV_PIX_FMT_NV12 else choice.pixFmt
            yuv.format(swFmt); yuv.width(width); yuv.height(height)
            if (av_frame_get_buffer(yuv, 32) < 0) return fail("out of memory")
            var pts = 0L
            var lastKeyAt = 0L
            while (running) {
                r = av_read_frame(fmt, pkt)
                if (r < 0) { if (r == AVERROR_EAGAIN()) continue; return fail("the capture ended (${err(r)})") }
                val captureTime = System.currentTimeMillis() / 1e3
                if (avcodec_send_packet(dec, pkt) < 0) { av_packet_unref(pkt); continue }
                av_packet_unref(pkt)
                while (avcodec_receive_frame(dec, raw) == 0) {
                    if (raw.width() != inW || raw.height() != inH) { av_frame_unref(raw); return fail("the source changed size") }
                    sws = sws_getCachedContext(sws, inW, inH, raw.format(), width, height, swFmt, SWS_BILINEAR, null, null, null as DoublePointer?)
                    av_frame_make_writable(yuv)
                    sws_scale(sws, raw.data(), raw.linesize(), 0, inH, yuv.data(), yuv.linesize())
                    av_frame_unref(raw)
                    var frame = yuv
                    if (choice.pixFmt == AV_PIX_FMT_VAAPI) {
                        av_frame_unref(hw)
                        if (av_hwframe_get_buffer(enc.hw_frames_ctx(), hw, 0) < 0 || av_hwframe_transfer_data(hw, yuv, 0) < 0) return fail("could not upload to the GPU")
                        frame = hw
                    }
                    frame.pts(pts++)
                    // A keyframe asked for (a device joined, or one dropped a frame), or the 4 s safety one.
                    val key = keyframeWanted || pts - lastKeyAt >= params.fps * 4L
                    frame.pict_type(if (key) AV_PICTURE_TYPE_I else AV_PICTURE_TYPE_NONE)
                    if (key) { keyframeWanted = false; lastKeyAt = pts }
                    if (avcodec_send_frame(enc, frame) < 0) return fail("the encoder refused a frame")
                    while (avcodec_receive_packet(enc, out) == 0) {
                        val data = ByteArray(out.size()).also { out.data().get(it) }
                        emit(data, out.flags() and AV_PKT_FLAG_KEY != 0, captureTime)
                        av_packet_unref(out)
                    }
                    started.countDown()
                }
            }
        } catch (e: Throwable) {
            fail("capture stopped: ${e.message}")
        } finally {
            started.countDown()
            av_packet_free(pkt); av_frame_free(raw); av_frame_free(yuv); av_frame_free(hw); av_packet_free(out)
            sws?.let { sws_freeContext(it) }
            dec?.let { avcodec_free_context(it) }
            enc?.let { avcodec_free_context(it) }
            hwDevice?.let { av_buffer_unref(it) }
            avformat_close_input(fmt)
            av_dict_free(opts)
        }
    }

    /** Opens one encoder and checks it takes a frame; null when it cannot. */
    private fun openEncoder(codec: AVCodec, c: Encoders.Choice): Pair<AVCodecContext, AVBufferRef?>? {
        val enc = avcodec_alloc_context3(codec)
        enc.width(width); enc.height(height)
        enc.time_base(av_make_q(1, params.fps)); enc.framerate(av_make_q(params.fps, 1))
        enc.pix_fmt(c.pixFmt)
        enc.bit_rate(params.bitrate.toLong()); enc.rc_max_rate(params.bitrate.toLong()); enc.rc_buffer_size((params.bitrate / params.fps).coerceAtLeast(100_000))
        enc.gop_size(params.fps * 4); enc.max_b_frames(0)
        enc.flags(enc.flags() or AV_CODEC_FLAG_GLOBAL_HEADER or AV_CODEC_FLAG_LOW_DELAY)
        enc.profile(AV_PROFILE_HEVC_MAIN)
        var dev: AVBufferRef? = null
        if (c.hwDevice != AV_HWDEVICE_TYPE_NONE) {
            val d = AVBufferRef()
            if (av_hwdevice_ctx_create(d, c.hwDevice, null as String?, null as AVDictionary?, 0) < 0) { avcodec_free_context(enc); return null }
            dev = d
            val frames = av_hwframe_ctx_alloc(d)
            val fc = AVHWFramesContext(frames.data())
            fc.format(c.pixFmt); fc.sw_format(AV_PIX_FMT_NV12); fc.width(width); fc.height(height); fc.initial_pool_size(4)
            if (av_hwframe_ctx_init(frames) < 0) { av_buffer_unref(frames); av_buffer_unref(d); avcodec_free_context(enc); return null }
            enc.hw_frames_ctx(av_buffer_ref(frames))
            av_buffer_unref(frames)
        }
        val o = AVDictionary(null)
        for ((k, v) in c.options) av_dict_set(o, k, v, 0)
        val r = avcodec_open2(enc, codec, o)
        av_dict_free(o)
        if (r < 0) {
            log("Encoder: ${c.name} did not open (${err(r)})")
            avcodec_free_context(enc); dev?.let { av_buffer_unref(it) }
            return null
        }
        return enc to dev
    }

    private var sets: ParameterSets? = null

    private fun emitParameterSets(annexB: ByteArray?) {
        if (annexB == null || annexB.isEmpty()) return
        val nals = AnnexB.split(annexB).filter { (it[0].toInt() shr 1) and 0x3F in 32..34 }
        if (nals.size < 3) return
        val p = ParameterSets(4, nals)
        if (p != sets) { sets = p; sink.parameterSets(p) }
    }

    private fun emit(annexB: ByteArray, key: Boolean, timestamp: Double) {
        val nals = AnnexB.split(annexB)
        val inBand = nals.filter { (it[0].toInt() shr 1) and 0x3F in 32..34 }
        if (inBand.size >= 3) {
            val p = ParameterSets(4, inBand)
            if (p != sets) { sets = p; sink.parameterSets(p) }
        }
        val o = ByteArrayOutputStream(annexB.size + 16)
        for (n in nals) {
            val type = (n[0].toInt() shr 1) and 0x3F
            if (type in 32..35) continue                       // parameter sets go as kind 0; no delimiters
            o.write(ByteBuffer.allocate(4).putInt(n.size).array()); o.write(n)
        }
        if (o.size() > 0 && sets != null) sink.frame(o.toByteArray(), key, timestamp)
    }

    private fun fail(why: String) {
        if (startError == null && started.count > 0) startError = why
        else if (running) sink.failed(why)
        running = false
        started.countDown()
        log("Capture: $why")
    }

    private fun err(code: Int): String {
        val b = BytePointer(256L)
        av_strerror(code, b, 256)
        val bytes = ByteArray(256).also { b.get(it) }
        b.close()
        return String(bytes, 0, bytes.indexOf(0).let { if (it < 0) bytes.size else it }, Charsets.UTF_8)
    }

    companion object {
        /** Starts a capture and its encoder; throws with the reason when it does not run. */
        fun open(capture: CaptureSpec, params: StreamParams, outSize: Pair<Int, Int>?, sink: VideoSink, log: (String) -> Unit): FfmpegVideo {
            val v = FfmpegVideo(capture, params, outSize, sink, log)
            val error = v.start()
            if (error != null) { v.close(); throw java.io.IOException(error) }
            return v
        }
    }
}

/** Annex B: NAL units between start codes. */
object AnnexB {
    fun split(b: ByteArray): List<ByteArray> {
        val starts = ArrayList<Pair<Int, Int>>()
        var i = 0
        while (i + 3 <= b.size) {
            if (b[i] == 0.toByte() && b[i + 1] == 0.toByte() && b[i + 2] == 1.toByte()) {
                starts.add((if (i > 0 && b[i - 1] == 0.toByte()) i - 1 else i) to i + 3); i += 3
            } else i++
        }
        return starts.mapIndexedNotNull { k, (_, p) ->
            val end = if (k + 1 < starts.size) starts[k + 1].first else b.size
            if (end > p) b.copyOfRange(p, end) else null
        }
    }
}

@Suppress("unused") private val keepRational: AVRational? = null
