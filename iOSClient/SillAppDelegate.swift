import UIKit

/// The app delegate SwiftUI gives `SillApp` (`@UIApplicationDelegateAdaptor`): it implements nothing
/// but `buildMenu(with:)`, which SwiftUI's own delegate calls for each build of a menu system, to put
/// the Mac's menus in the iPad's menu bar (docs/menu-bar-plan.md §7.4). SwiftUI keeps its own handling
/// of scenes and of `sill://` links (ContentView's `onOpenURL`).
///
/// Nothing is inserted on an iPhone, before iPadOS 26 (there the main menu only feeds the ⌘ list of
/// key commands, and the Mac's menus have none), with no window key, or when the key window's
/// session has no menus.
final class SillAppDelegate: UIResponder, UIApplicationDelegate {
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

    /// One build of the main menu: the focused session's menus, if it has any.
    static func build(_ builder: UIMenuBuilder) {
        #if DEBUG
        // The guards under test (S3): View gone before the insertion.
        if UserDefaults.standard.bool(forKey: "SillMenuNoView"), builder.menu(for: .view) != nil { builder.remove(menu: .view) }
        #endif
        var line = "nothing inserted (no window is key)"
        if let client = MacMenuHub.shared.focused {
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
