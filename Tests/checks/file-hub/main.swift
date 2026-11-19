import Foundation
import Network
import CryptoKit

// FileHub with FileStore, LockPolicy and the ledgers, fed a device's kinds 34 and 49 as StreamServer hands them on
// (with the lock's reading as they arrived), on a scratch folder of its own (under .build/checks/file-hub: `scratch` below),
// never ~/Downloads; no network (the connections are never started), no host, no encoder.
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
    private let lock = NSLock()
    private var sentMessages: [(FileTransfer, ObjectIdentifier)] = []
    init(_ name: String, free: UInt64? = nil) {
        folder = scratch.appendingPathComponent(name, isDirectory: true)
        let box = SentBox()
        hub = FileHub(gate: gate, folder: folder, testFree: free) { t, c in box.add(t, c) }
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
    func context(share: Bool = true, peers: [NWConnection: (String, Bool)]) {
        var c = FileHub.Context()
        c.share = share; c.folder = folder; c.place = "Downloads › Sill"
        for (conn, (name, paired)) in peers { c.peers[ObjectIdentifier(conn)] = FileHub.Peer(name: name, paired: paired) }
        hub.update(c); flush()
    }
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

print("file-hub: \(checks - failures)/\(checks) checks passed")
exit(failures == 0 ? 0 : 1)
