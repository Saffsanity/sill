import Foundation
import ScreenCaptureKit
import StreamProtocol

/// Sill's desk (the Mac client, which asks for whole-app capture): each of the host's windows a
/// device shows as a window of its own lives on a virtual display of its own while it does, sized to
/// the device's window, so the host's own displays limit neither its size nor its shape, nothing
/// overlaps it, and the person at the Mac keeps their desk as it was. Each is a VirtualStage (the
/// iPad's Virtual Display staging, one per window here), its display just larger than the window;
/// the capture is the stage's crop of that display with the window's app and the system's own
/// processes (AppCrop.filter), so its menus, popovers and the share pill's menu show. A window goes
/// home, to where it was, once no device shows it (`keep`), when the last device leaves, and at
/// exit (VirtualStage's snapshots). Main actor.
@MainActor
final class DeskStages {
    private var stages: [UInt32: VirtualStage] = [:]
    private let sizer: WindowSizer
    private let catalog: WindowCatalog

    init(sizer: WindowSizer, catalog: WindowCatalog) {
        self.sizer = sizer
        self.catalog = catalog
    }

    struct TooSmall: Error, CustomStringConvertible {
        let size: CGSize
        var description: String { "asked for \(Int(size.width))×\(Int(size.height)) pt" }
    }

    var staged: Set<UInt32> { Set(stages.keys) }
    /// The desk display's scale: what a desk window's capture is at most (a 1× desk on an ultrawide).
    var scale: CGFloat { CGFloat(shared.displayScale) }
    /// The one display every desk window shares (VirtualStage.host): this Mac keeps one virtual
    /// display online at a time, so a display per window took the last one offline and sent its
    /// window home. Made with the first window, gone with the last.
    private lazy var shared: VirtualStage = {
        let s = VirtualStage(sizer: sizer, catalog: catalog)
        s.serial = VirtualStage.freshSerial()
        // The window server took it away (sleep): every window on it is on some real display now.
        s.onLost = { [weak self] in
            guard let self else { return }
            for (_, stage) in self.stages { stage.releaseWindow() }
            self.stages.removeAll()
        }
        return s
    }()

    /// Puts `window` on its desk display at `size` (points), or keeps it there, and returns what to
    /// capture: the filter, the crop in the display's points, and the output size in points. `fps`
    /// is the display's rate (the main stream's, 60 or 120); nil keeps the rate it has (a side
    /// stream, whose lower rate must not make the display again and move the window home and back).
    /// `room`: the device's largest screen, which the display covers from the start, so the window
    /// grows up to full screen there without the display being made again.
    func prepare(_ window: SCWindow, size: CGSize, captureScale: CGFloat, fps: Int?, room: CGSize? = nil) async throws
        -> (filter: SCContentFilter, sourceRect: CGRect, size: CGSize) {
        // A window closing or minimizing can report a size of nothing: never a display for it.
        guard size.width >= 32, size.height >= 32 else { throw TooSmall(size: size) }
        let id = window.windowID
        let existing = stages[id]
        let stage = existing ?? VirtualStage(sizer: sizer, catalog: catalog)
        stage.host = shared
        if let room { shared.deskRoom = CGSize(width: max(room.width, shared.deskRoom?.width ?? 0), height: max(room.height, shared.deskRoom?.height ?? 0)) }
        stages[id] = stage
        let rate = fps ?? 60   // the shared display's own rate is 120 whatever this is
        try await shared.ensureShared()   // first: its scale caps the capture's
        let captureScale = min(captureScale, scale)
        stage.onLost = { [weak self] in self?.stages[id] = nil }   // the window is home already
        let envelope = Self.envelope(for: CGSize(width: max(size.width, room?.width ?? 0), height: max(size.height, room?.height ?? 0)))
        let prepared: VirtualStage.Prepared
        do {
            prepared = try await stage.prepare(window: window, wanted: size, envelope: envelope, captureScale: captureScale, refreshHz: rate)
        } catch {
            stage.release()
            stages[id] = nil
            throw error
        }
        var filter = prepared.filter
        if let display = stage.scDisplay, let owner = window.owningApplication,
           let content = await WindowCatalog.shareableContent(excludingDesktopWindows: false, onScreenWindowsOnly: true, timeout: 2) {
            filter = AppCrop.filter(display: display, owner: owner.processID, applications: content.applications)
        }
        return (filter, prepared.sourceRect, prepared.outputSize ?? prepared.sourceRect.size)
    }

    /// Where the window's picture is on screen, for input (nil when it is not on the desk).
    func captureRect(for id: UInt32) -> CGRect? {
        guard let stage = stages[id], stage.isStaged else { return nil }
        return stage.captureRectOnScreen
    }

    /// Every staged window not in `keep` goes home and its display goes.
    func keep(_ keep: Set<UInt32>) {
        for id in staged.subtracting(keep) { release(id) }
    }

    func release(_ id: UInt32) {
        stages.removeValue(forKey: id)?.release()
        // The display stays until Sill quits: each new one is a new screen to macOS, which asks what
        // to show on it ("What do you want to show on Sill?") and may mirror the main screen there.
    }

    func releaseAll() {
        for id in staged { release(id) }
    }

    /// A display just larger than the window: room for its menu bar, rounded up to 16 points, and
    /// at most `largest` (measured on macOS 27.0.1 at 2×: 3840 and 4096 points wide came up with no
    /// mode at all and ScreenCaptureKit never listed them; 3792×2160, 3808×1512 and 2560×2400 did).
    static func envelope(for size: CGSize) -> CGSize {
        func up(_ v: CGFloat) -> CGFloat { (v / 16).rounded(.up) * 16 }
        let want = CGSize(width: up(size.width + 16), height: up(size.height + 48))
        return VirtualStage.clamp(CGSize(width: min(want.width, largest.width), height: min(want.height, largest.height)))
    }

    static let largest = CGSize(width: 3792, height: 2160)
}
