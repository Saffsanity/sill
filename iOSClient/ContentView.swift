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
            #if DEBUG
            client.connectFromLaunchArgument()   // -SillConnect host:port, for the off-Bonjour test hosts
            #endif
        }
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
/// * `-SillMoveTest 1` — with `-SillConnect`: that session counts as a direct (AWDL) one, and a
///   second later the same address is listed as the Mac's network row, so the move to the network
///   runs for real (a second connection shows the same host in its first window list and takes the
///   session over once the fence is down; the host logs a second "Client connected" and the first
///   "Client left", and streams on). `refused` lists port 1 instead: each try is given up after
///   5 s and the session stays direct. `other:PORT` lists that port of the same address under the
///   same name: another synthetic host there is refused at its first window list (another launch)
///   and not tried again while it stays listed; the first host's own port, with `-SillConnect`
///   going through a proxy that delays each direction, moves once the fence has waited out the
///   proxy's round trip. `to:HOST:PORT` lists that address under the same name: the same host
///   reached another way, so the Settings panel's route word changes at the hand-over (from
///   `127.0.0.1`, none, to this Mac's `fe80::…%en0`, "Wi-Fi"). The console says what happened
///   ("discovery: …", "move to the network …", "session: …" for the route;
///   `xcrun simctl launch --console-pty`).
/// * `-SillWiredTest HOST:PORT` — a "Wired" row's dial goes to the cable first and falls back to
///   the row as listed; this puts that fallback under test. `-SillConnect`'s dial, any network
///   row's (each counts as Wired) and a move's under `-SillMoveTest` go to HOST:PORT first, with
///   the address they would have dialled as the fallback: `192.0.2.1:9` (never answers) gives way
///   after 2.5 s, `127.0.0.1:1` (nothing listens) at once, and the session comes up on the
///   address as before ("wired dial … dialing unconstrained" on the console).
/// * `-SillSettings 1` — start with the Settings panel open (a real Mac's state under `-SillLive 1`).
/// * `-SillSettingsCase <case>` — what the mock Mac's settings look like: `default` (Sill.app),
///   `cli`, `software`, `custom`, `vdproblem`, `vdstream`, `legacy`, `pending`, `timeout`,
///   `direct`, `directlink` (connected over it) or `nodirect` (a host without it) (see
///   `MockCatalog.SettingsCase`). The mock answers a pick after 0.35 s. The session's route, the
///   readout's last word: Wi-Fi, except `directlink` (Direct), `wired` (Wired) and `noroute`
///   (none, as a connection whose path says nothing).
/// * `-SillConnectCase <case>` — show the connect screen instead, in a discovery state: `looking`,
///   `hint` (nothing listed: the hint and Search Nearby), `nearby` (a Wi-Fi row and Direct
///   rows), `methods` (a row ending in each word: Wired, Wi-Fi, none, Direct, and long names) or
///   `denied` (Local Network access denied: the status says what to do, no hint).
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

/// Before a Mac is picked: the Macs the browsers found, as drawer-style rows that end in how each is
/// reachable ("Wired", "Wi-Fi", or "Direct" for one reached over peer-to-peer Wi-Fi; nothing when
/// the device cannot tell), and, when none turns up on the network, why, with Search Nearby. Along
/// the bottom, a footer says Sill needs its free Mac app, where to get it, and links the privacy
/// policy (App Review guidelines 2.1 and 5.1.1(i)). None of it shows while connected: the stream
/// screen takes this one's place (`ContentView`).
struct ConnectScreen: View {
    @ObservedObject var client: StreamClient

    private var device: String { UIDevice.current.userInterfaceIdiom == .phone ? "iPhone" : "iPad" }

    /// The least room between the column and the footer.
    private static let footerGap: CGFloat = 24
    /// How far a footer link's tap area reaches above and below its words: a footnote line is about
    /// 16 pt, so the area is about 44 pt tall at the default size. The layout never sees it (the
    /// Settings panel's Done does the same).
    private static let linkReach: CGFloat = 14

    var body: some View {
        // The column centred on the screen, where it sat before there was a footer, and the footer
        // along the bottom: the footer never moves the title. Only a column that would come within
        // the gap of the footer rises to keep it. One too tall for that even at the top (many Macs
        // on a phone held sideways) scrolls above the footer, which stays in reach, as the Settings
        // panel keeps its header and foot.
        ViewThatFits(in: .vertical) {
            ColumnOverFooter(gap: Self.footerGap) {
                column
                footer
            }
            VStack(spacing: 0) {
                ScrollView {
                    column.padding(.vertical, 16)
                }
                .scrollIndicatorsFlash(onAppear: true)
                // The rows fade into the edge above the footer instead of being cut off there.
                .mask {
                    VStack(spacing: 0) {
                        Color.black
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 24)
                    }
                }
                footer.padding(.top, 12)
            }
        }
    }

    private var column: some View {
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
                // The kind of link, never the Wi-Fi network's name: that needs Location access,
                // which Sill does not ask for (DiscoveryPolicy.method).
                DrawerRow(height: 50, highlighted: false, title: mac.name, trailing: mac.method?.word,
                          action: { client.connect(to: mac) }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.iconFallback)
                        Image(systemName: "desktopcomputer")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 32, height: 32)
                }
                .accessibilityLabel(mac.method.map { "\(mac.name), \($0.word)" } ?? mac.name)
                .accessibilityHint(mac.direct ? "Connects without a shared Wi\u{2011}Fi network" : "")
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
        // column. Vertically it is still centred (ColumnOverFooter): what adds height moves it up
        // by half as much.
        .frame(width: 380, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    /// For someone who found Sill here first, and for App Review: what else it needs, where to get
    /// it, and the privacy policy. Muted and 13 pt like the status line, but it follows the text
    /// size, up to the Settings panel's cap (the column keeps its fixed sizes); it wraps, never
    /// truncates. Each link opens in Safari (a Link hands its URL to the environment's openURL),
    /// and VoiceOver reads it as a link. The addresses are SillLinks'.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Needs the free Sill app on your Mac.")
                .foregroundStyle(Palette.muted)
                .fixedSize(horizontal: false, vertical: true)
            // Side by side while they fit on one line, else one under the other, far enough apart
            // that their tap areas meet without overlapping. Upward the areas reach a little into
            // the line above, which is plain text.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    footerLink("Get it at \(SillLinks.siteName)", to: SillLinks.download)
                    Text(" · ")
                        .foregroundStyle(Palette.muted)
                        .accessibilityHidden(true)
                    footerLink("Privacy Policy", to: SillLinks.privacy)
                }
                VStack(alignment: .leading, spacing: 2 * Self.linkReach) {
                    footerLink("Get it at \(SillLinks.siteName)", to: SillLinks.download)
                    footerLink("Privacy Policy", to: SillLinks.privacy)
                }
            }
        }
        .font(.footnote)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .padding(.horizontal, 10)
        // Under the column's own edge, so the two line up.
        .frame(width: 380, alignment: .leading)
        .frame(maxWidth: .infinity)
        // Room for the last link's tap area, which then stays on the screen.
        .padding(.bottom, Self.linkReach)
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

/// The connect screen's column and footer: the column centred in the whole height, where it sat
/// before there was a footer, and the footer along the bottom. A column that would come within
/// `gap` of the footer rises to keep the gap, no higher than the top. Its ideal height is both
/// parts and the gap, so under `ViewThatFits` a column that cannot keep the gap goes to the
/// scrolling form instead.
private struct ColumnOverFooter: Layout {
    let gap: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let (column, footer) = sizes(width: proposal.width, subviews) else { return .zero }
        let needed = column.height + gap + footer.height
        let height = proposal.height.flatMap { $0.isFinite ? max($0, needed) : nil } ?? needed
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? max(column.width, footer.width)
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let (column, footer) = sizes(width: bounds.width, subviews) else { return }
        subviews[1].place(at: CGPoint(x: bounds.minX, y: bounds.maxY - footer.height), anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: footer.height))
        let centred = bounds.midY - column.height / 2
        let clear = bounds.maxY - footer.height - gap - column.height
        subviews[0].place(at: CGPoint(x: bounds.minX, y: max(bounds.minY, min(centred, clear))), anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: column.height))
    }

    /// The column's and the footer's heights at this width, each as tall as it wants.
    private func sizes(width: CGFloat?, _ subviews: Subviews) -> (CGSize, CGSize)? {
        guard subviews.count == 2 else { return nil }
        let proposal = ProposedViewSize(width: width, height: nil)
        return (subviews[0].sizeThatFits(proposal), subviews[1].sizeThatFits(proposal))
    }
}
