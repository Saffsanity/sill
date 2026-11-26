// TEST ONLY. Probe P4 (2026-11-26; docs/steps/2026-11-18-virtual-desktop-2b.md, "P3's result, and probe P4"): where
// the line runs between the Virtual Desktops macOS keeps at 2x and those it runs at 1x. P3 (Noah's run, 2026-11-26)
// found that of an iPhone 15 Pro's sizes macOS keeps 589×1189 and 1101×589 (Full Screen, upright and on its side) and
// does not keep 1077×448 (on its side, its controls showing) nor 800×499 (upright, its controls showing, grown): each
// came up at 1x, in place and made as it is. So a longer side of 800 points is not what decides, and nothing between a
// shorter side of 499 and of 589 points had been tried. This tries it, at 2x and 120 Hz unless said:
//   1. made at 589×1189 (kept), then in place, the Virtual Desktop's way, through
//      - the shape of an iPhone on its side with its controls showing (718×299 points, 2.40:1), from tall to short:
//        1383×576, 1345×560, 1297×540, 1229×512, 1153×480;
//      - the shape of an upright iPhone's pane over its controls (377×235 points, 1.60:1): 945×589, 924×576, 898×560,
//        866×540, 821×512;
//      - what decides, the shorter side, the height or the pixels: 499×1189 (narrow and tall), 448×1077 (the size not
//        kept, turned), 1600×448 (short and wide, more pixels than 1101×589), 800×540 (fewer pixels than any kept),
//        754×784 (the stage's history: both sides under 800) and 800×800;
//      after a size macOS does not keep, back to 589×1189 first, so that every step starts from the same state (if it
//      does not come back, the rest of the case is skipped and said so);
//   2. 1077×448 at 60 Hz, made as it is, and 3. 800×499 at 60 Hz: does the rate decide;
//   4. 1297×540 and 5. 866×540, made as they are: a make, where the ladders followed (a make is what Sill does first).
// Each size's last line is its verdict, "P4 … kept at 2x: yes|no (…)", with its pixels; the last two lines name the
// smallest size kept of each shape. Sill's bend for an iPhone (VirtualDesktopSize.phone: no side under 400 points, one
// of 800 or more) is then set from what this finds.
//
// The display is "Sill Probe", Sill's Desktop identity with a serial of its own (0xF00D), so macOS remembers nothing for
// Sill's own display. Nothing else is made, moved, posted or captured: no window, no pointer, no ScreenCaptureKit, no
// VideoToolbox, never the rotation setting. Compiled with Sources/SillHost/VirtualDisplay.swift alone (run.sh); the real
// run is Noah's, from Terminal.app, with Sill quit and no device connected.
//
//   probe-floor --dry-run            the plan and the private API's surface (looked up, no display): an agent's
//   probe-floor --make [--case N]    the real run (run.sh starts it), or one case of it
import AppKit
import CoreGraphics
import Foundation

struct Step { let group: String; let w: Int; let h: Int }
struct Case { let label: String; let w: Int; let h: Int; let hz: Double; let steps: [Step] }
struct Result { let group: String; let w: Int; let h: Int; let kept: Bool }

let side = "on its side, its controls showing, 2.40:1"
let pane = "upright, its controls showing, 1.60:1"
let what = "what decides"

let cases: [Case] = [
    Case(label: "upright with Full Screen, which macOS keeps (P3), then the ladders in place", w: 589, h: 1189, hz: 120, steps: [
        Step(group: side, w: 1383, h: 576),
        Step(group: side, w: 1345, h: 560),
        Step(group: side, w: 1297, h: 540),
        Step(group: side, w: 1229, h: 512),
        Step(group: side, w: 1153, h: 480),
        Step(group: pane, w: 945, h: 589),
        Step(group: pane, w: 924, h: 576),
        Step(group: pane, w: 898, h: 560),
        Step(group: pane, w: 866, h: 540),
        Step(group: pane, w: 821, h: 512),
        Step(group: what, w: 499, h: 1189),
        Step(group: what, w: 448, h: 1077),
        Step(group: what, w: 1600, h: 448),
        Step(group: what, w: 800, h: 540),
        Step(group: what, w: 754, h: 784),
        Step(group: what, w: 800, h: 800),
    ]),
    Case(label: "on its side with its controls, pixel for pixel, at 60 Hz (does the rate decide)", w: 1077, h: 448, hz: 60, steps: []),
    Case(label: "upright with its controls, grown, at 60 Hz", w: 800, h: 499, hz: 60, steps: []),
    Case(label: "the 2.40:1 shape 540 points high, made as it is (a make, where the ladder followed)", w: 1297, h: 540, hz: 120, steps: []),
    Case(label: "the 1.60:1 shape 540 points high, made as it is", w: 866, h: 540, hz: 120, steps: []),
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

/// A size's pixels at 2x and how many they are: "2594×1080 px, 2.80 MP".
func pixelWords(_ w: Int, _ h: Int) -> String {
    let mp = Double(w * 2) * Double(h * 2) / 1_000_000
    return "\(w * 2)×\(h * 2) px, \(String(format: "%.2f", mp)) MP"
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

/// The Virtual Desktop's follow in place (VirtualDesktopSize.InPlace, as P2b and P2c measured it, and as P3 did it):
/// applySettings: with the size alone; at 2x, done; at its pixels at 1x, once macOS lists it at 2x usable, a CoreGraphics
/// switch to it.
@MainActor
func follow(_ d: VirtualDisplay, toWidth w: Int, height h: Int, hz: Double, t0: Date) async -> String {
    let size = VirtualDisplay.ModeSize(width: w, height: h)
    let answered = (try? d.applyModes([size], refreshHz: hz)) ?? false
    var trace = ["applySettings: \(answered ? "YES" : "NO") at +\(ms(t0)) ms"]
    guard answered else { return trace.joined(separator: "; ") }
    let land = Date().addingTimeInterval(2)
    while Date() < land {
        if kept(d, w, h) { trace.append("at it @2× at +\(ms(t0)) ms"); return trace.joined(separator: "; ") }
        if let r = d.reading, r.scale == 1, r.widthPt == w * 2, r.heightPt == h * 2 {
            trace.append("at \(r.widthPt)×\(r.heightPt) @1× at +\(ms(t0)) ms")
            let listed = Date().addingTimeInterval(1)
            while Date() < listed, !d.listsUsable(size) { try? await Task.sleep(for: .milliseconds(20)) }
            guard d.listsUsable(size) else { trace.append("its 2x mode never listed usable"); return trace.joined(separator: "; ") }
            let code = d.switchToListed(size)
            trace.append("switch: complete \(code.map(String.init) ?? "not listed") at +\(ms(t0)) ms")
            let done = Date().addingTimeInterval(1.5)
            while Date() < done {
                if kept(d, w, h) { trace.append("at it @2× at +\(ms(t0)) ms"); return trace.joined(separator: "; ") }
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
    say("Probe P4, where macOS keeps a small Virtual Desktop at 2x (macOS \(ProcessInfo.processInfo.operatingSystemVersionString))")
    let problems = VirtualDisplay.checkPrivateAPI()
    guard problems.isEmpty else { for p in problems { say("  FAIL \(p)") }; return 1 }
    say("  private API: all \(VirtualDisplay.privateAPISurface.count) selectors present (looked up only)")
    let picked = cases.enumerated().filter { only == nil || $0.offset + 1 == only }
    if dry || !make {
        for (i, c) in picked {
            say("  case \(i + 1): \(c.label): \(c.w)×\(c.h) pt @2× at \(Int(c.hz)) Hz (\(pixelWords(c.w, c.h))), backing 4096×4096 px"
                + (c.steps.isEmpty ? "" : "; then in place, back to it after each size not kept:"))
            for s in c.steps { say("    \(s.w)×\(s.h) (\(pixelWords(s.w, s.h)); \(s.group))") }
        }
        say("  dry run: nothing made")
        return 0
    }
    var code: Int32 = 0
    var results: [Result] = []
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
            say("P4 made \(c.w)x\(c.h) at \(Int(c.hz)) Hz (\(pixelWords(c.w, c.h))): kept at 2x: no (not made: \(error))")
            code = 1
            continue
        }
        let up = await d.waitUntilOnline(timeout: 3)
        say("  made id \(d.displayID) in \(ms(t0)) ms; online at the size asked: \(up); it reads \(readWords(d)); backing \(d.backing.wide)×\(d.backing.high) px")
        say("  \(await screenWords(d.displayID))")
        let first = kept(d, c.w, c.h)
        say("P4 made \(c.w)x\(c.h) at \(Int(c.hz)) Hz (\(pixelWords(c.w, c.h))): kept at 2x: \(first ? "yes" : "no (it came up at \(readWords(d)))")")
        if !first && !c.steps.isEmpty {
            say("  the size the ladders start from was not kept this time; its steps are not tried")
        }
        for s in (first ? c.steps : []) {
            try? await Task.sleep(for: .milliseconds(700))
            let trace = await follow(d, toWidth: s.w, height: s.h, hz: c.hz, t0: Date())
            let ok = kept(d, s.w, s.h)
            say("  in place to \(s.w)×\(s.h): \(trace)")
            say("P4 in place \(s.w)x\(s.h) at \(Int(c.hz)) Hz (\(pixelWords(s.w, s.h)); \(s.group)): kept at 2x: \(ok ? "yes" : "no (it reads \(readWords(d)))")")
            results.append(Result(group: s.group, w: s.w, h: s.h, kept: ok))
            if !ok {
                // Back to the size it was made at, so that the next step starts where every other does.
                try? await Task.sleep(for: .milliseconds(400))
                let back = await follow(d, toWidth: c.w, height: c.h, hz: c.hz, t0: Date())
                if !kept(d, c.w, c.h) {
                    say("  back to \(c.w)×\(c.h): NOT at it (\(back)); the rest of this case is skipped, its sizes not tried")
                    break
                }
            }
        }
        try? await Task.sleep(for: .milliseconds(1500))
        let id = d.displayID
        d.destroy()
        let t2 = Date()
        while online().contains(id), Date().timeIntervalSince(t2) < 3 { try? await Task.sleep(for: .milliseconds(50)) }
        say("  removed; gone after \(ms(t2)) ms: \(!online().contains(id)); displays before \(before), after \(online())")
        try? await Task.sleep(for: .milliseconds(500))
    }
    if !results.isEmpty {
        say("")
        for g in [side, pane] {
            let tried = results.filter { $0.group == g }
            guard !tried.isEmpty else { continue }
            let least = tried.filter { $0.kept }.min { $0.h < $1.h }
            say("P4 \(g): " + (least.map { "the smallest kept at 2x of the \(tried.count) tried in place: \($0.w)x\($0.h)" }
                                ?? "none of the \(tried.count) tried in place was kept at 2x"))
        }
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
