// Full screen's rules on their own (iOSClient/FullScreenPolicy.swift; docs/full-screen-plan.md): the hide's
// touch rule (EdgeFlick) by cases at the numbers' edges, sampled at 60, 120 and 240 Hz, then 30,000 random
// strokes against an independent model and the invariants; the swipe in (EdgeReveal), the pointer at the
// edge (EdgeDwell), when it is offered, armed and must show, the hint, the room and the levels.
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

/// A stroke as a list of samples (x from the screen's left edge, y, t), fed to the rule as UIKit would: the
/// first a landing, the rest moves, the last the lift (unless `lift` is false: still down).
struct Stroke {
    var points: [(x: Double, y: Double, t: Double)]
    var lift = true
    var ticks: [Double] = []

    func run() -> (verdict: EdgeFlick.Verdict, decidedAt: Int?) {
        var rule = EdgeFlick()
        var decidedAt: Int? = nil
        for (i, p) in points.enumerated() {
            let v: EdgeFlick.Verdict
            if i == 0 { v = rule.began(x: p.x, y: p.y, t: p.t) }
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

/// A straight stroke: lands at (x0, y0), moves to (x1, y1) at `speed` points a second along it, sampled at
/// `hz`, after resting `rest` seconds where it landed; lifts at the end.
func line(from x0: Double, _ y0: Double, to x1: Double, _ y1: Double, speed: Double, hz: Double = 120, rest: Double = 0) -> Stroke {
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
    return Stroke(points: points)
}

func verdict(_ s: Stroke) -> EdgeFlick.Verdict { s.run().verdict }
func hides(_ s: Stroke) -> Bool { verdict(s) == .hide }
func why(_ s: Stroke) -> EdgeFlick.Reason? { if case .notAFlick(let r) = verdict(s) { return r }; return nil }

// MARK: - Flicks that hide

for hz in [60.0, 120, 240] {
    for speed in [320.0, 500, 800, 1200, 2000] {
        for start in [14.0, 24, 36, 48] {
            // Off the edge: the last sample at the edge, where a finger sliding off is last seen.
            let s = line(from: start, 300, to: 0, 300, speed: speed, hz: hz)
            check(hides(s), "a flick from \(start) at \(speed) pt/s, \(hz) Hz, hides (got \(verdict(s)))")
        }
    }
}
// Angles: up to about 50° from straight left, either way.
for (dy, label) in [(0.0, "straight"), (-20, "30° up"), (36, "45° down"), (-40, "48° up")] {
    let s = line(from: 44, 300, to: 0, 300 + dy, speed: 700)
    check(hides(s), "a flick \(label) hides (got \(verdict(s)))")
}
// A case's lip: the finger stops 20 to 24 pt in and lifts there, still fast.
check(hides(line(from: 48, 400, to: 22, 400, speed: 600)), "a flick stopped by a case's lip 22 pt in hides")
check(hides(line(from: 48, 400, to: EdgeFlick.reach, 400, speed: 600)), "a flick lifted exactly at the reach hides")
// The last sample further in, the speed carrying it off within the projection: 30 pt in at 1,500 pt/s.
check(hides(line(from: 48, 400, to: 30, 400, speed: 1500)), "a fast flick last seen 30 pt in hides (projection)")
// A flick that rests a moment where it landed, then goes, inside the duration.
check(hides(line(from: 40, 400, to: 0, 400, speed: 900, rest: 0.1)), "a flick after a 0.1 s rest hides")
// At the edges of the numbers.
check(hides(line(from: EdgeFlick.band, 300, to: 0, 300, speed: 400)), "a flick from exactly the band's edge hides")
check(hides(line(from: EdgeFlick.travel, 300, to: 0, 300, speed: 400)), "a flick of exactly the travel hides")
check(hides(Stroke(points: [(30, 300, 0), (29.5, 300, 0.19), (15, 300, 0.22), (0, 300, EdgeFlick.duration)])),
      "a flick lifting exactly at the duration hides (it rested, then went fast)")
// Exactly 300 pt/s over the last 50 ms (binary fractions of a second, so the arithmetic is exact).
check(hides(Stroke(points: [(37.5, 300, 0), (18.75, 300, 0.0625), (0, 300, 0.125)])), "a flick at exactly the speed hides")
// Lifted exactly at the reach, too slow for the projection to carry it off: the reach alone.
check(hides(line(from: 48, 300, to: EdgeFlick.reach, 300, speed: 400)), "lifted at the reach at 400 pt/s hides")

// MARK: - Strokes that must not hide

// A scroll from the middle that runs off the left edge: landed outside the band, decided at once.
let scrollOff = line(from: 400, 300, to: 0, 300, speed: 1500)
check(why(scrollOff) == .outsideBand && scrollOff.run().decidedAt == 0, "a scroll from the middle off the left edge is the Mac's at once")
check(why(line(from: EdgeFlick.band + 0.5, 300, to: 0, 300, speed: 900)) == .outsideBand, "half a point past the band is the Mac's")
// A slow drag to the edge: at 100 pt/s it is still down at the duration; at 200 pt/s it lifts too slow.
let slowDrag = line(from: 40, 300, to: 0, 300, speed: 100)
check(why(slowDrag) == .tooLong, "a slow drag to the edge (100 pt/s) is let go by the duration")
if let at = slowDrag.run().decidedAt {
    check(at < slowDrag.points.count - 1 && slowDrag.points[at].t - EdgeFlick.duration < 0.01,
          "a slow drag is let go by its first move past the duration, while it still moves (sample \(at) of \(slowDrag.points.count))")
}
check(why(line(from: 40, 300, to: 0, 300, speed: 200)) == .tooSlow, "a drag to the edge at 200 pt/s is too slow")
check(why(line(from: 40, 300, to: 0, 300, speed: 299)) == .tooSlow, "a drag at 299 pt/s is too slow")
// A drag in the band going right, up or down, and decided within a few points.
let right = line(from: 30, 300, to: 130, 300, speed: 600)
check(why(right) == .movedRight, "a drag in the band going right is not a flick")
if let at = right.run().decidedAt { check(right.points[at].x - 30 <= EdgeFlick.rightSlop + 6, "a drag right is let go within a sample of 6 pt (at \(right.points[at].x - 30) pt)") }
let up = line(from: 30, 300, to: 28, 150, speed: 600)
check(why(up) == .steep, "a drag in the band going up is not a flick")
if let at = up.run().decidedAt { check(abs(up.points[at].y - 300) <= EdgeFlick.judgeAfter + 6, "a drag up is let go within a sample of 8 pt") }
check(why(line(from: 30, 300, to: 26, 480, speed: 600)) == .steep, "a drag in the band going down is not a flick")
check(why(line(from: 44, 300, to: 0, 360, speed: 900)) == .steep, "a flick 54° down is too steep")
// A tap and a long press in the band: a tap lifts where it landed; a long press is let go by the clock.
check(why(Stroke(points: [(20, 300, 0), (20.5, 300.2, 0.08)])) == .tooShort, "a tap in the band still clicks (not a flick)")
let press = Stroke(points: [(20, 300, 0)], lift: false, ticks: [0.1, 0.2, EdgeFlick.duration + 0.01])
check(why(press) == .tooLong, "a long press in the band is let go by the duration")
check(press.run().decidedAt == 1, "a still finger is let go at the duration's tick, before the long press's 0.45 s")
// A grip resting on the edge, then rolling off it as it lifts after a second.
check(why(Stroke(points: [(8, 500, 0), (6, 500, 0.5), (0, 500, 1.0)])) == .tooLong, "a grip resting on the edge does not hide")
// A grip that rolls off quickly: too close to the edge to travel 12 pt.
check(why(line(from: 9, 500, to: 0, 500, speed: 600)) == .tooShort, "a touch landing 9 pt from the edge cannot be a flick")
// Lifted short of the edge, going slower than the projection would carry.
check(why(line(from: 48, 300, to: 28, 300, speed: 400)) == .shortOfEdge, "lifted 28 pt in at 400 pt/s is short of the edge")
// Only the lift past the duration: a stroke that rests 0.2 s, then flicks, lifting at 0.3 s.
check(why(Stroke(points: [(40, 300, 0), (39, 300, 0.2), (0, 300, 0.3)])) == .tooLong, "a flick lifting past the duration is held too long")
// Exactly 6 pt right.
check(why(Stroke(points: [(30, 300, 0), (36, 300, 0.02), (20, 300, 0.05), (0, 300, 0.08)])) == .movedRight,
      "a stroke that moved exactly 6 pt right is the Mac's")
// Level all the way, swerving at the lift to 51° down.
check(why(Stroke(points: [(40, 300, 0), (30, 300, 0.02), (20, 300, 0.04), (0, 350, 0.06)])) == .steep,
      "a stroke whose lift swerves 51° down is too steep")
// A second finger, and a cancel.
var two = EdgeFlick()
_ = two.began(x: 30, y: 300, t: 0)
_ = two.moved(x: 26, y: 300, t: 0.01)
check(two.another() == .notAFlick(.secondTouch), "a second finger lets the stroke go")
check(two.ended(x: 0, y: 300, t: 0.05) == .notAFlick(.secondTouch), "a verdict never changes after it is given")
var cancelled = EdgeFlick()
_ = cancelled.began(x: 30, y: 300, t: 0)
check(cancelled.cancelled() == .notAFlick(.cancelled), "a cancelled touch is let go")
// A flick that first goes right a little, then back off the edge: the right move decided it.
let wiggle = Stroke(points: [(30, 300, 0), (37, 300, 0.02), (20, 300, 0.05), (0, 300, 0.08)])
check(why(wiggle) == .movedRight, "a stroke that moved right 7 pt first is the Mac's, whatever follows")
// Moves before the lift never hide.
var midway = EdgeFlick()
_ = midway.began(x: 40, y: 300, t: 0)
for (i, x) in [30.0, 20, 10, 0].enumerated() { check(midway.moved(x: x, y: 300, t: 0.01 * Double(i + 1)) == .undecided, "a move to \(x) leaves it undecided until the lift") }
// Numbers for the console.
check(midway.numbers.contains("landed 40.0 pt from the edge"), "the console's numbers say where it landed")

// MARK: - Glue rules: which touches are judged

check(EdgeFlickGate.judges(direct: true, alreadyDown: 0), "a finger with nothing else down is judged")
check(!EdgeFlickGate.judges(direct: false, alreadyDown: 0), "a Pencil or the iPad's pointer is never judged")
check(!EdgeFlickGate.judges(direct: true, alreadyDown: 1), "a finger beside another already down is not judged")

// MARK: - Random strokes against a model

/// An independent model of the rule, written from the documented numbers: the verdict for a whole stroke.
func model(_ s: Stroke) -> EdgeFlick.Verdict {
    let p = s.points
    guard let first = p.first else { return .undecided }
    if first.x > 48 { return .notAFlick(.outsideBand) }
    // Moves (and the lift) in order: the first that shows it is not a flick decides.
    for (i, q) in p.enumerated() where i > 0 {
        let isLift = s.lift && i == p.count - 1
        if q.t - first.t > 0.25 { return .notAFlick(.tooLong) }
        let dx = q.x - first.x, dy = q.y - first.y
        if dx >= 6 { return .notAFlick(.movedRight) }
        if !isLift {
            if hypot(dx, dy) >= 8, abs(dy) > 1.2 * max(-dx, 0) { return .notAFlick(.steep) }
            continue
        }
        if -dx < 12 { return .notAFlick(.tooShort) }
        if abs(dy) > 1.2 * -dx { return .notAFlick(.steep) }
        var from = first
        for earlier in p[..<i] where earlier.t <= q.t - 0.05 { from = earlier }
        let v = q.t > from.t ? (from.x - q.x) / (q.t - from.t) : 0
        if v < 300 { return .notAFlick(.tooSlow) }
        if q.x <= 24 || q.x - v * 0.05 <= 0 { return .hide }
        return .notAFlick(.shortOfEdge)
    }
    if !s.lift, let last = s.ticks.last, last - first.t > 0.25 { return .notAFlick(.tooLong) }
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

var hidden = 0, outside = 0, decidedEarly = 0
for n in 0..<30_000 {
    // Mostly near the edge, heading left, at speeds and angles either side of the numbers; some rest first,
    // some wander, some stay down.
    let x0 = n % 7 == 0 ? r(48...400) : r(0...60)
    let y0 = r(100...700)
    let angle = r(-1.4...1.4) + (n % 11 == 0 ? Double.pi : 0)
    let length = r(0...90)
    let x1 = x0 - cos(angle) * length, y1 = y0 + sin(angle) * length
    let hz = [60.0, 120, 240][n % 3]
    var s = line(from: x0, y0, to: max(x1, -20), y1, speed: r(40...2500), hz: hz, rest: n % 5 == 0 ? r(0...0.3) : 0)
    // UIKit never reports a touch off the screen: a stroke that crosses the edge lifts there, last seen at it.
    if let off = s.points.firstIndex(where: { $0.x <= 0 }), off > 0 {
        s.points = Array(s.points[...off]).map { (x: max($0.x, 0), y: $0.y, t: $0.t) }
    }
    if n % 13 == 0 {
        // Wander: a jittered path.
        s.points = s.points.enumerated().map { i, q in i == 0 ? q : (x: max(q.x + r(-3...3), 0), y: q.y + r(-3...3), t: q.t) }
    }
    if n % 17 == 0 { s.lift = false; s.ticks = [s.points.last!.t + 0.3] }
    let run = s.run()
    let expected = model(s)
    check(run.verdict == expected, "random stroke \(n): rule \(run.verdict), model \(expected); \(s.points.prefix(3).map { "(\(Int($0.x)),\(Int($0.y)),\(String(format: "%.3f", $0.t)))" }) … \(s.points.count) samples, lift \(s.lift)")
    let first = s.points[0]
    // I1: landed outside the band, decided at the landing, never a hide.
    if first.x > EdgeFlick.band {
        outside += 1
        check(run.decidedAt == 0 && run.verdict == .notAFlick(.outsideBand), "I1 stroke \(n): outside the band is the Mac's at once")
    }
    // I2: a hide only at the lift, of a stroke that meets every number.
    if run.verdict == .hide {
        hidden += 1
        let last = s.points.last!
        check(s.lift && run.decidedAt == s.points.count - 1, "I2 stroke \(n): a hide only at the lift")
        check(first.x <= EdgeFlick.band && first.x - last.x >= EdgeFlick.travel && last.t - first.t <= EdgeFlick.duration,
              "I2 stroke \(n): a hide landed in the band, travelled, and was quick")
        check(abs(last.y - first.y) <= EdgeFlick.steepness * (first.x - last.x), "I2 stroke \(n): a hide went left")
    }
    // I3: the hold is bounded: undecided strokes are only those still down within the duration.
    if run.verdict == .undecided {
        check(!s.lift && (s.ticks.last ?? s.points.last!.t) - first.t <= EdgeFlick.duration, "I3 stroke \(n): undecided only while it may still be a flick")
    }
    // I4: a stroke that went right 6 pt, or steep after 8, is decided by that sample.
    if let i = s.points.firstIndex(where: { $0.x - first.x >= EdgeFlick.rightSlop }), first.x <= EdgeFlick.band {
        check((run.decidedAt ?? Int.max) <= i, "I4 stroke \(n): decided by the sample that moved right 6 pt")
    }
    if run.decidedAt != nil, run.decidedAt! > 0 { decidedEarly += 1 }
}
check(hidden > 1000 && outside > 2000, "the random strokes cover both sides (\(hidden) hides, \(outside) outside the band)")

// MARK: - The swipe in

check(EdgeReveal.progress(translation: 0, width: 1000) == 0, "no travel, no progress")
check(EdgeReveal.progress(translation: 250, width: 1000) == 0.25, "a quarter of the width, a quarter of the way")
check(EdgeReveal.progress(translation: 1500, width: 1000) == 1, "progress stops at the whole")
check(EdgeReveal.progress(translation: -20, width: 1000) == 0, "progress never goes back past nothing")
check(EdgeReveal.progress(translation: 20, width: 0) == 0, "no width, no progress")
check(EdgeReveal.finishes(translation: 340, velocity: 0, width: 1000), "past a third of the width it finishes")
check(!EdgeReveal.finishes(translation: 320, velocity: 0, width: 1000), "short of a third, at rest, it springs back")
check(EdgeReveal.finishes(translation: 300, velocity: 300, width: 1000), "the lift's speed carries it past a third (300 + 45)")
check(EdgeReveal.finishes(translation: 20, velocity: 500, width: 1000), "a flick in finishes from 20 pt")
check(!EdgeReveal.finishes(translation: 8, velocity: 500, width: 1000), "a flick of 8 pt does not")
check(EdgeReveal.finishes(translation: EdgeReveal.flickTravel, velocity: EdgeReveal.flickSpeed, width: 1000), "a flick at exactly the numbers finishes")
check(!EdgeReveal.finishes(translation: 900, velocity: -250, width: 1000), "moving back at the lift springs back, however far it came")
check(!EdgeReveal.finishes(translation: 900, velocity: -EdgeReveal.backSpeed, width: 1000), "back at exactly the speed springs back")
check(EdgeReveal.finishes(translation: 900, velocity: -100, width: 1000), "drifting back slowly from far in still finishes")
check(EdgeReveal.finishes(translation: 132, velocity: 0, width: 393) && !EdgeReveal.finishes(translation: 130, velocity: 0, width: 393), "an iPhone upright: a third is 131 pt")
check(!EdgeReveal.finishes(translation: 100, velocity: 0, width: 0), "no width never finishes")

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

// MARK: - Offered, armed, must show

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
check(FullScreenPolicy.flickArmed(S(), level: .shown, voiceOver: false), "the flick listens while the interface shows")
check(!FullScreenPolicy.flickArmed(S(), level: .hidden, voiceOver: false), "not while hidden (the swipe in listens then)")
check(!FullScreenPolicy.flickArmed(S(), level: .shown, voiceOver: true), "not under VoiceOver, which keeps one-finger swipes")
check(!FullScreenPolicy.flickArmed(S(somethingOpen: true), level: .shown, voiceOver: false), "not with something open")

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

check(ChromeLevel.shown.afterFlick == .hidden && ChromeLevel.hidden.afterReveal == .shown, "one level: a flick hides it all, a swipe brings it all")
check(ChromeLevel.shown < ChromeLevel.hidden && ChromeLevel.allCases.count == 2, "two levels in this build, ordered")
check(ChromeLevel.hidden.rawValue - ChromeLevel.shown.rawValue == 2, "room for a level between (#279's second step)")
check(FullScreenPolicy.Copy.footnote(device: "iPad").contains("shake your iPad"), "the footnote names the device")
check(FullScreenPolicy.Copy.pictureLabel(mac: "Mac mini") == "Mac mini’s picture. Sill’s controls are hidden.", "the picture's label")
check(FullScreenPolicy.Copy.inputLabels.first == FullScreenPolicy.Copy.action, "Voice Control's first name is the action's")

print("full-screen: \(checks) checks, \(failures) failed (\(hidden) of 30,000 random strokes hid, \(outside) landed outside the band)")
exit(failures == 0 ? 0 : 1)
