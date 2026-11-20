// iOSClient/TouchHold.swift on its own: the picture's touch and hold in Direct Touch (issue #178). With this
// device's Hold, Then Drag off (the default, PR #292) a hold right-clicks at once, as before #178, and its
// moves, lift and cancel send nothing. On, a hold lifted where it was pressed right-clicks at the lift; a hold
// that then moves past the slop drags with the left button from where it was pressed, to the lift; a cancel
// lets the button up and clicks nothing; input before a hold, or after its end, sends nothing. Then 20,000
// random holds, the switch on or off, against a model written here.
//   swiftc -O iOSClient/TouchHold.swift Tests/checks/touch-hold/main.swift -o check && ./check
import CoreGraphics
import Foundation

typealias H = TouchHold
var fails = 0, passes = 0
func check(_ ok: Bool, _ name: String) { if ok { passes += 1; print("ok   \(name)") } else { fails += 1; print("FAIL \(name)") } }

let o = CGPoint(x: 100, y: 200)
func at(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint { CGPoint(x: o.x + dx, y: o.y + dy) }

// MARK: - The constants

check(H.press == 0.45, "the hold is 0.45 s, the right click's as before: \(H.press)")
check(H.slop == 8, "the slop is 8 pt: \(H.slop)")

// MARK: - The switch: Hold, Then Drag, this device's own, off unless turned on (PR #292)

check(H.key == "Sill.holdThenDrag", "the switch's key: \(H.key)")
check(H.defaultOn == false, "off unless turned on: a hold right-clicks at once until its owner asks for the drag")
check(H.title == "Hold, Then Drag", "the switch's title: \(H.title)")
check(H.footnote == "Touch and hold a moment, then move your finger to drag what’s under it: a window, a slider or a selection. Lift without moving to right-click. Off, touch and hold right-clicks at once.",
      "the words under the switch: \(H.footnote)")

// Off: the right click at once, where the hold began, as before #178; the finger's moves, its lift and a
// cancel send nothing, and nothing is held.
do {
    var h = H()
    check(h.began(at: o, drags: false) == [.rightClick(o)], "off: a right click at once, where the hold began")
    check(!h.isHeld && !h.isDragging, "off: nothing is held after it")
    check(h.moved(to: at(3, 0)) == [], "off: a move inside the slop sends nothing")
    check(h.moved(to: at(60, 30)) == [], "off: a move past the slop sends nothing: no button down, no drag")
    check(!h.isDragging, "off: never dragging")
    check(h.ended(at: at(60, 30)) == [], "off: the lift sends nothing: no second right click, no button up")
    check(h.cancelled() == [], "off: a cancel sends nothing")
}
do {
    var h = H()
    _ = h.began(at: o, drags: false)
    check(h.cancelled() == [], "off: cancelled right after the hold: nothing more")
    check(h.ended(at: o) == [], "off: and a lift after it, nothing")
}
// A change of the switch takes the next hold, and nothing carries over between holds.
do {
    var h = H()
    _ = h.began(at: o, drags: false)
    _ = h.ended(at: o)
    check(h.began(at: o, drags: true) == [], "on after off: nothing at the hold, the moves and the lift decide")
    check(h.moved(to: at(20, 0)) == [.leftDown(o), .move(at(20, 0))], "on after off: the drag as on")
    check(h.ended(at: at(20, 0)) == [.leftUp(at(20, 0))], "on after off: the button up at the lift")
    let p = CGPoint(x: 400, y: 300)
    check(h.began(at: p, drags: false) == [.rightClick(p)], "off after on: a right click at once again")
    check(h.moved(to: CGPoint(x: 460, y: 300)) == [] && h.ended(at: CGPoint(x: 460, y: 300)) == [], "off after on: no drag")
}

// MARK: - A hold lifted where it was pressed: a right click at the lift

do {
    var h = H()
    check(h.began(at: o, drags: true) == [], "on: nothing at the hold itself, not yet a right click")
    check(h.isHeld && !h.isDragging, "a hold that began is held, not dragging")
    check(h.ended(at: o) == [.rightClick(o)], "lifted where it began: a right click there")
    check(!h.isHeld && !h.isDragging, "after the lift nothing is held")
}
do {
    var h = H()
    _ = h.began(at: o, drags: true)
    check(h.moved(to: at(5, 0)) == [], "5 pt: nothing yet")
    check(h.moved(to: at(0, -8)) == [], "8 pt, at the slop: nothing yet")
    check(h.moved(to: at(-5.6, 5.6)) == [], "7.9 pt diagonally: nothing yet")
    check(h.ended(at: at(3, 3)) == [.rightClick(o)], "lifted inside the slop: a right click where it began, not where it lifted")
}

// MARK: - A hold that moves past the slop: a left drag from where it began

do {
    var h = H()
    _ = h.began(at: o, drags: true)
    check(h.moved(to: at(8.5, 0)) == [.leftDown(o), .move(at(8.5, 0))], "past 8 pt: the button down where the hold began, then the move")
    check(h.isDragging, "dragging after the slop")
    check(h.moved(to: at(40, 30)) == [.move(at(40, 30))], "then each move a move")
    check(h.moved(to: at(1, 1)) == [.move(at(1, 1))], "back inside the slop: still a drag's move")
    check(h.ended(at: at(60, 10)) == [.leftUp(at(60, 10))], "lifted: the button up where it lifted, no right click")
    check(!h.isHeld && !h.isDragging, "after the drag nothing is held")
}
do {
    var h = H()
    _ = h.began(at: o, drags: true)
    check(h.moved(to: at(6, 6)) == [.leftDown(o), .move(at(6, 6))], "8.49 pt diagonally is past the slop (the distance, not each axis)")
}
do {
    var h = H()
    _ = h.began(at: o, drags: true)
    check(h.moved(to: at(0, 30)).filter { if case .leftDown = $0 { return true } else { return false } }.count == 1, "one button down")
    for i in 0..<10 { _ = h.moved(to: at(CGFloat(i), 30)) }
    let rest = h.moved(to: at(50, 50))
    check(rest == [.move(at(50, 50))], "never a second button down: \(rest)")
}

// MARK: - A cancel: the button up if it was down, never a click

do {
    var h = H()
    _ = h.began(at: o, drags: true)
    _ = h.moved(to: at(20, 0))
    _ = h.moved(to: at(30, 5))
    check(h.cancelled() == [.leftUp(at(30, 5))], "cancelled mid-drag: the button up where the finger was last")
    check(!h.isHeld && !h.isDragging, "after a cancel nothing is held")
    check(h.cancelled() == [], "a second cancel sends nothing")
}
do {
    var h = H()
    _ = h.began(at: o, drags: true)
    _ = h.moved(to: at(3, 0))
    check(h.cancelled() == [], "cancelled before the slop: no right click, nothing")
    check(h.ended(at: o) == [], "and a lift after it sends nothing")
}

// MARK: - Nothing before a hold, nothing after it

do {
    var h = H()
    check(h.moved(to: o) == [], "a move with no hold: nothing")
    check(h.ended(at: o) == [], "a lift with no hold: nothing")
    check(h.cancelled() == [], "a cancel with no hold: nothing")
    _ = h.began(at: o, drags: true)
    _ = h.ended(at: o)
    check(h.moved(to: at(50, 0)) == [], "a move after the lift: nothing")
}
do {
    var h = H()
    _ = h.began(at: o, drags: true)
    _ = h.moved(to: at(30, 0))
    _ = h.ended(at: at(30, 0))
    let p = CGPoint(x: 500, y: 500)
    _ = h.began(at: p, drags: true)
    check(!h.isDragging, "the next hold starts afresh")
    check(h.ended(at: p) == [.rightClick(p)], "and lifted where it began right-clicks there")
}

// MARK: - 20,000 random holds against a model, the switch on or off

struct Rng { var s: UInt64; mutating func next() -> UInt64 { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s }
    mutating func unit() -> CGFloat { CGFloat(next() % 10_000) / 10_000 } }
var rng = Rng(s: 0x5EED_178)
var stuck = 0, wrong = 0, rights = 0, drags = 0, offs = 0
for _ in 0..<20_000 {
    var h = H()
    let start = CGPoint(x: rng.unit() * 1000, y: rng.unit() * 700)
    let on = rng.next() % 4 != 0
    var sent = h.began(at: start, drags: on)
    var far = false
    var last = start
    for _ in 0..<Int(rng.next() % 12) {
        let p = CGPoint(x: start.x + (rng.unit() - 0.5) * 30, y: start.y + (rng.unit() - 0.5) * 30)
        if hypot(p.x - start.x, p.y - start.y) > 8 { far = true }
        last = p
        sent += h.moved(to: p)
    }
    let lift = CGPoint(x: last.x + (rng.unit() - 0.5) * 4, y: last.y)
    let cancel = rng.next() % 5 == 0
    sent += cancel ? h.cancelled() : h.ended(at: lift)
    // The model: off, one right click at the start, whatever followed; on, a hold that went past the slop is
    // one left drag from the start, ended where it lifted (or where it was last, when cancelled), and one that
    // never did is a right click at the start, or nothing.
    let downs = sent.filter { if case .leftDown = $0 { return true } else { return false } }
    let ups = sent.filter { if case .leftUp = $0 { return true } else { return false } }
    let clicks = sent.filter { if case .rightClick = $0 { return true } else { return false } }
    if downs.count != ups.count { stuck += 1 }
    let expected: Bool
    if !on {
        offs += 1
        expected = sent == [.rightClick(start)]
    } else if far {
        drags += 1
        expected = downs == [.leftDown(start)] && ups == [.leftUp(cancel ? last : lift)] && clicks.isEmpty
            && sent.first == .leftDown(start) && sent.last == ups.last
    } else {
        if !cancel { rights += 1 }
        expected = sent == (cancel ? [] : [.rightClick(start)])
    }
    if !expected { wrong += 1 }
    if h.isHeld || h.isDragging { wrong += 1 }
}
check(stuck == 0, "no random hold leaves the button down: \(stuck)")
check(wrong == 0, "every random hold as the model says, nothing held after it: \(wrong) wrong (\(drags) drags, \(rights) right clicks at the lift, \(offs) with the switch off)")
check(drags > 1000 && rights > 1000 && offs > 1000, "the random holds reach every end: \(drags) drags, \(rights) right clicks at the lift, \(offs) with the switch off")

print("\(passes) passed, \(fails) failed")
exit(fails == 0 ? 0 : 1)
