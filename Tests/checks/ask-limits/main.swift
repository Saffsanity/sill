// H3 (step 1): AskLimits (PairingWindow.swift), pure, compiled with StreamProtocol's sources as one
// module: one window at a time is the ask rule's (the door check); here 10 minutes of quiet by key
// and by address, 3 device-opened windows in any 10 minutes, which closes quiet their asker
// (cancelled on the Mac and stopped; not used, not expired, not withdrawn by its device: the
// security review, 2026-09-27), the reason a proof turned away closed hears, and the test override.
import Foundation
var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) { if ok { passes += 1; print("ok   \(name)") } else { fails += 1; print("FAIL \(name)") }; fflush(stdout) }
let keyA = Data([0xA]), keyB = Data([0xB]), keyC = Data([0xC])
let x = "fe80::1c0f:2a:6e1:9b3", y = "10.128.0.41", z = "2601:600::77"

check("the constants: 600 s of quiet, a 600 s span, 3 windows", AskLimits.quietFor == 600 && AskLimits.span == 600 && AskLimits.maxWindows == 3)
var l = AskLimits()
check("default: both 600 s", l.quietSeconds == 600 && l.spanSeconds == 600)
check("fresh: nobody is quiet, no recent windows", !l.quiet(fingerprint: keyA, source: x, now: 0) && l.recentWindows(now: 0) == 0)

// Quiet, by key and by address.
l.closedUnused(fingerprint: keyA, source: x, now: 100)
check("closed unused: that key from that address is quiet", l.quiet(fingerprint: keyA, source: x, now: 100))
check("by key: the same key from another address is quiet", l.quiet(fingerprint: keyA, source: y, now: 200))
check("by address: another key from the same address is quiet", l.quiet(fingerprint: keyB, source: x, now: 200))
check("another key from another address is not", !l.quiet(fingerprint: keyB, source: y, now: 200))
check("quiet for 10 minutes: at 699.9 s yes, at 700 s no", l.quiet(fingerprint: keyA, source: x, now: 699.9) && !l.quiet(fingerprint: keyA, source: x, now: 700)
      && !l.quiet(fingerprint: keyB, source: x, now: 700) && !l.quiet(fingerprint: keyA, source: y, now: 700))
check("quietSince: when the window closed", l.quietSince(fingerprint: keyA, source: y, now: 280) == 100 && l.quietSince(fingerprint: keyB, source: y, now: 280) == nil)
l.closedUnused(fingerprint: keyB, source: y, now: 400)
check("quietSince: the later of the key's and the address's", l.quietSince(fingerprint: keyA, source: y, now: 450) == 400
      && l.quietSince(fingerprint: keyB, source: x, now: 450) == 400 && l.quietSince(fingerprint: keyA, source: x, now: 450) == 100)
check("quietSince: an expired close no longer counts (A from x is free at 701; from y, y's close at 400 still counts)", l.quietSince(fingerprint: keyA, source: x, now: 701) == nil
      && l.quietSince(fingerprint: keyA, source: y, now: 701) == 400)
l.closedUnused(fingerprint: keyA, source: z, now: 800)
check("closing again restarts the key's quiet", l.quiet(fingerprint: keyA, source: "10.9.9.9", now: 1399) && !l.quiet(fingerprint: keyA, source: "10.9.9.9", now: 1400))
check("x's close at 100 no longer counts at 800 (another key from x is free)", !l.quiet(fingerprint: keyC, source: x, now: 800))

// At most 3 device-opened windows in any 10 minutes.
var w = AskLimits()
w.opened(now: 0); w.opened(now: 100); w.opened(now: 200)
check("three windows: 3 recent at 250", w.recentWindows(now: 250) == 3)
check("the first drops out at exactly 600 s", w.recentWindows(now: 599.9) == 3 && w.recentWindows(now: 600) == 2)
check("all gone after 800 s", w.recentWindows(now: 800) == 0)
w.opened(now: 650)
check("a window at 650: 100, 200 and 650 count at 699", w.recentWindows(now: 699) == 3)
check("opening prunes nothing it should keep: 200 and 650 count at 750", w.recentWindows(now: 750) == 2)
check("opened windows do not make anyone quiet", !w.quiet(fingerprint: keyA, source: x, now: 700))

// Which closes quiet the asker.
check("quiets: a window the Mac's user cancelled, and one stopped by five wrong codes", AskLimits.quiets(.cancelled) && AskLimits.quiets(.stopped))
check("quiets: not a window a device paired with, nor none", !AskLimits.quiets(.used) && !AskLimits.quiets(.none))
check("quiets: not a window that simply ran out (its device's next tap gets a fresh code, as its words say)", !AskLimits.quiets(.expired))
check("quiets: not a window its own device withdrew (its Cancel, or paired over the cable)", !AskLimits.quiets(.withdrawn))

// What a proof turned away closed hears (kind 20's reason), which the device's words follow.
typealias W = PairingWindow
check("closed: the proof that stopped the window hears stopped; a later one closed",
      W.closedReason(.stopped, stoppedByThisProof: true) == "stopped" && W.closedReason(.stopped, stoppedByThisProof: false) == "closed")
check("closed: after its time ran out, expired, whether or not this proof noticed it",
      W.closedReason(.expired, stoppedByThisProof: true) == "expired" && W.closedReason(.expired, stoppedByThisProof: false) == "expired")
check("closed: used, cancelled, withdrawn and none hear closed",
      [W.CloseReason.used, .cancelled, .withdrawn, .none].allSatisfy { W.closedReason($0, stoppedByThisProof: true) == "closed" && W.closedReason($0, stoppedByThisProof: false) == "closed" })

// The window itself: its device's Cancel (withdrawn) closes it, and a later proof hears closed.
var win = PairingWindow()
win.open(secret: Data(repeating: 1, count: 16), code: "000000000000", now: 0, requestedBy: "iPad", byDevice: .init(fingerprint: keyA, source: x), forRemote: false)
win.close(.withdrawn)
check("withdrawn: the window is closed, and says why", !win.isOpen && win.closeReason == .withdrawn)
if case .closed(let r) = win.tryProof(method: "qr", proof: Data(), fpDevice: keyA, fpMac: keyB, source: x, now: 1) {
    check("withdrawn: a later proof is turned away closed, with no try counted", W.closedReason(r, stoppedByThisProof: false) == "closed")
} else { check("withdrawn: a later proof is turned away closed", false) }

// The test override.
let t = AskLimits(seconds: 5)
check("SILL_TEST_ASK_QUIET's seconds replace both 600 s", t.quietSeconds == 5 && t.spanSeconds == 5)
var t2 = AskLimits(seconds: 5)
t2.closedUnused(fingerprint: keyA, source: x, now: 0); t2.opened(now: 0)
check("with 5 s: quiet at 4.9, not at 5; the window counts at 4.9, not at 5",
      t2.quiet(fingerprint: keyA, source: x, now: 4.9) && !t2.quiet(fingerprint: keyA, source: x, now: 5)
      && t2.recentWindows(now: 4.9) == 1 && t2.recentWindows(now: 5) == 0)
let env = ["SILL_TEST_ASK_QUIET": "5"]
check("SILL_TEST_ASK_QUIET on a test host", AskLimits.testSeconds(testHost: true, environment: env) == 5
      && AskLimits.testSeconds(testHost: true, environment: ["SILL_TEST_ASK_QUIET": "2.5"]) == 2.5)
check("SILL_TEST_ASK_QUIET ignored by a host that is not a test host", AskLimits.testSeconds(testHost: false, environment: env) == nil)
check("SILL_TEST_ASK_QUIET: a positive finite number only",
      ["0", "-1", "abc", "", "inf", "nan", "1e400"].allSatisfy { AskLimits.testSeconds(testHost: true, environment: ["SILL_TEST_ASK_QUIET": $0]) == nil }
      && AskLimits.testSeconds(testHost: true, environment: [:]) == nil)
check("AskLimits(seconds: nil) is the default", AskLimits(seconds: nil).quietSeconds == 600 && AskLimits(seconds: nil).spanSeconds == 600)

print(fails == 0 ? "ALL PASS (\(passes))" : "\(fails) FAIL, \(passes) pass")
if fails > 0 { exit(1) }
