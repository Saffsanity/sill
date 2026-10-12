import AppKit

// A Dock icon for one of the other Mac's apps (Sill Viewer's DockProxies): Sill Viewer makes a copy of
// this app per remote app, named after it, and launches it while that app has a window open there.
// It has no window and no menus of its own: its icon is the remote app's, clicking it brings that
// app's windows forward in Sill Viewer, and its Dock menu lists them. It talks to Sill Viewer by
// distributed notifications and quits when told to, or when Sill Viewer goes.
//   SillDockProxy --app <bundle ID> --viewer <pid> [--icon <png>]

final class Proxy: NSObject, NSApplicationDelegate {
    static let stateName = Notification.Name("me.saffer.sill.client.dock.state")
    static let actionName = Notification.Name("me.saffer.sill.client.dock.action")

    let app: String
    let viewer: pid_t
    let icon: String?
    private var windows: [(id: String, title: String)] = []
    private var exitWatch: DispatchSourceProcess?

    init(app: String, viewer: pid_t, icon: String?) {
        self.app = app
        self.viewer = viewer
        self.icon = icon
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let icon, let image = NSImage(contentsOfFile: icon) { NSApp.applicationIconImage = image }
        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: Self.stateName, object: app, queue: .main) { [weak self] note in
            guard let self else { return }
            if note.userInfo?["quit"] as? Bool == true { NSApp.terminate(nil); return }
            let ids = note.userInfo?["ids"] as? [String] ?? []
            let titles = note.userInfo?["titles"] as? [String] ?? []
            self.windows = zip(ids, titles).map { ($0, $1) }
        }
        // Sill Viewer gone: so is this.
        let watch = DispatchSource.makeProcessSource(identifier: viewer, eventMask: .exit, queue: .main)
        watch.setEventHandler { NSApp.terminate(nil) }
        watch.resume()
        exitWatch = watch
        if kill(viewer, 0) != 0 { NSApp.terminate(nil) }
        post(["ask": "state"])
    }

    /// Clicked in the Dock, or switched to: Sill Viewer brings this app's windows forward.
    func applicationDidBecomeActive(_ notification: Notification) {
        post(["ask": "focus"])
        NSRunningApplication(processIdentifier: viewer)?.activate()
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
            menu.addItem(item)
        }
        return menu
    }

    @objc private func pick(_ item: NSMenuItem) {
        guard let id = item.representedObject as? String else { return }
        post(["ask": "window", "window": id])
        NSRunningApplication(processIdentifier: viewer)?.activate()
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
guard let app, let viewer else { exit(2) }
let delegate = Proxy(app: app, viewer: viewer, icon: icon)
NSApplication.shared.delegate = delegate
NSApplication.shared.setActivationPolicy(.regular)
NSApplication.shared.run()
