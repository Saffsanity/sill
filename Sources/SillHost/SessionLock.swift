import Foundation
import AppKit
import CoreGraphics
import SystemConfiguration
import notify
import os

/// Whether this Mac's console is this user's and unlocked (LockPolicy, docs/locked-mac-plan.md): what every
/// device may see and do, the ask rule's step 1 (docs/home-pairing-plan.md §4.3: a locked Mac pairs nothing
/// by itself and opens no window), and --print-cable's last line.
///
/// The witnesses, read on this type's own queue (`sill.lock`), never on the main actor:
/// - the console's user, State:/Users/ConsoleUser in the dynamic store (SCDynamicStoreCopyConsoleUser):
///   watched, so a change calls back on the queue, and read at each look;
/// - the screen's lock state, notify(3)'s com.apple.sessionagent.screenIsLocked: registered with
///   notify_register_dispatch, so a change calls back on the queue, and read at each look;
/// - the session dictionary (CGSessionCopyCurrentDictionary), a WindowServer round trip read on a queue of
///   its own with a bound (LockPolicy.sessionBound), once at start whatever the others say (the first
///   reading needs every witness), then only to confirm an unlock the others say
///   (LockPolicy.readsSession): one that does not answer in time counts as locked until it does;
/// - in Sill.app, loginwindow's notifications and NSWorkspace's session notifications
///   (`watchNotifications`, registered `.deliverImmediately`, so none waits while Sill is not active),
///   whose handler (`note`) sets the reading itself, before any other work and with no WindowServer call.
/// The CLI has the first three. LockPolicy.Reader makes the reading of them, and the moment it changes,
/// from whichever thread looked, `gate` has it (the server drops what it withholds from then on) and its
/// line is printed; the coordinator hears of it through `onChange`.
///
/// Looks: at start, at each witness's change, once a second while a device is connected (`devices`), and
/// when an unlock's settle ends.
///
/// TEST ONLY, on a test host only (DoorPolicy.isTestHost; TestHooks says elsewhere that each is ignored):
/// SILL_TEST_LOCKED=1 (this session's screen locked for the run), SILL_TEST_LOCKED_FILE=<path> (read at
/// each look: 1 screen locked, 2 off console, anything else nothing), SILL_TEST_LOCK_NOTIFY=<name> (the
/// screen's lock state from a notify name of the test's own, under me.saffer.sill.test.),
/// SILL_TEST_LOCK_NOTE='<s> <name>[; …]' (notifications delivered to `note` on cue, nothing posted) and
/// SILL_TEST_LOCK_LOG=1 (each look's witnesses and reading).
package final class SessionLock: @unchecked Sendable {
    package static let shared = SessionLock()

    /// The reading the server, the doors and the coordinator go by: off console until the first look.
    let gate = LockGate(.offConsole, established: false)
    /// The coordinator's: the gate changed. Called on whatever thread changed it, holding no lock. Set
    /// before `start`.
    package var onChange: (@Sendable () -> Void)?

    private struct Inner {
        var reader = LockPolicy.Reader()
        /// When the session read in flight started, nil for none: one at a time.
        var sessionReadStarted: Double?
        var devices = 0
        var started = false
    }
    private let state = OSAllocatedUnfairLock(initialState: Inner())
    private let queue = DispatchQueue(label: "sill.lock", qos: .userInitiated)
    private let sessionQueue = DispatchQueue(label: "sill.lock.session", qos: .userInitiated)

    // On `queue`.
    private var store: SCDynamicStore?
    private var notifyStatus: UInt32 = 1          // not NOTIFY_STATUS_OK until registered
    private var notifyToken: Int32 = 0
    private var pollTimer: DispatchSourceTimer?
    private var settleTimer: DispatchSourceTimer?
    private var settleAt: Double?
    private var hooks = Hooks()
    /// Sill.app's observer of the notifications (main thread).
    private var observer: NoteObserver?

    /// TEST ONLY hooks, read once at `start` on a test host.
    private struct Hooks {
        var locked = false
        var file: String?
        var notifyName: String?
        var notes: [(at: Double, name: String)] = []
        var log = false
    }

    private init() {}

    private static func clock() -> Double { ProcessInfo.processInfo.systemUptime }

    // MARK: Starting

    /// Starts the witnesses and the first look, once. `testHost`: whether the TEST ONLY hooks count.
    package func start(testHost: Bool) {
        let first = state.withLockUnchecked { s -> Bool in
            defer { s.started = true }
            return !s.started
        }
        guard first else { return }
        let hooks = Self.hooks(testHost: testHost, environment: ProcessInfo.processInfo.environment)
        let startedAt = Self.clock()
        queue.async { [self] in
            self.hooks = hooks
            registerScreen()
            registerConsole()
            look(cause: "start")
            for (at, name) in hooks.notes {
                queue.asyncAfter(deadline: .now() + max(0, startedAt + at - Self.clock())) { [self] in
                    print("Test lock: \(name) delivered to SessionLock as the notification would be (nothing posted).")
                    note(name)
                }
            }
        }
    }

    /// The connected devices: once a second's look while there are any; a device's arrival looks at once.
    package func devices(_ count: Int) {
        queue.async { [self] in
            let was = state.withLockUnchecked { s -> Int in defer { s.devices = count }; return s.devices }
            if LockPolicy.polls(devices: count) {
                if pollTimer == nil {
                    let t = DispatchSource.makeTimerSource(queue: queue)
                    t.schedule(deadline: .now() + LockPolicy.pollInterval, repeating: LockPolicy.pollInterval, leeway: .milliseconds(50))
                    t.setEventHandler { [weak self] in self?.look(cause: "poll") }
                    t.resume()
                    pollTimer = t
                }
                if was == 0 { look(cause: "a device connected") }
            } else {
                pollTimer?.cancel()
                pollTimer = nil
            }
        }
    }

    /// The ask rule's step 1: this Mac's console is this user's and its screen unlocked, now.
    package var unlocked: Bool { gate.established && gate.reading == .unlocked }

    // MARK: The witnesses (on `queue`)

    private func registerScreen() {
        let name = hooks.notifyName ?? LockPolicy.screenStateName
        var token: Int32 = 0
        notifyStatus = notify_register_dispatch(name, &token, queue) { [weak self] _ in self?.look(cause: "the screen's lock state") }
        if notifyStatus == NOTIFY_STATUS_OK { notifyToken = token }
    }

    private func readScreen() -> LockPolicy.Screen {
        guard notifyStatus == NOTIFY_STATUS_OK else { return .unreadable }
        var value: UInt64 = 0
        let got = notify_get_state(notifyToken, &value)
        return LockPolicy.screen(registered: notifyStatus, got: got, state: value)
    }

    private func registerConsole() {
        var context = SCDynamicStoreContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        guard let store = SCDynamicStoreCreate(nil, "Sill" as CFString, { _, _, _ in
            SessionLock.shared.look(cause: "the console's user")         // on `queue` (the store's queue)
        }, &context) else { return }
        let key = SCDynamicStoreKeyCreateConsoleUser(nil)
        if SCDynamicStoreSetNotificationKeys(store, [key] as CFArray, nil), SCDynamicStoreSetDispatchQueue(store, queue) {
            self.store = store
        }
    }

    private func readConsole() -> LockPolicy.Console {
        var uid: uid_t = 0, gid: gid_t = 0
        let name = SCDynamicStoreCopyConsoleUser(store, &uid, &gid) as String?
        return LockPolicy.console(name: name, uid: UInt32(uid), ownUID: UInt32(getuid()), readable: store != nil)
    }

    /// TEST ONLY: what SILL_TEST_LOCKED or SILL_TEST_LOCKED_FILE says now.
    private func testReading() -> LockPolicy.Reading? {
        if hooks.locked { return .screenLocked }
        guard let path = hooks.file else { return nil }
        return LockPolicy.fileReading(try? String(contentsOfFile: path, encoding: .utf8))
    }

    // MARK: Looks

    /// Reads the console's user, the screen's state and the TEST ONLY hooks, then makes the reading (with
    /// `update` applied first). On `queue`.
    private func look(cause: String, update: ((inout LockPolicy.Reader) -> Void)? = nil) {
        let console = readConsole(), screen = readScreen(), test = testReading()
        let now = Self.clock()
        let (change, startRead, line) = state.withLockUnchecked { s -> (LockPolicy.Change?, Bool, String?) in
            update?(&s.reader)
            s.reader.console(console)
            s.reader.screen(screen)
            s.reader.test(test)
            let change = settle(&s, now: now)
            let startRead = s.sessionReadStarted == nil && LockPolicy.readsSession(s.reader.witnesses)
            if startRead { s.sessionReadStarted = now }
            return (change, startRead, hooks.log ? logLine(s.reader, cause: cause) : nil)
        }
        if let line { print(line) }
        if let change { changed(change) }
        if startRead { readSession(startedAt: now) }
        scheduleSettle()
    }

    /// The reader's look at `now`, its change to the gate at once. Under `state`'s lock.
    private func settle(_ s: inout Inner, now: Double) -> LockPolicy.Change? {
        guard let change = s.reader.look(at: now) else { return nil }
        gate.set(change.to)
        return change
    }

    private func logLine(_ r: LockPolicy.Reader, cause: String) -> String {
        LockPolicy.testLogLine(r.witnesses, raw: LockPolicy.reading(r.witnesses), gate: r.gate, established: r.established, cause: cause)
    }

    /// A change of the gate: its line now, then the coordinator.
    private func changed(_ change: LockPolicy.Change) {
        if let line = LockPolicy.line(change) { print(line) }
        onChange?()
    }

    /// The session dictionary on its own queue, bounded: unanswered after LockPolicy.sessionBound counts as
    /// locked until it answers. On `queue`.
    private func readSession(startedAt: Double) {
        sessionQueue.async { [self] in
            let session = LockPolicy.session(CGSessionCopyCurrentDictionary() as? [String: Any])
            queue.async { [self] in
                look(cause: "the session's dictionary") { reader in reader.session(session, startedAt: startedAt) }
                state.withLockUnchecked { s in if s.sessionReadStarted == startedAt { s.sessionReadStarted = nil } }
            }
        }
        queue.asyncAfter(deadline: .now() + LockPolicy.sessionBound) { [self] in
            let late = state.withLockUnchecked { $0.sessionReadStarted == startedAt }
            guard late else { return }
            look(cause: "the session's dictionary did not answer") { reader in reader.session(.unanswered, startedAt: startedAt) }
        }
    }

    /// An unlock's settle ends at a look after a session read made then (LockPolicy.Reader). On `queue`.
    private func scheduleSettle() {
        let ends = state.withLockUnchecked { $0.reader.settleEndsAt }
        guard let ends else {
            settleTimer?.cancel(); settleTimer = nil; settleAt = nil
            return
        }
        guard settleAt != ends else { return }
        settleTimer?.cancel()
        settleAt = ends
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + max(0, ends - Self.clock()) + 0.005)
        t.setEventHandler { [weak self] in self?.settleEnded() }
        t.resume()
        settleTimer = t
    }

    private func settleEnded() {
        settleTimer = nil
        settleAt = nil
        let now = Self.clock()
        let start = state.withLockUnchecked { s -> Bool in
            guard s.sessionReadStarted == nil else { return false }
            s.sessionReadStarted = now
            return true
        }
        if start {
            readSession(startedAt: now)
        } else {
            // A read is in flight: look again once it has had time to answer.
            queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.look(cause: "the settle") }
        }
    }

    // MARK: Notifications

    /// A notification by name (`LockPolicy.noteNames`), on whatever thread delivered it: the reading it
    /// sets is the gate's at once (a lock or a switch away; an unlock waits for every witness and the
    /// settle), then the other witnesses are read afresh on `queue`.
    package func note(_ name: String) {
        guard let note = LockPolicy.noteNames[name] else { return }
        let now = Self.clock()
        let change = state.withLockUnchecked { s -> LockPolicy.Change? in
            s.reader.note(note)
            return settle(&s, now: now)
        }
        if let change { changed(change) }
        queue.async { [weak self] in self?.look(cause: name) }
    }

    /// Sill.app: loginwindow's lock, unlock and console notifications and NSWorkspace's session ones, each
    /// delivered at once (`.deliverImmediately`), also while Sill is not active. Call once, on the main
    /// thread under the AppKit loop.
    package func watchNotifications() {
        guard observer == nil else { return }
        let o = NoteObserver()
        let center = DistributedNotificationCenter.default()
        for name in LockPolicy.distributedNames {
            center.addObserver(o, selector: #selector(NoteObserver.received(_:)), name: Notification.Name(name), object: nil,
                               suspensionBehavior: .deliverImmediately)
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in LockPolicy.workspaceNames {
            workspace.addObserver(o, selector: #selector(NoteObserver.received(_:)), name: Notification.Name(name), object: nil)
        }
        observer = o
    }

    // MARK: --print-cable, and the TEST ONLY hooks' words

    /// --print-cable's words for the console, from one look at every witness (the session dictionary
    /// bounded, as at a look). No test hook: the report reads the real console.
    package static func consoleDescription() -> String {
        var reader = LockPolicy.Reader()
        var uid: uid_t = 0, gid: gid_t = 0
        let name = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid) as String?
        reader.console(LockPolicy.console(name: name, uid: UInt32(uid), ownUID: UInt32(getuid()), readable: true))
        var token: Int32 = 0, value: UInt64 = 0
        let registered = notify_register_check(LockPolicy.screenStateName, &token)
        let got = registered == NOTIFY_STATUS_OK ? notify_get_state(token, &value) : registered
        reader.screen(LockPolicy.screen(registered: registered, got: got, state: value))
        if registered == NOTIFY_STATUS_OK { notify_cancel(token) }
        let answered = DispatchSemaphore(value: 0)
        let box = OSAllocatedUnfairLock<LockPolicy.Session>(initialState: .unanswered)
        DispatchQueue.global(qos: .userInitiated).async {
            let s = LockPolicy.session(CGSessionCopyCurrentDictionary() as? [String: Any])
            box.withLock { $0 = s }
            answered.signal()
        }
        _ = answered.wait(timeout: .now() + LockPolicy.sessionBound)
        reader.session(box.withLock { $0 }, startedAt: 0)
        switch LockPolicy.reading(reader.witnesses) {
        case .unlocked: return "unlocked, your session on the console."
        case .screenLocked: return "locked (the screen is locked)."
        case .offConsole: return "locked (another user, the login window or nobody is on the console)."
        }
    }

    /// The TEST ONLY hooks a test host takes (nothing on any other host: TestHooks says there that each is
    /// ignored).
    private static func hooks(testHost: Bool, environment env: [String: String]) -> Hooks {
        var h = Hooks()
        guard testHost else { return h }
        h.locked = env["SILL_TEST_LOCKED"] == "1"
        if let path = env["SILL_TEST_LOCKED_FILE"], !path.isEmpty { h.file = path }
        h.notifyName = LockPolicy.testNotifyName(env["SILL_TEST_LOCK_NOTIFY"])
        h.notes = LockPolicy.testNotes(env["SILL_TEST_LOCK_NOTE"]) ?? []
        h.log = env["SILL_TEST_LOCK_LOG"] == "1"
        return h
    }

    /// The lines a test host prints at start for the hooks it has (none without them).
    package static func testHookLines(testHost: Bool, environment env: [String: String]) -> [String] {
        guard testHost else { return [] }
        var lines: [String] = []
        if env["SILL_TEST_LOCKED"] == "1" { lines.append("Test lock: this Mac's screen counts as locked for the run (SILL_TEST_LOCKED).") }
        if let path = env["SILL_TEST_LOCKED_FILE"], !path.isEmpty {
            lines.append("Test lock: this Mac counts as locked while \(path) holds 1 and as switched to another user while it holds 2 (read at each look, once a second while a device is connected).")
        }
        if let raw = env["SILL_TEST_LOCK_NOTIFY"] {
            lines.append(LockPolicy.testNotifyName(raw).map { "Test lock: the screen's lock state is read from the notify name \($0), not \(LockPolicy.screenStateName)." }
                         ?? "SILL_TEST_LOCK_NOTIFY=\(raw) ignored: a name under \(LockPolicy.testNotifyPrefix), at most 128 characters.")
        }
        if let raw = env["SILL_TEST_LOCK_NOTE"] {
            lines.append(LockPolicy.testNotes(raw).map { "Test lock: \($0.count) notification\($0.count == 1 ? "" : "s") to deliver (SILL_TEST_LOCK_NOTE)." }
                         ?? "SILL_TEST_LOCK_NOTE=\(raw) ignored: '<seconds> <name>' parts split by ';', each name one SessionLock hears.")
        }
        if env["SILL_TEST_LOCK_LOG"] == "1" { lines.append("Test lock: each look's witnesses are printed (SILL_TEST_LOCK_LOG).") }
        return lines
    }
}

/// Sill.app's observer of the lock notifications: each to SessionLock.note, on the thread that delivered it.
private final class NoteObserver: NSObject {
    @objc func received(_ n: Notification) { SessionLock.shared.note(n.name.rawValue) }
}
