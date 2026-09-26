import Foundation
import StreamProtocol

/// What the connect screen says, and whether this device reconnects, when a session ends: with the
/// Mac's goodbye (kind 22), or without one (the connection just ended). One rule for every route,
/// whether or not a window list came (docs/update-notice-plan.md §7.3). Pure: Foundation and
/// StreamProtocol, checked on its own with swiftc.
///
/// The five reasons hosts have sent since remote access keep their words and their reconnects.
/// "update" (a Mac whose device floor is above this device's version, DeviceGate) and any other
/// reason are notices: the host's own words (its `message`, cleaned), shown as the status line, and
/// a reconnect only when the Mac asks for one (`"reconnect":true`); "update" also offers the App
/// Store. Before this rule a reason the device did not know showed "‹Mac› disconnected…" and
/// reconnected at once, so a Mac that refused the device was dialled again and again.
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
    static let knownReasons: Set<String> = [Goodbye.quit, Goodbye.removed, Goodbye.remoteOff, Goodbye.internetOff, Goodbye.busy]

    /// A goodbye this build shows by the Mac's words: "update", or a reason it does not know (a
    /// kind 22 that did not decode reads as reason "").
    static func isNotice(_ goodbye: Goodbye) -> Bool {
        !knownReasons.contains(goodbye.reason)
    }

    /// The session ended with `goodbye` (nil: no goodbye came). `mac` is what the status line calls
    /// the Mac (its saved name, else its Bonjour name or the address dialled), `device` "iPad" or
    /// "iPhone", `saved` whether the Mac is a saved one (its remote door may be dialled).
    static func outcome(_ goodbye: Goodbye?, mac: String, device: String, saved: Bool) -> Outcome {
        guard let goodbye else {
            return Outcome(text: saved ? "\(mac) disconnected. Sill will reconnect when it can reach it."
                                       : "\(mac) disconnected. It will reconnect when the Mac is back.",
                           reconnect: true, remoteAllowed: saved, isNotice: false)
        }
        switch goodbye.reason {
        case Goodbye.quit:
            return Outcome(text: "\(mac) quit Sill. This \(device) reconnects when it’s back.",
                           reconnect: true, remoteAllowed: saved, isNotice: false)
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
