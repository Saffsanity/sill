package me.saffer.sill.host

import java.awt.Robot
import java.awt.Toolkit
import java.awt.datatransfer.DataFlavor
import java.awt.datatransfer.StringSelection
import java.awt.datatransfer.SystemFlavorMap
import java.awt.image.BufferedImage
import java.io.ByteArrayOutputStream
import java.io.File
import javax.imageio.IIOImage
import javax.imageio.ImageIO
import javax.imageio.ImageWriteParam

/** Window thumbnails (kind 3): the window's part of the screen, scaled down, as a JPEG. */
internal object Thumbnails {
    private val robot by lazy { try { Robot() } catch (_: Exception) { null } }

    fun ofScreen(r: Rect, screen: Rect, maxWidth: Int): ByteArray? {
        val x = r.x.coerceIn(screen.x, screen.x + screen.w - 1); val y = r.y.coerceIn(screen.y, screen.y + screen.h - 1)
        val w = minOf(r.w, screen.x + screen.w - x); val h = minOf(r.h, screen.y + screen.h - y)
        if (w < 8 || h < 8) return null
        val shot = synchronized(this) { robot?.createScreenCapture(java.awt.Rectangle(x, y, w, h)) } ?: return null
        return jpeg(scaled(shot, maxWidth))
    }

    fun scaled(img: BufferedImage, maxWidth: Int): BufferedImage {
        if (img.width <= maxWidth) return img
        val h = (img.height.toLong() * maxWidth / img.width).toInt().coerceAtLeast(1)
        val out = BufferedImage(maxWidth, h, BufferedImage.TYPE_INT_RGB)
        out.createGraphics().apply {
            setRenderingHint(java.awt.RenderingHints.KEY_INTERPOLATION, java.awt.RenderingHints.VALUE_INTERPOLATION_BILINEAR)
            drawImage(img, 0, 0, maxWidth, h, null); dispose()
        }
        return out
    }

    fun jpeg(img: BufferedImage, quality: Float = 0.7f): ByteArray {
        val rgb = if (img.type == BufferedImage.TYPE_INT_RGB) img else BufferedImage(img.width, img.height, BufferedImage.TYPE_INT_RGB).also { it.createGraphics().apply { drawImage(img, 0, 0, null); dispose() } }
        val o = ByteArrayOutputStream()
        val writer = ImageIO.getImageWritersByFormatName("jpeg").next()
        ImageIO.createImageOutputStream(o).use { ios ->
            writer.output = ios
            val p = writer.defaultWriteParam.apply { compressionMode = ImageWriteParam.MODE_EXPLICIT; compressionQuality = quality }
            writer.write(null, IIOImage(rgb, null, null), p)
        }
        writer.dispose()
        return o.toByteArray()
    }

    fun png(img: BufferedImage): ByteArray = ByteArrayOutputStream().also { ImageIO.write(img, "png", it) }.toByteArray()
}

/**
 * The system clipboard's text, through AWT (X11's CLIPBOARD selection, or the Windows clipboard).
 * As Sill.app's ClipboardPolicy, a copy a password manager marks as concealed is never read, judged
 * by its formats before any text: on Windows "ExcludeClipboardContentFromMonitorProcessing" and
 * "Clipboard Viewer Ignore" (KeePass, 1Password, Bitwarden, the Windows clipboard history's own
 * convention) and "CanIncludeInClipboardHistory" holding 0; on X11 "x-kde-passwordManagerHint"
 * holding "secret" (KeePassXC, KDE's Klipper convention); and macOS's nspasteboard.org markers,
 * which some cross-platform managers also set.
 */
internal object Clipboards {
    /** Formats whose presence alone marks a copy concealed. */
    val markers = listOf("ExcludeClipboardContentFromMonitorProcessing", "Clipboard Viewer Ignore",
        "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType")
    /** Formats that mark it by their value: the value that does. */
    val valued = mapOf("CanIncludeInClipboardHistory" to byteArrayOf(0, 0, 0, 0), "x-kde-passwordManagerHint" to "secret".encodeToByteArray())

    /** Each native format as a flavor of its own, so AWT reports it (an unregistered one it leaves out). */
    private val flavors: Map<String, DataFlavor> by lazy {
        val map = SystemFlavorMap.getDefaultFlavorMap() as SystemFlavorMap
        (markers + valued.keys).associateWith { native ->
            DataFlavor("application/x-sill-marker-${native.lowercase().filter { it.isLetterOrDigit() }};class=java.io.InputStream", native).also {
                map.addUnencodedNativeForFlavor(it, native); map.addFlavorForUnencodedNative(native, it)
            }
        }
    }

    fun text(): String? = try {
        val c = Toolkit.getDefaultToolkit().systemClipboard
        if (concealed(c)) null
        else if (c.isDataFlavorAvailable(DataFlavor.stringFlavor)) c.getData(DataFlavor.stringFlavor) as? String else null
    } catch (_: Exception) { null }

    fun concealed(c: java.awt.datatransfer.Clipboard): Boolean {
        val available = try { c.availableDataFlavors.toSet() } catch (_: Exception) { return false }
        for ((native, f) in flavors) {
            if (f !in available) continue
            val wanted = valued[native] ?: return true
            val got = try { (c.getData(f) as? java.io.InputStream)?.use { it.readNBytes(64) } } catch (_: Exception) { null } ?: return true
            if (got.copyOfRange(0, minOf(got.size, wanted.size)).contentEquals(wanted)) return true
        }
        return false
    }

    fun setText(text: String) {
        try { Toolkit.getDefaultToolkit().systemClipboard.setContents(StringSelection(text), null) } catch (_: Exception) {}
    }

    /** TEST ONLY: a flavor that stands for [native] (what a password manager puts beside the text). */
    internal fun flavorFor(native: String): DataFlavor = flavors.getValue(native)
}

/**
 * Linux's installed apps: the desktop entries (freedesktop.org's Desktop Entry Specification) in
 * the XDG data directories and Flatpak's exports, those a menu shows, with their icon themes' PNGs.
 */
internal class DesktopEntries(val entries: List<Entry>) {
    class Entry(val id: String, val name: String, val command: List<String>, val icon: String?, val wmClass: String?) {
        fun iconPng(): ByteArray? {
            val i = icon ?: return null
            val f = if (i.startsWith("/")) File(i) else iconFile(i) ?: return null
            if (!f.isFile || !f.name.endsWith(".png")) return null
            return try {
                val img = ImageIO.read(f) ?: return null
                Thumbnails.png(if (img.width > 128) scaledArgb(img, 128) else img)
            } catch (_: Exception) { null }
        }
    }

    fun forClass(cls: String): Entry? = entries.firstOrNull { it.wmClass.equals(cls, true) } ?: entries.firstOrNull { it.id.equals(cls, true) }
        ?: entries.firstOrNull { it.id.substringAfterLast('.').equals(cls, true) } ?: entries.firstOrNull { it.name.equals(cls, true) }

    companion object {
        private fun dataDirs(): List<File> {
            val home = System.getenv("XDG_DATA_HOME") ?: (System.getProperty("user.home") + "/.local/share")
            val dirs = (System.getenv("XDG_DATA_DIRS") ?: "/usr/local/share:/usr/share").split(':').filter { it.isNotEmpty() }
            return (listOf(home) + dirs + listOf("/var/lib/flatpak/exports/share", System.getProperty("user.home") + "/.local/share/flatpak/exports/share")).map(::File).distinct()
        }

        fun load(): DesktopEntries {
            val seen = HashSet<String>()
            val out = ArrayList<Entry>()
            for (d in dataDirs()) {
                val apps = File(d, "applications")
                apps.walkTopDown().maxDepth(3).filter { it.isFile && it.name.endsWith(".desktop") }.forEach { f ->
                    val id = f.relativeTo(apps).path.removeSuffix(".desktop").replace('/', '-')
                    if (!seen.add(id)) return@forEach
                    parse(f, id)?.let(out::add)
                }
            }
            return DesktopEntries(out.sortedBy { it.name.lowercase() })
        }

        fun parse(f: File, id: String): Entry? {
            val m = HashMap<String, String>()
            var inMain = false
            for (line in try { f.readLines() } catch (_: Exception) { return null }) {
                val t = line.trim()
                if (t.startsWith("[")) { inMain = t == "[Desktop Entry]"; continue }
                if (!inMain || t.startsWith("#") || '=' !in t) continue
                val (k, v) = t.split('=', limit = 2).let { it[0].trim() to it[1].trim() }
                m.putIfAbsent(k, v)
            }
            if (m["Type"] != "Application" || m["NoDisplay"] == "true" || m["Hidden"] == "true") return null
            val exec = m["Exec"] ?: return null
            val name = m["Name"] ?: return null
            return Entry(id, name, command(exec) .ifEmpty { return null }, m["Icon"], m["StartupWMClass"])
        }

        /** Exec's arguments, quoting undone and field codes (%f, %U…) left out. */
        fun command(exec: String): List<String> {
            val args = ArrayList<String>()
            val cur = StringBuilder(); var quoted = false; var any = false
            var i = 0
            while (i < exec.length) {
                val c = exec[i]
                when {
                    c == '\\' && i + 1 < exec.length -> { cur.append(exec[i + 1]); i++; any = true }
                    c == '"' -> { quoted = !quoted; any = true }
                    c == ' ' && !quoted -> { if (any) args.add(cur.toString()); cur.clear(); any = false }
                    else -> { cur.append(c); any = true }
                }
                i++
            }
            if (any) args.add(cur.toString())
            return args.filter { !(it.length == 2 && it[0] == '%') }.map { it.replace("%%", "%") }
        }

        private fun iconFile(name: String): File? {
            for (d in dataDirs()) {
                for (size in listOf("128x128", "96x96", "64x64", "48x48", "256x256", "512x512", "32x32")) {
                    for (theme in listOf("hicolor", "Adwaita", "breeze")) {
                        val f = File(d, "icons/$theme/$size/apps/$name.png")
                        if (f.isFile) return f
                    }
                }
                File(d, "pixmaps/$name.png").takeIf { it.isFile }?.let { return it }
            }
            return null
        }

        fun scaledArgb(img: BufferedImage, size: Int): BufferedImage {
            val out = BufferedImage(size, size * img.height / img.width, BufferedImage.TYPE_INT_ARGB)
            out.createGraphics().apply {
                setRenderingHint(java.awt.RenderingHints.KEY_INTERPOLATION, java.awt.RenderingHints.VALUE_INTERPOLATION_BICUBIC)
                drawImage(img, 0, 0, out.width, out.height, null); dispose()
            }
            return out
        }
    }
}
