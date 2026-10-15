import AppKit
import StreamProtocol

/// The menu bar: this app's own menu first (macOS requires it), then Edit, so the connect window's
/// fields can paste. With the remote apps' Dock icons off (DockProxies.enabled), this app is a regular
/// one and, while one of the other Mac's windows is key, that app's menus as the other Mac has them
/// follow instead, read as each opens (MacMenus); with them on, those menus are the Dock icons' own.
/// Sill's controls are the status item's. Rebuilt when the key window changes and when the other
/// Mac's top level changes (MacMenuHub). Main thread.
final class MainMenu: NSObject {
    private let client: StreamClient
    /// The top level the bar was last built from, so an unchanged one is not rebuilt (a rebuild
    /// closes an open menu).
    private var built: (version: Int?, titles: [String], remote: Bool)?

    init(client: StreamClient) {
        self.client = client
        super.init()
    }

    func install() {
        MacMenuHub.shared.onChange = { [weak self] _ in self?.rebuild() }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification, NSApplication.didBecomeActiveNotification] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.rebuild() }
        }
        rebuild()
    }

    private var remoteKey: Bool { !DockProxies.enabled && NSApp.keyWindow is StreamWindow && client.connected }

    func rebuild() {
        let remote = remoteKey
        let state = client.menus
        let shape = (version: state.version, titles: state.menus.map(\.title), remote: remote)
        if let built, built.version == shape.version, built.titles == shape.titles, built.remote == shape.remote,
           NSApp.mainMenu != nil { return }
        built = shape
        let bar = NSMenu(title: "Main Menu")
        bar.addItem(appMenu())
        if remote {
            for item in MacMenus.topLevelItems(client) { bar.addItem(item) }
        } else {
            bar.addItem(editMenu())
        }
        NSApp.mainMenu = bar
    }

    private func appMenu() -> NSMenuItem {
        let name = "Sill Viewer"
        let menu = NSMenu(title: name)
        menu.addItem(withTitle: "About \(name)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Hide \(name)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = menu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        // Here, not in a View menu: the menus after this one are the other Mac's app's. Its ⌃⌘F works
        // once ⌃⌥⌘⎋ has given the keyboard back to this Mac.
        let full = menu.addItem(withTitle: "Enter/Exit Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        full.keyEquivalentModifierMask = [.control, .command]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit \(name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let item = NSMenuItem(title: name, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private func editMenu() -> NSMenuItem {
        let menu = NSMenu(title: "Edit")
        menu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let item = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
