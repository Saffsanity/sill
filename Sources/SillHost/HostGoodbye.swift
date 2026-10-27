import Foundation
import StreamProtocol

/// Which goodbye (kind 22) every connected device hears as Sill or the Mac goes, and the lines the
/// log gets for it (docs/update-notice-plan.md §7.3, issue #105).
///
/// How macOS ends Sill.app at a log out, a restart or a shut down, as far as it is known (2026-10-20):
/// - Observed: a restart begun from another account while Sill.app ran in this one (2026-10-19, no
///   device connected) ended it with SIGTERM during the system shutdown (launchd: "exited due to
///   exit(143) during system shutdown"): HostShutdown's signal path, whose goodbye was then "quit",
///   not a Quit; its own session's loginwindow logged no log out. The other account's loginwindow,
///   and its strings: a log out, restart or shut down begun in a session quits that session's
///   ordinary apps with quit Apple events, and its UI-element apps (Sill.app is one: LSUIElement)
///   only after the point of no return, with a kill attempt ("doing kill attempt") and a quit event
///   to an app it could not kill ("Could not kill %@, sending a quit event").
/// - Observed with a probe on this Mac (macOS 27.0.1, an accessory app sending quit Apple events to
///   itself): AppKit posts NSWorkspace's willPowerOff as it handles a quit Apple event whose
///   `kAEQuitReason` is an attribute, whatever the reason ('rest', 'shut', 'rlgo', 'quia', any), just
///   before applicationShouldTerminate; with the reason as a parameter (AERegistry.h's word), or
///   none, it posts nothing.
/// - Inferred, not observed: that loginwindow cannot kill Sill.app (it turns sudden termination off)
///   and so sends it a quit Apple event with the reason as an attribute, bringing willPowerOff with
///   it, when the log out, restart or shut down is begun in Sill's own session.
///
/// So the choice, `Going`: NSWorkspace's willPowerOff, when it comes (StreamCoordinator's
/// `observePowerOff`), is the first signal, and for `powerOffStands` after it the goodbye is
/// `powerOff`, "shutdown" in the words "‹Mac› is shutting down or restarting." (willPowerOff says
/// neither which of a log out, a restart and a shut down nor whether someone cancels it). Nothing is
/// sent then: it goes out when Sill goes, by the SIGTERM that ends it (one that comes while Sill's
/// Quit still waits on a full-screen window, say) or a quit Apple event, never by Sill's own Quit
/// from its menu. A quit Apple event's reason, read as a parameter or an attribute (`quitReason`),
/// refines it: a restart (`restart`, "‹Mac› is restarting."), a shut down (`shutDown`, "‹Mac› is
/// shutting down."), a log out (`quit`: the Mac stays up, and Sill comes back with the next login).
/// Without willPowerOff or a reason (Sill's menu, another app's quit, a signal, a restart begun from
/// another account as above): `quit`, byte for byte as before. The Mac going to sleep is
/// NSWorkspace's willSleep (StreamCoordinator's `observeSleep`): `sleep`.
///
/// One goodbye per connection, the first (StreamServer's `told`): a Quit right after a sleep's
/// goodbye, or after a device was removed, never replaces what that device was told.
///
/// Pure: Foundation and StreamProtocol, checked in Tests/checks/goodbye (with the device's reading of
/// each goodbye, the codes against the SDK's own constants, and a quit event's reason read both ways).
package enum HostGoodbye {
    /// How Sill or the Mac goes, as far as Sill can tell.
    package enum Going: Equatable {
        /// Sill quits (its menu, another app, a signal, a log out that says so): "quit".
        case quit
        /// The Mac is about to sleep (NSWorkspace's willSleep): "sleep".
        case sleep
        /// A quit Apple event's reason said a shut down: "shutdown", "‹Mac› is shutting down."
        case shutDown
        /// A quit Apple event's reason said a restart: "restart", "‹Mac› is restarting."
        case restart
        /// macOS said the Mac is about to log out, restart or shut down (willPowerOff), and no quit
        /// reason said which: "shutdown", "‹Mac› is shutting down or restarting."
        case powerOff
    }

    /// `kAERestart` ('rest') and `kAEShowRestartDialog` ('rrst'), spelled here so this file needs
    /// Foundation only.
    package static let restartReasons: Set<UInt32> = [0x7265_7374, 0x7272_7374]
    /// `kAEShutDown` ('shut') and `kAEShowShutdownDialog` ('rsdn').
    package static let shutdownReasons: Set<UInt32> = [0x7368_7574, 0x7273_646E]
    /// `kAEReallyLogOut` ('rlgo') and `kAELogOut` ('logo'): the Mac stays up, so a "quit".
    package static let logOutReasons: Set<UInt32> = [0x726C_676F, 0x6C6F_676F]
    /// `kAEQuitReason` ('why?'), `kCoreEventClass` ('aevt') and `kAEQuitApplication` ('quit').
    package static let quitReasonKeyword: UInt32 = 0x7768_793F
    static let coreEventClass: UInt32 = 0x6165_7674, quitApplication: UInt32 = 0x7175_6974

    /// How Sill goes at its end, from what ended it and what macOS said before: the quit Apple
    /// event's reason (`reason`; nil: none, or no such event), whether Sill's own Quit ended it with
    /// no Apple event (`byMenu`: its menu, ⌘Q), and whether macOS said, less than `powerOffStands`
    /// before, that the Mac is about to log out, restart or shut down (`poweringOff`, willPowerOff:
    /// `poweringOff(since:now:)`). A reason that says which decides; otherwise willPowerOff makes the
    /// end by a signal or by a quit Apple event `powerOff`, never Sill's own Quit (after a log out,
    /// restart or shut down someone cancelled, a Quit from the menu is a quit); and without it, `quit`.
    package static func forQuit(reason: UInt32?, byMenu: Bool = false, poweringOff: Bool) -> Going {
        if let reason {
            if restartReasons.contains(reason) { return .restart }
            if shutdownReasons.contains(reason) { return .shutDown }
            if logOutReasons.contains(reason) { return .quit }
        }
        return poweringOff && !byMenu ? .powerOff : .quit
    }

    /// How long NSWorkspace's willPowerOff counts (`poweringOff(since:now:)`): ten minutes. In the
    /// probe AppKit posts it just before the Quit it brings, so a log out, restart or shut down that
    /// goes ahead ends Sill moments after it; one cancelled (an app that would not quit, someone's
    /// Cancel) leaves nothing behind after this.
    package static let powerOffStands: Double = 600

    /// Whether the willPowerOff that came at `since` (systemUptime; nil: none came) still counts at
    /// `now`.
    package static func poweringOff(since: Double?, now: Double) -> Bool {
        guard let since else { return false }
        return now >= since && now - since < powerOffStands
    }

    /// The goodbye every device hears for `going`, with the Mac's name (`mac`) in its words.
    package static func goodbye(_ going: Going, mac: String) -> Goodbye {
        switch going {
        case .quit: return Goodbye(reason: Goodbye.quit)
        case .sleep: return Goodbye.asleep(mac: mac)
        case .shutDown: return Goodbye.shuttingDown(mac: mac)
        case .restart: return Goodbye.restarting(mac: mac)
        case .powerOff: return Goodbye.shuttingDownOrRestarting(mac: mac)
        }
    }

    /// The reason in a quit Apple event (`kAEQuitReason`): its parameter, else its attribute, as a
    /// four-character code. Nil for no event (a quit from the menu), an event that is not a quit
    /// Apple event, and one without a reason.
    package static func quitReason(in event: NSAppleEventDescriptor?) -> UInt32? {
        guard let event, event.eventClass == coreEventClass, event.eventID == quitApplication else { return nil }
        let keyword = AEKeyword(quitReasonKeyword)
        guard let reason = event.paramDescriptor(forKeyword: keyword) ?? event.attributeDescriptor(forKeyword: keyword) else { return nil }
        let code = reason.enumCodeValue   // a type code, an enumeration or a 32-bit number alike
        return code == 0 ? nil : code
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

    /// The log's line each time NSWorkspace's willPowerOff comes; what the devices were told follows
    /// when Sill goes (`line`).
    package static let powerOffLine = "macOS says the Mac is about to log out, restart or shut down."

    /// A four-character code as its characters ('rest'), or its number when they are not printable.
    static func fourCharacters(_ code: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8((code >> UInt32($0)) & 0xFF) }
        guard bytes.allSatisfy({ (0x20...0x7E).contains($0) }) else { return String(code) }
        return "'" + String(decoding: bytes, as: UTF8.self) + "'"
    }

    /// The log's line once `devices` devices were told: one for the Mac's own going, "The Mac is
    /// going to sleep: 2 devices told."; none when no device was connected, and none for a `quit`,
    /// whose Quit prints its own line (HostShutdown), as before.
    package static func line(_ going: Going, devices: Int) -> String? {
        guard devices > 0 else { return nil }
        let told = "\(devices) device\(devices == 1 ? "" : "s") told."
        switch going {
        case .sleep: return "The Mac is going to sleep: \(told)"
        case .shutDown: return "The Mac is shutting down: \(told)"
        case .restart: return "The Mac is restarting: \(told)"
        case .powerOff: return "The Mac is shutting down or restarting: \(told)"
        case .quit: return nil
        }
    }
}

/// The Mac between its sleep goodbye and its wake (the verifier's review of PR #100, 2026-10-26): from
/// NSWorkspace's willSleep, when every connected device hears "sleep", until its didWake, no door admits
/// a session. Until the Mac actually sleeps the host still runs, and a session's start declares user
/// activity (DisplayWake, #151), which could light the display of a Mac someone has just put to sleep,
/// or keep it awake; and 0.5.1, the App Store build, reads "sleep" as a reason it does not know, with
/// `"reconnect":true`, and dials the Mac's still-listed row as soon as its session ends, which over TLS
/// is the Mac's cancel a second after the goodbye (DeviceGate.closeWait), inside the sleep's transition.
/// So a session that comes then gets the same goodbye (`refusal`), closed as the device gate closes a
/// refused one, and is never registered: this build's device reads it as the sleep's (GoodbyePolicy,
/// DiscoveryPolicy: the Mac counted as asleep again, its first dial 20 s later), 0.5.1 shows its words
/// and dials again (StreamServer slows a source refused five times in a minute, as the gate does), and
/// DisplayWake declares nothing while the window runs.
///
/// How it ends: at didWake; a willSleep opens it again from that moment; and it lapses `limit` after
/// willSleep in the Mac's awake time (ProcessInfo's systemUptime, which stops while the Mac sleeps), so
/// a didWake that never comes leaves no door shut for good. Whether a dark wake (a Bonjour Sleep Proxy
/// waking the Mac for a device's dial, Power Nap) posts didWake is not known here: if it does, the
/// window ends at it and a session admitted then is #151's case (the support page's sleeping Mac, Noah's
/// sleep-proxy item); if it does not, the window runs through it, and its awake time counts toward the
/// limit. Ten minutes covers the transition (macOS waits up to 30 s for apps before it sleeps), the dark
/// wakes the device's own dials can bring (nine, the first 20 s after the goodbye, then every 30 s), and
/// the wake itself; a Mac that never slept is refused at most that long. Pure, checked in
/// Tests/checks/goodbye; StreamServer keeps one under a lock (the doors read it on the network queue,
/// NSWorkspace's observers write it on the main thread).
package struct SleepWindow: Equatable, Sendable {
    /// How long the window lasts without a didWake, in the Mac's awake time.
    package static let limit: Double = 600

    /// When willSleep came (systemUptime); nil: no window.
    package private(set) var since: Double?

    package init() {}

    /// NSWorkspace's willSleep at `now`: the window opens, or opens again from now.
    package mutating func willSleep(at now: Double) { since = now }

    /// NSWorkspace's didWake, or a window that lapsed and was noticed: the window ends.
    package mutating func didWake() { since = nil }

    /// Whether the Mac counts as asleep at `now`: from willSleep until didWake, `limit` at most. A clock
    /// that reads before its willSleep counts as ended (never a door stuck shut).
    package func asleep(at now: Double) -> Bool {
        guard let since else { return false }
        return now >= since && now - since < Self.limit
    }

    /// A window still open that no longer counts at `now` (it ran its `limit` without a didWake).
    package func lapsed(at now: Double) -> Bool { since != nil && !asleep(at: now) }

    /// What a door says to a session that comes at `now`: while the Mac is asleep, the goodbye every
    /// connected device heard at willSleep (`HostGoodbye.goodbye(.sleep, mac:)`); else nil, admit it.
    package func refusal(at now: Double, mac: String) -> Goodbye? {
        asleep(at: now) ? HostGoodbye.goodbye(.sleep, mac: mac) : nil
    }

    /// The log's line for a session refused while the Mac is asleep, the first from its source in a
    /// minute (StreamServer counts the rest).
    package static func refusedLine(endpoint: String) -> String {
        "The Mac is going to sleep: refused a session from \(endpoint) with the same goodbye."
    }

    /// The minute's count of the rest from one source.
    package static func refusedCountLine(_ n: Int, source: String) -> String {
        "The Mac is going to sleep: refused \(n) more session\(n == 1 ? "" : "s") from \(source) in the last minute."
    }

    /// didWake ended an open window: one line, with the sessions refused while it ran.
    package static func wokeLine(refused: Int) -> String {
        "The Mac woke: devices can connect again"
            + (refused > 0 ? " (\(refused) session\(refused == 1 ? "" : "s") refused while it slept)." : ".")
    }

    /// The window lapsed without a didWake, noticed when a door or DisplayWake next asked.
    package static var lapsedLine: String {
        "The Mac said it was going to sleep \(Int(limit / 60)) minutes ago and has not said it woke: devices can connect again."
    }
}
