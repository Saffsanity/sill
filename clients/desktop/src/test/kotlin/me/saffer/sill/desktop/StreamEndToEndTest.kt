package me.saffer.sill.desktop

import me.saffer.sill.core.ClientInfo
import me.saffer.sill.core.HevcSample
import me.saffer.sill.core.Identity
import me.saffer.sill.core.ModelHost
import me.saffer.sill.core.ParameterSets
import me.saffer.sill.core.SessionListener
import me.saffer.sill.core.SillSession
import me.saffer.sill.core.SillTls
import me.saffer.sill.core.Trust
import me.saffer.sill.core.Viewport
import java.util.concurrent.atomic.AtomicInteger
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** The model Mac streams real HEVC; TLS, the session, the gate and the decoding thread make pictures of it. */
class StreamEndToEndTest {
    @Test
    fun picturesFromTheModelMac() {
        ModelHost(video = HevcSample.load("sample-motion.hevc"), frameIntervalMs = 16).use { host ->
            host.requirePairing = false
            val pictures = AtomicInteger()
            var size = 0 to 0
            val pipeline = VideoPipeline(newDecoder = { HevcDecoder(false) }, targetSize = { _, _ -> 320 to 208 },
                onPicture = { p, w, h -> pictures.incrementAndGet(); size = w to h; assertEquals(320 * 208, p.pixels.size) })
            val c = SillTls.dial(host.address, Identity.generate(), SillTls.SESSION_ALPN, Trust.Pinned(host.fingerprint))
            val s = SillSession(c, ClientInfo("0.6.0", "1", "Test (JVM)", "PC", null, "pc"), object : SessionListener {
                override fun onVideoFormat(sets: ParameterSets) { pipeline.format(sets) }
                override fun onFrame(annexB: ByteArray, keyframe: Boolean, timestamp: Double) { pipeline.frame(annexB, keyframe) }
            })
            s.start(Viewport(800.0, 520.0, null, fps = 60))
            val end = System.nanoTime() + 10_000_000_000
            while (pipeline.decoded < 30 && System.nanoTime() < end) Thread.sleep(20)
            assertEquals(30, pipeline.decoded, "every frame decoded")
            assertEquals(0, pipeline.failures)
            assertTrue(pictures.get() >= 10, "${pictures.get()} pictures shown")
            assertEquals(642 to 418, size)
            s.close(); pipeline.close()
        }
    }
}
