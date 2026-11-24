import Foundation
import CoreGraphics

// Sill's own Desktop display: its size and rate by default the device's (VirtualDesktopSize; Noah, 2026-11-18: "should
// default to resolution and refresh of client device, not what we originally proposed"), and the guard for #380
// (DisplayMakeGuard: two runs in a row that ended while making a display, and Sill makes none by itself until Try
// Again). Compiled with Sources/SillHost/VirtualDesktopSize.swift and DisplayMakeGuard.swift; the guard's Store runs in
// a folder of its own under .build, never Sill.app's.

var checks = 0
var failures = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String) {
    checks += 1
    if ok { return }
    failures += 1
    print("FAIL: \(what())")
}

typealias VDS = VirtualDesktopSize
func size(_ w: Int, _ h: Int) -> VDS.Size { VDS.Size(widthPt: w, heightPt: h, scale: 2) }
func panel(_ w: Double, _ h: Double) -> VDS.Size? { VDS.device(room: nil, panel: CGSize(width: w, height: h)) }

// MARK: This device: the plan's table (docs/virtual-desktop-plan.md §4, revised 2026-11-18), held sideways and upright

let table: [(String, Double, Double, Int, Int)] = [
    ("iPad Pro 13-inch (M4)", 1376, 1032, 1376, 1032),
    ("iPad Pro 11-inch (M4)", 1210, 834, 1210, 834),
    ("iPad Pro 12.9-inch", 1366, 1024, 1366, 1024),
    ("iPad Air 11-inch, iPad", 1180, 820, 1180, 820),
    ("iPad mini (A17 Pro), grown evenly to 800", 1133, 744, 1218, 800),
    ("iPhone 15 Pro's room clear of the Dynamic Island", 735, 393, 1496, 800),
    ("iPhone 16 Pro's room", 750, 402, 1493, 800),
    ("iPhone Duo's inner display, flat (the harness's)", 951, 669, 1137, 800),
]
for (name, w, h, ew, eh) in table {
    check(panel(w, h) == size(ew, eh), "\(name) sideways: \(Int(w))×\(Int(h)) → \(ew)×\(eh) (\(String(describing: panel(w, h))))")
    check(panel(h, w) == size(eh, ew), "\(name) upright: \(Int(h))×\(Int(w)) → \(eh)×\(ew) (\(String(describing: panel(h, w))))")
}
// Each side to whole points first (a device's points can be fractions: Stage Manager's windows, the Duo's halves).
check(panel(1133.4, 744.4) == size(1218, 800), "fractions rounded first: 1133.4×744.4 as 1133×744")
check(panel(1209.5, 834.4) == size(1210, 834), "a half point rounds up, less rounds down")
check(panel(800, 800) == size(800, 800) && panel(799.6, 800) == size(800, 800), "exactly 800 a side kept; 799.6 is 800")
check(panel(4096, 1000) == size(4096, 1000), "exactly 4096 kept")
// Larger than the ceiling: both sides shrink by one factor (8192 pixels at 2x, VirtualDisplay's).
check(panel(5000, 3000) == size(4096, 2458), "5000×3000 → 4096×2458 (\(String(describing: panel(5000, 3000))))")
check(panel(3000, 8000) == size(1536, 4096), "3000×8000 upright → 1536×4096")
// Grown then shrunk, and a shape no device has gives way to 800…4096 a side.
check(panel(16384, 1000) == size(4096, 800), "16384×1000 (16:1): 4096×800, held")
check(panel(1, 16384) == size(800, 4096), "1×16384: 800×4096, held")
check(panel(1, 1) == size(800, 800), "a point square: 800×800")
check(panel(4096, 800) == size(4096, 800), "5.12:1, the longest shape kept: as it is")
check(panel(500, 100) == size(4000, 800), "5:1 small: grown to 4000×800, the shape kept")
// The room (phase 2b's Viewport.room) before the panel; none, or one with no area, the panel.
let room = VDS.device(room: CGSize(width: 1376, height: 1032), panel: CGSize(width: 1376, height: 950))
check(room == size(1376, 1032), "the room before the panel (an iPad's whole screen, not its pane under the bar)")
check(VDS.device(room: nil, panel: CGSize(width: 1376, height: 950)) == size(1376, 950), "no room (every build before 2b): the panel")
check(VDS.device(room: CGSize(width: 0, height: 900), panel: CGSize(width: 1180, height: 820)) == size(1180, 820), "a room with no area: the panel")
check(VDS.device(room: nil, panel: nil) == nil, "nothing: none (the caller's fallback)")
check(VDS.device(room: nil, panel: CGSize(width: 0, height: 0)) == nil, "a panel with no area: none")
check(VDS.device(room: nil, panel: CGSize(width: -5, height: 300)) == nil, "a negative side: none")
check(VDS.device(room: CGSize(width: Double.nan, height: 900), panel: nil) == nil, "NaN: none")
check(VDS.device(room: CGSize(width: Double.infinity, height: 900), panel: CGSize(width: 1180, height: 820)) == size(1180, 820),
      "an infinite room: the panel")
check(VDS.fallback == size(1920, 1080), "the fallback with no viewport: #200's 1920×1080 at Retina")
check(VDS.minSide == 800 && VDS.maxSide == 4096 && VDS.scale == 2, "800 to 4096 points a side, at 2x")

// 20,000 random panels within what a host takes (ViewportBounds: 1 to 16384 points a side): every side 800 to 4096 and
// whole, at 2x; a device whose rounded sides are both within 800…4096 gets them exactly; a shape within 800:4096 is kept
// within two points (the shorter side against the longer's factor); never smaller than the device in both sides.
var rng = SystemRandomNumberGenerator()
var shapeChecked = 0
for i in 0..<20_000 {
    let w = i % 4 == 0 ? Double(Int.random(in: 1...16384, using: &rng)) : Double.random(in: 1...16384, using: &rng)
    let h = i % 3 == 0 ? Double.random(in: 300...2000, using: &rng) : Double.random(in: 1...16384, using: &rng)
    guard let s = panel(w, h) else { check(false, "random \(w)×\(h): none"); continue }
    let wr = max(1, w.rounded()), hr = max(1, h.rounded())
    let ok = (800...4096).contains(s.widthPt) && (800...4096).contains(s.heightPt) && s.scale == 2
    if !ok { check(false, "random \(w)×\(h) → \(s): a side out of 800…4096"); continue }
    if (800...4096).contains(wr) && (800...4096).contains(hr) {
        check(s.widthPt == Int(wr) && s.heightPt == Int(hr), "random \(w)×\(h) within bounds → \(s): not its own points")
    }
    let longR = max(wr, hr), shortR = min(wr, hr)
    if longR / shortR <= 4096.0 / 800.0 {
        shapeChecked += 1
        let long = Double(max(s.widthPt, s.heightPt)), short = Double(min(s.widthPt, s.heightPt))
        let landscapeKept = (wr >= hr) == (s.widthPt >= s.heightPt) || wr == hr || s.widthPt == s.heightPt
        check(abs(short - shortR * long / longR) <= 2 && landscapeKept, "random \(w)×\(h) → \(s): the shape not kept")
    }
}
check(shapeChecked > 5000, "the shape judged on enough random panels (\(shapeChecked))")

// MARK: The rate: the device's, held to 24 and to the Mac's Frame Rate limit; 60 with no viewport

check(VDS.rate(viewportFPS: 120, limit: 120) == 120, "a ProMotion iPad, the limit 120: 120 Hz")
check(VDS.rate(viewportFPS: 60, limit: 120) == 60, "an iPad mini: 60 Hz")
check(VDS.rate(viewportFPS: nil, limit: 120) == 60, "no viewport: 60")
check(VDS.rate(viewportFPS: 120, limit: 60) == 60, "the Mac's limit 60: 60")
check(VDS.rate(viewportFPS: 120, limit: 30) == 30, "the Mac's limit 30: 30")
check(VDS.rate(viewportFPS: 10, limit: 120) == 24, "a rate under 24: 24")
check(VDS.rate(viewportFPS: 500, limit: 120) == 120, "a rate past the limit: the limit")
check(VDS.rate(viewportFPS: nil, limit: 10) == 24, "a limit under 24 is no limit under 24")

// MARK: Whose viewport sizes it: the asking device's, else the newest, else none

check(VDS.matched(asker: "ipad", newest: "iphone", sent: ["ipad", "iphone"]) == "ipad", "the asker's when it sent one")
check(VDS.matched(asker: "ipad", newest: "iphone", sent: ["iphone"]) == "iphone", "the asker without one: the newest")
check(VDS.matched(asker: nil, newest: "iphone", sent: ["iphone"]) == "iphone", "no asker known: the newest")
check(VDS.matched(asker: "ipad", newest: nil, sent: []) == nil, "nobody sent one: none")
check(VDS.matched(asker: "ipad", newest: "gone", sent: ["ipad"]) == "ipad", "the newest gone: the asker's")
check(VDS.matched(asker: "gone", newest: "gone", sent: ["ipad"]) == nil, "both gone: none")

// MARK: The refresh rate the Desktop's stream is held to (defect 4 of the assessment)

check(VDS.refreshHeld(stop: 75, sills: 60, onSills: false) == 75, "a stop's rate first")
check(VDS.refreshHeld(stop: 75, sills: 60, onSills: true) == 75, "a stop's rate first, always")
check(VDS.refreshHeld(stop: nil, sills: 60, onSills: true) == 60, "on Sill's own display: its rate (a 120 Hz device beside the 60 Hz one it was made for)")
check(VDS.refreshHeld(stop: nil, sills: 60, onSills: false) == nil, "no stop and not on Sill's display (the stand-in): none")
check(VDS.refreshHeld(stop: nil, sills: nil, onSills: true) == nil, "Sill's display with no rate read: none")

// MARK: The creation line: the mode it came up at, what was asked when it differs, whose screen

check(VDS.createdLine(came: size(1218, 800), asked: size(1218, 800), hz: 60, id: 66, device: "iPad mini")
      == "Headless display: created 1218×800 pt @2× at 60 Hz (id 66) for iPad mini, its screen.", "the line as the plan words it")
check(VDS.createdLine(came: VDS.Size(widthPt: 1218, heightPt: 800, scale: 1), asked: size(1218, 800), hz: 60, id: 66, device: "iPad mini")
      == "Headless display: created 1218×800 pt @1× at 60 Hz (asked 1218×800 @2×) (id 66) for iPad mini, its screen.",
      "a mode other than the one asked: both said (#200's line claimed @2× whatever it got)")
check(VDS.createdLine(came: size(1218, 800), asked: size(1218, 800), hz: 60, id: nil, device: "iPad")
      == "Headless display: created 1218×800 pt @2× at 60 Hz (TEST ONLY: none made, SILL_TEST_HEADLESS) for iPad, its screen.",
      "a test host's said display")
check(VDS.createdLine(came: VDS.fallback, asked: VDS.fallback, hz: 60, id: 7, device: nil)
      == "Headless display: created 1920×1080 pt @2× at 60 Hz (id 7) at 1920×1080: no device's screen known yet.",
      "no viewport from any device")

// MARK: The guard for #380 (DisplayMakeGuard)

typealias G = DisplayMakeGuard
check(G.tripAt == 2, "two runs in a row")
check(G.atLaunch(markerFound: true, stops: 0) == 1, "a marker at launch: one stop")
check(G.atLaunch(markerFound: true, stops: 1) == 2, "a second in a row: two")
check(G.atLaunch(markerFound: false, stops: 1) == 1, "no marker: the count as kept")
check(G.atLaunch(markerFound: false, stops: 0) == 0, "no marker, none kept: none")
check(G.atLaunch(markerFound: true, stops: -3) == 1, "a count under 0 kept: taken as 0")
check(!G.holds(stops: 0) && !G.holds(stops: 1) && G.holds(stops: 2) && G.holds(stops: 5), "holds from two")
check(G.afterMake(cameUp: true, stops: 1) == 0 && G.afterMake(cameUp: true, stops: 2) == 0, "a display that came up: 0")
check(G.afterMake(cameUp: false, stops: 1) == 1 && G.afterMake(cameUp: false, stops: 0) == 0, "one that did not: unchanged")
let when = Date(timeIntervalSince1970: 1_795_000_000)
check(G.marker(role: "stage", at: when) == "stage 2026-11-18T11:06:40Z\n", "the marker: its role and the time, UTC (\(G.marker(role: "stage", at: when)))")
check(G.parse(G.marker(role: "desktop", at: when)).map { $0.role == "desktop" && $0.at == when } == true, "a marker read back")
check(G.parse("") == nil && G.parse("stage") == nil && G.parse("window 2026-11-18T11:06:40Z") == nil && G.parse("stage tomorrow") == nil,
      "anything else is no marker's words")
check(G.launchLine(marker: nil, stops: 1) == nil, "no marker: no line")
check(G.launchLine(marker: G.marker(role: "stage", at: when), stops: 1)
      == "Sill stopped while making a display last time (its window display, 2026-11-18T11:06:40Z); after 2 runs in a row it makes none by itself.",
      "one stop: its line (\(G.launchLine(marker: G.marker(role: "stage", at: when), stops: 1) ?? "nil"))")
check(G.launchLine(marker: G.marker(role: "desktop", at: when), stops: 2)
      == "Sill stopped while making a display last time (2 runs in a row: its Desktop display, 2026-11-18T11:06:40Z); it makes none by itself until you choose Try Again in Settings › Virtual Display.",
      "two in a row: it holds, and where Try Again is")
check(G.launchLine(marker: "", stops: 2)
      == "Sill stopped while making a display last time (2 runs in a row); it makes none by itself until you choose Try Again in Settings › Virtual Display.",
      "a marker half written still counts, without its words")

// The Store, in a folder of its own: a run that ends while making (a crash), the next one, Try Again, a clean quit.
let base = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : NSTemporaryDirectory())
    .appendingPathComponent("guard-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
try? FileManager.default.removeItem(at: base)
var kept = 0
func store(_ name: String) -> G.Store {
    G.Store(folder: base.appendingPathComponent(name), readStops: { kept }, writeStops: { kept = $0 })
}
try? FileManager.default.createDirectory(at: base.appendingPathComponent("a"), withIntermediateDirectories: true)
var s = store("a")
check(s.stops == 0 && !s.holds && s.launchLine == nil && !s.markerPresent, "a first launch: nothing")
s.willMake("stage", at: when)
check(s.markerPresent, "the marker written before the private calls")
check((try? String(contentsOf: base.appendingPathComponent("a/making-display"), encoding: .utf8)) == "stage 2026-11-18T11:06:40Z\n",
      "…saying what and when")
s.made(cameUp: true)
check(!s.markerPresent && s.stops == 0, "came up: the marker gone, nothing counted")
s.willMake("stage", at: when)                    // and the run ends here: a crash
s = store("a")
check(s.stops == 1 && kept == 1 && !s.holds && s.launchLine?.hasPrefix("Sill stopped while making a display last time (its window display") == true,
      "the next launch: one stop, its line, still making displays")
check(!s.markerPresent, "…and the marker taken")
s.willMake("desktop", at: when)                  // ends again
s = store("a")
check(s.stops == 2 && kept == 2 && s.holds, "two runs in a row: it holds")
check(s.launchLine?.contains("until you choose Try Again") == true, "…and says where Try Again is")
s = store("a")
check(s.stops == 2 && s.holds && s.launchLine == nil, "a launch with no marker keeps holding, with no line")
s.tryAgain()
check(s.stops == 0 && kept == 0 && !s.holds, "Try Again: 0, kept")
s.willMake("desktop", at: when)
s.made(cameUp: false)
check(!s.markerPresent && s.stops == 0, "a make that failed is no stop")
s.willMake("stage", at: when)
s = store("a")
check(s.stops == 1, "one stop")
s.willMake("stage", at: when)
s.made(cameUp: true)
check(s.stops == 0 && kept == 0, "a display that came up resets the count")
s.willMake("stage", at: when)
s.quitting()
s = store("a")
check(s.stops == 0 && s.launchLine == nil, "a clean quit while making is no stop")
// A marker left empty (the run ended mid-write) still counts, and so does one that is no text at all.
FileManager.default.createFile(atPath: base.appendingPathComponent("a/making-display").path, contents: Data())
s = store("a")
check(s.stops == 1 && s.launchLine?.contains("last time;") == true, "an empty marker counts (\(s.launchLine ?? "nil"))")
FileManager.default.createFile(atPath: base.appendingPathComponent("a/making-display").path, contents: Data([0xFF, 0xFE, 0x00, 0xD8]))
s = store("a")
check(s.stops == 2 && s.holds && !s.markerPresent, "a marker that is no text counts too, and is taken (\(s.stops))")
s.tryAgain()
// The TEST ONLY store: the count in a file beside the marker.
let testFolder = base.appendingPathComponent("test")
var t = G.Store.test(folder: testFolder)
check(t.stops == 0 && !t.holds, "a test folder: nothing")
t.willMake("desktop", at: when)
t = G.Store.test(folder: testFolder)
t.willMake("desktop", at: when)
t = G.Store.test(folder: testFolder)
check(t.stops == 2 && t.holds && (try? String(contentsOf: testFolder.appendingPathComponent("display-make-stops"), encoding: .utf8)) == "2\n",
      "the test store's count in its file")
t.tryAgain()
check(G.Store.test(folder: testFolder).stops == 0, "Try Again written to it")

// 2,000 random lives of Sill.app against a model: each run makes displays that come up, fail, or end the run mid-way
// (a crash), quits cleanly or not, and the person may choose Try Again; never a display by itself while it holds.
for life in 0..<2_000 {
    let folder = "life\(life % 4)"
    try? FileManager.default.removeItem(at: base.appendingPathComponent(folder))
    try? FileManager.default.createDirectory(at: base.appendingPathComponent(folder), withIntermediateDirectories: true)
    kept = 0
    var model = 0
    var markerLeft = false
    for _ in 0..<Int.random(in: 1...8, using: &rng) {
        let run = store(folder)
        if markerLeft { model += 1 }                // the model: one more stop for a run that ended while making
        markerLeft = false
        check(run.stops == model && run.holds == (model >= 2), "life \(life): the count \(run.stops), the model \(model)")
        if Bool.random(using: &rng), model >= 2 { run.tryAgain(); model = 0 }
        var crashed = false
        for _ in 0..<Int.random(in: 0...3, using: &rng) {
            if run.holds { check(model >= 2, "life \(life): holds only from two"); break }   // makes none by itself
            run.willMake(Bool.random(using: &rng) ? "stage" : "desktop", at: when)
            switch Int.random(in: 0...2, using: &rng) {
            case 0: run.made(cameUp: true); model = 0
            case 1: run.made(cameUp: false)
            default: crashed = true; markerLeft = true
            }
            if crashed { break }
        }
        if !crashed, Bool.random(using: &rng) { run.quitting() }
        check(run.markerPresent == markerLeft, "life \(life): the marker left only by a run that ended while making")
    }
}
try? FileManager.default.removeItem(at: base)

print("virtual-desktop: \(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
