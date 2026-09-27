import SwiftUI
import Network
import StreamProtocol

struct ContentView: View {
    @StateObject private var client = StreamClient()
    /// Tells the host what this device sees, once a second while connected. Also covers the DEBUG
    /// harness's `-SillLive 1` session, which runs on this same client.
    @StateObject private var statsReporter = ClientStatsReporter()

    var body: some View {
        root.onAppear { statsReporter.attach(to: client) }
    }

    @ViewBuilder private var root: some View {
        #if DEBUG
        if let spec = LayoutHarness.Spec.fromLaunchArguments {
            // The harness gets the app's own client so `-SillLive 1` can put a real session inside
            // the fake screen; without that argument it never touches it.
            LayoutHarness(spec: spec, live: client)
        } else {
            app
        }
        #else
        app
        #endif
    }

    private var app: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if client.connected {
                StreamScreen(client: client)
            } else {
                ConnectScreen(client: client)
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            client.startBrowsing()
            client.startRemote()                 // saved Macs without a key are cleared; DEBUG pairing arguments
            #if DEBUG
            client.connectFromLaunchArgument()   // -SillConnect host:port, for the off-Bonjour test hosts
            #endif
        }
        // sill://pair from the Camera, Messages or `xcrun simctl openurl`: a confirmation first.
        .onOpenURL { client.handleOpenURL($0) }
    }
}

#if DEBUG

// MARK: - Layout harness (DEBUG only)

/// Renders `StreamScreen` at an exact point size so an iPad simulator can stand in for the iPhone
/// Duo's screens — 1000×710 for the unfolded inner display, 710×1000 for portrait and the folded
/// laptop posture, 500×710 and 710×500 for the outer display.
///
/// Only a launch argument turns it on. The whole contract:
///
/// * `-SillLayout 1000x710` — required; the fake screen's size in points.
/// * `-SillDrawer 1` — start with the app drawer open. This, `-SillScaleOpen 1` and `-SillSettings 1`
///   also work in a live session (the normal app with `-SillConnect`, and `-SillLive 1`), where each
///   opens 1.5 s after the stream screen shows, once the Desktop has started (StreamScreen).
/// * `-SillScaleOpen 1` — start with the Aa slider unfolded (as while a finger holds it);
///   `-SillScale 1.5` sets the scale it opens at.
/// * `-SillWindowMenu 1` — open the first thumbnail's traffic lights and keep them open.
/// * `-SillKeyboard 1` — start with the software keyboard shown: in the mock only the Keyboard
///   button lights (a real keyboard upsets the fake screen); under `-SillLive 1` and in the normal
///   app (with `-SillConnect`) the input view takes first responder half a second after the stream
///   screen shows, so the keyboard really comes up. A simulator shows it only with no hardware
///   keyboard connected to it (booted headless, or I/O › Keyboard › Connect Hardware Keyboard off).
/// * `-SillKeyboardToggle <s>[,<s>…]` — at each of these seconds after the stream screen shows, the
///   keyboard toggles as the Keyboard button does (the Settings panel put away, then the input
///   view's first responder toggled): a stand-in for a tap, since no gate drives the UI. In the
///   normal app too, and in the mock (where a real keyboard then upsets the fake screen).
/// * `-SillInputTest 1` — with `-SillConnect` on this Mac's loopback (127.0.0.1, [::1] or
///   localhost), once per launch, in the portrait key row's and trackpad's own code: the key row
///   taps cmd, esc, shift and ctrl through its caps' action 1.0, 1.4, 1.8 and 2.0 s after it shows
///   (⌘esc goes out; shift and ctrl stay latched), then the trackpad checks that a touch at its
///   centre lands on it and strokes 60 pt right and 40 down (2.6 s), taps with shift and ctrl held
///   around the click (3.2 s) and scrolls five 8 pt steps (3.8 s). Each event goes out as the
///   controls send it, and the console says what ran ("input test: …"). A synthetic host counts
///   what it gets as `in.dry` and posts nothing; a real host (Sill.app, SillHost without
///   `--synthetic`) posts it on this Mac, and the test does not check which it reached: point it
///   only at a synthetic host, or put a relay that drops kind 8 (input) in front of the host.
/// * `-SillActive none` — start with nothing streaming (also `desktop`, or a window ID like `104`).
///   The mock otherwise starts on Code's window, as the boards draw it.
/// * `-SillIdiom pad` — draw a screen taller than wide and narrower than 600 pt as an iPad draws
///   such a window (the compact halves), not as a phone does (`DuoLayout.phoneArrangement`), so an
///   iPhone simulator can photograph it; `phone` the other way round. Also in the normal app.
/// * `-SillLive 1` — host the app's *real* `StreamClient` in the frame instead of the mock, so the
///   simulator can connect to a Mac over Bonjour at a Duo size. Not connected yet shows the normal
///   connect screen inside the frame. Without it nothing touches the network, exactly as before.
/// * `-SillHUD 1` — not a harness argument, but it combines with these: the fps / frame age / RTT
///   readout on the display view (see `DiagnosticsHUDView`). It works with or without the harness.
/// * `-SillConnect 127.0.0.1:PORT` — connect straight to that address, in the normal app and under
///   `-SillLive 1`. The synthetic test hosts (`SillHost --synthetic`, the bare `SillMenuBar
///   --synthetic`) stay off Bonjour, so this is how the simulator reaches them.
/// * `-SillMoveTest 1` — with `-SillConnect`: that session counts as a direct (AWDL) one, and a
///   second later the same address is listed as the Mac's network row, so the move to the network
///   runs for real (a second connection shows the same host in its first window list and takes the
///   session over once the fence is down; the host logs a second "Client connected" and the first
///   "Client left", and streams on). `refused` lists port 1 instead: each try is given up after
///   5 s and the session stays direct. `other:PORT` lists that port of the same address under the
///   same name: another synthetic host there is refused at its first window list (another launch)
///   and not tried again while it stays listed; the first host's own port, with `-SillConnect`
///   going through a proxy that delays each direction, moves once the fence has waited out the
///   proxy's round trip. `to:HOST:PORT` lists that address under the same name, read as
///   `-SillConnect`'s is (`to:[::1]:P` works too): the same host reached another way, so the
///   Settings panel's route word changes at the hand-over (from `127.0.0.1`, none, to this Mac's
///   `fe80::…%en0`, "Wi-Fi"). The console says what happened
///   ("discovery: …", "move to the network …", "session: …" for the route;
///   `xcrun simctl launch --console-pty`).
/// * `-SillWiredTest HOST:PORT` — a "Wired" row's dial goes to the cable first and falls back to
///   the row as listed; this puts that fallback under test. `-SillConnect`'s dial, any network
///   row's (each counts as Wired) and a move's under `-SillMoveTest` go to HOST:PORT first, with
///   the address they would have dialled as the fallback: `192.0.2.1:9` (never answers) gives way
///   after 2.5 s, `127.0.0.1:1` (nothing listens) at once, and the session comes up on the
///   address as before ("wired dial … dialing unconstrained" on the console).
/// * `-SillPathTest '<spec>'` — with `-SillConnect`: the session's Mac is listed as a network row
///   whose interfaces change on cue, so the session follows the best path for real
///   (`StreamClient.followBestPath`). The spec: `wifi=HOST:PORT cable=HOST:PORT` (where a dial to
///   the row's Wi-Fi and to its cable goes), then events `SECONDS:WHAT` from the first `.ready`:
///   `+cable` (the row gains anpi0), `-cable` (it loses it, and a session on the cable is reported
///   unsatisfied, as iOS reports a pulled cable), `cut` (it loses it, and a session on the cable is
///   closed at once), `close` (the session's connection closed at once, the row as it is: the Mac
///   evicting the device), `-row` (it loses it, nothing more), `mute` (pongs stop counting),
///   `-wifi`, `+wifi`. A `cable=` that never answers (`192.0.2.1:9`), refuses (`127.0.0.1:1`) or
///   is another synthetic host fails each move to the cable (tried less often each time, and
///   another host's listing not again). `direct` counts the session as one over AWDL, so the row
///   is where the move from AWDL takes it. With the iPad on this Mac's cable, this Mac's own
///   `fe80::…%en14` reads "Wired" and `fe80::…%en0` "Wi-Fi": `-SillConnect fe80::…%en0:PORT
///   -SillPathTest 'wifi=fe80::…%en0:PORT cable=fe80::…%en14:PORT 3:+cable'` moves the session to
///   the cable 2 s after the cable is listed, and the host logs "Client connected: …%en14" and
///   "Client left: …%en0". The console says what happened ("path: …").
/// * `-SillSettings 1` — start with the Settings panel open (a real Mac's state under `-SillLive 1`).
/// * `-SillSettingsEnd 1` — with `-SillSettings 1`: the panel's rows start scrolled to their end,
///   so a photo of a short screen shows the last groups (Direct Wireless, Away from home, This
///   iPad). `-SillSettingsScroll gestures` starts them at the This iPad group instead (its switch
///   and rows, which its footnote pushes out of the end's view on a short screen).
/// * `-SillSettingsCase <case>` — what the mock Mac's settings look like: `default` (Sill.app),
///   `cli`, `software`, `custom`, `vdproblem`, `vdstream`, `legacy`, `pending`, `timeout`,
///   `direct`, `directlink` (connected over it), `nodirect` (a host without it), `wired` or
///   `noroute`; and for the Away from home group, away from home: `remote` (through Tailscale,
///   48 ms, saved), `remoteinternet` or `remoteslow` (the slow-link callout); at home:
///   `remotepair` (Pair This iPad…), `remoteoff` (the footnote only) or `noremote` (no kind 18: no
///   group) (see `MockCatalog.SettingsCase`). The mock answers a pick after 0.35 s. The session's
///   route, the readout's last word: Wi-Fi, except `directlink` (Direct), `wired` (Wired),
///   `noroute` (none, as a connection whose path says nothing), and `remote`, `remoteinternet`
///   and `remoteslow` (none: the route line under it says how instead).
/// * `-Sill.trackpadGestures 0` — not a harness argument either: this device's switch for
///   three-finger gestures (the Settings panel's last group, This iPad) off for one run, in the
///   normal app too. The mock Mac takes gestures (`WindowList.gestures` 1) in every settings case
///   but `legacy`, whose group then says to update Sill on the Mac.
/// * `-SillScanOverlay 1` — the stream screen under Pair This iPad…'s overlay (a drawn viewfinder).
/// * `-SillPointer <state>` — the pointer sprite in one of docs/pointer-visibility-plan.md's states,
///   over the mock's 2800×1800 frame, drawn as a dim rectangle so a photo shows where the frame is
///   (the mock never streams): `mac@0.40,0.30` (the Mac has the pointer, over the stream: its arrow
///   in every layout), `device@0.62,0.55` (this device's trackpad: its arrow in portrait only),
///   `hidden` (the Mac has it, off the stream: none) or `pencil@0.50,0.50` (this device's Pencil:
///   none, unless `-SillPencilPointer 1`, Q2's flip, draws it in every layout). Ignored with
///   `-SillLive 1`, whose session shows the real thing.
/// * `-SillInputScript '<t> <step>; …'` — with `-SillLive 1` only: input for the simulator gates,
///   which have no finger (`InputScript`): `t` is seconds since the session's first window list, and
///   a step is `down`, `pad DX,DY`, `lift` or `click` on the portrait pad, `tap X,Y` on the stream
///   (a frame fraction), `key USAGE` (a hardware key) or `row USAGE` (a key of the portrait key
///   row). The console says "input script: …" at each. It runs only when the session was dialled
///   by `-SillConnect` to a loopback address and the host's first window list has no version
///   (Sill.app's always has, and would post the input to this Mac): else "input script: refused:
///   …" and nothing is sent. Point it only at `--synthetic` hosts.
/// * `-SillConnectCase <case>` — show the connect screen instead, in a discovery state: `looking`,
///   `hint` (nothing listed: the hint and Search Nearby), `nearby` (a Wi-Fi row and Direct
///   rows), `methods` (a row ending in each word: Wired, Wi-Fi, none, Direct, and long names) or
///   `denied` (Local Network access denied: the status says what to do, no hint); `update` (a Mac
///   refused this version: "Update Sill on your iPad to keep using Mac mini. It needs version 1.2
///   or later." as the status line above a Wi‑Fi row, and "Update Sill in the App Store" under it
///   when `-SillAppStoreURL https://apps.apple.com/app/id000000000` gives the link an address) or
///   `notice` (a goodbye reason this build does not know: the Mac's two-line message, no link);
///   or remote access's: `remote` (Remote rows), `addmac`, `addcode`, `addcodeerror`, `pairing`,
///   `remotedial`, `remotefail` (with `-SillRemoteFailure vpnoff|timeout|timeoutip|refused|dns|
///   wrongmac|revoked|notsill|gaveup|quit|removed|remoteoff`), `camera` (refused) or
///   `externalpair` (an outside link's confirmation). Ignored with `-SillLive 1`. The mock never
///   browses; Search Nearby and a row's tap only change what it shows (see
///   `MockCatalog.ConnectCase`).
/// * Real pairing, in the normal app and under `-SillLive 1` (not the mock): `-SillPairURL
///   '<sill://pair…>'` pairs with that link at launch without the confirmation; `-SillPairCode
///   <12 digits> -SillPairAddress host:port` the typed path; `-SillDialSaved 1` dials the first
///   saved Mac as a tap on its Remote row would; `-SillForgetMacs 1` clears the saved Macs and
///   this device's key; `-SillDeviceKeySE 1` makes and uses a Secure Enclave device key under its
///   own tag (R0-a: a real device only, the simulator has no Secure Enclave);
///   `-Sill.savedMacs '<JSON>'` seeds the saved Macs for one run (never written; `'[]'` empties);
///   `-SillRemoteRoute vpn|internet` makes a remote session to a test host on loopback count as
///   one through Tailscale or over the internet (the 60 fps request, the slow-link callout), and
///   `-SillScreenFPS 120` makes the simulator's screen count as a 120 Hz one (also in the mock).
/// * `-Sill.directWirelessMacs '("Mac mini")'` — not a harness argument either: the device's saved
///   memory of Macs seen with Direct Wireless on, which a launch argument sets for one run (`'()'`
///   empties it), in the normal app and under `-SillLive 1`. Unlike `-Sill.savedMacs`, what the
///   run learns is still saved.
/// * Versions, in the normal app too: `-SillHelloVersion <v>` is the version this device's hello
///   (kind 23) gives, for a host's device floor under test (`SILL_TEST_MIN_DEVICE_VERSION`);
///   `-SillAppStoreURL <https url>` is the App Store link's address while SillLinks has none.
///
/// A fake screen too wide for the simulator but fitting on its side (1133×744 on an iPad Pro 13"
/// held upright) is drawn a quarter turn clockwise: rotate the screenshot back
/// (`sips -r 270 shot.png`). Touches follow the rotation. One that fits neither way (the Duo's
/// 710×1000 on an iPhone) is drawn scaled down to fit, upright or turned, whichever is larger
/// (`Fit`); only the drawing shrinks, the stream screen still lays out at the fake size, and the
/// console says so ("harness: 710x1000 drawn at 0.62"). A fake screen that reaches into the
/// simulator's own safe area (a phone's whole container on that phone: 440x894 on an iPhone 18 Pro
/// Max, 402x812 on an 18 Pro) passes the stream screen the simulator's bottom inset, which it
/// ignores, so the trackpad runs past the fake screen's bottom edge: photograph such a size on a
/// larger simulator, or in the normal app.
///
/// Console lines for the gates, in the harness and the normal app alike: `viewport: 386×241 pt,
/// scale none, 60 fps` for each viewport the stream screen sends the Mac (StreamScreen).
///
/// Launch arguments land in `NSArgumentDomain`, which is not persisted, so a normal launch is
/// exactly the app it was before. None of this is built in Release.
///
/// The fake screen is a fixed frame centred on black with a 1 pt #333 ring so its bounds are
/// visible in a screenshot. The ring sits *outside* the frame, so the interior is exactly W×H.
/// The container ignores the safe area, and since the frame is centred and smaller than the
/// device's safe area, the iPad's own insets never reach `StreamScreen`: the fake screen behaves
/// like a device screen with zero insets.
struct LayoutHarness: View {
    struct Spec {
        let size: CGSize
        let drawerOpen: Bool
        let keyboardShown: Bool
        let scaleOpen: Bool
        let textScale: Double?
        let live: Bool
        /// What the mock should be streaming. Ignored when `live`.
        let mockActive: StreamSource
        let settingsOpen: Bool
        /// The mock Mac's settings. Ignored when `live`.
        let settingsCase: MockCatalog.SettingsCase
        /// The connect screen in a discovery state, instead of the stream screen. Ignored when `live`.
        let connectCase: MockCatalog.ConnectCase?
        /// The stream screen under the pairing overlay.
        let scanOverlay: Bool
        /// The mock's pointer state (`-SillPointer`), and Q2's flip (`-SillPencilPointer 1`). Ignored
        /// when `live`.
        let pointer: String?
        let pencilPointer: Bool

        static var fromLaunchArguments: Spec? {
            let defaults = UserDefaults.standard
            guard let raw = defaults.string(forKey: "SillLayout") else { return nil }
            let parts = raw.lowercased().split(separator: "x")
            guard parts.count == 2,
                  let width = Double(parts[0]), let height = Double(parts[1]),
                  width > 0, height > 0 else { return nil }
            return Spec(size: CGSize(width: width, height: height),
                        drawerOpen: defaults.bool(forKey: "SillDrawer"),
                        keyboardShown: defaults.bool(forKey: "SillKeyboard"),
                        scaleOpen: defaults.bool(forKey: "SillScaleOpen"),
                        textScale: defaults.double(forKey: "SillScale") > 0 ? defaults.double(forKey: "SillScale") : nil,
                        live: defaults.bool(forKey: "SillLive"),
                        mockActive: mockActive(defaults.string(forKey: "SillActive")),
                        settingsOpen: defaults.bool(forKey: "SillSettings"),
                        settingsCase: MockCatalog.SettingsCase(rawValue: defaults.string(forKey: "SillSettingsCase") ?? "") ?? .default,
                        connectCase: MockCatalog.ConnectCase(rawValue: defaults.string(forKey: "SillConnectCase") ?? ""),
                        scanOverlay: defaults.bool(forKey: "SillScanOverlay"),
                        pointer: defaults.string(forKey: "SillPointer"),
                        pencilPointer: defaults.bool(forKey: "SillPencilPointer"))
        }

        private static func mockActive(_ raw: String?) -> StreamSource {
            switch raw?.lowercased() {
            case "none": return .none
            case "desktop": return .desktop
            case let value?: return UInt32(value).map { StreamSource.window($0) } ?? .window(102)
            case nil: return .window(102)
            }
        }
    }

    let spec: Spec
    /// The app's real client, used only when `-SillLive 1` was passed.
    @ObservedObject var live: StreamClient
    @StateObject private var mock: StreamClient

    init(spec: Spec, live: StreamClient) {
        self.spec = spec
        self.live = live
        _mock = StateObject(wrappedValue: spec.connectCase.map(MockCatalog.connectClient)
                                ?? MockCatalog.client(active: spec.mockActive, settings: spec.settingsCase,
                                                      pointer: spec.pointer, pencilPointer: spec.pencilPointer))
    }

    var body: some View {
        GeometryReader { geo in
            let fit = Fit(screen: spec.size, room: geo.size)
            ZStack {
                Color.black
                screen
                    .frame(width: spec.size.width, height: spec.size.height)
                    .clipped()
                    .padding(1)
                    .background(Color(hex: 0x333333))
                    .rotationEffect(.degrees(fit.turned ? 90 : 0))
                    // Only the drawing shrinks: the stream screen still lays out at the fake size.
                    .scaleEffect(fit.scale)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear {
                if fit.scale < 1 {
                    print("harness: \(Int(spec.size.width))x\(Int(spec.size.height)) drawn at "
                          + String(format: "%.2f", fit.scale) + (fit.turned ? ", turned" : ""))
                }
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .statusBar(hidden: true)
        .onAppear {
            if spec.live {
                live.startBrowsing()
                live.startRemote()
                live.connectFromLaunchArgument()
            }
        }
    }

    /// How the fake screen goes on the simulator's: as it is when it fits, a quarter turn when it
    /// fits only on its side, and otherwise scaled down, upright or turned, whichever is larger (the
    /// Duo's and the iPad's sizes on an iPhone simulator). The ring is counted in the scaled case.
    struct Fit: Equatable {
        let turned: Bool
        let scale: CGFloat
        init(screen: CGSize, room: CGSize) {
            if screen.width <= room.width && screen.height <= room.height {
                turned = false; scale = 1
            } else if screen.height <= room.width && screen.width <= room.height {
                turned = true; scale = 1
            } else {
                let w = screen.width + 2, h = screen.height + 2
                let upright = min(room.width / w, room.height / h)
                let onItsSide = min(room.width / h, room.height / w)
                turned = onItsSide > upright
                scale = max(0.01, max(upright, onItsSide))
            }
        }
    }

    @ViewBuilder private var screen: some View {
        if spec.live {
            ZStack {
                Color.black
                if live.connected {
                    StreamScreen(client: live,
                                 drawerOpen: spec.drawerOpen,
                                 keyboardShown: spec.keyboardShown,
                                 scaleOpen: spec.scaleOpen, textScale: spec.textScale,
                                 settingsOpen: spec.settingsOpen)
                } else {
                    ConnectScreen(client: live)
                }
            }
        } else if let c = spec.connectCase {
            let options = MockCatalog.connectScreenOptions(c)
            ZStack {
                Color.black
                ConnectScreen(client: mock, adding: options.adding, typed: options.typed, scannerOverride: options.scanner)
            }
        } else {
            StreamScreen(client: mock,
                         drawerOpen: spec.drawerOpen,
                         keyboardShown: spec.keyboardShown,
                         scaleOpen: spec.scaleOpen, textScale: spec.textScale,
                         settingsOpen: spec.settingsOpen,
                         pairingOverlay: spec.scanOverlay, scannerOverride: .placeholder)
        }
    }
}

/// `-SillInputScript '<t> <step>; …'` (with `-SillLive 1`): input for the simulator gates of
/// docs/pointer-visibility-plan.md (S2–S5), which cannot put a finger on the simulator. `t` is
/// seconds since the session's first window list; a step is
/// * `down` — a finger lands on the portrait pad: a stroke starts, its cursor from the anchor;
/// * `pad DX,DY` — that finger moves DX, DY points (a stroke starts first if none is down);
/// * `lift` — it comes up;
/// * `click` — a tap on the pad: a click where its cursor is;
/// * `tap X,Y` — a finger's tap on the stream at that fraction of the frame;
/// * `key USAGE` — a hardware key (a HID usage), down and up: this device's pointer hides;
/// * `row USAGE` — a key of the portrait key row: what the sprite shows stays;
/// * `gesture NAME[,FINGERS]` — a three-finger (or four-finger) gesture a surface decided, through
///   `StreamClient.sendGesture` as a surface's decision goes (the switch, the Mac's `gestures`, the
///   Desktop first while a window streams): swipeUp, swipeDown, swipeLeft, swipeRight, pinch or
///   spread; the console says whether it went ("input script: t=… gesture swipeUp: sent").
/// The pad and the overlay register themselves as they join a window, and each step calls their
/// own methods, so the feed, the anchor and the sprite get what a finger would give them. The
/// console prints "input script: t=… <step>" as each runs. Once per launch.
///
/// Only against a test host on this Mac (`refusal`): the steps send real input, and Sill.app, whose
/// home door admits loopback, would post it, clicking, typing and moving the Mac's real pointer. So
/// the session must have been dialled to a loopback address, and its first window list must carry
/// no `hostVersion` (Sill.app always sends one; SillHost and the bare SillMenuBar never do). The
/// gates start only `--synthetic` hosts, which post nothing; SillHost or the bare SillMenuBar without
/// `--synthetic` would post the input, so never point a script at one.
enum InputScript {
    enum Step: Equatable, CustomStringConvertible {
        case down, pad(dx: Double, dy: Double), lift, click, tap(x: Double, y: Double), key(UInt16), row(UInt16)
        case gesture(TrackpadGestures.Gesture, fingers: Int)

        var description: String {
            switch self {
            case .down: return "down"
            case .pad(let dx, let dy): return "pad \(dx),\(dy)"
            case .lift: return "lift"
            case .click: return "click"
            case .tap(let x, let y): return "tap \(x),\(y)"
            case .key(let usage): return "key \(usage)"
            case .row(let usage): return "row \(usage)"
            case .gesture(let g, let fingers): return "gesture \(g.rawValue)" + (fingers == 3 ? "" : ",\(fingers)")
            }
        }
    }

    /// The portrait pad and the stream's overlay now in a window (TrackpadSurface, InputOverlayView).
    static weak var pad: TrackpadSurface?
    static weak var overlay: InputOverlayView?
    private static var started = false

    /// The steps of a script, in its order; nil when a step does not read.
    static func parse(_ text: String) -> [(at: Double, step: Step)]? {
        var steps: [(at: Double, step: Step)] = []
        for item in text.split(separator: ";") {
            let words = item.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard words.count >= 2, let at = Double(words[0]), at.isFinite, at >= 0 else { return nil }
            let pair = words.count == 3 ? words[2].split(separator: ",").compactMap { Double($0) } : []
            let step: Step
            switch (words[1], words.count) {
            case ("down", 2): step = .down
            case ("lift", 2): step = .lift
            case ("click", 2): step = .click
            case ("pad", 3) where pair.count == 2: step = .pad(dx: pair[0], dy: pair[1])
            case ("tap", 3) where pair.count == 2: step = .tap(x: pair[0], y: pair[1])
            case ("key", 3): guard let usage = UInt16(words[2]) else { return nil }; step = .key(usage)
            case ("row", 3): guard let usage = UInt16(words[2]) else { return nil }; step = .row(usage)
            case ("gesture", 3):
                let parts = words[2].split(separator: ",").map(String.init)
                guard let g = TrackpadGestures.Gesture(rawValue: parts[0]), parts.count <= 2 else { return nil }
                let fingers = parts.count == 2 ? Int(parts[1]) : 3
                guard let fingers, fingers == 3 || fingers == 4 else { return nil }
                step = .gesture(g, fingers: fingers)
            default: return nil
            }
            steps.append((at, step))
        }
        return steps
    }

    /// Why the script must not run against this session, or nil when it may: it runs only when the
    /// session was dialled to a loopback address (`-SillConnect 127.0.0.1:PORT`, `::1:PORT` or
    /// `localhost:PORT`; a Bonjour row, a saved Mac or any other address never is) and the host's
    /// first window list carries no `hostVersion`, which Sill.app always sends. (`[::1]:PORT` never
    /// arrives: UserDefaults reads a launch argument that starts with `[` as a property list, and
    /// drops it.)
    static func refusal(endpoint: NWEndpoint?, hostVersion: String?) -> String? {
        guard let endpoint, isLoopback(endpoint) else {
            return "the session was not dialled to a loopback address (-SillConnect 127.0.0.1:PORT)"
        }
        if let hostVersion { return "the host says it is Sill \(hostVersion), which posts input to this Mac" }
        return nil
    }

    /// An address on this Mac's loopback: 127.0.0.0/8, ::1 (also as an IPv4-mapped address), or
    /// the name localhost.
    static func isLoopback(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let address): return address.isLoopback
        case .ipv6(let address): return address.isLoopback || address.asIPv4?.isLoopback == true
        case .name(let name, _): return name.lowercased() == "localhost"
        @unknown default: return false
        }
    }

    /// The session's first window list is in (StreamClient): the script starts, once per launch,
    /// if `refusal` lets it.
    static func sessionListed(_ client: StreamClient) {
        let defaults = UserDefaults.standard
        guard !started, defaults.bool(forKey: "SillLive"), let text = defaults.string(forKey: "SillInputScript") else { return }
        started = true
        if let why = refusal(endpoint: client.connection?.endpoint, hostVersion: client.hostVersion) {
            print("input script: refused: \(why)")
            return
        }
        guard let steps = parse(text) else {
            print("input script: cannot read it: \(text)")
            return
        }
        print("input script: \(steps.count) steps")
        for (at, step) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + at) { [weak client] in
                guard let client else { return }
                run(step, at: at, client: client)
            }
        }
    }

    private static func run(_ step: Step, at: Double, client: StreamClient) {
        var done = true
        switch step {
        case .down: if let pad { pad.scriptDown() } else { done = false }
        case .pad(let dx, let dy): if let pad { pad.scriptMove(dx: dx, dy: dy) } else { done = false }
        case .lift: if let pad { pad.scriptLift() } else { done = false }
        case .click: if let pad { pad.scriptClick() } else { done = false }
        case .tap(let x, let y): if let overlay { overlay.scriptTap(x: x, y: y) } else { done = false }
        case .key(let usage): if let overlay { overlay.scriptKey(usage) } else { done = false }
        case .row(let usage):
            client.sendFromKeyRow(.key(hidUsage: usage, down: true, modifiers: 0))
            client.sendFromKeyRow(.key(hidUsage: usage, down: false, modifiers: 0))
        case .gesture(let g, let fingers):
            let went = client.sendGesture(g, fingers: fingers)
            print(String(format: "input script: t=%.2f ", at) + "\(step): " + (went ? "sent" : "not sent (the switch is off, or the Mac takes none)"))
            return
        }
        print(String(format: "input script: t=%.2f ", at) + (done ? "\(step)" : "\(step): nothing to take it in this layout"))
    }
}
#endif

/// Before a Mac is picked: the Macs the browsers found and the saved ones they do not list, as
/// drawer-style rows that end in how each is reachable ("Wired", "Wi-Fi", or "Direct" for one
/// reached over peer-to-peer Wi-Fi; "Remote" for a saved Mac dialed through its VPN or the internet;
/// nothing when the device cannot tell); when none turns up on the network, why, with Search
/// Nearby; and Add a Mac… last, which unfolds the pairing card in the column's place
/// (docs/remote-access-plan.md §7.8, §7.10). A saved Mac's row has a menu: Connect or Connect
/// Remotely, and Forget. Along the bottom, a footer says Sill needs its free Mac app and where to
/// get it, and links support and the privacy policy (App Review guidelines 1.5, 2.1 and 5.1.1(i)).
/// None of it shows while connected: the stream screen takes this one's place (`ContentView`).
struct ConnectScreen: View {
    @ObservedObject var client: StreamClient
    @State private var adding: Bool
    @State private var typed: Bool
    /// A field of the card has the keyboard.
    @State private var editing = false
    /// The DEBUG harness's stand-in for the camera (the simulator has none); nil on a device.
    let scannerOverride: CodeScanner.Mode?
    @AccessibilityFocusState private var titleFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(client: StreamClient, adding: Bool = false, typed: Bool = false, scannerOverride: CodeScanner.Mode? = nil) {
        self.client = client
        self.scannerOverride = scannerOverride
        _adding = State(initialValue: adding)
        _typed = State(initialValue: typed)
    }

    private var device: String { StreamClient.deviceWord }
    private var scannerMode: CodeScanner.Mode { scannerOverride ?? CodeScanner.currentMode }
    /// Where the scanner cannot run (the simulator), the card starts on the typed path.
    private var scannerUsable: Bool { scannerOverride != nil || CodeScanner.isSupported }

    /// The least room between the column and the footer.
    private static let footerGap: CGFloat = 24
    /// How far a footer link's tap area reaches above and below its words: a footnote line is about
    /// 16 pt, so the area is about 44 pt tall at the default size. The layout never sees it (the
    /// Settings panel's Done does the same).
    private static let linkReach: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let layout = ConnectLayout(size: geo.size)
            // A field has the keyboard: the column goes to the top (the half-folded Duo's is already
            // in the top half), so Pair stays above the keyboard. The screen ignores the keyboard's
            // safe area below, so nothing else moves (the footer stays under the keyboard).
            let toTop = editing && !layout.topHalf
            // The column where it sat before there was a footer, and the footer along the bottom:
            // the footer never moves the title. Only a column that would come within the gap of the
            // footer rises to keep it; one too tall for that even at the top (many Macs on a phone
            // held sideways) scrolls above the footer, which stays in reach, as the Settings panel
            // keeps its header and foot. One scroll view whatever the fit, so a fit that changes
            // (the card's words folding while a field has the keyboard, a row more) never builds
            // the column anew: the card keeps its fields and its camera.
            VStack(spacing: 0) {
                ScrollView(.vertical) {
                    ColumnOverFooter(
                        // The Duo half-folded: centred in the top half, at most 500 pt tall, so nothing
                        // crosses the crease and the keyboard has the lower half (the footer stays along
                        // the bottom, under the keyboard while it is up). Elsewhere centred in the whole
                        // height, as before.
                        centreHeight: layout.topHalf ? min(geo.size.height / 2, 500) : geo.size.height,
                        visibleHeight: geo.size.height, gap: Self.footerGap, atTop: toTop) {
                        column(layout)
                            .frame(width: adding && layout.short && !typed ? layout.sideBySideWidth : layout.columnWidth,
                                   alignment: .leading)
                            // Placed by its leading edge, not centred: the side-by-side card is wider
                            // than the rows, and centring it moved the title sideways as the card
                            // unfolded.
                            .padding(.leading, layout.columnX)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        // The footer's height, measured here; the one shown is the one below.
                        footer(layout)
                            .hidden()
                            .accessibilityHidden(true)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicatorsFlash(onAppear: true)
                // A column that scrolls fades out above the footer instead of being cut off at it, and
                // keeps a little room before it. Both are in the gap, which a column that fits keeps
                // clear, so neither ever reaches one.
                .mask {
                    VStack(spacing: 0) {
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: Self.footerGap / 2)
                        Color.clear.frame(height: Self.footerGap / 2)
                    }
                }
                footer(layout)
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onChange(of: client.pairing) { old, new in
            // Paired but no session came (10 s): the card closes, and the Mac is a saved row.
            if case .paired = old, new == .idle, !client.connected { fold() }
        }
        // VoiceOver hears each status line (§7.8): a remote dial and why it failed, a reconnect,
        // "Stopped trying…", "… is saved", Forget, and the line a session ended with (why the Mac
        // closed it), which is already set when this screen comes back. A changed Text alone is
        // never spoken, and the rows keep the focus.
        .onAppear { announce(client.status) }
        .onChange(of: client.status) { _, line in announce(line) }
    }

    /// Not the idle "Looking for Macs…" lines, which change as the search does.
    private func announce(_ line: String) {
        guard !line.isEmpty, line != StreamClient.lookingOnNetwork, line != StreamClient.lookingNearby else { return }
        AccessibilityNotification.Announcement(line).post()
    }

    private func column(_ layout: ConnectLayout) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Leading, so the title never jumps sideways when the hint, a row or the card widens the
            // column. Vertically it is still centred (ColumnOverFooter): what adds height moves it up
            // by half as much.
            Text(adding || client.pendingLink != nil ? "Add a Mac" : "Connect to a Mac")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 10)
                .accessibilityAddTraits(adding ? .isHeader : [])
                .accessibilityFocused($titleFocused)

            if let link = client.pendingLink {
                LinkConfirmation(link: link, pair: {
                    // The card shows the pairing's progress; should it fail, the scanner (or the
                    // typed path where there is none) is there to try again.
                    typed = !scannerUsable
                    adding = true
                    client.confirmPendingLink()
                }, cancel: { client.cancelPendingLink() })
                .padding(.horizontal, 10)
                .padding(.top, 4)
            } else if adding {
                AddMacCard(client: client, layout: layout, typed: $typed, scannerMode: scannerMode, close: fold, editing: $editing)
                    .padding(.horizontal, 10)
                    .padding(.top, 4)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            } else {
                rows
            }
        }
    }

    @ViewBuilder private var rows: some View {
        Text(client.status)
            .font(.system(size: 13))
            .foregroundStyle(Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.bottom, 4)

        // A Mac that no longer serves this version said so (GoodbyePolicy's "update", its words the
        // status line above): where to get the new one, while the status line still says why. Not
        // before Sill's App Store address is known (SillLinks): the words say what to do anyway.
        if let notice = client.notice, notice.storeLink, notice.text == client.status, let url = SillLinks.appStore {
            Link(destination: url) {
                Text("Update Sill in the App Store")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the App Store.")
        }

        ForEach(client.macs) { mac in
            // The kind of link, never the Wi-Fi network's name: that needs Location access, which
            // Sill does not ask for (DiscoveryPolicy.method); "Remote" for a saved Mac dialed away
            // from home.
            DrawerRow(height: 50, highlighted: false, title: mac.name, trailing: mac.word,
                      action: { client.connect(to: mac) }) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.iconFallback)
                    Image(systemName: "desktopcomputer")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                }
                .frame(width: 32, height: 32)
            }
            .accessibilityLabel(mac.word.map { "\(mac.name), \($0)" } ?? mac.name)
            .accessibilityHint(mac.direct ? "Connects without a shared Wi\u{2011}Fi network"
                               : mac.route == .remote ? "Connects through your VPN or the internet." : "")
            .contextMenu { menu(for: mac) }
        }

        if client.showsNearbyHint {
            Text("Your Mac has to be on the same Wi\u{2011}Fi network as this \(device), or have Direct Wireless Connection turned on in Sill. Away from home, add it once with a code from your Mac.")
                .font(.system(size: 13))
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
            // Once the nearby search runs, a line in the button's place says so, whatever the
            // status line says (a disconnect's message stays there), at the button's height so
            // nothing moves.
            if client.searchingNearby {
                Text("Also looking nearby")
                    .font(.system(size: 15))
                    .foregroundStyle(Palette.muted)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 10)
            } else {
                Button(action: {
                    client.searchNearby()
                    // The button leaves from under VoiceOver's cursor: say what it started.
                    AccessibilityNotification.Announcement("Also looking nearby").post()
                }) {
                    Text("Search Nearby")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .padding(.horizontal, 10)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Also looks for a Mac with Direct Wireless Connection turned on, without a Wi\u{2011}Fi network.")
            }
        }

        // Always the last line, from the first frame, so nothing moves when it is needed.
        Button(action: unfold) {
            Text("Add a Mac…")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.horizontal, 10)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Pairs this \(device) with a Mac so you can reach it away from home.")
    }

    /// A saved Mac's row: Connect (a Remote row) or Connect Remotely (its network row, to try the
    /// VPN path at home), and Forget. Other Macs' rows have no menu.
    @ViewBuilder private func menu(for mac: FoundMac) -> some View {
        if let id = mac.macID {
            if mac.route == .remote {
                Button { client.connect(to: mac) } label: { Label("Connect", systemImage: "globe") }
            } else if mac.route == .network {
                Button { client.connectRemotely(id) } label: { Label("Connect Remotely", systemImage: "globe") }
            }
            let name = client.savedMac(id) != nil ? client.displayName(id) : mac.name
            Button(role: .destructive) { client.forget(id) } label: { Label("Forget \(name)", systemImage: "trash") }
        }
    }

    private func unfold() {
        client.pairing = .idle
        typed = !scannerUsable
        withAnimation(reduceMotion ? .easeOut(duration: 0.18) : .spring(duration: 0.3, bounce: 0.1)) { adding = true }
        titleFocused = true
    }

    private func fold() {
        client.cancelPairing()
        editing = false
        withAnimation(.easeOut(duration: 0.18)) { adding = false }
        titleFocused = true
    }

    // MARK: The footer

    /// For someone who found Sill here first, and for App Review: what else it needs, where to get
    /// it, where to get help, and the privacy policy. Muted and 13 pt like the status line, but it
    /// follows the text size, up to the Settings panel's cap (the column keeps its fixed sizes); it
    /// wraps, never truncates. Each link opens in Safari (a Link hands its URL to the environment's
    /// openURL), and VoiceOver reads it as a link. The addresses are SillLinks'.
    private func footer(_ layout: ConnectLayout) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Needs the free Sill app on your Mac.")
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            // All three on one line while they fit, else the download link over the other two,
            // the lines far enough apart that their tap areas meet without overlapping. Upward the
            // areas reach a little into the line above, which is plain text.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    downloadLink
                    linkSeparator
                    supportAndPrivacy
                }
                VStack(alignment: .leading, spacing: 2 * Self.linkReach) {
                    downloadLink
                    supportAndPrivacy
                }
            }
        }
        .font(.footnote)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .padding(.horizontal, 10)
        // Under the column's own edge and as wide as the rows, so the two line up; on a screen
        // narrower than 412 pt (a phone, a window in Slide Over) that is the screen's width less
        // the margins, so the links go to a second line rather than past the edge.
        .frame(width: layout.columnWidth, alignment: .leading)
        .padding(.leading, layout.columnX)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Room for the last link's tap area, which then stays on the screen.
        .padding(.bottom, Self.linkReach)
    }

    private var downloadLink: some View {
        footerLink("Get it at \(SillLinks.siteName)", to: SillLinks.download)
    }

    /// Support, then the privacy policy, on one line.
    private var supportAndPrivacy: some View {
        HStack(spacing: 0) {
            footerLink("Support", to: SillLinks.support)
            linkSeparator
            footerLink("Privacy Policy", to: SillLinks.privacy)
        }
    }

    /// The dot between two links on a line. VoiceOver skips it.
    private var linkSeparator: some View {
        Text(" · ")
            .foregroundStyle(Palette.muted)
            .accessibilityHidden(true)
    }

    private func footerLink(_ title: LocalizedStringKey, to url: URL) -> some View {
        Link(destination: url) {
            Text(title)
                .foregroundStyle(Palette.accent)
                // A link centres a label that wraps (a longer address); keep it on the footer's edge.
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, Self.linkReach)
                .contentShape(Rectangle())
        }
        .padding(.vertical, -Self.linkReach)
    }
}

/// The connect screen's column inside the scroll view that sits above its footer. The column sits
/// where it would without a footer: centred in `centreHeight` (the whole height, or the Duo's top
/// half) or, while a field has the keyboard, at the top. A column that would come within `gap` of
/// the footer rises to keep it, but never closer than 16 pt to the top. The content is then exactly
/// the scroll view's height, so nothing scrolls; a column that cannot keep both makes the content
/// taller, with the same 16 pt above it, and scrolls. So at the switch the column neither moves nor
/// jumps: it rises until it is 16 pt from the top, and from there it scrolls.
///
/// The second subview is the footer again, hidden, which only gives the footer's height: the scroll
/// view is `visibleHeight` less that, and its content never learns its container's height.
private struct ColumnOverFooter: Layout {
    /// The height the column is centred in, from the top.
    let centreHeight: CGFloat
    /// The scroll view and the footer together: the screen's height.
    let visibleHeight: CGFloat
    let gap: CGFloat
    /// A field has the keyboard: the column at the top.
    let atTop: Bool
    /// The least room above the column, however it sits: risen, at the top or scrolling.
    private let topRoom: CGFloat = 16

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let (column, footer) = sizes(width: proposal.width, subviews) else { return .zero }
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? max(column.width, footer.width)
        let room = visibleHeight - footer.height
        // A point short of the scroll view while it fits, so no rounding ever lets it scroll.
        return CGSize(width: width, height: fits(column: column.height, room: room) ? max(0, room - 1)
                                                                                   : topRoom + column.height + gap)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let (column, footer) = sizes(width: bounds.width, subviews) else { return }
        let room = visibleHeight - footer.height
        let y: CGFloat
        if !fits(column: column.height, room: room) || atTop {
            y = topRoom
        } else {
            let centred = centreHeight / 2 - column.height / 2
            let clear = room - gap - column.height
            y = max(topRoom, min(centred, clear))
        }
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.minY + y), anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: column.height))
        subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: footer.height))
    }

    /// Whether the column keeps the room above it and the gap below without scrolling.
    private func fits(column: CGFloat, room: CGFloat) -> Bool {
        topRoom + column + gap <= room
    }

    /// The column's and the footer's heights at this width, each as tall as it wants.
    private func sizes(width: CGFloat?, _ subviews: Subviews) -> (CGSize, CGSize)? {
        guard subviews.count == 2 else { return nil }
        let proposal = ProposedViewSize(width: width, height: nil)
        return (subviews[0].sizeThatFits(proposal), subviews[1].sizeThatFits(proposal))
    }
}
