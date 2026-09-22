import Foundation
import AppKit
import ScreenCaptureKit
import ImageIO
import UniformTypeIdentifiers
import StreamProtocol

/// Knows what is on the Mac: the on-screen windows (polled), a small JPEG thumbnail of each,
/// app icons, and the installed apps for the drawer. Everything here runs on the main actor;
/// callbacks fire there too and the coordinator forwards to the network.
@MainActor
final class WindowCatalog {
    private(set) var windows: [SCWindow] = []
    private(set) var infos: [WindowInfo] = []
    private(set) var display: SCDisplay?
    private(set) var installedApps: [AppInfo] = []

    /// Fires when the window list changes (new, closed, retitled, resized, reordered).
    var onWindowsChanged: (([WindowInfo]) -> Void)?
    /// A fresh thumbnail for one window.
    var onThumbnail: ((UInt32, Data) -> Void)?
    /// An icon we have not announced yet (running or installed app).
    var onNewIcon: ((String, Data) -> Void)?

    /// Thumbnails cost a screenshot per window; only take them while someone is looking.
    var thumbnailsWanted = false

    private var seenOrder: [UInt32] = []
    private var icons: [String: Data] = [:]
    private var announcedIcons: Set<String> = []
    private var polling = false

    static let ownPID = ProcessInfo.processInfo.processIdentifier

    func start() {
        guard !polling else { return }
        polling = true
        Task { @MainActor in
            while true {
                await refreshWindows()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        Task { @MainActor in
            while true {
                if thumbnailsWanted { await refreshThumbnails() }
                try? await Task.sleep(for: .milliseconds(1500))
            }
        }
        Task { @MainActor in scanInstalledApps() }
    }

    func window(id: UInt32) -> SCWindow? { windows.first { $0.windowID == id } }

    /// Every icon we know, for a client that just connected.
    var allIcons: [(bundleID: String, png: Data)] { icons.map { ($0.key, $0.value) } }

    // MARK: Windows

    func refreshWindows() async {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true) else { return }
        display = content.displays.first
        let visible = content.windows.filter { w in
            guard let app = w.owningApplication, !app.applicationName.isEmpty else { return false }
            return w.windowLayer == 0                                  // drops widgets, wallpaper, backstop
                && w.frame.width > 100 && w.frame.height > 100
                && app.processID != Self.ownPID
        }
        // The system's order is not front-to-back and shuffles between polls. The brief wants a
        // fixed order in the bar, so keep first-seen order and append newcomers.
        let byID = Dictionary(uniqueKeysWithValues: visible.map { ($0.windowID, $0) })
        seenOrder = seenOrder.filter { byID[$0] != nil } + visible.map(\.windowID).filter { !seenOrder.contains($0) }
        let ordered = seenOrder.compactMap { byID[$0] }
        let newInfos = ordered.map { w in
            WindowInfo(id: w.windowID,
                       title: w.title ?? "",
                       appName: w.owningApplication?.applicationName ?? "",
                       bundleID: w.owningApplication?.bundleIdentifier ?? "",
                       width: Int(w.frame.width), height: Int(w.frame.height))
        }
        windows = ordered
        for w in ordered { announceIconIfNeeded(for: w.owningApplication) }
        if newInfos != infos {
            infos = newInfos
            onWindowsChanged?(newInfos)
        }
    }

    private func refreshThumbnails() async {
        // 2× the 104×66 pt tile in the client's bar. Fit each window's aspect inside that box.
        let box = CGSize(width: 208, height: 132)
        for w in windows {
            let sf = min(box.width / w.frame.width, box.height / w.frame.height)
            let config = SCStreamConfiguration()
            config.width = max(2, Int(w.frame.width * sf))
            config.height = max(2, Int(w.frame.height * sf))
            config.showsCursor = false
            let filter = SCContentFilter(desktopIndependentWindow: w)
            guard let image = try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config),
                  let jpeg = Self.jpeg(image, quality: 0.6) else { continue }
            onThumbnail?(w.windowID, jpeg)
        }
    }

    // MARK: Icons

    private func announceIconIfNeeded(for app: SCRunningApplication?) {
        guard let app else { return }
        let id = app.bundleIdentifier
        guard !id.isEmpty, !announcedIcons.contains(id) else { return }
        let image = NSRunningApplication(processIdentifier: app.processID)?.icon
            ?? NSWorkspace.shared.icon(forFile: NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)?.path ?? "")
        announce(bundleID: id, image: image)
    }

    private func announce(bundleID: String, image: NSImage) {
        guard let png = Self.png(image, size: 64) else { return }
        icons[bundleID] = png
        announcedIcons.insert(bundleID)
        onNewIcon?(bundleID, png)
    }

    // MARK: Installed apps

    private func scanInstalledApps() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dirs = ["/Applications", "/Applications/Utilities", "/System/Applications", "/System/Applications/Utilities",
                    home.appendingPathComponent("Applications").path]
        var seen: Set<String> = []
        var apps: [AppInfo] = []
        for dir in dirs {
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir) else { continue }
            for name in names where name.hasSuffix(".app") {
                let url = URL(fileURLWithPath: dir).appendingPathComponent(name)
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, !seen.contains(id) else { continue }
                seen.insert(id)
                var display = FileManager.default.displayName(atPath: url.path)
                if display.hasSuffix(".app") { display.removeLast(4) }
                apps.append(AppInfo(name: display, bundleID: id))
                if !announcedIcons.contains(id) {
                    announce(bundleID: id, image: NSWorkspace.shared.icon(forFile: url.path))
                }
            }
        }
        installedApps = apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: Image encoding

    private static func jpeg(_ image: CGImage, quality: CGFloat) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    private static func png(_ image: NSImage, size: Int) -> Data? {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                         samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = NSSize(width: size, height: size)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .copy, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
