import Foundation

/// When the host tells macOS a user is active, so the Mac's display wakes and stays on while a
/// device uses it (docs/display-wake-plan.md, issue #134). With the display asleep ScreenCaptureKit
/// has nothing to capture and the device shows black windows; the lock screen is never seen, so
/// nobody can type the password. `caffeinate -u` over SSH was the workaround; this is the same
/// declaration (IOPMAssertionDeclareUserActivity), made by DisplayWake on this rule's say.
///
/// A device that connects always declares: that is the wake. Its input and its picks declare at most
/// once every `interval`, which postpones display sleep while someone works from the device, up to
/// the Mac's own display-sleep setting from the last declaration, as a local user's keys would.
/// Every declaration is an IPC call, so a pointer's moves, many a second, must not each make one.
/// When the last device leaves (`allLeft`), the next connect starts afresh. Pure (Foundation),
/// checked with swiftc (Tests/checks/display-wake).
struct DisplayWakePolicy: Equatable {
    enum Reason: String, Equatable {
        /// A device's session began (StreamServer's connect).
        case connected
        /// A device's input (a click, a scroll, a key, text, a gesture) or its pick of what streams.
        case activity
    }

    /// The least time between two declarations for `activity`. Well under the shortest display
    /// sleep macOS offers (1 minute), so a display never sleeps under a device that is in use.
    static let interval: TimeInterval = 10

    /// When the last declaration was made, nil before the first and after `allLeft`.
    private(set) var lastDeclared: TimeInterval?

    /// Whether to declare now, for this reason, at `now` (seconds on any steady clock); notes the
    /// declaration when it says yes.
    mutating func declares(_ reason: Reason, now: TimeInterval) -> Bool {
        switch reason {
        case .connected:
            break
        case .activity:
            if let last = lastDeclared, now - last < Self.interval, now >= last { return false }
        }
        lastDeclared = now
        return true
    }

    /// The last device left: nothing more is declared for it, and the next activity declares at once.
    mutating func allLeft() {
        lastDeclared = nil
    }
}
