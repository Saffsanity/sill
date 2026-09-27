import SwiftUI
import UIKit

/// Which session's Mac menus the iPad's menu bar shows (docs/menu-bar-plan.md §7.4), and when it is
/// rebuilt. One per process; main thread.
///
/// The app can have several windows (scenes), each with its own StreamClient, and the bar is one for
/// the app. A window's key status says nothing about which of them the bar's choices would reach:
/// for an app built against the iOS 15 SDK or later every window is key in its own scene
/// (UIWindow.h), so two Sill windows are both key at once. So the bar shows the menus of the app's
/// one window, while exactly one window scene is connected; with two or more it shows none of them
/// (a choice could reach a session the user is not looking at), and each window's Menus button still
/// has its own session's. `WindowSessionObserver` in each scene tells the hub which session its
/// window holds; a scene connecting, going or coming forward, and a client whose top level changes
/// (its version, app, menus, stale flag or note) or whose session ends, ask UIKit for a rebuild when
/// they can change what the bar shows. UIKit rebuilds lazily (measured: at the next key event or
/// focus change), so the bar can hold an older top level for a while; each of its menus then asks by
/// the title it was built with (MacMenuState rule 11), and one the current top level lacks asks for
/// another rebuild. Only an iPad on iPadOS 26 or later has the bar; anywhere else nothing is
/// rebuilt, and the Menus button is the way in.
final class MacMenuHub {
    static let shared = MacMenuHub()

    /// Each scene's session and the window it is shown in (weak: a closed window leaves nothing).
    private struct Entry {
        weak var client: StreamClient?
        weak var window: UIWindow?
    }
    private var entries: [Entry] = []
    private var observers: [NSObjectProtocol] = []

    private init() {
        for name in [UIScene.willConnectNotification, UIScene.didDisconnectNotification, UIScene.didActivateNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.rebuild()
            })
        }
    }

    /// The session whose menus the bar shows, or none and why (the console's words).
    var focus: (client: StreamClient?, why: String) {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { $0.session.role == .windowApplication }
        guard scenes.count == 1, let scene = scenes.first else {
            return (nil, scenes.isEmpty ? "no window" : "\(scenes.count) windows: each one's Menus button has its own session's")
        }
        entries.removeAll { $0.client == nil || $0.window == nil }
        guard let client = entries.first(where: { $0.window?.windowScene === scene })?.client else {
            return (nil, "no session in the window")
        }
        return (client, "")
    }

    /// The client of the app's one window, whose menus the bar shows.
    var focused: StreamClient? { focus.client }

    /// A session's screen moved into `window` (nil: out of every window).
    func session(_ client: StreamClient, window: UIWindow?) {
        entries.removeAll { $0.client == nil || $0.client === client }
        if let window { entries.append(Entry(client: client, window: window)) }
        rebuild()
    }

    /// `client`'s top level changed, or its session ended, or one of its bar menus found no menu of
    /// its title in the current top level.
    func menusChanged(_ client: StreamClient) {
        guard client === focused else { return }
        rebuild()
    }

    /// Whether this device has the iPadOS 26 menu bar the Mac's menus are inserted in.
    static var hasMenuBar: Bool {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return false }
        if #available(iOS 26.0, *) { return true }
        return false
    }

    private func rebuild() {
        guard Self.hasMenuBar else { return }
        UIMenuSystem.main.setNeedsRebuild()
    }
}

/// A zero-size view beside a session's screen that tells `MacMenuHub` which window shows that
/// session, when it moves into one (one per scene, next to its StreamClient).
struct WindowSessionObserver: UIViewRepresentable {
    let client: StreamClient

    func makeUIView(context: Context) -> WindowSessionObserverView {
        let view = WindowSessionObserverView()
        view.client = client
        return view
    }

    func updateUIView(_ view: WindowSessionObserverView, context: Context) {
        view.client = client
    }
}

final class WindowSessionObserverView: UIView {
    weak var client: StreamClient? {
        didSet { if client !== oldValue { report() } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        report()
    }

    private func report() {
        guard let client else { return }
        MacMenuHub.shared.session(client, window: window)
    }
}

#if DEBUG
/// `-SillSecondWindow 1`: a second Sill window (scene) opens 2 s after launch, as the system's New
/// Window does, so a run can show what the iPad's bar does with two (ContentView's contract). Once
/// per process.
enum SecondWindow {
    private static var opened = false

    static func openFromLaunchArgument() {
        guard !opened, UserDefaults.standard.bool(forKey: "SillSecondWindow") else { return }
        opened = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            print("menubar: harness: opening a second window")
            UIApplication.shared.requestSceneSessionActivation(nil, userActivity: nil, options: nil) { error in
                print("menubar: harness: no second window: \(error.localizedDescription)")
            }
        }
    }
}
#endif
