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
/// when the Mac asks for one (`"reconnect":true`); "update" also offers the App Store. Before this
/// rule a reason the device did not know showed "‹Mac› disconnected…" and reconnected at once, so a
/// Mac that refused the device was dialled again and again.
///
/// The Mac's own going (issue #105): "sleep", "shutdown" and "restart" are notices too (said whatever
/// the session's state, a remote dial's before its first window list included), in this build's
/// words and always with a reconnect, which waits as `went` says (DiscoveryPolicy: the Mac counted as
/// asleep, or a Mac going down left alone until it is listed afresh), and through the remote door
/// only for a session that came that way: at home such a dial would only replace the words while
/// the Mac is away, and the Mac's row brings it back. A device from before them shows the Mac's
/// `message` ("‹Mac› is going to sleep.") and follows its `reconnect`.
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
        /// Said whatever the session's state, before a remote dial's failure rules (RemoteDialPolicy),
        /// which know only the older reasons: the Mac's own words ("update", a reason this build does
        /// not know), or this build's for the Mac going to sleep, shutting down or restarting.
        var isNotice: Bool
        /// How the Mac said it went, for the reconnect's waits (DiscoveryPolicy's `quitAt`,
        /// `asleepAt`, `offAt`): nil for every other end.
        var went: Went? = nil
    }

    /// How the Mac said it went: Sill quit (a Mac row listed since before the goodbye is the
    /// registration that is going), the Mac is going to sleep (the Mac counted as asleep), or it is
    /// shutting down or restarting (a row listed since before it left alone until listed afresh).
    enum Went: Equatable { case quit, asleep, off }

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
    /// "iPhone", `saved` whether the Mac is a saved one (its remote door may be dialled), `remote`
    /// whether the session came through the remote door.
    static func outcome(_ goodbye: Goodbye?, mac: String, device: String, saved: Bool, remote: Bool = false) -> Outcome {
        guard let goodbye else {
            return Outcome(text: saved ? "\(mac) disconnected. Sill will reconnect when it can reach it."
                                       : "\(mac) disconnected. It will reconnect when the Mac is back.",
                           reconnect: true, remoteAllowed: saved, isNotice: false)
        }
        switch goodbye.reason {
        case Goodbye.quit:
            return Outcome(text: "\(mac) quit Sill. This \(device) reconnects when it’s back.",
                           reconnect: true, remoteAllowed: saved, isNotice: false, went: .quit)
        // The Mac's own going: this build's words, and notices (not in `knownReasons`), as "update"
        // is, so they are said whatever the session's state, a remote dial's before its first list too.
        case Goodbye.sleep:
            return Outcome(text: "\(mac) went to sleep. This \(device) reconnects when it wakes.",
                           reconnect: true, remoteAllowed: saved && remote, isNotice: true, went: .asleep)
        case Goodbye.shutdown:
            return Outcome(text: "\(mac) is shutting down. This \(device) reconnects when it’s back.",
                           reconnect: true, remoteAllowed: saved && remote, isNotice: true, went: .off)
        case Goodbye.restart:
            return Outcome(text: "\(mac) is restarting. This \(device) reconnects when it’s back.",
                           reconnect: true, remoteAllowed: saved && remote, isNotice: true, went: .off)
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

    /// The host's message as the status line shows it: one line of at most `messageLimit`
    /// characters, without control or bidirectional characters; nil when nothing printable is left.
    /// Shown as plain text (SwiftUI's Text of a String): no Markdown, no link from the host.
    static func message(_ goodbye: Goodbye) -> String? {
        let text = SafeText.label(goodbye.message ?? "", limit: messageLimit)
        return text.isEmpty ? nil : text
    }
}
