import CoreGraphics
import Foundation

// H3 of docs/pointer-visibility-plan.md, the host's part: PointerControl (who moves the Mac's
// pointer, and the fraction kind 26 carries) and kind 26 itself (MacPointer's JSON, the kind table).
// Compiled with Sources/StreamProtocol and Sources/SillHost/PointerControl.swift (its `import
// StreamProtocol` dropped), as build.sh does.
var failures = 0, checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
final class Device {}
let deviceA = Device(), deviceB = Device()
let A = ObjectIdentifier(deviceA), B = ObjectIdentifier(deviceB)
typealias C = PointerControl
func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

// MARK: Who has the pointer

// At launch nobody has driven: the Mac has it, and the first read only sets the last position.
do {
    var c = C()
    check(c.controller == .mac, "at launch the Mac has the pointer")
    check(!c.read(pt(100, 100), now: 10.0), "the first read hands nothing over")
    check(!c.read(pt(100, 100), now: 10.03) && c.controller == .mac, "a still pointer changes nothing")
    check(!c.read(pt(200, 100), now: 10.06) && c.controller == .mac, "a move while the Mac has it: still the Mac's, and no hand-over")
}

// A pointer input hands its device the pointer and opens the settle, which absorbs Sill's own move
// (absolute, 300 pt away) and every read until it ends; then a move counts from where Sill left it.
do {
    var c = C()
    c.read(pt(100, 100), now: 0.97)
    c.inputArrived(from: A, movesPointer: true, now: 1.0)
    check(c.controller == .client(A), "a pointer input hands its device the pointer")
    check(!c.read(pt(400, 100), now: 1.03), "Sill's own move within the settle is Sill's")
    check(!c.read(pt(420, 110), now: 1.20) && c.controller == .client(A), "every read within the settle is Sill's")
    check(!c.read(pt(420, 110), now: 1.25), "the settle over, the pointer where Sill left it: nothing")
    check(!c.read(pt(420.3, 110), now: 1.28), "0.3 pt from where Sill left it: nothing")
    check(!c.read(pt(420.49, 110), now: 1.31) && c.controller == .client(A), "0.49 pt from it: nothing")
    check(c.read(pt(420.5, 110), now: 1.34), "0.5 pt from where Sill left it: the Mac's move, a hand-over")
    check(c.controller == .mac, "…and the Mac has the pointer")
    check(!c.read(pt(430, 110), now: 1.37) && c.controller == .mac, "a hand-over happens once")
}

// The settle's end: a pointer input at 2.0 opens it until 2.25, exclusive.
do {
    var c = C()
    c.read(pt(0, 0), now: 1.99)
    c.inputArrived(from: A, movesPointer: true, now: 2.0)
    c.read(pt(0, 0), now: 2.01)
    check(!c.read(pt(50, 0), now: 2.2499) && c.controller == .client(A), "just inside the settle: Sill's")
    check(c.read(pt(60, 0), now: 2.25) && c.controller == .mac, "at 2.25 the settle is over: the Mac's")
}

// A diagonal of 0.5 pt counts; 0.49 does not.
do {
    var c = C()
    c.read(pt(10, 10), now: 0)
    c.inputArrived(from: A, movesPointer: false, now: 0.01)
    check(!c.read(pt(10.3, 10.39), now: 0.03), "a diagonal of 0.49 pt: nothing")
    check(c.read(pt(10.3, 10.4), now: 0.06), "a diagonal of 0.5 pt: the Mac's")
}

// Jitter of ±0.3 pt around one point never hands over: measured from the last position that counted.
do {
    var c = C()
    c.read(pt(500, 300), now: 0)
    c.inputArrived(from: A, movesPointer: false, now: 0.01)
    var any = false
    for i in 1...200 {
        let d: CGFloat = i % 2 == 0 ? 0.3 : -0.3
        any = c.read(pt(500 + d, 300 - d), now: 0.01 + Double(i) * 0.03) || any
    }
    check(!any && c.controller == .client(A), "±0.3 pt of jitter for 6 s never hands over")
}

// A slow drift adds up: 0.2 pt a read hands over at the third (0.6 pt from where it started).
do {
    var c = C()
    c.read(pt(100, 100), now: 0)
    c.inputArrived(from: A, movesPointer: false, now: 0.01)
    check(!c.read(pt(100.2, 100), now: 0.03), "drift, first read: 0.2 pt")
    check(!c.read(pt(100.4, 100), now: 0.06), "drift, second read: 0.4 pt")
    check(c.read(pt(100.6, 100), now: 0.09) && c.controller == .mac, "drift, third read: 0.6 pt, the Mac's")
}
// The same drift inside the settle, and 0.2 pt a read after it: still adds up from where Sill left it.
do {
    var c = C()
    c.read(pt(0, 0), now: 0.99)
    c.inputArrived(from: A, movesPointer: true, now: 1.0)
    c.read(pt(50, 50), now: 1.1)
    c.read(pt(50, 50), now: 1.2)
    var reads: [Bool] = []
    for i in 1...4 { reads.append(c.read(pt(50 + 0.2 * CGFloat(i), 50), now: 1.25 + Double(i) * 0.03)) }
    check(reads == [false, false, true, false], "after the settle, 0.2 pt a read hands over at the third: \(reads)")
}

// Keys and typed text hand the device the pointer without opening the settle: the Mac's next real
// move shows its arrow at once.
do {
    var c = C()
    c.read(pt(200, 200), now: 0)
    c.inputArrived(from: A, movesPointer: false, now: 0.02)   // a key
    check(c.controller == .client(A), "a key hands its device the pointer")
    check(c.read(pt(201, 200), now: 0.03), "the Mac's move 10 ms after a key is the Mac's")
    c.inputArrived(from: A, movesPointer: PointerControl.movesPointer(.text("a")), now: 0.05)
    check(c.controller == .client(A), "typed text hands its device the pointer")
    check(c.read(pt(202, 200), now: 0.06), "the Mac's move right after typed text is the Mac's")
}
// A key after a pointer input neither ends nor extends its settle.
do {
    var c = C()
    c.read(pt(0, 0), now: 0.99)
    c.inputArrived(from: A, movesPointer: true, now: 1.0)
    c.inputArrived(from: A, movesPointer: false, now: 1.1)
    check(!c.read(pt(80, 0), now: 1.2), "a key does not end the pointer input's settle")
    c.read(pt(80, 0), now: 1.24)
    check(c.read(pt(90, 0), now: 1.26), "nor extend it")
}

// Sill's own motion noted before a post or a warp opens the settle and never hands the pointer over:
// a held click posted long after it was read, or VirtualStage's warp home.
do {
    var c = C()
    c.read(pt(300, 300), now: 5.0)
    c.inputArrived(from: A, movesPointer: false, now: 5.01)
    c.sillMoved(now: 6.0)
    check(c.controller == .client(A), "sillMoved leaves a device's control")
    c.read(pt(300, 300), now: 6.0)
    check(!c.read(pt(700, 400), now: 6.1) && c.controller == .client(A), "the late post's move is Sill's")
    check(!c.read(pt(700, 400), now: 6.3), "…and where it landed counts as Sill's")
    check(c.read(pt(701, 400), now: 6.33) && c.controller == .mac, "then a real move is the Mac's")
    c.sillMoved(now: 7.0)
    check(c.controller == .mac, "sillMoved leaves the Mac's control too")
}
// The settle runs to the latest end asked for, whatever order the notes come in.
do {
    var c = C()
    c.read(pt(0, 0), now: 2.99)
    c.inputArrived(from: A, movesPointer: true, now: 3.0)   // to 3.25
    c.sillMoved(now: 3.1)                                   // to 3.35
    c.sillMoved(now: 3.0)                                   // a note from before: to 3.25, which ends nothing
    c.read(pt(0, 0), now: 3.2)
    check(!c.read(pt(40, 0), now: 3.3), "a later note extends the settle")
    check(!c.read(pt(45, 0), now: 3.34), "an earlier note does not cut it short")
    check(c.read(pt(50, 0), now: 3.36), "past the latest end a move counts")
}

// One controller: the device whose input the host read last; a leaving driver hands back.
do {
    var c = C()
    c.read(pt(0, 0), now: 0)
    c.inputArrived(from: A, movesPointer: false, now: 0.01)
    c.inputArrived(from: B, movesPointer: false, now: 0.02)
    check(c.controller == .client(B), "the device whose input came last has the pointer")
    c.clientLeft(A)
    check(c.controller == .client(B), "another device leaving changes nothing")
    c.clientLeft(B)
    check(c.controller == .mac, "the driving device leaving hands the pointer back to the Mac")
    c.inputArrived(from: A, movesPointer: false, now: 0.05)
    check(c.read(pt(5, 0), now: 0.06) && c.controller == .mac, "then the Mac's move takes it from A")
    c.inputArrived(from: A, movesPointer: false, now: 0.07)
    c.inputArrived(from: B, movesPointer: false, now: 0.08)
    c.inputArrived(from: A, movesPointer: false, now: 0.09)
    check(c.controller == .client(A), "back and forth: the last one")
    c.clientLeft(B)
    check(c.controller == .client(A), "B leaving while A drives: A keeps it")
    c.clientLeft(A)
    check(c.controller == .mac, "A leaving: the Mac")
    c.clientLeft(A)
    check(c.controller == .mac, "a second leave changes nothing")
}

// A read after a gap starts afresh: the pointer was not watched, and Sill may have moved it then.
do {
    var c = C()
    c.read(pt(100, 100), now: 0)
    c.inputArrived(from: A, movesPointer: false, now: 0.01)
    c.read(pt(100, 100), now: 0.03)
    c.sillMoved(now: 0.1)                                  // the warp home, while no sample runs
    check(!c.read(pt(900, 500), now: 1.0) && c.controller == .client(A), "a read 0.97 s after the one before: afresh, not the Mac's")
    check(c.read(pt(901, 500), now: 1.03) && c.controller == .mac, "the next read's move counts from there")
}
// The gap's edge: exactly `settle` after the read before is still watched.
do {
    var c = C()
    c.read(pt(0, 0), now: 5.0)
    c.inputArrived(from: A, movesPointer: false, now: 5.01)
    check(c.read(pt(10, 0), now: 5.25), "0.25 s after the read before: watched, the Mac's move")
    var d = C()
    d.read(pt(0, 0), now: 5.0)
    d.inputArrived(from: A, movesPointer: false, now: 5.01)
    check(!d.read(pt(10, 0), now: 5.2501) && d.controller == .client(A), "0.2501 s after it: afresh")
}

// MARK: Moving (the frame-rate sampling, Q4)

do {
    var c = C()
    check(!c.isMoving(now: 0), "nothing read: not moving")
    c.read(pt(0, 0), now: 1.0)
    check(!c.isMoving(now: 1.0), "one read: not moving")
    c.read(pt(0, 0), now: 1.03)
    check(!c.isMoving(now: 1.03), "the same point again: not moving")
    c.read(pt(0.1, 0), now: 1.06)
    check(c.isMoving(now: 1.06), "a read that differs from the one before: moving")
    check(c.isMoving(now: 1.159), "…for 0.1 s")
    check(!c.isMoving(now: 1.161), "…and not after")
    c.read(pt(0.1, 0), now: 1.09)
    check(!c.isMoving(now: 1.161), "a still read does not extend it")
    c.inputArrived(from: A, movesPointer: true, now: 1.1)
    c.read(pt(300, 0), now: 1.12)
    check(c.isMoving(now: 1.2), "Sill's own motion is motion too (another device may be watching)")
    c.read(pt(310, 0), now: 2.0)
    check(!c.isMoving(now: 2.0), "a change across a gap is not motion")
}

// MARK: Which inputs open the settle

let pointerEvents: [InputEvent] = [.pointer(.move, x: 0.25, y: 0.5), .pointer(.leftDown, x: 0, y: 0), .pointer(.leftUp, x: 1, y: 1),
                                   .pointer(.rightDown, x: 0.5, y: 0.5), .pointer(.rightUp, x: 0.5, y: 0.5),
                                   .scroll(x: 0.5, y: 0.5, dx: 0, dy: 0.1), .scrollGesture(.began, x: 0.5, y: 0.5),
                                   .scrollGesture(.momentumEnded, x: 0.1, y: 0.9)]
for e in pointerEvents {
    check(C.movesPointer(e) && C.movesPointer(payload: Wire.encode(e)), "\(e) moves the pointer")
}
for e in [InputEvent.text("a"), .text("\n"), .key(hidUsage: 4, down: true, modifiers: 0), .key(hidUsage: 44, down: false, modifiers: 1 << 20)] {
    check(!C.movesPointer(e) && !C.movesPointer(payload: Wire.encode(e)), "\(e) does not")
}
check(!C.movesPointer(payload: Data()) && !C.movesPointer(payload: Data("{}".utf8)) && !C.movesPointer(payload: Data("{\"pointer\":{}}".utf8)),
      "a payload that does not decode moves nothing")
check(C.movesPointer(payload: Data(#"{"pointer":{"_0":"move","x":0.25,"y":0.5}}"#.utf8)), "the wire's own move (sillclient.py's --move)")
check(!C.movesPointer(payload: Data(#"{"key":{"down":true,"hidUsage":4,"modifiers":0}}"#.utf8)), "the wire's own key (sillclient.py's --key)")

// MARK: Random runs against the rules' invariants

// 5,000 runs of random inputs, notes, leaves and reads (steps of 1 to 400 ms, moves of 0 to 3 pt or
// jumps): a read inside a settle never hands over or changes the controller; `read` is true exactly
// when a device had the pointer and the Mac has it after; the controller changes only as the rules say.
var rng = SystemRandomNumberGenerator()
var invariantFailures = 0
for _ in 0..<5_000 {
    var c = C()
    var t = 0.0, p = pt(500, 500)
    var settleEnd = -Double.infinity
    for _ in 0..<60 {
        t += Double.random(in: 0.001...0.4, using: &rng)
        let before = c.controller
        switch Int.random(in: 0..<10, using: &rng) {
        case 0, 1:
            let who = Bool.random(using: &rng) ? A : B
            let moves = Bool.random(using: &rng)
            c.inputArrived(from: who, movesPointer: moves, now: t)
            if moves { settleEnd = max(settleEnd, t + C.settle) }
            if c.controller != .client(who) { invariantFailures += 1; print("input did not hand over") }
        case 2:
            c.sillMoved(now: t)
            settleEnd = max(settleEnd, t + C.settle)
            if c.controller != before { invariantFailures += 1; print("sillMoved changed the controller") }
        case 3:
            let who = Bool.random(using: &rng) ? A : B
            c.clientLeft(who)
            let want: C.Controller = before == .client(who) ? .mac : before
            if c.controller != want { invariantFailures += 1; print("clientLeft: \(c.controller) for \(before)") }
        default:
            if Int.random(in: 0..<8, using: &rng) == 0 {
                p = pt(CGFloat.random(in: 0...3000, using: &rng), CGFloat.random(in: 0...2000, using: &rng))
            } else {
                p = pt(p.x + CGFloat.random(in: -1.5...1.5, using: &rng), p.y + CGFloat.random(in: -1.5...1.5, using: &rng))
            }
            let handed = c.read(p, now: t)
            if t < settleEnd, handed || c.controller != before { invariantFailures += 1; print("a read inside the settle handed over") }
            if handed != (before != .mac && c.controller == .mac) { invariantFailures += 1; print("read's result") }
            if !handed && c.controller != before { invariantFailures += 1; print("the controller changed without a hand-over") }
        }
    }
}
check(invariantFailures == 0, "5,000 random runs: \(invariantFailures) broke an invariant")

// MARK: The fraction kind 26 carries

let pattern = CGRect(x: 0, y: 0, width: 1512, height: 949)   // the synthetic test pattern (§4.7)
func frac(_ p: CGPoint, _ r: CGRect = pattern) -> (Double, Double, Bool) {
    let f = C.fraction(of: p, in: r); return (f.x, f.y, f.inside)
}
func same(_ a: (Double, Double, Bool), _ b: (Double, Double, Bool)) -> Bool { a.0 == b.0 && a.1 == b.1 && a.2 == b.2 }
check(same(frac(pt(756, 474.5)), (0.5, 0.5, true)), "H4's first step: the middle")
check(same(frac(pt(1134, 237.25)), (0.75, 0.25, true)), "H4's second step")
check(same(frac(pt(-40, 474.5)), (-0.0265, 0.5, false)), "H4's third step: off the pattern")
check(same(frac(pt(378, 711.75)), (0.25, 0.75, true)), "H4's fourth step")
check(same(frac(pt(0, 0)), (0, 0, true)), "the top-left corner is inside")
check(same(frac(pt(1511.99, 948.99)), (1, 1, true)), "the last column and row are inside, rounded to 1")
check(same(frac(pt(1511.99, 0)), (1, 0, true)) && same(frac(pt(0, 948.99)), (0, 1, true)), "the other corners' last points")
check(same(frac(pt(1512, 949)), (1, 1, false)), "the bottom-right corner itself is outside: the far edges are the next display's")
check(same(frac(pt(1512, 474.5)), (1, 0.5, false)) && same(frac(pt(756, 949)), (0.5, 1, false)),
      "the column at maxX and the row at maxY are outside (the review, 2026-09-27)")
check(!frac(pt(-0.01, 400)).2 && !frac(pt(400, -0.01)).2, "just left of or above the rectangle: outside")
check(!frac(pt(1512.01, 400)).2 && !frac(pt(400, 949.01)).2, "just right of or below it: outside")
check(same(frac(pt(1512.02, 400)), (1.0, 0.4215, false)), "outside, x rounds to 1.0 and it is still outside (judged before rounding)")
check(same(frac(pt(-0.03, 400)), (0, 0.4215, false)) && frac(pt(-0.03, 400)).0.sign == .minus,
      "outside on the left rounds to -0.0, and is still outside")
let window = CGRect(x: 100, y: 200, width: 400, height: 300)
check(same(frac(pt(300, 350), window), (0.5, 0.5, true)), "an offset rectangle")
check(same(frac(pt(100, 200), window), (0, 0, true)) && same(frac(pt(499.99, 499.99), window), (1, 1, true)), "its corners")
check(!frac(pt(500, 350), window).2 && !frac(pt(300, 500), window).2, "its right and bottom edges are past it")
check(same(frac(pt(50, 350), window), (-0.125, 0.5, false)), "left of it")
check(same(frac(pt(504, 1)), (0.3333, 0.0011, true)) && same(frac(pt(1008, 1)), (0.6667, 0.0011, true)), "rounded to 4 places")
check(same(frac(pt(0.2, 0)), (0.0001, 0, true)) && same(frac(pt(0.07, 0)), (0, 0, true)), "rounding at the fourth place")
check(same(frac(pt(756, 474.5), CGRect(x: 1512, y: 949, width: -1512, height: -949)), (0.5, 0.5, true)), "a rectangle given with negative sizes")
check(!frac(pt(0, 0), CGRect(x: 0, y: 0, width: 0, height: 949)).2 && !frac(pt(0, 0), CGRect(x: 0, y: 0, width: 1512, height: 0)).2,
      "an empty rectangle is never inside")
check(!frac(pt(0, 0), .null).2 && !frac(pt(0, 0), .infinite).2 && !frac(pt(0, 0), .zero).2, "null, infinite and zero rectangles")
check(!frac(pt(.nan, 10)).2 && !frac(pt(10, .infinity)).2, "a non-finite point")
// Halfway down, so only the guard keeps it out: unguarded, x is 10 / ∞ = 0 and y 0.5, inside.
check(!frac(pt(10, 5), CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 10)).2, "a rectangle of infinite width")
check(!frac(pt(10, 5), CGRect(x: 0, y: 0, width: 10, height: CGFloat.infinity)).2, "a rectangle of infinite height")
let second = CGRect(x: 1512, y: 0, width: 1920, height: 1080)
check(!frac(pt(1600, 500)).2 && frac(pt(1600, 500), second).2, "a second display to the right: outside the first, inside itself")
check(!frac(pt(1512, 474.5)).2 && same(frac(pt(1512, 474.5), second), (0, 0.4394, true)),
      "the second display's first column: its own, not the first's")

// MARK: Kind 26 (StreamProtocol)

let sorted = JSONEncoder(); sorted.outputFormatting = .sortedKeys
func json<T: Encodable>(_ x: T) -> String { String(decoding: try! sorted.encode(x), as: UTF8.self) }
let over = MacPointer(x: 0.4213, y: 0.1873, inside: true, seen: 12)
check(json(over) == #"{"inside":true,"seen":12,"x":0.4213,"y":0.1873}"#, "over the stream: \(json(over))")
let off = MacPointer(inside: false, seen: 12)
check(json(off) == #"{"inside":false,"seen":12}"#, "off it, x and y left out: \(json(off))")
check(json(MacPointer()) == "{}", "an empty MacPointer is {}")
check(Wire.decode(MacPointer.self, from: Wire.encode(over)) == over, "round trip")
check(Wire.decode(MacPointer.self, from: Wire.encode(off)) == off, "round trip, off")
check(Wire.decode(MacPointer.self, from: Data("{}".utf8)) == MacPointer(), "{} decodes, every field nil")
check(Wire.decode(MacPointer.self, from: Data(#"{"inside":true,"x":0.5,"y":0.25,"seen":3,"who":"mac","extra":[1,{"a":2}]}"#.utf8))
      == MacPointer(x: 0.5, y: 0.25, inside: true, seen: 3), "unknown keys are skipped")
check(Wire.decode(MacPointer.self, from: Data(#"{"x":"0.5"}"#.utf8)) == nil, "a string for x does not decode")
check(Wire.decode(MacPointer.self, from: Data(#"{"seen":1.5}"#.utf8)) == nil, "a fraction for seen does not decode")
check(Wire.decode(MacPointer.self, from: Data("[]".utf8)) == nil, "not an object")
check(Wire.encode(MacPointer(x: 0.4213, y: 0.1873, inside: true, seen: 1234)).count == 49, "the plan's example is 49 bytes")
check(Wire.encode(MacPointer(x: 0.4213, y: 0.1873, inside: true, seen: 1234)).count <= 64, "…and fits 64")
check(MacPointer.rounded(0.42134) == 0.4213 && MacPointer.rounded(0.42136) == 0.4214, "rounded to 4 places")
check(MacPointer.rounded(1.0 / 3.0) == 0.3333 && MacPointer.rounded(0.99996) == 1.0 && MacPointer.rounded(0) == 0, "rounded: thirds and ends")
check(MacPointer.rounded(-0.00004) == 0 && MacPointer.rounded(-0.0265) == -0.0265, "rounded below zero")
check(String(decoding: Wire.encode(MacPointer(x: MacPointer.rounded(1.0 / 3.0), y: MacPointer.rounded(2.0 / 3.0), inside: true)), as: UTF8.self)
      .contains("0.3333") && !String(decoding: Wire.encode(MacPointer(x: MacPointer.rounded(1.0 / 3.0))), as: UTF8.self).contains("0.33333"),
      "a rounded fraction stays short in JSON")
// What a device reads from it.
check(over.position.map { $0.x == 0.4213 && $0.y == 0.1873 } == true, "position: over the stream")
check(off.position == nil && MacPointer(x: 0.5, y: 0.5, inside: false).position == nil, "position: none off the stream")
check(MacPointer(x: 0.5, y: 0.5).position == nil, "position: inside nil counts as false")
check(MacPointer(x: 0.5, inside: true).position == nil && MacPointer(y: 0.5, inside: true).position == nil, "position: inside without both")
check(MacPointer(x: .nan, y: 0.5, inside: true).position == nil && MacPointer(x: 0.5, y: .infinity, inside: true).position == nil,
      "position: not finite")
check(MacPointer(x: 1.2, y: -0.1, inside: true).position.map { $0.x == 1.2 && $0.y == -0.1 } == true,
      "position: out-of-range values are passed on (the sprite clamps them)")

// The kind: 26, between the Mac's menus' 24, 25 and 27, every other kind unchanged, and a reader that knows it
// takes it with its payload.
let known: [(StreamMessageKind, UInt8)] = [
    (.parameterSets, 0), (.frame, 1), (.windowList, 2), (.thumbnail, 3), (.appIcon, 4), (.appList, 5), (.selectSource, 6),
    (.launchApp, 7), (.input, 8), (.viewport, 9), (.ping, 10), (.pong, 11), (.clientStats, 12), (.tick, 13), (.cursorShape, 14),
    (.windowCommand, 15), (.hostSettings, 16), (.changeSettings, 17), (.macInfo, 18), (.pairRequest, 19), (.pairResult, 20),
    (.pairingWanted, 21), (.goodbye, 22), (.hello, 23), (.macMenu, 24), (.pressMenuItem, 25), (.macPointer, 26),
    (.fetchMenu, 27), (.gesture, 28), (.unknown, 255),
]
for (kind, raw) in known {
    check(kind.rawValue == raw && StreamMessageKind(rawValue: raw) == kind, "kind \(raw) is \(kind)")
}
var unknownRaw: [UInt8] = []
for raw in UInt8.min...UInt8.max where !known.contains(where: { $0.1 == raw }) {
    let header = Data([raw]) + Data(count: 9) + Data([0, 0, 0, 3])
    if StreamMessageKind(rawValue: raw) != nil || StreamMessage.parseHeader(header)?.kind != .unknown { unknownRaw.append(raw) }
}
check(unknownRaw.isEmpty, "every other kind (29…254) is unknown to this build: \(unknownRaw)")
let message = StreamMessage(kind: .macPointer, timestamp: 1_790_000_000.25, isKeyframe: false, payload: Wire.encode(over)).serialized()
let header = StreamMessage.parseHeader(message)
check(message.first == 26 && header?.kind == .macPointer && header?.payloadLength == message.count - StreamMessage.headerLength
      && header?.timestamp == 1_790_000_000.25 && header?.isKeyframe == false, "a kind 26 message's header")
check(Wire.decode(MacPointer.self, from: message.subdata(in: StreamMessage.headerLength..<message.count)) == over, "…and its payload")
check(message.count - StreamMessage.headerLength <= StreamMessage.maxOtherHostPayload, "within a device's cap for host messages")

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
