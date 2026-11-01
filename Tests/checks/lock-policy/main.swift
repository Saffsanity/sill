// LockPolicy (Sources/SillHost/LockPolicy.swift; docs/locked-mac-plan.md), pure, compiled with
// StreamProtocol's sources as one module (the real files: module.txt): the three readings and how the
// witnesses make one (unknown counts as locked), what each notification sets, the effective reading's
// settle (an unlock only after 2 s of every witness saying so and a session read made since), when
// SessionLock reads, what each reading allows, what the server's gate withholds, a device's requests at
// each reading, the window list, the placeholder's size, the window that comes back, the TEST ONLY hooks'
// words, the lines, LockGate, the device's words and cover (Switcher.swift's LockedMac), and a copy of
// the coordinator's glue (StreamCoordinator.swift's `lockChanged`, `enforceLock`, `select`'s gate and its
// end, `lockedMidSwitch`, `afterUnlock`, `handle`'s weighing at the reading as a message arrived and now)
// run through directed and random sessions: no window and no display starts streaming while the gate
// reads locked, a locked Mac with a device settles on the placeholder, a pick made while locked never
// streams, and what streamed at the lock comes back after the unlock unless a pick, its closing or
// nobody left says otherwise.
import Foundation
import AppKit

var checks = 0, failures = 0
func check(_ ok: Bool, _ what: String) {
    checks += 1
    if ok { print("ok   \(what)") } else { failures += 1; print("FAIL \(what)") }
    fflush(stdout)
}
func json<T: Encodable>(_ v: T) -> String { String(decoding: Wire.encode(v), as: UTF8.self) }
/// The same with its keys sorted: two encodes of one value need not list them in one order.
func sortedJSON<T: Encodable>(_ v: T) -> String {
    let e = JSONEncoder()
    e.outputFormatting = [.sortedKeys]
    return String(decoding: (try? e.encode(v)) ?? Data(), as: UTF8.self)
}

typealias P = LockPolicy
typealias R = LockPolicy.Request
typealias Reading = LockPolicy.Reading
let readings = Reading.allCases

// MARK: - The readings

check(readings == [.unlocked, .screenLocked, .offConsole], "three readings, in the order of what each keeps from the devices")
check(Reading.unlocked < .screenLocked && Reading.screenLocked < .offConsole, "unlocked < screen locked < off console")
check(!Reading.unlocked.locked && Reading.screenLocked.locked && Reading.offConsole.locked, "both locked readings are locked")
for a in readings { for b in readings {
    check(P.restrictive(a, b) == max(a, b) && P.restrictive(a, b) == P.restrictive(b, a), "restrictive(\(a), \(b)) is the more restrictive")
} }

// MARK: - The witnesses' readers

let me: UInt32 = 501
check(P.console(name: "noah", uid: me, ownUID: me, readable: true) == .thisUser, "the console's user is this one: this user")
check(P.console(name: "loginwindow", uid: 0, ownUID: me, readable: true) == .otherUser,
      "loginwindow on the console (a fast user switch, uid 0): another user")
check(P.console(name: "loginwindow", uid: me, ownUID: me, readable: true) == .otherUser, "loginwindow is never this user, whatever its uid")
check(P.console(name: "alex", uid: 502, ownUID: me, readable: true) == .otherUser, "another user's session: another user")
check(P.console(name: nil, uid: 0, ownUID: me, readable: true) == .nobody && P.console(name: "", uid: me, ownUID: me, readable: true) == .nobody,
      "no console user: nobody")
check(P.console(name: "noah", uid: me, ownUID: me, readable: false) == .unreadable, "the dynamic store not asked: unreadable")

check(P.screen(registered: 0, got: 0, state: 0) == .unlocked, "notify state 0: the screen unlocked")
check(P.screen(registered: 0, got: 0, state: 1) == .locked && P.screen(registered: 0, got: 0, state: 7) == .locked, "notify state not 0: locked")
check(P.screen(registered: 1, got: 0, state: 0) == .unreadable && P.screen(registered: 0, got: 2, state: 0) == .unreadable,
      "a registration or a read that failed: unreadable")
check(P.screenStateName == "com.apple.sessionagent.screenIsLocked", "the screen's notify name")

check(P.session(nil) == .noDictionary, "no session dictionary (no GUI session): none")
check(P.session([:]) == .offConsole, "a dictionary without kCGSSessionOnConsoleKey: off console")
check(P.session(["kCGSSessionOnConsoleKey": NSNumber(value: 0)]) == .offConsole, "kCGSSessionOnConsoleKey 0: off console")
check(P.session(["kCGSSessionOnConsoleKey": NSNumber(value: 1)]) == .unlocked, "on the console, no lock key: unlocked")
check(P.session(["kCGSSessionOnConsoleKey": NSNumber(value: 1), "CGSSessionScreenIsLocked": NSNumber(value: 1)]) == .screenLocked,
      "CGSSessionScreenIsLocked 1: screen locked")
check(P.session(["kCGSSessionOnConsoleKey": NSNumber(value: 1), "CGSSessionScreenIsLocked": NSNumber(value: 0)]) == .unlocked,
      "CGSSessionScreenIsLocked 0: unlocked")
check(P.session(["kCGSSessionOnConsoleKey": NSNumber(value: 1), "CGSSessionScreenIsLocked": "yes"]) == .screenLocked,
      "CGSSessionScreenIsLocked that is not a number: screen locked")
check(P.session(["kCGSSessionOnConsoleKey": "1"]) == .offConsole, "kCGSSessionOnConsoleKey that is not a number: off console")

// MARK: - The witnesses' reading (every combination)

let consoles: [P.Console] = [.notRead, .thisUser, .otherUser, .nobody, .unreadable]
let screens: [P.Screen] = [.notRead, .locked, .unlocked, .unreadable]
let sessions: [P.Session] = [.notRead, .unlocked, .screenLocked, .offConsole, .noDictionary, .unanswered]
/// The plan's rule, written again: off console when any console witness says so or the user is unknown;
/// else locked when any screen witness says so or one is unknown; the test hook's reading added.
func expectedReading(_ w: P.Witnesses) -> Reading {
    if w.test == .offConsole || w.console != .thisUser || w.consoleNote == .offConsole || w.session == .offConsole { return .offConsole }
    if w.test == .screenLocked || w.screen != .unlocked || w.screenNote == .screenLocked || w.session != .unlocked { return .screenLocked }
    return .unlocked
}
var combos = 0, wrong = 0, unlockedCombos = 0
var firstWrong: String?
for c in consoles { for s in screens { for d in sessions { for sn in [nil, P.Note.screenLocked] { for cn in [nil, P.Note.offConsole] {
    for t in [nil] + readings {
        var w = P.Witnesses()
        w.console = c; w.screen = s; w.session = d; w.screenNote = sn; w.consoleNote = cn; w.test = t
        combos += 1
        let got = P.reading(w)
        if got != expectedReading(w) { wrong += 1; if firstWrong == nil { firstWrong = "\(w) read \(got)" } }
        if got == .unlocked { unlockedCombos += 1 }
        // A session read is wanted exactly when every other witness says unlocked.
        var others = w; others.session = .unlocked
        if P.wantsSessionRead(w) != (P.reading(others) == .unlocked) { wrong += 1; if firstWrong == nil { firstWrong = "wantsSessionRead \(w)" } }
    }
} } } } }
check(wrong == 0 && combos == 5 * 4 * 6 * 2 * 2 * 4, "\(combos) witness combinations read as the rule says" + (firstWrong.map { ": \($0)" } ?? ""))
check(unlockedCombos == 2, "only every witness saying unlocked (and the test hook nothing or unlocked) reads unlocked: \(unlockedCombos) of \(combos)")
var w0 = P.Witnesses()
check(P.reading(w0) == .offConsole, "nothing read yet: off console (unknown counts as locked)")
w0.console = .thisUser; w0.screen = .unlocked; w0.session = .unlocked
check(P.reading(w0) == .unlocked, "every witness unlocked: unlocked")
var wl = w0; wl.screenNote = .screenLocked
check(P.reading(wl) == .screenLocked, "a lock notification with no unlock yet: screen locked")
var wu = w0; wu.session = .unanswered
check(P.reading(wu) == .screenLocked, "a session read that did not answer within its bound: locked")
var wn = w0; wn.screen = .unreadable
check(P.reading(wn) == .screenLocked, "the screen's state that cannot be read: locked")
var wf = w0; wf.console = .otherUser
check(P.reading(wf) == .offConsole, "another user (loginwindow) on the console: off console, whatever the screen says")
var wfs = w0; wfs.consoleNote = .offConsole
check(P.reading(wfs) == .offConsole, "a switch-away notification with no switch back: off console")
var wt = w0; wt.test = .screenLocked
check(P.reading(wt) == .screenLocked, "a test host's hook says locked: locked")
check(!P.wantsSessionRead(wl) && P.wantsSessionRead(wu) && P.wantsSessionRead(w0), "a session read only to confirm an unlock the others say")
var wStart = P.Witnesses(); wStart.console = .otherUser; wStart.screen = .locked
check(P.readsSession(P.Witnesses()) && P.readsSession(wStart) && !P.readsSession(wl) && P.readsSession(wu),
      "SessionLock reads the dictionary before it was ever read, whatever the others say; then only to confirm an unlock")

// SessionLock's look as it runs it: the console and the screen read, a session read started when
// `readsSession` says (answered at once here), then the reader's look. A host that starts while the Mac
// reads locked has its reading at its first look, and its unlock waits for the settle (found live: the
// reading had stayed unknown, so the device was told "another user" at a locked screen, and the unlock
// skipped the settle).
func sessionLockLook(_ r: inout P.Reader, console: P.Console, screen: P.Screen, answer: P.Session, at t: Double) -> [P.Change] {
    var changes: [P.Change] = []
    r.console(console); r.screen(screen)
    if let c = r.look(at: t) { changes.append(c) }
    if P.readsSession(r.witnesses) {
        r.session(answer, startedAt: t)
        if let c = r.look(at: t) { changes.append(c) }
    }
    return changes
}
let starts: [(P.Console, P.Screen, P.Session, Reading)] = [
    (.thisUser, .unlocked, .unlocked, .unlocked), (.thisUser, .locked, .screenLocked, .screenLocked),
    (.thisUser, .locked, .unlocked, .screenLocked), (.otherUser, .unlocked, .unlocked, .offConsole),
    (.otherUser, .unlocked, .offConsole, .offConsole), (.nobody, .unlocked, .noDictionary, .offConsole),
    (.thisUser, .unlocked, .unanswered, .screenLocked),
]
for (console, screen, answer, want) in starts {
    var r = P.Reader()
    let changes = sessionLockLook(&r, console: console, screen: screen, answer: answer, at: 0)
    check(r.established && r.gate == want && changes == [P.Change(from: nil, to: want)],
          "a host that starts with the console \(console), the screen \(screen), the dictionary \(answer): \(want) at its first look")
    guard want.locked else { continue }
    _ = sessionLockLook(&r, console: .thisUser, screen: .unlocked, answer: .unlocked, at: 10)
    let early = r.gate
    _ = sessionLockLook(&r, console: .thisUser, screen: .unlocked, answer: .unlocked, at: 12.1)
    check(early.locked && r.gate == .unlocked, "…and its unlock waits for the settle (\(early) at once, \(r.gate) 2.1 s later)")
}

// MARK: - The notifications

check(Set(P.noteNames.keys) == Set(P.distributedNames + P.workspaceNames) && P.noteNames.count == 6,
      "six notifications: loginwindow's four distributed ones and NSWorkspace's two")
check(P.noteNames["com.apple.screenIsLocked"] == .screenLocked && P.noteNames["com.apple.screenIsUnlocked"] == .screenUnlocked,
      "com.apple.screenIsLocked and screenIsUnlocked: the screen")
check(P.noteNames["com.apple.sessionDidMoveOffConsole"] == .offConsole && P.noteNames["com.apple.sessionDidMoveOnConsole"] == .onConsole,
      "com.apple.sessionDidMoveOffConsole and OnConsole: the console")
check(P.noteNames[NSWorkspace.sessionDidResignActiveNotification.rawValue] == .offConsole
      && P.noteNames[NSWorkspace.sessionDidBecomeActiveNotification.rawValue] == .onConsole,
      "NSWorkspace's session notifications, by AppKit's own names: resign is off console, become is on")
check(P.workspaceNames == [NSWorkspace.sessionDidResignActiveNotification.rawValue, NSWorkspace.sessionDidBecomeActiveNotification.rawValue],
      "the workspace names are AppKit's constants")
for short in ["screenIsLocked", "screenIsUnlocked", "sessionDidMoveOffConsole", "sessionDidMoveOnConsole", "sessionDidResignActive", "sessionDidBecomeActive"] {
    check(P.noteName(short).map { P.noteNames[$0] != nil } == true, "the short name \(short) names one SessionLock hears")
}
check(P.noteName("com.apple.screenIsLocked") == "com.apple.screenIsLocked" && P.noteName("screenIsDim") == nil && P.noteName("") == nil,
      "a full name as it is; an unknown one nothing")

/// A reader with every witness read unlocked at time 0 and its first look made (unlocked at once).
func unlockedReader() -> P.Reader {
    var r = P.Reader()
    r.console(.thisUser); r.screen(.unlocked); r.session(.unlocked, startedAt: 0)
    _ = r.look(at: 0)
    return r
}
for (name, note) in P.noteNames {
    var r = unlockedReader()
    r.note(note)
    let change = r.look(at: 0.001)
    switch note {
    case .screenLocked: check(change == P.Change(from: .unlocked, to: .screenLocked) && r.gate == .screenLocked, "\(name): locked at once, before any other witness")
    case .offConsole: check(change == P.Change(from: .unlocked, to: .offConsole) && r.gate == .offConsole, "\(name): off console at once")
    case .screenUnlocked, .onConsole: check(change == nil && r.gate == .unlocked, "\(name) alone changes nothing (never an unlock by itself)")
    }
}

// MARK: - The effective reading

var r = P.Reader()
check(!r.established && r.gate == .offConsole, "a new reader: no reading, the gate off console")
r.console(.thisUser); r.screen(.unlocked)
check(r.look(at: 0) == nil && !r.established, "before the session dictionary is read: still no reading")
r.session(.unlocked, startedAt: 0)
check(r.look(at: 0.001) == P.Change(from: nil, to: .unlocked) && r.gate == .unlocked, "the first reading with every witness read: taken as it is (unlocked at once)")
r.screen(.locked)
check(r.look(at: 5) == P.Change(from: .unlocked, to: .screenLocked) && r.gate == .screenLocked, "the screen locks: locked at once")
r.console(.otherUser)
check(r.look(at: 6) == P.Change(from: .screenLocked, to: .offConsole), "another user takes the console: off console at once")
r.console(.thisUser)
check(r.look(at: 7) == P.Change(from: .offConsole, to: .screenLocked), "back on the console with the screen locked: screen locked at once (a paired device may type)")
r.screen(.unlocked)
check(r.look(at: 8) == nil && r.gate == .screenLocked && r.unlockedSince == 8, "the screen unlocks: the settle starts, still locked")
check(r.look(at: 9.5) == nil && r.gate == .screenLocked, "1.5 s into the settle: still locked")
check(r.look(at: 10.1) == nil && r.gate == .screenLocked, "2.1 s, but no session read since the settle began: still locked")
r.session(.unlocked, startedAt: 10.2)
check(r.look(at: 10.2) == P.Change(from: .screenLocked, to: .unlocked) && r.gate == .unlocked && r.unlockedSince == nil,
      "2.2 s, a session read made since confirms it: unlocked")
check(P.Reader.settle == 2, "the settle is 2 s")

// The flap: back on the console, unlocked for 1.2 s, then macOS's own lock (loginwindow, 2026-10-31).
var flap = P.Reader()
flap.console(.otherUser); flap.screen(.unlocked); flap.session(.unlocked, startedAt: 0)
_ = flap.look(at: 0)
check(flap.gate == .offConsole, "the flap: off console first")
flap.console(.thisUser); flap.note(.onConsole)
_ = flap.look(at: 44.052)
flap.session(.unlocked, startedAt: 44.06)
_ = flap.look(at: 44.06)
check(flap.gate == .offConsole && flap.unlockedSince == 44.052, "the flap: on the console with every witness unlocked, the settle runs, still locked")
flap.screen(.locked); flap.note(.screenLocked)
check(flap.look(at: 45.227) == P.Change(from: .offConsole, to: .screenLocked) && flap.unlockedSince == nil,
      "the flap: macOS locks 1.2 s later: screen locked, the windows never went out")
flap.screen(.unlocked); flap.note(.screenUnlocked)
_ = flap.look(at: 57.44)
flap.session(.unlocked, startedAt: 59.45)
check(flap.look(at: 59.45) == P.Change(from: .screenLocked, to: .unlocked), "the flap: the password typed, 2 s settle, unlocked")

// The clearing rules: a lost notification does not hold the Mac locked for good once a witness saw the change.
var lost = unlockedReader()
lost.note(.screenLocked); lost.screen(.locked)
_ = lost.look(at: 1)
lost.screen(.unlocked)                         // the unlock seen by notify(3), its notification lost
check(lost.witnesses.screenNote == nil, "a lock notification whose unlock was lost: cleared once notify(3) saw the unlock")
var lostC = unlockedReader()
lostC.note(.offConsole); lostC.console(.otherUser)
_ = lostC.look(at: 1)
lostC.console(.thisUser)                       // the switch back seen in the dynamic store, its notification lost
check(lostC.witnesses.consoleNote == nil, "a switch-away notification whose switch back was lost: cleared once the console's user is this one again")
var spurious = unlockedReader()
spurious.note(.screenLocked)                   // no witness ever moves (another app posting the name)
_ = spurious.look(at: 1)
spurious.screen(.unlocked); spurious.console(.thisUser)    // each look reads them again, unchanged
spurious.session(.unlocked, startedAt: 5)
check(spurious.look(at: 5) == nil && spurious.gate == .screenLocked && spurious.witnesses.screenNote == .screenLocked,
      "a lock notification no witness confirms keeps the Mac locked until its unlock (locked wins; a screen read unlocked all along clears nothing)")
spurious.note(.screenUnlocked)
_ = spurious.look(at: 6)
spurious.session(.unlocked, startedAt: 8.1)
check(spurious.look(at: 8.1) == P.Change(from: .screenLocked, to: .unlocked), "…and the unlock notification, with the settle, ends it")
var stillOther = unlockedReader()
stillOther.note(.offConsole)
_ = stillOther.look(at: 1)
stillOther.console(.thisUser)                  // this user throughout: no switch back seen
check(stillOther.witnesses.consoleNote == .offConsole && stillOther.gate == .offConsole,
      "a switch-away notification is not cleared by a console that never changed")

// Random witness sequences against the settle's invariants.
struct RNG { var x: UInt64; mutating func next() -> UInt64 { x ^= x << 13; x ^= x >> 7; x ^= x << 17; return x }
             mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) } }
var rng = RNG(x: 0x5157_4C4F_434B_ED11)
var readerRuns = 0, readerBroken = 0, unlocks = 0, locks = 0
var readerFirst: String?
for _ in 0..<4_000 {
    var rd = P.Reader()
    var t = 0.0
    var rawUnlockedSince: Double?        // the model's own: since when every witness has said unlocked
    var lastSessionStart = -1.0
    var log: [String] = []
    var broken: String?
    for _ in 0..<(10 + rng.int(60)) {
        t += [0.001, 0.05, 0.3, 0.9, 1.0, 1.7, 2.0, 2.5][rng.int(8)]
        // Unlocked witnesses more often than not, so the settle is reached as often as a lock.
        switch rng.int(9) {
        case 0: let c = rng.int(3) > 0 ? P.Console.thisUser : consoles[1 + rng.int(4)]; rd.console(c); log.append("console \(c)")
        case 1: let s = rng.int(3) > 0 ? P.Screen.unlocked : screens[1 + rng.int(3)]; rd.screen(s); log.append("screen \(s)")
        case 2:
            let s = rng.int(3) > 0 ? P.Session.unlocked : sessions[1 + rng.int(5)]
            rd.session(s, startedAt: t); if s != .unanswered { lastSessionStart = t }; log.append("session \(s)")
        case 3:
            let n = rng.int(2) == 0 ? [P.Note.screenUnlocked, .onConsole][rng.int(2)] : [P.Note.screenLocked, .offConsole][rng.int(2)]
            rd.note(n); log.append("note \(n)")
        case 4: rd.test(rng.int(4) == 0 ? readings[rng.int(3)] : nil); log.append("test")
        default: log.append("look")
        }
        let wasGate = rd.gate, wasEstablished = rd.established
        let change = rd.look(at: t)
        let raw = P.reading(rd.witnesses)
        rawUnlockedSince = raw == .unlocked ? (rawUnlockedSince ?? t) : nil
        if raw.locked, rd.established, rd.gate != raw { broken = "the witnesses say \(raw) and the gate reads \(rd.gate)" }
        if rd.gate == .unlocked, raw.locked { broken = "unlocked while a witness says \(raw)" }
        if change?.to == .unlocked, change?.from != nil {
            unlocks += 1
            guard let since = rawUnlockedSince, t - since >= P.Reader.settle - 1e-9, lastSessionStart >= since else {
                broken = "unlocked without 2 s of every witness unlocked and a session read since (since \(rawUnlockedSince ?? -1), read \(lastSessionStart), now \(t))"
                break
            }
        }
        if change?.to.locked == true { locks += 1 }
        if wasEstablished, !rd.established { broken = "the reading was lost" }
        if wasEstablished, change == nil, rd.gate != wasGate { broken = "the gate moved without a change" }
        if broken != nil { break }
    }
    readerRuns += 1
    if let broken { readerBroken += 1; if readerFirst == nil { readerFirst = broken + " after " + log.joined(separator: ", ") } }
}
check(readerBroken == 0, "\(readerRuns) random witness sequences: locked at once, never unlocked while a witness says locked, an unlock only after the settle"
      + (readerFirst.map { ": \($0)" } ?? ""))
check(unlocks > 300 && locks > 1_000, "the random sequences reach what they test: \(unlocks) unlocks after a lock, \(locks) locks")

// MARK: - When SessionLock reads

check(P.pollInterval == 1, "once a second while a device is connected")
check(!P.polls(devices: 0) && P.polls(devices: 1) && P.polls(devices: 3), "no poll with no device connected")
check(P.sessionBound == 0.5, "a session read counts as unanswered after 0.5 s")

// MARK: - What each reading allows

let open = P.allowed(.unlocked), screen = P.allowed(.screenLocked), off = P.allowed(.offConsole)
check(open == P.Allowed(display: true, windows: true, appsAndIcons: true, launches: true, sound: true, clipboard: true, pointer: true,
                         gestures: true, virtualDisplay: true, input: .everyone, wakeOnConnect: true, wakeOnActivity: true),
      "unlocked: everything")
check(!P.lockScreenStreams, "a locked screen's display does not stream (the placeholder instead), until a test shows its frames")
check(screen == P.Allowed(display: false, windows: false, appsAndIcons: false, launches: false, sound: false, clipboard: false, pointer: false,
                           gestures: false, virtualDisplay: false, input: .paired, wakeOnConnect: false, wakeOnActivity: true),
      "screen locked: nothing of the Mac, a paired device's input alone, which may wake the display")
check(off == P.Allowed(display: false, windows: false, appsAndIcons: false, launches: false, sound: false, clipboard: false, pointer: false,
                        gestures: false, virtualDisplay: false, input: .nobody, wakeOnConnect: false, wakeOnActivity: false),
      "off console: nothing at all, no input from anyone, no display activity")
for rd in readings { for paired in [false, true] {
    let want = rd == .unlocked || (rd == .screenLocked && paired)
    check(P.takesInput(rd, paired: paired) == want, "takesInput(\(rd), paired: \(paired)) is \(want)")
} }

// MARK: - The server's gate

let gateKinds: [StreamMessageKind] = [.parameterSets, .frame, .windowList, .thumbnail, .appIcon, .appList, .pong, .tick, .cursorShape,
                                      .hostSettings, .macInfo, .goodbye, .macMenu, .macPointer, .clipboard, .audio]
let pictures: [P.Picture?] = [nil, .placeholder, .display, .window]
for rd in readings { for kind in gateKinds { for picture in pictures {
    let got = P.withheld(kind, picture: picture, reading: rd)
    let want: Bool
    if !rd.locked { want = false } else {
        switch kind {
        case .frame, .parameterSets: want = picture != .placeholder
        case .thumbnail, .appIcon, .appList, .audio, .clipboard, .cursorShape, .macPointer: want = true
        default: want = false
        }
    }
    check(got == want, "\(rd): kind \(kind.rawValue) (\(picture.map { "\($0)" } ?? "no picture")) \(want ? "withheld" : "sent")")
} } }
let gate = LockGate()
check(gate.reading == .unlocked && gate.established && !gate.withholds(.frame), "a server's own gate never locks (the harnesses)")
let session = LockGate(.offConsole, established: false)
check(session.reading == .offConsole && !session.established && session.withholds(.frame, picture: .display)
      && !session.withholds(.frame, picture: .placeholder), "SessionLock's gate before its first reading: off console, the display withheld")
session.set(.unlocked)
check(session.reading == .unlocked && session.established && !session.withholds(.thumbnail), "set: the reading, established")
session.set(.screenLocked)
check(session.locked && session.withholds(.thumbnail) && session.withholds(.macPointer) && !session.withholds(.windowList), "set locked: withheld at once")

// MARK: - A device's requests

let everyRequest: [(R, String)] = [
    (.pick(.window(7)), "a window picked"), (.pick(.desktop), "the Desktop picked"), (.pick(.none), "nothing picked"),
    (.launch, "an app launched"), (.windowCommand, "a window's buttons"), (.menuSubscription, "the menus' subscription"),
    (.menuRequest, "a menu fetched or chosen"), (.gesture, "a gesture"), (.clipboardText, "a device's clipboard text"),
    (.clipboardSubscription, "the clipboard's subscription or stop"), (.input(letsGo: false), "input"),
    (.input(letsGo: true), "the up of what the device holds down"), (.other, "settings, the viewport, a keyframe, Pair This iPad…"),
]
func expectedDecision(_ r: R, _ rd: Reading, paired: Bool) -> P.Decision {
    guard rd.locked else { return .take }
    switch r {
    case .pick(.window): return .refuse(.pick)
    case .pick: return .take
    case .launch: return .refuse(.launch)
    case .windowCommand: return .refuse(.windowCommand)
    case .menuSubscription, .clipboardSubscription, .other: return .take
    case .menuRequest: return .refuse(.menus)
    case .gesture: return .refuse(.gesture)
    case .clipboardText: return .refuse(.clipboard)
    case .input(let letsGo):
        let types = rd == .screenLocked && paired
        return types ? .take : (letsGo ? .letGo : .refuse(.input))
    }
}
for (q, what) in everyRequest { for rd in readings { for paired in [false, true] {
    let got = P.decide(q, reading: rd, paired: paired), want = expectedDecision(q, rd, paired: paired)
    check(got == want, "\(rd), \(what) from a\(paired ? " paired" : "n unpaired") session: \(want) (got \(got))")
} } }
check(P.decide(.input(letsGo: false), reading: .offConsole, paired: true) == .refuse(.input),
      "off console a paired session's input is dropped too (nothing typed here reaches another session's login window)")
check(P.decide(.input(letsGo: true), reading: .offConsole, paired: true) == .letGo, "off console the up of a key or button held down still goes")
check(P.decide(.input(letsGo: false), reading: .screenLocked, paired: true) == .take, "at a locked screen a paired session types (the owner's password)")
check(P.Refusal.allCases.map(\.rawValue) == ["pick", "launch", "windowCommand", "menus", "gesture", "clipboard", "input"],
      "seven refusal kinds, each its own summary line")
// Judged at the more restrictive of the reading at arrival and now: what came while locked never acts after.
for arrived in readings { for now in readings {
    let rd = P.restrictive(arrived, now)
    check((P.decide(.pick(.window(3)), reading: rd, paired: true) == .take) == (arrived == .unlocked && now == .unlocked),
          "a window pick that arrived \(arrived) and is handled \(now): taken only if unlocked both times")
} }

// MARK: - The window list

let windows = [WindowInfo(id: 11, title: "Budget.numbers", appName: "Numbers", bundleID: "com.apple.iWork.Numbers", width: 1200, height: 800),
               WindowInfo(id: 12, title: "Inbox", appName: "Mail", bundleID: "com.apple.mail", width: 1000, height: 700)]
var full = WindowList(macName: "Noah’s MacBook Pro", windows: windows, active: .window(11), launchID: "L1", hostVersion: "0.6.0",
                      protocol: 1, gestures: 1, clipboard: 1)
full.keyRepeat = 1
let unlockedList = P.list(full, reading: .unlocked)
check(sortedJSON(unlockedList) == sortedJSON(full) && Wire.encode(unlockedList).count == Wire.encode(full).count,
      "unlocked: the list as it is, byte for byte: \(sortedJSON(unlockedList))")
check(!json(unlockedList).contains("locked") && !json(unlockedList).contains("offConsole"), "unlocked: no `locked`, no `offConsole`")
for rd in [Reading.screenLocked, .offConsole] {
    let l = P.list(full, reading: rd)
    check(l.windows.isEmpty && l.clipboard == nil && !json(l).contains("clipboard"), "\(rd): no windows, no clipboard")
    check(l.locked == true && json(l).contains(#""locked":true"#), "\(rd): `locked` true")
    check(rd == .offConsole ? (l.offConsole == true && json(l).contains(#""offConsole":true"#)) : (l.offConsole == nil && !json(l).contains("offConsole")),
          "\(rd): `offConsole` \(rd == .offConsole ? "true" : "left out")")
    check(l.macName == full.macName && l.active == full.active && l.launchID == "L1" && l.hostVersion == "0.6.0" && l.protocol == 1
          && l.gestures == 1 && l.keyRepeat == 1, "\(rd): the rest of the list as it is")
    check(!json(l).contains("Budget") && !json(l).contains("Inbox") && !json(l).contains("com.apple.mail"), "\(rd): no window's title, app or bundle in the bytes")
    let back = Wire.decode(WindowList.self, from: Wire.encode(l))
    check(back?.locked == true && back?.offConsole == l.offConsole && back?.windows.isEmpty == true, "\(rd): the list round-trips")
}
let before = #"{"macName":"Mac mini","windows":[],"active":{"desktop":{}},"launchID":"L","hostVersion":"0.5.1","protocol":1,"gestures":1,"clipboard":1}"#
check(Wire.decode(WindowList.self, from: Data(before.utf8)).map { $0.locked == nil && $0.offConsole == nil && $0.clipboard == 1 } == true,
      "an older host's list (Sill for Mac 0.5.1's keys) decodes, locked and offConsole nil")
struct OlderReader: Decodable { var macName: String; var windows: [WindowInfo]; var active: StreamSource; var clipboard: Int?; var keyRepeat: Int? }
check(Wire.decode(OlderReader.self, from: Wire.encode(P.list(full, reading: .offConsole))).map { $0.windows.isEmpty && $0.clipboard == nil } == true,
      "an older device reads a locked list (it skips both keys) and sees no windows")

// MARK: - The placeholder

check(P.placeholderSize(display: nil) == (1280, 800), "no display (a test host): 1280×800")
check(P.placeholderSize(display: (1512, 982)) == (1512, 982), "the display's own size in points")
check(P.placeholderSize(display: (1513, 983)) == (1512, 982), "even sides")
check(P.placeholderSize(display: (10, 20)) == (64, 64) && P.placeholderSize(display: (0, 900)) == (1280, 800), "at least 64 a side; a zero display none")

// MARK: - Reconciling coalesced changes

for rd in readings { for streams in [P.Streams.nothing, .placeholder, .display, .window] { for listed in [false, true] {
    let want: Bool
    switch (rd.locked, streams) {
    case (true, .window): want = true
    case (true, .display): want = !P.lockScreenStreams || rd == .offConsole
    case (true, _): want = false
    case (false, .placeholder): want = true
    case (false, _): want = listed
    }
    check(P.reconciles(rd, streams: streams, lockedListSent: listed) == want,
          "\(rd), \(streams) streaming\(listed ? ", a locked list sent last" : ""): \(want ? "acted on" : "nothing to put right")")
} } }

// MARK: - The window that comes back

var s = P.Restore()
check(s.comesBack == nil, "a new Restore: nothing to come back")
check(s.select(.window(3), active: .desktop, pick: true, reading: .unlocked) == .proceed, "unlocked: a window picked proceeds")
check(s.select(.desktop, active: .window(3), pick: false, reading: .unlocked) == .proceed && s.select(.none, active: .desktop, pick: false, reading: .unlocked) == .proceed,
      "unlocked: the Desktop and nothing proceed")
s.lockBegan(active: .window(5))
check(s.comesBack == 5, "the lock began with a window streaming: it is what comes back")
s = P.Restore(); s.lockBegan(active: .desktop)
check(s.comesBack == nil, "the lock began with the Desktop: no window comes back")
for rd in [Reading.screenLocked, .offConsole] {
    var t = P.Restore()
    check(t.select(.window(5), active: .window(5), pick: false, reading: rd) == .desktop && t.comesBack == 5,
          "\(rd): a restart of the window that streams becomes the Desktop (the placeholder), and comes back")
    check(t.select(.window(6), active: .desktop, pick: false, reading: rd) == .stay && t.comesBack == 6, "\(rd), the Desktop streaming: a window asked for changes nothing but what comes back")
    check(t.select(.window(8), active: .none, pick: true, reading: rd) == .desktop && t.comesBack == 8, "\(rd), nothing streaming: a window asked for starts the Desktop")
    check(t.select(.desktop, active: .desktop, pick: true, reading: rd) == .proceed && t.comesBack == 8, "\(rd): the Desktop picked proceeds (the placeholder) and keeps what comes back")
    check(t.select(.none, active: .desktop, pick: false, reading: rd) == .proceed && t.comesBack == 8, "\(rd): nothing proceeds (the last device left)")
}
var u = P.Restore(); _ = u.select(.window(8), active: .none, pick: false, reading: .screenLocked)
var v = u
check(v.afterUnlock(listed: [8, 9], active: .desktop, placeholder: true, devices: 1, reading: .unlocked) == .window(8) && v.comesBack == nil,
      "after the unlock: the window comes back in place of the placeholder, once")
check(v.afterUnlock(listed: [8, 9], active: .desktop, placeholder: true, devices: 1, reading: .unlocked) == .desktop,
      "…and a second time the Desktop (no window remembered)")
v = u
check(v.afterUnlock(listed: [9], active: .desktop, placeholder: true, devices: 1, reading: .unlocked) == .desktop && v.comesBack == nil,
      "after the unlock: a window no longer listed gives the Desktop in place of the placeholder")
v = u
check(v.afterUnlock(listed: [8], active: .window(9), placeholder: false, devices: 1, reading: .unlocked) == nil && v.comesBack == nil,
      "after the unlock: something else picked since (no placeholder): nothing")
v = u
check(v.afterUnlock(listed: [8], active: .desktop, placeholder: false, devices: 1, reading: .unlocked) == nil, "the display streams already: nothing")
v = u
check(v.afterUnlock(listed: [8], active: .desktop, placeholder: true, devices: 0, reading: .unlocked) == nil && v.comesBack == nil,
      "no device connected: nothing")
v = u
check(v.afterUnlock(listed: [8], active: .desktop, placeholder: true, devices: 1, reading: .screenLocked) == nil && v.comesBack == 8,
      "locked again before the unlock's look: nothing, and the window is kept")
check(v.afterUnlock(listed: [8], active: .desktop, placeholder: true, devices: 1, reading: .unlocked) == .window(8), "…and it comes back at the next unlock")
v = u
check(v.select(.window(9), active: .desktop, pick: true, reading: .unlocked) == .proceed && v.comesBack == nil, "unlocked: a pick forgets what would have come back")
v = u
check(v.select(.desktop, active: .desktop, pick: false, reading: .unlocked) == .proceed && v.comesBack == 8, "unlocked: a restart keeps what comes back")
v = u
v.devicesLeft()
check(v.comesBack == nil, "the last device left: nothing comes back")

// MARK: - The TEST ONLY hooks

check(P.fileReading("1") == .screenLocked && P.fileReading("1\n") == .screenLocked && P.fileReading(" 1 \n") == .screenLocked, "the file: 1 is the screen locked")
check(P.fileReading("2") == .offConsole && P.fileReading("2\n") == .offConsole, "the file: 2 is off console")
check(P.fileReading("0") == nil && P.fileReading("") == nil && P.fileReading(nil) == nil && P.fileReading("yes") == nil
      && P.fileReading("11") == nil && P.fileReading("3") == nil && P.fileReading("12") == nil, "the file: anything else says nothing")
check(P.testNotifyName("me.saffer.sill.test.lock.1") == "me.saffer.sill.test.lock.1", "a test notify name under the prefix")
check(P.testNotifyName("com.apple.sessionagent.screenIsLocked") == nil && P.testNotifyName("me.saffer.sill.test.") == nil
      && P.testNotifyName(nil) == nil && P.testNotifyName("me.saffer.sill.test." + String(repeating: "x", count: 120)) == nil,
      "never a system name, an empty one or a long one")
let notes = P.testNotes("3 screenIsLocked; 8.5 com.apple.screenIsUnlocked;10 sessionDidResignActive")
check(notes?.count == 3 && notes?[0].at == 3 && notes?[0].name == "com.apple.screenIsLocked" && notes?[1].at == 8.5
      && notes?[2].name == "NSWorkspaceSessionDidResignActiveNotification", "SILL_TEST_LOCK_NOTE: times and names")
check(P.testNotes("3") == nil && P.testNotes("x screenIsLocked") == nil && P.testNotes("3 screenIsDim") == nil && P.testNotes("-1 screenIsLocked") == nil
      && P.testNotes("") == nil && P.testNotes(nil) == nil, "a part that does not parse: none")

// MARK: - The lines

check(P.line(P.Change(from: nil, to: .unlocked)) == nil, "a host that starts unlocked says nothing new")
check(P.line(P.Change(from: nil, to: .screenLocked)) == P.line(P.Change(from: .unlocked, to: .screenLocked)), "one that starts locked says so")
check(P.line(P.Change(from: .unlocked, to: .screenLocked)) == "Locked: this Mac's screen is locked; devices see none of it until it is unlocked, and only a paired device types at it.",
      "the lock's line")
check(P.line(P.Change(from: .screenLocked, to: .offConsole)) == "Locked: another user, or the login window, is on this Mac's screen; devices see none of this session, and nothing they send is posted, until it is back.",
      "off console's line")
check(P.line(P.Change(from: .offConsole, to: .unlocked)) == P.unlockedLine
      && P.unlockedLine == "Unlocked: this Mac's screen is unlocked; devices see its windows again.", "the unlock's line")
check(P.menuNote == "The Mac is locked.", "the menus' note")
let words: [(P.Refusal, String, String)] = [
    (.pick, "Locked: refused a window pick; devices see none of this Mac until it is unlocked.",
     "Locked: refused 3 window picks; devices see none of this Mac until it is unlocked."),
    (.launch, "Locked: refused an app launch; devices see none of this Mac until it is unlocked.",
     "Locked: refused 3 app launches; devices see none of this Mac until it is unlocked."),
    (.windowCommand, "Locked: refused a window's button; devices see none of this Mac until it is unlocked.",
     "Locked: refused 3 presses of windows' buttons; devices see none of this Mac until it is unlocked."),
    (.menus, "Locked: refused a menu request; devices see none of this Mac until it is unlocked.",
     "Locked: refused 3 menu requests; devices see none of this Mac until it is unlocked."),
    (.gesture, "Locked: refused a gesture; devices see none of this Mac until it is unlocked.",
     "Locked: refused 3 gestures; devices see none of this Mac until it is unlocked."),
    (.clipboard, "Locked: dropped a device's clipboard text; the clipboard waits for this Mac to be unlocked.",
     "Locked: dropped 3 clipboard texts from devices; the clipboard waits for this Mac to be unlocked."),
    (.input, "Locked: dropped an input event; only a paired device types at a locked Mac, and no device at one switched to another user.",
     "Locked: dropped 3 input events; only a paired device types at a locked Mac, and no device at one switched to another user."),
]
for (kind, one, three) in words {
    check(P.refusedLine(kind, count: 1) == one, "\(kind)'s line for one: \(P.refusedLine(kind, count: 1))")
    check(P.refusedLine(kind, count: 3) == three, "\(kind)'s line for three: \(P.refusedLine(kind, count: 3))")
    check(P.refusedLine(kind, count: 0) == one, "\(kind)'s line for a count of none reads as one")
}
let logLine = P.testLogLine(w0, raw: .unlocked, gate: .offConsole, established: false, cause: "start")
check(logLine.hasPrefix("Test lock: start: reads unlocked, gate unknown (off console)") && logLine.contains("console thisUser"),
      "the TEST ONLY lock log: \(logLine)")

// MARK: - The device's words and cover (StreamProtocol)

var locked1 = WindowList(macName: "M", windows: [], active: .desktop); locked1.locked = true
var locked2 = locked1; locked2.offConsole = true
check(LockedMac.why(WindowList(macName: "M", windows: [], active: .desktop)) == nil, "a list without `locked`: not locked")
check(LockedMac.why(locked1) == .screenLocked && LockedMac.why(locked2) == .otherUser, "`locked`: the screen; with `offConsole`: another user")
var odd = WindowList(macName: "M", windows: [], active: .desktop); odd.offConsole = true
check(LockedMac.why(odd) == nil, "`offConsole` without `locked`: not locked")
check(LockedMac.line(mac: "Noah’s MacBook Pro", why: .screenLocked) == "Noah’s MacBook Pro is locked. Unlock it to see its windows.", "the line, locked")
check(LockedMac.line(mac: "Noah’s MacBook Pro", why: .otherUser) == "Noah’s MacBook Pro is switched to another user. Its windows come back when you switch back on the Mac.",
      "the line, another user")
check(LockedMac.line(mac: "", why: .screenLocked) == "The Mac is locked. Unlock it to see its windows.", "the line without the Mac's name")
check(LockedMac.title(mac: "Mac mini", shade: .locked(.screenLocked)) == "Mac mini is locked"
      && LockedMac.title(mac: "Mac mini", shade: .locked(.otherUser)) == "Mac mini is switched to another user"
      && LockedMac.title(mac: "Mac mini", shade: .unlocking) == "Unlocking…", "the cover's titles")
check(LockedMac.detail(shade: .locked(.screenLocked), paired: true) == "To unlock it from here, type its password and press Return. Its windows come back once it is unlocked."
      && LockedMac.detail(shade: .locked(.screenLocked), paired: false) == "Its windows come back once it is unlocked."
      && LockedMac.detail(shade: .locked(.screenLocked), paired: nil) == "Its windows come back once it is unlocked.",
      "the cover's line at a locked screen: the password only for a paired session")
check(LockedMac.detail(shade: .locked(.otherUser), paired: true) == "Its windows come back when you switch back to your account on the Mac. Nothing typed here reaches it meanwhile."
      && LockedMac.detail(shade: .unlocking, paired: true) == nil, "the cover's line for another user: nothing typed reaches it; none while unlocking")
check(LockedMac.shade(nil, list: nil) == nil && LockedMac.shade(nil, list: .screenLocked) == .locked(.screenLocked)
      && LockedMac.shade(.locked(.screenLocked), list: .otherUser) == .locked(.otherUser), "the cover follows a locked list")
check(LockedMac.shade(.locked(.otherUser), list: nil) == .unlocking && LockedMac.shade(.unlocking, list: nil) == .unlocking,
      "after a locked list, an unlocked one: Unlocking… until the picture")
check(LockedMac.shade(.unlocking, frameIsKeyframe: true) == nil && LockedMac.shade(.unlocking, frameIsKeyframe: false) == .unlocking
      && LockedMac.shade(.locked(.screenLocked), frameIsKeyframe: true) == .locked(.screenLocked) && LockedMac.shade(nil, frameIsKeyframe: true) == nil,
      "a keyframe ends Unlocking…, never the locked cover (the placeholder's keyframe comes while locked)")
check(LockedMac.unlockingTimeout == 4, "Unlocking… waits 4 s at most")
// Random lists and frames: the cover is up whenever the last list said locked, and stays until a keyframe after it.
var shadeBroken = 0
for _ in 0..<2_000 {
    var shade: LockedMac.Shade? = nil
    var lastLocked = false, waiting = false
    for _ in 0..<30 {
        if rng.int(2) == 0 {
            let why: LockedMac.Why? = [nil, .screenLocked, .otherUser][rng.int(3)]
            shade = LockedMac.shade(shade, list: why)
            if why != nil { waiting = false } else if lastLocked || waiting { waiting = true }
            lastLocked = why != nil
        } else {
            let key = rng.int(3) == 0
            shade = LockedMac.shade(shade, frameIsKeyframe: key)
            if key, waiting { waiting = false }
        }
        if lastLocked, shade == nil || shade == .unlocking { shadeBroken += 1 }
        if waiting, shade != .unlocking { shadeBroken += 1 }
        if !lastLocked, !waiting, shade != nil { shadeBroken += 1 }
    }
}
check(shadeBroken == 0, "2000 random sessions of lists and frames: the cover while locked, Unlocking… until a keyframe after it, none otherwise")

// MARK: - The coordinator's glue

/// A copy of StreamCoordinator's glue around LockPolicy: the gate (SessionLock's effective reading, which
/// the Reader above makes), `lockChanged` once per change with the reading as it is then, a select taking a
/// step to finish (so one can be under way when the gate changes) and reading the gate again at its end, as
/// the coordinator does after each await; the tasks it starts run as their own steps.
struct Glue {
    enum Job: Equatable { case lockChanged, enforce, afterUnlock, desktop }
    var gate: Reading = .unlocked
    var acted: Reading? = .unlocked
    var restore = P.Restore()
    var active: StreamSource = .none
    var placeholder = false
    var inFlight: StreamSource?        // a select under way, with the source its gate let through
    var listed: Set<UInt32> = [1, 2, 3]
    var devices = 1
    var pendingLaunch: UInt32?
    var jobs: [Job] = []
    var deselectWhenSettled = false
    var violations: [String] = []
    /// Windows a device picked while the gate read locked, at arrival or after: none may ever stream before an unlock.
    var refusedPicks: Set<UInt32> = []
    var started: [String] = []

    mutating func gateChanges(to r: Reading) {
        guard r != gate else { return }
        gate = r
        if r.locked == false { refusedPicks = [] }
        jobs.append(.lockChanged)
    }

    var streams: P.Streams { placeholder ? .placeholder : isWindow(active) ? .window : active == .desktop ? .display : .nothing }

    mutating func lockChanged() {
        let now = gate
        let was = acted
        acted = now
        guard now != was || P.reconciles(now, streams: streams, lockedListSent: false) else { return }
        if now.locked {
            pendingLaunch = nil
            restore.lockBegan(active: active)
            enforceLock()
        } else if was != nil || devices > 0 {
            afterUnlock()
        }
    }

    mutating func enforceLock() {
        guard gate.locked, inFlight == nil, devices > 0 else { return }
        if active == .desktop, placeholder || P.allowed(gate).display { return }
        select(.desktop, pick: false)
    }

    mutating func select(_ source: StreamSource, pick: Bool) {
        guard inFlight == nil else { return }       // `switching`: refused
        var source = source
        switch restore.select(source, active: active, pick: pick, reading: gate) {
        case .proceed: break
        case .desktop: source = .desktop
        case .stay: return
        }
        inFlight = source
    }

    /// The select under way ends: its awaits are over, the gate is read again, and what it starts streams.
    mutating func finishSelect() {
        guard let source = inFlight else { return }
        inFlight = nil
        placeholder = false
        switch source {
        case .none:
            active = .none
        case .window(let id):
            if gate.locked { lockedMidSwitch(source); return }
            active = listed.contains(id) ? source : .none
            if case .window = active { started.append("window \(id) at \(gate)") }
        case .desktop:
            if P.allowed(gate).display {
                active = .desktop
                started.append("display at \(gate)")
                if gate.locked { violations.append("the display started while the gate read \(gate)") }
            } else {
                active = .desktop
                placeholder = true
            }
        }
        if gate.locked, case .window(let id) = active { violations.append("window \(id) began streaming while the gate read \(gate)") }
        if case .window(let id) = active, refusedPicks.contains(id), gate.locked { violations.append("a refused pick of \(id) streams") }
        if deselectWhenSettled {
            deselectWhenSettled = false
            if devices == 0, active != .none { select(.none, pick: false) }
        }
        if gate.locked, active != .none, !placeholder { jobs.append(.enforce) }
    }

    mutating func lockedMidSwitch(_ source: StreamSource) {
        if devices > 0 { _ = restore.select(source, active: active, pick: false, reading: gate) }
        active = .none
        placeholder = false
        jobs.append(.desktop)
    }

    mutating func afterUnlock() {
        guard devices > 0 else { return }
        if inFlight != nil { jobs.append(.afterUnlock); return }     // waits for the switch
        guard !gate.locked else { return }
        if let next = restore.afterUnlock(listed: Array(listed), active: active, placeholder: placeholder, devices: devices, reading: gate) {
            select(next, pick: false)
        }
    }

    mutating func runJob() {
        guard !jobs.isEmpty else { return }
        switch jobs.removeFirst() {
        case .lockChanged: lockChanged()
        case .enforce: enforceLock()
        case .afterUnlock: afterUnlock()
        case .desktop: if devices > 0 { select(.desktop, pick: false) }
        }
    }

    /// A device's messages (`handle`): judged by the more restrictive of the gate as it arrived and now.
    mutating func devicePick(_ s: StreamSource, arrived: Reading) {
        guard devices > 0 else { return }
        if P.decide(.pick(s), reading: P.restrictive(arrived, gate), paired: true) != .take {
            if case .window(let id) = s { refusedPicks.insert(id) }
            return
        }
        if inFlight != nil { return }                   // handlePick during a switch (to another source: dropped)
        select(s, pick: true)
    }

    mutating func deviceLaunch(_ id: UInt32, arrived: Reading) {
        guard devices > 0 else { return }
        guard P.decide(.launch, reading: P.restrictive(arrived, gate), paired: true) == .take else { return }
        pendingLaunch = id
    }

    /// The launched app's window appears (`windowsChanged`, which the catalog's poll calls only while a
    /// device is connected).
    mutating func windowAppears(_ id: UInt32) {
        listed.insert(id)
        guard devices > 0 else { return }
        if gate.locked, !isWindow(active) { return }
        if pendingLaunch == id {
            pendingLaunch = nil
            select(.window(id), pick: true)
        }
    }

    mutating func windowCloses(_ id: UInt32) {
        listed.remove(id)
        guard devices > 0 else { return }
        if gate.locked, !isWindow(active) { return }
        if active == .window(id) { select(.none, pick: false) }
    }

    mutating func restart() { select(active, pick: false) }

    mutating func deviceLeaves() {
        guard devices > 0 else { return }
        devices -= 1
        if devices == 0 {
            restore.devicesLeft()
            if inFlight != nil { deselectWhenSettled = true } else if active != .none { select(.none, pick: false) }
        }
    }

    mutating func deviceJoins() { devices += 1 }

    mutating func settle() {
        var steps = 0
        while (inFlight != nil || !jobs.isEmpty), steps < 200 {
            if inFlight != nil { finishSelect() } else { runJob() }
            steps += 1
        }
        if steps >= 200 { violations.append("did not settle") }
    }

    var settledViolation: String? {
        if gate.locked, case .window(let id) = active { return "settled at \(gate) with window \(id) streaming" }
        if gate.locked, active == .desktop, !placeholder { return "settled at \(gate) with the display streaming" }
        if gate.locked, devices > 0, active != .desktop, active != .none { return "settled at \(gate) without the placeholder" }
        if !gate.locked, acted == .unlocked, placeholder { return "settled unlocked with the placeholder streaming" }
        return nil
    }

    func isWindow(_ s: StreamSource) -> Bool { if case .window = s { return true }; return false }
}

func scenario(_ name: String, _ body: (inout Glue) -> Bool) {
    var g = Glue()
    let ok = body(&g)
    check(ok && g.violations.isEmpty, "\(name)\(g.violations.isEmpty ? "" : ": " + g.violations.joined(separator: "; "))")
}

scenario("S1: a window streams, the screen locks: the placeholder streams; the unlock: the window comes back") { g in
    g.devicePick(.window(2), arrived: .unlocked); g.settle()
    guard g.active == .window(2) else { return false }
    g.gateChanges(to: .screenLocked); g.settle()
    guard g.active == .desktop, g.placeholder, g.restore.comesBack == 2 else { return false }
    g.gateChanges(to: .unlocked); g.settle()
    return g.active == .window(2) && !g.placeholder
}
scenario("S2: the window closes while locked: the Desktop (the display) after the unlock") { g in
    g.devicePick(.window(2), arrived: .unlocked); g.settle()
    g.gateChanges(to: .screenLocked); g.settle()
    g.windowCloses(2); g.settle()
    g.gateChanges(to: .unlocked); g.settle()
    return g.active == .desktop && !g.placeholder
}
scenario("S3: a pick right after the unlock, before the window comes back, wins") { g in
    g.devicePick(.window(2), arrived: .unlocked); g.settle()
    g.gateChanges(to: .screenLocked); g.settle()
    g.gate = .unlocked                               // the gate unlocks; lockChanged not run yet
    g.devicePick(.window(3), arrived: .unlocked); g.settle()
    g.jobs.append(.lockChanged); g.settle()
    return g.active == .window(3)
}
scenario("S4: the gate locks while a switch to a window is under way: the window never streams, the placeholder follows") { g in
    g.devicePick(.window(2), arrived: .unlocked)     // under way
    g.gateChanges(to: .offConsole)
    g.finishSelect()
    guard g.active == .none, g.jobs.contains(.desktop) else { return false }
    g.settle()
    guard g.active == .desktop, g.placeholder, g.restore.comesBack == 2 else { return false }
    g.gateChanges(to: .unlocked); g.settle()
    return g.active == .window(2)
}
scenario("S5: a device's window pick while locked is refused, and never streams, after the unlock either") { g in
    g.devicePick(.desktop, arrived: .unlocked); g.settle()
    g.gateChanges(to: .screenLocked); g.settle()
    g.devicePick(.window(3), arrived: .screenLocked); g.settle()
    guard g.active == .desktop, g.placeholder, g.restore.comesBack == nil else { return false }
    g.gateChanges(to: .unlocked); g.settle()
    return g.active == .desktop && !g.placeholder
}
scenario("S6: a pick that arrived while locked and is handled after the unlock is refused (judged at its arrival)") { g in
    g.devicePick(.desktop, arrived: .unlocked); g.settle()
    g.gateChanges(to: .screenLocked); g.settle()
    g.gateChanges(to: .unlocked)
    g.devicePick(.window(1), arrived: .screenLocked); g.settle()
    return g.active == .desktop && !g.placeholder && g.refusedPicks.contains(1) && !g.started.contains { $0.hasPrefix("window 1") }
}
scenario("S7: a restart while locked and the placeholder streaming: nothing restarts, the window is remembered") { g in
    g.devicePick(.window(1), arrived: .unlocked); g.settle()
    g.gateChanges(to: .screenLocked); g.settle()
    g.select(.window(1), pick: false)                // a settings change's restart of what streamed
    guard g.inFlight == nil, g.active == .desktop, g.placeholder else { return false }
    g.gateChanges(to: .unlocked); g.settle()
    return g.active == .window(1)
}
scenario("S8: the last device leaves while locked: nothing comes back for the next one") { g in
    g.devicePick(.window(2), arrived: .unlocked); g.settle()
    g.gateChanges(to: .screenLocked); g.settle()
    g.deviceLeaves(); g.settle()
    guard g.active == .none else { return false }
    g.deviceJoins(); g.devicePick(.desktop, arrived: .screenLocked); g.settle()
    guard g.placeholder else { return false }
    g.gateChanges(to: .unlocked); g.settle()
    return g.active == .desktop && !g.placeholder
}
scenario("S9: a launch asked for before the lock picks nothing while locked") { g in
    g.devicePick(.desktop, arrived: .unlocked); g.settle()
    g.deviceLaunch(9, arrived: .unlocked)
    g.gateChanges(to: .screenLocked); g.settle()
    g.windowAppears(9); g.settle()
    guard g.active == .desktop, g.placeholder else { return false }
    g.gateChanges(to: .unlocked); g.settle()
    return g.active == .desktop && !g.placeholder
}
scenario("S10: a launch while locked is refused, also one that arrived locked and is handled unlocked") { g in
    g.devicePick(.desktop, arrived: .unlocked); g.settle()
    g.gateChanges(to: .offConsole); g.settle()
    g.deviceLaunch(9, arrived: .offConsole)
    g.gateChanges(to: .unlocked)
    g.deviceLaunch(8, arrived: .offConsole)
    return g.pendingLaunch == nil
}
scenario("S11: locked again before the unlock's look: the window waits for the next unlock") { g in
    g.devicePick(.window(2), arrived: .unlocked); g.settle()
    g.gateChanges(to: .screenLocked); g.settle()
    g.gate = .unlocked; g.gate = .screenLocked       // an unlock and a lock before lockChanged ran
    g.jobs.append(.lockChanged); g.settle()
    guard g.active == .desktop, g.placeholder, g.restore.comesBack == 2 else { return false }
    g.gateChanges(to: .unlocked); g.settle()
    return g.active == .window(2)
}
scenario("S12: nothing streams at the lock with a device connected: the placeholder, then the Desktop after the unlock") { g in
    g.gateChanges(to: .screenLocked); g.settle()
    guard g.active == .desktop, g.placeholder else { return false }
    g.gateChanges(to: .unlocked); g.settle()
    return g.active == .desktop && !g.placeholder
}
scenario("S13: the Desktop asked for while off console streams the placeholder, never the display") { g in
    g.gateChanges(to: .offConsole); g.settle()
    g.devicePick(.desktop, arrived: .offConsole); g.settle()
    return g.active == .desktop && g.placeholder && g.started.isEmpty
}
scenario("S14: the Desktop asked for while the screen is locked: the placeholder too (the display only with lockScreenStreams)") { g in
    g.gateChanges(to: .screenLocked); g.settle()
    g.devicePick(.desktop, arrived: .screenLocked); g.settle()
    return g.active == .desktop && g.placeholder && g.started.isEmpty
}
scenario("S15: the display streams, another user takes the console: the placeholder at once; back and locked: still it") { g in
    g.devicePick(.desktop, arrived: .unlocked); g.settle()
    guard g.active == .desktop, !g.placeholder else { return false }
    g.gateChanges(to: .offConsole); g.settle()
    guard g.placeholder else { return false }
    g.gateChanges(to: .screenLocked); g.settle()
    guard g.placeholder else { return false }
    g.gateChanges(to: .unlocked); g.settle()
    return g.active == .desktop && !g.placeholder
}

// Random sessions: the rule's invariants under every interleaving the glue allows.
var sessionsRun = 0, sessionsBroken = 0, returned = 0, lockedSettles = 0, refusedSeen = 0
var firstBroken: String?
for _ in 0..<5_000 {
    var g = Glue()
    var log: [String] = []
    var previousGate = g.gate
    for _ in 0..<(20 + rng.int(40)) {
        let e = rng.int(13)
        let arrived = rng.int(3) == 0 ? previousGate : g.gate     // a message that arrived a moment ago
        switch e {
        case 0: previousGate = g.gate; g.gateChanges(to: readings[rng.int(3)]); log.append("gate \(g.gate)")
        case 1: g.runJob(); log.append("job")
        case 2: let w = UInt32(1 + rng.int(4)); g.devicePick(.window(w), arrived: arrived); log.append("pick \(w) (arrived \(arrived))")
        case 3: g.devicePick(.desktop, arrived: arrived); log.append("pick desktop")
        case 4: g.restart(); log.append("restart")
        case 5: g.finishSelect(); log.append("finish")
        case 6: g.runJob(); log.append("job")
        case 7: let w = UInt32(1 + rng.int(4)); g.windowCloses(w); log.append("close \(w)")
        case 8: let w = UInt32(1 + rng.int(4)); g.windowAppears(w); log.append("open \(w)")
        case 9: let w = UInt32(5 + rng.int(2)); g.deviceLaunch(w, arrived: arrived); log.append("launch \(w)")
        case 10: if rng.int(3) == 0 { g.deviceLeaves(); log.append("leave") } else { g.deviceJoins(); log.append("join") }
        case 11: g.devicePick(.none, arrived: arrived); log.append("pick none")
        default: g.settle(); log.append("settle")
        }
        if !g.refusedPicks.isEmpty { refusedSeen += 1 }
    }
    // Settle with the gate as it is now.
    g.jobs.append(.lockChanged); g.settle()
    if let v = g.settledViolation { g.violations.append(v) }
    if g.gate.locked { lockedSettles += 1 }
    // Then unlock and settle: what was remembered, if listed with a device left, streams.
    let remembered = g.restore.comesBack
    let wasLocked = g.gate.locked
    let placeholderAtUnlock = g.placeholder
    g.gateChanges(to: .unlocked); g.settle()
    if let v = g.settledViolation { g.violations.append(v) }
    if wasLocked, let w = remembered, g.listed.contains(w), g.devices > 0, placeholderAtUnlock, g.active != .window(w) {
        g.violations.append("window \(w) did not come back (active \(g.active))")
    }
    if wasLocked, let w = remembered, g.active == .window(w) { returned += 1 }
    sessionsRun += 1
    if !g.violations.isEmpty {
        sessionsBroken += 1
        if firstBroken == nil { firstBroken = g.violations.joined(separator: "; ") + " after " + log.joined(separator: ", ") }
    }
}
check(sessionsBroken == 0, "\(sessionsRun) random sessions: no window or display starts while the gate reads locked, a locked Mac settles on the placeholder, the remembered window comes back"
      + (firstBroken.map { ": \($0)" } ?? ""))
check(returned > 150 && lockedSettles > 1_000 && refusedSeen > 1_000,
      "the random sessions reach what they test: \(returned) windows came back after an unlock, \(lockedSettles) settled locked, \(refusedSeen) steps after a refused pick")

print("\(checks - failures) of \(checks) checks passed")
exit(failures == 0 ? 0 : 1)
