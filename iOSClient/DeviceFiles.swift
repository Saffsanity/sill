import Foundation
import Network
import CryptoKit
// In the app StreamProtocol is its own module; the device-files check compiles this file with
// StreamProtocol's sources and the Mac's FileHub as one module, where there is nothing to import.
#if canImport(StreamProtocol)
import StreamProtocol
#endif

/// This device's files to the Mac (docs/files-plan.md §8): the session's one outgoing transfer, on a
/// queue of its own (`sill.files`), never the main thread. The person picks files (the Files picker),
/// photos (the Photos picker) or shares one into Sill (StreamClient+Files hands them here as `Source`s);
/// their sizes are read first, off this queue (an iCloud file downloads then, under NSFileCoordinator),
/// then the offer goes and, once the Mac accepts, the parts: 64 KiB at a time, read from the file in
/// place and never whole, hashed as they go, each file's end with its SHA-256. The sender's ledger
/// (FileSender) decides what goes, within the acknowledgement window (FileFlow.window: the person using
/// the stream, away from home, the link behind); SessionLink's uplink ledger hands a file's message
/// only into what the person's input, pings and stats leave, and never while a move's fence or hold
/// stands (`sendFile`). So nothing waits anywhere beyond one part, and a tap waits behind at most a
/// window. A transfer belongs to the connection it was offered on: that connection no longer being the
/// session's (a move, the session's end) ends it `lost`, and the Mac deletes what was partial.
///
/// Threading: everything on `queue`, but the sizes' reading (a global queue, so a slow iCloud download
/// never holds a cancel up). `onSnapshot` comes on `queue`; the client hops to the main thread.
/// Foundation, Network and CryptoKit only: checked with swiftc against the Mac's own FileHub on loopback
/// (Tests/checks/device-files).
final class DeviceFiles: @unchecked Sendable {
    /// A file the person picked, dropped or shared, as the outbox reads it.
    struct Source: Equatable {
        /// Where it is: a security-scoped URL from the Files picker or the share sheet (`scoped`), or a
        /// copy of Sill's own (`ownCopy`: a photo's file, an Inbox copy) that is deleted once the transfer
        /// ends, whatever its end.
        let url: URL
        /// Its name as the Mac is told (the Mac cleans it: FileNames).
        let name: String
        var scoped = false
        var ownCopy = false
        /// Its type identifier, informational only.
        var type: String?

        init(url: URL, name: String, scoped: Bool = false, ownCopy: Bool = false, type: String? = nil) {
            self.url = url; self.name = name; self.scoped = scoped; self.ownCopy = ownCopy; self.type = type
        }
    }

    /// What the client knows of the session, pushed at each change (main thread).
    struct Context: Equatable {
        /// The session runs through the remote door.
        var away = false
        /// The Mac reports this device's link behind or stalled (kind 16's `link`).
        var linkBehind = false
    }

    /// The outgoing transfer as the chip and the rows show it (FilesCopy+Device.swift, pure).
    typealias Snapshot = OutgoingFiles

    /// The one outgoing transfer, once its sizes are read.
    private final class Outgoing {
        let serial: Int
        let connection: NWConnection
        let sources: [Source]
        let files: [FileTransfer.File]
        var sender: FileSender
        /// A message that found no room: it goes first once there is.
        var held: Data?
        /// The file being read, its handle, and how far.
        var reading: (index: Int, handle: FileHandle, at: UInt64)?
        var hash = SHA256()
        var snapshot: Snapshot
        var published = 0.0

        init(serial: Int, connection: NWConnection, sources: [Source], files: [FileTransfer.File], sender: FileSender, snapshot: Snapshot) {
            self.serial = serial; self.connection = connection; self.sources = sources; self.files = files
            self.sender = sender; self.snapshot = snapshot
        }
    }

    /// While the sizes are read.
    private struct Preparing {
        let serial: Int
        let connection: NWConnection
        let sources: [Source]
        var snapshot: Snapshot
    }

    let queue = DispatchQueue(label: "sill.files", qos: .utility)
    private let link: SessionLink
    private var context = Context()
    private var preparing: Preparing?
    private var out: Outgoing?
    private var serials = 0
    private var timer: DispatchSourceTimer?
    /// The scoped URLs this transfer opened (`startAccessingSecurityScopedResource`), closed at its end.
    private var accessing: [URL] = []
    /// The transfer as the chip shows it, at each change (throttled to `publishEvery` while parts go).
    /// On `queue`.
    var onSnapshot: ((Snapshot) -> Void)?
    /// TEST ONLY (the device-files check): the window, instead of FileFlow's.
    var windowOverride: Int?
    /// How often the chip's percentage moves at most.
    static let publishEvery = 0.1
    /// How often the clock looks while a transfer runs: no answer, no progress, a fence or hold over.
    static let tickEvery = 0.25

    init(link: SessionLink) {
        self.link = link
        link.onRoom = { [weak self] in self?.roomCame() }
    }

    private static func clock() -> Double { ProcessInfo.processInfo.systemUptime }

    // MARK: From the main thread

    /// The session's context: away from home, the link behind.
    func update(_ new: Context) {
        queue.async { [self] in context = new }
    }

    /// Sends `sources` to the Mac on the session's connection `connection` as one transfer: their sizes
    /// first, then the offer. Refused (the snapshot says why) while another runs.
    func send(_ sources: [Source], on connection: NWConnection) {
        queue.async { [self] in start(sources, on: connection) }
    }

    /// The person's Cancel (the chip's): the Mac is told, what it had is deleted there.
    func cancel() {
        queue.async { [self] in
            if var p = preparing {
                preparing = nil
                p.snapshot.phase = .stopped(reason: FileReason.cancelled.rawValue, message: nil, byPeer: false, name: nil)
                p.snapshot.since = Self.clock()
                cleanUp(p.sources)
                onSnapshot?(p.snapshot)
                return
            }
            guard let o = out else { return }
            perform(o.sender.stop(.cancelled, tellPeer: true), o)
        }
    }

    /// This end stops the transfer: the session ended (`lost`, the Mac not told: its connection's end
    /// tells it), Sill left the screen for good (`background`).
    func stop(_ reason: FileReason, tellPeer: Bool) {
        queue.async { [self] in
            if var p = preparing {
                preparing = nil
                p.snapshot.phase = .stopped(reason: reason.rawValue, message: nil, byPeer: false, name: nil)
                p.snapshot.since = Self.clock()
                cleanUp(p.sources)
                onSnapshot?(p.snapshot)
            }
            guard let o = out else { return }
            perform(o.sender.stop(reason, tellPeer: tellPeer), o)
        }
    }

    // MARK: From the network queue

    /// A kind 49 from the Mac on `connection`: the answer to this device's offer, its acknowledgements,
    /// its `done`, a cancel. Anything else (the Mac's own offers, which this build takes none of) is
    /// ignored.
    func received(_ t: FileTransfer, from connection: NWConnection) {
        queue.async { [self] in
            guard let o = out, o.connection === connection, t.transfer == o.sender.transfer else { return }
            let now = Self.clock()
            switch t.knownOp {
            case .answer?:
                perform(o.sender.answered(t, now: now), o, message: t.message)
                if o.sender.phase == .sending || o.sender.phase == .finishing { phase(o, .sending, now: now) }
                pump(o)
            case .ack?:
                perform(o.sender.acked(file: t.file, offset: t.offset, now: now), o)
                guard out === o else { return }
                o.snapshot.acked = o.sender.ackedTotal
                if now - o.published >= Self.publishEvery { publish(o, now: now) }
                pump(o)
            case .done?:
                perform(o.sender.done(t), o)
            case .cancel?:
                perform(o.sender.peerCancelled(t.reason), o, message: t.message)
            case .offer?, .end?, .pick?:
                break   // the Mac's own transfers: this build takes none (no `Hello.files`)
            case nil:
                break   // an op this build does not know
            }
        }
    }

    /// SessionLink: the connection holds nothing any more after a file's message found no room.
    private func roomCame() {
        queue.async { [self] in if let o = out { pump(o) } }
    }

    // MARK: The transfer

    private func start(_ sources: [Source], on connection: NWConnection) {
        serials += 1
        let serial = serials
        let names = sources.map { FileNames.clean($0.name) }
        let snapshot = Snapshot(serial: serial, phase: .preparing, names: names, total: 0, acked: 0, since: Self.clock())
        // One at a time: the rows and the share sheet's question offer nothing while one runs
        // (FilePolicy.deviceOffers says `busy`), so a second is only a race with its start; it is dropped,
        // and the running one's chip stays.
        guard preparing == nil, out == nil, !sources.isEmpty else {
            for s in sources where s.ownCopy { Self.deleteOwnCopy(s.url) }
            return
        }
        preparing = Preparing(serial: serial, connection: connection, sources: sources, snapshot: snapshot)
        onSnapshot?(snapshot)
        // The sizes, off this queue: a file in iCloud Drive downloads first, and a cancel meanwhile must
        // not wait for it.
        for s in sources where s.scoped {
            if s.url.startAccessingSecurityScopedResource() { accessing.append(s.url) }
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let sized = Self.sizes(sources)
            self?.queue.async { self?.prepared(serial, sized) }
        }
    }

    /// Each source's size, or the first that cannot be read (a folder among them).
    private enum Sized {
        case sizes([UInt64])
        case cantRead(name: String, folder: Bool)
    }

    private static func sizes(_ sources: [Source]) -> Sized {
        var out: [UInt64] = []
        for s in sources {
            if (try? s.url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                return .cantRead(name: FileNames.clean(s.name), folder: true)
            }
            guard let handle = try? openForReading(s.url), let size = try? handle.seekToEnd() else {
                return .cantRead(name: FileNames.clean(s.name), folder: false)
            }
            try? handle.close()
            out.append(size)
        }
        return .sizes(out)
    }

    /// `url` opened for reading under NSFileCoordinator (a file of a file provider, iCloud Drive among
    /// them, is downloaded first). The handle stays good after the coordination ends.
    private static func openForReading(_ url: URL) throws -> FileHandle {
        var coordination: NSError?
        var opened: Result<FileHandle, Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordination) { u in
            opened = Result { try FileHandle(forReadingFrom: u) }
        }
        if let coordination { throw coordination }
        return try opened.get()
    }

    private func prepared(_ serial: Int, _ sized: Sized) {
        guard let p = preparing, p.serial == serial else { return }   // cancelled meanwhile
        preparing = nil
        let now = Self.clock()
        var snapshot = p.snapshot
        snapshot.since = now
        let sizes: [UInt64]
        switch sized {
        case .cantRead(let name, let folder):
            snapshot.phase = .stopped(reason: folder ? DeviceFilesCopy.folderReason : FileReason.cantRead.rawValue, message: nil,
                                      byPeer: false, name: name)
            cleanUp(p.sources)
            onSnapshot?(snapshot)
            return
        case .sizes(let s):
            sizes = s
        }
        let total = sizes.reduce(UInt64(0)) { $0 &+ $1 }
        snapshot.total = total
        // What the Mac would refuse anyway (FilePolicy.answer), said before anything goes.
        let tooMany = sizes.count > FilePolicy.maxFiles, tooBig = total > FilePolicy.maxBytes
        let ids = Self.ids(sizes.count)
        let files = zip(p.sources, zip(ids, sizes)).map { s, f in FileTransfer.File(id: f.0, name: s.name, size: f.1, type: s.type) }
        let transfer = UInt32.random(in: 1 ... .max)
        let offer = FileTransfer.offer(transfer: transfer, files: files)
        guard !tooMany, !tooBig, let payload = offer.payload else {
            snapshot.phase = .stopped(reason: (tooBig ? FileReason.tooBig : .tooMany).rawValue, message: nil, byPeer: false, name: nil)
            cleanUp(p.sources)
            onSnapshot?(snapshot)
            return
        }
        snapshot.phase = .offering
        let sender = FileSender(transfer: transfer, files: files.map { FileSender.Entry(id: $0.id, size: $0.size) }, now: now)
        let o = Outgoing(serial: serial, connection: p.connection, sources: p.sources, files: files, sender: sender, snapshot: snapshot)
        out = o
        o.held = Self.message(.fileTransfer, payload)
        publish(o, now: now)
        startClock()
        pump(o)
    }

    /// `n` file ids: random, never 0, none twice.
    private static func ids(_ n: Int) -> [UInt32] {
        var seen = Set<UInt32>(), out: [UInt32] = []
        while out.count < n {
            let id = UInt32.random(in: 1 ... .max)
            if seen.insert(id).inserted { out.append(id) }
        }
        return out
    }

    private static func message(_ kind: StreamMessageKind, _ payload: Data) -> Data {
        StreamMessage(kind: kind, timestamp: Date().timeIntervalSince1970, isKeyframe: false, payload: payload).serialized()
    }

    /// The window now (FileFlow.window): the person's last input from SessionLink, the context's rest.
    private func window(now: Double) -> Int {
        if let w = windowOverride { return w }
        let active = FileFlow.active(lastInput: link.lastInputAt, now: now)
        return FileFlow.window(away: context.away, active: active, linkBehind: context.linkBehind)
    }

    /// Whatever may go now: what waited for room first, then the sender's next part or end while its
    /// window allows (FileSender.next), each read and hashed as it goes. Stops at the first that finds
    /// no room (SessionLink calls back, or the clock tries again).
    private func pump(_ o: Outgoing) {
        while out === o {
            if let data = o.held {
                switch link.sendFile(data, on: o.connection) {
                case .sent: o.held = nil
                case .later: return
                case .gone: perform(o.sender.stop(.lost, tellPeer: false), o); return
                }
            }
            guard let action = o.sender.next(window: window(now: Self.clock())) else { return }
            switch action {
            case .sendPart(let id, let offset, let count):
                guard let bytes = read(o, file: id, offset: offset, count: count) else {
                    let name = o.files.firstIndex { $0.id == id }.map { o.snapshot.names[$0] }
                    perform(o.sender.stop(.cantRead, tellPeer: true), o, name: name)
                    return
                }
                let size = o.files.first { $0.id == id }?.size ?? 0
                o.held = Self.message(.fileChunk, FileChunk.pack(id: id, name: "", total: size, offset: offset, bytes: bytes))
            case .sendEnd(let id):
                let digest = Base64URL.encode(Data(o.hash.finalize()))
                o.hash = SHA256()
                if let r = o.reading { try? r.handle.close() }
                o.reading = nil
                guard let payload = FileTransfer.end(transfer: o.sender.transfer, file: id, sha256: digest).payload else { return }
                o.held = Self.message(.fileTransfer, payload)
                if o.sender.phase == .finishing { phase(o, .finishing, now: Self.clock()) }
            case .send, .completed, .stopped:
                return   // only `next`'s two come here
            }
        }
    }

    /// `count` bytes of file `id` from `offset`, read in order (a file is opened at its first part and
    /// closed after its last), hashed; nil when they cannot be read whole (the file shrank, or went).
    private func read(_ o: Outgoing, file id: UInt32, offset: UInt64, count: Int) -> Data? {
        guard let index = o.files.firstIndex(where: { $0.id == id }) else { return nil }
        if o.reading?.index != index {
            if let r = o.reading { try? r.handle.close() }
            o.reading = nil
            guard let handle = try? Self.openForReading(o.sources[index].url) else { return nil }
            o.reading = (index, handle, 0)
        }
        guard var r = o.reading, r.at == offset,
              let data = try? r.handle.read(upToCount: count), data.count == count else { return nil }
        r.at += UInt64(count)
        o.reading = r
        o.hash.update(data: data)
        return data
    }

    /// The sender's actions but `next`'s: its kind 49s (a cancel, which goes on the person's lane so it
    /// never waits behind a part), its end.
    private func perform(_ actions: [FileSender.Action], _ o: Outgoing, message: String? = nil, name: String? = nil) {
        for a in actions {
            switch a {
            case .send(let t):
                if let payload = t.payload { link.send(Self.message(.fileTransfer, payload)) }
            case .sendPart, .sendEnd:
                break   // only from `next`, in `pump`
            case .completed(let t):
                o.snapshot.acked = o.sender.ackedTotal
                phase(o, .done(t), now: Self.clock())
                finish(o)
            case .stopped(let reason, let byPeer):
                phase(o, .stopped(reason: reason, message: message, byPeer: byPeer, name: name), now: Self.clock())
                finish(o)
            }
        }
    }

    private func phase(_ o: Outgoing, _ p: Snapshot.Phase, now: Double) {
        guard o.snapshot.phase != p else { return }
        o.snapshot.phase = p
        o.snapshot.since = now
        publish(o, now: now)
    }

    private func publish(_ o: Outgoing, now: Double) {
        o.published = now
        onSnapshot?(o.snapshot)
    }

    /// The transfer is over: its file closed, its scoped URLs let go, its own copies deleted.
    private func finish(_ o: Outgoing) {
        if let r = o.reading { try? r.handle.close() }
        o.reading = nil
        o.held = nil
        cleanUp(o.sources)
        if out === o { out = nil }
        timer?.cancel()
        timer = nil
    }

    private func cleanUp(_ sources: [Source]) {
        for url in accessing { url.stopAccessingSecurityScopedResource() }
        accessing = []
        for s in sources where s.ownCopy { Self.deleteOwnCopy(s.url) }
    }

    /// A copy of Sill's own, and the folder of its own it sits in under the outbox.
    static func deleteOwnCopy(_ url: URL) {
        let fm = FileManager.default
        try? fm.removeItem(at: url)
        let folder = url.deletingLastPathComponent()
        if folder.deletingLastPathComponent().standardizedFileURL == outbox.standardizedFileURL { try? fm.removeItem(at: folder) }
    }

    /// Where copies of Sill's own wait to go (a photo's file, a shared file iOS copied in): tmp/SillOutbox,
    /// one folder for each pick, deleted once its transfer ends and, for what a quit left, at launch.
    static var outbox: URL { FileManager.default.temporaryDirectory.appendingPathComponent("SillOutbox", isDirectory: true) }

    /// At launch: what an earlier run left in the outbox.
    static func cleanOutbox() {
        try? FileManager.default.removeItem(at: outbox)
    }

    // MARK: The clock

    private func startClock() {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + Self.tickEvery, repeating: Self.tickEvery, leeway: .milliseconds(50))
        t.setEventHandler { [weak self] in self?.tick() }
        timer = t
        t.resume()
    }

    /// No answer within a minute, no progress within 30 s (FileSender.tick); the transfer's connection
    /// no longer the session's (`lost`); what waited for a fence or a hold to end tried again.
    private func tick() {
        guard let o = out else { timer?.cancel(); timer = nil; return }
        let now = Self.clock()
        if link.connection !== o.connection {
            perform(o.sender.stop(.lost, tellPeer: false), o)
            return
        }
        perform(o.sender.tick(now: now), o)
        guard out === o else { return }
        if o.snapshot.acked != o.sender.ackedTotal { o.snapshot.acked = o.sender.ackedTotal; publish(o, now: now) }
        pump(o)
    }

    // MARK: For the checks

    /// The outgoing transfer's bytes sent and acknowledged, nil without one. Waits for the queue.
    var progress: (sent: UInt64, acked: UInt64, window: Int)? {
        queue.sync { out.map { ($0.sender.sentTotal, $0.sender.ackedTotal, window(now: Self.clock())) } }
    }
}
