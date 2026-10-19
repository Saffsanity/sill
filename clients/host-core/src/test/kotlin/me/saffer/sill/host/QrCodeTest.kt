package me.saffer.sill.host

import me.saffer.sill.core.Json
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith

/** The pairing window's QR codes against python-qrcode's (src/test/qr/generate.py), module for module. */
class QrCodeTest {
    @Test fun matchesTheReferenceImplementation() {
        val vectors = Json.parse(javaClass.getResourceAsStream("/sill/qr-vectors.json")!!.readBytes()) as List<*>
        assertEquals(13, vectors.size)
        for (v in vectors) {
            v as Map<*, *>
            val text = v["text"] as String
            val qr = QrCode.encode(text)
            assertEquals(v["version"].toString().toInt(), qr.version, "version of ${text.take(40)}")
            assertEquals(v["mask"].toString().toInt(), qr.mask, "mask of ${text.take(40)}")
            val rows = qr.modules.map { r -> r.joinToString("") { if (it) "1" else "0" } }
            assertEquals(v["rows"], rows, "modules of ${text.take(40)}")
        }
    }

    @Test fun sizesAndLimits() {
        assertEquals(21, QrCode.encode("a").size)
        assertEquals(177, QrCode.encode("x".repeat(2331)).size)
        assertFailsWith<IllegalArgumentException> { QrCode.encode("x".repeat(2332)) }
    }
}
