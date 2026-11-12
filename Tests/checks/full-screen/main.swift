// Full screen's rules on their own (iOSClient/FullScreenPolicy.swift; docs/full-screen-plan.md): the swipe in's
// start (EdgeSwipe) by cases at the numbers' edges, sampled at 60, 120 and 240 Hz, then 30,000 random strokes
// against an independent model and the invariants; the rest of the swipe in (EdgeReveal), the preview's cut over
// the picture's place in every layout, with the layouts' own geometry (RevealCut, DuoPosture's split and
// PhonePortraitLayout), the pointer at the edge (EdgeDwell), when it is offered and must show, the shake, the
// Settings rows' place, the hint, the room, the levels and the words.
import CoreGraphics
import Foundation

var failures = 0
var checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String) {
    checks += 1
    if !ok {
        failures += 1
        if failures <= 60 { print("FAIL " + what()) }
    }
}

// MARK: - Strokes

/// A touch as a list of samples (x from the window's left edge, y, t), fed to the rule as the recognizer feeds
/// it: the first a landing (in a window whose band is `band`, alone unless `alone` is false), the rest moves,
/// the last the lift (unless `lift` is false: still down); then the clock's `ticks`.
struct Stroke {
    var points: [(x: Double, y: Double, t: Double)]
    var lift = true
    var ticks: [Double] = []
    var band = EdgeSwipe.band
    var alone = true

    func run() -> (verdict: EdgeSwipe.Verdict, decidedAt: Int?) {
        var rule = EdgeSwipe()
        var decidedAt: Int? = nil
        for (i, p) in points.enumerated() {
            let v: EdgeSwipe.Verdict
            if i == 0 { v = rule.began(x: p.x, y: p.y, t: p.t, band: band, alone: alone) }
            else if i == points.count - 1, lift { v = rule.ended(x: p.x, y: p.y, t: p.t) }
            else { v = rule.moved(x: p.x, y: p.y, t: p.t) }
            if v.decided, decidedAt == nil { decidedAt = i }
        }
        for t in ticks {
            if rule.tick(t: t).decided, decidedAt == nil { decidedAt = points.count }
        }
        return (rule.verdict, decidedAt)
    }
}

/// A straight stroke: lands at (x0, y0), moves to (x1, y1) at `speed` points a second, sampled at `hz`, after
/// resting `rest` seconds where it landed; stays down at the end unless `lift`.
func line(from x0: Double, _ y0: Double, to x1: Double, _ y1: Double, speed: Double, hz: Double = 120, rest: Double = 0,
          lift: Bool = false, band: Double = EdgeSwipe.band) -> Stroke {
    let length = hypot(x1 - x0, y1 - y0)
    let time = length / speed
    var points: [(x: Double, y: Double, t: Double)] = [(x0, y0, 0)]
    var t = 1 / hz
    while t < rest { points.append((x0, y0, t)); t += 1 / hz }
    let steps = max(1, Int((time * hz).rounded(.up)))
    for k in 1...steps {
        let f = min(1, Double(k) / Double(steps))
        points.append((x0 + (x1 - x0) * f, y0 + (y1 - y0) * f, rest + time * f))
    }
    return Stroke(points: points, lift: lift, band: band)
}

func verdict(_ s: Stroke) -> EdgeSwipe.Verdict { s.run().verdict }
func swipes(_ s: Stroke) -> Bool { verdict(s) == .swipe }
func why(_ s: Stroke) -> EdgeSwipe.Reason? { if case .notASwipe(let r) = verdict(s) { return r }; return nil }

// MARK: - Swipes in

for hz in [60.0, 120, 240] {
    for speed in [60.0, 200, 600, 1500, 3000] {
        for start in [0.0, 4, 12, 23.9, EdgeSwipe.band] {
            let s = line(from: start, 400, to: start + 200, 400, speed: speed, hz: hz)
            check(swipes(s), "a swipe in from \(start) pt at \(speed) pt/s, \(hz) Hz (got \(verdict(s)))")
            // Judged by the first sample 8 pt from its landing, no later.
            if let at = s.run().decidedAt {
                check(s.points[at].x - start >= EdgeSwipe.judgeAfter && (at == 1 || s.points[at - 1].x - start < EdgeSwipe.judgeAfter),
                      "a swipe in from \(start) pt at \(speed) pt/s, \(hz) Hz, is judged by its first sample 8 pt in")
            }
        }
    }
}
// Its angle: up to 45° from straight right, either way, and exactly 45°.
for (dy, label) in [(0.0, "straight"), (-50, "27° up"), (80, "39° down"), (-99, "44.7° up")] {
    let s = line(from: 6, 400, to: 106, 400 + dy, speed: 800)
    check(swipes(s), "a swipe in \(label) (got \(verdict(s)))")
}
check(verdict(Stroke(points: [(6, 400, 0), (14, 392, 0.01)], lift: false)) == .swipe, "exactly 45° up, 8 pt each way, is a swipe in")
check(why(Stroke(points: [(6, 400, 0), (13.9, 408, 0.01)], lift: false)) == .steep, "a hair steeper than 45° is not")
// The band: 24 pt, or the window's left safe-area inset where that is wider (an iPhone on its side, 59 pt).
check(EdgeSwipe.reach(leftInset: 0) == 24 && EdgeSwipe.reach(leftInset: 10) == 24 && EdgeSwipe.reach(leftInset: 59) == 59,
      "the band is 24 pt, or a wider left inset")
check(swipes(line(from: 50, 200, to: 250, 200, speed: 600, band: 59)), "on an iPhone's side, a swipe in from 50 pt (inside its 59 pt margin)")
check(swipes(line(from: 59, 200, to: 259, 200, speed: 600, band: 59)), "from exactly the wider band's edge")
check(why(line(from: 59.5, 200, to: 259, 200, speed: 600, band: 59)) == .outsideBand, "half a point past the wider band is the Mac's")
// Judged at 8 pt on either axis, never before.
var near = EdgeSwipe()
_ = near.began(x: 4, y: 300, t: 0, band: 24)
check(near.moved(x: 11.9, y: 300, t: 0.02) == .undecided, "7.9 pt in, undecided")
check(near.moved(x: 12, y: 300, t: 0.03) == .swipe, "8 pt in, a swipe in")
check(near.moved(x: 0, y: 300, t: 0.04) == .swipe && near.ended(x: 0, y: 300, t: 0.05) == .swipe, "a verdict never changes after it is given")
check(near.numbers.contains("landed 4.0 pt from the left edge"), "the console's numbers say where it landed")

// MARK: - Touches that are not swipes in

let scroll = line(from: 300, 400, to: 600, 400, speed: 1500)
check(why(scroll) == .outsideBand && scroll.run().decidedAt == 0, "a touch further in is the Mac's at its landing")
check(why(line(from: EdgeSwipe.band + 0.5, 400, to: 200, 400, speed: 900)) == .outsideBand, "half a point past the band is the Mac's")
let left = line(from: 20, 400, to: -40, 400, speed: 600)
check(why(left) == .notRightward, "a drag left from the band is the Mac's")
if let at = left.run().decidedAt { check(20 - left.points[at].x <= EdgeSwipe.judgeAfter + 6, "let go within a sample of 8 pt (at \(20 - left.points[at].x) pt)") }
check(why(line(from: 10, 400, to: 10, 200, speed: 600)) == .notRightward, "a drag straight up from the band is the Mac's")
check(why(line(from: 10, 400, to: 10, 700, speed: 600)) == .notRightward, "a drag straight down from the band is the Mac's")
check(why(line(from: 10, 400, to: 40, 600, speed: 600)) == .steep, "a drag down and a little right is the Mac's")
check(why(line(from: 10, 400, to: 40, 200, speed: 600)) == .steep, "a drag up and a little right is the Mac's")
let still = Stroke(points: [(10, 400, 0)], lift: false, ticks: [0.1, 0.2, EdgeSwipe.decideWithin + 0.01])
check(why(still) == .tooLong && still.run().decidedAt == 1, "a still finger is let go by the clock at 0.3 s, before a long press's 0.45 s")
check(EdgeSwipe.decideWithin > 0.1 && EdgeSwipe.decideWithin < 0.45, "0.3 s: past a swipe's start, before a long press")
let slow = line(from: 10, 400, to: 60, 400, speed: 20)
check(why(slow) == .tooLong, "a drag right too slow to reach 8 pt by 0.3 s is the Mac's")
if let at = slow.run().decidedAt { check(slow.points[at].t - EdgeSwipe.decideWithin < 0.01, "let go by its first move past 0.3 s") }
check(why(Stroke(points: [(10, 400, 0), (10.5, 400.2, 0.08)])) == .lifted, "a tap at the edge is the Mac's (let go at its lift)")
check(why(Stroke(points: [(10, 400, 0), (16, 400, 0.05)])) == .lifted, "a lift 6 pt right, before it is judged, is the Mac's")
check(why(Stroke(points: [(10, 400, 0)], lift: false, alone: false)) == .secondTouch, "a finger beside another already down is the Mac's")
var two = EdgeSwipe()
_ = two.began(x: 10, y: 300, t: 0, band: 24)
_ = two.moved(x: 13, y: 300, t: 0.01)
check(two.another() == .notASwipe(.secondTouch), "a second finger lets it go")
check(two.moved(x: 40, y: 300, t: 0.05) == .notASwipe(.secondTouch), "and it stays let go")
var cancelled = EdgeSwipe()
_ = cancelled.began(x: 10, y: 300, t: 0, band: 24)
check(cancelled.cancelled() == .notASwipe(.cancelled), "a cancelled touch is let go")
var once = EdgeSwipe()
_ = once.began(x: 10, y: 300, t: 0, band: 24)
check(once.began(x: 300, y: 300, t: 0.1, band: 24) == .undecided, "a second landing changes nothing")

// MARK: - Random strokes against a model

/// An independent model of the start, written from the documented numbers: the verdict for a whole stroke.
func model(_ s: Stroke) -> EdgeSwipe.Verdict {
    let p = s.points
    guard let first = p.first else { return .undecided }
    if !s.alone { return .notASwipe(.secondTouch) }
    if first.x > s.band { return .notASwipe(.outsideBand) }
    for (i, q) in p.enumerated() where i > 0 {
        let isLift = s.lift && i == p.count - 1
        if isLift { return .notASwipe(.lifted) }
        if q.t - first.t > 0.3 { return .notASwipe(.tooLong) }
        let dx = q.x - first.x, dy = q.y - first.y
        if abs(dx) < 8 && abs(dy) < 8 { continue }
        if dx <= 0 { return .notASwipe(.notRightward) }
        return abs(dy) > dx ? .notASwipe(.steep) : .swipe
    }
    if let last = s.ticks.last, last - first.t > 0.3 { return .notASwipe(.tooLong) }
    return .undecided
}

struct Seeded: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
var gen = Seeded(state: 20261112)
func r(_ range: ClosedRange<Double>) -> Double { Double.random(in: range, using: &gen) }

var swiped = 0, outside = 0
for n in 0..<30_000 {
    // Mostly near the edge, at every angle, at speeds either side of the clock; some rest first, some wander,
    // some lift early, some stay down, some land beside another finger, some in an iPhone's 59 pt margin.
    let band = n % 9 == 0 ? 59.0 : EdgeSwipe.band
    let x0 = n % 7 == 0 ? r(24...400) : r(0...70)
    let y0 = r(100...700)
    let angle = r(-Double.pi...Double.pi)
    let length = r(0...120)
    let hz = [60.0, 120, 240][n % 3]
    var s = line(from: x0, y0, to: x0 + cos(angle) * length, y0 + sin(angle) * length, speed: r(10...3000), hz: hz,
                 rest: n % 5 == 0 ? r(0...0.4) : 0, lift: n % 4 == 0, band: band)
    if n % 13 == 0 {
        s.points = s.points.enumerated().map { i, q in i == 0 ? q : (x: q.x + r(-3...3), y: q.y + r(-3...3), t: q.t) }
    }
    if n % 17 == 0 { s.ticks = [s.points.last!.t + 0.35] }
    if n % 23 == 0 { s.alone = false }
    let run = s.run()
    let expected = model(s)
    check(run.verdict == expected, "random stroke \(n): rule \(run.verdict), model \(expected); \(s.points.count) samples, lift \(s.lift)")
    let first = s.points[0]
    // I1: outside the band (or beside another finger), decided at the landing, never a swipe in.
    if first.x > s.band || !s.alone {
        outside += 1
        check(run.decidedAt == 0 && run.verdict != .swipe, "I1 stroke \(n): decided at its landing")
    }
    // I2: a swipe in landed in the band, alone, and its judging sample is right of the landing, no steeper than 45°.
    if run.verdict == .swipe, let at = run.decidedAt {
        swiped += 1
        let q = s.points[at]
        check(first.x <= s.band && s.alone && q.x - first.x >= 8 && abs(q.y - first.y) <= q.x - first.x && q.t - first.t <= 0.3,
              "I2 stroke \(n): a swipe in landed in the band and set off right within 45° by 0.3 s")
    }
    // I3: the hold is bounded: undecided only while still down, under 8 pt, within 0.3 s.
    if run.verdict == .undecided {
        check(!s.lift && (s.ticks.last ?? s.points.last!.t) - first.t <= 0.3, "I3 stroke \(n): undecided only while it may still be one")
    }
    // I4: decided by the first sample 8 pt from the landing, if that came within 0.3 s.
    if s.alone, first.x <= s.band, let i = s.points.indices.dropFirst().first(where: { max(abs(s.points[$0].x - first.x), abs(s.points[$0].y - first.y)) >= 8 }),
       s.points[i].t - first.t <= 0.3 {
        check((run.decidedAt ?? Int.max) <= i, "I4 stroke \(n): decided by the sample 8 pt from its landing")
    }
}
check(swiped > 1000 && outside > 3000, "the random strokes cover both sides (\(swiped) swipes in, \(outside) let go at the landing)")

// MARK: - The rest of the swipe in

check(EdgeReveal.progress(translation: 0, width: 1000) == 0, "no travel, no progress")
check(EdgeReveal.progress(translation: 250, width: 1000) == 0.25, "a quarter of the width, a quarter of the way")
check(EdgeReveal.progress(translation: 1500, width: 1000) == 1, "progress stops at the whole")
check(EdgeReveal.progress(translation: -20, width: 1000) == 0, "progress never goes back past nothing")
check(EdgeReveal.progress(translation: 20, width: 0) == 0, "no width, no progress")
check(EdgeReveal.distance(width: 393) == EdgeReveal.pull && EdgeReveal.distance(width: 1133) == EdgeReveal.pull
      && EdgeReveal.distance(width: 852) == EdgeReveal.pull && EdgeReveal.distance(width: 744) == EdgeReveal.pull,
      "80 pt on every screen Noah tried (a third of each is more)")
check(EdgeReveal.distance(width: 150) == 50, "a third of a narrow window, under 80 pt")
check(EdgeReveal.finishes(translation: 80, velocity: 0, width: 1133), "80 pt in on an iPad mini sideways: it comes in")
check(!EdgeReveal.finishes(translation: 79, velocity: 0, width: 1133), "79 pt in, at rest: it springs back")
check(EdgeReveal.finishes(translation: 70, velocity: 70, width: 1133), "the lift's speed carries it the rest (70 + 10.5)")
check(!EdgeReveal.finishes(translation: 60, velocity: 100, width: 1133), "a lift too slow to carry it")
check(EdgeReveal.finishes(translation: 20, velocity: 400, width: 1000), "a flick in finishes from 20 pt")
check(!EdgeReveal.finishes(translation: 8, velocity: 350, width: 1000), "a flick of 8 pt does not (its coast short of 80 pt)")
check(EdgeReveal.finishes(translation: EdgeReveal.flickTravel, velocity: EdgeReveal.flickSpeed, width: 1000), "a flick at exactly the numbers finishes")
check(!EdgeReveal.finishes(translation: 20, velocity: EdgeReveal.flickSpeed - 1, width: 1000), "a lift just under the flick's speed, its coast short of 80 pt, springs back")
// The numbers themselves, as literals (the cases above move with the constants): 300 pt/s after 12 pt.
check(EdgeReveal.finishes(translation: 20, velocity: 300, width: 1000), "a flick in at 300 pt/s finishes from 20 pt (its coast alone, 20 + 45, would not)")
check(!EdgeReveal.finishes(translation: 20, velocity: 299, width: 1000), "at 299 pt/s, 20 pt springs back")
check(EdgeReveal.finishes(translation: 12, velocity: 300, width: 1000) && !EdgeReveal.finishes(translation: 11.9, velocity: 300, width: 1000),
      "a flick in counts once it has moved 12 pt")
check(!EdgeReveal.finishes(translation: 900, velocity: -250, width: 1000), "moving back at the lift springs back, however far it came")
check(!EdgeReveal.finishes(translation: 900, velocity: -EdgeReveal.backSpeed, width: 1000), "back at exactly the speed springs back")
check(EdgeReveal.finishes(translation: 900, velocity: -100, width: 1000), "drifting back slowly from far in still finishes")
check(!EdgeReveal.finishes(translation: 100, velocity: 0, width: 0), "no width never finishes")
// Noah's lifts on his devices (2026-11-12): 124 to 703 pt in came in; a drag in and back sprang back.
for (t, v, w) in [(202.0, 2032.0, 393.0), (301, 1002, 852), (703, 269, 852), (289, 1427, 852), (124, 300, 744)] {
    check(EdgeReveal.finishes(translation: t, velocity: v, width: w), "Noah's lift of \(t) pt at \(v) pt/s on \(w) pt comes in")
}
for (t, v, w) in [(-27.0, -993.0, 852.0), (-25, 0, 393), (-46, -1660, 852), (-62, -1008, 393)] {
    check(!EdgeReveal.finishes(translation: t, velocity: v, width: w), "Noah's drag in and back (\(t) pt at \(v) pt/s) springs back")
}

// MARK: - The preview's cut: the picture's whole place in each layout

/// The cut and what the preview draws share the line and cover the preview, and the cut runs the whole width.
func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 1e-9 }
func partition(_ place: RevealCut.Place, _ size: CGSize, _ what: String) {
    let cut = RevealCut.cut(place, in: size), shown = RevealCut.shown(place, in: size)
    check(cut.minX == 0 && cut.width == size.width && shown.minX == 0 && shown.width == size.width,
          "\(what): the cut and the controls' band run the whole width")
    check(close(cut.height + shown.height, size.height) && cut.height >= 0 && shown.height >= 0,
          "\(what): together they are the preview's height")
    switch place {
    case .under: check(shown.minY == 0 && close(shown.maxY, cut.minY) && close(cut.maxY, size.height), "\(what): the bar's band, then the cut to the bottom")
    case .over: check(cut.minY == 0 && close(cut.maxY, shown.minY) && close(shown.maxY, size.height), "\(what): the cut from the top, then the controls' band")
    }
}

// Landscape: under the bar, exactly at its bottom edge; the pane 8 pt inside its area, its margin and the area's
// black all in the cut (Noah on an iPad mini on its side: "the bottom of it has a small black bar below it").
let sideways: [(String, CGSize, CGFloat)] = [
    ("an iPad mini on its side", CGSize(width: 1133, height: 720), 86), ("an iPad Pro 13-inch on its side", CGSize(width: 1376, height: 1008), 86),
    ("an iPhone 15 Pro on its side", CGSize(width: 734, height: 393), 78), ("the Duo open flat on its side", CGSize(width: 951, height: 669), 86),
    ("the Duo's book pose", CGSize(width: 951, height: 669), 86), ("the Duo's cover on its side", CGSize(width: 594, height: 466), 78),
]
for (what, size, bar) in sideways {
    let place = RevealCut.landscape(barHeight: bar)
    let cut = RevealCut.cut(place, in: size)
    check(cut == CGRect(x: 0, y: bar, width: size.width, height: size.height - bar), "\(what): everything under the \(bar) pt bar")
    check(cut.contains(CGRect(x: 0, y: bar, width: size.width, height: size.height - bar).insetBy(dx: 8, dy: 8)),
          "\(what): the pane and its margin in the cut")
    check(RevealCut.shown(place, in: size) == CGRect(x: 0, y: 0, width: size.width, height: bar), "\(what): the bar alone shows")
    partition(place, size, what)
}

// The halves: over the controls' block, the picture's half, the pane's margin and the laptop pose's fold in the
// cut; the block's own top margin (PortraitMetrics' padTop: 12, compact 10) stays black above the window bar,
// as it is once the controls land. The split is DuoPosture's, as the layout takes it.
let regularControls: CGFloat = 12 + 78 + 2 * 10 + 48 + 22, compactControls: CGFloat = 10 + 62 + 2 * 10 + (2 * 44 + 8) + 16
let upright: [(String, CGSize, FoldInfo, CGFloat, CGFloat, CGFloat)] = [
    ("an iPad mini upright", CGSize(width: 744, height: 1109), .inferred, 1.6, regularControls, 12),
    ("an iPad Pro 13-inch upright", CGSize(width: 1032, height: 1352), .inferred, 1.6, regularControls, 12),
    ("an iPad window 375 pt wide", CGSize(width: 375, height: 1109), .inferred, 1.6, compactControls, 10),
    ("the Duo open flat upright, 16:10", CGSize(width: 669, height: 951), .known(nil), 1.6, regularControls, 12),
    ("the Duo open flat upright, a tall window", CGSize(width: 669, height: 951), .known(nil), 1338.0 / 1902, regularControls, 12),
    ("the Duo open flat upright, a wide window", CGSize(width: 669, height: 951), .known(nil), 3440.0 / 1440, regularControls, 12),
    ("the Duo's laptop pose", CGSize(width: 669, height: 951), .known(CGRect(x: 0, y: 455.5, width: 669, height: 40)), 1.6, regularControls, 12),
]
for (what, size, fold, aspect, controls, padTop) in upright {
    let split = DuoPosture.portraitSplit(size, fold, aspect: aspect, controls: controls)
    let place = RevealCut.halves(split)
    let cut = RevealCut.cut(place, in: size)
    check(cut == CGRect(x: 0, y: 0, width: size.width, height: split.controls), "\(what): everything over the controls' block at \(split.controls)")
    check(cut.contains(CGRect(x: 0, y: 0, width: size.width, height: split.picture).insetBy(dx: DuoPosture.paneInset, dy: DuoPosture.paneInset))
          && cut.contains(CGRect(x: 0, y: 0, width: size.width, height: split.picture)), "\(what): the pane and its margin in the cut")
    if let band = fold.horizontalBand {
        check(cut.contains(CGRect(x: 0, y: band.minY.rounded(.down), width: size.width, height: band.maxY.rounded(.up) - band.minY.rounded(.down))),
              "\(what): the fold's band in the cut")
    }
    check(split.controls + padTop - cut.maxY == padTop, "\(what): \(padTop) pt of the block's black above the window bar, as once landed")
    partition(place, size, what)
}

// A phone upright, and the Duo's cover upright: over the bottom of the picture's room, whatever the video, Larger
// Picture's room too; the gap above row 1 stays black, 24 pt to the buttons, the shown layout's own (Noah on an
// iPhone upright: "just a touch of black above the UI buttons on iPhone in portrait to make it look uniform"); and
// never the pane at the video's shape (a tall window with Larger Picture showed its room's black beside it).
let phones: [(String, CGSize, Bool)] = [
    ("an iPhone 15 Pro", CGSize(width: 393, height: 793), false), ("an iPhone 16 Pro Max", CGSize(width: 440, height: 894), false),
    ("an iPhone SE", CGSize(width: 375, height: 647), false), ("an iPhone at 320 pt, zoomed", CGSize(width: 320, height: 548), false),
    ("the Duo's cover upright", CGSize(width: 382, height: 678), true),
]
let videos = [CGSize(width: 1600, height: 1000), CGSize(width: 1920, height: 1080), CGSize(width: 786, height: 1586),
              CGSize(width: 1000, height: 1000), CGSize(width: 3440, height: 1440), CGSize(width: 20, height: 400)]
var largerSeen = 0
for (what, size, foldable) in phones {
    for larger in [false, true] {
        let keyboard = PhonePortraitLayout.keyboard(for: size, largerPicture: larger, foldable: foldable)
        let layout = PhonePortraitLayout(size: size, keyboard: keyboard)
        if layout.largerPicture { largerSeen += 1 }
        let name = what + (layout.largerPicture ? " with Larger Picture" : "")
        let place = RevealCut.phone(layout)
        let cut = RevealCut.cut(place, in: size)
        check(cut == CGRect(x: 0, y: 0, width: size.width, height: layout.picture.maxY), "\(name): everything over the picture's room")
        check(cut.contains(layout.picture) && cut.contains(layout.picture.insetBy(dx: -PhonePortraitLayout.margin, dy: 0)),
              "\(name): the room and its side margins in the cut")
        for video in videos + [CGSize(width: 2 * size.width, height: 2 * size.height)] {
            let pane = layout.largerPicture ? layout.pane(video: video) : layout.picture
            check(pane.isEmpty || cut.contains(pane), "\(name): the pane at \(Int(video.width))×\(Int(video.height)) in the cut")
        }
        var rows = [layout.row1, layout.keys, layout.trackpad]
        if !layout.largerPicture { rows.append(layout.strip) }
        check(rows.allSatisfy { $0.minY >= cut.maxY && RevealCut.shown(place, in: size).contains($0) }, "\(name): every row shows, none cut")
        check(layout.row1.minY - cut.maxY == PhonePortraitLayout.margin + PhonePortraitLayout.underPicture + PhonePortraitLayout.band
              && layout.row1.minY - cut.maxY == 24, "\(name): 24 pt of black above row 1, the layout's own gap")
        partition(place, size, name)
    }
}
check(largerSeen >= 2, "Larger Picture's room was among the phones (\(largerSeen))")

// The rule at its edges: a line past the preview, no preview.
let screen10 = CGSize(width: 10, height: 10)
check(RevealCut.cut(.under(-5), in: screen10) == CGRect(x: 0, y: 0, width: 10, height: 10)
      && RevealCut.cut(.under(15), in: screen10) == CGRect(x: 0, y: 10, width: 10, height: 0)
      && RevealCut.cut(.over(15), in: screen10) == CGRect(x: 0, y: 0, width: 10, height: 10)
      && RevealCut.cut(.over(-5), in: screen10) == CGRect(x: 0, y: 0, width: 10, height: 0),
      "a line past the preview: all of it, or none")
check(RevealCut.shown(.under(15), in: screen10) == CGRect(x: 0, y: 0, width: 10, height: 10)
      && RevealCut.shown(.over(-5), in: screen10) == CGRect(x: 0, y: 0, width: 10, height: 10),
      "a line past the preview: the band is all of it")
check(RevealCut.cut(.under(5), in: CGSize(width: 0, height: 10)) == .zero && RevealCut.cut(.over(5), in: CGSize(width: 10, height: 0)) == .zero
      && RevealCut.shown(.under(5), in: .zero) == .zero && RevealCut.shown(.over(5), in: CGSize(width: 10, height: 0)) == .zero,
      "no preview: no cut, nothing shown")
for n in 0..<5_000 {
    let size = CGSize(width: r(1...1400), height: r(1...1400))
    let line = CGFloat(r(-50...1450))
    for place in [RevealCut.Place.under(line), .over(line)] {
        partition(place, size, "random \(n)")
        let cut = RevealCut.cut(place, in: size), y = min(max(line, 0), size.height)
        if case .under = place { check(cut.minY == y, "random \(n): the cut starts at the bar's edge") } else { check(cut.maxY == y, "random \(n): the cut ends at the controls' black") }
    }
}

// MARK: - The pointer at the edge

var dwell = EdgeDwell()
check(!dwell.hover(x: 0, t: 0, pencil: false), "the pointer just came to the edge")
check(!dwell.check(t: 0.4), "not yet at 0.4 s")
check(dwell.check(t: EdgeDwell.dwell), "at the dwell it shows the interface")
check(!dwell.check(t: 1.0), "once per stay")
check(!dwell.hover(x: 0.5, t: 1.1, pencil: false), "still at the edge: nothing more")
check(!dwell.hover(x: 30, t: 1.2, pencil: false), "it left")
check(!dwell.hover(x: 0, t: 1.3, pencil: false) && dwell.check(t: 1.8), "back at the edge: again after the dwell")
var pencil = EdgeDwell()
_ = pencil.hover(x: 0, t: 0, pencil: true)
check(!pencil.check(t: 2), "a Pencil hovering at the edge never counts")
var away = EdgeDwell()
_ = away.hover(x: 0, t: 0, pencil: false)
check(!away.hover(x: 2, t: 0.3, pencil: false) && !away.check(t: 1), "a pointer 2 pt in is not at the edge")
var ended = EdgeDwell()
_ = ended.hover(x: 0, t: 0, pencil: false)
ended.ended()
check(!ended.check(t: 1), "the hover ended: no dwell")

// MARK: - Offered, must show

let screen = CGRect(x: 0, y: 0, width: 1133, height: 744)
check(FullScreenPolicy.offered(window: screen, screen: screen), "a window that covers the screen is offered it")
check(FullScreenPolicy.offered(window: screen.insetBy(dx: 0.25, dy: 0.25), screen: screen), "within half a point")
check(!FullScreenPolicy.offered(window: CGRect(x: 0, y: 0, width: 700, height: 744), screen: screen), "Split View's left app is not")
check(!FullScreenPolicy.offered(window: CGRect(x: 433, y: 0, width: 700, height: 744), screen: screen), "Split View's right app is not")
check(!FullScreenPolicy.offered(window: CGRect(x: 60, y: 40, width: 900, height: 600), screen: screen), "a Stage Manager window is not")
check(!FullScreenPolicy.offered(window: .zero, screen: screen), "no window, nothing offered")

typealias S = FullScreenPolicy.Situation
check(FullScreenPolicy.mustShow(S()) == nil, "nothing calls the interface back while a window streams")
let reasons: [(S, FullScreenPolicy.ShowReason)] = [
    (S(tour: true), .tour), (S(pairing: true), .pairing), (S(linkLine: true), .linkLine),
    (S(lockCover: true), .locked), (S(offConsoleView: true), .offConsoleView), (S(streaming: false), .nothingStreams),
    (S(coversScreen: false), .window),
]
for (s, reason) in reasons { check(FullScreenPolicy.mustShow(s) == reason, "\(reason.rawValue) brings the interface back") }
check(FullScreenPolicy.mustShow(S(coversScreen: false, streaming: false, tour: true, pairing: true, linkLine: true, lockCover: true, offConsoleView: true)) == .tour,
      "the first reason in order is the one said")
check(FullScreenPolicy.mustShow(S(somethingOpen: true)) == nil, "something open over the stream is no reason to show")
check(FullScreenPolicy.hideAllowed(S()), "a hide is allowed while a window streams")
check(!FullScreenPolicy.hideAllowed(S(somethingOpen: true)), "no hide while something is open over the stream")
for (s, reason) in reasons { check(!FullScreenPolicy.hideAllowed(s), "no hide while \(reason.rawValue) would bring it back") }

// MARK: - The shake and the Settings rows

check(FullScreenPolicy.shakeShows(.hidden, switchOn: true), "hidden, the switch on: a shake brings the controls back")
check(!FullScreenPolicy.shakeShows(.hidden, switchOn: false), "the switch off: a shake does nothing of Sill's")
check(!FullScreenPolicy.shakeShows(.shown, switchOn: true), "shown: a shake does nothing of Sill's")
check(FullScreenPolicy.shakeToUndoOff(.hidden, switchOn: true), "hidden, the switch on: Shake to Undo off for the app")
check(!FullScreenPolicy.shakeToUndoOff(.hidden, switchOn: false) && !FullScreenPolicy.shakeToUndoOff(.shown, switchOn: true),
      "otherwise Shake to Undo stays as it is")
check(FullScreenPolicy.shakeKey == "Sill.shakeToShowControls", "the switch's key")
check(FullScreenPolicy.rowsPlace(macSettingsShown: true) == .afterFrameRate, "the Mac's settings show: after Frame Rate")
check(FullScreenPolicy.rowsPlace(macSettingsShown: false) == .thisDevice, "they do not: in This iPad's group")

// MARK: - The hint

check(FullScreenPolicy.showsHint(shownBefore: 0, forced: false), "the first time, the hint")
check(FullScreenPolicy.showsHint(shownBefore: FullScreenPolicy.hintTimes - 1, forced: false), "the third time, the hint")
check(!FullScreenPolicy.showsHint(shownBefore: FullScreenPolicy.hintTimes, forced: false), "the fourth time, none")
check(FullScreenPolicy.showsHint(shownBefore: 99, forced: true), "-SillFullScreenHint 1 forces it")
check(FullScreenPolicy.hintTimes == 3 && FullScreenPolicy.hintSeconds == 2.5, "three times, two and a half seconds")

// MARK: - The room

typealias I = FullScreenPolicy.Insets
let phoneUpright = CGSize(width: 393, height: 852), phoneSideways = CGSize(width: 852, height: 393)
check(FullScreenPolicy.room(size: phoneUpright, insets: I(top: 59, bottom: 34), choice: .clearOfHousing)
      == CGRect(x: 0, y: 59, width: 393, height: 793), "an iPhone 15 Pro upright: under the Dynamic Island, down to the bottom edge")
check(FullScreenPolicy.room(size: phoneSideways, insets: I(left: 59, bottom: 21, right: 59), choice: .clearOfHousing)
      == CGRect(x: 59, y: 0, width: 734, height: 393), "sideways: clear of the housing's side, the whole height")
check(FullScreenPolicy.room(size: phoneSideways, insets: I(left: 59, bottom: 21, right: 59), choice: .screen)
      == CGRect(x: 0, y: 0, width: 852, height: 393), "the whole screen")
check(FullScreenPolicy.room(size: phoneSideways, insets: I(left: 59, bottom: 21, right: 59), choice: .safeArea)
      == CGRect(x: 59, y: 0, width: 734, height: 372), "the safe area")
check(FullScreenPolicy.room(size: CGSize(width: 1133, height: 744), insets: I(bottom: 20), choice: .clearOfHousing)
      == CGRect(x: 0, y: 0, width: 1133, height: 744), "an iPad mini sideways, status bar hidden: the whole screen")
check(FullScreenPolicy.room(size: CGSize(width: 1133, height: 744), insets: I(top: 24, bottom: 20), choice: .clearOfHousing, topIsStatusBar: true)
      == CGRect(x: 0, y: 0, width: 1133, height: 744), "an iPad before its status bar has gone: the status bar's inset never counted")
check(FullScreenPolicy.room(size: CGSize(width: 1133, height: 744), insets: I(top: 24, bottom: 20), choice: .safeArea, topIsStatusBar: true)
      == CGRect(x: 0, y: 0, width: 1133, height: 724), "an iPad's safe area: clear of the home indicator, not of the status bar")
check(FullScreenPolicy.room(size: phoneUpright, insets: I(top: 59, bottom: 34), choice: .clearOfHousing, topIsStatusBar: false).minY == 59,
      "an iPhone's top inset is its sensor housing, counted")
check(FullScreenPolicy.room(size: CGSize(width: 669, height: 951), insets: I(bottom: 34), choice: .clearOfHousing, foldTop: 455.5)
      == CGRect(x: 0, y: 0, width: 669, height: 455.5), "the Duo's laptop pose: above the fold")
check(FullScreenPolicy.room(size: CGSize(width: 669, height: 951), insets: I(bottom: 34), choice: .clearOfHousing, foldTop: 1000)
      == CGRect(x: 0, y: 0, width: 669, height: 951), "a fold past the screen changes nothing")
check(FullScreenPolicy.room(size: CGSize(width: 466, height: 678), insets: I(bottom: 34, right: 84), choice: .clearOfHousing)
      == CGRect(x: 0, y: 0, width: 382, height: 678), "the Duo's cover upright: clear of the camera strip")
check(FullScreenPolicy.room(size: CGSize(width: 10, height: 10), insets: I(top: 20, left: 20), choice: .safeArea).width == 0,
      "insets larger than the screen leave no room, never a negative one")

// MARK: - The levels and the words

check(ChromeLevel.shown.afterHide == .hidden && ChromeLevel.hidden.afterReveal == .shown, "one level: Full Screen hides it all, a swipe brings it all")
check(ChromeLevel.shown < ChromeLevel.hidden && ChromeLevel.allCases.count == 2, "two levels in this build, ordered")
check(ChromeLevel.hidden.rawValue - ChromeLevel.shown.rawValue == 2, "room for a level between (#279's second step)")
check(FullScreenPolicy.Copy.footnote == "Hides Sill’s controls, so only the picture shows. Swipe in from the left edge to bring them back.",
      "Full Screen's words")
check(FullScreenPolicy.Copy.shakeTitle == "Shake to Show Controls", "the switch's title")
check(FullScreenPolicy.Copy.shakeFootnote(device: "iPad") == "Shaking your iPad brings the controls back too.", "the switch's words name the device")
check(FullScreenPolicy.Copy.notOffered == "Full Screen works while Sill fills the screen.", "while Sill does not fill the screen")
check(FullScreenPolicy.Copy.pictureLabel(mac: "Mac mini") == "Mac mini’s picture. Sill’s controls are hidden.", "the picture's label")
check(FullScreenPolicy.Copy.inputLabels.first == FullScreenPolicy.Copy.action, "Voice Control's first name is the action's")

print("full-screen: \(checks) checks, \(failures) failed (\(swiped) of 30,000 random strokes swiped in, \(outside) let go at their landing)")
exit(failures == 0 ? 0 : 1)
