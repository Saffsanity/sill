import Foundation
import AppKit
import CoreGraphics

/// Whether this Mac's user is at an unlocked console (docs/home-pairing-plan.md §4.3): the ask
/// rule's step 1 (a locked Mac pairs nothing by itself and opens no window, which nobody could
/// see), and --print-cable's last line.
///
/// The witness is `CGSessionCopyCurrentDictionary()`: unlocked when `kCGSSessionOnConsoleKey` is 1
/// (this user's session is the one on the console, not another user's under fast user switching)
/// and `CGSSessionScreenIsLocked` is absent or false; no dictionary counts as locked. That lock key
/// is undocumented, and a rename would read as unlocked, so Sill.app adds a second witness, the
/// distributed notifications `com.apple.screenIsLocked` and `com.apple.screenIsUnlocked`
/// (`watchNotifications`): either one saying locked wins. The CLI has the dictionary only.
///
/// Main actor, where the ask is judged. TEST ONLY: SILL_TEST_LOCKED=1, on a test host only
/// (DoorPolicy.isTestHost), makes it say locked.
@MainActor
package final class SessionLock {
    package static let shared = SessionLock()

    /// The last notification said locked (Sill.app only).
    private var notifiedLocked = false
    /// Whether this user's session is currently on the console (macOS Fast User Switching, #211).
    package private(set) var isOnConsole = true
    package var onConsoleChanged: ((Bool) -> Void)?
    private var observers: [NSObjectProtocol] = []

    private init() {}

    /// Whether the console is this user's and unlocked, now. `testHost`: whether SILL_TEST_LOCKED
    /// may count.
    package func unlocked(testHost: Bool) -> Bool {
        if Self.testLocked(testHost: testHost, environment: ProcessInfo.processInfo.environment) { return false }
        let dictionary = CGSessionCopyCurrentDictionary() as? [String: Any]
        return Self.unlocked(dictionary: dictionary, notifiedLocked: notifiedLocked)
    }

    /// Sill.app: the lock and unlock notifications as a second witness. Call once, on the main
    /// actor under the AppKit loop.
    package func watchNotifications() {
        guard observers.isEmpty else { return }
        let d = CGSessionCopyCurrentDictionary() as? [String: Any]
        if let on = d?["kCGSSessionOnConsoleKey"] as? NSNumber {
            isOnConsole = on.boolValue
        }
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
            Task { @MainActor in SessionLock.shared.notifiedLocked = true }
        })
        observers.append(center.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"), object: nil, queue: .main) { _ in
            Task { @MainActor in SessionLock.shared.notifiedLocked = false }
        })
        let ws = NSWorkspace.shared.notificationCenter
        observers.append(ws.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                guard SessionLock.shared.isOnConsole else { return }
                SessionLock.shared.isOnConsole = false
                print("Console session: switched away from this user's session (Fast User Switching); input is paused until this session returns.")
                SessionLock.shared.onConsoleChanged?(false)
            }
        })
        observers.append(ws.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in
                guard !SessionLock.shared.isOnConsole else { return }
                SessionLock.shared.isOnConsole = true
                print("Console session: this user's session is back on the console.")
                SessionLock.shared.onConsoleChanged?(true)
            }
        })
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
        if testLocked(testHost: testHost, environment: ProcessInfo.processInfo.environment) { return "locked (SILL_TEST_LOCKED)." }
        guard let d = CGSessionCopyCurrentDictionary() as? [String: Any] else { return "locked (no console session)." }
        guard let onConsole = d["kCGSSessionOnConsoleKey"] as? NSNumber, onConsole.boolValue else {
            return "locked (another user's session is on the console)."
        }
        return unlocked(dictionary: d, notifiedLocked: false) ? "unlocked, your session on the console." : "locked."
    }

    /// TEST ONLY: SILL_TEST_LOCKED=1, on a test host only.
    nonisolated static func testLocked(testHost: Bool, environment: [String: String]) -> Bool {
        testHost && environment["SILL_TEST_LOCKED"] == "1"
    }
}
