// TEST ONLY: the menu gates' app (docs/menu-bar-plan.md §5). A controlled AppKit menu bar for a
// synthetic host started with SILL_TEST_MENU_PID, so the host's reads and presses can be checked
// without touching a real app.
//
// Build:  swiftc -O Scripts/menufixture.swift -o $T/menufixture -framework AppKit
// Run:    $T/menufixture serve LOG SECONDS     the app; exits by itself after SECONDS (at most 120)
//         $T/menufixture label PID             prints that fixture's label, read over Accessibility
//
// `serve` never activates itself: the prohibited policy, a background-only app that cannot be
// activated (no Dock icon, no menu bar of its own on screen; an accessory app run from a shell
// took the front at launch, 2026-09-27), whose menus Accessibility reads as any app's (the probe),
// and one borderless 240×40 window far off every display (at -20000, -20000), which ignores the
// mouse and can never be key; it holds one label, "none" at first. Every menu delegate and
// validation callback is logged with its time (seconds since 1970, then since launch), and every
// action as "ACTION ‹item›", then "PRESS '‹item›' in '‹its menu›'", setting the label: Set Label A →
// "A", Set Label B → "B", Deep Leaf → "Deep", Rebuilt Leaf → "Rebuilt", any other → its title.
// SIGUSR1 gives Probe › Rebuilt a new menu whose one item has the same title, SIGUSR2 one titled
// "Renamed Leaf", as an app that builds its menus again does (Electron): the old item's element is
// then invalid, and the host finds the item again by its path. (AppKit's menu item elements are
// positional: items replaced inside the same NSMenu leave an element answering for whatever item
// is at its place now, measured 2026-09-27; Dynamic N, retitled at each validation, shows the
// host's title check for that case.) SIGHUP inserts a leaf "Inserted" at the top of Probe, in the
// same menu, so every item of Probe moves down one place, its submenus included, and the top level
// stays as it was: an app changing a menu in place. SIGALRM gives Probe a new menu holding the same
// items, so every element read in Probe is invalid and the host walks from the bar.
import AppKit

let arguments = CommandLine.arguments
func usage() -> Never {
    FileHandle.standardError.write(Data("usage: menufixture serve LOG SECONDS | menufixture label PID\n".utf8))
    exit(2)
}
guard arguments.count >= 3 else { usage() }

// MARK: - label: another process reads the fixture's label over Accessibility

if arguments[1] == "label" {
    guard let pid = pid_t(arguments[2]) else { usage() }
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 1.0)
    func attribute(_ e: AXUIElement, _ name: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
    }
    func find(_ e: AXUIElement, depth: Int) -> String? {
        if (attribute(e, kAXRoleAttribute) as? String) == kAXStaticTextRole, let v = attribute(e, kAXValueAttribute) as? String { return v }
        guard depth < 6 else { return nil }
        for child in (attribute(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] {
            if let v = find(child, depth: depth + 1) { return v }
        }
        return nil
    }
    for window in (attribute(app, kAXWindowsAttribute) as? [AXUIElement]) ?? [] {
        if let v = find(window, depth: 0) { print(v); exit(0) }
    }
    print("(no label)")
    exit(1)
}
guard arguments[1] == "serve", arguments.count >= 4, let lifetime = Double(arguments[3]) else { usage() }

// MARK: - serve: the app

let logPath = arguments[2]
FileManager.default.createFile(atPath: logPath, contents: nil)
let logHandle = FileHandle(forWritingAtPath: logPath)!
let started = Date()
func log(_ s: String) {
    let now = Date()
    let line = String(format: "%.3f %8.3f ", now.timeIntervalSince1970, now.timeIntervalSince(started)) + s + "\n"
    logHandle.write(Data(line.utf8))
}

let app = NSApplication.shared
_ = app.setActivationPolicy(.prohibited)

// The label, in a window no one sees and that never takes a click or the keyboard.
let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 240, height: 40), styleMask: [.borderless],
                      backing: .buffered, defer: false)
window.ignoresMouseEvents = true
window.isReleasedWhenClosed = false
let label = NSTextField(labelWithString: "none")
label.frame = NSRect(x: 8, y: 10, width: 224, height: 20)
window.contentView?.addSubview(label)
window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
window.orderFrontRegardless()

var validations: [String: Int] = [:]
var dynamic = 0

final class Controller: NSObject, NSMenuItemValidation {
    @objc func act(_ sender: NSMenuItem) {
        log("ACTION \(sender.title)")
        log("PRESS '\(sender.title)' in '\(sender.menu?.title ?? "?")'")
        let names = ["Set Label A": "A", "Set Label B": "B", "Deep Leaf": "Deep", "Rebuilt Leaf": "Rebuilt"]
        label.stringValue = names[sender.title] ?? sender.title
    }
    @objc func slow(_ sender: NSMenuItem) {
        log("ACTION \(sender.title) (sleeping 2 s)")
        Thread.sleep(forTimeInterval: 2)
        label.stringValue = sender.title
        log("ACTION \(sender.title) done")
    }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        validations[item.title, default: 0] += 1
        log("validateMenuItem '\(item.title)'")
        switch item.tag {
        case 1: item.state = .on
        case 2: item.state = .mixed
        case 3: return false                                    // Unavailable, Close
        case 4: dynamic += 1; item.title = "Dynamic \(dynamic)" // retitled at each validation
        default: break
        }
        return true
    }
}

final class LoggingDelegate: NSObject, NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) { log("menuNeedsUpdate '\(menu.title)'") }
    func menuWillOpen(_ menu: NSMenu) { log("menuWillOpen '\(menu.title)'") }
    func menuDidClose(_ menu: NSMenu) { log("menuDidClose '\(menu.title)'") }
}

/// Open Recent: filled by its delegate at each read, as AppKit's own is.
final class RecentDelegate: NSObject, NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        log("menuNeedsUpdate '\(menu.title)' (filling)")
        menu.removeAllItems()
        for title in ["Recent 1", "Recent 2"] { menu.addItem(item(title)) }
        menu.addItem(.separator())
        menu.addItem(item("Clear Menu"))
    }
    func menuWillOpen(_ menu: NSMenu) { log("menuWillOpen '\(menu.title)'") }
    func menuDidClose(_ menu: NSMenu) { log("menuDidClose '\(menu.title)'") }
}

let controller = Controller()
let logging = LoggingDelegate()
let recent = RecentDelegate()

func item(_ title: String, key: String = "", mods: NSEvent.ModifierFlags = [.command], tag: Int = 0,
          action: Selector? = #selector(Controller.act(_:)), target: AnyObject? = controller) -> NSMenuItem {
    let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
    it.keyEquivalentModifierMask = mods
    it.tag = tag
    it.target = target
    return it
}
func key(_ scalar: Int) -> String { String(Character(UnicodeScalar(scalar)!)) }
func submenu(_ title: String, _ items: [NSMenuItem], delegate: NSMenuDelegate? = logging) -> NSMenuItem {
    let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    let menu = NSMenu(title: title)
    menu.delegate = delegate
    for i in items { menu.addItem(i) }
    it.submenu = menu
    return it
}

let main = NSMenu(title: "Main")
// The app menu: the bar shows it under the process's name, "menufixture".
main.addItem(submenu("menufixture", [
    item("About menufixture"),
    .separator(),
    item("Quit menufixture", key: "q", action: #selector(NSApplication.terminate(_:)), target: app),
]))
let openRecent = submenu("Open Recent", [item("Placeholder")], delegate: recent)
main.addItem(submenu("File", [
    item("New", key: "n"),
    item("Open…", key: "o"),
    .separator(),
    openRecent,
    .separator(),
    item("Close", key: "w", tag: 3),
]))
main.addItem(submenu("Edit", [                           // nil-targeted: disabled without a key window
    item("Undo", key: "z", action: Selector(("undo:")), target: nil),
    item("Redo", key: "Z", action: Selector(("redo:")), target: nil),
    .separator(),
    item("Cut", key: "x", action: #selector(NSText.cut(_:)), target: nil),
    item("Copy", key: "c", action: #selector(NSText.copy(_:)), target: nil),
    item("Paste", key: "v", action: #selector(NSText.paste(_:)), target: nil),
]))

let hidden = item("Hidden", key: "h", mods: [.command, .shift]); hidden.isHidden = true
let custom = NSMenuItem(title: "Custom View", action: nil, keyEquivalent: "")
let customView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
let customButton = NSButton(title: "Button in a view", target: controller, action: #selector(Controller.act(_:)))
customButton.frame = NSRect(x: 12, y: 0, width: 160, height: 24)
customView.addSubview(customButton)
custom.view = customView
let imageOnly = item("")
imageOnly.image = NSImage(size: NSSize(width: 16, height: 16))      // no accessibility description
let alternate = item("Alternate", key: "k", mods: [.command, .option]); alternate.isAlternate = true
let rebuilt = submenu("Rebuilt", [item("Rebuilt Leaf")])
let deep = submenu("Deep", [submenu("Level 2", [submenu("Level 3", [item("Deep Leaf")])])])
main.addItem(submenu("Probe", [
    item("Set Label A", key: "a", mods: [.command, .option]),
    item("Set Label B", key: "b", mods: [.control, .shift]),
    .separator(),
    item("Checked", tag: 1),
    item("Mixed", tag: 2),
    item("Unavailable", tag: 3),
    hidden,
    custom,
    imageOnly,
    .separator(),
    item("F5 Item", key: key(NSF5FunctionKey), mods: []),
    item("Delete Item", key: "\u{8}"),
    item("Up Item", key: key(NSUpArrowFunctionKey), mods: [.command, .control]),
    item("Escape Item", key: "\u{1b}", mods: []),
    item("Space Item", key: " ", mods: [.command, .option]),
    item("Primary", key: "k"),
    alternate,
    item("Dynamic 0", tag: 4),
    item("Slow Action", action: #selector(Controller.slow(_:))),
    rebuilt,
    deep,
    submenu("300 Items", (1...300).map { item("Item \($0)") }),
    submenu("600 Items", (1...600).map { item("Item \($0)") }),
]))
app.mainMenu = main

// SIGUSR1: Rebuilt's menu made again, a new NSMenu with an item of the same title; SIGUSR2: one
// titled "Renamed Leaf". A new menu, not new items in the old one: only then is the old element gone.
signal(SIGUSR1, SIG_IGN); signal(SIGUSR2, SIG_IGN)
var signalSources: [DispatchSourceSignal] = []
for (sig, title) in [(SIGUSR1, "Rebuilt Leaf"), (SIGUSR2, "Renamed Leaf")] {
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler {
        let menu = NSMenu(title: "Rebuilt")
        menu.delegate = logging
        menu.addItem(item(title))
        rebuilt.submenu = menu
        log("REBUILT Rebuilt's menu as a new one holding '\(title)'")
    }
    source.resume()
    signalSources.append(source)
}
// SIGHUP: "Inserted" at the top of Probe, in the same menu. SIGALRM: Probe's items moved into a new
// menu (the old one emptied).
let probeItem = main.item(withTitle: "Probe")!
signal(SIGHUP, SIG_IGN); signal(SIGALRM, SIG_IGN)
let insertSource = DispatchSource.makeSignalSource(signal: SIGHUP, queue: .main)
insertSource.setEventHandler {
    probeItem.submenu?.insertItem(item("Inserted"), at: 0)
    log("INSERTED 'Inserted' at the top of Probe")
}
insertSource.resume()
signalSources.append(insertSource)
let renewSource = DispatchSource.makeSignalSource(signal: SIGALRM, queue: .main)
renewSource.setEventHandler {
    guard let old = probeItem.submenu else { return }
    let items = old.items
    old.removeAllItems()
    let menu = NSMenu(title: "Probe")
    menu.delegate = logging
    for i in items { menu.addItem(i) }
    probeItem.submenu = menu
    log("RENEWED Probe as a new menu holding its \(items.count) items")
}
renewSource.resume()
signalSources.append(renewSource)

log("started pid \(getpid()), window at \(window.frame)")
print("menufixture pid \(getpid())")
fflush(stdout)
Timer.scheduledTimer(withTimeInterval: min(max(lifetime, 1), 120), repeats: false) { _ in
    log("exiting; validations \(validations.values.reduce(0, +))")
    exit(0)
}
app.run()
