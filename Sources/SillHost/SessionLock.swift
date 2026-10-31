import Foundation
import AppKit
import CoreGraphics

/// Whether this Mac's user is at an unlocked console (docs/home-pairing-plan.md §4.3): the ask
/// rule's step 1 (a locked Mac pairs nothing by itself and opens no window, which nobody could
/// see), --print-cable's last line, and since 2026-10-31 what every device may see and do
/// (LockPolicy, docs/locked-mac-plan.md: a locked Mac shows its lock screen and nothing else).
///
/// The witness is `CGSessionCopyCurrentDictionary()`: unlocked when `kCGSSessionOnConsoleKey` is 1
/// (this user's session is the one on the console, not another user's under fast user switching)
/// and `CGSSessionScreenIsLocked` is absent or false; no dictionary counts as locked. That lock key
/// is undocumented, and a rename would read as unlocked, so Sill.app adds a second witness, the
/// distributed notifications `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked`
/// (`watchNotifications`): either one saying locked wins. The CLI has the dictionary only. Sill.app
/// also hears NSWorkspace's fast user switches, which only make the coordinator read again at once
/// (`onChange`).
///
/// Main actor, where the ask is judged. TEST ONLY, on a test host only (DoorPolicy.isTestHost):
/// SILL_TEST_LOCKED=1 makes it say locked; SILL_TEST_LOCKED_FILE=<path> says locked while that file
/// holds "1" (LockPolicy.fileSaysLocked), read at each reading, so a test can lock and unlock a
/// running host.
@MainActor
package final class SessionLock {
    package static let shared = SessionLock()

    /// The last notification said locked (Sill.app only).
    private var notifiedLocked = false
    private var observers: [NSObjectProtocol] = []
    /// A notification that may have changed the reading came (Sill.app only): the coordinator reads the
    /// lock again at once instead of at its next poll.
    package var onChange: (@MainActor () -> Void)?

    private init() {}

    /// Whether the console is this user's and unlocked, now. `testHost`: whether SILL_TEST_LOCKED and
    /// SILL_TEST_LOCKED_FILE may count.
    package func unlocked(testHost: Bool) -> Bool {
        if Self.testLocked(testHost: testHost, environment: ProcessInfo.processInfo.environment) { return false }
        let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any]
        return Self.unlocked(dictionary: dictionary, notifiedLocked: notifiedLocked)
    }

    /// Sill.app: the lock and unlock notifications as a second witness. Call once, on the main
    /// actor under the AppKit loop.
    package func watchNotifications() {
        guard observers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
            Task { @MainActor in
                SessionLock.shared.notifiedLocked = true
                SessionLock.shared.onChange?()
            }
        })
        observers.append(center.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            Task { @MainActor in
                SessionLock.shared.notifiedLocked = false
                SessionLock.shared.onChange?()
            }
        })
        // Another user's session taking the console, and this one getting it back: no witness of their
        // own (the dictionary's kCGSSessionOnConsoleKey says it), only a reading now, not at the next poll.
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in SessionLock.shared.onChange?() }
            })
        }
    }

    /// The rule, pure: unlocked only with a dictionary whose `kCGSSessionOnConsoleKey` is 1 (true)
    /// and whose `CGSSessionScreenIsLocked` is absent or false, and no notification saying locked.
    nonisolated static func unlocked(dictionary: [String: Any]?, notifiedLocked: Bool) -> Bool {
        guard !notifiedLocked, let d = dictionary else { return false }
        guard let onConsole = d["kCGSSessionOnConsoleKey"] as? NSNumber, onConsole.boolValue else { return false }
        if let locked = d["CGSSessionScreenIsLocked"] {
            guard let n = locked as? NSNumber, !n.boolValue else { return false }
        }
        return true
    }

    /// --print-cable's words for the console, from the session dictionary (the CLI has no other
    /// witness).
    nonisolated static func consoleDescription(testHost: Bool) -> String {
        if let hook = testLockedBy(testHost: testHost, environment: ProcessInfo.processInfo.environment) { return "locked (\(hook))." }
        guard let d = CGSessionCopyCurrentDictionary() as? [String: Any] else { return "locked (no console session)." }
        guard let onConsole = d["kCGSSessionOnConsoleKey"] as? NSNumber, onConsole.boolValue else {
            return "locked (another user's session is on the console)."
        }
        return unlocked(dictionary: d, notifiedLocked: false) ? "unlocked, your session on the console." : "locked."
    }

    /// TEST ONLY: SILL_TEST_LOCKED=1, or SILL_TEST_LOCKED_FILE's file holding "1", on a test host only.
    nonisolated static func testLocked(testHost: Bool, environment: [String: String]) -> Bool {
        testLockedBy(testHost: testHost, environment: environment) != nil
    }

    /// The TEST ONLY variable that says locked now, nil for none: SILL_TEST_LOCKED=1 for the run, else
    /// SILL_TEST_LOCKED_FILE while its file holds "1" (read now).
    nonisolated static func testLockedBy(testHost: Bool, environment: [String: String]) -> String? {
        guard testHost else { return nil }
        if environment["SILL_TEST_LOCKED"] == "1" { return "SILL_TEST_LOCKED" }
        guard let path = environment["SILL_TEST_LOCKED_FILE"], !path.isEmpty,
              LockPolicy.fileSaysLocked(try? String(contentsOfFile: path, encoding: .utf8)) else { return nil }
        return "SILL_TEST_LOCKED_FILE"
    }

    /// The line a test host prints at start while SILL_TEST_LOCKED_FILE is set; nil without it, and on
    /// any other host (TestHooks says there that it is ignored).
    nonisolated static func testHookLine(testHost: Bool, environment: [String: String]) -> String? {
        guard testHost, let path = environment["SILL_TEST_LOCKED_FILE"], !path.isEmpty else { return nil }
        return "Test lock: this Mac counts as locked while \(path) holds 1 (read every second while a device is connected)."
    }
}
