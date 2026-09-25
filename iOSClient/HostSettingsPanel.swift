import SwiftUI
import UIKit
import StreamProtocol

/// The Settings panel: the Mac's streaming settings, changed from here the way the Sill menu on
/// the Mac changes them (one change, one apply, at most one short restart; Sill.app saves them).
///
/// A panel in the view hierarchy, mirroring the Apps drawer on the trailing edge; not a sheet,
/// popover or Menu. The client has no system presentation anywhere; sheets and popovers adapt by
/// size class, which is unknown for the Duo; the layout harness draws a fake Duo screen inside an
/// iPad window, which a system presentation would escape; and a tall sheet or a flipped popover
/// could cross the half-folded crease. Its height follows its content; only the middle scrolls,
/// where the room under the bar is short (259 pt on the outer display in portrait), so the header
/// and Disconnect are always in reach.
///
/// Every control shows `client.settings.displayed` (the Mac's value with this device's unanswered
/// pick over it) and sends through `client.changeSettings`, one field per control, from its action
/// only. Errors show inline, never in alerts.
struct HostSettingsPanel: View {
    @ObservedObject var client: StreamClient
    /// Done, Esc or ⌘., and the VoiceOver escape gesture.
    let close: () -> Void

    @AccessibilityFocusState private var headerFocused: Bool
    /// Two seconds on this connection and still no state: the Mac runs a Sill without settings.
    @State private var olderMac = false
    /// Bumped when Low Power Mode toggles, so the frame rate note is read again.
    @State private var powerState = 0

    private var mac: String { client.macName.isEmpty ? "the Mac" : client.macName }
    private static let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

    var body: some View {
        VStack(spacing: 0) {
            header
            // The rows at their own height when they fit, a scroll view in the room left when not.
            ViewThatFits(in: .vertical) {
                middle
                ScrollView { middle }
                    .scrollIndicatorsFlash(onAppear: true)
                    .scrollBounceBehavior(.basedOnSize)
            }
            foot
        }
        .padding(14)
        .background(Self.shape.fill(Palette.bar))
        .overlay(Self.shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
        .shadow(color: .black.opacity(0.65), radius: 30, x: 0, y: 24)
        .tint(Palette.accent)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        // VoiceOver stays inside while it is open, the escape gesture closes it, and focus starts
        // on the Mac's name.
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, close)
        .onAppear { headerFocused = true }
        // A refused change: the control has already gone back to the Mac's value, and the reason
        // is in the footer or the note. The haptic is a no-op on an iPad.
        .sensoryFeedback(.warning, trigger: client.settingsRefusals)
        .onChange(of: client.settingsRefusals) { _, _ in
            AccessibilityNotification.Announcement("\(mac) kept its setting").post()
        }
        .onChange(of: client.settingsProblem) { _, problem in
            if let problem { AccessibilityNotification.Announcement(problem).post() }
        }
        .task(id: client.connectedAt) {
            olderMac = false
            let elapsed = client.connectedAt.map { Date().timeIntervalSince($0) } ?? 0
            if elapsed < 2 { try? await Task.sleep(for: .seconds(2 - elapsed)) }
            if !Task.isCancelled { olderMac = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange).receive(on: RunLoop.main)) { _ in
            powerState += 1
        }
    }

    // MARK: Header and foot (pinned)

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(client.macName.isEmpty ? "Mac" : client.macName)
                    .font(.headline)
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($headerFocused)
                if let state = client.settings.host {
                    VStack(alignment: .leading, spacing: 1) {
                        // Wraps rather than cutting the bitrate off at larger text sizes; each
                        // value keeps its unit (no-break spaces).
                        Text(Self.readout(state.stream))
                            .fixedSize(horizontal: false, vertical: true)
                        // Its own line: beside the numbers it never fit the panel's width, and it
                        // is what confirms the Virtual Display switch took effect.
                        if state.stream?.onVirtualDisplay == true {
                            Text("On the virtual display")
                        }
                        // How this device reaches the Mac: over peer-to-peer Wi-Fi, which the Direct
                        // Wireless Connection row can turn off.
                        if client.connectedDirectly {
                            Text("Connected directly")
                        }
                    }
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Palette.muted)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Self.spokenReadout(state.stream, direct: client.connectedDirectly))
                }
            }
            Spacer(minLength: 8)
            // A 44 pt tall tap area (the word alone is about 42×22) without moving the header: the
            // padding and the shape sit inside the label, which is what the button hit-tests, and
            // the layout takes them back outside.
            Button(action: close) {
                Text("Done")
                    .padding(.vertical, 11)
                    .padding(.horizontal, 4)
                    .contentShape(Rectangle())
            }
            .padding(.vertical, -11)
            .padding(.horizontal, -4)
            .font(.body.weight(.semibold))
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 12)
    }

    /// Disconnect, in Leave's old place of honour: the bar's last slot is Settings now.
    private var foot: some View {
        Button(action: { client.disconnect() }) {
            // The header already names the Mac: when a long name leaves no room, "Disconnect"
            // alone says enough (a truncated "Disconnect from…ah's MacBook Pro" read badly).
            ViewThatFits(in: .horizontal) {
                Label("Disconnect from \(mac)", systemImage: "xmark.circle").lineLimit(1)
                Label("Disconnect", systemImage: "xmark.circle").lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.accent)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.control))
        .accessibilityLabel("Disconnect from \(mac)")
        .padding(.top, 10)
    }

    // MARK: Middle (scrolls when short)

    @ViewBuilder private var middle: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let state = client.settings.host, let shown = client.settings.displayed {
                if state.softwareEncoder {
                    Callout(text: "\(mac)’s hardware encoder isn’t responding, so streams run at up to 60 fps at Standard until the Mac restarts.")
                }
                if let problem = client.settingsProblem {
                    Callout(text: problem)
                }
                streamRows(shown)
                Footnote(text: streamFooter)
                // As in the Mac's Settings › Streaming: its own group, the Mac's name for it, and
                // what it trades away.
                Rows {
                    Toggle(isOn: binding(shown.prioritizeSpeed) { HostSettingsChange(prioritizeSpeed: $0) }) {
                        RowTitle(title: "Prioritize Encoding Speed", since: client.settings.pendingSince(.prioritizeSpeed))
                    }
                    .rowFrame()
                }
                Footnote(text: "Lower latency when \(mac) is busy, at a softer picture.")
                Rows {
                    let unavailable = !state.virtualDisplayAvailable && !shown.virtualDisplay
                    Toggle(isOn: binding(shown.virtualDisplay) { HostSettingsChange(virtualDisplay: $0) }) {
                        RowTitle(title: "Virtual Display", since: client.settings.pendingSince(.virtualDisplay))
                    }
                    // Off and impossible on this host: disabled, the reason under it. On, it can
                    // always be turned off, as from the Mac's own menu.
                    .disabled(unavailable)
                    .accessibilityHint(state.virtualDisplayNote ?? "")
                    .rowFrame()
                }
                if let note = state.virtualDisplayNote {
                    Footnote(text: note, warning: true)
                } else {
                    Footnote(text: "The window you pick moves onto an invisible display on \(mac) while it streams, so it keeps updating when covered.")
                }
                Footnote(text: "Applies to every device streaming from \(mac). The stream restarts for a moment.")
                // Direct Wireless Connection: how devices reach the Mac, not how it streams; after the
                // closing footer, whose "the stream restarts" is not true of it, and last, the least
                // changed row with the longest footer (the outer display's 259 pt shows the rest
                // first). Never disabled: off from a directly connected device is allowed, as on the
                // Mac, and its consequence is written beside it. No row for a host without it.
                if let direct = shown.directWireless {
                    Rows {
                        Toggle(isOn: binding(direct) { HostSettingsChange(directWireless: $0) }) {
                            RowTitle(title: "Direct Wireless Connection", since: client.settings.pendingSince(.directWireless))
                        }
                        // A warning about turning it off, so only while the switch shows on.
                        .accessibilityHint(client.connectedDirectly && direct ? "Turning this off disconnects this \(device)." : "")
                        .rowFrame()
                    }
                    Footnote(text: directFooter(on: direct))
                }
                if !state.persistent {
                    Footnote(text: "SillHost keeps these until it quits.")
                }
            } else if olderMac {
                Label("Update Sill on \(mac) to change these from here.", systemImage: "arrow.down.circle")
                    .font(.body)
                    .foregroundStyle(Palette.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 4)
            } else {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(Palette.muted)
                    Text("Loading settings…")
                }
                .font(.footnote)
                .foregroundStyle(Palette.muted)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 4)
            }
        }
    }

    /// Most-changed first, so the outer display's 259 pt shows Quality, Resolution and Frame Rate
    /// before anything scrolls.
    private func streamRows(_ shown: StreamSettings) -> some View {
        Rows {
            AdaptiveRow(title: "Quality", since: client.settings.pendingSince(.bitrate)) {
                Picker("Quality", selection: binding(shown.bitrate) { HostSettingsChange(bitrate: $0) }) {
                    ForEach(QualityPreset.allCases) { Text($0.title).tag($0.rawValue) }
                    if QualityPreset(rawValue: shown.bitrate) == nil {
                        // Set by hand on the Mac: shown, never offered (the Mac's menu does the same).
                        Text(QualityPreset.title(forBitrate: shown.bitrate)).tag(shown.bitrate)
                    }
                }
                .pickerStyle(.menu)
                .fixedSize()     // one line; the row stacks instead when it does not fit beside the title
            }
            RowDivider()
            AdaptiveRow(title: "Resolution", since: client.settings.pendingSince(.captureScale)) {
                Picker("Resolution", selection: binding(shown.captureScale) { HostSettingsChange(captureScale: $0) }) {
                    Text("Retina").tag(2.0)
                    Text("Standard").tag(1.0)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            RowDivider()
            AdaptiveRow(title: "Frame Rate", since: client.settings.pendingSince(.maxFPS)) {
                // A Mac-held value such as 90 selects no segment, as on the Mac.
                Picker("Frame Rate", selection: binding(shown.maxFPS) { HostSettingsChange(maxFPS: $0) }) {
                    Text("60 fps").tag(60)
                    Text("120 fps").tag(120)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
    }

    /// Shows the value the panel displays; moving the control sends that one field. Nothing else
    /// ever sends (not `onChange(of:)`, not a state arriving).
    private func binding<V>(_ value: V, _ change: @escaping (V) -> HostSettingsChange) -> Binding<V> {
        Binding(get: { value }, set: { client.changeSettings(change($0)) })
    }

    // MARK: Copy

    /// Under the Mac's name: what actually runs, which confirms a change took effect and shows
    /// what the software encoder caps. Whether it runs on the virtual display is a line of its own
    /// (see `header`).
    static func readout(_ stream: RunningStream?) -> String {
        guard let s = stream else { return "Not streaming" }
        return "\(s.width)×\(s.height) · \(s.fps)\u{00A0}fps · \(s.mbps)\u{00A0}Mbps"
    }

    static func spokenReadout(_ stream: RunningStream?, direct: Bool = false) -> String {
        let link = direct ? ", connected directly" : ""
        guard let s = stream else { return "Not streaming" + link }
        return "Streaming \(s.width) by \(s.height), \(s.fps) frames per second, \(s.mbps) megabits per second"
            + (s.onVirtualDisplay ? ", on the virtual display" : "") + link
    }

    /// "iPhone" or "iPad", for copy about this device.
    private var device: String { UIDevice.current.userInterfaceIdiom == .phone ? "iPhone" : "iPad" }

    /// Under the Direct Wireless Connection row: what it does and costs, and, while the switch shows
    /// on and this device is connected over it, what turning it off does to this device: the Mac
    /// disconnects every device on peer-to-peer Wi-Fi once its listener has changed (1.5 s), and a
    /// device still connected directly shares no network the Mac is listed on (one that does moves
    /// to it by itself), so it cannot come back until it does. Once the switch shows off (turned
    /// off here or on the Mac, with this connection still up for that moment) the warning is moot.
    private func directFooter(on: Bool) -> String {
        var text = "Lets devices reach \(mac) without a shared Wi\u{2011}Fi network, the way AirDrop does. While it’s on, streaming over Wi\u{2011}Fi can stutter."
        if on, client.connectedDirectly { text += " This \(device) is connected directly: turning this off disconnects it." }
        return text
    }

    /// Under the stream rows: what Quality counts and what its top presets need (the Mac's
    /// Settings › Streaming says the same). A frame rate limit above what this screen shows changes
    /// nothing for it, which is worth saying on a 60 Hz device.
    private var streamFooter: String {
        _ = powerState
        var text = "Quality is per 60 fps; a 120 fps stream gets twice as much. " + QualityPreset.fastLinkNote
        let wanted = StreamClient.wantedFPS()
        guard wanted < 120 else { return text }
        if ProcessInfo.processInfo.isLowPowerModeEnabled, StreamClient.screenMaximumFPS() >= 120 {
            text += " Low Power Mode holds this \(device) to \(wanted) fps."
        } else {
            text += " This \(device) shows up to \(wanted) fps."
        }
        return text
    }
}

// MARK: - Rows

/// An inset group of rows on the drawer's control colour.
private struct Rows<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.control))
    }
}

/// A row's title with the pending spinner beside it.
private struct RowTitle: View {
    let title: String
    let since: Double?
    var body: some View {
        HStack(spacing: 6) {
            Text(title).foregroundStyle(Palette.text)
            PendingSpinner(since: since)
        }
    }
}

/// A title with its control beside it, or under it when larger text leaves no room beside.
private struct AdaptiveRow<Control: View>: View {
    let title: String
    let since: Double?
    let control: Control
    /// A text size change while the panel is open left the menu picker measured at the old size
    /// (seen going from accessibility sizes back to Large: the row stayed stacked), so the row is
    /// rebuilt, and measured afresh, whenever it changes.
    @Environment(\.dynamicTypeSize) private var typeSize
    init(title: String, since: Double?, @ViewBuilder control: () -> Control) {
        self.title = title; self.since = since; self.control = control()
    }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                label
                Spacer(minLength: 8)
                control
            }
            VStack(alignment: .leading, spacing: 8) {
                label
                control
            }
            .padding(.vertical, 8)
        }
        .id(typeSize)
        .rowFrame()
    }
    /// The control carries the same title for VoiceOver, so this one is not read twice.
    private var label: some View { RowTitle(title: title, since: since).accessibilityHidden(true) }
}

/// A hairline between rows, inset like the system's.
private struct RowDivider: View {
    var body: some View {
        Rectangle().fill(Color.white.opacity(0.08)).frame(height: 0.5).padding(.leading, 14)
    }
}

/// A small spinner shown only once a pick has waited 300 ms for its answer: a quick Mac never
/// makes it flicker.
private struct PendingSpinner: View {
    let since: Double?
    @State private var shown = false
    var body: some View {
        ZStack {
            if shown { ProgressView().controlSize(.small).tint(Palette.muted) }
        }
        .frame(width: shown ? nil : 0)
        .accessibilityHidden(true)
        .task(id: since) {
            shown = false
            guard let since else { return }
            let wait = 0.3 - (ProcessInfo.processInfo.systemUptime - since)
            if wait > 0 { try? await Task.sleep(for: .seconds(wait)) }
            if !Task.isCancelled { shown = true }
        }
    }
}

/// A group's footer: small, muted, from the leading edge; orange with a warning sign for a problem.
private struct Footnote: View {
    let text: String
    var warning = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if warning { Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true) }
            Text(text)
        }
        .font(.footnote)
        .foregroundStyle(warning ? Color.orange : Palette.muted)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }
}

/// Something to know before touching anything: the Mac did not answer, or its hardware encoder
/// is down. Above the groups.
private struct Callout: View {
    let text: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).accessibilityHidden(true)
            Text(text).foregroundStyle(Palette.text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.orange.opacity(0.14)))
        .accessibilityElement(children: .combine)
        .padding(.bottom, 10)
    }
}

private extension View {
    /// A row inside a group: at least 44 pt tall, inset 14 pt.
    func rowFrame() -> some View {
        frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.horizontal, 14)
    }
}
