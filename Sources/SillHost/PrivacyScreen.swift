import CoreGraphics
import Foundation
import StreamProtocol

// Privacy mode, part 2 (docs/privacy-mode-plan.md; DarkenPolicy): this Mac's screens dark while a device uses it, the
// main actor's side, built up to the two places where the Mac itself is touched. Each is a seam, filled on a test host
// by a dry run that only says what it would do, and in Sill.app by what the probe G0 decides
// (docs/steps/2026-11-18-privacy-darken.md): until then Sill.app has neither, and darkening cannot be turned on there.

/// The seam where this Mac's screens are actually darkened: DarkenPolicy's `raise`, `lift` and `hint`. Sill.app's, once
/// G0 has measured them, are its own black windows (#184's recipe: one borderless black window per screen, no shadow,
/// ignoring the mouse, on every Space, stationary, beside full-screen windows, out of the window cycle) at the level and
/// opacity G0 picks, ordered in by `raise` synchronously, before the coordinator declares the connect's user activity
/// (rule 5). While up it re-syncs itself at every display change (rule 13: a new screen's window in before an old one
/// goes, from the display reconfiguration callback as early as macOS tells).
@MainActor
protocol Curtain: AnyObject {
    /// Up on these screens (DarkenPolicy.screens' displays), now.
    func raise(_ screens: [UInt32])
    /// Down, now.
    func lift()
    /// The hint's two lines (DarkenPolicy.Words.hintFirst, `hintSecond(hint)`) on each dark screen until `until`
    /// (PrivacyScreen's clock), then faded.
    func hint(_ hint: DarkenPolicy.Hint, until: Double)
}

/// The seam where this Mac's own keys, clicks and pointer are observed, only while it is dark (DarkenPolicy rule 7):
/// each event's kind and whether Sill posted it (DarkenPolicy.eventTag, or what G0's step 4 finds tells them apart),
/// never a key code or a character. Sill.app's, once G0 has answered, is NSEvent's global monitor (with a local one
/// for events sent to Sill itself).
@MainActor
protocol LocalInput: AnyObject {
    func start(_ handler: @escaping @MainActor (DarkenPolicy.Local, _ tagged: Bool) -> Void)
    func stop()
}

/// Darken this Mac's screen while a device uses it (DarkenPolicy; docs/privacy-mode-plan.md, part 2): the rule's state
/// and what carries it out. Its inputs, all on the main actor: the registered sessions, away and at home, at every
/// connect (before the coordinator's `deviceActive(.connect)`: rule 5) and departure (`sessions`); the switches at once
/// (`switched`, from `setTarget`); a change of SessionLock's reading (`readingChanged`); a paired device's input taken
/// at the locked screen (`deviceInputAtLockedScreen`); a quit (`quit`). While the rule waits on the clock it ticks every
/// `DarkenPolicy.tick` on a main-actor Task (the CLI's dispatchMain drains the main queue on a worker thread, so nothing
/// here assumes isolation), reading the lock's `pending` (HostStatus.privacyLock) for rule 6's hold. Its lock (rule 7)
/// is ScreenLocker's (a dry run on a test host), confirmed by SessionLock's reading like the lock's own.
@MainActor
final class PrivacyScreen {
    private var state: DarkenPolicy.State
    /// The two seams: nil where nothing fills them (Sill.app until G0), and then nothing is darkened or watched.
    private let curtain: Curtain?
    private let input: LocalInput?
    private let locker: ScreenLocker
    private let status: HostStatus
    private let gate: LockGate
    private let hooks: DarkenPolicy.TestHooks
    /// TEST ONLY: a test host's screens to cover (SILL_TEST_PRIVACY_DISPLAYS), else this Mac's online displays.
    private let testScreens: Int?
    /// The lines `start` prints: a test host's hooks, then the switch when it is on.
    let startLines: [String]
    private var ticking: Task<Void, Never>?
    private var watching = false
    private let origin = ContinuousClock.now

    /// `dry`: a test host (synthetic), whose seams are dry runs; `testHost`: whether the TEST ONLY hooks count.
    init(config: HostConfig, dry: Bool, testHost: Bool, status: HostStatus, gate: LockGate,
         environment: [String: String] = ProcessInfo.processInfo.environment) {
        hooks = DarkenPolicy.testHooks(testHost: testHost, environment: environment)
        let lockHooks = PrivacyPolicy.testHooks(testHost: testHost, environment: environment)
        testScreens = lockHooks.displays
        curtain = dry ? DryCurtain(stamped: hooks.log) : nil
        input = dry ? hooks.inputFile.map { FileInput(path: $0) } : nil
        locker = ScreenLocker(mode: dry ? .dry(noSymbol: lockHooks.noSymbol) : .real)
        // Nothing fills the seams outside a test host yet: darkening stays off there, whatever the config says.
        var scope = config.darkenScreen
        var lines = hooks.lines
        if curtain == nil, scope != .off {
            lines.append(Self.waitsForProbe)
            scope = .off
        }
        state = DarkenPolicy.State(scope: scope, keysLock: config.darkenKeysLock, lockAfterSession: config.lockAfterSession,
                                   grace: lockHooks.grace ?? DarkenPolicy.grace)
        if scope != .off { lines.append(Self.startLine(scope, keysLock: config.darkenKeysLock)) }
        startLines = lines
        self.status = status
        self.gate = gate
        if scope != .off { run(state.screens(screenIDs().count, at: 0)) }
        run(state.reading(PrivacyLock.mac(gate), at: 0))
    }

    /// Outside a test host, until G0 fills the seams.
    static let waitsForProbe = "Privacy: darkening this Mac’s screen waits for its probe (docs/privacy-mode-plan.md, G0); this build darkens nothing."

    static func startLine(_ scope: HostConfig.Darken, keysLock: Bool) -> String {
        "Privacy: Darken this Mac’s screen is on: \(scope == .away ? "while a device away from home is connected" : "while a device is connected")"
            + (keysLock ? "; a key or click on this Mac locks it." : "; keys and clicks on this Mac reach its apps.")
    }

    // MARK: Inputs

    /// The registered sessions now (cut off ones left out), away from home and at home. At a connect the coordinator
    /// calls this before it declares the connect's user activity, so a sleeping panel lights up black (rule 5).
    func sessions(away: Int, home: Int) {
        let now = now()
        if state.scope != .off { run(state.screens(screenIDs().count, at: now)) }
        run(state.sessions(away: away, home: home, at: now))
    }

    /// The switches, at once (`setTarget`). Outside a test host darkening stays off until G0 fills the seams.
    func switched(_ config: HostConfig) {
        let scope = curtain == nil ? .off : config.darkenScreen
        let now = now()
        if scope != .off { run(state.screens(screenIDs().count, at: now)) }
        run(state.switched(scope: scope, keysLock: config.darkenKeysLock, lockAfterSession: config.lockAfterSession, at: now))
    }

    /// The displays changed (rule 13): the count the rule goes by. The filled curtain calls it from the display
    /// reconfiguration callback, beside its own re-sync; with darkening off nothing is read.
    func displaysChanged() {
        guard state.scope != .off else { return }
        run(state.screens(screenIDs().count, at: now()))
    }

    /// SessionLock's reading changed.
    func readingChanged() {
        run(state.reading(PrivacyLock.mac(gate), at: now()))
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
                curtain?.raise(screenIDs())
                watch(true)
            case .lift:
                curtain?.lift()
                watch(false)
            case .hint(let hint, let until):
                curtain?.hint(hint, until: until)
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
    }

    /// The Mac's own input is observed only while the black is up.
    private func watch(_ on: Bool) {
        guard on != watching, let input else { return }
        watching = on
        if on {
            input.start { [weak self] kind, tagged in
                guard let self else { return }
                self.run(self.state.local(kind, tagged: tagged, at: self.now()))
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

// MARK: A test host's seams: dry runs

/// A test host's curtain: says what it would draw and counts it (`priv.raise`, `priv.lift`, `priv.hint`); never a window.
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

    func hint(_ hint: DarkenPolicy.Hint, until: Double) {
        Stats.shared.bump("priv.hint")
        say(DarkenPolicy.Words.dryHint(hint))
    }

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
