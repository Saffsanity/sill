package me.saffer.sill.desktop

import me.saffer.sill.core.Json
import me.saffer.sill.core.KeyValueStore
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.nio.file.attribute.PosixFilePermissions

/**
 * The Windows client's settings, saved Macs and key: one JSON file in the user's own application
 * data (%APPDATA%\Sill on Windows, whose folder only that user and the system can read;
 * ~/.config/sill elsewhere, made readable by the owner alone). Written whole to a temporary file
 * and moved into place, so a crash never leaves half a file.
 */
class DesktopStore(private val file: File = defaultFile()) : KeyValueStore {
    private val values: MutableMap<String, String> = load()

    private fun load(): MutableMap<String, String> = try {
        @Suppress("UNCHECKED_CAST")
        (Json.parse(file.readText()) as Map<String, Any?>).mapNotNull { (k, v) -> (v as? String)?.let { k to it } }.toMap(LinkedHashMap())
    } catch (_: Exception) { LinkedHashMap() }

    @Synchronized override fun get(key: String) = values[key]

    @Synchronized override fun put(key: String, value: String?) {
        if (value == null) values.remove(key) else values[key] = value
        file.parentFile.mkdirs()
        restrict(file.parentFile)
        val tmp = File(file.parentFile, file.name + ".tmp")
        tmp.writeText(Json.write(values))
        restrict(tmp)
        Files.move(tmp.toPath(), file.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
    }

    private fun restrict(f: File) {
        try { Files.setPosixFilePermissions(f.toPath(), PosixFilePermissions.fromString(if (f.isDirectory) "rwx------" else "rw-------")) }
        catch (_: UnsupportedOperationException) { /* Windows: the profile folder's ACL already limits it to this user */ }
    }

    companion object {
        fun defaultFile(): File {
            val appData = System.getenv("APPDATA")
            val dir = if (System.getProperty("os.name").lowercase().startsWith("windows") && appData != null) File(appData, "Sill")
                else File(System.getenv("XDG_CONFIG_HOME") ?: (System.getProperty("user.home") + "/.config"), "sill")
            return File(dir, "sill.json")
        }
    }
}
