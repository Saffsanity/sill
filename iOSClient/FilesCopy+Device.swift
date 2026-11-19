import Foundation
import StreamProtocol

/// The device's own words for files and photos (docs/files-plan.md §10): the Files rows of This ‹device›,
/// their footnote, and the chip over the stream that follows a transfer. The reasons' words both ends
/// share are FilesCopy's (StreamProtocol). Pure (Foundation and StreamProtocol): Tests/checks/files reads
/// every line, and which rows show when (`rows`).
enum DeviceFilesCopy {
    /// A stopped transfer's reason that never goes on the wire: the person picked a folder, which this
    /// version does not send (docs/files-plan.md §8.3).
    static let folderReason = "folder"

    // MARK: The rows

    static func sendFiles(mac: String) -> String { "Send Files to \(mac)…" }
    static func sendPhotos(mac: String) -> String { "Send Photos to \(mac)…" }

    /// How the Files rows show for what FilePolicy.deviceOffers says: hidden (nothing to show: the CLI,
    /// a locked Mac, whose header already says why), shown and enabled only at `yes`, shown disabled with
    /// the footnote's reason otherwise.
    struct Rows: Equatable {
        let shown: Bool
        let enabled: Bool
    }

    static func rows(_ offering: FilePolicy.Offering) -> Rows {
        switch offering {
        case .hidden: return Rows(shown: false, enabled: false)
        case .yes: return Rows(shown: true, enabled: true)
        case .older, .off, .notPaired, .busy: return Rows(shown: true, enabled: false)
        }
    }

    /// Under the rows: where the files go, or why the rows are disabled. Nil while they are hidden.
    static func footnote(_ offering: FilePolicy.Offering, mac: String, device: String) -> String? {
        switch offering {
        case .hidden: return nil
        case .yes, .busy:
            return "Files and photos you send go to \(FilesCopy.defaultPlace) on \(mac), or to the folder chosen in Sill’s Settings there. They go as they are: photos and videos as originals."
        case .notPaired:
            return "Files go only between paired devices. Pair this \(device) with \(mac) to send files."
        case .off:
            return "\(mac) doesn’t take files now. Turn on Share files with devices in Sill’s Settings on \(mac)."
        case .older:
            return "To send files, update Sill on \(mac)."
        }
    }

    // MARK: The chip

    /// "“IMG_1204.heic”", or "3 files".
    static func what(_ names: [String]) -> String {
        names.count == 1 ? "“\(names[0])”" : "\(names.count) files"
    }

    /// The chip's first line for a transfer in each phase.
    static func title(_ s: OutgoingFiles, mac: String, device: String) -> String {
        switch s.phase {
        case .preparing: return "Getting \(what(s.names)) ready…"
        case .offering, .sending, .finishing: return "Sending \(what(s.names)) to \(mac)"
        case .done(let t): return saved(t, count: s.names.count, mac: mac)
        case .stopped(let reason, let message, let byPeer, let name):
            return stopped(reason, message: message, byPeer: byPeer, name: name, mac: mac, device: device)
        }
    }

    /// The chip's second line while it runs: what it waits for, or how far it is. Nil once it is over.
    static func detail(_ s: OutgoingFiles, mac: String) -> String? {
        switch s.phase {
        case .preparing: return "Reading the files…"
        case .offering: return "Waiting for \(mac)…"
        case .sending, .finishing: return percent(s.fraction)
        case .done, .stopped: return nil
        }
    }

    /// "42%": rounded down, so it says 100% only once the Mac has written every byte.
    static func percent(_ fraction: Double) -> String {
        let f = fraction.isFinite ? min(max(fraction, 0), 1) : 0
        return "\(Int((f * 100).rounded(.down)))%"
    }

    /// The Mac's `done`: "Saved in Downloads › Sill on Mac mini.", in the Mac's own words for where.
    static func saved(_ t: FileTransfer, count: Int, mac: String) -> String {
        let place = SafeText.label(t.place ?? "", limit: 120)
        let where_ = place.isEmpty ? FilesCopy.defaultPlace : place
        return count == 1 ? "Saved in \(where_) on \(mac)." : "Saved \(count) files in \(where_) on \(mac)."
    }

    /// A stopped transfer's line: the person's own Cancel, a folder, or the reason both ends share
    /// (FilesCopy.reasonLine; one this build does not know by the Mac's own words).
    static func stopped(_ reason: String, message: String?, byPeer: Bool, name: String?, mac: String, device: String) -> String {
        if reason == folderReason {
            return "\(name.map { "“\($0)”" } ?? "That") is a folder. Sill sends files, not folders."
        }
        if reason == FileReason.cancelled.rawValue {
            return byPeer ? "\(mac) stopped the transfer." : "Sending stopped."
        }
        return FilesCopy.reasonLine(reason, mac: mac, device: device, name: name, message: message)
    }

    /// Whether the chip's line is a warning (the triangle): anything stopped but the person's own Cancel.
    static func warns(_ s: OutgoingFiles) -> Bool {
        if case .stopped(let reason, _, let byPeer, _) = s.phase {
            return !(reason == FileReason.cancelled.rawValue && !byPeer)
        }
        return false
    }

    /// VoiceOver's label for the running chip, its value the percentage.
    static func spoken(_ s: OutgoingFiles, mac: String, device: String) -> String {
        let title = title(s, mac: mac, device: device)
        guard let detail = detail(s, mac: mac) else { return title }
        return title + ", " + detail
    }

    /// What VoiceOver is told as a transfer starts, ends or stops: nil for the phases in between.
    static func announcement(_ s: OutgoingFiles, mac: String, device: String) -> String? {
        switch s.phase {
        case .offering: return "Sending \(what(s.names)) to \(mac)."
        case .done, .stopped: return title(s, mac: mac, device: device)
        case .preparing, .sending, .finishing: return nil
        }
    }

    static let cancel = "Cancel"
    static let cancelSpoken = "Cancel sending"
    static let send = "Send"
    /// The Files rows' row while a transfer runs.
    static let stopSending = "Stop Sending"

    /// The Settings panel's line under the Files rows while a transfer runs or just ended: the chip's words
    /// on one line ("Sending “a.pdf” to Mac mini · 42%").
    static func panelLine(_ s: OutgoingFiles, mac: String, device: String) -> String {
        title(s, mac: mac, device: device) + (detail(s, mac: mac).map { " · " + $0 } ?? "")
    }

    // MARK: A file shared into Sill

    /// The chip's question while a session takes files.
    static func sendShared(_ names: [String], mac: String) -> String { "Send \(what(names)) to \(mac)?" }
    /// The connect screen's line while none does.
    static func sharedWaits(_ names: [String]) -> String { "Connect to a Mac to send \(what(names))." }

    /// How long a transfer's end stays on the chip.
    static let resultLifetime = 6.0
}

/// This device's outgoing transfer as the chip and the rows show it (DeviceFiles publishes it at each
/// change). Pure, so the words below are checked with it.
struct OutgoingFiles: Equatable {
    enum Phase: Equatable {
        /// Reading the files' sizes (an iCloud file downloads first).
        case preparing
        /// Offered: waiting for the Mac's answer.
        case offering
        case sending
        /// Every byte went: waiting for the Mac's word that it kept them.
        case finishing
        /// The Mac kept every file: its `done` (where, in its words).
        case done(FileTransfer)
        /// Stopped, by this device or the Mac (`byPeer`), with its reason (a string: one from the Mac
        /// this build may not know, shown by `message`), and the file it was about, if one.
        case stopped(reason: String, message: String?, byPeer: Bool, name: String?)
    }

    /// A number for this transfer, new at each `send` (from 1); `localSerial` for what the client shows before
    /// DeviceFiles has the files (the Photos picker's items loading, or what could not be had of them).
    let serial: Int
    static let localSerial = 0
    var phase: Phase
    /// The files' names as sent, in order.
    let names: [String]
    var total: UInt64
    /// What the Mac has written (its acknowledgements).
    var acked: UInt64
    /// When the phase last changed (systemUptime).
    var since: Double

    var isOver: Bool {
        switch phase {
        case .done, .stopped: return true
        case .preparing, .offering, .sending, .finishing: return false
        }
    }

    /// The share written so far, 0 to 1 (1 for a transfer of no bytes once done).
    var fraction: Double {
        if case .done = phase { return 1 }
        return total == 0 ? 0 : min(1, Double(acked) / Double(total))
    }

    /// Whether the session's own moves wait (from Direct Wireless to the network, up to the cable, home from
    /// away; docs/files-plan.md §8.5): while a transfer runs, since it belongs to the connection it was
    /// offered on and a move would end it. A move off a path that is gone never waits.
    static func holdsMoves(_ out: OutgoingFiles?) -> Bool { out.map { !$0.isOver } ?? false }
}
