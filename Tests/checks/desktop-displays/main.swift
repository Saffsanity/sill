// DesktopDisplays (Sources/StreamProtocol/DesktopDisplays.swift) on its own: which of the Mac's displays
// the Desktop streams when it has more than one, and the Desktop button that steps to the next (issue #91,
// Noah's decision: "the tapping method").
//
//   Tests/checks/desktop-displays/run.sh
//
// What it checks: the candidates (never Sill's own virtual display; left to right, then top to bottom, as
// System Settings › Displays arranges them, whatever order macOS lists them in); the display the Desktop
// streams (the one chosen while it is connected, by its UUID, so the same display back under a new ID after
// a sleep is still the one; else the fallback, then the first); the next one (wrapping; none with one
// display); its number; the device's button (its label, VoiceOver's value, and whether a tap asks for the
// next display); and where the Mac's pointer goes after a switch. Then 5,000 random arrangements against
// the rule's properties:
//   P1 the candidates are the displays that are not Sill's, each once, in order;
//   P2 stepping `next` from any candidate visits every candidate once and comes back;
//   P3 a chosen display among the candidates is always the one resolved, whatever its ID;
//   P4 the resolved display is always a candidate (or none when there is none).
import Foundation

var failures = 0, passes = 0
func check(_ ok: Bool, _ what: String) {
    if ok { passes += 1; print("ok   \(what)") } else { failures += 1; print("FAIL \(what)") }
}
func eq<T: Equatable>(_ a: T, _ b: T, _ what: String) { check(a == b, "\(what): \(a)" + (a == b ? "" : " (want \(b))")) }

typealias D = DesktopDisplays
func display(_ id: UInt32, _ uuid: String, x: Double, y: Double = 0, w: Double = 1512, h: Double = 982, sills: Bool = false) -> D.Display {
    D.Display(id: id, uuid: uuid, frame: CGRect(x: x, y: y, width: w, height: h), isSills: sills)
}

// A MacBook Pro's built-in screen (main, at the origin) with two monitors, the left one listed first by
// macOS under the higher ID (marliechorgan's three displays on #173: "(1)" on the left was ID 4).
let builtIn = display(1, "BUILTIN", x: 0, y: 0)
let left = display(4, "BENQ-L", x: -3840, y: -2160, w: 3840, h: 2160)
let right = display(2, "BENQ-R", x: 0, y: -2160, w: 3840, h: 2160)
let sills = display(54, "SILL-VD", x: 1512, y: 0, w: 1366, h: 1024, sills: true)
let listed = [builtIn, right, sills, left]

// MARK: The candidates

let c = D.candidates(listed)
eq(c.map(\.id), [4, 2, 1], "three displays: left to right, then top to bottom, never Sill's own")
eq(D.candidates([sills]).map(\.id), [], "Sill's own virtual display alone: no candidate")
eq(D.candidates([]).map(\.id), [], "no display: no candidate")
eq(D.candidates([display(7, "A", x: 0, y: 0), display(8, "B", x: 0, y: -1080)]).map(\.id), [8, 7],
   "two displays stacked: the top one first")
eq(D.candidates([display(3, "B", x: 1920), display(9, "A", x: 0)]).map(\.id), [9, 3], "side by side: the left one first, whatever its ID")

// MARK: The display the Desktop streams

eq(D.resolve(chosen: nil, among: c, fallback: 1)?.id, 1, "nothing chosen: the fallback (today's: the main display, or macOS's first)")
eq(D.resolve(chosen: nil, among: c, fallback: 99)?.id, 4, "nothing chosen, the fallback not a candidate: the first")
eq(D.resolve(chosen: nil, among: c, fallback: 54)?.id, 4, "the fallback Sill's own display: never; the first")
eq(D.resolve(chosen: nil, among: c, fallback: nil)?.id, 4, "no fallback: the first")
eq(D.resolve(chosen: "BENQ-R", among: c, fallback: 1)?.id, 2, "a chosen display connected: that one")
eq(D.resolve(chosen: "GONE", among: c, fallback: 1)?.id, 1, "a chosen display unplugged: the fallback")
eq(D.resolve(chosen: "SILL-VD", among: c, fallback: 1)?.id, 1, "Sill's own display chosen somehow: never")
let afterSleep = D.candidates([display(53, "BUILTIN", x: 0), display(52, "BENQ-R", x: 0, y: -2160, w: 3840, h: 2160)])
eq(D.resolve(chosen: "BENQ-R", among: afterSleep, fallback: 53)?.id, 52,
   "the chosen display back under a new ID after a sleep (2026-10-28: 21 → 53 and 52): still the one")
eq(D.resolve(chosen: nil, among: [], fallback: 1)?.id, nil, "no candidate: none")

// MARK: The next display

eq(D.next(after: 4, in: c)?.id, 2, "next after the left monitor: the right one")
eq(D.next(after: 2, in: c)?.id, 1, "next after the right monitor: the built-in screen")
eq(D.next(after: 1, in: c)?.id, 4, "next after the last: back to the first")
eq(D.next(after: 99, in: c)?.id, 4, "next after a display no longer listed: the first")
eq(D.next(after: nil, in: c)?.id, 4, "next after none: the first")
eq(D.next(after: 1, in: [builtIn])?.id, nil, "one display: no next")
eq(D.next(after: nil, in: [])?.id, nil, "no display: no next")
eq(D.next(after: 54, in: c)?.id, 4, "next after Sill's own display (not a candidate): the first")

// MARK: After a step

eq(D.afterStep(stepped: "BENQ-R", previous: "BENQ-L", streamed: true), "BENQ-R", "the stepped-to display streams: kept")
eq(D.afterStep(stepped: "BENQ-R", previous: "BENQ-L", streamed: false), "BENQ-L",
   "it does not stream (ScreenCaptureKit refused it): back to the display it was on, which streamed")
eq(D.afterStep(stepped: "BENQ-R", previous: nil, streamed: false), nil, "it does not stream, nothing known before: no choice")

// MARK: Its number

eq(D.number(of: 4, in: c), 1, "the left monitor is display 1")
eq(D.number(of: 1, in: c), 3, "the built-in screen is display 3")
eq(D.number(of: 54, in: c), nil, "Sill's own display has no number")
eq(D.number(of: nil, in: c), nil, "none has no number")

// MARK: Where input lands

// A device stepped to the right monitor: the catalog's display is the right one at once, but the capture
// still runs on the left one until the restart, and that is what the device shows.
eq(D.landing(streaming: 4, among: c), left.frame, "input lands on the display the capture was built on, not the one just chosen")
let moved = D.candidates([display(4, "BENQ-L", x: 3840, y: 0, w: 3840, h: 2160), builtIn])
eq(D.landing(streaming: 4, among: moved), CGRect(x: 3840, y: 0, width: 3840, height: 2160),
   "the same display moved in System Settings › Displays: where the newest look has it")
eq(D.landing(streaming: 99, among: c), nil, "the streamed display gone: none (the catalog's display then)")
eq(D.landing(streaming: nil, among: c), nil, "no Desktop capture yet: none (the catalog's display then)")
eq(D.landing(streaming: 54, among: c), nil, "Sill's own display is no candidate: none")

// MARK: The device's button

eq(D.label(displays: nil, current: nil), "Desktop", "a Mac before this build: Desktop")
eq(D.label(displays: 1, current: 1), "Desktop", "one display: Desktop, as today")
eq(D.label(displays: 2, current: 1), "Desktop 1", "two displays, the first: Desktop 1")
eq(D.label(displays: 3, current: 3), "Desktop 3", "three displays, the third: Desktop 3")
eq(D.label(displays: 2, current: nil), "Desktop", "two displays, which one unknown: Desktop")
eq(D.label(displays: 2, current: 3), "Desktop", "a number past the count: Desktop")
eq(D.label(displays: 2, current: 0), "Desktop", "a number of 0: Desktop")
eq(D.accessibilityValue(displays: 2, current: 1), "Display 1 of 2", "VoiceOver: Display 1 of 2")
eq(D.accessibilityValue(displays: 1, current: 1), nil, "VoiceOver with one display: no value")
eq(D.accessibilityValue(displays: nil, current: nil), nil, "VoiceOver, a Mac before this build: no value")
eq(D.accessibilityValue(displays: 2, current: 5), nil, "VoiceOver, a number past the count: no value")
eq(D.tapSendsNext(desktopStreams: true, displays: 2), true, "the Desktop streaming, two displays: a tap asks for the next")
eq(D.tapSendsNext(desktopStreams: true, displays: 1), false, "one display: a tap picks the Desktop, as today")
eq(D.tapSendsNext(desktopStreams: true, displays: nil), false, "a Mac before this build: a tap picks the Desktop, as today")
eq(D.tapSendsNext(desktopStreams: false, displays: 3), false, "a window streaming: a tap picks the Desktop")
eq(D.tapSendsNext(desktopStreams: true, displays: 0), false, "no display: a tap picks the Desktop")

// MARK: The pointer after a switch

eq(D.pointerTarget(pointer: CGPoint(x: 100, y: 100), on: right.frame), CGPoint(x: 1920, y: -1080),
   "the pointer on the built-in screen, the Desktop now on the right monitor: its centre")
eq(D.pointerTarget(pointer: CGPoint(x: 100, y: -100), on: right.frame), nil, "the pointer already on it: left where it is")
eq(D.pointerTarget(pointer: nil, on: left.frame), CGPoint(x: -1920, y: -1080), "the pointer unknown: the centre")
eq(D.pointerTarget(pointer: CGPoint(x: 0, y: 0), on: right.frame), CGPoint(x: 1920, y: -1080),
   "the pointer on the shared edge, the right monitor's bottom (its rectangle ends there): the centre")

// MARK: Random arrangements

var rng = SystemRandomNumberGenerator()
var stepped = 0
for _ in 0..<5_000 {
    let n = Int.random(in: 0...5, using: &rng)
    var all: [D.Display] = []
    var used = Set<UInt32>()
    for i in 0..<n {
        var id: UInt32
        repeat { id = UInt32.random(in: 1...200, using: &rng) } while used.contains(id)
        used.insert(id)
        all.append(display(id, "U\(i)", x: Double(Int.random(in: -4...4, using: &rng)) * 1000 + Double(i),
                           y: Double(Int.random(in: -2...2, using: &rng)) * 1000, sills: Bool.random(using: &rng) && i == 0))
    }
    let cands = D.candidates(all.shuffled(using: &rng))
    let mine = all.filter { !$0.isSills }
    // P1
    if Set(cands.map(\.id)) != Set(mine.map(\.id)) || cands.count != mine.count { check(false, "P1 the candidates are the displays not Sill's: \(cands.map(\.id)) of \(all.map(\.id))") }
    for (a, b) in zip(cands, cands.dropFirst()) where (a.frame.minX, a.frame.minY) > (b.frame.minX, b.frame.minY) {
        check(false, "P1 the candidates in order: \(a.frame.origin) before \(b.frame.origin)")
    }
    // P2
    if cands.count > 1, let start = cands.randomElement(using: &rng) {
        var seen = [start.id]
        var at = start.id
        for _ in 0..<cands.count { at = D.next(after: at, in: cands)!.id; seen.append(at) }
        if seen.last != start.id || Set(seen).count != cands.count { check(false, "P2 next visits every candidate once: \(seen)") }
        stepped += 1
    } else if D.next(after: cands.first?.id, in: cands) != nil {
        check(false, "P2 one display or none: no next")
    }
    // P3
    if let chosen = cands.randomElement(using: &rng), D.resolve(chosen: chosen.uuid, among: cands, fallback: UInt32.random(in: 0...200, using: &rng))?.id != chosen.id {
        check(false, "P3 the chosen display is the one resolved: \(chosen.id)")
    }
    // P4
    let r = D.resolve(chosen: Bool.random(using: &rng) ? "U\(Int.random(in: 0...6, using: &rng))" : nil, among: cands,
                      fallback: all.randomElement(using: &rng)?.id)
    if cands.isEmpty ? r != nil : !cands.contains(where: { $0 == r }) { check(false, "P4 the resolved display is a candidate: \(String(describing: r?.id))") }
}
check(stepped > 1000, "the random arrangements stepped through \(stepped) with two displays or more")
check(failures == 0, "5,000 random arrangements: P1 to P4 held")

print("\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
