import AppKit
import ApplicationServices
import StreamProtocol

/// An app's own Dock menu, for a Mac client's Dock icon of it (kind 39, DockMenu). Accessibility has an
/// app's Dock menu only while the Dock shows it: it is shown (AXShowMenu on the app's Dock item), read
/// or one item pressed, and closed again, so it flashes in this Mac's Dock for about half a second.
/// Read: the items the app adds, without its windows at the top (the client lists its own) and without
/// the Dock's own section at the end (Options, Show All Windows, Hide, Quit: the client's Dock adds
/// those). Every Accessibility call runs on its own queue; nothing else of the Dock is touched.
final class DockMenus: @unchecked Sendable {
    private let queue = DispatchQueue(label: "sill.dockmenu", qos: .userInitiated)

    /// The Dock's own items, left out (and never pressed from a device). By their English titles: on a
    /// Mac in another language they are read and offered like the app's.
    private static let docksOwn: Set<String> = ["Options", "Show All Windows", "Hide", "Hide Others", "Show", "Quit",
                                                "Force Quit", "Show Recents", "Keep in Dock", "Remove from Dock",
                                                "Open at Login", "Show in Finder", "Assign To"]

    /// `app`'s menu; `done` on the main queue (empty: no menu, or the app is not running here).
    func read(_ app: String, windowTitles: Set<String>, done: @escaping ([DockMenu.Item]) -> Void) {
        queue.async {
            let items = Self.withMenu(app) { menu in Self.items(of: menu, windowTitles: windowTitles) } ?? []
            DispatchQueue.main.async { done(items) }
        }
    }

    /// The item at `id` pressed, if it is one `read` offers (the app's, not a window or the Dock's own)
    /// and its title is still `title`.
    func press(_ app: String, id: Int, title: String, windowTitles: Set<String> = [], done: @escaping (Bool) -> Void) {
        queue.async {
            let pressed = Self.withMenu(app, keepOpen: true) { menu -> Bool in
                let children = Self.children(menu)
                let offered = Self.items(of: menu, windowTitles: windowTitles)
                guard children.indices.contains(id), offered.contains(where: { $0.id == id && $0.title == title && $0.separator != true }),
                      Self.title(children[id]) == title, Self.enabled(children[id]) else { return false }
                return AXUIElementPerformAction(children[id], kAXPressAction as CFString) == .success
            } ?? false
            DispatchQueue.main.async { done(pressed) }
        }
    }

    /// Every app's Dock badge (Accessibility's AXStatusLabel on its Dock item), by bundle ID, read on
    /// this queue without showing anything; `done` on the main queue.
    func badges(done: @escaping ([String: String]) -> Void) {
        queue.async {
            var found: [String: String] = [:]
            if let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first {
                let root = AXUIElementCreateApplication(dock.processIdentifier)
                AXUIElementSetMessagingTimeout(root, 1)
                for list in Self.children(root) {
                    for item in Self.children(list) where Self.attribute(item, kAXSubroleAttribute) as? String == "AXApplicationDockItem" {
                        guard let label = Self.attribute(item, "AXStatusLabel") as? String, !label.isEmpty,
                              let url = Self.attribute(item, kAXURLAttribute) as? URL,
                              let id = Bundle(url: url)?.bundleIdentifier else { continue }
                        found[id] = String(label.prefix(8))
                    }
                }
            }
            DispatchQueue.main.async { done(found) }
        }
    }

    /// The app's Dock icon clicked: a running app with no window opens one (the Dock's reopen).
    func reopen(_ app: String) {
        queue.async {
            if let item = Self.dockItem(for: app) { AXUIElementPerformAction(item, kAXPressAction as CFString) }
        }
    }

    // MARK: Accessibility

    /// The app's Dock menu shown, `body` run on it, then closed (unless an item was pressed: that closes it).
    private static func withMenu<T>(_ app: String, keepOpen: Bool = false, _ body: (AXUIElement) -> T) -> T? {
        guard let item = dockItem(for: app) else { return nil }
        guard AXUIElementPerformAction(item, "AXShowMenu" as CFString) == .success else { return nil }
        var menu: AXUIElement?
        for _ in 0..<30 {   // shown within a few hundred ms
            if let m = element(attribute(item, "AXShownMenuUIElement")), !children(m).isEmpty { menu = m; break }
            usleep(30_000)
        }
        guard let menu else { close(item); return nil }
        let result = body(menu)
        if !keepOpen || (result as? Bool) != true { close(item) }
        return result
    }

    private static func close(_ item: AXUIElement) {
        if let shown = element(attribute(item, "AXShownMenuUIElement")) { AXUIElementPerformAction(shown, kAXCancelAction as CFString) }
    }

    /// The Dock's item for the running app `app` (by its bundle's URL, else its name).
    private static func dockItem(for app: String) -> AXUIElement? {
        guard let running = NSRunningApplication.runningApplications(withBundleIdentifier: app).first,
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        let root = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(root, 1)
        let bundle = running.bundleURL?.standardizedFileURL.path
        var byName: AXUIElement?
        for list in children(root) {
            // An app's own item only: a folder or stack of the same name has a menu of the Dock's.
            for item in children(list) where attribute(item, kAXSubroleAttribute) as? String == "AXApplicationDockItem" {
                if let url = attribute(item, kAXURLAttribute) as? URL, url.standardizedFileURL.path == bundle { return item }
                if byName == nil, title(item) == running.localizedName { byName = item }
            }
        }
        return byName
    }

    private static func items(of menu: AXUIElement, windowTitles: Set<String>) -> [DockMenu.Item] {
        var all = children(menu).enumerated().map { i, e -> DockMenu.Item in
            let t = title(e)
            return DockMenu.Item(id: i, title: t, enabled: enabled(e), separator: t.isEmpty ? true : nil)
        }
        // The app's windows at the top (the client lists its own), and the Dock's own section at the end.
        while let first = all.first, first.separator != true, windowTitles.contains(first.title) { all.removeFirst() }
        while let last = all.last, last.separator == true || docksOwn.contains(last.title) { all.removeLast() }
        while all.first?.separator == true { all.removeFirst() }
        return all
    }

    private static func attribute(_ e: AXUIElement, _ name: String) -> AnyObject? {
        var v: AnyObject?
        return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
    }
    /// `value` if it is an Accessibility element.
    private static func element(_ value: AnyObject?) -> AXUIElement? {
        guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private static func children(_ e: AXUIElement) -> [AXUIElement] { (attribute(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
    private static func title(_ e: AXUIElement) -> String { attribute(e, kAXTitleAttribute) as? String ?? "" }
    private static func enabled(_ e: AXUIElement) -> Bool { attribute(e, kAXEnabledAttribute) as? Bool ?? true }
}
