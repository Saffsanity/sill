import CoreGraphics
import Foundation
import IOKit.pwr_mgt

/// Tells macOS that someone is using the Mac, for a device (issue #134): IOKit's
/// IOPMAssertionDeclareUserActivity with kIOPMUserActiveLocal, the declaration `caffeinate -u`
/// makes, and the kind WindowServer makes for a key press. A display that is asleep powers on, and
/// display sleep is postponed "up to the user's display sleep Energy Saver settings" (IOPMLib.h), so
/// the display sleeps again by the Mac's own setting once no device uses it: nothing is held.
/// (WindowServer's UserIsActive assertion for a key press shows that setting as its timeout in
/// `pmset -g assertions`.) The same ID goes back with each call of its type, as the header asks: one
/// ID for local declarations and one for remote ones, since whether powerd keeps an assertion's type
/// when its ID comes back with the other is not documented. None is released early, and the process's
/// assertions go with it when it quits. TEST ONLY `SILL_TEST_USER_ACTIVE=remote` declares
/// kIOPMUserActiveRemote instead, and `auto` by PR #229's rule (DisplayWake.userType); the caller
/// gives each declaration its type.
///
/// DisplayWake decides when (the coordinator, on the main actor); a test host never gets here. The
/// call is an IPC to powerd and may block, so it runs on a queue of its own: the main display's sleep
/// state read just before it and again `DisplayWake.secondLook` later on the same queue, and the lines
/// DisplayWake.Report allows (a wake once, else a line a minute at most).
final class DisplayActivity: @unchecked Sendable {
    private let queue = DispatchQueue(label: "sill.display-wake", qos: .userInitiated)
    // On `queue`.
    private var assertionIDs: [DisplayWake.UserType: IOPMAssertionID] = [:]
    private var report = DisplayWake.Report()

    /// Declares user activity for `device` (its name for the line) because of `activity`, as a user
    /// of `type`: local, as a key press on the Mac does, unless TEST ONLY SILL_TEST_USER_ACTIVE says
    /// otherwise (DisplayWake.userType).
    func declare(for device: String, _ activity: DisplayWake.Activity, as type: DisplayWake.UserType) {
        queue.async { [self] in
            let wasAsleep = Self.mainDisplayAsleep()
            var id = assertionIDs[type] ?? IOPMAssertionID(kIOPMNullAssertionID)
            let userType = type == .remote ? kIOPMUserActiveRemote : kIOPMUserActiveLocal
            let result = IOPMAssertionDeclareUserActivity(DisplayWake.assertionName as CFString, userType, &id)
            if result == kIOReturnSuccess {
                assertionIDs[type] = id
                Stats.shared.bump(DisplayWake.declaredKey)
            }
            let said = report.declared(device: device, activity: activity, wasAsleep: wasAsleep, result: result,
                                       remote: type == .remote)
            if let line = said.line { print(line) }
            guard let look = said.look else { return }
            // Whether it woke the display shows once the panel is on: a wake only when it reads on.
            queue.asyncAfter(deadline: .now() + DisplayWake.secondLook) { [self] in
                let line = report.looked(look, asleepNow: Self.mainDisplayAsleep(), at: CFAbsoluteTimeGetCurrent())
                if let line { print(line) }
            }
        }
    }

    private static func mainDisplayAsleep() -> Bool { CGDisplayIsAsleep(CGMainDisplayID()) != 0 }
}
