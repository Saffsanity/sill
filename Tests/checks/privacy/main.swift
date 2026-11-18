// PrivacyPolicy (Sources/SillHost/PrivacyPolicy.swift; docs/privacy-mode-plan.md, part 1): Lock this Mac when the last
// device leaves (issues #283 and #275), compiled with StreamProtocol's sources and LockPolicy.swift as one module
// (module.txt), for DesktopDisplays.role and LockPolicy.Reading.
//
//   Tests/checks/privacy/run.sh             compile and run the check
//   Tests/checks/privacy/run.sh --mutants   one-line mutants of PrivacyPolicy.swift; each must fail it
//
// What it checks: the constants; who acts (`locksForReal`: Sill.app itself alone, never --synthetic; the CLI, the bare
// SillMenuBar binary and a test host make the dry run); the gate's reading as the rule reads it (`mac`: one not
// established is unknown); rule 10's displays (`typesAt`, through DesktopDisplays.role's real identities: the Mac's
// own panel and a monitor are screens, Sill's stage and Desktop displays and macOS's stand-in for a Mac with no screen
// are not); the switch off (nothing, ever); the wait (the last departure starts it, one registering ends it, the
// switch turned off ends it, a quit ends it; 2 → 1 → 0, a move that never reaches 0, the wait's boundary); its end
// (unlocked with a display: the lock; locked already, another user on the screen, a reading not established, no
// display: no lock, each with its line, the display asked only when it matters); the confirmation (the reading says
// locked, the screen locked or off console; unavailable; still unlocked after `lockConfirm`; a device back meanwhile,
// whose display never sleeps); a lock at a time; Turn off its display too off (locked: its line, no display sleep; a
// failure still sleeps it); Only after a device away from home (a visit with none away starts no wait and says so; one
// away session in the visit is enough, also one before a return within the wait; each visit starts afresh; turned on
// during a wait it ends a wait with none away, keeps one with one; turned off it starts none); what the last attempt
// left for Settings (`failure`, `warning`); a quit and a crash (a new launch's state never locks without a departure
// it saw); the TEST ONLY hooks; every word; then the rule driven as the coordinator's glue drives it (the server's
// count of registered sessions, each session's route after its count, the switches, the reading, the call answered
// later, macOS's lock showing late or never, ticks exactly while pending) through 20,000 seeded random sessions
// against the rule's invariants:
//   I1 a lock only at a wait's end: the switch on since the last departure (with Only after a device away from home,
//      a session of that visit away), no session since, not quitting, the Mac reading unlocked with a display, at
//      least `grace` and at most `grace` + a tick after that departure;
//   I2 at most one lock per departure, and never one with a lock still unconfirmed;
//   I3 every lock is followed by exactly one outcome (locked, or couldn't lock) within `lockConfirm` + a tick, unless
//      Sill quits first, its line as the reading, the sessions and Turn off its display too say;
//   I4 the displays sleep only right after a lock's outcome (locked with Turn off its display too on, or a failure),
//      and never while a session is connected;
//   I5 `pending` is a wait or a confirmation, and the glue ticks exactly while it holds;
//   I6 every departure and every switch says what the model expects, and every wait that ends on its own says why in
//      one line;
//   I7 nothing at all happens in a session whose switch was never on;
//   I8 a quit ends everything: no action after it, and a wait under way says so once.
// Which connections the server registers (a pairing connection, one the device gate refuses and one an update's hold
// sends away never do; one cut off leaves through `unregister` like any other) is StreamServer's, not this rule's: the
// rule sees only the count, and that is read in StreamServer.swift (`clients` changes in `register` and `unregister`
// alone, each calling onClientCountChanged) and run live by Scripts/privacy-check/live.py's pairing and gate cases.
import Foundation

var checks = 0, failures = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String) {
    checks += 1
    if ok { print("ok   \(what())") } else { failures += 1; print("FAIL \(what())") }
}
func same<T: Equatable>(_ got: T, _ want: T, _ what: String) {
    check(got == want, got == want ? what : "\(what): got \(got), want \(want)")
}

typealias P = PrivacyPolicy
typealias A = PrivacyPolicy.Action
typealias W = PrivacyPolicy.Words
let G = P.grace

func lines(_ actions: [A]) -> [String] { actions.compactMap { if case .line(let l) = $0 { return l } else { return nil } } }
func has(_ actions: [A], _ a: A) -> Bool { actions.contains(a) }

// MARK: - The constants

same(P.grace, 30, "the wait is 30 s (the plan's open decision 4)")
same(P.lockConfirm, 3, "a lock has 3 s to show in the reading")
check(P.tick > 0 && P.tick * 2 <= P.lockConfirm, "the tick (\(P.tick) s) looks at least twice within a lock's confirmation")
check(P.tick < G, "the tick is well inside the wait")

// MARK: - Who acts: Sill.app itself alone (the review of PR #402, finding 1)

check(P.locksForReal(synthetic: false, bundled: true), "Sill.app itself: the real lock")
check(!P.locksForReal(synthetic: false, bundled: false),
      "the bare SillMenuBar binary and the CLI (not bundled), even advertising as a real host: the dry run")
check(!P.locksForReal(synthetic: true, bundled: true), "Sill.app with --synthetic: the dry run")
check(!P.locksForReal(synthetic: true, bundled: false), "a test host: the dry run")

// MARK: - The gate's reading as the rule reads it

typealias R = LockPolicy.Reading
same(P.mac(.unlocked, established: true), .unlocked, "unlocked, established: unlocked")
same(P.mac(.screenLocked, established: true), .screenLocked, "the screen locked, established: locked")
same(P.mac(.offConsole, established: true), .offConsole, "off console, established: off console")
for r in R.allCases {
    same(P.mac(r, established: false), .unknown, "\(r) not established yet: unknown, never unlocked")
}

// MARK: - Rule 10: a display a lock screen could take a password at (issue #298)

typealias DD = DesktopDisplays
check(!P.typesAt([]), "no display at all: none to type at")
check(P.typesAt([.screen]), "a screen: one to type at")
check(!P.typesAt([.stage]), "Sill's stage display alone (a picked window's): none")
check(!P.typesAt([.sillDesktop]), "Sill's Desktop display alone: none (until #200 says otherwise)")
check(!P.typesAt([.standIn]), "macOS's stand-in for a Mac with no screen (#298's Mac): none")
check(!P.typesAt([.stage, .sillDesktop, .standIn]), "all of Sill's and macOS's stand-in: none")
check(P.typesAt([.stage, .screen]) && P.typesAt([.standIn, .screen]), "a screen among them: one")
let builtIn = DD.role(vendor: 0x610, product: 0xA050, madeByStage: false)
let dell = DD.role(vendor: 0x10AC, product: 0x4205, madeByStage: false)
let stage = DD.role(vendor: DD.sillVendor, product: DD.stageProduct, madeByStage: false)
let desktop = DD.role(vendor: DD.sillVendor, product: DD.desktopProduct, madeByStage: false)
let standIn = DD.role(vendor: 0x756e6b6e, product: 0x76697274, madeByStage: false)
check(P.typesAt([builtIn]) && P.typesAt([dell]), "the Mac's own panel and a DELL monitor, by their identities: screens to type at")
check(!P.typesAt([stage]) && !P.typesAt([desktop]) && !P.typesAt([standIn]),
      "Sill's stage (0x5111, 1), Sill's Desktop (0x5111, 2) and macOS's stand-in ('unkn', 'virt'), by their identities: none")
check(P.typesAt([stage, standIn, dell]), "a Mac mini with a monitor while Sill stages a window: one to type at")

// MARK: - Off: nothing, ever

do {
    var s = P.State(on: false)
    var all: [A] = []
    all += s.sessions(1, at: 0)
    all += s.sessions(0, at: 5)
    all += s.tick(at: 100, mac: .unlocked, display: true)
    all += s.sessions(2, at: 110)
    all += s.sessions(0, at: 111)
    all += s.tick(at: 200, mac: .unlocked, display: true)
    check(all.isEmpty && !s.pending, "the switch off: a device comes and goes, and nothing happens or is said")
    same(s.quit(), [], "the switch off: a quit says nothing either")
}

// MARK: - The wait and the lock

do {
    var s = P.State(on: true)
    same(s.sessions(1, at: 0), [], "a device connects: nothing")
    check(!s.pending, "nothing pending while a device is connected")
    same(s.sessions(0, at: 10), [.line(W.lastLeft(G))], "the last device leaves: the wait begins, said once")
    check(s.pending && s.waitingSince == 10, "the wait runs from the departure")
    same(s.tick(at: 39.9, mac: .unlocked, display: true), [], "at 29.9 s of the wait: nothing yet")
    let end = s.tick(at: 40, mac: .unlocked, display: true)
    same(end, [.line(W.locking(G)), .lock], "at 30 s: the line, then the lock")
    check(s.pending && s.waitingSince == nil && s.confirmingSince == 40, "the confirmation runs from the lock")
    same(s.called(.made, at: 40.01), [], "the call made: nothing until the reading says")
    same(s.tick(at: 40.5, mac: .unlocked, display: true), [.look], "still unlocked at 0.5 s: SessionLock looks again")
    same(s.tick(at: 41, mac: .screenLocked, display: true), [.line(W.lockedAndSleeps), .sleepDisplays],
         "the reading says locked: the line, then the displays sleep (#275)")
    check(!s.pending && s.last == .locked && s.failure == nil, "done: nothing pending, the outcome locked, no failure")
    same(s.tick(at: 200, mac: .unlocked, display: true), [], "after it: nothing more, whatever the reading")
}

do {
    var s = P.State(on: true)
    _ = s.sessions(1, at: 0)
    _ = s.sessions(0, at: 10)
    var display = 0
    func shown() -> Bool { display += 1; return true }
    _ = s.tick(at: 20, mac: .unlocked, display: shown())
    check(display == 0, "the displays are not looked at before the wait's end")
    _ = s.tick(at: 40, mac: .unlocked, display: shown())
    check(display == 1, "the displays are looked at once, at the wait's end")
    _ = s.tick(at: 41, mac: .screenLocked, display: shown())
    check(display == 1, "nor during the confirmation")
}

do {
    // The boundary: a device back at 29.99 s keeps the Mac unlocked; the wait ends at exactly 30 s.
    var s = P.State(on: true)
    _ = s.sessions(1, at: 0)
    _ = s.sessions(0, at: 10)
    same(s.sessions(1, at: 39.99), [.line(W.cameBack(G))], "a device connects again at 29.99 s: the wait ends, said once")
    check(!s.pending, "nothing pending")
    same(s.tick(at: 45, mac: .unlocked, display: true), [], "no lock at the wait's old end")
    same(s.sessions(0, at: 50), [.line(W.lastLeft(G))], "it leaves again: a new wait")
    same(s.tick(at: 79.99, mac: .unlocked, display: true), [], "the new wait counts from the new departure")
    same(s.tick(at: 80, mac: .unlocked, display: true), [.line(W.locking(G)), .lock], "and ends 30 s after it")
}

do {
    // Two devices: only the last one's departure counts; a move (the new connection before the old one leaves) never
    // reaches zero.
    var s = P.State(on: true)
    same(s.sessions(1, at: 0) + s.sessions(2, at: 1) + s.sessions(1, at: 2), [], "two devices, one leaves: nothing")
    check(!s.pending, "nothing pending while one is still connected")
    same(s.sessions(0, at: 3), [.line(W.lastLeft(G))], "the last leaves: the wait")
    var m = P.State(on: true)
    same(m.sessions(1, at: 0) + m.sessions(2, at: 10) + m.sessions(1, at: 10.2), [], "a move: two connections for a moment, then one")
    check(!m.pending, "a move starts no wait")
    same(m.sessions(1, at: 11), [], "the same count again: nothing")
    same(m.sessions(0, at: 12) + m.sessions(0, at: 13), [.line(W.lastLeft(G))], "zero twice: one wait, from the first")
    check(m.waitingSince == 12, "the wait counts from the first zero")
    same(m.sessions(-1, at: 14), [], "a count below zero reads as none")
    check(m.sessions == 0, "and is kept as none")
    same(m.sessions(1, at: 15), [.line(W.cameBack(G))], "a session after it ends the wait as any does")
}

do {
    // The switch.
    var s = P.State(on: true)
    _ = s.sessions(1, at: 0)
    _ = s.sessions(0, at: 10)
    same(s.switched(false, at: 15), [.line(W.switchedOff)], "turned off during the wait: the wait ends, said once")
    check(!s.pending && !s.on, "nothing pending, the switch off")
    same(s.tick(at: 60, mac: .unlocked, display: true), [], "no lock at the wait's old end")
    same(s.switched(false, at: 61), [], "off again: nothing")
    same(s.switched(true, at: 62), [], "on with no device connected: no wait (no departure under the switch)")
    check(!s.pending, "nothing pending")
    same(s.tick(at: 200, mac: .unlocked, display: true), [], "and no lock")
    _ = s.sessions(1, at: 300)
    same(s.sessions(0, at: 310), [.line(W.lastLeft(G))], "a departure after it was turned on: the wait")
    var late = P.State(on: false)
    _ = late.sessions(1, at: 0)
    _ = late.sessions(0, at: 10)
    same(late.switched(true, at: 20), [], "turned on 10 s after the last device left: no wait for that departure")
    same(late.tick(at: 50, mac: .unlocked, display: true), [], "and no lock")
    var during = P.State(on: false)
    _ = during.sessions(1, at: 0)
    _ = during.switched(true, at: 5)
    same(during.sessions(0, at: 10), [.line(W.lastLeft(G))], "turned on while a device is connected: its departure waits")
    same(during.switched(true, at: 11), [], "on again: nothing")
}

// MARK: - The wait's end when no lock is made

for (mac, line, outcome) in [(P.Mac.screenLocked, W.alreadyLocked, P.Outcome.alreadyLocked),
                             (.offConsole, W.notOnConsole, .offConsole),
                             (.unknown, W.unknownReading, .unknown)] {
    var s = P.State(on: true)
    _ = s.sessions(1, at: 0)
    _ = s.sessions(0, at: 10)
    var display = 0
    func shown() -> Bool { display += 1; return true }
    same(s.tick(at: 40, mac: mac, display: shown()), [.line(line)], "the wait ends with the Mac \(mac): no lock, its line")
    check(!s.pending && s.last == outcome && display == 0, "\(mac): nothing pending, the outcome \(outcome), the displays not looked at")
}
do {
    var s = P.State(on: true)
    _ = s.sessions(1, at: 0)
    _ = s.sessions(0, at: 10)
    same(s.tick(at: 40, mac: .unlocked, display: false), [.line(W.noDisplay)], "no display to type at (#298): no lock, its line")
    check(!s.pending && s.last == .noDisplay, "nothing pending, the outcome no display")
}

// MARK: - The confirmation

do {
    var s = P.State(on: true)
    _ = s.sessions(1, at: 0)
    _ = s.sessions(0, at: 10)
    _ = s.tick(at: 40, mac: .unlocked, display: true)
    same(s.tick(at: 40.2, mac: .offConsole, display: true), [.line(W.lockedAndSleeps), .sleepDisplays],
         "the lock shows as the login window (off console): locked, the displays sleep")
}
do {
    var s = P.State(on: true)
    _ = s.sessions(1, at: 0)
    _ = s.sessions(0, at: 10)
    _ = s.tick(at: 40, mac: .unlocked, display: true)
    same(s.tick(at: 42.99, mac: .unlocked, display: true), [.look], "still unlocked at 2.99 s: another look")
    same(s.tick(at: 43, mac: .unlocked, display: true),
         [.line(W.couldNotLock(W.stillUnlockedLog, sleeps: true)), .sleepDisplays],
         "still unlocked at 3 s: the failure's line, and the displays sleep instead")
    check(!s.pending && s.last == .failed(W.stillUnlockedReason) && s.failure == W.stillUnlockedReason,
          "the failure kept for Settings, in its words")
    same(s.tick(at: 44, mac: .screenLocked, display: true), [], "a lock that shows after that changes nothing")
}
do {
    var s = P.State(on: true)
    _ = s.sessions(1, at: 0)
    _ = s.sessions(0, at: 10)
    _ = s.tick(at: 40, mac: .unlocked, display: true)
    same(s.called(.unavailable(W.unavailableLog), at: 40.01),
         [.line(W.couldNotLock(W.unavailableLog, sleeps: true)), .sleepDisplays],
         "the call unavailable (no SACLockScreenImmediate): the failure's line, and the displays sleep instead")
    check(!s.pending && s.failure == W.unavailableReason, "nothing pending, the failure in Settings' words")
    same(s.called(.unavailable(W.unavailableLog), at: 40.02), [], "a second answer: nothing")
    same(s.tick(at: 43, mac: .unlocked, display: true), [], "and no second failure at 3 s")
    // A later success clears it; an outcome with no lock attempted keeps it.
    _ = s.sessions(1, at: 100)
    _ = s.sessions(0, at: 110)
    same(s.tick(at: 140, mac: .screenLocked, display: true), [.line(W.alreadyLocked)], "a later wait ends locked already")
    check(s.failure == W.unavailableReason, "the last attempt's failure stays (no lock was attempted since)")
    _ = s.sessions(1, at: 200)
    _ = s.sessions(0, at: 210)
    _ = s.tick(at: 240, mac: .unlocked, display: true)
    _ = s.tick(at: 240.5, mac: .screenLocked, display: true)
    check(s.failure == nil && s.last == .locked, "a lock that happens clears it")
}
do {
    // A device back while the lock is confirmed: its display never sleeps.
    var s = P.State(on: true)
    _ = s.sessions(1, at: 0)
    _ = s.sessions(0, at: 10)
    _ = s.tick(at: 40, mac: .unlocked, display: true)
    same(s.sessions(1, at: 40.3), [], "a device connects while the lock is confirmed: no line (the wait is over)")
    same(s.tick(at: 40.5, mac: .screenLocked, display: true), [.line(W.lockedDeviceBack)],
         "locked: its line, and the display stays on for the device")
    var f = P.State(on: true)
    _ = f.sessions(1, at: 0)
    _ = f.sessions(0, at: 10)
    _ = f.tick(at: 40, mac: .unlocked, display: true)
    _ = f.sessions(1, at: 41)
    same(f.tick(at: 43, mac: .unlocked, display: true), [.line(W.couldNotLock(W.stillUnlockedLog, sleeps: false))],
         "not locked by 3 s with a device back: the failure's line, no display sleep")
    var u = P.State(on: true)
    _ = u.sessions(1, at: 0)
    _ = u.sessions(0, at: 10)
    _ = u.tick(at: 40, mac: .unlocked, display: true)
    _ = u.sessions(1, at: 40.005)
    same(u.called(.unavailable(W.unavailableLog), at: 40.01), [.line(W.couldNotLock(W.unavailableLog, sleeps: false))],
         "the call unavailable with a device back: the failure's line, no display sleep")
}
do {
    // One lock at a time: a confirmation still under way when another wait ends.
    var s = P.State(on: true)
    _ = s.sessions(1, at: 0)
    _ = s.sessions(0, at: 10)
    _ = s.tick(at: 40, mac: .unlocked, display: true)
    var t = P.State(on: true, grace: 1)
    _ = t.sessions(1, at: 0)
    _ = t.sessions(0, at: 1)
    same(t.tick(at: 2, mac: .unlocked, display: true), [.line(W.locking(1)), .lock], "a 1 s wait (a test host's): the lock")
    _ = t.sessions(1, at: 2.1)
    same(t.sessions(0, at: 2.2), [.line(W.lastLeft(1))], "a device came and went during the confirmation: a new wait")
    same(t.tick(at: 3.2, mac: .unlocked, display: true), [.look, .line(W.lockUnderWay(1))],
         "its end with the first lock still unconfirmed: no second lock, the line says so")
    check(t.pending && t.waitingSince == nil, "the confirmation still runs; the wait is over")
    same(t.tick(at: 5, mac: .unlocked, display: true), [.line(W.couldNotLock(W.stillUnlockedLog, sleeps: true)), .sleepDisplays],
         "the first lock's confirmation decides for both")
    check(s.confirmingSince == 40, "(the first state, untouched by the second, still confirms its lock)")
}

// MARK: - Turn off its display too, off

do {
    var s = P.State(on: true, sleeps: false)
    _ = s.sessions(1, at: 0)
    _ = s.sessions(0, at: 10)
    same(s.tick(at: 40, mac: .unlocked, display: true), [.line(W.locking(G)), .lock], "its display left on: the same wait and lock")
    same(s.tick(at: 40.5, mac: .screenLocked, display: true), [.line(W.locked)], "locked: its line, and no display sleep")
    check(!s.pending && s.last == .locked && s.failure == nil, "done, locked")
    var back = P.State(on: true, sleeps: false)
    _ = back.sessions(1, at: 0)
    _ = back.sessions(0, at: 10)
    _ = back.tick(at: 40, mac: .unlocked, display: true)
    _ = back.sessions(1, at: 40.2)
    same(back.tick(at: 40.5, mac: .screenLocked, display: true), [.line(W.locked)], "locked with a device back: the same line")
    var f = P.State(on: true, sleeps: false)
    _ = f.sessions(1, at: 0)
    _ = f.sessions(0, at: 10)
    _ = f.tick(at: 40, mac: .unlocked, display: true)
    same(f.tick(at: 43, mac: .unlocked, display: true), [.line(W.couldNotLock(W.stillUnlockedLog, sleeps: true)), .sleepDisplays],
         "a lock that fails still puts the display to sleep instead (the lock's own way, whatever the switch)")
    var u = P.State(on: true, sleeps: false)
    _ = u.sessions(1, at: 0)
    _ = u.sessions(0, at: 10)
    _ = u.tick(at: 40, mac: .unlocked, display: true)
    same(u.called(.unavailable(W.unavailableLog), at: 40.01), [.line(W.couldNotLock(W.unavailableLog, sleeps: true)), .sleepDisplays],
         "and so does the call unavailable")
    // Read when the lock is confirmed: changed during the wait or the confirmation, the new value counts.
    var c = P.State(on: true)
    _ = c.sessions(1, at: 0)
    _ = c.sessions(0, at: 10)
    c.setSleeps(false)
    check(!c.sleeps, "turned off during the wait: kept")
    _ = c.tick(at: 40, mac: .unlocked, display: true)
    same(c.tick(at: 40.5, mac: .screenLocked, display: true), [.line(W.locked)], "and read at the confirmation: no display sleep")
    var d = P.State(on: true, sleeps: false)
    _ = d.sessions(1, at: 0)
    _ = d.sessions(0, at: 10)
    _ = d.tick(at: 40, mac: .unlocked, display: true)
    d.setSleeps(true)
    same(d.tick(at: 40.5, mac: .screenLocked, display: true), [.line(W.lockedAndSleeps), .sleepDisplays],
         "turned on during the confirmation: the display sleeps")
}

// MARK: - Only after a device away from home

do {
    // A visit with no session away: no wait, said once; nothing locks.
    var s = P.State(on: true, onlyAway: true)
    _ = s.sessions(1, at: 0)
    s.joined(away: false)
    same(s.sessions(0, at: 10), [.line(W.notAway)], "a visit at home alone: no wait, its line")
    check(!s.pending && !s.awaySeen, "nothing pending, the visit over")
    same(s.tick(at: 60, mac: .unlocked, display: true), [], "and no lock")
    // One away session in the visit is enough, whoever leaves last.
    _ = s.sessions(1, at: 100)
    s.joined(away: false)
    _ = s.sessions(2, at: 101)
    s.joined(away: true)
    check(s.awaySeen, "a session away from home seen")
    _ = s.sessions(1, at: 102)
    same(s.sessions(0, at: 110), [.line(W.lastLeft(G))], "an iPad at home leaves after an iPhone away did: the wait")
    same(s.tick(at: 140, mac: .unlocked, display: true), [.line(W.locking(G)), .lock], "and the lock")
    check(!s.awaySeen, "the visit over with its wait")
    _ = s.tick(at: 140.5, mac: .screenLocked, display: true)
    // Each visit starts afresh.
    _ = s.sessions(1, at: 200)
    s.joined(away: false)
    same(s.sessions(0, at: 210), [.line(W.notAway)], "the next visit, at home alone: no wait")
}
do {
    // A return within the wait goes on with the visit: the session away before it counts.
    var s = P.State(on: true, onlyAway: true)
    _ = s.sessions(1, at: 0)
    s.joined(away: true)
    same(s.sessions(0, at: 10), [.line(W.lastLeft(G))], "the iPhone away leaves: the wait")
    same(s.sessions(1, at: 15), [.line(W.cameBack(G))], "the iPad at home connects within it: the wait ends")
    s.joined(away: false)
    same(s.sessions(0, at: 20), [.line(W.lastLeft(G))], "the iPad leaves: the visit had one away, so the wait")
    same(s.tick(at: 50, mac: .unlocked, display: true), [.line(W.locking(G)), .lock], "and the lock")
}
do {
    // A wait that ended for any reason but a return ends the visit.
    var s = P.State(on: true, onlyAway: true)
    _ = s.sessions(1, at: 0)
    s.joined(away: true)
    _ = s.sessions(0, at: 10)
    same(s.tick(at: 40, mac: .screenLocked, display: true), [.line(W.alreadyLocked)], "a visit away ends locked already")
    _ = s.sessions(1, at: 50)
    s.joined(away: false)
    same(s.sessions(0, at: 60), [.line(W.notAway)], "the next visit, at home alone: no wait")
    var o = P.State(on: true, onlyAway: true)
    _ = o.sessions(1, at: 0)
    o.joined(away: true)
    _ = o.sessions(0, at: 10)
    same(o.switched(false, at: 12), [.line(W.switchedOff)], "the switch off during a visit away's wait")
    _ = o.switched(true, at: 13)
    _ = o.sessions(1, at: 20)
    o.joined(away: false)
    same(o.sessions(0, at: 30), [.line(W.notAway)], "on again, the next visit at home alone: no wait")
    var n = P.State(on: false, onlyAway: true)
    _ = n.sessions(1, at: 0)
    n.joined(away: true)
    same(n.sessions(0, at: 10), [], "the switch off: a visit away leaves and nothing is said")
    _ = n.switched(true, at: 11)
    _ = n.sessions(1, at: 20)
    n.joined(away: false)
    same(n.sessions(0, at: 30), [.line(W.notAway)], "turned on, a visit at home alone after it: no wait (that visit was over)")
    var k = P.State(on: true, onlyAway: true)
    _ = k.sessions(1, at: 0)
    k.joined(away: true)
    _ = k.switched(false, at: 5)
    _ = k.switched(true, at: 6)
    same(k.sessions(0, at: 10), [.line(W.lastLeft(G))], "the switch off and on while a device away stays: its departure waits")
}
do {
    // The switch changed at once.
    var s = P.State(on: true)
    _ = s.sessions(1, at: 0)
    s.joined(away: false)
    _ = s.sessions(0, at: 10)
    same(s.setOnlyAway(true, at: 15), [.line(W.nowOnlyAway)], "turned on during a wait for a visit at home alone: the wait ends, said")
    check(!s.pending && s.onlyAway, "nothing pending")
    same(s.tick(at: 60, mac: .unlocked, display: true), [], "and no lock")
    same(s.setOnlyAway(true, at: 61), [], "on again: nothing")
    var a = P.State(on: true)
    _ = a.sessions(1, at: 0)
    a.joined(away: true)
    _ = a.sessions(0, at: 10)
    same(a.setOnlyAway(true, at: 15), [], "turned on during a wait for a visit with one away: the wait goes on")
    same(a.tick(at: 40, mac: .unlocked, display: true), [.line(W.locking(G)), .lock], "and locks")
    var b = P.State(on: true, onlyAway: true)
    _ = b.sessions(1, at: 0)
    b.joined(away: false)
    _ = b.sessions(0, at: 10)
    same(b.setOnlyAway(false, at: 12), [], "turned off after a departure that started no wait: none starts")
    same(b.tick(at: 60, mac: .unlocked, display: true), [], "and no lock")
    var q = P.State(on: true)
    _ = q.sessions(1, at: 0)
    _ = q.sessions(0, at: 10)
    _ = q.quit()
    same(q.setOnlyAway(true, at: 11), [], "after a quit: nothing")
    var off = P.State(on: false)
    same(off.setOnlyAway(true, at: 1) + off.setOnlyAway(false, at: 2), [], "with the switch off: nothing")
    var j = P.State(on: true, onlyAway: true)
    _ = j.sessions(1, at: 0)
    j.joined(away: false)
    j.joined(away: false)
    check(!j.awaySeen, "sessions at home never count as away")
}

// MARK: - Settings' warning

same(P.warning(on: false, noDisplay: true, failure: "x"), nil, "the switch off: no warning")
same(P.warning(on: true, noDisplay: false, failure: nil), nil, "on, a display, no failure: no warning")
same(P.warning(on: true, noDisplay: true, failure: nil), W.noDisplayWarning, "on, no display: its warning")
same(P.warning(on: true, noDisplay: false, failure: W.unavailableReason), W.failedWarning(W.unavailableReason), "on, a failure: its warning")
same(P.warning(on: true, noDisplay: true, failure: W.unavailableReason), W.noDisplayWarning, "no display wins over a failure")

// MARK: - A quit, and a crash

do {
    var s = P.State(on: true)
    _ = s.sessions(1, at: 0)
    _ = s.sessions(0, at: 10)
    same(s.quit(), [.line(W.quitting)], "a quit during the wait: its line, once")
    check(!s.pending && s.quitting, "nothing pending")
    same(s.quit(), [], "a second quit: nothing")
    same(s.tick(at: 40, mac: .unlocked, display: true), [], "no lock at the wait's end")
    same(s.sessions(1, at: 41) + s.sessions(0, at: 42) + s.tick(at: 80, mac: .unlocked, display: true), [],
         "nothing after a quit, whatever comes")
    var q = P.State(on: true)
    _ = q.sessions(1, at: 0)
    same(q.quit(), [], "a quit with a device connected: nothing to say")
    same(q.sessions(0, at: 1), [], "its devices leaving as Sill quits start no wait")
    var c = P.State(on: true)
    _ = c.sessions(1, at: 0)
    _ = c.sessions(0, at: 10)
    _ = c.tick(at: 40, mac: .unlocked, display: true)
    same(c.quit(), [], "a quit while a lock is confirmed: nothing more said (the lock was asked)")
    same(c.called(.unavailable(W.unavailableLog), at: 40.1) + c.tick(at: 44, mac: .unlocked, display: true), [],
         "no failure line or display sleep after the quit")
}
do {
    // A crash or a force quit leaves nothing behind: the next launch's state starts with no wait.
    var s = P.State(on: true)
    check(!s.pending && s.sessions == 0 && s.waitingSince == nil && s.last == nil, "a new launch: nothing pending")
    var all: [A] = s.sessions(0, at: 0)
    for t in stride(from: 0.5, through: 120, by: 0.5) { all += s.tick(at: t, mac: .unlocked, display: true) }
    check(all.isEmpty, "a new launch with no device: no lock in two minutes (it locks only after a departure it saw)")
}

// MARK: - The TEST ONLY hooks

do {
    let none = P.testHooks(testHost: false, environment: ["SILL_TEST_PRIVACY_GRACE": "5", "SILL_TEST_PRIVACY_DISPLAYS": "0",
                                                          "SILL_TEST_PRIVACY_NO_SYMBOL": "1"])
    check(none == P.TestHooks(), "a host that is not a test host takes none and says nothing (TestHooks says they are ignored)")
    let h = P.testHooks(testHost: true, environment: ["SILL_TEST_PRIVACY_GRACE": "5", "SILL_TEST_PRIVACY_DISPLAYS": "0",
                                                      "SILL_TEST_PRIVACY_NO_SYMBOL": "1"])
    check(h.grace == 5 && h.displays == 0 && h.noSymbol, "a test host takes all three")
    same(h.lines.count, 3, "one line each")
    check(h.lines[0].contains("5 s") && h.lines[1].contains("0 displays") && h.lines[2].contains("SACLockScreenImmediate"),
          "the lines say what each does")
    same(P.testHooks(testHost: true, environment: [:]), P.TestHooks(), "a test host with none set: nothing, no line")
    for bad in ["0.4", "601", "abc", "-1", "nan"] {
        let b = P.testHooks(testHost: true, environment: ["SILL_TEST_PRIVACY_GRACE": bad])
        check(b.grace == nil && b.lines.count == 1 && b.lines[0].hasPrefix("SILL_TEST_PRIVACY_GRACE=\(bad) ignored"),
              "a wait of \(bad) s: ignored, said once")
    }
    check(P.testHooks(testHost: true, environment: ["SILL_TEST_PRIVACY_GRACE": "0.5"]).grace == 0.5
          && P.testHooks(testHost: true, environment: ["SILL_TEST_PRIVACY_GRACE": "600"]).grace == 600, "0.5 and 600 s are taken")
    for bad in ["-1", "17", "two", "1.5"] {
        let b = P.testHooks(testHost: true, environment: ["SILL_TEST_PRIVACY_DISPLAYS": bad])
        check(b.displays == nil && b.lines.count == 1 && b.lines[0].hasPrefix("SILL_TEST_PRIVACY_DISPLAYS=\(bad) ignored"),
              "\(bad) displays: ignored, said once")
    }
    check(P.testHooks(testHost: true, environment: ["SILL_TEST_PRIVACY_DISPLAYS": "1"]).lines == [
        "Test privacy: this Mac counts as having 1 display to type its password at (SILL_TEST_PRIVACY_DISPLAYS)."],
          "one display, in the singular")
    check(!P.testHooks(testHost: true, environment: ["SILL_TEST_PRIVACY_NO_SYMBOL": "0"]).noSymbol
          && P.testHooks(testHost: true, environment: ["SILL_TEST_PRIVACY_NO_SYMBOL": "0"]).lines.isEmpty,
          "SILL_TEST_PRIVACY_NO_SYMBOL=0: the call as it is, no line")
    check(P.testHooks(testHost: true, environment: ["SILL_TEST_PRIVACY_GRACE": ""]) == P.TestHooks(), "an empty value: nothing")
    // A test host's wait in every line.
    var s = P.State(on: true, grace: 5)
    _ = s.sessions(1, at: 0)
    same(s.sessions(0, at: 1), [.line("Privacy: the last device left; this Mac locks in 5 s unless one connects again.")],
         "a 5 s wait says 5 s")
    same(s.tick(at: 6, mac: .unlocked, display: true), [.line("Privacy: locking this Mac: the last device left 5 s ago."), .lock],
         "and locks after 5 s")
}

// MARK: - Every word

let logLines = [W.startLine(G), W.lastLeft(G), W.cameBack(G), W.switchedOff, W.locking(G), W.lockedAndSleeps, W.lockedDeviceBack,
                W.locked, W.alreadyLocked, W.notOnConsole, W.unknownReading, W.noDisplay, W.lockUnderWay(G),
                W.couldNotLock(W.unavailableLog, sleeps: true), W.couldNotLock(W.stillUnlockedLog, sleeps: false), W.quitting,
                W.notAway, W.nowOnlyAway, W.startLine(G, sleeps: false, onlyAway: true, dry: true)]
check(logLines.allSatisfy { $0.hasPrefix("Privacy: ") && $0.hasSuffix(".") && !$0.contains("  ") }, "every log line starts with \"Privacy: \" and ends with a full stop")
check(Set(logLines).count == logLines.count, "no two log lines alike")
check([W.dryLock, W.drySleep].allSatisfy { $0.hasPrefix("Privacy (dry run): would ") && $0.contains("nothing") },
      "the dry run's lines say it would, and that nothing happens")
same(W.startLine(G), "Privacy: Lock this Mac when the last device leaves is on: 30 s after the last device leaves, Sill locks this Mac and puts its display to sleep.",
     "the start line, Sill.app's, as it was")
same(W.startLine(5, sleeps: false, onlyAway: true, dry: true),
     "Privacy: Lock this Mac when the last device leaves is on: 5 s after the last device leaves, when one connected from away from home, Sill locks this Mac. A dry run here (only Sill.app itself locks a Mac): it says what it would do.",
     "the start line with the display left on, only after a device away, in a dry run")
check(W.startLine(G, dry: true).hasPrefix(W.startLine(G).dropLast()) && W.startLine(G, dry: true).contains("dry run"),
      "a dry run's start line is Sill.app's with the dry run said after it")
same(W.locked, "Privacy: this Mac is locked.", "locked with its display left on")
same(W.notAway, "Privacy: the last device left; none connected from away from home, so this Mac won’t be locked.", "a visit at home alone")
check(W.nowOnlyAway.contains("only after a device away from home") && W.nowOnlyAway.contains("won’t be locked"), "the switch's line says what ended the wait")
same(W.sleepToggle, "Turn off its display too", "the display's switch (#275)")
same(W.awayToggle, "Only after a device away from home", "the scope's switch (the plan's open decision 5)")
same(W.footnoteOn(G), W.footnoteOn(G, sleeps: true, onlyAway: false), "the footnote's defaults are the switches' defaults")
check(!W.footnoteOn(G, sleeps: false).contains("sleep") && W.footnoteOn(G, sleeps: false).contains("30 seconds"),
      "the footnote with the display left on says no sleep")
check(W.footnoteOn(G, onlyAway: true).contains("away from home") && !W.footnoteOn(G).contains("away from home"),
      "the footnote says away from home only with that switch on")
same(W.lastLeft(G), "Privacy: the last device left; this Mac locks in 30 s unless one connects again.", "the departure's line")
same(W.cameBack(G), "Privacy: a device connected again within 30 s; this Mac won’t be locked.", "a return's line")
same(W.locking(G), "Privacy: locking this Mac: the last device left 30 s ago.", "the lock's line")
same(W.lockedAndSleeps, "Privacy: this Mac is locked; its display sleeps.", "the confirmation's line")
same(W.noDisplay, "Privacy: not locking this Mac: it has no display to type its password at (issue #298).", "rule 10's line names #298")
same(W.couldNotLock(W.unavailableLog, sleeps: true),
     "Privacy: couldn’t lock this Mac (macOS has no SACLockScreenImmediate); its display sleeps instead.", "the missing call's line")
same(W.couldNotLock(W.stillUnlockedLog, sleeps: true),
     "Privacy: couldn’t lock this Mac (it still read unlocked 3 s later); its display sleeps instead.", "the unconfirmed lock's line")
same(W.couldNotLock("x", sleeps: false), "Privacy: couldn’t lock this Mac (x).", "a failure with a device back: no display sleep said")
check(W.startLine(G).contains("30 s") && W.startLine(G).contains("display to sleep"), "the start line says the wait and the sleep")
same(W.toggle, "Lock this Mac when the last device leaves", "the switch's words (#283)")
check(W.footnoteOn(G).contains("30 seconds") && W.footnoteOn(G).contains("drops and comes back") && W.footnoteOn(G).contains("sleep")
      && W.footnoteOn(G).contains("paired device"), "the footnote with it on: the wait and why, the sleep, the way back")
check(!W.footnoteOff.isEmpty && W.footnoteOff.contains("locks itself"), "the footnote with it off says what it does")
same(W.failedWarning(W.unavailableReason), "Sill couldn’t lock this Mac the last time: this version of macOS doesn’t let Sill lock it.",
     "the warning after a missing call")
same(W.stillUnlockedReason, "it was still unlocked 3 seconds after Sill asked", "the unconfirmed lock in Settings' words")
check(W.noDisplayWarning.contains("no display") && W.noDisplayWarning.contains("password"), "the no-display warning says why")
same(W.seconds(1), "1 second", "one second, singular")
same(W.seconds(30), "30 seconds", "thirty seconds")
same(W.number(1.5), "1.5", "a half second")
same(W.number(600), "600", "a whole number")

// MARK: - The rule as the coordinator's glue drives it, through random sessions

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

/// The registered sessions as the rule hears of them: each registration's count (`onClientCountChanged`), then its
/// route (`onClientConnected`: away from home or not), each departure's count, in order. Which connections register
/// at all is the server's (see the header), not modelled here.
struct Sessions {
    var away: [Bool] = []
    mutating func register(away a: Bool) -> Int { away.append(a); return away.count }
    mutating func leave(_ i: Int) -> Int { away.remove(at: i); return away.count }
}

var rng = Rng(s: 0x2830_275)
var violations: [String: Int] = [:], firstViolation: [String: String] = [:]
func violated(_ what: String, _ detail: String) {
    violations[what, default: 0] += 1
    if firstViolation[what] == nil { firstViolation[what] = detail }
}
let endLines: (Double) -> [String] = { g in [W.locking(g), W.alreadyLocked, W.notOnConsole, W.unknownReading, W.noDisplay, W.lockUnderWay(g)] }
var runs = 0, locks = 0, outcomes = 0, waitsEnded = 0, returns = 0, quits = 0, sleeps = 0, neverOnRuns = 0
var unavailable = 0, failedConfirm = 0, deviceBackOutcomes = 0, lockedNoSleep = 0, notAwayLines = 0, nowOnlyAwayLines = 0
var awayLocks = 0, failuresNoSleepSwitch = 0
let eps = 1e-9
for run in 0..<20_000 {
    runs += 1
    let everOn = rng.below(10) != 0
    var on = everOn && rng.below(4) != 0
    var sleepsOn = rng.below(3) != 0
    var onlyAway = rng.below(3) == 0
    let grace = [P.grace, 1, 2, 5][rng.below(4)]
    var s = P.State(on: on, sleeps: sleepsOn, onlyAway: onlyAway, grace: grace)
    var server = Sessions()
    var mac = P.Mac.unlocked
    var display = true
    var t = 0.0
    // The model, from the events alone (never from the rule's output): this visit's session away from home, the
    // departure under the switch and whether its wait ended, the lock asked and not yet decided, the quit.
    var visitAway = false
    var dep: Double?
    var depEnded = false
    var lockedFor: Double?          // the departure the last lock was for
    var unconfirmed: Double?
    var callAnswerAt: Double?
    var callAnswer = P.Call.made
    /// When macOS's lock shows in the reading after a call made (sometimes later than the confirmation's time, sometimes
    /// never), as SessionLock's notify witness would say it.
    var lockShowsAt: Double?
    var quit = false
    var nextTick: Double?

    /// Judges what the rule said at `now` against the model, then follows the glue: ticks exactly while pending.
    func judge(_ actions: [A], at now: Double, expectLines: [String]? = nil) {
        if !everOn, !actions.isEmpty { violated("I7", "run \(run): \(actions) with the switch never on") }
        if quit, !actions.isEmpty { violated("I8", "run \(run): \(actions) after the quit at \(now)") }
        if let expectLines, lines(actions) != expectLines {
            violated("I6", "run \(run): said \(lines(actions)), the model expected \(expectLines) at \(now)")
        }
        var previous: A?
        for a in actions {
            switch a {
            case .lock:
                locks += 1
                if onlyAway { awayLocks += 1 }
                if !on || !server.away.isEmpty || quit || mac != .unlocked || !display {
                    violated("I1", "run \(run): a lock with on \(on), \(server.away.count) sessions, quit \(quit), \(mac), display \(display)")
                }
                if let d = dep {
                    if now - d < grace - eps || now - d > grace + P.tick + eps {
                        violated("I1", "run \(run): a lock \(now - d) s after the departure (wait \(grace))")
                    }
                    if lockedFor == d { violated("I2", "run \(run): a second lock for the departure at \(d)") }
                    lockedFor = d
                } else {
                    violated("I1", "run \(run): a lock with no departure under the switch at \(now)")
                }
                if unconfirmed != nil { violated("I2", "run \(run): a lock while another was unconfirmed at \(now)") }
                unconfirmed = now
                callAnswerAt = now + rng.unit() * 0.05
                callAnswer = rng.below(8) == 0 ? .unavailable(W.unavailableLog) : .made
                lockShowsAt = callAnswer == .made && rng.below(4) != 0 ? now + rng.unit() * 4 : nil
            case .sleepDisplays:
                sleeps += 1
                if !server.away.isEmpty { violated("I4", "run \(run): the displays put to sleep with a session connected at \(now)") }
                guard case .line(let l)? = previous, l == W.lockedAndSleeps && sleepsOn || l.hasPrefix("Privacy: couldn’t lock this Mac") else {
                    violated("I4", "run \(run): the displays put to sleep other than right after a lock's outcome (its display switch \(sleepsOn)) at \(now)")
                    break
                }
            case .look:
                if unconfirmed == nil { violated("I5", "run \(run): a look with no lock to confirm at \(now)") }
            case .line(let l):
                if l == W.lockedAndSleeps || l == W.lockedDeviceBack || l == W.locked || l.hasPrefix("Privacy: couldn’t lock this Mac") {
                    outcomes += 1
                    if l == W.lockedDeviceBack { deviceBackOutcomes += 1 }
                    if l == W.locked { lockedNoSleep += 1 }
                    guard let asked = unconfirmed else { violated("I3", "run \(run): an outcome with no lock asked at \(now)"); break }
                    if now - asked > P.lockConfirm + P.tick + eps { violated("I3", "run \(run): an outcome \(now - asked) s after the lock") }
                    let locked = mac == .screenLocked || mac == .offConsole
                    let empty = server.away.isEmpty
                    if l == W.lockedAndSleeps && !(locked && empty && sleepsOn) || l == W.lockedDeviceBack && !(locked && !empty && sleepsOn)
                        || l == W.locked && !(locked && !sleepsOn) {
                        violated("I3", "run \(run): '\(l)' with the Mac \(mac), \(server.away.count) sessions, its display switch \(sleepsOn)")
                    }
                    if l.hasPrefix("Privacy: couldn’t lock this Mac") {
                        if l.hasSuffix("instead.") != empty { violated("I4", "run \(run): '\(l)' with \(server.away.count) sessions") }
                        if !sleepsOn { failuresNoSleepSwitch += 1 }
                    }
                    if l.contains(W.stillUnlockedLog) {
                        failedConfirm += 1
                        if locked || now - asked < P.lockConfirm - eps { violated("I3", "run \(run): '\(l)' \(now - asked) s in, the Mac \(mac)") }
                    }
                    if l.contains(W.unavailableLog) { unavailable += 1 }
                    unconfirmed = nil
                    callAnswerAt = nil
                } else if endLines(grace).contains(l) {
                    waitsEnded += 1
                    guard let d = dep, !depEnded else { violated("I6", "run \(run): '\(l)' with no wait at \(now)"); break }
                    if now - d < grace - eps || now - d > grace + P.tick + eps { violated("I6", "run \(run): a wait ended \(now - d) s in (wait \(grace))") }
                    let want: String
                    switch mac {
                    case .screenLocked: want = W.alreadyLocked
                    case .offConsole: want = W.notOnConsole
                    case .unknown: want = W.unknownReading
                    case .unlocked: want = !display ? W.noDisplay : unconfirmed != nil ? W.lockUnderWay(grace) : W.locking(grace)
                    }
                    if l != want { violated("I6", "run \(run): the wait ended with '\(l)', the Mac \(mac), display \(display): want '\(want)'") }
                    depEnded = true
                    visitAway = false       // the visit is over with its wait
                }
            }
            previous = a
        }
        let waiting = dep != nil && !depEnded
        if !quit, s.pending != (waiting || unconfirmed != nil) {
            violated("I5", "run \(run): pending \(s.pending), the model's wait \(waiting) and lock \(unconfirmed != nil) at \(now)")
        }
        if quit, s.pending { violated("I8", "run \(run): pending after the quit") }
        if s.pending { if nextTick == nil { nextTick = now + P.tick } } else { nextTick = nil }
    }

    func countChanged(_ count: Int) {
        let before = s.sessions
        var expect: [String] = []
        if !quit {
            if count > 0, dep != nil, !depEnded { expect = [W.cameBack(grace)]; returns += 1 }
            if count > 0 { dep = nil; depEnded = false }
            if count == 0, before > 0 {
                if on, !onlyAway || visitAway {
                    dep = t; depEnded = false; expect = [W.lastLeft(grace)]
                } else {
                    // No wait: the visit is over (said only with the switch on).
                    if on { expect = [W.notAway]; notAwayLines += 1 }
                    visitAway = false
                }
            }
        }
        let out = s.sessions(count, at: t)
        if out.contains(where: { if case .line = $0 { return false } else { return true } }) {
            violated("I6", "run \(run): a count change did more than say: \(out)")
        }
        judge(out, at: t, expectLines: expect)
    }

    let steps = 40 + rng.below(120)
    var step = 0
    while step < steps {
        let gap = rng.below(3) == 0 ? rng.unit() * 0.6 : rng.unit() * Double(rng.below(3) == 0 ? 40 : 4)
        let at = t + gap
        // What comes first: the glue's tick, the call's answer, or the next event.
        if let tick = nextTick, tick <= at, tick <= (callAnswerAt ?? .infinity) {
            t = tick
            nextTick = nil
            judge(s.tick(at: t, mac: mac, display: display), at: t)
            continue
        }
        if let answerAt = callAnswerAt, answerAt <= at {
            t = answerAt
            callAnswerAt = nil
            judge(s.called(callAnswer, at: t), at: t)
            continue
        }
        if let shows = lockShowsAt, shows <= at, !quit {
            t = shows
            lockShowsAt = nil
            let was = mac
            mac = .screenLocked
            // The glue's lockChanged: a tick only while pending.
            if mac != was, s.pending { judge(s.tick(at: t, mac: mac, display: display), at: t) }
            continue
        }
        step += 1
        t = at
        // The model's own deadlines: a wait or a lock left undecided past its time.
        if let d = dep, !depEnded, t > d + grace + P.tick + eps, !quit { violated("I6", "run \(run): the wait from \(d) never ended (now \(t))") }
        if let u = unconfirmed, t > u + P.lockConfirm + P.tick + eps, !quit { violated("I3", "run \(run): the lock at \(u) never decided (now \(t))") }
        if quit { continue }
        switch rng.below(20) {
        case 0...5:
            // A session registers: its count, then its route (the coordinator's onClientConnected), as the server
            // reports them. Away from home one time in three.
            let away = rng.below(3) == 0
            countChanged(server.register(away: away))
            s.joined(away: away)
            if away { visitAway = true }
        case 6...11:
            if !server.away.isEmpty { countChanged(server.leave(rng.below(server.away.count))) }
        case 12:
            // Turn off its display too, changed: read at the next confirmed lock.
            sleepsOn.toggle()
            s.setSleeps(sleepsOn)
        case 13, 14:
            let was = mac
            mac = [P.Mac.unlocked, .unlocked, .screenLocked, .offConsole, .unknown][rng.below(5)]
            // The glue's lockChanged: a tick only while pending.
            if mac != was, s.pending { judge(s.tick(at: t, mac: mac, display: display), at: t) }
        case 15:
            display = rng.below(4) != 0
        case 16, 17:
            guard everOn else { break }
            on.toggle()
            var expect: [String] = []
            if !on, dep != nil, !depEnded { expect = [W.switchedOff]; dep = nil; depEnded = false; visitAway = false }
            judge(s.switched(on, at: t), at: t, expectLines: expect)
        case 18:
            guard rng.below(6) == 0 else { break }
            quits += 1
            let expect = dep != nil && !depEnded ? [W.quitting] : []
            let out = s.quit()
            if lines(out) != expect || out.count != expect.count { violated("I8", "run \(run): a quit said \(out), want \(expect)") }
            quit = true
            dep = nil
            unconfirmed = nil
            callAnswerAt = nil
            nextTick = nil
            judge([], at: t)
        default:
            // Only after a device away from home, changed: turned on, it ends a wait for a visit with none away.
            onlyAway.toggle()
            var expect: [String] = []
            if onlyAway, !visitAway, dep != nil, !depEnded { expect = [W.nowOnlyAway]; dep = nil; depEnded = false; nowOnlyAwayLines += 1 }
            judge(s.setOnlyAway(onlyAway, at: t), at: t, expectLines: expect)
        }
    }
    // After a quit, nothing: the rule is fed everything and says nothing.
    if quit {
        let after = s.sessions(server.register(away: true), at: t + 1) + s.sessions(0, at: t + 2) + s.tick(at: t + 100, mac: .unlocked, display: true)
            + s.called(.unavailable("x"), at: t + 101) + s.switched(!on, at: t + 102) + s.setOnlyAway(!onlyAway, at: t + 103) + s.quit()
        if !after.isEmpty { violated("I8", "run \(run): actions after the quit: \(after)") }
    }
    if !everOn { neverOnRuns += 1 }
}
for name in ["I1", "I2", "I3", "I4", "I5", "I6", "I7", "I8"] {
    check(violations[name] == nil, "\(runs) random sessions hold \(name)" + (violations[name].map { ": \($0) violations, e.g. \(firstViolation[name]!)" } ?? ""))
}
check(locks > 2_000 && outcomes > 1_500 && waitsEnded > 3_000 && returns > 1_000 && quits > 500 && sleeps > 1_000 && neverOnRuns > 1_000
      && unavailable > 100 && failedConfirm > 100 && deviceBackOutcomes > 10 && lockedNoSleep > 100 && notAwayLines > 500
      && nowOnlyAwayLines > 50 && awayLocks > 200 && failuresNoSleepSwitch > 20,
      "the random sessions reach what they test: \(locks) locks (\(awayLocks) only after a device away), \(outcomes) outcomes "
      + "(\(unavailable) unavailable, \(failedConfirm) unconfirmed, \(deviceBackOutcomes) with a device back, \(lockedNoSleep) locked with the "
      + "display left on, \(failuresNoSleepSwitch) failures with it left on), \(waitsEnded) waits ended, \(returns) returns, \(notAwayLines) "
      + "visits at home alone, \(nowOnlyAwayLines) waits ended by the scope's switch, \(quits) quits, \(sleeps) display sleeps, "
      + "\(neverOnRuns) runs never on")

print("privacy: \(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
