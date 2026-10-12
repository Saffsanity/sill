import AppKit
import ScreenCaptureKit

/// A window captured with what belongs to it (the Mac client asks for this: SideStreamRequest's
/// `wholeApp`): its display, cropped to the window's frame, with every other regular app left out,
/// and Sill (its pairing window has the code). Its menus, popovers and sheets show, and so does what
/// the system draws over it from its own processes (the window menu of its buttons, the capture
/// indicator's menu, open and save panels, share sheets), so it is plain the window is another
/// Mac's; another app's window never does. A window in full screen (its own Space, which a display
/// crop of this Space does not show) is captured alone instead (nil).
/// An app-based filter takes the app's windows as they come, so a menu opened after the capture
/// started shows too. The crop is fixed: a window that moves is captured again (its frame is in
/// `frame`). Main actor.
enum AppCrop {
    struct Crop {
        let filter: SCContentFilter
        /// In the display's own points: ScreenCaptureKit's `sourceRect`.
        let sourceRect: CGRect
        /// The window's frame in global points when the crop was made.
        let frame: CGRect
    }

    @MainActor
    static func crop(for window: SCWindow, frame live: CGRect? = nil) async -> Crop? {
        let frame = live ?? window.frame
        guard let content = await WindowCatalog.shareableContent(excludingDesktopWindows: false, onScreenWindowsOnly: true, timeout: 2),
              let owner = window.owningApplication else { return nil }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        guard let display = content.displays.first(where: { CGDisplayBounds($0.displayID).contains(center) })
                ?? content.displays.first(where: { CGDisplayBounds($0.displayID).intersects(frame) }) else { return nil }
        let bounds = CGDisplayBounds(display.displayID)
        if abs(frame.width - bounds.width) < 2 && frame.height >= bounds.height - 40 { return nil }   // full screen
        let filter = Self.filter(display: display, owner: owner.processID, applications: content.applications)
        let local = frame.offsetBy(dx: -bounds.minX, dy: -bounds.minY).intersection(CGRect(origin: .zero, size: bounds.size))
        guard local.width >= 16, local.height >= 16 else { return nil }
        return Crop(filter: filter, sourceRect: local, frame: frame)
    }

    /// `display` with the owner's app and the system's own processes, every other regular app, Sill
    /// and the backdrop left out (the crop's filter, and Sill's desk's: DeskStages).
    static func filter(display: SCDisplay, owner: pid_t, applications: [SCRunningApplication]) -> SCContentFilter {
        let own = ProcessInfo.processInfo.processIdentifier
        let regular = Set(NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.map(\.processIdentifier))
        let others = applications.filter {
            $0.processID == own || backdrop.contains($0.bundleIdentifier)
                || ($0.processID != owner && regular.contains($0.processID))
        }
        return SCContentFilter(display: display, excludingApplications: others, exceptingWindows: [])
    }

    /// What lies behind and beside every window, never another Mac's window's: the Dock, the wallpaper
    /// (WindowManager's) and Notification Centre's widgets.
    static let backdrop: Set<String> = ["com.apple.dock", "com.apple.WindowManager", "com.apple.notificationcenterui"]
}

/// macOS's own sign that a window is being shared: the purple pill in place of its traffic lights,
/// whose menu (Move & Resize, Full Screen, Move to…) the system draws over it. macOS draws the pill
/// only while the window itself is captured, which a display crop (AppCrop) is not, so beside each
/// cropped window a capture of the window alone runs, 32×32 at 1 fps, its frames dropped: the pill
/// and its menu then show in the crop, and the person controlling the window from afar sees that it
/// is shared as they would on the Mac. Main actor.
@MainActor
final class SharePill {
    private let capture = WindowCapture()

    func start(_ window: SCWindow) async {
        capture.statsPrefix = "pill"
        try? await capture.start(filter: SCContentFilter(desktopIndependentWindow: window), width: 32, height: 32, fps: 1,
                                 showsCursor: false)
    }

    func stop() async { await capture.stop() }
}
