package me.saffer.sill.core.ui

import me.saffer.sill.core.HostSettingsChange
import me.saffer.sill.core.HostSettingsState
import me.saffer.sill.core.QualityPreset
import me.saffer.sill.core.RunningStream
import me.saffer.sill.core.StreamSettings

/** One of the six settings a device can change on the Mac (HostSettingsLedger.swift). */
enum class SettingsField { MaxFPS, Bitrate, CaptureScale, PrioritizeSpeed, VirtualDisplay, DirectWireless }

val HostSettingsChange.fields: List<SettingsField>
    get() = listOfNotNull(
        maxFPS?.let { SettingsField.MaxFPS }, bitrate?.let { SettingsField.Bitrate },
        captureScale?.let { SettingsField.CaptureScale }, prioritizeSpeed?.let { SettingsField.PrioritizeSpeed },
        virtualDisplay?.let { SettingsField.VirtualDisplay }, directWireless?.let { SettingsField.DirectWireless },
    )

fun HostSettingsChange.only(f: SettingsField) = when (f) {
    SettingsField.MaxFPS -> HostSettingsChange(maxFPS = maxFPS)
    SettingsField.Bitrate -> HostSettingsChange(bitrate = bitrate)
    SettingsField.CaptureScale -> HostSettingsChange(captureScale = captureScale)
    SettingsField.PrioritizeSpeed -> HostSettingsChange(prioritizeSpeed = prioritizeSpeed)
    SettingsField.VirtualDisplay -> HostSettingsChange(virtualDisplay = virtualDisplay)
    SettingsField.DirectWireless -> HostSettingsChange(directWireless = directWireless)
}

fun HostSettingsChange.adding(o: HostSettingsChange) = HostSettingsChange(token,
    o.maxFPS ?: maxFPS, o.bitrate ?: bitrate, o.captureScale ?: captureScale, o.prioritizeSpeed ?: prioritizeSpeed,
    o.virtualDisplay ?: virtualDisplay, o.directWireless ?: directWireless)

/** HostSettings.swift's `applied(to:)`: these fields over `s`. */
fun HostSettingsChange.applied(s: StreamSettings) = StreamSettings(maxFPS ?: s.maxFPS, bitrate ?: s.bitrate,
    captureScale ?: s.captureScale, prioritizeSpeed ?: s.prioritizeSpeed, virtualDisplay ?: s.virtualDisplay,
    directWireless ?: s.directWireless)

val HostSettingsChange.isEmpty get() = fields.isEmpty()

/**
 * What the Settings panel shows: the Mac's last word on this connection with this device's
 * unanswered picks over it, field by field. HostSettingsLedger.swift's `SettingsLedger`, rule for
 * rule (its doc comment has the nine): a pick sends only what changes what is shown; an answer clears
 * only the picks carrying its token, and reports the ones it refused; a pick unanswered for the
 * timeout goes back; nothing is kept across connections.
 */
class SettingsLedger {
    data class Entry(val change: HostSettingsChange, val token: Int, val sentAt: Double)

    var host: HostSettingsState? = null
        private set
    private val pending = LinkedHashMap<SettingsField, Entry>()

    val displayed: StreamSettings?
        get() = host?.let { h -> pending.values.fold(h.settings) { s, e -> e.change.applied(s) } }

    fun pendingSince(f: SettingsField): Double? = pending[f]?.sentAt

    fun pick(change: HostSettingsChange, token: Int, now: Double): HostSettingsChange? {
        val shown = displayed ?: return null
        var out = HostSettingsChange(token = token)
        for (f in change.fields) {
            if (f == SettingsField.DirectWireless && shown.directWireless == null) continue
            val single = change.only(f)
            if (single.applied(shown) == shown) continue
            pending[f] = Entry(single, token, now)
            out = out.adding(single)
        }
        return if (out.isEmpty) null else out
    }

    fun receive(state: HostSettingsState): Set<SettingsField> {
        host = state.copy(answering = null)
        val token = state.answering ?: return emptySet()
        val refused = HashSet<SettingsField>()
        val it = pending.entries.iterator()
        while (it.hasNext()) {
            val (f, e) = it.next()
            if (e.token != token) continue
            it.remove()
            if (e.change.applied(state.settings) != state.settings) refused.add(f)
        }
        return refused
    }

    fun expire(now: Double, timeout: Double): Boolean {
        val before = pending.size
        pending.entries.removeIf { now - it.value.sentAt > timeout }
        return pending.size != before
    }

    fun reset() { host = null; pending.clear() }

    companion object {
        /** A pick unanswered after max(4 s, 4 × the worst round trip) goes back (StreamClient). */
        fun timeout(rttMaxMs: Int?) = maxOf(4.0, 4.0 * (rttMaxMs ?: 0) / 1000.0)
    }
}

/**
 * The Settings panel's words (HostSettingsPanel.swift), so every platform's panel reads the same:
 * the header's readout, each row's title and choices, every footnote.
 */
object PanelCopy {
    const val done = "Done"
    const val quality = "Quality"
    const val resolution = "Resolution"
    const val frameRate = "Frame Rate"
    const val prioritizeSpeed = "Prioritize Encoding Speed"
    const val virtualDisplay = "Virtual Display"
    const val directWireless = "Direct Wireless Connection"
    const val loading = "Loading settings…"
    val resolutions = listOf("Retina" to 2.0, "Standard" to 1.0)
    val frameRates = listOf("60 fps" to 60, "120 fps" to 120)

    fun macName(name: String) = name.ifEmpty { "the Mac" }
    fun title(name: String) = name.ifEmpty { "Mac" }

    /** The header's readout: "3024×1964 · 60 fps · 40 Mbps · Wi-Fi", no-break spaces keeping each
     *  value with its unit and each "·" with the value before it. */
    fun readout(stream: RunningStream?, route: String? = null): String {
        val values = stream?.let { listOf("${it.width}×${it.height}", "${it.fps} fps", "${it.mbps} Mbps") } ?: listOf("Not streaming")
        return (values + listOfNotNull(route)).joinToString(" · ")
    }

    const val onVirtualDisplay = "On the virtual display"

    fun qualityChoices(current: Int): List<Pair<String, Int>> {
        val presets = QualityPreset.entries.map { it.label to it.bitrate }
        return if (QualityPreset.entries.none { it.bitrate == current }) presets + ("Custom — ${current / 1_000_000} Mbps" to current) else presets
    }

    val fastLinkNote = "${QualityPreset.ULTRA.title} and ${QualityPreset.EXTREME.title} need the USB cable or very fast Wi‑Fi; if the picture lags, step down."

    /** Under the stream rows (`streamFooter`): `wanted` the frame rate this device asks for. */
    fun streamFooter(device: String, wanted: Int, awayCapped: Boolean = false, lowPower: Boolean = false): String {
        var t = "Quality is per 60 fps; a 120 fps stream gets twice as much. $fastLinkNote"
        if (wanted >= 120) return t
        t += when {
            awayCapped -> " Away from home, this $device asks for $wanted fps, which halves the data your Mac sends."
            lowPower -> " Low Power Mode holds this $device to $wanted fps."
            else -> " This $device shows up to $wanted fps."
        }
        return t
    }

    fun speedFooter(mac: String) = "Lower latency when $mac is busy, at a softer picture."
    fun virtualDisplayFooter(mac: String) = "The window you pick moves onto an invisible display on $mac while it streams, so it keeps updating when covered."
    fun appliesFooter(mac: String) = "Applies to every device streaming from $mac. The stream restarts for a moment."
    fun directFooter(mac: String, device: String, on: Boolean, connectedDirectly: Boolean): String {
        var t = "Lets devices reach $mac without a shared Wi‑Fi network, the way AirDrop does. While it’s on, streaming over Wi‑Fi can stutter."
        if (on && connectedDirectly) t += " This $device is connected directly: turning this off disconnects it."
        return t
    }
    fun directFromAfar(mac: String) = "Change this on $mac, or from a device near it."
    const val persistentNote = "SillHost keeps these until it quits."
    fun softwareEncoder(mac: String) = "$mac’s hardware encoder is busy or not responding, so for now streams run at up to 60 fps at Standard."
    fun olderMac(mac: String) = "Update Sill on $mac to change these from here."
    fun disconnect(mac: String) = "Disconnect from $mac"
    const val disconnectShort = "Disconnect"
    fun kept(mac: String) = "$mac kept its setting"
    fun noAnswer(mac: String) = "$mac didn’t answer. Try again."
    /** The link's callout (HostSettingsPanel's `linkCallout`) and its button: `quality` and
     *  `suggestion` whole (no-break spaces, PanelCopy.whole's job on iOS). */
    fun linkCallout(quality: String, suggestion: String) = "The link can’t carry $quality. $suggestion is recommended."
    fun linkUse(suggestion: String) = "Use $suggestion"

    /** This device's own group, after the Mac's (HostSettingsPanel's `thisDevice`): its preferences, never sent. */
    fun thisDevice(device: String) = "This $device"
    const val keepScreenOn = "Keep Screen On"
    /** Under Keep Screen On: what it does while connected, on or off. */
    fun keepScreenOnFooter(mac: String, device: String, on: Boolean) =
        if (on) "While connected to $mac, this $device doesn’t dim or lock by itself, so a stream you only watch stays in view."
        else "This $device dims and locks by itself while connected, as it does elsewhere."
}
