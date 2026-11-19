import Foundation
import Network
import CryptoKit

// DeviceFiles with SessionLink's uplink ledger (the device's sender) against the Mac's own FileHub (its receiver),
// over loopback: a stand-in Mac listens on 127.0.0.1, reads each connection as StreamServer does (a header, then its
// payload), hands kinds 34 and 49 to a real FileHub as `onFileMessage` does and writes the hub's kind 49s back, and
// records every message it read, in order. The device dials it, reads the Mac's messages with its own MessageReader
// and hands kind 49 to DeviceFiles, as StreamClient does. Files go into a scratch folder of the check's own
// (under .build/checks/device-files: `scratch` below), never ~/Downloads; nothing else of the host runs. Every wait waits for
// what it needs, with a generous limit, never a fixed sleep that a slow machine could overrun, but where a check
// is that nothing happens (a hold, a cancel), which it watches for a while.
var failures = 0
var checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
let fm = FileManager.default
/// The run's scratch folder: the one module.py gives it (SILL_CHECK_SCRATCH), which it removes however the run ends (a
/// crash or its time limit too), else .build/checks/device-files/scratch-<pid> for a binary run by hand. Removed here at
/// every exit (`exit` skips a `defer` at the top level, which left one of them behind each run until 2026-11-19).
let scratch = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SILL_CHECK_SCRATCH"]
                  ?? fm.currentDirectoryPath + "/.build/checks/device-files/scratch-\(getpid())", isDirectory: true)
try? fm.removeItem(at: scratch)
try! fm.createDirectory(at: scratch, withIntermediateDirectories: true)
atexit { try? FileManager.default.removeItem(at: scratch) }
func now() -> Double { ProcessInfo.processInfo.systemUptime }
// A whole run takes seconds; one that stalls everywhere (a mutant) fails here, well before module.py's 300 s limit.
Thread.detachNewThread {
    sleep(200)
    print("FAIL: the check ran past 200 s: \(checks - failures)/\(checks) checks passed by then")
    exit(1)
}
func waitFor(_ limit: Double, _ ok: () -> Bool) -> Bool {
    let end = now() + limit
    while now() < end { if ok() { return true }; usleep(2_000) }
    return ok()
}
func listing(_ url: URL) -> [String] { ((try? fm.contentsOfDirectory(atPath: url.path)) ?? []).filter { $0 != FileStore.stagingName }.sorted() }
func staged(_ url: URL) -> [String] { ((try? fm.contentsOfDirectory(atPath: url.appendingPathComponent(FileStore.stagingName).path)) ?? []).sorted() }
func randomData(_ n: Int) -> Data {
    var d = Data(count: n)
    d.withUnsafeMutableBytes { p in if let b = p.baseAddress, n > 0 { arc4random_buf(b, n) } }
    return d
}
func make(_ folder: URL, _ name: String, _ size: Int) -> URL {
    try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent(name)
    try! randomData(size).write(to: url)
    return url
}
/// A numbered input message (kind 8), as SessionLink counts one.
func input(_ n: Int) -> Data {
    var p = Data(); p.appendBigEndian(UInt32(n))
    return StreamMessage(kind: .input, timestamp: 0, isKeyframe: false, payload: p).serialized()
}

/// The stand-in Mac: a listener on loopback, each connection read as StreamServer reads it, files to a real FileHub.
final class Mac {
    let listener: NWListener
    let hub: FileHub
    let gate = LockGate()
    let folder: URL
    let queue = DispatchQueue(label: "mac")
    private let lock = NSLock()
    private var conns: [NWConnection] = []
    /// Every message read, in order: its kind, its payload's size, the connection's number, when.
    private var read: [(kind: StreamMessageKind, size: Int, conn: Int, at: Double)] = []
    var share = true
    var paired = true
    /// A slow Mac: each part holds its reading this long (microseconds), so a transfer lasts.
    var partDelay: useconds_t = 0

    init(_ name: String) {
        folder = scratch.appendingPathComponent(name, isDirectory: true)
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: 0)
        listener = try! NWListener(using: params)
        hub = FileHub(gate: gate, folder: folder) { t, c in
            guard let payload = t.payload else { return }
            c.send(content: StreamMessage(kind: .fileTransfer, timestamp: 0, isKeyframe: false, payload: payload).serialized(),
                   completion: .contentProcessed { _ in })
        }
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
        listener.newConnectionHandler = { [unowned self] c in self.accept(c) }
        listener.start(queue: queue)
        ready.wait()
    }

    var port: NWEndpoint.Port { listener.port! }
    var connections: [NWConnection] { lock.lock(); defer { lock.unlock() }; return conns }
    var messages: [(kind: StreamMessageKind, size: Int, conn: Int, at: Double)] { lock.lock(); defer { lock.unlock() }; return read }
    func count(_ kind: StreamMessageKind) -> Int { messages.filter { $0.kind == kind }.count }

    /// The hub's context as the coordinator pushes it: the switch, the folder, each connection's name and pairing.
    func pushContext() {
        var c = FileHub.Context()
        c.share = share; c.folder = folder; c.place = "Downloads › Sill"
        for conn in connections { c.peers[ObjectIdentifier(conn)] = FileHub.Peer(name: "Test iPad", paired: paired) }
        hub.update(c)
        hub.queue.sync {}
    }

    private func accept(_ c: NWConnection) {
        lock.lock(); conns.append(c); let n = conns.count; lock.unlock()
        pushContext()
        c.start(queue: queue)
        readHeader(c, n)
    }

    private func readHeader(_ c: NWConnection, _ n: Int) {
        c.receive(minimumIncompleteLength: StreamMessage.headerLength, maximumLength: StreamMessage.headerLength) { [weak self] data, _, done, error in
            guard let self, let data, let h = StreamMessage.parseHeader(data) else { return }
            guard h.payloadLength > 0 else { self.got(h, Data(), c, n); if !done, error == nil { self.readHeader(c, n) }; return }
            c.receive(minimumIncompleteLength: h.payloadLength, maximumLength: h.payloadLength) { payload, _, done2, error2 in
                guard let payload, payload.count == h.payloadLength else { return }
                self.got(h, payload, c, n)
                if !done2, error2 == nil { self.readHeader(c, n) }
            }
        }
    }

    private func got(_ h: StreamHeader, _ payload: Data, _ c: NWConnection, _ n: Int) {
        lock.lock(); read.append((h.kind, payload.count, n, now())); lock.unlock()
        if h.kind == .fileChunk, partDelay > 0 { usleep(partDelay) }
        if h.kind == .fileChunk || h.kind == .fileTransfer {
            hub.received(StreamMessage(kind: h.kind, timestamp: h.timestamp, isKeyframe: h.isKeyframe, payload: payload), from: c,
                         arrived: .unlocked) {}
        }
    }

    func stop() {
        for c in connections { c.cancel() }
        listener.cancel()
    }
}

/// The device: a SessionLink and its DeviceFiles, a connection to the stand-in read by MessageReader.
final class Device {
    let link = SessionLink()
    let files: DeviceFiles
    let queue = DispatchQueue(label: "device.net")
    private let lock = NSLock()
    private var shots: [OutgoingFiles] = []
    private var readers: [MessageReader] = []
    var connection: NWConnection!

    init(_ mac: Mac) {
        files = DeviceFiles(link: link)
        files.onSnapshot = { [weak self] s in self?.record(s) }
        connection = dial(mac)
        link.connection = connection
        _ = waitFor(5) { mac.connections.count >= 1 }
    }

    func dial(_ mac: Mac) -> NWConnection {
        let c = NWConnection(host: "127.0.0.1", port: mac.port, using: .tcp)
        let reader = MessageReader(connection: c, stillReads: { [weak self] in self?.link.reads(c) ?? false }, onBytes: { _ in },
                                   onMessage: { [weak self] h, p in
                                       guard h.kind == .fileTransfer, let t = FileTransfer.parse(p) else { return }
                                       self?.files.received(t, from: c)
                                   }, onEnd: { _ in })
        readers.append(reader)
        let ready = DispatchSemaphore(value: 0)
        c.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
        c.start(queue: queue)
        _ = ready.wait(timeout: .now() + 5)
        queue.async { reader.start() }
        return c
    }

    private func record(_ s: OutgoingFiles) { lock.lock(); shots.append(s); lock.unlock() }
    var snapshots: [OutgoingFiles] { lock.lock(); defer { lock.unlock() }; return shots }
    var last: OutgoingFiles? { snapshots.last }
    /// The transfer's end (done or stopped), waited for.
    func end(_ limit: Double = 60) -> OutgoingFiles? {
        _ = waitFor(limit) { last?.isOver == true }
        return last
    }
    func send(_ sources: [DeviceFiles.Source]) { files.send(sources, on: connection) }
    func stop() { connection.cancel() }
}

/// The largest unacknowledged share seen while `run` lasts, sampled every millisecond.
final class InFlight {
    private let lock = NSLock()
    private var most: UInt64 = 0
    private var going = true
    private var samples = 0
    init(_ d: Device) {
        Thread.detachNewThread { [self] in
            while true {
                lock.lock(); let go = going; lock.unlock()
                guard go else { return }
                if let p = d.files.progress {
                    lock.lock(); most = max(most, p.sent - p.acked); samples += 1; lock.unlock()
                }
                usleep(1_000)
            }
        }
    }
    func finish() -> (most: UInt64, samples: Int) { lock.lock(); defer { lock.unlock() }; going = false; return (most, samples) }
}

func phases(_ d: Device) -> [String] {
    var out: [String] = []
    for s in d.snapshots {
        let p: String
        switch s.phase {
        case .preparing: p = "preparing"
        case .offering: p = "offering"
        case .sending: p = "sending"
        case .finishing: p = "finishing"
        case .done: p = "done"
        case .stopped(let r, _, let byPeer, _): p = "stopped:\(r)\(byPeer ? ":peer" : "")"
        }
        if out.last != p { out.append(p) }
    }
    return out
}
func stopped(_ s: OutgoingFiles?) -> (reason: String, byPeer: Bool, name: String?)? {
    if case .stopped(let r, _, let byPeer, let name)? = s?.phase { return (r, byPeer, name) }
    return nil
}

// MARK: - The ledger, on its own

do {
    var l = UplinkLedger()
    let oa = NSObject(), ob = NSObject()   // kept alive: two identifiers that differ
    let a = ObjectIdentifier(oa), b = ObjectIdentifier(ob)
    check(l.pending(for: a) == 0 && UplinkLedger.filesMayGo(pending: 0, fenced: false, held: false), "nothing handed: a file may go")
    let e1 = l.handed(100, .first, to: a)
    check(l.pending(for: a) == 100 && l.pending(.first, for: a) == 100 && l.pending(.files, for: a) == 0, "an input counted on its lane")
    check(!UplinkLedger.filesMayGo(pending: l.pending(for: a), fenced: false, held: false), "the connection holds an input: no file")
    check(UplinkLedger.filesMayGo(pending: 0, fenced: false, held: false) && !UplinkLedger.filesMayGo(pending: 0, fenced: true, held: false)
          && !UplinkLedger.filesMayGo(pending: 0, fenced: false, held: true), "a fence or a hold: no file, whatever is pending")
    l.wantRoom()
    check(l.taken(100, .first, epoch: e1) && l.pending(for: a) == 0, "taken: room, said once")
    check(!l.taken(0, .first, epoch: e1), "and only once")
    let e2 = l.handed(65_572, .files, to: a)
    check(e2 == e1, "the same connection, the same epoch")
    let e3 = l.handed(10, .first, to: b)
    check(e3 == e2 + 1 && l.pending(for: b) == 10 && l.pending(for: a) == 0, "another connection: counted afresh, the old one not")
    l.wantRoom()
    check(!l.taken(65_572, .files, epoch: e2) && l.pending(for: b) == 10, "a completion from the old connection counts nothing")
    check(l.taken(10, .first, epoch: e3), "the new one's: room")
    _ = l.handed(5, .files, to: b)
    check(!l.taken(500, .files, epoch: e3 - 1) && l.pending(.files, for: b) == 5, "an earlier epoch never counts off")
    l.wantRoom()
    _ = l.handed(3, .first, to: b)
    check(!l.taken(5, .files, epoch: e3), "room only once nothing is left: an input still pending")
    check(l.taken(3, .first, epoch: e3) && l.total == 0, "then room")
}

// MARK: - Files kept whole, within the window

do {
    let mac = Mac("whole")
    let dev = Device(mac)
    let src = scratch.appendingPathComponent("src-whole")
    let sizes = [("empty.txt", 0), ("one.bin", 1), ("chunk.bin", 65_536), ("chunk-plus-one.bin", 65_537), ("three.bin", 3_000_000),
                 ("twenty.bin", 20_000_000)]
    let urls = sizes.map { make(src, $0.0, $0.1) }
    dev.files.windowOverride = 128 * 1024
    let flight = InFlight(dev)
    let began = now()
    dev.send(zip(sizes, urls).map { DeviceFiles.Source(url: $1, name: $0.0) })
    let end = dev.end()
    let seen = flight.finish()
    let took = now() - began
    if case .done(let t)? = end?.phase {
        check(t.kept == sizes.map(\.0) && t.place == "Downloads › Sill", "done with every name as kept, in order: \(t.kept ?? [])")
    } else {
        check(false, "the transfer is done: \(String(describing: end?.phase))")
    }
    check(listing(mac.folder) == sizes.map(\.0).sorted(), "every file kept: \(listing(mac.folder))")
    check(zip(sizes, urls).allSatisfy { (try? Data(contentsOf: mac.folder.appendingPathComponent($0.0))) == (try? Data(contentsOf: $1)) },
          "each byte for byte its source")
    check(staged(mac.folder).isEmpty, "nothing left in the staging folder")
    check(seen.most <= 128 * 1024 && seen.samples > 10, "never more than the window unacknowledged: at most \(seen.most) bytes in \(seen.samples) samples")
    check(end?.acked == end?.total && end?.total == UInt64(sizes.map(\.1).reduce(0, +)) && end?.fraction == 1, "every byte acknowledged")
    check(phases(dev) == ["preparing", "offering", "sending", "finishing", "done"], "its phases: \(phases(dev))")
    let parts = mac.messages.filter { $0.kind == .fileChunk }
    check(parts.allSatisfy { $0.size <= FileFlow.chunkBytes + FileChunk.headerBytes }, "no part over 64 KiB")
    check(mac.count(.fileTransfer) == 1 + sizes.count, "one offer and one end a file, nothing else: \(mac.count(.fileTransfer))")
    print(String(format: "whole: %.1f MB in %.2f s (%.0f MB/s), at most %d bytes unacknowledged", Double(end?.total ?? 0) / 1e6, took,
                 Double(end?.total ?? 0) / 1e6 / max(took, 0.001), seen.most))
    // A second transfer on the same session, one part at a time (a window smaller than a part).
    dev.files.windowOverride = 1
    let flight1 = InFlight(dev)
    let small = make(src, "five.bin", 5_000_000)
    dev.send([DeviceFiles.Source(url: small, name: "five.bin")])
    _ = waitFor(60) { dev.snapshots.filter { $0.isOver }.count == 2 }
    let seen1 = flight1.finish()
    if case .done? = dev.last?.phase {} else { check(false, "the second transfer is done: \(String(describing: dev.last?.phase))") }
    check((try? Data(contentsOf: mac.folder.appendingPathComponent("five.bin"))) == (try? Data(contentsOf: small)), "kept whole")
    check(seen1.most <= UInt64(FileFlow.chunkBytes), "a window under a part: one part at a time (\(seen1.most))")
    dev.stop(); mac.stop()
}

// MARK: - The person's Cancel, the Mac's stop, a refusal

do {
    let mac = Mac("cancel")
    let dev = Device(mac)
    let src = scratch.appendingPathComponent("src-cancel")
    let big = make(src, "big.bin", 40_000_000)
    dev.files.windowOverride = 64 * 1024
    dev.send([DeviceFiles.Source(url: big, name: "big.bin")])
    check(waitFor(20) { (dev.last?.acked ?? 0) >= 1_000_000 }, "under way: \(String(describing: dev.last?.acked))")
    dev.files.cancel()
    let end = dev.end(10)
    check(stopped(end).map { $0.reason == "cancelled" && !$0.byPeer } == true, "the person's Cancel: stopped cancelled: \(String(describing: end?.phase))")
    _ = waitFor(5) { mac.messages.last?.kind == .fileTransfer }
    usleep(300_000)
    let msgs = mac.messages
    let at = msgs.lastIndex { $0.kind == .fileTransfer }
    check(at != nil && msgs[(at! + 1)...].allSatisfy { $0.kind != .fileChunk }, "nothing of the file after the cancel")
    mac.hub.queue.sync {}
    check(listing(mac.folder).isEmpty && staged(mac.folder).isEmpty, "the Mac kept nothing and deleted its partial")
    // The Mac stops the next one (it locked).
    dev.send([DeviceFiles.Source(url: big, name: "big.bin")])
    check(waitFor(20) { dev.last?.phase == .sending && (dev.last?.acked ?? 0) >= 500_000 }, "the next one under way")
    mac.hub.stopAll(.locked, tellPeer: true)
    let locked = dev.end(10)
    check(stopped(locked).map { $0.reason == "locked" && $0.byPeer } == true, "the Mac locked: stopped locked, by the Mac: \(String(describing: locked?.phase))")
    mac.hub.queue.sync {}
    check(staged(mac.folder).isEmpty, "its partial deleted")
    // Refusals: the switch off, then a session no longer paired.
    mac.share = false; mac.pushContext()
    let n = dev.snapshots.count
    dev.send([DeviceFiles.Source(url: make(src, "a.txt", 10), name: "a.txt")])
    _ = waitFor(10) { dev.snapshots.count > n && dev.last?.isOver == true }
    check(stopped(dev.last).map { $0.reason == "off" && $0.byPeer } == true, "the switch off: refused off: \(String(describing: dev.last?.phase))")
    mac.share = true; mac.paired = false; mac.pushContext()
    usleep(1_100_000)   // the Mac's rate: two offers a second from one connection
    let m = dev.snapshots.count
    dev.send([DeviceFiles.Source(url: src.appendingPathComponent("a.txt"), name: "a.txt")])
    _ = waitFor(10) { dev.snapshots.count > m && dev.last?.isOver == true }
    check(stopped(dev.last).map { $0.reason == "notPaired" && $0.byPeer } == true, "not paired: refused notPaired: \(String(describing: dev.last?.phase))")
    check(listing(mac.folder).isEmpty, "nothing kept")
    dev.stop(); mac.stop()
}

// MARK: - A hold: files pause, nothing of them waits, the person's input goes first

do {
    let mac = Mac("hold")
    let dev = Device(mac)
    let src = scratch.appendingPathComponent("src-hold")
    let big = make(src, "big.bin", 30_000_000)
    dev.files.windowOverride = 64 * 1024
    dev.send([DeviceFiles.Source(url: big, name: "big.bin")])
    check(waitFor(20) { (dev.last?.acked ?? 0) >= 1_000_000 }, "under way")
    check(dev.link.hold(dev.connection), "the session's connection held (its path gone)")
    // Two of the clock's looks before the inputs: a part it handed while held would go out ahead of them.
    usleep(600_000)
    let partsAtHold = mac.count(.fileChunk)
    for i in 0..<5 { dev.link.send(input(i)) }
    usleep(400_000)
    check(mac.count(.fileChunk) == partsAtHold, "no part while held: \(mac.count(.fileChunk) - partsAtHold) more")
    check(mac.count(.input) == 0, "the inputs wait for the hold")
    check(dev.link.pendingBytes[.files] == 0, "nothing of the file handed while held")
    let released = now()
    _ = dev.link.unhold(dev.connection)
    let end = dev.end(60)
    if case .done? = end?.phase {} else { check(false, "the transfer finishes after the hold: \(String(describing: end?.phase))") }
    check((try? Data(contentsOf: mac.folder.appendingPathComponent("big.bin"))) == (try? Data(contentsOf: big)), "kept whole")
    let after = mac.messages.filter { $0.at >= released }
    check(after.prefix(5).allSatisfy { $0.kind == .input }, "after the hold the inputs first, then the file: \(after.prefix(6).map { $0.kind.rawValue })")
    // A hold with nothing else sent: no completion calls the file back, so the clock's look resumes it.
    dev.send([DeviceFiles.Source(url: big, name: "again.bin")])
    check(waitFor(20) { dev.snapshots.count > 0 && dev.last?.names == ["again.bin"] && (dev.last?.acked ?? 0) >= 1_000_000 }, "the next under way")
    _ = dev.link.hold(dev.connection)
    usleep(500_000)
    _ = dev.link.unhold(dev.connection)
    let again = dev.end(20)
    if case .done? = again?.phase {} else { check(false, "it resumes by itself after a quiet hold: \(String(describing: again?.phase))") }
    dev.stop(); mac.stop()
}

// MARK: - The person's input never queues behind more than one part

do {
    let mac = Mac("lanes")
    let dev = Device(mac)
    let src = scratch.appendingPathComponent("src-lanes")
    let big = make(src, "big.bin", 40_000_000)
    mac.partDelay = 1_500   // about 40 MB/s at the home window: the transfer outlasts the inputs
    dev.files.windowOverride = nil   // FileFlow's own: home, idle, then active as inputs go
    dev.send([DeviceFiles.Source(url: big, name: "big.bin")])
    check(waitFor(20) { dev.last?.phase == .sending }, "under way")
    let idle = dev.files.progress?.window
    var most = 0, windows = Set<Int>(), during = 0
    for i in 0..<100 {
        most = max(most, dev.link.pendingBytes[.files] ?? 0)
        dev.link.send(input(i))
        if let p = dev.files.progress { windows.insert(p.window); during += 1 }
        usleep(3_000)
    }
    check(during >= 50, "the inputs went while the file did: \(during) of 100")
    check(most <= FileFlow.chunkBytes + FileChunk.headerBytes + StreamMessage.headerLength,
          "at an input, at most one part's message pending ahead of it: \(most)")
    check(idle == FileFlow.homeIdle && windows == [FileFlow.shared],
          "idle at home 512 KiB; the person using the stream narrows it to 128 KiB: \(String(describing: idle)), \(windows.sorted())")
    let end = dev.end(60)
    if case .done? = end?.phase {} else { check(false, "done: \(String(describing: end?.phase))") }
    check(waitFor(5) { mac.count(.input) == 100 }, "every input arrived: \(mac.count(.input))")
    dev.stop(); mac.stop()
}

// MARK: - The connection no longer the session's: lost

do {
    let mac = Mac("lost")
    let dev = Device(mac)
    let src = scratch.appendingPathComponent("src-lost")
    let big = make(src, "big.bin", 30_000_000)
    dev.files.windowOverride = 64 * 1024
    dev.send([DeviceFiles.Source(url: big, name: "big.bin")])
    check(waitFor(20) { (dev.last?.acked ?? 0) >= 500_000 }, "under way")
    let old = dev.connection!
    let other = dev.dial(mac)
    dev.link.connection = other   // a move without a fence: the session's connection is another
    let end = dev.end(5)
    check(stopped(end).map { $0.reason == "lost" && !$0.byPeer } == true, "stopped lost: \(String(describing: end?.phase))")
    old.cancel()
    if let first = mac.connections.first { mac.hub.stop(connection: ObjectIdentifier(first), .lost, tellPeer: false) }
    mac.hub.queue.sync {}
    check(staged(mac.folder).isEmpty && listing(mac.folder).isEmpty, "the Mac deleted the partial when the old connection went")
    other.cancel(); mac.stop()
}

// MARK: - A move's fenced hand-over mid-transfer: nothing of the file waits or rides onto the new connection

do {
    let mac = Mac("fence")
    let dev = Device(mac)
    let src = scratch.appendingPathComponent("src-fence")
    let big = make(src, "big.bin", 30_000_000)
    dev.files.windowOverride = 64 * 1024
    dev.send([DeviceFiles.Source(url: big, name: "big.bin")])
    check(waitFor(20) { (dev.last?.acked ?? 0) >= 500_000 }, "under way")
    let old = dev.connection!
    let new = dev.dial(mac)
    // The stand-in never echoes pings, so this fence stays up: what is sent from now waits for it.
    let nonce = Data((0..<8).map { _ in UInt8.random(in: 0 ... 255) })
    dev.link.handOver(from: old, to: new, fencePing: StreamMessage(kind: .ping, timestamp: 0, isKeyframe: false, payload: nonce).serialized(),
                      nonce: nonce)
    for i in 0..<3 { dev.link.send(input(i)) }
    let end = dev.end(5)
    check(stopped(end).map { $0.reason == "lost" && !$0.byPeer } == true, "the session moved: stopped lost: \(String(describing: end?.phase))")
    usleep(300_000)
    check(mac.messages.filter { $0.conn == 2 && ($0.kind == .fileChunk || $0.kind == .fileTransfer) }.isEmpty,
          "nothing of the file on the new connection")
    check(dev.link.pendingBytes[.files] == 0, "nothing of the file handed to it")
    check(mac.messages.filter { $0.conn == 2 && $0.kind == .input }.isEmpty, "the inputs wait for the fence, as before")
    _ = dev.link.dropHandOver()
    old.cancel(); new.cancel(); mac.stop()
}

// MARK: - What cannot be sent: a folder, a file gone, one that shrinks, too many

do {
    let mac = Mac("unreadable")
    let dev = Device(mac)
    let src = scratch.appendingPathComponent("src-unreadable")
    let folder = src.appendingPathComponent("Holiday", isDirectory: true)
    try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
    dev.send([DeviceFiles.Source(url: make(src, "a.txt", 5), name: "a.txt"), DeviceFiles.Source(url: folder, name: "Holiday")])
    let f = dev.end(10)
    check(stopped(f).map { $0.reason == DeviceFilesCopy.folderReason && $0.name == "Holiday" && !$0.byPeer } == true,
          "a folder: stopped before any offer, named: \(String(describing: f?.phase))")
    let n = dev.snapshots.count
    dev.send([DeviceFiles.Source(url: src.appendingPathComponent("missing.bin"), name: "missing.bin")])
    _ = waitFor(10) { dev.snapshots.count > n && dev.last?.isOver == true }
    check(stopped(dev.last).map { $0.reason == "cantRead" && $0.name == "missing.bin" } == true, "a file gone: cantRead: \(String(describing: dev.last?.phase))")
    check(mac.count(.fileTransfer) == 0, "the Mac heard nothing of either")
    var many: [DeviceFiles.Source] = []
    let tiny = make(src, "tiny.txt", 1)
    for i in 0...FilePolicy.maxFiles { many.append(DeviceFiles.Source(url: tiny, name: "t\(i).txt")) }
    let m = dev.snapshots.count
    dev.send(many)
    _ = waitFor(10) { dev.snapshots.count > m && dev.last?.isOver == true }
    check(stopped(dev.last).map { $0.reason == "tooMany" && !$0.byPeer } == true && mac.count(.fileTransfer) == 0,
          "501 files: tooMany here, before any offer: \(String(describing: dev.last?.phase))")
    // A file that shrinks while it goes: cantRead, the Mac told, its partial deleted.
    let shrink = make(src, "shrink.bin", 30_000_000)
    dev.files.windowOverride = 64 * 1024
    let k = dev.snapshots.count
    dev.send([DeviceFiles.Source(url: shrink, name: "shrink.bin")])
    check(waitFor(20) { dev.snapshots.count > k && (dev.last?.acked ?? 0) >= 300_000 }, "under way")
    // Ten bytes short of its size: every part reads whole but the last, which comes up short. A short part
    // sent anyway would end at the Mac (`damaged`, by the Mac) instead of here.
    let h = try! FileHandle(forWritingTo: shrink); try! h.truncate(atOffset: 30_000_000 - 10); try! h.close()
    let s = dev.end(20)
    check(stopped(s).map { $0.reason == "cantRead" && $0.name == "shrink.bin" && !$0.byPeer } == true,
          "a file that shrank: cantRead here, never a short part sent: \(String(describing: s?.phase))")
    _ = waitFor(5) { staged(mac.folder).isEmpty }
    check(staged(mac.folder).isEmpty && listing(mac.folder).isEmpty, "the Mac was told and deleted its partial")
    dev.stop(); mac.stop()
}

// MARK: - Sill's own copies go once their transfer ends; a second send while one runs

do {
    let mac = Mac("copies")
    let dev = Device(mac)
    let pick = DeviceFiles.outbox.appendingPathComponent("check-\(getpid())-\(UUID().uuidString)", isDirectory: true)
    let copy = make(pick, "IMG_0001.heic", 200_000)
    dev.send([DeviceFiles.Source(url: copy, name: "IMG_0001.heic", ownCopy: true, type: "public.heic")])
    let end = dev.end(20)
    if case .done? = end?.phase {} else { check(false, "done: \(String(describing: end?.phase))") }
    check(!fm.fileExists(atPath: copy.path) && !fm.fileExists(atPath: pick.path), "the copy and its folder deleted after the transfer")
    // A second send while one runs: dropped, the running one's chip untouched, its own copy deleted.
    let src = scratch.appendingPathComponent("src-copies")
    let big = make(src, "big.bin", 20_000_000)
    dev.files.windowOverride = 64 * 1024
    dev.send([DeviceFiles.Source(url: big, name: "big.bin")])
    check(waitFor(20) { dev.last?.phase == .sending }, "under way")
    let pick2 = DeviceFiles.outbox.appendingPathComponent("check-\(getpid())-\(UUID().uuidString)", isDirectory: true)
    let copy2 = make(pick2, "IMG_0002.heic", 1_000)
    dev.send([DeviceFiles.Source(url: copy2, name: "IMG_0002.heic", ownCopy: true)])
    usleep(300_000)
    check(dev.snapshots.allSatisfy { $0.names != ["IMG_0002.heic"] } && !fm.fileExists(atPath: copy2.path),
          "a second send while one runs: dropped, its copy deleted")
    let end2 = dev.end(60)
    if case .done? = end2?.phase {} else { check(false, "the running one finishes: \(String(describing: end2?.phase))") }
    dev.stop(); mac.stop()
}

print("device-files: \(checks - failures)/\(checks) checks passed")
exit(failures == 0 ? 0 : 1)
