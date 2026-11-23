import ApplicationServices
import CoreGraphics
import Foundation
import StreamProtocol

// Privacy mode, part 2 (docs/privacy-mode-plan.md; DarkenPolicy): this Mac's screens dark while a device uses it, the
// main actor's side. The two places where the Mac itself is touched are seams: in Sill.app itself (DarkenPolicy
// .darkensForReal, the lock's rule) its black windows (WindowCurtain) and its watch on this Mac's own keys, clicks and
// pointer (MonitorInput), both in PrivacyCurtain.swift, made as the probe G0 of 2026-11-23 measured; on every other host
// (the CLI, the bare SillMenuBar binary, a test host) a dry run that only says what it would do.

/// The seam where this Mac's screens are actually darkened: DarkenPolicy's `raise`, `lift` and `hint`. Sill.app's is
/// WindowCurtain: one black window per screen at DarkenPolicy.windowLevel, ordered in by `raise` synchronously, before
/// the coordinator declares the connect's user activity (rule 5), and re-synced at every display change (`resync`: a new
/// screen's window in before an old one goes, rule 13).
@MainActor
protocol Curtain: AnyObject {
    /// Up on these screens (DarkenPolicy.screens' displays), now.
    func raise(_ screens: [UInt32])
    /// Down, now.
    func lift()
    /// The hint's two lines (DarkenPolicy.Words.hintFirst, `hintSecond(hint)`) on each dark screen for `seconds`, then
    /// faded.
    func hint(_ hint: DarkenPolicy.Hint, for seconds: Double)
    /// The displays changed while up: these are the screens to cover now.
    func resync(_ screens: [UInt32])
}

/// The seam where this Mac's own keys, clicks and pointer are observed, only while it is dark (DarkenPolicy rule 7):
/// each event's kind and whether Sill posted it (DarkenPolicy.ownEvent), never a key code or a character. Sill.app's is
/// MonitorInput (NSEvent's global monitor, with a local one for events sent to Sill itself).
@MainActor
protocol LocalInput: AnyObject {
    func start(_ handler: @escaping @MainActor (DarkenPolicy.Local, _ own: Bool) -> Void)
    func stop()
}

/// Darken this Mac's screen while a device uses it (DarkenPolicy; docs/privacy-mode-plan.md, part 2): the rule's state
/// and what carries it out. Its inputs, all on the main actor: the registered sessions, away and at home, at every
/// connect (before the coordinator's `deviceActive(.connect)`: rule 5) and departure (`sessions`); the switches at once
/// (`switched`, from `setTarget`); a change of SessionLock's reading (`readingChanged`); a paired device's input taken
/// at the locked screen (`deviceInputAtLockedScreen`); the displays (`displaysChanged`, Sill.app's DisplayChanges while
/// darkening is on); a quit (`quit`). While the rule waits on the clock it ticks every `DarkenPolicy.tick` on a
/// main-actor Task (the CLI's dispatchMain drains the main queue on a worker thread, so nothing here assumes isolation),
/// reading the lock's `pending` (HostStatus.privacyLock) for rule 6's hold. Its lock (rule 7) is ScreenLocker's (a dry
/// run anywhere but in Sill.app itself), confirmed by SessionLock's reading like the lock's own. While the black is up
/// the main actor beats once a second for PrivacyWatchdog (rule 12), which ends Sill.app if the beats stop for
/// `DarkenPolicy.hangLimit` (its dry run elsewhere only says so).
@MainActor
final class PrivacyScreen {
    private var state: DarkenPolicy.State
    /// Sill.app itself (DarkenPolicy.darkensForReal): its seams are its own, its locker locks, its watchdog quits.
    private let real: Bool
    /// The two seams. The dry run has no input watch unless a test host reads one from a file.
    private let curtain: Curtain
    private let input: LocalInput?
    private let locker: ScreenLocker
    private let watchdog: PrivacyWatchdog
    /// Sill.app's watch on display changes while darkening is on (nil on every other host, whose displays a test host
    /// fixes with SILL_TEST_PRIVACY_DISPLAYS).
    private let displays: DisplayChanges?
    private let status: HostStatus
    private let gate: LockGate
    private let hooks: DarkenPolicy.TestHooks
    /// TEST ONLY: a test host's screens to cover (SILL_TEST_PRIVACY_DISPLAYS), else this Mac's online displays.
    private let testScreens: Int?
    /// The lines `start` prints: a test host's hooks, the watchdog's reopening, then the switch when it is on.
    let startLines: [String]
    private var ticking: Task<Void, Never>?
    private var beating: Task<Void, Never>?
    private var watching = false
    /// TEST ONLY: SILL_TEST_PRIVACY_STALL has stopped the main thread once.
    private var stalled = false
    private let origin = ContinuousClock.now

    /// `real`: Sill.app itself (DarkenPolicy.darkensForReal, the lock's rule): its black windows, its watch on this Mac's
    /// own input, its locker and its watchdog act. Anything else gets the dry run: DryCurtain, a test host's FileInput,
    /// ScreenLocker's and PrivacyWatchdog's dry runs. `testHost`: whether the TEST ONLY hooks count.
    init(config: HostConfig, real: Bool, testHost: Bool, status: HostStatus, gate: LockGate,
         environment: [String: String] = ProcessInfo.processInfo.environment) {
        hooks = DarkenPolicy.testHooks(testHost: testHost, environment: environment)
        let lockHooks = PrivacyPolicy.testHooks(testHost: testHost, environment: environment)
        testScreens = lockHooks.displays
        self.real = real
        if real {
            curtain = WindowCurtain()
            input = MonitorInput()
        } else {
            curtain = DryCurtain(stamped: hooks.log)
            input = hooks.inputFile.map { FileInput(path: $0) }
        }
        locker = ScreenLocker(mode: real ? .real : .dry(noSymbol: lockHooks.noSymbol))
        watchdog = PrivacyWatchdog(mode: real ? .real(bundlePath: Bundle.main.bundleURL.path) : .dry)
        displays = real ? DisplayChanges() : nil
        var lines = hooks.lines
        if real, DarkenPolicy.followsWatchdog(record: PrivacyWatchdog.lastReopen(), now: Date().timeIntervalSince1970) {
            lines.append(DarkenPolicy.Words.reopened)
        }
        let scope = config.darkenScreen
        state = DarkenPolicy.State(scope: scope, keysLock: config.darkenKeysLock, lockAfterSession: config.lockAfterSession,
                                   grace: lockHooks.grace ?? DarkenPolicy.grace)
        if scope != .off { lines.append(DarkenPolicy.Words.startLine(scope, keysLock: config.darkenKeysLock, dry: !real)) }
        startLines = lines
        self.status = status
        self.gate = gate
        displays?.onChange = { [weak self] in self?.displaysChanged() }
        followDisplays()
        if scope != .off { run(state.screens(screenIDs().count, at: 0)) }
        run(state.reading(PrivacyPolicy.mac(gate.reading, established: gate.established), at: 0))
    }

    // MARK: Inputs

    /// The registered sessions now (cut off ones left out), away from home and at home. At a connect the coordinator
    /// calls this before it declares the connect's user activity, so a sleeping panel lights up black (rule 5).
    func sessions(away: Int, home: Int) {
        let now = now()
        if state.scope != .off { run(state.screens(screenIDs().count, at: now)) }
        run(state.sessions(away: away, home: home, at: now))
    }

    /// The switches, at once (`setTarget`).
    func switched(_ config: HostConfig) {
        let now = now()
        if config.darkenScreen != .off { run(state.screens(screenIDs().count, at: now)) }
        run(state.switched(scope: config.darkenScreen, keysLock: config.darkenKeysLock, lockAfterSession: config.lockAfterSession, at: now))
        followDisplays()
    }

    /// The displays changed (rule 13; Sill.app's DisplayChanges, from the display reconfiguration callback and
    /// AppKit's screen parameters notification): the black windows follow the screens now, a new one's in before an old
    /// one's out, and the rule its count. With darkening off nothing is read.
    func displaysChanged() {
        guard state.scope != .off else { return }
        let ids = screenIDs()
        if state.up { curtain.resync(ids) }
        run(state.screens(ids.count, at: now()))
    }

    /// SessionLock's reading changed.
    func readingChanged() {
        run(state.reading(PrivacyPolicy.mac(gate.reading, established: gate.established), at: now()))
    }

    /// A paired device's input was taken at the locked screen (rule 8's witness: the unlock that follows is its).
    func deviceInputAtLockedScreen(_ name: String) {
        state.deviceInputAtLockedScreen(name, at: now())
    }

    /// Sill is quitting: lit at once, nothing after.
    func quit() {
        run(state.quit(at: now()))
    }

    /// TEST ONLY (SILL_TEST_PRIVACY_LOG on a test host): a stamped line beside the dry curtain's, for rule 5's order.
    func testLog(_ what: String) {
        guard hooks.log else { return }
        print(String(format: "Test privacy: %.3f s %@", now(), what))
    }

    // MARK: The rule's actions

    private func run(_ actions: [DarkenPolicy.Action]) {
        for action in actions {
            switch action {
            case .raise:
                curtain.raise(screenIDs())
                watch(true)
                if real, state.keysLock, !AXIsProcessTrusted() { print(DarkenPolicy.Words.noAccessibility) }
                stallOnceForTest()
            case .lift:
                curtain.lift()
                watch(false)
            case .hint(let hint, let until):
                curtain.hint(hint, for: max(0, until - now()))
            case .lock:
                locker.lock { [weak self] call in
                    Task { @MainActor in
                        guard let self else { return }
                        self.run(self.state.called(call, at: self.now()))
                    }
                }
                SessionLock.shared.lookNow(cause: "Sill asked macOS to lock this Mac")
            case .look:
                SessionLock.shared.lookNow(cause: "Sill asked macOS to lock this Mac")
            case .line(let line):
                print(line)
            }
        }
        status.update { $0.privacyDark = state.up }
        followPending()
        followDark()
    }

    /// The Mac's own input is observed only while the black is up.
    private func watch(_ on: Bool) {
        guard on != watching, let input else { return }
        watching = on
        if on {
            input.start { [weak self] kind, own in
                guard let self else { return }
                self.run(self.state.local(kind, tagged: own, at: self.now()))
            }
        } else {
            input.stop()
        }
    }

    /// The tick runs while the rule waits on the clock, and stops with it.
    private func followPending() {
        if state.pending {
            guard ticking == nil else { return }
            ticking = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(Int(DarkenPolicy.tick * 1000)))
                    guard let self, !Task.isCancelled else { return }
                    self.run(self.state.tick(at: self.now(), lockHolds: self.status.snapshot.privacyLock.pending))
                }
            }
        } else {
            ticking?.cancel()
            ticking = nil
        }
    }

    /// Rule 12: while the black is up, the main actor beats once a second for the watchdog, which watches the beats
    /// from a queue of its own; down, the watchdog rests.
    private func followDark() {
        if state.up {
            guard beating == nil else { return }
            watchdog.arm()
            beating = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    self?.watchdog.beat()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
        } else {
            guard beating != nil else { return }
            beating?.cancel()
            beating = nil
            watchdog.disarm()
        }
    }

    /// Sill.app watches the displays while darkening is on, and only then.
    private func followDisplays() {
        displays?.watch(state.scope != .off)
    }

    /// TEST ONLY (SILL_TEST_PRIVACY_STALL on a test host): the main thread stops once, a second after the black first
    /// goes up, for the hook's seconds, so the watchdog's dry run speaks while the host goes on after it.
    private func stallOnceForTest() {
        guard let seconds = hooks.stall, !stalled else { return }
        stalled = true
        print("Test privacy: the main thread stops for \(PrivacyPolicy.Words.number(seconds)) s in 1 s (SILL_TEST_PRIVACY_STALL).")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            Thread.sleep(forTimeInterval: seconds)
            print("Test privacy: the main thread goes on after \(PrivacyPolicy.Words.number(seconds)) s (SILL_TEST_PRIVACY_STALL).")
        }
    }

    // MARK: Readings

    /// Seconds since this object was made, on ContinuousClock (counting while the Mac sleeps).
    private func now() -> Double {
        let d = ContinuousClock.now - origin
        return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }

    /// Rule 13: the screens to cover, or a test host's count (SILL_TEST_PRIVACY_DISPLAYS: that many made-up ones).
    private func screenIDs() -> [UInt32] {
        if let testScreens { return (0..<testScreens).map { UInt32(1000 + $0) } }
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        let displays = ids.prefix(Int(count)).map { id in
            let b = CGDisplayBounds(id)
            return DarkenPolicy.Display(id: id, vendor: CGDisplayVendorNumber(id), product: CGDisplayModelNumber(id),
                                        width: Double(b.width), height: Double(b.height))
        }
        return DarkenPolicy.screens(displays)
    }
}

// MARK: The dry run's seams (everything but Sill.app itself)

/// The dry run's curtain (the CLI, the bare SillMenuBar binary, a test host): says what it would draw and counts it
/// (`priv.raise`, `priv.lift`, `priv.hint`); never a window.
@MainActor
final class DryCurtain: Curtain {
    private let stamped: Bool
    private let origin = ContinuousClock.now

    init(stamped: Bool) { self.stamped = stamped }

    func raise(_ screens: [UInt32]) {
        Stats.shared.bump("priv.raise")
        say(DarkenPolicy.Words.dryRaise(screens.count))
    }

    func lift() {
        Stats.shared.bump("priv.lift")
        say(DarkenPolicy.Words.dryLift)
    }

    func hint(_ hint: DarkenPolicy.Hint, for seconds: Double) {
        Stats.shared.bump("priv.hint")
        say(DarkenPolicy.Words.dryHint(hint))
    }

    /// A test host's displays never change (SILL_TEST_PRIVACY_DISPLAYS).
    func resync(_ screens: [UInt32]) {}

    private func say(_ line: String) {
        guard stamped else { print(line); return }
        let d = ContinuousClock.now - origin
        print(String(format: "%@ (test: %.3f s)", line, Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18))
    }
}

/// A test host's view of this Mac's own input (SILL_TEST_PRIVACY_INPUT): while started, the file is read every quarter
/// second; its word (`key`, `click` or `move`, with ` tagged` for one Sill posted) is taken once and the file removed.
/// Never an event monitor, never this Mac's keyboard or mouse. Counts `priv.localDry`.
@MainActor
final class FileInput: LocalInput {
    private let path: String
    private var polling: Task<Void, Never>?

    init(path: String) { self.path = path }

    func start(_ handler: @escaping @MainActor (DarkenPolicy.Local, Bool) -> Void) {
        stop()
        let path = self.path
        polling = Task { @MainActor in
            while !Task.isCancelled {
                if let text = try? String(contentsOfFile: path, encoding: .utf8) {
                    try? FileManager.default.removeItem(atPath: path)
                    if let event = DarkenPolicy.testInput(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        Stats.shared.bump("priv.localDry")
                        print("Test privacy: this Mac’s own \(event.0)\(event.tagged ? " (tagged: Sill’s own)" : "") from \(path).")
                        handler(event.0, event.tagged)
                    } else {
                        print("Test privacy: \(path) said nothing the probe of this Mac’s own input takes (key, click or move, then tagged).")
                    }
                }
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    func stop() {
        polling?.cancel()
        polling = nil
    }
}
