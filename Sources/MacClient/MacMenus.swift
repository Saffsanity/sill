import AppKit
import StreamProtocol

/// The other Mac's menu bar for the app it streams (kinds 24, 25, 27; docs/menu-bar-plan.md), as
/// this Mac's menu bar while the Dock icons are off (MainMenu; with them on, the icons read the
/// menus through StreamWindows): the top level as the shared MacMenuState has it, each menu read
/// from the other Mac as it opens (a "Loading…" row until the answer), each item pressed there
/// through Accessibility. The Mac's shortcuts show as text only: a real key
/// equivalent here would take the key from the stream, which sends it to the other Mac anyway.
/// Main thread.
enum MacMenus {
    /// The other Mac's top-level menus as menu bar items (MainMenu), each read as it opens; a note
    /// (no menus, stale, not readable) as one disabled menu.
    static func topLevelItems(_ client: StreamClient) -> [NSMenuItem] {
        let state = client.menus
        var out: [NSMenuItem] = []
        if let version = state.version, !state.menus.isEmpty {
            for row in state.menus {
                guard let id = row.id else { continue }
                let item = NSMenuItem(title: row.title, action: nil, keyEquivalent: "")
                item.submenu = Loader.menu(title: row.title, client: client) { client, done in
                    client.fetchTopMenu(id: id, title: row.title, builtVersion: version, completion: done)
                }
                item.isEnabled = row.enabled && !state.stale
                out.append(item)
            }
        } else if let note = state.note {
            let item = NSMenuItem(title: "Menus", action: nil, keyEquivalent: "")
            let menu = NSMenu(title: "Menus")
            menu.addItem(disabled(note))
            item.submenu = menu
            out.append(item)
        }
        return out
    }

    static func disabled(_ text: String) -> NSMenuItem {
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// A submenu that asks the other Mac for its items each time it opens.
    final class Loader: NSObject, NSMenuDelegate {
        typealias Fetch = (StreamClient, @escaping (MacMenuState.Content) -> Void) -> Void
        private weak var client: StreamClient?
        private let fetch: Fetch
        /// Each open's answer goes only to that open: a late one is dropped.
        private var generation = 0

        private init(client: StreamClient, fetch: @escaping Fetch) {
            self.client = client
            self.fetch = fetch
        }

        static func menu(title: String, client: StreamClient, fetch: @escaping Fetch) -> NSMenu {
            let menu = NSMenu(title: title)
            menu.autoenablesItems = false
            let loader = Loader(client: client, fetch: fetch)
            menu.delegate = loader
            objc_setAssociatedObject(menu, &loaderKey, loader, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            menu.addItem(disabled("Loading…"))
            return menu
        }

        func menuWillOpen(_ menu: NSMenu) {
            generation += 1
            let mine = generation
            menu.removeAllItems()
            menu.addItem(MacMenus.disabled("Loading…"))
            guard let client else { return }
            fetch(client) { [weak self, weak menu, weak client] content in
                guard let self, let menu, let client, self.generation == mine else { return }
                self.fill(menu, content, client)
            }
        }

        private func fill(_ menu: NSMenu, _ content: MacMenuState.Content, _ client: StreamClient) {
            menu.removeAllItems()
            switch content {
            case .message(let text):
                menu.addItem(MacMenus.disabled(text))
            case .sections(let sections, let more):
                for (i, section) in sections.enumerated() {
                    if i > 0 { menu.addItem(.separator()) }
                    for row in section { menu.addItem(item(row, client)) }
                }
                if more > 0 { menu.addItem(MacMenus.disabled("\(more) more on the other Mac")) }
            }
        }

        private func item(_ row: MacMenuState.Row, _ client: StreamClient) -> NSMenuItem {
            switch row.kind {
            case .note:
                return MacMenus.disabled(row.title)
            case .submenu:
                let item = NSMenuItem(title: row.title, action: nil, keyEquivalent: "")
                item.isEnabled = row.enabled && row.id != nil
                if item.isEnabled {
                    item.submenu = Loader.menu(title: row.title, client: client) { client, done in client.fetchMenu(row, completion: done) }
                }
                return item
            case .item:
                let item = Pressable(row: row, client: client)
                item.isEnabled = row.enabled
                switch row.mark {
                case .off: item.state = .off
                case .on: item.state = .on
                case .mixed: item.state = .mixed
                }
                if let key = row.key, !key.isEmpty {
                    let title = NSMutableAttributedString(string: row.title + "    ")
                    title.append(NSAttributedString(string: key, attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
                    item.attributedTitle = title
                }
                return item
            }
        }
    }

    /// An item that presses its row on the other Mac.
    final class Pressable: NSMenuItem {
        private let row: MacMenuState.Row
        private weak var client: StreamClient?
        init(row: MacMenuState.Row, client: StreamClient) {
            self.row = row
            self.client = client
            super.init(title: row.title, action: #selector(press), keyEquivalent: "")
            target = self
        }
        required init(coder: NSCoder) { fatalError() }
        @objc private func press() { client?.pressMenuItem(row) }
    }
}

private var loaderKey: UInt8 = 0

#if DEBUG
extension MacMenus {
    /// DEBUG `-SillMenuTest 1`: once the top level arrives, the pull-down's first enabled menu is
    /// built and opened as a click would open it (its loader asks the other Mac), and 2 s later its
    /// rows are printed ("menus test: …"); the first enabled item is pressed when `-SillMenuTest
    /// press`. Against `Scripts/menufixture.swift` through a synthetic host only (SILL_TEST_MENU_PID).
    static func testIfAsked(_ client: StreamClient) {
        guard let mode = UserDefaults.standard.string(forKey: "SillMenuTest"), !tested,
              let version = client.menus.version,
              let row = client.menus.menus.first(where: { $0.enabled && $0.id != nil }), let id = row.id else { return }
        tested = true
        print("menus test: top level \(client.menus.menus.map(\.title)), opening \(row.title)")
        let menu = Loader.menu(title: row.title, client: client) { client, done in
            client.fetchTopMenu(id: id, title: row.title, builtVersion: version, completion: done)
        }
        menu.delegate?.menuWillOpen?(menu)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            print("menus test: \(row.title): " + menu.items.map { $0.isSeparatorItem ? "—" : ($0.attributedTitle?.string ?? $0.title) + ($0.isEnabled ? "" : " (disabled)") }.joined(separator: " | "))
            if mode == "press", let item = menu.items.first(where: { $0 is Pressable && $0.isEnabled }) {
                print("menus test: pressing \(item.title)")
                _ = item.target?.perform(item.action)
            }
            withExtendedLifetime(menu) {}
        }
    }
    private static var tested = false
}
#endif
