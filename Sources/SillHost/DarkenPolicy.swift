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
/// - **Under the lock screen** (rule 4, `staysUnderLockScreen`, settled by the probe G0 on 2026-11-23): the black
///   windows sit at `windowLevel`, under macOS's lock screen, and stay up whatever the reading, so a lock shows the lock
///   screen above them and an unlock (by anyone) reveals black. G0 found such a level (`levelFits`): at the screen
///   saver's level the lock screen came in front (loginwindow at layers 2001 and 2004) and Noah locked and unlocked over
///   the black, while a notification, the volume indicator, Spotlight, Mission Control and the Force Quit window (layer
///   996) all stayed behind it. The fallback (the constant false: the windows down at a locked reading, up again at an
///   unlocked one) stays in the rule, checked, for a macOS that moves its lock screen.
/// - **Up before the panel lights** (rule 5): `sessions` returns `raise` at the connect of a session that counts, and the
///   coordinator calls it before it declares the connect's user activity (DisplayWake), in the same main-actor turn.
/// - **The session's end** (rule 6): when the last session that counts leaves, the windows stay up `wait` (Settings'
///   Stay dark after the last device leaves: 5 s by default, or 30 s, HostConfig.darkenWait; Noah, 2026-11-24), then
///   lift, unless a session that counts comes back meanwhile (one line each). If that departure also started the lock's
///   wait (no session at all left, Lock this Mac when the last device leaves on: `lockFollows`), the dark holds at its
///   end while the lock is under way (`lockHolds`: PrivacyPolicy's wait or confirmation pending), so the room never sees
///   the desktop between the dark and the lock screen; never longer than `lockGrace` (the lock's 30 s) + `lockConfirm` +
///   `holdSlack` after the departure (R0: the screen never stays dark). With no lock to follow (`lightsAtKey`), the
///   wait's hint says when the screen comes back, and a key or click on this Mac lights it at once and locks nothing:
///   the lock at a key is for while a device is connected. With a lock to follow, a key or click locks, as before.
///   Whether a device left on purpose cannot be told without a change to the wire (a device's own Disconnect and its
///   liveness check both close the connection cleanly, and the second reconnects), so every departure waits the same.
/// - **Someone at the Mac** (rule 7, `local`): while the windows are up and the Mac reads unlocked, a key or a click Sill
///   did not post (`ownEvent`: it carries neither `eventTag` nor Sill's own process as its source) asks `lock` with the
///   switch "A key or click on this Mac locks it" on (at most once per `lockConfirm`), and shows the hint; with it off,
///   or for a pointer movement or a scroll (`localKind`), only the hint. A lock that does not show in the reading within
///   `lockConfirm`, or that macOS cannot make, switches the hint to its ⌃⌘Q wording (macOS's own lock, which nothing
///   observing keys stops) and asks no more until a lock shows or a switch changes. While the Mac reads locked or off
///   console, nothing counts: the lock screen takes it.
/// - **Taken back** (rule 8): an unlock while dark (the reading unlocked after screen locked or off console) is the
///   Mac's own unless a paired device's input was posted at the locked screen within `remoteUnlockWindow` before it
///   (LockPolicy lets only a paired session type there); off console nothing is posted, so a return to the console is
///   always the Mac's own. The Mac's own: the windows lift and stay down until no session at all is connected, or a
///   switch of darkening changes. The device's: the screen stays dark.
/// - **A switch changed** (rule 9): off lifts at once (its wait cancelled); on with a session that counts raises at
///   once; a change of scope that leaves no session counting lifts at once (no wait: the person chose it). Any change of
///   the darkening's switches clears `takenBack`.
/// - **Quitting** (rule 11): lift at once, nothing asked from then on.
/// - **A hung Sill** (rule 12): the watchdog's decisions, `watchdogFires`, `reopens`, `followsWatchdog` and
///   `reopenCommand`, pure here (PrivacyWatchdog carries them out). G0's frozen probe kept its black window up for as
///   long as it was stopped, and a killed one lost it within 16 ms: only an end of the process lifts a hung Sill's.
/// - **Screens** (rule 13, `screens`): every screen (DesktopDisplays.role) of some size; never Sill's stage or Desktop
///   display, nor macOS's stand-in for a Mac with no screen.
/// - **The pointer** (rule 15, `shouldHidePointer`; Noah, 2026-11-24: "The cursor is still shown when darkened", the
///   plan's open decision 14 decided): hidden while the black windows are up and the Mac reads unlocked, with Hide the
///   pointer too on (HostConfig.darkenHidesPointer); shown for the lock screen and another user's session, and again
///   before the black comes down, whichever way it ends. macOS has one pointer and hides it on every screen at once, so
///   the rule goes by what the person at the Mac needs: no pointer while every screen they can see is black (a screen
///   just plugged in is about to be, and Sill's own displays are seen by nobody at the Mac), and the pointer whenever
///   they are to use the Mac (every screen lit, the lock screen, another user). A device's own pointer is drawn from
///   where the Mac's is and the shape macOS reports (kinds 26 and 14), neither of which the hide touches.
/// - **The pointer's hide made again** (rule 15, `pointerCheck`, run 7; Noah, 2026-11-26: the pointer showed on the
///   black after his iPhone stepped to a Virtual Desktop Sill made and back to the Mac's own display): while Sill has it
///   hidden, its hide is made again (`renewPointer`: a show and a hide in one turn) after the displays changed (once they
///   have been still `displaysSettle`), after a device stepped the Desktop to another stop and after Sill moved the
///   pointer to another display, whatever it reads: the window server keeps the hide per display too, and its shared
///   state (CGCursorIsVisible) can say hidden while one display shows it. At a look once a `beat` while dark, only when it
///   reads as showing (so the show cannot make a hidden pointer flash), at most `lookTries` looks in a row; then once
///   that it still shows. Each renewal counted by its cause, and its line said once per cause and read in each raise.
/// - **Only Sill.app itself darkens** (rule 14, `darkensForReal`: the lock's rule, PrivacyPolicy.locksForReal). The
///   CLI, the bare SillMenuBar binary and every test host decide the same and act on nothing: their glue says what it
///   would do (the "(dry run)" lines), draws nothing, watches no input, locks nothing and never quits for the watchdog.
/// - **Settings › Devices** (`scope(on:onlyAway:)`): Darken this Mac's screen, and under it Only while a device is away
///   from home (on by default, remembered while the first is off), A key or click on this Mac locks it (on), Hide the
///   pointer too (on) and Stay dark after the last device leaves (5 seconds, or 30).
///
/// Pure (Foundation, StreamProtocol's DesktopDisplays and SafeText, HostConfig's scope, PrivacyPolicy's constants,
/// readings and rule of who acts), checked with them as one module (Tests/checks/darken).
package enum DarkenPolicy {
    // MARK: The constants

    /// The lock's wait (rule 6): the dark held for a lock its departure started lasts at most this + `lockConfirm` +
    /// `holdSlack` after that departure. The dark's own wait is Settings' choice (HostConfig.darkenWait: 5 s, or 30 s, the
    /// same as this); a test host's SILL_TEST_PRIVACY_GRACE shortens both.
    package static let lockGrace: Double = PrivacyPolicy.grace
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
    /// Rule 7: what every event Sill posts carries (`CGEventSource.userData`, so `kCGEventSourceUserData`: InputInjector
    /// sets it on its source), never a person's hardware (whose events carry 0). G0's step 4: NSEvent's global monitor
    /// keeps it (a posted pointer move and Shift, 0x53494C4C50525631), and an untagged one carries 0.
    package static let eventTag: Int64 = 0x5349_4C4C_5052_5631
    /// The glue's tick while something here waits on the clock (`State.pending`).
    static let tick: Double = 0.5
    /// Rule 4: the black windows sit under macOS's lock screen (settled by G0: `windowLevel` fits under it).
    package static let staysUnderLockScreen = true
    /// The main actor's beat while the black is up: the watchdog's (rule 12) and the pointer's look (rule 15).
    package static let beat: Double = 1
    /// Rule 15, renewed: how long the displays stay still before the pointer's hide is made again after they changed (a
    /// Virtual Desktop's make is several changes over about 0.7 s: one renewal after the last of them).
    package static let displaysSettle: Double = 0.25
    /// Rule 15, renewed: the looks in a row that hide the pointer again when it reads as showing; the next says once that
    /// it still shows (macOS not hiding it), and the look rests until it reads hidden again or the pointer is hidden anew.
    package static let lookTries = 2

    // MARK: The black windows (the probe G0, 2026-11-23, on Noah's Mac14,9 with macOS 27.2.1)

    /// What G0's step 2 saw with the black windows at the screen saver's level (1000, #184's), every layer the window
    /// server listed. Behind the black, and so to stay behind it: the Force Quit window (loginwindow, 996), the volume
    /// indicator (101), a notification banner and Spotlight (23), Mission Control and the Dock (2 to 20); Noah saw
    /// none of them ("No", "No", "No", "Only black", "No").
    static let probeHidden = [996, 101, 23, 20, 19, 14, 2]
    /// In front of it, at its own level: another app's window (1×1 pt, transparent) listed in front of the black for the
    /// whole spell once that app ordered it in again. Two windows at one level stack by who ordered last, so the same
    /// level is no barrier.
    static let probeSameLevel = 1000
    /// In front of it: macOS's lock screen (loginwindow, layers 2001 and 2004). Noah locked with ⌃⌘Q, saw "regular lock
    /// screen", unlocked, and found the black still there until the spell ended.
    static let probeLockScreen = [2001, 2004]
    /// The highest window level macOS names under its lock screen (kCGAssistiveTechHighWindowLevel), which assistive
    /// windows (spoken text's captions, hover text) share.
    static let assistiveLevel = 1500

    /// The black windows' level (rule 4): one above the highest level macOS names under its lock screen, so no window of
    /// a named level (the screen saver's, an assistive one) ties with them, above everything G0 saw hidden, and 500
    /// under the lock screen, so a person at the Mac always sees it. G0's step 1 measured no cost of the level: covered
    /// windows drew on at 99 to 101 % under the black at 1000, 1500 and the shielding level alike.
    package static let windowLevel = 1501
    /// Opaque, as #184's: G0's step 1 found no difference (not opaque, S2, drew 100 to 101 % as the opaque ones), and
    /// step 5 found every screen pure black (Night Shift, True Tone, an HDR video, two screens).
    package static let windowOpaque = true

    /// Whether a level keeps what G0 saw hidden behind the black, ties with no named level under the lock screen (no
    /// window of another app at the same level can be ordered in front), and stays under the lock screen.
    static func levelFits(_ level: Int) -> Bool {
        probeHidden.allSatisfy { $0 < level } && level > probeSameLevel && level > assistiveLevel
            && probeLockScreen.allSatisfy { level < $0 }
    }

    // MARK: Someone at the Mac: which events (rule 7)

    /// The kind of an event of this Mac's own (NSEvent.EventType's and CGEventType's number), nil for one that is none
    /// of these: a key down (10); a mouse button down, left (1), right (3) or other (25); a pointer move (5), a drag (6,
    /// 7, 27) or a scroll (22), which only show the hint. A modifier alone (12), a key or button up and anything else
    /// count for nothing. Never a key code or a character.
    static func localKind(eventType: Int) -> Local? {
        switch eventType {
        case 10: return .key
        case 1, 3, 25: return .click
        case 5, 6, 7, 27, 22: return .move
        default: return nil
        }
    }

    /// The event types the glue's observer asks NSEvent for (each `localKind` takes).
    static let watchedEventTypes = [10, 1, 3, 25, 5, 6, 7, 27, 22]

    /// Rule 7: an event Sill posted itself, which never counts as a person's: it carries `eventTag` (InputInjector's
    /// source), or its source is this very process. G0's step 4: the posted events named the probe's own process as
    /// their source (and carried the tag when tagged), Noah's own pointer move process 0 and no tag.
    static func ownEvent(userData: Int64, sourcePID: Int64, ownPID: Int64) -> Bool {
        userData == eventTag || sourcePID == ownPID
    }

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

    // MARK: Settings › Devices

    /// The host's scope from Settings' two switches: Darken this Mac's screen, and under it Only while a device is away
    /// from home (HostSettings keeps it while the first is off, so turning darkening on again keeps the choice).
    package static func scope(on: Bool, onlyAway: Bool) -> HostConfig.Darken {
        guard on else { return .off }
        return onlyAway ? .away : .any
    }

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

    /// What the hint says: a key locks this Mac, or the way to use it here (⌃⌘Q); or, in the wait after the last device
    /// left with no lock to follow, that the screen comes back within these seconds and a key or click brings it back now.
    package enum Hint: Equatable, Sendable {
        case lock, pass
        case left(Int)
    }

    /// Rule 15, renewed (run 7): what may have let macOS show the pointer again while Sill has it hidden.
    package enum PointerCause: String, CaseIterable, Hashable, Sendable {
        /// The displays changed (one added, removed or given a new mode: Sill's own Virtual Desktop or stage display, a
        /// monitor, anything), once they have been still `displaysSettle` (Sill.app's DisplayChanges; the black laid
        /// again before).
        case displays
        /// A device stepped the Desktop to another stop (kind 47), and Sill moved the pointer there (never a test host).
        case step
        /// Sill moved the pointer to another display otherwise: the stage's warp home from its display.
        case warp
        /// The look, once a `beat` while dark: the pointer read as showing.
        case look

        /// When, in the log's words.
        package var when: String {
            switch self {
            case .displays: return "after the displays changed"
            case .step: return "after a device stepped to another display"
            case .warp: return "after Sill moved it to another display"
            case .look: return "on the black"
            }
        }

        /// Its statistics key (`Stats`): every renewal counted by its cause.
        package var statsKey: String { "priv.renew" + rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
    }

    /// A renewal's line said in this raise: its cause, and whether the pointer read as showing.
    struct Renewal: Hashable, Sendable {
        var cause: PointerCause
        var showing: Bool
    }

    enum Action: Equatable, Sendable {
        /// The black windows up on every screen to cover (`screens`), with the hint; at a connect, before anything else.
        case raise
        /// The black windows down.
        case lift
        /// Rule 15: this Mac's pointer hidden (true), only once the black is up; or shown again (false), before it comes
        /// down, at the lock screen and at another user's session.
        case pointer(hidden: Bool)
        /// Rule 15, renewed: the pointer Sill has hidden, hidden again now (a show and a hide in one turn: one hide still
        /// outstanding), for this cause.
        case renewPointer(PointerCause)
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
        /// The wait after the last session that darkens leaves (rule 6): Settings' choice (HostConfig.darkenWait, 5 or
        /// 30 s), or a test host's SILL_TEST_PRIVACY_GRACE.
        private(set) var wait: Double
        /// Hide the pointer too (HostConfig.darkenHidesPointer; rule 15).
        private(set) var hidesPointer: Bool
        /// The lock's wait (`DarkenPolicy.lockGrace`, or a test host's SILL_TEST_PRIVACY_GRACE): the hold's bound.
        let lockGrace: Double
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
        /// The pointer is hidden (the last `pointer` said).
        private(set) var pointerHidden = false
        /// Rule 15, renewed: the renewals' lines said since the black last came down (each cause once for each read).
        private(set) var renewalsSaid: Set<Renewal> = []
        /// Rule 15, renewed: the looks in a row that read the pointer as showing since it was last hidden or read hidden.
        private(set) var looksShowing = 0
        /// Rule 15, renewed: the line that it still shows after `lookTries` looks was said since the black last came down.
        private(set) var saidStillShows = false
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

        init(scope: HostConfig.Darken, keysLock: Bool, lockAfterSession: Bool,
             wait: Double = HostConfig.standard.darkenWait.seconds, hidesPointer: Bool = HostConfig.standard.darkenHidesPointer,
             lockGrace: Double = DarkenPolicy.lockGrace, underLockScreen: Bool = DarkenPolicy.staysUnderLockScreen) {
            self.scope = scope
            self.keysLock = keysLock
            self.lockAfterSession = lockAfterSession
            self.wait = wait
            self.hidesPointer = hidesPointer
            self.lockGrace = lockGrace
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
        /// Rule 15: the pointer hidden now: the black up on a Mac that reads unlocked (the lock screen and another user's
        /// session have theirs), with Hide the pointer too on.
        var shouldHidePointer: Bool { up && hidesPointer && mac == .unlocked }
        /// Rule 6: the wait after the last session that darkens left runs with no lock to follow it and no lock asked at
        /// a key being confirmed: a key or click lights the screens at once, and the hint says when they come back.
        var lightsAtKey: Bool { waitingSince != nil && !lockFollows && askedAt == nil }
        /// Something here waits on the clock: the glue ticks (`DarkenPolicy.tick`), and Sill.app holds App Nap off.
        var pending: Bool { waitingSince != nil || holdingSince != nil || askedAt != nil }
        /// The hint's wording now.
        var hint: Hint {
            if lightsAtKey { return .left(max(1, Int(wait.rounded(.up)))) }
            return keysLock && !keysPass ? .lock : .pass
        }

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
                    let left = lightsAtKey
                    waitingSince = nil
                    holdingSince = nil
                    lockFollows = false
                    out.append(.line(Words.cameBack))
                    // The wait's hint, still showing, says the device is back.
                    if up, left, let until = hintUntil, until > now { out.append(.hint(hint, until: until)) }
                }
            } else if countingBefore > 0, darkBefore {
                waitingSince = now
                lockFollows = lockAfterSession && sessions == 0
                out.append(.line(Words.lastLeft(wait, keyLights: lightsAtKey)))
                // With no lock to follow, the person at the Mac is told when the screen comes back, and that a key or
                // click brings it back now.
                if up, lightsAtKey { out += showHint(at: now) }
            } else if sessions > 0 {
                // A session that does not darken joined while the wait runs: the lock's wait ended with it.
                lockFollows = false
            }
            // Rule 8: taken back until no session at all is connected.
            if sessions == 0 { takenBack = false }
            return out + settle(at: now)
        }

        /// The switches changed (Settings › Devices, at once). `wait` and `hidesPointer`: Stay dark after the last device
        /// leaves (a wait under way ends by the new one) and Hide the pointer too, nil keeping them; neither is a switch of
        /// darkening (rule 9's).
        mutating func switched(scope: HostConfig.Darken, keysLock: Bool, lockAfterSession: Bool, wait: Double? = nil,
                               hidesPointer: Bool? = nil, at now: Double) -> [Action] {
            let scopeChanged = scope != self.scope
            let darkening = scopeChanged || keysLock != self.keysLock
            let hintBefore = hint
            self.lockAfterSession = lockAfterSession
            if !lockAfterSession { lockFollows = false }
            if let wait { self.wait = wait }
            if let hidesPointer { self.hidesPointer = hidesPointer }
            guard darkening else { return pointer() }
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

        /// Rule 15, renewed (run 7): `cause` may have let macOS show the pointer again. `showing`: whether it reads as
        /// showing now (CGCursorIsVisible: the window server's own state, the same for every app), nil with nothing to
        /// read it (the dry run). Only while Sill has it hidden (`pointerHidden`, which follows `shouldHidePointer` after
        /// every event: the black up on an unlocked Mac with Hide the pointer too on). After the displays changed, a step
        /// or Sill's warp, its hide is made again whatever it reads: the window server keeps the hide per display too, and
        /// its shared state can say hidden while one display shows it. At the look, only when it reads as showing, so the
        /// renewal's show cannot make a hidden pointer flash; at most `lookTries` looks in a row, then once that it still
        /// shows, the look resting until it reads hidden or the pointer is hidden anew. Each renewal's line once per cause
        /// and read until the black comes down (`renewalsSaid`), after the renewal itself.
        mutating func pointerCheck(_ cause: PointerCause, showing: Bool?) -> [Action] {
            guard pointerHidden else { return [] }
            let shows = showing == true
            if cause == .look {
                guard shows else { looksShowing = 0; return [] }
                looksShowing += 1
                if looksShowing > DarkenPolicy.lookTries {
                    guard !saidStillShows else { return [] }
                    saidStillShows = true
                    return [.line(Words.pointerStillShows)]
                }
            }
            var out: [Action] = [.renewPointer(cause)]
            if renewalsSaid.insert(Renewal(cause: cause, showing: shows)).inserted {
                out.append(.line(Words.pointerRenewed(cause, showing: shows)))
            }
            return out
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
            // Rule 6: the last device that darkens has left and no lock follows: a key or click lights the screens at
            // once, and locks nothing (keys locking or passing alike).
            if kind != .move, lightsAtKey {
                waitingSince = nil
                return [.line(Words.litByKey)] + settle(at: now)
            }
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
            if let since = waitingSince, now - since >= wait {
                waitingSince = nil
                if lockFollows, lockHolds {
                    holdingSince = since
                    out.append(.line(Words.holding))
                }
                lockFollows = false
            }
            if let since = holdingSince, !lockHolds || now - since >= lockGrace + lockConfirm + DarkenPolicy.holdSlack {
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
            return pointer() + [.lift, .line(Words.quitting)]
        }

        // MARK: Helpers

        /// The windows follow `shouldBeUp`: up with the dark's line and the hint, then the pointer hidden; or the pointer
        /// shown, then down. Up or down as they were, the pointer follows the reading and its switch.
        private mutating func settle(at now: Double) -> [Action] {
            let want = shouldBeUp
            guard want != up else { return pointer() }
            up = want
            if want { return [.raise, .line(Words.dark(scope, screens: screens))] + showHint(at: now) + pointer() }
            hintUntil = nil
            // Rule 15, renewed: the next raise says each renewal's line again.
            renewalsSaid = []
            saidStillShows = false
            return pointer() + [.lift]
        }

        /// Rule 15: the pointer follows `shouldHidePointer`. Hidden anew, the look starts counting again.
        private mutating func pointer() -> [Action] {
            let want = shouldHidePointer
            guard want != pointerHidden else { return [] }
            if want { looksShowing = 0 }
            pointerHidden = want
            return [.pointer(hidden: want)]
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

    /// A launch that follows the watchdog's end (its record, written just before, at most `reopenedWithin` old): it
    /// says so once (`Words.reopened`).
    static func followsWatchdog(record: Double?, now: Double) -> Bool {
        guard let record else { return false }
        return now >= record && now - record <= reopenedWithin
    }

    /// How long after the watchdog's end a launch still counts as its reopening (`open` and Sill's own wait for the
    /// Sill before it to be gone, AppUpdater.waitForOtherSill, take a few seconds).
    static let reopenedWithin: Double = 60

    /// How the watchdog opens Sill again: a new instance (`-n`, the stuck one is ending), in the background (`-g`), from
    /// Sill.app's own bundle, never the bare binary; nil for anything that is not an app bundle.
    static func reopenCommand(bundlePath: String) -> [String]? {
        guard bundlePath.hasSuffix(".app") else { return nil }
        return ["/usr/bin/open", "-n", "-g", bundlePath]
    }

    // MARK: The TEST ONLY hooks

    /// What a test host takes (DoorPolicy.isTestHost; TestHooks says elsewhere that each is ignored):
    /// SILL_TEST_PRIVACY_INPUT=<file> (the Mac's own input, in place of the observer: a test host reads `key`, `click`
    /// or `move`, with ` tagged` after it for one Sill posted, once from the file and removes it, only while dark; and
    /// for rule 15's renewal (run 7) `displays N`, its screens to cover now N as a display change tells Sill.app, and
    /// `pointer showing` or `pointer hidden`, what its dry run reads of the pointer from then on: `testWord`),
    /// SILL_TEST_PRIVACY_LOG=1 (the dry curtain's lines and the connect's display wake stamped with the host's clock, so
    /// rule 5's order shows in the log) and SILL_TEST_PRIVACY_STALL=<seconds> (1 to 30: the main thread stops once for
    /// that long a second after the black first goes up, so the watchdog's dry run says what it would do). The wait and
    /// the displays are part 1's hooks (SILL_TEST_PRIVACY_GRACE, SILL_TEST_PRIVACY_DISPLAYS), which darkening shares.
    struct TestHooks: Equatable, Sendable {
        var inputFile: String?
        var log = false
        var stall: Double?
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
        if let raw = env["SILL_TEST_PRIVACY_STALL"], !raw.isEmpty {
            if let s = Double(raw), s >= 1, s <= 30 {
                h.stall = s
                h.lines.append("Test privacy: the main thread stops once for \(PrivacyPolicy.Words.number(s)) s, a second after the black first goes up (SILL_TEST_PRIVACY_STALL).")
            } else {
                h.lines.append("SILL_TEST_PRIVACY_STALL=\(raw) ignored: seconds from 1 to 30.")
            }
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

    /// A test host's input file's word, all it takes (SILL_TEST_PRIVACY_INPUT): this Mac's own input (`testInput`), or
    /// for rule 15's renewal (run 7) its screens to cover now (`displays N`, 0 to 16, as a display change tells
    /// Sill.app) or what its dry run reads of the pointer from then on (`pointer showing`, `pointer hidden`).
    enum TestWord: Equatable, Sendable {
        case input(Local, tagged: Bool)
        case displays(Int)
        case pointer(showing: Bool)
    }

    static func testWord(_ word: String) -> TestWord? {
        if let input = testInput(word) { return .input(input.0, tagged: input.tagged) }
        let parts = word.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count == 2 else { return nil }
        switch (parts[0], parts[1]) {
        case ("displays", let n):
            guard let count = Int(n), (0...16).contains(count) else { return nil }
            return .displays(count)
        case ("pointer", "showing"): return .pointer(showing: true)
        case ("pointer", "hidden"): return .pointer(showing: false)
        default: return nil
        }
    }

    // MARK: Every word

    package enum Words {
        // Settings › Devices (the section before Lock this Mac when the last device leaves)
        package static let toggle = "Darken this Mac’s screen"
        /// The rows under it, shown while it is on.
        package static let awayToggle = "Only while a device is away from home"
        package static let keysToggle = "A key or click on this Mac locks it"
        package static let pointerToggle = "Hide the pointer too"
        package static let waitPicker = "Stay dark after the last device leaves"
        /// The picker's choices: "5 seconds", "30 seconds".
        package static func waitChoice(_ wait: HostConfig.DarkenWait) -> String { PrivacyPolicy.Words.seconds(wait.seconds) }
        package static let footnoteOff = "For a Mac you use from afar: its displays stay black while you use it, so people near it see nothing."
        /// `lock`: Lock this Mac when the last device leaves is on (the black then holds for its lock).
        package static func footnoteOn(onlyAway: Bool, keysLock: Bool, wait: Double = HostConfig.standard.darkenWait.seconds,
                                       lock: Bool = false) -> String {
            (onlyAway
                ? "This Mac’s displays turn black while an iPhone or iPad uses it from away from home (through a VPN or over the internet), so people near it see nothing."
                : "This Mac’s displays turn black while an iPhone or iPad is connected, so people near it see nothing.")
                + " They come back \(PrivacyPolicy.Words.seconds(wait)) after the last one leaves, "
                + (lock ? "or, when this Mac locks then, once its lock screen shows." : "or at once with a key or click on this Mac.")
                + (keysLock
                    ? " While a device is connected, a key or click on this Mac locks it; unlock it here with your password or Touch ID and its displays stay lit until every device has left."
                    : " While a device is connected, keys and clicks on this Mac still reach its apps, unseen. To use it here, press Control-Command-Q, then unlock it.")
        }
        /// Under the switches while keys lock and Sill lacks Accessibility (a click is still noticed without it).
        package static let accessibilityWarning = "Sill needs Accessibility to notice a key pressed on this Mac; a click still locks it. Allow it in Settings › Permissions."

        // Sill.log
        /// The start line while the switch is on. `dry`: not Sill.app itself (`darkensForReal`), which only says what it
        /// would do.
        package static func startLine(_ scope: HostConfig.Darken, keysLock: Bool, wait: Double = HostConfig.standard.darkenWait.seconds,
                                      hidesPointer: Bool = HostConfig.standard.darkenHidesPointer, dry: Bool) -> String {
            "Privacy: Darken this Mac’s screen is on: \(scope == .away ? "while a device away from home is connected" : "while a device is connected")"
                + " and for \(PrivacyPolicy.Words.number(wait)) s after the last one leaves"
                + (keysLock ? "; a key or click on this Mac locks it" : "; keys and clicks on this Mac reach its apps")
                + (hidesPointer ? "; the pointer is hidden on the black." : "; the pointer stays visible on the black.")
                + (dry ? " A dry run here (only Sill.app itself darkens a Mac’s screen): it says what it would do." : "")
        }
        /// Sill.app itself, as its screen darkens with keys locking, without Accessibility (AXIsProcessTrusted false).
        package static let noAccessibility = "Privacy: Sill can’t notice a key pressed on this Mac without Accessibility; a click still locks it."
        package static func dark(_ scope: HostConfig.Darken, screens: Int) -> String {
            let who = scope == .away ? "a device away from home is connected" : "a device is connected"
            return "Privacy: this Mac’s screen is dark while \(who) (\(displays(screens)))."
        }
        /// `keyLights`: no lock follows the departure, so a key or click lights the screen at once (`lightsAtKey`).
        package static func lastLeft(_ wait: Double, keyLights: Bool) -> String {
            "Privacy: the last device left; this Mac’s screen stays dark for \(PrivacyPolicy.Words.number(wait)) s in case it comes back"
                + (keyLights ? ", or until a key or click on it." : ", and then while a lock is under way.")
        }
        package static let cameBack = "Privacy: a device came back; this Mac’s screen stays dark."
        /// The wait is over while the lock its departure started is under way: the dark holds for it.
        package static let holding = "Privacy: this Mac’s screen stays dark until the lock under way shows."
        /// A key or click in the wait with no lock to follow.
        package static let litByKey = "Privacy: someone pressed a key or clicked on this Mac after the last device left; its screen is lit again, and nothing locks."
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
        /// The watchdog's end within `relaunchSpacing` of the last one that reopened Sill (no loop), or outside Sill.app.
        package static let watchdogNoReopen = "Privacy: Sill’s main thread hasn’t answered for \(PrivacyPolicy.Words.number(DarkenPolicy.hangLimit)) s while this Mac’s screen was dark; Sill quits so the screen isn’t left black, and doesn’t open again (it did less than 10 minutes ago)."
        package static let reopened = "Privacy: Sill opened again after it quit with this Mac’s screen dark (its main thread had stopped answering)."

        // The hint on each dark screen (two lines). A click as well as a key: a secure text field (a password) and
        // Terminal's Secure Keyboard Entry withhold keys from every observer, never a click.
        package static func hintFirst(_ hint: Hint) -> String {
            switch hint {
            case .lock, .pass: return "This Mac is in use from another device."
            case .left(let s): return "This Mac’s screen comes back within \(PrivacyPolicy.Words.seconds(Double(s)))."
            }
        }
        package static func hintSecond(_ hint: Hint) -> String {
            switch hint {
            case .lock: return "Press any key or click to lock it."
            case .pass: return "To use it here, press Control-Command-Q, then unlock it."
            case .left: return "Press any key or click to bring it back now."
            }
        }

        // Rule 15: the pointer, as Sill.app hides and shows it (PointerHider), once each time.
        package static let pointerHidden = "Privacy: this Mac’s pointer is hidden while its screen is dark."
        package static let pointerShown = "Privacy: this Mac’s pointer shows again."
        /// Once per run: the private calls are missing (PointerCalls), so the pointer stays visible; darkening goes on.
        package static let pointerUnavailable = "Privacy: this Mac’s pointer stays visible on the black: this macOS has no CGSSetConnectionProperty for Sill to hide it with."
        /// Once per run: macOS refused the property or the hide.
        package static func pointerRefused(_ code: Int) -> String {
            "Privacy: this Mac’s pointer stays visible on the black: macOS didn’t let Sill hide it (error \(code))."
        }
        package static func pointerShowFailed(_ code: Int) -> String {
            "Privacy: couldn’t show this Mac’s pointer again (error \(code)); it comes back when Sill quits."
        }
        /// Rule 15, renewed (run 7): the pointer's hide made again, once per cause and read in each raise. `showing`: it
        /// read as showing just before (CGCursorIsVisible); otherwise it read as hidden, or nothing reads it.
        package static func pointerRenewed(_ cause: PointerCause, showing: Bool) -> String {
            showing ? "Privacy: this Mac’s pointer was showing again \(cause.when); hidden again."
                    : "Privacy: this Mac’s pointer hidden again \(cause.when), to be sure."
        }
        /// The look found it showing after `lookTries` renewals in a row: once in a raise.
        package static let pointerStillShows = "Privacy: this Mac’s pointer still showed after Sill hid it again twice; it may stay visible on the black."
        /// Once per run, at Sill.app's first hide: this macOS has no CGCursorIsVisible, so nothing looks at the pointer.
        package static let pointerNoLook = "Privacy: this macOS has no CGCursorIsVisible; Sill hides the pointer again only after a display change or a step."

        // The dry run (PrivacyScreen's DryCurtain) of everything but Sill.app itself: the CLI, the bare binary, a test host
        package static func dryRaise(_ screens: Int) -> String {
            "Privacy (dry run): would darken \(displays(screens)); nothing is drawn."
        }
        package static let dryLift = "Privacy (dry run): would light this Mac’s screen again; nothing was drawn."
        package static func dryHint(_ hint: Hint) -> String {
            "Privacy (dry run): would show “\(hintFirst(hint)) \(hintSecond(hint))”; nothing is drawn."
        }
        /// `found`: the private calls PointerHider would make are found by name here (looked up, never called); `reads`:
        /// CGCursorIsVisible, which the look reads, too.
        package static func dryPointerHide(found: Bool, reads: Bool) -> String {
            guard found else { return "Privacy (dry run): would leave this Mac’s pointer visible: this macOS has no CGSSetConnectionProperty." }
            return reads ? "Privacy (dry run): would hide this Mac’s pointer (CGSMainConnectionID and CGSSetConnectionProperty found, and CGCursorIsVisible to look at it); it stays visible."
                         : "Privacy (dry run): would hide this Mac’s pointer (CGSMainConnectionID and CGSSetConnectionProperty found; no CGCursorIsVisible to look at it); it stays visible."
        }
        package static let dryPointerShow = "Privacy (dry run): would show this Mac’s pointer again; it was never hidden."
        /// Rule 15, renewed: each renewal of the dry run.
        package static func dryPointerRenew(_ cause: PointerCause) -> String {
            "Privacy (dry run): would hide this Mac’s pointer again \(cause.when) (a show and a hide at once); it stays visible."
        }
        /// The watchdog's dry run (PrivacyWatchdog on everything but Sill.app itself): it says, and the host goes on.
        package static let dryWatchdog = "Privacy (dry run): Sill’s main thread hasn’t answered for \(PrivacyPolicy.Words.number(DarkenPolicy.hangLimit)) s while this Mac’s screen was dark; would quit Sill and open it again; nothing quits."

        /// "1 display", "2 displays".
        package static func displays(_ n: Int) -> String { "\(n) display\(n == 1 ? "" : "s")" }
    }
}
