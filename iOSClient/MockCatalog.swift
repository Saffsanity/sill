#if DEBUG
import UIKit
import StreamProtocol

/// DEBUG-only stand-in for a live session, used by the layout harness in `ContentView`.
///
/// It builds a `StreamClient` that *looks* connected — window list, thumbnails, icons, installed
/// apps — without touching the network: `StreamClient` only starts Bonjour when `startBrowsing()`
/// is called, so nothing here needs a hook into it. The connect screen's cases (`connectClient`)
/// are a client that is not connected and never browses. The display view stays black, since no frames
/// ever arrive; the harness is about layout, not picture.
///
/// None of this exists in a Release build.
enum MockCatalog {

    // MARK: - The catalog

    /// Bundle ID → the colour the design boards give that app's icon.
    private static let boardColours: [String: UInt32] = [
        "com.apple.finder": 0x2F62C4,
        "com.microsoft.VSCode": 0x1F6F8B,
        "com.apple.Notes": 0x8A6A10,
        "com.apple.Safari": 0x4A55C9,
        "com.apple.MobileSMS": 0x1F7A45,
        "com.apple.Terminal": 0x3A3D44,
        "com.apple.calculator": 0x3A3D44,
        "com.apple.iCal": 0xA3475F,
        "com.apple.mail": 0x2F62C4,
        "com.apple.Music": 0xA3475F,
    ]

    private static let mockWindows: [WindowInfo] = [
        WindowInfo(id: 101, title: "Desktop", appName: "Finder",
                   bundleID: "com.apple.finder", width: 1400, height: 900),
        WindowInfo(id: 102, title: "stream.py", appName: "Code",
                   bundleID: "com.microsoft.VSCode", width: 1440, height: 900),
        WindowInfo(id: 103, title: "Packing list", appName: "Notes",
                   bundleID: "com.apple.Notes", width: 1360, height: 880),
        WindowInfo(id: 104, title: "Release notes", appName: "Safari",
                   bundleID: "com.apple.Safari", width: 1400, height: 920),
        WindowInfo(id: 105, title: "Team chat", appName: "Messages",
                   bundleID: "com.apple.MobileSMS", width: 1280, height: 880),
        WindowInfo(id: 106, title: "zsh", appName: "Terminal",
                   bundleID: "com.apple.Terminal", width: 1400, height: 900),
    ]

    private static let mockApps: [AppInfo] = [
        AppInfo(name: "Calculator", bundleID: "com.apple.calculator"),
        AppInfo(name: "Calendar", bundleID: "com.apple.iCal"),
        AppInfo(name: "Mail", bundleID: "com.apple.mail"),
        AppInfo(name: "Music", bundleID: "com.apple.Music"),
    ]

    /// A client populated as if a Mac had just sent its whole catalog. Main thread.
    ///
    /// `active` is what the Mac would be streaming: the default is Code's window, as the boards
    /// draw it. `.none` is the state a fresh connection starts in — nothing picked yet, so the app
    /// drawer opens by itself — which the harness asks for with `-SillActive none`.
    static func client(active: StreamSource = .window(102), settings: SettingsCase = .default) -> StreamClient {
        let client = StreamClient()
        // Never browses, not even after the panel's Disconnect, when a remembered Mac would look
        // missing from a network the mock never looked at.
        client.mockDiscovery = true
        client.connected = true
        client.status = "Connected to Mac mini"
        client.macName = "Mac mini"
        client.windows = mockWindows
        client.active = active
        client.apps = mockApps
        client.videoSize = CGSize(width: 2800, height: 1800)

        var icons: [String: UIImage] = [:]
        for app in mockWindows.map({ ($0.bundleID, $0.appName) }) + mockApps.map({ ($0.bundleID, $0.name) }) {
            icons[app.0] = icon(colour: boardColours[app.0] ?? 0x3A3D44, initials: String(app.1.prefix(2)))
        }
        client.icons = icons

        var thumbnails: [UInt32: UIImage] = [:]
        for (index, window) in mockWindows.enumerated() {
            thumbnails[window.id] = thumbnail(seed: index)
        }
        client.thumbnails = thumbnails

        seed(client, settings: settings)
        return client
    }

    // MARK: - The Mac's settings

    /// `-SillSettingsCase`: the states the Settings panel has to look right in. The mock streams
    /// 2880×1800 · 60 fps · 15 Mbps unless a case says otherwise.
    enum SettingsCase: String {
        case `default`   // Sill.app: saved, the virtual display available and off
        case cli         // SillHost without --virtual-display: kept until it quits, the switch off and disabled
        case software    // the hardware encoder is down: the callout, a 1440×900 stream under Retina / 120 fps targets
        case custom      // a bitrate set by hand on the Mac: "Custom — 12 Mbps"
        case vdproblem   // the virtual display on, but off for this session after repeated losses
        case vdstream    // a window streaming from the virtual display at 120 fps, 50 Mbps: the longest readout
        case legacy      // an older Sill on the Mac: no state ever arrives (connected 10 s ago)
        case pending     // a Quality pick sent 1 s ago that is never answered and never expires: its spinner
        case timeout     // the Mac did not answer a pick: the inline problem
        case direct      // Direct Wireless Connection on (every other case has it off, so its row shows)
        case directlink  // on, and this device connected over it: the header line and the footer's warning
        case nodirect    // a host without the setting (the ipad-host-settings build): no row
        case remote          // connected through Tailscale, 48 ms, a saved Mac: the route line, Paired for remote access
        case remoteinternet  // connected over the internet, 120 ms
        case remoteslow      // through Tailscale on a slow link (320 ms): the slow-link callout
        case remotepair      // at home, Remote Access on, not saved: Pair This iPad…
        case remoteoff       // at home, Remote Access off: the footnote only
        case noremote        // at home, an older Mac without kind 18: no Away from home group
    }

    /// The Mac's kind 18 in the remote cases: Tailscale's name and addresses, and Wi‑Fi.
    static func macInfo(remoteAccess: Bool = true, internet: Bool = false) -> MacInfo {
        var addresses = [MacAddress(host: "mac-mini.tail1234.ts.net", kind: MacAddress.vpn, via: "Tailscale"),
                         MacAddress(host: "100.101.102.103", kind: MacAddress.vpn, via: "Tailscale"),
                         MacAddress(host: "192.168.1.20", kind: MacAddress.lan, via: "Wi\u{2011}Fi")]
        if internet { addresses.append(MacAddress(host: "203.0.113.9", kind: MacAddress.internet, via: "Router")) }
        return MacInfo(macID: "A3C5HR4RBV67YR21", name: "Mac mini", issuedAt: 1_790_265_600, remoteAccess: remoteAccess,
                       remotePort: 7455, internet: internet, addresses: remoteAccess ? addresses : [])
    }

    /// One second of link numbers with this round trip (ms), for the route line.
    static func linkStats(rtt: Double) -> StreamClient.LinkStats {
        StreamClient.LinkStats(fps: 60, frameAge: StreamClient.MedianMax([rtt / 2 + 4]),
                               rtt: StreamClient.MedianMax([rtt - 2, rtt, rtt + 3]))
    }

    /// Lays a case's state into the client as if the Mac had sent it on this connection.
    private static func seed(_ client: StreamClient, settings c: SettingsCase) {
        client.connectedAt = Date().addingTimeInterval(c == .legacy ? -10 : -60)
        guard c != .legacy else { return }
        var state = HostSettingsState(
            settings: StreamSettings(maxFPS: 120, bitrate: 15_000_000, captureScale: 2, prioritizeSpeed: false, virtualDisplay: false,
                                     directWireless: false),
            persistent: true, virtualDisplayAvailable: true, softwareEncoder: false,
            stream: RunningStream(width: 2880, height: 1800, fps: 60, mbps: 15, onVirtualDisplay: false))
        switch c {
        case .cli:
            state.persistent = false
            state.virtualDisplayAvailable = false
            state.virtualDisplayNote = "Start SillHost with --virtual-display to use it."
        case .software:
            state.softwareEncoder = true
            state.stream = RunningStream(width: 1440, height: 900, fps: 60, mbps: 15, onVirtualDisplay: false)
        case .custom:
            state.settings.bitrate = 12_000_000
            state.stream?.mbps = 12
        case .vdproblem:
            state.settings.virtualDisplay = true
            state.virtualDisplayNote = "Off for this session: the system removed the virtual display 3 times. Turn it off and on to try again."
        case .vdstream:
            state.settings.virtualDisplay = true
            state.settings.bitrate = 25_000_000
            state.stream = RunningStream(width: 3024, height: 1898, fps: 120, mbps: 50, onVirtualDisplay: true)
        case .direct:
            state.settings.directWireless = true
        case .directlink:
            state.settings.directWireless = true
            client.connectedDirectly = true
        case .nodirect:
            state.settings.directWireless = nil
        case .remote, .remoteslow:
            client.route = .remote(.vpn("Tailscale"))
            client.macInfo = macInfo()
            client.macInfoSaved = true
            client.showMockLinkStats(linkStats(rtt: c == .remoteslow ? 320 : 48))
            state.stream = RunningStream(width: 2880, height: 1800, fps: 60, mbps: 15, onVirtualDisplay: false)
        case .remoteinternet:
            client.route = .remote(.internet)
            client.macInfo = macInfo(internet: true)
            client.macInfoSaved = true
            client.showMockLinkStats(linkStats(rtt: 120))
        case .remotepair:
            client.macInfo = macInfo()
        case .remoteoff:
            client.macInfo = macInfo(remoteAccess: false)
        case .default, .legacy, .pending, .timeout, .noremote:
            break
        }
        if client.macInfo != nil { client.macInfoAt = Date().addingTimeInterval(-59) }
        var ledger = SettingsLedger()
        _ = ledger.receive(state)
        if c == .pending {
            _ = ledger.pick(HostSettingsChange(bitrate: 25_000_000), token: 0, now: ProcessInfo.processInfo.systemUptime - 1)
            client.mockFrozen = true
        }
        client.settings = ledger
        if c == .timeout { client.settingsProblem = "Mac mini didn’t answer. Try again." }
    }

    // MARK: - The connect screen

    /// `-SillConnectCase`: the connect screen's discovery states. The mock is not connected and never
    /// browses (`mockDiscovery`): Search Nearby and a row's tap only change what it shows.
    enum ConnectCase: String {
        case looking   // the first seconds: nothing listed yet
        case hint      // nothing listed after the network's 3 s: the hint and Search Nearby
        case nearby    // searching nearby: a network row, then Direct rows (one with a long name)
        case denied    // Local Network access denied: the status says what to do, and no hint
        case remote        // a network row, a Direct row and two Remote rows (a long name, a "(2)")
        case addmac        // Add a Mac unfolded, scanning (a drawn viewfinder: the simulator has no camera)
        case addcode       // the typed path, empty
        case addcodeerror  // the typed path after a wrong code: "That code didn’t work…"
        case pairing       // "Pairing with Mac mini…"
        case remotedial    // "Connecting to Mac mini remotely…"
        case remotefail    // a remote dial's failure, -SillRemoteFailure vpnoff|timeout|timeoutip|refused|dns|wrongmac|revoked|notsill|gaveup|quit|removed|remoteoff
        case camera        // Add a Mac with the camera refused
        case externalpair  // an outside sill://pair link waiting for its confirmation
    }

    /// How the connect screen starts in a case: the card unfolded, on the typed path, and the
    /// viewfinder's stand-in.
    static func connectScreenOptions(_ c: ConnectCase) -> (adding: Bool, typed: Bool, scanner: CodeScanner.Mode) {
        switch c {
        case .addmac, .pairing: return (true, false, .placeholder)
        case .addcode, .addcodeerror: return (true, true, .placeholder)
        case .camera: return (true, false, .denied)
        default: return (false, false, .placeholder)
        }
    }

    /// A stand-in pairing link: a made-up key and secret, so nothing pairs with it.
    static var mockLink: PairLink {
        let addresses = ["192.168.1.20", "mac-mini.tail1234.ts.net"].compactMap { text -> ParsedAddress? in
            if case .success(let a) = AddressParser.parse(text) { return a }
            return nil
        }
        return PairLink(fingerprint: Data((0..<32).map { UInt8($0 &* 7 &+ 3) }), secret: Data(repeating: 0x16, count: 16),
                        name: "Mac mini", port: 7455, addresses: addresses)
    }

    static func connectClient(_ c: ConnectCase) -> StreamClient {
        let client = StreamClient()
        client.mockDiscovery = true
        client.status = StreamClient.lookingOnNetwork
        func mac(_ name: String, direct: Bool) -> FoundMac {
            FoundMac(name: name, endpoint: .service(name: name, type: "_sill._tcp", domain: "local.", interface: nil),
                     route: direct ? .direct : .network)
        }
        func remote(_ name: String, _ id: String) -> FoundMac { FoundMac(name: name, endpoint: nil, route: .remote, macID: id) }
        let remoteRows = [mac("Studio", direct: false), mac("Mac mini", direct: true),
                          remote("Noah Saffer’s MacBook Pro in the Studio", "A3C5HR4RBV67YR21"), remote("Mac mini (2)", "0123456789ABCDEF")]
        switch c {
        case .looking:
            break
        case .hint:
            client.showsNearbyHint = true
        case .nearby:
            client.searchingNearby = true
            client.status = StreamClient.lookingNearby
            // The long name checks that "Direct" never truncates: the title does.
            client.macs = [mac("Studio", direct: false), mac("Mac mini", direct: true),
                           mac("Noah Saffer’s MacBook Pro in the Studio (2)", direct: true)]
        case .denied:
            client.status = StreamClient.allowLocalNetwork
        case .remote:
            // The long name checks that "Remote" never truncates: the title does.
            client.macs = remoteRows
        case .addmac, .addcode, .camera:
            break
        case .addcodeerror:
            client.pairing = .failed(.wrongCode(triesLeft: 4))
        case .pairing:
            client.pairing = .working("Pairing with Mac mini…")
        case .remotedial:
            client.macs = remoteRows
            client.status = "Connecting to Mac mini remotely…"
        case .remotefail:
            client.macs = remoteRows
            client.status = failureCopy(UserDefaults.standard.string(forKey: "SillRemoteFailure") ?? "timeout")
        case .externalpair:
            client.pendingLink = mockLink
        }
        return client
    }

    /// The status line of each remote failure, in the words the device uses (RemoteCopy).
    static func failureCopy(_ kind: String) -> String {
        let device = StreamClient.deviceWord
        let vpn = RemoteDialPolicy.Candidate(host: "100.101.102.103", port: 7455, kind: MacAddress.vpn, via: "Tailscale")
        let name = RemoteDialPolicy.Candidate(host: "mac-mini.tail1234.ts.net", port: 7455, kind: MacAddress.vpn, via: "Tailscale")
        let router = RemoteDialPolicy.Candidate(host: "203.0.113.9", port: 7455, kind: MacAddress.internet, via: "Router")
        func copy(_ f: RemoteDialPolicy.Failure, _ c: RemoteDialPolicy.Candidate?) -> String {
            RemoteCopy.dialFailure(f, mac: "Mac mini", candidate: c, vpnName: "Tailscale", device: device)
        }
        switch kind {
        case "vpnoff": return copy(.vpnOff, vpn)
        case "refused": return copy(.refused, vpn)
        case "dns": return copy(.nameNotFound, name)
        case "wrongmac": return copy(.wrongMac, vpn)
        case "revoked": return copy(.revoked, vpn)
        case "notsill": return copy(.notSill, router)
        case "gaveup": return "Stopped trying to reach Mac mini. Tap it to try again."
        case "quit": return "Mac mini quit Sill. This \(device) reconnects when it’s back."
        case "removed": return "Mac mini removed this \(device). To use it again, pair it again."
        case "remoteoff": return "Mac mini turned off Remote Access."
        case "timeoutip": return copy(.noAnswer, router)
        default: return copy(.noAnswer, vpn)
        }
    }

    // MARK: - Drawn images

    private static func colour(_ hex: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha)
    }

    /// 64×64 rounded square in the board colour with the app's two-letter initials.
    private static func icon(colour hex: UInt32, initials: String) -> UIImage {
        let side: CGFloat = 64
        let size = CGSize(width: side, height: side)
        return UIGraphicsImageRenderer(size: size).image { _ in
            colour(hex).setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 15).fill()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 26, weight: .semibold),
                .foregroundColor: UIColor.white,
            ]
            let text = initials as NSString
            let bounds = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: (side - bounds.width) / 2, y: (side - bounds.height) / 2),
                      withAttributes: attributes)
        }
    }

    /// 208×132 window portrait: a dark body under a 9 pt title strip, with a few grey bars so it
    /// reads as a tiny window rather than a blank rectangle.
    private static func thumbnail(seed: Int) -> UIImage {
        let size = CGSize(width: 208, height: 132)
        return UIGraphicsImageRenderer(size: size).image { _ in
            colour(0x26282D).setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: size)).fill()

            colour(0x34373D).setFill()
            UIBezierPath(rect: CGRect(x: 0, y: 0, width: size.width, height: 9)).fill()
            colour(0x4A4E56).setFill()
            for dot in 0..<3 {
                UIBezierPath(ovalIn: CGRect(x: 6 + CGFloat(dot) * 8, y: 3, width: 3, height: 3)).fill()
            }

            // Widths shuffle with the seed so six thumbnails are not one image repeated.
            let widths: [CGFloat] = [150, 96, 128, 72, 164, 110]
            colour(0xFFFFFF, alpha: 0.16).setFill()
            for row in 0..<5 {
                let width = widths[(seed + row) % widths.count]
                let bar = CGRect(x: 14, y: 26 + CGFloat(row) * 18, width: width, height: 7)
                UIBezierPath(roundedRect: bar, cornerRadius: 3.5).fill()
            }
        }
    }
}
#endif
