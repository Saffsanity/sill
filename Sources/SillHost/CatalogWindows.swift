import Foundation

/// Which of ScreenCaptureKit's on-screen windows the catalog lists: the tiles in a device's window
/// strip (WindowCatalog.refreshWindows). Pure, on plain values, so `Tests/checks/catalog-windows`
/// holds it.
///
/// An app's window is one whose owner has a name (the window server's own windows, the menu bar's
/// and the wallpaper's backstops, have none), on the normal layer 0 (the wallpaper, the desktop's
/// icons and its widgets sit below it; the menu bar, the Dock and panels above), larger than
/// 100 × 100 points, and not this process's (Sill's Settings, its log, the pairing window with its
/// code). Of those, a helper's window (`Helper`) is left out too: it has no picture of its own, and
/// a device showed it as a blank tile that nothing could bring forward (issue #114).
enum CatalogWindows {
    /// One window as ScreenCaptureKit lists it: an SCWindow and its owningApplication, in plain values.
    struct Window: Equatable {
        var title: String?
        /// The owner's name: nil without an owning application, empty for the window server's own
        /// windows (macOS 27 lists those under an owner with no name and no bundle identifier).
        var appName: String?
        /// The owner's bundle identifier: empty for a process with no bundle (a tool run from a
        /// shell, whose windows macOS lists under its executable's name).
        var bundleID: String?
        var pid: Int32
        var layer: Int
        var width: Double
        var height: Double
    }

    /// Why a window that passes `isAppWindow` is still no app's window.
    enum Helper: Equatable {
        /// "LayerProbeParent": AppKit and SwiftUI make one for themselves when a display appears (an
        /// off-screen window that probes layer backing on the new screen). It carries the app's name
        /// and no content, showed up as a duplicate tile with a blank thumbnail, and the window server
        /// drops it onto a real display when a virtual display goes away.
        case layerProbe
        /// A window of macOS's own interface (`systemInterface`), whatever its title: Stage Manager's
        /// strip and, from macOS 27, the wallpaper (WindowManager), the Dock and Mission Control,
        /// Control Center, the menu bar's extras, notifications and widgets, the screenshot tools.
        /// None is an app's window, and WindowManager, SystemUIServer, Notification Center and the
        /// screenshot tools have no icon of their own, so a device showed macOS's generic app icon on
        /// a blank tile (issue #114).
        case systemInterface
        /// An untitled window of a process with no bundle identifier: a tool's overlay or helper (a
        /// window border, a highlight), with no title or icon to show it by.
        case untitledWithoutBundle
    }

    /// The owners whose windows are macOS's own interface, lowercased (bundle identifiers compare
    /// without regard to case). The same owners ScreenCaptureKit recorders leave out of their
    /// window pickers. Not the open and save panel service (`com.apple.appkit.xpc.*`): a sandboxed
    /// app's Open and Save panels may be its windows, and they are windows someone works in.
    static let systemInterface: Set<String> = [
        "com.apple.windowmanager",          // Stage Manager, window tiling; the wallpaper from macOS 27
        "com.apple.dock",                   // the Dock, Mission Control, the wallpaper before macOS 27
        "com.apple.controlcenter",
        "com.apple.systemuiserver",
        "com.apple.notificationcenterui",
        "com.apple.screencaptureui",
    ]

    /// The catalog's filter before issue #114: an app's window by its owner, layer, size and process.
    static func isAppWindow(_ w: Window, ownPID: Int32) -> Bool {
        guard let name = w.appName, !name.isEmpty else { return false }
        return w.layer == 0 && w.width > 100 && w.height > 100 && w.pid != ownPID
    }

    /// Which helper's window this is, if any (judged on its own, not only for an app's window).
    static func helper(_ w: Window) -> Helper? {
        if (w.title ?? "").lowercased().contains("layerprobe") { return .layerProbe }
        let id = (w.bundleID ?? "").lowercased()
        if systemInterface.contains(id) { return .systemInterface }
        let untitled = (w.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if untitled && id.isEmpty { return .untitledWithoutBundle }
        return nil
    }

    /// Whether a device's window strip gets this window.
    static func lists(_ w: Window, ownPID: Int32) -> Bool {
        isAppWindow(w, ownPID: ownPID) && helper(w) == nil
    }

    /// The lines the catalog prints for the windows one look left out that the filter before issue
    /// #114 would have listed: one per owner for as long as the host runs (`named` keeps which), so
    /// Sill.log names what a device no longer sees. LayerProbeParent's windows were left out before
    /// and print nothing.
    static func leftOutLines(_ windows: [Window], ownPID: Int32, named: inout Set<String>) -> [String] {
        var lines: [String] = []
        for w in windows where isAppWindow(w, ownPID: ownPID) {
            guard let kind = helper(w), kind != .layerProbe else { continue }
            let name = w.appName ?? "", id = w.bundleID ?? ""
            guard named.insert("\(id) \(name)").inserted else { continue }
            lines.append(kind == .systemInterface
                ? "Catalog: leaving out the windows of \(name) (\(id)): they are macOS's own, not an app's."
                : "Catalog: leaving out the untitled windows of \(name) (no bundle identifier): a helper's, not an app's.")
        }
        return lines
    }
}
