// DeviceIdlePolicy (iOSClient/DeviceIdlePolicy.swift): when Sill holds the device's own auto-lock off
// (PR #230, towards issue #134). Compiled on its own with swiftc (run.sh).
//
// What it checks: the limit; no window, a window in the background, one not streaming, one never used:
// nothing held; a window in front streaming: held until 10 minutes after its last use, not at exactly
// 10 minutes; two windows: the later end, one in front enough, one in the background or not streaming
// never extending it; a window that closed (absent from the list) holds nothing; a limit given for one
// run; then 20,000 random sets of windows against the invariants:
//   D1 held exactly when some window in front, streaming and used, was used less than the limit ago;
//   D2 the end is the latest of those windows' last use plus the limit, and after now;
//   D3 a window in the background, not streaming or never used changes nothing, wherever it is listed;
//   D4 the list's order changes nothing.
// Then what counts as the person's use (`lastUse`, `sessionStart`: the verification's N1, 2026-10-29):
// the latest of the four, a session's start only as the person started it and carried across the
// automatic reconnect's; the N1 cases through a model of DeviceIdleTimer's stamps (a link that keeps
// dropping and coming back by itself, a Mac that keeps stopping its capture and the device asking
// again, the device's own pointer re-centre, each held for good by the rule before); then 20,000
// random lives of one window against:
//   D5 the hold ends exactly at the person's latest use plus the limit (a session the person started,
//      input the person sent, a control, the window coming to the front), never at anything the
//      device did by itself, and only while the window streams in front.
import Foundation

var fails = 0, passes = 0
func check(_ what: String, _ ok: Bool) {
    if ok { passes += 1; print("ok   \(what)") } else { fails += 1; print("FAIL \(what)") }
}
func eq<T: Equatable>(_ a: T, _ b: T, _ what: String) { check("\(what): \(a)" + (a == b ? "" : " (want \(b))"), a == b) }

typealias P = DeviceIdlePolicy
typealias Win = DeviceIdlePolicy.Window
func win(_ front: Bool = true, _ streaming: Bool = true, used: Double? = 100) -> Win {
    Win(foregroundActive: front, streaming: streaming, lastUsedAt: used)
}

eq(P.idleLimit, 600, "auto-lock held off for 10 minutes after the last use")
eq(P.holdEnds([], now: 100), nil, "no window: nothing held")
eq(P.holdEnds([win(used: 100)], now: 100), 700, "a window in front, streaming, used now: held until 10 minutes on")
eq(P.holdEnds([win(used: 100)], now: 699.9), 700, "9 min 59.9 s later: still held")
eq(P.holdEnds([win(used: 100)], now: 700), nil, "exactly 10 minutes later: the device's own auto-lock again")
eq(P.holdEnds([win(used: 100)], now: 5000), nil, "an hour later: nothing held")
eq(P.holdEnds([win(false, used: 100)], now: 100), nil, "a window in the background (Split View's other side, the app away): nothing held")
eq(P.holdEnds([win(true, false, used: 100)], now: 100), nil, "a window in front that does not stream (connecting, the Mac stopped it): nothing held")
eq(P.holdEnds([win(used: nil)], now: 100), nil, "a window never used: nothing held")
eq(P.holdEnds([win(used: 100), win(used: 400)], now: 500), 1000, "two windows streaming in front: the later use's end")
eq(P.holdEnds([win(used: 400), win(used: 100)], now: 500), 1000, "in either order")
eq(P.holdEnds([win(used: 100), win(false, used: 450)], now: 500), 700, "a window in the background used later does not extend it")
eq(P.holdEnds([win(used: 100), win(true, false, used: 450)], now: 500), 700, "nor one that stopped streaming")
eq(P.holdEnds([win(false, used: 450), win(used: 100)], now: 800), nil, "the one in front idle 11 minutes, the other in the background: nothing held")
eq(P.holdEnds([win(false, used: 100), win(true, false, used: 100)], now: 100), nil,
   "one window streaming in the background, the other in front not streaming: nothing held")
// One window's stream screen going away while another's session goes on: the caller lists what is open.
eq(P.holdEnds([win(used: 300)], now: 400), 900, "the second window still streaming after the first closed: held")
eq(P.holdEnds([win(used: 100)], now: 100, limit: 20), 120, "a limit for one run (DEBUG -SillIdleLimit): 20 s")
eq(P.holdEnds([win(used: 100)], now: 120, limit: 20), nil, "and it ends then")

// 20,000 random sets of windows.
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
var rng = Rng(s: 0x230_134)
let limit: Double = 600            // the documented number, written out
var violations: [String: Int] = [:], first: [String: String] = [:]
func violated(_ what: String, _ detail: String) { violations[what, default: 0] += 1; if first[what] == nil { first[what] = detail } }
var held = 0, notHeld = 0
for set in 0..<20_000 {
    let now = 10_000 + rng.unit() * 1_000_000
    let windows: [Win] = (0..<rng.below(5)).map { _ in
        let used: Double? = rng.below(8) == 0 ? nil : now - rng.unit() * 1_500
        return win(rng.below(3) != 0, rng.below(3) != 0, used: used)
    }
    let ends = P.holdEnds(windows, now: now)
    let detail = "set \(set) at \(now): \(windows) -> \(ends.map { "\($0)" } ?? "nothing")"
    let holding = windows.filter { $0.foregroundActive && $0.streaming && $0.lastUsedAt != nil }
    let want = holding.map { $0.lastUsedAt! + limit }.max().flatMap { $0 > now ? $0 : nil }
    if (ends != nil) != (want != nil) { violated("D1 held when it should not be, or not when it should", detail) }
    if ends != want { violated("D2 the end is not the latest use plus the limit", detail) }
    if let e = ends, e <= now { violated("D2 an end not after now", detail) }
    // D3: a window that holds nothing, added anywhere.
    var more = windows
    more.insert(win(false, rng.below(2) == 0, used: now), at: rng.below(more.count + 1))
    more.insert(win(true, false, used: now), at: rng.below(more.count + 1))
    more.insert(win(true, true, used: nil), at: rng.below(more.count + 1))
    if P.holdEnds(more, now: now) != ends { violated("D3 a window that holds nothing changed it", detail) }
    if P.holdEnds(windows.reversed(), now: now) != ends { violated("D4 the order changed it", detail) }
    if ends != nil { held += 1 } else { notHeld += 1 }
}
for (what, n) in violations.sorted(by: { $0.key < $1.key }) { check("\(what): \(n) times; first: \(first[what] ?? "")", false) }
check("20,000 random sets of windows (\(held) held, \(notHeld) not): every invariant", violations.isEmpty && held > 3_000 && notHeld > 3_000)

// What counts as the person's use (N1).
typealias Uses = DeviceIdlePolicy.Uses
eq(P.lastUse(Uses(input: nil, control: nil, session: nil, front: nil)), nil, "no use at all: none")
eq(P.lastUse(Uses(input: 5, control: nil, session: nil, front: nil)), 5, "input the person sent alone")
eq(P.lastUse(Uses(input: nil, control: 6, session: nil, front: nil)), 6, "a stream screen's control alone")
eq(P.lastUse(Uses(input: nil, control: nil, session: 7, front: nil)), 7, "a session's start alone")
eq(P.lastUse(Uses(input: nil, control: nil, session: nil, front: 8)), 8, "the window coming to the front alone")
eq(P.lastUse(Uses(input: 5, control: 9, session: 3, front: 1)), 9, "the latest of the four: a control")
eq(P.lastUse(Uses(input: 9, control: 5, session: 3, front: 1)), 9, "the latest of the four: input")
eq(P.lastUse(Uses(input: 1, control: 5, session: 9, front: 3)), 9, "the latest of the four: a session's start")
eq(P.lastUse(Uses(input: 1, control: 5, session: 3, front: 9)), 9, "the latest of the four: the front")
eq(P.sessionStart(previous: nil, reconnected: false, now: 50), 50,
   "a session the person started (a tap, Connect Remotely, a pairing): its start counts")
eq(P.sessionStart(previous: 10, reconnected: false, now: 50), 50, "a new one the person started counts from its own start")
eq(P.sessionStart(previous: 10, reconnected: true, now: 50), 10,
   "the automatic reconnect's: the start of the session it reconnects, never its own")
eq(P.sessionStart(previous: nil, reconnected: true, now: 50), nil, "the automatic reconnect's after none: none")

// A model of DeviceIdleTimer's stamps for one window in front (StreamScreen.swift), with the rule
// before this fix beside it (`before`: the moment it began streaming, reset whenever it stopped, and
// every input the device sent, its own re-centre too).
struct Life {
    var uses = Uses(input: nil, control: nil, session: nil, front: 0)
    var connected = false, streaming = false, front = true
    var beganStreaming: Double? = nil, anyInput: Double? = nil      // the rule before
    var personLatest: Double? = 0                                     // the oracle: the person's latest use
    mutating func personConnects(_ t: Double) {
        uses.session = P.sessionStart(previous: uses.session, reconnected: false, now: t); personLatest = t
        connected = true; streams(t)
    }
    mutating func reconnectsByItself(_ t: Double) {                   // the link dropped and came back
        connected = false; streaming = false; beganStreaming = nil
        uses.session = P.sessionStart(previous: uses.session, reconnected: true, now: t)
        connected = true; streams(t)
    }
    mutating func macStopsAndDeviceAsksAgain(_ t: Double) {           // no session start: active blinks
        streaming = false; beganStreaming = nil; streams(t)
    }
    mutating func streams(_ t: Double) { streaming = connected; if streaming, beganStreaming == nil { beganStreaming = t } }
    mutating func recentres(_ t: Double) { anyInput = t }             // the device's own input: no person's stamp
    mutating func personInput(_ t: Double) { uses.input = t; anyInput = t; personLatest = t }
    mutating func personControl(_ t: Double) { uses.control = t; personLatest = t }
    mutating func toBackground() { front = false; uses.front = nil }
    mutating func toFront(_ t: Double) { front = true; uses.front = t; personLatest = t }
    mutating func disconnects() { connected = false; streaming = false; beganStreaming = nil }
    func ends(_ now: Double) -> Double? {
        P.holdEnds([Win(foregroundActive: front, streaming: streaming, lastUsedAt: P.lastUse(uses))], now: now)
    }
    func endsBefore(_ now: Double) -> Double? {
        let used = [anyInput, uses.control, beganStreaming, uses.front].compactMap { $0 }.max()
        return P.holdEnds([Win(foregroundActive: front, streaming: streaming, lastUsedAt: used)], now: now)
    }
}
do {
    var l = Life(); l.personConnects(0)
    var held = 0, heldBefore = 0
    for k in 1...60 { let t = Double(k * 60); l.reconnectsByItself(t); if l.ends(t) != nil { held += 1 }; if l.endsBefore(t) != nil { heldBefore += 1 } }
    eq(held, 9, "N1, a link that drops and comes back by itself every minute for an hour, nobody at it: held 9 minutes after the tap, then the device's own")
    check("N1, the rule before held it at every reconnect: \(heldBefore) of 60", heldBefore == 60)
    eq(l.ends(3_600), nil, "N1, an hour on: the device's own auto-lock")
}
do {
    var l = Life(); l.personConnects(0)
    var held = 0, heldBefore = 0
    for k in 1...360 { let t = Double(k * 10); l.macStopsAndDeviceAsksAgain(t); if l.ends(t) != nil { held += 1 }; if l.endsBefore(t) != nil { heldBefore += 1 } }
    eq(held, 59, "N1, a Mac that stops its capture every 10 s and the device asking again, nobody at it: held until 10 minutes after the tap")
    check("N1, the rule before held it at every new stream: \(heldBefore) of 360", heldBefore == 360)
}
do {
    var l = Life(); l.personConnects(0)
    var held = 0, heldBefore = 0
    for k in 1...60 { let t = Double(k * 60); l.recentres(t); if l.ends(t) != nil { held += 1 }; if l.endsBefore(t) != nil { heldBefore += 1 } }
    eq(held, 9, "N1, the device's own pointer re-centre every minute (new frame sizes), nobody at it: no use")
    check("N1, the rule before held it at every re-centre: \(heldBefore) of 60", heldBefore == 60)
}
do {
    var l = Life(); l.personConnects(0)
    l.personInput(900); eq(l.ends(900), 1_500, "a tap at 15 minutes: held until 25")
    l.reconnectsByItself(1_000); eq(l.ends(1_000), 1_500, "the automatic reconnect at 16 minutes extends nothing")
    l.personControl(1_400); l.disconnects(); eq(l.ends(1_400), nil, "Disconnect: nothing held while nothing streams")
    l.personConnects(2_000); eq(l.ends(2_000), 2_600, "a tap on the Mac again: held from that session's start")
    l.reconnectsByItself(2_100); eq(l.ends(2_100), 2_600, "the automatic reconnect carries that session's start, no more")
    l.toBackground(); eq(l.ends(2_200), nil, "Sill in the background: the device's own")
    l.toFront(3_000); eq(l.ends(3_000), 3_600, "back in front: the person brought it, held 10 minutes from then")
    l.macStopsAndDeviceAsksAgain(3_500); eq(l.ends(3_500), 3_600, "the Mac's capture stopped and asked again: nothing more")
}

// D5: 20,000 random lives of one window.
var rngLife = Rng(s: 0x230_0001)
var lifeViolations: [String: Int] = [:], lifeFirst: [String: String] = [:]
var lifeHeld = 0, lifeNotHeld = 0
for life in 0..<20_000 {
    var l = Life(); var t = 0.0
    l.personConnects(0)
    var log: [String] = ["connect@0"]
    for _ in 0..<(1 + rngLife.below(30)) {
        t += 1 + rngLife.unit() * 400
        switch rngLife.below(9) {
        case 0: l.personConnects(t); log.append("connect@\(Int(t))")
        case 1: l.reconnectsByItself(t); log.append("reconnect@\(Int(t))")
        case 2: l.macStopsAndDeviceAsksAgain(t); log.append("macStop@\(Int(t))")
        case 3: l.recentres(t); log.append("recentre@\(Int(t))")
        case 4: l.personInput(t); log.append("input@\(Int(t))")
        case 5: l.personControl(t); log.append("control@\(Int(t))")
        case 6: l.toBackground(); log.append("background@\(Int(t))")
        case 7: if !l.front { l.toFront(t); log.append("front@\(Int(t))") }
        default: l.disconnects(); log.append("disconnect@\(Int(t))")
        }
        let now = t + (rngLife.below(2) == 0 ? 0 : rngLife.unit() * 900)
        let want: Double? = (l.front && l.streaming) ? l.personLatest.map { $0 + limit }.flatMap { $0 > now ? $0 : nil } : nil
        let got = l.ends(now)
        if got != want {
            let what = "D5 the hold does not end at the person's latest use plus the limit"
            lifeViolations[what, default: 0] += 1
            if lifeFirst[what] == nil { lifeFirst[what] = "life \(life): \(log.joined(separator: " ")), at \(Int(now)): \(got.map { "\($0)" } ?? "nothing") (want \(want.map { "\($0)" } ?? "nothing"))" }
        }
        if got != nil { lifeHeld += 1 } else { lifeNotHeld += 1 }
    }
}
for (what, n) in lifeViolations.sorted(by: { $0.key < $1.key }) { check("\(what): \(n) times; first: \(lifeFirst[what] ?? "")", false) }
check("20,000 random lives of one window (\(lifeHeld) looks held, \(lifeNotHeld) not): D5", lifeViolations.isEmpty && lifeHeld > 10_000 && lifeNotHeld > 10_000)

print(fails == 0 ? "ok: \(passes) checks" : "FAILED: \(fails) of \(passes + fails) checks")
exit(fails == 0 ? 0 : 1)
