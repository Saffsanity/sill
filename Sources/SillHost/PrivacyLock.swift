import CoreGraphics
import Foundation
import StreamProtocol

/// Lock this Mac when the last device leaves (PrivacyPolicy; docs/privacy-mode-plan.md, part 1): the main actor's
/// side. It owns the rule's state and carries out what it says: the lock and the display sleep through ScreenLocker
/// (a dry run on a test host), SessionLock's looks while a lock is confirmed, the log's lines, and the status
/// Settings › Devices and the App Nap hold read.
///
/// Its inputs, all on the main actor: the server's count of registered sessions (`sessions`, from the coordinator's
/// `onClientCountChanged`), the switch (`switched`, from `setTarget` at once, never a restart), a change of
/// SessionLock's reading (`readingChanged`, from `lockChanged`) and Sill quitting (`quit`). While a wait or a
/// confirmation runs it ticks every `PrivacyPolicy.tick` on a main-actor Task (the CLI's dispatchMain drains the main
/// queue on a worker thread, so nothing here assumes isolation), reading the gate (`SessionLock.shared.gate`, which
/// any thread may read) and, at a wait's end, this Mac's displays (`PrivacyPolicy.typesAt`, or a test host's
/// SILL_TEST_PRIVACY_DISPLAYS). The clock is ContinuousClock's, which keeps counting while the Mac sleeps: a wait
/// that spans a sleep ends at the first tick after the wake.
@MainActor
final class PrivacyLock {
    private var state: PrivacyPolicy.State
    private let locker: ScreenLocker
    private let status: HostStatus
    private let gate: LockGate
    /// TEST ONLY: a test host's displays to type a password at (SILL_TEST_PRIVACY_DISPLAYS), else this Mac's.
    private let testDisplays: Int?
    /// The lines `start` prints: a test host's hooks, then the switch when it is on.
    let startLines: [String]
    private var ticking: Task<Void, Never>?
    private let origin = ContinuousClock.now

    /// `dry`: a test host's locker (synthetic: it never locks); `testHost`: whether the TEST ONLY hooks count.
    init(on: Bool, dry: Bool, testHost: Bool, status: HostStatus, gate: LockGate,
         environment: [String: String] = ProcessInfo.processInfo.environment) {
        let hooks = PrivacyPolicy.testHooks(testHost: testHost, environment: environment)
        state = PrivacyPolicy.State(on: on, grace: hooks.grace ?? PrivacyPolicy.grace)
        locker = ScreenLocker(mode: dry ? .dry(noSymbol: hooks.noSymbol) : .real)
        self.status = status
        self.gate = gate
        testDisplays = hooks.displays
        startLines = hooks.lines + (on ? [PrivacyPolicy.Words.startLine(hooks.grace ?? PrivacyPolicy.grace)] : [])
        publish(display: on ? hasDisplay() : nil)
    }

    // MARK: Inputs

    /// The server's count of registered sessions changed.
    func sessions(_ count: Int) {
        run(state.sessions(count, at: now()))
        if count > 0, state.on { publish(display: hasDisplay()) }
    }

    /// Lock this Mac when the last device leaves, turned on or off (at once).
    func switched(_ on: Bool) {
        guard on != state.on else { return }
        run(state.switched(on, at: now()))
        publish(display: on ? hasDisplay() : nil)
    }

    /// SessionLock's reading changed: a lock under confirmation is decided at once.
    func readingChanged() {
        guard state.pending else { return }
        tick()
    }

    /// Sill is quitting: nothing locks from now on (a wait under way says so).
    func quit() {
        run(state.quit())
    }

    /// Settings › Devices opened: whether this Mac has a display to type its password at, again (a monitor plugged
    /// in or out since), for its warning.
    func lookAtDisplays() {
        guard state.on else { return }
        publish(display: hasDisplay())
    }

    // MARK: The rule's actions

    private func run(_ actions: [PrivacyPolicy.Action]) {
        for action in actions {
            switch action {
            case .line(let line):
                print(line)
            case .look:
                SessionLock.shared.lookNow(cause: "Sill asked macOS to lock this Mac")
            case .sleepDisplays:
                locker.sleepDisplays()
            case .lock:
                locker.lock { [weak self] call in
                    Task { @MainActor in
                        guard let self else { return }
                        self.run(self.state.called(call, at: self.now()))
                        self.publish(display: nil)
                    }
                }
                // SessionLock reads afresh, so a lock that shows at once is confirmed at the next tick.
                SessionLock.shared.lookNow(cause: "Sill asked macOS to lock this Mac")
            }
        }
        publish(display: nil)
        followPending()
    }

    /// The tick runs while a wait or a confirmation does, and stops with them.
    private func followPending() {
        if state.pending {
            guard ticking == nil else { return }
            ticking = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(Int(PrivacyPolicy.tick * 1000)))
                    guard let self, !Task.isCancelled else { return }
                    self.tick()
                }
            }
        } else {
            ticking?.cancel()
            ticking = nil
        }
    }

    private func tick() {
        let mac = Self.mac(gate)
        run(state.tick(at: now(), mac: mac, display: hasDisplay()))
    }

    // MARK: Readings

    /// Seconds since this object was made, on ContinuousClock (counting while the Mac sleeps).
    private func now() -> Double {
        let d = ContinuousClock.now - origin
        return Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }

    /// The gate's reading as the rule reads it: not established is unknown.
    static func mac(_ gate: LockGate) -> PrivacyPolicy.Mac {
        guard gate.established else { return .unknown }
        switch gate.reading {
        case .unlocked: return .unlocked
        case .screenLocked: return .screenLocked
        case .offConsole: return .offConsole
        }
    }

    /// Rule 10: an online display whose role is a screen (DesktopDisplays.role), or a test host's count.
    private func hasDisplay() -> Bool {
        if let testDisplays { return testDisplays > 0 }
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return false }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return false }
        let roles = ids.prefix(Int(count)).map {
            DesktopDisplays.role(vendor: CGDisplayVendorNumber($0), product: CGDisplayModelNumber($0), madeByStage: false)
        }
        return PrivacyPolicy.typesAt(roles)
    }

    /// The status Settings › Devices and Sill.app's App Nap hold read. `display`: a fresh look at the displays,
    /// nil to keep the last one.
    private func publish(display: Bool?) {
        let s = state
        status.update {
            var p = $0.privacyLock
            p.on = s.on
            p.pending = s.pending
            p.failure = s.failure
            if let display { p.noDisplay = !display }
            if !s.on { p.noDisplay = false }
            $0.privacyLock = p
        }
    }
}
