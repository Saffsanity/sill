package me.saffer.sill.desktop

import me.saffer.sill.core.HostSettingsChange
import me.saffer.sill.core.QualityPreset
import me.saffer.sill.core.ui.PanelCopy
import me.saffer.sill.core.ui.SettingsField
import me.saffer.sill.core.ui.Symbol
import me.saffer.sill.core.ui.Type
import me.saffer.sill.swingui.ActionRow
import me.saffer.sill.swingui.Callout
import me.saffer.sill.swingui.MenuRow
import me.saffer.sill.swingui.RowGroup
import me.saffer.sill.swingui.SegmentedRow
import me.saffer.sill.swingui.SwitchRow
import me.saffer.sill.swingui.WrapLabel
import java.awt.Insets
import javax.swing.JComponent

/**
 * The Settings panel's rows (HostSettingsPanel.middle), in the iOS app's order with its words
 * (PanelCopy): the callouts, Quality, Resolution and Frame Rate, Prioritize Encoding Speed, Virtual
 * Display, Direct Wireless Connection, each with its footnote. Every control reads the ledger's
 * view and sends through [StreamFrame.pick]; nothing is sent when a state arrives.
 */
internal class SettingsView(private val frame: StreamFrame) {
    /** No settings 2 s after connecting: a Mac from before them. */
    var olderMac = false
    private var shownKey: String? = null
    // The live rows, updated in place while the panel's structure stays (so a switch slides, a segment moves).
    private var quality: MenuRow? = null
    private var resolution: SegmentedRow? = null
    private var frameRate: SegmentedRow? = null
    private var speed: SwitchRow? = null
    private var virtual: SwitchRow? = null
    private var direct: SwitchRow? = null

    private val device = "PC"

    fun rebuild(force: Boolean = false) {
        val host = frame.hostSettings()
        val shown = frame.displayedSettings()
        val pending = SettingsField.entries.map { frame.pendingSince(it) }
        // What decides which rows there are; the values alone are updated in place.
        val key = listOf(host != null && shown != null, host?.softwareEncoder, frame.problem,
            host?.link?.takeIf { it.isBehind }?.let { Triple(it.suggestedBitrate, it.suggestedCaptureScale, host.settings.bitrate) },
            shown?.directWireless != null, host?.persistent, host?.virtualDisplayNote, host?.virtualDisplayAvailable, olderMac, frame.mac, frame.wantedFps(),
            shown?.bitrate?.let { b -> QualityPreset.of(b) == null }).toString()
        val sheet = frame.settings
        sheet.title = PanelCopy.title(frame.mac)
        sheet.lines = host?.let { h -> listOfNotNull(PanelCopy.readout(h.stream), if (h.stream?.onVirtualDisplay == true) PanelCopy.onVirtualDisplay else null) } ?: emptyList()
        sheet.foot.long = PanelCopy.disconnect(PanelCopy.macName(frame.mac))
        if (!force && key == shownKey) { update(); return }
        shownKey = key
        val mac = PanelCopy.macName(frame.mac)
        val body = sheet.body
        body.removeAll()
        quality = null; resolution = null; frameRate = null; speed = null; virtual = null; direct = null
        fun footnote(text: String, warning: Boolean = false, top: Int = 6) = WrapLabel(text, Type.footnote, me.saffer.sill.core.ui.Palette.muted, Insets(top, 14, 12, 14), warning)
        val add: (JComponent) -> Unit = { body.add(it) }
        if (host != null && shown != null) {
            if (host.softwareEncoder) add(Callout(PanelCopy.softwareEncoder(mac)))
            frame.problem?.let { add(Callout(it)) }
            host.link?.takeIf { it.isBehind }?.let { l ->
                val now = QualityPreset.of(host.settings.bitrate)?.title ?: "this quality"
                val sug = l.suggestedBitrate?.let { QualityPreset.of(it) }
                val scale = l.suggestedCaptureScale?.let { s -> PanelCopy.resolutions.firstOrNull { it.second == s }?.first }
                val name = sug?.let { it.title + (scale?.let { s -> " · $s" } ?: "") }
                if (name != null) add(Callout(PanelCopy.linkCallout(now, name), PanelCopy.linkUse(name)) {
                    frame.pick(HostSettingsChange(bitrate = sug.bitrate, captureScale = l.suggestedCaptureScale))
                })
                else add(Callout("The link can’t carry $now."))
            }
            add(RowGroup(listOf(
                MenuRow(PanelCopy.quality, PanelCopy.qualityChoices(shown.bitrate), shown.bitrate) { frame.pick(HostSettingsChange(bitrate = it)) }
                    .also { quality = it },
                SegmentedRow(PanelCopy.resolution, PanelCopy.resolutions.map { it.first }, PanelCopy.resolutions.indexOfFirst { it.second == shown.captureScale }) { i ->
                    frame.pick(HostSettingsChange(captureScale = PanelCopy.resolutions[i].second))
                }.also { resolution = it },
                SegmentedRow(PanelCopy.frameRate, PanelCopy.frameRates.map { it.first }, PanelCopy.frameRates.indexOfFirst { it.second == shown.maxFPS }) { i ->
                    frame.pick(HostSettingsChange(maxFPS = PanelCopy.frameRates[i].second))
                }.also { frameRate = it },
            )))
            add(footnote(PanelCopy.streamFooter(device, frame.wantedFps())))
            add(RowGroup(listOf(SwitchRow(PanelCopy.prioritizeSpeed, shown.prioritizeSpeed) { frame.pick(HostSettingsChange(prioritizeSpeed = it)) }
                .also { speed = it })))
            add(footnote(PanelCopy.speedFooter(mac)))
            val unavailable = !host.virtualDisplayAvailable && !shown.virtualDisplay
            add(RowGroup(listOf(SwitchRow(PanelCopy.virtualDisplay, shown.virtualDisplay) { frame.pick(HostSettingsChange(virtualDisplay = it)) }
                .apply { enabledRow = !unavailable }.also { virtual = it })))
            val note = host.virtualDisplayNote
            if (note != null) add(footnote(note, warning = true)) else add(footnote(PanelCopy.virtualDisplayFooter(mac)))
            add(footnote(PanelCopy.appliesFooter(mac)))
            shown.directWireless?.let { direct ->
                add(RowGroup(listOf(SwitchRow(PanelCopy.directWireless, direct) { frame.pick(HostSettingsChange(directWireless = it)) }
                    .also { this.direct = it })))
                // A PC never reaches the Mac over peer-to-peer Wi-Fi, so never "connected directly".
                add(footnote(PanelCopy.directFooter(mac, device, direct, connectedDirectly = false)))
            }
            if (!host.persistent) add(footnote(PanelCopy.persistentNote))
        } else if (olderMac) {
            add(ActionRow(PanelCopy.olderMac(mac), accent = false, symbol = Symbol.UpdateCircle, onClick = null))
        } else {
            add(ActionRow(PanelCopy.loading, accent = false, onClick = null))
        }
        update()
        body.revalidate()
        body.repaint()
        frame.relayoutSettings()
    }

    /** The rows' values and spinners from the ledger's view. */
    private fun update() {
        val shown = frame.displayedSettings() ?: return
        quality?.apply { selected = shown.bitrate; choices = PanelCopy.qualityChoices(shown.bitrate); pendingSince = frame.pendingSince(SettingsField.Bitrate) }
        resolution?.apply { select(PanelCopy.resolutions.indexOfFirst { it.second == shown.captureScale }); pendingSince = frame.pendingSince(SettingsField.CaptureScale) }
        frameRate?.apply { select(PanelCopy.frameRates.indexOfFirst { it.second == shown.maxFPS }); pendingSince = frame.pendingSince(SettingsField.MaxFPS) }
        speed?.apply { set(shown.prioritizeSpeed); pendingSince = frame.pendingSince(SettingsField.PrioritizeSpeed) }
        virtual?.apply { set(shown.virtualDisplay); pendingSince = frame.pendingSince(SettingsField.VirtualDisplay) }
        direct?.apply { shown.directWireless?.let(::set); pendingSince = frame.pendingSince(SettingsField.DirectWireless) }
        frame.settings.repaint()
    }
}
