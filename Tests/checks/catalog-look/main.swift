// CatalogLook (Sources/SillHost/CatalogLook.swift) on its own: whether a capture may be built from the
// catalog's last look at the windows and displays, or the catalog looks again first, and the Desktop's
// one more try after a start that failed (the black screen of 2026-10-28: Sill.app 36.5 hours with no
// device, its last look's display 21 gone, the dock's displays back as 53 and 52, the Desktop built on
// 21's SCDisplay and refused by ScreenCaptureKit, "The stream is nil").
//
//   Tests/checks/catalog-look/run.sh
//
// What it checks: the rule's order (the display first, whatever the look's age; then no look; then the
// age) at its edges; the 2026-10-28 case itself; a look kept fresh by the poll never looked at again; an
// asleep display looked at again (one look, and nothing else); an empty list of displays judged by the age
// alone; the poll interval followed; the lines and the age's words; then 20,000 random looks against the
// rule's properties:
//   P1 a display not among the active ones, with any active, is always looked at again, at any age;
//   P2 a look older than two poll intervals is always looked at again;
//   P3 a look no older than two poll intervals whose display is among the active ones is never looked at again;
//   P4 no look yet is always looked at again;
//   P5 an empty list of displays never makes the display the reason;
//   P6 the reason is the display whenever the display is the trouble, else the age's.
import Foundation

var failures = 0, passes = 0
func check(_ ok: Bool, _ what: String) {
    if ok { passes += 1; print("ok   \(what)") } else { failures += 1; print("FAIL \(what)") }
}
func eq<T: Equatable>(_ a: T, _ b: T, _ what: String) { check(a == b, "\(what): \(a)" + (a == b ? "" : " (want \(b))")) }

typealias L = CatalogLook
let poll = 2.0          // WindowCatalog.pollInterval
func look(age: TimeInterval?, display: UInt32?, now: [UInt32], poll p: TimeInterval = poll) -> L.Why? {
    L.lookAgain(age: age, display: display, displaysNow: now, pollInterval: p)
}

// MARK: The constants

eq(L.staleAfterPolls, 2, "a look older than two poll intervals is from a spell with no device")
eq(L.seconds(.seconds(2)), 2, "seconds: 2 s")
eq(L.seconds(.milliseconds(1500)), 1.5, "seconds: 1.5 s")
eq(L.seconds(.seconds(36 * 3600 + 1800)), 131_400, "seconds: 36.5 h")
check(abs(L.seconds(.nanoseconds(1)) - 1e-9) < 1e-15, "seconds: a nanosecond")

// MARK: 2026-10-28

// The catalog's last look was from 10-27 05:42, display 21; at 18:15:43 on 10-28 macOS had 53 and 52
// active (and Sill's own virtual displays 54 and 55 only while a window is staged).
let spell = 36.5 * 3600
eq(look(age: spell, display: 21, now: [53, 52]), .displayGone(21), "2026-10-28: display 21 is gone: looked at again")
eq(look(age: spell, display: 53, now: [53, 52]), .old(spell), "2026-10-28: even had 21 stayed 53, a look 36.5 h old is looked at again")
eq(look(age: 0.06, display: 53, now: [53, 52]), nil, "2026-10-28: the look that landed 60 ms before the start: fresh, display 53 there")
eq(look(age: spell, display: 21, now: [53, 52, 54, 55]), .displayGone(21), "2026-10-28 with a window staged: 21 is gone all the same")

// MARK: A session (the poll keeps the look fresh)

for age in [0, 0.05, 1, 2, 2.4, 3.9, 4.0] {
    eq(look(age: age, display: 1, now: [1]), nil, "a session: a look \(age) s old on the active display 1 will do")
}
eq(look(age: 4.0001, display: 1, now: [1]), .old(4.0001), "just past two poll intervals: looked at again")
eq(look(age: 4.0, display: 1, now: [1, 2, 3]), nil, "two poll intervals to the dot will do (strictly older is stale)")
eq(look(age: 1, display: 2, now: [1, 2, 3]), nil, "the display among several active ones, not the first: will do")

// MARK: The display

eq(look(age: 1, display: 21, now: [53]), .displayGone(21), "a fresh look whose display went (unplugged between two polls): looked at again")
eq(look(age: 1, display: 21, now: [53, 52]), .displayGone(21), "gone, with two others")
eq(look(age: nil, display: 21, now: [53]), .displayGone(21), "gone with no age: the display's reason first")
eq(look(age: spell, display: 21, now: [53]), .displayGone(21), "gone and old: the display's reason first")
// Asleep: CGGetActiveDisplayList leaves a sleeping display out, so it is looked at again (one look, then
// the capture as before: DisplayWake wakes it).
eq(look(age: 1, display: 1, now: [2]), .displayGone(1), "asleep (not active), another awake: looked at again")
eq(look(age: 1, display: nil, now: [1]), .noDisplay, "the last look had no display and macOS has one now: looked at again")
eq(look(age: spell, display: nil, now: [1]), .noDisplay, "no display in an old look: the display's reason first")
eq(look(age: nil, display: nil, now: [1]), .noDisplay, "no look and no display, one active: the display's reason first")

// MARK: No displays to judge by (none active, or the call failed)

eq(look(age: 1, display: 21, now: []), nil, "no active display: a fresh look will do (nothing to judge the display by)")
eq(look(age: 1, display: nil, now: []), nil, "no active display, none in the look, fresh: will do")
eq(look(age: spell, display: 21, now: []), .old(spell), "no active display: the age alone decides")
eq(look(age: nil, display: 21, now: []), .never, "no active display, no look: never looked")
eq(look(age: nil, display: nil, now: []), .never, "nothing at all: never looked")

// MARK: No look yet

eq(look(age: nil, display: 1, now: [1]), .never, "no look yet (a display left from nowhere): looked at")

// MARK: The poll interval followed

eq(look(age: 9, display: 1, now: [1], poll: 5), nil, "a 5 s poll: 9 s will do")
eq(look(age: 10.5, display: 1, now: [1], poll: 5), .old(10.5), "a 5 s poll: 10.5 s is stale")
eq(look(age: 2.5, display: 1, now: [1], poll: 1), .old(2.5), "a 1 s poll: 2.5 s is stale")

// MARK: The Desktop's line

eq(L.desktopLine(was: 21, now: 53, age: spell), "Desktop: display 21 → 53 (the displays changed since the last look, 36 h ago).",
   "the line, 2026-10-28")
eq(L.desktopLine(was: 21, now: 53, age: 1.2), "Desktop: display 21 → 53 (the displays changed since the last look, 1.2 s ago).",
   "the line, a display changed between two polls")
eq(L.desktopLine(was: 21, now: 53, age: nil), "Desktop: display 21 → 53 (the displays changed since the last look).", "the line with no age")
eq(L.desktopLine(was: 53, now: 53, age: spell), nil, "no line when the display is the same (an old look, nothing changed)")
eq(L.desktopLine(was: nil, now: 53, age: nil), nil, "no line after no look")
eq(L.desktopLine(was: 21, now: nil, age: spell), nil, "no line when the new look has no display")

// MARK: The one more try's line

eq(L.retryLine(source: "the whole desktop", error: "Error Domain=CoreGraphicsErrorDomain Code=1003 \"Start stream failed\"", display: 53),
   "Could not start streaming the whole desktop: Error Domain=CoreGraphicsErrorDomain Code=1003 \"Start stream failed\". Looked at the displays again: trying once more on display 53.",
   "the retry line, a display")
eq(L.retryLine(source: "a synthetic test pattern (software encoder)", error: "E", display: nil),
   "Could not start streaming a synthetic test pattern (software encoder): E. Trying once more.", "the retry line, the test pattern")
check(L.retryLine(source: "the whole desktop", error: "E", display: 53).hasPrefix("Could not start streaming the whole desktop: E."),
      "the retry line starts as the old failure line did (a grep for it still finds it)")

// MARK: The age's words

eq(L.ageWords(0), "0.0 s", "words: 0")
eq(L.ageWords(0.46), "0.4 s", "words: 0.46 s rounds down")
eq(L.ageWords(9.99), "9.9 s", "words: 9.99 s")
eq(L.ageWords(10), "10 s", "words: 10 s")
eq(L.ageWords(59.9), "59 s", "words: 59.9 s")
eq(L.ageWords(60), "1 min", "words: a minute")
eq(L.ageWords(3599), "59 min", "words: 59 min")
eq(L.ageWords(3600), "1 h", "words: an hour")
eq(L.ageWords(spell), "36 h", "words: 36.5 h")
eq(L.ageWords(48 * 3600 - 1), "47 h", "words: under two days in hours")
eq(L.ageWords(48 * 3600), "2 days", "words: two days")
eq(L.ageWords(10 * 86400 + 5), "10 days", "words: ten days")
eq(L.ageWords(-3), "0.0 s", "words: a negative age reads as none")

// MARK: Random looks against the properties

var rng = SystemRandomNumberGenerator()
var p1 = 0, p2 = 0, p3 = 0, p4 = 0, p5 = 0, p6 = 0
let trials = 20_000
for _ in 0..<trials {
    let p = [0.5, 1, 2, 5][Int.random(in: 0..<4, using: &rng)]
    let active = (0..<Int.random(in: 0...3, using: &rng)).map { _ in UInt32.random(in: 1...6, using: &rng) }
    let display: UInt32? = Bool.random(using: &rng) && Int.random(in: 0..<5, using: &rng) == 0 ? nil : UInt32.random(in: 1...6, using: &rng)
    let age: TimeInterval? = Int.random(in: 0..<8, using: &rng) == 0 ? nil
        : [Double.random(in: 0...(3 * p), using: &rng), 2 * p, Double.random(in: 0...200_000, using: &rng)][Int.random(in: 0..<3, using: &rng)]
    let why = look(age: age, display: display, now: active, poll: p)
    let displayTrouble = !active.isEmpty && (display.map { !active.contains($0) } ?? true)
    let stale = age.map { $0 > 2 * p } ?? true
    if displayTrouble, why == nil { p1 += 1 }
    if let age, age > 2 * p, why == nil { p2 += 1 }
    if let age, age <= 2 * p, let display, active.contains(display), why != nil { p3 += 1 }
    if age == nil, why == nil { p4 += 1 }
    if active.isEmpty, let why { if case .displayGone = why { p5 += 1 }; if case .noDisplay = why { p5 += 1 } }
    switch why {
    case .displayGone(let id)?: if !displayTrouble || id != display { p6 += 1 }
    case .noDisplay?: if !displayTrouble || display != nil { p6 += 1 }
    case .never?: if displayTrouble || age != nil { p6 += 1 }
    case .old(let a)?: if displayTrouble || a != age || !stale { p6 += 1 }
    case nil: if displayTrouble || stale { p6 += 1 }
    }
}
eq(p1, 0, "P1 (\(trials) random looks): a display not among the active ones is always looked at again")
eq(p2, 0, "P2: a look older than two poll intervals is always looked at again")
eq(p3, 0, "P3: a look no older than two poll intervals on an active display is never looked at again")
eq(p4, 0, "P4: no look yet is always looked at again")
eq(p5, 0, "P5: an empty list of displays never makes the display the reason")
eq(p6, 0, "P6: the reason is the display whenever it is the trouble, else the age's")

print("\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
