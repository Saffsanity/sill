// The message-reader check (docs/remote-bundle-plan.md §11, H5): iOSClient/MessageReader.swift on
// its own, with StreamProtocol's StreamMessage.swift, against a stand-in Mac on loopback. Each case
// has a fresh listener and connection; the stand-in writes bytes as the case says, and the device
// side reads them with a MessageReader whose callbacks this check records on the device's queue.
//
//   swiftc -O iOSClient/MessageReader.swift Sources/StreamProtocol/StreamMessage.swift \
//     Tests/checks/message-reader/main.swift -o .build/checks/message-reader/check
//   .build/checks/message-reader/check [CASE...]
//
// Cases: random (2,000 messages of 0 B to 3 MB, 21 of them empty, of every kind and one no build
// knows, written in random chunks of 1 B to 300 KB with random pauses: every one delivered byte for
// byte and in order, every byte reported once, no read over 256 KB, each payload in at least one
// read per 256 KB), burst (six 3 MB frames written at once: still no read over 256 KB), slow (a
// 1 MB frame at 2 Mbit/s: a read reported at least every 0.3 s while it comes; the plan's 3 MB at
// 1 Mbit/s would take 24 s), eof (the end in the middle of a payload: .closed, nothing delivered),
// eofheader (a header and the end, there before the reader looks: the same, and no read after the
// end), eofbetween (two messages and the end, there before the reader looks: both, then .closed
// without an error, and no read after the end, which would fail with ENODATA), eoflater (the end
// 0.2 s after two messages: the same), toobig (a frame announcing 40 MB and
// a window list announcing 4 MB + 1: .tooBig, nothing read after the header), caps (a 4 MB window
// list and a 5 MB frame: both delivered), stop and stopmid (stillReads false between messages and
// in the middle of a payload: no callback after it, stillReads asked at most once more, and after
// the stop between messages nothing read: a second reader finds the next message whole), stopend
// (the last message stops the reading and the end came with it: no end reported after it). Every
// callback is checked to run on the reader's queue. Prints "ok" or "FAIL" per check; exits 1 on any
// failure.
import Foundation
import Network

var failures = 0
func check(_ ok: Bool, _ what: String) {
    print(ok ? "ok   \(what)" : "FAIL \(what)")
    if !ok { failures += 1 }
}
func now() -> Double { ProcessInfo.processInfo.systemUptime }

// MARK: Messages whose bytes can be checked

/// A small deterministic generator (SplitMix64), so a failing run can be repeated.
struct Rand {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func int(_ range: ClosedRange<Int>) -> Int {
        range.lowerBound + Int(next() % UInt64(range.upperBound - range.lowerBound + 1))
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    /// Log-uniform in 1...max: most small, some large.
    mutating func logSize(_ max: Int) -> Int { Swift.max(1, Int(exp(unit() * log(Double(max))))) }
}

/// Message `index`'s payload: its bytes follow from the index alone.
func payload(_ index: Int, _ length: Int) -> Data {
    var d = Data(count: length)
    d.withUnsafeMutableBytes { raw in
        let words = length / 8
        let p = raw.baseAddress!
        for w in 0..<words {
            let v = (UInt64(index) << 40) ^ UInt64(w) &* 0x9E3779B97F4A7C15
            p.storeBytes(of: v, toByteOffset: w * 8, as: UInt64.self)
        }
        for b in (words * 8)..<length { p.storeBytes(of: UInt8(truncatingIfNeeded: index &+ b), toByteOffset: b, as: UInt8.self) }
    }
    return d
}

func message(_ index: Int, _ kind: StreamMessageKind, _ length: Int) -> Data {
    StreamMessage(kind: kind, timestamp: Double(index), isKeyframe: index % 7 == 0, payload: payload(index, length)).serialized()
}

/// A header alone, announcing `length` bytes of `kind`.
func header(_ kind: StreamMessageKind, _ length: Int) -> Data {
    var d = StreamMessage(kind: kind, timestamp: 1, isKeyframe: false, payload: Data()).serialized()
    d.replaceSubrange(10..<14, with: withUnsafeBytes(of: UInt32(length).bigEndian) { Data($0) })
    return d
}

// MARK: The stand-in Mac and the device side

/// What the device side saw. Touched only on `device` (the reader's queue).
final class Seen {
    var reads: [(t: Double, n: Int)] = []
    var messages: [(header: StreamHeader, payload: Data, reads: Int)] = []
    var readsInMessage = 0
    var ends: [MessageReader.End] = []
    var reading = true
    var stoppedAt: Double?
    var asksAfterStop = 0
    var callbacksAfterStop = 0
}

/// The stand-in's end of the connection, set on `mac` once accepted.
final class Accepted { var connection: NWConnection? }

final class Rig {
    let mac = DispatchQueue(label: "mac")
    let device = DispatchQueue(label: "device")
    let listener: NWListener
    private let accepted = Accepted()
    var server: NWConnection? { accepted.connection }
    let client: NWConnection
    let seen = Seen()
    /// Called on `device` for each message, after it is recorded (a case may stop reading there).
    var onMessage: ((Seen) -> Void)?

    init() {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: 0)
        listener = try! NWListener(using: params)
        let ready = DispatchSemaphore(value: 0)
        let serverReady = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { if case .ready = $0 { ready.signal() } }
        listener.newConnectionHandler = { [mac, accepted] c in
            accepted.connection = c
            c.stateUpdateHandler = { if case .ready = $0 { serverReady.signal() } }
            c.start(queue: mac)
        }
        listener.start(queue: mac)
        guard ready.wait(timeout: .now() + 5) == .success, let port = listener.port else { fatalError("no listener") }
        client = NWConnection(host: "127.0.0.1", port: port, using: .tcp)
        let clientReady = DispatchSemaphore(value: 0)
        client.stateUpdateHandler = { if case .ready = $0 { clientReady.signal() } }
        client.start(queue: device)
        guard clientReady.wait(timeout: .now() + 5) == .success, serverReady.wait(timeout: .now() + 5) == .success else { fatalError("no connection") }
    }

    /// Starts the reader on the device's queue.
    func read() {
        device.async { [self] in
            let seen = self.seen
            MessageReader(connection: client,
                          stillReads: { [device] in
                              dispatchPrecondition(condition: .onQueue(device))
                              if !seen.reading { seen.asksAfterStop += 1 }
                              return seen.reading
                          },
                          onBytes: { [device] n in
                              dispatchPrecondition(condition: .onQueue(device))
                              if !seen.reading { seen.callbacksAfterStop += 1 }
                              seen.reads.append((now(), n))
                              seen.readsInMessage += 1
                          },
                          onMessage: { [device] header, payload in
                              dispatchPrecondition(condition: .onQueue(device))
                              if !seen.reading { seen.callbacksAfterStop += 1 }
                              seen.messages.append((header, payload, seen.readsInMessage))
                              seen.readsInMessage = 0
                              self.onMessage?(seen)
                          },
                          onEnd: { [device] end in
                              dispatchPrecondition(condition: .onQueue(device))
                              if !seen.reading { seen.callbacksAfterStop += 1 }
                              seen.ends.append(end)
                          }).start()
        }
    }

    /// Writes `data` on the stand-in's side; `done` once it was taken. `final`: the end (FIN) goes
    /// with it, so the device's last read tends to bring both.
    func write(_ data: Data, final: Bool = false, done: @escaping () -> Void = {}) {
        mac.async { [self] in
            if final {
                server!.send(content: data, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in done() })
            } else {
                server!.send(content: data, completion: .contentProcessed { _ in done() })
            }
        }
    }

    /// The stand-in's end of the connection (FIN).
    func finish() {
        mac.async { [self] in server!.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in }) }
    }

    /// Waits (up to `limit` seconds) until `done` holds on the device's queue.
    @discardableResult
    func wait(_ limit: Double, until done: @escaping (Seen) -> Bool) -> Bool {
        let deadline = now() + limit
        while now() < deadline {
            if device.sync(execute: { done(seen) }) { return true }
            usleep(5_000)
        }
        return device.sync { done(seen) }
    }

    func look<T>(_ f: (Seen) -> T) -> T { device.sync { f(seen) } }

    func close() {
        client.forceCancel()
        mac.sync { server?.forceCancel() }
        listener.cancel()
    }
}

func isClosed(_ e: MessageReader.End) -> Bool { if case .closed = e { return true }; return false }
func tooBig(_ e: MessageReader.End) -> StreamHeader? { if case .tooBig(let h) = e { return h }; return nil }

// MARK: The cases

func random() {
    let rig = Rig()
    var r = Rand(state: 20260926)
    let count = 2000
    var sizes: [Int] = []
    for _ in 0..<count {
        let u = r.unit()
        sizes.append(u < 0.65 ? r.int(0...1024) : u < 0.90 ? r.int(1025...65536) : u < 0.98 ? r.int(65537...1 << 20) : r.int((1 << 20) + 1...3 << 20))
    }
    for i in stride(from: 5, to: count, by: 97) { sizes[i] = 0 }   // empty payloads (an empty window list)
    let kinds: [StreamMessageKind] = [.frame, .windowList, .thumbnail, .appIcon, .pong, .unknown]
    var chosen: [StreamMessageKind] = []
    for _ in 0..<count { chosen.append(kinds[r.int(0...kinds.count - 1)]) }
    // Unknown kinds must be read and delivered like any other (the reader never judges a kind).
    let total = sizes.reduce(0) { $0 + $1 + StreamMessage.headerLength }
    rig.read()
    // The stand-in: the messages one after another, cut into chunks of 1 B to 300 KB, sent one at a
    // time, with a pause of up to 3 ms before one chunk in twenty.
    var w = Rand(state: 7)
    var index = 0
    var pending = Data()
    func next() {
        while pending.count < 300_000, index < count {
            // StreamMessage has no .unknown to send: an unknown kind is a raw kind byte of 200.
            var m = message(index, chosen[index] == .unknown ? .frame : chosen[index], sizes[index])
            if chosen[index] == .unknown { m[m.startIndex] = 200 }
            pending.append(m)
            index += 1
        }
        guard !pending.isEmpty else { return }
        let n = min(pending.count, w.logSize(300_000))
        let chunk = pending.prefix(n)
        pending.removeFirst(n)
        let pause = w.unit() < 0.05 ? w.unit() * 0.003 : 0
        rig.write(Data(chunk)) {
            if pause > 0 { rig.mac.asyncAfter(deadline: .now() + pause) { next() } } else { next() }
        }
    }
    rig.mac.async { next() }
    let started = now()
    let all = rig.wait(60) { $0.messages.count >= count }
    let seconds = now() - started
    check(all, "random: \(rig.look { $0.messages.count }) of \(count) messages delivered (\(total / 1_000_000) MB in \(String(format: "%.1f", seconds)) s)")
    var intact = true, ordered = true, piecesOK = true
    rig.look { seen in
        for (i, m) in seen.messages.enumerated() where i < count {
            if Int(m.header.timestamp) != i { ordered = false; continue }
            let kind: StreamMessageKind = chosen[i] == .unknown ? .unknown : chosen[i]
            if m.header.kind != kind || m.header.payloadLength != sizes[i] || m.header.isKeyframe != (i % 7 == 0) || m.payload != payload(i, sizes[i]) {
                intact = false
            }
            // A header is one read; a payload at least one per 256 KB.
            let needed = 1 + (sizes[i] + MessageReader.piece - 1) / MessageReader.piece
            if m.reads < needed { piecesOK = false }
        }
    }
    check(ordered, "random: in order")
    check(intact, "random: every message byte for byte (kind, length, keyframe flag, payload), unknown kinds included")
    check(piecesOK, "random: each payload reported in at least one read per 256 KB")
    let (sum, largest) = rig.look { ($0.reads.reduce(0) { $0 + $1.n }, $0.reads.map(\.n).max() ?? 0) }
    check(sum == total, "random: every byte reported once (\(sum) of \(total))")
    check(largest <= MessageReader.piece, "random: no read over 256 KB (largest \(largest))")
    check(rig.look { $0.ends.isEmpty }, "random: no end while the connection is open")
    rig.close()
}

func burst() {
    let rig = Rig()
    let big = 3 << 20
    var all = Data()
    for i in 0..<6 { all.append(message(i, .frame, big)) }
    rig.write(all)                       // written before the reader starts: the socket holds a lot
    usleep(200_000)
    rig.read()
    check(rig.wait(20) { $0.messages.count == 6 }, "burst: six 3 MB frames delivered")
    let largest = rig.look { $0.reads.map(\.n).max() ?? 0 }
    check(largest <= MessageReader.piece, "burst: no read over 256 KB (largest \(largest))")
    check(rig.look { $0.messages.allSatisfy { $0.reads >= 1 + big / MessageReader.piece } }, "burst: each frame in at least 12 reads after its header")
    check(rig.look { $0.messages.enumerated().allSatisfy { $0.element.payload == payload($0.offset, big) } }, "burst: byte for byte")
    rig.close()
}

func slow() {
    let rig = Rig()
    let length = 1 << 20
    let m = message(1, .frame, length)
    rig.read()
    // 2 Mbit/s: 4 KB every 16 ms.
    var sent = 0
    let t0 = now()
    func next() {
        guard sent < m.count else { return }
        let n = min(4096, m.count - sent)
        let chunk = m.subdata(in: sent..<sent + n)
        sent += n
        rig.write(chunk) { rig.mac.asyncAfter(deadline: .now() + 0.016) { next() } }
    }
    rig.mac.async { next() }
    check(rig.wait(15) { $0.messages.count == 1 }, "slow: a 1 MB frame at 2 Mbit/s delivered (\(String(format: "%.1f", now() - t0)) s)")
    let times = rig.look { $0.reads.map(\.t) }
    let gaps = zip(times.dropFirst(), times).map { $0 - $1 }
    let worst = gaps.max() ?? .infinity
    check(times.count > 20 && worst <= 0.3, "slow: a read reported at least every 0.3 s while it came (\(times.count) reads, the longest gap \(String(format: "%.3f", worst)) s)")
    check(rig.look { $0.messages.first?.payload == payload(1, length) }, "slow: byte for byte")
    rig.close()
}

func eof() {
    let rig = Rig()
    rig.read()
    var partial = header(.frame, 100_000)
    partial.append(payload(3, 50_000))
    rig.write(partial) { rig.finish() }
    check(rig.wait(5) { !$0.ends.isEmpty }, "eof: the end in the middle of a payload ends the reading")
    check(rig.look { $0.ends.count == 1 && isClosed($0.ends[0]) }, "eof: as .closed, once")
    check(rig.look { $0.messages.isEmpty }, "eof: the message cut short is not delivered")
    if case .closed(let error)? = rig.look({ $0.ends.first }) { check(error == nil, "eof: a clean end carries no error (\(error.map { "\($0)" } ?? "none"))") }
    rig.close()
}

func eofAfterHeader() {
    // A header and the end, both there before the reader looks: the header's read brings the end.
    let rig = Rig()
    rig.write(header(.windowList, 100), final: true)
    usleep(200_000)
    rig.read()
    check(rig.wait(5) { !$0.ends.isEmpty }, "eofheader: the end right after a header ends the reading")
    check(rig.look { $0.ends.count == 1 && isClosed($0.ends[0]) && $0.messages.isEmpty }, "eofheader: as .closed, once, nothing delivered")
    if case .closed(let error)? = rig.look({ $0.ends.first }) { check(error == nil, "eofheader: a clean end carries no error (\(error.map { "\($0)" } ?? "none"))") }
    rig.close()
}

func eofBetween() {
    // Two messages and the end, all there before the reader looks: the last piece's read brings
    // the end with it, and nothing may be read after it.
    let rig = Rig()
    rig.write(message(1, .windowList, 1000))
    rig.write(message(2, .frame, 300_000), final: true)
    usleep(200_000)
    rig.read()
    check(rig.wait(5) { !$0.ends.isEmpty }, "eofbetween: the end after two messages ends the reading")
    check(rig.look { $0.messages.count == 2 && $0.messages[1].payload == payload(2, 300_000) }, "eofbetween: both messages first, whole")
    check(rig.look { $0.ends.count == 1 && isClosed($0.ends[0]) }, "eofbetween: then .closed, once")
    if case .closed(let error)? = rig.look({ $0.ends.first }) { check(error == nil, "eofbetween: a clean end carries no error (\(error.map { "\($0)" } ?? "none"))") }
    rig.close()
}

func eofLater() {
    // Two messages, then the end 0.2 s later while the reader waits for the next header.
    let rig = Rig()
    rig.read()
    rig.write(message(1, .windowList, 1000))
    rig.write(message(2, .frame, 300_000)) { rig.mac.asyncAfter(deadline: .now() + 0.2) { rig.finish() } }
    check(rig.wait(5) { !$0.ends.isEmpty }, "eoflater: the end after two messages ends the reading")
    check(rig.look { $0.messages.count == 2 && $0.ends.count == 1 && isClosed($0.ends[0]) }, "eoflater: both messages, then .closed, once")
    if case .closed(let error)? = rig.look({ $0.ends.first }) { check(error == nil, "eoflater: a clean end carries no error (\(error.map { "\($0)" } ?? "none"))") }
    rig.close()
}

func tooBigCase(_ kind: StreamMessageKind, _ length: Int, _ what: String) {
    let rig = Rig()
    rig.read()
    var d = header(kind, length)
    d.append(Data(count: 65536))           // what follows the header must never be read
    rig.write(d)
    check(rig.wait(5) { !$0.ends.isEmpty }, "toobig: \(what) ends the reading")
    check(rig.look { $0.ends.count == 1 && tooBig($0.ends[0])?.payloadLength == length && tooBig($0.ends[0])?.kind == kind }, "toobig: \(what) as .tooBig with its header")
    usleep(300_000)
    check(rig.look { $0.reads.map(\.n) == [StreamMessage.headerLength] && $0.messages.isEmpty }, "toobig: \(what): nothing read after the header")
    rig.close()
}

func caps() {
    let rig = Rig()
    rig.read()
    var d = message(1, .windowList, StreamMessage.maxOtherHostPayload)
    d.append(message(2, .frame, 5 << 20))
    rig.write(d)
    check(rig.wait(20) { $0.messages.count == 2 }, "caps: a 4 MB window list and a 5 MB frame (each within its own cap) delivered")
    check(rig.look { $0.ends.isEmpty }, "caps: and the reading goes on")
    rig.close()
}

func stop() {
    let rig = Rig()
    let count = 300
    rig.onMessage = { seen in
        if seen.messages.count == 100 { seen.reading = false; seen.stoppedAt = now() }
    }
    rig.read()
    var all = Data()
    for i in 0..<count { all.append(message(i, .thumbnail, 50_000)) }
    rig.write(all)
    rig.wait(5) { !$0.reading }
    usleep(500_000)
    check(rig.look { $0.messages.count == 100 }, "stop: nothing delivered after stillReads said false (\(rig.look { $0.messages.count }) of 100)")
    check(rig.look { $0.callbacksAfterStop == 0 }, "stop: no callback after it")
    check(rig.look { $0.asksAfterStop <= 1 }, "stop: stillReads asked at most once more (\(rig.look { $0.asksAfterStop }))")
    // Nothing was read after it: a second reader on the same connection finds message 100 whole,
    // header first. A read that went out anyway would have taken its header.
    let found = DispatchSemaphore(value: 0)
    var next: (header: StreamHeader, payload: Data)?
    rig.device.async {
        MessageReader(connection: rig.client, stillReads: { next == nil }, onBytes: { _ in },
                      onMessage: { header, payload in next = (header, payload); found.signal() },
                      onEnd: { _ in found.signal() }).start()
    }
    _ = found.wait(timeout: .now() + 5)
    let whole = rig.device.sync { next.map { Int($0.header.timestamp) == 100 && $0.payload == payload(100, 50_000) } ?? false }
    check(whole, "stop: no read after it (a second reader finds message 100 whole)")
    rig.close()
}

func stopAtEnd() {
    // Two messages and the end, all there before the reader looks, so the last piece's read brings
    // the end with it (as in eofbetween); the last message stops the reading (a move's fence coming
    // back on the old connection). The end is then not this reader's to report.
    let rig = Rig()
    rig.onMessage = { seen in
        if seen.messages.count == 2 { seen.reading = false; seen.stoppedAt = now() }
    }
    rig.write(message(1, .windowList, 1000))
    rig.write(message(2, .frame, 300_000), final: true)
    usleep(200_000)
    rig.read()
    rig.wait(5) { !$0.reading }
    usleep(300_000)
    check(rig.look { $0.messages.count == 2 && $0.messages[1].payload == payload(2, 300_000) }, "stopend: both messages delivered, whole")
    check(rig.look { $0.ends.isEmpty && $0.callbacksAfterStop == 0 }, "stopend: no end reported after the message that stopped the reading, though the end came with it")
    check(rig.look { $0.asksAfterStop <= 1 }, "stopend: stillReads asked at most once more (\(rig.look { $0.asksAfterStop }))")
    rig.close()
}

func stopMid() {
    let rig = Rig()
    rig.read()
    let m = message(1, .frame, 3 << 20)
    // 8 Mbit/s: the frame takes 3 s; stop 0.5 s in.
    var sent = 0
    func next() {
        guard sent < m.count else { return }
        let n = min(16384, m.count - sent)
        let chunk = m.subdata(in: sent..<sent + n)
        sent += n
        rig.write(chunk) { rig.mac.asyncAfter(deadline: .now() + 0.016) { next() } }
    }
    rig.mac.async { next() }
    usleep(500_000)
    let readsBefore = rig.look { seen -> Int in seen.reading = false; seen.stoppedAt = now(); return seen.reads.count }
    usleep(1_000_000)
    check(readsBefore > 3, "stopmid: reads came before the stop (\(readsBefore))")
    check(rig.look { $0.callbacksAfterStop == 0 && $0.messages.isEmpty && $0.ends.isEmpty }, "stopmid: no callback after stillReads said false in the middle of a payload")
    check(rig.look { $0.asksAfterStop <= 1 }, "stopmid: no read after it (stillReads asked \(rig.look { $0.asksAfterStop }) more times, at most 1)")
    rig.close()
}

let cases: [(String, () -> Void)] = [
    ("random", random), ("burst", burst), ("slow", slow), ("eof", eof), ("eofheader", eofAfterHeader), ("eofbetween", eofBetween), ("eoflater", eofLater),
    ("toobig", { tooBigCase(.frame, 40 << 20, "a frame announcing 40 MB"); tooBigCase(.windowList, (4 << 20) + 1, "a window list announcing 4 MB + 1") }),
    ("caps", caps), ("stop", stop), ("stopend", stopAtEnd), ("stopmid", stopMid),
]
let wanted = Set(CommandLine.arguments.dropFirst())
for (name, run) in cases where wanted.isEmpty || wanted.contains(name) { run() }
print(failures == 0 ? "message-reader: every check passed" : "message-reader: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
