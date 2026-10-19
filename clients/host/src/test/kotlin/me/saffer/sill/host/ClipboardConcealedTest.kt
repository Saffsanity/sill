package me.saffer.sill.host

import java.awt.GraphicsEnvironment
import java.awt.Toolkit
import java.awt.datatransfer.ClipboardOwner
import java.awt.datatransfer.DataFlavor
import java.awt.datatransfer.Transferable
import java.io.ByteArrayInputStream
import java.io.File
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import org.junit.jupiter.api.Assumptions.assumeTrue

/**
 * A copy a password manager marks as concealed is never read (Sill.app's ClipboardPolicy): another
 * process owns the clipboard, as the password manager would, offering the text and the marker; this
 * one reads it through Clipboards as the host does. Needs a display (X11 under Xvfb, or Windows).
 */
class ClipboardConcealedTest {
    private fun owned(vararg args: String, read: () -> String?): String? {
        val java = File(System.getProperty("java.home"), "bin/java").path
        val p = ProcessBuilder(java, "-cp", System.getProperty("java.class.path"), ClipboardOwnerMain::class.java.name, *args)
            .redirectErrorStream(true).start()
        try {
            val lines = p.inputStream.bufferedReader()
            val ready = generateSequence { lines.readLine() }.firstOrNull { it == "owning" }   // past the JVM's own notices
            assertEquals("owning", ready, "the owner's ready line")
            Thread.sleep(300)
            return read()
        } finally { p.destroy(); p.waitFor(5, TimeUnit.SECONDS) }
    }

    @Test
    fun concealedCopiesAreNeverRead() {
        val os = System.getProperty("os.name").lowercase()
        assumeTrue(!GraphicsEnvironment.isHeadless() && (os.startsWith("windows") || System.getenv("DISPLAY") != null), "needs a display")
        assertEquals("plain text", owned("plain text") { Clipboards.text() })
        for (marker in Clipboards.markers) assertNull(owned("hunter2", marker) { Clipboards.text() }, marker)
        assertNull(owned("hunter2", "x-kde-passwordManagerHint=secret") { Clipboards.text() })
        assertNull(owned("hunter2", "CanIncludeInClipboardHistory=0") { Clipboards.text() })
        assertEquals("allowed", owned("allowed", "CanIncludeInClipboardHistory=1") { Clipboards.text() })
        assertEquals("not secret", owned("not secret", "x-kde-passwordManagerHint=other") { Clipboards.text() })
    }
}

/** The other process: owns the clipboard with TEXT and, optionally, one marker (NAME or NAME=VALUE) until it is stopped. */
object ClipboardOwnerMain {
    @JvmStatic fun main(args: Array<String>) {
        val text = args[0]
        val marker = args.getOrNull(1)?.split('=', limit = 2)
        val markerFlavor = marker?.let { Clipboards.flavorFor(it[0]) }
        val markerBytes = when {
            marker == null || marker.size < 2 -> byteArrayOf(1)
            marker[0] == "CanIncludeInClipboardHistory" -> byteArrayOf(marker[1].toInt().toByte(), 0, 0, 0)
            else -> marker[1].encodeToByteArray()
        }
        val t = object : Transferable, ClipboardOwner {
            override fun getTransferDataFlavors() = listOfNotNull(DataFlavor.stringFlavor, markerFlavor).toTypedArray()
            override fun isDataFlavorSupported(f: DataFlavor) = f in transferDataFlavors
            override fun getTransferData(f: DataFlavor): Any = if (f == markerFlavor) ByteArrayInputStream(markerBytes) else text
            override fun lostOwnership(c: java.awt.datatransfer.Clipboard?, contents: Transferable?) {}
        }
        Toolkit.getDefaultToolkit().systemClipboard.setContents(t, t)
        println("owning"); System.out.flush()
        Thread.sleep(30_000)
    }
}
