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

print(fails == 0 ? "ok: \(passes) checks" : "FAILED: \(fails) of \(passes + fails) checks")
exit(fails == 0 ? 0 : 1)
