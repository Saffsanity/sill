// KeyframeRecovery (iOSClient): when the device asks the Mac for a fresh picture after its display
// layer was interrupted. Compiled with iOSClient/KeyframeRecovery.swift alone (run.sh).
import Foundation

var failures = 0, checks = 0
func check(_ ok: Bool, _ what: String) {
    checks += 1
    if ok { print("ok   \(what)") } else { failures += 1; print("FAIL \(what)") }
}

var r = KeyframeRecovery()
check(!r.shouldAsk(streaming: false, now: 100), "nothing streams: no ask")
check(r.shouldAsk(streaming: true, now: 100), "a stream, first time: ask")
check(!r.shouldAsk(streaming: true, now: 100.5), "0.5 s later: no second ask")
check(!r.shouldAsk(streaming: true, now: 101.99), "just under 2 s later: still none")
check(r.shouldAsk(streaming: true, now: 102), "2 s later: ask again")
check(!r.shouldAsk(streaming: true, now: 103), "1 s after that: none")

var idle = KeyframeRecovery()
check(!idle.shouldAsk(streaming: false, now: 50), "nothing streams")
check(idle.shouldAsk(streaming: true, now: 50.1), "a refused ask (nothing streamed) does not hold back the next")

var clock = KeyframeRecovery()
check(clock.shouldAsk(streaming: true, now: 200), "an ask")
check(clock.shouldAsk(streaming: true, now: 10), "the clock went back (a new boot's uptime): ask")

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
