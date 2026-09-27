// H3 (docs/trackpad-gestures-plan.md §9.1): iOSClient/TrackpadGestures.swift on its own, the device's half of
// the trackpad gestures: which stroke goes silent (three fingers down before any has travelled, no button held,
// however slowly they came and whatever rests on the glass), which of those arms (the three that landed last,
// within the window), how long the silence lasts (until the next stroke's first touch), and what the first lift
// of one of the three decides: each swipe at, under and over its distances, the flick, the axis rule both ways,
// the fingers moving together (a thumb-led pinch, a grab, a thumb pinching with three fingers are no swipe),
// pinch and spread at their ratio, travel winning over a spread, a resting thumb, a brief extra contact, a
// fourth finger, a fifth, a cancel, a swipe taken back, one decision a stroke. Then 5,000 random strokes
// against a model written here from the plan.
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
    var armedAfter: [Bool] = []       // `armed` after each event
    var silencedAt: Int?              // the index of the event that silenced the stroke
    var armedAt: Int?                 // the index of the event after which the stroke was first armed
    var decidedAt: Int?               // the index of the event that output a gesture
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
        if out == .silenced, r.silencedAt == nil { r.silencedAt = i }
        if case .gesture = out, r.decidedAt == nil { r.decidedAt = i }
        if g.armed, r.armedAt == nil { r.armedAt = i }
        r.silentAfter.append(g.silent)
        r.armedAfter.append(g.armed)
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

/// The fingers land `stagger` s apart from `t0`, then every finger moves from `start` by `f(k)` (its
/// position at step k of `steps`, one step per `dt` s), then they lift one by one `liftGap` s apart.
/// Ids from `id0`.
func stroke(_ start: [CGPoint], stagger: Double = 0.016, steps: Int = 10, dt: Double = 0.01, liftGap: Double = 0.008,
            holding: Bool = false, t0: Double = 0, id0: Int = 0, move: (Int, Int, CGPoint) -> CGPoint) -> [Event] {
    var ev: [Event] = []
    for (i, p) in start.enumerated() { ev.append(.down(id0 + i, p, t0 + Double(i) * stagger, holding: holding)) }
    var t = t0 + Double(start.count - 1) * stagger
    var now = start
    for k in 1...max(steps, 1) {
        t += dt
        for i in start.indices {
            now[i] = move(i, k, start[i])
            ev.append(.move(id0 + i, now[i], t))
        }
    }
    for i in start.indices {
        t += liftGap
        ev.append(.up(id0 + i, now[i], t))
    }
    return ev
}
/// A swipe by (dx, dy) in `steps` even steps.
func swipe(_ n: Int = 3, dx: CGFloat, dy: CGFloat, steps: Int = 10, dt: Double = 0.01, stagger: Double = 0.016,
           t0: Double = 0, id0: Int = 0) -> [Event] {
    stroke(hand(n), stagger: stagger, steps: steps, dt: dt, t0: t0, id0: id0) { _, k, p in
        CGPoint(x: p.x + dx * CGFloat(k) / CGFloat(steps), y: p.y + dy * CGFloat(k) / CGFloat(steps))
    }
}
/// Every finger toward (scale < 1) or away from the fingers' centroid, to `scale` of its distance.
func pinch(_ n: Int = 3, scale: CGFloat, steps: Int = 12, stagger: Double = 0.016, from points: [CGPoint]? = nil) -> [Event] {
    let start = points ?? hand(n)
    let c = CGPoint(x: start.map(\.x).reduce(0, +) / CGFloat(start.count), y: start.map(\.y).reduce(0, +) / CGFloat(start.count))
    return stroke(start, stagger: stagger, steps: steps) { _, k, p in
        let s = 1 + (scale - 1) * CGFloat(k) / CGFloat(steps)
        return CGPoint(x: c.x + (p.x - c.x) * s, y: c.y + (p.y - c.y) * s)
    }
}
/// Every finger from its start to its end in `steps` even steps, `dt` apart, after landing `stagger` apart;
/// they lift in `liftOrder` (indices), `liftGap` apart.
func path(_ start: [CGPoint], to end: [CGPoint], steps: Int = 20, dt: Double = 0.012, stagger: Double = 0.016,
          liftOrder: [Int]? = nil, liftGap: Double = 0.01, t0: Double = 0, id0: Int = 0) -> [Event] {
    var ev: [Event] = []
    for (i, p) in start.enumerated() { ev.append(.down(id0 + i, p, t0 + Double(i) * stagger, holding: false)) }
    var t = t0 + Double(start.count - 1) * stagger
    for k in 1...steps {
        t += dt
        let f = CGFloat(k) / CGFloat(steps)
        for i in start.indices {
            ev.append(.move(id0 + i, CGPoint(x: start[i].x + (end[i].x - start[i].x) * f, y: start[i].y + (end[i].y - start[i].y) * f), t))
        }
    }
    for i in liftOrder ?? Array(start.indices) { t += liftGap; ev.append(.up(id0 + i, end[i], t)) }
    return ev
}
func gesture(_ r: Run) -> G.Output? { r.outputs.first { if case .gesture = $0 { return true } else { return false } } }
func only(_ r: Run, _ g: G.Gesture, fingers: Int = 3) -> Bool { r.outputs == [.silenced, .gesture(g, fingers: fingers)] }
func silencedNothing(_ r: Run) -> Bool { r.outputs == [.silenced] }
func shifted(_ ev: [Event], by dt: Double) -> [Event] {
    ev.map { e in
        switch e {
        case .down(let i, let p, let t, let h): return .down(i, p, t + dt, holding: h)
        case .move(let i, let p, let t): return .move(i, p, t + dt)
        case .up(let i, let p, let t): return .up(i, p, t + dt)
        case .cancel(let i): return .cancel(i)
        }
    }
}

// MARK: - Each direction, and the swipe's distance

check("three fingers 16 ms apart, up 60 pt: silenced, then swipe up", only(run(swipe(dx: 0, dy: -60)), .swipeUp))
check("down 60 pt: swipe down", only(run(swipe(dx: 0, dy: 60)), .swipeDown))
check("left 60 pt: swipe left", only(run(swipe(dx: -60, dy: 0)), .swipeLeft))
check("right 60 pt: swipe right", only(run(swipe(dx: 60, dy: 0)), .swipeRight))
check("up exactly 40 pt, slowly: a swipe (at swipeDistance)", only(run(swipe(dx: 0, dy: -40, steps: 40, dt: 0.02)), .swipeUp))
check("up 39.9 pt, slowly: nothing", silencedNothing(run(swipe(dx: 0, dy: -39.9, steps: 40, dt: 0.02))))
check("left exactly 40 pt, slowly: a swipe", only(run(swipe(dx: -40, dy: 0, steps: 40, dt: 0.02)), .swipeLeft))
check("right 39.9 pt, slowly: nothing", silencedNothing(run(swipe(dx: 39.9, dy: 0, steps: 40, dt: 0.02))))
check("up 200 pt: still one swipe up", only(run(swipe(dx: 0, dy: -200)), .swipeUp))
check("down exactly 40 pt, slowly: a swipe", only(run(swipe(dx: 0, dy: 40, steps: 40, dt: 0.02)), .swipeDown))
check("right exactly 40 pt, slowly: a swipe", only(run(swipe(dx: 40, dy: 0, steps: 40, dt: 0.02)), .swipeRight))
check("down 39.9 pt, slowly: nothing", silencedNothing(run(swipe(dx: 0, dy: 39.9, steps: 40, dt: 0.02))))

// MARK: - The flick

check("25 pt fast (about 660 pt/s): a flick, swipe down", only(run(swipe(dx: 0, dy: 25, steps: 3, dt: 0.01)), .swipeDown))
check("25 pt over a second: no flick, nothing", silencedNothing(run(swipe(dx: 0, dy: 25, steps: 50, dt: 0.02))))
check("exactly 20 pt fast: a flick", only(run(swipe(dx: 20, dy: 0, steps: 2, dt: 0.01)), .swipeRight))
check("19.9 pt fast: nothing", silencedNothing(run(swipe(dx: 19.9, dy: 0, steps: 2, dt: 0.01))))
check("left 25 pt fast: a flick, swipe left", only(run(swipe(dx: -25, dy: 0, steps: 3, dt: 0.01)), .swipeLeft))
check("up 25 pt fast: a flick, swipe up", only(run(swipe(dx: 0, dy: -25, steps: 3, dt: 0.01)), .swipeUp))
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
// 5 pt over a second, then 30 pt in 40 ms: 35 pt in all (under swipeDistance), about 600 pt/s over the
// last 50 ms: a flick.
let slow = samples(from: 0.032, steps: 100, up0: 0, by: 5)
let flick = slow + samples(from: 1.032, steps: 4, up0: 5, by: 30)
check("5 pt slowly, then 30 pt in 40 ms: a flick, swipe up", only(run(upThrough(flick)), .swipeUp))
// The same 30 pt in 80 ms: about 375 pt/s over the last 50 ms.
let notFlick = slow + samples(from: 1.032, steps: 8, up0: 5, by: 30)
check("the same 30 pt in 80 ms: nothing", silencedNothing(run(upThrough(notFlick))))
// 30 pt fast, then still for 60 ms (no new sample) before the lift: no speed left at the lift.
check("30 pt fast, then still 60 ms before the lift: nothing",
      silencedNothing(run(upThrough([(0.042, 10), (0.052, 20), (0.062, 30), (0.122, 30)]))))

// MARK: - The axis

check("right 40, down 30 (1.33): swipe right", only(run(swipe(dx: 40, dy: 30)), .swipeRight))
check("right 40, down 31 (1.29): not a swipe, nothing", silencedNothing(run(swipe(dx: 40, dy: 31))))
check("right 39, down 30 (exactly 1.3): swipe right", only(run(swipe(dx: 39, dy: 30)), .swipeRight))
check("up 40, left 30 (1.33): swipe up", only(run(swipe(dx: -30, dy: -40)), .swipeUp))
check("up 40, left 31 (1.29): nothing", silencedNothing(run(swipe(dx: -31, dy: -40))))
check("up 39, right 30 (exactly 1.3): swipe up", only(run(swipe(dx: 30, dy: -39)), .swipeUp))
check("a diagonal of 60 on each axis: nothing", silencedNothing(run(swipe(dx: 60, dy: 60))))

// MARK: - Pinch and spread

check("pinch to 0.5: pinch", only(run(pinch(scale: 0.5)), .pinch))
/// A 3-4-5 triangle about an exact centroid: the fingers 30, 40 and 50 pt from it, a mean of exactly
/// 40, so a scale of 0.75 or 1.25 lands exactly on the ratio.
let triangle = [CGPoint(x: 330, y: 300), CGPoint(x: 300, y: 340), CGPoint(x: 270, y: 260)]
check("pinch to exactly 0.75: pinch", only(run(pinch(scale: 0.75, from: triangle)), .pinch))
check("pinch to 0.76: nothing", silencedNothing(run(pinch(scale: 0.76, from: triangle))))
check("spread to 1.8: spread", only(run(pinch(scale: 1.8)), .spread))
check("spread to exactly 1.25: spread", only(run(pinch(scale: 1.25, from: triangle)), .spread))
check("spread to 1.24: nothing", silencedNothing(run(pinch(scale: 1.24, from: triangle))))
check("pinch the hand to 0.76: nothing", silencedNothing(run(pinch(scale: 0.76))))
check("spread the hand to 1.24: nothing", silencedNothing(run(pinch(scale: 1.24))))
check("four fingers pinch to 0.5: pinch, fingers 4", only(run(pinch(4, scale: 0.5)), .pinch, fingers: 4))
check("four fingers spread to 1.8: spread, fingers 4", only(run(pinch(4, scale: 1.8)), .spread, fingers: 4))
do {
    // Up 60 while spreading to 1.5: every finger still moves at least 54 up, together: the swipe wins.
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
    check("three fingers on one spot, still: silenced, nothing", silencedNothing(run(ev)))
}

// MARK: - Together: a pinch or a spread led by one digit is no swipe (the review's F2)

/// Two fingers 100 pt apart at y 300 stay; the thumb, 150 pt below at y 450 (or 30 pt below for a
/// spread), travels `by` toward (negative: away from) them. Thumb and fingers land 16 ms apart.
func thumbLed(_ by: CGFloat, thumbAt: CGFloat = 450) -> [Event] {
    let start = [CGPoint(x: 250, y: 300), CGPoint(x: 350, y: 300), CGPoint(x: 300, y: thumbAt)]
    let end = [start[0], start[1], CGPoint(x: 300, y: thumbAt - by)]
    return path(start, to: end)
}
for by in [60, 90, 110, 119, 120, 130, 200] as [CGFloat] {
    check("a thumb-led pinch, the thumb up \(Int(by)) to two still fingers: pinch", only(run(thumbLed(by)), .pinch))
}
for by in [110, 120, 150] as [CGFloat] {
    check("a thumb-led spread, the thumb down \(Int(by)) from two still fingers: spread", only(run(thumbLed(-by, thumbAt: 330)), .spread))
}
check("a quick thumb-led pinch, the thumb up 70 in 60 ms (a flick's speed): pinch",
      only(run(path([CGPoint(x: 250, y: 300), CGPoint(x: 350, y: 300), CGPoint(x: 300, y: 450)],
                    to: [CGPoint(x: 250, y: 300), CGPoint(x: 350, y: 300), CGPoint(x: 300, y: 380)], steps: 5)), .pinch))
/// A grab: the fingers 100 pt apart at y 200, the thumb `gap` below; each digit moves `d` toward the
/// other side, the fingers drawing in a quarter of that.
func grab(_ d: CGFloat, gap: CGFloat = 300) -> [Event] {
    let s = [CGPoint(x: 250, y: 200), CGPoint(x: 350, y: 200), CGPoint(x: 300, y: 200 + gap)]
    let e = [CGPoint(x: 250 + d * 0.25, y: 200 + d), CGPoint(x: 350 - d * 0.25, y: 200 + d), CGPoint(x: 300, y: 200 + gap - d)]
    return path(s, to: e)
}
for d in [60, 100, 115, 120, 140] as [CGFloat] {
    check("a grab, thumb and fingers \(Int(d)) pt each toward the other: pinch", only(run(grab(d, gap: d > 130 ? 320 : 300)), .pinch))
}
/// The Mac's own pinch: a thumb and three fingers (Apps on a Mac). The fingers come down `down` and
/// in `inward`, the thumb up `up`; the thumb lands fourth (after the three armed) or first (with them).
func macPinch(thumbFirst: Bool, down: CGFloat = 60, inward: CGFloat = 20, up: CGFloat = 60, spread: Bool = false) -> [Event] {
    let fingers = [CGPoint(x: 200, y: 300), CGPoint(x: 300, y: 285), CGPoint(x: 400, y: 300)]
    let thumb = CGPoint(x: 320, y: 470)
    let sign: CGFloat = spread ? -1 : 1
    var start = fingers, end = [CGPoint(x: 200 + inward * sign, y: 300 + down * sign), CGPoint(x: 300, y: 285 + down * sign),
                                CGPoint(x: 400 - inward * sign, y: 300 + down * sign)]
    if thumbFirst { start.insert(thumb, at: 0); end.insert(CGPoint(x: 320, y: 470 - up * sign), at: 0) }
    else { start.append(thumb); end.append(CGPoint(x: 320, y: 470 - up * sign)) }
    return path(start, to: end)
}
check("the Mac's pinch, the thumb landing fourth: pinch, fingers 4", only(run(macPinch(thumbFirst: false)), .pinch, fingers: 4))
check("the Mac's pinch, the thumb landing fourth, fingers down 45, thumb up 90: pinch, fingers 4",
      only(run(macPinch(thumbFirst: false, down: 45, inward: 25, up: 90)), .pinch, fingers: 4))
check("the Mac's pinch, the thumb landing first: pinch, fingers 4", only(run(macPinch(thumbFirst: true)), .pinch, fingers: 4))
check("the Mac's spread, the thumb landing fourth: spread, fingers 4", only(run(macPinch(thumbFirst: false, spread: true)), .spread, fingers: 4))
do {
    // Each of the three moves at least half the centroid's way along the swipe: at exactly half, a swipe.
    // Two fingers up 90, the third (between them) up 36: the centroid 72 up, half of it 36.
    let s = [CGPoint(x: 200, y: 300), CGPoint(x: 250, y: 300), CGPoint(x: 300, y: 300)]
    let atHalf = path(s, to: [CGPoint(x: 200, y: 210), CGPoint(x: 250, y: 264), CGPoint(x: 300, y: 210)])
    check("two up 90, one up 36 (exactly half the centroid's 72): swipe up", only(run(atHalf), .swipeUp))
    // The third up 35.9: short of half, not together; the two leave it behind, the spread grows: a spread.
    let short = path(s, to: [CGPoint(x: 200, y: 210), CGPoint(x: 250, y: 264.1), CGPoint(x: 300, y: 210)])
    check("two up 90, one up 35.9 (short of half): no swipe, a spread", only(run(short), .spread))
    // A fourth finger moving against the swipe: 29.9 pt against a 60 pt swipe up is less than half, the
    // swipe; 30 is half, no swipe (and, the spread short of 1.25, nothing). It moved (24 pt or more), so it
    // counts. Whole numbers throughout, so the half is exact.
    func againstBy(_ back: CGFloat) -> [Event] {
        let h4 = [CGPoint(x: 200, y: 300), CGPoint(x: 260, y: 300), CGPoint(x: 320, y: 300), CGPoint(x: 380, y: 310)]
        return stroke(h4) { i, k, p in i == 3 ? CGPoint(x: p.x, y: p.y + (k == 10 ? back : back * CGFloat(k) / 10)) : CGPoint(x: p.x, y: p.y - 6 * CGFloat(k)) }
    }
    check("three up 60, a fourth 29.9 pt the other way: swipe up, fingers 4", only(run(againstBy(29.9)), .swipeUp, fingers: 4))
    check("three up 60, a fourth exactly 30 pt the other way (half): no swipe, nothing", silencedNothing(run(againstBy(30))))
    // A fourth finger that moved under 24 pt does not take part: it neither breaks the swipe nor counts.
    check("three up 60, a fourth 23.9 pt the other way: swipe up, fingers 3", only(run(againstBy(23.9)), .swipeUp))
    check("three up 60, a fourth exactly 24 pt the other way: it took part, swipe up, fingers 4", only(run(againstBy(24)), .swipeUp, fingers: 4))
}

// MARK: - Silence and arming

func threeDown(at times: [Double], holding: [Bool] = [false, false, false]) -> [Event] {
    hand(3).enumerated().map { .down($0.offset, $0.element, times[$0.offset], holding: holding[$0.offset]) }
}
do {
    let r = run(threeDown(at: [0, 0.05, 0.15]))
    check("the third lands at exactly chordWindow (0.15 s): silenced and armed", r.silencedAt == 2 && r.armedAt == 2)
    let late = run(threeDown(at: [0, 0.05, 0.1501]))
    check("the third lands at 0.1501 s: silenced at the third all the same, never armed", late.silencedAt == 2 && late.armedAt == nil)
    let together = run(threeDown(at: [0, 0, 0]))
    check("all three together (one event's time): silenced and armed", together.silencedAt == 2 && together.armedAt == 2)
    let held = run(threeDown(at: [0, 0.01, 0.02], holding: [false, false, true]))
    check("the third with a button held: never silent, never armed", held.silencedAt == nil && held.armedAt == nil && !held.silentAfter.contains(true))
    let heldFirst = run(threeDown(at: [0, 0.01, 0.02], holding: [true, false, false]))
    check("a button held at the first finger only: silenced and armed at the third", heldFirst.silencedAt == 2 && heldFirst.armedAt == 2)
}
do {
    let h = hand(3)
    let moved23: [Event] = [.down(0, h[0], 0, holding: false), .move(0, CGPoint(x: h[0].x, y: h[0].y - 23.9), 0.03),
                            .down(1, h[1], 0.05, holding: false), .down(2, h[2], 0.08, holding: false)]
    let m23 = run(moved23)
    check("the first finger moved 23.9 pt before the third: silenced and armed", m23.silencedAt == 3 && m23.armedAt == 3)
    let moved24: [Event] = [.down(0, h[0], 0, holding: false), .move(0, CGPoint(x: h[0].x + 24, y: h[0].y), 0.03),
                            .down(1, h[1], 0.05, holding: false), .down(2, h[2], 0.08, holding: false)]
    let m24 = run(moved24)
    check("the first finger moved exactly 24 pt: never silent, never armed", m24.silencedAt == nil && m24.armedAt == nil)
    let movedBack: [Event] = [.down(0, h[0], 0, holding: false), .move(0, CGPoint(x: h[0].x + 30, y: h[0].y), 0.02),
                              .move(0, h[0], 0.04), .down(1, h[1], 0.05, holding: false), .down(2, h[2], 0.08, holding: false)]
    check("a finger that moved 30 pt and came back: never silent", run(movedBack).silencedAt == nil)
    let secondMoved: [Event] = [.down(0, h[0], 0, holding: false), .down(1, h[1], 0.02, holding: false),
                                .move(1, CGPoint(x: h[1].x, y: h[1].y + 25), 0.04), .down(2, h[2], 0.06, holding: false)]
    check("the second finger moved 25 pt: never silent", run(secondMoved).silencedAt == nil)
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
do {
    // Placed slowly (the review's B1 and B2): silent from the third finger, so nothing clicks or
    // scrolls; never armed, so nothing is decided either.
    let r = run(swipe(dx: 0, dy: -60, stagger: 0.08))
    check("three fingers 80 ms apart (the third at 0.16 s), up 60: silenced, never armed, nothing", silencedNothing(r) && r.armedAt == nil && r.silencedAt == 2)
    check("three fingers 100 ms apart, swipe up 180: silenced, nothing", silencedNothing(run(swipe(dx: 0, dy: -180, stagger: 0.1))))
    let p = run(pinch(scale: 0.45, stagger: 0.1))
    check("three fingers 100 ms apart, pinch to 0.45: silenced at the third, nothing", silencedNothing(p) && p.silencedAt == 2)
    check("and silent to the end", p.silentAfter.last == true)
}
check("silenced exactly once", run(swipe(4, dx: 0, dy: -60)).outputs.filter { $0 == .silenced }.count == 1)

// MARK: - A thumb resting on the glass (the review's F1)

/// A thumb (id 9) resting still since t = 0 at (40, 500); the fingers of `ev` come later. It lifts at `liftAt`,
/// or with the others when nil.
func withThumb(_ ev: [Event], thumbAt: CGPoint = CGPoint(x: 40, y: 500), liftAt: Double? = nil) -> [Event] {
    var out: [Event] = [.down(9, thumbAt, 0, holding: false)]
    out += ev
    let end = (ev.last?.time ?? 0) + 0.02
    if let liftAt, let i = out.firstIndex(where: { $0.time > liftAt && $0.time >= 0 }) {
        out.insert(.up(9, thumbAt, liftAt), at: i)
    } else {
        out.append(.up(9, thumbAt, liftAt ?? end))
    }
    return out
}
do {
    let r = run(withThumb(swipe(dx: 0, dy: -120, t0: 3)))
    check("a thumb resting since 0, three fingers land 16 ms apart at 3 s, up 120: swipe up, fingers 3", only(r, .swipeUp))
    check("silent from the second of them (three down), armed at the third", r.silencedAt == 2 && r.armedAt == 3)
    let pinched = run(withThumb(stroke(hand(3), steps: 12, t0: 3) { _, k, p in
        let c = CGPoint(x: 300, y: 300 + 0.05 * 62 / 3 * 3)
        let s = 1 - 0.55 * CGFloat(k) / 12
        return CGPoint(x: c.x + (p.x - c.x) * s, y: c.y + (p.y - c.y) * s)
    }))
    check("a resting thumb, three fingers pinch to 0.45: pinch, fingers 3", only(pinched, .pinch))
    // The thumb lifts first, after the three moved: its lift is not one of theirs and decides nothing.
    var ev = withThumb(swipe(dx: 0, dy: -120, t0: 3))
    let thumbUp = ev.removeLast()
    let firstLift = ev.firstIndex { if case .up = $0 { return true } else { return false } }!
    ev.insert(thumbUp, at: firstLift)
    if case .up(let i, let p, _) = ev[firstLift], i == 9 { ev[firstLift] = .up(9, p, ev[firstLift + 1].time - 0.001) }
    let t = run(ev)
    check("the resting thumb lifting first decides nothing; the first of the three to lift does: swipe up", only(t, .swipeUp) && t.decidedAt == firstLift + 1)
    // Three fingers the thumb rested beside, placed within the window over the last three landings.
    let atEdge = run(withThumb(threeDown(at: [3.0, 3.05, 3.15])))
    check("a resting thumb, three fingers at 3.0, 3.05 and 3.15 s: armed at exactly the window", atEdge.armedAt == 3)
    let pastEdge = run(withThumb(threeDown(at: [3.0, 3.05, 3.1501])))
    check("a resting thumb, three fingers at 3.0, 3.05 and 3.1501 s: silent, never armed", pastEdge.armedAt == nil && pastEdge.silencedAt == 2)
    // A thumb that dragged the pointer first: a stroke that travelled is never silent (today's).
    var dragged: [Event] = [.down(9, CGPoint(x: 40, y: 500), 0, holding: false), .move(9, CGPoint(x: 80, y: 500), 0.5)]
    dragged += swipe(dx: 0, dy: -120, t0: 3)
    dragged.append(.up(9, CGPoint(x: 80, y: 500), 4))
    let d = run(dragged)
    check("a thumb that moved 40 pt first, then three fingers: never silent, nothing", d.outputs.isEmpty && !d.silentAfter.contains(true))
    // Two fingers resting, a third lands half a second later: silent, never armed.
    let restTwo = run(threeDown(at: [0, 0.02, 0.52]))
    check("two fingers resting, a third 0.5 s later: silenced, never armed", restTwo.silencedAt == 2 && restTwo.armedAt == nil)
    // A resting thumb and four fingers: a fifth finger down, silent and deciding nothing.
    check("a resting thumb, four fingers swipe up: five down, silenced, nothing", silencedNothing(run(withThumb(swipe(4, dx: 0, dy: -100, t0: 3)))))
}

// MARK: - A brief extra contact (the review's F3)

/// Three fingers swipe up 120 at 300 pt/s (5 pt every 16.7 ms), landing 16 ms apart; a fourth contact lands at
/// `at` and lifts, still, at `liftAt`; or, with `moves`, goes up with them until it lifts.
func slowSwipe(fourthAt at: Double? = nil, liftAt: Double = 0, moves: Bool = false) -> [Event] {
    let h = hand(3)
    let fourth = CGPoint(x: 150, y: 420)
    var ev: [Event] = h.enumerated().map { .down($0.offset, $0.element, Double($0.offset) * 0.016, holding: false) }
    var t = 0.032, landed = false, lifted = false
    for k in 1...24 {
        t += 1.0 / 60
        if let at, !landed, t >= at { ev.append(.down(3, fourth, at, holding: false)); landed = true }
        for i in 0..<3 { ev.append(.move(i, CGPoint(x: h[i].x, y: h[i].y - 5 * CGFloat(k)), t)) }
        if landed, !lifted, moves { ev.append(.move(3, CGPoint(x: fourth.x, y: fourth.y - 5 * CGFloat(k)), t)) }
        if landed, !lifted, t >= liftAt {
            ev.append(.up(3, moves ? CGPoint(x: fourth.x, y: fourth.y - 5 * CGFloat(k)) : fourth, t)); lifted = true
        }
    }
    for i in 0..<3 { t += 0.01; ev.append(.up(i, CGPoint(x: h[i].x, y: h[i].y - 120), t)) }
    return ev
}
check("a slow swipe up 120, nothing else: swipe up, fingers 3", only(run(slowSwipe()), .swipeUp))
check("the same, a still fourth contact landing at 50 ms and lifting at 102 ms: swipe up, fingers 3",
      only(run(slowSwipe(fourthAt: 0.05, liftAt: 0.102)), .swipeUp))
check("the same, the contact lifting at 142 ms: swipe up, fingers 3", only(run(slowSwipe(fourthAt: 0.05, liftAt: 0.142)), .swipeUp))
do {
    let r = run(slowSwipe(fourthAt: 0.05, liftAt: 0.102))
    check("the contact's lift decides nothing; the first of the three to lift decides", r.decidedAt.map { i -> Bool in
        if case .up(let id, _, _) = slowSwipe(fourthAt: 0.05, liftAt: 0.102)[i] { return id == 0 } else { return false } } ?? false)
}
check("a fourth finger going up with them and lifting first: it took part, swipe up, fingers 4",
      only(run(slowSwipe(fourthAt: 0.05, liftAt: 0.3, moves: true)), .swipeUp, fingers: 4))
do {
    // A fast swipe (a flick's speed) with the brief contact: three fingers, not four.
    let h = hand(3)
    var ev: [Event] = h.enumerated().map { .down($0.offset, $0.element, Double($0.offset) * 0.016, holding: false) }
    ev.append(.down(3, CGPoint(x: 150, y: 420), 0.04, holding: false))
    for k in 1...3 { for i in 0..<3 { ev.append(.move(i, CGPoint(x: h[i].x, y: h[i].y - 10 * CGFloat(k)), 0.032 + Double(k) * 0.01)) } }
    ev.append(.up(3, CGPoint(x: 150, y: 420), 0.063))
    for i in 0..<3 { ev.append(.up(i, CGPoint(x: h[i].x, y: h[i].y - 30), 0.07 + Double(i) * 0.001)) }
    check("a flick up 30 with a still contact lifting first: swipe up, fingers 3", only(run(ev), .swipeUp))
}

// MARK: - Silence lasts until the next stroke

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
    let again = run(shifted(swipe(dx: 60, dy: 0), by: 10), &h)
    check("a second three-finger stroke silences and decides afresh", again.outputs == [.silenced, .gesture(.swipeRight, fingers: 3)])
    var s = G()
    _ = run(swipe(dx: 0, dy: -60, stagger: 0.1), &s)
    let wasSilent = s.silent
    _ = s.down(20, at: CGPoint(x: 100, y: 100), time: 3, holding: false)
    check("a stroke placed too slowly to arm stays silent until the next stroke's first touch", wasSilent && !s.silent)
}

// MARK: - Four, five, cancels, one decision

check("four fingers up 60: swipe up, fingers 4", only(run(swipe(4, dx: 0, dy: -60)), .swipeUp, fingers: 4))
check("four fingers left 60: swipe left, fingers 4", only(run(swipe(4, dx: -60, dy: 0)), .swipeLeft, fingers: 4))
do {
    let h = hand(4)
    // The fourth finger stays where it landed while the three swipe up: the three's swipe, and the fourth,
    // which took no part, is not counted.
    let ev = stroke(h) { i, k, p in i == 3 ? p : CGPoint(x: p.x, y: p.y - 6 * CGFloat(k)) }
    check("a fourth finger that stays still: the three decide, swipe up, fingers 3", only(run(ev), .swipeUp))
    // The fourth moves right 200 while the three swipe up: across the swipe, not against it: still up.
    let ev2 = stroke(h) { i, k, p in i == 3 ? CGPoint(x: p.x + 20 * CGFloat(k), y: p.y) : CGPoint(x: p.x, y: p.y - 6 * CGFloat(k)) }
    check("a fourth finger going its own way across the swipe: the three decide, swipe up, fingers 4", only(run(ev2), .swipeUp, fingers: 4))
    // All four swipe down and the fourth lifts first: its lift only leaves; the next of the three to lift
    // decides, and the fourth took part.
    var ev3 = stroke(h, steps: 10) { _, k, p in CGPoint(x: p.x, y: p.y + 6 * CGFloat(k)) }
    if let i = ev3.firstIndex(where: { if case .up = $0 { return true } else { return false } }) {
        let ups = ev3[i...].compactMap { e -> (Int, CGPoint, Double)? in if case .up(let a, let b, let c) = e { return (a, b, c) } else { return nil } }
        ev3.removeSubrange(i...)
        let order = [3, 0, 1, 2]
        for (j, id) in order.enumerated() { let u = ups.first { $0.0 == id }!; ev3.append(.up(id, u.1, ups[0].2 + Double(j) * 0.008)) }
    }
    let r3 = run(ev3)
    check("the fourth finger lifts first: only the next of the three decides, swipe down, fingers 4", only(r3, .swipeDown, fingers: 4))
    check("and it decides at the second lift", r3.decidedAt.map { i -> Bool in if case .up(0, _, _) = ev3[i] { return true } else { return false } } ?? false)
    // Four together in one event.
    let together = stroke(h, stagger: 0) { _, k, p in CGPoint(x: p.x - 7 * CGFloat(k), y: p.y) }
    check("four landing together: swipe left, fingers 4", only(run(together), .swipeLeft, fingers: 4))
}
check("five fingers swipe up: silent, nothing decided", silencedNothing(run(swipe(5, dx: 0, dy: -80))))
check("five fingers: silent after", run(swipe(5, dx: 0, dy: -80)).silentAfter.last == true)
do {
    // Cancelled mid-swipe: nothing, and still silent.
    var ev = Array(swipe(dx: 0, dy: -80).prefix(3 + 3 * 5))
    ev += [.cancel(0), .cancel(1), .cancel(2)]
    let r = run(ev)
    check("three fingers cancelled mid-swipe: silenced, nothing", r.outputs == [.silenced])
    check("still silent after the cancel", r.silentAfter.last == true)
    // One cancelled, the other two lift after a swipe: nothing (the cancel decided).
    var ev2 = Array(swipe(dx: 0, dy: -80).prefix(3 + 3 * 10))
    ev2 += [.cancel(1), .up(0, CGPoint(x: hand(3)[0].x, y: hand(3)[0].y - 80), 0.5), .up(2, CGPoint(x: hand(3)[2].x, y: hand(3)[2].y - 80), 0.51)]
    check("one finger cancelled after the swipe, two lift: nothing", run(ev2).outputs == [.silenced])
    // Cancelled before three were down: silent from the third all the same, never armed, nothing decided.
    let h = hand(3)
    var ev3: [Event] = [.down(0, h[0], 0, holding: false), .down(1, h[1], 0.01, holding: false), .cancel(0),
                        .down(0, h[0], 0.02, holding: false), .down(2, h[2], 0.03, holding: false)]
    for k in 1...10 { for i in 0..<3 { ev3.append(.move(i, CGPoint(x: h[i].x, y: h[i].y - 8 * CGFloat(k)), 0.03 + Double(k) * 0.01)) } }
    ev3 += (0..<3).map { .up($0, CGPoint(x: h[$0].x, y: h[$0].y - 80), 0.2 + Double($0) * 0.01) }
    let r3 = run(ev3)
    check("a touch cancelled before three were down: silenced at the third, never armed, nothing", silencedNothing(r3) && r3.silencedAt == 4 && r3.armedAt == nil)
    // Four fingers, iPadOS takes them all (cancels): nothing reaches the Mac.
    var ev4 = Array(swipe(4, dx: 0, dy: -100).prefix(4 + 4 * 6))
    ev4 += [.cancel(0), .cancel(1), .cancel(2), .cancel(3)]
    check("four fingers taken by iPadOS (cancelled): nothing", run(ev4).outputs == [.silenced])
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
    check("up 80 and back before the lift: nothing", silencedNothing(run(back)))
    // The decision is measured from arming, not landing: the fingers moved 20 pt down before the third
    // landed, then 45 up: 45 from where they were at arming, a swipe up (25 from where they landed).
    var fromArming: [Event] = [.down(0, h[0], 0, holding: false), .move(0, CGPoint(x: h[0].x, y: h[0].y + 20), 0.01),
                               .down(1, CGPoint(x: h[1].x, y: h[1].y + 20), 0.02, holding: false),
                               .down(2, CGPoint(x: h[2].x, y: h[2].y + 20), 0.03, holding: false)]
    for k in 1...15 { for i in 0..<3 { fromArming.append(.move(i, CGPoint(x: h[i].x, y: h[i].y + 20 - 3 * CGFloat(k)), 0.03 + Double(k) * 0.03)) } }
    fromArming += (0..<3).map { .up($0, CGPoint(x: h[$0].x, y: h[$0].y - 25), 0.5 + Double($0) * 0.01) }
    check("measured from arming: 45 pt up from there is a swipe up", only(run(fromArming), .swipeUp))
    // Resting 0.6 s after landing, then a swipe (the rig's case that dragged): silent from landing, a swipe.
    var rest: [Event] = h.enumerated().map { .down($0.offset, $0.element, Double($0.offset) * 0.016, holding: false) }
    for k in 1...10 { for i in 0..<3 { rest.append(.move(i, CGPoint(x: h[i].x, y: h[i].y - 6 * CGFloat(k)), 0.632 + Double(k) * 0.01)) } }
    rest += (0..<3).map { .up($0, CGPoint(x: h[$0].x, y: h[$0].y - 60), 0.8 + Double($0) * 0.01) }
    check("three rest 0.6 s, then swipe up: swipe up", only(run(rest), .swipeUp))
    // One of the three lifts before anything moved: that lift decides nothing; the two that swipe on
    // decide nothing more and send nothing.
    var early: [Event] = h.enumerated().map { .down($0.offset, $0.element, Double($0.offset) * 0.016, holding: false) }
    early.append(.up(2, h[2], 0.1))
    for k in 1...10 { for i in 0..<2 { early.append(.move(i, CGPoint(x: h[i].x, y: h[i].y - 8 * CGFloat(k)), 0.1 + Double(k) * 0.01)) } }
    early += [.up(0, CGPoint(x: h[0].x, y: h[0].y - 80), 0.3), .up(1, CGPoint(x: h[1].x, y: h[1].y - 80), 0.31)]
    let e = run(early)
    check("one of the three lifts before anything moved, two swipe on: nothing", silencedNothing(e))
    check("and those two send nothing either (silent)", e.silentAfter.last == true)
    // The lift's own position counts: the moves reached 30 pt, the lift reports 120 (and the other two, at
    // 30, moved exactly half the centroid's 60: together).
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
    // A fourth finger landing after the three moved 30 pt up, and staying; then 30 more: 60 from arming, a
    // swipe (a fourth finger that re-based the stroke would leave 30); it took no part.
    var mid4: [Event] = h.enumerated().map { .down($0.offset, $0.element, Double($0.offset) * 0.016, holding: false) }
    for k in 1...5 { for i in 0..<3 { mid4.append(.move(i, CGPoint(x: h[i].x, y: h[i].y - 6 * CGFloat(k)), 0.032 + Double(k) * 0.02)) } }
    mid4.append(.down(3, CGPoint(x: 480, y: 300), 0.15, holding: false))
    for k in 1...5 { for i in 0..<3 { mid4.append(.move(i, CGPoint(x: h[i].x, y: h[i].y - 30 - 6 * CGFloat(k)), 0.15 + Double(k) * 0.02)) } }
    mid4 += (0..<3).map { .up($0, CGPoint(x: h[$0].x, y: h[$0].y - 60), 0.3 + Double($0) * 0.01) } + [.up(3, CGPoint(x: 480, y: 300), 0.34)]
    check("a fourth finger landing mid-swipe does not re-base it: swipe up, fingers 3", only(run(mid4), .swipeUp))
    // The thumb of the Mac's pinch lifts first, where it moved 20 pt, having lifted 60 pt up: its lift's
    // position counts, so it took part and the stroke is the pinch it was.
    var liftedThumb = macPinch(thumbFirst: false)
    if let i = liftedThumb.lastIndex(where: { if case .up(3, _, _) = $0 { return true } else { return false } }) {
        liftedThumb.remove(at: i)
        let firstUp = liftedThumb.firstIndex { if case .up = $0 { return true } else { return false } }!
        // The thumb's moves stop at 20 pt up; it lifts 60 pt up just before the others.
        liftedThumb = liftedThumb.map { e in
            if case .move(3, let p, let t) = e { return .move(3, CGPoint(x: p.x, y: max(p.y, 470 - 20)), t) } else { return e }
        }
        liftedThumb.insert(.up(3, CGPoint(x: 320, y: 410), liftedThumb[firstUp].time - 0.001), at: firstUp)
    }
    check("the Mac's pinch, its thumb lifting first 60 pt up (its moves said 20): pinch, fingers 4", only(run(liftedThumb), .pinch, fingers: 4))
    // A cancelled stroke's silence ends with the next stroke's first touch.
    var g = G()
    _ = run(Array(swipe(dx: 0, dy: -60).prefix(9)) + [.cancel(0), .cancel(1), .cancel(2)], &g)
    let wasSilent = g.silent
    _ = g.down(20, at: CGPoint(x: 100, y: 100), time: 3, holding: false)
    check("a cancelled stroke stays silent until the next stroke's first touch", wasSilent && !g.silent)
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
    check("a swipe's direction is the way its fingers go, a pinch and a spread have none",
          G.Gesture.swipeUp.direction == CGVector(dx: 0, dy: -1) && G.Gesture.swipeDown.direction == CGVector(dx: 0, dy: 1)
          && G.Gesture.swipeLeft.direction == CGVector(dx: -1, dy: 0) && G.Gesture.swipeRight.direction == CGVector(dx: 1, dy: 0)
          && G.Gesture.pinch.direction == nil && G.Gesture.spread.direction == nil)
    let t = G()
    check("the tunables are the plan's", t.chordWindow == 0.15 && t.chordTravel == 24 && t.swipeDistance == 40 && t.flickDistance == 20
          && t.flickSpeed == 500 && t.flickWindow == 0.05 && t.axisRatio == 1.3 && t.swipeShare == 0.5 && t.pinchRatio == 0.25)
}
check("a three-finger tap: silenced, nothing", silencedNothing(run(stroke(hand(3), steps: 1, dt: 0.05) { _, _, p in p })))

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
    struct F { var landed: CGPoint; var at: Double; var now: CGPoint }
    var down: [Int: F] = [:]
    var outputs: [G.Output] = [], silent: [Bool] = []
    var s = false, travelled = false, cancelled = false, over = false
    var three: [Int] = [], start: [Int: CGPoint] = [:], other: [Int: (from: CGPoint, to: CGPoint)] = [:]
    var samples: [(Double, CGPoint)] = []
    func mean(_ ids: [Int], _ at: [Int: CGPoint]) -> CGPoint {
        let pts = ids.sorted().map { at[$0]! }
        return CGPoint(x: pts.map(\.x).reduce(0, +) / CGFloat(pts.count), y: pts.map(\.y).reduce(0, +) / CGFloat(pts.count))
    }
    for e in events {
        switch e {
        case .down(let id, let p, let t, let h):
            if down.isEmpty { s = false; travelled = false; cancelled = false; over = false; three = []; start = [:]; other = [:]; samples = [] }
            down[id] = F(landed: p, at: t, now: p)
            if down.count > 4 { over = true }
            if !three.isEmpty {
                other[id] = (p, p)
            } else if down.count >= 3 && !travelled && !h {
                if !s { s = true; outputs.append(.silenced) }
                let last3 = Array(down.keys.sorted { a, b in down[a]!.at < down[b]!.at || (down[a]!.at == down[b]!.at && a < b) }.suffix(3))
                if !over && !cancelled && t - down[last3[0]]!.at <= 0.15 {
                    three = last3.sorted()
                    for i in three { start[i] = down[i]!.now }
                    for (i, f) in down where !three.contains(i) { other[i] = (f.now, f.now) }
                    samples = [(t, mean(three, start))]
                }
            }
        case .move(let id, let p, let t):
            guard down[id] != nil else { break }
            down[id]!.now = p
            if three.isEmpty {
                if hypot(p.x - down[id]!.landed.x, p.y - down[id]!.landed.y) >= 24 { travelled = true }
            } else {
                if other[id] != nil { other[id]!.to = p }
                if !over && three.contains(id) {
                    var at: [Int: CGPoint] = [:]
                    for i in three { at[i] = down[i]?.now ?? start[i]! }
                    samples.append((t, mean(three, at)))
                }
            }
        case .up(let id, let p, let t):
            guard down[id] != nil else { break }
            down[id]!.now = p
            if other[id] != nil { other[id]!.to = p }
            if !three.isEmpty && !over && three.contains(id) {
                over = true
                var end: [Int: CGPoint] = [:]
                for i in three { end[i] = down[i]?.now ?? start[i]! }
                let c0 = mean(three, start), c1 = mean(three, end)
                let dx = c1.x - c0.x, dy = c1.y - c0.y, d = hypot(dx, dy)
                var ref = samples[0]
                for sm in samples where sm.0 <= t - 0.05 { ref = sm }
                let v = t - ref.0 > 0 ? hypot(c1.x - ref.1.x, c1.y - ref.1.y) / CGFloat(t - ref.0) : 0
                let took = other.filter { hypot($0.value.to.x - $0.value.from.x, $0.value.to.y - $0.value.from.y) >= 24 }
                var g: G.Gesture?
                if (d >= 40 || (d >= 20 && v >= 500)) && max(abs(dx), abs(dy)) >= 1.3 * min(abs(dx), abs(dy)) {
                    let (ux, uy): (CGFloat, CGFloat) = abs(dx) > abs(dy) ? (dx < 0 ? -1 : 1, 0) : (0, dy < 0 ? -1 : 1)
                    let along = dx * ux + dy * uy
                    let mine = three.allSatisfy { (end[$0]!.x - start[$0]!.x) * ux + (end[$0]!.y - start[$0]!.y) * uy >= 0.5 * along }
                    let theirs = took.values.allSatisfy { ($0.to.x - $0.from.x) * ux + ($0.to.y - $0.from.y) * uy > -0.5 * along }
                    if mine && theirs { g = abs(dx) > abs(dy) ? (dx < 0 ? .swipeLeft : .swipeRight) : (dy < 0 ? .swipeUp : .swipeDown) }
                }
                if g == nil {
                    var a = start, b = end
                    for (i, o) in took { a[i] = o.from; b[i] = o.to }
                    let ids = Array(a.keys)
                    let ca = mean(ids, a), cb = mean(ids, b)
                    let r0 = ids.sorted().map { hypot(a[$0]!.x - ca.x, a[$0]!.y - ca.y) }.reduce(0, +) / CGFloat(ids.count)
                    let r1 = ids.sorted().map { hypot(b[$0]!.x - cb.x, b[$0]!.y - cb.y) }.reduce(0, +) / CGFloat(ids.count)
                    if r0 > 0 { if r1 / r0 <= 0.75 { g = .pinch } else if r1 / r0 >= 1.25 { g = .spread } }
                }
                if let g { outputs.append(.gesture(g, fingers: min(3 + took.count, 4))) }
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
struct Shuffler: RandomNumberGenerator { mutating func next() -> UInt64 { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return seed } }
var shuffler = Shuffler()
/// One random stroke: one to five fingers, sometimes a thumb resting from the start, landing together or
/// apart (sometimes slowly), a first finger moving before the rest land, a translation, a pinch or a spread,
/// one digit (a thumb) going its own way, a brief still contact, a cancel, a swipe taken back, lifts in any
/// order.
func randomStroke(from t0: Double, ids: Int) -> [Event] {
    let n = 1 + Int(rnd() * 5)
    let c = CGPoint(x: 200 + rnd() * 400, y: 200 + rnd() * 300)
    var start = hand(n, at: c).map { CGPoint(x: $0.x + (rnd() - 0.5) * 20, y: $0.y + (rnd() - 0.5) * 20) }
    if rnd() < 0.1 { start = start.map { _ in c } }          // fingers on one spot
    var ev: [Event] = []
    var t = t0
    var resting: CGPoint?
    if rnd() < 0.2 {                                        // a thumb resting from the start
        resting = CGPoint(x: c.x - 150 + rnd() * 40, y: c.y + 120 + rnd() * 40)
        ev.append(.down(ids + 8, resting!, t, holding: false))
        if rnd() < 0.2 { t += 0.05; ev.append(.move(ids + 8, CGPoint(x: resting!.x + rnd() * 40, y: resting!.y), t)) }
        t += 0.1 + rnd() * 0.8
    }
    let stagger = rnd() < 0.2 ? 0 : (rnd() < 0.15 ? 0.08 + rnd() * 0.1 : rnd() * 0.12)
    let dx = (rnd() - 0.5) * 160, dy = (rnd() - 0.5) * 160
    let scale = rnd() < 0.5 ? 1 : 0.4 + rnd() * 1.4
    let steps = 1 + Int(rnd() * 20)
    let dt = 0.004 + rnd() * 0.03
    let preMove = rnd() < 0.3 ? rnd() * 35 : 0                // the first finger moving before the rest land
    let own = rnd() < 0.25 ? Int(rnd() * Double(n)) : -1      // a digit going its own way (a thumb-led pinch)
    let ownBy = CGPoint(x: (rnd() - 0.5) * 60, y: (rnd() - 0.5) * 300)
    var now = start
    for i in 0..<n {
        ev.append(.down(ids + i, start[i], t, holding: rnd() < 0.05))
        if i == 0 && preMove > 0 { t += 0.005; now[0] = CGPoint(x: start[0].x + preMove, y: start[0].y); ev.append(.move(ids, now[0], t)) }
        t += stagger
    }
    let cancelAt = rnd() < 0.1 ? Int(rnd() * Double(steps + 1)) : -1
    let back = rnd() < 0.1
    let brief = rnd() < 0.15 ? (1 + Int(rnd() * Double(steps)), 1 + Int(rnd() * 4)) : (-1, 0)  // a still contact: lands, lifts
    let briefAt = CGPoint(x: c.x + 170, y: c.y + 110)
    let cx = start.map(\.x).reduce(0, +) / CGFloat(n), cy = start.map(\.y).reduce(0, +) / CGFloat(n)
    for k in 1...steps {
        t += dt
        if k == cancelAt {
            // The system takes every touch: the fingers, a resting thumb, a brief contact still down.
            for i in 0..<n { ev.append(.cancel(ids + i)) }
            ev += [.cancel(ids + 8), .cancel(ids + 9)]
            return ev
        }
        if k == brief.0 { ev.append(.down(ids + 9, briefAt, t, holding: false)) }
        if brief.0 > 0, k == brief.0 + brief.1 { ev.append(.up(ids + 9, briefAt, t)) }
        var f = CGFloat(k) / CGFloat(steps)
        if back { f = f < 0.5 ? 2 * f : 2 - 2 * f }
        let s = 1 + (scale - 1) * f
        for i in 0..<n {
            var p = CGPoint(x: cx + (start[i].x - cx) * s + dx * f + (rnd() - 0.5) * 3, y: cy + (start[i].y - cy) * s + dy * f + (rnd() - 0.5) * 3)
            if i == own { p = CGPoint(x: start[i].x + ownBy.x * f, y: start[i].y + ownBy.y * f) }
            now[i] = p
            if rnd() < 0.9 { ev.append(.move(ids + i, p, t)) }
        }
    }
    if brief.0 > 0, brief.0 + brief.1 > steps { t += 0.005; ev.append(.up(ids + 9, briefAt, t)) }
    var order = Array(0..<n)
    if rnd() < 0.5 { order.shuffle(using: &shuffler) }
    var lifts: [(Int, CGPoint)] = order.map { (ids + $0, now[$0]) }
    if let resting { lifts.insert((ids + 8, resting), at: Int(rnd() * Double(lifts.count + 1))) }
    for (id, p) in lifts { t += rnd() * 0.02; ev.append(.up(id, p, t)) }
    return ev
}
var mismatches = 0
var tallies: [String: Int] = [:]
var real = G()
var clock = 0.0
for k in 0..<5_000 {
    let ev = randomStroke(from: clock, ids: k * 10)
    clock = (ev.map(\.time).max() ?? clock) + 0.2
    let want = model(ev)
    let got = run(ev, &real)
    for o in want.outputs { if case .gesture(let g, let f) = o { tallies["\(g.rawValue)\(f)", default: 0] += 1 } else { tallies["silenced", default: 0] += 1 } }
    if got.outputs != want.outputs || got.silentAfter != want.silent {
        mismatches += 1
        if mismatches <= 5 { print("  random \(k): got \(got.outputs) want \(want.outputs)") }
    }
}
check("5,000 random strokes (\(tallies.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", "))): outputs and silence as the model", mismatches == 0)
check("the random strokes reach every gesture, with three fingers and with four", G.Gesture.allCases.allSatisfy { g in tallies["\(g.rawValue)3"] != nil }
      && tallies.keys.contains { $0.hasSuffix("4") })

print("\(passes + fails) checks, \(fails) failed")
exit(fails == 0 ? 0 : 1)
