// DisplayWake (Sources/SillHost/DisplayWake.swift) with the wire's message kinds and input events
// (Sources/StreamProtocol/StreamMessage.swift and Input.swift): when the host declares user activity
// on the Mac for a device (issue #134, PR #151), what a key press on the Mac does, so a sleeping
// display wakes for a person at the device and sleeps again by the Mac's own setting once nobody
// uses it.
//
//   Tests/checks/display-wake/run.sh   (build.sh compiles the three files with this one)
//
// What it checks: the constants; which of a device's messages are a person at it, every kind there
// is (a connect, kinds 7, 8, 15, 25, 28; never 6, 9, 17, 21, 27, 32, 44, nor any other, nor input that
// does not decode), every input event; the device's own move to a new frame's middle (a bare pointer
// move under 2 s after the host's stream restart or new frame size; at 2 s a person's again), the
// latest change counting, a clock set back ending the window; the interval (a connect every time,
// the rest only 5 s or more after the last declaration, at exactly 5 s too, what was held off or was
// not a person's not restarting it, a clock set back never holding one off); a test host counting
// exactly where a real one declares; the lines; what DisplayActivity says after its second look
// (Report: a wake only when the display read asleep before and on after, once for one wake, any other
// declaration's line at most once a minute, a woke line counting as that minute's, a refusal once,
// again after a success); the TEST ONLY user type (SILL_TEST_USER_ACTIVE); then 20,000 random
// sessions against the rule's invariants and 20,000 against Report's:
//   I1 every connect declares (a test host: counts);
//   I2 two declarations by anything but a connect are never under 5 s apart, unless the clock went back;
//   I3 a person's activity (this file's own table) 5 s or more after the last declaration declares,
//      and so does one after the clock went back;
//   I4 a test host never declares, a real one never counts;
//   I5 through a person's activity that keeps coming (no gap over g), the time since the last
//      declaration is never over 5 s + g: the display stays on as it would for local input;
//   I6 the device's own (a pick, a bare move in the window after a stream change, any other kind,
//      input that does not decode) never declares nor counts, and moves nothing;
//   R1 a woke line only for a declaration whose display read asleep before and on at its look;
//   R2 one woke line for one wake: never two for declarations made before the same woke line;
//   R3 every wake said: asleep before, on at the look, and made after the last woke line;
//   R4 any other line at most once a minute (counting woke lines), unless the clock went back, and
//      said whenever that allows;
//   R5 a refusal said once, and again only after a declaration went through; it takes no look.
import Foundation

var failures = 0, passes = 0
func check(_ ok: Bool, _ what: String) {
    if ok { passes += 1; print("ok   \(what)") } else { failures += 1; print("FAIL \(what)") }
}
func eq<T: Equatable>(_ a: T, _ b: T, _ what: String) { check(a == b, "\(what): \(a)" + (a == b ? "" : " (want \(b))")) }

typealias W = DisplayWake
typealias Kind = StreamMessageKind

extension DisplayWake.Decision: CustomStringConvertible {
    var description: String {
        switch self {
        case .nothing: return "nothing"
        case .declare(let activity): return "declare(\(activity))"
        case .count: return "count"
        }
    }
}

/// A message of `kind` from a device, with its input event (kind 8).
func msg(_ kind: Kind, _ input: InputEvent? = nil) -> W.Event { .message(kind, input) }
let tap = InputEvent.pointer(.leftDown, x: 0.3, y: 0.4)
let move = InputEvent.pointer(.move, x: 0.31, y: 0.42)
/// StreamClient.pointerFrameChanged's own move, exactly as a device sends it.
let recentred = InputEvent.pointer(.move, x: 0.5, y: 0.5)
let shift = InputEvent.key(hidUsage: 225, down: true, modifiers: 0)
let person = msg(.input, tap)
let desktop = msg(.selectSource)

/// Runs `steps` through a fresh rule: an event at a time, or (nil) the host's stream change then.
/// Returns the events' decisions.
func run(_ steps: [(W.Event?, TimeInterval)], testHost: Bool = false) -> [W.Decision] {
    var w = W(testHost: testHost)
    var out: [W.Decision] = []
    for (event, t) in steps {
        if let event { out.append(w.decide(event, at: t)) } else { w.streamChanged(at: t) }
    }
    return out
}

// MARK: - The constants

eq(W.interval, 5, "the interval: 5 s")
eq(W.recentre, 2, "a bare move is the device's own for 2 s after a stream change")
eq(W.secondLook, 0.5, "the second look at the display: 0.5 s after the declaration")
eq(W.declaredLineInterval, 60, "a declaration's line at most once a minute")
eq(W.assertionName, "Sill: a device is using this Mac", "the assertion's name in pmset -g assertions")
check(W.assertionName.utf8.count <= 128, "the assertion's name within IOPMLib.h's 128 characters (\(W.assertionName.utf8.count))")
eq(W.declaredKey, "disp.wake", "the stats key for a declaration")
eq(W.dryKey, "disp.wakeDry", "the stats key for a test host's count")
eq(W.success, 0, "kIOReturnSuccess is 0")
check(W.declaredKey != W.dryKey, "the two keys differ")
eq(W.userActiveVariable, "SILL_TEST_USER_ACTIVE", "the TEST ONLY variable's name")

// MARK: - Whose each message is: every kind there is

/// The kinds that are a person at the device, written out: the rule's table must be exactly this.
let personKinds: [UInt8: W.Activity] = [7: .launch, 8: .input, 15: .windowButton, 25: .menuItem, 28: .gesture]
var kinds = 0
let fresh = W(testHost: false)
for raw in 0...255 {
    guard let kind = Kind(rawValue: UInt8(raw)) else { continue }
    kinds += 1
    eq(fresh.activity(msg(kind, kind == .input ? tap : nil), at: 100), personKinds[UInt8(raw)], "kind \(raw) (\(kind))")
}
// A kind added to the wire fails this until it is decided here (and in the rule).
eq(kinds, 32, "every kind there is decided (a new kind: say here whether it is a person at the device)")
for (raw, what) in [(6, "a pick, the device's own Desktop request among them"), (9, "the viewport"), (17, "a settings change"),
                    (21, "show your pairing code"), (27, "a menu fetched"), (32, "the clipboard"),
                    (44, "a keyframe request")] as [(UInt8, String)] {
    let kind = Kind(rawValue: raw)!
    eq(fresh.activity(msg(kind), at: 100), nil, "never kind \(raw), \(what)")
    eq(fresh.activity(msg(kind, tap), at: 100), nil, "never kind \(raw), whatever input rides with it")
}
eq(fresh.activity(msg(.input), at: 100), nil, "input that does not decode: nothing")
eq(fresh.activity(.connect, at: 100), .connect, "a connect")
do {
    var w = W(testHost: false)
    for t in [0.0, 0.05, 10, 600, 3600] { eq(w.decide(desktop, at: t), .nothing, "a pick at \(t) s: nothing") }
    eq(w.lastDeclared, nil, "picks declare nothing and move nothing")
}

// MARK: - Every input event

let events: [(InputEvent, String)] = [
    (move, "a pointer move"), (.pointer(.leftDown, x: 0.1, y: 0.2), "a press"), (.pointer(.leftUp, x: 0.1, y: 0.2), "a release"),
    (.pointer(.rightDown, x: 0.1, y: 0.2), "a right press"), (.pointer(.rightUp, x: 0.1, y: 0.2), "a right release"),
    (.scroll(x: 0.5, y: 0.5, dx: 0, dy: 0.01), "a scroll"), (.scrollGesture(.began, x: 0.5, y: 0.5), "a scroll's start"),
    (.scrollGesture(.ended, x: 0.5, y: 0.5), "a scroll's end"), (.scrollGesture(.momentumBegan, x: 0.5, y: 0.5), "a coast's start"),
    (.scrollGesture(.momentumEnded, x: 0.5, y: 0.5), "a coast's end"), (.text("a"), "text"), (shift, "a modifier key down"),
    (.key(hidUsage: 225, down: false, modifiers: 0), "a key up"),
]
for (event, what) in events {
    eq(fresh.activity(msg(.input, event), at: 100), .input, "\(what) with no stream change: a person's")
    var w = W(testHost: false)
    w.streamChanged(at: 100)
    let isMove: Bool
    if case .pointer(.move, _, _) = event { isMove = true } else { isMove = false }
    eq(w.activity(msg(.input, event), at: 100.5), isMove ? nil : .input,
       "\(what) 0.5 s after a stream change: \(isMove ? "the device's own" : "a person's")")
}

// MARK: - The device's own move to a new frame's middle

do {
    var w = W(testHost: false)
    eq(w.streamChangedAt, nil, "fresh: no stream change yet")
    w.streamChanged(at: 100)
    eq(w.streamChangedAt, 100, "the stream change's time kept")
    eq(w.activity(msg(.input, recentred), at: 100), nil, "the re-centre at the change's instant: the device's own")
    eq(w.activity(msg(.input, recentred), at: 101.999), nil, "1.999 s after: the device's own")
    eq(w.activity(msg(.input, move), at: 102), .input, "a move exactly 2 s after: a person's")
    eq(w.activity(msg(.input, recentred), at: 160), .input, "a minute after: a person's, even at the middle")
    eq(w.activity(msg(.input, recentred), at: 99), .input, "the clock set back before the change: the window is over")
    eq(w.activity(msg(.input, tap), at: 100.1), .input, "a tap in the window: a person's")
    eq(w.activity(msg(.input, shift), at: 100.1), .input, "a modifier key in the window: a person's")
    eq(w.activity(msg(.gesture), at: 100.1), .gesture, "a gesture in the window: a person's")
    w.streamChanged(at: 105)
    eq(w.activity(msg(.input, move), at: 106), nil, "a second change: the window counts from the latest")
    w.streamChanged(at: 50)
    eq(w.activity(msg(.input, move), at: 51), nil, "a change at an earlier clock: it is the latest")
    eq(w.activity(msg(.input, move), at: 106), .input, "and the one before it no longer holds a move")
}
eq(run([(.connect, 0), (nil, 0.4), (msg(.input, recentred), 0.6), (msg(.input, move), 7)]),
   [.declare(.connect), .nothing, .declare(.input)],
   "connect, the stream starts, the device re-centres: nothing; the person's move later declares")
eq(run([(person, 0), (nil, 4), (msg(.input, recentred), 5.2), (msg(.input, move), 6.1)]),
   [.declare(.input), .nothing, .declare(.input)],
   "a re-centre due by the interval holds nothing off: the next move past the window declares")
do {
    // The review's case: the Mac's display sleeps with the device left on the Desktop; macOS stops the
    // capture, the device asks for the Desktop again by itself, the host restarts the stream and the
    // device re-centres its own pointer. Nobody is at either end: nothing is declared.
    var w = W(testHost: false)
    eq(w.decide(.connect, at: 0), .declare(.connect), "untouched device: the connect")
    eq(w.decide(desktop, at: 0.05), .nothing, "its own Desktop request")
    eq(w.decide(desktop, at: 600), .nothing, "ten minutes later, the Desktop asked for again after a capture stop")
    w.streamChanged(at: 600.3)
    eq(w.decide(msg(.input, recentred), at: 600.4), .nothing, "the re-centre on the restarted stream")
    eq(w.decide(desktop, at: 1200), .nothing, "ten minutes on, the Desktop asked for again")
    w.streamChanged(at: 1200.2)
    eq(w.decide(msg(.input, recentred), at: 1201.9), .nothing, "and the re-centre 1.7 s after that restart")
    eq(w.lastDeclared, 0, "nothing declared since the connect")
    eq(w.decide(msg(.input, move), at: 1300), .declare(.input), "a person moving the pointer later: declares")
}

// MARK: - The connect: every time

eq(run([(.connect, 0), (.connect, 0.001), (.connect, 0.002)]), [.declare(.connect), .declare(.connect), .declare(.connect)],
   "three connects within 2 ms: each declares (two devices, a move's second connection)")
eq(run([(person, 0), (.connect, 1)]), [.declare(.input), .declare(.connect)], "a connect 1 s after input's declaration still declares")
eq(run([(.connect, 0), (person, 0.5)]), [.declare(.connect), .nothing], "input 0.5 s after the connect: nothing")
eq(run([(person, 0), (.connect, 4), (person, 5), (person, 9)]), [.declare(.input), .declare(.connect), .nothing, .declare(.input)],
   "a connect at 4 s restarts the interval: input at 5 s nothing, at 9 s declares")
eq(run([(nil, 0), (.connect, 0.5)]), [.declare(.connect)], "a connect in the window after a stream change: declares")

// MARK: - A person's activity, held to the interval

do {
    // A stream of input every 0.1 s for a minute, after a connect at 0.
    var w = W(testHost: false)
    var declaredAt: [TimeInterval] = []
    if w.decide(.connect, at: 0) != .nothing { declaredAt.append(0) }
    for i in 1...600 {
        let t = Double(i) / 10
        if w.decide(msg(.input, i % 2 == 0 ? move : tap), at: t) != .nothing { declaredAt.append(t) }
    }
    let gaps = zip(declaredAt.dropFirst(), declaredAt).map { $0 - $1 }
    eq(declaredAt.count, 13, "input every 0.1 s for 60 s after a connect: 13 declarations (0, 5, …, 60)")
    check(gaps.allSatisfy { abs($0 - 5) < 0.0001 }, "input every 0.1 s: declarations 5 s apart (\(gaps.map { String(format: "%.1f", $0) }.joined(separator: " ")))")
}
eq(run([(person, 0), (person, 1), (person, 2), (person, 3), (person, 4), (person, 5), (person, 6)]),
   [.declare(.input), .nothing, .nothing, .nothing, .nothing, .declare(.input), .nothing],
   "input every second: what was held off does not restart the interval (5 s declares)")
eq(run([(person, 0), (person, 4.9), (person, 9.8), (person, 14.7)]), [.declare(.input), .nothing, .declare(.input), .nothing],
   "input every 4.9 s: every other one declares")
eq(run([(person, 0), (person, 600)]), [.declare(.input), .declare(.input)], "input after 10 minutes of nothing: declares at once (the display may have slept)")
eq(run([(person, 0), (person, 5 - 1e-9)]), [.declare(.input), .nothing], "input just under 5 s: nothing")
eq(run([(person, 0), (person, 5)]), [.declare(.input), .declare(.input)], "input at exactly 5 s: declares")
eq(run([(msg(.launchApp), 0), (msg(.launchApp), 3), (msg(.launchApp), 5)]), [.declare(.launch), .nothing, .declare(.launch)],
   "an app opened: held to the interval like input")
eq(run([(person, 0), (msg(.windowCommand), 2), (msg(.windowCommand), 6)]), [.declare(.input), .nothing, .declare(.windowButton)],
   "a window's button: held to the interval")
eq(run([(msg(.pressMenuItem), 0), (msg(.gesture), 5), (msg(.pressMenuItem), 9.9), (msg(.gesture), 10)]),
   [.declare(.menuItem), .declare(.gesture), .nothing, .declare(.gesture)], "a menu item and a gesture: held to the interval")
eq(run([(person, 0), (desktop, 6), (msg(.viewport), 7), (msg(.changeSettings), 8), (person, 8.5)]),
   [.declare(.input), .nothing, .nothing, .nothing, .declare(.input)],
   "what is not a person's restarts nothing: input 8.5 s after the last declaration declares")
eq(run([(person, 0), (nil, 4.5), (msg(.input, recentred), 5.5), (person, 6)]), [.declare(.input), .nothing, .declare(.input)],
   "the device's own move does not restart the interval")

// MARK: - A clock set back

eq(run([(person, 1000), (person, 10)]), [.declare(.input), .declare(.input)], "the clock set back 990 s: input declares")
eq(run([(person, 1000), (person, 10), (person, 11), (person, 15)]), [.declare(.input), .declare(.input), .nothing, .declare(.input)],
   "after the clock went back, the interval counts from the new time")
eq(run([(person, 1000), (person, 999.9)]), [.declare(.input), .declare(.input)], "the clock back by 0.1 s: declares")
eq(run([(person, 1000), (person, 1000)]), [.declare(.input), .nothing], "the same instant: nothing")

// MARK: - A test host

do {
    let steps: [(W.Event?, TimeInterval)] = [(.connect, 0), (desktop, 0.1), (person, 2), (msg(.input, move), 5.2), (.connect, 5.3),
                                             (nil, 6), (msg(.input, recentred), 6.2), (msg(.gesture), 11)]
    let real = run(steps), test = run(steps, testHost: true)
    eq(real, [.declare(.connect), .nothing, .nothing, .declare(.input), .declare(.connect), .nothing, .declare(.gesture)], "a session on a real host")
    eq(test, [.count, .nothing, .nothing, .count, .count, .nothing, .count], "the same session on a test host: counts where it declares")
    check(!test.contains { if case .declare = $0 { return true }; return false }, "a test host never declares")
    var t = W(testHost: true)
    eq(t.decide(.connect, at: 0), .count, "a test host's connect counts")
    eq(t.lastDeclared, 0, "a test host's count restarts the interval as a declaration does")
    eq(t.decide(person, at: 1), .nothing, "a test host's input 1 s later: nothing")
}

// MARK: - The lines

eq(W.why(.connect), "connected", "why: a connect")
eq(W.why(.launch), "opened an app", "why: an app opened")
eq(W.why(.input), "sent input", "why: input")
eq(W.why(.windowButton), "pressed a window’s button", "why: a window's button")
eq(W.why(.menuItem), "chose a menu item", "why: a menu item")
eq(W.why(.gesture), "made a trackpad gesture", "why: a gesture")
check(Set(W.Activity.allCases.map(W.why)).count == W.Activity.allCases.count, "each activity's words its own")
eq(W.wokeLine(device: "iPad (iPad14,1)", activity: .connect), "Woke the display for iPad (iPad14,1), which connected.",
   "the woke line for a connect")
eq(W.wokeLine(device: "Noah’s iPhone", activity: .input), "Woke the display for Noah’s iPhone, which sent input.",
   "the woke line for input")
eq(W.wokeLine(device: "127.0.0.1:52011", activity: .gesture), "Woke the display for 127.0.0.1:52011, which made a trackpad gesture.",
   "the woke line naming an address")
eq(W.declaredLine(device: "iPad (iPad14,1)", activity: .input, asleepNow: false), "Declared activity for iPad (iPad14,1), which sent input.",
   "the declaration's line, the display on")
eq(W.declaredLine(device: "iPad (iPad14,1)", activity: .connect, asleepNow: true),
   "Declared activity for iPad (iPad14,1), which connected, but the display read asleep 0.5 s later.",
   "the declaration's line, the display asleep at the second look")
check(W.Activity.allCases.allSatisfy { a in
    [W.wokeLine(device: "d", activity: a), W.declaredLine(device: "d", activity: a, asleepNow: true),
     W.declaredLine(device: "d", activity: a, asleepNow: false)].allSatisfy { !$0.contains("\n") && $0.hasSuffix(".") }
}, "every line is one line, ending in a full stop")
// kIOReturnNotPrivileged, 0xe00002c1.
let notPrivileged = Int32(bitPattern: 0xe000_02c1)
eq(W.failedLine(notPrivileged),
   "Could not wake the display: macOS refused to declare user activity (IOKit error 0xe00002c1). A sleeping display stays dark until someone wakes it at the Mac.",
   "the refusal's line, its code in hex")
eq(W.failedLine(1), "Could not wake the display: macOS refused to declare user activity (IOKit error 0x1). A sleeping display stays dark until someone wakes it at the Mac.",
   "a small code in hex")

// MARK: - What DisplayActivity says (Report)

/// One declaration through `r`, then its second look: the lines said, in order.
func declareAndLook(_ r: inout W.Report, device: String = "iPad", activity: W.Activity = .connect, asleepBefore: Bool,
                    asleepAfter: Bool, at t: TimeInterval, result: Int32 = 0) -> [String] {
    let said = r.declared(device: device, activity: activity, wasAsleep: asleepBefore, result: result)
    var lines = said.line.map { [$0] } ?? []
    if let look = said.look, let line = r.looked(look, asleepNow: asleepAfter, at: t + W.secondLook) { lines.append(line) }
    return lines
}
do {
    var r = W.Report()
    eq(declareAndLook(&r, asleepBefore: true, asleepAfter: false, at: 0), ["Woke the display for iPad, which connected."],
       "asleep before, on at the look: the woke line")
    eq(r.wakesSaid, 1, "one wake said")
    eq(declareAndLook(&r, activity: .input, asleepBefore: false, asleepAfter: false, at: 5), [],
       "on before, a look 5 s after the woke line: nothing (the woke line was this minute's)")
    eq(declareAndLook(&r, activity: .input, asleepBefore: false, asleepAfter: false, at: 59.9), [], "a look 59.9 s after it: nothing")
    eq(declareAndLook(&r, activity: .input, asleepBefore: false, asleepAfter: false, at: 60), ["Declared activity for iPad, which sent input."],
       "a look 60 s after it: the declaration's line")
    eq(declareAndLook(&r, activity: .input, asleepBefore: false, asleepAfter: false, at: 70), [], "10 s later: nothing")
    eq(declareAndLook(&r, activity: .input, asleepBefore: true, asleepAfter: false, at: 75), ["Woke the display for iPad, which sent input."],
       "a new wake within the minute: its woke line all the same")
    eq(declareAndLook(&r, activity: .input, asleepBefore: true, asleepAfter: true, at: 200),
       ["Declared activity for iPad, which sent input, but the display read asleep 0.5 s later."],
       "asleep before and after (a closed lid, a display slow to wake): no woke line, the declaration's line")
    eq(declareAndLook(&r, activity: .input, asleepBefore: true, asleepAfter: true, at: 205), [], "again 5 s later: nothing")
    eq(declareAndLook(&r, activity: .input, asleepBefore: true, asleepAfter: true, at: 100), ["Declared activity for iPad, which sent input, but the display read asleep 0.5 s later."],
       "the clock set back: the line is not held off")
}
do {
    // Two declarations made before the panel came on (two devices, a move's second connection): one wake.
    var r = W.Report()
    let a = r.declared(device: "iPad", activity: .connect, wasAsleep: true, result: 0)
    let b = r.declared(device: "iPhone", activity: .connect, wasAsleep: true, result: 0)
    eq(a.line, nil, "the first declaration: nothing until its look")
    eq(b.line, nil, "the second: nothing until its look")
    eq(r.looked(a.look!, asleepNow: false, at: 0.5), "Woke the display for iPad, which connected.", "the first look: the woke line")
    eq(r.looked(b.look!, asleepNow: false, at: 0.51), nil, "the second look, the same wake: no second woke line")
    eq(r.wakesSaid, 1, "one wake said for the two")
    let c = r.declared(device: "iPhone", activity: .input, wasAsleep: true, result: 0)
    eq(r.looked(c.look!, asleepNow: false, at: 30), "Woke the display for iPhone, which sent input.",
       "a declaration made after the woke line, asleep before and on after: a wake of its own")
}
do {
    // The first declaration's look finds the display still asleep, the second's on: the wake is the second's.
    var r = W.Report()
    let a = r.declared(device: "iPad", activity: .connect, wasAsleep: true, result: 0)
    let b = r.declared(device: "iPhone", activity: .connect, wasAsleep: true, result: 0)
    eq(r.looked(a.look!, asleepNow: true, at: 0.5), "Declared activity for iPad, which connected, but the display read asleep 0.5 s later.",
       "a look before the panel is on: the declaration's line")
    eq(r.looked(b.look!, asleepNow: false, at: 0.7), "Woke the display for iPhone, which connected.", "the next look finds it on: the wake")
}
do {
    var r = W.Report()
    let refused = r.declared(device: "iPad", activity: .connect, wasAsleep: true, result: notPrivileged)
    eq(refused.line, W.failedLine(notPrivileged), "refused: the refusal's line at once")
    eq(refused.look, nil, "refused: no second look")
    check(r.saidFailure, "the refusal noted")
    let again = r.declared(device: "iPad", activity: .input, wasAsleep: true, result: notPrivileged)
    eq(again.line, nil, "refused again: nothing")
    eq(again.look, nil, "refused again: no look")
    let ok = r.declared(device: "iPad", activity: .input, wasAsleep: false, result: 0)
    check(!r.saidFailure && ok.line == nil && ok.look != nil, "a declaration that went through clears the refusal, and is looked at again")
    eq(r.declared(device: "iPad", activity: .input, wasAsleep: true, result: notPrivileged).line, W.failedLine(notPrivileged),
       "refused after a success: said again")
    var first = W.Report()
    eq(first.declared(device: "iPad", activity: .launch, wasAsleep: false, result: 1).line, W.failedLine(1), "a first refusal is said")
}

// MARK: - The TEST ONLY user type

func userActive(_ value: String?, testHost: Bool = false) -> (remote: Bool, line: String?) {
    W.userActive(environment: value.map { [W.userActiveVariable: $0] } ?? [:], testHost: testHost)
}
check(userActive(nil) == (false, nil), "unset: local, no line")
check(userActive("") == (false, nil), "empty: as unset")
check(userActive("remote") == (true, "TEST: user activity is declared as remote (kIOPMUserActiveRemote), not local (SILL_TEST_USER_ACTIVE=remote)."),
      "remote on a real host (Sill.app too): remote, and a TEST line")
check(userActive("local") == (false, "TEST: user activity is declared as local (kIOPMUserActiveLocal), as without SILL_TEST_USER_ACTIVE."),
      "local: local, and a TEST line")
do {
    let odd = userActive("Remote\nWoke the display for nobody.")
    check(!odd.remote, "another value: local")
    check(odd.line == "SILL_TEST_USER_ACTIVE ignored: it takes local or remote; user activity is declared as local.",
          "another value: ignored with one line that does not echo it")
    check(userActive("remote", testHost: true) == (false, "SILL_TEST_USER_ACTIVE ignored: a test host declares no user activity (it counts disp.wakeDry)."),
          "remote on a test host: ignored, with one line")
    check(W.userActive(environment: ["SILL_TEST_USERACTIVE": "remote"], testHost: false) == (false, nil), "another variable: nothing")
}

// MARK: - 20,000 random sessions: the rule

/// SplitMix64: the same sessions every run.
struct Rng {
    var s: UInt64
    mutating func next() -> UInt64 {
        s &+= 0x9E37_79B9_7F4A_7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func below(_ n: Int) -> Int { Int(next() % UInt64(n)) }
}

var rng = Rng(s: 0x5111_134)
var violations: [String: Int] = [:], firstViolation: [String: String] = [:]
func violated(_ what: String, _ detail: String) {
    violations[what, default: 0] += 1
    if firstViolation[what] == nil { firstViolation[what] = detail }
}
/// The documented numbers, written out: the invariants do not take them from the rule.
let five: TimeInterval = 5, two: TimeInterval = 2
/// The model's own table of what is a person at the device.
func isPerson(_ event: W.Event, now: TimeInterval, lastChange: TimeInterval?) -> Bool {
    switch event {
    case .connect: return true
    case .message(let kind, let input):
        switch kind.rawValue {
        case 7, 15, 25, 28: return true
        case 8:
            guard let input else { return false }
            if case .pointer(.move, _, _) = input, let c = lastChange, now >= c, now - c < two { return false }
            return true
        default: return false
        }
    }
}
let otherKinds: [Kind] = (0...255).compactMap { Kind(rawValue: UInt8($0)) }.filter { ![7, 8, 15, 25, 28].contains($0.rawValue) }
var steps = 0, declared = 0, counted = 0, heldOff = 0, clockBacks = 0, streamed = 0, own = 0, ownMoves = 0, changes = 0
for session in 0..<20_000 {
    let testHost = rng.below(4) == 0
    var w = W(testHost: testHost)
    var now = rng.unit() * 1_000_000
    var lastDecl: TimeInterval?            // the model's own: when the last declaration (or count) was made
    var lastChange: TimeInterval?          // and the host's last stream change
    var lastPersonAt: TimeInterval?        // the last person's activity, with no clock set back since
    // A person's activity that keeps coming: no gap over `streamGap` (I5).
    let streamGap = 0.05 + rng.unit() * 3
    for _ in 0..<(5 + rng.below(60)) {
        // The next step's time: gaps from milliseconds to minutes, activity that keeps coming within
        // `streamGap`, and now and then the clock set back.
        let gap: TimeInterval
        let kind = rng.below(100)
        if kind < 3 {
            gap = -(rng.unit() * 600)
        } else if kind < 60 {
            gap = rng.unit() * streamGap
        } else if kind < 90 {
            gap = rng.unit() * 12
        } else {
            gap = rng.unit() * 900
        }
        now += gap
        steps += 1
        if gap < 0 { clockBacks += 1; lastPersonAt = nil }
        // Now and then the host's stream restarts or sends a new frame size.
        if rng.below(100) < 6 {
            w.streamChanged(at: now)
            lastChange = now
            changes += 1
            if w.streamChangedAt != now { violated("the rule's stream change is not the model's", "session \(session) at \(now)") }
            continue
        }
        // The event: mostly input, often a bare move (a re-centre when the stream just changed).
        let roll = rng.below(100)
        let event: W.Event
        switch roll {
        case ..<6: event = .connect
        case ..<16: event = msg(.selectSource)
        case ..<24: event = msg(otherKinds[rng.below(otherKinds.count)], rng.below(2) == 0 ? tap : nil)
        case ..<26: event = msg(.input)
        case ..<29: event = msg(.launchApp)
        case ..<35: event = msg([Kind.windowCommand, .pressMenuItem, .gesture][rng.below(3)])
        case ..<65: event = msg(.input, rng.below(3) == 0 ? recentred : move)
        default: event = msg(.input, events[rng.below(events.count)].0)
        }
        let personNow = isPerson(event, now: now, lastChange: lastChange)
        let detail = "session \(session) (test host \(testHost)): \(event) at \(now), last \(lastDecl.map { "\($0)" } ?? "none"), change \(lastChange.map { "\($0)" } ?? "none")"
        // I5, before the decision: through a person's activity that keeps coming, never more than 5 s + the
        // gap since the last declaration.
        if personNow, event != .connect, let prev = lastPersonAt, now - prev >= 0, now - prev <= streamGap, let last = lastDecl {
            streamed += 1
            if now - last > five + streamGap { violated("I5 a person's activity kept coming and the display was not kept on", detail) }
        }
        let d = w.decide(event, at: now)
        let said = detail + ": \(d)"
        // I4
        if testHost, case .declare = d { violated("I4 a test host declared", said) }
        if !testHost, d == .count { violated("I4 a real host counted", said) }
        let acted = d != .nothing
        if !personNow {
            // I6
            own += 1
            if case .message(.input, let input?) = event, case .pointer(.move, _, _) = input { ownMoves += 1 }
            if acted { violated("I6 the device's own message declared or counted", said) }
        } else if event == .connect {
            // I1
            if !acted { violated("I1 a connect that did not declare", said) }
        } else if let last = lastDecl {
            // I2, I3
            if acted, now >= last, now - last < five { violated("I2 two declarations under 5 s apart", said) }
            if !acted, now - last >= five { violated("I3 a due declaration held off", said) }
            if !acted, now < last { violated("I3 a clock set back held a declaration off", said) }
        } else if !acted {
            violated("I3 the first declaration held off", said)
        }
        if case .declare(let activity) = d, (activity == .connect) != (event == .connect) {
            violated("a declaration for the wrong activity", said)
        }
        if personNow { lastPersonAt = now }
        if acted {
            lastDecl = now
            if testHost { counted += 1 } else { declared += 1 }
        } else if personNow {
            heldOff += 1
        }
        // The rule's own record agrees with the model's.
        if w.lastDeclared != lastDecl { violated("the rule's last declaration is not the model's", said) }
    }
}
for (what, count) in violations.sorted(by: { $0.key < $1.key }) {
    check(false, "\(what): \(count) times; first: \(firstViolation[what] ?? "")")
}
check(violations.isEmpty && declared > 50_000 && counted > 15_000 && heldOff > 100_000 && clockBacks > 10_000 && streamed > 100_000
      && own > 100_000 && ownMoves > 5_000 && changes > 30_000,
      "20,000 random sessions, \(steps) steps (\(declared) declared, \(counted) counted on test hosts, \(heldOff) held off, "
      + "\(own) the device's own, \(ownMoves) of them its moves after \(changes) stream changes, \(clockBacks) clocks set back, "
      + "\(streamed) of a person's that kept coming): every invariant")

// MARK: - 20,000 random sessions: what DisplayActivity says

violations = [:]; firstViolation = [:]
var looks = 0, wokeLines = 0, sharedWakes = 0, declaredLines = 0, quiet = 0, refusals = 0, refusalLines = 0, wallBacks = 0
for session in 0..<20_000 {
    var r = W.Report()
    // The queue's own clock (asyncAfter's DispatchTime: it never goes back) and the wall clock the lines
    // are timed by (CFAbsoluteTimeGetCurrent), set back now and then.
    var rt = 0.0
    var offset = rng.unit() * 1_000_000
    var asleep = rng.below(2) == 0                  // the main display, as CGDisplayIsAsleep reads it
    var wakeAt: Double?                              // when a declaration's wake turns it on (queue clock)
    var pending: [(look: W.Report.Look, due: Double, index: Int)] = []
    var index = 0, lastWokeIndex = -1               // the queue's order: declarations and looks
    var lastLineAt: TimeInterval?                    // the model's own: the last woke or declared line
    var refusedSinceSuccess = false
    let lidClosed = rng.below(8) == 0                // a display no declaration wakes
    let total = 5 + rng.below(40)
    var made = 0
    func readAsleep() -> Bool {
        if let w = wakeAt, rt >= w { asleep = false; wakeAt = nil }
        return asleep
    }
    while made < total || !pending.isEmpty {
        let gap = rng.below(3) == 0 ? rng.unit() * 0.6 : rng.unit() * 90
        if let first = pending.min(by: { $0.due < $1.due }), first.due <= rt + gap || made >= total {
            // A look that is due before the next thing happens.
            pending.removeAll { $0.index == first.index }
            rt = max(rt, first.due)
            index += 1
            let a = readAsleep()
            let now = rt + offset
            looks += 1
            let line = r.looked(first.look, asleepNow: a, at: now)
            let detail = "session \(session): look of #\(first.index) at \(now) (asleep before \(first.look.wasAsleep), now \(a)): \(line ?? "nothing")"
            let isWoke = line?.hasPrefix("Woke the display") ?? false
            let wake = first.look.wasAsleep && !a && first.index > lastWokeIndex
            // R1, R2, R3
            if isWoke, !(first.look.wasAsleep && !a) { violated("R1 a woke line for a display that did not wake", detail) }
            if isWoke, first.index < lastWokeIndex { violated("R2 two woke lines for one wake", detail) }
            if wake, !isWoke { violated("R3 a wake not said", detail) }
            if isWoke, line != W.wokeLine(device: first.look.device, activity: first.look.activity) { violated("R1 the wrong woke line", detail) }
            if first.look.wasAsleep, !a, !wake { sharedWakes += 1 }
            // R4
            if !isWoke {
                let allowed = lastLineAt.map { now < $0 || now - $0 >= 60 } ?? true
                if line != nil, !allowed { violated("R4 a declaration's line under a minute after the last", detail) }
                if line == nil, allowed { violated("R4 a declaration's line held off", detail) }
                if let line, line != W.declaredLine(device: first.look.device, activity: first.look.activity, asleepNow: a) {
                    violated("R4 the wrong line", detail)
                }
                if line != nil { declaredLines += 1 } else { quiet += 1 }
            }
            if line != nil { lastLineAt = now }
            if isWoke { lastWokeIndex = index; wokeLines += 1 }
            continue
        }
        rt += gap
        made += 1
        if rng.below(100) < 3 { offset -= rng.unit() * 300; wallBacks += 1 }   // the wall clock set back
        if rng.below(10) == 0 { asleep = true; wakeAt = nil; continue }        // the display goes to sleep
        index += 1
        let a = readAsleep()
        let failed = rng.below(12) == 0
        let result: Int32 = failed ? notPrivileged : 0
        let said = r.declared(device: ["iPad", "iPhone"][rng.below(2)], activity: W.Activity.allCases[rng.below(W.Activity.allCases.count)],
                              wasAsleep: a, result: result)
        let detail = "session \(session): declaration #\(index) at \(rt + offset) (failed \(failed)): \(said.line ?? "nothing")"
        // R5
        if failed {
            refusals += 1
            if said.look != nil { violated("R5 a refusal looked at again", detail) }
            if refusedSinceSuccess, said.line != nil { violated("R5 a refusal said twice", detail) }
            if !refusedSinceSuccess, said.line != W.failedLine(result) { violated("R5 a refusal not said", detail) }
            if said.line != nil { refusalLines += 1 }
            refusedSinceSuccess = true
        } else {
            refusedSinceSuccess = false
            if said.line != nil { violated("R5 a line before the look", detail) }
            guard let look = said.look else { violated("R5 a declaration that went through with no look", detail); continue }
            pending.append((look, rt + W.secondLook, index))
            // A declaration wakes a sleeping display a little before or after its look, unless the lid is closed.
            if a, !lidClosed, wakeAt == nil { wakeAt = rt + [0.05, 0.3, 0.45, 0.8, 2.5][rng.below(5)] }
        }
    }
}
for (what, count) in violations.sorted(by: { $0.key < $1.key }) {
    check(false, "\(what): \(count) times; first: \(firstViolation[what] ?? "")")
}
check(violations.isEmpty && wokeLines > 5_000 && sharedWakes > 500 && declaredLines > 20_000 && quiet > 10_000 && refusalLines > 2_000
      && wallBacks > 5_000,
      "20,000 random sessions of DisplayActivity, \(looks) looks (\(wokeLines) woke lines, \(sharedWakes) wakes already said, "
      + "\(declaredLines) other lines, \(quiet) held to the minute; \(refusals) refusals, \(refusalLines) said; "
      + "\(wallBacks) wall clocks set back): every invariant")

print(failures == 0 ? "ok: \(passes) checks" : "FAILED: \(failures) of \(passes + failures) checks")
exit(failures == 0 ? 0 : 1)
