// DarkenPolicy (Sources/SillHost/DarkenPolicy.swift; docs/privacy-mode-plan.md, part 2): this Mac's screens dark while a
// device uses it (issues #133 and #323), compiled with StreamProtocol's sources, HostConfig.swift and PrivacyPolicy.swift
// as one module (module.txt).
//
//   Tests/checks/darken/run.sh             compile and run the check
//   Tests/checks/darken/run.sh --mutants   one-line mutants of DarkenPolicy.swift; each must fail it
//
// What it checks: the constants (the lock's wait and confirmation shared, the windows under the lock screen until G0);
// rule 13's screens (through DesktopDisplays.role's real identities); rule 2's sessions that darken; rule 1, off
// (nothing ever); rules 3 and 5, the dark and its raise at a connect (its line, the hint, the order); rule 6, the wait
// (its line, a return, its boundary, two sessions, a move, a move home, a test host's shorter wait) and the hold for the
// lock when the same departure started the lock's wait (held while the lock is under way, never past its bound, never
// for a departure that left a session behind); rule 4, under the lock screen and its fallback; rule 7, a key, a click and
// the pointer on the dark Mac (the lock asked once per confirmation, its confirmation, a lock that does not show or
// cannot be made, the hint's wording and pace, Sill's own events, a locked Mac); rule 8, taken back (the Mac's own unlock
// and the device's, the window, off console, until every session has left or a switch changes); rule 9, the switches;
// rule 11, a quit; rule 12, the watchdog's decisions; rule 13's count; the TEST ONLY hooks; every word; then a model of
// the coordinator's glue running this rule beside the lock's (PrivacyPolicy) through 20,000 seeded random sessions
// against the invariants:
//   I1 the windows are up exactly when the rule says (`up` == `shouldBeUp` after every event), and always while a
//      session that darkens is connected with the switch on, a screen, no quit, not taken back, and (under the lock
//      screen, or unlocked);
//   I2 never up with the switch off, while quitting or with no screen;
//   I3 never up longer than `grace` + `lockConfirm` + the slack, plus one lock asked at a key (`lockConfirm`) and a
//      tick, once no session that darkens is connected (R0: the screen never stays black);
//   I4 a lock only at a person's key or click on the dark, unlocked Mac with keys locking, never while quitting, taken
//      back, or within `lockConfirm` of the last;
//   I5 taken back only by an unlock with no paired device's input at the locked screen in the window before it, and
//      cleared once no session is connected or a switch of darkening changes;
//   I6 `raise` and `lift` alternate, and the glue's windows follow them;
//   I7 Sill's own (tagged) input never does anything;
//   I8 the dark never lifts while the lock its departure started is still under way, within the hold's bound;
//   I9 at a connect that darkens, `raise` comes from the session count, before the glue declares the display wake.
import Foundation

var checks = 0, failures = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String) {
    checks += 1
    if ok { print("ok   \(what())") } else { failures += 1; print("FAIL \(what())") }
}
func same<T: Equatable>(_ got: T, _ want: T, _ what: String) {
    check(got == want, got == want ? what : "\(what): got \(got), want \(want)")
}

typealias D = DarkenPolicy
typealias A = DarkenPolicy.Action
typealias W = DarkenPolicy.Words
typealias PW = PrivacyPolicy.Words
let G = D.grace

func lines(_ a: [A]) -> [String] { a.compactMap { if case .line(let l) = $0 { return l } else { return nil } } }
func hints(_ a: [A]) -> [D.Hint] { a.compactMap { if case .hint(let h, _) = $0 { return h } else { return nil } } }

/// A state with `screens` screens and the Mac read unlocked, nothing connected.
func make(_ scope: HostConfig.Darken = .away, keysLock: Bool = true, lock: Bool = false, under: Bool = true,
          screens: Int = 1, grace: Double = D.grace) -> D.State {
    var s = D.State(scope: scope, keysLock: keysLock, lockAfterSession: lock, grace: grace, underLockScreen: under)
    _ = s.screens(screens, at: 0)
    _ = s.reading(.unlocked, at: 0)
    return s
}

// MARK: - The constants

same(D.grace, PrivacyPolicy.grace, "the dark's wait is the lock's, so one departure ends both together")
same(D.grace, 30, "the wait is 30 s")
same(D.lockConfirm, PrivacyPolicy.lockConfirm, "a lock asked at a key has the lock's 3 s to show")
same(D.remoteUnlockWindow, 10, "an unlock is the device's if it typed at the lock screen in the 10 s before")
check(D.remoteUnlockWindow > 2 + 2, "the window covers the gate's 2 s settle and the typing")
same(D.hintFor, 10, "the hint shows for 10 s")
same(D.hangLimit, 10, "the watchdog waits 10 s")
same(D.relaunchSpacing, 600, "Sill reopens at most once in 10 minutes")
check(D.eventTag != 0 && D.eventTag != 1 && D.eventTag != -1, "the tag is no value a person's hardware or a default sets")
check(D.tick > 0 && D.tick * 2 <= D.lockConfirm, "the tick looks at least twice within a confirmation")
check(D.holdSlack >= 2 * D.tick, "the hold's slack covers the two rules' ticks")
check(D.staysUnderLockScreen, "the black windows sit under the lock screen until the probe G0 says otherwise")

// MARK: - Rule 13: the screens to cover

typealias DD = DesktopDisplays
let builtIn = D.Display(id: 1, vendor: 0x610, product: 0xA050, width: 1512, height: 982)
let dell = D.Display(id: 2, vendor: 0x10AC, product: 0x4205, width: 2560, height: 1440)
let stage = D.Display(id: 3, vendor: DD.sillVendor, product: DD.stageProduct, width: 1920, height: 1080)
let sillDesktop = D.Display(id: 4, vendor: DD.sillVendor, product: DD.desktopProduct, width: 2732, height: 2048)
let standIn = D.Display(id: 5, vendor: 0x756e6b6e, product: 0x76697274, width: 1920, height: 1080)
let gone = D.Display(id: 6, vendor: DD.noMonitor, product: DD.noMonitor, madeByStage: true, width: 1920, height: 1080)
same(D.screens([builtIn, dell]), [1, 2], "the Mac's own panel and a monitor are covered, in the order given")
same(D.screens([dell, builtIn]), [2, 1], "the order is the caller's")
same(D.screens([stage, sillDesktop, standIn, gone]), [], "never Sill's stage or Desktop display, macOS's stand-in, or a display the stage made that has gone")
same(D.screens([stage, dell, sillDesktop]), [2], "a monitor beside Sill's displays")
same(D.screens([D.Display(id: 7, vendor: 0x10AC, product: 1, width: 0, height: 900), D.Display(id: 8, vendor: 0x10AC, product: 1, width: 900, height: 0)]),
     [], "a zero-size display is not covered")
same(D.screens([]), [], "no display, nothing to cover")
same(D.screens([D.Display(id: 9, vendor: DD.sillVendor, product: 9, width: 100, height: 100)]), [9],
     "another display with Sill's vendor number but neither of its products is a screen (DesktopDisplays.role's rule)")

// MARK: - Rule 2: which sessions darken

check(!D.counts(.off, away: true) && !D.counts(.off, away: false), "off: no session darkens")
check(D.counts(.away, away: true) && !D.counts(.away, away: false), "only away: a session away from home, not one at home")
check(D.counts(.any, away: true) && D.counts(.any, away: false), "whenever: every session")

// MARK: - Rule 1: off, nothing ever

do {
    var s = make(.off, lock: true)
    var all: [A] = []
    all += s.sessions(away: 1, home: 1, at: 1)
    all += s.local(.key, tagged: false, at: 2)
    all += s.reading(.screenLocked, at: 3)
    s.deviceInputAtLockedScreen("iPad", at: 3.5)
    all += s.reading(.unlocked, at: 4)
    all += s.sessions(away: 0, home: 0, at: 5)
    all += s.tick(at: 40, lockHolds: true)
    all += s.screens(2, at: 41)
    all += s.screens(0, at: 42)
    all += s.screens(1, at: 43)
    all += s.switched(scope: .off, keysLock: false, lockAfterSession: false, at: 44)
    all += s.called(.unavailable("x"), at: 45)
    same(all, [], "with darkening off nothing happens and nothing is said, whatever comes")
    check(!s.up && !s.pending, "and nothing is up or waiting")
}

// MARK: - Rules 3 and 5: dark while a session that darkens is connected; up at its connect

do {
    var s = make(.away)
    same(s.sessions(away: 0, home: 1, at: 1), [], "only away: a device at home connects, nothing changes")
    let a = s.sessions(away: 1, home: 1, at: 2)
    same(a, [.raise, .line(W.dark(.away, screens: 1)), .hint(.lock, until: 2 + D.hintFor)],
         "a device away from home connects: up first, then its line and the hint for 10 s (rule 5: the glue calls this before the wake)")
    same(lines(a), ["Privacy: this Mac’s screen is dark while a device away from home is connected (1 display)."], "the dark's line")
    check(s.up && !s.pending, "up, nothing waits on the clock")
    same(s.sessions(away: 2, home: 1, at: 3), [], "a second device away: nothing new")
    same(s.sessions(away: 1, home: 1, at: 4), [], "one of two away leaves: still dark, no line")
}
do {
    var s = make(.any, screens: 2)
    let a = s.sessions(away: 0, home: 1, at: 1)
    same(a.first, .raise, "whenever connected: a device at home darkens too, up first")
    same(lines(a), ["Privacy: this Mac’s screen is dark while a device is connected (2 displays)."], "its line, two displays")
}
do {
    var s = make(.any, screens: 0)
    same(s.sessions(away: 1, home: 0, at: 1), [], "no screen to cover (#200's Mac with Sill's display only): nothing goes up")
    let a = s.screens(1, at: 2)
    same(a.first, .raise, "a screen appears while a device is connected: up")
    same(lines(a), [W.dark(.any, screens: 1)], "with the dark's line")
}
do {
    var s = make(.any)
    _ = s.sessions(away: 0, home: 1, at: 1)
    same(s.screens(2, at: 2), [], "a second screen while up: nothing for the rule (the glue covers it)")
    let a = s.screens(0, at: 3)
    same(a, [.line(W.noScreen), .lift], "every screen gone: down, with its line")
    same(s.screens(1, at: 4).first, .raise, "and up again when one comes back")
}
do {
    // A move: the new connection registers before the old one leaves.
    var s = make(.away)
    _ = s.sessions(away: 1, home: 0, at: 1)
    same(s.sessions(away: 2, home: 0, at: 2) + s.sessions(away: 1, home: 0, at: 2.1), [], "a move away to away: nothing")
    // A move home: under "only away" the device no longer darkens; the wait runs as for a departure.
    _ = s.sessions(away: 1, home: 1, at: 3)
    let a = s.sessions(away: 0, home: 1, at: 3.1)
    same(a, [.line(W.lastLeft(G))], "a move home: the last device away has gone; the screen stays dark for the wait")
    check(s.up && s.waitingSince == 3.1 && !s.lockFollows, "up, waiting, and no lock follows (a session is still connected)")
}

// MARK: - Rule 6: the wait, and the hold for the lock

do {
    var s = make(.away)
    _ = s.sessions(away: 1, home: 0, at: 1)
    same(s.sessions(away: 0, home: 0, at: 10), [.line("Privacy: the last device left; this Mac’s screen stays dark for 30 s in case it comes back.")],
         "the last device leaves: its line, still up")
    check(s.up && s.pending && s.waitingSince == 10, "up and waiting")
    same(s.tick(at: 39.9, lockHolds: false), [], "29.9 s later: still dark")
    same(s.tick(at: 40, lockHolds: false), [.line("Privacy: this Mac’s screen is lit again."), .lift], "30 s later: lit again")
    check(!s.up && !s.pending, "down, nothing waits")
    same(s.tick(at: 41, lockHolds: false), [], "nothing after")
}
do {
    var s = make(.away)
    _ = s.sessions(away: 1, home: 0, at: 1)
    _ = s.sessions(away: 0, home: 0, at: 10)
    same(s.sessions(away: 1, home: 0, at: 25), [.line("Privacy: a device came back within 30 s; this Mac’s screen stays dark.")],
         "a device back within the wait: one line, no second raise")
    check(s.up && !s.pending, "up, the wait over")
    same(s.tick(at: 41, lockHolds: false), [], "the old wait's end changes nothing")
}
do {
    var s = make(.away, grace: 5)
    _ = s.sessions(away: 1, home: 0, at: 1)
    same(lines(s.sessions(away: 0, home: 0, at: 2)), [W.lastLeft(5)], "a test host's shorter wait in its line")
    check(W.lastLeft(5).contains(" 5 s "), "the line says 5 s")
    same(s.tick(at: 6.9, lockHolds: false), [], "before 5 s: dark")
    same(s.tick(at: 7, lockHolds: false).last, .lift, "at 5 s: lit")
}
do {
    // The same departure started the lock's wait: the dark holds while the lock is under way.
    var s = make(.away, lock: true)
    _ = s.sessions(away: 1, home: 0, at: 1)
    _ = s.sessions(away: 0, home: 0, at: 10)
    check(s.lockFollows, "no session left with the lock on: the lock's wait started with this one")
    same(s.tick(at: 40, lockHolds: true), [], "the wait's end while the lock is under way: still dark")
    check(s.up && s.pending && s.holdingSince == 10, "held, since the departure")
    same(s.tick(at: 41.5, lockHolds: true), [], "the lock still being confirmed: dark")
    same(s.tick(at: 42, lockHolds: false), [.line(W.lit), .lift], "the lock decided: lit (under the lock screen)")
}
do {
    var s = make(.away, lock: true)
    _ = s.sessions(away: 1, home: 0, at: 1)
    _ = s.sessions(away: 0, home: 0, at: 10)
    _ = s.tick(at: 40, lockHolds: true)
    same(s.tick(at: 43.9, lockHolds: true), [], "a lock that never decides: dark up to its bound")
    same(s.tick(at: 10 + G + D.lockConfirm + D.holdSlack, lockHolds: true).last, .lift,
         "and lit at the wait + the confirmation + the slack, whatever the lock says (R0)")
}
do {
    var s = make(.away, lock: true)
    _ = s.sessions(away: 1, home: 0, at: 1)
    _ = s.sessions(away: 0, home: 0, at: 10)
    same(s.tick(at: 40, lockHolds: false).last, .lift, "the lock's wait ended with no lock (locked already, no display): lit at once")
}
do {
    var s = make(.away, lock: true)
    _ = s.sessions(away: 1, home: 1, at: 1)
    _ = s.sessions(away: 0, home: 1, at: 10)
    check(!s.lockFollows, "a device at home still connected: the lock's wait has not started")
    same(s.tick(at: 40, lockHolds: true).last, .lift, "so the dark's end does not wait for a lock that is not this departure's")
}
do {
    var s = make(.away, lock: true)
    _ = s.sessions(away: 1, home: 0, at: 1)
    _ = s.sessions(away: 0, home: 0, at: 10)
    _ = s.sessions(away: 0, home: 1, at: 12)
    check(!s.lockFollows, "a device at home joins during the wait: the lock's wait ended with it")
    _ = s.sessions(away: 0, home: 0, at: 20)
    check(!s.lockFollows, "and leaving again starts a later lock wait: not this one's")
    same(s.tick(at: 40, lockHolds: true).last, .lift, "the dark's end at 30 s does not hold for it")
}
do {
    var s = make(.away, lock: false)
    _ = s.sessions(away: 1, home: 0, at: 1)
    _ = s.sessions(away: 0, home: 0, at: 10)
    check(!s.lockFollows, "the lock's switch off: no lock follows")
    same(s.tick(at: 40, lockHolds: true).last, .lift, "the dark's end never holds")
}
do {
    var s = make(.away, lock: true)
    _ = s.sessions(away: 1, home: 0, at: 1)
    _ = s.sessions(away: 0, home: 0, at: 10)
    _ = s.tick(at: 40, lockHolds: true)
    same(s.sessions(away: 1, home: 0, at: 41), [.line(W.cameBack(G))], "a device back during the hold: dark goes on")
    check(s.up && s.holdingSince == nil && !s.pending, "no hold, nothing waits")
}

// MARK: - Rule 4: under the lock screen, and the fallback

do {
    var s = make(.away)
    _ = s.sessions(away: 1, home: 0, at: 1)
    same(s.reading(.screenLocked, at: 2), [], "under the lock screen: a lock changes nothing (the lock screen shows above)")
    check(s.up, "still up under it")
    same(s.reading(.offConsole, at: 3), [], "another user on the console: nothing (this session's windows are off the screen)")
}
do {
    var s = make(.away, under: false)
    _ = s.sessions(away: 1, home: 0, at: 1)
    same(s.reading(.screenLocked, at: 2), [.line("Privacy: this Mac is locked; the black lifts so its lock screen shows."), .lift],
         "fallback: a lock takes the black down so the person at the Mac sees the lock screen")
    s.deviceInputAtLockedScreen("iPad", at: 5)
    let a = s.reading(.unlocked, at: 6)
    same(a.first, .line(W.deviceUnlocked("iPad")), "the device's unlock: its line first")
    same(Array(a.dropFirst().prefix(2)), [.raise, .line(W.dark(.away, screens: 1))], "then the black up again")
    same(s.reading(.offConsole, at: 7), [.line(W.lockScreenShows), .lift], "fallback: off console, down too")
}
do {
    var s = D.State(scope: .any, keysLock: true, lockAfterSession: false, underLockScreen: false)
    _ = s.screens(1, at: 0)
    same(s.sessions(away: 0, home: 1, at: 1), [], "fallback: a reading not established yet: nothing up (it could be the lock screen)")
    same(s.reading(.unlocked, at: 2).first, .raise, "up once it reads unlocked")
    var u = D.State(scope: .any, keysLock: true, lockAfterSession: false)
    _ = u.screens(1, at: 0)
    same(u.sessions(away: 0, home: 1, at: 1).first, .raise, "under the lock screen: up before any reading")
}

// MARK: - Rule 7: someone at the Mac

do {
    var s = make(.away)
    _ = s.sessions(away: 1, home: 0, at: 1)
    let k = s.local(.key, tagged: false, at: 20)
    same(k, [.line("Privacy: locking this Mac: someone pressed a key or clicked on it."), .lock, .hint(.lock, until: 30)],
         "a key on the dark Mac: the lock, its line and the hint")
    check(s.pending && s.askedAt == 20, "its confirmation waits on the clock")
    same(s.local(.key, tagged: false, at: 20.5), [], "another key half a second later: no second lock, no hint (a second hasn't passed)")
    same(s.tick(at: 21.5, lockHolds: false), [.look], "the tick asks SessionLock to look while the lock is confirmed")
    same(s.reading(.screenLocked, at: 22), [], "the lock shows: confirmed, nothing more (the lock screen is above)")
    check(s.askedAt == nil && !s.pending && s.up, "nothing waits; still up under the lock screen")
    same(s.local(.key, tagged: false, at: 22.5), [], "a key at the locked Mac: the lock screen takes it")
    s.deviceInputAtLockedScreen("iPad", at: 24)
    same(s.reading(.unlocked, at: 26), [.line(W.deviceUnlocked("iPad"))], "the device typed the password: dark stays")
    same(s.local(.click, tagged: false, at: 26.5), [.line(W.locking), .lock, .hint(.lock, until: 36.5)],
         "a click 6.5 s after the last lock asked: locks again")
}
do {
    var s = make(.away)
    _ = s.sessions(away: 1, home: 0, at: 1)
    _ = s.local(.key, tagged: false, at: 10)
    same(s.local(.click, tagged: false, at: 12.9), [.hint(.lock, until: 22.9)], "within 3 s of the last ask: only the hint")
    same(s.tick(at: 12.95, lockHolds: false), [.look], "still being confirmed")
    let t = s.tick(at: 13, lockHolds: false)
    same(t, [.line("Privacy: couldn’t lock this Mac (it still read unlocked 3 s later); its screen now says to press Control-Command-Q."),
             .hint(.pass, until: 23)], "unlocked 3 s later: the failure's line, and the hint says ⌃⌘Q")
    check(s.keysPass && s.up, "keys pass from now on; still dark")
    same(s.local(.key, tagged: false, at: 20), [.hint(.pass, until: 30)], "a key after a failed lock: the ⌃⌘Q hint, no new lock")
    _ = s.reading(.screenLocked, at: 21)
    check(!s.keysPass, "a lock that shows (the person's ⌃⌘Q) lets keys lock again")
}
do {
    var s = make(.away)
    _ = s.sessions(away: 1, home: 0, at: 1)
    _ = s.local(.key, tagged: false, at: 10)
    same(s.called(.made, at: 10.01), [], "the call made: the reading decides")
    let a = s.called(.unavailable(PW.unavailableLog), at: 10.02)
    same(a, [.line("Privacy: couldn’t lock this Mac (macOS has no SACLockScreenImmediate); its screen now says to press Control-Command-Q."),
             .hint(.pass, until: 20.02)], "no lock call on this macOS: its line, the ⌃⌘Q hint")
    same(s.called(.unavailable(PW.unavailableLog), at: 10.03), [], "answered once")
    same(s.tick(at: 13.5, lockHolds: false), [], "and no confirmation runs out after it")
}
do {
    var s = make(.away, keysLock: false)
    _ = s.sessions(away: 1, home: 0, at: 1)
    same(s.local(.key, tagged: false, at: 12), [.hint(.pass, until: 22)], "keys pass: a key only shows the ⌃⌘Q hint (it reaches the app)")
    same(s.local(.click, tagged: false, at: 12.5), [], "the hint at most once a second")
    same(s.local(.move, tagged: false, at: 13.1), [.hint(.pass, until: 23.1)], "a second later, again")
}
do {
    var s = make(.away)
    _ = s.sessions(away: 1, home: 0, at: 1)
    same(s.local(.move, tagged: false, at: 12), [.hint(.lock, until: 22)], "the pointer moved: only the hint, never a lock")
    same(s.local(.move, tagged: false, at: 12.5), [], "half a second later: nothing")
    same(s.local(.key, tagged: true, at: 14), [], "a key Sill posted (tagged): nothing")
    same(s.local(.click, tagged: true, at: 14), [], "a click Sill posted: nothing")
    same(s.local(.move, tagged: true, at: 30), [], "a move Sill posted: nothing")
}
do {
    var s = make(.away)
    same(s.local(.key, tagged: false, at: 1), [], "nothing connected, not dark: a key is nobody's business")
    _ = s.sessions(away: 0, home: 1, at: 2)
    same(s.local(.key, tagged: false, at: 3), [], "a device at home under only away: not dark, nothing")
    var o = make(.away)
    _ = o.sessions(away: 1, home: 0, at: 1)
    _ = o.reading(.offConsole, at: 2)
    same(o.local(.key, tagged: false, at: 3), [], "off console: nothing counts")
    _ = o.quit(at: 4)
    _ = o.reading(.unlocked, at: 5)
    same(o.local(.key, tagged: false, at: 6), [], "quitting: nothing counts")
}

do {
    // A key in the wait's last moments: the dark holds for that lock's confirmation, then lifts if it did not show.
    var s = make(.away)
    _ = s.sessions(away: 1, home: 0, at: 1)
    _ = s.sessions(away: 0, home: 0, at: 1.5)
    same(s.local(.key, tagged: false, at: 31), [.line(W.locking), .lock, .hint(.lock, until: 41)], "a key half a second before the wait ends")
    same(s.tick(at: 31.5, lockHolds: false), [.look], "the wait over, its lock still being confirmed: still dark")
    check(s.up && s.waitingSince == nil && s.askedAt == 31, "held by that lock alone")
    same(s.tick(at: 34, lockHolds: false), [.line(W.couldNotLock(W.stillUnlocked)), .line(W.lit), .lift],
         "the lock did not show within 3 s: its line, lit")
}
do {
    // A failed lock leaves keys passing until a lock shows or a switch of darkening changes.
    var s = make(.away)
    _ = s.sessions(away: 1, home: 0, at: 1)
    _ = s.local(.key, tagged: false, at: 2)
    _ = s.called(.unavailable(PW.unavailableLog), at: 2.1)
    check(s.keysPass, "keys pass after the call was unavailable")
    _ = s.switched(scope: .any, keysLock: true, lockAfterSession: false, at: 3)
    check(!s.keysPass, "a switch of darkening changed: keys may lock again")
    same(s.local(.key, tagged: false, at: 6).dropLast(), [.line(W.locking), .lock], "and a key asks the lock again")
}

// MARK: - Rule 8: taken back

do {
    var s = make(.away)
    _ = s.sessions(away: 1, home: 0, at: 1)
    _ = s.reading(.screenLocked, at: 5)
    same(s.reading(.unlocked, at: 8), [.line("Privacy: unlocked on this Mac itself; its screen stays lit until every device has left."), .lift],
         "unlocked with nothing typed from a device (Touch ID, the password at the Mac): the Mac's own, lit")
    check(s.takenBack && !s.up, "taken back")
    same(s.sessions(away: 2, home: 0, at: 9), [], "another device away connects: still lit")
    same(s.local(.key, tagged: false, at: 10), [], "keys at the Mac do nothing now")
    same(s.sessions(away: 1, home: 0, at: 11), [], "one leaves: nothing (no wait while taken back)")
    same(s.sessions(away: 0, home: 0, at: 12), [], "the last leaves: no wait, nothing")
    check(!s.takenBack && !s.pending, "taken back ends when no session is connected")
    same(s.sessions(away: 1, home: 0, at: 13).first, .raise, "the next device away darkens it again")
}
do {
    var s = make(.away)
    _ = s.sessions(away: 1, home: 0, at: 1)
    _ = s.reading(.screenLocked, at: 5)
    s.deviceInputAtLockedScreen("iPad (iPad14,1)", at: 6)
    same(s.reading(.unlocked, at: 16), [.line("Privacy: unlocked from iPad (iPad14,1); this Mac’s screen stays dark.")],
         "unlocked 10 s after the device typed: the device's, dark")
    _ = s.reading(.screenLocked, at: 20)
    s.deviceInputAtLockedScreen("iPad", at: 21)
    same(s.reading(.unlocked, at: 31.01), [.line(W.takenBack), .lift], "more than 10 s after: the Mac's own")
}
do {
    var s = make(.away)
    _ = s.sessions(away: 1, home: 0, at: 1)
    s.deviceInputAtLockedScreen("iPad", at: 2)
    _ = s.reading(.screenLocked, at: 3)
    same(s.reading(.unlocked, at: 4), [.line(W.takenBack), .lift], "input from a device while unlocked is no witness for a later unlock")
}
do {
    var s = make(.away)
    _ = s.sessions(away: 1, home: 0, at: 1)
    _ = s.reading(.screenLocked, at: 2)
    s.deviceInputAtLockedScreen("iPad", at: 3)
    _ = s.reading(.offConsole, at: 4)
    same(s.reading(.unlocked, at: 5), [.line(W.takenBack), .lift], "back to the console from another user: always the Mac's own")
}
do {
    var s = make(.away)
    _ = s.sessions(away: 1, home: 0, at: 1)
    _ = s.reading(.screenLocked, at: 2)
    s.deviceInputAtLockedScreen("iPad", at: 3)
    _ = s.reading(.unlocked, at: 4)
    _ = s.reading(.screenLocked, at: 5)
    same(s.reading(.unlocked, at: 6), [.line(W.takenBack), .lift], "a device's input is used once: the next unlock is judged afresh")
}
do {
    var s = make(.away)
    _ = s.sessions(away: 1, home: 0, at: 1)
    _ = s.reading(.screenLocked, at: 2)
    _ = s.reading(.unlocked, at: 3)
    let a = s.switched(scope: .away, keysLock: false, lockAfterSession: false, at: 4)
    same(a.first, .raise, "taken back, then a switch of darkening changes: dark again")
    check(!s.takenBack, "no longer taken back")
}
do {
    var s = make(.away)
    _ = s.sessions(away: 1, home: 0, at: 1)
    _ = s.sessions(away: 0, home: 0, at: 2)
    _ = s.reading(.screenLocked, at: 3)
    same(s.reading(.unlocked, at: 4), [.line(W.takenBack), .lift], "taken back during the wait: lit at once")
    check(!s.pending, "the wait is over")
    same(s.tick(at: 40, lockHolds: true), [], "and its end does nothing")
}
do {
    var s = make(.away)
    _ = s.reading(.screenLocked, at: 1)
    same(s.reading(.unlocked, at: 2), [], "an unlock while not dark: nothing")
    check(!s.takenBack, "and nothing is taken back")
    same(W.deviceUnlocked("iPad\nPrivacy: forged"), "Privacy: unlocked from iPad Privacy: forged; this Mac’s screen stays dark.",
         "a device's name is one line (SafeText)")
    same(W.deviceUnlocked(nil), "Privacy: unlocked from a device; this Mac’s screen stays dark.", "no name: a device")
}

// MARK: - Rule 9: the switches

do {
    var s = make(.away)
    _ = s.sessions(away: 1, home: 0, at: 1)
    same(s.switched(scope: .off, keysLock: true, lockAfterSession: false, at: 2),
         [.line("Privacy: Darken this Mac’s screen is off; this Mac’s screen is lit again."), .lift], "off: lit at once")
    same(s.switched(scope: .away, keysLock: true, lockAfterSession: false, at: 3).first, .raise, "on with a device away: dark at once")
}
do {
    var s = make(.away)
    _ = s.sessions(away: 1, home: 0, at: 1)
    _ = s.sessions(away: 0, home: 0, at: 2)
    same(s.switched(scope: .off, keysLock: true, lockAfterSession: false, at: 3), [.line(W.switchedOff), .lift], "off during the wait: lit at once")
    check(!s.pending, "the wait cancelled")
}
do {
    var s = make(.away)
    _ = s.sessions(away: 0, home: 1, at: 1)
    same(s.switched(scope: .any, keysLock: true, lockAfterSession: false, at: 2).first, .raise, "only away → whenever, a device at home: dark")
    same(s.switched(scope: .away, keysLock: true, lockAfterSession: false, at: 3),
         [.line("Privacy: Darken this Mac’s screen changed, and no device it darkens for is connected; this Mac’s screen is lit again."), .lift],
         "whenever → only away, only a device at home: lit at once, no wait")
    check(!s.pending, "no wait")
}
do {
    var s = make(.away)
    _ = s.sessions(away: 1, home: 0, at: 1)
    same(s.switched(scope: .away, keysLock: false, lockAfterSession: false, at: 2), [.hint(.pass, until: 12)],
         "keys locking → passing while dark: the hint says ⌃⌘Q at once")
    same(s.local(.key, tagged: false, at: 13), [.hint(.pass, until: 23)], "and a key no longer locks")
    same(s.switched(scope: .away, keysLock: false, lockAfterSession: true, at: 14), [], "the lock's switch alone: nothing for the dark")
}
do {
    var s = make(.away, lock: true)
    _ = s.sessions(away: 1, home: 0, at: 1)
    _ = s.sessions(away: 0, home: 0, at: 2)
    same(s.switched(scope: .away, keysLock: false, lockAfterSession: true, at: 3), [.hint(.pass, until: 13)],
         "keys passing during the wait: the hint's new wording, and the wait goes on")
    check(s.pending && s.lockFollows, "still waiting, the lock still following")
    _ = s.switched(scope: .away, keysLock: false, lockAfterSession: false, at: 4)
    check(!s.lockFollows, "the lock's switch off: no lock follows")
    same(s.tick(at: 32, lockHolds: true).last, .lift, "so the wait's end lifts")
}

// MARK: - Rule 11: a quit

do {
    var s = make(.away, lock: true)
    _ = s.sessions(away: 1, home: 0, at: 1)
    same(s.quit(at: 2), [.lift, .line("Privacy: Sill is quitting; this Mac’s screen is lit again.")], "a quit: lit at once, then its line")
    same(s.quit(at: 2.1), [], "once")
    var all: [A] = []
    all += s.sessions(away: 0, home: 0, at: 3)
    all += s.sessions(away: 1, home: 0, at: 4)
    all += s.reading(.screenLocked, at: 5)
    all += s.reading(.unlocked, at: 6)
    all += s.local(.key, tagged: false, at: 7)
    all += s.switched(scope: .any, keysLock: false, lockAfterSession: true, at: 8)
    all += s.screens(0, at: 9)
    all += s.screens(1, at: 10)
    all += s.tick(at: 50, lockHolds: false)
    all += s.called(.unavailable("x"), at: 51)
    same(all, [], "nothing after a quit")
    check(!s.up && !s.pending, "down, nothing waits")
    var n = make(.away)
    same(n.quit(at: 1), [], "a quit with nothing dark: nothing said")
}

// MARK: - Rule 12: a hung Sill

check(!D.watchdogFires(lastBeat: 0, now: 9.99, dark: true), "9.99 s without a beat: not yet")
check(D.watchdogFires(lastBeat: 0, now: 10, dark: true), "10 s: the watchdog ends Sill")
check(!D.watchdogFires(lastBeat: 0, now: 100, dark: false), "never while not dark")
check(D.reopens(lastReopen: nil, now: 5), "the first such end reopens Sill")
check(!D.reopens(lastReopen: 100, now: 699), "not again within 10 minutes")
check(D.reopens(lastReopen: 100, now: 700), "again after them")
check(D.reopens(lastReopen: 100, now: 50), "a clock that went back (a restart) never stops it")

// MARK: - The TEST ONLY hooks

do {
    let env = ["SILL_TEST_PRIVACY_INPUT": "/tmp/x", "SILL_TEST_PRIVACY_LOG": "1"]
    same(D.testHooks(testHost: false, environment: env), D.TestHooks(), "not a test host: no hook taken, no line")
    let h = D.testHooks(testHost: true, environment: env)
    same(h.inputFile, "/tmp/x", "a test host reads the Mac's own input from the file")
    check(h.log, "and stamps its lines")
    same(h.lines.count, 2, "one line each")
    let r = D.testHooks(testHost: true, environment: ["SILL_TEST_PRIVACY_INPUT": "relative", "SILL_TEST_PRIVACY_LOG": "yes"])
    same(r.inputFile, nil, "a relative path is ignored")
    check(!r.log, "SILL_TEST_PRIVACY_LOG takes 1 only")
    same(r.lines, ["SILL_TEST_PRIVACY_INPUT=relative ignored: an absolute path."], "with its line")
    same(D.testHooks(testHost: true, environment: [:]), D.TestHooks(), "nothing set: nothing")
    check(D.testInput("key")! == (.key, false) && D.testInput("click")! == (.click, false) && D.testInput("move")! == (.move, false),
          "the file's words: key, click, move")
    check(D.testInput("key tagged")! == (.key, true) && D.testInput(" move  tagged ")! == (.move, true), "with tagged: one Sill posted")
    check(D.testInput("") == nil && D.testInput("type") == nil && D.testInput("key now") == nil && D.testInput("key tagged twice") == nil,
          "anything else is nothing")
}

// MARK: - Every word

do {
    let all: [String] = [W.dark(.away, screens: 1), W.dark(.any, screens: 2), W.lastLeft(30), W.cameBack(30), W.lit, W.switchedOff,
                         W.noneCounts, W.noScreen, W.quitting, W.locking, W.couldNotLock("why"), W.lockScreenShows, W.takenBack,
                         W.deviceUnlocked("iPad"), W.watchdog, W.reopened]
    check(all.allSatisfy { $0.hasPrefix("Privacy: ") && $0.hasSuffix(".") && !$0.contains("\n") }, "every log line begins with Privacy: and is one sentence")
    check(Set(all).count == all.count, "no two lines alike")
    check(all.allSatisfy { !$0.contains("'") }, "typographic apostrophes only")
    same(W.watchdog, "Privacy: Sill’s main thread hasn’t answered for 10 s while this Mac’s screen was dark; Sill quits so the screen isn’t left black, and opens again.", "the watchdog's line")
    same(W.reopened, "Privacy: Sill opened again after it quit with this Mac’s screen dark (its main thread had stopped answering).", "the line at the next launch")
    same(W.hintFirst, "This Mac is in use from another device.", "the hint's first line")
    same(W.hintSecond(.lock), "Press any key to lock it.", "its second, keys locking")
    same(W.hintSecond(.pass), "To use it here, press Control-Command-Q, then unlock it.", "its second, keys passing")
    same(W.dryRaise(1), "Privacy (test host): would darken 1 display; nothing is drawn.", "a test host's raise")
    same(W.dryRaise(3), "Privacy (test host): would darken 3 displays; nothing is drawn.", "plural")
    same(W.dryLift, "Privacy (test host): would light this Mac’s screen again; nothing was drawn.", "a test host's lift")
    same(W.dryHint(.pass), "Privacy (test host): would show “This Mac is in use from another device. To use it here, press Control-Command-Q, then unlock it.”; nothing is drawn.", "a test host's hint")
    same(W.displays(1) + ", " + W.displays(0) + ", " + W.displays(2), "1 display, 0 displays, 2 displays", "display counts")
    same(W.stillUnlocked, PW.stillUnlockedLog, "the same words as the lock's for a lock that did not show")
}

// MARK: - A model of the glue, both rules together, through random sessions

/// SplitMix64: the same sessions every run.
struct Rng {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func below(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}

var violations: [String: Int] = [:]
var firstViolation: [String: String] = [:]
func violated(_ name: String, _ what: String) {
    violations[name, default: 0] += 1
    if firstViolation[name] == nil { firstViolation[name] = what }
}

let runs = 20_000
let eps = 1e-9
var raises = 0, lifts = 0, keyLocks = 0, holds = 0, takenBacks = 0, deviceUnlocks = 0, waitsLit = 0, fallbackRuns = 0
var rng = Rng(state: 0x5111_DA2C)
for run in 0..<runs {
    let under = rng.below(5) != 0
    if !under { fallbackRuns += 1 }
    let scopes: [HostConfig.Darken] = [.off, .away, .any]
    var scope = scopes[rng.below(3)]
    var keysLock = rng.below(4) != 0
    var lockOn = rng.below(2) == 0
    let grace = rng.below(3) == 0 ? 2.0 : 6.0
    var d = D.State(scope: scope, keysLock: keysLock, lockAfterSession: lockOn, grace: grace, underLockScreen: under)
    var p = PrivacyPolicy.State(on: lockOn, grace: grace)
    var t = 0.0
    var sessions: [Bool] = []           // each connected session's away flag
    var mac: PrivacyPolicy.Mac = .unlocked
    var screens = 1 + rng.below(2)
    var quit = false
    var windows = false                 // what the glue did with the black windows
    var lastCountingAt: Double? = nil   // when the sessions that darken last dropped to none, while none is connected
    var lastAsk: Double? = nil
    var deviceTypedAt: Double? = nil
    var takenBack = false
    var lockWaitFor: Double? = nil      // the departure whose lock the dark may hold for (both waits started together)
    var lockShowsAt: Double? = nil      // a lock asked: the reading says locked then
    var pendingCall: PrivacyPolicy.Call? = nil
    var callFor = 0                     // 1: the dark's lock, 2: the lock rule's
    var nextTick: Double? = nil

    func counting() -> Int { sessions.filter { D.counts(scope, away: $0) }.count }

    _ = d.screens(screens, at: 0)
    _ = d.reading(.unlocked, at: 0)

    func apply(_ actions: [A], from event: String) {
        for a in actions {
            switch a {
            case .raise:
                raises += 1
                if windows { violated("I6", "run \(run): raise while up (\(event)) at \(t)") }
                windows = true
            case .lift:
                lifts += 1
                if !windows { violated("I6", "run \(run): lift while down (\(event)) at \(t)") }
                windows = false
                // I8: never down while the lock its departure started is under way, within the hold's bound.
                if let dep = lockWaitFor, event == "tick", p.pending, t < dep + grace + D.lockConfirm + D.holdSlack - eps {
                    violated("I8", "run \(run): lit \(t - dep) s after the departure while the lock is under way")
                }
            case .lock:
                keyLocks += 1
                if event != "key" && event != "click" { violated("I4", "run \(run): a lock from \(event) at \(t)") }
                if !keysLock || quit || takenBack || mac != .unlocked || !windows {
                    violated("I4", "run \(run): a lock with keys \(keysLock), quit \(quit), taken back \(takenBack), \(mac), up \(windows)")
                }
                if let l = lastAsk, t - l < D.lockConfirm - eps { violated("I4", "run \(run): a lock \(t - l) s after the last") }
                lastAsk = t
                // The lock call: unavailable now and then; made, the reading says locked soon, late, or never.
                if rng.below(6) == 0 {
                    pendingCall = .unavailable(PW.unavailableLog); callFor = 1
                } else {
                    lockShowsAt = rng.below(4) != 0 ? t + rng.unit() * 4 : nil
                }
            case .hint, .look:
                break
            case .line(let l):
                if l == W.takenBack { takenBacks += 1 }
                if l.hasPrefix("Privacy: unlocked from") { deviceUnlocks += 1 }
                if l == W.lit && event == "tick" { waitsLit += 1 }
            }
        }
    }

    func applyLock(_ actions: [PrivacyPolicy.Action]) {
        for a in actions {
            switch a {
            case .lock:
                if rng.below(6) == 0 { pendingCall = .unavailable(PW.unavailableLog); callFor = 2 }
                else { lockShowsAt = rng.below(4) != 0 ? t + rng.unit() * 4 : nil }
            default: break
            }
        }
    }

    /// I1, I2, I3 after every event.
    func invariants(_ event: String) {
        if d.up != d.shouldBeUp { violated("I1", "run \(run): up \(d.up), should \(d.shouldBeUp) after \(event) at \(t)") }
        if windows != d.up { violated("I6", "run \(run): the glue's windows \(windows), the rule's \(d.up) after \(event)") }
        let wanted = scope != .off && counting() > 0 && screens > 0 && !quit && !takenBack && (under || mac == .unlocked)
        if wanted && !windows { violated("I1", "run \(run): down with a session that darkens after \(event) at \(t)") }
        if windows && (scope == .off || quit || screens == 0) { violated("I2", "run \(run): up with scope \(scope), quit \(quit), screens \(screens)") }
        if windows, counting() == 0, let since = lastCountingAt,
           t - since > grace + D.lockConfirm + D.holdSlack + D.lockConfirm + 2 * D.tick + eps {
            violated("I3", "run \(run): up \(t - since) s after the last session that darkens (\(event))")
        }
        if takenBack != d.takenBack { violated("I5", "run \(run): taken back \(d.takenBack), the model's \(takenBack) after \(event)") }
    }

    func setSessions(_ new: [Bool], _ event: String) {
        let before = counting()
        let darkBefore = d.wantsDark
        sessions = new
        if counting() == 0 { if before > 0 { lastCountingAt = t } } else { lastCountingAt = nil }
        if before > 0, counting() == 0, sessions.isEmpty, lockOn, darkBefore { lockWaitFor = t }
        if !sessions.isEmpty { lockWaitFor = nil }
        if sessions.isEmpty { takenBack = false }
        // The glue: the dark's count first, then the wake (the coordinator's `deviceActive(.connect)`), then the server's
        // count for the lock (its own Task).
        let a = d.sessions(away: sessions.filter { $0 }.count, home: sessions.filter { !$0 }.count, at: t)
        apply(a, from: event)
        // I9 (rule 5): a session that darkens is up when the dark's call returns, before the wake is declared; and only
        // a session that darkens joining raises.
        let wanted = scope != .off && counting() > 0 && screens > 0 && !quit && !takenBack && (under || mac == .unlocked)
        if wanted && !windows { violated("I9", "run \(run): not up when \(event) returned, before the wake, at \(t)") }
        if a.contains(.raise), counting() <= before { violated("I9", "run \(run): a raise from \(event) with no session that darkens joining") }
        applyLock(p.sessions(sessions.count, at: t))
        invariants(event)
    }

    while t < 120 && !(quit && t > 1) {
        t += 0.05 + rng.unit() * 1.5
        // The ticks due by now, both rules, the lock's first (each runs on its own Task; the order is not promised, so
        // the dark's hold looks at the lock's `pending` either way).
        while let due = nextTick, due <= t {
            let saved = t
            t = due
            if lockShowsAt.map({ $0 <= t }) ?? false, mac == .unlocked {
                mac = .screenLocked; lockShowsAt = nil
                apply(d.reading(mac, at: t), from: "reading")
                applyLock(p.tick(at: t, mac: mac, display: screens > 0))
                invariants("reading")
            }
            if rng.below(2) == 0 {
                applyLock(p.tick(at: t, mac: mac, display: screens > 0))
                apply(d.tick(at: t, lockHolds: p.pending), from: "tick")
            } else {
                apply(d.tick(at: t, lockHolds: p.pending), from: "tick")
                applyLock(p.tick(at: t, mac: mac, display: screens > 0))
            }
            if d.holdingSince != nil { holds += 1 }
            invariants("tick")
            t = saved
            nextTick = (d.pending || p.pending) ? due + D.tick : nil
        }
        if let call = pendingCall {
            pendingCall = nil
            if callFor == 1 { apply(d.called(call, at: t), from: "call") } else { applyLock(p.called(call, at: t)) }
            invariants("call")
        }
        guard !quit else { break }
        switch rng.below(20) {
        case 0, 1, 2:
            setSessions(sessions + [rng.below(2) == 0], "join")
        case 3, 4:
            if !sessions.isEmpty { var s = sessions; s.remove(at: rng.below(s.count)); setSessions(s, "leave") }
        case 5:
            // A move: the new connection first, then the old one's departure.
            if !sessions.isEmpty {
                let i = rng.below(sessions.count)
                setSessions(sessions + [rng.below(2) == 0], "move")
                var s = sessions; s.remove(at: i); setSessions(s, "move")
            }
        case 6:
            // The Mac's own lock (⌃⌘Q), another user, or back.
            let options: [PrivacyPolicy.Mac] = [.screenLocked, .offConsole, .unlocked]
            let new = options[rng.below(3)]
            if new != mac {
                let was = mac
                mac = new
                if new == .unlocked, was != .unlocked, d.wantsDark {
                    let devices = was == .screenLocked && (deviceTypedAt.map { t - $0 <= D.remoteUnlockWindow } ?? false)
                    if !devices { takenBack = true; lockWaitFor = nil }
                }
                if new == .unlocked { deviceTypedAt = nil }
                apply(d.reading(new, at: t), from: "reading")
                if lockShowsAt != nil, new != .unlocked { lockShowsAt = nil }
                applyLock(p.tick(at: t, mac: mac, display: screens > 0))
                invariants("reading")
            }
        case 7:
            // A paired device types at the locked screen.
            if mac == .screenLocked, !sessions.isEmpty, rng.below(2) == 0 {
                d.deviceInputAtLockedScreen("iPad", at: t)
                deviceTypedAt = t
            }
        case 8, 9, 10:
            let kinds: [D.Local] = [.key, .click, .move]
            let k = kinds[rng.below(3)]
            let tagged = rng.below(4) == 0
            let a = d.local(k, tagged: tagged, at: t)
            if tagged, !a.isEmpty { violated("I7", "run \(run): Sill's own \(k) did \(a)") }
            apply(a, from: k == .key ? "key" : k == .click ? "click" : "move")
            invariants("local")
        case 11:
            let newScope = scopes[rng.below(3)], newKeys = rng.below(4) != 0, newLock = rng.below(2) == 0
            if newScope != scope || newKeys != keysLock { takenBack = false }
            let wasCounting = counting()
            scope = newScope; keysLock = newKeys
            if newScope != d.scope || counting() == 0 { lockWaitFor = nil }
            if newLock != lockOn, !newLock { lockWaitFor = nil }
            if counting() == 0, wasCounting > 0 || newScope != d.scope { lastCountingAt = t }
            if counting() > 0 { lastCountingAt = nil }
            lockOn = newLock
            apply(d.switched(scope: newScope, keysLock: newKeys, lockAfterSession: newLock, at: t), from: "switch")
            applyLock(p.switched(newLock, at: t))
            invariants("switch")
        case 12:
            screens = rng.below(4) == 0 ? 0 : 1 + rng.below(3)
            apply(d.screens(screens, at: t), from: "screens")
            invariants("screens")
        case 13:
            if rng.below(30) == 0 {
                quit = true
                apply(d.quit(at: t), from: "quit")
                applyLock(p.quit())
                if windows { violated("I2", "run \(run): up after the quit") }
            }
        default:
            break
        }
        if nextTick == nil, d.pending || p.pending { nextTick = t + D.tick }
    }
}
for name in ["I1", "I2", "I3", "I4", "I5", "I6", "I7", "I8", "I9"] {
    check(violations[name] == nil, "\(runs) random sessions hold \(name)" + (violations[name].map { ": \($0) violations, e.g. \(firstViolation[name]!)" } ?? ""))
}
check(raises > 10_000 && lifts > 10_000 && keyLocks > 1_000 && holds > 100 && takenBacks > 500 && deviceUnlocks > 100 && waitsLit > 1_000 && fallbackRuns > 1_000,
      "the random sessions reach what they test: \(raises) raises, \(lifts) lifts, \(keyLocks) locks at a key, \(holds) ticks held for a lock, "
      + "\(takenBacks) taken back, \(deviceUnlocks) devices' unlocks, \(waitsLit) waits that ended lit, \(fallbackRuns) runs with the fallback")

print("darken: \(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
