package me.saffer.sill.host

import me.saffer.sill.core.QualityPreset
import kotlin.math.max
import kotlin.math.min

/**
 * What the host's UI shows, as plain values: the snapshot [StreamHost.status] takes, and what
 * Sill.app says about the same state (StatusText.swift, MenuBuilder in StatusItemController.swift,
 * PairDeviceWindow.swift, SettingsPanes.swift and DevicesPane.swift), word for word where a PC is
 * the same and with "this PC" where the Mac says "this Mac". Pure, so the tray's card, its menu, the
 * Settings window, the pairing window and the tooltip all say the same, and HostStatusTest holds
 * them to Sill.app's rules.
 */
data class HostStatusSnapshot(
    val network: Network,
    val devices: List<Device> = emptyList(),
    val stream: Stream? = null,
    /** Frames the encoder put out in the last second (0: a still picture). */
    val encodedFps: Int = 0,
    /** A device's ask opened the pairing window, which still shows its code. */
    val pairingRequest: PairingRequest? = null,
) {
    sealed class Network {
        object Starting : Network()
        data class Advertising(val name: String) : Network()
        /** Bonjour off (tests, `advertise = false`): devices dial the port by address. */
        data class NotAdvertised(val port: Int) : Network()
        data class Failed(val error: String) : Network()
    }

    /** One connected device: its name from its hello ("iPad (iPad14,1)"), else its address until it says it. */
    data class Device(val id: String, val name: String?, val endpoint: String, val fps: Int? = null, val frameAgeMs: Int? = null,
                      val rttMs: Int? = null, val route: String? = null)

    data class Stream(val kind: Kind, val title: String, val width: Int, val height: Int, val fps: Int, val mbps: Int, val softwareEncoder: Boolean = false) {
        enum class Kind { WINDOW, DESKTOP }
    }

    data class PairingRequest(val name: String)
}

/** The status item's glyph (Sill.app's StatusGlyph.State). */
enum class HostGlyph { IDLE, CONNECTED, STREAMING, ATTENTION }

/** A row's symbol: the SF Symbol Sill.app shows (macwindow, menubar.dock.rectangle, iphone, ipad) and the PC's own. */
enum class RowSymbol { WINDOW, DESKTOP, PHONE, TABLET, COMPUTER }

/** Everything the card, the menu and the tooltip say (Sill.app's StatusPresentation). */
data class HostPresentation(
    val glyph: HostGlyph,
    val header: String,
    val subtitle: String?,
    val source: Row?,
    val devices: List<Row>,
    val attention: List<Attention>,
    val tooltip: String,
    val advertisedName: String?,
) {
    data class Row(val id: String, val symbol: RowSymbol, val title: String, val detail: String?)
    data class Attention(val title: String, val subtitle: String, val action: MenuAction)
}

object HostStatusText {
    /** `startupError`: the host could not start (its port taken); the card says so. */
    fun present(s: HostStatusSnapshot, startupError: String? = null): HostPresentation {
        val (header, subtitle) = headline(s, startupError)
        val attention = ArrayList<HostPresentation.Attention>()
        s.pairingRequest?.let { attention += HostPresentation.Attention("${shortName(it.name)} Wants to Pair", "A code is showing.", MenuAction.ShowPairing) }
        val glyph = when {
            startupError != null || s.network is HostStatusSnapshot.Network.Failed || s.pairingRequest != null -> HostGlyph.ATTENTION
            s.stream != null -> HostGlyph.STREAMING
            s.devices.isNotEmpty() -> HostGlyph.CONNECTED
            else -> HostGlyph.IDLE
        }
        return HostPresentation(glyph, header, subtitle, sourceRow(s), s.devices.map(::deviceRow), attention,
            tooltip = "Sill — $header", advertisedName = (s.network as? HostStatusSnapshot.Network.Advertising)?.name)
    }

    /** The header and its explanation; the first match wins (StatusText.headline). */
    private fun headline(s: HostStatusSnapshot, startupError: String?): Pair<String, String?> {
        if (startupError != null) return "Sill Couldn’t Start" to startupError
        when (val n = s.network) {
            HostStatusSnapshot.Network.Starting -> return "Starting…" to null
            is HostStatusSnapshot.Network.Failed -> return "Not Visible on the Network" to "${n.error}. Quit and reopen Sill Host to try again."
            is HostStatusSnapshot.Network.NotAdvertised -> return "Not Advertised" to "Not advertised; devices connect to port ${n.port} by address."
            is HostStatusSnapshot.Network.Advertising -> {}
        }
        val count = s.devices.size
        if (count > 0) {
            val who = if (count == 1) s.devices[0].name?.let(::shortName) ?: "a Device" else "$count Devices"
            if (s.stream != null) return "Streaming to $who" to null
            val connected = if (count == 1) s.devices[0].name?.let(::shortName) ?: "Device" else "$count Devices"
            return "$connected Connected" to "Pick a window on the device to start streaming."
        }
        val name = (s.network as HostStatusSnapshot.Network.Advertising).name
        return "Waiting for a Device" to "Open Sill on your device. This PC appears as “$name”."
    }

    /** "iPad" from "iPad (iPad14,1)". */
    fun shortName(device: String): String = device.substringBefore(" (").ifEmpty { device }

    /** "Notepad — A very long window title that goes on" → "Notepad — A very lo…that goes on". */
    fun middleTruncated(text: String, limit: Int): String {
        if (text.length <= limit || limit <= 1) return text
        val keep = limit - 1
        return text.take((keep + 1) / 2) + "…" + text.takeLast(keep / 2)
    }

    /**
     * What streams: "Notepad — notes.txt" over "2560×1440 · 58 of 60 fps · 15 Mbps" (a still picture
     * "60 fps, still", about as wide as a one-digit count, so the card keeps its height), with one
     * device how it is connected, and "· software encoder" when FFmpeg fell back to x265.
     */
    private fun sourceRow(s: HostStatusSnapshot): HostPresentation.Row? {
        val stream = s.stream ?: return null
        val (title, symbol) = when (stream.kind) {
            HostStatusSnapshot.Stream.Kind.WINDOW -> middleTruncated(stream.title, 44) to RowSymbol.WINDOW
            HostStatusSnapshot.Stream.Kind.DESKTOP -> "Whole Desktop" to RowSymbol.DESKTOP
        }
        val rate = if (s.encodedFps > 0) "${min(s.encodedFps, stream.fps)} of ${stream.fps} fps" else "${stream.fps} fps, still"
        var detail = "${stream.width}×${stream.height} · $rate · ${stream.mbps} Mbps"
        if (s.devices.size == 1) s.devices[0].route?.let { detail += " · ${routeWord(it)}" }
        if (stream.softwareEncoder) detail += " · software encoder"
        return HostPresentation.Row("source", symbol, title, detail)
    }

    /**
     * "iPad (iPad14,1)" over "60 fps · frame age 9 ms · RTT 7 ms"; its address until its first
     * report. A second without a sample reads "–" (the client's -1), as in Sill.app's card.
     */
    private fun deviceRow(d: HostStatusSnapshot.Device): HostPresentation.Row {
        val name = d.name ?: d.endpoint
        val parts = ArrayList<String>()
        if (d.fps != null && d.frameAgeMs != null && d.rttMs != null) parts += "${d.fps} fps · frame age ${ms(d.frameAgeMs)} · RTT ${ms(d.rttMs)}"
        d.route?.let { parts += routeWord(it) }
        return HostPresentation.Row(d.id, symbolFor(name), name, parts.joinToString(" · ").ifEmpty { null })
    }

    /** Sill.app tells an iPhone from an iPad by the name; a PC also serves Android phones and tablets and PCs. */
    fun symbolFor(name: String): RowSymbol {
        val n = name.lowercase()
        return when {
            "iphone" in n || "phone" in n || "pixel" in n || "galaxy s" in n -> RowSymbol.PHONE
            "windows" in n || "linux" in n || n.endsWith(" pc") || "desktop" in n || "laptop" in n -> RowSymbol.COMPUTER
            else -> RowSymbol.TABLET
        }
    }

    /** Kept whole when a detail wraps: no-break spaces, and Wi‑Fi's non-breaking hyphen. */
    private fun routeWord(route: String) = route.replace(" ", " ").replace("Wi-Fi", "Wi‑Fi")

    private fun ms(v: Int) = if (v < 0) "–" else "$v ms"
}

/** What a menu entry does (Sill.app's MenuEntry.Action, the PC's subset). */
sealed class MenuAction {
    object None : MenuAction()
    data class SetMaxFPS(val fps: Int) : MenuAction()
    data class SetBitrate(val bitrate: Int) : MenuAction()
    data class SetCaptureScale(val scale: Double) : MenuAction()
    object ToggleLaunchAtLogin : MenuAction()
    object ShowPairing : MenuAction()
    object ShowLog : MenuAction()
    object ShowSettings : MenuAction()
    object Quit : MenuAction()
    /** One of a Picker's choices, by its place (Settings' pop-up buttons open the same menu). */
    data class Choose(val index: Int) : MenuAction()
}

/** One line of the menu, or its card, or a separator. `key`: the shortcut's key with Ctrl (Sill.app's ⌘). */
data class MenuEntry(
    val kind: Kind,
    val title: String = "",
    val subtitle: String? = null,
    val checked: Boolean = false,
    val enabled: Boolean = true,
    val key: Char? = null,
    val attention: Boolean = false,
    val action: MenuAction = MenuAction.None,
    val children: List<MenuEntry> = emptyList(),
) {
    enum class Kind { CARD, ITEM, SEPARATOR }
    /** "Ctrl+Q", as Windows and Linux menus print a shortcut. */
    val shortcut: String? get() = key?.let { "Ctrl+${it.uppercaseChar()}" }

    companion object { val separator = MenuEntry(Kind.SEPARATOR) }
}

/** Launch at Login: whether it can be set, whether it is, and why it failed. */
data class LoginState(val available: Boolean, val on: Boolean, val error: String? = null)

/**
 * The tray menu, top to bottom (MenuBuilder.entries): the card, what needs attention, then the
 * stream's controls, how the host runs, and the windows. Left out, as the PC host has none of them:
 * Virtual Display (macOS's CGVirtualDisplay), Direct Wireless Connection (AWDL), Remote Access… (the
 * PC's one door serves home and away), Permissions (Windows and X11 ask for none), and the update
 * offer (no update check yet).
 */
object HostMenu {
    fun entries(p: HostPresentation, config: HostConfig, login: LoginState): List<MenuEntry> {
        val menu = ArrayList<MenuEntry>()
        menu += MenuEntry(MenuEntry.Kind.CARD, p.header)
        for (a in p.attention) menu += MenuEntry(MenuEntry.Kind.ITEM, a.title, a.subtitle, attention = true, enabled = a.action != MenuAction.None, action = a.action)
        menu += MenuEntry.separator
        menu += MenuEntry(MenuEntry.Kind.ITEM, "Frame Rate", children = listOf(60, 120).map {
            MenuEntry(MenuEntry.Kind.ITEM, "Up to $it fps", checked = config.maxFPS == it, action = MenuAction.SetMaxFPS(it))
        })
        val quality = QualityPreset.entries.map { MenuEntry(MenuEntry.Kind.ITEM, it.title, checked = config.bitrate == it.bitrate, action = MenuAction.SetBitrate(it.bitrate)) }.toMutableList()
        if (QualityPreset.of(config.bitrate) == null) quality += MenuEntry(MenuEntry.Kind.ITEM, qualityTitle(config.bitrate), checked = true, enabled = false)
        menu += MenuEntry(MenuEntry.Kind.ITEM, "Quality", "Per 60 fps; a 120 fps stream gets twice as much", children = quality)
        menu += MenuEntry(MenuEntry.Kind.ITEM, "Resolution", children = listOf(
            MenuEntry(MenuEntry.Kind.ITEM, "Retina", checked = config.captureScale >= 1.5, action = MenuAction.SetCaptureScale(2.0)),
            MenuEntry(MenuEntry.Kind.ITEM, "Standard", "A quarter of the pixels; much lighter to encode", checked = config.captureScale < 1.5, action = MenuAction.SetCaptureScale(1.0)),
        ))
        menu += MenuEntry.separator
        menu += MenuEntry(MenuEntry.Kind.ITEM, "Launch at Login", subtitle = if (!login.available) "Available when Sill Host runs from its installed copy" else login.error,
            checked = login.on, enabled = login.available, action = MenuAction.ToggleLaunchAtLogin)
        menu += MenuEntry.separator
        menu += MenuEntry(MenuEntry.Kind.ITEM, "Pair a Device…", action = MenuAction.ShowPairing)
        menu += MenuEntry(MenuEntry.Kind.ITEM, "Show Log…", action = MenuAction.ShowLog)
        menu += MenuEntry(MenuEntry.Kind.ITEM, "Settings…", key = ',', action = MenuAction.ShowSettings)
        menu += MenuEntry.separator
        menu += MenuEntry(MenuEntry.Kind.ITEM, "Quit Sill Host", key = 'q', action = MenuAction.Quit)
        return menu
    }

    /** QualityPreset.title(forBitrate:): a preset's name, or "Custom — 12 Mbps". */
    fun qualityTitle(bitrate: Int) = QualityPreset.of(bitrate)?.title ?: "Custom — ${bitrate / 1_000_000} Mbps"
}

/**
 * The pairing window's words (PairDeviceWindow.swift's PairDeviceView), for the window the host's
 * Pair a Device… opens and the one a device's ask opens.
 */
object PairingCopy {
    const val TITLE = "Pair a Device"

    /** Where the window is: waiting with its code, or how it ended (PairDeviceView.Phase). */
    sealed class Phase {
        data class Waiting(val triesLeft: Int, val wrongFrom: String?) : Phase()
        data class Paired(val name: String) : Phase()
        object Stopped : Phase()
        object Expired : Phase()
        object Closed : Phase()
    }

    /** A window a device opened: "iPad (iPad14,1) on this network asked to pair." */
    fun askedLine(name: String?, from: String?) = "${name ?: "A device"} ${from ?: "on this network"} asked to pair."
    const val ASKED_NEXT = "Point it at this code, or tap Enter Code Instead and type the code."
    const val INTRO = "In Sill on your device, tap this PC, or tap Add a Host… (Add a Mac… in older versions) when you’re away, then scan this code or type the one below."
    const val CANT_SCAN = "Can’t scan? Tap Enter Code Instead, and type:"
    const val ADDRESS = "Address"
    const val CODE = "Code"
    const val CONTROL = "A paired device can see and control this PC."
    const val DIDNT_ASK = "Didn’t ask for this? Click Cancel."

    /** "Works once, for the next 4:58.", from the seconds left (rounded up). */
    fun countdown(secondsLeft: Double): String {
        val left = max(0, kotlin.math.ceil(secondsLeft).toInt())
        return "Works once, for the next ${left / 60}:${"%02d".format(left % 60)}."
    }

    /** "1234 5678 9012". */
    fun grouped(code: String) = code.chunked(4).joinToString(" ")

    fun wrongCode(from: String, triesLeft: Int) = "A wrong code came from $from. $triesLeft tr${if (triesLeft == 1) "y" else "ies"} left."

    /** The line under the code once the window no longer waits. */
    fun ended(p: Phase): String? = when (p) {
        is Phase.Paired -> "Paired with ${p.name}."
        Phase.Stopped -> "Pairing stopped after ${PairingWindow.MAX_WRONG} wrong codes."
        Phase.Expired -> "This code expired."
        Phase.Closed -> "This code no longer works."
        is Phase.Waiting -> null
    }

    /** The buttons, leading to trailing: the default one last. */
    fun buttons(p: Phase): List<String> = when (p) {
        is Phase.Waiting, Phase.Closed -> listOf("Cancel")
        is Phase.Paired -> listOf("Done")
        Phase.Stopped, Phase.Expired -> listOf("Cancel", "New Code")
    }

    /**
     * What to type on the device (PairingWindowAddress's rule, with the PC's one door): Tailscale's
     * address first, which works at home and away, with this network's under it; else this
     * network's, with another VPN's under it. The port after a colon when it is not 7455.
     */
    data class Address(val primary: String, val secondary: String?)

    fun address(lan: List<String>, vpn: List<String>, port: Int, defaultPort: Int = StreamHost.DEFAULT_PORT): Address? {
        fun withPort(a: String) = if (port == defaultPort) a else "$a:$port"
        val tailscale = vpn.firstOrNull(::isTailscale)
        val first = tailscale ?: lan.firstOrNull() ?: vpn.firstOrNull() ?: return null
        val second = if (tailscale != null) lan.firstOrNull() else vpn.firstOrNull { it != first }
        return Address(withPort(first), second?.let(::withPort))
    }

    /** 100.64.0.0/10, Tailscale's (and carrier NAT's) range. */
    fun isTailscale(a: String): Boolean {
        val p = a.split(".").mapNotNull { it.toIntOrNull() }
        return p.size == 4 && p[0] == 100 && p[1] in 64..127
    }
}

/** Settings' words that are the PC's own (SettingsPanes.swift and DevicesPane.swift have the rest). */
object SettingsCopy {
    const val REQUIRE_ON = "Each device pairs once, with a code this PC shows when it asks. Everything devices send and receive is encrypted."
    const val REQUIRE_OFF = "Any device on your network and any app on this PC can see and control it without pairing. Connections are still encrypted."
    const val PAIRED_FOOTER = "A paired device can see and control this PC on your network, and from afar through a VPN such as Tailscale. If one is lost, remove it here."
    const val NAME_FOOTER = "This is the PC’s name."
    const val CLIPBOARD_FOOTER = "Text you copy here can be pasted on a connected device, and text sent from one with Paste becomes this PC’s. Copies a password manager marks as concealed stay on this PC."
    const val SPEED_FOOTER = "Lower latency when the PC is busy, at a softer picture."
    fun streamingFooter(fastLinkNote: String) =
        "Each device asks for its own screen’s rate, up to this limit. Quality is per 60 fps; a 120 fps stream gets twice as much. $fastLinkNote Changes apply at once: the current stream restarts for a moment."
    fun removed(name: String) = "$name can no longer connect. To use it again, pair it again."
    const val NO_DEVICES = "No paired devices yet."

    /** "Paired Oct 18 with the code · last connected 2 minutes ago" (PairedDeviceRow.detail). */
    fun pairedDetail(d: PairedDevice, now: Double, zone: java.time.ZoneId = java.time.ZoneId.systemDefault()): String {
        val paired = java.time.Instant.ofEpochMilli((d.pairedAt * 1000).toLong()).atZone(zone)
        val today = java.time.Instant.ofEpochMilli((now * 1000).toLong()).atZone(zone)
        val day = paired.format(java.time.format.DateTimeFormatter.ofPattern(if (paired.year == today.year) "MMM d" else "MMM d, yyyy", java.util.Locale.US))
        var out = "Paired $day"
        when (d.method) { "qr" -> out += " with the QR code"; "code" -> out += " with the code"; "cable" -> out += " over the USB cable" }
        d.lastConnectedAt?.let { out += " · last connected ${relative(now - it)}" }
        return out
    }

    /** RelativeDateTimeFormatter's full, named style, in English: "just now", "2 minutes ago", "yesterday". */
    fun relative(seconds: Double): String {
        val s = seconds.toLong()
        fun unit(n: Long, u: String) = "$n $u${if (n == 1L) "" else "s"} ago"
        return when {
            s < 60 -> "just now"
            s < 3600 -> unit(s / 60, "minute")
            s < 86_400 -> unit(s / 3600, "hour")
            s < 2 * 86_400 -> "yesterday"
            s < 7 * 86_400 -> unit(s / 86_400, "day")
            s < 30 * 86_400 -> if (s / (7 * 86_400) == 1L) "last week" else unit(s / (7 * 86_400), "week")
            else -> unit(s / (30 * 86_400), "month")
        }
    }
}

/**
 * Launch at Login on the PC: a value under HKCU\Software\Microsoft\Windows\CurrentVersion\Run on
 * Windows, an XDG autostart entry (~/.config/autostart/sill-host.desktop) on Linux. Pure: what is
 * written where; the host module writes it, only when the person turns it on.
 */
object LoginItemSpec {
    const val RUN_KEY = "HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run"
    const val RUN_VALUE = "Sill Host"
    const val DESKTOP_FILE = "sill-host.desktop"

    /** The autostart folder: $XDG_CONFIG_HOME/autostart, else ~/.config/autostart. */
    fun autostartDir(env: Map<String, String>, home: String): String =
        (env["XDG_CONFIG_HOME"]?.takeIf { it.startsWith("/") } ?: "$home/.config") + "/autostart"

    /** The command, quoted for the Run key (a path with spaces) or a desktop entry's Exec. */
    fun windowsCommand(exe: String) = "\"$exe\""

    fun desktopEntry(exe: String): String {
        val quoted = if (exe.any { it == ' ' || it == '"' || it == '\\' }) "\"" + exe.replace("\\", "\\\\").replace("\"", "\\\"") + "\"" else exe
        return "[Desktop Entry]\nType=Application\nName=Sill Host\nComment=This computer's windows on your other devices\nExec=$quoted\nTerminal=false\nX-GNOME-Autostart-enabled=true\n"
    }
}
