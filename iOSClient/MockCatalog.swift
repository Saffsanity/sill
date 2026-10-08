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
    static func client(active: StreamSource = .window(102), settings: SettingsCase = .default,
                       menus: MenuCase? = .code, pointer: String? = nil, pencilPointer: Bool = false) -> StreamClient {
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
        // `-SillOverlayLine asking|shown|openonmac|locked|noanswer`: Pair This iPad…'s line over a
        // session at home that speaks TLS, as the Mac's answer to its ask sets it (the mock never
        // asks: over it the overlay reads "…is showing a code now." as over a plain door).
        if let line = UserDefaults.standard.string(forKey: "SillOverlayLine") {
            let device = StreamClient.deviceWord
            switch line {
            case "asking": client.overlayAskLine = DiscoveryPolicy.HomeCopy.overlayAsking(mac: "Mac mini")
            case "shown": client.overlayAskLine = DiscoveryPolicy.overlayLine(.shown, mac: "Mac mini", device: device)
            case "openonmac": client.overlayAskLine = DiscoveryPolicy.overlayLine(.openOnMac, mac: "Mac mini", device: device)
            case "locked": client.overlayAskLine = DiscoveryPolicy.overlayLine(.locked, mac: "Mac mini", device: device)
            case "noanswer": client.overlayAskLine = DiscoveryPolicy.overlayLine(nil, mac: "Mac mini", device: device)
            default: break
            }
        }
        // nil under `-SillLive 1`: the mock is never shown then, and must say nothing on the console.
        if let menus { client.showMockMenus(macMenus(menus)) }
        if let pointer { seedPointer(client, pointer, pencilPointer: pencilPointer) }
        return client
    }

    /// `-SillPointer <state>`: the mock's pointer in one of the plan's states (see the harness's
    /// contract in ContentView and `StreamClient.debugSeedPointer`), over the mock's frame, which the
    /// display view is told of since no parameter sets ever arrive; `pencilPointer` is Q2's flip.
    private static func seedPointer(_ client: StreamClient, _ state: String, pencilPointer: Bool) {
        guard client.debugSeedPointer(state, pencilShows: pencilPointer) else {
            print("-SillPointer \(state): not a state (mac@X,Y, device@X,Y, hidden or pencil@X,Y)")
            return
        }
        client.displayView.debugFrameSize(client.videoSize)
    }

    // MARK: - The Mac's menus

    /// `-SillMacMenu`: the Mac's menus in the harness (docs/menu-bar-plan.md §7.8). The mock Mac
    /// answers a menu 0.2 s after it opens and a choice 0.2 s after it is made, unless a case says
    /// otherwise.
    enum MenuCase: String {
        case code       // VS Code's ten menus: File with shortcuts, sections, a ✓, a disabled item and Open Recent ▸; Code › Settings ▸ Themes ▸ three deep; View › Appearance with ✓s and a mixed mark; Run with disabled items
        case blender    // only Blender and Window, as Blender's menu bar reads over Accessibility
        case long       // a Window menu of 300 windows, and a History of 600 (500 sent, and "100 more on the Mac")
        case stale      // Code not answering on the Mac: every menu disabled under the note
        case noaccess   // no Accessibility for Sill on the Mac: the note, no menus
        case none       // no menus (nothing streams, Sill itself frontmost): no Menus button
        case slow       // code's menus, each answered after 1.5 s (UIKit's placeholder meanwhile)
        case timeout    // code's menus, never answered: "Mac mini didn’t answer. Open the menu again." after 4 s
        case refuse     // code's menus, every choice refused: "The menus changed. Open the menu again."
    }

    /// What the mock Mac sends: its top level, every menu's items by id, and how it answers.
    struct MacMenus {
        let topLevel: MacMenu
        let tree: [String: [MacMenuItem]]
        /// How long a fetch waits for its answer; nil: for ever (`timeout`).
        let fetchDelay: Double?
        let refusesChoices: Bool

        /// The answer to a kind 27, as a host sends it: at most 500 items, `more` for the rest.
        func answer(_ r: FetchMenu) -> MacMenu {
            let items = tree[r.id ?? ""] ?? []
            let sent = Array(items.prefix(500))
            return MacMenu(version: topLevel.version, answering: r.token, menu: r.id, items: sent,
                           more: items.count > sent.count ? items.count - sent.count : nil)
        }

        /// The answer to a kind 25.
        func answer(_ r: PressMenuItem) -> MacMenu {
            refusesChoices
                ? MacMenu(version: topLevel.version, answering: r.token, pressed: false, note: MacMenuState.changedNote)
                : MacMenu(version: topLevel.version, answering: r.token, pressed: true)
        }
    }

    static func macMenus(_ c: MenuCase) -> MacMenus {
        func top(_ titles: [String], app: String?, bundleID: String? = nil, stale: Bool? = nil, note: String? = nil) -> MacMenu {
            MacMenu(version: 3, app: app, bundleID: bundleID,
                    menus: titles.enumerated().map { MacMenuItem(id: "\($0.offset + 1)", title: $0.element, submenu: true) },
                    stale: stale, note: note)
        }
        let codeTitles = ["Code", "File", "Edit", "Selection", "View", "Go", "Run", "Terminal", "Window", "Help"]
        let vscode = "com.microsoft.VSCode"
        switch c {
        case .code, .slow, .timeout, .refuse, .stale:
            let stale = c == .stale
            return MacMenus(topLevel: top(codeTitles, app: "Code", bundleID: vscode, stale: stale ? true : nil,
                                          note: stale ? "Code isn’t responding." : nil),
                            tree: codeTree,
                            fetchDelay: c == .slow ? 1.5 : c == .timeout ? nil : 0.2,
                            refusesChoices: c == .refuse)
        case .blender:
            return MacMenus(topLevel: top(["Blender", "Window"], app: "Blender", bundleID: "org.blenderfoundation.blender"),
                            tree: ["1": items("1", ["About Blender", "—", "Preferences… | ⌘,", "—", "Services ▸", "—",
                                                    "Hide Blender | ⌘H", "Hide Others | ⌥⌘H", "Show All", "—", "Quit Blender | ⌘Q"]),
                                   "1.4": items("1.4", ["!No Services Apply"]),
                                   "2": items("2", ["Minimize | ⌘M", "Zoom", "—", "Toggle Window Fullscreen | ⌃⌘F", "Toggle System Console",
                                                    "—", "Bring All to Front", "—", "✓untitled.blend"])],
                            fetchDelay: 0.2, refusesChoices: false)
        case .long:
            let windows = (1...300).map { "Window \($0) — notes-\($0).md" }
            let history = (1...600).map { "Visited page \($0)" }
            return MacMenus(topLevel: top(["Code", "File", "Window", "History"], app: "Code", bundleID: vscode),
                            tree: ["1": codeTree["1"] ?? [], "2": codeTree["2"] ?? [],
                                   "3": items("3", ["Minimize | ⌘M", "Zoom", "—"] + windows),
                                   "4": items("4", history)],
                            fetchDelay: 0.2, refusesChoices: false)
        case .noaccess:
            return MacMenus(topLevel: MacMenu(version: 3, app: "Code", bundleID: vscode, menus: [],
                                              note: "Allow Accessibility for Sill on the Mac (System Settings › Privacy & Security › Accessibility)."),
                            tree: [:], fetchDelay: 0.2, refusesChoices: false)
        case .none:
            return MacMenus(topLevel: MacMenu(version: 3, menus: []), tree: [:], fetchDelay: 0.2, refusesChoices: false)
        }
    }

    /// VS Code's menus as a Mac with this build reads them (a selection of each).
    private static let codeTree: [String: [MacMenuItem]] = [
        "1": items("1", ["About Visual Studio Code", "—", "Settings ▸", "—", "Services ▸", "—", "Hide Visual Studio Code | ⌘H",
                         "Hide Others | ⌥⌘H", "Show All", "—", "Quit Visual Studio Code | ⌘Q"]),
        "1.2": items("1.2", ["Settings | ⌘,", "Extensions | ⇧⌘X", "Keyboard Shortcuts [⌘K ⌘S]", "Snippets", "Tasks", "—",
                             "Themes ▸", "—", "Backup and Sync Settings…", "Online Services Settings"]),
        "1.2.6": items("1.2.6", ["Color Theme [⌘K ⌘T]", "File Icon Theme", "Product Icon Theme"]),
        "1.4": items("1.4", ["!No Services Apply", "—", "Services Settings"]),
        "2": items("2", ["New Text File | ⌘N", "New File… | ⌃⌥⌘N", "—", "Open Recent ▸", "Open… | ⌘O", "Open Folder…",
                         "New Window | ⇧⌘N", "—", "Save Workspace As…", "Save | ⌘S", "Save As… | ⇧⌘S", "—",
                         "✓Auto Save", "—", "!Revert File", "Close Editor | ⌘W", "Close Window | ⇧⌘W"]),
        "2.3": items("2.3", ["Reopen Closed Editor | ⇧⌘T", "—", "~/Downloads/winstream", "~/Code/site", "~/Notes/trip.md", "—",
                             "More… | ⌃R", "—", "Clear Recently Opened"]),
        "3": items("3", ["Undo | ⌘Z", "Redo | ⇧⌘Z", "—", "Cut | ⌘X", "Copy | ⌘C", "Paste | ⌘V", "—", "Find | ⌘F",
                         "Replace | ⌥⌘F", "—", "Find in Files | ⇧⌘F", "Replace in Files | ⇧⌘H", "—",
                         "Toggle Line Comment | ⌘/", "Toggle Block Comment | ⌥⇧A", "—", "Start Dictation… | fn D",
                         "Emoji & Symbols | fn E"]),
        "4": items("4", ["Select All | ⌘A", "Expand Selection | ⌃⇧⌘→", "Shrink Selection | ⌃⇧⌘←", "—", "Copy Line Up | ⌥⇧↑",
                         "Copy Line Down | ⌥⇧↓", "Move Line Up | ⌥↑", "Move Line Down | ⌥↓", "—",
                         "Add Cursor Above | ⌥⌘↑", "Add Cursor Below | ⌥⌘↓", "—", "Column Selection Mode"]),
        "5": items("5", ["Command Palette… | ⇧⌘P", "Open View…", "—", "Appearance ▸", "Editor Layout ▸", "—",
                         "Explorer | ⇧⌘E", "Search | ⇧⌘F", "Source Control | ⌃⇧G", "Run | ⇧⌘D", "Extensions | ⇧⌘X", "—",
                         "Problems | ⇧⌘M", "Output | ⇧⌘U", "Terminal | ⌃`", "—", "✓Word Wrap | ⌥Z"]),
        "5.3": items("5.3", ["Full Screen | ⌃⌘F", "Zen Mode [⌘K Z]", "Centered Layout", "—", "✓Primary Side Bar | ⌘B",
                             "Secondary Side Bar | ⌥⌘B", "✓Status Bar", "~Minimap", "✓Panel | ⌘J"]),
        "5.4": items("5.4", ["Split Up", "Split Down", "Split Left", "Split Right", "—", "Single", "Two Columns", "Three Columns"]),
        "6": items("6", ["Back | ⌃-", "Forward | ⌃⇧-", "Last Edit Location [⌘K ⌘Q]", "—", "Go to File… | ⌘P",
                         "Go to Symbol in Workspace… | ⌘T", "—", "Go to Symbol in Editor… | ⇧⌘O", "Go to Definition | F12",
                         "Go to Line/Column… | ⌃G"]),
        "7": items("7", ["Start Debugging | F5", "Run Without Debugging | ⌃F5", "!Stop Debugging | ⇧F5",
                         "!Restart Debugging | ⇧⌘F5", "—", "Open Configurations", "Add Configuration…", "—",
                         "!Step Over | F10", "!Step Into | F11", "!Step Out | ⇧F11", "—", "Toggle Breakpoint | F9"]),
        "8": items("8", ["New Terminal | ⌃⇧`", "Split Terminal | ⌘\\", "—", "Run Task…", "Run Build Task… | ⇧⌘B",
                         "Run Active File", "Run Selected Text"]),
        "9": items("9", ["Minimize | ⌘M", "Zoom", "Fill | fn ⌃F", "Center | fn ⌃C", "—", "Bring All to Front", "—",
                         "✓stream.py — winstream", "index.html — site"]),
        "10": items("10", ["Welcome", "Show All Commands | ⇧⌘P", "Documentation", "Editor Playground", "Show Release Notes", "—",
                           "Keyboard Shortcuts Reference [⌘K ⌘R]", "Video Tutorials", "Tips and Tricks", "—", "Report Issue",
                           "—", "View License", "Privacy Statement", "—", "Toggle Developer Tools | ⌥⌘I"]),
    ]

    /// A menu's items from one line each: "—" a separator, "Title ▸" a submenu, "Title | ⌘S" a
    /// shortcut, and a first "!" (disabled), "✓" (on) or "~" (mixed). Ids from `parent`, 0-based,
    /// separators counted, as the Mac numbers them.
    private static func items(_ parent: String, _ lines: [String]) -> [MacMenuItem] {
        lines.enumerated().map { index, line in
            let id = "\(parent).\(index)"
            if line == "—" { return MacMenuItem(separator: true) }
            var text = Substring(line)
            var enabled: Bool?
            var mark: String?
            if text.hasPrefix("!") { enabled = false; text = text.dropFirst() }
            if text.hasPrefix("✓") { mark = "✓"; text = text.dropFirst() } else if text.hasPrefix("~") && !text.hasPrefix("~/") { mark = "-"; text = text.dropFirst() }
            let parts = text.components(separatedBy: " | ")
            if parts[0].hasSuffix(" ▸") {
                return MacMenuItem(id: id, title: String(parts[0].dropLast(2)), enabled: enabled, submenu: true)
            }
            return MacMenuItem(id: id, title: parts[0], enabled: enabled, mark: mark, key: parts.count > 1 ? parts[1] : nil)
        }
    }

    // MARK: - The Mac's settings

    /// `-SillSettingsCase`: the states the Settings panel has to look right in. The mock streams
    /// 2880×1800 · 60 fps · 15 Mbps over Wi-Fi unless a case says otherwise.
    enum SettingsCase: String {
        case `default`   // Sill.app: saved, the virtual display available and off
        case cli         // SillHost without --virtual-display: kept until it quits, the switch off and disabled
        case software    // the hardware encoder is down: the callout, a 1440×900 stream under Retina / 120 fps targets
        case custom      // a bitrate set by hand on the Mac: "Custom — 12 Mbps"
        case vdproblem   // the virtual display on, but off for this session after repeated losses
        case vdstream    // a window streaming from the virtual display, 120 fps at Extreme, 300 Mbps: the longest readout
        case legacy      // an older Sill on the Mac: no state ever arrives (connected 10 s ago)
        case pending     // a Quality pick sent 1 s ago that is never answered and never expires: its spinner
        case timeout     // the Mac did not answer a pick: the inline problem
        case direct      // Direct Wireless Connection on (every other case has it off, so its row shows)
        case directlink  // on, and this device connected over it: "Direct" in the readout and the footer's warning
        case nodirect    // a host without the setting (the ipad-host-settings build): no row
        case wired       // the session runs over the USB cable (or Ethernet): "Wired" in the readout
        case noroute     // a path that names no link (loopback, a VPN): the readout ends in the bitrate
        case remote          // connected through Tailscale, 48 ms, a saved Mac: the route line, Paired
        case remoteinternet  // connected over the internet, 120 ms
        case remoteslow      // through Tailscale on a slow link (320 ms): the slow-link callout
        case remotepair      // at home over a plain door, Remote Access on, not saved: Pair This iPad…
        case remoteoff       // at home over a plain door, Remote Access off: the footnote only
        case noremote        // at home, an older Mac without kind 18: no Away from home group
        // Pairing at home (docs/home-pairing-plan.md §7.6, §7.9): a session at home over TLS.
        case paired          // a saved Mac, Remote Access on: Paired, and how Sill reaches it from afar
        case pairedoff       // a saved Mac, Remote Access off: Paired, and how to turn it on
        case openpair        // not saved, on a Mac that lets any device in (Require pairing off), Remote Access off: Pair This iPad…
        // Away from home and the link (docs/remote-bundle-plan.md §5.8, §6.7), through Tailscale:
        case away            // the away quality runs (Low · Standard; home Pro · Retina): "Away: Low · Standard"
        case awaymixed       // away, while a device at home is connected: "Home quality: Pro · Retina (…)"
        case awayhome        // at home over Wi‑Fi, Remote Access on: the footnote says what runs away from home
        case linkbehind      // away at Pro · Retina on a link that cannot carry it: the callout and "Use Low · Standard"
        case linkmixed       // behind while a device at home keeps Pro: the callout without a button
        case linklow         // behind at Low · Standard: "even at Low", no button
        case linkstalled     // stalled: the Mac's alone, so no callout
    }

    /// The away and link cases: the Mac's two qualities (home Pro · Retina, away Low · Standard unless
    /// the case raises it), the settings this connection controls, what runs, and the link's report.
    private static func seedAway(_ client: StreamClient, _ state: inout HostSettingsState, _ c: SettingsCase) {
        let home = (bitrate: 40_000_000, scale: 2.0)
        var awayPair = (bitrate: 4_000_000, scale: 1.0)
        if c == .linkbehind || c == .linkstalled { awayPair = (40_000_000, 2) }
        let atHome = c == .awayhome
        let running = !(c == .awaymixed || c == .linkmixed || atHome)
        state.away = AwayQuality(homeBitrate: home.bitrate, homeCaptureScale: home.scale, awayBitrate: awayPair.bitrate,
                                 awayCaptureScale: awayPair.scale, thisConnectionAway: !atHome, awayRunning: running)
        // The pair this connection's controls set: the away one away from home.
        let controls = atHome ? home : awayPair
        state.settings.bitrate = controls.bitrate
        state.settings.captureScale = controls.scale
        // What runs: the away pair while every device is away, else the home one.
        let runs = running ? awayPair : home
        state.stream = runs.scale >= 1.5 ? RunningStream(width: 2880, height: 1800, fps: 60, mbps: runs.bitrate / 1_000_000, onVirtualDisplay: false)
                                         : RunningStream(width: 1440, height: 900, fps: 60, mbps: runs.bitrate / 1_000_000, onVirtualDisplay: false)
        client.macInfo = macInfo()
        client.macInfoSaved = true
        // At home a saved Mac's session speaks TLS since pairing at home, as `paired`'s does.
        if atHome { client.mockHomeTLS = true }
        if !atHome {
            client.remoteRoute = .vpn("Tailscale")
            client.showMockLinkStats(linkStats(rtt: c == .linkbehind || c == .linkmixed || c == .linklow || c == .linkstalled ? 180 : 48))
        }
        switch c {
        case .linkbehind:
            state.link = LinkReport(state: LinkReport.behind, withheldPerSecond: 52, bitrate: 40_000_000, carriedKbps: 6_400,
                                    suggestedBitrate: 4_000_000, suggestedCaptureScale: 1)
        case .linkmixed:
            state.link = LinkReport(state: LinkReport.behind, withheldPerSecond: 44, bitrate: 40_000_000, carriedKbps: 9_100,
                                    suggestedBitrate: 4_000_000, suggestedCaptureScale: 1)
        case .linklow:
            state.link = LinkReport(state: LinkReport.behind, withheldPerSecond: 20, bitrate: 4_000_000, carriedKbps: 2_100)
        case .linkstalled:
            state.link = LinkReport(state: LinkReport.stalled, withheldPerSecond: 60, bitrate: 40_000_000)
        default:
            break
        }
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
        // How this session reaches the Mac: read from the connection, whatever the Mac runs.
        // Away from home the route line under the readout says how instead (`remote`,
        // `remoteinternet`, `remoteslow`), and the readout ends in the bitrate.
        switch c {
        case .directlink: client.route = .direct
        case .wired: client.route = .wired
        case .noroute, .remote, .remoteinternet, .remoteslow, .away, .awaymixed, .linkbehind, .linkmixed, .linklow, .linkstalled:
            client.route = nil
        default: client.route = .wifi
        }
        // A Mac from this build takes the trackpad gestures (its window list says so); an older one
        // does not, and its Settings panel says to update it.
        client.hostGestures = c == .legacy ? nil : TrackpadGesture.generation
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
            state.settings.bitrate = 150_000_000
            state.stream = RunningStream(width: 3024, height: 1898, fps: 120, mbps: 300, onVirtualDisplay: true)
        case .direct:
            state.settings.directWireless = true
        case .directlink:
            state.settings.directWireless = true
            client.connectedDirectly = true
        case .nodirect:
            state.settings.directWireless = nil
        case .remote, .remoteslow:
            client.remoteRoute = .vpn("Tailscale")
            client.macInfo = macInfo()
            client.macInfoSaved = true
            client.showMockLinkStats(linkStats(rtt: c == .remoteslow ? 320 : 48), slow: c == .remoteslow)
            state.stream = RunningStream(width: 2880, height: 1800, fps: 60, mbps: 15, onVirtualDisplay: false)
        case .remoteinternet:
            client.remoteRoute = .internet
            client.macInfo = macInfo(internet: true)
            client.macInfoSaved = true
            client.showMockLinkStats(linkStats(rtt: 120))
        case .remotepair:
            client.macInfo = macInfo()
        case .remoteoff:
            client.macInfo = macInfo(remoteAccess: false)
        case .paired, .pairedoff:
            client.macInfo = macInfo(remoteAccess: c == .paired)
            client.macInfoSaved = true
            client.mockHomeTLS = true
        case .openpair:
            client.macInfo = macInfo(remoteAccess: false)
            client.mockHomeTLS = true
        case .away, .awaymixed, .awayhome, .linkbehind, .linkmixed, .linklow, .linkstalled:
            seedAway(client, &state, c)
        case .default, .legacy, .pending, .timeout, .wired, .noroute, .noremote:
            break
        }
        // `-SillLinkLine behind`: the Mac reports the link behind on this connection, whatever the
        // case, so the stream screen shows its line (with the panel closed). Its suggestion is the
        // host's for a slow link (LinkJudge.suggestion): Low, with Standard from Retina; at Low, the
        // same bitrate at Standard from Retina, and nothing from Low · Standard.
        if UserDefaults.standard.string(forKey: "SillLinkLine") == "behind", state.link == nil {
            let bitrate = state.settings.bitrate, retina = state.settings.captureScale >= 1.5, low = QualityPreset.low.rawValue
            let suggestion: (bitrate: Int, captureScale: Double?)? = bitrate > low ? (low, retina ? 1 : nil) : (retina ? (bitrate, 1) : nil)
            state.link = LinkReport(state: LinkReport.behind, withheldPerSecond: 52, bitrate: bitrate, carriedKbps: 2_100,
                                    suggestedBitrate: suggestion?.bitrate, suggestedCaptureScale: suggestion?.captureScale)
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
        case nearby    // searching nearby: a Wi-Fi row, then Direct rows (one with a long name)
        case methods   // every word a row can end in: Wired, Wi-Fi, none, long names with Wired and Wi-Fi, Direct
        case denied    // Local Network access denied: the status says what to do, and no hint
        case update    // a Mac refused this version: its words, a Wi‑Fi row, the App Store link (with -SillAppStoreURL)
        case notice    // a goodbye reason this build does not know: the Mac's two-line message, no link
        case remote        // a network row, a Direct row and two Remote rows (a long name, a "(2)")
        case addmac        // Add a Mac unfolded, scanning (a drawn viewfinder: the simulator has no camera)
        case addcode       // the typed path, empty
        case addcodeerror  // the typed path after a wrong code: "That code didn’t work…"
        case pairing       // "Pairing with Mac mini…"
        case remotedial    // "Connecting to Mac mini remotely…"
        case remotefail    // a remote dial's failure, -SillRemoteFailure vpnoff|timeout|timeoutip|refused|dns|wrongmac|revoked|notsill|gaveup|quit|removed|remoteoff
        case camera        // Add a Mac with the camera refused
        case externalpair  // an outside sill://pair link waiting for its confirmation
        // Pairing at home (docs/home-pairing-plan.md §7.3–7.9). Each row's word is DiscoveryPolicy.rowWord's.
        case homerows        // a saved Wi-Fi row, Not paired, an unpaired Wired (the cable), a Wired row through a USB Ethernet adapter (Not paired), an open door's (Not paired), Update Sill, long names
        case homeasking      // a tap on a Not paired row: "Pairing with Mac mini…", the row lit
        case homecard        // the Mac shows its code: the home card, scanning (a drawn viewfinder)
        case homecode        // the home card's typed path, empty
        case homecodeerror   // the typed path after a wrong code: "That code didn’t work… 4 tries left."
        case homelocked      // the Mac is locked (a Wired row over the cable): "Unlock Mac mini, then tap it again."
        case homeopenonmac   // the Mac showed no code by itself: "…choose Pair iPhone or iPad… in the Sill menu…"
        case homerevoked     // the Mac removed this device: its row reads Not paired
        case homecabledone   // paired over the cable, the session on its way: "Paired with Mac mini over the cable."
        case homeolder       // a tap on an Update Sill row: "Mac mini runs an older Sill…"
        case pairingrequired // Require pairing turned on while this device was connected without pairing
    }

    /// How the connect screen starts in a case: the card unfolded, on the typed path, and the
    /// viewfinder's stand-in. The home card unfolds from the client's `homeAsk` (ConnectScreen).
    static func connectScreenOptions(_ c: ConnectCase) -> (adding: Bool, typed: Bool, scanner: CodeScanner.Mode) {
        switch c {
        case .addmac, .pairing: return (true, false, .placeholder)
        case .addcode, .addcodeerror: return (true, true, .placeholder)
        case .camera: return (true, false, .denied)
        case .homecode, .homecodeerror: return (false, true, .placeholder)
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
        /// A row as `recomputeMacs` makes it: Direct only for a Direct row. No wired interface: the
        /// mock never dials.
        func mac(_ name: String, _ method: DiscoveryPolicy.Method?) -> FoundMac {
            FoundMac(name: name, endpoint: .service(name: name, type: "_sill._tcp", domain: "local.", interface: nil),
                     route: method == .direct ? .direct : .network, method: method)
        }
        func remote(_ name: String, _ id: String) -> FoundMac { FoundMac(name: name, endpoint: nil, route: .remote, macID: id) }
        let remoteRows = [mac("Studio", .wifi), mac("Mac mini", .direct),
                          remote("Noah Saffer’s MacBook Pro in the Studio", "A3C5HR4RBV67YR21"), remote("Mac mini (2)", "0123456789ABCDEF")]
        /// A row at home as `recomputeMacs` makes it: its door (`p`), what this device knows of its
        /// Mac, and the word DiscoveryPolicy.rowWord gives them. `cable`: a Wired row whose interface
        /// carries only link-local addresses (the USB cable to the Mac); false for a USB Ethernet
        /// adapter on the LAN.
        func home(_ name: String, _ method: DiscoveryPolicy.Method?, door: DiscoveryPolicy.HomeDoor = .pairingRequired,
                  saved: Bool = false, revoked: Bool = false, homeTLS: Bool = false, cable: Bool = false) -> FoundMac {
            let word = DiscoveryPolicy.rowWord(door: door, saved: saved, revoked: revoked, homeTLS: homeTLS,
                                               debug: StreamClient.debugBuild, method: method, cable: cable)
            return FoundMac(name: name, endpoint: .service(name: name, type: "_sill._tcp", domain: "local.", interface: nil),
                            route: method == .direct ? .direct : .network, macID: saved ? "HOMEPAIRING\(name.count)" : nil,
                            method: method, door: door, homeWord: word)
        }
        /// A tap's ask on `row` (`homeAsk`), waiting for its answer or answered `shown`.
        func ask(_ row: FoundMac, shown: Bool) -> HomeAsk {
            var a = HomeAsk(target: HomeDialer.Target(endpoint: row.endpoint!, peerToPeer: row.direct, row: row.id, label: row.name),
                            name: row.name, cableRow: row.homeWord == .pairsOverCable, savedID: nil, tagNamed: false)
            if shown { a.phase = .shown }
            return a
        }
        let studio = home("Studio", .wifi, saved: true, homeTLS: true)
        let device = StreamClient.deviceWord
        typealias Copy = DiscoveryPolicy.HomeCopy
        switch c {
        case .looking:
            break
        case .hint:
            client.showsNearbyHint = true
        case .nearby:
            client.searchingNearby = true
            client.status = StreamClient.lookingNearby
            // The long name checks that "Direct" never truncates: the title does.
            client.macs = [mac("Studio", .wifi), mac("Mac mini", .direct),
                           mac("Noah Saffer’s MacBook Pro in the Studio (2)", .direct)]
        case .methods:
            // Network rows first, then the Direct one, as DiscoveryPolicy.rows orders them. "Office
            // iMac" was seen only on interfaces the device cannot name (DiscoveryPolicy.method: no
            // word). The long names check that the word never truncates or wraps, the title does:
            // "Wi-Fi" is spelled with a non-breaking hyphen.
            client.searchingNearby = true
            client.status = StreamClient.lookingNearby
            client.macs = [mac("Mac Studio", .wired), mac("Mac mini", .wifi), mac("Office iMac", nil),
                           mac("Noah Saffer’s MacBook Pro in the Studio (2)", .wired),
                           mac("Noah Saffer’s iMac on the Desk by the Window", .wifi),
                           mac("MacBook Air", .direct)]
        case .denied:
            client.status = StreamClient.allowLocalNetwork
        case .update, .notice:
            // As a session ends with it (StreamClient.endWithNotice): the words as the status line,
            // the notice beside them. The message is the host's (DeviceGate's), for this device.
            client.macs = [mac("Mac mini", .wifi)]
            let goodbye = c == .update
                ? Goodbye(reason: Goodbye.update, message: "Update Sill on your \(StreamClient.deviceWord) to keep using Mac mini. It needs version 1.2 or later.",
                          minimumVersion: "1.2", reconnect: false)
                // A reason this build does not know ("pairingRequired" is pairing at home's own now).
                : Goodbye(reason: "pairAgain",
                          message: "Mac mini now lets in only the devices it has paired with. On the Mac, choose Pair iPhone or iPad…, then scan its code with this \(StreamClient.deviceWord).",
                          reconnect: false)
            let outcome = GoodbyePolicy.outcome(goodbye, mac: "Mac mini", device: StreamClient.deviceWord, saved: false)
            client.status = outcome.text
            client.notice = StreamClient.Notice(text: outcome.text, storeLink: outcome.storeLink)
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
        case .homerows:
            // The long names check that "Not paired" and "Update Sill" never truncate or wrap: the
            // title does.
            client.macs = [home("Mac mini", .wifi, saved: true, homeTLS: true),
                           home("Studio", .wifi),
                           home("MacBook Pro", .wired, cable: true),
                           home("Office iMac", .wired, cable: false),
                           home("Living Room iMac", .wifi, door: .open),
                           home("Mac Studio", .wifi, door: .plain, saved: true, homeTLS: true),
                           home("Noah Saffer’s MacBook Pro in the Studio (2)", .wifi),
                           home("Noah Saffer’s iMac on the Desk by the Window", .wired, door: .plain, saved: true, homeTLS: true)]
        case .homeasking:
            let mini = home("Mac mini", .wifi)
            client.macs = [mini, studio]
            client.homeAsk = ask(mini, shown: false)
            client.status = Copy.pairing(mac: mini.name, cable: false)
        case .homecard, .homecode, .homecodeerror:
            let mini = home("Mac mini", .wifi)
            client.macs = [mini, studio]
            client.homeAsk = ask(mini, shown: true)
            client.status = Copy.showing(mac: mini.name, device: device)
            if c == .homecodeerror { client.pairing = .failed(.wrongCode(triesLeft: 4)) }
        case .homelocked:
            client.macs = [home("Mac mini", .wired, cable: true), studio]
            client.status = Copy.locked(mac: "Mac mini")
        case .homeopenonmac:
            client.macs = [home("Mac mini", .wifi), studio]
            client.status = Copy.openOnMac(mac: "Mac mini")
        case .homerevoked:
            client.macs = [home("Mac mini", .wifi, saved: true, revoked: true, homeTLS: true), studio]
            client.status = Copy.removed(mac: "Mac mini", device: device)
        case .homecabledone:
            client.macs = [home("Mac mini", .wired, saved: true, homeTLS: true), studio]
            client.status = Copy.pairedOverCable(mac: "Mac mini")
        case .homeolder:
            client.macs = [home("Mac mini", .wifi, door: .plain, saved: true, homeTLS: true), studio]
            client.status = DiscoveryPolicy.updateSillStatus(mac: "Mac mini")
        case .pairingrequired:
            client.macs = [home("Mac mini", .wifi), studio]
            client.status = Copy.pairingRequired(mac: "Mac mini", device: device)
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
        // A session's goodbyes, in the words GoodbyePolicy gives them.
        case "quit": return GoodbyePolicy.outcome(Goodbye(reason: Goodbye.quit), mac: "Mac mini", device: device, saved: true).text
        case "removed": return GoodbyePolicy.outcome(Goodbye(reason: Goodbye.removed), mac: "Mac mini", device: device, saved: true).text
        case "remoteoff": return GoodbyePolicy.outcome(Goodbye(reason: Goodbye.remoteOff), mac: "Mac mini", device: device, saved: true).text
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
