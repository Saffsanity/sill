import Foundation
import CoreGraphics

// Checks WindowRestore (Sources/SillHost/WindowRestore.swift; docs/restore-window-frames-plan.md,
// issue #57): a window Sill sized for a device goes back when it stops streaming. First the rule at
// its edges: `keep`, `fitted`, `decide` for every outcome, `homeForStage`, the ledger and the lines;
// then the two sequences that read and move a window, `fit` (WindowSizer.resize's) and `stop`
// (each window `restoreFits` puts back), with `stageHome` and `Ledger.restore`, against a stand-in
// window that logs every call. Then a model: a stand-in Mac (`Mac`, which answers the sequences' reads
// and writes as `WindowSizer.AXWindows` does Accessibility's) and a copy of the coordinator's glue
// around them (StreamCoordinator's `fitToViewport`, `select`, `restoreFits`, `stageHome`,
// `shutdownForExit`; the virtual display's stage): random sessions of picks, viewports, restarts, the
// catalog's resize check, the person at the Mac moving, resizing, closing and full-screening windows,
// apps that clamp to a minimum, snap to a grid or apply a size late, the virtual display on and off,
// the last device leaving and Quit, each window's frame held to where the person expects it. The
// sequences and the rule are the real ones; the glue is written again here and can drift from the
// coordinator's.
//
// Compiled alone with this file (build.sh): swiftc -O WindowRestore.swift main.swift

var failures = 0
var passes = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String) {
    if ok { passes += 1 } else { failures += 1; if failures <= 40 { print("FAIL: \(what())") } }
}
func eq<T: Equatable>(_ got: T, _ want: T, _ what: String) { check(got == want, "\(what): got \(got), want \(want)") }
func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }
func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
func S(_ w: CGFloat, _ h: CGFloat) -> CGSize { CGSize(width: w, height: h) }

// MARK: keep

let area = R(0, 25, 1512, 920)        // a laptop's display below its menu bar, above its Dock
eq(WindowRestore.keep(R(100, 100, 800, 500), in: area), P(100, 100), "keep: inside stays")
eq(WindowRestore.keep(R(900, 100, 800, 500), in: area), P(712, 100), "keep: off the right edge comes left")
eq(WindowRestore.keep(R(100, 600, 800, 500), in: area), P(100, 445), "keep: off the bottom comes up")
eq(WindowRestore.keep(R(-50, 100, 800, 500), in: area), P(0, 100), "keep: off the left edge comes right")
eq(WindowRestore.keep(R(100, 10, 800, 500), in: area), P(100, 25), "keep: under the menu bar comes down")
eq(WindowRestore.keep(R(300, 100, 2000, 500), in: area), P(0, 100), "keep: wider than the area keeps its left edge in it")
eq(WindowRestore.keep(R(100, 300, 800, 1200), in: area), P(100, 25), "keep: taller than the area keeps its top in it")
eq(WindowRestore.keep(R(712, 445, 800, 500), in: area), P(712, 445), "keep: exactly at the right and bottom edges stays")
eq(WindowRestore.keep(R(1400, 900, 800, 500), in: area), P(712, 445), "keep: off two edges comes in on both")
eq(WindowRestore.keep(R(2000, 100, 300, 200), in: R(1512, 0, 1920, 1080)), P(2000, 100), "keep: a second display's area")

// MARK: fitted

let O = R(100, 100, 1200, 800)        // the window as the person had it
let Sz = S(800, 500)                  // what the device's panel asks for
let Sf = R(100, 100, 800, 500)        // where Sill left it
let first = WindowRestore.fitted(nil, before: O, after: Sf, asked: Sz)
eq(first, WindowRestore.Record(original: O, set: Sf, asked: Sz, moved: false), "fitted: the first records where it was")
let refit = WindowRestore.fitted(first, before: Sf, after: R(100, 100, 500, 800), asked: S(500, 800))
eq(refit, WindowRestore.Record(original: O, set: R(100, 100, 500, 800), asked: S(500, 800), moved: false),
   "fitted: a rotation keeps the original, takes the new frame and size asked")
eq(WindowRestore.fitted(first, before: R(102, 98, 800, 500), after: R(102, 98, 640, 400), asked: S(640, 400)).moved, false,
   "fitted: 2 pt from where Sill left it is not a move")
eq(WindowRestore.fitted(first, before: R(102.5, 100, 800, 500), after: R(102.5, 100, 640, 400), asked: S(640, 400)).moved, true,
   "fitted: 2.5 pt across is a move")
eq(WindowRestore.fitted(first, before: R(100, 103, 800, 500), after: R(100, 103, 640, 400), asked: S(640, 400)).moved, true,
   "fitted: 3 pt down is a move")
let movedOnce = WindowRestore.fitted(first, before: R(300, 200, 800, 500), after: R(300, 200, 640, 400), asked: S(640, 400))
let afterMove = WindowRestore.fitted(movedOnce, before: R(300, 200, 640, 400), after: R(300, 200, 800, 500), asked: Sz)
eq(afterMove.moved, true, "fitted: a move stays noted through a later fit in place")
eq(afterMove.original, O, "fitted: the original survives every later fit")
eq(WindowRestore.fitted(first, before: R(100, 100, 1000, 700), after: Sf, asked: Sz),
   WindowRestore.Record(original: O, set: Sf, asked: Sz, moved: false),
   "fitted: a resize on the Mac that a re-fit undid is forgotten (no move)")
// A resize from another edge or corner moves the top-left corner and keeps the opposite edges: no move.
// Sill left it at (100,100,800×500): right edge 900, bottom 600.
for (what, before) in [("the left edge", R(-20, 100, 920, 500)), ("the top edge", R(100, 40, 800, 560)),
                       ("the top-left corner", R(-20, 40, 920, 560)), ("the top-right corner", R(100, 40, 1000, 560)),
                       ("the bottom-left corner", R(-20, 100, 920, 700)), ("the left edge inwards", R(400, 100, 500, 500))] {
    let r = WindowRestore.fitted(first, before: before, after: CGRect(origin: before.origin, size: Sz), asked: Sz)
    eq(r.moved, false, "fitted: a resize from \(what) that a re-fit undid is not a move")
    eq(decide(r, CGRect(origin: before.origin, size: Sz)), .restore(O, whole: true), "decide: after a resize from \(what) undone: back whole")
}
eq(WindowRestore.fitted(first, before: R(100, 100, 802, 500), after: Sf, asked: Sz).moved, false, "fitted: the right edge 2 pt out is no move")
eq(WindowRestore.fitted(first, before: R(97, 100, 806, 500), after: Sf, asked: Sz).moved, false,
   "fitted: both side edges 3 pt out (Option held) is a resize, no move")
eq(WindowRestore.fitted(first, before: R(60, 60, 880, 580), after: Sf, asked: Sz).moved, false,
   "fitted: every edge 40 pt out (Option, a corner) is a resize, no move")
eq(WindowRestore.fitted(first, before: R(97, 100, 803, 500), after: Sf, asked: Sz).moved, false, "fitted: the left edge 3 pt out, the right kept: no move")
eq(WindowRestore.fitted(first, before: R(97, 100, 804, 500), after: Sf, asked: Sz).moved, false,
   "fitted: the left edge 3 pt out and the right 1 pt out: a resize")
eq(WindowRestore.fitted(first, before: R(97, 100, 801.5, 500), after: Sf, asked: Sz).moved, true,
   "fitted: 3 pt left at Sill's size (within 2 pt): a move")
eq(WindowRestore.fitted(first, before: R(97, 100, 800, 500), after: Sf, asked: Sz).moved, true, "fitted: 3 pt left, its size kept: a move")
eq(WindowRestore.fitted(first, before: R(97, 100, 799, 500), after: Sf, asked: Sz).moved, true, "fitted: 3 pt left and 1 pt narrower: a move")
eq(WindowRestore.fitted(first, before: R(150, 100, 900, 500), after: Sf, asked: Sz).moved, true, "fitted: moved right and widened: a move")
eq(WindowRestore.fitted(first, before: R(100, 160, 800, 700), after: Sf, asked: Sz).moved, true, "fitted: moved down and made taller: a move")
eq(WindowRestore.fitted(first, before: R(160, 100, 740, 640), after: Sf, asked: Sz).moved, false,
   "fitted: the left edge in and the bottom out (the right and the top kept): a resize")
eq(WindowRestore.movedSince(first, R(103, 103, 800, 500)), true, "movedSince: 3 pt each way")
eq(WindowRestore.movedSince(first, R(100, 103, 800, 500)), true, "movedSince: 3 pt down")
eq(WindowRestore.movedSince(first, R(100, 103, 800, 497)), false, "movedSince: the top edge 3 pt in")
eq(WindowRestore.shifted(from: Sf, to: R(103, 100, 800, 500)), true, "shifted: 3 pt across")
eq(WindowRestore.shifted(from: Sf, to: R(102, 102, 800, 500)), false, "shifted: 2 pt each way is none")
eq(WindowRestore.shifted(from: Sf, to: R(90, 100, 830, 500)), false, "shifted: the edges apart is none")
eq(WindowRestore.shifted(from: Sf, to: R(110, 110, 780, 480)), false, "shifted: the edges together is none")
// An app that applies a size after answering read back its old size (1200×800) for Sill's 800×500: it
// is moved at either of Sill's sizes, and a resize from an edge is judged from where Sill really left it.
let late = WindowRestore.fitted(nil, before: O, after: O, asked: Sz)
eq(WindowRestore.movedSince(late, R(150, 130, 800, 500)), true, "movedSince: a late app moved at the size asked")
eq(WindowRestore.movedSince(late, R(150, 130, 1200, 800)), true, "movedSince: a late app moved at the size read back")
eq(WindowRestore.movedSince(late, R(100, 100, 800, 500)), false, "movedSince: a late app where Sill left it")
eq(WindowRestore.movedSince(late, R(-20, 100, 920, 500)), false, "movedSince: a late app's left edge dragged out from the size asked")
eq(WindowRestore.movedSince(late, R(160, 40, 740, 560)), false, "movedSince: a late app's top-left corner dragged, the size asked")
eq(WindowRestore.movedSince(late, R(600, 500, 850, 520)), true, "movedSince: a late app moved and resized")

// MARK: decide

let rec = first
func decide(_ r: WindowRestore.Record, _ current: CGRect?, fullScreen: Bool = false, area a: CGRect? = area) -> WindowRestore.Decision {
    WindowRestore.decide(r, current: current, fullScreen: fullScreen, area: a)
}
eq(decide(rec, nil), .gone, "decide: no frame is gone")
eq(decide(rec, nil, fullScreen: true), .gone, "decide: gone before full screen")
eq(decide(rec, Sf, fullScreen: true), .leave(.fullScreen), "decide: full screen is left as it is")
eq(decide(rec, O, fullScreen: true), .leave(.fullScreen), "decide: full screen, even at the original frame")
eq(decide(rec, O), .home, "decide: at the original frame is home")
eq(decide(rec, R(102, 98, 1198, 802)), .home, "decide: within 2 pt of the original is home")
eq(decide(rec, Sf), .restore(O, whole: true), "decide: where Sill left it goes back whole")
eq(decide(rec, R(102, 102, 798, 502)), .restore(O, whole: true), "decide: within 2 pt of where Sill left it goes back whole")
eq(decide(rec, R(103, 100, 800, 500)), .restore(R(103, 100, 1200, 800), whole: false),
   "decide: moved 3 pt keeps its place and gets its size back")
eq(decide(rec, R(900, 300, 800, 500)), .restore(R(312, 145, 1200, 800), whole: false),
   "decide: moved near the corner: its size back, kept on the display")
eq(decide(rec, R(900, 300, 800, 500), area: nil), .restore(R(900, 300, 1200, 800), whole: false),
   "decide: no area, no nudge")
eq(decide(rec, R(1600, 200, 800, 500), area: R(1512, 0, 1920, 1080)), .restore(R(1600, 200, 1200, 800), whole: false),
   "decide: moved to the second display keeps to it")
eq(decide(rec, R(100, 100, 803, 500)), .leave(.resized), "decide: 3 pt wider than Sill left it was resized on the Mac")
eq(decide(rec, R(100, 100, 800, 497)), .leave(.resized), "decide: 3 pt shorter was resized on the Mac")
eq(decide(rec, R(100, 100, 1000, 700)), .leave(.resized), "decide: resized on the Mac is left alone")
eq(decide(rec, R(300, 300, 1200, 800)), .leave(.resized), "decide: its own size by hand elsewhere is the person's")
// An app that applies a size after answering the write read back its old frame: at the asked size it
// is Sill's all the same.
let lagging = WindowRestore.fitted(nil, before: O, after: O, asked: Sz)
eq(decide(lagging, Sf), .restore(O, whole: true), "decide: a late app at the asked size goes back whole")
eq(decide(lagging, R(400, 300, 800, 500)), .restore(R(312, 145, 1200, 800), whole: false), "decide: a late app, moved")
eq(decide(lagging, O), .settle(O), "decide: a late app stopped before it showed Sill's size: its frame written again")
eq(decide(lagging, R(101, 99, 1199, 801)), .settle(O), "decide: settled within 2 pt of the original too")
eq(decide(WindowRestore.fitted(nil, before: O, after: O, asked: S(1202, 798)), O), .home,
   "decide: asked within 2 pt of its own size: home, nothing to settle")
eq(decide(WindowRestore.fitted(nil, before: O, after: R(100, 100, 1203, 800), asked: Sz), O), .home,
   "decide: a read-back that showed a change: home is home")
eq(decide(WindowRestore.fitted(lagging, before: Sf, after: Sf, asked: S(640, 400)), O), .home,
   "decide: back at its own frame after a fit that showed: the person's (home)")
eq(decide(lagging, R(100, 100, 803, 500)), .leave(.resized), "decide: a late app off both the read-back and the asked size")
// An app with a minimum took more than asked: what it read back is Sill's.
let clamped = WindowRestore.fitted(nil, before: O, after: R(100, 100, 900, 600), asked: Sz)
eq(decide(clamped, R(100, 100, 900, 600)), .restore(O, whole: true), "decide: a minimum read back goes back whole")
eq(decide(clamped, R(100, 100, 800, 500)), .restore(O, whole: true), "decide: the asked size of a clamped app is still Sill's")
// Moved at a later fit: whole no longer, even where Sill last left it.
let noted = WindowRestore.Record(original: O, set: Sf, asked: Sz, moved: true)
eq(decide(noted, Sf), .restore(R(100, 100, 1200, 800), whole: false), "decide: a noted move keeps its place where Sill left it")
eq(decide(noted, R(200, 200, 800, 500)), .restore(R(200, 145, 1200, 800), whole: false), "decide: a noted move, moved again")
// A size the app refused (it read back its own): a move is all that is left, and the person's.
let refused = WindowRestore.fitted(nil, before: O, after: O, asked: S(1200, 800))
eq(decide(refused, R(150, 120, 1200, 800)), .home, "decide: its own size where it was moved is home")
eq(decide(refused, R(0, 0, 1200, 800)), .restore(R(0, 25, 1200, 800), whole: false),
   "decide: its own size under the menu bar comes down (the area)")
// Sill nudged it and the app kept its size: back to the original place.
let nudged = WindowRestore.fitted(nil, before: R(900, 100, 600, 400), after: R(712, 100, 600, 400), asked: S(800, 500))
eq(decide(nudged, R(712, 100, 600, 400)), .restore(R(900, 100, 600, 400), whole: true), "decide: a nudge Sill made is undone")

// MARK: homeForStage

eq(WindowRestore.homeForStage(.restore(O, whole: true)), O, "homeForStage: the original")
eq(WindowRestore.homeForStage(.restore(R(5, 6, 7, 8), whole: false)), R(5, 6, 7, 8), "homeForStage: its own size where it was moved")
eq(WindowRestore.homeForStage(.home), nil, "homeForStage: already home: as found")
eq(WindowRestore.homeForStage(.settle(O)), O, "homeForStage: settled: the original")
eq(WindowRestore.homeForStage(.leave(.resized)), nil, "homeForStage: resized: as found")
eq(WindowRestore.homeForStage(.leave(.fullScreen)), nil, "homeForStage: full screen: as found")
eq(WindowRestore.homeForStage(.gone), nil, "homeForStage: gone")

// MARK: The ledger

do {
    var ledger = WindowRestore.Ledger<String>()
    check(ledger.isEmpty, "ledger: empty at first")
    ledger.fitted(7, handle: "seven", before: O, after: Sf, asked: Sz)
    eq(ledger.record(7), first, "ledger: the first fit's record")
    check(!ledger.isEmpty, "ledger: not empty after a fit")
    ledger.fitted(7, handle: "seven again", before: Sf, after: R(100, 100, 500, 800), asked: S(500, 800))
    eq(ledger.entries[7]?.handle, "seven", "ledger: a re-fit keeps the first fit's handle")
    eq(ledger.record(7)?.original, O, "ledger: a re-fit keeps the original")
    eq(ledger.record(7)?.set, R(100, 100, 500, 800), "ledger: a re-fit takes the new frame")
    ledger.fitted(9, handle: "nine", before: R(0, 25, 400, 300), after: R(0, 25, 500, 400), asked: S(500, 400))
    ledger.fitted(3, handle: "three", before: R(10, 30, 400, 300), after: R(10, 30, 500, 400), asked: S(500, 400))
    let out = ledger.stopping(keeping: 7)
    eq(out.map(\.id), [3, 9], "ledger: stopping returns every window but the one kept, in ID order")
    eq(out.map(\.entry.handle), ["three", "nine"], "ledger: with their handles")
    eq(ledger.record(3), nil, "ledger: a stopped window is taken out")
    check(ledger.record(7) != nil, "ledger: the kept window stays")
    eq(ledger.stopping(keeping: 7).count, 0, "ledger: nothing more to stop")
    eq(ledger.stopping(keeping: 42).map(\.id), [7], "ledger: keeping a window it does not have stops every one")
    check(ledger.isEmpty, "ledger: empty after the last stop")
    ledger.fitted(5, handle: "five", before: O, after: Sf, asked: Sz)
    eq(ledger.take(5)?.handle, "five", "ledger: take hands over the entry")
    check(ledger.take(5) == nil, "ledger: taken once")
    check(ledger.isEmpty, "ledger: empty after take")
    ledger.fitted(5, handle: "five, later", before: Sf, after: R(100, 100, 640, 400), asked: S(640, 400))
    eq(ledger.record(5)?.original, Sf, "ledger: after take, a fit starts afresh from where it was")
    eq(ledger.entries[5]?.handle, "five, later", "ledger: with the new handle")
    eq(ledger.stopping(keeping: nil).map(\.id), [5], "ledger: keeping nothing stops every one")
    // In window ID order whatever order the dictionary keeps (its seed is random per process).
    for id in [41, 7, 300, 12, 9, 1024, 2, 77, 5, 64, 1, 900] as [CGWindowID] {
        ledger.fitted(id, handle: "w\(id)", before: O, after: Sf, asked: Sz)
    }
    eq(ledger.stopping(keeping: 77).map(\.id), [1, 2, 5, 7, 9, 12, 41, 64, 300, 900, 1024], "ledger: stopping in window ID order")
    eq(ledger.stopping(keeping: nil).map(\.id), [77], "ledger: then the one kept")
}

// MARK: The lines

let safari = WindowRestore.name(app: "Safari", title: "Apple Developer")
eq(safari, "Safari — Apple Developer", "name: app and title")
eq(WindowRestore.name(app: "Finder", title: ""), "Finder", "name: an untitled window is its app")
eq(WindowRestore.text(R(212, 95, 1280, 800)), "(212,95,1280×800)", "text: a frame as the stage writes it")
eq(WindowRestore.text(R(-1512, 24.4, 1280.6, 800)), "(-1512,24,1281×800)", "text: rounded, a display to the left")
eq(WindowRestore.line(.gone, name: safari, current: nil, done: false), nil, "line: none for a window gone")
eq(WindowRestore.line(.home, name: safari, current: O, done: false), nil, "line: none for a window already home")
eq(WindowRestore.line(.settle(O), name: safari, current: O, done: true), nil, "line: none for a window settled where it was")
eq(WindowRestore.line(.leave(.fullScreen), name: safari, current: R(0, 0, 1512, 982), done: false),
   "Left Safari — Apple Developer as it is: it is full screen", "line: full screen")
eq(WindowRestore.line(.leave(.resized), name: safari, current: R(300, 300, 1000, 700), done: false),
   "Left Safari — Apple Developer at (300,300,1000×700): it was resized on the Mac", "line: resized")
eq(WindowRestore.line(.restore(O, whole: true), name: safari, current: Sf, done: true),
   "Restored Safari — Apple Developer to (100,100,1200×800)", "line: restored whole, in the stage's words")
eq(WindowRestore.line(.restore(R(312, 145, 1200, 800), whole: false), name: safari, current: R(900, 300, 800, 500), done: true),
   "Restored Safari — Apple Developer to (312,145,1200×800), its own size where it was moved", "line: restored, moved")
eq(WindowRestore.line(.restore(O, whole: true), name: safari, current: Sf, done: false),
   "Could not restore Safari — Apple Developer to (100,100,1200×800)", "line: a restore that failed")
eq(WindowRestore.notAnsweringLine(name: safari), "Could not restore Safari — Apple Developer: it is not answering Accessibility",
   "line: an app that does not answer")

// MARK: The sequences: fit, stop, stageHome, Ledger.restore

/// A stand-in window for the sequences' cases: its frame and answers, every call logged in order.
struct One: WindowRestore.Access {
    var at: CGRect?                       // Accessibility's frame; nil: no answer, or gone
    var full = false
    var listed = true
    var screen: CGRect? = area
    var positionAnswer: WindowRestore.Write = .done
    var sizeAnswer: WindowRestore.Write = .done
    var minimum = CGSize.zero             // the app's minimum: what it takes for a smaller size
    var putAnswer = true
    var readBackFails = false             // the read right after a size write that went through gets no answer
    var failNext = false
    var calls: [String] = []
    mutating func frame(_ w: Int) -> CGRect? {
        calls.append("frame")
        if failNext { failNext = false; return nil }
        return at
    }
    mutating func isFullScreen(_ w: Int) -> Bool { calls.append("fullScreen"); return full }
    mutating func isListed(_ w: Int) -> Bool { calls.append("listed"); return listed }
    mutating func visibleArea(around r: CGRect) -> CGRect? { screen }
    mutating func setPosition(_ w: Int, _ p: CGPoint) -> WindowRestore.Write {
        calls.append("position \(Int(p.x)),\(Int(p.y))")
        if positionAnswer == .done { at?.origin = p }
        return positionAnswer
    }
    mutating func setSize(_ w: Int, _ s: CGSize) -> WindowRestore.Write {
        calls.append("size \(Int(s.width))×\(Int(s.height))")
        if sizeAnswer == .done {
            at?.size = CGSize(width: max(s.width, minimum.width), height: max(s.height, minimum.height))
            failNext = readBackFails
        }
        return sizeAnswer
    }
    mutating func put(_ w: Int, at f: CGRect) -> Bool {
        calls.append("put \(WindowRestore.text(f))")
        if putAnswer { at = f }
        return putAnswer
    }
    func name(_ w: Int) -> String { "App — Doc" }
}

do {
    // A window in full screen: nothing read or written but that.
    var a = One(at: R(0, 0, 1512, 982), full: true)
    eq(WindowRestore.fit(1, to: Sz, fallback: .zero, on: &a), .fullScreen, "fit: not in full screen")
    eq(a.calls, ["fullScreen"], "fit: full screen, nothing written")
    // A plain fit: no nudge, the size, the read-back.
    a = One(at: O)
    eq(WindowRestore.fit(1, to: Sz, fallback: .zero, on: &a), .fitted(before: O, after: Sf, timedOut: false), "fit: plain")
    eq(a.calls, ["fullScreen", "frame", "size 800×500", "frame"], "fit: plain, its calls")
    // Near the right edge: nudged left first so the asked frame stays on the display.
    a = One(at: R(900, 100, 600, 400))
    eq(WindowRestore.fit(1, to: Sz, fallback: .zero, on: &a), .fitted(before: R(900, 100, 600, 400), after: R(712, 100, 800, 500), timedOut: false),
       "fit: nudged onto the display")
    eq(a.calls, ["fullScreen", "frame", "position 712,100", "size 800×500", "frame"], "fit: the nudge before the size")
    // The size refused after the nudge: the nudge put back, nothing recorded.
    a = One(at: R(900, 100, 600, 400), sizeAnswer: .refused(-25200))
    eq(WindowRestore.fit(1, to: Sz, fallback: .zero, on: &a), .refused(-25200), "fit: the size refused")
    eq(a.calls, ["fullScreen", "frame", "position 712,100", "size 800×500", "position 900,100"], "fit: the nudge put back after a refusal")
    eq(a.at, R(900, 100, 600, 400), "fit: back where it was after a refusal")
    // Refused without a nudge: nothing to put back.
    a = One(at: O, sizeAnswer: .refused(-25200))
    eq(WindowRestore.fit(1, to: Sz, fallback: .zero, on: &a), .refused(-25200), "fit: refused in place")
    eq(a.calls, ["fullScreen", "frame", "size 800×500"], "fit: refused in place, no move")
    // A window that will not move still resizes, and the second nudge, refused too, leaves it where it took the size.
    a = One(at: R(900, 100, 600, 400), positionAnswer: .refused(-25200))
    eq(WindowRestore.fit(1, to: Sz, fallback: .zero, on: &a), .fitted(before: R(900, 100, 600, 400), after: R(900, 100, 800, 500), timedOut: false),
       "fit: a window that will not move")
    eq(a.calls, ["fullScreen", "frame", "position 712,100", "size 800×500", "frame", "position 712,100"], "fit: both nudges tried")
    // An app's minimum above the size asked: what it took, kept on the display by a second nudge.
    a = One(at: R(700, 100, 600, 400), minimum: S(900, 600))
    eq(WindowRestore.fit(1, to: Sz, fallback: .zero, on: &a), .fitted(before: R(700, 100, 600, 400), after: R(612, 100, 900, 600), timedOut: false),
       "fit: a minimum, nudged after")
    eq(a.calls, ["fullScreen", "frame", "size 800×500", "frame", "position 612,100", "frame"], "fit: the second nudge reads the frame again")
    // A minimum above the size asked, with room for it: what the app took, where it is.
    a = One(at: O, minimum: S(900, 600))
    eq(WindowRestore.fit(1, to: Sz, fallback: .zero, on: &a), .fitted(before: O, after: R(100, 100, 900, 600), timedOut: false), "fit: a minimum, in place")
    // No frame from Accessibility: the window server's frame is the one before, and nothing to nudge
    // from; the size went through, unseen: recorded as a read-back that has not shown it yet.
    a = One(at: nil)
    eq(WindowRestore.fit(1, to: Sz, fallback: O, on: &a), .fitted(before: O, after: O, timedOut: false), "fit: no frame, before or after")
    eq(a.calls, ["fullScreen", "frame", "size 800×500", "frame"], "fit: no frame, no nudge")
    // The size went through, its read-back did not: its old size where it was put (after the nudge).
    a = One(at: R(900, 100, 600, 400), readBackFails: true)
    eq(WindowRestore.fit(1, to: Sz, fallback: .zero, on: &a), .fitted(before: R(900, 100, 600, 400), after: R(712, 100, 600, 400), timedOut: false),
       "fit: a read-back that fails: its old size, where it was put")
    eq(a.calls, ["fullScreen", "frame", "position 712,100", "size 800×500", "frame"], "fit: a read-back that fails, no second nudge")
    // Its record goes back whole whether the size showed by the stop or not, the nudge undone either way.
    let unseen = WindowRestore.fitted(nil, before: R(900, 100, 600, 400), after: R(712, 100, 600, 400), asked: Sz)
    eq(decide(unseen, R(712, 100, 800, 500)), .restore(R(900, 100, 600, 400), whole: true), "decide: an unseen size that showed: back whole")
    eq(decide(unseen, R(712, 100, 600, 400)), .restore(R(900, 100, 600, 400), whole: true), "decide: an unseen size not yet shown: the nudge undone")
    let unseenInPlace = WindowRestore.fitted(nil, before: O, after: O, asked: Sz)
    eq(decide(unseenInPlace, O), .settle(O), "decide: an unseen size in place, not yet shown: settled")
    // The size went unanswered: the nudge put back, the frame as it was, the size asked kept in the record.
    a = One(at: R(900, 100, 600, 400), sizeAnswer: .timedOut)
    eq(WindowRestore.fit(1, to: Sz, fallback: .zero, on: &a), .fitted(before: R(900, 100, 600, 400), after: R(900, 100, 600, 400), timedOut: true),
       "fit: a size with no answer is recorded")
    eq(a.calls, ["fullScreen", "frame", "position 712,100", "size 800×500", "position 900,100"], "fit: no answer: the nudge put back, no read-back")
    a = One(at: O, sizeAnswer: .timedOut)
    eq(WindowRestore.fit(1, to: Sz, fallback: .zero, on: &a), .fitted(before: O, after: O, timedOut: true), "fit: no answer in place")
    eq(a.calls, ["fullScreen", "frame", "size 800×500"], "fit: no answer in place, no move")
    // Its record: the app takes the size later and goes back whole; or never, and its frame is written again.
    let unanswered = WindowRestore.fitted(nil, before: O, after: O, asked: Sz)
    eq(decide(unanswered, Sf), .restore(O, whole: true), "decide: a size that went unanswered and landed later goes back")
    eq(decide(unanswered, O), .settle(O), "decide: a size that went unanswered and never landed: settled")
    // No display: no nudges.
    a = One(at: R(900, 100, 600, 400), screen: nil)
    eq(WindowRestore.fit(1, to: Sz, fallback: .zero, on: &a), .fitted(before: R(900, 100, 600, 400), after: R(900, 100, 800, 500), timedOut: false),
       "fit: no display, no nudge")

    // stop: the rule's decision, and the move it calls for through the window's own element.
    a = One(at: Sf)
    eq(WindowRestore.stop(7, 1, first, on: &a), WindowRestore.Stopped(id: 7, decision: .restore(O, whole: true), done: true,
                                                                        line: "Restored App — Doc to (100,100,1200×800)"), "stop: back whole")
    eq(a.calls, ["frame", "fullScreen", "put (100,100,1200×800)"], "stop: read, then put")
    eq(a.at, O, "stop: where it was")
    a = One(at: Sf, putAnswer: false)
    eq(WindowRestore.stop(7, 1, first, on: &a).line, "Could not restore App — Doc to (100,100,1200×800)", "stop: a put that failed")
    eq(WindowRestore.stop(7, 1, first, on: &a).done, false, "stop: a put that failed is not done")
    a = One(at: nil, listed: true)
    eq(WindowRestore.stop(7, 1, first, on: &a), WindowRestore.Stopped(id: 7, decision: nil, done: false,
                                                                        line: "Could not restore App — Doc: it is not answering Accessibility"),
       "stop: no frame from a listed window: not answering")
    eq(a.calls, ["frame", "listed"], "stop: not answering, no writes")
    a = One(at: nil, listed: false)
    eq(WindowRestore.stop(7, 1, first, on: &a), WindowRestore.Stopped(id: 7, decision: .gone, done: false, line: nil), "stop: gone")
    eq(a.calls, ["frame", "listed"], "stop: gone, no writes")
    a = One(at: Sf, full: true)
    eq(WindowRestore.stop(7, 1, first, on: &a), WindowRestore.Stopped(id: 7, decision: .leave(.fullScreen), done: false,
                                                                        line: "Left App — Doc as it is: it is full screen"), "stop: full screen")
    eq(a.calls, ["frame", "fullScreen"], "stop: full screen, no writes")
    a = One(at: O)
    eq(WindowRestore.stop(7, 1, first, on: &a), WindowRestore.Stopped(id: 7, decision: .home, done: false, line: nil), "stop: home")
    eq(a.calls, ["frame", "fullScreen"], "stop: home, no writes")
    a = One(at: O)
    eq(WindowRestore.stop(7, 1, lagging, on: &a), WindowRestore.Stopped(id: 7, decision: .settle(O), done: true, line: nil), "stop: settled")
    eq(a.calls, ["frame", "fullScreen", "put (100,100,1200×800)"], "stop: settled, written again")
    a = One(at: R(100, 100, 1000, 700))
    eq(WindowRestore.stop(7, 1, first, on: &a).line, "Left App — Doc at (100,100,1000×700): it was resized on the Mac", "stop: resized")
    eq(a.calls, ["frame", "fullScreen"], "stop: resized, no writes")
    a = One(at: R(900, 300, 800, 500))
    eq(WindowRestore.stop(7, 1, first, on: &a).decision, .restore(R(312, 145, 1200, 800), whole: false), "stop: moved, kept on its display")

    // stageHome: the frame it would go back to, nothing moved.
    a = One(at: R(900, 300, 800, 500))
    eq(WindowRestore.stageHome(1, first, on: &a), R(312, 145, 1200, 800), "stageHome: moved")
    eq(a.calls, ["frame", "fullScreen"], "stageHome: reads only")
    a = One(at: O)
    eq(WindowRestore.stageHome(1, first, on: &a), nil, "stageHome: home: as found")
    a = One(at: Sf, full: true)
    eq(WindowRestore.stageHome(1, first, on: &a), nil, "stageHome: full screen: as found")
    a = One(at: nil)
    eq(WindowRestore.stageHome(1, first, on: &a), nil, "stageHome: no frame: as found")
    eq(a.calls, ["frame"], "stageHome: no frame, nothing more")

    // keepsStreaming: a window off the list on its way into or out of full screen keeps streaming.
    let laptop = R(0, 0, 1512, 982), external = R(1512, 0, 1920, 1080)
    a = One(at: nil)
    eq(WindowRestore.keepsStreaming(nil as Int?, looks: 1, wasFullScreen: true, on: &a), true, "keepsStreaming: full screen when last listed")
    eq(WindowRestore.keepsStreaming(nil as Int?, looks: 3, wasFullScreen: true, on: &a), true, "keepsStreaming: through the third look")
    eq(WindowRestore.keepsStreaming(nil as Int?, looks: 4, wasFullScreen: true, on: &a), false, "keepsStreaming: not a fourth")
    eq(WindowRestore.keepsStreaming(nil as Int?, looks: 1, wasFullScreen: false, on: &a), false, "keepsStreaming: never full screen: it stops")
    eq(a.calls, [], "keepsStreaming: a window Sill did not fit is not asked")
    a = One(at: Sf, full: true, listed: false)
    eq(WindowRestore.keepsStreaming(1, looks: 1, wasFullScreen: false, on: &a), true, "keepsStreaming: fitted, Accessibility says full screen")
    eq(a.calls, ["frame", "fullScreen"], "keepsStreaming: a frame, then full screen")
    a = One(at: Sf, full: false, listed: false)
    eq(WindowRestore.keepsStreaming(1, looks: 1, wasFullScreen: false, on: &a), false, "keepsStreaming: fitted, not full screen, never listed so: it stops")
    eq(WindowRestore.keepsStreaming(1, looks: 2, wasFullScreen: true, on: &a), true, "keepsStreaming: fitted, full screen when last listed, the flag already down")
    eq(WindowRestore.keepsStreaming(1, looks: 4, wasFullScreen: true, on: &a), false, "keepsStreaming: fitted, not a fourth look")
    a = One(at: nil, full: true, listed: false)
    eq(WindowRestore.keepsStreaming(1, looks: 1, wasFullScreen: true, on: &a), false, "keepsStreaming: fitted and gone (no frame, not listed): it stops")
    a = One(at: nil, full: true, listed: true)
    eq(WindowRestore.keepsStreaming(1, looks: 1, wasFullScreen: false, on: &a), true, "keepsStreaming: no frame but listed is not gone")
    // coversDisplay: a full-screen window's listed frame.
    eq(WindowRestore.coversDisplay(laptop, [laptop, external]), true, "coversDisplay: the laptop's whole display")
    eq(WindowRestore.coversDisplay(external, [laptop, external]), true, "coversDisplay: the external display")
    eq(WindowRestore.coversDisplay(R(0, 25, 1512, 957), [laptop]), false, "coversDisplay: the area under the menu bar is a window's")
    eq(WindowRestore.coversDisplay(R(0, 1, 1512, 981), [laptop]), true, "coversDisplay: a point short at the top still counts")
    eq(WindowRestore.coversDisplay(R(0, 2, 1512, 980), [laptop]), false, "coversDisplay: two points short at the top does not")
    eq(WindowRestore.coversDisplay(R(0, 0, 1482, 982), [laptop]), true, "coversDisplay: 98 % of it")
    eq(WindowRestore.coversDisplay(R(0, 0, 1481, 982), [laptop]), false, "coversDisplay: under 98 %")
    eq(WindowRestore.coversDisplay(R(-10, -10, 1600, 1100), [laptop]), true, "coversDisplay: larger than the display")
    eq(WindowRestore.coversDisplay(R(1000, 0, 1512, 982), [laptop, external]), false, "coversDisplay: across two displays, all of neither")
    eq(WindowRestore.coversDisplay(laptop, []), false, "coversDisplay: no display")
    eq(WindowRestore.coversDisplay(laptop, [R(0, 0, 0, 0)]), false, "coversDisplay: an empty display")

    // Ledger.restore: every window but the one kept, in window ID order, but the staged one, which is taken out unasked.
    var ledger = WindowRestore.Ledger<Int>()
    ledger.fitted(9, handle: 1, before: O, after: Sf, asked: Sz)
    ledger.fitted(4, handle: 1, before: O, after: Sf, asked: Sz)
    ledger.fitted(6, handle: 1, before: O, after: Sf, asked: Sz)
    ledger.fitted(2, handle: 1, before: O, after: Sf, asked: Sz)
    a = One(at: Sf)
    let stopped = ledger.restore(keeping: 4, staged: 6, on: &a)
    eq(stopped.map(\.id), [2, 9], "Ledger.restore: in ID order, the kept and the staged left out")
    eq(stopped.map(\.decision), [.restore(O, whole: true), .home], "Ledger.restore: each decided as it is then")
    eq(ledger.record(6), nil, "Ledger.restore: the staged window's record taken out")
    check(ledger.record(4) != nil, "Ledger.restore: the kept window's record stays")
    eq(ledger.restore(keeping: nil, staged: nil, on: &a).map(\.id), [4], "Ledger.restore: then the one kept")
}

let unitPasses = passes
let unitFailures = failures
print("window-restore: the rule, \(unitPasses + unitFailures) cases, \(unitFailures) failed")

// MARK: The model: a stand-in Mac, and a copy of the coordinator's glue around the real sequences

/// A seeded generator, so a failing session can be run again.
struct RNG {
    var s: UInt64
    mutating func next() -> UInt64 {
        s &+= 0x9E3779B97F4A7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    mutating func range(_ lo: Int, _ hi: Int) -> CGFloat { CGFloat(lo + int(hi - lo + 1)) }
    mutating func chance(_ p: Double) -> Bool { Double(next() % 1_000_000) / 1_000_000 < p }
}

/// How an app takes a size: its minimum, a grid it snaps down to, whether it applies a size only after
/// answering the write (Accessibility then reads the old one until it does), and whether its window
/// cannot be resized at all (it refuses the size, -25200, as the restore probe's step 9 measured).
struct AppKind {
    var minSize: CGSize; var grid: CGFloat; var late: Bool; var fixed = false
    /// Busy: a size write gets no answer in time (half of them); it lands at the next look, or (a
    /// quarter of a fit's) never. Only apps that take any size asked are slow or flaky here: a size that
    /// lands unseen, or a read-back that fails, is taken as the size asked, which an app that clamps or
    /// snaps does not keep.
    var slow = false
    /// The read right after a size write that went through gets no answer (half the time).
    var flaky = false
}

struct Win {
    var frame: CGRect
    var app: AppKind
    var closed = false
    var fullScreen = false
    var beforeFullScreen: CGRect = .zero
    var pendingSize: CGSize?
    var failNextRead = false
    /// Entering or leaving full screen: off every list for this many more steps, Accessibility reading
    /// `transitionFrame` and `transitionFlag` (AXFullScreen) meanwhile, every write refused.
    var transition = 0
    var transitionFlag = false
    var transitionFrame: CGRect = .zero
}

/// The Mac: two displays, the windows, and Accessibility's view of them, answering the sequences'
/// reads and writes as WindowSizer.AXWindows does. Every write it takes marks the window touched.
struct Mac: WindowRestore.Access {
    static let displays = [R(0, 0, 1512, 982), R(1512, 0, 1920, 1080)]
    static let visible = [R(0, 25, 1512, 920), R(1512, 25, 1920, 1055)]
    static let virtualDisplay = R(6000, 0, 2400, 2400)
    var wins: [CGWindowID: Win] = [:]
    var touched: Set<CGWindowID> = []
    /// How a window in a full-screen Space answers a move or a size, which nobody has measured: an
    /// error (-25200), or success while nothing changes. Each session takes one.
    var fullScreenWritesDone = false
    /// For a slow or flaky app's answers, write by write.
    var dice = RNG(s: 1)
    /// Inside `put`: a slow app's size that goes unanswered lands at the next look all the same.
    var putting = false
    var readsFailed = 0

    /// WindowSizer.visibleArea: the display holding most of the rect (the first on a tie).
    static func area(around r: CGRect) -> CGRect {
        func overlap(_ a: CGRect) -> CGFloat { let i = a.intersection(r); return i.isNull ? 0 : i.width * i.height }
        var best = visible[0]
        for a in visible.dropFirst() where overlap(a) > overlap(best) { best = a }
        return best
    }
    static func takes(_ app: AppKind, _ s: CGSize) -> CGSize {
        var w = max(s.width, app.minSize.width), h = max(s.height, app.minSize.height)
        if app.grid > 1 { w = (w / app.grid).rounded(.down) * app.grid; h = (h / app.grid).rounded(.down) * app.grid }
        return S(max(w, app.minSize.width), max(h, app.minSize.height))
    }
    /// Accessibility's frame: nil for a window gone; a late app's old size until it applies; whatever it
    /// reads mid-way into or out of full screen.
    func ax(_ id: CGWindowID) -> CGRect? {
        guard let w = wins[id], !w.closed else { return nil }
        return w.transition > 0 ? w.transitionFrame : w.frame
    }
    /// A step of time: a window on its way into or out of full screen gets there.
    mutating func tick() {
        for id in wins.keys where wins[id]!.transition > 0 { wins[id]!.transition -= 1 }
    }
    mutating func applyLate() {
        for (id, w) in wins where w.pendingSize != nil {
            if !w.closed { wins[id]!.frame.size = w.pendingSize! }
            wins[id]!.pendingSize = nil
        }
        for id in wins.keys { wins[id]!.failNextRead = false }
    }

    mutating func frame(_ id: CGWindowID) -> CGRect? {
        if wins[id]?.failNextRead == true { wins[id]!.failNextRead = false; readsFailed += 1; return nil }
        return ax(id)
    }
    mutating func isFullScreen(_ id: CGWindowID) -> Bool {
        guard let w = wins[id] else { return false }
        return w.transition > 0 ? w.transitionFlag : w.fullScreen
    }
    mutating func isListed(_ id: CGWindowID) -> Bool { ax(id) != nil && wins[id]!.transition == 0 }
    mutating func visibleArea(around r: CGRect) -> CGRect? { Mac.area(around: r) }
    mutating func setPosition(_ id: CGWindowID, _ p: CGPoint) -> WindowRestore.Write {
        guard let w = wins[id], !w.closed else { return .refused(-25202) }
        if w.transition > 0 { return .refused(-25200) }
        if w.fullScreen { return fullScreenWritesDone ? .done : .refused(-25200) }
        wins[id]!.frame.origin = p
        touched.insert(id)
        return .done
    }
    mutating func setSize(_ id: CGWindowID, _ s: CGSize) -> WindowRestore.Write {
        guard let w = wins[id], !w.closed else { return .refused(-25202) }
        if w.transition > 0 { return .refused(-25200) }
        if w.fullScreen { return fullScreenWritesDone ? .done : .refused(-25200) }
        if w.app.fixed { return .refused(-25200) }
        let took = Self.takes(w.app, s)
        touched.insert(id)
        if w.app.slow, dice.chance(0.5) {
            // Queued behind any earlier size: the last one wins when the app gets to them.
            if putting || dice.chance(0.75) { wins[id]!.pendingSize = took }
            return .timedOut
        }
        // Answered: whatever was queued before it has been taken, and this comes after.
        if w.app.late { wins[id]!.pendingSize = took } else { wins[id]!.pendingSize = nil; wins[id]!.frame.size = took }
        if w.app.flaky, dice.chance(0.5) { wins[id]!.failNextRead = true }
        return .done
    }
    /// WindowSizer.restore: position, size, position, and once more while the window is listed when an
    /// answer did not come in time; a window gone is nothing to move.
    mutating func put(_ id: CGWindowID, at f: CGRect) -> Bool {
        guard ax(id) != nil else { return true }
        putting = true
        defer { putting = false }
        var answers = [setPosition(id, f.origin), setSize(id, f.size), setPosition(id, f.origin)]
        if answers.contains(.timedOut), isListed(id) {
            answers = [setPosition(id, f.origin), setSize(id, f.size), setPosition(id, f.origin)]
        }
        return answers.allSatisfy { $0 == .done }
    }
    func name(_ id: CGWindowID) -> String { "App\(id) — Doc\(id)" }
}

enum Source: Equatable { case none, desktop, window(CGWindowID) }

/// What the person at the Mac expects of one window through a spell of Sill's fits.
struct Spell {
    var original: CGRect
    var moved = false
    var resizedSinceFit = false
    var movedSinceFit = false
    var resizesSinceFit = 0
    var fromAnEdgeSinceFit = false
    /// It left full screen while it streamed (the review's finding 1).
    var leftFullScreen = false
    /// A move and a resize, or two resizes, between two fits: the rule sees only where they ended, which
    /// a move and a resize from an edge can both explain, so either way back is right from then on.
    var loose = false
}

struct Model {
    var mac = Mac()
    let seed: UInt64
    var rng: RNG
    /// For what the model's first version did not have (full-screen answers, windows that cannot be
    /// resized), so each session keeps its windows and steps.
    var side: RNG
    var ledger = WindowRestore.Ledger<CGWindowID>()
    var active: Source = .none
    var panel: CGSize? = nil
    var scale: CGFloat? = nil
    var vd = false
    var staged: (id: CGWindowID, home: CGRect)? = nil
    var encoderSize: CGSize? = nil
    var shuttingDown = false
    // windowsChanged's: the streamed window was full screen when last listed, and its looks off the list.
    var listedFullScreen: CGWindowID? = nil
    var missingLooks = 0
    // The oracle.
    var spells: [CGWindowID: Spell] = [:]
    var expectHome: [CGWindowID: [CGRect]] = [:]    // a staged window's way home
    var personFrame: [CGWindowID: CGRect] = [:]     // a window Sill never touched: where the person left it
    var log: [String] = []
    var seen: [String: Int] = [:]

    init(seed: UInt64) {
        self.seed = seed
        rng = RNG(s: seed)
        side = RNG(s: seed ^ 0x5EED_5EED)
        mac.fullScreenWritesDone = side.chance(0.5)
        mac.dice = RNG(s: side.next())
        let kinds = [AppKind(minSize: S(200, 150), grid: 1, late: false), AppKind(minSize: S(700, 450), grid: 1, late: false),
                     AppKind(minSize: S(300, 200), grid: 7, late: false), AppKind(minSize: S(200, 150), grid: 1, late: true)]
        for id in CGWindowID(1)...CGWindowID(4) {
            let app = kinds[rng.int(kinds.count)]
            let size = Mac.takes(app, S(rng.range(400, 1300), rng.range(300, 860)))
            let a = Mac.visible[rng.int(2)]
            let origin = P(a.minX + rng.range(0, Int(max(0, a.width - size.width))), a.minY + rng.range(0, Int(max(0, a.height - size.height))))
            var kind = app
            if side.chance(0.1) { kind.fixed = true }
            if kind.minSize.width <= 200, kind.grid == 1 {
                if side.chance(0.25) { kind.slow = true }
                if side.chance(0.25) { kind.flaky = true }
            }
            mac.wins[id] = Win(frame: CGRect(origin: origin, size: size), app: kind)
            personFrame[id] = mac.wins[id]!.frame
        }
    }

    mutating func note(_ s: String) { seen[s, default: 0] += 1 }

    // StreamCoordinator.fitToViewport, around WindowSizer.resize's sequence (WindowRestore.fit).
    mutating func fit(_ id: CGWindowID) {
        guard !shuttingDown, let panel, let scale, scale > 0 else { return }
        let target = S((panel.width / scale).rounded(), (panel.height / scale).rounded())
        guard let current = mac.wins[id], !current.closed else { return }
        if abs(current.frame.width - target.width) <= 2, abs(current.frame.height - target.height) <= 2 { return }
        let readsFailed = mac.readsFailed
        let axBefore = mac.ax(id)
        defer { if mac.readsFailed > readsFailed { note("read-back failed") } }
        switch WindowRestore.fit(id, to: target, fallback: current.frame, on: &mac) {
        case .fullScreen:
            note("fit: full screen")
        case .refused:
            note("fit refused")
            // Refused, with any nudge made for it put back: where it was.
            check(mac.ax(id) == axBefore, "model seed \(seed): window \(id) moved by a refused fit, from \(String(describing: axBefore)) to \(String(describing: mac.ax(id)))")
        case .fitted(let before, let after, let timedOut):
            if timedOut { note("fit: no answer") }
            let had = ledger.record(id) != nil
            ledger.fitted(id, handle: id, before: before, after: after, asked: target)
            if had, var sp = spells[id] {
                if (sp.movedSinceFit && sp.resizesSinceFit > 0) || sp.resizesSinceFit > 1 { sp.loose = true; note("compound changes between fits") }
                else if sp.fromAnEdgeSinceFit { note("re-fit after a resize from an edge") }
                sp.resizedSinceFit = false; sp.movedSinceFit = false; sp.resizesSinceFit = 0; sp.fromAnEdgeSinceFit = false
                spells[id] = sp
                note("re-fit")
            } else if !had {
                spells[id] = Spell(original: before); note("first fit")
            }
        }
    }

    /// Where the person expects a window of a spell to end when it stops streaming now (either of two
    /// after changes the rule cannot tell apart).
    func expected(_ id: CGWindowID) -> [CGRect]? {
        guard let w = mac.wins[id], !w.closed, let spell = spells[id] else { return nil }
        if w.fullScreen || spell.resizedSinceFit { return [w.frame] }
        let size = Mac.takes(w.app, spell.original.size)
        let whole = CGRect(origin: spell.original.origin, size: size)
        let target = CGRect(origin: w.frame.origin, size: spell.original.size)
        let kept = CGRect(origin: WindowRestore.keep(target, in: Mac.area(around: w.frame)), size: size)
        if spell.loose { return [whole, kept] }
        return [spell.moved ? kept : whole]
    }

    // StreamCoordinator.restoreFits: the ledger's restore (WindowRestore.stop for each), then the lines.
    mutating func restoreFits(keeping keep: CGWindowID?, why: String) {
        // What the person expects of each window about to stop, before anything moves.
        var wants: [CGWindowID: [CGRect]] = [:]
        var midway: Set<CGWindowID> = []
        for id in ledger.entries.keys where id != keep {
            wants[id] = expected(id)
            if (mac.wins[id]?.transition ?? 0) > 0 { midway.insert(id) }
        }
        if let s = staged?.id, s != keep, ledger.record(s) != nil { note("skipped: staged"); spells[s] = nil }
        let stopped = ledger.restore(keeping: keep, staged: staged?.id, on: &mac)
        mac.applyLate()          // a late app applies the restore's size before anyone looks
        for st in stopped {
            let id = st.id
            switch st.decision {
            case nil: note("decision: not answering")
            case .gone?: note("decision: gone")
            case .home?: note("decision: home")
            case .settle?: note("decision: settle")
            case .leave(.fullScreen)?: note("decision: full screen")
            case .leave(.resized)?: note("decision: resized")
            case .restore(_, whole: true)?: note("decision: whole")
            case .restore(_, whole: false)?: note("decision: moved")
            }
            note(st.decision == .gone ? "stop: gone" : "stop: \(why)")
            if midway.contains(id) {
                // The residual: a pick, Disconnect, Quit or a restart within the second a window takes to
                // enter or leave full screen. Its frame then is no way to judge it; every write is refused.
                note("stop during a full-screen transition")
                spells[id] = nil
                continue
            }
            if spells[id]?.leftFullScreen == true, case .restore? = st.decision { note("went back after leaving full screen while it streamed") }
            if case .restore(let f, let whole)? = st.decision, st.done {
                let name = mac.name(id)
                eq(st.line, whole ? "Restored \(name) to \(WindowRestore.text(f))" : "Restored \(name) to \(WindowRestore.text(f)), its own size where it was moved",
                   "model seed \(seed): window \(id)'s line")
            }
            if st.decision != .gone, let want = wants[id] ?? nil, let now = mac.ax(id) {
                check(want.contains { WindowRestore.same(now, $0) }, "model seed \(seed): window \(id) stopped (\(why), \(String(describing: st.decision))) at \(now), the person expects \(want); \(log.suffix(8))")
            }
            spells[id] = nil
        }
    }

    // StreamCoordinator.stageHome and VirtualStage.prepare (step 5's placement, then the move).
    mutating func stage(_ id: CGWindowID) -> Bool {
        guard let w = mac.wins[id], !w.closed, !w.fullScreen, w.transition == 0, let current = mac.ax(id) else { note("staging failed"); return false }
        var home: CGRect? = nil
        if let r = ledger.record(id) {
            home = WindowRestore.stageHome(id, r, on: &mac)
            note(home == nil ? "staged: as found" : "staged: with a home")
            expectHome[id] = expected(id)
        } else {
            expectHome[id] = [current]
        }
        let placementHome = home ?? current
        let size = S((panel.map { $0.width / (scale ?? 1) } ?? current.width).rounded(), (panel.map { $0.height / (scale ?? 1) } ?? current.height).rounded())
        _ = mac.put(id, at: CGRect(origin: Mac.virtualDisplay.origin, size: size))
        mac.applyLate()
        staged = (id, placementHome)
        _ = ledger.take(id)
        spells[id] = nil
        return true
    }

    // VirtualStage.releaseWindow.
    mutating func releaseStage() {
        guard let s = staged else { return }
        staged = nil
        if mac.ax(s.id) != nil {
            _ = mac.put(s.id, at: s.home)
            mac.applyLate()
            note("stage released")
            if let want = expectHome[s.id], let now = mac.ax(s.id) {
                let app = mac.wins[s.id]!.app
                check(want.contains { WindowRestore.same(now, $0) || WindowRestore.same(now, CGRect(origin: $0.origin, size: Mac.takes(app, $0.size))) },
                      "model seed \(seed): staged window \(s.id) went home to \(now), expected \(want); \(log.suffix(8))")
            }
        }
        expectHome[s.id] = nil
    }
    // StreamCoordinator.select, the parts that bear on fitted and staged windows.
    mutating func select(_ source: Source) {
        guard !shuttingDown else { return }
        if source != active { missingLooks = 0 }
        if vd {
            if case .window(let id) = source { if let s = staged, s.id != id { releaseStage() } } else { releaseStage() }
        }
        if case .window(let next) = source {
            restoreFits(keeping: next, why: active == source ? "restart" : (active == .none ? "pick" : "switch"))
        } else {
            restoreFits(keeping: nil, why: source == .desktop ? "desktop" : "none")
        }
        switch source {
        case .none:
            active = .none
        case .desktop:
            active = .desktop
            encoderSize = nil
        case .window(let id):
            // The catalog's on-screen list (the full list on the virtual display's path).
            guard let w = mac.wins[id], !w.closed, vd || w.transition == 0 else {
                if vd { releaseStage() }
                active = .none
                restoreFits(keeping: nil, why: "window gone")      // the defer
                return
            }
            listedFullScreen = WindowRestore.coversDisplay(w.frame, Mac.displays) ? id : nil
            if vd, staged?.id == id {
                // A re-place on the same display: the stage keeps its home.
            } else if vd, stage(id) {
            } else {
                if vd { releaseStage() }                           // the fallback streams the real window
                fit(id)
            }
            active = .window(id)
            encoderSize = mac.wins[id]!.frame.size
        }
        if active == .none { restoreFits(keeping: nil, why: "nothing streams") }
    }

    mutating func personMove(_ id: CGWindowID) {
        guard var w = mac.wins[id], !w.closed, !w.fullScreen, w.transition == 0, staged?.id != id else { return }
        let a = Mac.visible[rng.int(2)]
        var p = P(a.minX + rng.range(0, Int(max(0, a.width - 200))), a.minY + rng.range(0, Int(max(0, a.height - 150))))
        // Never within a few points of where Sill left it: there a move and none are the same.
        if let set = ledger.record(id)?.set, abs(p.x - set.minX) <= 4, abs(p.y - set.minY) <= 4 { p.x += 40 }
        if abs(p.x - w.frame.minX) <= 4, abs(p.y - w.frame.minY) <= 4 { p.y += 40 }
        w.frame.origin = p
        mac.wins[id] = w
        if spells[id] != nil { spells[id]!.moved = true; spells[id]!.movedSinceFit = true }
        if !mac.touched.contains(id) { personFrame[id] = w.frame }
        log.append("person moved \(id) to \(p)")
    }

    mutating func personResize(_ id: CGWindowID) {
        guard var w = mac.wins[id], !w.closed, !w.fullScreen, w.transition == 0, staged?.id != id else { return }
        var s = Mac.takes(w.app, S(rng.range(300, 1400), rng.range(200, 900)))
        // A resize the rule can see: off what Sill left and asked for by more than its tolerance.
        if let r = ledger.record(id) {
            for _ in 0..<4 where WindowRestore.same(s, r.set.size) || WindowRestore.same(s, r.asked) || WindowRestore.same(s, w.frame.size) {
                s = Mac.takes(w.app, S(s.width + 50, s.height + 30))
            }
            if WindowRestore.same(s, r.set.size) || WindowRestore.same(s, r.asked) { return }
        }
        if WindowRestore.same(s, w.frame.size) { return }
        // From the bottom-right corner (the top-left kept), the left edge (the right kept), the top (the
        // bottom kept), the top-left corner, or with Option held (the middle kept).
        let was = w.frame
        switch side.int(5) {
        case 0: w.frame.size = s
        case 1: w.frame = R(was.maxX - s.width, was.minY, s.width, s.height)
        case 2: w.frame = R(was.minX, was.maxY - s.height, s.width, s.height)
        case 3: w.frame = R(was.maxX - s.width, was.maxY - s.height, s.width, s.height)
        default: w.frame = R((was.midX - s.width / 2).rounded(), (was.midY - s.height / 2).rounded(), s.width, s.height)
        }
        if w.frame.origin != was.origin { note("person resized from an edge"); spells[id]?.fromAnEdgeSinceFit = true }
        w.pendingSize = nil
        mac.wins[id] = w
        if spells[id] != nil { spells[id]!.resizedSinceFit = true; spells[id]!.resizesSinceFit += 1 }
        if !mac.touched.contains(id) { personFrame[id] = w.frame }
        log.append("person resized \(id) to \(s)")
    }

    mutating func toggleFullScreen(_ id: CGWindowID) {
        guard var w = mac.wins[id], !w.closed, staged?.id != id, w.pendingSize == nil, w.transition == 0 else { return }
        let from = w.frame
        if w.fullScreen {
            w.fullScreen = false
            w.frame = w.beforeFullScreen
            if active == .window(id) { spells[id]?.leftFullScreen = true }
        } else {
            w.beforeFullScreen = w.frame
            w.fullScreen = true
            w.frame = Mac.displays[Mac.visible.firstIndex(of: Mac.area(around: w.frame)) ?? 0]
        }
        // On the way, off every list for a step or two, Accessibility reading the flag already flipped or
        // not yet, and the frame it came from, the one it goes to, or one between.
        if side.chance(0.6) {
            w.transition = 1 + side.int(2)
            w.transitionFlag = side.chance(0.5)
            switch side.int(3) {
            case 0: w.transitionFrame = from
            case 1: w.transitionFrame = w.frame
            default: w.transitionFrame = R(((from.minX + w.frame.minX) / 2).rounded(), ((from.minY + w.frame.minY) / 2).rounded(),
                                           ((from.width + w.frame.width) / 2).rounded(), ((from.height + w.frame.height) / 2).rounded())
            }
            note(w.fullScreen ? "entering full screen, off the list" : "leaving full screen, off the list")
        }
        mac.wins[id] = w
        log.append("full screen \(id) \(w.fullScreen)\(w.transition > 0 ? " (off the list \(w.transition), AX \(w.transitionFlag) \(w.transitionFrame))" : "")")
    }

    /// The catalog's poll (windowsChanged): a closed streamed window stops; a regular window whose
    /// size left the encoder's restarts, and the restart fits it again.
    mutating func poll() {
        guard case .window(let id) = active, let w = mac.wins[id] else { return }
        if w.closed || w.transition > 0 {
            // Off the list: closed, or on its way into or out of full screen (a staged window cannot be).
            missingLooks += 1
            let fitted: CGWindowID? = ledger.record(id) != nil ? id : nil
            let evidence = listedFullScreen == id || (fitted != nil && mac.isFullScreen(id))
            let keeps = WindowRestore.keepsStreaming(fitted, looks: missingLooks, wasFullScreen: listedFullScreen == id, on: &mac)
            // Gone is Accessibility's to say, so only for a window Sill fitted; another closed window's
            // capture stops (StreamCoordinator's capture.onStopped), which this model leaves out.
            check(keeps == (missingLooks <= WindowRestore.fullScreenGrace && (fitted != nil ? !w.closed && evidence : listedFullScreen == id)),
                  "model seed \(seed): window \(id) off the list (closed \(w.closed), look \(missingLooks), evidence \(evidence)) kept streaming: \(keeps); \(log.suffix(6))")
            if keeps { note("kept streaming off the list"); return }
            missingLooks = 0
            select(.none)
            return
        }
        missingLooks = 0
        listedFullScreen = WindowRestore.coversDisplay(w.frame, Mac.displays) ? id : nil
        if staged?.id == id { return }
        if let e = encoderSize, !WindowRestore.same(e, w.frame.size) { note("poll restart"); select(active) }
    }

    mutating func step() {
        mac.tick()
        mac.applyLate()
        let ids = Array(mac.wins.keys).sorted()
        let id = ids[rng.int(ids.count)]
        switch rng.int(100) {
        case 0..<16:
            log.append("pick \(id)"); select(.window(id))
        case 16..<20:
            log.append("pick desktop"); select(.desktop)
        case 20..<34:
            let panels = [S(1000, 710), S(710, 1000), S(1133, 744), S(386, 241), S(500, 710)]
            let scales: [CGFloat?] = [nil, 0.5, 0.75, 1, 1.25, 1.5]
            panel = panels[rng.int(panels.count)]
            scale = scales[rng.int(scales.count)]
            log.append("viewport \(panel!) at \(scale.map { "\($0)" } ?? "nil")")
            if case .window(let a) = active {
                if vd, staged?.id == a { _ = mac.put(a, at: CGRect(origin: Mac.virtualDisplay.origin, size: S((panel!.width / (scale ?? 1)).rounded(), (panel!.height / (scale ?? 1)).rounded()))) }
                else { fit(a) }       // the encoder keeps its size: the next poll restarts
            }
        case 34..<38:
            log.append("restart"); if active != .none { select(active) }
        case 38..<50:
            poll()
        case 50..<62:
            personMove(id)
        case 62..<70:
            personResize(id)
        case 70..<73:
            log.append("close \(id)")
            if var w = mac.wins[id], !w.closed { w.closed = true; mac.wins[id] = w }
            poll()
        case 73..<77:
            if case .window(let a) = active, side.chance(0.5) { toggleFullScreen(a) } else { toggleFullScreen(id) }
        case 77..<82:
            log.append("virtual display \(vd ? "off" : "on")")
            if vd {
                releaseStage()
                vd = false
                if case .window = active { select(active) }
            } else {
                vd = true
                if case .window = active { select(active) }
            }
        case 82..<88:
            log.append("last device left"); panel = nil; scale = nil
            if active != .none { select(.none) }
        default:
            break
        }
    }

    mutating func quit() {
        log.append("quit")
        shuttingDown = true
        restoreFits(keeping: nil, why: "quit")
        releaseStage()
        check(ledger.isEmpty, "model seed \(seed): records left after Quit")
        check(staged == nil, "model seed \(seed): a window left staged after Quit")
        // A window Sill never touched is where the person left it.
        for (id, w) in mac.wins where !w.closed && !mac.touched.contains(id) && !w.fullScreen {
            check(w.frame == personFrame[id], "model seed \(seed): window \(id), never sized, moved from \(personFrame[id]!) to \(w.frame)")
        }
    }
}

let sessions = 5_000
var globalSeen: [String: Int] = [:]
for n in 0..<sessions {
    var m = Model(seed: UInt64(n) &* 7919 &+ 17)
    let steps = 20 + m.rng.int(60)
    for _ in 0..<steps { m.step() }
    m.quit()
    for (k, v) in m.seen { globalSeen[k, default: 0] += v }
}

// Every transition the issue names, and every outcome, came up.
let needed = ["first fit", "re-fit", "fit refused", "fit: full screen", "fit: no answer", "read-back failed", "person resized from an edge",
              "compound changes between fits", "re-fit after a resize from an edge", "entering full screen, off the list",
              "leaving full screen, off the list", "kept streaming off the list", "stop during a full-screen transition",
              "went back after leaving full screen while it streamed", "stop: switch", "stop: desktop", "stop: none", "stop: quit", "stop: gone", "decision: whole", "decision: moved", "decision: resized", "decision: full screen", "decision: home", "decision: settle",
              "staged: with a home", "staged: as found", "stage released", "poll restart"]
for k in needed { check((globalSeen[k] ?? 0) > 0, "model: never came up: \(k)") }
print("window-restore: the model, \(sessions) sessions: " + needed.map { "\($0) \(globalSeen[$0] ?? 0)" }.joined(separator: ", "))

// Display wake on connect & input, and restart on screen wake (issue #134):
typealias DWP = DisplayWakePolicy
check(DWP.inputThrottle == 2.0 && DWP.wakeRestartDelay == 1.0, "DisplayWakePolicy constants")
check(DWP.shouldDeclareActivity(isConnect: true, lastDeclaredAt: 10.0, now: 10.5, synthetic: false) == true,
      "connect always declares activity even within throttle window")
check(DWP.shouldDeclareActivity(isConnect: false, lastDeclaredAt: nil, now: 10.0, synthetic: false) == true,
      "first input declares activity")
check(DWP.shouldDeclareActivity(isConnect: false, lastDeclaredAt: 10.0, now: 11.9, synthetic: false) == false,
      "input within 2.0 s throttle does not declare activity again")
check(DWP.shouldDeclareActivity(isConnect: false, lastDeclaredAt: 10.0, now: 12.0, synthetic: false) == true,
      "input at 2.0 s declares activity")
check(DWP.shouldDeclareActivity(isConnect: true, lastDeclaredAt: nil, now: 10.0, synthetic: true) == false,
      "synthetic host never declares user activity")
check(DWP.holdsSleepAssertion(connectedDevices: 1, synthetic: false) == true
      && DWP.holdsSleepAssertion(connectedDevices: 0, synthetic: false) == false
      && DWP.holdsSleepAssertion(connectedDevices: 1, synthetic: true) == false,
      "sleep assertion held only while connectedDevices > 0 and not synthetic")
check(DWP.shouldRestartOnScreenWake(connectedDevices: 1, active: true, shuttingDown: false, synthetic: false) == true
      && DWP.shouldRestartOnScreenWake(connectedDevices: 0, active: true, shuttingDown: false, synthetic: false) == false
      && DWP.shouldRestartOnScreenWake(connectedDevices: 1, active: false, shuttingDown: false, synthetic: false) == false
      && DWP.shouldRestartOnScreenWake(connectedDevices: 1, active: true, shuttingDown: true, synthetic: false) == false
      && DWP.shouldRestartOnScreenWake(connectedDevices: 1, active: true, shuttingDown: false, synthetic: true) == false,
      "shouldRestartOnScreenWake requires connected client, active source, not shuttingDown, not synthetic")

if failures == 0 {
    print("window-restore: all \(passes) checks passed")
    exit(0)
} else {
    print("window-restore: \(failures) of \(passes + failures) checks FAILED")
    exit(1)
}
