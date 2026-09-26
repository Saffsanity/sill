// Review fix check: iOSClient/SessionLink.swift on its own, against a stand-in for the Mac on
// loopback. The stand-in reads every connection on one serial queue in arrival order, as
// StreamServer does, echoes pings, and records each input's sequence number; the first connection
// (the "direct" one) delivers each message `slow` seconds late, in order, like AWDL. Two senders
// (a serial queue at 2 ms and a global queue at 5 ms) number their messages and hand them to the
// link under one test lock, so the order of the numbers is the order of the sends. Regular pings
// go on the session's connection every 30 ms, as StreamClient's do, so the fence's nonce must
// tell its pong apart. The client reads both connections the way StreamClient does (SessionLink.reads,
// fenceReturned on the old one, release when it closes).
//
//   swiftc -O iOSClient/SessionLink.swift Sources/StreamProtocol/StreamMessage.swift \
//     Tests/checks/fence/main.swift -o .build/checks/fence/check && .build/checks/fence/check ok
//
// Modes: ok (the fence comes back), nofence (the pre-fix hand-over: switch at once; the hazard
// should show as inversions), timeout (the stand-in stops reading the direct connection's messages
// at the hand-over: released by the caller's timeout), oldcloses (the stand-in closes the direct
// connection during the fence: released at once).
// follow-best-path (2026-09-25), the moves off a cable whose path is gone, which have no fence:
// hold (at the hand-over moment the stand-in stops taking anything from the first connection, as a
// pulled cable delivers nothing more; the client holds, dials a second connection and adopts it: what
// was sent from the hold on arrives, in order), holdclosed (the same, but the first connection is
// closed at the hold, and its closing must not release the hold onto it), unhold (a hold, then the
// path back after 200 ms: what waited goes out on the first connection, all of it, in order), and
// adoptfence (a fenced hand-over to a second connection, then at once an adopt of a third, as a move
// down right after a move up would: the fence stays up until the slow first connection's pong).
// Its review fixes (2026-09-25), a fence or a hold while an earlier hand-over's fence is up:
// twofences (a hand-over from the slow first connection to a second, then at once from the second to
// a third, as a move to the cable landing while the move from AWDL's fence is up: both fences end by
// their pongs, and what waits goes out on the third only once the first is down; before the fix the
// second fence replaced the first, whose held messages were lost and whose pong ended nothing),
// holdfence and holdadopt (a hand-over from the slow first connection to a second whose path then
// goes at once, as a cable pulled right after a move landed on it: the second is held, the stand-in
// takes nothing more from it, and a third adopts the session after the first fence is down, or before
// it; before the fix the hold was refused while a fence stood), and twomoves (a hand-over, its fence down, then a
// second one: each old connection is handed back for closing once, when what waited has gone out).
//   (the old SessionLink needs $SP/review/fencecheck/oldshim.swift, which gives Released its `waiting`)
// pointer-visibility (2026-09-26, docs/pointer-visibility-plan.md §3.3), SessionLink's count of the input
// messages (kind 8) meant for the session's connection, which the Mac's pointer reports (kind 26) are
// judged by: in every mode above, once everything has arrived, the count must equal the inputs the
// stand-in read on the session's last connection; and count (a script of sends and connection changes
// on one thread, no senders, pings or read loops, so each fence ends only where the script ends it: the
// count after every step, then what each of eleven connections delivered).
import Foundation
import Network

let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "ok"
let slow = 0.12
let total: UInt32 = 600
let handOverAt = 0.3
let releaseAfter = mode == "timeout" ? 0.6 : 1.5    // the caller's timeout (StreamClient: 3 s)

func message(_ kind: StreamMessageKind, _ payload: Data) -> Data {
    StreamMessage(kind: kind, timestamp: Date().timeIntervalSince1970, isKeyframe: false, payload: payload).serialized()
}
func randomNonce() -> Data { withUnsafeBytes(of: UInt64.random(in: .min ... .max)) { Data($0) } }
func be32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.bigEndian) { Data($0) } }
func now() -> Double { ProcessInfo.processInfo.systemUptime }

// MARK: The stand-in for the Mac

final class Stub {
    let queue = DispatchQueue(label: "stub")      // StreamServer's one network queue
    let listener: NWListener
    var conns: [NWConnection] = []
    var closed: Set<Int> = []
    var muted: Set<Int> = []
    var arrived: [UInt32] = []
    /// The inputs (kind 8) read on each connection, and each connection's remote port (the client's own).
    var inputsOn: [Int: Int] = [:]
    var ports: [Int: UInt16] = [:]
    var ready = DispatchSemaphore(value: 0)

    init() throws {
        listener = try NWListener(using: .tcp, on: .any)
        listener.stateUpdateHandler = { [weak self] s in if case .ready = s { self?.ready.signal() } }
        listener.newConnectionHandler = { [weak self] c in self?.accept(c) }
        listener.start(queue: queue)
    }
    var port: NWEndpoint.Port { listener.port! }

    private func accept(_ c: NWConnection) {
        let i = conns.count
        conns.append(c)
        if case .hostPort(_, let port) = c.endpoint { ports[i] = port.rawValue }
        c.start(queue: queue)
        // Each connection's messages go through its own delay line, in order, then to `queue`.
        let line = DispatchQueue(label: "line\(i)")
        let delay = i == 0 ? slow : 0
        read(c, i, line, delay)
        // Frames, so a pong sits behind other traffic as on the real link: 20 KB every 10 ms.
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 0.01, repeating: 0.01)
        t.setEventHandler { [weak self] in
            guard let self, !self.closed.contains(i) else { return }
            c.send(content: message(.frame, Data(count: 20_000)), completion: .contentProcessed { _ in })
        }
        t.resume()
        timers.append(t)
        if i == 1 {
            if mode == "timeout" { muted.insert(0) }
            if mode == "oldcloses" {
                queue.asyncAfter(deadline: .now() + 0.03) { [self] in closed.insert(0); conns[0].cancel() }
            }
        }
    }
    var timers: [DispatchSourceTimer] = []

    private func read(_ c: NWConnection, _ i: Int, _ line: DispatchQueue, _ delay: Double) {
        c.receive(minimumIncompleteLength: 14, maximumLength: 14) { [weak self] data, _, isComplete, error in
            guard let self, let data, let h = StreamMessage.parseHeader(data) else { return }
            let got = { (payload: Data) in
                let due = now() + delay
                line.async {
                    let wait = due - now()
                    if wait > 0 { Thread.sleep(forTimeInterval: wait) }
                    self.queue.async { self.process(h, payload, c, i) }
                }
                self.read(c, i, line, delay)
            }
            if h.payloadLength == 0 { got(Data()); return }
            c.receive(minimumIncompleteLength: h.payloadLength, maximumLength: h.payloadLength) { data, _, _, _ in
                guard let data else { return }
                got(data)
            }
        }
    }

    private func process(_ h: StreamHeader, _ payload: Data, _ c: NWConnection, _ i: Int) {
        guard !closed.contains(i), !muted.contains(i) else { return }
        switch h.kind {
        case .ping: c.send(content: message(.pong, payload), completion: .contentProcessed { _ in })
        case .input:
            arrived.append(payload.withUnsafeBytes { UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self)) })
            inputsOn[i, default: 0] += 1
        default: break
        }
    }
}

// MARK: The client, as StreamClient drives the link

let link = SessionLink()
let clientQueue = DispatchQueue(label: "sill.net")
let stub = try Stub()
stub.ready.wait()

let stateLock = NSLock()
var nextSeq: UInt32 = 1
var seqAtHandOver: UInt32 = 0
var fence: (how: String, held: Int, seconds: Double)?
var ends: [(how: String, held: Int, waiting: Int, clear: Bool, closed: Int)] = []   // every fence or hold that ended, in order
var handOverTime = 0.0
var seqAtDrop: UInt32 = 0
var droppedCount = -1
var readsOldAfterDrop = true

func connect() -> NWConnection {
    let c = NWConnection(host: "127.0.0.1", port: stub.port, using: .tcp)
    let ready = DispatchSemaphore(value: 0)
    c.stateUpdateHandler = { s in if case .ready = s { ready.signal() } }
    c.start(queue: clientQueue)
    ready.wait()
    return c
}

func fenceEnded(_ how: String, _ r: SessionLink.Released) {
    stateLock.lock(); fence = (how, r.held, r.seconds); ends.append((how, r.held, r.waiting, r.clear, r.close.count)); stateLock.unlock()
}

func readLoop(_ c: NWConnection) {
    guard link.reads(c) else { return }
    c.receive(minimumIncompleteLength: 14, maximumLength: 14) { data, _, isComplete, error in
        guard link.reads(c) else { return }
        guard let data, let h = StreamMessage.parseHeader(data) else {
            if isComplete || error != nil, let r = link.release(c) { fenceEnded("closed", r) }
            return
        }
        let deliver = { (payload: Data) in
            if c !== link.connection, h.kind == .pong, let r = link.fenceReturned(payload, on: c) { fenceEnded("pong", r) }
            readLoop(c)
        }
        if h.payloadLength == 0 { deliver(Data()); return }
        c.receive(minimumIncompleteLength: h.payloadLength, maximumLength: h.payloadLength) { data, _, isComplete, error in
            guard link.reads(c) else { return }
            guard let data else {
                if isComplete || error != nil, let r = link.release(c) { fenceEnded("closed", r) }
                return
            }
            deliver(data)
        }
    }
}

/// The stand-in's index of the client's connection `c` (by `c`'s local port), once it has accepted it.
func stubIndex(of c: NWConnection) -> Int? {
    guard case .hostPort(_, let port)? = c.currentPath?.localEndpoint else { return nil }
    return stub.queue.sync { stub.ports.first(where: { $0.value == port.rawValue })?.key }
}

/// Mode count: SessionLink.inputsOnSession through a script on this one thread.
func countMode(_ c0: NWConnection) -> Never {
    var bad = 0
    var seq: UInt32 = 0
    func expect(_ what: String, _ want: Int) {
        let got = link.inputsOnSession
        print("count: \(what): \(got)\(got == want ? "" : ", want \(want)")")
        if got != want { bad += 1 }
    }
    func inputs(_ n: Int) { for _ in 0..<n { seq += 1; link.send(message(.input, be32(seq))) } }
    func notInput() { link.send(message(.viewport, Data(#"{"width":1,"height":1}"#.utf8))) }
    func fence(_ from: NWConnection, _ to: NWConnection) -> Data {
        let nonce = randomNonce()
        link.handOver(from: from, to: to, fencePing: message(.ping, nonce), nonce: nonce)
        return nonce
    }
    expect("a new session's connection", 0)
    inputs(3); notInput()
    expect("three inputs and a viewport on it", 3)
    let c1 = connect()
    let n1 = fence(c0, c1)
    expect("a hand-over with nothing waiting restarts at 0", 0)
    inputs(2); notInput()
    expect("two inputs kept for the fence", 2)
    _ = link.fenceReturned(n1, on: c0)
    expect("the fence down: what waited went out on the connection it was counted for", 2)
    inputs(1)
    expect("one more, sent at once", 3)
    _ = link.hold(c1)
    inputs(2)
    expect("two held", 5)
    let c2 = connect()
    _ = link.adopt(c2)
    expect("adopt restarts at the two held, which go out on the new connection first", 2)
    inputs(1)
    expect("one more on it", 3)
    _ = link.hold(c2)
    inputs(2)
    expect("two held on it", 5)
    _ = link.unhold(c2)
    expect("unhold leaves it: what was held goes out on the connection it was counted for", 5)
    let c3 = connect()
    let n3 = fence(c2, c3)
    inputs(2)
    expect("a second hand-over, two kept", 2)
    let c4 = connect()
    _ = fence(c3, c4)
    expect("a hand-over while an earlier fence stands restarts at the two still waiting", 2)
    inputs(1)
    _ = link.hold(c4)
    inputs(1)
    expect("one more kept and one held", 4)
    let c5 = connect()
    _ = link.adopt(c5)
    expect("adopt with both fences up: all four wait for them, then go out on it", 4)
    _ = link.fenceReturned(n3, on: c2)
    expect("the first fence down", 4)
    _ = link.release(c3)
    expect("the second let go: the four go out", 4)
    inputs(1)
    expect("one more", 5)
    let c6 = connect()
    _ = fence(c5, c6)
    inputs(3)
    expect("three kept for a fence", 3)
    link.connection = nil
    expect("the session's connection gone: they still wait", 3)
    _ = link.dropHandOver()
    expect("a new session drops the hand-over, and what waited never goes out", 0)
    inputs(1)
    expect("an input with no connection goes nowhere", 0)
    let c7 = connect()
    link.connection = c7
    expect("a new session's connection", 0)
    inputs(2)
    expect("two on it", 2)
    let c8 = connect()
    let n8 = fence(c7, c8)
    inputs(1)
    let c9 = connect()
    link.connection = c9
    expect("the setter while a fence stands restarts at the one waiting, which goes out on the connection set", 1)
    _ = link.fenceReturned(n8, on: c7)
    inputs(1)
    expect("the fence down, one more", 2)
    link.connection = nil
    expect("the session's connection gone, nothing waiting: nothing counted", 0)
    let c10 = connect()
    link.connection = c10
    inputs(1)
    expect("a new session's connection, one input on it", 1)
    Thread.sleep(forTimeInterval: slow * 2 + 0.5)
    let connections = [c0, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10]
    let want = [3, 3, 5, 0, 0, 5, 0, 2, 0, 2, 1]
    let got = connections.map { c in stubIndex(of: c).map { i in stub.queue.sync { stub.inputsOn[i] ?? 0 } } ?? -1 }
    print("count: the stand-in read \(got) inputs on the eleven connections, want \(want)")
    if got != want { bad += 1 }
    print(bad == 0 ? "PASS" : "FAIL")
    exit(bad == 0 ? 0 : 1)
}

let old = connect()
link.connection = old
if mode == "count" { countMode(old) }
readLoop(old)
let start = now()

func sendNext() -> Bool {
    stateLock.lock(); defer { stateLock.unlock() }
    guard nextSeq <= total else { return false }
    link.send(message(.input, be32(nextSeq)))
    nextSeq += 1
    return true
}
let senderA = DispatchSource.makeTimerSource(queue: clientQueue)
senderA.schedule(deadline: .now(), repeating: 0.002)
senderA.setEventHandler { _ = sendNext() }
senderA.resume()
let senderB = DispatchSource.makeTimerSource(queue: .global())
senderB.schedule(deadline: .now(), repeating: 0.005)
senderB.setEventHandler { _ = sendNext() }
senderB.resume()
let pinger = DispatchSource.makeTimerSource(queue: clientQueue)
pinger.schedule(deadline: .now() + 0.03, repeating: 0.03)
pinger.setEventHandler {
    guard let c = link.connection else { return }
    c.send(content: message(.ping, withUnsafeBytes(of: now().bitPattern.bigEndian) { Data($0) }), completion: .contentProcessed { _ in })
}
pinger.resume()

Thread.sleep(forTimeInterval: handOverAt)
var adoptDuringFence: SessionLink.Released?? = nil
var extra: [NWConnection] = []
if ["hold", "holdclosed", "unhold"].contains(mode) {
    stateLock.lock()
    seqAtHandOver = nextSeq - 1
    handOverTime = now()
    if mode == "hold" { stub.queue.sync { _ = stub.muted.insert(0) } }
    if mode == "holdclosed" { stub.queue.sync { _ = stub.closed.insert(0); stub.conns[0].cancel() } }
    let holding = link.hold(old)
    stateLock.unlock()
    if !holding { print("hold refused"); exit(1) }
    if mode == "unhold" {
        Thread.sleep(forTimeInterval: 0.2)
        if let r = link.unhold(old) { fenceEnded("unhold", r) }
    } else {
        let new = connect()                    // the move's dial, while the hold keeps what is sent
        extra.append(new)
        Thread.sleep(forTimeInterval: 0.05)
        if let r = link.adopt(new) { fenceEnded("adopt", r) }
        readLoop(new)
    }
} else if mode == "twofences" {
    let new1 = connect(), new2 = connect()
    extra += [new1, new2]
    stateLock.lock()
    seqAtHandOver = nextSeq - 1
    handOverTime = now()
    let nonce1 = randomNonce()
    link.handOver(from: old, to: new1, fencePing: message(.ping, nonce1), nonce: nonce1)
    stateLock.unlock()
    readLoop(new1)
    Thread.sleep(forTimeInterval: 0.03)        // well inside the slow first connection's round trip
    stateLock.lock()
    let nonce2 = randomNonce()
    link.handOver(from: new1, to: new2, fencePing: message(.ping, nonce2), nonce: nonce2)
    stateLock.unlock()
    readLoop(new2)
    clientQueue.asyncAfter(deadline: .now() + releaseAfter) {
        if let r = link.release(old) { fenceEnded("timeout", r) }
        if let r = link.release(new1) { fenceEnded("timeout", r) }
    }
} else if mode == "twomoves" {
    let new1 = connect(), new2 = connect()
    extra += [new1, new2]
    stateLock.lock()
    seqAtHandOver = nextSeq - 1
    handOverTime = now()
    let nonce1 = randomNonce()
    link.handOver(from: old, to: new1, fencePing: message(.ping, nonce1), nonce: nonce1)
    stateLock.unlock()
    readLoop(new1)
    Thread.sleep(forTimeInterval: 0.5)         // the slow first connection's pong is back by now
    stateLock.lock()
    let nonce2 = randomNonce()
    link.handOver(from: new1, to: new2, fencePing: message(.ping, nonce2), nonce: nonce2)
    stateLock.unlock()
    readLoop(new2)
    clientQueue.asyncAfter(deadline: .now() + releaseAfter) {
        if let r = link.release(old) { fenceEnded("timeout", r) }
        if let r = link.release(new1) { fenceEnded("timeout", r) }
    }
} else if mode == "holdfence" || mode == "holdadopt" {
    let new1 = connect()
    extra.append(new1)
    stateLock.lock()
    seqAtHandOver = nextSeq - 1
    handOverTime = now()
    let nonce = randomNonce()
    link.handOver(from: old, to: new1, fencePing: message(.ping, nonce), nonce: nonce)
    stateLock.unlock()
    readLoop(new1)
    Thread.sleep(forTimeInterval: 0.01)
    stub.queue.sync { _ = stub.muted.insert(1) }   // the second connection's path is gone: nothing more of it arrives
    if !link.hold(new1) { print("hold refused"); exit(1) }
    if mode == "holdfence" { Thread.sleep(forTimeInterval: 0.4) }   // the first fence's pong comes back meanwhile
    let new2 = connect()
    extra.append(new2)
    if let r = link.adopt(new2) { fenceEnded("adopt", r) }
    readLoop(new2)
    clientQueue.asyncAfter(deadline: .now() + releaseAfter) {
        if let r = link.release(old) { fenceEnded("timeout", r) }
    }
} else if mode == "newsession" || mode == "newsessionhold" {
    // review-moves-b (the merge's lens): #13's session replacement while a hand-over's fence, or a hold,
    // stands, as StreamClient.adopt (a remote dial's winner) and connect do it: the session's connection
    // set to nil and cancelled, abandonMove's dropHandOver (its connections cancelled), then the new
    // session's connection set. Then a hold and an unhold on the new connection, as a later move's would
    // end: what waited for the old session must never reach the Mac, not even then; everything sent from
    // the new connection on arrives, in order; the old connection is no longer read.
    let new1 = connect()
    extra.append(new1)
    stateLock.lock()
    seqAtHandOver = nextSeq - 1
    handOverTime = now()
    if mode == "newsession" {
        let nonce = randomNonce()
        link.handOver(from: old, to: new1, fencePing: message(.ping, nonce), nonce: nonce)
    } else {
        _ = link.hold(old)
    }
    stateLock.unlock()
    if mode == "newsession" { readLoop(new1) }
    Thread.sleep(forTimeInterval: 0.05)            // inside the slow first connection's round trip
    let new2 = connect()
    extra.append(new2)
    stateLock.lock()
    seqAtDrop = nextSeq - 1
    let session = link.connection
    link.connection = nil
    session?.cancel()
    let dropped = link.dropHandOver()
    for c in dropped { c.cancel() }
    droppedCount = dropped.count
    readsOldAfterDrop = link.reads(old)
    link.connection = new2
    stateLock.unlock()
    readLoop(new2)
    Thread.sleep(forTimeInterval: 0.1)
    if !link.hold(new2) { print("hold on the new session refused"); exit(1) }
    Thread.sleep(forTimeInterval: 0.05)
    if let r = link.unhold(new2) { fenceEnded("unhold", r) }
    clientQueue.asyncAfter(deadline: .now() + releaseAfter) {
        if let r = link.release(old) { fenceEnded("timeout", r) }
        if let r = link.release(new1) { fenceEnded("timeout", r) }
    }
} else if mode == "adoptfence" {
    let new1 = connect(), new2 = connect()
    extra += [new1, new2]
    stateLock.lock()
    seqAtHandOver = nextSeq - 1
    handOverTime = now()
    let nonce = withUnsafeBytes(of: UInt64.random(in: .min ... .max)) { Data($0) }
    link.handOver(from: old, to: new1, fencePing: message(.ping, nonce), nonce: nonce)
    stateLock.unlock()
    readLoop(new1)
    Thread.sleep(forTimeInterval: 0.03)        // well inside the slow first connection's round trip
    adoptDuringFence = .some(link.adopt(new2))
    readLoop(new2)
    clientQueue.asyncAfter(deadline: .now() + releaseAfter) {
        if let r = link.release(old) { fenceEnded("timeout", r) }
    }
} else {
    let new = connect()
    extra.append(new)
    stateLock.lock()
    seqAtHandOver = nextSeq - 1
    handOverTime = now()
    if mode == "nofence" {
        link.connection = new                      // the hand-over before the fix
    } else {
        let nonce = withUnsafeBytes(of: UInt64.random(in: .min ... .max)) { Data($0) }
        link.handOver(from: old, to: new, fencePing: message(.ping, nonce), nonce: nonce)
    }
    stateLock.unlock()
    readLoop(new)
    clientQueue.asyncAfter(deadline: .now() + releaseAfter) {
        if let r = link.release(old) { fenceEnded("timeout", r) }
    }
}

while true { stateLock.lock(); let done = nextSeq > total; stateLock.unlock(); if done { break }; Thread.sleep(forTimeInterval: 0.05) }
Thread.sleep(forTimeInterval: max(releaseAfter, 1.0) + 0.5)
let sessionIndex = link.connection.flatMap(stubIndex)
let sessionCount = link.inputsOnSession
old.cancel(); for c in extra { c.cancel() }
Thread.sleep(forTimeInterval: 0.2)

let arrived = stub.queue.sync { stub.arrived }
var inversions = 0
for (a, b) in zip(arrived, arrived.dropFirst()) where b < a { inversions += 1 }
let increasing = inversions == 0
let set = Set(arrived)
let missing = (1...total).filter { !set.contains($0) }
let afterHandOverMissing = missing.filter { $0 > seqAtHandOver }
let dupes = arrived.count - set.count
print("mode \(mode): \(arrived.count) of \(total) inputs arrived, \(missing.count) missing (\(afterHandOverMissing.count) sent after the hand-over at #\(seqAtHandOver)), \(dupes) duplicates, \(inversions) inversions")
if let f = fence {
    print("fence: ended by \(f.how) after \(Int((f.seconds * 1000).rounded())) ms, \(f.held) held")
} else {
    print("fence: none ended")
}
if ends.count > 1 { print("ends: " + ends.map { "\($0.how) (\($0.held) out, \($0.waiting) waiting\($0.clear ? ", clear" : "")\($0.closed > 0 ? ", \($0.closed) to close" : ""))" }.joined(separator: ", ")) }
// Whatever the mode, the last end that let messages go says nothing stands any more (StreamClient closes the old
// connections then), and every end before it that let none go while some waited says something still stands.
let clearOK = ends.last.map { $0.clear } ?? true
    && ends.dropLast().allSatisfy { !($0.held == 0 && $0.waiting > 0) || !$0.clear }
// Each hand-over's old connection is handed back for closing exactly once, and only by an end that is clear
// (what waited, its viewport first, has gone out).
let fencesMade = ["ok": 1, "timeout": 1, "oldcloses": 1, "adoptfence": 1, "twofences": 2, "twomoves": 2, "holdfence": 1, "holdadopt": 1,
                  "hold": 0, "holdclosed": 0, "unhold": 0, "nofence": 0, "newsession": 0, "newsessionhold": 0][mode] ?? -1
#if OLD   // SessionLink before the review fixes knew nothing of it (its caller closed each old connection at its fence's end)
let closeOK = true
#else
let closeOK = ends.map(\.closed).reduce(0, +) == fencesMade && ends.allSatisfy { $0.clear || $0.closed == 0 }
#endif
var ok: Bool
if !clearOK { print("clear: wrong") }
if !closeOK { print("close: wrong (\(ends.map(\.closed)) for \(fencesMade) fences)") }
switch mode {
case "ok":
    ok = increasing && missing.isEmpty && dupes == 0 && fence?.how == "pong" && (fence?.held ?? 0) > 0
        && (fence?.seconds ?? 9) >= slow * 0.9 && (fence?.seconds ?? 9) < 1.0
case "nofence":
    ok = inversions > 0          // the hazard, reproduced: this check exists to catch it
case "timeout":
    ok = increasing && dupes == 0 && afterHandOverMissing.isEmpty && fence?.how == "timeout" && (fence?.held ?? 0) > 0
case "oldcloses":
    ok = increasing && dupes == 0 && afterHandOverMissing.isEmpty && fence?.how == "closed" && (fence?.seconds ?? 9) < 0.5
case "hold", "holdclosed":
    ok = increasing && dupes == 0 && afterHandOverMissing.isEmpty && fence?.how == "adopt" && (fence?.held ?? 0) > 0
case "unhold":
    ok = increasing && missing.isEmpty && dupes == 0 && fence?.how == "unhold" && (fence?.held ?? 0) > 0
case "twofences":
    // Both fences down by their pongs; what waited went out once, when the last of them was down.
    ok = increasing && missing.isEmpty && dupes == 0 && ends.count == 2 && ends.allSatisfy { $0.how == "pong" }
        && ends[0].held == 0 && ends[0].waiting > 0 && !ends[0].clear && ends[1].held > 0 && ends[1].waiting == 0 && ends[1].clear
case "twomoves":
    // Each fence down by its pong and clear; closeOK: each old connection handed back once (two in all).
    ok = increasing && missing.isEmpty && dupes == 0 && ends.count == 2 && ends.allSatisfy { $0.how == "pong" && $0.clear }
case "holdfence":
    // The first fence down by its pong with everything still waiting for the hold, then the adopt sent it.
    ok = increasing && missing.isEmpty && dupes == 0 && ends.count == 2 && ends[0].how == "pong" && ends[0].held == 0
        && ends[0].waiting > 0 && !ends[0].clear && ends[1].how == "adopt" && ends[1].held > 0 && ends[1].waiting == 0 && ends[1].clear
case "holdadopt":
    // The adopt with the first fence still up: everything waits for its pong, then goes out on the third.
    ok = increasing && missing.isEmpty && dupes == 0 && ends.count == 2 && ends[0].how == "adopt" && ends[0].held == 0
        && ends[0].waiting > 0 && !ends[0].clear && ends[1].how == "pong" && ends[1].held > 0 && ends[1].waiting == 0 && ends[1].clear
case "newsession", "newsessionhold":
    // A: sent before the hand-over or hold (on the first connection); B: after it, before the new session
    // (waited, then dropped: none may ever arrive); C: the new session's (all of it, in order).
    let a = arrived.filter { $0 <= seqAtHandOver }, b = arrived.filter { $0 > seqAtHandOver && $0 <= seqAtDrop }
    let c = arrived.filter { $0 > seqAtDrop }
    let cMissing = ((seqAtDrop + 1)...total).filter { !set.contains($0) }
    let inc = { (xs: [UInt32]) in zip(xs, xs.dropFirst()).allSatisfy { $0 < $1 } }
    print("newsession: sent before \(seqAtHandOver) (arrived \(a.count)), during \(seqAtDrop - seqAtHandOver) (arrived \(b.count)), after \(total - seqAtDrop) (arrived \(c.count), missing \(cMissing.count)); dropped \(droppedCount) connections; old read after the drop: \(readsOldAfterDrop); ends \(ends.map(\.how))")
    ok = b.isEmpty && cMissing.isEmpty && inc(a) && inc(c) && dupes == 0 && !readsOldAfterDrop && droppedCount == 1
        && seqAtDrop > seqAtHandOver && ends.count == 1 && ends[0].how == "unhold" && ends[0].clear && ends[0].held > 0
case "adoptfence":
    // The adopt left the fence up (nil), and the fence ended by its pong with everything in order.
    ok = increasing && missing.isEmpty && dupes == 0 && fence?.how == "pong" && (fence?.held ?? 0) > 0
        && adoptDuringFence != nil && adoptDuringFence! == nil
default:
    ok = false
}
// The count: every input meant for the session's last connection, and only those, as the Mac read them.
let readOnSession = stub.queue.sync { sessionIndex.flatMap { stub.inputsOn[$0] } }
let countOK = sessionIndex != nil && readOnSession == sessionCount
print("count: \(sessionCount) inputs counted for the session's connection (#\(sessionIndex.map(String.init) ?? "?")), the stand-in read \(readOnSession.map(String.init) ?? "none")")
ok = ok && (clearOK || mode == "nofence") && closeOK && countOK
print(ok ? "PASS" : "FAIL")
exit(ok ? 0 : 1)
