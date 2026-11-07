import Foundation
import AppKit
import CoreGraphics
import ScreenCaptureKit
import StreamProtocol

/// The Desktop in full screen (`Viewport.deviceDesktop`): a virtual display at the device's own
/// size, made the Mac's main display while it streams, as Screen Sharing's High Performance mode
/// does. The menu bar and the Dock move onto it, so the device shows a whole Mac desktop edge to
/// edge at its own resolution instead of the real screen fitted with black bars.
///
/// Geometry: the display is the device's screen in device points divided by its text scale (Aa;
/// none means 1:1), at 2× HiDPI, grown evenly to the private API's least 320×240 pt.
///
/// The Mac's own screens, as High Performance screen sharing leaves the host's: while it lives, every
/// window on another display is moved onto it (through Accessibility, as the window stage moves one;
/// each goes back to where it was with `release`), and every other display (Sill's window stage aside)
/// is covered by a black window of Sill's at the shielding level (`Curtain`, as Apple Remote
/// Desktop's curtain), so the Mac shows nothing and takes no click while the device has it. No
/// mirror: mirroring the Mac's screens (a 5K one among them) cost the stream its rate, and a mirror
/// ignores its gamma. The curtain is Sill's own window, which no capture of Sill's takes, and it goes
/// with the process.
///
/// Lifetime: created when the Desktop starts with the flag on, recreated when the wanted size
/// changes (a rotation, an Aa step), removed when anything else streams, the flag goes off, the
/// last device leaves or the host quits. Before it goes, the display that was main becomes main
/// again; the window server then moves the windows that were on it back to a real display.
///
/// Main actor throughout, like the coordinator. Uses the same private API as `VirtualStage`, with
/// the same vendor (so the app keeps its own windows off it) and a product ID of its own (so macOS
/// remembers its arrangement apart from the window stage's).
@MainActor
final class DeviceDesktop {
    static let productID: UInt32 = 0x0002, serialNum: UInt32 = 1

    enum Failure: Error, CustomStringConvertible {
        case displayCreate(Error)
        case neverOnline
        case notListedBySCK

        var description: String {
            switch self {
            case .displayCreate(let e): return "displayCreate: \(e)"
            case .neverOnline: return "neverOnline (the device's display never came up)"
            case .notListedBySCK: return "notListedBySCK (ScreenCaptureKit never listed the device's display)"
            }
        }
    }

    private var display: VirtualDisplay?
    private(set) var scDisplay: SCDisplay?
    /// The display that was main before this one took over, to give the role back.
    private var previousMain: CGDirectDisplayID?
    /// The windows moved onto it, each with its way back.
    private var gathered: [WindowSizer.Placement] = []
    /// The black windows over the Mac's own displays.
    private var curtains: [NSWindow] = []
    /// What moves the windows (the coordinator's), and the windows on screen now (its catalog, looked
    /// at again). Without them, nothing is moved.
    var sizer: WindowSizer?
    var windowsOnScreen: (() async -> [SCWindow])?
    private var generation = 0
    /// The window server took the display away on its own: the coordinator restarts the Desktop.
    var onLost: (() -> Void)?

    var isLive: Bool { display?.isAlive == true && scDisplay != nil }
    var displayID: CGDirectDisplayID? { display?.displayID }
    /// The display in CG global points (top-left origin), for input and the pointer.
    var frame: CGRect? { display.map { CGDisplayBounds($0.displayID) } }
    /// The display's size in points.
    var size: CGSize? { display.map { CGSize(width: $0.widthPt, height: $0.heightPt) } }

    /// The display's size for a viewport: the panel in Mac points, even, at least 320×240.
    static func wantedSize(for v: Viewport) -> CGSize? {
        guard v.width > 0, v.height > 0 else { return nil }
        let scale = (v.scale ?? 1) > 0 ? (v.scale ?? 1) : 1
        var w = v.width / scale, h = v.height / scale
        let grow = max(1, 320 / w, 240 / h)
        w *= grow; h *= grow
        func even(_ x: Double) -> CGFloat { CGFloat(min(8192, max(2, (x / 2).rounded() * 2))) }
        return CGSize(width: even(w), height: even(h))
    }

    /// Whether the live display already is `size` at `refreshHz`.
    func matches(size: CGSize, refreshHz: Int) -> Bool {
        guard isLive, let d = display else { return false }
        return d.widthPt == Int(size.width) && d.heightPt == Int(size.height) && Int(d.refreshHz) == refreshHz
    }

    /// A display of `size` points, online, main, and listed by ScreenCaptureKit.
    func ensure(size: CGSize, refreshHz: Int) async throws -> SCDisplay {
        if matches(size: size, refreshHz: refreshHz), let sc = scDisplay { return sc }
        release()

        let t0 = Date()
        let d: VirtualDisplay
        do {
            d = try VirtualDisplay(name: "Sill Desktop", widthPt: Int(size.width), heightPt: Int(size.height), scale: 2,
                                   refreshHz: Double(refreshHz), vendorID: VirtualStage.vendorID,
                                   productID: Self.productID, serialNum: Self.serialNum)
        } catch {
            throw Failure.displayCreate(error)
        }
        generation += 1
        let gen = generation
        display = d
        d.onTerminated = { [weak self] in Task { @MainActor [weak self] in self?.lost(generation: gen) } }

        let online = await d.waitUntilOnline(timeout: 3)
        if !online {
            if d.bounds.width == 0 { release(); throw Failure.neverOnline }
            print("Device desktop is online but not at \(d.widthPt)×\(d.heightPt) @2×: backing \(d.pixelSize.width)×\(d.pixelSize.height) px.")
        }
        makeMain(d.displayID)

        // ScreenCaptureKit lists new displays a little after CoreGraphics does (see VirtualStage).
        let t1 = Date()
        var listed: SCDisplay?
        while Date().timeIntervalSince(t1) < 3 {
            let remaining = max(0.2, 3 - Date().timeIntervalSince(t1))
            if let c = await WindowCatalog.shareableContent(excludingDesktopWindows: false, onScreenWindowsOnly: true, timeout: remaining),
               let found = c.displays.first(where: { $0.displayID == d.displayID }) { listed = found; break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let listed, display === d else { release(); throw Failure.notListedBySCK }
        scDisplay = listed
        await gatherWindows(onto: d.displayID)
        guard display === d else { release(); throw Failure.notListedBySCK }
        drawCurtains(except: d.displayID)
        Stats.shared.bump("dd.created")
        print("Device desktop \(d.widthPt)×\(d.heightPt) pt @2× id \(d.displayID): main, ready after \(Int(Date().timeIntervalSince(t0) * 1000)) ms")
        return listed
    }

    /// The main display's role back to the one that had it, then the display gone. Idempotent.
    func release() {
        guard let d = display else { scDisplay = nil; return }
        let id = d.displayID
        liftCurtains()
        returnWindows()
        if let previous = previousMain, previous != id, CGMainDisplayID() == id { makeMain(previous) }
        previousMain = nil
        display = nil
        scDisplay = nil
        d.destroy()
        print("Removed device desktop \(id)")
    }

    /// Makes `id` the main display: the main display is the one at the global origin, so it moves
    /// there and every other display moves by the same amount, keeping the arrangement.
    private func makeMain(_ id: CGDirectDisplayID) {
        let main = CGMainDisplayID()
        guard main != id else { return }
        if display?.displayID == id, previousMain == nil { previousMain = main }
        let shift = CGDisplayBounds(id).origin
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return }
        for other in ids.prefix(Int(count)) {
            let o = CGDisplayBounds(other).origin
            CGConfigureDisplayOrigin(config, other, Int32(o.x - shift.x), Int32(o.y - shift.y))
        }
        if CGCompleteDisplayConfiguration(config, .forSession) != .success {
            print("Device desktop: could not make display \(id) the main display.")
        }
    }

    /// Every window on another display (not Sill's window stage) onto `id`, at its size where that
    /// fits, else fitted, at the place it had on its own display as far as that fits too. A window in
    /// full screen stays (it refuses moves).
    private func gatherWindows(onto id: CGDirectDisplayID) async {
        guard let sizer, let windowsOnScreen else { print("Device desktop: no window mover; windows stay where they are."); return }
        // AppKit learns the new screen (its menu bar) through the run loop, usually within a frame.
        let deadline = Date().addingTimeInterval(1)
        while VirtualStage.screen(for: id) == nil, Date() < deadline { try? await Task.sleep(for: .milliseconds(50)) }
        let target = CGDisplayBounds(id)
        guard let area = WindowSizer.visibleArea(around: target), area.intersects(target) else {
            print("Device desktop: AppKit does not know its screen yet (\(NSScreen.screens.count) screens); windows stay where they are.")
            return
        }
        let displays = WindowSizer.displayFrames()
        var moved = 0, skipped = 0
        for w in await windowsOnScreen() {
            guard display?.displayID == id else { return }
            let frame = WindowSizer.liveBounds(of: w.windowID) ?? w.frame
            let center = CGPoint(x: frame.midX, y: frame.midY)
            guard !target.contains(center),
                  let home = displays.first(where: { $0.contains(center) }) ?? displays.first(where: { $0.intersects(frame) }),
                  let source = Self.displayID(at: home), CGDisplayVendorNumber(source) != VirtualStage.vendorID,
                  let p = sizer.placement(for: w), !WindowSizer.isFullScreen(p.element) else { skipped += 1; continue }
            let size = CGSize(width: min(frame.width, area.width), height: min(frame.height, area.height))
            // Its place on its own display, as a fraction of the room it had there, kept inside the area.
            let roomX = max(1, home.width - frame.width), roomY = max(1, home.height - frame.height)
            let fx = min(1, max(0, (frame.minX - home.minX) / roomX)), fy = min(1, max(0, (frame.minY - home.minY) / roomY))
            let origin = CGPoint(x: (area.minX + fx * (area.width - size.width)).rounded(),
                                 y: (area.minY + fy * (area.height - size.height)).rounded())
            sizer.move(p, to: CGRect(origin: origin, size: size))
            gathered.append(p)
            moved += 1
        }
        print("Device desktop: \(moved) window\(moved == 1 ? "" : "s") moved onto it; \(skipped) left (on it already, in full screen or not matched).")
    }

    /// The active display whose bounds are `rect`.
    private static func displayID(at rect: CGRect) -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return nil }
        return ids.prefix(Int(count)).first { CGDisplayBounds($0) == rect }
    }

    /// Every window gathered back where it was. Before the main role goes back: the frames are in the
    /// arrangement they were read in.
    private func returnWindows() {
        guard let sizer, !gathered.isEmpty else { gathered = []; return }
        let count = gathered.count
        for p in gathered { sizer.restore(p) }
        gathered = []
        print("Device desktop: \(count) window\(count == 1 ? "" : "s") back on the Mac's own screens.")
    }

    /// A black window of Sill's over each of the Mac's own displays: nothing to see, nothing to click.
    private func drawCurtains(except id: CGDirectDisplayID) {
        liftCurtains()
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                  number != id, CGDisplayVendorNumber(number) != VirtualStage.vendorID else { continue }
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
            w.setFrame(screen.frame, display: false)
            w.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
            w.backgroundColor = .black
            w.isOpaque = true
            w.hasShadow = false
            w.isReleasedWhenClosed = false
            w.ignoresMouseEvents = false
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            let label = NSTextField(labelWithString: "This Mac is in use on a device.")
            label.textColor = NSColor(white: 0.35, alpha: 1)
            label.font = .systemFont(ofSize: 15)
            label.translatesAutoresizingMaskIntoConstraints = false
            let content = NSView()
            content.addSubview(label)
            NSLayoutConstraint.activate([label.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                                         label.centerYAnchor.constraint(equalTo: content.centerYAnchor)])
            w.contentView = content
            w.orderFrontRegardless()
            curtains.append(w)
        }
        print("Device desktop: \(NSScreen.screens.count) screens known to AppKit, \(curtains.count) covered.")
        if !curtains.isEmpty {
            print("Device desktop: the Mac's own \(curtains.count == 1 ? "screen is" : "\(curtains.count) screens are") dark while it streams.")
        }
    }

    private func liftCurtains() {
        for w in curtains { w.orderOut(nil); w.close() }
        curtains = []
    }

    private func lost(generation gen: Int) {
        guard gen == generation, display != nil else { return }
        liftCurtains()
        returnWindows()
        display = nil
        scDisplay = nil
        previousMain = nil
        Stats.shared.bump("dd.lost")
        onLost?()
    }
}
