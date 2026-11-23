import Foundation
import StreamProtocol

/// Privacy mode (issues #133, #283 and #275; docs/privacy-mode-plan.md), part 1: Lock this Mac when the last device
/// leaves. Noah's #283: "An option on the Mac: when the last device disconnects, the Mac locks its screen (or logs out)
/// by itself. … So I can unlock my Mac from far away, and when I'm done it stays unlocked for anyone who walks up to it.
/// Locking it on the way out closes that." Lock, never log out ("Locking keeps everything running, and a paired device
/// can unlock it again"), after "a short wait first, so a connection that drops and comes back by itself (Wi-Fi
/// blinking) doesn't lock the Mac while I'm still using it". Darkening the screen (part 2) waits for the plan's G0.
///
/// The rule, events in and actions out, the clock the caller's (seconds that keep counting while the Mac sleeps):
/// - **Off unless turned on** (`State.on`, HostConfig.lockAfterSession, the Mac's alone): off, nothing happens and
///   nothing is said. Under it two switches of its own (the review of PR #402; Noah's "a toggle wherever sensible"):
///   Turn off its display too (`sleeps`, HostConfig.lockSleepsDisplay, on by default) and Only after a device away
///   from home (`onlyAway`, HostConfig.lockOnlyAfterAway, off by default).
/// - **Which departures count.** The registered sessions, as the server counts them (`sessions`): every session of
///   either door, paired or not, home or away, a session cut off while it leaves (its connection closes like any
///   other: StreamServer's `unregister`). A connection that only pairs (`sill-pair/1`), one the device gate refuses and
///   one an update's hold sends away are never registered, so they never start a wait nor end one. A move between
///   routes registers its new connection before the old one leaves, so the count never reaches zero; a reconnect
///   within the wait ends it. With Only after a device away from home, the last departure starts the wait only when a
///   session of that visit was away from home (`joined`, AwayPolicy.isAway): the sessions since the Mac last had none
///   with no wait under way, so a session back within a wait goes on with the visit; otherwise a line says why not.
/// - **The wait** (`grace`, 30 s): the last session's departure with the switch on starts it; a session registering
///   within it, the switch turned off, Only after a device away from home turned on with no session of the visit
///   away, and Sill quitting end it, each with its line.
/// - **At its end** (`tick`): this Mac locked already, another user (or the login window) on its console, or a reading
///   not established (`mac`): nothing is locked, a line says why. No display a lock screen could take a password at
///   (issue #298: a Mac with no working screen rejects the password typed from a device; `typesAt`): nothing is
///   locked, the line and Settings say so. Otherwise `lock`, then the confirmation: SessionLock's reading says locked
///   within `lockConfirm` (`look` asks it to read again meanwhile), and with Turn off its display too the displays
///   sleep (#275) unless a session came back meanwhile; the call unavailable (no `SACLockScreenImmediate`) or the
///   reading still unlocked: the failure's line, and the displays sleep instead (whatever that switch says), which
///   locks a Mac that asks for its password at once after display sleep.
/// - **Quitting** (`quit`): nothing locks from then on (a quit is this Mac's own user, a logout or an update's
///   restart); a wait under way says so. A crash or a force quit leaves no wait behind: a new launch starts with none,
///   and locks only after a departure it saw itself (the person who opens Sill again is usually at the Mac).
/// - **Only Sill.app itself acts** (`locksForReal`). The CLI, the bare SillMenuBar binary and every test host decide
///   the same and act on nothing: ScreenLocker's dry run says what it would do.
///
/// Pure (Foundation, and StreamProtocol's DesktopDisplays and LockPolicy's Reading), checked with StreamProtocol's
/// sources and LockPolicy.swift as one module (Tests/checks/privacy). `package` where Sill.app's Settings › Devices
/// reads it (its words, the status).
package enum PrivacyPolicy {
    // MARK: The constants

    /// The wait after the last device left before this Mac locks (the plan's open decision 4): a device's reconnect
    /// after a drop takes a few seconds, and iOS suspends Sill some seconds after it leaves the screen.
    package static let grace: Double = 30
    /// How long a lock Sill asked for has to show in SessionLock's reading before it counts as failed.
    package static let lockConfirm: Double = 3
    /// The glue's tick while a wait or a confirmation runs, and only then (`State.pending`).
    static let tick: Double = 0.5

    // MARK: Who acts

    /// Whether this host's lock and display sleep are real (ScreenLocker's `.real`): Sill.app itself alone (`bundled`:
    /// AppModel.bundled, the coordinator's `testHooks` false), and never with `--synthetic`. The CLI, the bare
    /// SillMenuBar binary (whose previews and `-SillSetAfter` any agent runs, and which saves the switch in its own
    /// defaults like any change) and every test host make ScreenLocker's dry run whatever the switch says: each says
    /// what it would do, and nothing is locked and no display sleeps (the review of PR #402, finding 1).
    static func locksForReal(synthetic: Bool, bundled: Bool) -> Bool { bundled && !synthetic }

    // MARK: Inputs

    /// This Mac's console as SessionLock's gate reads it (LockPolicy): unlocked; this session's screen locked; another
    /// user, the login window or nobody on the console; or no reading established yet.
    enum Mac: Equatable, Sendable { case unlocked, screenLocked, offConsole, unknown }

    /// The gate's reading (LockGate's `reading` and `established`) as the rule reads it: a gate with no reading
    /// established yet is `unknown`, never unlocked, so nothing locks before SessionLock has looked.
    static func mac(_ reading: LockPolicy.Reading, established: Bool) -> Mac {
        guard established else { return .unknown }
        switch reading {
        case .unlocked: return .unlocked
        case .screenLocked: return .screenLocked
        case .offConsole: return .offConsole
        }
    }

    /// What the lock call answered (ScreenLocker).
    enum Call: Equatable, Sendable {
        /// The private call was made. It returns nothing: SessionLock's reading tells whether the Mac locked.
        case made
        /// It could not be made: why, in the log's words.
        case unavailable(String)
    }

    /// Rule 10 (issue #298): whether a lock screen on these displays could take a password typed from a device. A
    /// screen (DesktopDisplays.role: the Mac's own, a monitor, Sidecar, AirPlay, another app's virtual display), never
    /// Sill's stage display or Desktop display, nor macOS's stand-in for a Mac with no screen, whose login window
    /// rejects the right password typed from a device (#298). #200's display for a Mac with no screen (PR #395, a
    /// `.sillDesktop`) does not count here as merged: whether a Mac whose only display is Sill's should lock is a
    /// question for Noah in PR #395 (docs/privacy-mode-plan.md's rule 10 foresaw that it would).
    static func typesAt(_ roles: [DesktopDisplays.Role]) -> Bool { roles.contains(.screen) }

    // MARK: Outputs

    enum Action: Equatable, Sendable {
        /// Lock this Mac now (ScreenLocker: login.framework's SACLockScreenImmediate on its own queue; anything but
        /// Sill.app itself only says it would, `locksForReal`).
        case lock
        /// Put the displays to sleep (`pmset displaysleepnow`; anything but Sill.app itself only says it would).
        case sleepDisplays
        /// SessionLock looks again now: a lock's confirmation needs a fresh reading (its witnesses that are not
        /// watched, a test host's file among them, are read only at a look).
        case look
        /// One log line.
        case line(String)
    }

    /// What a wait ended in (the check's, and the log's).
    enum Outcome: Equatable, Sendable {
        case locked
        case alreadyLocked
        case offConsole
        case unknown
        /// Rule 10: no display to type the password at.
        case noDisplay
        /// The lock was asked and did not happen: why, in Settings' words.
        case failed(String)
    }

    /// Settings › Devices' warning under the switch, while it is on: no display to type the password at (rule 10),
    /// else the last lock Sill asked for that did not happen; nil for neither.
    package static func warning(on: Bool, noDisplay: Bool, failure: String?) -> String? {
        guard on else { return nil }
        if noDisplay { return Words.noDisplayWarning }
        return failure.map(Words.failedWarning)
    }

    // MARK: The state

    /// The rule's state, which the main actor owns (PrivacyLock). Every mutating call returns what to do, in order.
    struct State: Equatable, Sendable {
        /// Lock this Mac when the last device leaves (HostConfig.lockAfterSession).
        private(set) var on: Bool
        /// Turn off its display too (HostConfig.lockSleepsDisplay): read when a lock is confirmed.
        private(set) var sleeps: Bool
        /// Only after a device away from home (HostConfig.lockOnlyAfterAway): read at the last departure.
        private(set) var onlyAway: Bool
        /// The wait (`PrivacyPolicy.grace`, or a test host's SILL_TEST_PRIVACY_GRACE).
        let grace: Double
        /// The sessions registered now, as the server counts them.
        private(set) var sessions = 0
        /// A session away from home registered during this visit (`joined`): the sessions since the Mac last had none
        /// with no wait under way. Kept whatever the switches say; cleared when a visit ends (a departure that starts
        /// no wait, a wait that ends but by a session's return).
        private(set) var awaySeen = false
        /// When the last session left, while its wait runs.
        private(set) var waitingSince: Double?
        /// When the lock was asked, while its confirmation runs.
        private(set) var confirmingSince: Double?
        /// Sill is quitting: nothing locks from now on.
        private(set) var quitting = false
        /// What the last wait ended in; nil before the first.
        private(set) var last: Outcome?
        /// Why the last lock Sill asked for did not happen, in Settings' words; nil once one did, and before any.
        private(set) var failure: String?

        init(on: Bool, sleeps: Bool = true, onlyAway: Bool = false, grace: Double = PrivacyPolicy.grace) {
            self.on = on
            self.sleeps = sleeps
            self.onlyAway = onlyAway
            self.grace = grace
        }

        /// A wait or a lock's confirmation runs: the glue ticks (`PrivacyPolicy.tick`), and Sill.app holds App Nap
        /// off so the ticks keep their time.
        var pending: Bool { waitingSince != nil || confirmingSince != nil }

        /// The server's count of registered sessions changed. The last one leaving with the switch on starts the wait,
        /// unless Only after a device away from home is on and no session of the visit was away (its line says so);
        /// one registering ends it.
        mutating func sessions(_ count: Int, at now: Double) -> [Action] {
            let was = sessions
            sessions = max(0, count)
            guard !quitting else { return [] }
            if sessions > 0 {
                guard waitingSince != nil else { return [] }
                waitingSince = nil
                return [.line(Words.cameBack(grace))]
            }
            guard was > 0 else { return [] }
            guard on, !onlyAway || awaySeen else {
                // No wait: the visit is over.
                awaySeen = false
                return on ? [.line(Words.notAway)] : []
            }
            waitingSince = now
            return [.line(Words.lastLeft(grace))]
        }

        /// A session registered (the glue calls it after the count that took it): whether it is away from home
        /// (AwayPolicy.isAway), for Only after a device away from home.
        mutating func joined(away: Bool) {
            if away { awaySeen = true }
        }

        /// The switch changed (Settings › Devices). Off ends a wait under way; on starts none: only a departure with
        /// the switch on does.
        mutating func switched(_ on: Bool, at now: Double) -> [Action] {
            guard on != self.on else { return [] }
            self.on = on
            guard !on, waitingSince != nil else { return [] }
            waitingSince = nil
            awaySeen = false
            return [.line(Words.switchedOff)]
        }

        /// Turn off its display too changed: the next confirmed lock reads it.
        mutating func setSleeps(_ sleeps: Bool) {
            self.sleeps = sleeps
        }

        /// Only after a device away from home changed. On, with a wait under way for a visit that had no session away
        /// from home: the wait ends, with its line. Off starts no wait: only a departure does.
        mutating func setOnlyAway(_ onlyAway: Bool, at now: Double) -> [Action] {
            guard onlyAway != self.onlyAway else { return [] }
            self.onlyAway = onlyAway
            guard onlyAway, !awaySeen, waitingSince != nil else { return [] }
            waitingSince = nil
            return [.line(Words.nowOnlyAway)]
        }

        /// The glue's tick, and a change of the reading: a confirmation decided (the reading says locked, or its time
        /// is up), then a wait ended. `display` is asked only at a wait's end, with the Mac reading unlocked.
        mutating func tick(at now: Double, mac: Mac, display: @autoclosure () -> Bool) -> [Action] {
            guard !quitting else { return [] }
            var out: [Action] = []
            if let since = confirmingSince {
                if mac == .screenLocked || mac == .offConsole {
                    confirmingSince = nil
                    last = .locked
                    failure = nil
                    if !sleeps {
                        out.append(.line(Words.locked))
                    } else {
                        out += sessions == 0 ? [.line(Words.lockedAndSleeps), .sleepDisplays] : [.line(Words.lockedDeviceBack)]
                    }
                } else if now - since >= PrivacyPolicy.lockConfirm {
                    confirmingSince = nil
                    last = .failed(Words.stillUnlockedReason)
                    failure = Words.stillUnlockedReason
                    out.append(.line(Words.couldNotLock(Words.stillUnlockedLog, sleeps: sessions == 0)))
                    if sessions == 0 { out.append(.sleepDisplays) }
                } else {
                    out.append(.look)
                }
            }
            guard let since = waitingSince, now - since >= grace else { return out }
            waitingSince = nil
            awaySeen = false        // the visit is over with its wait
            guard on, sessions == 0 else { return out }
            switch mac {
            case .screenLocked:
                last = .alreadyLocked
                out.append(.line(Words.alreadyLocked))
            case .offConsole:
                last = .offConsole
                out.append(.line(Words.notOnConsole))
            case .unknown:
                last = .unknown
                out.append(.line(Words.unknownReading))
            case .unlocked:
                guard display() else {
                    last = .noDisplay
                    out.append(.line(Words.noDisplay))
                    break
                }
                // One lock at a time: a confirmation still under way (asked at an earlier wait's end, a device that
                // came and went since) decides for this one too.
                guard confirmingSince == nil else {
                    out.append(.line(Words.lockUnderWay(grace)))
                    break
                }
                confirmingSince = now
                out += [.line(Words.locking(grace)), .lock]
            }
            return out
        }

        /// The lock call's answer. Unavailable: the failure's line, and the displays sleep instead (unless a session
        /// came back meanwhile). Made: nothing until the reading says (`tick`).
        mutating func called(_ call: Call, at now: Double) -> [Action] {
            guard case .unavailable(let why) = call, confirmingSince != nil, !quitting else { return [] }
            confirmingSince = nil
            last = .failed(Words.unavailableReason)
            failure = Words.unavailableReason
            var out: [Action] = [.line(Words.couldNotLock(why, sleeps: sessions == 0))]
            if sessions == 0 { out.append(.sleepDisplays) }
            return out
        }

        /// Sill is quitting (the app's Quit, a logout, an update's restart, a signal): nothing locks from now on.
        mutating func quit() -> [Action] {
            guard !quitting else { return [] }
            quitting = true
            let waited = waitingSince != nil
            waitingSince = nil
            confirmingSince = nil
            return waited ? [.line(Words.quitting)] : []
        }
    }

    // MARK: The TEST ONLY hooks

    /// What a test host takes (DoorPolicy.isTestHost; TestHooks says elsewhere that each is ignored):
    /// SILL_TEST_PRIVACY_GRACE=<seconds> (the wait, 0.5 to 600), SILL_TEST_PRIVACY_DISPLAYS=<n> (the displays a lock
    /// screen could take a password at, 0 to 16, in place of this Mac's) and SILL_TEST_PRIVACY_NO_SYMBOL=1 (the lock
    /// call answers as on a macOS without SACLockScreenImmediate). `lines`: one for each set, taken or not.
    struct TestHooks: Equatable, Sendable {
        var grace: Double?
        var displays: Int?
        var noSymbol = false
        var lines: [String] = []
    }

    static func testHooks(testHost: Bool, environment env: [String: String]) -> TestHooks {
        var h = TestHooks()
        guard testHost else { return h }
        if let raw = env["SILL_TEST_PRIVACY_GRACE"], !raw.isEmpty {
            if let s = Double(raw), s >= 0.5, s <= 600 {
                h.grace = s
                h.lines.append("Test privacy: the wait before the lock is \(Words.number(s)) s (SILL_TEST_PRIVACY_GRACE).")
            } else {
                h.lines.append("SILL_TEST_PRIVACY_GRACE=\(raw) ignored: seconds from 0.5 to 600.")
            }
        }
        if let raw = env["SILL_TEST_PRIVACY_DISPLAYS"], !raw.isEmpty {
            if let n = Int(raw), (0...16).contains(n) {
                h.displays = n
                h.lines.append("Test privacy: this Mac counts as having \(n) display\(n == 1 ? "" : "s") to type its password at (SILL_TEST_PRIVACY_DISPLAYS).")
            } else {
                h.lines.append("SILL_TEST_PRIVACY_DISPLAYS=\(raw) ignored: a number from 0 to 16.")
            }
        }
        if env["SILL_TEST_PRIVACY_NO_SYMBOL"] == "1" {
            h.noSymbol = true
            h.lines.append("Test privacy: the lock answers as on a macOS without SACLockScreenImmediate (SILL_TEST_PRIVACY_NO_SYMBOL).")
        }
        return h
    }

    // MARK: Every word

    package enum Words {
        // Settings › Devices
        package static let toggle = "Lock this Mac when the last device leaves"
        /// The two switches under it, shown while it is on.
        package static let sleepToggle = "Turn off its display too"
        package static let awayToggle = "Only after a device away from home"
        package static let footnoteOff = "For a Mac you use from afar: once you’re done, it locks itself, so whoever walks up to it finds its lock screen."
        package static func footnoteOn(_ grace: Double, sleeps: Bool = true, onlyAway: Bool = false) -> String {
            "This Mac locks \(seconds(grace)) after the last iPhone or iPad leaves (a connection that drops and comes back within that time doesn’t lock it)"
                + (sleeps ? ", and its display goes to sleep." : ".")
                + (onlyAway ? " Only when one of them connected from away from home, through a VPN or over the internet: devices used only at home leave it as it is." : "")
                + " A paired device can unlock it again with your password."
        }
        package static let noDisplayWarning = "This Mac has no display to show its lock screen on, so Sill won’t lock it: you couldn’t type its password from a device."
        package static func failedWarning(_ why: String) -> String { "Sill couldn’t lock this Mac the last time: \(why)." }
        package static let unavailableReason = "this version of macOS doesn’t let Sill lock it"
        package static let stillUnlockedReason = "it was still unlocked \(seconds(PrivacyPolicy.lockConfirm)) after Sill asked"

        // Sill.log
        /// `dry`: not Sill.app itself (`locksForReal`), which only says what it would do.
        package static func startLine(_ grace: Double, sleeps: Bool = true, onlyAway: Bool = false, dry: Bool = false) -> String {
            "Privacy: Lock this Mac when the last device leaves is on: \(number(grace)) s after the last device leaves"
                + (onlyAway ? ", when one connected from away from home," : ",")
                + " Sill locks this Mac" + (sleeps ? " and puts its display to sleep." : ".")
                + (dry ? " A dry run here (only Sill.app itself locks a Mac): it says what it would do." : "")
        }
        package static func lastLeft(_ grace: Double) -> String {
            "Privacy: the last device left; this Mac locks in \(number(grace)) s unless one connects again."
        }
        package static let notAway = "Privacy: the last device left; none connected from away from home, so this Mac won’t be locked."
        package static let nowOnlyAway = "Privacy: Lock this Mac when the last device leaves is now only after a device away from home, and none was; this Mac won’t be locked."
        package static func cameBack(_ grace: Double) -> String {
            "Privacy: a device connected again within \(number(grace)) s; this Mac won’t be locked."
        }
        package static let switchedOff = "Privacy: Lock this Mac when the last device leaves is off; this Mac won’t be locked."
        package static func locking(_ grace: Double) -> String { "Privacy: locking this Mac: the last device left \(number(grace)) s ago." }
        package static func lockUnderWay(_ grace: Double) -> String {
            "Privacy: the last device left \(number(grace)) s ago; the lock Sill asked for before is still being confirmed."
        }
        package static let lockedAndSleeps = "Privacy: this Mac is locked; its display sleeps."
        /// Turn off its display too off.
        package static let locked = "Privacy: this Mac is locked."
        package static let lockedDeviceBack = "Privacy: this Mac is locked; its display stays on for the device that connected meanwhile."
        package static let alreadyLocked = "Privacy: not locking this Mac: it is locked already."
        package static let notOnConsole = "Privacy: not locking this Mac: another user, or the login window, is on its screen."
        package static let unknownReading = "Privacy: not locking this Mac: Sill can’t tell yet whether it is locked."
        package static let noDisplay = "Privacy: not locking this Mac: it has no display to type its password at (issue #298)."
        package static func couldNotLock(_ why: String, sleeps: Bool) -> String {
            "Privacy: couldn’t lock this Mac (\(why))" + (sleeps ? "; its display sleeps instead." : ".")
        }
        package static let unavailableLog = "macOS has no SACLockScreenImmediate"
        package static let stillUnlockedLog = "it still read unlocked \(number(PrivacyPolicy.lockConfirm)) s later"
        package static let quitting = "Privacy: Sill is quitting; this Mac won’t be locked."

        // The dry run (ScreenLocker) of everything but Sill.app itself: the CLI, the bare binary, a test host
        package static let dryLock = "Privacy (dry run): would lock this Mac now; nothing is locked."
        package static let drySleep = "Privacy (dry run): would put this Mac’s display to sleep; nothing sleeps."

        /// "30 seconds", "1 second", "1.5 seconds".
        package static func seconds(_ s: Double) -> String { "\(number(s)) second\(s == 1 ? "" : "s")" }
        /// "30", "1.5".
        package static func number(_ s: Double) -> String {
            s == s.rounded() ? String(Int(s)) : String(format: "%.1f", s)
        }
    }
}
