// TEST ONLY. Probe P3 (2026-11-25; docs/steps/2026-11-18-virtual-desktop-2b.md, sixth part): what macOS does with the
// Virtual Desktop an iPhone gets pixel for pixel (Noah, 2026-11-24: "middle one for iPhones"). No display narrower than
// 744 points had ever been made on Noah's Mac (P1: 1133×744 at 2x), and the stage's history says macOS ran a display
// with both sides under 800 points at 1x (754×784 came up at 800×832). So this makes, one at a time, the sizes an
// iPhone 15 Pro gets (393×852 points at 3x, 1179×2556 pixels), each for a few seconds, reads back what macOS made of it
// (its points, its pixels a point, its pixels, its rate, its menu bar and the room under it), and removes it:
//   1. upright with Full Screen, 589×1189 at 120 Hz, made as the Virtual Desktop is (a 4096-pixel square backing), then
//      followed in place the Virtual Desktop's way (applySettings: with the size alone, and a CoreGraphics switch where
//      macOS lands a turn at 1x first): on its side with Full Screen 1101×589, its controls showing 1077×448, upright with
//      its controls 800×499 (the 16:10 pane grown: Sill's default 1), and back to 589×1189;
//   2. the 16:10 pane pixel for pixel, 565×352 (both sides under 800: what the bend avoids), made as it is;
//   3. on its side with its controls, 1077×448, made as it is;
//   4. upright with its controls grown, 800×499, made as it is.
// Each case's last line is its verdict, "P3 …: kept at 2x: yes|no (…)". Sill makes the size that works instead (the
// 800-point floor) wherever macOS does not keep one, and says so in one line; this says whether it ever will.
//
// The display is "Sill Probe", Sill's Desktop identity with a serial of its own (0xF00D), so macOS remembers nothing for
// Sill's own display. Nothing else is made, moved, posted or captured: no window, no pointer, no ScreenCaptureKit, no
// VideoToolbox. Compiled with Sources/SillHost/VirtualDisplay.swift alone (run.sh); the real run is Noah's, from
// Terminal.app, with Sill quit and no device connected.
//
//   probe-phone --dry-run            the plan and the private API's surface (looked up, no display): an agent's
//   probe-phone --make [--case N]    the real run (run.sh starts it), or one case of it
import AppKit
import CoreGraphics
import Foundation

struct Step { let label: String; let w: Int; let h: Int }
struct Case { let label: String; let w: Int; let h: Int; let hz: Double; let steps: [Step] }

let cases: [Case] = [
    Case(label: "upright with Full Screen (393×793 pt, 1179×2379 px)", w: 589, h: 1189, hz: 120, steps: [
        Step(label: "on its side with Full Screen (734×393 pt)", w: 1101, h: 589),
        Step(label: "on its side, its controls showing (718×299 pt)", w: 1077, h: 448),
        Step(label: "upright, its controls showing, the 16:10 pane grown (377×235 pt)", w: 800, h: 499),
        Step(label: "upright with Full Screen again", w: 589, h: 1189),
    ]),
    Case(label: "the 16:10 pane over its controls pixel for pixel (377×235 pt, 1131×705 px; both sides under 800)", w: 565, h: 352, hz: 120, steps: []),
    Case(label: "on its side, its controls showing (718×299 pt, 2154×897 px)", w: 1077, h: 448, hz: 120, steps: []),
    Case(label: "upright, its controls showing, grown (Sill's default 1)", w: 800, h: 499, hz: 120, steps: []),
]

let args = CommandLine.arguments
let dry = args.contains("--dry-run")
let make = args.contains("--make")
let only = args.firstIndex(of: "--case").flatMap { i in i + 1 < args.count ? Int(args[i + 1]) : nil }
var logPath: String? = args.firstIndex(of: "--log").flatMap { i in i + 1 < args.count ? args[i + 1] : nil }

func say(_ s: String) {
    print(s)
    fflush(stdout)
    if let p = logPath, let h = FileHandle(forWritingAtPath: p) { h.seekToEndOfFile(); h.write((s + "\n").data(using: .utf8)!); h.closeFile() }
}

func online() -> [CGDirectDisplayID] {
    var n: UInt32 = 0
    CGGetOnlineDisplayList(0, nil, &n)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(n))
    CGGetOnlineDisplayList(n, &ids, &n)
    return Array(ids.prefix(Int(n)))
}

func readWords(_ d: VirtualDisplay) -> String {
    guard let r = d.reading else { return "no mode" }
    return "\(r.widthPt)×\(r.heightPt) pt @\(r.scale)×, \(d.pixelSize.width)×\(d.pixelSize.height) px, \(r.hz) Hz"
}

@MainActor
func screenWords(_ id: CGDirectDisplayID) async -> String {
    let until = Date().addingTimeInterval(1)
    while Date() < until {
        if let s = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id }) {
            let bar = Int((s.frame.maxY - s.visibleFrame.maxY).rounded())
            return "menu bar \(bar) pt, the room under it \(Int(s.visibleFrame.width))×\(Int(s.visibleFrame.height)) pt"
        }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return "AppKit lists no screen for it after 1 s"
}

func kept(_ d: VirtualDisplay, _ w: Int, _ h: Int) -> Bool {
    guard let r = d.reading else { return false }
    return r.widthPt == w && r.heightPt == h && r.scale == 2
}

/// The Virtual Desktop's follow in place (VirtualDesktopSize.InPlace, as P2b and P2c measured it): applySettings: with the
/// size alone; at 2x, done; at its pixels at 1x, once macOS lists it at 2x usable, a CoreGraphics switch to it.
@MainActor
func follow(_ d: VirtualDisplay, to s: Step, hz: Double, t0: Date) async -> String {
    let size = VirtualDisplay.ModeSize(width: s.w, height: s.h)
    let answered = (try? d.applyModes([size], refreshHz: hz)) ?? false
    var trace = ["applySettings: \(answered ? "YES" : "NO") at +\(ms(t0)) ms"]
    guard answered else { return trace.joined(separator: "; ") }
    let land = Date().addingTimeInterval(2)
    while Date() < land {
        if kept(d, s.w, s.h) { trace.append("at it @2× at +\(ms(t0)) ms"); return trace.joined(separator: "; ") }
        if let r = d.reading, r.scale == 1, r.widthPt == s.w * 2, r.heightPt == s.h * 2 {
            trace.append("at \(r.widthPt)×\(r.heightPt) @1× at +\(ms(t0)) ms")
            let listed = Date().addingTimeInterval(1)
            while Date() < listed, !d.listsUsable(size) { try? await Task.sleep(for: .milliseconds(20)) }
            guard d.listsUsable(size) else { trace.append("its 2x mode never listed usable"); return trace.joined(separator: "; ") }
            let code = d.switchToListed(size)
            trace.append("switch: complete \(code.map(String.init) ?? "not listed") at +\(ms(t0)) ms")
            let done = Date().addingTimeInterval(1.5)
            while Date() < done {
                if kept(d, s.w, s.h) { trace.append("at it @2× at +\(ms(t0)) ms"); return trace.joined(separator: "; ") }
                try? await Task.sleep(for: .milliseconds(20))
            }
            trace.append("not at it @2× 1.5 s after the switch")
            return trace.joined(separator: "; ")
        }
        try? await Task.sleep(for: .milliseconds(20))
    }
    trace.append("not at it 2 s after (it reads \(readWords(d)))")
    return trace.joined(separator: "; ")
}

func ms(_ t0: Date) -> Int { Int(Date().timeIntervalSince(t0) * 1000) }

@MainActor
func run() async -> Int32 {
    say("Probe P3, an iPhone's Virtual Desktop pixel for pixel (macOS \(ProcessInfo.processInfo.operatingSystemVersionString))")
    let problems = VirtualDisplay.checkPrivateAPI()
    guard problems.isEmpty else { for p in problems { say("  FAIL \(p)") }; return 1 }
    say("  private API: all \(VirtualDisplay.privateAPISurface.count) selectors present (looked up only)")
    let picked = cases.enumerated().filter { only == nil || $0.offset + 1 == only }
    if dry || !make {
        for (i, c) in picked {
            say("  case \(i + 1): \(c.label): \(c.w)×\(c.h) pt @2× at \(Int(c.hz)) Hz, backing 4096×4096 px"
                + (c.steps.isEmpty ? "" : "; then in place: " + c.steps.map { "\($0.w)×\($0.h) (\($0.label))" }.joined(separator: ", ")))
        }
        say("  dry run: nothing made")
        return 0
    }
    var code: Int32 = 0
    for (i, c) in picked {
        say("")
        say("Case \(i + 1) of \(cases.count): \(c.label)")
        let before = online()
        let t0 = Date()
        let d: VirtualDisplay
        do {
            d = try VirtualDisplay(name: "Sill Probe", widthPt: c.w, heightPt: c.h, scale: 2, refreshHz: c.hz,
                                   vendorID: 0x5111, productID: 0x0002, serialNum: 0xF00D, backing: (4096, 4096))
        } catch {
            say("P3 \(c.w)x\(c.h) at \(Int(c.hz)) Hz: kept at 2x: no (not made: \(error))")
            code = 1
            continue
        }
        let up = await d.waitUntilOnline(timeout: 3)
        say("  made id \(d.displayID) in \(ms(t0)) ms; online at the size asked: \(up); it reads \(readWords(d)); backing \(d.backing.wide)×\(d.backing.high) px")
        say("  \(await screenWords(d.displayID))")
        let first = kept(d, c.w, c.h)
        say("P3 \(c.w)x\(c.h) at \(Int(c.hz)) Hz: kept at 2x: \(first ? "yes" : "no (it came up at \(readWords(d)))")")
        for s in c.steps {
            try? await Task.sleep(for: .milliseconds(1200))
            let t1 = Date()
            let trace = await follow(d, to: s, hz: c.hz, t0: t1)
            say("  in place to \(s.w)×\(s.h), \(s.label): \(trace)")
            say("  \(await screenWords(d.displayID))")
            say("P3 in place \(s.w)x\(s.h): kept at 2x: \(kept(d, s.w, s.h) ? "yes" : "no (it reads \(readWords(d)))")")
        }
        try? await Task.sleep(for: .milliseconds(1500))
        let id = d.displayID
        d.destroy()
        let t2 = Date()
        while online().contains(id), Date().timeIntervalSince(t2) < 3 { try? await Task.sleep(for: .milliseconds(50)) }
        say("  removed; gone after \(ms(t2)) ms: \(!online().contains(id)); displays before \(before), after \(online())")
        try? await Task.sleep(for: .milliseconds(500))
    }
    return code
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
// Ctrl-C or run.sh's limit: the display goes with the process (VirtualDisplay's deinit at exit is not relied on).
signal(SIGINT) { _ in exit(130) }
signal(SIGTERM) { _ in exit(143) }
Task { @MainActor in exit(await run()) }
app.run()
