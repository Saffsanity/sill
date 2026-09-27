import SwiftUI
import UIKit

/// Which session's Mac menus the iPad's menu bar shows (docs/menu-bar-plan.md §7.4), and when it is
/// rebuilt. One per process; main thread.
///
/// The bar is the key window's: the app can have several windows (scenes), each with its own
/// StreamClient, and `KeyWindowObserver` in each tells the hub whose window is key. A client whose
/// top level changes (its version, app, menus, stale flag or note) calls `menusChanged`, and so does
/// the end of its session; either, and a change of `focused`, asks UIKit for a rebuild when it
/// concerns the focused client. UIKit rebuilds lazily (measured: at the next key event or focus
/// change), so the bar can hold an older top level for a while; each of its menus then asks by the
/// title it was built with (MacMenuState rule 11), and one the current top level lacks asks for
/// another rebuild. Only an iPad on iPadOS 26 or later has the bar; anywhere else nothing is
/// rebuilt, and the Menus button is the way in.
final class MacMenuHub {
    static let shared = MacMenuHub()

    /// The client of the window that is key, whose menus the bar shows.
    private(set) weak var focused: StreamClient?

    private init() {}

    /// A window reports whether it is key (`KeyWindowObserver`): the key one's client is focused,
    /// and a client whose window stops being key is not.
    func window(of client: StreamClient, isKey: Bool) {
        if isKey {
            guard focused !== client else { return }
            focused = client
            rebuild()
        } else if focused === client {
            focused = nil
            rebuild()
        }
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

/// A zero-size view beside a session's screen that tells `MacMenuHub` whether its window is key:
/// when it moves into a window, and at that window's key notifications (one per scene, next to its
/// StreamClient).
struct KeyWindowObserver: UIViewRepresentable {
    let client: StreamClient

    func makeUIView(context: Context) -> KeyWindowObserverView {
        let view = KeyWindowObserverView()
        view.client = client
        return view
    }

    func updateUIView(_ view: KeyWindowObserverView, context: Context) {
        view.client = client
    }
}

final class KeyWindowObserverView: UIView {
    weak var client: StreamClient? {
        didSet { if client !== oldValue { report() } }
    }
    private var observers: [NSObjectProtocol] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        isAccessibilityElement = false
        isHidden = true
    }

    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        if let window {
            for name in [UIWindow.didBecomeKeyNotification, UIWindow.didResignKeyNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    self?.report()
                })
            }
        }
        report()
    }

    private func report() {
        guard let client else { return }
        MacMenuHub.shared.window(of: client, isKey: window?.isKeyWindow == true)
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }
}
