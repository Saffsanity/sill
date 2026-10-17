import Foundation
import IOKit.pwr_mgt

/// Wakes the Mac's display for a device and keeps it from sleeping while the device is used
/// (docs/display-wake-plan.md, issue #134): IOPMAssertionDeclareUserActivity, the call behind
/// `caffeinate -u`, when DisplayWakePolicy says so. It powers the display on and postpones display
/// sleep up to the Mac's own Energy Saver setting from the last call; no special privilege needed.
///
/// Threading: `note` and `allLeft` from the main actor (the coordinator), where the policy lives. The
/// IOKit calls may block on IPC, so they run on `queue`, which alone touches `assertion`.
/// A synthetic host (`dryRun`) counts what it would declare and declares nothing.
@MainActor
final class DisplayWake {
    /// A synthetic host's: count, never touch this Mac's display.
    var dryRun = false

    private var policy = DisplayWakePolicy()
    private let box = Box()

    /// A device connected (`.connected`) or used the Mac (`.activity`).
    func note(_ reason: DisplayWakePolicy.Reason) {
        guard policy.declares(reason, now: ProcessInfo.processInfo.systemUptime) else { return }
        Stats.shared.bump("wake.\(reason.rawValue)")
        if dryRun { return }
        box.declare(logged: reason == .connected)
    }

    /// The last device left: the declaration is released, so the display sleeps by the Mac's own
    /// settings from now, and the next device's connect wakes it again.
    func allLeft() {
        policy.allLeft()
        if dryRun { return }
        box.release()
    }

    private final class Box: @unchecked Sendable {   // `assertion` and `failed` are confined to `queue`
        private let queue = DispatchQueue(label: "sill.display-wake", qos: .userInitiated)
        private var assertion = IOPMAssertionID(0)
        private var failed = false

        func declare(logged: Bool) {
            queue.async {
                var id = self.assertion
                let result = IOPMAssertionDeclareUserActivity("Sill: a device is using this Mac" as CFString,
                                                              kIOPMUserActiveLocal, &id)
                if result == kIOReturnSuccess {
                    self.assertion = id
                    if logged || self.failed { print("Display: awake for a device.") }
                    self.failed = false
                } else if !self.failed {
                    self.failed = true
                    print("Display: could not wake the display (IOReturn \(result)).")
                }
            }
        }

        func release() {
            queue.async {
                guard self.assertion != 0 else { return }
                IOPMAssertionRelease(self.assertion)
                self.assertion = 0
            }
        }
    }
}
