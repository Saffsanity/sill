import Foundation

// The rules of files and photos between a device and the Mac, both ends (docs/files-plan.md §6): who may
// offer and when, how each end answers (FilePolicy), what a name from the other end becomes (FileNames), how
// much of a file may be on its way at once so the picture and the person's input come first (FileFlow),
// each transfer's ledger at its sender and at its receiver (FileSender, FileReceiver: the plan's
// FileTransferState, §6.4), and the words both ends show (FilesCopy). Pure (Foundation only): the Mac's FileHub and FileStore and the device's
// DeviceFiles do only what reads, writes and sends; Tests/checks/files checks this file with StreamProtocol.

public enum FilePolicy {
    /// `WindowList.files` from a host that takes files from a paired device.
    public static let takes = 1
    /// `WindowList.files` from a host that also gives files to one (the Open panel, the menu).
    public static let gives = 2
    /// `Hello.files` from a device that takes files from the Mac.
    public static let deviceTakes = 1
    /// The most files one transfer carries. Folders are not offered in this version.
    public static let maxFiles = 500
    /// The most bytes one transfer carries (100 GB, as Finder counts them).
    public static let maxBytes: UInt64 = 100_000_000_000
    /// What a transfer leaves free on the Mac's volume (2 GB): one that would leave less is refused.
    public static let keepFree: UInt64 = 2_000_000_000
    /// Offers a second from one connection; more are refused `rate`. A cancel never counts.
    public static let offerRate = 2
    /// Incoming transfers running on the Mac at once, from every device.
    public static let macTransfers = 4
    /// How long a sender waits for its offer's answer (the receiver's person deciding, at most).
    public static let answerWait = 60.0
    /// How long a transfer may go without progress before its sender (or receiver) stops it `stalled`.
    public static let stallLimit = 30.0
    /// How long the Mac's Open panel waits for a pick.
    public static let panelLimit = 180.0
    /// How soon after a device's own pick closed it may ask again.
    public static let pickSpacing = 5.0

    // MARK: An offer, as a receiver reads it

    /// An offer as a receiver judges it: its transfer, its files in order, their total (saturating, so a
    /// hostile size never wraps) and, from a device, where it let go.
    public struct Offer: Equatable, Sendable {
        public let transfer: UInt32
        public let files: [FileTransfer.File]
        public let total: UInt64
        public let drop: FileTransfer.Point?
        public let asked: Bool
    }

    /// A kind 49 `offer` as this build takes it: nil when it has no transfer, no files, or one id twice (a
    /// receiver refuses it `damaged` when it names a transfer, and drops it otherwise). A drop point that is
    /// not a number is dropped (saved, never dropped). Its count and total are judged by `answer`.
    public static func offer(_ t: FileTransfer) -> Offer? {
        guard t.knownOp == .offer, let transfer = t.transfer, let files = t.files, !files.isEmpty,
              Set(files.map(\.id)).count == files.count else { return nil }
        var total: UInt64 = 0
        for f in files {
            let (sum, over) = total.addingReportingOverflow(f.size)
            total = over ? .max : sum
        }
        let drop = t.drop.flatMap { $0.x.isFinite && $0.y.isFinite ? $0 : nil }
        return Offer(transfer: transfer, files: files, total: total, drop: drop, asked: t.asked == true)
    }

    // MARK: The device offers

    /// What the device's Files rows say (docs/files-plan.md §9): hidden (nothing to show: a Mac that says
    /// nothing of files and no version, the CLI; or a locked Mac, whose header says why), `older` (update
    /// Sill on the Mac), `off` (its switch), `notPaired`, `busy` (a transfer of this device's runs), or
    /// `yes`.
    public enum Offering: Equatable, Sendable {
        case hidden, older, off, notPaired, busy, yes
    }

    /// `hostFiles`: the last window list's `files`; `hostVersion`: its `hostVersion`; `locked`: its
    /// `locked`; `sessionPaired`: the last kind 16's (nil before one came); `sending`: an outgoing transfer
    /// of this session runs.
    public static func deviceOffers(connected: Bool, hostFiles: Int?, hostVersion: String?, locked: Bool,
                                    sessionPaired: Bool?, sending: Bool) -> Offering {
        guard connected, !locked else { return .hidden }
        guard let files = hostFiles else { return hostVersion == nil ? .hidden : .older }
        guard files >= takes else { return .off }
        guard sessionPaired == true else { return .notPaired }
        return sending ? .busy : .yes
    }

    // MARK: The Mac answers a device's offer

    /// The Mac's answer to a device's offer, first failing wins: Share files with devices off; the session's
    /// key not on the trust list now; the Mac locked or off console, at the reading the offer arrived at or
    /// at the reading now (`locked`, LockPolicy's judgement); past the rate (`rateAdmits` false, from
    /// `admits`); another transfer from this device running, or `macTransfers` on the Mac; more than
    /// `maxFiles` files; more than `maxBytes`; less free space than the total and `keepFree` (`freeSpace`,
    /// read only when everything else passed; nil when it cannot be read, which refuses nothing: the
    /// write's own failure says so). Nil: accept. A name is never a reason: it is cleaned (FileNames).
    public static func answer(_ offer: Offer, shareFiles: Bool, paired: Bool, locked: Bool, rateAdmits: Bool,
                              runningFromDevice: Int, runningOnMac: Int, freeSpace: () -> UInt64?) -> FileReason? {
        guard shareFiles else { return .off }
        guard paired else { return .notPaired }
        guard !locked else { return .locked }
        guard rateAdmits else { return .rate }
        guard runningFromDevice == 0, runningOnMac < macTransfers else { return .busy }
        guard offer.files.count <= maxFiles else { return .tooMany }
        guard offer.total <= maxBytes else { return .tooBig }
        if let free = freeSpace() {
            let (need, over) = offer.total.addingReportingOverflow(keepFree)
            if over || free < need { return .noRoom }
        }
        return nil
    }

    /// The rate of a connection's offers at `now`, after `arrivals` (the times of its earlier offers the
    /// rate took in the last second, whatever `answer` then said of them; never a cancel, which is not
    /// counted at all): whether this one is within `offerRate` a second, and the arrivals to keep (at most
    /// `offerRate`, so a flood costs nothing more).
    public static func admits(arrivals: [Double], now: Double) -> (taken: Bool, kept: [Double]) {
        let recent = arrivals.filter { now - $0 < 1 }
        guard recent.count < offerRate else { return (false, recent) }
        return (true, recent + [now])
    }

    // MARK: The device answers the Mac's offer

    public enum DeviceAnswer: Equatable, Sendable {
        case accept
        /// Wait for the person: Accept, or Decline (`declined`).
        case ask
        case refuse(FileReason)
    }

    /// Another incoming transfer running: `busy`; over `maxFiles` or `maxBytes`: `tooMany`, `tooBig`; files
    /// this device asked for (`asked`): accept; Ask Before Receiving Files on: ask; else accept.
    public static func deviceAnswers(_ offer: Offer, receiving: Bool, askBefore: Bool) -> DeviceAnswer {
        if receiving { return .refuse(.busy) }
        if offer.files.count > maxFiles { return .refuse(.tooMany) }
        if offer.total > maxBytes { return .refuse(.tooBig) }
        if offer.asked { return .accept }
        return askBefore ? .ask : .accept
    }

    // MARK: The Mac offers to a device

    /// Whether the Mac may offer files to a device, nil when it may: its hello said it takes files; the
    /// session is paired; the Mac unlocked; Share files with devices on; no other outgoing transfer to it.
    public static func macOffers(helloFiles: Int?, paired: Bool, locked: Bool, shareFiles: Bool,
                                 sendingToDevice: Bool) -> FileReason? {
        guard shareFiles else { return .off }
        guard (helloFiles ?? 0) >= deviceTakes else { return .off }
        guard paired else { return .notPaired }
        guard !locked else { return .locked }
        return sendingToDevice ? .busy : nil
    }

    /// Whether the Mac shows its Open panel for a device's pick, nil when it does: as `macOffers`, and no
    /// panel already up for any device, and none of this device's closed within `pickSpacing`.
    public static func takesPick(helloFiles: Int?, paired: Bool, locked: Bool, shareFiles: Bool, sendingToDevice: Bool,
                                 panelUp: Bool, lastClosed: Double?, now: Double) -> FileReason? {
        if let why = macOffers(helloFiles: helloFiles, paired: paired, locked: locked, shareFiles: shareFiles,
                               sendingToDevice: sendingToDevice) { return why }
        if panelUp { return .busy }
        if let closed = lastClosed, now - closed < pickSpacing { return .rate }
        return nil
    }
}

// MARK: - Names

/// A file's name from the other end (docs/files-plan.md §6.2): one path component, never hidden, never
/// empty, at most `maxBytes` of UTF-8 with its extension whole, so a number to keep it unique and the
/// volume's 255 bytes always fit. Logs never carry one (FilesCopy).
public enum FileNames {
    /// The most UTF-8 bytes a cleaned name keeps.
    public static let maxBytes = 200
    /// An extension kept whole when a name is cut is at most this many UTF-8 bytes.
    public static let maxExtensionBytes = 16
    /// What an empty name becomes, and what goes in front of a name that starts with a dot.
    public static let fallback = "File"
    /// How many numbers `unique` tries.
    public static let uniqueTries = 9_999

    /// `/`, `:` and NUL become `-`; every other control character (C0, DEL, C1), every format character
    /// (the bidi controls U+202A–U+202E, U+2066–U+2069, U+200E, U+200F and U+061C, the zero-width U+200B–
    /// U+200D and U+FEFF, and the rest of Unicode's invisible Cf) and every line and paragraph separator
    /// removed; NFC; white space trimmed at both ends and dots at the end; a name whose first byte is a dot
    /// gets `fallback` in front (never a hidden file); empty becomes `fallback`; cut to `maxBytes` on a
    /// character boundary, the extension (≤ `maxExtensionBytes`) kept whole. Idempotent.
    public static func clean(_ name: String) -> String {
        var scalars = String.UnicodeScalarView()
        for s in name.unicodeScalars {
            if s.value == 0 || s == "/" || s == ":" { scalars.append("-"); continue }
            switch s.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator: continue
            default: scalars.append(s)
            }
        }
        var out = trimmed(String(scalars).precomposedStringWithCanonicalMapping)
        if out.utf8.first == UInt8(ascii: ".") { out = fallback + out }
        if out.isEmpty { out = fallback }
        out = cut(out)
        return out.isEmpty ? fallback : out
    }

    /// White space at both ends and dots at the end, by scalars, until neither is left.
    static func trimmed(_ s: String) -> String {
        var scalars = Array(s.unicodeScalars)
        while let first = scalars.first, first.properties.isWhitespace { scalars.removeFirst() }
        while let last = scalars.last, last.properties.isWhitespace || last == "." { scalars.removeLast() }
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }

    /// `name`'s extension: what follows its last dot, when that dot is not its first scalar and the
    /// extension is 1 to `maxExtensionBytes` UTF-8 bytes.
    static func split(_ name: String) -> (base: String, ext: String?) {
        let scalars = Array(name.unicodeScalars)
        guard let dot = scalars.lastIndex(of: "."), dot > 0, dot < scalars.count - 1 else { return (name, nil) }
        var base = String.UnicodeScalarView(), ext = String.UnicodeScalarView()
        base.append(contentsOf: scalars[..<dot]); ext.append(contentsOf: scalars[(dot + 1)...])
        let e = String(ext)
        guard e.utf8.count <= maxExtensionBytes else { return (name, nil) }
        return (String(base), e)
    }

    /// At most `maxBytes`, by whole characters, the extension kept; what the cut leaves at the end is
    /// trimmed again.
    static func cut(_ name: String) -> String {
        guard name.utf8.count > maxBytes else { return name }
        let (base, ext) = split(name)
        let budget = ext.map { maxBytes - $0.utf8.count - 1 } ?? maxBytes
        var kept = "", used = 0
        for c in base {
            let n = String(c).utf8.count
            if used + n > budget { break }
            kept.append(c); used += n
        }
        // A first character larger than the budget leaves nothing: never ".ext" (a hidden file).
        if kept.isEmpty, ext != nil { kept = fallback }
        return trimmed(ext.map { kept + "." + $0 } ?? kept)
    }

    /// `name`, or "name 2.ext", "name 3.ext"… whichever `taken` says is free (the folder's own answer: a
    /// volume that ignores case counts "A.pdf" as "a.pdf"). Nil after `uniqueTries`. The move into place
    /// is exclusive anyway, so a name taken in between is never overwritten.
    public static func unique(_ name: String, taken: (String) -> Bool) -> String? {
        if !taken(name) { return name }
        let (base, ext) = split(name)
        for n in 2...(uniqueTries + 1) {
            let candidate = ext.map { "\(base) \(n).\($0)" } ?? "\(name) \(n)"
            if !taken(candidate) { return candidate }
        }
        return nil
    }
}

// MARK: - The window

/// How much of a file may be on its way at once (docs/files-plan.md §6.3): a sender keeps at most a window
/// of bytes beyond the receiver's last acknowledgement, so a tap waits behind at most that much, and the
/// picture never waits behind a file's backlog.
public enum FileFlow {
    /// The most a sender puts in one part.
    public static let chunkBytes = 64 * 1024
    /// At home while the person does nothing: about 100 MB/s at 5 ms round trips.
    public static let homeIdle = 512 * 1024
    /// At home while the person uses the stream, or away while they do nothing.
    public static let shared = 128 * 1024
    /// Away while the person uses the stream, or while the link is behind or stalled: 6.5 Mbit/s at 80 ms.
    public static let tight = 64 * 1024
    /// Input from this device this recently counts as the person using the stream.
    public static let activeFor = 1.0
    /// The Mac's sends wait until the connection holds no more than this of what it was handed.
    public static let idleBytes = 64 * 1024

    public static func window(away: Bool, active: Bool, linkBehind: Bool) -> Int {
        if linkBehind || (away && active) { return tight }
        if away || active { return shared }
        return homeIdle
    }

    /// Whether the person used the stream within `activeFor` of `now` (`lastInput`: their last input).
    public static func active(lastInput: Double?, now: Double) -> Bool {
        guard let last = lastInput else { return false }
        return now - last < activeFor
    }

    /// Whether a part of `count` bytes may go, `inFlight` bytes being unacknowledged: within the window,
    /// or the first when nothing is (so a window smaller than a part never stops a transfer).
    public static func maySend(inFlight: UInt64, count: Int, window: Int) -> Bool {
        inFlight == 0 || inFlight + UInt64(max(0, count)) <= UInt64(max(0, window))
    }

    /// The Mac's own sends to a device: only while its connection holds no more than `idleBytes` of what it
    /// was handed (`pendingBytes`), and never while the device waits for a keyframe or one is still on its
    /// way to it, so a frame never queues behind more than one part and a keyframe never waits for one.
    public static func hostMaySend(pendingBytes: Int, needsKeyframe: Bool, keyframesInFlight: Int) -> Bool {
        pendingBytes <= idleBytes && !needsKeyframe && keyframesInFlight == 0
    }
}

// MARK: - The ledger: a transfer at its receiver

/// One transfer as its receiver keeps it (docs/files-plan.md §6.4): the offer's files, cleaned, what has
/// been written of the one on its way, which are kept, and what to do next. Pure: driven by events (the
/// answer, a part, an end, a finish, a cancel, a stop, the clock), it returns what its owner does, in
/// order. The owner performs `write` and `finish` and, when either fails, skips the actions after it and
/// calls `stop` (cantSave or noRoom). Parts come in order, file after file; anything else ends the
/// transfer `damaged`. Nothing is written before the transfer is accepted, or after it ends.
public struct FileReceiver: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        /// Offered, not answered yet (a device's person deciding; the Mac answers at once).
        case asking
        case receiving
        case done
        /// Stopped, by either end, with its reason (one this build may not know, from the other end).
        case cancelled(String)
    }

    public struct Entry: Equatable, Sendable {
        public let id: UInt32
        /// FileNames.clean of the offer's name.
        public let name: String
        public let size: UInt64
        public fileprivate(set) var written: UInt64 = 0
        /// Its name as kept, once kept.
        public fileprivate(set) var kept: String?
    }

    public enum Action: Equatable, Sendable {
        /// This kind 49 to the sender.
        case send(FileTransfer)
        /// Make this file's staging file, new and empty.
        case open(UInt32)
        /// Write the part's bytes at `offset` of this file's staging file.
        case write(UInt32, offset: UInt64, count: Int)
        /// It is whole: check its size and its SHA-256 against `sha256`, mark it, move it into place under
        /// a free name, and report with `finished`.
        case finish(UInt32, sha256: String)
        /// Delete every staging file of this transfer; what was kept stays.
        case deletePartials
        /// Every file kept, by its name as kept: tell the person.
        case completed([String])
        /// Stopped: tell the person why (`byPeer`: the other end said so).
        case stopped(String, byPeer: Bool)
    }

    /// What became of a file `finish` checked.
    public enum Finish: Equatable, Sendable {
        case kept(String)
        /// Its size or its SHA-256 is not the sender's.
        case damaged
        /// It could not be marked or moved into place (`cantSave`), or the volume is full (`noRoom`).
        case failed(FileReason)
    }

    public let transfer: UInt32
    /// Where kept files are, in the receiver's words (`FileTransfer.place`).
    public let place: String
    public private(set) var files: [Entry]
    public private(set) var phase: Phase = .asking
    /// The file on its way (an index of `files`).
    public private(set) var current = 0
    /// The time of the offer, the answer, or the last part, end or finish.
    public private(set) var lastProgress: Double

    public init(offer: FilePolicy.Offer, place: String, now: Double) {
        transfer = offer.transfer
        self.place = place
        files = offer.files.map { Entry(id: $0.id, name: FileNames.clean($0.name), size: $0.size) }
        lastProgress = now
    }

    public var isOver: Bool {
        switch phase {
        case .done, .cancelled: return true
        case .asking, .receiving: return false
        }
    }

    /// Whether this transfer's parts are being taken (a part for another phase is dropped by its owner).
    public var takesParts: Bool { phase == .receiving }
    /// The names of the files kept so far, in order.
    public var keptNames: [String] { files.compactMap(\.kept) }
    /// What has been written in all, kept files included.
    public var bytesWritten: UInt64 { files.reduce(0) { $0 + $1.written } }
    public var totalBytes: UInt64 { files.reduce(0) { $0 &+ $1.size } }

    public mutating func accept(now: Double) -> [Action] {
        guard phase == .asking else { return [] }
        phase = .receiving
        lastProgress = now
        return [.send(.accepted(transfer: transfer)), .open(files[0].id)]
    }

    public mutating func decline(_ reason: FileReason) -> [Action] {
        guard phase == .asking else { return [] }
        phase = .cancelled(reason.rawValue)
        return [.send(.refused(transfer: transfer, reason: reason)), .stopped(reason.rawValue, byPeer: false)]
    }

    /// A kind 34 for this transfer: the next bytes of the file on its way, or the end of the transfer.
    public mutating func part(id: UInt32, total: UInt64, offset: UInt64, count: Int, now: Double) -> [Action] {
        guard phase == .receiving else { return [] }
        let f = files[current]
        guard id == f.id, total == f.size, offset == f.written, count > 0, count <= FileChunk.maxBytes,
              UInt64(count) <= f.size - f.written else { return stop(.damaged, tellPeer: true) }
        files[current].written += UInt64(count)
        lastProgress = now
        return [.write(id, offset: offset, count: count),
                .send(.ack(transfer: transfer, file: id, offset: offset + UInt64(count)))]
    }

    /// The sender's end of the file on its way: it must be whole, and its SHA-256 well formed.
    public mutating func end(file: UInt32?, sha256: String?, now: Double) -> [Action] {
        guard phase == .receiving else { return [] }
        let f = files[current]
        guard file == f.id, f.written == f.size, let sha = sha256, Base64URL.decode(sha)?.count == 32
        else { return stop(.damaged, tellPeer: true) }
        lastProgress = now
        return [.finish(f.id, sha256: sha)]
    }

    /// What `finish` found for the file on its way: kept, the next one opened or, after the last, `done`.
    public mutating func finished(_ file: UInt32, _ result: Finish, now: Double) -> [Action] {
        guard phase == .receiving, files[current].id == file else { return [] }
        switch result {
        case .damaged: return stop(.damaged, tellPeer: true)
        case .failed(let reason): return stop(reason, tellPeer: true)
        case .kept(let name):
            files[current].kept = name
            current += 1
            lastProgress = now
            if current < files.count { return [.open(files[current].id)] }
            phase = .done
            let names = keptNames
            return [.send(.done(transfer: transfer, kept: names, place: place)), .completed(names)]
        }
    }

    /// The sender's cancel.
    public mutating func peerCancelled(_ reason: String?) -> [Action] {
        guard !isOver else { return [] }
        let why = reason ?? FileReason.lost.rawValue
        phase = .cancelled(why)
        return [.deletePartials, .stopped(why, byPeer: true)]
    }

    /// This end stops it: a lock, a cut-off, a write that failed, the Mac's switch, a quit, the connection
    /// gone (`tellPeer` false then), the person's Cancel.
    public mutating func stop(_ reason: FileReason, tellPeer: Bool) -> [Action] {
        guard !isOver else { return [] }
        phase = .cancelled(reason.rawValue)
        var out: [Action] = [.deletePartials]
        if tellPeer { out.append(.send(.cancel(transfer: transfer, reason: reason))) }
        out.append(.stopped(reason.rawValue, byPeer: false))
        return out
    }

    /// The clock: no answer within `answerWait` (`noAnswer`), no progress within `stallLimit` (`stalled`).
    public mutating func tick(now: Double) -> [Action] {
        switch phase {
        case .asking where now - lastProgress >= FilePolicy.answerWait: return stop(.noAnswer, tellPeer: true)
        case .receiving where now - lastProgress >= FilePolicy.stallLimit: return stop(.stalled, tellPeer: true)
        default: return []
        }
    }
}

// MARK: - The ledger: a transfer at its sender

/// One transfer as its sender keeps it (docs/files-plan.md §6.4): the files by id and size, how much has
/// gone and how much the receiver acknowledged, and what to send next within the window. Pure, as
/// FileReceiver: its owner sends the offer, then asks `next` for a part or an end whenever the window may
/// have room (an answer, an ack, its own send done), reads and sends what it says, and passes on the
/// receiver's messages and the clock.
public struct FileSender: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case offering
        case sending
        /// Every part and end sent: waiting for the receiver's `done`.
        case finishing
        case done
        case cancelled(String)
    }

    public struct Entry: Equatable, Sendable {
        public let id: UInt32
        public let size: UInt64

        public init(id: UInt32, size: UInt64) { self.id = id; self.size = size }
    }

    public enum Action: Equatable, Sendable {
        /// This kind 49 to the receiver.
        case send(FileTransfer)
        /// Read these bytes of this file and send them as one kind 34.
        case sendPart(UInt32, offset: UInt64, count: Int)
        /// All of this file went: send its `end` with the SHA-256 of what was read.
        case sendEnd(UInt32)
        /// The receiver kept every file: its `done`.
        case completed(FileTransfer)
        case stopped(String, byPeer: Bool)
    }

    public let transfer: UInt32
    public let files: [Entry]
    public private(set) var phase: Phase = .offering
    /// The file whose parts go now.
    public private(set) var current = 0
    public private(set) var sentInFile: UInt64 = 0
    public private(set) var sentTotal: UInt64 = 0
    public private(set) var ackedTotal: UInt64 = 0
    public private(set) var offeredAt: Double
    public private(set) var lastProgress: Double
    /// Each file's first byte in the whole transfer.
    private let starts: [UInt64]

    public init(transfer: UInt32, files: [Entry], now: Double) {
        self.transfer = transfer
        self.files = files
        var s: [UInt64] = [], at: UInt64 = 0
        for f in files { s.append(at); at = at &+ f.size }
        starts = s
        offeredAt = now
        lastProgress = now
    }

    public var isOver: Bool {
        switch phase {
        case .done, .cancelled: return true
        case .offering, .sending, .finishing: return false
        }
    }

    public var totalBytes: UInt64 { files.reduce(0) { $0 &+ $1.size } }
    /// Sent and not acknowledged.
    public var inFlight: UInt64 { sentTotal - ackedTotal }

    /// The receiver's answer: accepted, the sending starts (ask `next`); refused, stopped with its reason.
    public mutating func answered(_ t: FileTransfer, now: Double) -> [Action] {
        guard phase == .offering else { return [] }
        if t.accept == true {
            phase = files.isEmpty ? .finishing : .sending
            lastProgress = now
            return []
        }
        let why = t.reason ?? FileReason.declined.rawValue
        phase = .cancelled(why)
        return [.stopped(why, byPeer: true)]
    }

    /// The next part within `window`, or the end of a file all of whose bytes went (a file of no bytes has
    /// only its end); nil when the window is full or nothing is left to send.
    public mutating func next(window: Int, chunk: Int = FileFlow.chunkBytes) -> Action? {
        guard phase == .sending, current < files.count else { return nil }
        let f = files[current]
        if sentInFile < f.size {
            let count = Int(min(UInt64(max(1, chunk)), f.size - sentInFile))
            guard FileFlow.maySend(inFlight: inFlight, count: count, window: window) else { return nil }
            let part = Action.sendPart(f.id, offset: sentInFile, count: count)
            sentInFile += UInt64(count)
            sentTotal += UInt64(count)
            return part
        }
        current += 1
        sentInFile = 0
        if current == files.count { phase = .finishing }
        return .sendEnd(f.id)
    }

    /// The receiver has written everything of `file` before `offset`. An ack of a file not sent yet, past
    /// what was sent, or going back ends the transfer `damaged`.
    public mutating func acked(file: UInt32?, offset: UInt64?, now: Double) -> [Action] {
        guard phase == .sending || phase == .finishing else { return [] }
        guard let file, let offset, let k = files.firstIndex(where: { $0.id == file }), offset <= files[k].size
        else { return stop(.damaged, tellPeer: true) }
        let at = starts[k] + offset
        guard at >= ackedTotal, at <= sentTotal else { return stop(.damaged, tellPeer: true) }
        ackedTotal = at
        lastProgress = now
        return []
    }

    /// The receiver's `done`: only once every end went and every byte was acknowledged, naming every file.
    public mutating func done(_ t: FileTransfer) -> [Action] {
        guard !isOver else { return [] }
        guard phase == .finishing, ackedTotal == sentTotal, sentTotal == totalBytes, t.kept?.count == files.count
        else { return stop(.damaged, tellPeer: true) }
        phase = .done
        return [.completed(t)]
    }

    public mutating func peerCancelled(_ reason: String?) -> [Action] {
        guard !isOver else { return [] }
        let why = reason ?? FileReason.lost.rawValue
        phase = .cancelled(why)
        return [.stopped(why, byPeer: true)]
    }

    public mutating func stop(_ reason: FileReason, tellPeer: Bool) -> [Action] {
        guard !isOver else { return [] }
        phase = .cancelled(reason.rawValue)
        var out: [Action] = []
        if tellPeer { out.append(.send(.cancel(transfer: transfer, reason: reason))) }
        out.append(.stopped(reason.rawValue, byPeer: false))
        return out
    }

    /// The clock: no answer within `answerWait` (`noAnswer`), no acknowledgement within `stallLimit`
    /// (`stalled`).
    public mutating func tick(now: Double) -> [Action] {
        switch phase {
        case .offering where now - offeredAt >= FilePolicy.answerWait: return stop(.noAnswer, tellPeer: true)
        case .sending where now - lastProgress >= FilePolicy.stallLimit,
             .finishing where now - lastProgress >= FilePolicy.stallLimit:
            return stop(.stalled, tellPeer: true)
        default: return []
        }
    }
}

// MARK: - The words

/// The words both ends show for a transfer (docs/files-plan.md §10): the reasons, and the Mac's log lines,
/// which carry counts and sizes and never a name. The device's own rows and chips are in
/// iOSClient/FilesCopy+Device.swift, the Mac's menu and Settings in StatusText and SettingsPanes.
public enum FilesCopy {
    /// Where the Mac keeps files from devices, as its menu, its log and a device say it.
    public static let defaultPlace = "Downloads › Sill"

    /// A reason as the person reads it. `mac`, `device`: the names; `name`: the file it is about, if one;
    /// `message`: the other end's own words for a reason this build does not know (cleaned here).
    public static func reasonLine(_ reason: String, mac: String, device: String, name: String? = nil,
                                  message: String? = nil) -> String {
        let file = name.map { "“\($0)”" } ?? "The file"
        switch FileReason(rawValue: reason) {
        case .off?: return "\(mac) doesn’t take files now."
        case .notPaired?: return "Files go only between paired devices."
        case .locked?: return "\(mac) is locked. Unlock it to send files."
        case .busy?: return "Another transfer with \(mac) is still going. Try again when it’s done."
        case .tooMany?: return "That’s more than \(FilePolicy.maxFiles) files. Send fewer at a time."
        case .tooBig?: return "That’s more than \(FilePolicy.maxBytes / 1_000_000_000) GB. Send less at a time."
        case .noRoom?: return "There isn’t enough room on \(mac) for these files."
        case .rate?: return "Too many at once. Try again in a moment."
        case .declined?: return "\(device) declined the files."
        case .noAnswer?: return "Nobody answered on \(device)."
        case .stalled?: return "The transfer stopped moving. Send it again."
        case .damaged?: return "\(file) didn’t arrive whole. Send it again."
        case .lost?: return "The connection to \(mac) ended. Send it again."
        case .cantSave?: return "\(mac) couldn’t save \(name.map { "“\($0)”" } ?? "the files")."
        case .cantRead?: return "Sill couldn’t read \(name.map { "“\($0)”" } ?? "the file") on this \(device)."
        case .nothingChosen?: return "No files were chosen on \(mac)."
        case .background?: return "Sending stopped when Sill left the screen. Send it again."
        case .cancelled?: return "The transfer was stopped."
        case nil:
            let own = SafeText.label(message ?? "", limit: 200)
            return own.isEmpty ? "\(mac) couldn’t take the files." : own
        }
    }

    // MARK: The Mac's log (counts and sizes, never a name or a byte)

    /// "12.3 MB", "512 KB", "1 byte": decimal, as Finder counts.
    public static func size(_ bytes: UInt64) -> String {
        if bytes == 1 { return "1 byte" }
        if bytes < 1_000 { return "\(bytes) bytes" }
        let units: [(Double, String)] = [(1e12, "TB"), (1e9, "GB"), (1e6, "MB"), (1e3, "KB")]
        let b = Double(bytes)
        for (scale, unit) in units where b >= scale {
            let v = b / scale
            return v < 10 ? String(format: "%.1f", v) + " " + unit : "\(Int(v.rounded())) \(unit)"
        }
        return "\(bytes) bytes"
    }

    static func count(_ n: Int) -> String { n == 1 ? "1 file" : "\(n) files" }

    /// "Files: saved 2 files (12.3 MB) from iPad in Downloads/Sill in 4.1 s."
    public static func savedLine(files: Int, bytes: UInt64, device: String, folder: String, seconds: Double) -> String {
        "Files: saved \(count(files)) (\(size(bytes))) from \(device) in \(folder) in \(String(format: "%.1f", seconds)) s."
    }

    /// "Files: iPad offers 2 files (12.3 MB)."
    public static func offeredLine(files: Int, bytes: UInt64, device: String) -> String {
        "Files: \(device) offers \(count(files)) (\(size(bytes)))."
    }

    /// "Files: the transfer from iPad stopped (the connection ended)." `byPeer`: "iPad cancelled …".
    public static func stoppedLine(_ reason: String, device: String, byPeer: Bool) -> String {
        let why = logReason(reason)
        return byPeer ? "Files: \(device) cancelled (\(why))." : "Files: the transfer from \(device) stopped (\(why))."
    }

    /// "Files: refused 3 offers from devices: not paired (2), locked (1)." (RefusalSummary's line).
    public static func refusedLine(_ counts: [String: Int]) -> String {
        let total = counts.values.reduce(0, +)
        let parts = FileReason.allCases.compactMap { r -> String? in
            guard let n = counts[r.rawValue], n > 0 else { return nil }
            return "\(logReason(r.rawValue)) (\(n))"
        }
        let others = counts.filter { FileReason(rawValue: $0.key) == nil && $0.value > 0 }.map(\.value).reduce(0, +)
        let all = parts + (others > 0 ? ["other (\(others))"] : [])
        return "Files: refused \(total == 1 ? "1 offer" : "\(total) offers") from devices: \(all.joined(separator: ", "))."
    }

    /// A reason in the log's words.
    public static func logReason(_ reason: String) -> String {
        switch FileReason(rawValue: reason) {
        case .off?: return "Share files with devices is off"
        case .notPaired?: return "not paired"
        case .locked?: return "locked"
        case .busy?: return "busy"
        case .tooMany?: return "too many files"
        case .tooBig?: return "too large"
        case .noRoom?: return "not enough room"
        case .rate?: return "too many offers"
        case .declined?: return "declined"
        case .noAnswer?: return "no answer"
        case .stalled?: return "stalled"
        case .damaged?: return "damaged"
        case .lost?: return "the connection ended"
        case .cantSave?: return "could not save"
        case .cantRead?: return "could not read"
        case .nothingChosen?: return "nothing chosen"
        case .background?: return "Sill left the screen"
        case .cancelled?: return "its person stopped it"
        case nil: return "a reason this build does not know"
        }
    }
}
