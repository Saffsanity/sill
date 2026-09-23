import Foundation
import AppKit
import ApplicationServices
import ScreenCaptureKit
import StreamProtocol

/// `--virtual-display`: the one owner of the virtual display and of the window moved onto it.
///
/// Why: ScreenCaptureKit only delivers frames when a window repaints, and macOS stops repainting
/// a window that is fully covered, so a streamed window buried on the Mac froze on the device. A
/// window alone on its own display is never covered. The stage creates that display (private
/// `CGVirtualDisplay`, see VirtualDisplay.swift), moves the picked window onto it with
/// Accessibility (no activation: AX position/size writes do not raise or focus anything), and
/// hands the coordinator a display filter plus the crop rectangle of the window on it. On
/// deselect, switch, last client leaving, loss of the display or exit it puts the window back
/// exactly where it was and removes the display.
///
/// Geometry: the display is not sized to the client's panel but to an *envelope* — a square whose
/// side is the panel's longer edge ÷ 0.5 (the smallest Aa scale), plus the menu bar — and reused
/// as long as the wanted window fits, so a rotation or an Aa step only re-places the window and
/// restarts the pipeline; no display is recreated and nothing flashes on the Mac. The encoded
/// frame is always exactly the window's rectangle (`sourceRect`), so the envelope is invisible on
/// the device. To get the task's literal "display sized to the panel", make `envelope` return
/// `windowSize`. Aa "Off" is treated as 1.0 here: the window is off the user's screen and goes
/// back on deselect, and 1.0 is the only scale that maps device points 1:1 to Mac points.
///
/// Threading: main actor throughout, like the coordinator. The teardown calls are synchronous with
/// no awaits, so the signal handler can run them at any main-actor suspension point.
@MainActor
final class VirtualStage {
    /// What the coordinator needs to start the pipeline on the staged window.
    struct Prepared {
        let filter: SCContentFilter
        /// The window's rectangle in the display's own points (origin at its top-left).
        let sourceRect: CGRect
        let describe: String
        /// Encode at this size (points × capture scale) instead of the crop's: full screen's band
        /// is the whole display wide, twice what the panel can show.
        var outputSize: CGSize? = nil
    }

    /// Every way staging can fail. Each is a reason to stream the real window as before.
    enum Failure: Error, CustomStringConvertible {
        case disabled(String)
        case accessibilityOff
        case screenRecordingOff
        case axWindowNotFound
        case displayCreate(Error)
        case neverOnline
        case notListedBySCK
        case moveRefused(AXError)
        case notOnDisplay(CGRect)
        case windowMissing

        var description: String {
            switch self {
            case .disabled(let why): return "virtual display disabled: \(why)"
            case .accessibilityOff: return "accessibilityOff (Accessibility permission is needed to move the window)"
            case .screenRecordingOff: return "screenRecordingOff (Screen Recording is needed to capture the display; without it ScreenCaptureKit also hangs while a virtual display exists)"
            case .axWindowNotFound: return "axWindowNotFound (no Accessibility window matches the picked one)"
            case .displayCreate(let e): return "displayCreate: \(e)"
            case .neverOnline: return "neverOnline (the virtual display never came up)"
            case .notListedBySCK: return "notListedBySCK (ScreenCaptureKit never listed the virtual display)"
            case .moveRefused(let e): return "moveRefused (\(WindowSizer.axErrorName(e)))"
            case .notOnDisplay(let r): return String(format: "notOnDisplay (the window stayed at %.0f,%.0f %.0f×%.0f; fullscreen Space or clamped origin?)", r.minX, r.minY, r.width, r.height)
            case .windowMissing: return "windowMissing (the window vanished while being staged)"
            }
        }
    }

    // MARK: State

    private(set) var display: VirtualDisplay?
    private(set) var scDisplay: SCDisplay?
    private(set) var placement: WindowSizer.Placement?
    /// The size the window actually took on the display, and the size that was asked for.
    private(set) var placedSize: CGSize?
    private var askedSize: CGSize?
    /// The staged window is in a full-screen Space on the display (a video made full screen): it
    /// fills the display and refuses moves and sizes, so the display is captured as it is.
    private(set) var fullScreen = false
    /// Whether the staged window covers the whole display, menu-bar strip included (a normal window
    /// filling the area below the menu bar covers 98 % of a display and must not count).
    var windowCoversDisplay: Bool {
        guard let d = display, let p = placement, let live = WindowSizer.liveBounds(of: p.windowID) else { return false }
        let bounds = CGDisplayBounds(d.displayID)
        return live.minY <= bounds.minY + 1 && Self.fraction(of: bounds, inside: live) >= 0.98
    }

    /// Whether the staged window is still in its full-screen Space: AppKit's word first (the frame
    /// it reports mid-transition sits a little short of the display), else 90 % coverage.
    var windowStillFullScreen: Bool {
        guard let p = placement else { return false }
        if WindowSizer.isFullScreen(p.element) { return true }
        guard let d = display, let live = WindowSizer.liveBounds(of: p.windowID) else { return false }
        return Self.fraction(of: CGDisplayBounds(d.displayID), inside: live) >= 0.9
    }

    /// The window's rectangle in display-local points, trimmed to even output pixels.
    private(set) var captureRect: CGRect = .zero
    /// Height of the menu bar macOS draws on the virtual display. A guess until measured from
    /// NSScreen after the first display comes up, then cached for the process.
    private var menuInset: CGFloat = 24
    private var insetMeasured = false
    /// Set when staging must not be attempted again this run (API missing, repeated failures).
    var disabledReason: String?
    private var creationFailures = 0
    /// Bumped per display created, so a late termination callback for an old display is ignored.
    private var generation = 0
    /// Where the Mac cursor was before the host first drove it onto the virtual display.
    private var cursorBefore: CGPoint?
    /// The window server tore the display down on its own (sleep, display arbitration). Main actor.
    var onLost: (() -> Void)?

    let sizer: WindowSizer
    let catalog: WindowCatalog

    /// Display bounds: 320 is VirtualDisplay's floor; 4096 keeps the 2× backing store at or under
    /// 8192 px, its ceiling.
    static let minSide: CGFloat = 320
    static let maxSide: CGFloat = 4096
    /// Fixed identity, so System Settings › Displays keeps one remembered "Sill" entry across runs
    /// (the probe used serial 0xF00D and does not collide).
    static let vendorID: UInt32 = 0x5111, productID: UInt32 = 0x0001, serialNum: UInt32 = 1

    init(sizer: WindowSizer, catalog: WindowCatalog) {
        self.sizer = sizer
        self.catalog = catalog
    }

    var isStaged: Bool { display != nil && placement != nil }

    /// True when `windowID` is the staged window and `size` is what was last asked for it (±2 pt),
    /// so a repeated viewport needs no restart. Compared against the asked size, not the size the
    /// app took: an app that enforces a minimum would otherwise restart on every re-sent viewport.
    func matches(windowID: CGWindowID, size: CGSize) -> Bool {
        guard let p = placement, p.windowID == windowID, let d = display, d.isAlive, let asked = askedSize else { return false }
        return abs(asked.width - size.width) <= 2 && abs(asked.height - size.height) <= 2
    }

    /// The captured rectangle in global screen coordinates: what the device's touch fractions map
    /// onto. Nil when nothing is staged.
    var captureRectOnScreen: CGRect? {
        guard isStaged, let d = display, captureRect != .zero else { return nil }
        let b = CGDisplayBounds(d.displayID)
        return captureRect.offsetBy(dx: b.minX, dy: b.minY)
    }

    /// The staged window's current rectangle on the display, in display-local points. Nil when
    /// nothing is staged or the window is gone.
    func liveCaptureRect() -> CGRect? {
        guard let p = placement, let d = display, d.isAlive, let live = WindowSizer.liveBounds(of: p.windowID) else { return nil }
        let db = CGDisplayBounds(d.displayID)
        let i = live.intersection(db)
        guard !i.isNull, i.width > 0, i.height > 0 else { return nil }
        return i.offsetBy(dx: -db.minX, dy: -db.minY)
    }

    /// The user dragged the staged window off the virtual display (Mission Control, a Space
    /// change): less than 90 % of it is on the display. False when the window is gone.
    var windowLeftDisplay: Bool {
        guard let p = placement, let d = display, d.isAlive, let live = WindowSizer.liveBounds(of: p.windowID) else { return false }
        return Self.fraction(of: live, inside: CGDisplayBounds(d.displayID)) < 0.9
    }

    // MARK: Geometry (pure; the numbers in CLAUDE.md come from these)

    /// The size the window should have on the virtual display, in Mac points: the client's panel
    /// divided by its text scale (Aa Off or a bad scale count as 1.0), or the window's own size
    /// when no viewport has arrived yet.
    static func windowSize(for v: Viewport?, own: CGSize) -> CGSize {
        guard let v, v.width > 0, v.height > 0 else { return own }
        let s = (v.scale ?? 1) > 0 ? (v.scale ?? 1) : 1
        return CGSize(width: (v.width / s).rounded(), height: (v.height / s).rounded())
    }

    /// The display size (without the menu bar) that fits this panel at every Aa scale and in both
    /// orientations: a square of the longer edge ÷ 0.5 (the slider's smallest step). No viewport →
    /// the window's own size.
    static func envelope(for v: Viewport?, windowSize: CGSize) -> CGSize {
        guard let v, v.width > 0, v.height > 0 else { return clamp(windowSize) }
        let side = ceil(max(v.width, v.height) / 0.5)
        return clamp(CGSize(width: side, height: side))
    }

    static func clamp(_ s: CGSize) -> CGSize {
        CGSize(width: min(max(s.width, minSide), maxSide), height: min(max(s.height, minSide), maxSide))
    }

    /// The NSScreen for a display ID, as the area below its menu bar in CG (top-left) coordinates.
    /// Nil until AppKit has noticed the display (it learns about it through the run loop).
    static func usableArea(of id: CGDirectDisplayID) -> CGRect? {
        guard let screen = screen(for: id), let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        let v = screen.visibleFrame
        return CGRect(x: v.minX, y: primaryHeight - v.maxY, width: v.width, height: v.height)
    }

    static func screen(for id: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == id }
    }

    /// The largest rectangle of the panel's aspect centred in a full-screen display: where an app
    /// letterboxes a video, and what the device shows edge to edge.
    static func fullScreenCrop(in size: CGSize, panel: CGSize) -> CGRect {
        guard panel.width > 0, panel.height > 0, size.width > 0, size.height > 0 else { return CGRect(origin: .zero, size: size) }
        let aspect = panel.width / panel.height
        if size.width / aspect <= size.height {
            let h = size.width / aspect
            return CGRect(x: 0, y: ((size.height - h) / 2).rounded(.down), width: size.width, height: h)
        } else {
            let w = size.height * aspect
            return CGRect(x: ((size.width - w) / 2).rounded(.down), y: 0, width: w, height: size.height)
        }
    }

    /// How much of `rect` lies inside `area`, 0…1.
    static func fraction(of rect: CGRect, inside area: CGRect) -> CGFloat {
        let i = rect.intersection(area)
        guard !i.isNull, rect.width > 0, rect.height > 0 else { return 0 }
        return (i.width * i.height) / (rect.width * rect.height)
    }

    private static func close(_ a: CGRect, _ b: CGRect, within t: CGFloat = 2) -> Bool {
        abs(a.minX - b.minX) <= t && abs(a.minY - b.minY) <= t && abs(a.width - b.width) <= t && abs(a.height - b.height) <= t
    }

    private static func fmt(_ r: CGRect) -> String {
        String(format: "(%.0f,%.0f,%.0f×%.0f)", r.minX, r.minY, r.width, r.height)
    }

    private static func ms(since t: Date) -> Int { Int(Date().timeIntervalSince(t) * 1000) }

    // MARK: Staging

    /// Puts `window` on the virtual display at `wanted` points (creating or growing the display to
    /// `envelope` if needed) and returns the filter and crop to capture it with. Fails fast before
    /// touching anything if Accessibility is off or the window cannot be matched; every later
    /// failure undoes what it did (window restored, a display that never worked destroyed) so the
    /// coordinator can fall back to plain window capture.
    /// `refreshHz` is the stream's rate: the display is made at it (a 120 Hz display for a
    /// ProMotion device), and recreated when it changes.
    func prepare(window: SCWindow, wanted: CGSize, envelope: CGSize, captureScale: CGFloat, refreshHz: Int = 60) async throws -> Prepared {
        self.refreshHz = refreshHz
        // (1) A run-level decision already made.
        if let why = disabledReason { throw Failure.disabled(why) }

        // (2) Nothing created yet: check the parts that need no display first. Screen Recording is
        // checked here on purpose: measured 2026-09-22, SCShareableContent never returns in an
        // unauthorized process once a virtual display exists, so never create one without it.
        guard AXIsProcessTrusted() else { throw Failure.accessibilityOff }
        guard CGPreflightScreenCaptureAccess() else { throw Failure.screenRecordingOff }
        let p: WindowSizer.Placement
        if let current = placement, current.windowID == window.windowID {
            p = current                                       // same window: keep its original frame
        } else if let fresh = sizer.placement(for: window) {
            p = fresh
        } else {
            throw Failure.axWindowNotFound
        }

        // (3) A→B: A goes home first; the display stays for B.
        if let other = placement, other.windowID != window.windowID { releaseWindow() }

        // (4) The display.
        try await ensureDisplay(atLeast: envelope)
        guard display != nil else { throw Failure.neverOnline }

        // (5) From here on the host owns the window. Record that *before* the first move: the
        // settle loop and the grow path below suspend (up to seconds), and a teardown that runs
        // there — Ctrl-C's `shutdownForExit`, the display-lost callback, the coordinator's catch —
        // only restores what `placement` names. The sizes are recorded once the move has settled.
        placement = p
        EmergencySnapshot.set((p.element, p.originalFrame))
        catalog.stagedWindowID = p.windowID

        // (5b) Full screen. A window the user put in a full-screen Space (a video made full screen,
        // 2026-09-23) fills the display and refuses moves and sizes; treating that as a misplaced
        // window fell back and even tore the display down under the Space. Capture the display as
        // it is, cropped to the panel's aspect around its middle, where the app letterboxes its
        // content. Normal placement resumes when it leaves full screen (the catalog's next poll).
        // Only for a window that is already on this display: one that is full screen on a real
        // display cannot be moved here and must stream as the real window (the coordinator's
        // fallback), not as an empty virtual display.
        if let d = display,
           let live = WindowSizer.liveBounds(of: p.windowID), live.intersects(CGDisplayBounds(d.displayID)),
           windowCoversDisplay || WindowSizer.isFullScreen(p.element) {
            let bounds = CGDisplayBounds(d.displayID)
            var crop = Self.fullScreenCrop(in: bounds.size, panel: wanted)
            let outW = evenPixels(crop.width * captureScale), outH = evenPixels(crop.height * captureScale)
            crop.size = CGSize(width: CGFloat(outW) / captureScale, height: CGFloat(outH) / captureScale)
            captureRect = crop
            placedSize = bounds.size
            askedSize = wanted
            fullScreen = true
            Stats.shared.bump("vd.fullScreen")
            let fresh = await catalog.resolveWindow(id: p.windowID) ?? window
            // No releaseWindow here: a full-screen window cannot be put back mid-Space anyway.
            guard let scDisplay, let alive = display, alive.isAlive else { throw Failure.notListedBySCK }
            print("\(p.appName) — \(p.title) is full screen on virtual display \(alive.displayID); capturing \(Self.fmt(crop)) of it")
            let filter = fresh.owningApplication.map { SCContentFilter(display: scDisplay, including: [$0], exceptingWindows: []) }
                ?? SCContentFilter(display: scDisplay, including: [fresh])
            // The band is the display's width, twice the panel's: encode at the panel's size.
            let output = CGSize(width: min(crop.width, wanted.width), height: min(crop.height, wanted.height))
            return Prepared(filter: filter, sourceRect: crop,
                            describe: "\(p.appName) — \(p.title) full screen on virtual display \(alive.displayID)",
                            outputSize: output)
        }
        fullScreen = false

        // (5c) A window between Spaces (leaving full screen) is off every list for up to a second:
        // wait for it rather than call it gone and tear the stage down.
        if WindowSizer.liveBounds(of: p.windowID) == nil {
            let deadline = Date().addingTimeInterval(1.5)
            while Date() < deadline, WindowSizer.liveBounds(of: p.windowID) == nil {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard WindowSizer.liveBounds(of: p.windowID) != nil else { releaseWindow(); throw Failure.windowMissing }
        }

        // (6) Place the window; grow the display once if the app enforces a larger minimum.
        var live = CGRect.zero
        var displayBounds = CGRect.zero
        for attempt in 0..<2 {
            guard let d = display else { releaseWindow(); throw Failure.neverOnline }
            displayBounds = CGDisplayBounds(d.displayID)
            let usable = Self.usableArea(of: d.displayID) ?? displayBounds.divided(atDistance: menuInset, from: .minYEdge).remainder
            let dest = CGRect(origin: usable.origin,
                              size: CGSize(width: min(wanted.width, usable.width), height: min(wanted.height, usable.height)))
            let before = WindowSizer.liveBounds(of: p.windowID)
            if let before, Self.close(before, dest), Self.fraction(of: before, inside: displayBounds) >= 0.9 {
                live = before                                 // already there (encoder hang, keyframe restart): no flicker
            } else {
                if cursorBefore == nil { cursorBefore = CGEvent(source: nil)?.location }
                let t0 = Date()
                let err = sizer.move(p, to: dest)
                guard err == .success else {
                    releaseWindow()
                    throw Failure.moveRefused(err)
                }
                // Wait for the window server to show the move, no blind sleep: until the frame is at
                // `dest` or has stopped changing (an app that clamps settles somewhere else).
                var same = 0
                var last = before
                let deadline = Date().addingTimeInterval(0.5)
                while Date() < deadline {
                    let now = WindowSizer.liveBounds(of: p.windowID)
                    if let now, Self.close(now, dest) { last = now; break }
                    same = (now == last) ? same + 1 : 0
                    last = now
                    if same >= 3 { break }
                    try? await Task.sleep(for: .milliseconds(20))
                }
                guard let moved = last ?? WindowSizer.liveBounds(of: p.windowID) else {
                    releaseWindow()
                    throw Failure.windowMissing
                }
                live = moved
                print("Moved \(p.appName) — \(p.title) from \(Self.fmt(p.originalFrame)) to \(Self.fmt(live)) in \(Self.ms(since: t0)) ms (asked \(Self.fmt(dest)))")
            }
            let oversized = live.width > usable.width + 2 || live.height > usable.height + 2
            if oversized, attempt == 0 {
                // The app took a bigger size than asked (its minimum). Grow the display to it once;
                // the window lands on a real display for a moment while the display is recreated.
                print("\(p.appName) insists on \(Int(live.width))×\(Int(live.height)) pt (asked \(Int(wanted.width))×\(Int(wanted.height))); growing the virtual display.")
                do {
                    try await ensureDisplay(atLeast: live.size)
                } catch {
                    releaseWindow()      // the old display is already gone; the window server dumped the window
                    throw error
                }
                // ensureDisplay sent the window home and forgot it while the display was replaced.
                // Record it again before the second placement, or the next switch would leave it
                // on the virtual display and a later select would take that spot for its home.
                placement = p
                EmergencySnapshot.set((p.element, p.originalFrame))
                catalog.stagedWindowID = p.windowID
                continue
            }
            let inside = Self.fraction(of: live, inside: displayBounds)
            guard inside >= (oversized ? 0.5 : 0.9) else {
                releaseWindow()
                throw Failure.notOnDisplay(live)
            }
            break
        }

        // (7) Record the sizes and hand over.
        placedSize = live.size
        askedSize = wanted
        var crop = live.intersection(displayBounds).offsetBy(dx: -displayBounds.minX, dy: -displayBounds.minY)
        // Trim to whole, even output pixels so ScreenCaptureKit never resamples a fractional crop.
        let outW = evenPixels(crop.width * captureScale), outH = evenPixels(crop.height * captureScale)
        crop.size = CGSize(width: CGFloat(outW) / captureScale, height: CGFloat(outH) / captureScale)
        captureRect = crop
        Stats.shared.bump("vd.placed")

        let fresh = await catalog.resolveWindow(id: p.windowID) ?? window
        // The grow path may have replaced the display, so read `display` again here rather than
        // the one step (4) produced (that one is destroyed by then).
        guard let scDisplay, let d = display, d.isAlive else {
            releaseWindow()
            throw Failure.notListedBySCK
        }
        print("Capturing \(Self.fmt(crop)) of virtual display \(d.displayID) for \(p.appName) — \(p.title)")
        let describe = "\(p.appName) — \(p.title) on virtual display \(d.displayID) (\(d.widthPt)×\(d.heightPt) pt @\(d.scale)×)"
        // The whole app on this display, not just the window: menus, popovers, sheets and tooltips
        // are their own windows and were missing from the stream (Messages' filter popover,
        // 2026-09-23). Nothing else lives on the virtual display, so this shows exactly the app.
        // Whatever lies outside the window's rectangle is still cut by the crop.
        let filter = fresh.owningApplication.map { SCContentFilter(display: scDisplay, including: [$0], exceptingWindows: []) }
            ?? SCContentFilter(display: scDisplay, including: [fresh])
        return Prepared(filter: filter, sourceRect: crop, describe: describe)
    }

    /// The refresh rate the next display is made at; see `prepare`.
    private var refreshHz = 60

    /// Reuses the current display if `env` fits below its menu bar and its refresh rate matches,
    /// else (re)creates it, waits for it to come online at 2×, measures the menu bar once, and
    /// waits for ScreenCaptureKit to list it. A recreate never shrinks below the current display,
    /// so one grown to an app's minimum is not grown a second time after a rate change. Throws
    /// with the display destroyed if it never came up or SCK never saw it.
    private func ensureDisplay(atLeast env: CGSize) async throws {
        var env = Self.clamp(env)
        env.height = min(env.height, Self.maxSide - menuInset)   // the menu bar counts toward the 8192 px ceiling
        if let d = display, d.isAlive, scDisplay != nil, Int(d.refreshHz) == refreshHz,
           CGFloat(d.widthPt) >= env.width, CGFloat(d.heightPt) - menuInset >= env.height {
            Stats.shared.bump("vd.reused")
            return
        }
        if let d = display {
            env = Self.clamp(CGSize(width: max(env.width, CGFloat(d.widthPt)), height: max(env.height, CGFloat(d.heightPt) - menuInset)))
        }
        // Recreating under a staged window (rate change, envelope grew) would let the window server
        // dump it anywhere on a real display until the new one is up: send it home first. prepare
        // re-records the placement and re-places the window once the new display is listed.
        if placement != nil { releaseWindow() }
        destroyDisplay()

        let t0 = Date()
        let d: VirtualDisplay
        do {
            d = try VirtualDisplay(name: "Sill", widthPt: Int(env.width), heightPt: Int(env.height + menuInset), scale: 2,
                                   refreshHz: Double(refreshHz), vendorID: Self.vendorID, productID: Self.productID, serialNum: Self.serialNum)
        } catch {
            creationFailures += 1
            if creationFailures >= 2 { disabledReason = "creating the display failed \(creationFailures) times (\(error))" }
            throw Failure.displayCreate(error)
        }
        creationFailures = 0
        generation += 1
        let gen = generation
        display = d
        let created = Self.ms(since: t0)
        // Fires on the display's private queue; the stage lives on the main actor.
        d.onTerminated = { [weak self] in Task { @MainActor [weak self] in self?.lost(generation: gen) } }

        let online = await d.waitUntilOnline(timeout: 3)
        let onlineMs = Self.ms(since: t0)
        if !online {
            if d.bounds.width == 0 {
                destroyDisplay()
                throw Failure.neverOnline
            }
            // Up, but not at the requested mode: occlusion-free beats crisp. "Capture started …
            // scale 1.0" in the log gives it away.
            print("Virtual display is online but not at \(d.widthPt)×\(d.heightPt) @2×: backing \(d.pixelSize.width)×\(d.pixelSize.height) px. Modes: \(d.availableModes().joined(separator: "; "))")
        }

        // The menu bar: AppKit learns the new screen through the run loop, usually within a frame.
        if !insetMeasured {
            let deadline = Date().addingTimeInterval(1)
            while Self.screen(for: d.displayID) == nil, Date() < deadline { try? await Task.sleep(for: .milliseconds(50)) }
            if let s = Self.screen(for: d.displayID) {
                let measured = s.frame.maxY - s.visibleFrame.maxY
                let guessed = menuInset
                insetMeasured = true
                menuInset = measured
                if CGFloat(d.heightPt) - measured < env.height {
                    // Guessed too small: once more with the measured bar, so the window fits.
                    print("Virtual display menu bar is \(Int(measured)) pt, not \(Int(guessed)); recreating the display to fit.")
                    return try await ensureDisplay(atLeast: env)
                }
            }
        }

        // ScreenCaptureKit lists new displays a little after CoreGraphics does. Bounded: without
        // Screen Recording this call has been seen to never return while a virtual display exists.
        let t1 = Date()
        var listed: SCDisplay?
        while Date().timeIntervalSince(t1) < 3 {
            let remaining = max(0.2, 3 - Date().timeIntervalSince(t1))
            if let c = await WindowCatalog.shareableContent(excludingDesktopWindows: true, onScreenWindowsOnly: true, timeout: remaining),
               let found = c.displays.first(where: { $0.displayID == d.displayID }) { listed = found; break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let listed, display === d else {
            destroyDisplay()
            throw Failure.notListedBySCK
        }
        scDisplay = listed
        Stats.shared.bump("vd.created")
        print("Virtual display \(d.widthPt)×\(d.heightPt) pt @2× id \(d.displayID): created \(created) ms, online \(onlineMs) ms, "
              + "listed by ScreenCaptureKit after \(Self.ms(since: t1)) ms, menu bar \(Int(menuInset)) pt\(insetMeasured ? "" : " (assumed)")")
    }

    /// A full-screen window cannot be put back where it was: take it out of full screen first and
    /// wait (bounded) for it to be a normal window again. For the switch and deselect paths; the
    /// synchronous teardowns (Ctrl-C) cannot wait and let the window server place the window.
    func leaveFullScreenIfNeeded() async {
        guard let p = placement, WindowSizer.isFullScreen(p.element) else { return }
        _ = WindowSizer.perform(.fullScreen, element: p.element)
        let deadline = Date().addingTimeInterval(2.0)
        while Date() < deadline {
            if !WindowSizer.isFullScreen(p.element), WindowSizer.liveBounds(of: p.windowID) != nil { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        fullScreen = false
    }

    // MARK: Teardown (synchronous, idempotent; the signal handler calls these)

    /// Puts the staged window back where it was and forgets it. The display stays.
    func releaseWindow() {
        if let p = placement {
            let ok = sizer.restore(p)
            print(ok ? "Restored \(p.appName) — \(p.title) to \(Self.fmt(p.originalFrame))"
                     : "Could not restore \(p.appName) — \(p.title) to \(Self.fmt(p.originalFrame)); it is on a real display but not where it was")
            Stats.shared.bump("vd.restored")
        }
        // The Mac cursor followed the device onto the virtual display: bring it back where it was
        // (or to the middle of the main display) so it is not stranded on a screen about to vanish.
        if let d = display, d.isAlive, let here = CGEvent(source: nil)?.location, CGDisplayBounds(d.displayID).contains(here) {
            let main = CGDisplayBounds(CGMainDisplayID())
            CGWarpMouseCursorPosition(cursorBefore ?? CGPoint(x: main.midX, y: main.midY))
        }
        cursorBefore = nil
        fullScreen = false
        placement = nil
        placedSize = nil
        askedSize = nil
        captureRect = .zero
        catalog.stagedWindowID = nil
        EmergencySnapshot.set(nil)
    }

    /// Removes the display. Call `releaseWindow()` first while both displays exist, so the window
    /// goes exactly where it was instead of wherever the window server dumps it.
    func destroyDisplay() {
        if let d = display {
            let id = d.displayID
            display = nil
            scDisplay = nil
            d.destroy()
            print("Removed virtual display \(id)")
        }
        display = nil
        scDisplay = nil
    }

    /// Window home, then display gone.
    func release() {
        releaseWindow()
        destroyDisplay()
    }

    /// The window server tore the display down (sleep, another display arriving). The object is
    /// dead; the window is already on some real display, so put it where it belongs.
    private func lost(generation gen: Int) {
        guard gen == generation, display != nil else { return }   // destroy() may fire this too; ignore our own
        display = nil
        scDisplay = nil
        releaseWindow()
        Stats.shared.bump("vd.lost")
        onLost?()
    }

    /// Last resort from `atexit`, on any thread, with no main-actor state: the window's element and
    /// original frame were snapshotted when it was placed. The display dies with the process.
    nonisolated static func emergencyRestore() {
        guard let snapshot = EmergencySnapshot.take() else { return }
        let (element, frame) = snapshot
        var origin = frame.origin, size = frame.size
        guard let pos = AXValueCreate(.cgPoint, &origin), let sz = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, pos)
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sz)
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, pos)
    }
}

/// The staged window's way home, readable from any thread at exit. Not on the main actor on
/// purpose: `atexit` handlers run wherever `exit` was called.
private enum EmergencySnapshot {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var value: (AXUIElement, CGRect)?

    static func set(_ v: (AXUIElement, CGRect)?) { lock.lock(); value = v; lock.unlock() }
    static func take() -> (AXUIElement, CGRect)? { lock.lock(); defer { value = nil; lock.unlock() }; return value }
}
