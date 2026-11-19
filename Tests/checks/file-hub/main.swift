import Foundation
import Network
import CryptoKit

// FileHub with FileStore, LockPolicy and the ledgers, fed a device's kinds 34 and 49 as StreamServer hands them on
// (with the lock's reading as they arrived), on a scratch folder of its own (under .build/checks/file-hub: `scratch` below),
// never ~/Downloads; no network (the connections are never started), no host, no encoder. Both ways: a device's files
// kept, and the Mac's files read and handed to the server one part at a time, as the server's room allows.
var failures = 0
var checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
let fm = FileManager.default
/// The run's scratch folder: the one module.py gives it (SILL_CHECK_SCRATCH), which it removes however the run ends (a
/// crash or its time limit too), else .build/checks/file-hub/scratch-<pid> for a binary run by hand. Removed here at
/// every exit (`exit` skips a `defer` at the top level, which left one of them behind each run until 2026-11-19).
let scratch = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SILL_CHECK_SCRATCH"]
                  ?? fm.currentDirectoryPath + "/.build/checks/file-hub/scratch-\(getpid())", isDirectory: true)
try? fm.removeItem(at: scratch)
try! fm.createDirectory(at: scratch, withIntermediateDirectories: true)
atexit { try? FileManager.default.removeItem(at: scratch) }
func sha(_ d: Data) -> String { Base64URL.encode(Data(SHA256.hash(data: d))) }
func listing(_ url: URL) -> [String] { ((try? fm.contentsOfDirectory(atPath: url.path)) ?? []).filter { $0 != FileStore.stagingName }.sorted() }
func staged(_ url: URL) -> [String] { ((try? fm.contentsOfDirectory(atPath: url.appendingPathComponent(FileStore.stagingName).path)) ?? []).sorted() }

/// One hub on its own folder, the messages it sends, and a way to feed it as the server does.
final class Rig {
    let folder: URL
    let gate = LockGate()
    let hub: FileHub
    let parts = PartBox()
    /// The device's last input, as the server stamps it (FileFlow.active).
    let input = InputBox()
    /// The device's picks the hub passed on (onPick).
    let picks = PickBox()
    /// How many transfers run, at each change (onRunning: Sill.app's App Nap hold).
    let running = PickBox()
    init(_ name: String, free: UInt64? = nil) {
        folder = scratch.appendingPathComponent(name, isDirectory: true)
        let box = SentBox(), parts = self.parts, input = self.input, picks = self.picks
        hub = FileHub(gate: gate, folder: folder, testFree: free, send: { t, c in box.add(t, c) },
                      sendPart: { d, c in parts.add(d, c) }, lastInput: { _ in input.at })
        hub.onPick = { id, transfer in picks.add(id, transfer) }
        let running = self.running
        hub.onRunning = { n in running.add(ObjectIdentifier(running), UInt32(n)) }
        self.box = box
    }
    let box: SentBox
    func feed(_ kind: StreamMessageKind, _ payload: Data, from c: NWConnection, arrived: LockPolicy.Reading = .unlocked) {
        let done = DispatchSemaphore(value: 0)
        hub.received(StreamMessage(kind: kind, timestamp: 0, isKeyframe: false, payload: payload), from: c, arrived: arrived) { done.signal() }
        done.wait()
    }
    func offer(_ t: FileTransfer, from c: NWConnection, arrived: LockPolicy.Reading = .unlocked) { feed(.fileTransfer, t.payload!, from: c, arrived: arrived) }
    func part(_ id: UInt32, total: UInt64, offset: UInt64, _ bytes: Data, from c: NWConnection, arrived: LockPolicy.Reading = .unlocked) {
        feed(.fileChunk, FileChunk.pack(id: id, name: "", total: total, offset: offset, bytes: bytes), from: c, arrived: arrived)
    }
    func flush() { hub.queue.sync {} }
    var sent: [FileTransfer] { flush(); return box.all.map(\.0) }
    func last(_ op: FileOp) -> FileTransfer? { sent.last { $0.knownOp == op } }
    func context(share: Bool = true, gives: Bool = false, takers: Set<NWConnection> = [], away: Bool = false,
                 peers: [NWConnection: (String, Bool)]) {
        var c = FileHub.Context()
        c.share = share; c.gives = gives; c.folder = folder; c.place = "Downloads › Sill"
        for (conn, (name, paired)) in peers {
            c.peers[ObjectIdentifier(conn)] = FileHub.Peer(name: name, paired: paired, takesFiles: takers.contains(conn), away: away)
        }
        hub.update(c); flush()
    }
}
final class PartBox {
    private let lock = NSLock()
    private var items: [(Data, ObjectIdentifier)] = []
    func add(_ d: Data, _ c: NWConnection) { lock.lock(); items.append((d, ObjectIdentifier(c))); lock.unlock() }
    var all: [(Data, ObjectIdentifier)] { lock.lock(); defer { lock.unlock() }; return items }
    /// Each part as the device reads it: its file, total, offset and bytes.
    var unpacked: [(id: UInt32, total: UInt64, offset: UInt64, bytes: Data)] {
        all.compactMap { d, _ in
            guard let h = StreamMessage.parseHeader(d), h.kind == .fileChunk,
                  let p = FileChunk.unpack(d.subdata(in: (d.startIndex + StreamMessage.headerLength)..<d.endIndex)) else { return nil }
            return (p.id, p.total, p.offset, p.bytes)
        }
    }
}
final class InputBox {
    private let lock = NSLock()
    private var value: Double?
    var at: Double? { get { lock.lock(); defer { lock.unlock() }; return value } set { lock.lock(); value = newValue; lock.unlock() } }
}
final class PickBox {
    private let lock = NSLock()
    private var items: [(ObjectIdentifier, UInt32)] = []
    func add(_ id: ObjectIdentifier, _ t: UInt32) { lock.lock(); items.append((id, t)); lock.unlock() }
    var all: [(ObjectIdentifier, UInt32)] { lock.lock(); defer { lock.unlock() }; return items }
}
final class SentBox {
    private let lock = NSLock()
    private var items: [(FileTransfer, ObjectIdentifier)] = []
    func add(_ t: FileTransfer, _ c: NWConnection) { lock.lock(); items.append((t, ObjectIdentifier(c))); lock.unlock() }
    var all: [(FileTransfer, ObjectIdentifier)] { lock.lock(); defer { lock.unlock() }; return items }
}
func connection() -> NWConnection { NWConnection(host: "127.0.0.1", port: 9, using: .tcp) }
extension NWConnection: @retroactive Hashable {
    public static func == (a: NWConnection, b: NWConnection) -> Bool { a === b }
    public func hash(into h: inout Hasher) { h.combine(ObjectIdentifier(self)) }
}

/// A whole transfer from `c`: the offer, every part in 64 KiB, each end. Returns the files' contents by id.
@discardableResult
func send(_ rig: Rig, _ files: [(UInt32, String, Data)], transfer: UInt32, from c: NWConnection) -> FileTransfer? {
    rig.offer(.offer(transfer: transfer, files: files.map { .init(id: $0.0, name: $0.1, size: UInt64($0.2.count)) }), from: c)
    guard rig.last(.answer)?.accept == true else { return rig.last(.answer) }
    for (id, _, data) in files {
        var at = 0
        while at < data.count {
            let n = min(65_536, data.count - at)
            rig.part(id, total: UInt64(data.count), offset: UInt64(at), data.subdata(in: at..<(at + n)), from: c)
            at += n
        }
        rig.offer(.end(transfer: transfer, file: id, sha256: sha(data)), from: c)
    }
    return rig.sent.last
}

// MARK: - A transfer kept whole

let big = Data((0..<300_000).map { UInt8($0 % 249) })
do {
    let rig = Rig("whole")
    let ipad = connection()
    rig.context(peers: [ipad: ("iPad (iPad14,1)", true)])
    let last = send(rig, [(1, "../report:final.pdf", big), (2, "empty", Data()), (3, ".hidden", Data("abc".utf8))], transfer: 7, from: ipad)
    check(rig.sent.first.map { $0.knownOp == .answer && $0.accept == true && $0.transfer == 7 } == true, "the offer accepted at once")
    let acks = rig.sent.filter { $0.knownOp == .ack }
    check(acks.count == 6 && acks.last.map { $0.file == 3 && $0.offset == 3 } == true, "an ack for each part, the last at the last byte: \(acks.count)")
    check(last.map { $0.knownOp == .done && $0.kept == ["File..-report-final.pdf", "empty", "File.hidden"] && $0.place == "Downloads › Sill" } == true,
          "done, with the names as kept and the place: \(String(describing: last))")
    check(listing(rig.folder) == ["File..-report-final.pdf", "File.hidden", "empty"], "three files kept: \(listing(rig.folder))")
    check((try? Data(contentsOf: rig.folder.appendingPathComponent("File..-report-final.pdf"))) == big, "byte for byte")
    check(staged(rig.folder).isEmpty, "nothing left in the staging folder")
    let q = (try? rig.folder.appendingPathComponent("empty").resourceValues(forKeys: [.quarantinePropertiesKey]))?.quarantineProperties
    check((q?["LSQuarantineAgentName"] as? String) == "Sill", "quarantined with Sill as the agent")
    // The same names again: numbered.
    send(rig, [(1, "empty", Data())], transfer: 8, from: ipad)
    check(rig.last(.done)?.kept == ["empty 2"], "the same name again: empty 2")
}

// MARK: - Refusals, in the rule's order, nothing written

do {
    let rig = Rig("refusals")
    let paired = connection(), stranger = connection()
    rig.context(peers: [paired: ("iPad", true), stranger: ("iPhone", false)])
    rig.offer(.offer(transfer: 1, files: [.init(id: 1, name: "a", size: 3)]), from: stranger)
    check(rig.last(.answer).map { $0.accept == false && $0.reason == "notPaired" } == true, "an unpaired session: notPaired")
    let ghost = connection()
    rig.offer(.offer(transfer: 2, files: [.init(id: 1, name: "a", size: 3)]), from: ghost)
    check(rig.last(.answer)?.reason == "notPaired", "a session the coordinator never named: notPaired")
    rig.offer(.offer(transfer: 3, files: [.init(id: 1, name: "a", size: 3)]), from: paired, arrived: .screenLocked)
    check(rig.last(.answer)?.reason == "locked", "an offer that arrived while the Mac read locked: locked, though it is unlocked now")
    rig.gate.set(.offConsole)
    rig.offer(.offer(transfer: 4, files: [.init(id: 1, name: "a", size: 3)]), from: paired)
    check(rig.last(.answer)?.reason == "locked", "off console: locked")
    rig.gate.set(.unlocked)
    rig.context(share: false, peers: [paired: ("iPad", true)])
    rig.offer(.offer(transfer: 5, files: [.init(id: 1, name: "a", size: 3)]), from: paired)
    check(rig.last(.answer)?.reason == "off", "the switch off: off")
    rig.context(peers: [paired: ("iPad", true)])
    rig.offer(FileTransfer(op: "offer", transfer: 6, files: [.init(id: 1, name: "a", size: 3), .init(id: 1, name: "b", size: 3)]), from: paired)
    check(rig.last(.answer)?.reason == "damaged", "an offer with one id twice: refused damaged")
    check(listing(rig.folder).isEmpty && staged(rig.folder).isEmpty, "nothing written for any of them")
    let full = Rig("full", free: 1_000)
    full.context(peers: [paired: ("iPad", true)])
    full.offer(.offer(transfer: 1, files: [.init(id: 1, name: "a", size: 3)]), from: paired)
    check(full.last(.answer)?.reason == "noRoom", "1,000 bytes free: noRoom")
}

// MARK: - The rate, busy, a part with no offer, another total

do {
    let rig = Rig("rate")
    let ipad = connection()
    rig.context(peers: [ipad: ("iPad", true)])
    for t in 0..<10 { rig.offer(.offer(transfer: UInt32(100 + t), files: [.init(id: 1, name: "f", size: 5)]), from: ipad) }
    let answers = rig.sent.filter { $0.knownOp == .answer }
    check(answers.count == 10 && answers[0].accept == true && answers[1].reason == "busy"
          && answers[2...].allSatisfy { $0.reason == "rate" }, "ten offers at once: one taken, one busy, eight past the rate: \(answers.map { $0.reason ?? "yes" })")
    let other = connection()
    rig.context(peers: [ipad: ("iPad", true), other: ("iPhone", true)])
    rig.part(9, total: 5, offset: 0, Data("hello".utf8), from: other)
    check(rig.sent.filter { $0.knownOp == .ack }.isEmpty && listing(rig.folder).isEmpty, "a part with no transfer: dropped, nothing written")
    rig.part(1, total: 6, offset: 0, Data("hello".utf8), from: ipad)
    check(rig.last(.cancel)?.reason == "damaged" && staged(rig.folder).isEmpty, "a part of another total: cancelled damaged, its partial deleted")
}

// MARK: - Stops mid-transfer: a lock, the switch, a cut-off, the device leaving, a quit

func midway(_ rig: Rig, _ c: NWConnection, transfer: UInt32) {
    rig.offer(.offer(transfer: transfer, files: [.init(id: 1, name: "big.bin", size: UInt64(big.count))]), from: c)
    rig.part(1, total: UInt64(big.count), offset: 0, big.subdata(in: 0..<65_536), from: c)
}
do {
    // A session of its own for each stop: the rate takes two offers a second from one connection.
    let rig = Rig("stops")
    var peers: [NWConnection: (String, Bool)] = [:]
    func fresh(paired: Bool = true) -> NWConnection {
        let c = connection(); peers[c] = ("iPad", paired); rig.context(peers: peers); return c
    }
    var c = fresh()
    midway(rig, c, transfer: 1)
    check(staged(rig.folder).count == 1, "one partial while it is on its way")
    rig.part(1, total: UInt64(big.count), offset: 65_536, big.subdata(in: 65_536..<131_072), from: c, arrived: .screenLocked)
    check(rig.last(.cancel)?.reason == "locked" && staged(rig.folder).isEmpty && listing(rig.folder).isEmpty,
          "a part that arrived while the Mac read locked: cancelled locked, the partial deleted")
    c = fresh()
    midway(rig, c, transfer: 2)
    rig.hub.stopAll(.locked, tellPeer: true); rig.flush()
    check(rig.last(.cancel).map { $0.transfer == 2 && $0.reason == "locked" } == true && staged(rig.folder).isEmpty, "the Mac locks: cancelled, deleted")
    c = fresh()
    midway(rig, c, transfer: 3)
    rig.context(share: false, peers: peers)
    check(rig.last(.cancel).map { $0.transfer == 3 && $0.reason == "off" } == true && staged(rig.folder).isEmpty, "the switch off: cancelled off, deleted")
    c = fresh()
    midway(rig, c, transfer: 4)
    peers[c] = ("iPad", false); rig.context(peers: peers)
    check(rig.last(.cancel).map { $0.transfer == 4 && $0.reason == "notPaired" } == true && staged(rig.folder).isEmpty,
          "removed from the trust list: cancelled notPaired, deleted")
    c = fresh()
    midway(rig, c, transfer: 5)
    let before = rig.sent.count
    rig.hub.stop(connection: ObjectIdentifier(c), .lost, tellPeer: false); rig.flush()
    check(rig.sent.count == before && staged(rig.folder).isEmpty, "the device left: nothing sent, its partial deleted")
    c = fresh()
    midway(rig, c, transfer: 6)
    rig.offer(.cancel(transfer: 6, reason: .cancelled), from: c)
    check(staged(rig.folder).isEmpty, "the device's cancel: its partial deleted")
    rig.offer(.cancel(transfer: 99, reason: .cancelled), from: c)
    c = fresh()
    midway(rig, c, transfer: 7)
    let sentBefore = rig.sent.count
    peers.removeValue(forKey: c); rig.context(peers: peers)
    check(staged(rig.folder).isEmpty && rig.sent.count == sentBefore,
          "a session the coordinator no longer lists: its partial deleted, nothing sent to it (it is gone)")
    c = fresh()
    midway(rig, c, transfer: 8)
    rig.hub.quit()
    check(staged(rig.folder).isEmpty && rig.last(.cancel)?.transfer == 8, "a quit: cancelled, deleted")
    check(listing(rig.folder).isEmpty, "nothing kept by any of them")
}

// MARK: - The Mac's files to a device: offered, read in parts as the server's room allows, within the window

func makeFile(_ folder: URL, _ name: String, _ data: Data) -> URL {
    try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent(name)
    try! data.write(to: url)
    return url
}
/// Every part the hub hands the server, until it waits for more than room (an ack, the receiver's answer).
func drain(_ rig: Rig, _ c: NWConnection, limit: Int = 10_000) {
    for _ in 0..<limit {
        let before = rig.parts.all.count
        rig.hub.room(c); rig.flush()
        if rig.parts.all.count == before { return }
    }
}
let src = scratch.appendingPathComponent("mac-src", isDirectory: true)
let macBig = Data((0..<300_000).map { UInt8(($0 * 7) % 251) })
let macFiles = [makeFile(src, "../Report:final.pdf", macBig), makeFile(src, "empty.txt", Data()), makeFile(src, "five.txt", Data("12345".utf8))]
do {
    let rig = Rig("give")
    let ipad = connection()
    rig.context(takers: [ipad], peers: [ipad: ("iPad", true)])
    rig.hub.send(macFiles, to: ipad); rig.flush()
    guard let offer = rig.last(.offer), let transfer = offer.transfer, let offered = offer.files else {
        check(false, "the Mac's files offered: \(rig.sent)"); exit(1)
    }
    check(offered.map(\.name) == ["Report-final.pdf", "empty.txt", "five.txt"] && offered.map(\.size) == [300_000, 0, 5]
          && offer.asked == nil, "offered with cleaned names, their sizes, not asked: \(offered.map(\.name))")
    check(Set(offered.map(\.id)).count == 3 && !offered.contains { $0.id == 0 }, "three ids, none twice, none 0")
    check(rig.parts.all.isEmpty, "no part before the device's answer")
    check(rig.running.all.last?.1 == 1, "a transfer to a device runs (the App Nap hold)")
    rig.offer(.accepted(transfer: transfer), from: ipad)
    check(rig.parts.all.count == 1, "accepted: one part handed, then the hub waits for the server's room (\(rig.parts.all.count))")
    drain(rig, ipad)
    let got = rig.parts.unpacked
    check(got.allSatisfy { $0.bytes.count <= 65_536 } && got.count == 6, "parts of at most 64 KiB: \(got.count)")
    var rebuilt: [UInt32: Data] = [:]
    for p in got {
        check(UInt64((rebuilt[p.id] ?? Data()).count) == p.offset, "in order, each at the end of what went before")
        rebuilt[p.id, default: Data()].append(p.bytes)
    }
    check(rebuilt[offered[0].id] == macBig && rebuilt[offered[1].id] == nil && rebuilt[offered[2].id] == Data("12345".utf8),
          "the files go byte for byte, the empty one with no part")
    let ends = rig.sent.filter { $0.knownOp == .end }
    check(ends.map(\.file) == offered.map(\.id) && ends.map(\.sha256) == [sha(macBig), sha(Data()), sha(Data("12345".utf8))],
          "each file's end with its SHA-256, in order")
    // The device acknowledges what it wrote, then says done.
    for p in got { rig.offer(.ack(transfer: transfer, file: p.id, offset: p.offset + UInt64(p.bytes.count)), from: ipad) }
    rig.offer(.done(transfer: transfer, kept: ["Report-final.pdf", "empty.txt", "five.txt"], place: "Files › Sill › From Mac"), from: ipad)
    check(rig.last(.cancel) == nil, "no cancel")
    check(rig.running.all.last?.1 == 0, "and nothing runs once it is done")
    rig.hub.send([macFiles[2]], to: ipad); rig.flush()
    check(rig.sent.filter { $0.knownOp == .offer }.count == 2, "done: the next transfer may start")
}

do {
    // The window: the person using the stream at home (128 KiB), away and using it (64 KiB); acks move it.
    let rig = Rig("window")
    let ipad = connection()
    rig.context(takers: [ipad], peers: [ipad: ("iPad", true)])
    let two = makeFile(src, "two-mb.bin", Data(count: 2_000_000))
    rig.input.at = ProcessInfo.processInfo.systemUptime + 3_600          // using it, for the check's whole run
    rig.hub.send([two], to: ipad); rig.flush()
    let t = rig.last(.offer)!.transfer!
    rig.offer(.accepted(transfer: t), from: ipad)
    drain(rig, ipad)
    check(rig.parts.all.count == 2, "the person using the stream: 128 KiB unacknowledged at most (\(rig.parts.all.count) parts)")
    let id = rig.last(.offer)!.files![0].id
    rig.offer(.ack(transfer: t, file: id, offset: 65_536), from: ipad)
    drain(rig, ipad)
    check(rig.parts.all.count == 3, "an ack: one more part (\(rig.parts.all.count))")
    rig.input.at = nil
    rig.offer(.ack(transfer: t, file: id, offset: 131_072), from: ipad)
    drain(rig, ipad)
    check(rig.parts.all.count == 10, "idle at home: 512 KiB unacknowledged (\(rig.parts.all.count) parts)")
    rig.offer(.cancel(transfer: t, reason: .cancelled), from: ipad)
    drain(rig, ipad)
    check(rig.parts.all.count == 10, "the device's cancel: nothing more")
    let away = Rig("away")
    let phone = connection()
    away.context(takers: [phone], away: true, peers: [phone: ("iPhone", true)])
    away.input.at = ProcessInfo.processInfo.systemUptime + 3_600
    away.hub.send([two], to: phone); away.flush()
    away.offer(.accepted(transfer: away.last(.offer)!.transfer!), from: phone)
    drain(away, phone)
    check(away.parts.all.count == 1, "away and in use: 64 KiB (\(away.parts.all.count) part)")
}

do {
    // Not offered: a device that does not take files, an unpaired one, a locked Mac, the switch off, one running, a folder.
    let rig = Rig("not-offered")
    let old = connection(), stranger = connection(), ipad = connection()
    rig.context(takers: [stranger, ipad], peers: [old: ("Old iPad", true), stranger: ("iPhone", false), ipad: ("iPad", true)])
    rig.hub.send([macFiles[2]], to: old); rig.hub.send([macFiles[2]], to: stranger); rig.flush()
    check(rig.sent.isEmpty, "nothing to a device whose hello takes no files, nor to an unpaired one")
    rig.gate.set(.screenLocked)
    rig.hub.send([macFiles[2]], to: ipad); rig.flush()
    check(rig.sent.isEmpty, "nothing while the Mac is locked")
    rig.gate.set(.unlocked)
    rig.context(share: false, takers: [ipad], peers: [ipad: ("iPad", true)])
    rig.hub.send([macFiles[2]], to: ipad); rig.flush()
    check(rig.sent.isEmpty, "nothing with Share files with devices off")
    rig.context(takers: [ipad], peers: [ipad: ("iPad", true)])
    rig.hub.send([src], to: ipad); rig.flush()
    check(rig.sent.isEmpty, "a folder: nothing offered")
    rig.hub.send([src.appendingPathComponent("gone.bin")], to: ipad); rig.flush()
    check(rig.sent.isEmpty, "a file that is not there: nothing offered")
    // Not a regular file: a named pipe would block the hub's queue on its first read, so it is never offered.
    let fifo = src.appendingPathComponent("pipe")
    check(mkfifo(fifo.path, 0o600) == 0, "a named pipe made")
    rig.hub.send([fifo], to: ipad); rig.flush()
    check(rig.sent.isEmpty, "a named pipe: nothing offered")
    unlink(fifo.path)
    rig.hub.send([macFiles[2]], to: ipad); rig.flush()
    rig.hub.send([macFiles[0]], to: ipad); rig.flush()
    check(rig.sent.filter { $0.knownOp == .offer }.count == 1, "a second transfer to a device while one runs: not offered")
    rig.offer(.refused(transfer: rig.last(.offer)!.transfer!, reason: .declined), from: ipad)
    rig.hub.send([macFiles[0]], to: ipad); rig.flush()
    check(rig.sent.filter { $0.knownOp == .offer }.count == 2, "declined: over, the next may go")
    let many = (0...FilePolicy.maxFiles).map { makeFile(src.appendingPathComponent("many"), "f\($0)", Data()) }
    let other = Rig("many")
    let ipad2 = connection()
    other.context(takers: [ipad2], peers: [ipad2: ("iPad", true)])
    other.hub.send(many, to: ipad2); other.flush()
    check(other.sent.isEmpty, "501 files: nothing offered")
    other.hub.send(Array(many.prefix(FilePolicy.maxFiles)), to: ipad2); other.flush()
    check(other.last(.offer)?.files?.count == FilePolicy.maxFiles, "500: offered")
}

do {
    // Stops while the Mac sends: a lock, the device leaving, a done that names fewer files, a file that shrinks.
    let rig = Rig("give-stops")
    var peers: [NWConnection: (String, Bool)] = [:]
    var takers = Set<NWConnection>()
    func fresh() -> NWConnection { let c = connection(); peers[c] = ("iPad", true); takers.insert(c); rig.context(takers: takers, peers: peers); return c }
    func started(_ c: NWConnection, _ url: URL) -> FileTransfer {
        rig.hub.send([url], to: c); rig.flush()
        let o = rig.last(.offer)!
        rig.offer(.accepted(transfer: o.transfer!), from: c)
        return o
    }
    var c = fresh()
    var o = started(c, macFiles[0])
    rig.hub.stopAll(.locked, tellPeer: true); rig.flush()
    check(rig.last(.cancel).map { $0.transfer == o.transfer && $0.reason == "locked" } == true, "the Mac locks: the device told locked")
    let handed = rig.parts.all.count
    drain(rig, c)
    check(rig.parts.all.count == handed, "and nothing more goes")
    c = fresh()
    o = started(c, macFiles[0])
    let sentBefore = rig.sent.count
    rig.hub.stop(connection: ObjectIdentifier(c), .lost, tellPeer: false); rig.flush()
    check(rig.sent.count == sentBefore, "the device left: nothing sent to it")
    c = fresh()
    o = started(c, macFiles[2])
    drain(rig, c)
    rig.offer(.ack(transfer: o.transfer!, file: o.files![0].id, offset: 5), from: c)
    rig.offer(.done(transfer: o.transfer!, kept: [], place: "x"), from: c)
    check(rig.last(.cancel).map { $0.transfer == o.transfer && $0.reason == "damaged" } == true, "a done that names fewer files: damaged")
    c = fresh()
    o = started(c, macFiles[0])
    rig.offer(.ack(transfer: o.transfer!, file: o.files![0].id, offset: 200_000), from: c)
    check(rig.last(.cancel).map { $0.transfer == o.transfer && $0.reason == "damaged" } == true, "an ack past what was sent: damaged")
    c = fresh()
    rig.hub.send([macFiles[0]], to: c); rig.flush()
    o = rig.last(.offer)!
    let partsBefore = rig.parts.all.count
    rig.offer(.accepted(transfer: o.transfer!), from: c, arrived: .screenLocked)
    check(rig.last(.cancel).map { $0.transfer == o.transfer && $0.reason == "locked" } == true && rig.parts.all.count == partsBefore,
          "a device's yes that came while the Mac read locked: nothing goes, the device told locked")
    let shrinking = makeFile(src, "shrinks.bin", Data(count: 200_000))
    c = fresh()
    o = started(c, shrinking)
    let h = try! FileHandle(forWritingTo: shrinking); try! h.truncate(atOffset: 100_000); try! h.close()
    let before = rig.parts.all.count
    drain(rig, c)
    check(rig.last(.cancel).map { $0.transfer == o.transfer && $0.reason == "cantRead" } == true, "a file that shrank: cantRead, the device told")
    // Never a short part: each one the offer's 64 KiB, or the rest of the file it offered (a short read stops it).
    let size = o.files![0].size
    let shrunk = rig.parts.unpacked.suffix(rig.parts.all.count - before + 1)
    check(shrunk.allSatisfy { UInt64($0.bytes.count) == min(65_536, size - $0.offset) && $0.total == size },
          "no short part of a file that shrank: \(shrunk.map { $0.bytes.count })")
}

do {
    // A device's pick: shown (onPick) only where the Mac gives files; answered with the files, asked; refused with words.
    let rig = Rig("pick")
    let ipad = connection(), phone = connection()
    rig.context(gives: true, takers: [ipad, phone], peers: [ipad: ("iPad", true), phone: ("iPhone", true)])
    rig.offer(.pick(transfer: 77), from: ipad)
    check(rig.picks.all.map(\.1) == [77] && rig.picks.all.first?.0 == ObjectIdentifier(ipad), "a pick: the Open panel asked for")
    rig.offer(.pick(transfer: 78), from: phone)
    check(rig.last(.cancel).map { $0.transfer == 78 && $0.reason == "busy" } == true && rig.picks.all.count == 1, "another device's pick while a panel is up: busy")
    rig.hub.pickEnded(ipad, transfer: 77, urls: [macFiles[2]]); rig.flush()
    check(rig.last(.offer).map { $0.transfer == 77 && $0.asked == true && $0.files?.count == 1 } == true, "chosen: offered as the pick's transfer, asked")
    rig.offer(.refused(transfer: 77, reason: .cancelled), from: ipad)
    rig.offer(.pick(transfer: 79), from: ipad)
    check(rig.last(.cancel).map { $0.transfer == 79 && $0.reason == "rate" } == true, "again within 5 s of its last: rate")
    rig.offer(.pick(transfer: 80), from: phone)
    rig.hub.pickEnded(phone, transfer: 80, urls: nil); rig.flush()
    check(rig.last(.cancel).map { $0.transfer == 80 && $0.reason == "nothingChosen" } == true, "nothing chosen: nothingChosen")
    let off = Rig("pick-off")
    let pad = connection()
    off.context(gives: false, takers: [pad], peers: [pad: ("iPad", true)])
    off.offer(.pick(transfer: 5), from: pad)
    check(off.last(.cancel).map { $0.transfer == 5 && $0.reason == "off" } == true && off.picks.all.isEmpty, "a Mac that gives no files: off, no panel")
    let locked = Rig("pick-locked")
    locked.context(gives: true, takers: [pad], peers: [pad: ("iPad", true)])
    locked.offer(.pick(transfer: 6), from: pad, arrived: .screenLocked)
    check(locked.last(.cancel).map { $0.transfer == 6 && $0.reason == "locked" } == true && locked.picks.all.isEmpty, "a pick that came while locked: locked")
    let unpaired = Rig("pick-unpaired")
    unpaired.context(gives: true, takers: [pad], peers: [pad: ("iPad", false)])
    unpaired.offer(.pick(transfer: 7), from: pad)
    check(unpaired.last(.cancel)?.reason == "notPaired" && unpaired.picks.all.isEmpty, "an unpaired device's pick: notPaired")
    let gone = Rig("pick-gone")
    gone.context(gives: true, takers: [pad], peers: [pad: ("iPad", true)])
    gone.offer(.pick(transfer: 8), from: pad)
    gone.hub.stopAll(.locked, tellPeer: true); gone.flush()
    check(gone.last(.cancel).map { $0.transfer == 8 && $0.reason == "locked" } == true, "the Mac locks while the panel is up: the device told")
    gone.hub.pickEnded(pad, transfer: 8, urls: [macFiles[2]]); gone.flush()
    check(gone.last(.offer) == nil, "the panel's late answer offers nothing")
}

print("file-hub: \(checks - failures)/\(checks) checks passed")
exit(failures == 0 ? 0 : 1)
