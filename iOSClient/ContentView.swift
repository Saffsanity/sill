import SwiftUI
import Network

struct ContentView: View {
    @StateObject private var client = StreamClient()

    var body: some View {
        #if DEBUG
        if let spec = LayoutHarness.Spec.fromLaunchArguments {
            LayoutHarness(spec: spec)
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
        .onAppear { client.startBrowsing() }
    }
}

#if DEBUG

// MARK: - Layout harness (DEBUG only)

/// Renders `StreamScreen` at an exact point size so an iPad simulator can stand in for the iPhone
/// Duo's screens — 1000×710 for the unfolded inner display, 710×1000 for portrait and the folded
/// laptop posture, 500×710 and 710×500 for the outer display.
///
/// Only a launch argument turns it on: `-SillLayout 1000x710`, optionally with `-SillDrawer 1` and
/// `-SillKeyboard 1`. Launch arguments land in `NSArgumentDomain`, which is not persisted, so a
/// normal launch is exactly the app it was before. None of this is built in Release.
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

        static var fromLaunchArguments: Spec? {
            let defaults = UserDefaults.standard
            guard let raw = defaults.string(forKey: "SillLayout") else { return nil }
            let parts = raw.lowercased().split(separator: "x")
            guard parts.count == 2,
                  let width = Double(parts[0]), let height = Double(parts[1]),
                  width > 0, height > 0 else { return nil }
            return Spec(size: CGSize(width: width, height: height),
                        drawerOpen: defaults.bool(forKey: "SillDrawer"),
                        keyboardShown: defaults.bool(forKey: "SillKeyboard"))
        }
    }

    let spec: Spec
    @StateObject private var client = MockCatalog.client()

    var body: some View {
        ZStack {
            Color.black
            StreamScreen(client: client,
                         drawerOpen: spec.drawerOpen,
                         keyboardShown: spec.keyboardShown)
                .frame(width: spec.size.width, height: spec.size.height)
                .clipped()
                .padding(1)
                .background(Color(hex: 0x333333))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .statusBar(hidden: true)
    }
}
#endif

/// Before a Mac is picked: the Bonjour results as drawer-style rows.
struct ConnectScreen: View {
    @ObservedObject var client: StreamClient

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

            ForEach(client.hosts, id: \.self) { host in
                DrawerRow(height: 50, highlighted: false, title: name(of: host), trailing: nil,
                          action: { client.connect(to: host) }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.iconFallback)
                        Image(systemName: "desktopcomputer")
                            .font(.system(size: 16))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 32, height: 32)
                }
            }
        }
        .frame(width: 380)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func name(of result: NWBrowser.Result) -> String {
        if case .service(let name, _, _, _) = result.endpoint { return name }
        return "\(result.endpoint)"
    }
}
