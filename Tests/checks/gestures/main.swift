// H3 (docs/trackpad-gestures-plan.md §9.1): iOSClient/TrackpadGestures.swift on its own, the device's half of
// the trackpad gestures: which stroke arms (three fingers within the window, before any has travelled, no
// button held), how long it stays silent (until the next stroke's first touch), and what it decides at the
// first lift: each swipe at, under and over its distances, the flick, the axis rule both ways, pinch and
// spread at their ratio, travel winning over a spread, a fourth finger, a fifth, a cancel, a swipe taken
// back, one decision a stroke. Then 5,000 random strokes against a model written here from the plan.
//   swiftc -O iOSClient/TrackpadGestures.swift Tests/checks/gestures/main.swift -o check && ./check
import CoreGraphics
import Foundation

typealias G = TrackpadGestures
var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) { if ok { passes += 1; print("ok   \(name)") } else { fails += 1; print("FAIL \(name)") } }

// MARK: - A stroke, as touches

enum Event {
    case down(Int, CGPoint, Double, holding: Bool)
    case move(Int, CGPoint, Double)
    case up(Int, CGPoint, Double)
    case cancel(Int)
    var time: Double {
        switch self {
        case .down(_, _, let t, _), .move(_, _, let t), .up(_, _, let t): return t
        case .cancel: return -1
        }
    }
}

struct Run {
    var outputs: [G.Output] = []      // every non-none output, in order
    var silentAfter: [Bool] = []      // `silent` after each event
    var armedAt: Int?                 // the index of the event that armed
}

func run(_ events: [Event], _ g: inout G) -> Run {
    var r = Run()
    for (i, e) in events.enumerated() {
        var out = G.Output.none
        switch e {
        case .down(let id, let p, let t, let h): out = g.down(id, at: p, time: t, holding: h)
        case .move(let id, let p, let t): g.moved(id, to: p, time: t)
        case .up(let id, let p, let t): out = g.up(id, at: p, time: t)
        case .cancel(let id): g.cancelled(id)
        }
        if out != .none { r.outputs.append(out) }
        if out == .armed, r.armedAt == nil { r.armedAt = i }
        r.silentAfter.append(g.silent)
    }
    return r
}
func run(_ events: [Event]) -> Run { var g = G(); return run(events, &g) }

/// Three fingers of one hand at `c`, 62 pt apart, in a slight arc (the critique's rig's).
func hand(_ n: Int, at c: CGPoint = CGPoint(x: 300, y: 300)) -> [CGPoint] {
    let offsets: [CGPoint] = n == 4 ? [CGPoint(x: -1.5, y: 0.25), CGPoint(x: -0.5, y: -0.15), CGPoint(x: 0.5, y: -0.2), CGPoint(x: 1.5, y: 0.2)]
        : n == 3 ? [CGPoint(x: -1, y: 0.2), CGPoint(x: 0, y: -0.15), CGPoint(x: 1, y: 0.1)]
        : n == 2 ? [CGPoint(x: -0.5, y: 0), CGPoint(x: 0.5, y: -0.1)]
        : n == 5 ? [CGPoint(x: -2, y: 0.4), CGPoint(x: -1, y: 0.2), CGPoint(x: 0, y: -0.15), CGPoint(x: 1, y: 0.1), CGPoint(x: 2, y: 0.5)]
        : [CGPoint.zero]
    return offsets.map { CGPoint(x: c.x + $0.x * 62, y: c.y + $0.y * 62) }
}

/// The fingers land `stagger` s apart from t = 0, then every finger moves from `start` by `f(k)` (its
/// displacement at step k of `steps`, one step per `dt` s), then they lift one by one `liftGap` s apart.
func stroke(_ start: [CGPoint], stagger: Double = 0.016, steps: Int = 10, dt: Double = 0.01, liftGap: Double = 0.008,
            holding: Bool = false, move: (Int, Int, CGPoint) -> CGPoint) -> [Event] {
    var ev: [Event] = []
    for (i, p) in start.enumerated() { ev.append(.down(i, p, Double(i) * stagger, holding: holding)) }
    var t = Double(start.count - 1) * stagger
    var now = start
    for k in 1...max(steps, 1) {
        t += dt
        for i in start.indices {
            now[i] = move(i, k, start[i])
            ev.append(.move(i, now[i], t))
        }
    }
    for i in start.indices {
        t += liftGap
        ev.append(.up(i, now[i], t))
    }
    return ev
}
/// A swipe by (dx, dy) in `steps` even steps.
func swipe(_ n: Int = 3, dx: CGFloat, dy: CGFloat, steps: Int = 10, dt: Double = 0.01, stagger: Double = 0.016) -> [Event] {
    stroke(hand(n), stagger: stagger, steps: steps, dt: dt) { _, k, p in
        CGPoint(x: p.x + dx * CGFloat(k) / CGFloat(steps), y: p.y + dy * CGFloat(k) / CGFloat(steps))
    }
}
/// Every finger toward (scale < 1) or away from the fingers' centroid, to `scale` of its distance.
func pinch(_ n: Int = 3, scale: CGFloat, steps: Int = 12, from points: [CGPoint]? = nil) -> [Event] {
    let start = points ?? hand(n)
    let c = CGPoint(x: start.map(\.x).reduce(0, +) / CGFloat(n), y: start.map(\.y).reduce(0, +) / CGFloat(n))
    return stroke(start, steps: steps) { _, k, p in
        let s = 1 + (scale - 1) * CGFloat(k) / CGFloat(steps)
        return CGPoint(x: c.x + (p.x - c.x) * s, y: c.y + (p.y - c.y) * s)
    }
}
func gesture(_ r: Run) -> G.Output? { r.outputs.first { if case .gesture = $0 { return true } else { return false } } }
func only(_ r: Run, _ g: G.Gesture, fingers: Int = 3) -> Bool { r.outputs == [.armed, .gesture(g, fingers: fingers)] }
func armedNothing(_ r: Run) -> Bool { r.outputs == [.armed] }

// MARK: - Each direction, and the swipe's distance

check("three fingers 16 ms apart, up 60 pt: armed, then swipe up", only(run(swipe(dx: 0, dy: -60)), .swipeUp))
check("down 60 pt: swipe down", only(run(swipe(dx: 0, dy: 60)), .swipeDown))
check("left 60 pt: swipe left", only(run(swipe(dx: -60, dy: 0)), .swipeLeft))
check("right 60 pt: swipe right", only(run(swipe(dx: 60, dy: 0)), .swipeRight))
check("up exactly 40 pt, slowly: a swipe (at swipeDistance)", only(run(swipe(dx: 0, dy: -40, steps: 40, dt: 0.02)), .swipeUp))
check("up 39.9 pt, slowly: nothing", armedNothing(run(swipe(dx: 0, dy: -39.9, steps: 40, dt: 0.02))))
check("left exactly 40 pt, slowly: a swipe", only(run(swipe(dx: -40, dy: 0, steps: 40, dt: 0.02)), .swipeLeft))
check("right 39.9 pt, slowly: nothing", armedNothing(run(swipe(dx: 39.9, dy: 0, steps: 40, dt: 0.02))))
check("up 200 pt: still one swipe up", only(run(swipe(dx: 0, dy: -200)), .swipeUp))

// MARK: - The flick

check("25 pt fast (about 660 pt/s): a flick, swipe down", only(run(swipe(dx: 0, dy: 25, steps: 3, dt: 0.01)), .swipeDown))
check("25 pt over a second: no flick, nothing", armedNothing(run(swipe(dx: 0, dy: 25, steps: 50, dt: 0.02))))
check("exactly 20 pt fast: a flick", only(run(swipe(dx: 20, dy: 0, steps: 2, dt: 0.01)), .swipeRight))
check("19.9 pt fast: nothing", armedNothing(run(swipe(dx: 19.9, dy: 0, steps: 2, dt: 0.01))))
/// Three fingers that land 16 ms apart and then move up together through `path`, each entry the
/// time and how far up the fingers are by then (samples every 10 ms or so, as glass reports them),
/// and lift at the last entry's time.
func upThrough(_ path: [(Double, CGFloat)]) -> [Event] {
    let h = hand(3)
    var ev: [Event] = h.enumerated().map { .down($0.offset, $0.element, Double($0.offset) * 0.016, holding: false) }
    for (time, up) in path { for i in 0..<3 { ev.append(.move(i, CGPoint(x: h[i].x, y: h[i].y - up), time)) } }
    let (last, up) = path.last!
    for i in 0..<3 { ev.append(.up(i, CGPoint(x: h[i].x, y: h[i].y - up), last + 0.000_1 * Double(i))) }
    return ev
}
// 5 pt over a second, then 30 pt in 40 ms: 35 pt in all (under swipeDistance), about 600 pt/s over the
// last 50 ms: a flick.
/// `steps` samples 10 ms apart after `from` s, the fingers going from `up0` to `up0 + by` pt up.
func samples(from: Double, steps: Int, up0: CGFloat, by: CGFloat) -> [(Double, CGFloat)] {
    var out: [(Double, CGFloat)] = []
    for k in 1...steps {
        let time: Double = from + Double(k) * 0.01
        let up: CGFloat = up0 + by * CGFloat(k) / CGFloat(steps)
        out.append((time, up))
    }
    return out
}
let slow = samples(from: 0.032, steps: 100, up0: 0, by: 5)
let flick = slow + samples(from: 1.032, steps: 4, up0: 5, by: 30)
check("5 pt slowly, then 30 pt in 40 ms: a flick, swipe up", only(run(upThrough(flick)), .swipeUp))
// The same 30 pt in 80 ms: about 375 pt/s over the last 50 ms.
let notFlick = slow + samples(from: 1.032, steps: 8, up0: 5, by: 30)
check("the same 30 pt in 80 ms: nothing", armedNothing(run(upThrough(notFlick))))
// 30 pt fast, then still for 60 ms (no new sample) before the lift: no speed left at the lift.
check("30 pt fast, then still 60 ms before the lift: nothing",
      armedNothing(run(upThrough([(0.042, 10), (0.052, 20), (0.062, 30), (0.122, 30)]))))

// MARK: - The axis

check("right 40, down 30 (1.33): swipe right", only(run(swipe(dx: 40, dy: 30)), .swipeRight))
check("right 40, down 31 (1.29): not a swipe, nothing", armedNothing(run(swipe(dx: 40, dy: 31))))
check("right 39, down 30 (exactly 1.3): swipe right", only(run(swipe(dx: 39, dy: 30)), .swipeRight))
check("up 40, left 30 (1.33): swipe up", only(run(swipe(dx: -30, dy: -40)), .swipeUp))
check("up 40, left 31 (1.29): nothing", armedNothing(run(swipe(dx: -31, dy: -40))))
check("up 39, right 30 (exactly 1.3): swipe up", only(run(swipe(dx: 30, dy: -39)), .swipeUp))
check("a diagonal of 60 on each axis: nothing", armedNothing(run(swipe(dx: 60, dy: 60))))

// MARK: - Pinch and spread

check("pinch to 0.5: pinch", only(run(pinch(scale: 0.5)), .pinch))
/// A 3-4-5 triangle about an exact centroid: the fingers 30, 40 and 50 pt from it, a mean of exactly
/// 40, so a scale of 0.75 or 1.25 lands exactly on the ratio.
let triangle = [CGPoint(x: 330, y: 300), CGPoint(x: 300, y: 340), CGPoint(x: 270, y: 260)]
check("pinch to exactly 0.75: pinch", only(run(pinch(scale: 0.75, from: triangle)), .pinch))
check("pinch to 0.76: nothing", armedNothing(run(pinch(scale: 0.76, from: triangle))))
check("spread to 1.8: spread", only(run(pinch(scale: 1.8)), .spread))
check("spread to exactly 1.25: spread", only(run(pinch(scale: 1.25, from: triangle)), .spread))
check("spread to 1.24: nothing", armedNothing(run(pinch(scale: 1.24, from: triangle))))
check("pinch the hand to 0.76: nothing", armedNothing(run(pinch(scale: 0.76))))
check("spread the hand to 1.24: nothing", armedNothing(run(pinch(scale: 1.24))))
do {
    // Up 60 while spreading to 1.5: the travel wins.
    let start = hand(3)
    let c = CGPoint(x: start.map(\.x).reduce(0, +) / 3, y: start.map(\.y).reduce(0, +) / 3)
    let both = stroke(start) { _, k, p in
        let s = 1 + 0.5 * CGFloat(k) / 10
        return CGPoint(x: c.x + (p.x - c.x) * s, y: c.y + (p.y - c.y) * s - 60 * CGFloat(k) / 10)
    }
    check("up 60 while spreading to 1.5: the swipe wins", only(run(both), .swipeUp))
    // A diagonal 50 on each axis while spreading: not a swipe (the axis), so a spread.
    let diagonal = stroke(start) { _, k, p in
        let s = 1 + 0.5 * CGFloat(k) / 10
        return CGPoint(x: c.x + (p.x - c.x) * s + 50 * CGFloat(k) / 10, y: c.y + (p.y - c.y) * s + 50 * CGFloat(k) / 10)
    }
    check("a diagonal 50 by 50 while spreading to 1.5: spread", only(run(diagonal), .spread))
    // Up 30 (under the swipe) while pinching to 0.5: a pinch.
    let small = stroke(start, steps: 50, dt: 0.02) { _, k, p in
        let s = 1 - 0.5 * CGFloat(k) / 50
        return CGPoint(x: c.x + (p.x - c.x) * s, y: c.y + (p.y - c.y) * s - 30 * CGFloat(k) / 50)
    }
    check("up 30 slowly while pinching to 0.5: pinch", only(run(small), .pinch))
}
do {
    // Three fingers on one spot: no spread to measure; a still stroke decides nothing.
    let p = CGPoint(x: 200, y: 200)
    let ev: [Event] = [.down(0, p, 0, holding: false), .down(1, p, 0.01, holding: false), .down(2, p, 0.02, holding: false),
                       .up(0, p, 0.3), .up(1, p, 0.31), .up(2, p, 0.32)]
    check("three fingers on one spot, still: armed, nothing", armedNothing(run(ev)))
}

// MARK: - Arming

func threeDown(at times: [Double], holding: [Bool] = [false, false, false]) -> [Event] {
    hand(3).enumerated().map { .down($0.offset, $0.element, times[$0.offset], holding: holding[$0.offset]) }
}
check("the third lands at exactly chordWindow (0.15 s): armed", run(threeDown(at: [0, 0.05, 0.15])).armedAt == 2)
check("the third lands at 0.1501 s: never armed", run(threeDown(at: [0, 0.05, 0.1501])).armedAt == nil)
check("all three together (one event's time): armed", run(threeDown(at: [0, 0, 0])).armedAt == 2)
check("the third with a button held: never armed", run(threeDown(at: [0, 0.01, 0.02], holding: [false, false, true])).armedAt == nil)
check("a button held at the first finger only: armed at the third", run(threeDown(at: [0, 0.01, 0.02], holding: [true, false, false])).armedAt == 2)
do {
    let h = hand(3)
    let moved23: [Event] = [.down(0, h[0], 0, holding: false), .move(0, CGPoint(x: h[0].x, y: h[0].y - 23.9), 0.03),
                            .down(1, h[1], 0.05, holding: false), .down(2, h[2], 0.08, holding: false)]
    check("the first finger moved 23.9 pt before the third: armed", run(moved23).armedAt == 3)
    let moved24: [Event] = [.down(0, h[0], 0, holding: false), .move(0, CGPoint(x: h[0].x + 24, y: h[0].y), 0.03),
                            .down(1, h[1], 0.05, holding: false), .down(2, h[2], 0.08, holding: false)]
    check("the first finger moved exactly 24 pt: never armed", run(moved24).armedAt == nil)
    let movedBack: [Event] = [.down(0, h[0], 0, holding: false), .move(0, CGPoint(x: h[0].x + 30, y: h[0].y), 0.02),
                              .move(0, h[0], 0.04), .down(1, h[1], 0.05, holding: false), .down(2, h[2], 0.08, holding: false)]
    check("a finger that moved 30 pt and came back: never armed", run(movedBack).armedAt == nil)
    let secondMoved: [Event] = [.down(0, h[0], 0, holding: false), .down(1, h[1], 0.02, holding: false),
                                .move(1, CGPoint(x: h[1].x, y: h[1].y + 25), 0.04), .down(2, h[2], 0.06, holding: false)]
    check("the second finger moved 25 pt: never armed", run(secondMoved).armedAt == nil)
    // Two scroll 60 pt, a third lands 133 ms after the first (the rig's): never armed, never silent.
    var scroll: [Event] = [.down(0, h[0], 0, holding: false), .down(1, h[1], 0.016, holding: false)]
    for k in 1...6 { scroll.append(.move(0, CGPoint(x: h[0].x, y: h[0].y - CGFloat(k) * 10), 0.016 + Double(k) * 0.016)); scroll.append(.move(1, CGPoint(x: h[1].x, y: h[1].y - CGFloat(k) * 10), 0.016 + Double(k) * 0.016)) }
    scroll.append(.down(2, h[2], 0.133, holding: false))
    for k in 1...10 { for i in 0..<3 { let base = i == 2 ? h[2] : CGPoint(x: h[i].x, y: h[i].y - 60); scroll.append(.move(i, CGPoint(x: base.x, y: base.y - CGFloat(k) * 12), 0.133 + Double(k) * 0.016)) } }
    scroll += [.up(0, h[0], 0.4), .up(1, h[1], 0.41), .up(2, h[2], 0.42)]
    let s = run(scroll)
    check("two scroll, a third joins after 133 ms: never armed", s.armedAt == nil && s.outputs.isEmpty)
    check("and never silent", !s.silentAfter.contains(true))
}
check("two fingers swipe up 100 pt: nothing, never silent", { let r = run(swipe(2, dx: 0, dy: -100)); return r.outputs.isEmpty && !r.silentAfter.contains(true) }())
check("one finger: nothing, never silent", { let r = run(swipe(1, dx: 0, dy: -100)); return r.outputs.isEmpty && !r.silentAfter.contains(true) }())
check("three fingers 50 ms apart: armed at the third", run(swipe(dx: 0, dy: -60, stagger: 0.05)).armedAt == 2)
check("three fingers 80 ms apart (the third at 0.16 s): never armed", run(swipe(dx: 0, dy: -60, stagger: 0.08)).armedAt == nil)
check("armed exactly once", run(swipe(4, dx: 0, dy: -60)).outputs.filter { $0 == .armed }.count == 1)

// MARK: - Silence

do {
    let r = run(swipe(dx: 0, dy: -60))
    check("not silent before the third finger", r.silentAfter[0] == false && r.silentAfter[1] == false)
    check("silent from the third finger", r.silentAfter[2] == true)
    check("still silent after the last lift", r.silentAfter.last == true)
    var g = G()
    _ = run(swipe(dx: 0, dy: -60), &g)
    _ = g.down(9, at: CGPoint(x: 10, y: 10), time: 5, holding: false)
    check("the next stroke's first touch ends the silence", g.silent == false)
    _ = g.up(9, at: CGPoint(x: 10, y: 10), time: 5.1)
    check("a tap after it is not silent", g.silent == false)
    var h = G()
    _ = run(swipe(dx: 0, dy: -60), &h)
    let again = run(swipe(dx: 60, dy: 0).map { e -> Event in
        switch e {
        case .down(let i, let p, let t, let hd): return .down(i, p, t + 10, holding: hd)
        case .move(let i, let p, let t): return .move(i, p, t + 10)
        case .up(let i, let p, let t): return .up(i, p, t + 10)
        case .cancel(let i): return .cancel(i)
        }
    }, &h)
    check("a second three-finger stroke arms and decides afresh", again.outputs == [.armed, .gesture(.swipeRight, fingers: 3)])
}

// MARK: - Four, five, cancels, one decision

check("four fingers up 60: swipe up, fingers 4", only(run(swipe(4, dx: 0, dy: -60)), .swipeUp, fingers: 4))
check("four fingers left 60: swipe left, fingers 4", only(run(swipe(4, dx: -60, dy: 0)), .swipeLeft, fingers: 4))
do {
    // The fourth finger stays where it landed while the three swipe up: still the three's swipe.
    let h = hand(4)
    let ev = stroke(h) { i, k, p in i == 3 ? p : CGPoint(x: p.x, y: p.y - 6 * CGFloat(k)) }
    check("a fourth finger that stays: the three decide, swipe up, fingers 4", only(run(ev), .swipeUp, fingers: 4))
    // The fourth moves right 200 while the three swipe up: still up.
    let ev2 = stroke(h) { i, k, p in i == 3 ? CGPoint(x: p.x + 20 * CGFloat(k), y: p.y) : CGPoint(x: p.x, y: p.y - 6 * CGFloat(k)) }
    check("a fourth finger going its own way: the three decide", only(run(ev2), .swipeUp, fingers: 4))
    // The fourth lifts first, the three still down and moved: that lift decides, from the three.
    var ev3 = stroke(h, steps: 10) { _, k, p in CGPoint(x: p.x, y: p.y + 6 * CGFloat(k)) }
    if let i = ev3.firstIndex(where: { if case .up = $0 { return true } else { return false } }) {
        let ups = ev3[i...].compactMap { e -> (Int, CGPoint, Double)? in if case .up(let a, let b, let c) = e { return (a, b, c) } else { return nil } }
        ev3.removeSubrange(i...)
        let order = [3, 0, 1, 2]
        for (j, id) in order.enumerated() { let u = ups.first { $0.0 == id }!; ev3.append(.up(id, u.1, ups[0].2 + Double(j) * 0.008)) }
    }
    check("the fourth finger lifts first: it decides, from the three, swipe down", only(run(ev3), .swipeDown, fingers: 4))
    // Four together in one event.
    let together = stroke(h, stagger: 0) { _, k, p in CGPoint(x: p.x - 7 * CGFloat(k), y: p.y) }
    check("four landing together: swipe left, fingers 4", only(run(together), .swipeLeft, fingers: 4))
}
check("five fingers swipe up: silent, nothing decided", armedNothing(run(swipe(5, dx: 0, dy: -80))))
check("five fingers: silent after", run(swipe(5, dx: 0, dy: -80)).silentAfter.last == true)
do {
    // Cancelled mid-swipe: nothing, and still silent.
    var ev = Array(swipe(dx: 0, dy: -80).prefix(3 + 3 * 5))
    ev += [.cancel(0), .cancel(1), .cancel(2)]
    let r = run(ev)
    check("three fingers cancelled mid-swipe: armed, nothing", r.outputs == [.armed])
    check("still silent after the cancel", r.silentAfter.last == true)
    // One cancelled, the other two lift after a swipe: nothing (the cancel decided).
    var ev2 = Array(swipe(dx: 0, dy: -80).prefix(3 + 3 * 10))
    ev2 += [.cancel(1), .up(0, CGPoint(x: hand(3)[0].x, y: hand(3)[0].y - 80), 0.5), .up(2, CGPoint(x: hand(3)[2].x, y: hand(3)[2].y - 80), 0.51)]
    check("one finger cancelled after the swipe, two lift: nothing", run(ev2).outputs == [.armed])
    // Cancelled before arming: the third finger after it does not arm.
    let h = hand(3)
    let ev3: [Event] = [.down(0, h[0], 0, holding: false), .down(1, h[1], 0.01, holding: false), .cancel(0),
                        .down(0, h[0], 0.02, holding: false), .down(2, h[2], 0.03, holding: false)]
    check("a touch cancelled before arming: that stroke never arms", run(ev3).armedAt == nil)
    // Four fingers, iPadOS takes them all (cancels): nothing reaches the Mac.
    var ev4 = Array(swipe(4, dx: 0, dy: -100).prefix(4 + 4 * 6))
    ev4 += [.cancel(0), .cancel(1), .cancel(2), .cancel(3)]
    check("four fingers taken by iPadOS (cancelled): nothing", run(ev4).outputs == [.armed])
}
do {
    // One decision a stroke: after the first lift decides up, the others keep moving and lift: nothing more.
    let h = hand(3)
    var ev: [Event] = h.enumerated().map { .down($0.offset, $0.element, Double($0.offset) * 0.016, holding: false) }
    for k in 1...10 { for i in 0..<3 { ev.append(.move(i, CGPoint(x: h[i].x, y: h[i].y - 6 * CGFloat(k)), 0.032 + Double(k) * 0.01)) } }
    ev.append(.up(0, CGPoint(x: h[0].x, y: h[0].y - 60), 0.14))
    for k in 1...10 { for i in 1..<3 { ev.append(.move(i, CGPoint(x: h[i].x + 10 * CGFloat(k), y: h[i].y - 60), 0.14 + Double(k) * 0.01)) } }
    ev += [.up(1, CGPoint(x: h[1].x + 100, y: h[1].y - 60), 0.3), .up(2, CGPoint(x: h[2].x + 100, y: h[2].y - 60), 0.31)]
    check("one decision a stroke: the first lift's swipe up, nothing after", only(run(ev), .swipeUp))
    // A swipe taken back before the lift: nothing.
    var back: [Event] = h.enumerated().map { .down($0.offset, $0.element, Double($0.offset) * 0.016, holding: false) }
    for k in 1...10 { for i in 0..<3 { back.append(.move(i, CGPoint(x: h[i].x, y: h[i].y - 8 * CGFloat(k)), 0.032 + Double(k) * 0.02)) } }
    for k in 1...10 { for i in 0..<3 { back.append(.move(i, CGPoint(x: h[i].x, y: h[i].y - 80 + 8 * CGFloat(k)), 0.232 + Double(k) * 0.02)) } }
    back += (0..<3).map { .up($0, h[$0], 0.6 + Double($0) * 0.01) }
    check("up 80 and back before the lift: nothing", armedNothing(run(back)))
    // The decision is measured from arming, not landing: the fingers moved 20 pt down before the third
    // landed, then 45 up: 45 from where they were at arming, a swipe up (25 from where they landed).
    var fromArming: [Event] = [.down(0, h[0], 0, holding: false), .move(0, CGPoint(x: h[0].x, y: h[0].y + 20), 0.01),
                               .down(1, CGPoint(x: h[1].x, y: h[1].y + 20), 0.02, holding: false),
                               .down(2, CGPoint(x: h[2].x, y: h[2].y + 20), 0.03, holding: false)]
    for k in 1...15 { for i in 0..<3 { fromArming.append(.move(i, CGPoint(x: h[i].x, y: h[i].y + 20 - 3 * CGFloat(k)), 0.03 + Double(k) * 0.03)) } }
    fromArming += (0..<3).map { .up($0, CGPoint(x: h[$0].x, y: h[$0].y - 25), 0.5 + Double($0) * 0.01) }
    check("measured from arming: 45 pt up from there is a swipe up", only(run(fromArming), .swipeUp))
}
do {
    var g = G()
    check("up for a finger never down: nothing", g.up(7, at: .zero, time: 1) == .none)
    g.moved(7, to: CGPoint(x: 50, y: 50), time: 1)
    g.cancelled(7)
    check("a move and a cancel for an unknown finger change nothing", g.silent == false)
    let a = run(swipe(dx: 12, dy: -70)), b = run(swipe(dx: 12, dy: -70))
    check("the same touches, the same outputs", a.outputs == b.outputs && a.silentAfter == b.silentAfter)
    check("the gestures, named as kind 28 names them", G.Gesture.allCases.map(\.rawValue) == ["swipeUp", "swipeDown", "swipeLeft", "swipeRight", "pinch", "spread"])
    let t = G()
    check("the tunables are the plan's", t.chordWindow == 0.15 && t.chordTravel == 24 && t.swipeDistance == 40 && t.flickDistance == 20
          && t.flickSpeed == 500 && t.flickWindow == 0.05 && t.axisRatio == 1.3 && t.pinchRatio == 0.25)
}

// MARK: - More edges

check("down exactly 40 pt, slowly: a swipe", only(run(swipe(dx: 0, dy: 40, steps: 40, dt: 0.02)), .swipeDown))
check("right exactly 40 pt, slowly: a swipe", only(run(swipe(dx: 40, dy: 0, steps: 40, dt: 0.02)), .swipeRight))
check("down 39.9 pt, slowly: nothing", armedNothing(run(swipe(dx: 0, dy: 39.9, steps: 40, dt: 0.02))))
check("left 25 pt fast: a flick, swipe left", only(run(swipe(dx: -25, dy: 0, steps: 3, dt: 0.01)), .swipeLeft))
check("up 25 pt fast: a flick, swipe up", only(run(swipe(dx: 0, dy: -25, steps: 3, dt: 0.01)), .swipeUp))
check("four fingers pinch to 0.5: pinch, fingers 4", only(run(pinch(4, scale: 0.5)), .pinch, fingers: 4))
check("four fingers spread to 1.8: spread, fingers 4", only(run(pinch(4, scale: 1.8)), .spread, fingers: 4))
check("a three-finger tap: armed, nothing", armedNothing(run(stroke(hand(3), steps: 1, dt: 0.05) { _, _, p in p })))
do {
    let h = hand(3)
    // Resting 0.6 s after landing, then a swipe (the rig's case that dragged): armed at landing, a swipe.
    var rest: [Event] = h.enumerated().map { .down($0.offset, $0.element, Double($0.offset) * 0.016, holding: false) }
    for k in 1...10 { for i in 0..<3 { rest.append(.move(i, CGPoint(x: h[i].x, y: h[i].y - 6 * CGFloat(k)), 0.632 + Double(k) * 0.01)) } }
    rest += (0..<3).map { .up($0, CGPoint(x: h[$0].x, y: h[$0].y - 60), 0.8 + Double($0) * 0.01) }
    check("three rest 0.6 s, then swipe up: swipe up", only(run(rest), .swipeUp))
    // One lifts before anything moved: that lift decides nothing; the two that swipe on decide nothing more.
    var early: [Event] = h.enumerated().map { .down($0.offset, $0.element, Double($0.offset) * 0.016, holding: false) }
    early.append(.up(2, h[2], 0.1))
    for k in 1...10 { for i in 0..<2 { early.append(.move(i, CGPoint(x: h[i].x, y: h[i].y - 8 * CGFloat(k)), 0.1 + Double(k) * 0.01)) } }
    early += [.up(0, CGPoint(x: h[0].x, y: h[0].y - 80), 0.3), .up(1, CGPoint(x: h[1].x, y: h[1].y - 80), 0.31)]
    let e = run(early)
    check("one lifts before anything moved, two swipe on: nothing", armedNothing(e))
    check("and those two send nothing either (silent)", e.silentAfter.last == true)
    // The lift's own position counts: the moves reached 30 pt, the lift reports 60.
    var liftPos: [Event] = h.enumerated().map { .down($0.offset, $0.element, Double($0.offset) * 0.016, holding: false) }
    for k in 1...10 { for i in 0..<3 { liftPos.append(.move(i, CGPoint(x: h[i].x - 3 * CGFloat(k), y: h[i].y), 0.032 + Double(k) * 0.05)) } }
    liftPos.append(.up(0, CGPoint(x: h[0].x - 120, y: h[0].y), 0.6))
    liftPos += [.up(1, CGPoint(x: h[1].x - 30, y: h[1].y), 0.61), .up(2, CGPoint(x: h[2].x - 30, y: h[2].y), 0.62)]
    check("the lifting finger's own position counts (30 pt moved, it lifts 120 pt out): swipe left", only(run(liftPos), .swipeLeft))
    // A fourth finger landing after the decision changes nothing.
    var late4: [Event] = Array(swipe(dx: 0, dy: -60).dropLast(2))
    late4.append(.down(3, CGPoint(x: 500, y: 500), 0.5, holding: false))
    late4 += [.up(1, h[1], 0.6), .up(2, h[2], 0.61), .up(3, CGPoint(x: 500, y: 500), 0.62)]
    check("a fourth finger after the decision: still swipe up, fingers 3", only(run(late4), .swipeUp))
    // A button held at the fourth finger: the stroke armed already, it decides as always.
    var held4: [Event] = hand(4).enumerated().map { .down($0.offset, $0.element, Double($0.offset) * 0.016, holding: $0.offset == 3) }
    for k in 1...10 { for i in 0..<4 { held4.append(.move(i, CGPoint(x: hand(4)[i].x, y: hand(4)[i].y + 6 * CGFloat(k)), 0.05 + Double(k) * 0.01)) } }
    held4 += (0..<4).map { .up($0, CGPoint(x: hand(4)[$0].x, y: hand(4)[$0].y + 60), 0.2 + Double($0) * 0.01) }
    check("a button held only at the fourth finger: swipe down, fingers 4", only(run(held4), .swipeDown, fingers: 4))
    // A fourth finger landing after the three moved 30 pt up; then 30 more: 60 from arming, a swipe (a
    // fourth finger that re-based the stroke would leave 30).
    var mid4: [Event] = h.enumerated().map { .down($0.offset, $0.element, Double($0.offset) * 0.016, holding: false) }
    for k in 1...5 { for i in 0..<3 { mid4.append(.move(i, CGPoint(x: h[i].x, y: h[i].y - 6 * CGFloat(k)), 0.032 + Double(k) * 0.02)) } }
    mid4.append(.down(3, CGPoint(x: 480, y: 300), 0.15, holding: false))
    for k in 1...5 { for i in 0..<3 { mid4.append(.move(i, CGPoint(x: h[i].x, y: h[i].y - 30 - 6 * CGFloat(k)), 0.15 + Double(k) * 0.02)) } }
    mid4 += (0..<3).map { .up($0, CGPoint(x: h[$0].x, y: h[$0].y - 60), 0.3 + Double($0) * 0.01) } + [.up(3, CGPoint(x: 480, y: 300), 0.34)]
    check("a fourth finger landing mid-swipe does not re-base it: swipe up, fingers 4", only(run(mid4), .swipeUp, fingers: 4))
    // A cancelled stroke's silence ends with the next stroke's first touch.
    var g = G()
    _ = run(Array(swipe(dx: 0, dy: -60).prefix(9)) + [.cancel(0), .cancel(1), .cancel(2)], &g)
    let wasSilent = g.silent
    _ = g.down(20, at: CGPoint(x: 100, y: 100), time: 3, holding: false)
    check("a cancelled stroke stays silent until the next stroke's first touch", wasSilent && !g.silent)
}

// MARK: - A touch that is not a finger

do {
    var g = G()
    _ = run(swipe(dx: 0, dy: -60), &g)
    let wasSilent = g.silent
    g.otherTouch()
    check("a Pencil after a finished gesture ends its silence", wasSilent && !g.silent)
    var h = G()
    let three = Array(swipe(dx: 0, dy: -60).prefix(3 + 3 * 5))
    _ = run(three, &h)
    h.otherTouch()
    check("a Pencil while the gesture's fingers are down leaves it silent", h.silent)
    let rest = run(Array(swipe(dx: 0, dy: -60).dropFirst(3 + 3 * 5)), &h)
    check("and the gesture still decides at the lift", rest.outputs == [.gesture(.swipeUp, fingers: 3)])
}

// MARK: - Sending (StreamClient.sendGesture's rule)

func sending(on: Bool = true, up: Bool = true, takes: Int?, window: Bool = false) -> (Bool, Bool) {
    let r = G.sending(switchOn: on, connected: up, hostGestures: takes, generation: 1, windowStreams: window)
    return (r.send, r.desktopFirst)
}
check("a Mac that says gestures 1: sent", sending(takes: 1) == (true, false))
check("a Mac from before (gestures nil): nothing sent", sending(takes: nil) == (false, false))
check("gestures 0: nothing sent", sending(takes: 0) == (false, false))
check("a later Mac (gestures 2) takes these too: sent", sending(takes: 2) == (true, false))
check("the switch off: nothing sent", sending(on: false, takes: 1) == (false, false))
check("no session: nothing sent", sending(up: false, takes: 1) == (false, false))
check("a window streaming: the Desktop first, then sent", sending(takes: 1, window: true) == (true, true))
check("a window streaming, an older Mac: no Desktop pick either", sending(takes: nil, window: true) == (false, false))
check("a window streaming, the switch off: no Desktop pick either", sending(on: false, takes: 1, window: true) == (false, false))

// MARK: - 5,000 random strokes against a model

/// The model: the plan's §6.1 written again, over a whole stroke's events at once.
func model(_ events: [Event]) -> (outputs: [G.Output], silent: [Bool]) {
    struct F { var landed: CGPoint; var now: CGPoint }
    var down: [Int: F] = [:]
    var outputs: [G.Output] = [], silent: [Bool] = []
    var s = false, first = 0.0, travelled = false, cancelled = false, three: [Int] = [], at: [Int: CGPoint] = [:], most = 0, over = false
    var samples: [(Double, CGPoint)] = []
    func mean(_ pts: [CGPoint]) -> CGPoint { CGPoint(x: pts.map(\.x).reduce(0, +) / CGFloat(pts.count), y: pts.map(\.y).reduce(0, +) / CGFloat(pts.count)) }
    for e in events {
        switch e {
        case .down(let id, let p, let t, let h):
            if down.isEmpty { s = false; first = t; travelled = false; cancelled = false; three = []; at = [:]; most = 0; over = false; samples = [] }
            down[id] = F(landed: p, now: p)
            if !three.isEmpty {
                most = max(most, down.count)
                if down.count > 4 { over = true }
            } else if down.count == 3 && t - first <= 0.15 && !travelled && !cancelled && !h {
                three = down.keys.sorted(); for i in three { at[i] = down[i]!.now }
                most = 3; s = true; samples = [(t, mean(three.map { at[$0]! }))]
                outputs.append(.armed)
            }
        case .move(let id, let p, let t):
            guard down[id] != nil else { break }
            down[id]!.now = p
            if three.isEmpty {
                if hypot(p.x - down[id]!.landed.x, p.y - down[id]!.landed.y) >= 24 { travelled = true }
            } else if !over && three.contains(id) {
                samples.append((t, mean(three.map { down[$0]?.now ?? at[$0]! })))
            }
        case .up(let id, let p, let t):
            guard down[id] != nil else { break }
            down[id]!.now = p
            if !three.isEmpty && !over {
                over = true
                let a = three.map { at[$0]! }, b = three.map { down[$0]?.now ?? at[$0]! }
                let c0 = mean(a), c1 = mean(b)
                let dx = c1.x - c0.x, dy = c1.y - c0.y, d = hypot(dx, dy)
                var ref = samples[0]
                for sm in samples where sm.0 <= t - 0.05 { ref = sm }
                let v = t - ref.0 > 0 ? hypot(c1.x - ref.1.x, c1.y - ref.1.y) / CGFloat(t - ref.0) : 0
                var g: G.Gesture?
                if (d >= 40 || (d >= 20 && v >= 500)) && max(abs(dx), abs(dy)) >= 1.3 * min(abs(dx), abs(dy)) {
                    g = abs(dx) > abs(dy) ? (dx < 0 ? .swipeLeft : .swipeRight) : (dy < 0 ? .swipeUp : .swipeDown)
                } else {
                    let r0 = a.map { hypot($0.x - c0.x, $0.y - c0.y) }.reduce(0, +) / 3
                    let r1 = b.map { hypot($0.x - c1.x, $0.y - c1.y) }.reduce(0, +) / 3
                    if r0 > 0 { if r1 / r0 <= 0.75 { g = .pinch } else if r1 / r0 >= 1.25 { g = .spread } }
                }
                if let g { outputs.append(.gesture(g, fingers: min(most, 4))) }
            }
            down[id] = nil
        case .cancel(let id):
            guard down[id] != nil else { break }
            down[id] = nil
            if three.isEmpty { cancelled = true } else { over = true }
        }
        silent.append(s)
    }
    return (outputs, silent)
}

var seed: UInt64 = 0x6E57_0DE5
func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 11) / Double(1 << 53) }
func randomStroke(from t0: Double, ids: Int) -> [Event] {
    let n = 1 + Int(rnd() * 5)                               // one to five fingers
    let c = CGPoint(x: 200 + rnd() * 400, y: 200 + rnd() * 300)
    var start = hand(n, at: c).map { CGPoint(x: $0.x + (rnd() - 0.5) * 20, y: $0.y + (rnd() - 0.5) * 20) }
    if rnd() < 0.1 { start = start.map { _ in c } }          // fingers on one spot
    var ev: [Event] = []
    var t = t0
    let stagger = rnd() < 0.2 ? 0 : rnd() * 0.12
    let dx = (rnd() - 0.5) * 160, dy = (rnd() - 0.5) * 160
    let scale = rnd() < 0.5 ? 1 : 0.4 + rnd() * 1.4
    let steps = 1 + Int(rnd() * 20)
    let dt = 0.004 + rnd() * 0.03
    let preMove = rnd() < 0.3 ? rnd() * 35 : 0                // the first finger moving before the rest land
    var now = start
    for i in 0..<n {
        ev.append(.down(ids + i, start[i], t, holding: rnd() < 0.05))
        if i == 0 && preMove > 0 { t += 0.005; now[0] = CGPoint(x: start[0].x + preMove, y: start[0].y); ev.append(.move(ids, now[0], t)) }
        t += stagger
    }
    let cancelAt = rnd() < 0.1 ? Int(rnd() * Double(steps + 1)) : -1
    let back = rnd() < 0.1
    let cx = start.map(\.x).reduce(0, +) / CGFloat(n), cy = start.map(\.y).reduce(0, +) / CGFloat(n)
    for k in 1...steps {
        t += dt
        if k == cancelAt { for i in 0..<n { ev.append(.cancel(ids + i)) }; return ev }
        var f = CGFloat(k) / CGFloat(steps)
        if back { f = f < 0.5 ? 2 * f : 2 - 2 * f }
        let s = 1 + (scale - 1) * f
        for i in 0..<n {
            let p = CGPoint(x: cx + (start[i].x - cx) * s + dx * f + (rnd() - 0.5) * 3, y: cy + (start[i].y - cy) * s + dy * f + (rnd() - 0.5) * 3)
            now[i] = p
            if rnd() < 0.9 { ev.append(.move(ids + i, p, t)) }
        }
    }
    var order = Array(0..<n)
    if rnd() < 0.5 { order.shuffle(using: &shuffler) }
    for i in order { t += rnd() * 0.02; ev.append(.up(ids + i, now[i], t)) }
    return ev
}
struct Shuffler: RandomNumberGenerator { mutating func next() -> UInt64 { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return seed } }
var shuffler = Shuffler()
var mismatches = 0
var tallies: [String: Int] = [:]
var real = G()
var clock = 0.0
for k in 0..<5_000 {
    let ev = randomStroke(from: clock, ids: k * 10)
    clock = (ev.last?.time ?? clock) + 0.2
    let want = model(ev)
    let got = run(ev, &real)
    for o in want.outputs { if case .gesture(let g, let f) = o { tallies["\(g.rawValue)\(f)", default: 0] += 1 } else { tallies["armed", default: 0] += 1 } }
    if got.outputs != want.outputs || got.silentAfter != want.silent {
        mismatches += 1
        if mismatches <= 5 { print("  random \(k): got \(got.outputs) want \(want.outputs)") }
    }
}
check("5,000 random strokes (\(tallies.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))): outputs and silence as the model", mismatches == 0)
check("the random strokes reach every gesture", G.Gesture.allCases.allSatisfy { g in tallies.keys.contains { $0.hasPrefix(g.rawValue) } })

print("\(passes + fails) checks, \(fails) failed")
exit(fails == 0 ? 0 : 1)
