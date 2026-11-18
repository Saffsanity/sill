import Foundation

// Files and photos between a device and the Mac (docs/files-plan.md §5): kind 34 carries a file's bytes
// (pull request #66's FileChunk, byte for byte), kind 49 everything else (FileTransfer: the offer, the
// answer, the acknowledgements that pace the sender, each file's SHA-256, the result, a cancel, a pick).
// A device sends either only to a host whose window list says `files` 1 or more, on a session whose
// kind 16 says `sessionPaired`; a host sends either only to a device whose hello says `files` (Hello).
// The rules both ends follow are FilePolicy.swift's.

/// A part of one file of an accepted transfer (kind 34, either way): pull request #66's layout, byte for
/// byte (kept from #189, so #66 can still rebase onto it): the file's id (`UInt32` BE), its name
/// (`UInt16` BE length, then UTF-8), its whole size and this part's offset (`UInt64` BE each), then the
/// bytes. This protocol sends the name empty, since the offer named the file; a reader takes a name it is
/// given and ignores it. Parts of a file come in order, file after file, each at most `maxBytes`.
public enum FileChunk {
    /// The most a receiver takes in one part (#66's): a larger part ends its transfer `damaged`. A sender
    /// of this protocol sends at most `FileFlow.chunkBytes`.
    public static let maxBytes = 512 * 1024
    /// The fixed bytes around the name: the id (4), the name's length (2), the size and the offset (8 each).
    public static let headerBytes = 22

    public static func pack(id: UInt32, name: String, total: UInt64, offset: UInt64, bytes: Data) -> Data {
        let n = Data(name.utf8.prefix(1024))
        var d = Data(capacity: headerBytes + n.count + bytes.count)
        d.appendBigEndian(id)
        d.appendBigEndian(UInt16(n.count))
        d.append(n)
        d.appendBigEndian(total)
        d.appendBigEndian(offset)
        d.append(bytes)
        return d
    }

    public static func unpack(_ d: Data) -> (id: UInt32, name: String, total: UInt64, offset: UInt64, bytes: Data)? {
        guard d.count >= 6 else { return nil }
        let id = d.readBigEndian(UInt32.self, at: 0)
        let n = Int(d.readBigEndian(UInt16.self, at: 4))
        guard d.count >= 6 + n + 16,
              let name = String(data: d.subdata(in: (d.startIndex + 6)..<(d.startIndex + 6 + n)), encoding: .utf8)
        else { return nil }
        let total = d.readBigEndian(UInt64.self, at: 6 + n)
        let offset = d.readBigEndian(UInt64.self, at: 14 + n)
        return (id, name, total, offset, d.subdata(in: (d.startIndex + 22 + n)..<d.endIndex))
    }
}

/// What a kind 49 does (`FileTransfer.op`). On the wire a String, never this enum: an op a build does not
/// know is ignored (`FileTransfer.knownOp` nil), so a later op never fails an older peer.
public enum FileOp: String, CaseIterable, Sendable {
    /// The sender's files, by id, name and size, before any byte (and, from a device, where it let go).
    case offer
    /// The receiver's yes, or no with a reason. No byte moves before it.
    case answer
    /// The receiver has written everything of `file` before `offset`: the sender's window moves on.
    case ack
    /// The sender's last word for `file`: its SHA-256.
    case end
    /// Every file kept: their names as kept, and where.
    case done
    /// Either end stops the transfer: what was partial is deleted, what was kept stays.
    case cancel
    /// A device asks for the Mac's Open panel (Get Files from ‹Mac›…), only to a host that says `files` 2.
    case pick
}

/// Why a transfer is refused or stopped (`FileTransfer.reason`). On the wire a String: a reason a build
/// does not know is shown by the message's own words (`message`), else generic ones (FilesCopy).
public enum FileReason: String, CaseIterable, Sendable {
    case off, notPaired, locked, busy, tooMany, tooBig, noRoom, rate, declined, noAnswer, stalled, damaged, lost
    case cantSave, cantRead, nothingChosen, background
    /// Either end's person stopped it (the chip's Cancel, the menu's Stop Transfer). Not in the plan's list,
    /// which named no reason for a person's own stop.
    case cancelled
}

/// Kind 49, both ways: one JSON shape for every message of a transfer but its bytes (docs/files-plan.md
/// §5.2). `op` says which (FileOp's names); every other field is optional and left out when nil. At most
/// `maxPayload` of JSON, under the host's 1 MiB for a device's message and the device's 4 MiB for a host's.
public struct FileTransfer: Codable, Hashable, Sendable {
    /// One file of an offer: its id (random, unique on the connection: kind 34's id), its name as the
    /// sender has it (the receiver cleans it, FileNames), its exact size, and its type identifier, which
    /// is informational only (never trusted).
    public struct File: Codable, Hashable, Sendable {
        public var id: UInt32
        public var name: String
        public var size: UInt64
        public var type: String?

        public init(id: UInt32, name: String, size: UInt64, type: String? = nil) {
            self.id = id; self.name = name; self.size = size; self.type = type
        }
    }

    /// Where a device's finger let go, as fractions of the picture (a tap's): the files go into the app
    /// under it. Absent: save, never drop.
    public struct Point: Codable, Hashable, Sendable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) { self.x = x; self.y = y }
    }

    public var op: String
    /// Random, chosen by whoever offers (for a pick, by the device; the Mac's offer answers with it).
    public var transfer: UInt32?
    public var files: [File]?
    public var drop: Point?
    /// Mac → device: these answer the device's own pick, so it takes them without asking.
    public var asked: Bool?
    public var accept: Bool?
    public var file: UInt32?
    public var offset: UInt64?
    /// base64url (unpadded) of the file's SHA-256.
    public var sha256: String?
    public var kept: [String]?
    /// Where the files are, in the receiver's words ("Downloads › Sill").
    public var place: String?
    public var droppedInto: String?
    public var dropRefused: String?
    public var reason: String?
    /// The sender's own words for `reason`, shown cleaned (SafeText) when the reader does not know it.
    public var message: String?

    public init(op: String, transfer: UInt32? = nil, files: [File]? = nil, drop: Point? = nil, asked: Bool? = nil,
                accept: Bool? = nil, file: UInt32? = nil, offset: UInt64? = nil, sha256: String? = nil,
                kept: [String]? = nil, place: String? = nil, droppedInto: String? = nil, dropRefused: String? = nil,
                reason: String? = nil, message: String? = nil) {
        self.op = op; self.transfer = transfer; self.files = files; self.drop = drop; self.asked = asked
        self.accept = accept; self.file = file; self.offset = offset; self.sha256 = sha256
        self.kept = kept; self.place = place; self.droppedInto = droppedInto; self.dropRefused = dropRefused
        self.reason = reason; self.message = message
    }

    /// The most a kind 49's JSON may be, either way. An offer of `FilePolicy.maxFiles` files whose names
    /// are cleaned (`FileNames.maxBytes`) fits in less than a third of it.
    public static let maxPayload = 512 * 1024

    /// The op as this build knows it; nil for one it does not (ignored).
    public var knownOp: FileOp? { FileOp(rawValue: op) }
    /// The reason as this build knows it; nil for none or one it does not.
    public var knownReason: FileReason? { reason.flatMap(FileReason.init(rawValue:)) }

    public static func offer(transfer: UInt32, files: [File], drop: Point? = nil, asked: Bool? = nil) -> FileTransfer {
        FileTransfer(op: FileOp.offer.rawValue, transfer: transfer, files: files, drop: drop, asked: asked)
    }
    public static func accepted(transfer: UInt32) -> FileTransfer {
        FileTransfer(op: FileOp.answer.rawValue, transfer: transfer, accept: true)
    }
    public static func refused(transfer: UInt32, reason: FileReason, message: String? = nil) -> FileTransfer {
        FileTransfer(op: FileOp.answer.rawValue, transfer: transfer, accept: false, reason: reason.rawValue, message: message)
    }
    public static func ack(transfer: UInt32, file: UInt32, offset: UInt64) -> FileTransfer {
        FileTransfer(op: FileOp.ack.rawValue, transfer: transfer, file: file, offset: offset)
    }
    public static func end(transfer: UInt32, file: UInt32, sha256: String) -> FileTransfer {
        FileTransfer(op: FileOp.end.rawValue, transfer: transfer, file: file, sha256: sha256)
    }
    public static func done(transfer: UInt32, kept: [String], place: String, droppedInto: String? = nil,
                            dropRefused: String? = nil) -> FileTransfer {
        FileTransfer(op: FileOp.done.rawValue, transfer: transfer, kept: kept, place: place,
                     droppedInto: droppedInto, dropRefused: dropRefused)
    }
    public static func cancel(transfer: UInt32, reason: FileReason, message: String? = nil) -> FileTransfer {
        FileTransfer(op: FileOp.cancel.rawValue, transfer: transfer, reason: reason.rawValue, message: message)
    }
    public static func pick(transfer: UInt32) -> FileTransfer {
        FileTransfer(op: FileOp.pick.rawValue, transfer: transfer)
    }

    /// Its JSON, or nil when that would be more than `maxPayload` (never sent).
    public var payload: Data? {
        let data = Wire.encode(self)
        guard !data.isEmpty, data.count <= Self.maxPayload else { return nil }
        return data
    }

    /// A kind 49's JSON as received: nil when it is more than `maxPayload` or not this shape.
    public static func parse(_ payload: Data) -> FileTransfer? {
        guard payload.count <= maxPayload else { return nil }
        return Wire.decode(FileTransfer.self, from: payload)
    }
}
