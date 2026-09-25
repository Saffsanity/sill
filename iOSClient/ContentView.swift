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
/// * `-SillDrawer 1` — start with the app drawer open.
/// * `-SillScaleOpen 1` — start with the Aa slider unfolded (as while a finger holds it);
///   `-SillScale 1.5` sets the scale it opens at.
/// * `-SillWindowMenu 1` — open the first thumbnail's traffic lights and keep them open.
/// * `-SillKeyboard 1` — start with the software keyboard shown.
/// * `-SillActive none` — start with nothing streaming (also `desktop`, or a window ID like `104`).
///   The mock otherwise starts on Code's window, as the boards draw it.
/// * `-SillLive 1` — host the app's *real* `StreamClient` in the frame instead of the mock, so the
///   simulator can connect to a Mac over Bonjour at a Duo size. Not connected yet shows the normal
///   connect screen inside the frame. Without it nothing touches the network, exactly as before.
/// * `-SillHUD 1` — not a harness argument, but it combines with these: the fps / frame age / RTT
///   readout on the display view (see `DiagnosticsHUDView`). It works with or without the harness.
/// * `-SillConnect 127.0.0.1:PORT` — connect straight to that address, in the normal app and under
///   `-SillLive 1`. The synthetic test hosts (`SillHost --synthetic`, the bare `SillMenuBar
///   --synthetic`) stay off Bonjour, so this is how the simulator reaches them.
/// * `-SillSettings 1` — start with the Settings panel open (a real Mac's state under `-SillLive 1`).
/// * `-SillSettingsCase <case>` — what the mock Mac's settings look like: `default` (Sill.app),
///   `cli`, `software`, `custom`, `vdproblem`, `vdstream`, `legacy`, `pending`, `timeout`,
///   `direct`, `directlink` (connected over it) or `nodirect` (a host without it) (see
///   `MockCatalog.SettingsCase`). The mock answers a pick after 0.35 s.
/// * `-SillConnectCase <case>` — show the connect screen instead, in a discovery state: `looking`,
///   `hint` (nothing listed: the hint and Search Nearby), `nearby` (a network row and Direct
///   rows) or `denied` (Local Network access denied: the status says what to do, no hint).
///   Ignored with `-SillLive 1`. The mock never browses; Search Nearby and a row's tap only
///   change what it shows (see `MockCatalog.ConnectCase`).
///
/// A fake screen too wide for the simulator but fitting on its side (1133×744 on an iPad Pro 13"
/// held upright) is drawn a quarter turn clockwise: rotate the screenshot back
/// (`sips -r 270 shot.png`). Touches follow the rotation.
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
                        connectCase: MockCatalog.ConnectCase(rawValue: defaults.string(forKey: "SillConnectCase") ?? ""))
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
                                ?? MockCatalog.client(active: spec.mockActive, settings: spec.settingsCase))
    }

    var body: some View {
        GeometryReader { geo in
            let fits = spec.size.width <= geo.size.width && spec.size.height <= geo.size.height
            let turned = !fits && spec.size.height <= geo.size.width && spec.size.width <= geo.size.height
            ZStack {
                Color.black
                screen
                    .frame(width: spec.size.width, height: spec.size.height)
                    .clipped()
                    .padding(1)
                    .background(Color(hex: 0x333333))
                    .rotationEffect(.degrees(turned ? 90 : 0))
            }
            .frame(width: geo.size.width, height: geo.size.height)
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
        } else if spec.connectCase != nil {
            ZStack {
                Color.black
                ConnectScreen(client: mock)
            }
        } else {
            StreamScreen(client: mock,
                         drawerOpen: spec.drawerOpen,
                         keyboardShown: spec.keyboardShown,
                         scaleOpen: spec.scaleOpen, textScale: spec.textScale,
                         settingsOpen: spec.settingsOpen)
        }
    }
}
#endif

/// Before a Mac is picked: the Macs the browsers found, as drawer-style rows ("Direct" for one
/// reached over peer-to-peer Wi-Fi), and, when none turns up on the network, why, with Search Nearby.
struct ConnectScreen: View {
    @ObservedObject var client: StreamClient

    private var device: String { UIDevice.current.userInterfaceIdiom == .phone ? "iPhone" : "iPad" }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Connect to a Mac")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Palette.text)
                .padding(.horizontal, 10)

            Text(client.status)
                .font(.system(size: 13))
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 10)
                .padding(.bottom, 4)

            ForEach(client.macs) { mac in
                DrawerRow(height: 50, highlighted: false, title: mac.name,
                          trailing: mac.route == .direct ? "Direct" : mac.route == .remote ? "Remote" : nil,
                          action: { client.connect(to: mac) }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.iconFallback)
                        Image(systemName: "desktopcomputer")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 32, height: 32)
                }
                .accessibilityHint(mac.direct ? "Connects without a shared Wi\u{2011}Fi network"
                                   : mac.route == .remote ? "Connects through your VPN or the internet." : "")
            }

            if client.showsNearbyHint {
                Text("Your Mac has to be on the same Wi\u{2011}Fi network as this \(device), or have Direct Wireless Connection turned on in Sill.")
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
        }
        // Leading, so the title never jumps sideways when the hint or the first row widens the
        // column. Vertically it is still centred: what adds height moves it up by half as much.
        .frame(width: 380, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
