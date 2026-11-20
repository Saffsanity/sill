import Foundation
import StreamProtocol

/// Privacy mode, part 2 (issues #133 and #323; docs/privacy-mode-plan.md, rules 1–5, 7–9 and 11–14): this Mac's screens
/// dark while a device uses it. Noah's assignment of 2026-11-18: "Privacy mode options (blank local display when remote
/// access is being used)"; #323: "as a toggle". Part 1, Lock this Mac when the last device leaves, is PrivacyPolicy's.
///
/// The rule, events in and actions out, the clock the caller's (ContinuousClock's seconds):
/// - **Off unless turned on** (rule 1): `scope` (HostConfig.darkenScreen) off, nothing ever happens or is said.
/// - **Which sessions darken** (rule 2, `counts`): with `.away` a session while it is away from home (AwayPolicy.isAway:
///   the remote door from a VPN, the internet or a relay on this Mac), with `.any` every registered session. A move
///   registers its new connection before the old one leaves, so the count never drops; a move home is a home session.
/// - **Dark** (rule 3, `wantsDark`): the switch on, a screen to cover (rule 13), Sill not quitting, the Mac not taken
///   back (rule 8), and a session that counts connected, or its wait (`grace`) under way, or the wait over and held for
///   the lock it ends in (rule 6), or a lock asked at a key on this Mac awaiting its confirmation (rule 7).
/// - **Under the lock screen** (rule 4, `staysUnderLockScreen`, which the probe G0 settles): the black windows sit under
///   macOS's lock screen and stay up whatever the reading, so a lock shows the lock screen above them and an unlock (by
///   anyone) reveals black. If G0 finds no level that is above everything else and under the lock screen, the constant
///   is false: the windows come down at a locked reading (the person at the Mac must see the lock screen) and go up
///   again at an unlocked one if the dark still holds. (The gate's unlock comes after its 2 s settle; the raw witness
///   would shorten that gap and is the glue's to add if the fallback is ever taken.)
/// - **Up before the panel lights** (rule 5): `sessions` returns `raise` at the connect of a session that counts, and the
///   coordinator calls it before it declares the connect's user activity (DisplayWake), in the same main-actor turn.
/// - **The session's end** (rule 6): when the last session that counts leaves, the windows stay up `grace` (30 s, the
///   lock's wait, PrivacyPolicy.grace), then lift, unless a session that counts comes back meanwhile (one line each). If
///   that departure also started the lock's wait (no session at all left, Lock this Mac when the last device leaves on:
///   `lockFollows`), the dark holds at its end while the lock is under way (`lockHolds`: PrivacyPolicy's wait or
///   confirmation pending), so the room never sees the desktop between the dark and the lock screen; never longer than
///   `grace` + `lockConfirm` + `holdSlack` after the departure (R0: the screen never stays dark).
/// - **Someone at the Mac** (rule 7, `local`): while the windows are up and the Mac reads unlocked, a key or a click Sill
///   did not post (without `eventTag`) asks `lock` with the switch "A key or click on this Mac locks it" on (at most once
///   per `lockConfirm`), and shows the hint; with it off, or for a pointer movement, only the hint. A lock that does not
///   show in the reading within `lockConfirm`, or that macOS cannot make, switches the hint to its ⌃⌘Q wording
///   (macOS's own lock, which nothing observing keys stops) and asks no more until a lock shows or a switch changes.
///   While the Mac reads locked or off console, nothing counts: the lock screen takes it.
/// - **Taken back** (rule 8): an unlock while dark (the reading unlocked after screen locked or off console) is the
///   Mac's own unless a paired device's input was posted at the locked screen within `remoteUnlockWindow` before it
///   (LockPolicy lets only a paired session type there); off console nothing is posted, so a return to the console is
///   always the Mac's own. The Mac's own: the windows lift and stay down until no session at all is connected, or a
///   switch of darkening changes. The device's: the screen stays dark.
/// - **A switch changed** (rule 9): off lifts at once (its wait cancelled); on with a session that counts raises at
///   once; a change of scope that leaves no session counting lifts at once (no wait: the person chose it). Any change of
///   the darkening's switches clears `takenBack`.
/// - **Quitting** (rule 11): lift at once, nothing asked from then on.
/// - **A hung Sill** (rule 12): the watchdog's decisions, `watchdogFires` and `reopens`, pure here.
/// - **Screens** (rule 13, `screens`): every screen (DesktopDisplays.role) of some size; never Sill's stage or Desktop
///   display, nor macOS's stand-in for a Mac with no screen.
/// - **Only Sill.app itself darkens** (rule 14, `darkensForReal`: the lock's rule, PrivacyPolicy.locksForReal). The
///   CLI, the bare SillMenuBar binary and every test host decide the same and act on nothing: their glue says what it
///   would do (the "(dry run)" lines), draws nothing, watches no input and locks nothing. Sill.app's own glue waits for
///   the probe G0 (`heldBack`): until it is filled, darkening stays off there whatever the switch says.
///
/// Pure (Foundation, StreamProtocol's DesktopDisplays and SafeText, HostConfig's scope, PrivacyPolicy's constants,
/// readings and rule of who acts), checked with them as one module (Tests/checks/darken).
package enum DarkenPolicy {
    // MARK: The constants

    /// The wait after the last session that darkens leaves (rule 6): the lock's, so a departure that starts both ends both
    /// together, and a test host's SILL_TEST_PRIVACY_GRACE shortens both.
    package static let grace: Double = PrivacyPolicy.grace
    /// How long a lock asked at a key on this Mac has to show in SessionLock's reading (the lock's own).
    package static let lockConfirm: Double = PrivacyPolicy.lockConfirm
    /// Rule 8: a device's input posted at the locked screen this long before an unlock makes the unlock the device's.
    /// The gate's unlock comes 2 s after the real one (LockPolicy.Reader.settle), and typing a password and Return takes
    /// a few seconds more.
    package static let remoteUnlockWindow: Double = 10
    /// Rule 7: how long the hint shows after the screen darkens and after the Mac's own keys or mouse are used.
    package static let hintFor: Double = 10
    /// Rule 6: the hold for the lock lasts at most this long past the lock's own `grace` + `lockConfirm` (the two waits
    /// start a few milliseconds apart, and each rule acts at its own tick).
    static let holdSlack: Double = 1
    /// Rule 12: the main thread unanswered this long while dark ends Sill (its windows go with it).
    package static let hangLimit: Double = 10
    /// Rule 12: Sill opens itself again after such an end at most once in this long, so it is never a loop.
    package static let relaunchSpacing: Double = 600
    /// Rule 7: what every event Sill posts carries (`CGEventSource.userData`, so `kCGEventSourceUserData`; InputInjector
    /// sets it on its source once the seam is filled), never a person's hardware (whose events carry 0). G0's step 4
    /// says whether NSEvent's global monitor keeps it.
    package static let eventTag: Int64 = 0x5349_4C4C_5052_5631
    /// The glue's tick while something here waits on the clock (`State.pending`).
    static let tick: Double = 0.5
    /// Rule 4: the black windows sit under macOS's lock screen (true until the probe G0 says otherwise).
    package static let staysUnderLockScreen = true

    // MARK: Who darkens (rule 14)

    /// Whether this host darkens for real: its black windows, its watch on this Mac's own keys, clicks and pointer, and
    /// the lock a key on the dark Mac asks (ScreenLocker's `.real`). The lock's own rule (PrivacyPolicy.locksForReal):
    /// Sill.app itself alone (`bundled`: AppModel.bundled, the coordinator's `testHooks` false), and never with
    /// `--synthetic`. The CLI, the bare SillMenuBar binary (whose previews and `-SillSetAfter` any agent runs) and every
    /// test host get the dry run whatever the switch says: they say what they would do (`Words.dryRaise`, `.dryLift`,
    /// `.dryHint`, PrivacyPolicy.Words.dryLock) and draw, watch and lock nothing (the review of PR #400, follow-up 1).
    static func darkensForReal(synthetic: Bool, bundled: Bool) -> Bool {
        PrivacyPolicy.locksForReal(synthetic: synthetic, bundled: bundled)
    }

    /// Whether darkening stays off here whatever the switch says: a host that darkens for real (`real`) whose seams are
    /// not filled (`filled`: Sill.app until the probe G0 has chosen how its black windows are made), which says so once
    /// (`Words.waitsForProbe`). A dry run is never held back: it draws nothing anyway.
    static func heldBack(real: Bool, filled: Bool) -> Bool { real && !filled }

    // MARK: Inputs

    /// A person's input on this Mac as the observer tells it: only its kind, never a key code or a character.
    enum Local: Equatable, Sendable { case key, click, move }

    /// A display as the glue lists it (NSScreen in Sill.app; the online displays, or a test host's count).
    struct Display: Equatable, Sendable {
        var id: UInt32
        var vendor: UInt32
        var product: UInt32
        /// The stage made it this run (DesktopDisplays.role's `madeByStage`).
        var madeByStage = false
        var width: Double
        var height: Double
    }

    /// Rule 13: the displays the black windows cover, in the order given: a screen (DesktopDisplays.role: the Mac's own,
    /// a monitor, Sidecar, AirPlay, another app's virtual display) of some size. Never Sill's stage display (a picked
    /// window's) or Desktop display, whose pictures nobody at the Mac sees, nor macOS's stand-in for a Mac with no screen.
    static func screens(_ displays: [Display]) -> [UInt32] {
        displays.filter {
            DesktopDisplays.role(vendor: $0.vendor, product: $0.product, madeByStage: $0.madeByStage) == .screen
                && $0.width > 0 && $0.height > 0
        }.map(\.id)
    }

    /// Rule 2: whether a session darkens this Mac's screens under `scope`.
    static func counts(_ scope: HostConfig.Darken, away: Bool) -> Bool {
        switch scope {
        case .off: return false
        case .away: return away
        case .any: return true
        }
    }

    // MARK: Outputs

    /// The hint's second line: a key locks this Mac, or the way to use it here (⌃⌘Q).
    package enum Hint: Equatable, Sendable { case lock, pass }

    enum Action: Equatable, Sendable {
        /// The black windows up on every screen to cover (`screens`), with the hint; at a connect, before anything else.
        case raise
        /// The black windows down.
        case lift
        /// The hint's two lines on each dark screen until `until` (the glue fades them then).
        case hint(Hint, until: Double)
        /// Lock this Mac now (ScreenLocker; a test host only says it would).
        case lock
        /// SessionLock looks again now: the lock's confirmation needs a fresh reading.
        case look
        /// One log line.
        case line(String)
    }

    // MARK: The state

    /// The rule's state, which the main actor owns (PrivacyScreen). Every mutating call returns what to do, in order.
    struct State: Equatable, Sendable {
        /// Darken this Mac's screen (HostConfig.darkenScreen).
        private(set) var scope: HostConfig.Darken
        /// A key or click on this Mac locks it (HostConfig.darkenKeysLock).
        private(set) var keysLock: Bool
        /// Lock this Mac when the last device leaves (HostConfig.lockAfterSession): whether a departure starts the lock's
        /// wait too.
        private(set) var lockAfterSession: Bool
        /// The wait (`DarkenPolicy.grace`, or a test host's SILL_TEST_PRIVACY_GRACE, the lock's too).
        let grace: Double
        /// Rule 4 (`staysUnderLockScreen`, or the check's choice).
        let underLockScreen: Bool

        /// The sessions registered now (cut off ones not counted), away from home and at home.
        private(set) var away = 0
        private(set) var home = 0
        /// The screens to cover now (rule 13).
        private(set) var screens = 0
        /// This Mac's console as SessionLock's gate reads it.
        private(set) var mac: PrivacyPolicy.Mac = .unknown

        /// The black windows are up (the last `raise` or `lift` said).
        private(set) var up = false
        /// When the last session that darkens left, while its wait runs (rule 6).
        private(set) var waitingSince: Double?
        /// That departure left no session at all with the lock's switch on: the lock's wait started with it.
        private(set) var lockFollows = false
        /// The wait is over and the dark holds for the lock under way; since that departure.
        private(set) var holdingSince: Double?
        /// The Mac's own user unlocked it while dark (rule 8).
        private(set) var takenBack = false
        /// Sill is quitting (rule 11).
        private(set) var quitting = false
        /// A lock asked at a key or click on this Mac, while its confirmation runs (rule 7); and the last one asked.
        private(set) var askedAt: Double?
        private(set) var lastAsk: Double?
        /// The last lock asked at a key did not happen: the hint says ⌃⌘Q, and keys ask no more.
        private(set) var keysPass = false
        /// The hint shows until then (rule 7), as the glue was last told.
        private(set) var hintUntil: Double?
        /// The last input a paired device posted at the locked screen, and its name (rule 8).
        private(set) var deviceInputAt: Double?
        private(set) var deviceName: String?

        init(scope: HostConfig.Darken, keysLock: Bool, lockAfterSession: Bool, grace: Double = DarkenPolicy.grace,
             underLockScreen: Bool = DarkenPolicy.staysUnderLockScreen) {
            self.scope = scope
            self.keysLock = keysLock
            self.lockAfterSession = lockAfterSession
            self.grace = grace
            self.underLockScreen = underLockScreen
        }

        /// Every session registered now.
        var sessions: Int { away + home }
        /// The sessions that darken (rule 2).
        var counting: Int { (DarkenPolicy.counts(scope, away: true) ? away : 0) + (DarkenPolicy.counts(scope, away: false) ? home : 0) }
        /// Rule 3: the screens are to be dark (the windows up unless rule 4 lowers them for the lock screen).
        var wantsDark: Bool {
            scope != .off && screens > 0 && !quitting && !takenBack
                && (counting > 0 || waitingSince != nil || holdingSince != nil || askedAt != nil)
        }
        /// Rule 4: the black windows up now.
        var shouldBeUp: Bool { wantsDark && (underLockScreen || mac == .unlocked) }
        /// Something here waits on the clock: the glue ticks (`DarkenPolicy.tick`), and Sill.app holds App Nap off.
        var pending: Bool { waitingSince != nil || holdingSince != nil || askedAt != nil }
        /// The hint's wording now.
        var hint: Hint { keysLock && !keysPass ? .lock : .pass }

        // MARK: Events

        /// The registered sessions changed (a connect, a departure, a move): how many are away and at home now.
        mutating func sessions(away: Int, home: Int, at now: Double) -> [Action] {
            let darkBefore = wantsDark, countingBefore = counting
            self.away = max(0, away)
            self.home = max(0, home)
            guard !quitting else { return [] }
            var out: [Action] = []
            if counting > 0 {
                if waitingSince != nil || holdingSince != nil {
                    waitingSince = nil
                    holdingSince = nil
                    lockFollows = false
                    out.append(.line(Words.cameBack(grace)))
                }
            } else if countingBefore > 0, darkBefore {
                waitingSince = now
                lockFollows = lockAfterSession && sessions == 0
                out.append(.line(Words.lastLeft(grace)))
            } else if sessions > 0 {
                // A session that does not darken joined while the wait runs: the lock's wait ended with it.
                lockFollows = false
            }
            // Rule 8: taken back until no session at all is connected.
            if sessions == 0 { takenBack = false }
            return out + settle(at: now)
        }

        /// The switches changed (Settings › Devices, at once).
        mutating func switched(scope: HostConfig.Darken, keysLock: Bool, lockAfterSession: Bool, at now: Double) -> [Action] {
            let scopeChanged = scope != self.scope
            let darkening = scopeChanged || keysLock != self.keysLock
            let hintBefore = hint
            self.lockAfterSession = lockAfterSession
            if !lockAfterSession { lockFollows = false }
            guard darkening else { return [] }
            self.scope = scope
            self.keysLock = keysLock
            takenBack = false
            keysPass = false
            guard !quitting else { return [] }
            if scopeChanged {
                // The person chose it: a wait or a hold under way ends now (the sessions decide from here).
                waitingSince = nil
                holdingSince = nil
                lockFollows = false
            }
            var out: [Action] = []
            if up && !shouldBeUp { out.append(.line(scope == .off ? Words.switchedOff : Words.noneCounts)) }
            out += settle(at: now)
            if up, hint != hintBefore, !out.contains(.raise) { out += showHint(at: now) }
            return out
        }

        /// The screens to cover changed (rule 13): their number now.
        mutating func screens(_ count: Int, at now: Double) -> [Action] {
            let before = screens
            screens = max(0, count)
            guard !quitting, (before == 0) != (screens == 0) else { return [] }
            var out: [Action] = []
            if screens == 0, up { out.append(.line(Words.noScreen)) }
            return out + settle(at: now)
        }

        /// SessionLock's reading changed.
        mutating func reading(_ new: PrivacyPolicy.Mac, at now: Double) -> [Action] {
            let was = mac
            mac = new
            guard !quitting, new != was else { return [] }
            var out: [Action] = []
            if new == .screenLocked || new == .offConsole {
                // A lock shows: one asked at a key is confirmed, and keys may lock again.
                askedAt = nil
                keysPass = false
                if up, !underLockScreen { out.append(.line(Words.lockScreenShows)) }
            }
            if new == .unlocked, was == .screenLocked || was == .offConsole, wantsDark {
                if was == .screenLocked, let at = deviceInputAt, now - at <= remoteUnlockWindow {
                    out.append(.line(Words.deviceUnlocked(deviceName)))
                } else {
                    takenBack = true
                    waitingSince = nil
                    holdingSince = nil
                    lockFollows = false
                    out.append(.line(Words.takenBack))
                }
            }
            if new == .unlocked { deviceInputAt = nil; deviceName = nil }
            return out + settle(at: now)
        }

        /// A paired device's input was posted at the locked screen (LockPolicy took it): rule 8's witness.
        mutating func deviceInputAtLockedScreen(_ name: String, at now: Double) {
            guard mac == .screenLocked else { return }
            deviceInputAt = now
            deviceName = name
        }

        /// A person's input on this Mac (the observer: its kind, and whether Sill posted it).
        mutating func local(_ kind: Local, tagged: Bool, at now: Double) -> [Action] {
            guard !tagged, !quitting, up, mac == .unlocked else { return [] }
            if kind != .move, keysLock, !keysPass, lastAsk.map({ now - $0 >= lockConfirm }) ?? true {
                lastAsk = now
                askedAt = now
                return [.line(Words.locking), .lock] + showHint(at: now)
            }
            // At most one hint a second while the pointer moves.
            if let until = hintUntil, until - now > hintFor - 1 { return [] }
            return showHint(at: now)
        }

        /// The lock call's answer for a lock asked at a key. Unavailable: the hint says ⌃⌘Q. Made: the reading decides.
        mutating func called(_ call: PrivacyPolicy.Call, at now: Double) -> [Action] {
            guard case .unavailable(let why) = call, askedAt != nil, !quitting else { return [] }
            askedAt = nil
            keysPass = true
            var out: [Action] = [.line(Words.couldNotLock(why))]
            if up { out += shouldBeUp ? showHint(at: now) : [.line(Words.lit)] }
            return out + settle(at: now)
        }

        /// The glue's tick, while `pending`. `lockHolds`: the lock's wait or its confirmation is under way (PrivacyPolicy).
        mutating func tick(at now: Double, lockHolds: Bool) -> [Action] {
            guard !quitting else { return [] }
            var out: [Action] = []
            if let asked = askedAt {
                if now - asked >= lockConfirm {
                    askedAt = nil
                    keysPass = true
                    out.append(.line(Words.couldNotLock(Words.stillUnlocked)))
                    if up, shouldBeUp { out += showHint(at: now) }
                } else {
                    out.append(.look)
                }
            }
            if let since = waitingSince, now - since >= grace {
                waitingSince = nil
                if lockFollows, lockHolds { holdingSince = since }
                lockFollows = false
            }
            if let since = holdingSince, !lockHolds || now - since >= grace + lockConfirm + DarkenPolicy.holdSlack {
                holdingSince = nil
            }
            if up, !shouldBeUp { out.append(.line(Words.lit)) }
            return out + settle(at: now)
        }

        /// Sill is quitting (Sill.app's Quit, a logout, an update's restart, a signal): lift at once, nothing after.
        mutating func quit(at now: Double) -> [Action] {
            guard !quitting else { return [] }
            quitting = true
            waitingSince = nil
            holdingSince = nil
            askedAt = nil
            guard up else { return [] }
            up = false
            hintUntil = nil
            return [.lift, .line(Words.quitting)]
        }

        // MARK: Helpers

        /// The windows follow `shouldBeUp`: up with the dark's line and the hint, or down.
        private mutating func settle(at now: Double) -> [Action] {
            let want = shouldBeUp
            guard want != up else { return [] }
            up = want
            if want { return [.raise, .line(Words.dark(scope, screens: screens))] + showHint(at: now) }
            hintUntil = nil
            return [.lift]
        }

        private mutating func showHint(at now: Double) -> [Action] {
            hintUntil = now + hintFor
            return [.hint(hint, until: now + hintFor)]
        }
    }

    // MARK: Rule 12: a hung Sill

    /// The watchdog ends Sill only while dark, and only once the main thread has gone `hangLimit` without a beat.
    package static func watchdogFires(lastBeat: Double, now: Double, dark: Bool) -> Bool {
        dark && now - lastBeat >= hangLimit
    }

    /// Sill opens itself again after such an end unless it did less than `relaunchSpacing` ago.
    package static func reopens(lastReopen: Double?, now: Double) -> Bool {
        guard let lastReopen else { return true }
        return now - lastReopen >= relaunchSpacing || now < lastReopen
    }

    // MARK: The TEST ONLY hooks

    /// What a test host takes (DoorPolicy.isTestHost; TestHooks says elsewhere that each is ignored):
    /// SILL_TEST_PRIVACY_INPUT=<file> (the Mac's own input, in place of the observer: a test host reads `key`, `click`
    /// or `move`, with ` tagged` after it for one Sill posted, once from the file and removes it) and
    /// SILL_TEST_PRIVACY_LOG=1 (the dry curtain's lines and the connect's display wake stamped with the host's clock, so
    /// rule 5's order shows in the log). The wait and the displays are part 1's hooks (SILL_TEST_PRIVACY_GRACE,
    /// SILL_TEST_PRIVACY_DISPLAYS), which darkening shares.
    struct TestHooks: Equatable, Sendable {
        var inputFile: String?
        var log = false
        var lines: [String] = []
    }

    static func testHooks(testHost: Bool, environment env: [String: String]) -> TestHooks {
        var h = TestHooks()
        guard testHost else { return h }
        if let path = env["SILL_TEST_PRIVACY_INPUT"], !path.isEmpty {
            if path.hasPrefix("/") {
                h.inputFile = path
                h.lines.append("Test privacy: this Mac's own input is read from \(path) (SILL_TEST_PRIVACY_INPUT).")
            } else {
                h.lines.append("SILL_TEST_PRIVACY_INPUT=\(path) ignored: an absolute path.")
            }
        }
        if env["SILL_TEST_PRIVACY_LOG"] == "1" {
            h.log = true
            h.lines.append("Test privacy: the dark's lines and the display wake are stamped (SILL_TEST_PRIVACY_LOG).")
        }
        return h
    }

    /// A test host's input file's word: the input it stands for, and whether Sill posted it; nil for anything else.
    static func testInput(_ word: String) -> (Local, tagged: Bool)? {
        let parts = word.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = parts.first, parts.count <= 2 else { return nil }
        let tagged = parts.count == 2
        if tagged, parts[1] != "tagged" { return nil }
        switch first {
        case "key": return (.key, tagged)
        case "click": return (.click, tagged)
        case "move": return (.move, tagged)
        default: return nil
        }
    }

    // MARK: Every word

    package enum Words {
        // Sill.log
        /// The start line while the switch is on. `dry`: not Sill.app itself (`darkensForReal`), which only says what it
        /// would do.
        package static func startLine(_ scope: HostConfig.Darken, keysLock: Bool, dry: Bool) -> String {
            "Privacy: Darken this Mac’s screen is on: \(scope == .away ? "while a device away from home is connected" : "while a device is connected")"
                + (keysLock ? "; a key or click on this Mac locks it." : "; keys and clicks on this Mac reach its apps.")
                + (dry ? " A dry run here (only Sill.app itself darkens a Mac’s screen): it says what it would do." : "")
        }
        /// Sill.app itself with the switch on, until the probe G0 fills its seams (`heldBack`).
        package static let waitsForProbe = "Privacy: darkening this Mac’s screen waits for its probe (docs/privacy-mode-plan.md, G0); this build darkens nothing."
        package static func dark(_ scope: HostConfig.Darken, screens: Int) -> String {
            let who = scope == .away ? "a device away from home is connected" : "a device is connected"
            return "Privacy: this Mac’s screen is dark while \(who) (\(displays(screens)))."
        }
        package static func lastLeft(_ grace: Double) -> String {
            "Privacy: the last device left; this Mac’s screen stays dark for \(PrivacyPolicy.Words.number(grace)) s in case it comes back."
        }
        package static func cameBack(_ grace: Double) -> String {
            "Privacy: a device came back within \(PrivacyPolicy.Words.number(grace)) s; this Mac’s screen stays dark."
        }
        package static let lit = "Privacy: this Mac’s screen is lit again."
        package static let switchedOff = "Privacy: Darken this Mac’s screen is off; this Mac’s screen is lit again."
        package static let noneCounts = "Privacy: Darken this Mac’s screen changed, and no device it darkens for is connected; this Mac’s screen is lit again."
        package static let noScreen = "Privacy: this Mac has no screen to darken now; its screen is lit again."
        package static let quitting = "Privacy: Sill is quitting; this Mac’s screen is lit again."
        package static let locking = "Privacy: locking this Mac: someone pressed a key or clicked on it."
        package static func couldNotLock(_ why: String) -> String {
            "Privacy: couldn’t lock this Mac (\(why)); its screen now says to press Control-Command-Q."
        }
        package static let stillUnlocked = "it still read unlocked \(PrivacyPolicy.Words.number(PrivacyPolicy.lockConfirm)) s later"
        package static let lockScreenShows = "Privacy: this Mac is locked; the black lifts so its lock screen shows."
        package static let takenBack = "Privacy: unlocked on this Mac itself; its screen stays lit until every device has left."
        package static func deviceUnlocked(_ name: String?) -> String {
            let n = SafeText.label(name ?? "")
            return "Privacy: unlocked from \(n.isEmpty ? "a device" : n); this Mac’s screen stays dark."
        }
        package static let watchdog = "Privacy: Sill’s main thread hasn’t answered for \(PrivacyPolicy.Words.number(DarkenPolicy.hangLimit)) s while this Mac’s screen was dark; Sill quits so the screen isn’t left black, and opens again."
        package static let reopened = "Privacy: Sill opened again after it quit with this Mac’s screen dark (its main thread had stopped answering)."

        // The hint on each dark screen (two lines)
        package static let hintFirst = "This Mac is in use from another device."
        package static func hintSecond(_ hint: Hint) -> String {
            hint == .lock ? "Press any key to lock it." : "To use it here, press Control-Command-Q, then unlock it."
        }

        // The dry run (PrivacyScreen's DryCurtain) of everything but Sill.app itself: the CLI, the bare binary, a test host
        package static func dryRaise(_ screens: Int) -> String {
            "Privacy (dry run): would darken \(displays(screens)); nothing is drawn."
        }
        package static let dryLift = "Privacy (dry run): would light this Mac’s screen again; nothing was drawn."
        package static func dryHint(_ hint: Hint) -> String {
            "Privacy (dry run): would show “\(hintFirst) \(hintSecond(hint))”; nothing is drawn."
        }

        /// "1 display", "2 displays".
        package static func displays(_ n: Int) -> String { "\(n) display\(n == 1 ? "" : "s")" }
    }
}
