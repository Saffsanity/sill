// LockPolicy (Sources/SillHost/LockPolicy.swift; docs/locked-mac-plan.md), pure, compiled with
// StreamProtocol's sources as one module: what a locked Mac shows and what a device may do at it, the
// window that comes back at the unlock, the lines, the device's line (Switcher.swift's LockedMac), and a
// copy of the coordinator's glue (StreamCoordinator.swift's `readLock`, `lockChanged`, `enforceLock`,
// `afterUnlock`, `select`'s gate and its end, `handle`'s weighing, the client count) run through directed
// and random sessions: no window ever starts streaming while the Mac reads locked, none streams once
// things settle, a device's pick made while locked never streams, and the window that streamed at the
// lock comes back at the unlock unless a pick, its closing or nobody left says otherwise.
import Foundation

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

// MARK: - A device's requests

let everyRequest: [(R, String)] = [
    (.pick(.window(7)), "a window picked"), (.pick(.desktop), "the Desktop picked"), (.pick(.none), "nothing picked"),
    (.launch, "an app launched"), (.windowCommand, "a window's buttons"), (.menuSubscription, "the menus' subscription"),
    (.menuRequest, "a menu fetched or chosen"), (.gesture, "a gesture"), (.clipboardText, "a device's clipboard text"),
    (.clipboardSubscription, "the clipboard's subscription or stop"), (.input(letsGo: false), "input"),
    (.input(letsGo: true), "the up of what the device holds down"), (.other, "settings, the viewport, a keyframe, Pair This iPad…"),
]
// The table the plan writes (docs/locked-mac-plan.md, "The rule"), locked: [unpaired, paired].
func expectedLocked(_ r: R, paired: Bool) -> P.Decision {
    switch r {
    case .pick(.window): return .refuse(.pick)
    case .pick: return .take
    case .launch: return .refuse(.launch)
    case .windowCommand: return .refuse(.windowCommand)
    case .menuSubscription: return .take
    case .menuRequest: return .refuse(.menus)
    case .gesture: return .refuse(.gesture)
    case .clipboardText: return .refuse(.clipboard)
    case .clipboardSubscription: return .take
    case .input(let letsGo): return paired ? .take : (letsGo ? .letGo : .refuse(.input))
    case .other: return .take
    }
}
for (r, what) in everyRequest {
    for paired in [false, true] {
        check(P.decide(r, locked: false, paired: paired) == .take, "unlocked, \(what) from a\(paired ? " paired" : "n unpaired") session: taken")
        let got = P.decide(r, locked: true, paired: paired), want = expectedLocked(r, paired: paired)
        check(got == want, "locked, \(what) from a\(paired ? " paired" : "n unpaired") session: \(want) (got \(got))")
    }
}
check(P.decide(.pick(.window(1)), locked: true, paired: true) == .refuse(.pick) && P.decide(.launch, locked: true, paired: true) == .refuse(.launch)
      && P.decide(.gesture, locked: true, paired: true) == .refuse(.gesture) && P.decide(.menuRequest, locked: true, paired: true) == .refuse(.menus),
      "locked: a paired session's pick, launch, gesture and menu are refused too (only its input is taken)")
check(P.decide(.input(letsGo: false), locked: true, paired: true) == .take && P.decide(.input(letsGo: true), locked: true, paired: true) == .take,
      "locked: a paired session's input lands whole, a down too (the owner types the password)")
check(P.decide(.input(letsGo: false), locked: true, paired: false) == .refuse(.input)
      && P.decide(.input(letsGo: true), locked: true, paired: false) == .letGo,
      "locked: an unpaired session types nothing; the up of a key or a button it holds down still goes")
check(P.Refusal.allCases.map(\.rawValue) == ["pick", "launch", "windowCommand", "menus", "gesture", "clipboard", "input"],
      "seven refusal kinds, each its own summary line")

// MARK: - What the devices are shown

let open = P.shown(locked: false), shut = P.shown(locked: true)
check(open == P.Shown(thumbnails: true, appsAndIcons: true, menus: true, sound: true, clipboard: true), "unlocked: everything shown")
check(!shut.thumbnails, "locked: no thumbnails")
check(!shut.appsAndIcons, "locked: no icons and no installed apps")
check(!shut.menus, "locked: no app's menus")
check(!shut.sound, "locked: no sound")
check(!shut.clipboard, "locked: the clipboard neither read nor written")

let windows = [WindowInfo(id: 11, title: "Budget.numbers", appName: "Numbers", bundleID: "com.apple.iWork.Numbers", width: 1200, height: 800),
               WindowInfo(id: 12, title: "Inbox", appName: "Mail", bundleID: "com.apple.mail", width: 1000, height: 700)]
var full = WindowList(macName: "Noah’s MacBook Pro", windows: windows, active: .window(11), launchID: "L1", hostVersion: "0.6.0",
                      protocol: 1, gestures: 1, clipboard: 1)
full.keyRepeat = 1
let unlockedList = P.list(full, locked: false), lockedList = P.list(full, locked: true)
check(sortedJSON(unlockedList) == sortedJSON(full) && Wire.encode(unlockedList).count == Wire.encode(full).count,
      "unlocked: the list as it is, byte for byte: \(sortedJSON(unlockedList))")
check(!json(unlockedList).contains("locked"), "unlocked: no `locked` key")
check(lockedList.windows.isEmpty, "locked: no windows")
check(lockedList.clipboard == nil && !json(lockedList).contains("clipboard"), "locked: no clipboard (a device sends no kind 32, offers no Paste)")
check(lockedList.locked == true && json(lockedList).contains(#""locked":true"#), "locked: `locked` true: \(json(lockedList))")
check(lockedList.macName == full.macName && lockedList.active == full.active && lockedList.launchID == "L1" && lockedList.hostVersion == "0.6.0"
      && lockedList.protocol == 1 && lockedList.gestures == 1 && lockedList.keyRepeat == 1,
      "locked: the rest of the list as it is (the Mac's name, what streams, the launch, the version, gestures, key repeat)")
check(!json(lockedList).contains("Budget") && !json(lockedList).contains("Inbox") && !json(lockedList).contains("com.apple.mail"),
      "locked: no window's title, app or bundle in the bytes")
let decoded = Wire.decode(WindowList.self, from: Wire.encode(lockedList))
check(decoded?.locked == true && decoded?.windows.isEmpty == true, "locked: the list round-trips")
check(Wire.decode(WindowList.self, from: Wire.encode(full))?.locked == nil, "a list without it decodes with locked nil")
let before = #"{"macName":"Mac mini","windows":[],"active":{"desktop":{}},"launchID":"L","hostVersion":"0.5.1","protocol":1,"gestures":1,"clipboard":1}"#
check(Wire.decode(WindowList.self, from: Data(before.utf8)).map { $0.locked == nil && $0.clipboard == 1 } == true,
      "an older host's list (Sill for Mac 0.5.1's keys) decodes, locked nil")
struct OlderReader: Decodable { var macName: String; var windows: [WindowInfo]; var active: StreamSource; var clipboard: Int?; var keyRepeat: Int? }
check(Wire.decode(OlderReader.self, from: Wire.encode(lockedList)).map { $0.macName == full.macName && $0.windows.isEmpty && $0.clipboard == nil } == true,
      "an older device reads a locked list (it skips `locked`) and sees no windows")
check(Wire.decode(WindowList.self, from: Data(#"{"macName":"M","windows":[],"active":{"none":{}},"locked":false}"#.utf8))?.locked == false,
      "`locked` false decodes (no host of this build sends it)")

// MARK: - The TEST ONLY file

check(P.fileSaysLocked("1") && P.fileSaysLocked("1\n") && P.fileSaysLocked(" 1 \n"), "the file: \"1\" says locked (white space around it too)")
check(!P.fileSaysLocked("0") && !P.fileSaysLocked("") && !P.fileSaysLocked(nil) && !P.fileSaysLocked("yes") && !P.fileSaysLocked("11")
      && !P.fileSaysLocked("true") && !P.fileSaysLocked("10"), "the file: \"0\", empty, missing or anything else says nothing")
check(P.pollInterval == 1, "the lock is read once a second while a device is connected")

// MARK: - The State

var s = P.State()
check(!s.locked && s.comesBack == nil, "a new State: unlocked, nothing to come back")
check(s.read(locked: false) == nil && !s.locked, "unlocked read unlocked: no change")
check(s.read(locked: true) == .locked && s.locked, "unlocked read locked: the lock")
check(s.read(locked: true) == nil && s.locked, "locked read locked: no change")
check(s.read(locked: false) == .unlocked && !s.locked, "locked read unlocked: the unlock")

// The gate, unlocked.
s = P.State()
check(s.select(.window(3), active: .desktop, pick: true) == .proceed, "unlocked: a window picked proceeds")
check(s.select(.desktop, active: .window(3), pick: false) == .proceed && s.select(.none, active: .desktop, pick: false) == .proceed,
      "unlocked: the Desktop and nothing proceed")
// The gate, locked.
s = P.State(); _ = s.read(locked: true)
check(s.select(.window(5), active: .window(5), pick: false) == .desktop && s.comesBack == 5,
      "locked: a restart of the window that streams becomes the Desktop, and it is what comes back")
check(s.select(.window(6), active: .desktop, pick: false) == .stay && s.comesBack == 6,
      "locked, the Desktop streaming: a window asked for changes nothing but what comes back")
check(s.select(.window(8), active: .none, pick: true) == .desktop && s.comesBack == 8,
      "locked, nothing streaming: a window asked for (a pick queued before the lock) starts the Desktop")
check(s.select(.desktop, active: .desktop, pick: true) == .proceed && s.comesBack == 8,
      "locked: the Desktop picked proceeds and keeps what comes back (the device asks for it by itself)")
check(s.select(.none, active: .desktop, pick: false) == .proceed && s.comesBack == 8, "locked: nothing proceeds (the last device left)")
// What comes back.
_ = s.read(locked: false)
var t = s
check(t.afterUnlock(listed: [8, 9], active: .desktop, devices: 1) == 8 && t.comesBack == nil, "the unlock: the window comes back, once")
check(t.afterUnlock(listed: [8, 9], active: .desktop, devices: 1) == nil, "…and not twice")
t = s
check(t.afterUnlock(listed: [9], active: .desktop, devices: 1) == nil && t.comesBack == nil, "the unlock: a window no longer listed does not come back")
t = s
check(t.afterUnlock(listed: [8], active: .window(9), devices: 1) == nil && t.comesBack == nil, "the unlock: something other than the Desktop streams: nothing comes back")
t = s
check(t.afterUnlock(listed: [8], active: .none, devices: 1) == nil, "the unlock: nothing streams: nothing comes back")
t = s
check(t.afterUnlock(listed: [8], active: .desktop, devices: 0) == nil && t.comesBack == nil, "the unlock: no device connected: nothing comes back")
t = s
check(t.select(.window(9), active: .desktop, pick: true) == .proceed && t.comesBack == nil
      && t.afterUnlock(listed: [8, 9], active: .desktop, devices: 1) == nil, "unlocked: a pick forgets what would have come back")
t = s
check(t.select(.desktop, active: .desktop, pick: false) == .proceed && t.comesBack == 8, "unlocked: a restart keeps what comes back")
t = s
t.devicesLeft()
check(t.comesBack == nil && t.afterUnlock(listed: [8], active: .desktop, devices: 1) == nil, "the last device left: nothing comes back")
// Locked again before the unlock's look: kept for the next unlock.
t = s
_ = t.read(locked: true)
check(t.afterUnlock(listed: [8], active: .desktop, devices: 1) == nil && t.comesBack == 8, "locked again before the unlock's look: kept")
_ = t.read(locked: false)
check(t.afterUnlock(listed: [8], active: .desktop, devices: 1) == 8, "…and it comes back at the next unlock")

// MARK: - The lines

check(P.lockedLine == "Locked: this Mac's screen is locked; devices see the lock screen until it is unlocked.", "the lock's line")
check(P.unlockedLine == "Unlocked: this Mac's screen is unlocked; devices see its windows again.", "the unlock's line")
check(P.menuNote == "The Mac is locked.", "the menus' note")
let words: [(P.Refusal, String, String)] = [
    (.pick, "Locked: refused a window pick; devices see only the lock screen until this Mac is unlocked.",
     "Locked: refused 3 window picks; devices see only the lock screen until this Mac is unlocked."),
    (.launch, "Locked: refused an app launch; devices see only the lock screen until this Mac is unlocked.",
     "Locked: refused 3 app launches; devices see only the lock screen until this Mac is unlocked."),
    (.windowCommand, "Locked: refused a window's button; devices see only the lock screen until this Mac is unlocked.",
     "Locked: refused 3 presses of windows' buttons; devices see only the lock screen until this Mac is unlocked."),
    (.menus, "Locked: refused a menu request; devices see only the lock screen until this Mac is unlocked.",
     "Locked: refused 3 menu requests; devices see only the lock screen until this Mac is unlocked."),
    (.gesture, "Locked: refused a gesture; devices see only the lock screen until this Mac is unlocked.",
     "Locked: refused 3 gestures; devices see only the lock screen until this Mac is unlocked."),
    (.clipboard, "Locked: dropped a device's clipboard text; the clipboard waits for this Mac to be unlocked.",
     "Locked: dropped 3 clipboard texts from devices; the clipboard waits for this Mac to be unlocked."),
    (.input, "Locked: dropped an input event from unpaired devices; only a paired device types at a locked Mac.",
     "Locked: dropped 3 input events from unpaired devices; only a paired device types at a locked Mac."),
]
for (kind, one, three) in words {
    check(P.refusedLine(kind, count: 1) == one, "\(kind)'s line for one: \(P.refusedLine(kind, count: 1))")
    check(P.refusedLine(kind, count: 3) == three, "\(kind)'s line for three: \(P.refusedLine(kind, count: 3))")
    check(P.refusedLine(kind, count: 0) == one, "\(kind)'s line for a count of none reads as one")
}

// MARK: - The device's line (StreamProtocol)

check(LockedMac.line(mac: "Noah’s MacBook Pro") == "Noah’s MacBook Pro is locked. Unlock it to see its windows.", "the device's line")
check(LockedMac.line(mac: "") == "The Mac is locked. Unlock it to see its windows.", "the device's line without the Mac's name")

// MARK: - The coordinator's glue

/// A copy of StreamCoordinator's glue around LockPolicy.State, a select taking one step to finish (so one
/// can be under way when the lock is read), the tasks `lockChanged` starts run as their own steps.
struct Glue {
    enum Job: Equatable { case enforce, afterUnlock, desktop }
    var lock = P.State()
    var truth = false                 // the console, read only by `readLock`
    var active: StreamSource = .none
    var inFlight: StreamSource?       // a select under way (`switching`), with the source the gate let through
    var inFlightPick = false
    var listed: Set<UInt32> = [1, 2, 3]
    var devices = 1
    var pendingLaunch: UInt32?
    var jobs: [Job] = []
    var deselectWhenSettled = false
    var violations: [String] = []
    /// Windows a device picked while the Mac read locked: none may ever start streaming before an unlock.
    var refusedPicks: Set<UInt32> = []
    var lines: [String] = []

    mutating func readLock() {
        if let c = lock.read(locked: truth) { lockChanged(c) }
    }

    mutating func lockChanged(_ c: P.Change) {
        lines.append(c == .locked ? P.lockedLine : P.unlockedLine)
        if c == .locked { pendingLaunch = nil }
        jobs.append(c == .locked ? .enforce : .afterUnlock)
        if c == .unlocked { refusedPicks = [] }
    }

    mutating func select(_ source: StreamSource, pick: Bool) {
        guard inFlight == nil else { return }       // `switching`: refused
        readLock()
        var source = source
        switch lock.select(source, active: active, pick: pick) {
        case .proceed: break
        case .desktop: source = .desktop
        case .stay: return
        }
        if lock.locked, case .window(let id) = source { violations.append("a select started window \(id) while locked") }
        inFlight = source
        inFlightPick = pick
    }

    /// The select under way ends: what it started streams (a window no longer listed: nothing), then its
    /// end's checks. A window whose switch finds the Mac read locked before its pipeline starts streams
    /// nothing (`lockedMidSwitch`): remembered, nothing for a moment, then the Desktop.
    mutating func finishSelect() {
        guard let source = inFlight else { return }
        inFlight = nil
        if case .window = source, lock.locked {
            if devices > 0 { _ = lock.select(source, active: active, pick: false) }
            active = .none
            jobs.append(.desktop)
        } else {
            switch source {
            case .window(let id): active = listed.contains(id) ? source : .none
            case .desktop, .none: active = source
            }
        }
        if lock.locked, case .window(let id) = active { violations.append("window \(id) began streaming while locked") }
        if deselectWhenSettled {
            deselectWhenSettled = false
            if devices == 0, active != .none { select(.none, pick: false) }
        }
        if lock.locked, case .window = active { jobs.append(.enforce) }
    }

    mutating func runJob() {
        guard !jobs.isEmpty else { return }
        let job = jobs.removeFirst()
        switch job {
        case .enforce:
            guard lock.locked, inFlight == nil, case .window = active, devices > 0 else { return }
            select(active, pick: false)
        case .afterUnlock:
            if inFlight != nil { jobs.append(.afterUnlock); return }     // waits for the switch
            guard !lock.locked else { return }
            if let id = lock.afterUnlock(listed: Array(listed), active: active, devices: devices), inFlight == nil {
                select(.window(id), pick: false)
            }
        case .desktop:
            if devices > 0 { select(.desktop, pick: false) }
        }
    }

    // A device's messages (`handle`): a fresh reading, then the lock's decision.
    mutating func devicePick(_ s: StreamSource) {
        guard devices > 0 else { return }
        readLock()
        if P.decide(.pick(s), locked: lock.locked, paired: true) != .take {
            if case .window(let id) = s { refusedPicks.insert(id) }
            return
        }
        if inFlight != nil { return }                   // handlePick during a switch (to another source: dropped)
        select(s, pick: true)
    }

    mutating func deviceLaunch(_ id: UInt32) {
        guard devices > 0 else { return }
        readLock()
        guard P.decide(.launch, locked: lock.locked, paired: true) == .take else { return }
        pendingLaunch = id
    }

    /// The launched app's window appears (`windowsChanged`, which the catalog's poll calls only while a
    /// device is connected).
    mutating func windowAppears(_ id: UInt32) {
        listed.insert(id)
        guard devices > 0 else { return }
        if lock.locked, !isWindow(active) { return }
        if pendingLaunch == id {
            pendingLaunch = nil
            select(.window(id), pick: true)
        }
    }

    mutating func windowCloses(_ id: UInt32) {
        listed.remove(id)
        guard devices > 0 else { return }
        if lock.locked, !isWindow(active) { return }
        if active == .window(id) { select(.none, pick: false) }
    }

    mutating func restart() { select(active, pick: false) }

    mutating func deviceLeaves() {
        guard devices > 0 else { return }
        devices -= 1
        if devices == 0 {
            lock.devicesLeft()
            if inFlight != nil { deselectWhenSettled = true } else if active != .none { select(.none, pick: false) }
        }
    }

    mutating func deviceJoins() {
        devices += 1
        readLock()                                       // `onClientConnected`, before the catalog
    }

    mutating func settle() {
        var steps = 0
        while (inFlight != nil || !jobs.isEmpty), steps < 100 {
            if inFlight != nil { finishSelect() } else { runJob() }
            steps += 1
        }
        if steps >= 100 { violations.append("did not settle") }
    }

    var settledViolation: String? {
        if lock.locked, case .window(let id) = active { return "settled while locked with window \(id) streaming" }
        return nil
    }

    func isWindow(_ s: StreamSource) -> Bool { if case .window = s { return true }; return false }
}

func scenario(_ name: String, _ body: (inout Glue) -> Bool) {
    var g = Glue()
    let ok = body(&g)
    check(ok && g.violations.isEmpty, "\(name)\(g.violations.isEmpty ? "" : ": " + g.violations.joined(separator: "; "))")
}

scenario("S1: a window streams, the Mac locks, the Desktop streams; it unlocks, the window comes back") { g in
    g.devicePick(.window(2)); g.settle()
    guard g.active == .window(2) else { return false }
    g.truth = true; g.readLock(); g.settle()
    guard g.active == .desktop, g.lock.comesBack == 2 else { return false }
    g.truth = false; g.readLock(); g.settle()
    return g.active == .window(2) && g.lines == [P.lockedLine, P.unlockedLine]
}
scenario("S2: the window closes while locked: the Desktop stays at the unlock") { g in
    g.devicePick(.window(2)); g.settle()
    g.truth = true; g.readLock(); g.settle()
    g.windowCloses(2); g.settle()
    g.truth = false; g.readLock(); g.settle()
    return g.active == .desktop
}
scenario("S3: a pick right after the unlock, before the window comes back, wins") { g in
    g.devicePick(.window(2)); g.settle()
    g.truth = true; g.readLock(); g.settle()
    g.truth = false; g.readLock()                    // the unlock's job waits behind the pick
    g.devicePick(.window(3)); g.settle()
    return g.active == .window(3)
}
scenario("S4: the lock read while a switch to a window is under way: the window never streams, the Desktop follows") { g in
    g.devicePick(.window(2))                         // under way
    g.truth = true; g.readLock()
    g.finishSelect()
    guard g.active == .none, g.jobs.contains(.desktop) else { return false }
    g.settle()
    guard g.active == .desktop, g.lock.comesBack == 2 else { return false }
    g.truth = false; g.readLock(); g.settle()
    return g.active == .window(2)
}
scenario("S5: a device's window pick while locked is refused, and never streams, at the unlock either") { g in
    g.devicePick(.desktop); g.settle()
    g.truth = true; g.readLock(); g.settle()
    g.devicePick(.window(3)); g.settle()
    guard g.active == .desktop, g.lock.comesBack == nil else { return false }
    g.truth = false; g.readLock(); g.settle()
    return g.active == .desktop
}
scenario("S6: the lock not yet read (the poll's second): a pick reads it first and is refused") { g in
    g.devicePick(.desktop); g.settle()
    g.truth = true                                   // locked, not read yet
    g.devicePick(.window(1)); g.settle()
    return g.lock.locked && g.active == .desktop
}
scenario("S7: a restart while locked and the Desktop streaming: nothing restarts, the window is remembered") { g in
    g.devicePick(.window(1)); g.settle()
    g.truth = true; g.readLock(); g.settle()
    g.select(.window(1), pick: false)                // a settings change's restart of what streamed
    guard g.inFlight == nil, g.active == .desktop else { return false }
    g.truth = false; g.readLock(); g.settle()
    return g.active == .window(1)
}
scenario("S8: the last device leaves while locked: nothing comes back for the next one") { g in
    g.devicePick(.window(2)); g.settle()
    g.truth = true; g.readLock(); g.settle()
    g.deviceLeaves(); g.settle()
    guard g.active == .none else { return false }
    g.deviceJoins(); g.devicePick(.desktop); g.settle()
    g.truth = false; g.readLock(); g.settle()
    return g.active == .desktop
}
scenario("S9: a launch asked for before the lock picks nothing while locked") { g in
    g.devicePick(.desktop); g.settle()
    g.deviceLaunch(9)
    g.truth = true; g.readLock(); g.settle()
    g.windowAppears(9); g.settle()
    guard g.active == .desktop else { return false }
    g.truth = false; g.readLock(); g.settle()
    return g.active == .desktop
}
scenario("S10: a launch while locked is refused") { g in
    g.devicePick(.desktop); g.settle()
    g.truth = true; g.readLock(); g.settle()
    g.deviceLaunch(9)
    return g.pendingLaunch == nil
}
scenario("S11: locked again before the unlock's look: the window waits for the next unlock") { g in
    g.devicePick(.window(2)); g.settle()
    g.truth = true; g.readLock(); g.settle()
    g.truth = false; g.readLock()
    g.truth = true; g.readLock()                     // before the unlock's job ran
    g.settle()
    guard g.active == .desktop, g.lock.comesBack == 2 else { return false }
    g.truth = false; g.readLock(); g.settle()
    return g.active == .window(2)
}
scenario("S12: nothing streams at the lock: nothing at the unlock") { g in
    g.truth = true; g.readLock(); g.settle()
    g.truth = false; g.readLock(); g.settle()
    return g.active == .none && g.lines.count == 2
}
scenario("S13: the Desktop asked for while locked (the device's own request) streams it") { g in
    g.truth = true; g.readLock(); g.settle()
    g.devicePick(.desktop); g.settle()
    return g.active == .desktop
}

// Random sessions: the rule's invariants under every interleaving the glue allows.
struct RNG { var x: UInt64; mutating func next() -> UInt64 { x ^= x << 13; x ^= x >> 7; x ^= x << 17; return x }
             mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) } }
var rng = RNG(x: 0x5157_4C4F_434B_ED11)
var sessions = 0, broken = 0, returned = 0, lockedSettles = 0, refusedSeen = 0
var firstBroken: String?
for _ in 0..<5_000 {
    var g = Glue()
    var log: [String] = []
    for _ in 0..<(20 + rng.int(40)) {
        let e = rng.int(12)
        switch e {
        case 0: g.truth.toggle(); log.append("console \(g.truth ? "locks" : "unlocks")")
        case 1: g.readLock(); log.append("read")
        case 2: let w = UInt32(1 + rng.int(4)); g.devicePick(.window(w)); log.append("pick \(w)")
        case 3: g.devicePick(.desktop); log.append("pick desktop")
        case 4: g.restart(); log.append("restart")
        case 5: g.finishSelect(); log.append("finish")
        case 6: g.runJob(); log.append("job")
        case 7: let w = UInt32(1 + rng.int(4)); g.windowCloses(w); log.append("close \(w)")
        case 8: let w = UInt32(1 + rng.int(4)); g.windowAppears(w); log.append("open \(w)")
        case 9: let w = UInt32(5 + rng.int(2)); g.deviceLaunch(w); log.append("launch \(w)")
        case 10: if rng.int(3) == 0 { g.deviceLeaves(); log.append("leave") } else { g.deviceJoins(); log.append("join") }
        default: g.settle(); log.append("settle")
        }
        if !g.refusedPicks.isEmpty { refusedSeen += 1 }
    }
    // Settle with the console as it is now, read.
    g.readLock(); g.settle()
    if let v = g.settledViolation { g.violations.append(v) }
    if g.lock.locked { lockedSettles += 1 }
    // Then unlock and settle: what was remembered, if listed with a device left, streams.
    let remembered = g.lock.comesBack
    let wasLocked = g.lock.locked
    let desktopAtUnlock = g.active == .desktop
    g.truth = false; g.readLock(); g.settle()
    if wasLocked, let w = remembered, g.listed.contains(w), g.devices > 0, desktopAtUnlock, g.active != .window(w) {
        g.violations.append("window \(w) did not come back (active \(g.active))")
    }
    if wasLocked, let w = remembered, g.active == .window(w) { returned += 1 }
    sessions += 1
    if !g.violations.isEmpty {
        broken += 1
        if firstBroken == nil { firstBroken = g.violations.joined(separator: "; ") + " after " + log.joined(separator: ", ") }
    }
}
check(broken == 0, "\(sessions) random sessions: no window starts streaming while locked, none streams once settled locked, the remembered window comes back"
      + (firstBroken.map { ": \($0)" } ?? ""))
check(returned > 200 && lockedSettles > 500 && refusedSeen > 1_000,
      "the random sessions reach what they test: \(returned) windows came back at an unlock, \(lockedSettles) settled locked, \(refusedSeen) steps after a refused pick")

print("\(checks - failures) of \(checks) checks passed")
exit(failures == 0 ? 0 : 1)
