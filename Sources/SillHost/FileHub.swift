import Foundation
import Network
import CryptoKit
import StreamProtocol

/// Files between devices and this Mac (docs/files-plan.md §7), both ways, on a queue of its own.
///
/// From a device: every transfer a paired device offers this Mac. The server hands it kinds 34 and 49 from its
/// network queue with the lock's reading at their arrival (`received`), never through the coordinator's
/// `onMessage`, so no part costs the main actor a hop. Here each offer is answered by the rules (FilePolicy.answer,
/// with LockPolicy's judgement of the lock at the reading it arrived at and the reading now), each accepted
/// transfer kept in its ledger (FileReceiver), and every write, hash, mark and move done through FileStore.
///
/// To a device (docs/files-plan.md §5.4, §7.5): files the Mac's person chose for a device (Sill's menu), or the
/// device's own pick (its Get Files, answered by the Mac's Open panel, `onPick`), offered only to a device whose
/// hello says it takes files, paired, on an unlocked Mac with Share files with devices on (FilePolicy.macOffers,
/// takesPick); each file read in parts here, hashed as it goes, and handed to the server one part at a time
/// (`sendPart`), which holds it while the picture needs the link and says when it went (`room`); the sender's
/// ledger (FileSender) keeps within the device's acknowledgement window (FileFlow.window: away, the person using
/// the stream, the link behind).
///
/// A transfer either way stops at a lock, a cut-off, the device leaving, the Mac's switch going off and a quit, and
/// what was partial is deleted then (and what a crash left, before the next transfer into the folder); what was
/// kept stays. Logs carry counts and sizes, never a name (FilesCopy).
///
/// Threading: every decision, read, write and timer on `sill.files`. The main actor pushes what it knows
/// (`update`: the switch, the folder, each session's name, pairing, hello and route) and starts and stops transfers
/// (`send`, `pickEnded`, `stop`, `stopAll`); the callbacks (`onOffer`, `onPick`, `onPickClosed`, `onRunning`) come
/// on `sill.files`, and their owners hop.
final class FileHub: @unchecked Sendable {
    /// What the main actor tells the hub, pushed at each change.
    struct Context: Equatable {
        /// Share files with devices, on a host with an identity (none at the CLI's plain door).
        var share = false
        /// This host gives files to a device that asks (`WindowList.files` 2: the Open panel, or a test host's
        /// TEST ONLY choice): a pick is shown, else refused `off`.
        var gives = false
        /// Where kept files go.
        var folder = FileStore.defaultDestination
        /// That place in a device's words ("Downloads › Sill").
        var place = FilesCopy.defaultPlace
        /// Each connected session: its name for the log and Where from, whether its key is on the trust list now
        /// (StreamCoordinator.sessionPaired), whether its hello takes files, and what its window reads.
        var peers: [ObjectIdentifier: Peer] = [:]
    }

    struct Peer: Equatable {
        var name: String
        var paired: Bool
        /// Its hello said `files` 1 or more (Hello.files): the Mac may offer it files.
        var takesFiles = false
        /// Through the remote door.
        var away = false
        /// The Mac's judgement of its link: behind or stalled (LinkJudge).
        var linkBehind = false
    }

    /// One transfer on its way from a device.
    private final class Incoming {
        var receiver: FileReceiver
        let connection: NWConnection
        let store: FileStore
        let device: String
        let started: Double
        var staging: FileStore.Staging?

        init(receiver: FileReceiver, connection: NWConnection, store: FileStore, device: String, started: Double) {
            self.receiver = receiver; self.connection = connection; self.store = store; self.device = device; self.started = started
        }
    }

    /// One transfer on its way to a device: the Mac's files, read in parts.
    private final class Outgoing {
        var sender: FileSender
        let connection: NWConnection
        let urls: [URL]
        let files: [FileTransfer.File]
        let device: String
        let started: Double
        /// A part was handed to the server and has not gone to the connection yet (`room` says when).
        var awaitingRoom = false
        /// The file being read, its handle, and how far.
        var reading: (index: Int, handle: FileHandle, at: UInt64)?
        var hash = SHA256()

        init(sender: FileSender, connection: NWConnection, urls: [URL], files: [FileTransfer.File], device: String, started: Double) {
            self.sender = sender; self.connection = connection; self.urls = urls; self.files = files; self.device = device
            self.started = started
        }
    }

    /// A device's pick waiting for the Mac's Open panel (one at a time, for every device).
    private struct Pick {
        let connection: NWConnection
        var id: ObjectIdentifier { ObjectIdentifier(connection) }
        let transfer: UInt32
        let at: Double
    }

    let queue = DispatchQueue(label: "sill.files", qos: .utility)
    private let gate: LockGate
    private let sendMessage: (FileTransfer, NWConnection) -> Void
    private let sendPart: (Data, NWConnection) -> Void
    private let lastInput: (NWConnection) -> Double?
    private var context = Context()
    private var store: FileStore
    private var incoming: [ObjectIdentifier: Incoming] = [:]
    private var outgoing: [ObjectIdentifier: Outgoing] = [:]
    private var arrivals: [ObjectIdentifier: [Double]] = [:]
    private var pick: Pick?
    /// When each device's last pick ended (FilePolicy.pickSpacing).
    private var pickClosed: [ObjectIdentifier: Double] = [:]
    private var timer: DispatchSourceTimer?
    /// The folders whose leftovers this launch has cleaned: each the first time a transfer is offered into
    /// it, never at launch, so a Mac whose devices never send a file never has Sill look into its Downloads
    /// (whether macOS asks about a folder Sill made at an earlier launch is not documented: the plan's §16).
    private var cleaned = Set<URL>()
    private lazy var refusals = RefusalSummary(queue: queue, categories: FileReason.allCases.map(\.rawValue),
                                               format: FilesCopy.refusedLine)
    /// TEST ONLY (SILL_TEST_FILES_LOG=1, a test host): each decision with its sizes, never a name or a byte.
    private let testLog: Bool
    /// TEST ONLY (SILL_TEST_FILES_FREE=<bytes>, a test host): the free space the rule reads.
    private let testFree: UInt64?
    /// A device's offer or pick: a person at it (DisplayWake). On `sill.files`.
    var onOffer: ((ObjectIdentifier) -> Void)?
    /// A device's pick to answer (the Open panel), with its transfer. On `sill.files`.
    var onPick: ((ObjectIdentifier, UInt32) -> Void)?
    /// The pick's panel must close: its time ran out, the device left, the Mac locked, the switch went off. On
    /// `sill.files`.
    var onPickClosed: ((ObjectIdentifier, UInt32) -> Void)?
    /// How many transfers run now, either way, at each change. On `sill.files`.
    var onRunning: ((Int) -> Void)?

    /// `send`: a transfer's kind 49 to a device (StreamServer.sendFileMessage); `sendPart`: one whole kind 34 of
    /// the Mac's to a device (StreamServer.sendFilePart, which calls `room` once it went); `lastInput`: when a
    /// device last sent input (StreamServer.lastInput), by ProcessInfo's uptime.
    init(gate: LockGate, folder: URL, testLog: Bool = false, testFree: UInt64? = nil,
         send: @escaping (FileTransfer, NWConnection) -> Void,
         sendPart: @escaping (Data, NWConnection) -> Void = { _, _ in },
         lastInput: @escaping (NWConnection) -> Double? = { _ in nil }) {
        self.gate = gate
        self.sendMessage = send
        self.sendPart = sendPart
        self.lastInput = lastInput
        self.testLog = testLog
        self.testFree = testFree
        context.folder = folder
        store = FileStore(destination: folder)
    }

    /// The monotonic clock every rule here compares.
    private static func clock() -> Double { ProcessInfo.processInfo.systemUptime }

    // MARK: From the main actor

    /// What the coordinator knows now. A switch turned off stops every transfer (`off`); a session no
    /// longer paired, its own (`notPaired`); a session gone, its own (`lost`, nobody told). A new folder
    /// takes the next transfer; one on its way finishes where it began.
    func update(_ new: Context) {
        queue.async { [self] in
            let old = context
            context = new
            if old.folder != new.folder { store = FileStore(destination: new.folder) }
            for id in Set(incoming.keys).union(outgoing.keys) {
                if !new.share { stop(id, .off, tellPeer: true) }
                else if new.peers[id] == nil { stop(id, .lost, tellPeer: false) }
                else if new.peers[id]?.paired != true { stop(id, .notPaired, tellPeer: true) }
            }
            if let p = pick {
                if !new.share || !new.gives { closePick(.off, tellPeer: true) }
                else if new.peers[p.id] == nil { closePick(.lost, tellPeer: false) }
                else if new.peers[p.id]?.paired != true { closePick(.notPaired, tellPeer: true) }
            }
            for id in arrivals.keys where new.peers[id] == nil { arrivals[id] = nil }
            for id in pickClosed.keys where new.peers[id] == nil { pickClosed[id] = nil }
        }
    }

    /// One session's transfers stop: it left (`lost`, `tellPeer` false), it was cut off (`notPaired`).
    func stop(connection id: ObjectIdentifier, _ reason: FileReason, tellPeer: Bool) {
        queue.async { [self] in
            stop(id, reason, tellPeer: tellPeer)
            if pick?.id == id { closePick(reason, tellPeer: tellPeer) }
            if !tellPeer { arrivals[id] = nil; pickClosed[id] = nil }
        }
    }

    /// Every transfer stops: the Mac locked (`locked`), its switch went off (`off`).
    func stopAll(_ reason: FileReason, tellPeer: Bool) {
        queue.async { [self] in
            for id in Set(incoming.keys).union(outgoing.keys) { stop(id, reason, tellPeer: tellPeer) }
            if pick != nil { closePick(reason, tellPeer: tellPeer) }
        }
    }

    /// At quit (HostShutdown): every transfer stopped and every partial deleted before the process ends.
    /// Waits for the hub's queue (which never waits for the main thread) for a second at most, so a write
    /// stuck on a slow volume never holds the quit; what it leaves goes before the next transfer.
    func quit() {
        let done = DispatchSemaphore(value: 0)
        queue.async { [self] in
            for id in Set(incoming.keys).union(outgoing.keys) { stop(id, .lost, tellPeer: true) }
            if pick != nil { closePick(.lost, tellPeer: true) }
            if cleaned.contains(store.destination) { store.cleanLeftovers() }
            done.signal()
        }
        _ = done.wait(timeout: .now() + 1)
    }

    /// The Mac's files to a device: chosen by the Mac's person (Sill's menu), or, with `pick`, the answer to the
    /// device's own pick (its transfer, so the device takes them without asking). Offered only as
    /// FilePolicy.macOffers allows; a pick refused says why to the device (`cancel`), the menu's in the log.
    func send(_ urls: [URL], to connection: NWConnection, pick transfer: UInt32? = nil) {
        queue.async { [self] in offer(urls, to: connection, pick: transfer) }
    }

    /// The pick's Open panel closed (`urls` the files chosen; nil or none: nothing chosen), or the test host's
    /// choice answered it.
    func pickEnded(_ connection: NWConnection, transfer: UInt32, urls: [URL]?) {
        queue.async { [self] in
            let id = ObjectIdentifier(connection)
            guard let p = pick, p.id == id, p.transfer == transfer else { return }
            pick = nil
            pickClosed[id] = Self.clock()
            guard let urls, !urls.isEmpty else {
                sendMessage(.cancel(transfer: transfer, reason: .nothingChosen), connection)
                if testLog { print("Test files: the pick of \(name(id)) ended with nothing chosen") }
                running()
                return
            }
            offer(urls, to: connection, pick: transfer)
        }
    }

    // MARK: From the network queue

    /// Kind 34 or 49 from `connection`, with the lock's reading as it arrived. `done` is called once it is
    /// dealt with (the server reads on only while little waits here).
    func received(_ message: StreamMessage, from connection: NWConnection, arrived: LockPolicy.Reading,
                  done: @escaping () -> Void) {
        queue.async { [self] in
            handle(message, from: connection, arrived: arrived)
            done()
        }
    }

    /// The server handed `connection` the part it held (StreamServer.onFileRoom): the next may be read.
    func room(_ connection: NWConnection) {
        queue.async { [self] in
            let id = ObjectIdentifier(connection)
            guard let o = outgoing[id], o.connection === connection else { return }
            o.awaitingRoom = false
            pump(o, id: id)
        }
    }

    private func handle(_ m: StreamMessage, from c: NWConnection, arrived: LockPolicy.Reading) {
        let id = ObjectIdentifier(c)
        let now = Self.clock()
        switch m.kind {
        case .fileTransfer:
            guard let t = FileTransfer.parse(m.payload) else { Stats.shared.bump("file.undecodable"); return }
            switch t.knownOp {
            case .offer?:
                offer(t, from: c, arrived: arrived, now: now)
            case .end?:
                guard let i = incoming[id], i.receiver.transfer == t.transfer else { Stats.shared.bump("file.stray"); return }
                if refusedLocked(arrived, cancels: false) { stop(id, .locked, tellPeer: true); return }
                perform(i.receiver.end(file: t.file, sha256: t.sha256, now: now), i, id: id, now: now)
            case .cancel?:
                if let i = incoming[id], i.receiver.transfer == t.transfer {
                    perform(i.receiver.peerCancelled(t.reason), i, id: id, now: now)
                } else if let o = outgoing[id], o.sender.transfer == t.transfer {
                    perform(o.sender.peerCancelled(t.reason), o, id: id)
                } else if let p = pick, p.id == id, p.transfer == t.transfer {
                    // The device gave up waiting for the panel: it closes.
                    closePick(.cancelled, tellPeer: false)
                }
            case .answer?, .ack?, .done?:
                guard let o = outgoing[id], o.sender.transfer == t.transfer else {
                    if testLog { print("Test files: a \(t.op) from \(name(id)) for no transfer of this Mac's ignored") }
                    return
                }
                // A device's word that came while the Mac read locked moves nothing (the lock stops the transfer).
                if refusedLocked(arrived, cancels: false) { stop(id, .locked, tellPeer: true); return }
                switch t.knownOp {
                case .answer?:
                    perform(o.sender.answered(t, now: now), o, id: id)
                    if outgoing[id] === o, o.sender.phase == .sending || o.sender.phase == .finishing {
                        if testLog { print("Test files: \(name(id)) accepted transfer \(o.sender.transfer)") }
                        pump(o, id: id)
                    }
                case .ack?:
                    perform(o.sender.acked(file: t.file, offset: t.offset, now: now), o, id: id)
                    if outgoing[id] === o { pump(o, id: id) }
                default:
                    perform(o.sender.done(t), o, id: id)
                }
            case .pick?:
                pick(t, from: c, arrived: arrived, now: now)
            case nil:
                if testLog { print("Test files: an op this build does not know from \(name(id)) ignored") }
            }
        case .fileChunk:
            guard let p = FileChunk.unpack(m.payload) else { Stats.shared.bump("file.undecodable"); return }
            guard let i = incoming[id], i.receiver.takesParts else { Stats.shared.bump("file.dropped"); return }
            // A part that came while the Mac read locked, or is handled while it does, writes nothing.
            if refusedLocked(arrived, cancels: false) { stop(id, .locked, tellPeer: true); return }
            perform(i.receiver.part(id: p.id, total: p.total, offset: p.offset, count: p.bytes.count, now: now), i, id: id, now: now,
                    bytes: p.bytes)
        default:
            break
        }
    }

    /// Whether the lock refuses a message that arrived at `arrived` and is handled now (LockPolicy.decide).
    private func refusedLocked(_ arrived: LockPolicy.Reading, cancels: Bool) -> Bool {
        LockPolicy.decide(.files(cancels: cancels), arrived: arrived, now: gate.reading, paired: true,
                          offConsoleView: gate.offConsoleView) != .take
    }

    /// Whether the lock refuses what the Mac would start now (an offer to a device, a pick's panel).
    private var lockedNow: Bool { refusedLocked(gate.reading, cancels: false) }

    private func name(_ id: ObjectIdentifier) -> String { context.peers[id]?.name ?? "a device" }

    // MARK: From a device

    private func offer(_ t: FileTransfer, from c: NWConnection, arrived: LockPolicy.Reading, now: Double) {
        let id = ObjectIdentifier(c)
        guard let transfer = t.transfer else { Stats.shared.bump("file.undecodable"); return }
        let rate = FilePolicy.admits(arrivals: arrivals[id] ?? [], now: now)
        arrivals[id] = rate.kept
        guard let o = FilePolicy.offer(t) else { refuse(transfer, .damaged, to: c); return }
        onOffer?(id)
        let paired = context.peers[id]?.paired == true
        let why = FilePolicy.answer(o, shareFiles: context.share, paired: paired, locked: refusedLocked(arrived, cancels: false),
                                    rateAdmits: rate.taken, runningFromDevice: incoming[id] == nil ? 0 : 1,
                                    runningOnMac: incoming.count, freeSpace: { [self] in testFree ?? store.freeSpace() })
        if let why { refuse(transfer, why, to: c); return }
        // What a crash or a quit left half written goes before the first transfer into this folder.
        if cleaned.insert(store.destination).inserted {
            let gone = store.cleanLeftovers()
            if gone > 0 { print("Files: deleted \(gone == 1 ? "1 partial file" : "\(gone) partial files") a transfer left before.") }
        }
        do { try store.prepare() } catch {
            print("Files: could not make the folder for files from devices (\((error as? FileStore.Failure).map { "\($0)" } ?? "\(error)")).")
            refuse(transfer, (error as? FileStore.Failure)?.reason ?? .cantSave, to: c)
            return
        }
        let i = Incoming(receiver: FileReceiver(offer: o, place: context.place, now: now), connection: c, store: store,
                         device: name(id), started: now)
        incoming[id] = i
        print(FilesCopy.offeredLine(files: o.files.count, bytes: o.total, device: i.device))
        if testLog { print("Test files: accepted transfer \(transfer) from \(i.device): \(o.files.count) files, \(o.total) bytes") }
        perform(i.receiver.accept(now: now), i, id: id, now: now)
        running()
    }

    private func refuse(_ transfer: UInt32, _ why: FileReason, to c: NWConnection) {
        sendMessage(.refused(transfer: transfer, reason: why), c)
        refusals.count(why.rawValue)
        if testLog { print("Test files: refused transfer \(transfer) from \(name(ObjectIdentifier(c))): \(why.rawValue)") }
    }

    /// The ledger's actions, in order. A write or a finish that fails skips the rest and stops the
    /// transfer with its reason (FileReceiver's contract).
    private func perform(_ actions: [FileReceiver.Action], _ i: Incoming, id: ObjectIdentifier, now: Double, bytes: Data = Data()) {
        for a in actions {
            switch a {
            case .send(let t):
                sendMessage(t, i.connection)
            case .open(let file):
                do { i.staging = try i.store.open(transfer: i.receiver.transfer, file: file) }
                catch { fail(i, id: id, error, now: now); return }
            case .write(_, _, let count):
                guard let s = i.staging, count == bytes.count else { fail(i, id: id, FileStore.Failure.cantSave("no staging file"), now: now); return }
                do { try i.store.write(bytes, to: s) } catch { fail(i, id: id, error, now: now); return }
            case .finish(let file, let sha):
                guard let s = i.staging, let entry = i.receiver.files.first(where: { $0.id == file }) else {
                    fail(i, id: id, FileStore.Failure.cantSave("no staging file"), now: now); return
                }
                i.staging = nil
                let result: FileReceiver.Finish
                do { result = .kept(try i.store.finish(s, size: entry.size, sha256: sha, name: entry.name, device: i.device)) }
                catch let f as FileStore.Failure { result = f == .damaged ? .damaged : .failed(f.reason) }
                catch { result = .failed(.cantSave) }
                if testLog { print("Test files: file \(file) of transfer \(i.receiver.transfer): \(entry.size) bytes, \(Self.word(result))") }
                perform(i.receiver.finished(file, result, now: now), i, id: id, now: now)
                return
            case .deletePartials:
                if let s = i.staging { i.store.discard(s) }
                i.staging = nil
            case .completed(let names):
                print(FilesCopy.savedLine(files: names.count, bytes: i.receiver.totalBytes, device: i.device,
                                          folder: logFolder(i.store), seconds: now - i.started))
                finished(id, i)
            case .stopped(let reason, let byPeer):
                print(FilesCopy.stoppedLine(reason, device: i.device, byPeer: byPeer))
                finished(id, i)
            }
        }
    }

    private static func word(_ f: FileReceiver.Finish) -> String {
        switch f {
        case .kept: return "kept"
        case .damaged: return "damaged"
        case .failed(let r): return r.rawValue
        }
    }

    /// The destination as the log names it: "Downloads/Sill" for the default, else the folder's own name.
    private func logFolder(_ s: FileStore) -> String {
        s.destination == FileStore.defaultDestination.standardizedFileURL ? "Downloads/Sill" : s.destination.lastPathComponent
    }

    private func fail(_ i: Incoming, id: ObjectIdentifier, _ error: Error, now: Double) {
        let reason = (error as? FileStore.Failure)?.reason ?? .cantSave
        if case FileStore.Failure.cantSave(let detail)? = error as? FileStore.Failure {
            print("Files: could not save a file from \(i.device) (\(detail)).")
        }
        perform(i.receiver.stop(reason, tellPeer: true), i, id: id, now: now)
    }

    /// Both directions of one session stop.
    private func stop(_ id: ObjectIdentifier, _ reason: FileReason, tellPeer: Bool) {
        if let i = incoming[id] { perform(i.receiver.stop(reason, tellPeer: tellPeer), i, id: id, now: Self.clock()) }
        if let o = outgoing[id] { perform(o.sender.stop(reason, tellPeer: tellPeer), o, id: id) }
    }

    private func finished(_ id: ObjectIdentifier, _ i: Incoming) {
        if let s = i.staging { i.store.discard(s); i.staging = nil }
        if incoming[id] === i { incoming[id] = nil }
        running()
    }

    // MARK: To a device

    /// A device's pick (its Get Files): FilePolicy.takesPick, then the Open panel (`onPick`); refused with a
    /// `cancel` that says why. A person at the device (DisplayWake).
    private func pick(_ t: FileTransfer, from c: NWConnection, arrived: LockPolicy.Reading, now: Double) {
        let id = ObjectIdentifier(c)
        guard let transfer = t.transfer else { Stats.shared.bump("file.undecodable"); return }
        // Picks count against the offers' rate: a flood of picks costs nothing more than one of offers.
        let rate = FilePolicy.admits(arrivals: arrivals[id] ?? [], now: now)
        arrivals[id] = rate.kept
        onOffer?(id)
        let peer = context.peers[id]
        var why = FilePolicy.takesPick(helloFiles: peer?.takesFiles == true ? FilePolicy.deviceTakes : nil, paired: peer?.paired == true,
                                       locked: refusedLocked(arrived, cancels: false), shareFiles: context.share && context.gives,
                                       sendingToDevice: outgoing[id] != nil, panelUp: pick != nil, lastClosed: pickClosed[id], now: now)
        if why == nil, !rate.taken { why = .rate }
        if let why {
            sendMessage(.cancel(transfer: transfer, reason: why), c)
            refusals.count(why.rawValue)
            if testLog { print("Test files: refused the pick \(transfer) of \(name(id)): \(why.rawValue)") }
            return
        }
        pick = Pick(connection: c, transfer: transfer, at: now)
        print(FilesCopy.pickLine(device: name(id)))
        onPick?(id, transfer)
        running()
    }

    /// The pick's panel closes without an answer (its time, the device gone, a lock, the switch): the device is
    /// told why, the panel's owner to close it.
    private func closePick(_ reason: FileReason, tellPeer: Bool) {
        guard let p = pick else { return }
        pick = nil
        pickClosed[p.id] = Self.clock()
        if tellPeer { sendMessage(.cancel(transfer: p.transfer, reason: reason), p.connection) }
        if testLog { print("Test files: the pick of \(name(p.id)) closed: \(reason.rawValue)") }
        onPickClosed?(p.id, p.transfer)
        running()
    }

    /// The Mac's offer to a device: its files' sizes (regular files only: a folder or a file that cannot be read
    /// refuses the whole offer, as the device's own does), the rules, then the offer.
    private func offer(_ urls: [URL], to c: NWConnection, pick transfer: UInt32?) {
        let id = ObjectIdentifier(c)
        let now = Self.clock()
        let peer = context.peers[id]
        let refusal: (FileReason) -> Void = { [self] why in
            if let transfer { sendMessage(.cancel(transfer: transfer, reason: why), c) }
            print(FilesCopy.notOfferedLine(why.rawValue, device: name(id)))
            if testLog { print("Test files: not offered to \(name(id)): \(why.rawValue)") }
        }
        if let why = FilePolicy.macOffers(helloFiles: peer?.takesFiles == true ? FilePolicy.deviceTakes : nil, paired: peer?.paired == true,
                                          locked: lockedNow, shareFiles: context.share, sendingToDevice: outgoing[id] != nil) {
            refusal(why); return
        }
        guard !urls.isEmpty else { refusal(.nothingChosen); return }
        var sizes: [UInt64] = []
        for url in urls {
            guard let v = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), v.isRegularFile == true,
                  let size = v.fileSize, size >= 0, FileManager.default.isReadableFile(atPath: url.path) else { refusal(.cantRead); return }
            sizes.append(UInt64(size))
        }
        let total = sizes.reduce(UInt64(0)) { $0 &+ $1 }
        guard sizes.count <= FilePolicy.maxFiles else { refusal(.tooMany); return }
        guard total <= FilePolicy.maxBytes else { refusal(.tooBig); return }
        var seen = Set<UInt32>(), ids: [UInt32] = []
        while ids.count < sizes.count {
            let n = UInt32.random(in: 1 ... .max)
            if seen.insert(n).inserted { ids.append(n) }
        }
        let files = zip(urls, zip(ids, sizes)).map { url, f in FileTransfer.File(id: f.0, name: FileNames.clean(url.lastPathComponent), size: f.1) }
        let number = transfer ?? UInt32.random(in: 1 ... .max)
        let message = FileTransfer.offer(transfer: number, files: files, asked: transfer == nil ? nil : true)
        guard message.payload != nil else { refusal(.tooMany); return }
        let o = Outgoing(sender: FileSender(transfer: number, files: files.map { FileSender.Entry(id: $0.id, size: $0.size) }, now: now),
                         connection: c, urls: urls, files: files, device: name(id), started: now)
        outgoing[id] = o
        sendMessage(message, c)
        print(FilesCopy.offeringLine(files: files.count, bytes: total, device: o.device))
        if testLog { print("Test files: offered transfer \(number) to \(o.device): \(files.count) files, \(total) bytes\(transfer == nil ? "" : ", asked")") }
        running()
    }

    /// The window to this device now (FileFlow.window): away, the person's last input, its link.
    private func window(_ id: ObjectIdentifier, _ c: NWConnection) -> Int {
        let peer = context.peers[id]
        let active = FileFlow.active(lastInput: lastInput(c), now: Self.clock())
        return FileFlow.window(away: peer?.away == true, active: active, linkBehind: peer?.linkBehind == true)
    }

    /// Whatever may go now: the sender's next part (one at a time: the server holds it until the link allows and
    /// says when it went, `room`) or a file's end, within the window.
    private func pump(_ o: Outgoing, id: ObjectIdentifier) {
        while outgoing[id] === o, !o.awaitingRoom {
            guard let action = o.sender.next(window: window(id, o.connection)) else { return }
            switch action {
            case .sendPart(let file, let offset, let count):
                guard let bytes = read(o, file: file, offset: offset, count: count) else {
                    perform(o.sender.stop(.cantRead, tellPeer: true), o, id: id)
                    return
                }
                let size = o.files.first { $0.id == file }?.size ?? 0
                let part = StreamMessage(kind: .fileChunk, timestamp: Date().timeIntervalSince1970, isKeyframe: false,
                                         payload: FileChunk.pack(id: file, name: "", total: size, offset: offset, bytes: bytes))
                o.awaitingRoom = true
                sendPart(part.serialized(), o.connection)
            case .sendEnd(let file):
                let digest = Base64URL.encode(Data(o.hash.finalize()))
                o.hash = SHA256()
                if let r = o.reading { try? r.handle.close() }
                o.reading = nil
                sendMessage(.end(transfer: o.sender.transfer, file: file, sha256: digest), o.connection)
            case .send, .completed, .stopped:
                return   // only `next`'s two come here
            }
        }
    }

    /// `count` bytes of file `id` from `offset`, read in order (a file is opened at its first part and closed
    /// after its last), hashed; nil when they cannot be read whole (the file shrank, or went).
    private func read(_ o: Outgoing, file id: UInt32, offset: UInt64, count: Int) -> Data? {
        guard let index = o.files.firstIndex(where: { $0.id == id }) else { return nil }
        if o.reading?.index != index {
            if let r = o.reading { try? r.handle.close() }
            o.reading = nil
            guard let handle = try? FileHandle(forReadingFrom: o.urls[index]) else { return nil }
            o.reading = (index, handle, 0)
        }
        guard var r = o.reading, r.at == offset,
              let data = try? r.handle.read(upToCount: count), data.count == count else { return nil }
        r.at += UInt64(count)
        o.reading = r
        o.hash.update(data: data)
        return data
    }

    /// The sender's actions but `next`'s: its kind 49s (a cancel), its end.
    private func perform(_ actions: [FileSender.Action], _ o: Outgoing, id: ObjectIdentifier) {
        for a in actions {
            switch a {
            case .send(let t):
                sendMessage(t, o.connection)
            case .sendPart, .sendEnd:
                break   // only from `next`, in `pump`
            case .completed:
                print(FilesCopy.sentLine(files: o.files.count, bytes: o.sender.totalBytes, device: o.device, seconds: Self.clock() - o.started))
                finished(id, o)
            case .stopped(let reason, let byPeer):
                print(FilesCopy.stoppedLine(reason, device: o.device, byPeer: byPeer, toDevice: true))
                finished(id, o)
            }
        }
    }

    private func finished(_ id: ObjectIdentifier, _ o: Outgoing) {
        if let r = o.reading { try? r.handle.close() }
        o.reading = nil
        if outgoing[id] === o { outgoing[id] = nil }
        running()
    }

    // MARK: The clock

    /// Once a second while a transfer runs or a pick waits: no answer, no progress (FileReceiver.tick,
    /// FileSender.tick), the pick's panel past its time (FilePolicy.panelLimit).
    private func running() {
        let count = incoming.count + outgoing.count
        onRunning?(count)
        if count == 0, pick == nil { timer?.cancel(); timer = nil; return }
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(200))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let now = Self.clock()
            for (id, i) in self.incoming { self.perform(i.receiver.tick(now: now), i, id: id, now: now) }
            for (id, o) in self.outgoing {
                self.perform(o.sender.tick(now: now), o, id: id)
                if self.outgoing[id] === o { self.pump(o, id: id) }
            }
            if let p = self.pick, now - p.at >= FilePolicy.panelLimit { self.closePick(.nothingChosen, tellPeer: true) }
        }
        timer = t
        t.resume()
    }

    // MARK: Test hooks

    /// TEST ONLY, honoured only by a test host (DoorPolicy.isTestHost): SILL_TEST_FILES_DIR (the folder; a
    /// synthetic host's default is its own under $TMPDIR, never ~/Downloads), SILL_TEST_FILES_LOG=1,
    /// SILL_TEST_FILES_FREE=<bytes>, SILL_TEST_FILES_PICK=<path>[:<path>…] (a device's pick answered with these
    /// files, no Open panel, and the list says `files` 2) and SILL_TEST_FILES_OFFER='<s> <path>[:<path>…]' (s
    /// seconds after a device whose hello takes files connects, the host offers it these files, as Sill's menu
    /// would). Their names are in TestHooks, which says when one is ignored.
    struct Hooks: Equatable {
        var folder: URL?
        var log = false
        var free: UInt64?
        var pick: [URL]?
        var offer: (seconds: Double, urls: [URL])?
        var lines: [String] = []

        static func == (a: Hooks, b: Hooks) -> Bool {
            a.folder == b.folder && a.log == b.log && a.free == b.free && a.pick == b.pick
                && a.offer?.seconds == b.offer?.seconds && a.offer?.urls == b.offer?.urls && a.lines == b.lines
        }
    }

    static func testHooks(testHost: Bool, synthetic: Bool, environment env: [String: String]) -> Hooks {
        var h = Hooks()
        if synthetic {
            // A synthetic host never writes into this Mac's Downloads.
            let tmp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            h.folder = tmp.appendingPathComponent("sill-test-files-\(getpid())", isDirectory: true)
        }
        guard testHost else { return h }
        var dir = false
        if let d = env["SILL_TEST_FILES_DIR"], !d.isEmpty { h.folder = URL(fileURLWithPath: d, isDirectory: true); dir = true }
        h.log = env["SILL_TEST_FILES_LOG"] == "1"
        if let free = env["SILL_TEST_FILES_FREE"], let n = UInt64(free) { h.free = n }
        let paths = { (s: Substring) in s.split(separator: ":").map { URL(fileURLWithPath: String($0)) } }
        if let p = env["SILL_TEST_FILES_PICK"], !p.isEmpty { h.pick = paths(Substring(p)) }
        if let o = env["SILL_TEST_FILES_OFFER"], let space = o.firstIndex(of: " "), let s = Double(o[..<space]), s >= 0 {
            let urls = paths(o[o.index(after: space)...])
            if !urls.isEmpty { h.offer = (s, urls) }
        }
        // One line, only when one of them is set: a host's output is otherwise what it was (the CLI's stdout).
        if dir || h.log || h.free != nil || h.pick != nil || h.offer != nil {
            var line = "Test files: folder \(h.folder?.path ?? "default")\(h.log ? ", each decision logged" : "")\(h.free.map { ", free space \($0) bytes" } ?? "")"
            if let p = h.pick { line += ", a pick answered with \(p.count == 1 ? "1 file" : "\(p.count) files")" }
            if let o = h.offer { line += ", \(o.urls.count == 1 ? "1 file" : "\(o.urls.count) files") offered \(o.seconds) s after a device connects" }
            h.lines.append(line)
        }
        return h
    }
}
