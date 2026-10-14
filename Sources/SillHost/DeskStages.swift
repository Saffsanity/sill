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

    /// Whether `id`'s window is full screen now (Accessibility's word); nil when it is not on the desk.
    func isFullScreen(_ id: UInt32) -> Bool? { stages[id].flatMap { $0.isStaged ? $0.isFullScreenNow : nil } }

    /// What a window's capture is at most: its display's scale (1× for a room wider than a 2×
    /// display can be: an ultrawide's).
    func scale(for id: UInt32) -> CGFloat { CGFloat(stages[id]?.displayScale ?? 2) }

    /// The display identities in use, by window: product IDs 0x100… with a serial kept for each, so
    /// a slot is the same monitor to macOS every time (it remembers "Extended" for it). Taken as
    /// needed, the lowest free first; no fixed number of windows.
    private var slots: [UInt32: Int] = [:]

    /// Windows the desk could not take (Accessibility found no window to move, it refused the move,
    /// or no room was left), by when: captured where they are meanwhile, and not tried again for a
    /// while (`mayTry`), so no display is made and removed for them over and over (see `spares`).
    private var cannotTake: [UInt32: Date] = [:]

    /// Whether the desk tries `id` again: a window picked on the device 30 s after it could not take
    /// it, one shown beside it 5 minutes after.
    func mayTry(_ id: UInt32, picked: Bool) -> Bool {
        cannotTake[id].map { Date().timeIntervalSince($0) >= (picked ? 30 : 300) } ?? true
    }

    private func freeSlot() -> Int { (0...).first { s in !slots.values.contains(s) && !spares.contains { $0.slot == s } }! }

    /// Displays windows have left, kept for the next window that needs one, so a window coming and going
    /// makes no display. Every display made and removed leaves macOS's ColorSync service more work for
    /// the rest of the login session (about 40 in a morning saturated it, and WindowServer, waiting on
    /// it, was killed by its watchdog), and a display made after another was removed can stream a
    /// third's picture (DeskPicture). As many as windows were on the desk at once; all removed together
    /// once the desk is empty (`keep`), or made again by hand (`releaseAll`).
    private var spares: [(spare: VirtualStage.Spare, slot: Int)] = []

    /// What the desk's displays may take of this Mac's memory in all: each holds a framebuffer of its
    /// own (about 130 MB for a Retina display at the largest size), so a new window goes on the desk
    /// only while the displays already made leave room for one more of the same.
    nonisolated static let memoryShare = 0.25

    /// The framebuffers the desk's displays hold now, in bytes, and the largest of them.
    private var framebuffers: (total: Double, largest: Double) {
        let each = (stages.values.compactMap(\.display) + spares.map(\.spare.display)).map { d in
            Double(d.madeWidthPt * d.scale) * Double(d.madeHeightPt * d.scale) * 4
        }
        return (each.reduce(0, +), each.max() ?? 0)
    }

    private func roomForAnother() -> Bool {
        let (total, largest) = framebuffers
        return total + max(largest, Double(Self.largest.width * Self.largest.height) * 4 * 4)
            <= Double(ProcessInfo.processInfo.physicalMemory) * Self.memoryShare
    }

    private static func serial(forSlot slot: Int) -> UInt32 {
        let key = "SillDeskSerial\(slot)"
        if let kept = UserDefaults.standard.object(forKey: key) as? Int, kept > 0 { return UInt32(kept) }
        let made = UInt32.random(in: 100_000...9_999_999)
        UserDefaults.standard.set(Int(made), forKey: key)
        return made
    }

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
        let stage: VirtualStage
        if let existing = stages[id] { stage = existing } else {
            // No display for a window that cannot go on one (see `spares`). A window picked on the device
            // (`fps`, the main stream) in another Space is found by Accessibility only once the stage
            // has brought that Space into view, so it is not looked up first.
            guard mayTry(id, picked: fps != nil) else { throw VirtualStage.Failure.axWindowNotFound }
            if fps == nil || window.isOnScreen, sizer.placement(for: window) == nil {
                cannotTake[id] = Date()
                throw VirtualStage.Failure.axWindowNotFound
            }
            stage = VirtualStage(sizer: sizer, catalog: catalog)
            if let kept = spares.popLast() {
                // A display another window left: no new one (`spares`).
                stage.adopt(kept.spare)
                slots[id] = kept.slot
                print("Sill's desk: window \(id) takes kept display \(kept.spare.display.displayID) (\(spares.count) more kept).")
            } else {
                guard roomForAnother() else { cannotTake[id] = Date(); throw TooMany(count: stages.count) }
                let slot = freeSlot()
                stage.productID = 0x100 + UInt32(slot)
                stage.serial = Self.serial(forSlot: slot)
                slots[id] = slot
            }
            stages[id] = stage
        }
        if let room { stage.deskRoom = CGSize(width: max(room.width, stage.deskRoom?.width ?? 0), height: max(room.height, stage.deskRoom?.height ?? 0)) }
        // A full-screen window is its display's size: never the size to make the display for (it grew
        // the display, which threw the window out of full screen and grew again); the size it had
        // before full screen stands in.
        let fullScreen = stage.isStaged && stage.isFullScreenNow
        let asked = size
        let size = fullScreen ? (stage.normalSize ?? size) : size
        stage.deskWindow = size
        // Its own display, made once at the room's size and 120 Hz, so neither a resize nor a rate
        // change makes it again, and a full-screen Space there covers this window's display alone.
        do { try await stage.ensureDeskDisplay() } catch { stage.release(); forget(id); cannotTake[id] = Date(); throw error }
        // Full screen (or just out of it): the display fitted to the window's own size on the device
        // first, whether it streams as the main window or beside it.
        // The main window's `size` is the device's window (a side stream's is the window's own, which
        // in full screen is the whole display: those keep the size they had before it).
        if stage.isStaged, stage.fitFullScreen(to: fps == nil ? nil : asked) { try? await Task.sleep(for: .milliseconds(400)) }
        let captureScale = min(captureScale, CGFloat(stage.displayScale))
        stage.onLost = { [weak self] in self?.forget(id) }   // the window is home already
        let envelope = Self.envelope(for: CGSize(width: max(size.width, room?.width ?? 0), height: max(size.height, room?.height ?? 0)))
        let prepared: VirtualStage.Prepared
        do {
            stage.mayReachOtherSpace = fps != nil
            prepared = try await stage.prepare(window: window, wanted: size, envelope: envelope, captureScale: captureScale, refreshHz: 120)
        } catch {
            stage.release()
            forget(id)
            // A window that refused the move, or was not found there, is not tried again for a while.
            cannotTake[id] = Date()
            throw error
        }
        cannotTake[id] = nil
        var filter = prepared.filter
        // The display's filter is used for the main stream, and for a window beside it only in full
        // screen (otherwise captured alone): not fetched for nothing.
        if fps != nil || stage.isFullScreenNow, let display = stage.scDisplay, let owner = window.owningApplication,
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

    /// Every staged window not in `keep` goes home, its display kept for the next (`spares`); once
    /// none is left on the desk, the kept displays go together.
    func keep(_ keep: Set<UInt32>) {
        for id in staged.subtracting(keep) { release(id) }
        if stages.isEmpty { removeSpares() }
    }

    /// The window home, its display kept for the next window (`spares`).
    func release(_ id: UInt32) {
        if let stage = stages[id], let kept = stage.handOver() {
            let d = kept.display
            // Torn down by the window server while kept (sleep, another display arriving): forgotten.
            d.onTerminated = { [weak self] in
                Task { @MainActor [weak self] in self?.spares.removeAll { $0.spare.display === d } }
            }
            spares.append((kept, slots[id] ?? 0))
        }
        forget(id)
    }

    /// The kept displays removed, together.
    private func removeSpares() {
        guard !spares.isEmpty else { return }
        let ids = spares.map { String($0.spare.display.displayID) }
        for s in spares { s.spare.display.onTerminated = nil; s.spare.display.destroy() }
        spares.removeAll()
        VirtualStage.arrangementChangedAt = Date()
        print("Sill's desk: removed its kept displays \(ids.joined(separator: ", ")).")
    }

    private func forget(_ id: UInt32) {
        stages[id] = nil
        slots[id] = nil
    }

    struct TooMany: Error, CustomStringConvertible {
        let count: Int
        var description: String {
            "Sill's desk has \(count) windows; their displays already take a quarter of this Mac's memory"
        }
    }

    /// Every window home and every display removed, kept ones too (a quit, the last device gone, or
    /// the desk made again by hand).
    func releaseAll() {
        for id in staged { release(id) }
        removeSpares()
        cannotTake.removeAll()
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
