import SwiftUI
import UIKit

/// The app delegate SwiftUI gives `SillApp` (`@UIApplicationDelegateAdaptor`): it implements nothing
/// but `buildMenu(with:)`, which SwiftUI's own delegate calls for each build of a menu system, to put
/// the Mac's menus in the iPad's menu bar (docs/menu-bar-plan.md §7.4). SwiftUI keeps its own handling
/// of scenes and of `sill://` links (ContentView's `onOpenURL`).
///
/// Nothing is inserted on an iPhone, before iPadOS 26 (there the main menu only feeds the ⌘ list of
/// key commands, and the Mac's menus have none), while the app has more than one window (MacMenuHub:
/// nothing says which window's session the bar's choices would reach), or when the window's session
/// has no menus.
final class SillAppDelegate: UIResponder, UIApplicationDelegate {
    /// An external display's scene before iOS 27 (a monitor or XR glasses on USB-C, with Stage Manager
    /// off on an iPad, or AirPlay): the stream goes there (ExternalDisplay). From iOS 27 that scene comes
    /// only through a scene accessory (ExternalDisplayAccessory). Every other scene is SwiftUI's, as before.
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Unnamed, SwiftUI's own (the session's `configuration` left the app with no window at all).
        guard session.role == .windowExternalDisplayNonInteractive else { return UISceneConfiguration(name: nil, sessionRole: session.role) }
        return ExternalDisplay.sceneConfiguration
    }

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == .main else { return }
        guard MacMenuHub.hasMenuBar, #available(iOS 26.0, *) else {
            #if DEBUG
            print("menubar: built: nothing inserted (not an iPad on iPadOS 26)")
            #endif
            return
        }
        MacMenuBar.build(builder)
    }
}

/// Where the Mac's menus go in the iPad's menu bar, and how (docs/menu-bar-plan.md §7.4, Q1).
///
/// Every insertion is one `insertElements` call with all the Mac's menus in their order, next to an
/// anchor looked up first (`menu(for:)`): UIMenuBuilder's headers do not say what an insertion next
/// to a missing identifier does, so none is ever made, and the root's end is the last resort. And
/// at most once per build: if the first menu's identifier is there already, nothing is inserted (a
/// second insertion would be a duplicate, which throws, or a conflict with the root, which drops
/// the whole insertion). The Mac's menus are never told apart or merged by title: the Mac's Window
/// and the iPad's stay two menus.
@available(iOS 26.0, *)
enum MacMenuBar {
    enum Layout: String {
        /// One menu per Mac menu, in the Mac's order, right after the iPad's View (the HIG's place
        /// for an app's own menus); Sill's own menus stay. The Mac's app menu, named after the app,
        /// marks where they begin.
        case perMenu
        /// Sill's File, Edit, Format and View go while the Mac's menus show (and with them Sill's
        /// ⌘W Close and its Edit commands, whose ⌘C, ⌘V, ⌘Z and ⌘A a text field over the stream,
        /// the pairing overlay's code field, would use with a hardware keyboard); the Mac's menus
        /// go before Window.
        case replace
        /// One menu named after the app holds the Mac's menus, after View.
        case one
    }

    /// Q1's default. DEBUG: `-SillMenuBarLayout perMenu|replace|one` for one run.
    static var layout: Layout {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "SillMenuBarLayout"), let l = Layout(rawValue: raw) { return l }
        #endif
        return .perMenu
    }

    /// One build of the main menu: the menus of the session in the app's one window, if it has any.
    static func build(_ builder: UIMenuBuilder) {
        #if DEBUG
        // The guards under test (S3): View gone before the insertion.
        if UserDefaults.standard.bool(forKey: "SillMenuNoView"), builder.menu(for: .view) != nil { builder.remove(menu: .view) }
        #endif
        let focus = MacMenuHub.shared.focus
        var line = "nothing inserted (\(focus.why))"
        if let client = focus.client {
            if client.menus.menus.isEmpty {
                line = "nothing inserted (the session has no menus)"
            } else {
                line = insert(MacMenuElements.topMenus(client, barIdentifiers: true), app: client.menus.app, into: builder)
                #if DEBUG
                // The guards under test (S3): a second insertion in the same build inserts nothing.
                if UserDefaults.standard.bool(forKey: "SillMenuBuildTwice") {
                    let again = insert(MacMenuElements.topMenus(client, barIdentifiers: true), app: client.menus.app, into: builder)
                    print("menubar: inserted again in the same build: \(again)")
                }
                #endif
            }
        }
        #if DEBUG
        print("menubar: built: \(line)")
        if UserDefaults.standard.bool(forKey: "SillMenuDump") { dump(builder) }
        #endif
    }

    /// Inserts the Mac's menus as `layout` says; what it did, for the console.
    static func insert(_ menus: [UIMenuElement], app: String?, into builder: UIMenuBuilder) -> String {
        guard let first = menus.first as? UIMenu else { return "nothing inserted (no menus)" }
        let layout = self.layout
        let inserted: [UIMenuElement]
        let once: UIMenu.Identifier
        switch layout {
        case .one:
            inserted = [UIMenu(title: app ?? "Mac", identifier: MacMenuElements.barWrapper, children: menus)]
            once = MacMenuElements.barWrapper
        case .perMenu, .replace:
            inserted = menus
            once = first.identifier
        }
        guard builder.menu(for: once) == nil else { return "nothing inserted (already in this build)" }
        if layout == .replace {
            for id in [UIMenu.Identifier.file, .edit, .format, .view] where builder.menu(for: id) != nil {
                builder.remove(menu: id)
            }
        }
        let place: String
        if layout != .replace, builder.menu(for: .view) != nil {
            builder.insertElements(inserted, afterMenu: .view)
            place = "after View"
        } else if builder.menu(for: .window) != nil {
            builder.insertElements(inserted, beforeMenu: .window)
            place = "before Window"
        } else if builder.menu(for: .root) != nil {
            builder.insertElements(inserted, atEndOfMenu: .root)
            place = "at the end of the bar"
        } else {
            return "nothing inserted (no root menu)"
        }
        return "\(menus.count) Mac menu\(menus.count == 1 ? "" : "s") \(place) (\(layout.rawValue))"
    }

    #if DEBUG
    /// `-SillMenuDump 1`: the root after each build, on the console, as the probe printed it (S3).
    static func dump(_ builder: UIMenuBuilder) {
        guard let root = builder.menu(for: .root) else { print("menubar: dump: no root menu"); return }
        func walk(_ e: UIMenuElement, _ depth: Int) {
            let pad = String(repeating: "  ", count: depth)
            if let m = e as? UIMenu {
                print("menubar: \(pad)MENU '\(m.title)' id=\(m.identifier.rawValue) n=\(m.children.count)")
                m.children.forEach { walk($0, depth + 1) }
            } else if let k = e as? UIKeyCommand {
                print("menubar: \(pad)KEY '\(k.title)' input=\(k.input ?? "nil") action=\(k.action.map(NSStringFromSelector) ?? "nil")")
            } else if let c = e as? UICommand {
                print("menubar: \(pad)COMMAND '\(c.title)' action=\(NSStringFromSelector(c.action))")
            } else if let a = e as? UIAction {
                print("menubar: \(pad)ACTION '\(a.title)'")
            } else if e is UIDeferredMenuElement {
                print("menubar: \(pad)DEFERRED")
            } else {
                print("menubar: \(pad)OTHER \(type(of: e)) '\(e.title)'")
            }
        }
        print("menubar: dump begins")
        walk(root, 0)
        print("menubar: dump ends")
    }
    #endif
}

/// The stream on an external display, with this device as its controller: while a monitor's scene is
/// up, the picture of the stream screen last shown (`show`) moves to it, the device's screen becomes a
/// trackpad (StreamScreen, PortraitStreamScreen), and the viewport is the monitor's size, so the Mac
/// sizes the window to it. The client's one display view lives in one window at a time; it comes back
/// to the device's screen as the monitor goes. Main thread.
final class ExternalDisplay: ObservableObject {
    static let shared = ExternalDisplay()
    /// The monitor's size in points while its scene is up; nil without one.
    @Published private(set) var size: CGSize?
    private(set) weak var client: StreamClient?
    /// Moves on each `show`, so a window whose picture the monitor gave up draws it again.
    @Published private var shown = 0
    private var window: UIWindow?

    /// The external display's scene, with its delegate: what both ways to that scene hand UIKit.
    static var sceneConfiguration: UISceneConfiguration {
        let config = UISceneConfiguration(name: "External display", sessionRole: .windowExternalDisplayNonInteractive)
        config.delegateClass = ExternalDisplaySceneDelegate.self
        return config
    }

    /// Whether `client`'s picture is on the monitor now.
    func shows(_ client: StreamClient) -> Bool { size != nil && self.client === client }

    /// The stream screen of `client` came forward: its picture is the one the monitor shows.
    func show(_ client: StreamClient) {
        guard self.client !== client else { return }
        self.client?.homeScene = nil
        self.client = client
        shown += 1
        attach()
        keepAwake()
    }

    /// The stream screen of `client` went away: the monitor shows nothing until the next one comes.
    func leave(_ client: StreamClient) {
        guard self.client === client else { return }
        client.homeScene = nil
        if client.displayView.superview === window?.rootViewController?.view { client.displayView.removeFromSuperview() }
        self.client = nil
        keepAwake()
    }

    fileprivate func connected(_ scene: UIWindowScene) {
        // Glasses and monitors alike take the picture edge to edge, with none of it scaled to a TV's overscan.
        scene.screen.overscanCompensation = .none
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIViewController()
        window.rootViewController?.view.backgroundColor = .black
        window.isHidden = false
        self.window = window
        size = scene.screen.bounds.size
        keepAwake()
        // After the stream screen has let go of the view (it hosts none while the monitor shows it).
        DispatchQueue.main.async { self.attach() }
    }

    #if DEBUG
    /// `-SillExternalDisplay WxH` (StreamScreen): a monitor's size with no scene, so nothing moves.
    func pretend(_ size: CGSize) {
        print("external: pretending a monitor of \(Int(size.width))×\(Int(size.height)) pt")
        self.size = size
    }
    #endif

    fileprivate func disconnected() {
        client?.homeScene = nil
        window = nil
        size = nil
        keepAwake()
    }

    /// With the picture on a monitor this screen may go untouched for a long while, and if it locks the
    /// stream stops (`DeviceIdleTimer`).
    var isHoldingAwake: Bool { size != nil && client != nil }
    private func keepAwake() { DeviceIdleTimer.shared.update() }

    private func attach() {
        guard size != nil, let client, let root = window?.rootViewController?.view else { return }
        let view = client.displayView
        if view.window?.windowScene !== window?.windowScene { client.homeScene = view.window?.windowScene ?? client.homeScene }
        view.removeFromSuperview()
        view.frame = root.bounds
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        root.addSubview(view)
    }
}

/// Asks for the external display's scene from iOS 27, which connects it only for a registered accessory,
/// and only while this view's controller is on screen: the stream screen hosts it, so a monitor shows the
/// device's own screen, as any app's, until a stream screen comes. Nothing before iOS 27.
struct ExternalDisplayAccessory: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        if #available(iOS 27.0, *) { return Registering() }
        return UIViewController()
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {}

    @available(iOS 27.0, *)
    private final class Registering: UIViewController {
        private var registration: UISceneAccessoryRegistration?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard registration == nil else { return }
            registration = registerSceneAccessory(.externalNonInteractive(sceneConfiguration: ExternalDisplay.sceneConfiguration))
        }

        override func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)
            if let registration { unregisterSceneAccessory(registration) }
            registration = nil
        }
    }
}

final class ExternalDisplaySceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        ExternalDisplay.shared.connected(scene)
    }

    func sceneDidDisconnect(_ scene: UIScene) { ExternalDisplay.shared.disconnected() }
}
