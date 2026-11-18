import Foundation
import Network
import StreamProtocol

/// Files from devices (docs/files-plan.md §7): every transfer a paired device offers this Mac, on a queue of
/// its own. The server hands it kinds 34 and 49 from its network queue with the lock's reading at their
/// arrival (`received`), never through the coordinator's `onMessage`, so no part costs the main actor a hop.
/// Here each offer is answered by the rules (FilePolicy.answer, with LockPolicy's judgement of the lock at
/// the reading it arrived at and the reading now), each accepted transfer kept in its ledger (FileReceiver),
/// and every write, hash, mark and move done through FileStore. A transfer stops at a lock, a cut-off, the
/// device leaving, the Mac's switch going off and a quit, and what was partial is deleted then (and what a
/// crash left, before the next transfer into the folder); what was kept stays. Logs carry counts and sizes,
/// never a name (FilesCopy).
///
/// Threading: every decision, write and timer on `sill.files`. The main actor pushes what it knows
/// (`update`: the switch, the folder, each session's name and pairing) and stops transfers (`stop`,
/// `stopAll`); the callbacks (`onOffer`, `onRunning`) come on `sill.files`, and their owners hop.
final class FileHub: @unchecked Sendable {
    /// What the main actor tells the hub, pushed at each change.
    struct Context: Equatable {
        /// Share files with devices, on a host with an identity (none at the CLI's plain door).
        var share = false
        /// Where kept files go.
        var folder = FileStore.defaultDestination
        /// That place in a device's words ("Downloads › Sill").
        var place = FilesCopy.defaultPlace
        /// Each connected session: its name for the log and Where from, and whether its key is on the trust
        /// list now (StreamCoordinator.sessionPaired).
        var peers: [ObjectIdentifier: Peer] = [:]
    }

    struct Peer: Equatable {
        var name: String
        var paired: Bool
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

    let queue = DispatchQueue(label: "sill.files", qos: .utility)
    private let gate: LockGate
    private let sendMessage: (FileTransfer, NWConnection) -> Void
    private var context = Context()
    private var store: FileStore
    private var incoming: [ObjectIdentifier: Incoming] = [:]
    private var arrivals: [ObjectIdentifier: [Double]] = [:]
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
    /// A device's offer: a person at it (DisplayWake). On `sill.files`.
    var onOffer: ((ObjectIdentifier) -> Void)?
    /// How many transfers run now, at each change. On `sill.files`.
    var onRunning: ((Int) -> Void)?

    init(gate: LockGate, folder: URL, testLog: Bool = false, testFree: UInt64? = nil,
         send: @escaping (FileTransfer, NWConnection) -> Void) {
        self.gate = gate
        self.sendMessage = send
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
            for (id, _) in incoming {
                if !new.share { stop(id, .off, tellPeer: true) }
                else if new.peers[id] == nil { stop(id, .lost, tellPeer: false) }
                else if new.peers[id]?.paired != true { stop(id, .notPaired, tellPeer: true) }
            }
            for id in arrivals.keys where new.peers[id] == nil { arrivals[id] = nil }
        }
    }

    /// One session's transfer stops: it left (`lost`, `tellPeer` false), it was cut off (`notPaired`).
    func stop(connection id: ObjectIdentifier, _ reason: FileReason, tellPeer: Bool) {
        queue.async { [self] in
            stop(id, reason, tellPeer: tellPeer)
            if !tellPeer { arrivals[id] = nil }
        }
    }

    /// Every transfer stops: the Mac locked (`locked`), its switch went off (`off`).
    func stopAll(_ reason: FileReason, tellPeer: Bool) {
        queue.async { [self] in for id in Array(incoming.keys) { stop(id, reason, tellPeer: tellPeer) } }
    }

    /// At quit (HostShutdown): every transfer stopped and every partial deleted before the process ends.
    /// Waits for the hub's queue, which never waits for the main thread.
    func quit() {
        queue.sync { [self] in
            for id in Array(incoming.keys) { stop(id, .lost, tellPeer: true) }
            if cleaned.contains(store.destination) { store.cleanLeftovers() }
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
                guard let i = incoming[id], i.receiver.transfer == t.transfer else { return }
                let actions = i.receiver.peerCancelled(t.reason)
                perform(actions, i, id: id, now: now)
            case .pick?:
                // Only a host that says `files` 2 shows its Open panel; this one says 1.
                if testLog { print("Test files: a pick from \(name(id)) ignored (this host gives no files)") }
            case .answer?, .ack?, .done?:
                // Answers to the Mac's own offers: it makes none in this build.
                if testLog { print("Test files: a \(t.op) from \(name(id)) ignored (no transfer of this Mac's)") }
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

    private func name(_ id: ObjectIdentifier) -> String { context.peers[id]?.name ?? "a device" }

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

    private func stop(_ id: ObjectIdentifier, _ reason: FileReason, tellPeer: Bool) {
        guard let i = incoming[id] else { return }
        perform(i.receiver.stop(reason, tellPeer: tellPeer), i, id: id, now: Self.clock())
    }

    private func finished(_ id: ObjectIdentifier, _ i: Incoming) {
        if let s = i.staging { i.store.discard(s); i.staging = nil }
        if incoming[id] === i { incoming[id] = nil }
        running()
    }

    // MARK: The clock

    /// Once a second while a transfer runs: no answer, no progress (FileReceiver.tick).
    private func running() {
        onRunning?(incoming.count)
        if incoming.isEmpty { timer?.cancel(); timer = nil; return }
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(200))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let now = Self.clock()
            for (id, i) in self.incoming { self.perform(i.receiver.tick(now: now), i, id: id, now: now) }
        }
        timer = t
        t.resume()
    }

    // MARK: Test hooks

    /// TEST ONLY, honoured only by a test host (DoorPolicy.isTestHost): SILL_TEST_FILES_DIR (the folder; a
    /// synthetic host's default is its own under $TMPDIR, never ~/Downloads), SILL_TEST_FILES_LOG=1 and
    /// SILL_TEST_FILES_FREE=<bytes>. Their names are in TestHooks, which says when one is ignored.
    struct Hooks: Equatable {
        var folder: URL?
        var log = false
        var free: UInt64?
        var lines: [String] = []
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
        // One line, only when one of them is set: a host's output is otherwise what it was (the CLI's stdout).
        if dir || h.log || h.free != nil {
            h.lines.append("Test files: folder \(h.folder?.path ?? "default")\(h.log ? ", each decision logged" : "")\(h.free.map { ", free space \($0) bytes" } ?? "")")
        }
        return h
    }
}
