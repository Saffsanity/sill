import Foundation
import Network

// The encoder-free sound harness's device (docs/audio-plan.md §11, H5–H8; Scripts/audio/build.sh
// compiles it with Sources/StreamProtocol, iOSClient/AudioDecoder.swift, iOSClient/AudioPlayout.swift and
// Sources/SillHost/TestTone.swift as one module, so nothing here imports StreamProtocol). What the device's StreamClient does with the
// Mac's sound, minus a speaker: a hello that lists "aac-eld" first, pings every 0.25 s and stats every
// second (so a remote door never takes it for gone), every message read, every kind 29 parsed, each
// epoch's decoder made from its format, every packet decoded, and each decoded sample placed by its
// packet's stamp, where the test tone's click must sit at each whole second of the wall clock. The host
// runs on this Mac, so its stamps and this clock are one clock: a packet's age (arrival minus stamp) is
// a true age, as a frame's is.
//
// It plays nothing: no audio device is opened. The device's playout model (AudioPlayout) runs on these
// arrivals as the device runs it, with an ideal output in place of a player (its timeline from the first
// packet, a stand-in IO buffer of 5 ms and output latency of 10 ms): its floor, cover, need, late packets
// and jumps are in each second's line and the summary.
//
// usage: audiocheck HOST PORT SECONDS [--tls] [--no-audio] [--label NAME]
//   --tls       the remote door (TLS 1.3, ALPN sill/1, a throwaway key; the harness admits any)
//   --no-audio  a hello without the codec: the host must send no kind 29
// One line a second ("t=3 frames=60 fage=1.2/3.4 aud=100 aage=15.2/17.0 clicks=1 model late=0 …"), then
// one summary line, "AUDIOCHECK …", with every number the gates read.

setvbuf(stdout, nil, _IOLBF, 0)
let args = CommandLine.arguments
guard args.count >= 4, let port = UInt16(args[2]), let seconds = Double(args[3]) else {
    print("usage: audiocheck HOST PORT SECONDS [--tls] [--no-audio] [--label NAME]"); exit(2)
}
let host = args[1]
let useTLS = args.contains("--tls")
let playsAudio = !args.contains("--no-audio")
let label = args.firstIndex(of: "--label").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } ?? "audiocheck"
let queue = DispatchQueue(label: "audiocheck")
let rate = 48_000.0
let click = TestTone.click(sampleRate: rate)
let started = Date().timeIntervalSince1970

func message(_ kind: StreamMessageKind, _ payload: Data = Data()) -> Data {
    StreamMessage(kind: kind, timestamp: Date().timeIntervalSince1970, isKeyframe: false, payload: payload).serialized()
}
@Sendable func pct(_ v: [Double], _ q: Double) -> Double {
    guard !v.isEmpty else { return .nan }
    let s = v.sorted()
    return s[min(s.count - 1, Int((q * Double(s.count - 1)).rounded()))]
}
@Sendable func f1(_ x: Double) -> String { x.isNaN ? "–" : String(format: "%.1f", x) }

// MARK: - What arrived (on `queue`)

final class Tally {
    var frames = 0, framesSecond = 0, keyframes = 0
    var frameAges: [Double] = [], frameAgesSecond: [Double] = []
    var formats = 0, epochs: [Int] = [], packets = 0, packetsSecond = 0, seqGaps = 0, orphans = 0, starts = 0
    var packetAges: [Double] = [], packetAgesSecond: [Double] = []
    var firstPacketAt: Double?, lastPacketAt: Double?
    var nextSeq: [Int: UInt32] = [:]
    /// Each segment's first packet: its age (how long after its stamp it arrived).
    var segmentStartAges: [Double] = []
    var decodeFailures = 0
    /// Each whole second's click: its offset from the second, ms.
    var clickOffsets: [Int: Double] = [:], clicksSecond = 0
    var notAudioBytes = 0
}
let t = Tally()

// MARK: - The playout model (on `queue`), on these arrivals, with an ideal output

var model = AudioPlayout()
/// The output's clock: the sample `s` of its timeline goes out at `modelT0 + s ÷ rate`; a render reaches
/// `modelIO` ahead of now. Set at the first packet.
var modelT0: Double?
let modelIO = 0.005, modelOL = 0.010
var modelTimer: DispatchSourceTimer?
final class ModelTally {
    var placed = 0, late = 0, lateAfter2 = 0, jumps = 0, jumpsAfter3 = 0, joins = 0, dups = 0
    var coverMax = 0.0, needMax = 0.0, coverMaxAfter3 = 0.0, seconds = 0
    var behind: [Int] = []
}
let mt = ModelTally()
/// The device's monotonic clock, which the model counts arrivals on.
func monotonic() -> Double { ProcessInfo.processInfo.systemUptime }
func modelRead(_ now: Double) {
    guard let t0 = modelT0 else { return }
    let s = ((now + modelIO - t0) * rate).rounded(.down)
    _ = model.played(sample: s, at: t0 + s / rate, now: now)
}
func modelArm() {
    modelTimer?.cancel()
    modelTimer = nil
    guard let d = model.deadline else { return }
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: .now() + max(0, d - monotonic()), leeway: .nanoseconds(0))
    timer.setEventHandler {
        let now = monotonic()
        modelRead(now)
        _ = model.tick(now: max(now, model.deadline ?? now))
        modelArm()
    }
    timer.resume()
    modelTimer = timer
}

// The sound's timeline: the current run of decoded samples (left channel) placed by their stamps, from
// `runWall` on; a new segment, a seq gap or a new epoch starts a new run.
var decoder: AudioDecoder?
var format: (epoch: Int, frames: Int, priming: Int)?
var run: [Float] = []
var runWall = 0.0
var runPrimed = false        // the run's decoder started clean (a segment's first packet) or has passed its first packet
var searched = Set<Int>()

func place(_ samples: ArraySlice<Float>, at wall: Double) {
    let at = run.isEmpty ? 0 : Int(((wall - runWall) * rate).rounded())
    if run.isEmpty { runWall = wall }
    // A run is contiguous within a segment; a stamp more than 2 frames off where the run ends starts it anew.
    if !run.isEmpty, abs(at - run.count) > 2 { run = []; runWall = wall }
    run.append(contentsOf: samples)
    // Each whole second the run now covers with a margin: the click's best match, ±600 frames.
    let last = runWall + Double(run.count) / rate
    var second = Int((runWall + 600 / rate).rounded(.up))
    while Double(second) + Double(600 + click.count) / rate <= last {
        if !searched.contains(second) {
            searched.insert(second)
            let want = Int(((Double(second) - runWall) * rate).rounded())
            var best = -Double.infinity, lag = 0
            for l in -600...600 {
                var acc = 0.0
                let s = want + l
                for j in 0..<click.count { acc += Double(click[j]) * Double(run[s + j]) }
                if acc > best { best = acc; lag = l }
            }
            t.clickOffsets[second] = Double(lag) / rate * 1000
            t.clicksSecond += 1
        }
        second += 1
    }
    // Keep a second and a half.
    if run.count > Int(1.5 * rate) {
        let drop = run.count - Int(rate)
        run.removeFirst(drop)
        runWall += Double(drop) / rate
    }
}

func took(_ header: StreamHeader, _ payload: Data) {
    let now = Date().timeIntervalSince1970
    switch header.kind {
    case .frame:
        model.frame(stamp: header.timestamp, arrival: monotonic())
        t.frames += 1; t.framesSecond += 1
        if header.isKeyframe { t.keyframes += 1 }
        let age = (now - header.timestamp) * 1000
        t.frameAges.append(age); t.frameAgesSecond.append(age)
    case .audio:
        guard let m = AudioMessage.parse(payload) else { t.decodeFailures += 1; return }
        switch m {
        case .format(let f):
            t.formats += 1
            guard let epoch = f.epoch, let frames = f.framesPerPacket, f.codec == "aac-eld" else { return }
            t.epochs.append(epoch)
            if model.format(epoch: epoch, framesPerPacket: frames, primingFrames: f.primingFrames ?? 0, cookie: f.cookie ?? Data()) {
                model.latency(output: modelOL, io: modelIO, refresh: 1.0 / 60, streamFPS: 60)
            }
            if format?.epoch == epoch { return }   // the epoch already playing (a move's new connection)
            decoder = try? AudioDecoder(framesPerPacket: frames, cookie: f.cookie ?? Data())
            format = (epoch, frames, f.primingFrames ?? 0)
            run = []
            runPrimed = false
            print("\(label): format epoch \(epoch) \(f.codec ?? "?") \(f.sampleRate ?? 0) Hz \(f.channels ?? 0) ch, \(frames) frames (priming \(f.primingFrames ?? 0)), \(f.source ?? "?")\(f.app.map { " " + $0 } ?? "")")
        case .packets(let p):
            t.packets += p.packets.count; t.packetsSecond += p.packets.count
            if t.firstPacketAt == nil { t.firstPacketAt = now - started }
            t.lastPacketAt = now - started
            let age = (now - header.timestamp) * 1000
            t.packetAges.append(age); t.packetAgesSecond.append(age)
            guard let fmt = format, fmt.epoch == p.epoch, let dec = decoder else { t.orphans += 1; return }
            var gap = false
            if let next = t.nextSeq[p.epoch], next != p.seq { t.seqGaps += 1; gap = true }
            t.nextSeq[p.epoch] = p.seq &+ UInt32(p.packets.count)
            if p.segmentStart {
                t.starts += 1
                t.segmentStartAges.append(age)
                dec.reset()
                run = []
                runPrimed = true
            } else if gap {
                dec.reset()
                run = []
                runPrimed = false
            }
            for i in 0..<p.packets.count {
                let now = monotonic()
                if modelT0 == nil { modelT0 = now + modelIO }
                modelRead(now)
                _ = model.packet(epoch: p.epoch, seq: p.seq &+ UInt32(i), stamp: header.timestamp + Double(i * fmt.frames) / rate,
                                 segmentStart: p.segmentStart && i == 0, now: now)
            }
            modelArm()
            for (i, packet) in p.packets.enumerated() {
                let stamp = header.timestamp + Double(i * fmt.frames) / rate
                guard let (left, _) = dec.decode(packet) else { t.decodeFailures += 1; continue }
                if !runPrimed {
                    // A packet decoded on a decoder that did not start with its segment: noise. Dropped;
                    // from the next on the run is the signal (within -41 dB, exact by the fourth).
                    runPrimed = true
                    continue
                }
                let skip = (p.segmentStart && i == 0) ? min(fmt.priming, left.count) : 0
                place(left[skip...], at: stamp + Double(skip) / rate)
            }
        }
    default:
        break
    }
}

// MARK: - The connection

model.away(useTLS)
let parameters: NWParameters
if useTLS {
    guard let key = RemoteKey.generate(), let identity = RemoteIdentity(privateKey: key) else { print("no identity"); exit(1) }
    let tls = RemoteTLS.options(identity: identity.tls, role: .client(alpn: RemoteTLS.sessionALPN), verify: { _ in true }, queue: queue)
    parameters = RemoteTLS.parameters(tls: tls, dialing: true)
} else {
    let tcp = NWProtocolTCP.Options()
    tcp.noDelay = true
    parameters = NWParameters(tls: nil, tcp: tcp)
    parameters.serviceClass = .interactiveVideo
}
let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: parameters)

func readNext() {
    connection.receive(minimumIncompleteLength: StreamMessage.headerLength, maximumLength: StreamMessage.headerLength) { data, _, done, error in
        guard let data, let header = StreamMessage.parseHeader(data) else {
            if done || error != nil { print("\(label): the host closed the connection at \(f1(Date().timeIntervalSince1970 - started)) s"); finish() }
            return
        }
        if header.payloadLength == 0 { took(header, Data()); readNext(); return }
        connection.receive(minimumIncompleteLength: header.payloadLength, maximumLength: header.payloadLength) { payload, _, done, error in
            guard let payload, payload.count == header.payloadLength else {
                if done || error != nil { finish() }
                return
            }
            took(header, payload)
            readNext()
        }
    }
}

connection.stateUpdateHandler = { state in
    switch state {
    case .ready:
        // The hello first, as a device from 2026-09-25 on sends it; with the codec, one from 2026-09-27 on.
        var hello: [String: Any] = ["appVersion": "0.6", "protocol": 1, "device": label]
        if playsAudio { hello["audio"] = ["aac-eld"] }
        connection.send(content: message(.hello, try! JSONSerialization.data(withJSONObject: hello)), completion: .contentProcessed { _ in })
        readNext()
    case .failed(let e), .waiting(let e):
        print("\(label): connection \(e)"); finish()
    default: break
    }
}
connection.start(queue: queue)

// Pings every 0.25 s and stats every second, as the device sends them; one line a second.
var second = 0
let pinger = DispatchSource.makeTimerSource(queue: queue)
pinger.schedule(deadline: .now() + 0.25, repeating: 0.25)
var pings = 0
pinger.setEventHandler {
    var stamp = ProcessInfo.processInfo.systemUptime.bitPattern.bigEndian
    connection.send(content: message(.ping, Data(bytes: &stamp, count: 8)), completion: .contentProcessed { _ in })
    pings += 1
    guard pings % 4 == 0 else { return }
    second += 1
    let stats = #"{"fps":\#(t.framesSecond),"frameAgeMs":0,"rttMs":0,"device":"\#(label)"}"#
    connection.send(content: message(.clientStats, Data(stats.utf8)), completion: .contentProcessed { _ in })
    let fa = t.frameAgesSecond, pa = t.packetAgesSecond
    let m = model.takeSecond(now: monotonic())
    mt.seconds += 1
    mt.placed += m.placed; mt.late += m.late; mt.jumps += m.jumps; mt.joins += m.joins; mt.dups += m.duplicates
    if second > 2 { mt.lateAfter2 += m.late }
    if second > 3 { mt.jumpsAfter3 += m.jumps; mt.coverMaxAfter3 = max(mt.coverMaxAfter3, m.cover) }
    mt.coverMax = max(mt.coverMax, m.cover); mt.needMax = max(mt.needMax, m.need)
    if let b = m.behindMs { mt.behind.append(b) }
    print("t=\(second) frames=\(t.framesSecond) fage=\(f1(pct(fa, 0.5)))/\(f1(fa.max() ?? .nan)) aud=\(t.packetsSecond) aage=\(f1(pct(pa, 0.5)))/\(f1(pa.max() ?? .nan)) clicks=\(t.clicksSecond)"
          + " model late=\(m.late) placed=\(m.placed) cover=\(f1(m.cover * 1000)) need=\(f1(m.need * 1000)) behind=\(m.behindMs.map(String.init) ?? "–") jumps=\(m.jumps)")
    t.framesSecond = 0; t.packetsSecond = 0; t.frameAgesSecond = []; t.packetAgesSecond = []; t.clicksSecond = 0
}
pinger.resume()

var finished = false
func finish() {
    guard !finished else { return }
    finished = true
    pinger.cancel()
    connection.cancel()
    let offsets = t.clickOffsets.sorted { $0.key < $1.key }.map(\.value)
    let within = offsets.filter { abs($0) <= 1 }.count
    let span = (t.lastPacketAt ?? 0) - (t.firstPacketAt ?? 0)
    let perSecond = span > 0 ? Double(max(0, t.packets - 1)) / span : 0
    print("AUDIOCHECK \(label): frames=\(t.frames) keyframes=\(t.keyframes) frameAge p50 \(f1(pct(t.frameAges, 0.5))) p95 \(f1(pct(t.frameAges, 0.95))) max \(f1(t.frameAges.max() ?? .nan)) ms; "
          + "packets=\(t.packets) (\(String(format: "%.2f", perSecond))/s) formats=\(t.formats) epochs=\(t.epochs) segmentStarts=\(t.starts) seqGaps=\(t.seqGaps) orphans=\(t.orphans) decodeFailures=\(t.decodeFailures); "
          + "packetAge p50 \(f1(pct(t.packetAges, 0.5))) p95 \(f1(pct(t.packetAges, 0.95))) max \(f1(t.packetAges.max() ?? .nan)) ms; "
          + "segmentStartAges \(t.segmentStartAges.map { f1($0) }); first at \(f1(t.firstPacketAt ?? .nan)) s, last at \(f1(t.lastPacketAt ?? .nan)) s; "
          + "clicks=\(offsets.count) within1ms=\(within) offsets min \(f1(offsets.min() ?? .nan)) max \(f1(offsets.max() ?? .nan)) ms; "
          + "model: placed=\(mt.placed) late=\(mt.late) lateAfter2=\(mt.lateAfter2) jumps=\(mt.jumps) jumpsAfter3=\(mt.jumpsAfter3) joins=\(mt.joins) "
          + "dups=\(mt.dups) coverMax=\(f1(mt.coverMax * 1000)) coverMaxAfter3=\(f1(mt.coverMaxAfter3 * 1000)) needMax=\(f1(mt.needMax * 1000)) "
          + "behindMedian=\(mt.behind.isEmpty ? "–" : String(mt.behind.sorted()[mt.behind.count / 2]))")
    exit(0)
}
queue.asyncAfter(deadline: .now() + seconds) { finish() }
dispatchMain()
