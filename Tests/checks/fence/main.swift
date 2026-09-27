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
// No step of a mode counts on the clock. On GitHub's runner (xcode-27-arm64, a shared virtual M1),
// sleeps overran by 90 ms and more (2026-09-26), so a second hand-over meant to land inside the slow
// connection's round trip landed after its pong, a new session meant to drop a hand-over's fence
// found it already down, and modes failed where SessionLink had done right. Each step waits for what
// it needs instead. The senders send only as many inputs as a step lets them (`send`), and the step
// goes on once those are out; the rest are let go (`allow`) just before the step that ends a fence or
// a hold, so they race it as a user's would. The slow connection's line stalls from just before a
// hand-over (`slowLine.pause`) until the mode has taken every step that must come before that fence's
// pong, as an AWDL link can stall: what it carries arrives afterwards, in order and with its spacing.
// An end a mode expects is waited for (`settle`), for up to `patience`, before the caller's timeout
// lets go of what is left (`timeout`). Right after each hand-over from the slow connection, a pong for
// a regular ping sent before it comes back there (`stalePong`), as one can, and must end nothing. And
// the results are read once the stand-in has read every connection to its end, each closed after the
// last input, not after a fixed wait.
//
//   swiftc -O iOSClient/SessionLink.swift Sources/StreamProtocol/*.swift \
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
// path back: what waited goes out on the first connection, all of it, in order), and
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
// review-moves-b: newsession and newsessionhold (a new session while a hand-over's fence, or a hold,
// stands: what waited for the old session never reaches the Mac; see the mode below).
// pointer-visibility (2026-09-26, docs/pointer-visibility-plan.md §3.3), SessionLink's count of the input
// messages (kind 8) meant for the session's connection, which the Mac's pointer reports (kind 26) are
// judged by: in every mode above, once the stand-in has read every connection to its end, the count must
// equal the inputs it read on the session's last connection; and count (a script of sends and connection
// changes on one thread, no senders, pings or read loops, so each fence ends only where the script ends
// it: the count after every step, then what each of eleven connections delivered, read to its end).
// remote-bundle (2026-09-27, docs/remote-bundle-plan.md §7), the move home: a session through the remote
// door handed to the home door. remotehome (the first connection is TLS 1.3, the remote door's own
// parameters and keys (RemoteTLS, RemoteIdentity) with any key trusted both ways, the second plain TCP,
// the home door's: as `ok`, the fence's ping and pong inside TLS) and remotedead (the remote connection
// dies while the move home is under way, its home connection already made: the stand-in closes it, the
// client sees its end and only then holds, as StreamClient.rescue does after the loss, and adopts the
// home connection without a fence). The check compiles all of Sources/StreamProtocol for them.
//   (the old SessionLink needs $SP/review/fencecheck/oldshim.swift, which gives Released its `waiting`)
import Foundation
import Network

let modes = ["ok", "nofence", "timeout", "oldcloses", "hold", "holdclosed", "unhold", "adoptfence", "twofences", "twomoves",
             "holdfence", "holdadopt", "newsession", "newsessionhold", "count", "remotehome", "remotedead"]
/// The modes whose first connection is the remote door's TLS.
let remoteModes: Set<String> = ["remotehome", "remotedead"]
let mode = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "ok"
if !modes.contains(mode) { print("unknown mode \(mode); modes: \(modes.joined(separator: " "))"); exit(2) }
let slow = 0.12
let total: UInt32 = 600
let before: UInt32 = 100       // sent on the first connection before its hand-over or hold
let releaseAfter = 0.6         // timeout: the caller's timeout (StreamClient: 3 s), which a fence with no pong ends by
let patience = 5.0             // how long an end a mode expects may take (a pong, a close), well past any real round trip
let deadline = 20.0            // the check's own waits, where SessionLink has no part: past it, the machine has stopped

func message(_ kind: StreamMessageKind, _ payload: Data) -> Data {
    StreamMessage(kind: kind, timestamp: Date().timeIntervalSince1970, isKeyframe: false, payload: payload).serialized()
}
func randomNonce() -> Data { withUnsafeBytes(of: UInt64.random(in: .min ... .max)) { Data($0) } }
func be32(_ v: UInt32) -> Data { withUnsafeBytes(of: v.bigEndian) { Data($0) } }
func now() -> Double { ProcessInfo.processInfo.systemUptime }

/// Waits until `done`, looking every millisecond, for up to `seconds`; whether it came.
func wait(_ seconds: Double, until done: () -> Bool) -> Bool {
    let end = now() + seconds
    while !done() {
        if now() >= end { return false }
        Thread.sleep(forTimeInterval: 0.001)
    }
    return true
}

/// One of the check's own waits (a connection, the senders, the stand-in reading to the end): past
/// `deadline` the check stops and fails, saying so, instead of hanging.
func require(_ what: String, _ done: () -> Bool) {
    guard wait(deadline, until: done) else {
        print("mode \(mode): the check stalled: \(what) took more than \(Int(deadline)) s")
        print("FAIL")
        exit(1)
    }
}

// MARK: The stand-in for the Mac

/// One connection's way into the stand-in: each message goes on in order, `delay` after it arrived.
/// The check stalls it (`pause`) and lets it go on (`resume`) as an AWDL link stalls: nothing goes on
/// meanwhile, and the line's clock stands still too, so what was sent before the stall keeps its
/// spacing after it.
final class Line {
    private let queue: DispatchQueue
    private let delay: Double
    private let cond = NSCondition()
    private var paused = false
    private var pausedAt = 0.0
    private var stood = 0.0        // how long the line has stood still, in all

    init(_ label: String, delay: Double) {
        queue = DispatchQueue(label: label)
        self.delay = delay
    }

    /// The time, less every stall. Under `cond`.
    private var clock: Double { (paused ? pausedAt : now()) - stood }

    func pause() {
        cond.lock()
        if !paused { paused = true; pausedAt = now() }
        cond.unlock()
    }

    func resume() {
        cond.lock()
        if paused { paused = false; stood += now() - pausedAt; cond.broadcast() }
        cond.unlock()
    }

    /// Runs `deliver`, for what has just arrived, once the line has carried it for `delay`.
    func carry(_ deliver: @escaping () -> Void) {
        cond.lock()
        let due = clock + delay
        cond.unlock()
        queue.async { [self] in
            cond.lock()
            while paused || clock < due {
                if paused { cond.wait() } else { _ = cond.wait(until: Date(timeIntervalSinceNow: due - clock)) }
            }
            cond.unlock()
            deliver()
        }
    }
}

final class Stub {
    let queue = DispatchQueue(label: "stub")      // StreamServer's one network queue
    let listener: NWListener
    var conns: [NWConnection] = []
    var lines: [Line] = []
    var closed: Set<Int> = []
    var muted: Set<Int> = []
    var finished: Set<Int> = []                   // read to their end, through their line
    var arrived: [UInt32] = []
    var inputsOn: [Int: Int] = [:]                // the inputs (kind 8) read on each connection
    var ready = DispatchSemaphore(value: 0)
    /// The remote door's stand-in (remotehome, remotedead): TLS 1.3 with the remote door's own
    /// parameters, a key of its own and any client key trusted. Its connections join the same list.
    var tlsListener: NWListener?
    var tlsReady = DispatchSemaphore(value: 0)

    init(tls: Bool) throws {
        listener = try NWListener(using: .tcp, on: .any)
        listener.stateUpdateHandler = { [weak self] s in if case .ready = s { self?.ready.signal() } }
        listener.newConnectionHandler = { [weak self] c in self?.accept(c) }
        listener.start(queue: queue)
        if tls {
            guard let key = RemoteKey.generate(), let identity = RemoteIdentity(privateKey: key) else {
                print("mode \(mode): no identity for the TLS door"); print("FAIL"); exit(1)
            }
            let options = RemoteTLS.options(identity: identity.tls, role: .server, queue: queue) { _, _ in true }
            let params = RemoteTLS.parameters(tls: options, dialing: false)
            params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            let l = try NWListener(using: params)
            l.stateUpdateHandler = { [weak self] s in if case .ready = s { self?.tlsReady.signal() } }
            l.newConnectionHandler = { [weak self] c in self?.accept(c) }
            l.start(queue: queue)
            tlsListener = l
        }
    }
    var port: NWEndpoint.Port { listener.port! }
    var tlsPort: NWEndpoint.Port { tlsListener!.port! }

    private func accept(_ c: NWConnection) {
        let i = conns.count
        conns.append(c)
        c.start(queue: queue)
        // Each connection's messages go through its own line, in order, then to `queue`.
        let line = Line("line\(i)", delay: i == 0 ? slow : 0)
        lines.append(line)
        read(c, i, line)
        // Frames, so a pong sits behind other traffic as on the real link: 20 KB every 10 ms.
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 0.01, repeating: 0.01)
        t.setEventHandler { [weak self] in
            guard let self, !self.closed.contains(i), !self.finished.contains(i) else { return }
            c.send(content: message(.frame, Data(count: 20_000)), completion: .contentProcessed { _ in })
        }
        t.resume()
        timers.append(t)
    }
    var timers: [DispatchSourceTimer] = []

    private func read(_ c: NWConnection, _ i: Int, _ line: Line) {
        c.receive(minimumIncompleteLength: 14, maximumLength: 14) { [weak self] data, _, _, _ in
            guard let self else { return }
            // The connection's end (the client closed it, or the stand-in did): through the line too,
            // so it comes after everything that arrived before it.
            let end = { line.carry { self.queue.async { _ = self.finished.insert(i) } } }
            guard let data, let h = StreamMessage.parseHeader(data) else { end(); return }
            let got = { (payload: Data) in
                line.carry { self.queue.async { self.process(h, payload, c, i) } }
                self.read(c, i, line)
            }
            if h.payloadLength == 0 { got(Data()); return }
            c.receive(minimumIncompleteLength: h.payloadLength, maximumLength: h.payloadLength) { data, _, _, _ in
                guard let data, data.count == h.payloadLength else { end(); return }
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

    // What a mode does to the stand-in, each on its queue.
    /// It takes nothing more from connection `i` (its path is gone): what it reads of it from now on, it drops.
    func mute(_ i: Int) { queue.sync { _ = muted.insert(i) } }
    /// It closes connection `i`.
    func close(_ i: Int) { queue.sync { _ = closed.insert(i); conns[i].cancel() } }
    /// It sends `data` on connection `i`, behind the frames already sent there.
    func send(_ data: Data, on i: Int) { queue.sync { conns[i].send(content: data, completion: .contentProcessed { _ in }) } }
    func line(_ i: Int) -> Line { queue.sync { lines[i] } }
}

// MARK: The client, as StreamClient drives the link

let link = SessionLink()
let clientQueue = DispatchQueue(label: "sill.net")
let stub = try Stub(tls: remoteModes.contains(mode))
if stub.ready.wait(timeout: .now() + deadline) == .timedOut { print("mode \(mode): the stand-in never listened"); print("FAIL"); exit(1) }
if stub.tlsListener != nil, stub.tlsReady.wait(timeout: .now() + deadline) == .timedOut {
    print("mode \(mode): the stand-in's TLS door never listened"); print("FAIL"); exit(1)
}
/// The device's key for the TLS door (remotehome, remotedead).
let deviceIdentity: RemoteIdentity? = remoteModes.contains(mode) ? RemoteKey.generate().flatMap { RemoteIdentity(privateKey: $0) } : nil

typealias End = (how: String, held: Int, waiting: Int, clear: Bool, closed: Int)
let stateLock = NSLock()
var nextSeq: UInt32 = 1
var budget: UInt32 = 0          // the senders send inputs up to this number, then wait for a step to let them go on
var seqAtHandOver: UInt32 = 0
var fence: (how: String, held: Int, seconds: Double)?
var ends: [End] = []            // every fence or hold that ended, in order
var seqAtDrop: UInt32 = 0
var droppedCount = -1
var readsOldAfterDrop = true
var connections: [NWConnection] = []          // the client's, in the order made (the stand-in numbers them the same)
var sawEnd: Set<ObjectIdentifier> = []        // connections whose read loop met their end
/// A regular ping's payload, stamped before any hand-over: its pong comes back on the first
/// connection after the hand-over (`stalePong`), where it must end nothing.
let stalePayload = withUnsafeBytes(of: (now() - 1).bitPattern.bigEndian) { Data($0) }
var staleRead = false
var staleEnded: Int?            // the ends that came with the stale pong (none), once it has been read

/// A connection to the stand-in: plain TCP (the home door), or with `tls` its TLS door, as a device
/// dials the remote door (any key trusted: this check is about order, not trust).
func connect(tls: Bool = false) -> NWConnection {
    let c: NWConnection
    if tls, let identity = deviceIdentity {
        let options = RemoteTLS.options(identity: identity.tls, role: .client(alpn: RemoteTLS.sessionALPN), verify: { _ in true }, queue: clientQueue)
        c = NWConnection(host: "127.0.0.1", port: stub.tlsPort, using: RemoteTLS.parameters(tls: options, dialing: true))
    } else {
        c = NWConnection(host: "127.0.0.1", port: stub.port, using: .tcp)
    }
    let ready = DispatchSemaphore(value: 0)
    c.stateUpdateHandler = { s in if case .ready = s { ready.signal() } }
    c.start(queue: clientQueue)
    connections.append(c)
    let n = connections.count
    if ready.wait(timeout: .now() + deadline) == .timedOut { print("mode \(mode): connection \(n) never became ready"); print("FAIL"); exit(1) }
    require("the stand-in accepting connection \(n)") { stub.queue.sync { stub.conns.count >= n } }
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
            if isComplete || error != nil { ended(c) }
            return
        }
        let deliver = { (payload: Data) in
            if c !== link.connection, h.kind == .pong, let r = link.fenceReturned(payload, on: c) { fenceEnded("pong", r) }
            if h.kind == .pong, payload == stalePayload { stateLock.lock(); staleRead = true; stateLock.unlock() }
            readLoop(c)
        }
        if h.payloadLength == 0 { deliver(Data()); return }
        c.receive(minimumIncompleteLength: h.payloadLength, maximumLength: h.payloadLength) { data, _, isComplete, error in
            guard link.reads(c) else { return }
            guard let data else {
                if isComplete || error != nil { ended(c) }
                return
            }
            deliver(data)
        }
    }
}

/// `c`'s read loop met its end: as StreamClient does, that releases its fence. Noted only after, so a
/// mode that waits for it (holdclosed) goes on once whatever the close did has been done.
func ended(_ c: NWConnection) {
    if let r = link.release(c) { fenceEnded("closed", r) }
    stateLock.lock(); sawEnd.insert(ObjectIdentifier(c)); stateLock.unlock()
}

/// The stand-in's index of the client's connection `c`: the stand-in numbers them in the order made.
func stubIndex(of c: NWConnection) -> Int? { connections.firstIndex { $0 === c } }

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
    // Every connection closed after what it carries, and read by the stand-in to its end, as the modes do.
    let script = [c0, c1, c2, c3, c4, c5, c6, c7, c8, c9, c10]
    clientQueue.sync {
        for c in script { c.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in }) }
    }
    require("the stand-in reading every connection to its end") { stub.queue.sync { stub.finished.count >= connections.count } }
    let want = [3, 3, 5, 0, 0, 5, 0, 2, 0, 2, 1]
    let got = script.map { c in stubIndex(of: c).map { i in stub.queue.sync { stub.inputsOn[i] ?? 0 } } ?? -1 }
    print("count: the stand-in read \(got) inputs on the eleven connections, want \(want)")
    if got != want { bad += 1 }
    print(bad == 0 ? "PASS" : "FAIL")
    exit(bad == 0 ? 0 : 1)
}

let old = connect(tls: remoteModes.contains(mode))
link.connection = old
if mode == "count" { countMode(old) }
readLoop(old)
let slowLine = stub.line(0)

func sendNext() -> Bool {
    stateLock.lock(); defer { stateLock.unlock() }
    guard nextSeq <= total, nextSeq <= budget else { return false }
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

/// Lets the senders go on to `n` inputs past those sent so far (to the last one with `n` nil), and
/// returns the number they stop at.
@discardableResult
func allow(_ n: UInt32? = nil) -> UInt32 {
    stateLock.lock(); defer { stateLock.unlock() }
    let upTo = n.map { min(total, nextSeq - 1 + $0) } ?? total
    budget = max(budget, upTo)
    return upTo
}

/// Lets the senders send `n` more inputs (the rest with `n` nil), and waits until they have.
func send(_ n: UInt32? = nil) {
    let upTo = allow(n)
    require("sending input #\(upTo)") { stateLock.lock(); defer { stateLock.unlock() }; return nextSeq > upTo }
}

/// Waits until `n` fences or holds in all have ended, for up to `within` (a mode's own ends come in a
/// round trip; a mutant's may never).
func settle(_ n: Int, within seconds: Double = patience) {
    _ = wait(seconds) { stateLock.lock(); defer { stateLock.unlock() }; return ends.count >= n }
}

/// The caller's timeout (StreamClient.fenceTimeout): lets go of the fences still up on `olds`, on the
/// client's queue, once the ends the mode expects have come, or `settle` has given up on them.
func timeout(_ olds: [NWConnection]) {
    clientQueue.sync {
        for c in olds { if let r = link.release(c) { fenceEnded("timeout", r) } }
    }
}

/// A pong for a regular ping sent before the hand-over comes back on the first connection, behind
/// its frames, as one can while the fence is up. Only the fence's own pong may end the fence.
func stalePong() {
    stateLock.lock(); let endsBefore = ends.count; stateLock.unlock()
    stub.send(message(.pong, stalePayload), on: 0)
    let read = wait(patience) { stateLock.lock(); defer { stateLock.unlock() }; return staleRead }
    stateLock.lock(); staleEnded = read ? ends.count - endsBefore : nil; stateLock.unlock()
}

/// The hand-over the fenced modes begin with: the slow first connection's line stalls with what it
/// carries still on its way, three more inputs go into it, and the session moves to `new` behind a
/// fence whose ping goes last on the first connection. Then the stale pong.
func handOverFromSlow(to new: NWConnection) {
    slowLine.pause()
    send(3)
    stateLock.lock()
    seqAtHandOver = nextSeq - 1
    let nonce = randomNonce()
    link.handOver(from: old, to: new, fencePing: message(.ping, nonce), nonce: nonce)
    stateLock.unlock()
    readLoop(new)
    stalePong()
}

/// A second hand-over, from `from` (not slow) to `to`.
func handOver(from: NWConnection, to: NWConnection) {
    stateLock.lock()
    let nonce = randomNonce()
    link.handOver(from: from, to: to, fencePing: message(.ping, nonce), nonce: nonce)
    stateLock.unlock()
    readLoop(to)
}

send(before)                                    // inputs, pings and frames on the first connection
var adoptDuringFence: SessionLink.Released?? = nil
switch mode {
case "ok":
    let new = connect()
    handOverFromSlow(to: new)
    send(5)                                     // these wait behind the fence,
    allow()                                     // the rest go on while it comes down
    slowLine.resume()
    settle(1)                                   // by its pong
    timeout([old])
case "nofence":
    let new = connect()
    slowLine.pause()
    send(3)
    stateLock.lock()
    seqAtHandOver = nextSeq - 1
    link.connection = new                       // the hand-over before the fix
    stateLock.unlock()
    readLoop(new)
    send(3)
    require("an input sent on the second connection arriving") { stub.queue.sync { stub.arrived.contains { $0 > seqAtHandOver } } }
    allow()
    slowLine.resume()                           // and the first connection's last inputs arrive after it
    timeout([old])
case "timeout":
    let new = connect()
    stub.mute(0)                                // nothing more of the first connection arrives: no pong
    handOverFromSlow(to: new)
    send(5)
    allow()
    slowLine.resume()
    settle(1, within: releaseAfter)             // nothing ends the fence,
    timeout([old])                              // so the caller's timeout does
case "oldcloses":
    let new = connect()
    handOverFromSlow(to: new)
    send(5)
    allow()
    stub.close(0)                               // the stand-in closes the first connection during the fence,
    settle(1)                                   // which releases it at once
    slowLine.resume()
    timeout([old])
case "hold", "holdclosed":
    stateLock.lock()
    seqAtHandOver = nextSeq - 1
    if mode == "hold" { stub.mute(0) }          // a pulled cable delivers nothing more
    let holding = link.hold(old)
    stateLock.unlock()
    if !holding { print("hold refused"); exit(1) }
    if mode == "holdclosed" {
        stub.close(0)                           // and the connection closes, which must not release the hold onto it
        _ = wait(patience) { stateLock.lock(); defer { stateLock.unlock() }; return sawEnd.contains(ObjectIdentifier(old)) }
    }
    send(5)                                     // held
    let new = connect()                         // the move's dial, while the hold keeps what is sent
    allow()
    if let r = link.adopt(new) { fenceEnded("adopt", r) }
    readLoop(new)
case "unhold":
    stateLock.lock()
    seqAtHandOver = nextSeq - 1
    let holding = link.hold(old)
    stateLock.unlock()
    if !holding { print("hold refused"); exit(1) }
    send(5)                                     // held until the path comes back
    allow()
    if let r = link.unhold(old) { fenceEnded("unhold", r) }
case "adoptfence":
    let new1 = connect(), new2 = connect()
    handOverFromSlow(to: new1)
    send(3)
    adoptDuringFence = .some(link.adopt(new2))  // while the first fence is up: it stays up
    readLoop(new2)
    send(3)
    allow()
    slowLine.resume()
    settle(1)
    timeout([old])
case "twofences":
    let new1 = connect(), new2 = connect()
    handOverFromSlow(to: new1)
    send(3)
    handOver(from: new1, to: new2)              // while the first fence is up
    send(3)
    settle(1)                                   // the second fence's pong, quick: what waits stays for the first
    allow()
    slowLine.resume()
    settle(2)
    timeout([old, new1])
case "twomoves":
    let new1 = connect(), new2 = connect()
    handOverFromSlow(to: new1)
    send(3)
    slowLine.resume()
    settle(1)                                   // the first fence down, clear
    send(3)                                     // on the second connection
    allow()
    handOver(from: new1, to: new2)
    settle(2)
    timeout([old, new1])
case "holdfence", "holdadopt":
    let new1 = connect()
    handOverFromSlow(to: new1)
    send(3)
    stub.mute(1)                                // the second connection's path is gone: nothing more of it arrives
    if !link.hold(new1) { print("hold refused"); exit(1) }
    send(3)
    if mode == "holdfence" {
        slowLine.resume()
        settle(1)                               // the first fence's pong: everything still waits for the hold
        send(3)
    }
    let new2 = connect()
    allow()
    if let r = link.adopt(new2) { fenceEnded("adopt", r) }
    readLoop(new2)
    if mode == "holdadopt" {
        slowLine.resume()
        settle(2)                               // the first fence's pong, after the adopt, lets it all go
    }
    timeout([old])
case "newsession", "newsessionhold":
    // review-moves-b (the merge's lens): #13's session replacement while a hand-over's fence, or a hold,
    // stands, as StreamClient.adopt (a remote dial's winner) and connect do it: the session's connection
    // set to nil and cancelled, abandonMove's dropHandOver (its connections cancelled), then the new
    // session's connection set. Then a hold and an unhold on the new connection, as a later move's would
    // end: what waited for the old session must never reach the Mac, not even then; everything sent from
    // the new connection on arrives, in order; the old connection is no longer read.
    let new1 = connect()
    if mode == "newsession" {
        handOverFromSlow(to: new1)              // the fence stands until the drop: the slow line stalls
    } else {
        stateLock.lock()
        seqAtHandOver = nextSeq - 1
        _ = link.hold(old)
        stateLock.unlock()
    }
    send(3)                                     // wait for the fence or the hold, and go with it
    let new2 = connect()
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
    send(3)                                     // the new session's, straight out
    if !link.hold(new2) { print("hold on the new session refused"); exit(1) }
    send(3)
    allow()
    if let r = link.unhold(new2) { fenceEnded("unhold", r) }
    slowLine.resume()
    timeout([old, new1])
case "remotehome":
    // The move home: from the remote door's TLS connection (slow, like a VPN's) to the home door's.
    let new = connect()
    handOverFromSlow(to: new)
    send(5)                                     // these wait behind the fence, which crosses TLS both ways,
    allow()                                     // the rest go on while it comes down
    slowLine.resume()
    settle(1)                                   // by its pong
    timeout([old])
case "remotedead":
    // The remote connection dies while the move home is under way: its home connection is made and
    // ready, then the stand-in closes the remote one, the client sees the end and only then holds (the
    // rescue), and adopts the home connection without a fence.
    let new = connect()
    stub.close(0)
    _ = wait(patience) { stateLock.lock(); defer { stateLock.unlock() }; return sawEnd.contains(ObjectIdentifier(old)) }
    stateLock.lock()
    seqAtHandOver = nextSeq - 1
    let holding = link.hold(old)
    stateLock.unlock()
    if !holding { print("hold refused after the remote connection's end"); exit(1) }
    send(5)                                     // held
    allow()
    if let r = link.adopt(new) { fenceEnded("adopt", r) }
    readLoop(new)
default:
    fatalError("a mode without a case")
}

// Every input sent, then every connection closed after the last of them: the results are read once
// the stand-in has read each connection to its end, so nothing sent can still be on its way.
send()
senderA.cancel()
senderB.cancel()
pinger.cancel()
// Every input has gone to the link: what it counted for the session's connection, which the Mac's pointer
// reports are judged by, and which connection that is.
let sessionIndex = link.connection.flatMap(stubIndex)
let sessionCount = link.inputsOnSession
slowLine.resume()
clientQueue.sync {
    for c in connections { c.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in }) }
}
if remoteModes.contains(mode) {
    // TLS's end does not reach the stand-in's reads while the device leaves the stand-in's frames on
    // that connection unread (it stopped reading it at the fence): the device resets it instead, once
    // the stand-in has read everything the fence let through (nothing is sent on it after the fence).
    _ = wait(patience) { stub.queue.sync { stub.finished.count >= connections.count - 1 } }
    clientQueue.sync { if old.state == .ready { old.forceCancel() } }
}
require("the stand-in reading every connection to its end") { stub.queue.sync { stub.finished.count >= connections.count } }
let arrived = stub.queue.sync { stub.arrived }
stateLock.lock()                                // held to the end: nothing ends after this
for c in connections { c.cancel() }

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
// The stale pong, in the modes that hand over from the slow connection: read there, and it ended nothing.
let staleSent = ["ok", "timeout", "oldcloses", "adoptfence", "twofences", "twomoves", "holdfence", "holdadopt", "newsession", "remotehome"].contains(mode)
let staleOK = !staleSent || staleEnded == 0
if staleSent {
    print(staleEnded == nil ? "stale pong: never read on the first connection" : "stale pong: read on the first connection, \(staleEnded == 0 ? "ended nothing" : "ENDED \(staleEnded!) (only the fence's own pong may)")")
}
// Whatever the mode, the last end that let messages go says nothing stands any more (StreamClient closes the old
// connections then), and every end before it that let none go while some waited says something still stands.
let clearOK = ends.last.map { $0.clear } ?? true
    && ends.dropLast().allSatisfy { !($0.held == 0 && $0.waiting > 0) || !$0.clear }
// Each hand-over's old connection is handed back for closing exactly once, and only by an end that is clear
// (what waited, its viewport first, has gone out).
let fencesMade = ["ok": 1, "timeout": 1, "oldcloses": 1, "adoptfence": 1, "twofences": 2, "twomoves": 2, "holdfence": 1, "holdadopt": 1,
                  "hold": 0, "holdclosed": 0, "unhold": 0, "nofence": 0, "newsession": 0, "newsessionhold": 0,
                  "remotehome": 1, "remotedead": 0][mode] ?? -1
#if OLD   // SessionLink before the review fixes knew nothing of it (its caller closed each old connection at its fence's end)
let closeOK = true
#else
let closeOK = ends.map(\.closed).reduce(0, +) == fencesMade && ends.allSatisfy { $0.clear || $0.closed == 0 }
#endif
var ok: Bool
if !clearOK { print("clear: wrong") }
if !closeOK { print("close: wrong (\(ends.map(\.closed)) for \(fencesMade) fences)") }
switch mode {
case "ok", "remotehome":
    // Its pong, a round trip of the slow connection at least after the hand-over, let out what waited.
    ok = increasing && missing.isEmpty && dupes == 0 && fence?.how == "pong" && (fence?.held ?? 0) > 0
        && (fence?.seconds ?? 0) >= slow * 0.9
case "nofence":
    ok = inversions > 0          // the hazard, reproduced: this check exists to catch it
case "timeout":
    ok = increasing && dupes == 0 && afterHandOverMissing.isEmpty && fence?.how == "timeout" && (fence?.held ?? 0) > 0
case "oldcloses":
    ok = increasing && dupes == 0 && afterHandOverMissing.isEmpty && fence?.how == "closed" && (fence?.held ?? 0) > 0
case "hold", "holdclosed", "remotedead":
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
let readOnSession = stub.queue.sync { sessionIndex.map { stub.inputsOn[$0] ?? 0 } }
let countOK = readOnSession == sessionCount
print("count: \(sessionCount) inputs counted for the session's connection (#\(sessionIndex.map(String.init) ?? "?")), the stand-in read \(readOnSession.map(String.init) ?? "none")")
ok = ok && (clearOK || mode == "nofence") && closeOK && staleOK && countOK
print(ok ? "PASS" : "FAIL")
exit(ok ? 0 : 1)
