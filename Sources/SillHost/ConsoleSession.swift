import Foundation

/// Whether this Mac's user session has the console (issue #211). Under fast user switching another
/// user's session, or the login window, can have the screen while Sill runs on in this one: the
/// stream and every connection stay up, but the input Sill posts reaches no window (macOS gives a
/// session off the console no events; the reporter's `ioreg` had this user `onConsole False` while
/// taps and keys went nowhere), and once the Mac switches back, input lands again by itself, with
/// no reconnect and no relaunch (the reporter's retest of 2026-10-23). So the host only says so:
/// one line each way, and kind 16's `sessionOnConsole`, false while off the console and nil while
/// on it, so every state a device is sent then is what it always was. A device shows it as a line
/// over the stream and a callout in its Settings panel (iOSClient/AwayCopy.swift); nothing stops a
/// stream, ends a session or holds input back.
///
/// The witness is `kCGSSessionOnConsoleKey` in `CGSessionCopyCurrentDictionary()`, the session
/// dictionary SessionLock reads for the ask (about 0.1 ms a read). ConsoleWatch looks when the host
/// starts, at each NSWorkspace session notification (under the AppKit loop: Sill.app, SillHost
/// --virtual-display), as a device connects, and every `lookInterval` while one is connected, which
/// is all the CLI's default path has (its main queue runs without a run loop, so no notification
/// reaches it). A read without a dictionary (no GUI session: a CLI over ssh) or without the key says
/// nothing, and changes nothing: the devices are never told the Mac is away on a guess.
///
/// Pure (Foundation only), checked by Tests/checks/console-session.
enum ConsoleSession {
    /// The session dictionary's key (CGSession.h's `kCGSessionOnConsoleKey`).
    static let onConsoleKey = "kCGSSessionOnConsoleKey"

    /// How often a host looks while a device is connected, in seconds.
    static let lookInterval = 1.0

    /// The `[1s]` lines' count of the input messages a device sent while this session was off the
    /// console (each one posted as usual, and dropped by macOS).
    static let offConsoleInputKey = "in.offConsole"

    /// The witness: true or false from `kCGSSessionOnConsoleKey`; nil without a dictionary or
    /// without the key.
    static func onConsole(dictionary: [String: Any]?) -> Bool? {
        guard let value = dictionary?[onConsoleKey] as? NSNumber else { return nil }
        return value.boolValue
    }

    /// Kind 16's `sessionOnConsole`: nil while on the console, false while not.
    static func wire(onConsole: Bool) -> Bool? { onConsole ? nil : false }

    /// What a look changes: the state it leaves and the line to print, or nil when it changes
    /// nothing (the state it already had, or a read that says nothing).
    static func next(current: Bool, read: Bool?) -> (onConsole: Bool, line: String)? {
        guard let read, read != current else { return nil }
        return (read, read ? backLine : awayLine)
    }

    static let awayLine = "Console: another user's session, or the login window, has this Mac's screen; macOS drops the taps and keys devices send until it switches back to this one. Devices stay connected."
    static let backLine = "Console: this user's session has the screen again; devices' taps and keys reach it."

    // MARK: TEST ONLY

    /// SILL_TEST_CONSOLE_FILE=<path>, on a --synthetic host only: the host reads that file instead of
    /// the session dictionary (`testRead`), so a test switches "users" by writing it. A synthetic
    /// host without it never reads the console at all; any other host ignores it with one line.
    static func testHook(synthetic: Bool, environment env: [String: String]) -> (path: String?, line: String?) {
        guard let path = env["SILL_TEST_CONSOLE_FILE"], !path.isEmpty else { return (nil, nil) }
        guard synthetic else { return (nil, "SILL_TEST_CONSOLE_FILE ignored: only a --synthetic host takes it.") }
        return (path, "Test console: read from \(path) (\"off\": another user's session has the screen), never this Mac's session.")
    }

    /// What the test file says: "off", whitespace around it ignored, is another session on the
    /// console; anything else, an empty file or none, this one.
    static func testRead(contents: String?) -> Bool {
        contents?.trimmingCharacters(in: .whitespacesAndNewlines) != "off"
    }
}
