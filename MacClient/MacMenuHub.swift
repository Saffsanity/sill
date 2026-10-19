import AppKit
import StreamProtocol

/// The streamed app's menus in this Mac's menu bar (docs/menu-bar-plan.md, the iPad's bar on a Mac):
/// one menu named after the app on the other Mac ("Safari"), holding its menus (File, Edit, …), after
/// the viewer's own Stream menu. One menu rather than the app's menus side by side, so the viewer's
/// own File, Edit and View never sit beside the other Mac's of the same name.
///
/// It shows the session of the key window (each window has its own client). Every menu is fetched
/// from the other Mac as it opens (a "Loading…" row meanwhile, filled in while it is open), and a
/// chosen item is pressed there. The other Mac's shortcuts show as text at the right edge and are
/// never this menu's key equivalents: typed in the stream they reach that Mac as keys (and never
/// clash with the viewer's own ⌘ shortcuts). Main thread.
final class MacMenuHub: NSObject {
    static let shared = MacMenuHub()

    /// The stream views on screen, each with its window's client.
    private let views = NSHashTable<StreamInputView>.weakObjects()
    /// The menu bar's item, kept between rebuilds; nil while no session has menus.
    private var barItem: NSMenuItem?
    /// The session and the top level the bar's item was built from.
    private weak var shownClient: StreamClient?
    private var shownVersion: Int?
    private var observers: [NSObjectProtocol] = []

    private override init() {
        super.init()
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.willCloseNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.rebuild() })
        }
        // SwiftUI replaces the main menu when its commands change: put the item back in the new one.
        observers.append(center.addObserver(forName: NSApplication.didUpdateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.keepInMainMenu()
        })
    }

    /// A stream view joined or left a window.
    func register(_ view: StreamInputView) {
        views.add(view)
        rebuild()
    }

    func unregister(_ view: StreamInputView) {
        views.remove(view)
        rebuild()
    }

    /// A client's top level changed (StreamClient.receiveMenus, resetMenus) or one of its menus was
    /// asked by a title the top level no longer has.
    func menusChanged(_ client: StreamClient) {
        if client === focused || client === shownClient { rebuild(force: true) }
    }

    /// The client of the key window's stream; while the viewer is in the background, the one whose
    /// window was key last (so its menus are there as the viewer comes forward), or the only one.
    private var focused: StreamClient? {
        let views = views.allObjects.filter { $0.window?.isVisible == true }
        if let key = views.first(where: { $0.window?.isKeyWindow == true }) {
            lastKey = key.window
            return key.client
        }
        return (views.first { $0.window === lastKey } ?? (views.count == 1 ? views.first : nil))?.client
    }
    private weak var lastKey: NSWindow?

    private func rebuild(force: Bool = false) {
        let client = focused
        let state = client?.menus
        guard let client, let state, let version = state.version, client.connected,
              !state.menus.isEmpty || state.note != nil else {
            removeItem()
            return
        }
        if !force, client === shownClient, version == shownVersion, barItem != nil { return }
        shownClient = client
        shownVersion = version

        let item = barItem ?? NSMenuItem()
        let title = state.app ?? (client.macName.isEmpty ? "Mac" : client.macName)
        item.title = title
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false
        if let note = state.note { menu.addItem(Self.note(note)) }
        for row in state.menus {
            guard let id = row.id else { continue }
            let entry = NSMenuItem(title: row.title, action: nil, keyEquivalent: "")
            entry.isEnabled = row.enabled && !state.stale
            if entry.isEnabled {
                entry.submenu = MenuLoader.menu(for: row, topLevelVersion: version, id: id, client: client)
            }
            menu.addItem(entry)
        }
        item.submenu = menu
        barItem = item
        keepInMainMenu()
    }

    private func removeItem() {
        barItem?.menu?.removeItem(barItem!)
        barItem = nil
        shownClient = nil
        shownVersion = nil
    }

    /// The item sits after the viewer's Stream menu (before Window), in whichever main menu is current.
    private func keepInMainMenu() {
        guard let item = barItem, let main = NSApp.mainMenu, item.menu !== main else { return }
        item.menu?.removeItem(item)
        let windowIndex = main.items.firstIndex { $0.submenu === NSApp.windowsMenu || $0.title == "Window" }
        main.insertItem(item, at: windowIndex ?? max(0, main.items.count - 1))
    }

    /// Words in a menu: disabled, so they can never be chosen.
    static func note(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}

/// One menu of the other Mac's, filled in from that Mac each time it opens (uncached, like the iPad's
/// deferred elements): the top level's menus ask by the title they were built with, submenus in the
/// version their row came in.
private final class MenuLoader: NSObject, NSMenuDelegate {
    private let row: MacMenuState.Row
    private let topLevelVersion: Int?
    private weak var client: StreamClient?
    /// The open that the answer belongs to: a menu closed and opened again ignores an older answer.
    private var generation = 0

    private init(row: MacMenuState.Row, topLevelVersion: Int?, client: StreamClient) {
        self.row = row
        self.topLevelVersion = topLevelVersion
        self.client = client
    }

    /// A submenu that loads itself; the loader lives as long as the menu (its delegate is weak).
    static func menu(for row: MacMenuState.Row, topLevelVersion: Int?, id: String, client: StreamClient) -> NSMenu {
        let menu = NSMenu(title: row.title)
        menu.autoenablesItems = false
        let loader = MenuLoader(row: row, topLevelVersion: topLevelVersion, client: client)
        menu.delegate = loader
        objc_setAssociatedObject(menu, &loaderKey, loader, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        menu.addItem(MacMenuHub.note("Loading…"))
        return menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        generation += 1
        let asked = generation
        menu.removeAllItems()
        menu.addItem(MacMenuHub.note("Loading…"))
        guard let client else {
            fill(menu, with: .message(MacMenuState.notConnected))
            return
        }
        let done: (MacMenuState.Content) -> Void = { [weak self, weak menu, weak client] content in
            guard let self, let menu, let client, asked == self.generation else { return }
            self.fill(menu, with: content, client: client)
        }
        if let version = topLevelVersion, let id = row.id {
            client.fetchTopMenu(id: id, title: row.title, builtVersion: version, completion: done)
        } else {
            client.fetchMenu(row, completion: done)
        }
    }

    private func fill(_ menu: NSMenu, with content: MacMenuState.Content, client: StreamClient? = nil) {
        menu.removeAllItems()
        switch content {
        case .message(let text):
            menu.addItem(MacMenuHub.note(text))
        case .sections(let sections, _):
            for (i, section) in sections.enumerated() {
                if i > 0 { menu.addItem(.separator()) }
                for row in section { menu.addItem(item(for: row, client: client)) }
            }
            if menu.items.isEmpty { menu.addItem(MacMenuHub.note("No items")) }
        }
    }

    private func item(for row: MacMenuState.Row, client: StreamClient?) -> NSMenuItem {
        switch row.kind {
        case .note:
            return MacMenuHub.note(row.title)
        case .submenu:
            let item = NSMenuItem(title: row.title, action: nil, keyEquivalent: "")
            item.isEnabled = row.enabled && row.id != nil
            if item.isEnabled, let client, let id = row.id {
                item.submenu = MenuLoader.menu(for: row, topLevelVersion: nil, id: id, client: client)
            }
            return item
        case .item:
            let item = NSMenuItem(title: row.title, action: #selector(MenuChoice.choose(_:)), keyEquivalent: "")
            let choice = MenuChoice(row: row, client: client)
            item.target = choice
            item.representedObject = choice     // the item keeps its target alive
            item.isEnabled = row.enabled
            switch row.mark {
            case .off: item.state = .off
            case .on: item.state = .on
            case .mixed: item.state = .mixed
            }
            if let key = row.key, !key.isEmpty { item.attributedTitle = Self.title(row.title, shortcut: key) }
            return item
        }
    }

    /// "Save" with "⇧⌘S" at the menu's right edge, in the secondary colour: the other Mac's shortcut,
    /// shown, never a key equivalent here.
    private static func title(_ title: String, shortcut: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .right, location: 260)]
        let font = NSFont.menuFont(ofSize: 0)
        let text = NSMutableAttributedString(string: title, attributes: [.font: font, .paragraphStyle: paragraph])
        text.append(NSAttributedString(string: "\t" + shortcut,
                                       attributes: [.font: font, .paragraphStyle: paragraph, .foregroundColor: NSColor.secondaryLabelColor]))
        return text
    }
}

private var loaderKey: UInt8 = 0

/// A chosen item: pressed on the other Mac, in the version its row came in.
private final class MenuChoice: NSObject {
    let row: MacMenuState.Row
    weak var client: StreamClient?

    init(row: MacMenuState.Row, client: StreamClient?) {
        self.row = row
        self.client = client
    }

    @objc func choose(_ sender: Any?) { client?.pressMenuItem(row) }
}
