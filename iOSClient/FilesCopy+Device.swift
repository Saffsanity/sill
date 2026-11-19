import Foundation
import UniformTypeIdentifiers
import StreamProtocol

/// The device's own words for files and photos (docs/files-plan.md §10): the Files rows of This ‹device›,
/// their footnote, and the chip over the stream that follows a transfer either way. The reasons' words both
/// ends share are FilesCopy's (StreamProtocol). Pure (Foundation, UniformTypeIdentifiers and StreamProtocol):
/// Tests/checks/files reads every line, and which rows and which chip show when (`rows`, `chip`).
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

    // MARK: Files from the Mac (docs/files-plan.md §8.4, §9 and §10)

    static func getFiles(mac: String) -> String { "Get Files from \(mac)…" }
    static let askBeforeTitle = "Ask Before Receiving Files"
    static let photosTitle = "Save Photos and Videos to Photos"

    /// Under the receiving rows: where files from the Mac are, whether Sill asks first, and where photos go.
    static func receiveFootnote(askBefore: Bool, photos: Bool, mac: String, device: String) -> String {
        var out = "Files from \(mac) are in the Files app, in On My \(device) › Sill."
        out += askBefore ? " Sill asks before saving files \(mac) sends you; files you get with Get Files come at once."
                         : " Files \(mac) sends you are saved without asking."
        if photos { out += " Photos and videos from \(mac) go to your Photos library." }
        return out
    }

    /// The folder in Documents (On My ‹iPad› › Sill) where files from `mac` go: "From Mac mini", the Mac's name
    /// cleaned as a file's name is (FileNames: one component, never hidden).
    static func folderName(mac: String) -> String {
        let name = FileNames.clean(mac)
        return "From " + (name == FileNames.fallback && mac.isEmpty ? "Mac" : name)
    }

    /// Where they are, in this device's words, which `done` tells the Mac (`FileTransfer.place`).
    static func place(mac: String) -> String { "Files › Sill › " + folderName(mac: mac) }

    /// A photo or a video, by its cleaned name's extension (never the sender's `type`): what Save to Photos
    /// takes.
    static func isPhotoOrVideo(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension
        guard !ext.isEmpty, let type = UTType(filenameExtension: ext) else { return false }
        return type.conforms(to: .image) || type.conforms(to: .movie)
    }

    /// The chip's first line for a transfer from the Mac.
    static func incomingTitle(_ i: IncomingFiles, mac: String, device: String) -> String {
        switch i.phase {
        case .asking: return "\(mac) wants to send you \(what(i.names)) (\(FilesCopy.size(i.total)))."
        case .receiving: return "Receiving \(what(i.names)) from \(mac)"
        case .done(let kept):
            return kept.count == 1 ? "“\(kept[0])” from \(mac) is in Files › Sill." : "\(kept.count) files from \(mac) are in Files › Sill."
        case .stopped(let reason, let message, let byPeer, let name):
            return incomingStopped(reason, message: message, byPeer: byPeer, name: name, names: i.names, mac: mac, device: device)
        }
    }

    /// The chip's second line while it runs; nil otherwise.
    static func incomingDetail(_ i: IncomingFiles) -> String? {
        if case .receiving = i.phase { return percent(i.fraction) }
        return nil
    }

    /// A transfer from the Mac that stopped, in the receiver's words; a reason this end has none of its own
    /// for, in the words both ends share (FilesCopy.reasonLine).
    static func incomingStopped(_ reason: String, message: String?, byPeer: Bool, name: String?, names: [String],
                                mac: String, device: String) -> String {
        let file = name.map { "“\($0)”" } ?? what(names)
        switch FileReason(rawValue: reason) {
        case .cancelled?: return byPeer ? "\(mac) stopped the transfer." : "Receiving stopped."
        case .noRoom? where !byPeer: return "There isn’t enough room on this \(device) for \(file)."
        case .cantSave? where !byPeer: return "Sill couldn’t save \(file) on this \(device)."
        case .lost?: return "The connection to \(mac) ended before \(file) came."
        case .stalled?: return "The transfer from \(mac) stopped moving."
        case .damaged?: return "\(file) didn’t arrive whole."
        case .background?: return "Receiving stopped when Sill left the screen."
        case .locked?: return "\(mac) locked, so the transfer stopped."
        case .off?: return "\(mac) doesn’t share files now."
        default: return FilesCopy.reasonLine(reason, mac: mac, device: device, name: name, message: message)
        }
    }

    /// Whether a transfer from the Mac's end shows on the chip: not this device's own Decline, nor a question
    /// nobody here answered (nobody looked); every other end does.
    static func incomingEndShown(_ i: IncomingFiles) -> Bool {
        if case .stopped(let reason, _, let byPeer, _) = i.phase, !byPeer,
           reason == FileReason.declined.rawValue || reason == FileReason.noAnswer.rawValue { return false }
        return true
    }

    /// Whether its end is a warning: anything stopped but this device's own Cancel.
    static func incomingWarns(_ i: IncomingFiles) -> Bool {
        if case .stopped(let reason, _, let byPeer, _) = i.phase { return !(reason == FileReason.cancelled.rawValue && !byPeer) }
        return false
    }

    /// What VoiceOver is told as a transfer from the Mac is offered, starts, ends or stops.
    static func incomingAnnouncement(_ i: IncomingFiles, mac: String, device: String) -> String? {
        switch i.phase {
        case .asking: return "\(mac) wants to send you \(what(i.names))."
        case .receiving: return "Receiving \(what(i.names)) from \(mac)."
        case .done, .stopped: return incomingEndShown(i) ? incomingTitle(i, mac: mac, device: device) : nil
        }
    }

    static let accept = "Accept"
    static let decline = "Decline"
    static let show = "Show"
    static let cancelReceivingSpoken = "Cancel receiving"

    /// Save to Photos, for the kept files that are photos or videos: "Save to Photos", "Save 3 to Photos".
    static func saveToPhotos(count: Int) -> String { count == 1 ? "Save to Photos" : "Save \(count) to Photos" }

    /// What became of Save to Photos, on the chip.
    enum PhotosResult: Equatable {
        case saved(Int)
        /// Add-only access refused (or restricted).
        case denied
        /// Photos refused the file (a format it does not take), named.
        case failed(String)
    }

    static func photosLine(_ r: PhotosResult) -> String {
        switch r {
        case .saved(let n): return n == 1 ? "Saved to Photos." : "Saved \(n) to Photos."
        case .denied: return "Sill can’t add to Photos. Allow it in Settings › Privacy & Security › Photos."
        case .failed(let name): return "Photos couldn’t take “\(name)”."
        }
    }

    /// Which transfer the chip shows when both directions have one: a question from the Mac first (it waits for
    /// the person), then one going to the Mac, then one coming from it, then whichever ended last.
    enum Chip: Equatable { case none, outgoing, incoming }

    static func chip(out: OutgoingFiles?, incoming: IncomingFiles?) -> Chip {
        if let i = incoming, case .asking = i.phase { return .incoming }
        if let o = out, !o.isOver { return .outgoing }
        if let i = incoming, !i.isOver { return .incoming }
        let shownIn = incoming.flatMap { incomingEndShown($0) ? $0 : nil }
        switch (out, shownIn) {
        case (let o?, let i?): return i.since > o.since ? .incoming : .outgoing
        case (.some, nil): return .outgoing
        case (nil, .some): return .incoming
        case (nil, nil): return .none
        }
    }

    /// Whether the session's own moves wait: while a transfer either way runs, since it belongs to the
    /// connection it began on (docs/files-plan.md §8.5).
    static func movesWait(out: OutgoingFiles?, incoming: IncomingFiles?) -> Bool {
        OutgoingFiles.holdsMoves(out) || IncomingFiles.holdsMoves(incoming)
    }
}

/// A transfer from the Mac to this device as the chip and the rows show it (DeviceFiles publishes it at each
/// change). Pure, so the words above are checked with it.
struct IncomingFiles: Equatable {
    enum Phase: Equatable {
        /// Offered by the Mac's person, not asked for here, and Ask Before Receiving Files is on: Accept or
        /// Decline (the Mac's minute runs).
        case asking
        case receiving
        /// Every file kept, by its name as kept, in order.
        case done([String])
        /// Stopped, by this device or the Mac (`byPeer`), with its reason, and the file it was about.
        case stopped(reason: String, message: String?, byPeer: Bool, name: String?)
    }

    /// A number for this transfer, new at each offer the device takes up (from 1).
    let serial: Int
    var phase: Phase
    /// The offer's names, cleaned as they will be kept (FileNames), in order.
    let names: [String]
    let total: UInt64
    /// What has been written here.
    var written: UInt64
    /// When the phase last changed (systemUptime).
    var since: Double
    /// The files answer this device's own Get Files.
    let asked: Bool

    var isOver: Bool {
        switch phase {
        case .done, .stopped: return true
        case .asking, .receiving: return false
        }
    }

    /// The share written so far, 0 to 1 (1 once done).
    var fraction: Double {
        if case .done = phase { return 1 }
        return total == 0 ? 0 : min(1, Double(written) / Double(total))
    }

    /// The kept files that are photos or videos (Save to Photos).
    var photos: [String] {
        if case .done(let kept) = phase { return kept.filter(DeviceFilesCopy.isPhotoOrVideo) }
        return []
    }

    /// Whether the session's own moves wait for it: while it runs (asked about, or coming).
    static func holdsMoves(_ i: IncomingFiles?) -> Bool { i.map { !$0.isOver } ?? false }
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
