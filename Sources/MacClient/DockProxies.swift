import AppKit

/// A Dock icon per remote app with a window open here, grouped as macOS groups an app's windows
/// (Sources/SillDockProxy): Sill Viewer carries one helper app; for each remote app it makes a copy,
/// named after that app with a bundle ID of its own, signs the copy ad hoc on this Mac (its
/// Info.plist changed, the original signature no longer holds; a copy made here carries no
/// quarantine), and launches it in the background. The helper shows the remote app's icon, lists
/// its windows in its Dock menu, and asks Sill Viewer to bring them forward when clicked; it quits
/// once that app has no window open here, or when Sill Viewer goes. Copies live in
/// ~/Library/Application Support/Sill Viewer/Dock and are made again only when the helper or the
/// name changes. Main thread.
final class DockProxies {
    struct AppWindows { let name: String; let icon: NSImage?; let windows: [Window] }
    /// A window in the Dock menu: the app's front one gets a ✓, a minimized one a ◆, as macOS marks its own.
    struct Window {
        enum State: String { case front, minimized, other }
        let id: UInt32
        let title: String
        let state: State
    }

    /// Bring an app's windows forward (nil window), or one window.
    var onFocus: ((_ app: String, _ window: UInt32?) -> Void)?
    /// A Dock icon kept in the Dock was clicked while its app had no window open here.
    var onLaunch: ((_ app: String) -> Void)?
    private var running: [String: NSRunningApplication] = [:]
    private var making: Set<String> = []
    private var last: [String: AppWindows] = [:]
    /// The apps whose badged icon is written: an icon can arrive from the other Mac after its Dock
    /// icon started, and is then written and shown.
    private var iconWritten: Set<String> = []
    private let work = DispatchQueue(label: "sill.dock", qos: .utility)

    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "SillClient.dockIcons") == nil || UserDefaults.standard.bool(forKey: "SillClient.dockIcons") }
        set { UserDefaults.standard.set(newValue, forKey: "SillClient.dockIcons") }
    }

    init() {
        DistributedNotificationCenter.default().addObserver(forName: Self.actionName, object: nil, queue: .main) { [weak self] note in
            guard let self, let app = note.object as? String else { return }
            if note.userInfo?["ask"] as? String == "launch" { self.onLaunch?(app); return }
            guard self.last[app] != nil else { return }
            switch note.userInfo?["ask"] as? String {
            case "focus": self.onFocus?(app, nil)
            case "window": self.onFocus?(app, (note.userInfo?["window"] as? String).flatMap { UInt32($0) })
            case "state": self.post(app)
            default: break
            }
        }
    }

    private static let stateName = Notification.Name("me.saffer.sill.client.dock.state")
    private static let actionName = Notification.Name("me.saffer.sill.client.dock.action")

    /// The remote apps with a window open here now, by bundle ID.
    func sync(_ apps: [String: AppWindows]) {
        let wanted = Self.enabled ? apps : [:]
        for app in Set(last.keys).subtracting(wanted.keys) { quit(app) }
        last = wanted
        for (app, info) in wanted {
            if let r = running[app], !r.isTerminated {
                if !iconWritten.contains(app), let icon = info.icon { writeIcon(app, icon) } else { post(app) }
                continue
            }
            launch(app, info)
        }
    }

    func quitAll() {
        for app in Array(last.keys) { quit(app) }
        last = [:]
    }

    private func quit(_ app: String) {
        iconWritten.remove(app)
        DistributedNotificationCenter.default().postNotificationName(Self.stateName, object: app, userInfo: ["quit": true],
                                                                     deliverImmediately: true)
        running[app] = nil
    }

    private func post(_ app: String) {
        guard let info = last[app] else { return }
        DistributedNotificationCenter.default().postNotificationName(
            Self.stateName, object: app,
            userInfo: ["ids": info.windows.map { String($0.id) }, "titles": info.windows.map(\.title),
                       "states": info.windows.map(\.state.rawValue), "icon": Self.iconURL(app).path],
            deliverImmediately: true)
    }

    private func launch(_ app: String, _ info: AppWindows) {
        guard !making.contains(app), let template = Self.template else { return }
        making.insert(app)
        let png = info.icon.map(Self.badged).flatMap(Self.png)
        if png != nil { iconWritten.insert(app) } else { iconWritten.remove(app) }
        let name = info.name
        let iconURL = Self.iconURL(app)
        work.async { [weak self] in
            if let png { try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true); try? png.write(to: iconURL) }
            let url = Self.make(app: app, name: name, template: template)
            DispatchQueue.main.async {
                guard let self else { return }
                self.making.remove(app)
                guard let url, self.last[app] != nil else { return }
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false
                config.addsToRecentItems = false
                config.arguments = ["--app", app, "--viewer", String(ProcessInfo.processInfo.processIdentifier), "--icon", iconURL.path]
                NSWorkspace.shared.openApplication(at: url, configuration: config) { running, error in
                    DispatchQueue.main.async {
                        if let error { print("dock: \(name)'s icon did not start: \(error.localizedDescription)"); return }
                        self.running[app] = running
                        self.post(app)
                    }
                }
            }
        }
    }

    /// The app's badged icon written, then its Dock icon told to show it.
    private func writeIcon(_ app: String, _ icon: NSImage) {
        guard let png = Self.png(Self.badged(icon)) else { return }
        iconWritten.insert(app)
        let url = Self.iconURL(app)
        work.async { [weak self] in
            try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            try? png.write(to: url)
            DispatchQueue.main.async { self?.post(app) }
        }
    }

    private static func iconURL(_ app: String) -> URL { folder.appendingPathComponent("\(slug(app)).png") }

    // MARK: The copies

    /// The helper inside Sill Viewer.
    private static var template: URL? {
        let url = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/SillDockProxy.app")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sill Viewer/Dock", isDirectory: true)
    }

    /// A safe bundle ID part and file name from a remote app's bundle ID.
    static func slug(_ app: String) -> String {
        let s = app.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || $0 == "." || $0 == "-" ? Character($0) : "-" }
        return String(String(s).prefix(100))
    }

    /// The copy for `app`, made (or made again) when the helper or the name changed. Off the main thread.
    private static func make(app: String, name: String, template: URL) -> URL? {
        let fm = FileManager.default
        let dest = folder.appendingPathComponent("\(slug(app)).app", isDirectory: true)
        let stampURL = dest.appendingPathComponent("Contents/Resources/stamp")
        let templateStamp = (try? fm.attributesOfItem(atPath: template.appendingPathComponent("Contents/MacOS/SillDockProxy").path)[.modificationDate] as? Date)
            .map { "\($0.timeIntervalSince1970)" } ?? "?"
        let stamp = "\(templateStamp)|\(name)"
        if (try? String(contentsOf: stampURL, encoding: .utf8)) == stamp { return dest }
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: template, to: dest)
            let plistURL = dest.appendingPathComponent("Contents/Info.plist")
            guard var plist = NSDictionary(contentsOf: plistURL) as? [String: Any] else { return nil }
            plist["CFBundleName"] = name
            plist["CFBundleDisplayName"] = name
            plist["CFBundleIdentifier"] = "me.saffer.sill.client.dock.\(slug(app))"
            plist["SillRemoteApp"] = app   // a copy kept in the Dock and clicked starts with no arguments
            (plist as NSDictionary).write(to: plistURL, atomically: true)
            try fm.createDirectory(at: dest.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
            try stamp.write(to: stampURL, atomically: true, encoding: .utf8)
            let sign = Process()
            sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            sign.arguments = ["--force", "--sign", "-", dest.path]
            sign.standardOutput = FileHandle.nullDevice
            sign.standardError = FileHandle.nullDevice
            try sign.run()
            sign.waitUntilExit()
            guard sign.terminationStatus == 0 else { print("dock: signing \(name)'s icon failed"); return nil }
            return dest
        } catch {
            print("dock: \(name)'s icon could not be made: \(error)")
            return nil
        }
    }

    /// The remote app's icon with Sill Viewer's own in its lower right corner, so its Dock icon reads
    /// as the other Mac's app, not this Mac's.
    static func badged(_ icon: NSImage) -> NSImage {
        let side = 512
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return icon }
        let full = NSRect(x: 0, y: 0, width: side, height: side)
        let b = CGFloat(side) * 0.42
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        icon.draw(in: full)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
        shadow.shadowBlurRadius = CGFloat(side) * 0.02
        shadow.shadowOffset = NSSize(width: 0, height: -CGFloat(side) * 0.008)
        shadow.set()
        NSApp.applicationIconImage?.draw(in: NSRect(x: CGFloat(side) - b, y: 0, width: b, height: b))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: side, height: side))
        image.addRepresentation(rep)
        return image
    }

    private static func png(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
