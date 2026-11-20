import Foundation
import CoreGraphics

// A device's two-finger pinch and turn, posted to the Mac as its trackpad's magnify and rotate gestures
// (PR #261, issue #260; the review of 2026-11-18 added the turn): PinchGestures
// (Sources/SillHost/PinchGestures.swift), what InputInjector posts for each InputEvent.magnify and
// .rotate, when its watchdog ends what a device left open, and what the host's end ends. The cases give
// the exact posts; then random sessions go through a model of InputInjector's glue (the pointer moved,
// each post, the watchdog rearmed after every event and firing after `idleTimeout` of quiet) against the
// invariants: a gesture's events in order (began, changed…, ended), each at the place it began, values
// bounded and numbers, the pointer moved only as a gesture begins with none open, nothing open after a
// second of quiet or the host's end.
//
// Compiled with Sources/StreamProtocol and Sources/SillHost/PinchGestures.swift as one module
// (-package-name sill), as build.sh does.

var failures = 0, checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}

typealias G = PinchGestures
typealias Post = PinchGestures.Post
let M = G.Kind.magnify, R = G.Kind.rotate
let a = CGPoint(x: 300, y: 200), b = CGPoint(x: 640, y: 410), c = CGPoint(x: 900.5, y: 77.25)

func str(_ p: Post) -> String { "\(p.kind.rawValue) \(p.phase.rawValue) \(p.value) at \(Int(p.at.x)),\(Int(p.at.y))" }
func str(_ s: G.Step) -> String {
    (s.ending.map(str) + (s.movePointerTo.map { ["move to \(Int($0.x)),\(Int($0.y))"] } ?? []) + s.posts.map(str)).joined(separator: "; ")
}

// MARK: - One pinch

do {
    var g = G()
    check(!g.isOpen && g.at == nil && g.open.isEmpty, "a new host has nothing open")
    let began = g.apply(M, .began, value: 0, at: a, pointer: b)
    check(began == G.Step(movePointerTo: a, posts: [Post(M, .began, 0, at: a)]), "a pinch's began moves the pointer under it, then begins there: \(str(began))")
    check(g.isOpen && g.open == [M] && g.at == a, "the magnify is open, at a")
    let changed = g.apply(M, .changed, value: 0.05, at: a, pointer: a)
    check(changed == G.Step(movePointerTo: nil, posts: [Post(M, .changed, 0.05, at: a)]), "a change goes as it came, no pointer move: \(str(changed))")
    let shrink = g.apply(M, .changed, value: -0.2, at: a, pointer: a)
    check(shrink.posts == [Post(M, .changed, -0.2, at: a)], "a pinch in goes as it came: \(str(shrink))")
    let ended = g.apply(M, .ended, value: 0, at: a, pointer: a)
    check(ended == G.Step(movePointerTo: nil, posts: [Post(M, .ended, 0, at: a)]), "the end: \(str(ended))")
    check(!g.isOpen && g.at == nil, "nothing open after the end")
    check(g.apply(M, .changed, value: 0.1, at: a, pointer: a) == .nothing, "a change after the end posts nothing")
    check(g.apply(M, .ended, value: 0, at: a, pointer: a) == .nothing, "a second end posts nothing")
}

// MARK: - The pointer

do {
    var g = G()
    let near = CGPoint(x: a.x + 0.6, y: a.y - 0.6)   // 0.85 pt away
    check(g.apply(M, .began, value: 0, at: a, pointer: near).movePointerTo == nil, "the pointer within a point of the pinch stays")
    g = G()
    let justOut = CGPoint(x: a.x + 1.01, y: a.y)
    check(g.apply(R, .began, value: 0, at: a, pointer: justOut).movePointerTo == a, "a point and a bit away: the pointer moves, for a turn as for a pinch")
    g = G()
    check(g.apply(M, .began, value: 0, at: a, pointer: a).movePointerTo == nil, "the pointer already there: no move")
    check(G.pointerSlop == 1, "the slop is a point")
}

// MARK: - Every event at the place it began

do {
    var g = G()
    _ = g.apply(M, .began, value: 0, at: a, pointer: a)
    check(g.apply(M, .changed, value: 0.1, at: b, pointer: a).posts == [Post(M, .changed, 0.1, at: a)], "a change sent from elsewhere goes where the pinch began")
    check(g.apply(M, .ended, value: 0, at: c, pointer: a).posts == [Post(M, .ended, 0, at: a)], "so does its end")
    _ = g.apply(R, .began, value: 0, at: c, pointer: a)
    check(g.at == c, "the next gesture begins where it says")
}

// MARK: - A began over an open one

do {
    var g = G()
    _ = g.apply(M, .began, value: 0, at: a, pointer: a)
    _ = g.apply(M, .changed, value: 0.3, at: a, pointer: a)
    let again = g.apply(M, .began, value: 0, at: b, pointer: a)
    check(again == G.Step(ending: [Post(M, .ended, 0, at: a)], movePointerTo: b, posts: [Post(M, .began, 0, at: b)]),
          "a began while a pinch is open ends that one where it was, then the pointer moves, then the new one begins where it says: \(str(again))")
    check(g.open == [M] && g.at == b, "one pinch open, at b")
}

// MARK: - The pinch and the turn together

do {
    var g = G()
    let first = g.apply(M, .began, value: 0, at: a, pointer: b)
    check(first.movePointerTo == a, "the first of the two moves the pointer")
    let second = g.apply(R, .began, value: 2, at: b, pointer: a)
    check(second == G.Step(movePointerTo: nil, posts: [Post(R, .began, 2, at: a)]),
          "the turn beginning while the pinch is open joins it where it is, no pointer move: \(str(second))")
    check(g.open == [M, R], "both open")
    check(g.apply(R, .changed, value: -4, at: c, pointer: a).posts == [Post(R, .changed, -4, at: a)], "the turn's change where the gesture is")
    check(g.apply(M, .ended, value: 0, at: a, pointer: a).posts == [Post(M, .ended, 0, at: a)], "the pinch ends")
    check(g.open == [R] && g.at == a, "the turn still open, still at a")
    check(g.apply(R, .changed, value: 1.5, at: b, pointer: a).posts == [Post(R, .changed, 1.5, at: a)], "the turn goes on where it was")
    check(g.apply(M, .began, value: 0, at: c, pointer: a) == G.Step(movePointerTo: nil, posts: [Post(M, .began, 0, at: a)]),
          "a pinch beginning again while the turn is open joins it where it is")
    _ = g.apply(R, .ended, value: 0, at: a, pointer: a)
    _ = g.apply(M, .ended, value: 0, at: a, pointer: a)
    check(!g.isOpen && g.at == nil, "both ended: nothing open, no place")
    // A turn's began over an open turn while the pinch is open: the turn ends and begins again, at the
    // gesture's place, and the pinch stays.
    _ = g.apply(M, .began, value: 0, at: a, pointer: a)
    _ = g.apply(R, .began, value: 0, at: a, pointer: a)
    let turnAgain = g.apply(R, .began, value: 0, at: b, pointer: a)
    check(turnAgain == G.Step(ending: [Post(R, .ended, 0, at: a)], movePointerTo: nil, posts: [Post(R, .began, 0, at: a)]),
          "a turn's began over an open turn beside an open pinch ends and begins it again where the gesture is: \(str(turnAgain))")
    check(g.open == [M, R] && g.at == a, "both still open at a")
}

// MARK: - The bounds, and what is not a number

do {
    var g = G()
    _ = g.apply(M, .began, value: 0, at: a, pointer: a)
    check(g.apply(M, .changed, value: 7.5, at: a, pointer: a).posts == [Post(M, .changed, 1, at: a)], "a magnification past a doubling is one")
    check(g.apply(M, .changed, value: -3, at: a, pointer: a).posts == [Post(M, .changed, -1, at: a)], "and past nothing, minus one")
    check(g.apply(M, .changed, value: 1, at: a, pointer: a).posts == [Post(M, .changed, 1, at: a)], "one itself is kept")
    _ = g.apply(R, .began, value: 0, at: a, pointer: a)
    check(g.apply(R, .changed, value: 400, at: a, pointer: a).posts == [Post(R, .changed, 90, at: a)], "a turn past a quarter is a quarter")
    check(g.apply(R, .changed, value: -91, at: a, pointer: a).posts == [Post(R, .changed, -90, at: a)], "either way")
    check(g.apply(R, .changed, value: 45, at: a, pointer: a).posts == [Post(R, .changed, 45, at: a)], "45° kept: the bound is not the magnify's")
    let before = g
    for v in [Double.nan, .infinity, -.infinity] {
        check(g.apply(M, .changed, value: v, at: a, pointer: a) == .nothing, "a magnification of \(v) posts nothing")
        check(g.apply(R, .ended, value: v, at: a, pointer: a) == .nothing, "a turn's end of \(v) posts nothing")
        check(g.apply(M, .began, value: v, at: b, pointer: a) == .nothing, "a began of \(v) posts nothing")
    }
    check(g.apply(M, .changed, value: 0.1, at: CGPoint(x: Double.nan, y: 3), pointer: a) == .nothing, "a place that is not a number: nothing")
    check(g == before, "what is not a number changes nothing open")
    check(G.maxMagnification == 1 && G.maxDegrees == 90 && G.idleTimeout == 1, "the bounds and the watchdog's second")
}

// MARK: - The watchdog and the host's end

do {
    var g = G()
    check(g.idle().isEmpty && g.releaseAll().isEmpty, "nothing open: the watchdog and the end post nothing")
    _ = g.apply(M, .began, value: 0, at: a, pointer: a)
    _ = g.apply(M, .changed, value: 0.2, at: b, pointer: a)
    check(g.idle() == [Post(M, .ended, 0, at: a)], "the watchdog ends an open pinch where it began, with 0")
    check(!g.isOpen && g.at == nil, "then nothing is open")
    check(g.apply(M, .changed, value: 0.1, at: a, pointer: a) == .nothing, "a change after the watchdog closed it posts nothing")
    _ = g.apply(R, .began, value: 0, at: b, pointer: a)
    _ = g.apply(M, .began, value: 0, at: c, pointer: b)
    check(g.idle() == [Post(M, .ended, 0, at: b), Post(R, .ended, 0, at: b)], "both open: both end, the pinch first, where the gesture is")
    _ = g.apply(R, .began, value: 0, at: c, pointer: b)
    check(g.releaseAll() == [Post(R, .ended, 0, at: c)], "the host's end ends a turn left open")
    check(!g.isOpen, "nothing after the end")
}

// MARK: - Random sessions through a model of InputInjector's glue

/// InputInjector's part, with a clock: each event of a device moves the pointer (`movePointerTo`), posts its
/// step's events and rearms the watchdog, which fires `idleTimeout` after the last event while anything is
/// open (`rearmPinchWatchdog`).
struct Glue {
    var g = G()
    var now = 0.0
    var pointer = CGPoint(x: 10, y: 10)
    var watchdogAt: Double? = nil
    var posted: [Post] = []
    var moves: [(at: CGPoint, kind: G.Kind, openBefore: Set<G.Kind>)] = []
    var badEnding = 0
    mutating func tick(to t: Double) {
        if let w = watchdogAt, w <= t {
            now = w
            posted += g.idle()
            watchdogAt = nil
        }
        now = t
    }
    mutating func event(_ kind: G.Kind, _ phase: PinchPhase, _ value: Double, _ at: CGPoint, time t: Double) {
        tick(to: t)
        let before = g.open
        let step = g.apply(kind, phase, value: value, at: at, pointer: pointer)
        if !step.ending.allSatisfy({ $0.phase == .ended && $0.kind == kind }) || step.ending.count > 1 { badEnding += 1 }
        posted += step.ending
        if let to = step.movePointerTo { pointer = to; moves.append((to, kind, before)) }
        posted += step.posts
        watchdogAt = g.isOpen ? now + G.idleTimeout : nil
    }
}

struct Seeded: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 { state &+= 0x9E3779B97F4A7C15; var z = state; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
}
var seeded = Seeded(state: 0x261)
var sessions = 0, postsSeen = 0, watchdogEnds = 0
let places = [a, b, c, CGPoint(x: 0, y: 0), CGPoint(x: 1511.5, y: 948.5)]
for _ in 0..<4_000 {
    sessions += 1
    var glue = Glue()
    var t = 0.0
    let count = Int.random(in: 1...40, using: &seeded)
    for _ in 0..<count {
        t += [0.004, 0.016, 0.05, 0.3, 0.9, 1.0, 1.2, 2.5].randomElement(using: &seeded)!
        let kind: G.Kind = Bool.random(using: &seeded) ? .magnify : .rotate
        let phase: PinchPhase = [.began, .changed, .changed, .changed, .ended].randomElement(using: &seeded)!
        let value: Double = [0, 0.01, -0.03, 0.5, 2, -7, 15, -200, .nan, .infinity].randomElement(using: &seeded)!
        glue.event(kind, phase, value, places.randomElement(using: &seeded)!, time: t)
    }
    let endedBefore = glue.posted.count
    // A second of quiet: whatever is open ends.
    glue.tick(to: t + G.idleTimeout + 0.001)
    if glue.posted.count > endedBefore { watchdogEnds += 1 }
    check(!glue.g.isOpen && glue.g.at == nil, "session \(sessions): nothing open after a second of quiet")
    // The posts, gesture by gesture: began, changed…, ended; each at its began's place; values bounded numbers.
    var open: [G.Kind: CGPoint] = [:]
    var ok = true, why = ""
    for p in glue.posted {
        postsSeen += 1
        if !p.value.isFinite { ok = false; why = "a value that is not a number: \(str(p))"; break }
        let bound = p.kind == .magnify ? G.maxMagnification : G.maxDegrees
        if abs(p.value) > bound { ok = false; why = "past its bound: \(str(p))"; break }
        switch p.phase {
        case .began:
            if open[p.kind] != nil { ok = false; why = "a began over an open \(p.kind)"; break }
            if let other = open.values.first, other != p.at { ok = false; why = "the second gesture somewhere else: \(str(p))"; break }
            open[p.kind] = p.at
        case .changed:
            guard let at = open[p.kind] else { ok = false; why = "a change with none open: \(str(p))"; break }
            if at != p.at { ok = false; why = "a change away from its began: \(str(p))"; break }
        case .ended:
            guard let at = open[p.kind] else { ok = false; why = "an end with none open: \(str(p))"; break }
            if at != p.at { ok = false; why = "an end away from its began: \(str(p))"; break }
            open[p.kind] = nil
        }
        if !ok { break }
    }
    check(ok, "session \(sessions): \(why)")
    check(open.isEmpty, "session \(sessions): every began has its end")
    check(glue.badEnding == 0, "session \(sessions): what a step ends first is one gesture of its own kind, ended")
    // The pointer moved only as a gesture began with none open, to that began's place.
    check(glue.moves.allSatisfy { $0.openBefore.isEmpty || $0.openBefore == [$0.kind] },
          "session \(sessions): the pointer moves only for a began with nothing else open (none, or only its own, which it ends first)")
    for m in glue.moves {
        check(glue.posted.contains { $0.phase == .began && $0.at == m.at }, "session \(sessions): the pointer moved to where a gesture began")
    }
    if sessions % 1000 == 0 {
        // The host's end after a session left open: nothing stays open, every post an end.
        var g = glue.g
        _ = g.apply(.magnify, .began, value: 0, at: a, pointer: a)
        let ends = g.releaseAll()
        check(!g.isOpen && ends.allSatisfy { $0.phase == .ended && $0.value == 0 }, "session \(sessions): the host's end closes all")
    }
}
check(watchdogEnds > 100, "the random sessions left gestures open for the watchdog (\(watchdogEnds) of \(sessions))")
check(G.Step.nothing.ending.isEmpty && G.Step.nothing.posts.isEmpty && G.Step.nothing.movePointerTo == nil, "nothing is nothing")
print("random: \(sessions) sessions, \(postsSeen) posts, \(watchdogEnds) ended by the watchdog")

print(failures == 0 ? "ok: \(checks) checks" : "\(failures) FAILED of \(checks)")
exit(failures == 0 ? 0 : 1)
