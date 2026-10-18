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
        Stats.shared.bump("dd.created")
        print("Device desktop \(d.widthPt)×\(d.heightPt) pt @2× id \(d.displayID): main, ready after \(Int(Date().timeIntervalSince(t0) * 1000)) ms")
        return listed
    }

    /// The main display's role back to the one that had it, then the display gone. Idempotent.
    func release() {
        guard let d = display else { scDisplay = nil; return }
        let id = d.displayID
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

    private func lost(generation gen: Int) {
        guard gen == generation, display != nil else { return }
        display = nil
        scDisplay = nil
        previousMain = nil
        Stats.shared.bump("dd.lost")
        onLost?()
    }
}
