// TEST ONLY. The modes probe: P2 of docs/virtual-desktop-plan.md (as revised 2026-11-18), phase 2b's first commit. Can
// Sill's Desktop display take a device's turn (its room the other way round) without being removed and made again?
// Compiled with Sources/SillHost/VirtualDisplay.swift by run.sh (see there for the refusals and the usage).
//
// Without --make (the dry run, what an agent runs): nothing is made, shown, moved or posted. It checks the private API's
// surface (class and method lookups only: no display), and prints the modes it would make, their backing, the steps and
// what each would measure. Exit 0 when the surface is there, 1 when not.
//
// With --make (Noah's, on a Mac at rest: Sill quit, nothing streaming, no device connected): it makes one display,
// "Sill Probe" (vendor 0x5111, product 0x0002, Sill's Desktop identity, but serial 0xF00D, so macOS remembers nothing for
// Sill's own display), with two modes, the room both ways (1376x1032 and 1032x1376 by default: an iPad Pro 13-inch
// sideways and upright), at 2x and the rate given; puts a window of its own on it (no other app's window is touched);
// then, each change timed and every reconfiguration callback logged with its flags:
//   1. switches to the turned mode with public CGConfigureDisplayWithDisplayMode (VirtualDisplay.switchMode), and back;
//   2. gives the live display a third mode with applySettings: again (VirtualDisplay.applyModes), smaller than the
//      backing it was made with, and switches to it, and back;
//   3. gives it a mode larger than that backing, and switches to it;
//   4. removes the display.
// After each: the display's ID (the same, or a new one), its bounds and backing, whether the callback called it a mode
// change (setMode) or a removal and an addition, and where the probe's window is (on the display, or moved off it).
// It ends with one verdict line for each way ("P2 in place …"). It never moves the pointer, posts no event, never
// activates (accessory app), and links no VideoToolbox. Exit 0 when it ran to the end, whatever macOS answered; 1 when
// the display could not be made; 2 for a bad argument.
import AppKit
import CoreGraphics
import Foundation

// MARK: Arguments

let args = Array(CommandLine.arguments.dropFirst())
let make = args.contains("--make")
func sizeArg(_ s: String) -> VirtualDisplay.ModeSize? {
    let p = s.lowercased().split(separator: "x")
    guard p.count == 2, let w = Int(p[0]), let h = Int(p[1]), w > 0, h > 0 else { return nil }
    return VirtualDisplay.ModeSize(width: w, height: h)
}
for a in args where a != "--make" && sizeArg(a) == nil && Int(a) == nil {
    print("display-modes-probe: unknown argument \(a) (usage: probe [--make] [WxH] [HZ])"); exit(2)
}
let room = args.lazy.compactMap(sizeArg).first ?? VirtualDisplay.ModeSize(width: 1376, height: 1032)
let hz = Double(args.lazy.compactMap { Int($0) }.first ?? 60)
guard room.width >= 320, room.height >= 320, room.width <= 4096, room.height <= 4096, hz >= 24, hz <= 240 else {
    print("display-modes-probe: the room must be 320…4096 points a side and the rate 24…240 Hz"); exit(2)
}

// The modes: the room, the room turned (a device held the other way), a third one smaller than the backing for the
// new-modes way (90 %, even), and one larger than the backing (125 % of the longer side, both ways).
let turned = room.turned
func even(_ v: Double) -> Int { Int((v / 2).rounded()) * 2 }
let smaller = VirtualDisplay.ModeSize(width: even(Double(room.width) * 0.9), height: even(Double(room.height) * 0.9))
let longer = max(room.width, room.height)
let larger = VirtualDisplay.ModeSize(width: even(Double(longer) * 1.25), height: even(Double(longer) * 1.25))
let madeWith = VirtualDisplay.modeList(asked: room, others: [turned])
let backing = VirtualDisplay.maxPixels(madeWith, scale: 2)
let identity = (vendor: UInt32(0x5111), product: UInt32(0x0002), serial: UInt32(0xF00D))

print("Display modes probe (P2), macOS \(ProcessInfo.processInfo.operatingSystemVersionString)\(make ? "" : ": the dry run, nothing made")")
let problems = VirtualDisplay.checkPrivateAPI()
if problems.isEmpty {
    print("  private API: all \(VirtualDisplay.privateAPISurface.count) selectors present (looked up only)")
} else {
    for p in problems { print("  FAIL \(p)") }
}
print("  the display: \"Sill Probe\", vendor 0x5111, product 0x0002 (Sill's Desktop identity), serial 0xF00D (not Sill's own), 2x, \(Int(hz)) Hz")
print("  made with \(madeWith.count) modes: \(madeWith.map(\.description).joined(separator: " and ")) pt; backing \(backing.wide)×\(backing.high) px")
print("  step 1: switch to \(turned) pt in place (CGConfigureDisplayWithDisplayMode), then back to \(room)")
print("  step 2: applySettings: again with \(room), \(turned) and \(smaller) pt (inside the backing); switch to \(smaller), then back")
print("  step 3: applySettings: again with \(room) and \(larger) pt (\(larger.width * 2)×\(larger.height * 2) px, beyond the backing); switch to \(larger)")
print("  step 4: remove it")
print("  after each: the ID, the bounds and backing, the reconfiguration callback's flags, where the probe's own window is")
guard make else {
    print("  dry run: nothing made. Noah, on a Mac at rest (Sill quit, no device connected): Scripts/display-modes-probe/run.sh --make\(room == VirtualDisplay.ModeSize(width: 1376, height: 1032) ? "" : " \(room)")\(hz == 60 ? "" : " \(Int(hz))")")
    exit(problems.isEmpty ? 0 : 1)
}
guard problems.isEmpty else { exit(1) }

// MARK: The real run (--make)

/// The reconfiguration callback's lines, as they come (main thread, through the AppKit event port).
final class Changes: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    private let t0 = Date()
    func add(_ id: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags) {
        var words: [String] = []
        let named: [(CGDisplayChangeSummaryFlags, String)] = [
            (.beginConfigurationFlag, "begin"), (.movedFlag, "moved"), (.setMainFlag, "setMain"), (.setModeFlag, "setMode"),
            (.addFlag, "add"), (.removeFlag, "remove"), (.enabledFlag, "enabled"), (.disabledFlag, "disabled"),
            (.mirrorFlag, "mirror"), (.unMirrorFlag, "unMirror"), (.desktopShapeChangedFlag, "desktopShapeChanged"),
        ]
        for (f, w) in named where flags.contains(f) { words.append(w) }
        let line = String(format: "%.3f s: id %u %@", Date().timeIntervalSince(t0), id, words.joined(separator: ","))
        lock.lock(); lines.append(line); lock.unlock()
    }
    func take() -> [String] { lock.lock(); defer { lines = []; lock.unlock() }; return lines }
}
let changes = Changes()
CGDisplayRegisterReconfigurationCallback({ id, flags, context in
    guard let context else { return }
    Unmanaged<Changes>.fromOpaque(context).takeUnretainedValue().add(id, flags)
}, Unmanaged.passUnretained(changes).toOpaque())

func screen(_ id: CGDirectDisplayID) -> NSScreen? {
    NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == id }
}
func ms(_ t: Date) -> Int { Int(Date().timeIntervalSince(t) * 1000) }
func online() -> [CGDirectDisplayID] {
    var n: UInt32 = 0
    CGGetOnlineDisplayList(0, nil, &n)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(n))
    CGGetOnlineDisplayList(n, &ids, &n)
    return Array(ids.prefix(Int(n)))
}

@MainActor
func run() async -> Int32 {
    let before = online()
    print("  displays before: \(before)")
    let t0 = Date()
    let d: VirtualDisplay
    do {
        d = try VirtualDisplay(name: "Sill Probe", widthPt: room.width, heightPt: room.height, scale: 2, refreshHz: hz,
                               vendorID: identity.vendor, productID: identity.product, serialNum: identity.serial,
                               otherModes: [turned])
    } catch {
        print("  FAIL make: \(error)")
        return 1
    }
    let id = d.displayID
    let up = await d.waitUntilOnline(timeout: 3)
    print("  made id \(id) in \(ms(t0)) ms; at \(room) @2×: \(up); \(state(d))")
    let modes = d.availableModes()
    print("  macOS lists \(modes.count) modes: \(modes.joined(separator: "; "))")
    for c in changes.take() { print("    callback \(c)") }

    // A window of the probe's own, on the display (no other app's window is touched).
    let deadline = Date().addingTimeInterval(1)
    while screen(id) == nil, Date() < deadline { try? await Task.sleep(for: .milliseconds(50)) }
    var window: NSWindow?
    if let s = screen(id) {
        let w = NSWindow(contentRect: NSRect(x: s.frame.midX - 240, y: s.frame.midY - 160, width: 480, height: 320),
                         styleMask: [.titled], backing: .buffered, defer: false)
        w.title = "Sill modes probe"
        w.isReleasedWhenClosed = false
        w.orderFrontRegardless()
        window = w
        try? await Task.sleep(for: .milliseconds(300))
        print("  the probe's window: \(whereIs(window, id))")
    } else {
        print("  NSScreen never listed the display within 1 s: no window put on it")
    }

    // Step 1: the modes listed at creation, switched in place.
    let inPlace = await change("step 1: switch to \(turned)", d, id, window, want: turned) { d.switchMode(to: turned) }
    let back = await change("step 1: back to \(room)", d, id, window, want: room) { d.switchMode(to: room) }

    // Step 2: new modes on the live display, inside its backing.
    var applied = false
    do { applied = try d.applyModes([room, turned, smaller]) } catch { print("  step 2: applySettings: threw \(error)") }
    print("  step 2: applySettings: with \(smaller) answered \(applied ? "YES" : "NO"); \(state(d))")
    for c in changes.take() { print("    callback \(c)") }
    var newModes = false
    if applied {
        print("  macOS lists now: \(d.availableModes().joined(separator: "; "))")
        newModes = await change("step 2: switch to \(smaller)", d, id, window, want: smaller) { d.switchMode(to: smaller) }
        _ = await change("step 2: back to \(room)", d, id, window, want: room) { d.switchMode(to: room) }
    }

    // Step 3: a mode beyond the backing it was made with.
    var largerApplied = false
    do { largerApplied = try d.applyModes([room, larger]) } catch { print("  step 3: applySettings: threw \(error)") }
    print("  step 3: applySettings: with \(larger) answered \(largerApplied ? "YES" : "NO"); \(state(d))")
    for c in changes.take() { print("    callback \(c)") }
    var largerTaken = false
    if largerApplied {
        largerTaken = await change("step 3: switch to \(larger)", d, id, window, want: larger) { d.switchMode(to: larger) }
    }

    // Step 4: removed.
    window?.close()
    let t4 = Date()
    d.destroy()
    while online().contains(id), Date().timeIntervalSince(t4) < 3 { try? await Task.sleep(for: .milliseconds(50)) }
    try? await Task.sleep(for: .milliseconds(200))
    print("  step 4: removed; gone from the online list after \(ms(t4)) ms: \(!online().contains(id)); displays after: \(online())")
    for c in changes.take() { print("    callback \(c)") }

    print("P2 in place by the modes listed at creation: \(inPlace && back ? "yes" : "no")")
    print("P2 new modes on the live display (applySettings: again, inside its backing): \(applied && newModes ? "yes" : "no")")
    print("P2 a mode beyond the backing it was made with: \(largerApplied ? (largerTaken ? "taken" : "listed, not taken") : "refused")")
    return 0
}

/// One change, timed: the call's answer, whether the display reads `want` within 3 s, its ID and state, the callbacks
/// since the last step and where the probe's window is half a second later.
@MainActor
func change(_ what: String, _ d: VirtualDisplay, _ id: CGDirectDisplayID, _ window: NSWindow?,
            want: VirtualDisplay.ModeSize, _ call: () -> Bool) async -> Bool {
    let t = Date()
    let answered = call()
    let took = await d.waitUntilOnline(timeout: 3)
    let tookMs = ms(t)
    try? await Task.sleep(for: .milliseconds(500))
    let sameID = d.displayID == id && online().contains(id)
    print("  \(what): answered \(answered), at \(want) after \(tookMs) ms: \(took); the same ID \(id) online: \(sameID); \(state(d))")
    for c in changes.take() { print("    callback \(c)") }
    print("    the probe's window: \(whereIs(window, id))")
    return answered && took && sameID
}

func state(_ d: VirtualDisplay) -> String {
    let b = d.bounds, px = d.pixelSize
    let rate = CGDisplayCopyDisplayMode(d.displayID).map { "\(Int($0.refreshRate.rounded())) Hz" } ?? "no mode"
    return "bounds \(Int(b.minX)),\(Int(b.minY)) \(Int(b.width))×\(Int(b.height)) pt, backing \(px.width)×\(px.height) px @\(d.currentScale)×, \(rate), main \(CGMainDisplayID() == d.displayID)"
}

@MainActor
func whereIs(_ window: NSWindow?, _ id: CGDirectDisplayID) -> String {
    guard let window else { return "none" }
    let f = window.frame
    let on = window.screen.flatMap { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID }
    return "frame \(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))×\(Int(f.height)) (AppKit), on display \(on.map(String.init) ?? "none")\(on == id ? " (the probe's)" : " (moved off it)")"
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
Task { @MainActor in
    let code = await run()
    exit(code)
}
app.run()
