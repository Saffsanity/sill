import Foundation
import SillHostCore

/// Everything the status item, its card and its menu say, as plain values. Made by
/// `StatusText.present` from the host's snapshot, so the same words appear in the menu, the
/// tooltip, the log's "Status:" lines and the previews.
struct StatusPresentation: Equatable {
    /// A line with a symbol: the stream's source, or one device.
    struct Row: Equatable, Identifiable {
        var id: String
        var symbol: String
        var title: String
        var detail: String?
    }

    /// Something that needs the user, shown in the menu with an orange warning.
    struct Attention: Equatable, Identifiable {
        enum Action: Equatable { case allowScreenRecording, allowAccessibility, none }
        var title: String
        var subtitle: String
        var action: Action
        var id: String { title }
    }

    var glyph: StatusGlyph.State
    var header: String
    var subtitle: String?
    var source: Row?
    var devices: [Row]
    var attention: [Attention]
    /// Under the menu's Virtual Display item.
    var virtualDisplayNote: String
    var tooltip: String
    var accessibilityLabel: String
    /// The name devices see this Mac as, once Bonjour has registered it.
    var advertisedName: String?
}

/// Whether Sill holds its two permissions, as last read.
struct PermissionState: Equatable {
    var screenRecording: Bool
    var accessibility: Bool
}

/// The status copy. Title case in menus, sentence case in explanations, typographic quotes.
enum StatusText {
    static func present(snapshot s: HostStatusSnapshot, permissions: PermissionState,
                        startupError: String?, hasCoordinator: Bool) -> StatusPresentation {
        let (header, subtitle) = headline(s, permissions, startupError, hasCoordinator)

        var attention: [StatusPresentation.Attention] = []
        if !permissions.screenRecording {
            attention.append(.init(title: "Allow Screen Recording…", subtitle: "Needed to show your windows on your devices.",
                                   action: .allowScreenRecording))
        }
        if !permissions.accessibility {
            attention.append(.init(title: "Allow Accessibility…", subtitle: "Devices can watch but not click or type.",
                                   action: .allowAccessibility))
        }
        // Kept to one line no wider than the rest of the menu: a menu item's subtitle does not wrap.
        if s.softwareEncoder, s.hardwareEncoderStuck {
            attention.append(.init(title: "Hardware Encoder Stuck",
                                   subtitle: "Streaming with the software encoder, up to 60 fps. Restarting the Mac fixes this.",
                                   action: .none))
        } else if s.softwareEncoder {
            attention.append(.init(title: "Hardware Encoder Busy",
                                   subtitle: "Streaming with the software encoder, up to 60 fps, until it answers again.",
                                   action: .none))
        }

        // The attention glyph means "Sill needs you". The test pattern needs no permission.
        let glyph: StatusGlyph.State
        if startupError != nil || isFailed(s.network) || (!s.synthetic && !(permissions.screenRecording && permissions.accessibility)) {
            glyph = .attention
        } else if s.stream != nil {
            glyph = .streaming
        } else if !s.devices.isEmpty {
            glyph = .connected
        } else {
            glyph = .idle
        }

        var name: String?
        if case .advertising(let n) = s.network { name = n }

        return StatusPresentation(glyph: glyph, header: header, subtitle: subtitle,
                                  source: sourceRow(s), devices: s.devices.map(deviceRow), attention: attention,
                                  virtualDisplayNote: virtualDisplayNote(s),
                                  tooltip: "Sill — \(header)", accessibilityLabel: "Sill, \(header)",
                                  advertisedName: name)
    }

    /// The header and its explanation; the first match wins.
    private static func headline(_ s: HostStatusSnapshot, _ permissions: PermissionState, _ startupError: String?,
                                 _ hasCoordinator: Bool) -> (String, String?) {
        if let startupError { return ("Sill Couldn’t Start", startupError) }
        if !hasCoordinator { return ("Starting…", nil) }
        switch s.network {
        case .starting:
            return ("Starting…", nil)
        case .failed(let error):
            return ("Not Visible on the Network", "\(error). Quit and reopen Sill to try again.")
        case .waiting:
            return ("Waiting for the Network",
                    "Sill appears on your iPhone and iPad once this Mac is on Wi-Fi or Ethernet and Local Network access is allowed.")
        case .notAdvertised(let port):
            return ("Test Pattern Mode", "Not advertised; test clients connect to port \(port).")
        case .registering, .advertising:
            break
        }
        if !permissions.screenRecording {
            return ("Screen Recording Is Off", "Devices can connect but can’t see any windows.")
        }
        let count = s.devices.count
        if count > 0 {
            let who = count == 1 ? (s.devices[0].name.map(shortName) ?? "a Device") : "\(count) Devices"
            if s.stream != nil { return ("Streaming to \(who)", nil) }
            let connected = count == 1 ? (s.devices[0].name.map(shortName) ?? "Device") : "\(count) Devices"
            return ("\(connected) Connected", "Pick a window on the device to start streaming.")
        }
        if case .advertising(let name) = s.network {
            return ("Waiting for a Device", "Open Sill on your iPhone or iPad. This Mac appears as “\(name)”.")
        }
        return ("Waiting for a Device", "Registering on the local network…")
    }

    private static func isFailed(_ n: HostStatusSnapshot.Network) -> Bool {
        if case .failed = n { return true }
        return false
    }

    /// "iPad" from "iPad (iPad14,1)".
    static func shortName(_ device: String) -> String {
        let name = device.components(separatedBy: " (").first ?? device
        return name.isEmpty ? device : name
    }

    /// What streams: "Safari — Apple Developer" over "3024×1898 · 118 of 120 fps · 30 Mbps" (a still
    /// picture: "120 fps, still"), and with one device, how it is connected: "… · 30 Mbps · Wi-Fi".
    /// With two or more, each device's own row says it.
    private static func sourceRow(_ s: HostStatusSnapshot) -> StatusPresentation.Row? {
        guard let stream = s.stream else { return nil }
        let title: String, symbol: String
        switch stream.kind {
        case .window: title = middleTruncated(stream.title, to: 44); symbol = "macwindow"
        case .desktop: title = "Whole Desktop"; symbol = "menubar.dock.rectangle"
        case .testPattern: title = "Test Pattern"; symbol = "checkerboard.rectangle"
        }
        // The encoder only produces a frame when the picture changed (ScreenCaptureKit delivers
        // frames on repaint), so 0 means a still window, not a stalled stream. "120 fps, still" is
        // about as wide as a one-digit count ("5 of 120 fps"), so a row wraps the same still as
        // changing, unless the count's own digits tip it: the open menu resizes the card on every
        // change, and "nothing changing" with the route word made it jump a line each time a
        // window stopped or started changing.
        let rate = s.encodedFPS > 0 ? "\(min(s.encodedFPS, stream.fps)) of \(stream.fps) fps" : "\(stream.fps) fps, still"
        var detail = "\(stream.width)×\(stream.height) · \(rate) · \(stream.mbps) Mbps"
        if s.devices.count == 1, let route = s.devices[0].route { detail += " · \(word(route))" }
        if stream.onVirtualDisplay {
            detail += " · virtual display"
        } else if s.virtualDisplayOn, stream.kind == .window {
            detail += " · real window (virtual display: \(s.lastStageFailure ?? s.virtualDisplayProblem ?? "unavailable"))"
        }
        if stream.softwareEncoder { detail += " · software encoder" }
        return StatusPresentation.Row(id: "source", symbol: symbol, title: title, detail: detail)
    }

    /// "iPad (iPad14,1)" over "118 fps · frame age 9 ms · RTT 7 ms · Wi-Fi"; the address until the
    /// device's first report (within a second), and until then the route alone. A second without
    /// a sample reads "–", as in the host's log line and the device's HUD: a still window sends no
    /// frames (ScreenCaptureKit delivers only repaints), and a second can pass without a pong.
    private static func deviceRow(_ d: HostStatusSnapshot.Device) -> StatusPresentation.Row {
        let name = d.name ?? d.endpoint
        let symbol = name.localizedCaseInsensitiveContains("iphone") ? "iphone" : "ipad"
        var parts: [String] = []
        if let fps = d.fps, let age = d.frameAgeMs, let rtt = d.rttMs {
            parts.append("\(fps) fps · frame age \(ms(age)) · RTT \(ms(rtt))")
        }
        if let route = d.route { parts.append(word(route)) }
        return StatusPresentation.Row(id: String(describing: d.id), symbol: symbol, title: name,
                                      detail: parts.isEmpty ? nil : parts.joined(separator: " · "))
    }

    /// How a device reaches this Mac, from this Mac's side of its connection (ClientLink.route):
    /// the words the device's connect screen and Settings panel use. "Wi-Fi" has a non-breaking
    /// hyphen, so a wrapped detail never splits it.
    private static func word(_ route: ClientLink.Route) -> String {
        switch route {
        case .wired: return "Wired"
        case .wifi: return "Wi\u{2011}Fi"
        case .direct: return "Direct"
        }
    }

    /// One of a device's reported times. Negative is the client's "no sample this second" (-1),
    /// never a time.
    private static func ms(_ v: Int) -> String { v < 0 ? "–" : "\(v) ms" }

    private static func virtualDisplayNote(_ s: HostStatusSnapshot) -> String {
        if let problem = s.virtualDisplayProblem { return "Unavailable: \(problem)" }
        if s.virtualDisplayOn, s.stream?.onVirtualDisplay == true { return "The streamed window is on the virtual display" }
        return "Picked windows leave this screen while they stream"
    }

    /// "Safari — A very long window title that goes on" → "Safari — A very long…that goes on".
    static func middleTruncated(_ text: String, to limit: Int) -> String {
        guard text.count > limit, limit > 1 else { return text }
        let keep = limit - 1
        return String(text.prefix((keep + 1) / 2)) + "…" + String(text.suffix(keep / 2))
    }
}
