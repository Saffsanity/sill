import AppKit
import CryptoKit
import ImageIO
import StreamProtocol

/// A Dock icon per remote app with a window open here, grouped as macOS groups an app's windows
/// (Sources/SillDockProxy): Sill Viewer carries one helper app; for each remote app it makes a copy,
/// named after that app with a bundle ID of its own, signs the copy ad hoc on this Mac (its
/// Info.plist changed, the original signature no longer holds; a copy made here carries no
/// quarantine), and launches it in the background. The helper shows the remote app's icon, lists
/// its windows in its Dock menu, and asks Sill Viewer to bring them forward when clicked; it quits
/// once that app has no window open here, or when Sill Viewer goes. Copies live in
/// ~/Library/Application Support/Sill Viewer/Dock and are made again only when the helper or the
/// name changes. Main thread.
///
/// The two talk by distributed notifications, which any process here can post and read, so none
/// carries anything: what a Dock icon shows (the window titles, the menu) is in a file only this user
/// can read (`<slug>.state`), and the notification only says it changed. A Dock icon's request is
/// signed: an HMAC of its contents under the key Sill Viewer writes there at each launch (`token`,
/// 0600), with a counter that must rise, so a process that watches the notifications learns what was
/// asked (a window's ID, a menu item's title) but can neither forge a request nor replay one.
final class DockProxies {
    /// An app's windows open here, and its Dock badge on the other Mac.
    struct AppWindows { let name: String; let icon: NSImage?; let windows: [Window]; var badge: String? = nil }
    /// A window in the Dock menu: the app's front one gets a ✓, as macOS marks its own.
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
    /// A Dock icon quit from the Dock: its app's windows close here.
    var onClose: ((_ app: String) -> Void)?
    /// Ask the other Mac for an app's own Dock menu (kind 39), and press one of its items there.
    var askMenu: ((_ app: String) -> Void)?
    var pressMenu: ((_ app: String, _ id: Int, _ title: String) -> Void)?
    /// Each app's own Dock menu on the other Mac, as last read, and when it was asked for.
    private var menus: [String: [DockMenu.Item]] = [:]
    private var menuAsked: [String: Date] = [:]
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

    /// This launch's secret, which a Dock icon's request must carry.
    private let token = UUID().uuidString
    /// Each app's last request counter, which the next must exceed.
    private var lastCounter: [String: Int64] = [:]

    init() {
        Self.writePrivate(Data(token.utf8), to: Self.folder.appendingPathComponent("token"))
        DistributedNotificationCenter.default().addObserver(forName: Self.actionName, object: nil, queue: .main) { [weak self] note in
            guard let self, let app = note.object as? String, let info = note.userInfo as? [String: String],
                  let n = info["n"].flatMap(Int64.init), n > self.lastCounter[app, default: 0],
                  let mac = info["mac"], mac == DockRequest.mac(app: app, info, key: self.token) else { return }
            self.lastCounter[app] = n
            if note.userInfo?["ask"] as? String == "launch" {
                // Only for an app that has a Dock icon here (one kept in the Dock and clicked).
                if FileManager.default.fileExists(atPath: Self.folder.appendingPathComponent(Self.slug(app)).path) { self.onLaunch?(app) }
                return
            }
            guard self.last[app] != nil else { return }
            switch note.userInfo?["ask"] as? String {
            case "focus": self.onFocus?(app, nil)
            case "window": self.onFocus?(app, (note.userInfo?["window"] as? String).flatMap { UInt32($0) })
            case "state": self.post(app)
            case "close": self.running[app] = nil; self.onClose?(app)
            case "menu": self.refreshMenu(app)
            case "dockItem":
                if let id = (note.userInfo?["item"] as? String).flatMap({ Int($0) }), let title = note.userInfo?["title"] as? String {
                    self.pressMenu?(app, id, title)
                }
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
        tell(app, ["quit": true])
        running[app] = nil
    }

    /// `state` written where only this user reads it, and the app's Dock icon told it changed.
    private func tell(_ app: String, _ state: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: state) else { return }
        Self.writePrivate(data, to: Self.folder.appendingPathComponent("\(Self.slug(app)).state"))
        DistributedNotificationCenter.default().postNotificationName(Self.stateName, object: app, userInfo: nil, deliverImmediately: true)
    }

    /// `data` at `url`, readable and writable by this user alone.
    private static func writePrivate(_ data: Data, to url: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let temp = url.appendingPathExtension("tmp")
        guard fm.createFile(atPath: temp.path, contents: data, attributes: [.posixPermissions: 0o600]) else { return }
        _ = try? fm.replaceItemAt(url, withItemAt: temp)
    }

    /// The app's Dock menu as the other Mac read it: shown in its Dock icon's menu from the next opening.
    func setMenu(_ app: String, _ items: [DockMenu.Item]) {
        menus[app] = items
        post(app)
    }

    /// Asked for again when the Dock icon's menu opens, at most every 20 s: each read shows the menu in
    /// the other Mac's Dock for a moment.
    private func refreshMenu(_ app: String) {
        if let at = menuAsked[app], Date().timeIntervalSince(at) < 20 { return }
        menuAsked[app] = Date()
        askMenu?(app)
    }

    private func post(_ app: String) {
        guard let info = last[app] else { return }
        let menu = menus[app] ?? []
        tell(app, ["badge": info.badge ?? "", "ids": info.windows.map { String($0.id) }, "titles": info.windows.map(\.title),
                   "states": info.windows.map(\.state.rawValue), "icon": Self.iconURL(app).path,
                   "menuIDs": menu.map { String($0.id) }, "menuTitles": menu.map(\.title),
                   "menuEnabled": menu.map { $0.enabled ? "1" : "0" }])
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
            if let url, let png { Self.installIcon(png, in: url) }
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
                        self.refreshMenu(app)
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
            if let name = self?.last[app]?.name ?? nil { Self.installIcon(png, in: Self.appURL(app, name: name)) }
            DispatchQueue.main.async { self?.post(app) }
        }
    }

    private static func iconURL(_ app: String) -> URL { folder.appendingPathComponent("\(slug(app)).png") }

    /// The copy for `app`: in a folder of its own (the bundle ID), named after the app, which is the
    /// name the Dock shows.
    private static func appURL(_ app: String, name: String) -> URL {
        let file = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return folder.appendingPathComponent(slug(app), isDirectory: true)
            .appendingPathComponent("\(file.isEmpty ? slug(app) : file).app", isDirectory: true)
    }

    /// The badged icon as the copy's own (AppIcon.icns), so a Dock icon kept in the Dock shows it while
    /// its app is not running; the copy signed again. Only when the icon changed. Off the main thread.
    private static func installIcon(_ png: Data, in app: URL) {
        let resources = app.appendingPathComponent("Contents/Resources", isDirectory: true)
        let kept = resources.appendingPathComponent("icon.png")
        guard FileManager.default.fileExists(atPath: app.path), (try? Data(contentsOf: kept)) != png,
              let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        let icns = resources.appendingPathComponent("AppIcon.icns")
        guard let dest = CGImageDestinationCreateWithURL(icns as CFURL, "com.apple.icns" as CFString, 5, nil) else { return }
        for side in [16, 32, 128, 256, 512] {
            guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
            ctx.interpolationQuality = .high
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            if let scaled = ctx.makeImage() { CGImageDestinationAddImage(dest, scaled, nil) }
        }
        guard CGImageDestinationFinalize(dest) else { return }
        try? png.write(to: kept)
        let plistURL = app.appendingPathComponent("Contents/Info.plist")
        if var plist = NSDictionary(contentsOf: plistURL) as? [String: Any], plist["CFBundleIconFile"] as? String != "AppIcon" {
            plist["CFBundleIconFile"] = "AppIcon"
            (plist as NSDictionary).write(to: plistURL, atomically: true)
        }
        let sign = Process()
        sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        sign.arguments = ["--force", "--sign", "-", app.path]
        sign.standardOutput = FileHandle.nullDevice
        sign.standardError = FileHandle.nullDevice
        try? sign.run()
        sign.waitUntilExit()
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: app.path)
        NSWorkspace.shared.noteFileSystemChanged(app.path)
    }

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
        let dest = appURL(app, name: name)
        // The Dock names an app after its file: one from before, named after the bundle ID, goes.
        try? fm.removeItem(at: folder.appendingPathComponent("\(slug(app)).app", isDirectory: true))
        let stampURL = dest.appendingPathComponent("Contents/Resources/stamp")
        let templateStamp = (try? fm.attributesOfItem(atPath: template.appendingPathComponent("Contents/MacOS/SillDockProxy").path)[.modificationDate] as? Date)
            .map { "\($0.timeIntervalSince1970)" } ?? "?"
        let stamp = "\(templateStamp)|\(name)"
        if (try? String(contentsOf: stampURL, encoding: .utf8)) == stamp { return dest }
        do {
            let home = dest.deletingLastPathComponent()
            try fm.createDirectory(at: home, withIntermediateDirectories: true)
            // A copy under another name (the app's name changed, or was not known yet) goes too.
            for old in (try? fm.contentsOfDirectory(at: home, includingPropertiesForKeys: nil)) ?? [] where old.pathExtension == "app" {
                try? fm.removeItem(at: old)
            }
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

/// A Dock icon's request, signed (DockProxies): the same code is in SillDockProxy.
enum DockRequest {
    /// HMAC-SHA256 of the app and every field but the MAC itself, in a fixed order, as hex.
    static func mac(app: String, _ info: [String: String], key: String) -> String {
        let text = ([app] + info.filter { $0.key != "mac" }.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" })
            .joined(separator: "\n")
        let code = HMAC<SHA256>.authenticationCode(for: Data(text.utf8), using: SymmetricKey(data: Data(key.utf8)))
        return code.map { String(format: "%02x", $0) }.joined()
    }
}
