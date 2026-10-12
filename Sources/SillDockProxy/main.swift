import AppKit

// A Dock icon for one of the other Mac's apps (Sill Viewer's DockProxies): Sill Viewer makes a copy of
// this app per remote app, named after it, and launches it while that app has a window open there.
// It has no window and no menus of its own: its icon is the remote app's, clicking it brings that
// app's windows forward in Sill Viewer, and its Dock menu lists them. It talks to Sill Viewer by
// distributed notifications and quits when told to, or when Sill Viewer goes.
//   SillDockProxy --app <bundle ID> --viewer <pid> [--icon <png>]
// Kept in the Dock and clicked while Sill Viewer has none of its app's windows, it starts with no
// arguments: its app is in its Info.plist (SillRemoteApp), it opens Sill Viewer if it is not running
// and asks it for that app, whose windows on the other Mac then open there (or the app is launched
// there); it quits if nothing comes of it within two minutes.

final class Proxy: NSObject, NSApplicationDelegate {
    static let stateName = Notification.Name("me.saffer.sill.client.dock.state")
    static let actionName = Notification.Name("me.saffer.sill.client.dock.action")

    let app: String
    var viewer: pid_t?
    let icon: String?
    private var heard = false
    /// Sill Viewer told this to quit (its app has no window open there): nothing to ask on the way out.
    private var told = false
    private var windows: [(id: String, title: String, state: String)] = []
    /// The app's own Dock menu on the other Mac (New Finder Window…): pressed there.
    private var remote: [(id: String, title: String, enabled: Bool)] = []
    private var exitWatch: DispatchSourceProcess?
    private var iconDate: Date?

    init(app: String, viewer: pid_t?, icon: String?) {
        self.app = app
        self.viewer = viewer
        self.icon = icon
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let icon { showIcon(icon) }
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: Self.stateName, object: app, queue: .main) { [weak self] note in
            guard let self else { return }
            if note.userInfo?["quit"] as? Bool == true { self.told = true; NSApp.terminate(nil); return }
            self.heard = true
            if let path = note.userInfo?["icon"] as? String { self.showIcon(path) }
            let ids = note.userInfo?["ids"] as? [String] ?? []
            let titles = note.userInfo?["titles"] as? [String] ?? []
            let states = note.userInfo?["states"] as? [String] ?? []
            let menuIDs = note.userInfo?["menuIDs"] as? [String] ?? []
            let menuTitles = note.userInfo?["menuTitles"] as? [String] ?? []
            let menuEnabled = note.userInfo?["menuEnabled"] as? [String] ?? []
            self.remote = menuIDs.indices.compactMap { i in
                i < menuTitles.count ? (menuIDs[i], menuTitles[i], i < menuEnabled.count ? menuEnabled[i] == "1" : true) : nil
            }
            self.windows = ids.indices.compactMap { i in
                i < titles.count ? (ids[i], titles[i], i < states.count ? states[i] : "") : nil
            }
        }
        if let viewer {
            watch(viewer)
            post(["ask": "state"])
            return
        }
        // Started from the Dock: Sill Viewer, opened if need be, is asked for this app.
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: Self.viewerID).first {
            watch(running.processIdentifier)
            post(["ask": "launch"])
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.viewerID) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] running, _ in
                DispatchQueue.main.async {
                    guard let self, let running else { NSApp.terminate(nil); return }
                    self.watch(running.processIdentifier)
                    // Its observer is up a moment after it launches: asked again until it answers.
                    for delay in [1.0, 3.0, 6.0, 10.0] {
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { if !self.heard { self.post(["ask": "launch"]) } }
                    }
                }
            }
        } else {
            NSApp.terminate(nil)
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [weak self] in if self?.heard == false { NSApp.terminate(nil) } }
    }

    static let viewerID = "me.saffer.sill.client"

    /// Sill Viewer gone: so is this.
    private func watch(_ pid: pid_t) {
        viewer = pid
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        exitWatch = source
        if kill(pid, 0) != 0 { NSApp.terminate(nil) }
    }

    /// The icon at `path` (the remote app's, badged as the other Mac's), shown again when it changed.
    private func showIcon(_ path: String) {
        let date = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date
        guard date != iconDate, let image = NSImage(contentsOfFile: path) else { return }
        iconDate = date
        NSApp.applicationIconImage = image
    }

    /// Quit from its Dock menu (or ⌘Q while it is in front): the app's windows close in Sill Viewer,
    /// as quitting an app closes its windows. The app on the other Mac goes on running.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if !told, viewer != nil { post(["ask": "close"]) }
        return .terminateNow
    }

    /// Clicked in the Dock, or switched to: Sill Viewer brings this app's windows forward.
    func applicationDidBecomeActive(_ notification: Notification) {
        post(["ask": heard ? "focus" : "launch"])
        if let viewer { NSRunningApplication(processIdentifier: viewer)?.activate() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        post(["ask": "focus"])
        return false
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        for w in windows {
            let item = NSMenuItem(title: w.title, action: #selector(pick(_:)), keyEquivalent: "")
            item.representedObject = w.id
            item.target = self
            // As macOS marks an app's own windows here: ✓ the front one, ◆ one in the Dock.
            if w.state == "front" { item.state = .on }
            if w.state == "minimized" {
                item.state = .mixed
                item.mixedStateImage = Self.diamond
            }
            menu.addItem(item)
        }
        if !remote.isEmpty {
            if !windows.isEmpty { menu.addItem(.separator()) }
            for r in remote {
                if r.title.isEmpty { menu.addItem(.separator()); continue }
                let item = NSMenuItem(title: r.title, action: r.enabled ? #selector(pickRemote(_:)) : nil, keyEquivalent: "")
                item.representedObject = r.id
                item.target = self
                item.isEnabled = r.enabled
                menu.addItem(item)
            }
        }
        post(["ask": "menu"])   // read again on the other Mac for the next opening (Sill Viewer paces it)
        return menu
    }

    @objc private func pickRemote(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String else { return }
        post(["ask": "dockItem", "item": id, "title": item.title])
    }

    private static let diamond: NSImage? = {
        let image = NSImage(systemSymbolName: "diamond.fill", accessibilityDescription: "Minimized")?
            .withSymbolConfiguration(.init(pointSize: 7, weight: .regular))
        image?.isTemplate = true
        return image
    }()

    @objc private func pick(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String else { return }
        post(["ask": "window", "window": id])
        if let viewer { NSRunningApplication(processIdentifier: viewer)?.activate() }
    }

    private func post(_ info: [String: String]) {
        DistributedNotificationCenter.default().postNotificationName(Self.actionName, object: app, userInfo: info,
                                                                     deliverImmediately: true)
    }
}

var app: String?
var viewer: pid_t?
var icon: String?
var args = CommandLine.arguments.dropFirst().makeIterator()
while let a = args.next() {
    switch a {
    case "--app": app = args.next()
    case "--viewer": viewer = args.next().flatMap { pid_t($0) }
    case "--icon": icon = args.next()
    default: break
    }
}
// Kept in the Dock and clicked: no arguments, the app from the Info.plist, the icon beside the copy.
if app == nil, let remote = Bundle.main.object(forInfoDictionaryKey: "SillRemoteApp") as? String {
    app = remote
    let png = Bundle.main.bundleURL.deletingPathExtension().appendingPathExtension("png").path
    if icon == nil, FileManager.default.fileExists(atPath: png) { icon = png }
}
guard let app else { exit(2) }
let delegate = Proxy(app: app, viewer: viewer, icon: icon)
NSApplication.shared.delegate = delegate
NSApplication.shared.setActivationPolicy(.regular)
NSApplication.shared.run()
