import AppKit

/// The main menu of an app that never shows one. An accessory app (LSUIElement) has no menu bar,
/// but AppKit still routes key equivalents through the main menu, so without this ⌘C, ⌘A, ⌘F,
/// ⌘W and ⌘Q would do nothing in the Settings and Log windows.
enum MainMenu {
    @MainActor
    static func make() -> NSMenu {
        let main = NSMenu()

        let sill = submenu(in: main, title: "Sill")
        sill.addItem(withTitle: String(localized: "About Sill"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        sill.addItem(.separator())
        sill.addItem(withTitle: String(localized: "Settings…"), action: #selector(AppDelegate.showSettings(_:)), keyEquivalent: ",")
        sill.addItem(.separator())
        sill.addItem(withTitle: String(localized: "Quit Sill"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let edit = submenu(in: main, title: String(localized: "Edit"))
        edit.addItem(withTitle: String(localized: "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: String(localized: "Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.addItem(.separator())
        let findItem = edit.addItem(withTitle: String(localized: "Find"), action: nil, keyEquivalent: "")
        let find = NSMenu(title: String(localized: "Find"))
        // performFindPanelAction: with the NSFindPanelAction tags, which a text view with a find
        // bar (the Log window) answers.
        let actions: [(String, String, NSFindPanelAction)] = [(String(localized: "Find…"), "f", .showFindPanel), (String(localized: "Find Next"), "g", .next),
                                                              (String(localized: "Find Previous"), "G", .previous)]
        for (title, key, tag) in actions {
            let item = find.addItem(withTitle: title, action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: key)
            item.tag = Int(tag.rawValue)
        }
        findItem.submenu = find

        let window = submenu(in: main, title: String(localized: "Window"))
        window.addItem(withTitle: String(localized: "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: String(localized: "Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        return main
    }

    @MainActor
    private static func submenu(in main: NSMenu, title: String) -> NSMenu {
        let item = main.addItem(withTitle: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        item.submenu = menu
        return menu
    }
}
