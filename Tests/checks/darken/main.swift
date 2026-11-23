// DarkenPolicy (Sources/SillHost/DarkenPolicy.swift; docs/privacy-mode-plan.md, part 2): this Mac's screens dark while a
// device uses it (issues #133 and #323), compiled with StreamProtocol's sources, HostConfig.swift and PrivacyPolicy.swift
// as one module (module.txt).
//
//   Tests/checks/darken/run.sh             compile and run the check
//   Tests/checks/darken/run.sh --mutants   one-line mutants of DarkenPolicy.swift (and five of PrivacyPolicy.swift's
//                                          switches and route); each must fail it
//
// What it checks: the constants (the lock's wait and confirmation shared, the windows under the lock screen); the probe
// G0's measurements (the black windows' level and opacity); rule 7's events (which count, which are Sill's own); the
// Settings switches as the scope; rule 14, who darkens (Sill.app itself alone, the lock's rule
// PrivacyPolicy.locksForReal; the dry run's words for everything else); rule 13's screens (through
// DesktopDisplays.role's real identities); rule 2's sessions that darken; rule 1, off
// (nothing ever); rules 3 and 5, the dark and its raise at a connect (its line, the hint, the order); rule 6, the wait
// (its line, a return, its boundary, two sessions, a move, a move home, a test host's shorter wait) and the hold for the
// lock when the same departure started the lock's wait (held while the lock is under way, never past its bound, never
// for a departure that left a session behind); rule 4, under the lock screen and its fallback; rule 7, a key, a click and
// the pointer on the dark Mac (the lock asked once per confirmation, its confirmation, a lock that does not show or
// cannot be made, the hint's wording and pace, Sill's own events, a locked Mac); rule 8, taken back (the Mac's own unlock
// and the device's, the window, off console, until every session has left or a switch changes); rule 9, the switches;
// rule 11, a quit; rule 12, the watchdog's decisions and its reopening; rule 13's count; the TEST ONLY hooks; every word
// (the log's, the hint's, the watchdog's, Settings'); both rules
// together, scripted (part 1's three switches and each session's route: a visit away and one at home under only after a
// device away, a device at home left behind, a move home, a switch turned on or off during the waits, the display left
// on); then a model of the coordinator's glue running this rule beside the lock's (PrivacyPolicy, its three switches,
// each session's route given to it as the server orders the callbacks) through 20,000 seeded random sessions against
// the invariants:
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
//   I8 the dark never lifts while the lock its departure started is still under way, within the hold's bound (the lock's
//      own line says whether its wait started with that departure: Only after a device away from home lets a visit
//      at home go);
//   I9 at a connect that darkens, `raise` comes from the session count, before the glue declares the display wake;
//   I10 a hold begins only for a departure that left no session with the lock's switch on, nothing since ending that,
//      while the lock's rule has its wait or a confirmation under way.
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
check(D.staysUnderLockScreen, "the black windows sit under the lock screen (the probe G0 found a level for it)")

// MARK: - The probe G0 (2026-11-23): the black windows' level and opacity

same(D.probeHidden, [996, 101, 23, 20, 19, 14, 2], "what G0 saw stay behind the black: Force Quit, the volume indicator, a notification and Spotlight, Mission Control and the Dock")
same(D.probeSameLevel, 1000, "the screen saver's level, where another app's window was listed in front of the black")
same(D.probeLockScreen, [2001, 2004], "the lock screen's layers, in front of the black")
same(D.assistiveLevel, 1500, "kCGAssistiveTechHighWindowLevel, the highest level macOS names under the lock screen")
check(D.levelFits(D.windowLevel), "the black windows' level fits what G0 measured")
same(D.windowLevel, 1501, "one above the assistive level")
check(D.probeHidden.allSatisfy { $0 < D.windowLevel }, "above everything G0 saw stay hidden")
check(D.windowLevel > D.probeSameLevel && D.windowLevel > D.assistiveLevel, "above every named level under the lock screen: no other app's window ties with it")
check(D.probeLockScreen.allSatisfy { D.windowLevel < $0 } && D.windowLevel <= D.probeLockScreen.min()! - 500,
      "under the lock screen, 500 below it at least, so a person at the Mac always sees it")
check(!D.levelFits(1000), "not the screen saver's level (#184's): another app's window can be ordered in front of it there")
check(!D.levelFits(1500), "not the assistive level: its windows (spoken text's captions, hover text) could show over the black")
check(D.levelFits(1501) && D.levelFits(2000), "anything above 1500 and under the lock screen fits")
check(!D.levelFits(2001) && !D.levelFits(2004) && !D.levelFits(2_147_483_628), "never at or over the lock screen (the shielding level, S3, covered it)")
check(!D.levelFits(996) && !D.levelFits(0), "never with the Force Quit window or ordinary windows")
check(D.windowOpaque, "opaque, as #184's: G0's S2 (not opaque) drew no differently")

// MARK: - Rule 7: which events are this Mac's own, and which Sill posted (G0's step 4)

same(D.localKind(eventType: 10), .key, "a key down is a key")
for t in [1, 3, 25] { same(D.localKind(eventType: t), .click, "mouse button down \(t) is a click") }
for t in [5, 6, 7, 27, 22] { same(D.localKind(eventType: t), .move, "pointer move, drag or scroll \(t) only shows the hint") }
for t in [2, 4, 26, 11, 12, 0, 9, 14, 18, 29, 30, 31, 32] { same(D.localKind(eventType: t), nil, "event type \(t) counts for nothing (an up, a modifier alone, a gesture, anything else)") }
same(Set(D.watchedEventTypes), Set((0..<64).filter { D.localKind(eventType: $0) != nil }), "the observer asks for exactly the events that count")
same(D.watchedEventTypes.count, Set(D.watchedEventTypes).count, "each once")
same(D.eventTag, 0x5349_4C4C_5052_5631, "the tag G0 saw kept in the global monitor (0x53494C4C50525631)")
check(D.ownEvent(userData: D.eventTag, sourcePID: 0, ownPID: 500), "the tag alone: Sill's own (an event a helper of Sill's might post)")
check(D.ownEvent(userData: 0, sourcePID: 500, ownPID: 500), "this process as the source alone: Sill's own (G0: a posted event names its poster)")
check(!D.ownEvent(userData: 0, sourcePID: 0, ownPID: 500), "a person's hardware (G0: process 0, no tag) is a person's")
check(!D.ownEvent(userData: 0, sourcePID: 777, ownPID: 500), "another app's posted event is a person's (someone at the Mac runs it)")
check(!D.ownEvent(userData: 0x1234, sourcePID: 0, ownPID: 500) && !D.ownEvent(userData: D.eventTag &+ 1, sourcePID: 0, ownPID: 500),
      "another tag is not Sill's")

// MARK: - Settings › Devices: the two switches as the scope

same(D.scope(on: false, onlyAway: true), .off, "off, only away remembered: off")
same(D.scope(on: false, onlyAway: false), .off, "off, whenever remembered: off")
same(D.scope(on: true, onlyAway: true), .away, "on, only while a device is away from home")
same(D.scope(on: true, onlyAway: false), .any, "on, whenever a device is connected")

// MARK: - Rule 14: only Sill.app itself darkens (the review of PR #400, follow-up 1)

check(D.darkensForReal(synthetic: false, bundled: true), "Sill.app itself: its own black windows, watch and lock")
check(!D.darkensForReal(synthetic: false, bundled: false),
      "the bare SillMenuBar binary and the CLI (not bundled), even without --synthetic: the dry run")
check(!D.darkensForReal(synthetic: true, bundled: true), "Sill.app with --synthetic: the dry run")
check(!D.darkensForReal(synthetic: true, bundled: false), "a test host: the dry run")
for synthetic in [false, true] {
    for bundled in [false, true] {
        same(D.darkensForReal(synthetic: synthetic, bundled: bundled), PrivacyPolicy.locksForReal(synthetic: synthetic, bundled: bundled),
             "the lock's rule, synthetic \(synthetic), bundled \(bundled): whatever darkens for real locks for real, and nothing else")
    }
}

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
same(D.reopenedWithin, 60, "a launch within a minute of the watchdog's end is its reopening")
check(D.followsWatchdog(record: 100, now: 100) && D.followsWatchdog(record: 100, now: 160), "the launch the watchdog's reopening makes says so")
check(!D.followsWatchdog(record: 100, now: 160.01), "a launch later is an ordinary one")
check(!D.followsWatchdog(record: 100, now: 99), "a record from the future (the clock went back) is no reopening")
check(!D.followsWatchdog(record: nil, now: 5), "no record, no reopening")
same(D.reopenCommand(bundlePath: "/Applications/Sill.app"), ["/usr/bin/open", "-n", "-g", "/Applications/Sill.app"],
     "a new instance of Sill.app's own bundle, in the background")
same(D.reopenCommand(bundlePath: "/Users/x/sill/.build/release"), nil, "never the bare binary's folder")

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
    let stall = D.testHooks(testHost: true, environment: ["SILL_TEST_PRIVACY_STALL": "12"])
    same(stall.stall, 12, "a test host stops its main thread once for SILL_TEST_PRIVACY_STALL's seconds")
    same(stall.lines, ["Test privacy: the main thread stops once for 12 s, a second after the black first goes up (SILL_TEST_PRIVACY_STALL)."], "with its line")
    same(D.testHooks(testHost: false, environment: ["SILL_TEST_PRIVACY_STALL": "12"]).stall, nil, "never anywhere but a test host")
    for raw in ["0.5", "31", "x"] {
        let h = D.testHooks(testHost: true, environment: ["SILL_TEST_PRIVACY_STALL": raw])
        check(h.stall == nil && h.lines == ["SILL_TEST_PRIVACY_STALL=\(raw) ignored: seconds from 1 to 30."], "a stall of \(raw) s is ignored, with its line")
    }
    check(D.testHooks(testHost: true, environment: ["SILL_TEST_PRIVACY_STALL": "1"]).stall == 1
          && D.testHooks(testHost: true, environment: ["SILL_TEST_PRIVACY_STALL": "30"]).stall == 30, "1 and 30 s are taken")
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
                         W.deviceUnlocked("iPad"), W.watchdog, W.watchdogNoReopen, W.reopened, W.noAccessibility,
                         W.startLine(.away, keysLock: true, dry: false), W.startLine(.any, keysLock: false, dry: true)]
    check(all.allSatisfy { $0.hasPrefix("Privacy: ") && $0.hasSuffix(".") && !$0.contains("\n") }, "every log line begins with Privacy: and is one sentence")
    check(Set(all).count == all.count, "no two lines alike")
    check(all.allSatisfy { !$0.contains("'") }, "typographic apostrophes only")
    same(W.watchdog, "Privacy: Sill’s main thread hasn’t answered for 10 s while this Mac’s screen was dark; Sill quits so the screen isn’t left black, and opens again.", "the watchdog's line")
    same(W.reopened, "Privacy: Sill opened again after it quit with this Mac’s screen dark (its main thread had stopped answering).", "the line at the next launch")
    same(W.hintFirst, "This Mac is in use from another device.", "the hint's first line")
    same(W.hintSecond(.lock), "Press any key or click to lock it.", "its second, keys locking: a click too (a secure field withholds keys from an observer, never a click)")
    same(W.hintSecond(.pass), "To use it here, press Control-Command-Q, then unlock it.", "its second, keys passing")
    same(W.dryRaise(1), "Privacy (dry run): would darken 1 display; nothing is drawn.", "the dry run's raise (anything but Sill.app itself)")
    same(W.dryRaise(3), "Privacy (dry run): would darken 3 displays; nothing is drawn.", "plural")
    same(W.dryLift, "Privacy (dry run): would light this Mac’s screen again; nothing was drawn.", "the dry run's lift")
    same(W.dryHint(.pass), "Privacy (dry run): would show “This Mac is in use from another device. To use it here, press Control-Command-Q, then unlock it.”; nothing is drawn.", "the dry run's hint")
    check([W.dryRaise(1), W.dryLift, W.dryHint(.lock), PW.dryLock].allSatisfy { $0.hasPrefix("Privacy (dry run): would ") },
          "the dry curtain's lines begin as the lock's dry run's")
    same(W.startLine(.away, keysLock: true, dry: false),
         "Privacy: Darken this Mac’s screen is on: while a device away from home is connected; a key or click on this Mac locks it.",
         "the start line, only away, keys locking (Sill.app itself)")
    same(W.startLine(.any, keysLock: false, dry: true),
         "Privacy: Darken this Mac’s screen is on: while a device is connected; keys and clicks on this Mac reach its apps. A dry run here (only Sill.app itself darkens a Mac’s screen): it says what it would do.",
         "whenever, keys passing, a dry run: it says so")
    check(W.startLine(.away, keysLock: true, dry: true).hasPrefix(W.startLine(.away, keysLock: true, dry: false)),
          "the dry run's sentence comes after the switch's words")
    same(W.watchdogNoReopen, "Privacy: Sill’s main thread hasn’t answered for 10 s while this Mac’s screen was dark; Sill quits so the screen isn’t left black, and doesn’t open again (it did less than 10 minutes ago).",
         "the watchdog's line within 10 minutes of the last reopening")
    same(W.noAccessibility, "Privacy: Sill can’t notice a key pressed on this Mac without Accessibility; a click still locks it.", "no Accessibility as the screen darkens")
    same(W.dryWatchdog, "Privacy (dry run): Sill’s main thread hasn’t answered for 10 s while this Mac’s screen was dark; would quit Sill and open it again; nothing quits.",
         "the watchdog's dry run (anything but Sill.app itself)")
    check(W.dryWatchdog.hasPrefix("Privacy (dry run): "), "it begins as every dry run's line")
    // Settings › Devices
    same(W.toggle, "Darken this Mac’s screen", "the switch")
    same(W.awayToggle, "Only while a device is away from home", "the scope's switch under it")
    same(W.keysToggle, "A key or click on this Mac locks it", "the keys' switch under it")
    same(W.footnoteOff, "For a Mac you use from afar: its displays stay black while you use it, so people near it see nothing.", "the footnote, off")
    same(W.footnoteOn(onlyAway: true, keysLock: true),
         "This Mac’s displays turn black while an iPhone or iPad uses it from away from home (through a VPN or over the internet), so people near it see nothing. They come back 30 seconds after the last one leaves. A key or click on this Mac locks it; unlock it here with your password or Touch ID and its displays stay lit until every device has left.",
         "the footnote, on as it comes: only away, keys locking")
    same(W.footnoteOn(onlyAway: false, keysLock: false),
         "This Mac’s displays turn black while an iPhone or iPad is connected, so people near it see nothing. They come back 30 seconds after the last one leaves. Keys and clicks on this Mac still reach its apps, unseen. To use it here, press Control-Command-Q, then unlock it.",
         "the footnote, whenever, keys passing")
    check(W.footnoteOn(onlyAway: true, keysLock: false, grace: 1).contains("They come back 1 second after"), "the footnote says the wait it has")
    same(W.accessibilityWarning, "Sill needs Accessibility to notice a key pressed on this Mac; a click still locks it. Allow it in Settings › Permissions.",
         "the warning without Accessibility")
    let settings = [W.toggle, W.awayToggle, W.keysToggle, W.footnoteOff, W.footnoteOn(onlyAway: true, keysLock: true),
                    W.footnoteOn(onlyAway: false, keysLock: false), W.accessibilityWarning]
    check(settings.allSatisfy { !$0.contains("'") && !$0.contains("\n") }, "Settings' words: typographic apostrophes, one line each")
    check([W.toggle, W.awayToggle, W.keysToggle].allSatisfy { !$0.hasSuffix(".") }, "a switch's title has no full stop")
    check([W.footnoteOff, W.footnoteOn(onlyAway: true, keysLock: true), W.accessibilityWarning].allSatisfy { $0.hasSuffix(".") }, "footnotes and the warning are sentences")
    same(W.displays(1) + ", " + W.displays(0) + ", " + W.displays(2), "1 display, 0 displays, 2 displays", "display counts")
    same(W.stillUnlocked, PW.stillUnlockedLog, "the same words as the lock's for a lock that did not show")
}

// MARK: - Both rules together: part 1's switches and each session's route (the review of PR #400, follow-up 2)

/// Darkening beside the lock (part 1's PrivacyPolicy with its three switches: Lock this Mac when the last device leaves,
/// Turn off its display too, Only after a device away from home), run as the coordinator runs them: at a registration
/// the server's count first (the lock's `sessions`, then `joined(away:)` with the session's route: onClientCountChanged
/// comes before onClientConnected), then the dark's sessions; at a departure the dark's first (onClientDisconnected
/// comes before onClientCountChanged), then the lock's count; the switches as setTarget gives them (the lock's, then the
/// dark's); both rules' ticks every `D.tick`, the lock's first, the dark reading the lock's `pending`; a lock asked shows
/// in the reading 1 s later. Every action of both, with its time.
struct Pair {
    var d: D.State
    var p: PrivacyPolicy.State
    var away = 0, home = 0
    var mac: PrivacyPolicy.Mac = .unlocked
    var askedAt: Double?
    var t = 0.0
    var log: [(t: Double, what: String)] = []

    init(_ scope: HostConfig.Darken, lock: Bool, sleeps: Bool = true, onlyAway: Bool = false) {
        d = D.State(scope: scope, keysLock: true, lockAfterSession: lock)
        p = PrivacyPolicy.State(on: lock, sleeps: sleeps, onlyAway: onlyAway)
        _ = d.screens(1, at: 0)
        _ = d.reading(.unlocked, at: 0)
    }

    mutating func dark(_ actions: [A]) {
        for a in actions {
            switch a {
            case .raise: log.append((t, "dark raise"))
            case .lift: log.append((t, "dark lift"))
            case .lock: log.append((t, "dark lock"))
            case .line(let l): log.append((t, "dark: " + l))
            case .hint, .look: break
            }
        }
    }

    mutating func lock(_ actions: [PrivacyPolicy.Action]) {
        for a in actions {
            switch a {
            case .lock: log.append((t, "lock lock")); askedAt = t
            case .sleepDisplays: log.append((t, "lock sleepDisplays"))
            case .line(let l): log.append((t, "lock: " + l))
            case .look: break
            }
        }
    }

    /// Both rules' ticks up to `until`.
    mutating func run(to until: Double) {
        while t + D.tick <= until + 1e-9 {
            t += D.tick
            if let asked = askedAt, t >= asked + 1, mac == .unlocked {
                mac = .screenLocked
                askedAt = nil
                dark(d.reading(mac, at: t))
            }
            lock(p.tick(at: t, mac: mac, display: true))
            dark(d.tick(at: t, lockHolds: p.pending))
        }
        t = until
    }

    mutating func join(away isAway: Bool, at time: Double) {
        run(to: time)
        if isAway { away += 1 } else { home += 1 }
        lock(p.sessions(away + home, at: t))
        p.joined(away: isAway)
        dark(d.sessions(away: away, home: home, at: t))
    }

    mutating func leave(away isAway: Bool, at time: Double) {
        run(to: time)
        if isAway { away -= 1 } else { home -= 1 }
        dark(d.sessions(away: away, home: home, at: t))
        lock(p.sessions(away + home, at: t))
    }

    /// The switches as setTarget gives them: PrivacyLock.switched (its display, the lock, only away), then the dark's.
    mutating func switches(lock on: Bool, sleeps: Bool = true, onlyAway: Bool, scope: HostConfig.Darken, at time: Double) {
        run(to: time)
        p.setSleeps(sleeps)
        lock(p.switched(on, at: t))
        lock(p.setOnlyAway(onlyAway, at: t))
        dark(d.switched(scope: scope, keysLock: d.keysLock, lockAfterSession: on, at: t))
    }

    /// When `what` happened.
    func at(_ what: String) -> [Double] { log.filter { $0.what == what }.map(\.t) }
}

do {
    var b = Pair(.away, lock: true, onlyAway: true)
    b.join(away: true, at: 1)
    b.leave(away: true, at: 10)
    b.run(to: 45)
    same(b.at("lock: " + PW.lastLeft(G)), [10], "only away, and the lock only after a device away: a device away leaves, the lock's wait starts")
    same(b.at("dark: " + W.lastLeft(G)), [10], "and the dark's, at the same departure")
    same(b.at("lock lock"), [40], "the lock at the wait's end")
    same(b.at("lock: " + PW.lockedAndSleeps), [41], "confirmed when the reading says locked, its display asleep")
    same(b.at("dark lift"), [41], "the dark held through the lock, lit once it showed and never before (rule 6)")
}
do {
    var b = Pair(.any, lock: true, onlyAway: true)
    b.join(away: false, at: 1)
    b.leave(away: false, at: 10)
    b.run(to: 50)
    same(b.at("dark raise"), [1], "whenever: a device at home darkens")
    same(b.at("lock: " + PW.notAway), [10], "the lock only after a device away: a visit at home starts no lock's wait")
    same(b.at("lock lock"), [], "and no lock comes")
    same(b.at("dark lift"), [40], "so the dark is lit at its own wait's end, held for no lock")
}
do {
    var b = Pair(.any, lock: true, onlyAway: true)
    b.join(away: true, at: 1)
    b.join(away: false, at: 2)
    b.leave(away: true, at: 5)
    b.leave(away: false, at: 10)
    b.run(to: 45)
    same(b.at("dark: " + W.lastLeft(G)) + b.at("lock: " + PW.lastLeft(G)), [10, 10],
         "whenever, a visit with a device away that left first: both waits start at the last departure, the one at home")
    same(b.at("lock lock"), [40], "the lock, for the visit had a device away")
    same(b.at("dark lift"), [41], "and the dark held for it")
}
do {
    var b = Pair(.away, lock: true)
    b.join(away: true, at: 1)
    b.join(away: false, at: 2)
    b.leave(away: true, at: 5)
    b.leave(away: false, at: 10)
    b.run(to: 45)
    same(b.at("dark: " + W.lastLeft(G)), [5], "only away: the last device away leaves, the dark's wait (a device at home stays)")
    same(b.at("lock: " + PW.lastLeft(G)), [10], "the lock's wait at the last departure of all")
    same(b.at("dark lift"), [35], "the dark lit at its own end: its departure left a device behind, so no lock followed it")
    same(b.at("lock lock"), [40], "the lock 30 s after the device at home left")
    same(b.at("dark raise"), [1], "nothing darkened again for the device at home")
}
do {
    var b = Pair(.away, lock: true, onlyAway: true)
    b.join(away: true, at: 1)
    b.join(away: false, at: 10)   // a move home: its new connection first
    b.leave(away: true, at: 10)   // then the old one away leaves
    b.leave(away: false, at: 20)
    b.run(to: 55)
    same(b.at("dark: " + W.lastLeft(G)), [10], "a move home under only away: the dark's wait")
    same(b.at("lock: " + PW.lastLeft(G)), [20], "the lock's at the departure from home (the visit had a device away)")
    same(b.at("dark lift"), [40], "the dark lit at its own end, never held for that later lock")
    same(b.at("lock lock"), [50], "the lock 30 s after that departure")
}
do {
    var b = Pair(.any, lock: true)
    b.join(away: false, at: 1)
    b.leave(away: false, at: 10)
    b.switches(lock: true, onlyAway: true, scope: .any, at: 15)
    b.run(to: 50)
    same(b.at("lock: " + PW.nowOnlyAway), [15], "only after a device away turned on during a visit at home's waits: the lock's ends")
    same(b.at("lock lock"), [], "no lock")
    same(b.at("dark lift"), [40], "the dark's wait goes on (none of its switches changed) and ends lit, held for nothing")
}
do {
    var b = Pair(.away, lock: false)
    b.join(away: true, at: 1)
    b.switches(lock: true, onlyAway: false, scope: .away, at: 5)
    b.leave(away: true, at: 10)
    b.run(to: 45)
    same(b.at("lock lock"), [40], "the lock's switch turned on while a device is connected: its departure locks")
    same(b.at("dark lift"), [41], "and the dark, told of that switch, holds for that lock")
}
do {
    var b = Pair(.away, lock: true, sleeps: false)
    b.join(away: true, at: 1)
    b.leave(away: true, at: 10)
    b.run(to: 45)
    same(b.at("lock: " + PW.locked), [41], "Turn off its display too off: locked, its display left on")
    same(b.at("lock sleepDisplays"), [], "no display sleep")
    same(b.at("dark lift"), [41], "the dark held for the lock as with it on: that switch is the lock's alone")
}
do {
    var b = Pair(.away, lock: true)
    b.join(away: true, at: 1)
    b.leave(away: true, at: 10)
    b.switches(lock: false, onlyAway: false, scope: .away, at: 20)
    b.run(to: 45)
    same(b.at("lock: " + PW.switchedOff), [20], "the lock's switch off during the waits: its wait ends")
    same(b.at("lock lock"), [], "no lock")
    same(b.at("dark lift"), [40], "the dark ends at its own time, held for nothing")
}
do {
    var b = Pair(.away, lock: true, onlyAway: true)
    b.join(away: true, at: 1)
    b.leave(away: true, at: 10)
    b.join(away: false, at: 12)
    b.leave(away: false, at: 20)
    b.run(to: 55)
    same(b.at("lock: " + PW.cameBack(G)), [12], "a device at home during the waits: the lock's wait ends")
    same(b.at("lock: " + PW.lastLeft(G)), [10, 20], "and starts again as it leaves (the visit had a device away)")
    same(b.at("dark lift"), [40], "the dark, which a device at home does not keep, lit at its own end: not held for the later lock")
    same(b.at("lock lock"), [50], "the lock 30 s after the device at home left")
}
do {
    var b = Pair(.away, lock: false)
    b.join(away: true, at: 1)
    b.leave(away: true, at: 10)
    b.run(to: 45)
    same(b.at("lock: " + PW.lastLeft(G)) + b.at("lock lock"), [], "the lock's switch off: darkening alone, no lock's wait and no lock")
    same(b.at("dark lift"), [40], "the dark lit at its own wait's end")
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
var holdsBegun = 0, onlyAwayHolds = 0, visitsAtHomeLetGo = 0, onlyAwayEndedWaits = 0, displayOnLocks = 0
var rng = Rng(state: 0x5111_DA2C)
for run in 0..<runs {
    let under = rng.below(5) != 0
    if !under { fallbackRuns += 1 }
    let scopes: [HostConfig.Darken] = [.off, .away, .any]
    var scope = scopes[rng.below(3)]
    var keysLock = rng.below(4) != 0
    var lockOn = rng.below(2) == 0
    // Part 1's two other switches (the review of PR #400, follow-up 2): its display, and only after a device away.
    var lockSleeps = rng.below(3) != 0
    var lockOnlyAway = rng.below(3) == 0
    let grace = rng.below(3) == 0 ? 2.0 : 6.0
    var d = D.State(scope: scope, keysLock: keysLock, lockAfterSession: lockOn, grace: grace, underLockScreen: under)
    var p = PrivacyPolicy.State(on: lockOn, sleeps: lockSleeps, onlyAway: lockOnlyAway, grace: grace)
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
    var lockWaitFor: Double? = nil      // the departure that started the dark's wait and the lock's own (its line said)
    var holdAllowed = false             // the dark's wait's departure left no session with the lock on, and nothing since ended that
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

    /// The lock's actions; whether its wait started (its own line says so, whatever its switches decided).
    @discardableResult
    func applyLock(_ actions: [PrivacyPolicy.Action]) -> Bool {
        var started = false
        for a in actions {
            switch a {
            case .lock:
                if rng.below(6) == 0 { pendingCall = .unavailable(PW.unavailableLog); callFor = 2 }
                else { lockShowsAt = rng.below(4) != 0 ? t + rng.unit() * 4 : nil }
            case .line(let l):
                if l == PW.lastLeft(grace) { started = true }
                if l == PW.notAway { visitsAtHomeLetGo += 1 }
                if l == PW.nowOnlyAway { onlyAwayEndedWaits += 1 }
                if l == PW.locked { displayOnLocks += 1 }
            default: break
            }
        }
        return started
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

    /// A session registers (the last of `new`, its route with it) or leaves, in the server's order: at a registration
    /// the count first (the lock's `sessions`, then `joined(away:)`: onClientCountChanged comes before
    /// onClientConnected), then the dark's sessions and the wake; at a departure the dark's first (onClientDisconnected
    /// comes before onClientCountChanged), then the lock's count. Each callback is a main-actor Task of its own.
    func setSessions(_ new: [Bool], _ event: String) {
        let before = counting()
        let darkBefore = d.wantsDark
        let joining = new.count > sessions.count ? new.last : nil
        sessions = new
        if counting() == 0 { if before > 0 { lastCountingAt = t } } else { lastCountingAt = nil }
        if sessions.isEmpty { takenBack = false }
        var lockStarted = false
        if let away = joining {
            lockStarted = applyLock(p.sessions(sessions.count, at: t))
            p.joined(away: away)
        }
        let a = d.sessions(away: sessions.filter { $0 }.count, home: sessions.filter { !$0 }.count, at: t)
        apply(a, from: event)
        // I9 (rule 5): a session that darkens is up when the dark's call returns, before the wake is declared; and only
        // a session that darkens joining raises.
        let wanted = scope != .off && counting() > 0 && screens > 0 && !quit && !takenBack && (under || mac == .unlocked)
        if wanted && !windows { violated("I9", "run \(run): not up when \(event) returned, before the wake, at \(t)") }
        if a.contains(.raise), counting() <= before { violated("I9", "run \(run): a raise from \(event) with no session that darkens joining") }
        if joining == nil { lockStarted = applyLock(p.sessions(sessions.count, at: t)) }
        // The dark's wait started at this departure: whether the lock may hold it (no session left, the lock on), and,
        // for I8, whether the lock's own wait started with it (Only after a device away from home lets a visit at home go).
        if !sessions.isEmpty { lockWaitFor = nil; holdAllowed = false }
        if before > 0, counting() == 0, darkBefore {
            holdAllowed = sessions.isEmpty && lockOn
            lockWaitFor = lockStarted ? t : nil
        }
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
            let wasHolding = d.holdingSince != nil
            var lockHolds = false
            if rng.below(2) == 0 {
                applyLock(p.tick(at: t, mac: mac, display: screens > 0))
                lockHolds = p.pending
                apply(d.tick(at: t, lockHolds: lockHolds), from: "tick")
            } else {
                lockHolds = p.pending
                apply(d.tick(at: t, lockHolds: lockHolds), from: "tick")
                applyLock(p.tick(at: t, mac: mac, display: screens > 0))
            }
            if d.holdingSince != nil { holds += 1 }
            // I10: a hold begins only for a departure that left no session with the lock's switch on (nothing since ending
            // that: a session, the lock's switch off, a change of scope, taken back), while the lock's rule has its wait
            // or a confirmation under way.
            if !wasHolding, d.holdingSince != nil {
                holdsBegun += 1
                if lockOnlyAway { onlyAwayHolds += 1 }
                if !holdAllowed || !lockHolds {
                    violated("I10", "run \(run): a hold begun at \(t) (allowed \(holdAllowed), the lock under way \(lockHolds))")
                }
            }
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
                    if !devices { takenBack = true; lockWaitFor = nil; holdAllowed = false }
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
            let newSleeps = rng.below(3) != 0, newOnlyAway = rng.below(3) == 0
            if newScope != scope || newKeys != keysLock { takenBack = false }
            let wasCounting = counting()
            scope = newScope; keysLock = newKeys
            if newScope != d.scope { lockWaitFor = nil; holdAllowed = false }
            if newLock != lockOn, !newLock { lockWaitFor = nil; holdAllowed = false }
            if counting() == 0, wasCounting > 0 || newScope != d.scope { lastCountingAt = t }
            if counting() > 0 { lastCountingAt = nil }
            lockOn = newLock; lockSleeps = newSleeps; lockOnlyAway = newOnlyAway
            // As setTarget gives them: the lock's (PrivacyLock.switched: its display, the switch, only away), then the dark's.
            p.setSleeps(lockSleeps)
            let lockActions = p.switched(lockOn, at: t) + p.setOnlyAway(lockOnlyAway, at: t)
            if lockActions.contains(.line(PW.nowOnlyAway)) { lockWaitFor = nil }
            applyLock(lockActions)
            apply(d.switched(scope: newScope, keysLock: newKeys, lockAfterSession: newLock, at: t), from: "switch")
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
for name in ["I1", "I2", "I3", "I4", "I5", "I6", "I7", "I8", "I9", "I10"] {
    check(violations[name] == nil, "\(runs) random sessions hold \(name)" + (violations[name].map { ": \($0) violations, e.g. \(firstViolation[name]!)" } ?? ""))
}
check(raises > 10_000 && lifts > 10_000 && keyLocks > 1_000 && holds > 100 && takenBacks > 500 && deviceUnlocks > 100 && waitsLit > 1_000 && fallbackRuns > 1_000,
      "the random sessions reach what they test: \(raises) raises, \(lifts) lifts, \(keyLocks) locks at a key, \(holds) ticks held for a lock, "
      + "\(takenBacks) taken back, \(deviceUnlocks) devices' unlocks, \(waitsLit) waits that ended lit, \(fallbackRuns) runs with the fallback")
check(holdsBegun > 100 && onlyAwayHolds > 20 && visitsAtHomeLetGo > 100 && onlyAwayEndedWaits > 10 && displayOnLocks > 50,
      "and part 1's switches with each session's route beside the dark: \(holdsBegun) holds begun, \(onlyAwayHolds) of them under only "
      + "after a device away, \(visitsAtHomeLetGo) visits at home the lock let go, \(onlyAwayEndedWaits) lock waits only away ended, "
      + "\(displayOnLocks) locks with the display left on")

print("darken: \(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
