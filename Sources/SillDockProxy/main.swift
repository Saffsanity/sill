import AppKit
import CryptoKit

// A Dock icon for one of the other Mac's apps (Sill Viewer's DockProxies): Sill Viewer makes a copy of
// this app per remote app, named after it, and launches it while that app has a window open there.
// It has no window and no menus of its own: its icon is the remote app's, clicking it brings that
// app's windows forward in Sill Viewer, and its Dock menu lists them. It talks to Sill Viewer by
// distributed notifications and quits when told to, or when Sill Viewer goes. A notification carries
// nothing anyone else could read: Sill Viewer's state for this app is in a file only this user reads
// (`<slug>.state` beside the copies), and a request is signed with Sill Viewer's key from there
// (`token`) and carries a counter that must rise, so a watcher can neither forge nor replay one.
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
    /// A badge was heard already: only a change after it can bounce.
    private var heardBadge = false
    /// The bounce asked for while the app bounces on the other Mac, to cancel when it stops.
    private var attentionRequest: Int?
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
        center.addObserver(forName: Self.stateName, object: app, queue: .main) { [weak self] _ in
            guard let self, let data = try? Data(contentsOf: self.folder.appendingPathComponent("\(self.slug).state")),
                  let state = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
            if state["quit"] as? Bool == true { self.told = true; NSApp.terminate(nil); return }
            self.heard = true
            if let path = state["icon"] as? String { self.showIcon(path) }
            // The app's badge on the other Mac ("3"), as its own Dock icon shows it there.
            let badge = state["badge"] as? String ?? ""
            if NSApp.dockTile.badgeLabel != (badge.isEmpty ? nil : badge) {
                // A badge that rose (a new mail, a new message) bounces the icon once, as the app's own
                // would; the first state, and a badge that falls or goes, do not.
                if self.heardBadge, Self.rose(from: NSApp.dockTile.badgeLabel ?? "", to: badge) {
                    NSApp.requestUserAttention(.informationalRequest)
                }
                NSApp.dockTile.badgeLabel = badge.isEmpty ? nil : badge
            }
            self.heardBadge = true
            // The app bouncing its Dock icon on the other Mac: this one bounces until that stops (a
            // one-time bounce there arrives as about a second of bouncing here).
            let attention = state["attention"] as? Bool == true
            if attention, self.attentionRequest == nil {
                let id = NSApp.requestUserAttention(.criticalRequest)
                self.attentionRequest = id >= 0 ? id : nil   // -1: this icon is the active app, nothing to do
            } else if !attention, let id = self.attentionRequest {
                NSApp.cancelUserAttentionRequest(id)
                self.attentionRequest = nil
            }
            let ids = state["ids"] as? [String] ?? []
            let titles = state["titles"] as? [String] ?? []
            let states = state["states"] as? [String] ?? []
            let menuIDs = state["menuIDs"] as? [String] ?? []
            let menuTitles = state["menuTitles"] as? [String] ?? []
            let menuEnabled = state["menuEnabled"] as? [String] ?? []
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

    /// Whether a badge rose: a count that grew, or a badge where there was none ("•" counts).
    static func rose(from old: String, to new: String) -> Bool {
        guard !new.isEmpty else { return false }
        guard !old.isEmpty else { return true }
        if let o = Int(old), let n = Int(new) { return n > o }
        return false
    }

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
            // ✓ the app's front window, as macOS marks it (the Dock draws no other mark in an app's
            // menu: a minimized window's ◆ is its own).
            if w.state == "front" { item.state = .on }
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

    @objc private func pick(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String else { return }
        post(["ask": "window", "window": id])
        if let viewer { NSRunningApplication(processIdentifier: viewer)?.activate() }
    }

    private func post(_ info: [String: String]) {
        // Read each time: Sill Viewer writes a new one at each launch.
        guard let token = try? String(contentsOf: folder.appendingPathComponent("token"), encoding: .utf8) else { return }
        var info = info
        // Microseconds since 1970: rises across this icon's launches as well as within one.
        counter = max(counter + 1, Int64(Date().timeIntervalSince1970 * 1_000_000))
        info["n"] = String(counter)
        info["mac"] = Self.mac(app: app, info, key: token)
        DistributedNotificationCenter.default().postNotificationName(Self.actionName, object: app, userInfo: info,
                                                                     deliverImmediately: true)
    }

    private var counter: Int64 = 0

    /// HMAC-SHA256 of the app and every field but the MAC itself (Sill Viewer's DockRequest.mac).
    static func mac(app: String, _ info: [String: String], key: String) -> String {
        // Each part with its length first, so no value can be read as another field.
        let parts = [app] + info.filter { $0.key != "mac" }.sorted { $0.key < $1.key }.flatMap { [$0.key, $0.value] }
        let text = parts.map { "\($0.utf8.count):\($0)" }.joined()
        let code = HMAC<SHA256>.authenticationCode(for: Data(text.utf8), using: SymmetricKey(data: Data(key.utf8)))
        return code.map { String(format: "%02x", $0) }.joined()
    }

    /// Sill Viewer's folder of copies (each in a folder of its own), where the token and the state are.
    private var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sill Viewer/Dock", isDirectory: true)
    }
    /// DockProxies.slug: this app's state file's name.
    private var slug: String {
        let s = app.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "-" ? Character($0) : "-" }
        return String(String(s).prefix(100))
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
