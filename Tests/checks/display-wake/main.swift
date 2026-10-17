// docs/display-wake-plan.md: Sources/SillHost/DisplayWakePolicy.swift on its own, compiled by build.sh:
//
//   Tests/checks/display-wake/build.sh . .build/checks/display-wake/check && .build/checks/display-wake/check
//
// What it checks: a connect always declares (the wake), the first activity declares, activity within
// `interval` of the last declaration does not, at exactly `interval` it does, a connect inside the
// interval still does and restarts it, `allLeft` makes the next activity declare at once, a clock that
// goes back never silences it, the interval under a minute (macOS's shortest display sleep); then a
// model of the rule against 20,000 random runs.
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)
var failures = 0
func check(_ ok: Bool, _ what: String) {
    print("\(ok ? "ok" : "FAIL") \(what)")
    if !ok { failures += 1 }
}
func eq<T: Equatable>(_ a: T, _ b: T, _ what: String) { check(a == b, "\(what): \(a)" + (a == b ? "" : " (want \(b))")) }

let i = DisplayWakePolicy.interval
check(i == 10, "the interval is 10 s")
check(i < 60, "the interval is under macOS's shortest display sleep")

do {
    var p = DisplayWakePolicy()
    eq(p.lastDeclared, nil, "nothing declared at first")
    eq(p.declares(.activity, now: 100), true, "the first activity declares")
    eq(p.lastDeclared, 100, "and is noted")
    eq(p.declares(.activity, now: 101), false, "activity a second later does not")
    eq(p.declares(.activity, now: 100 + i - 0.001), false, "nor just under the interval")
    eq(p.lastDeclared, 100, "a refusal notes nothing")
    eq(p.declares(.activity, now: 100 + i), true, "at exactly the interval it declares")
    eq(p.declares(.activity, now: 100 + i + 1), false, "and the interval runs from there")
}
do {
    var p = DisplayWakePolicy()
    eq(p.declares(.connected, now: 5), true, "a connect declares")
    eq(p.declares(.connected, now: 5.5), true, "a second device's connect half a second later declares too")
    eq(p.declares(.activity, now: 6), false, "activity inside the interval after a connect does not")
    eq(p.declares(.activity, now: 5.5 + i), true, "the interval runs from the last connect")
}
do {
    var p = DisplayWakePolicy()
    _ = p.declares(.activity, now: 50)
    p.allLeft()
    eq(p.lastDeclared, nil, "allLeft forgets the last declaration")
    eq(p.declares(.activity, now: 51), true, "the next activity after allLeft declares at once")
}
do {
    var p = DisplayWakePolicy()
    _ = p.declares(.activity, now: 1000)
    eq(p.declares(.activity, now: 10), true, "a clock that went back never silences it")
    eq(p.lastDeclared, 10, "and the declaration is noted at the new time")
}

// The model: a connect always declares; activity declares when nothing was declared since the last
// allLeft, when the interval has passed, or when the clock went back.
var rng = SystemRandomNumberGenerator()
var mismatches = 0, declared = 0, steps = 0
for _ in 0..<20_000 {
    var p = DisplayWakePolicy()
    var last: TimeInterval? = nil
    var now: TimeInterval = Double.random(in: 0...1000, using: &rng)
    for _ in 0..<Int.random(in: 1...30, using: &rng) {
        now += Bool.random(using: &rng) ? Double.random(in: 0...25, using: &rng) : -Double.random(in: 0...5, using: &rng)
        let roll = Int.random(in: 0..<10, using: &rng)
        steps += 1
        if roll == 0 { p.allLeft(); last = nil; continue }
        let reason: DisplayWakePolicy.Reason = roll == 1 ? .connected : .activity
        let want: Bool
        if reason == .connected { want = true } else if let l = last { want = now - l >= i || now < l } else { want = true }
        let got = p.declares(reason, now: now)
        if want { last = now; declared += 1 }
        if got != want || p.lastDeclared != last { mismatches += 1 }
    }
}
check(mismatches == 0, "20,000 random runs (\(steps) steps, \(declared) declarations) against the model: \(mismatches) mismatches")

print(failures == 0 ? "display-wake: all passed" : "display-wake: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
