import Foundation
import StreamProtocol

/// Which goodbye (kind 22) every connected device hears as Sill or the Mac goes, and the one line
/// the log gets for it (docs/update-notice-plan.md §7.3, issue #105).
///
/// Sill.app's Quit says why from the quit's own Apple event: macOS asks every app to quit, with a
/// reason (`kAEQuitReason`, AERegistry.h), when the Mac restarts, shuts down or logs out. A restart
/// or a shut down is said as such, with the Mac's words (`Goodbye.restarting`,
/// `Goodbye.shuttingDown`); a log out (the Mac stays up, and Sill comes back with the next login),
/// a quit from Sill's menu or another app's, and a signal (no reason) are "quit", as before. The
/// reason is read at the quit itself, never kept from NSWorkspace's willPowerOff, which fires for a
/// log out a person may still cancel: nothing is said to a device until Sill really goes. The Mac
/// going to sleep is NSWorkspace's willSleep (StreamCoordinator.observeSleep): `Goodbye.asleep`.
///
/// One goodbye per connection, the first (StreamServer's `told`): a Quit right after a sleep's
/// goodbye, or after a device was removed, never replaces what that device was told.
///
/// Pure: Foundation and StreamProtocol, checked in Tests/checks/goodbye (with the device's reading of
/// each goodbye, and the codes against the SDK's own constants).
package enum HostGoodbye {
    /// `kAERestart` ('rest') and `kAEShowRestartDialog` ('rrst'), spelled here so this file needs
    /// Foundation only.
    package static let restartReasons: Set<UInt32> = [0x7265_7374, 0x7272_7374]
    /// `kAEShutDown` ('shut') and `kAEShowShutdownDialog` ('rsdn').
    package static let shutdownReasons: Set<UInt32> = [0x7368_7574, 0x7273_646E]
    /// `kAEReallyLogOut` ('rlgo') and `kAELogOut` ('logo'): the Mac stays up, so a "quit".
    package static let logOutReasons: Set<UInt32> = [0x726C_676F, 0x6C6F_676F]

    /// The goodbye a Quit sends, from the quit's reason (nil: none, as for a quit from the menu or a
    /// signal). `mac` names the Mac in the words.
    package static func forQuit(reason: UInt32?, mac: String) -> Goodbye {
        guard let reason else { return Goodbye(reason: Goodbye.quit) }
        if restartReasons.contains(reason) { return Goodbye.restarting(mac: mac) }
        if shutdownReasons.contains(reason) { return Goodbye.shuttingDown(mac: mac) }
        return Goodbye(reason: Goodbye.quit)
    }

    /// The log's line when macOS gave the quit a reason (nil: none, no line), so a restart's,
    /// a shut down's or a log out's Quit can be told from one from the menu in Sill.log.
    package static func quitLine(reason: UInt32?) -> String? {
        guard let reason else { return nil }
        if restartReasons.contains(reason) { return "Quit: macOS asked Sill to quit for a restart." }
        if shutdownReasons.contains(reason) { return "Quit: macOS asked Sill to quit for a shut down." }
        if logOutReasons.contains(reason) { return "Quit: macOS asked Sill to quit for a log out." }
        return "Quit: macOS asked Sill to quit (reason \(fourCharacters(reason)))."
    }

    /// A four-character code as its characters ('rest'), or its number when they are not printable.
    static func fourCharacters(_ code: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> UInt32($0)) & 0xFF) }
        guard bytes.allSatisfy({ (0x20...0x7E).contains($0) }) else { return String(code) }
        return "'" + String(decoding: bytes, as: UTF8.self) + "'"
    }

    /// The log's line once `devices` devices were told: one for the Mac's own going, "The Mac is
    /// going to sleep: 2 devices told."; none when no device was connected, and none for a "quit",
    /// whose Quit prints its own line (HostShutdown), as before.
    package static func line(_ goodbye: Goodbye, devices: Int) -> String? {
        guard devices > 0 else { return nil }
        let told = "\(devices) device\(devices == 1 ? "" : "s") told."
        switch goodbye.reason {
        case Goodbye.sleep: return "The Mac is going to sleep: \(told)"
        case Goodbye.shutdown: return "The Mac is shutting down: \(told)"
        case Goodbye.restart: return "The Mac is restarting: \(told)"
        default: return nil
        }
    }
}
