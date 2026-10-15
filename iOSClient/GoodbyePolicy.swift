import Foundation
import StreamProtocol

/// What the connect screen says, and whether this device reconnects, when a session ends: with the
/// Mac's goodbye (kind 22), or without one (the connection just ended). One rule for every route,
/// whether or not a window list came (docs/update-notice-plan.md §7.3). Pure: Foundation and
/// StreamProtocol, checked on its own with swiftc.
///
/// The five reasons hosts have sent since remote access keep their words and their reconnects, and
/// so does "pairingRequired" (pairing at home: Require pairing turned on while this unpaired device
/// was connected; StreamClient+Home ends such a session at home with these words). "update" (a Mac
/// whose device floor is above this device's version, DeviceGate) and any other reason are notices:
/// the host's own words (its `message`, cleaned), shown as the status line, and a reconnect only
/// when the Mac asks for one (`"reconnect":true`); "update" also offers the App Store. The Mac's
/// "sleep" and "shutdown" are notices too, in this build's words and always with a reconnect.
/// Before this rule a reason the device did not know showed "‹Mac› disconnected…" and reconnected
/// at once, so a Mac that refused the device was dialled again and again.
enum GoodbyePolicy {
    struct Outcome: Equatable {
        /// The connect screen's status line.
        var text: String
        /// This device reconnects by itself (StreamClient.Reconnect).
        var reconnect: Bool
        /// That reconnect may dial the saved Mac through the remote door (only a saved Mac).
        var remoteAllowed: Bool
        /// "Update Sill in the App Store" under the status line ("update" only).
        var storeLink = false
        /// The Mac's own words: a goodbye this build shows as the host wrote it. Looked at before a
        /// remote dial's failure rules (RemoteDialPolicy), which know only the older reasons.
        var isNotice: Bool
    }

    /// The longest message shown, in characters (SafeText.label).
    static let messageLimit = 300

    /// The reasons whose words and reconnects are this build's own; "update" and any other reason
    /// are notices.
    static let knownReasons: Set<String> = [Goodbye.quit, Goodbye.removed, Goodbye.remoteOff, Goodbye.internetOff, Goodbye.busy,
                                            Goodbye.pairingRequired]

    /// A goodbye this build shows by the Mac's words: "update", or a reason it does not know (a
    /// kind 22 that did not decode reads as reason "").
    static func isNotice(_ goodbye: Goodbye) -> Bool {
        !knownReasons.contains(goodbye.reason)
    }

    /// The session ended with `goodbye` (nil: no goodbye came). `mac` is what the status line calls
    /// the Mac (its saved name, else its Bonjour name or the address dialled), `device` "iPad" or
    /// "iPhone", `saved` whether the Mac is a saved one (its remote door may be dialled).
    /// `away`: the session ended because this device was away (`awayEnd`); it words an end with no
    /// goodbye, and a goodbye's own words win.
    static func outcome(_ goodbye: Goodbye?, mac: String, device: String, saved: Bool, away: Away? = nil) -> Outcome {
        guard let goodbye else {
            let what = away.map { "The connection to \(mac) ended while \(awayWords($0, device: device))." } ?? "\(mac) disconnected."
            return Outcome(text: saved ? "\(what) Sill will reconnect when it can reach it."
                                       : "\(what) It will reconnect when the Mac is back.",
                           reconnect: true, remoteAllowed: saved, isNotice: false)
        }
        switch goodbye.reason {
        case Goodbye.quit:
            return Outcome(text: "\(mac) quit Sill. This \(device) reconnects when it’s back.",
                           reconnect: true, remoteAllowed: saved, isNotice: false)
        // The Mac's own going: this build's words, and notices (not in `knownReasons`), as "update"
        // is, so they are said whatever the session's state, a remote dial's before its first list too.
        case Goodbye.sleep:
            return Outcome(text: "\(mac) went to sleep. This \(device) reconnects when it wakes.",
                           reconnect: true, remoteAllowed: saved, isNotice: true)
        case Goodbye.shutdown:
            return Outcome(text: "\(mac) is shutting down, restarting or logging out. This \(device) reconnects when it’s back.",
                           reconnect: true, remoteAllowed: saved, isNotice: true)
        case Goodbye.removed:
            return Outcome(text: "\(mac) removed this \(device). To use it again, pair it again.",
                           reconnect: false, remoteAllowed: false, isNotice: false)
        case Goodbye.remoteOff:
            return Outcome(text: "\(mac) turned off Remote Access.", reconnect: true, remoteAllowed: false, isNotice: false)
        case Goodbye.internetOff:
            return Outcome(text: "\(mac) stopped accepting connections from the internet. Connect through your VPN.",
                           reconnect: true, remoteAllowed: false, isNotice: false)
        case Goodbye.busy:
            return Outcome(text: "\(mac) is already serving 8 devices.", reconnect: true, remoteAllowed: saved, isNotice: false)
        case Goodbye.pairingRequired:
            // Only at a home door over TLS, to an unpaired device: a tap on its row asks to pair.
            return Outcome(text: "\(mac) now asks devices to pair. Tap it to pair this \(device).",
                           reconnect: false, remoteAllowed: false, isNotice: false)
        case Goodbye.update:
            // The host always sends its message; these words are for one that does not.
            var own = "Update Sill on this \(device) to keep using \(mac)."
            if let floor = goodbye.minimumVersion.flatMap({ SillVersion($0) }) { own += " It needs version \(floor) or later." }
            return Outcome(text: message(goodbye) ?? own, reconnect: goodbye.reconnect == true, remoteAllowed: saved,
                           storeLink: true, isNotice: true)
        default:
            let reconnect = goodbye.reconnect == true
            let own = reconnect ? "\(mac) closed the connection. Sill will reconnect when it can."
                                : "\(mac) closed the connection. Tap it to try again."
            return Outcome(text: message(goodbye) ?? own, reconnect: reconnect, remoteAllowed: saved, isNotice: true)
        }
    }

    /// This device let the session go: Sill was in the background, or the device locked (iOS said it
    /// was locking the device's data), when the connection ended. The Mac drops a device that stops
    /// reading for 4 s, so such a session ends on its own.
    enum Away: Equatable { case background, locked }

    /// One time in the background with a session up: whether the device locked meanwhile, when Sill
    /// came back to the foreground (`returnedAt`), and whether a pong for a ping sent since then has
    /// arrived (`heardSince`: buffered bytes from before the suspension do not count).
    struct AwaySpell: Equatable {
        var locked = false
        var returnedAt: Double?
        var heardSince = false
    }

    /// Sill entered the background while `connected`. An unconfirmed spell keeps `locked` (the
    /// connection may already be dead from the lock); a confirmed one starts afresh.
    static func enteredBackground(connected: Bool, current: AwaySpell?) -> AwaySpell? {
        guard connected else { return nil }
        if let current, !current.heardSince {
            return AwaySpell(locked: current.locked)
        }
        return AwaySpell()
    }

    /// A pong arrived for a ping sent at `pingSentAt`: counts only once Sill has come back and the
    /// ping was sent since (`returnedAt`), so bytes buffered before the suspension never clear the
    /// spell.
    static func heardPong(pingSentAt: Double, spell: inout AwaySpell?) {
        if let ret = spell?.returnedAt, pingSentAt >= ret { spell?.heardSince = true }
    }

    /// The session ended with `goodbye` after `spell`: away when no goodbye said why and nothing
    /// came from the Mac after the return.
    static func awayEnd(goodbye: Goodbye?, spell: AwaySpell?) -> Away? {
        guard goodbye == nil, let spell, !spell.heardSince else { return nil }
        return spell.locked ? .locked : .background
    }

    /// The reconnect line's note after an away end (DiscoveryPolicy.reconnectLine, the remote dial's).
    static func awayNote(_ away: Away?, device: String) -> String? {
        away.map { "(the connection ended while \(awayWords($0, device: device)))" }
    }

    private static func awayWords(_ away: Away, device: String) -> String {
        away == .locked ? "this \(device) was locked" : "Sill was in the background"
    }

    /// The host's message as the status line shows it: one line of at most `messageLimit`
    /// characters, without control or bidirectional characters; nil when nothing printable is left.
    /// Shown as plain text (SwiftUI's Text of a String): no Markdown, no link from the host.
    static func message(_ goodbye: Goodbye) -> String? {
        let text = SafeText.label(goodbye.message ?? "", limit: messageLimit)
        return text.isEmpty ? nil : text
    }
}
