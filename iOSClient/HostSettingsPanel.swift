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
/// where the room under the bar is short (259 pt in the compact halves at 500×710, an iPad window
/// that narrow; 275 on an iPhone SE on its side), so the header and Disconnect are always in reach.
///
/// Every control shows `client.settings.displayed` (the Mac's value with this device's unanswered
/// pick over it) and sends through `client.changeSettings`, one field per control, from its action
/// only. Errors show inline, never in alerts. The last group, This iPad (or iPhone), is the device's
/// own: its switch is a preference here (`StreamClient.gesturesKey`) and sends nothing to the Mac;
/// its rows, as accessibility actions, do their gestures (`client.sendGesture`), since VoiceOver
/// keeps three fingers for itself.
struct HostSettingsPanel: View {
    @ObservedObject var client: StreamClient
    /// Done, Esc or ⌘., and the VoiceOver escape gesture.
    let close: () -> Void
    /// Pair This iPad…: the stream screen puts the panel away and covers the stream with the
    /// pairing overlay.
    var pairThisDevice: () -> Void = {}

    @AccessibilityFocusState private var headerFocused: Bool
    /// Two seconds on this connection and still no state: the Mac runs a Sill without settings.
    @State private var olderMac = false
    /// Bumped when Low Power Mode toggles, so the frame rate note is read again.
    @State private var powerState = 0
    /// This device's switch for three-finger gestures (docs/trackpad-gestures-plan.md §8): on unless
    /// turned off, read by `StreamClient.sendGesture` at each gesture, never sent.
    @AppStorage(StreamClient.gesturesKey) private var gesturesOn = true
    /// VoiceOver is on: it keeps three-finger swipes and taps for itself, so the This iPad group says
    /// its rows do the gestures instead.
    @State private var voiceOver = HostSettingsPanel.voiceOverRunning

    private var mac: String { client.macName.isEmpty ? "the Mac" : client.macName }
    private static let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
    /// DEBUG `-SillSettingsEnd 1`: the rows start scrolled to their end, so a photo of a short
    /// screen shows the last groups (Direct Wireless, Away from home, This iPad).
    private static var startsAtEnd: Bool {
        #if DEBUG
        return UserDefaults.standard.bool(forKey: "SillSettingsEnd")
        #else
        return false
        #endif
    }
    /// DEBUG `-SillSettingsScroll gestures`: the rows start scrolled to the This iPad group, so a
    /// photo of a short screen shows its switch and rows, which the footnote under them pushes out
    /// of `-SillSettingsEnd`'s view.
    private static var startsAtGestures: Bool {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "SillSettingsScroll") == "gestures"
        #else
        return false
        #endif
    }
    private static let gesturesGroupID = "thisDevice"
    /// `UIAccessibility.isVoiceOverRunning`; DEBUG `-SillVoiceOver 1` says it is, for the harness's
    /// photos of the group's VoiceOver footnote.
    static var voiceOverRunning: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "SillVoiceOver") { return true }
        #endif
        return UIAccessibility.isVoiceOverRunning
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            // The rows at their own height when they fit, a scroll view in the room left when not.
            ViewThatFits(in: .vertical) {
                middle
                ScrollViewReader { reader in
                    ScrollView { middle }
                        .scrollIndicatorsFlash(onAppear: true)
                        .scrollBounceBehavior(.basedOnSize)
                        .defaultScrollAnchor(Self.startsAtEnd ? .bottom : .top)
                        .onAppear { if Self.startsAtGestures { reader.scrollTo(Self.gesturesGroupID, anchor: .top) } }
                }
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
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification).receive(on: RunLoop.main)) { _ in
            voiceOver = Self.voiceOverRunning
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
                        // value keeps its unit (no-break spaces), and a wrap falls after a "·".
                        // It ends in how this device's connection reaches the Mac, the connect
                        // screen's word; "Direct" is the old "Connected directly" line.
                        Text(Self.readout(state.stream, route: client.route))
                            .fixedSize(horizontal: false, vertical: true)
                        // Its own line: beside the numbers it never fit the panel's width, and it
                        // is what confirms the Virtual Display switch took effect.
                        if state.stream?.onVirtualDisplay == true {
                            Text("On the virtual display")
                        }
                        // From afar, how, with the round trip (it needs no clock agreement between
                        // the two devices, unlike frame age); the readout above then ends in the
                        // bitrate. Wraps like the readout (larger text on the outer display cut it
                        // off), after a "·" as the readout does, and never inside the route: its
                        // spaces are no-break ones, as on the Mac's card (at xxLarge on the outer
                        // display it read "Connected through" / "Tailscale · 48 ms").
                        if let r = remoteRoute {
                            Text("Connected \(r.phrase.replacingOccurrences(of: " ", with: "\u{00A0}"))\u{00A0}· \(Self.rttText(client.linkStats))")
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Palette.muted)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Self.spokenReadout(state.stream, route: client.route, remote: remoteRoute,
                                                           rttMs: client.linkStats?.rtt?.median))
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
                    // Neither a restart nor a return is promised: hosts before 2026-09-25 keep the
                    // software encoder until they relaunch, newer ones go back by themselves.
                    Callout(text: "\(mac)’s hardware encoder is busy or not responding, so for now streams run at up to 60 fps at Standard.")
                }
                if let problem = client.settingsProblem {
                    Callout(text: problem)
                }
                // Away from home on a slow link: what helps. It goes when the link recovers, and
                // with the panel.
                if remoteRoute != nil, client.slowLink {
                    Callout(text: "The picture is arriving slowly from \(mac). Choose Low quality or Standard resolution.")
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
                // changed row with the longest footer (the compact halves' 259 pt shows the rest
                // first). Disabled only away from home (the Mac refuses it from a remote connection):
                // off from a directly connected device is allowed, as on the Mac, and its consequence
                // is written beside it. No row for a host without it.
                if let direct = shown.directWireless {
                    Rows {
                        Toggle(isOn: binding(direct) { HostSettingsChange(directWireless: $0) }) {
                            RowTitle(title: "Direct Wireless Connection", since: client.settings.pendingSince(.directWireless))
                        }
                        // A warning about turning it off, so only while the switch shows on.
                        .accessibilityHint(client.connectedDirectly && direct ? "Turning this off disconnects this \(device)." : "")
                        // From afar the Mac refuses it anyway: how devices near the Mac reach it is
                        // theirs and the Mac's to change.
                        .disabled(remoteRoute != nil)
                        .rowFrame()
                    }
                    Footnote(text: remoteRoute != nil ? "Change this on \(mac), or from a device near it." : directFooter(on: direct))
                }
                if !state.persistent {
                    Footnote(text: "SillHost keeps these until it quits.")
                }
                awayFromHome
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
            // After everything of the Mac's, whatever state its settings are in: while they load, and
            // for a Mac without them too.
            thisDevice
        }
    }

    /// Most-changed first, so the compact halves' 259 pt shows Quality, Resolution and Frame Rate
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

    // MARK: Away from home

    /// This connection's way in from afar, when it is one.
    private var remoteRoute: RemoteRoute? { client.remoteRoute }

    /// The last group (docs/remote-access-plan.md §7.11): whether this device can reach the Mac
    /// away from home, from the Mac's kind 18. None from an older Mac (no kind 18 on this connection).
    @ViewBuilder private var awayFromHome: some View {
        if let info = client.macInfo {
            Text("Away from home")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 14)
                .padding(.top, 6)
                .padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)
            if client.macInfoSaved {
                Rows {
                    Label("Paired for remote access", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Palette.text)
                        .rowFrame()
                }
                if let r = remoteRoute {
                    Footnote(text: "Connected \(r.phrase).")
                } else {
                    Footnote(text: "Away from home, Sill reaches \(mac) \(Self.reach(info)).")
                }
            } else if info.remoteAccess {
                Rows {
                    Button(action: pairThisDevice) {
                        Text("Pair This \(device)…")
                            .foregroundStyle(Palette.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .rowFrame()
                }
                Footnote(text: "Pair once to reach \(mac) through your VPN or the internet. \(mac) shows a code; scan it with this \(device).")
            } else {
                Footnote(text: "To reach \(mac) away from home, turn on Remote Access in Sill’s Settings on the Mac.")
            }
        }
    }

    // MARK: This device

    /// The last group: this device's own switch for three-finger gestures, and what each does when
    /// the Mac takes them. Last because it is the least changed, and the compact halves' 259 pt show
    /// the Mac's rows first. The switch reaches nothing; a row, activated by VoiceOver, Voice Control
    /// or Switch Control, does its gesture on the Mac as three fingers would (`sendGesture`: the
    /// switch, the Mac's `gestures`, the Desktop first while a window streams).
    @ViewBuilder private var thisDevice: some View {
        Text("This \(device)")
            .font(.footnote.weight(.medium))
            .foregroundStyle(Palette.muted)
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
            .id(Self.gesturesGroupID)
        Rows {
            Toggle(isOn: $gesturesOn) {
                Text("Three-Finger Gestures").foregroundStyle(Palette.text)
            }
            .rowFrame()
            if gesturesOn, macTakesGestures {
                ForEach(Self.gestureRows, id: \.gesture) { row in
                    RowDivider()
                    GestureRow(symbol: row.symbol, gesture: row.gesture, action: row.action, does: row.does) {
                        _ = client.sendGesture($0, fingers: 3)
                    }
                }
            }
        }
        Footnote(text: gesturesFooter)
    }

    /// The Mac's window list said it takes the gestures (`WindowList.gestures`).
    private var macTakesGestures: Bool { (client.hostGestures ?? 0) >= TrackpadGesture.generation }

    /// What each gesture does on the Mac, and what the row does as an accessibility action: its one
    /// gesture, or, for the Spaces, one action each way (natural direction: a swipe left brings the
    /// Space on the right). The pinch opens Launchpad on macOS 14 and 15, from the same key.
    private static let gestureRows: [(symbol: String, gesture: String, action: String, does: [GestureRow.Action])] = [
        ("arrow.up", "Swipe Up", "Mission Control", [GestureRow.Action(name: "Mission Control", gesture: .swipeUp)]),
        ("arrow.down", "Swipe Down", "App Exposé", [GestureRow.Action(name: "App Exposé", gesture: .swipeDown)]),
        ("arrow.left.and.right", "Swipe Left or Right", "Spaces", [GestureRow.Action(name: "Space on the Right", gesture: .swipeLeft),
                                                                   GestureRow.Action(name: "Space on the Left", gesture: .swipeRight)]),
        ("arrow.down.right.and.arrow.up.left", "Pinch", "Apps", [GestureRow.Action(name: "Apps", gesture: .pinch)]),
        ("arrow.up.left.and.arrow.down.right", "Spread", "Show Desktop", [GestureRow.Action(name: "Show Desktop", gesture: .spread)]),
    ]

    /// Under the switch: where the gestures go and what they do, or why nothing happens.
    private var gesturesFooter: String {
        guard gesturesOn else { return "Three-finger strokes do nothing while this is off." }
        guard macTakesGestures else { return "Update Sill on \(mac) to use these." }
        // VoiceOver keeps three-finger swipes and taps for itself, and no touch of them reaches Sill.
        var text = voiceOver ? "VoiceOver keeps three-finger gestures for itself, so the rows above do them on \(mac) instead."
            : "Three fingers on the trackpad or over the stream."
        text += " While a window streams, a gesture shows the Desktop first, and the opposite gesture closes what one opened. \(mac) does these with its own keyboard shortcuts: one turned off in its Keyboard settings does nothing."
        if device == "iPad" { text += " Four-finger swipes and a Magic Keyboard trackpad’s gestures stay with iPadOS." }
        return text
    }

    /// "through Tailscale (mac-mini.tail1234.ts.net)": the first VPN or internet address the Mac
    /// gave; otherwise "through your VPN or the internet".
    static func reach(_ info: MacInfo) -> String {
        guard let a = info.addresses.first(where: { $0.kind == MacAddress.vpn || $0.kind == MacAddress.internet }) else {
            return "through your VPN or the internet"
        }
        if a.kind == MacAddress.internet { return "over the internet (\(a.host))" }
        let name = a.via.isEmpty || a.via.hasPrefix("VPN (") ? "your VPN" : a.via
        return "through \(name) (\(a.host))"
    }

    // MARK: Copy

    /// Under the Mac's name: what actually runs, which confirms a change took effect and shows
    /// what the software encoder caps, then how this device's connection reaches the Mac
    /// ("… · 15 Mbps · Wi-Fi"; StreamClient.route), when its path says (never on a remote session:
    /// its route line says how instead). Whether it runs on the virtual display is a line of its
    /// own (see `header`). A no-break space before each "·" keeps it with the value before it, so a
    /// wrap at larger text never starts a line with one.
    static func readout(_ stream: RunningStream?, route: DiscoveryPolicy.Method? = nil) -> String {
        let values = stream.map { ["\($0.width)×\($0.height)", "\($0.fps)\u{00A0}fps", "\($0.mbps)\u{00A0}Mbps"] } ?? ["Not streaming"]
        return (values + [route?.word].compactMap { $0 }).joined(separator: "\u{00A0}· ")
    }

    /// "48 ms", the last second's median round trip; "–" for a second without a pong.
    static func rttText(_ stats: StreamClient.LinkStats?) -> String {
        stats?.rtt.map { "\($0.median)\u{00A0}ms" } ?? "–"
    }

    /// The readout as VoiceOver says it, ending in how this device reaches the Mac: its link, or
    /// from afar the remote route with the round trip, which wins (a remote session has no link
    /// word; see `header`).
    static func spokenReadout(_ stream: RunningStream?, route: DiscoveryPolicy.Method? = nil, remote: RemoteRoute? = nil,
                              rttMs: Int? = nil) -> String {
        var link = route.map { ", " + spoken($0) } ?? ""
        if let remote {
            link = ", connected \(remote.phrase)" + (rttMs.map { ", \($0) millisecond round trip" } ?? "")
        }
        guard let s = stream else { return "Not streaming" + link }
        return "Streaming \(s.width) by \(s.height), \(s.fps) frames per second, \(s.mbps) megabits per second"
            + (s.onVirtualDisplay ? ", on the virtual display" : "") + link
    }

    /// The route as VoiceOver says it: a sentence's end rather than the bare word.
    private static func spoken(_ route: DiscoveryPolicy.Method) -> String {
        switch route {
        case .wired: return "connected by cable"
        case .wifi: return "connected over Wi-Fi"
        case .direct: return "connected directly"
        }
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
    /// nothing for it, which is worth saying on a 60 Hz device; away from home this device asks
    /// for 60 fps.
    private var streamFooter: String {
        _ = powerState
        var text = "Quality is per 60 fps; a 120 fps stream gets twice as much. " + QualityPreset.fastLinkNote
        let away = client.awayCapsFrameRate
        let wanted = StreamClient.wantedFPS(remote: away)
        guard wanted < 120 else { return text }
        if away, StreamClient.wantedFPS() > wanted {
            text += " Away from home, this \(device) asks for \(wanted) fps, which halves the data your Mac sends."
        } else if ProcessInfo.processInfo.isLowPowerModeEnabled, StreamClient.screenMaximumFPS() >= 120 {
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

/// One gesture and what it does on the Mac: the words side by side when they fit and stacked when
/// larger text leaves no room, never cut off; one VoiceOver element ("Swipe Up, Mission Control").
/// A touch does nothing here; activated by VoiceOver, Voice Control or Switch Control (which cannot
/// make three-finger strokes, or keep them) it does its gesture: a button for one, a named action
/// each way for the Spaces.
private struct GestureRow: View {
    struct Action { let name: String; let gesture: TrackpadGestures.Gesture }
    let symbol: String
    let gesture: String
    let action: String
    let does: [Action]
    let perform: (TrackpadGestures.Gesture) -> Void
    /// Measured afresh when the text size changes, as `AdaptiveRow` is.
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        if let only = does.first, does.count == 1 {
            row.accessibilityAddTraits(.isButton).accessibilityAction { perform(only.gesture) }
        } else {
            row.accessibilityActions {
                ForEach(does, id: \.name) { item in Button(item.name) { perform(item.gesture) } }
            }
        }
    }
    private var row: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                icon
                Text(gesture).foregroundStyle(Palette.text)
                Spacer(minLength: 8)
                Text(action).foregroundStyle(Palette.muted)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                icon
                VStack(alignment: .leading, spacing: 2) {
                    Text(gesture).foregroundStyle(Palette.text)
                    Text(action).foregroundStyle(Palette.muted)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 8)
        }
        .id(typeSize)
        .rowFrame()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(gesture), \(action)")
    }
    private var icon: some View {
        Image(systemName: symbol)
            .foregroundStyle(Palette.muted)
            .frame(width: 24)
            .accessibilityHidden(true)
    }
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
