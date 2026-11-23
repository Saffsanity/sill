// recordcheck: the recording rig's device (docs/recording-plan.md, Tests, "The rig"). It connects to a loopback test
// host as a device does (a hello listing aac-eld when it records sound, the Desktop picked, pings and stats with
// `recording`), and records the stream with the app's own StreamRecorder, compiled into it with StreamProtocol,
// SillAudio's AudioDecoder, KeyframeRecovery and the three rules (build.sh): the count, the ask at "1" kept from
// any other ask, the light, the asks while "Starting…", the chain's asks, space, and the stop, as
// StreamClient+Recording does them. Its movies go into OUT, never a Documents folder; OUT/summary.json says what
// happened, for moviecheck and run.py.
//
//   recordcheck PORT OUT SECONDS [--start S] [--stop S] [--sound] [--next-display-at S] [--kill-at S]
//               [--free-start BYTES --free-scale K]
//
// --start: Start tapped S seconds in (the count; the ask at S + 2, the light at S + 3); --stop: Stop tapped; --kill-at:
// the process ends itself with SIGKILL then, mid-recording (the movie must still open: fragments); --free-start and
// --free-scale: the free space the space rule reads, BYTES less K times the bytes the light says; --next-display-at:
// a kind 47 then (a test host with SILL_TEST_DISPLAYS steps to its next stop, another size: a new part).
import Foundation
import Network

setvbuf(stdout, nil, _IOLBF, 0)
var args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    defer { args.removeSubrange(i...(i + 1)) }
    return args[i + 1]
}
func flag(_ name: String) -> Bool {
    guard let i = args.firstIndex(of: name) else { return false }
    args.remove(at: i)
    return true
}
let startAt = Double(option("--start") ?? "") ?? 2
let stopAt = Double(option("--stop") ?? "") ?? 20
let killAt = Double(option("--kill-at") ?? "")
let nextDisplayAt = Double(option("--next-display-at") ?? "")
let freeStart = Int64(option("--free-start") ?? "")
let freeScale = Double(option("--free-scale") ?? "") ?? 1
let withSound = flag("--sound")
guard args.count == 3, let port = UInt16(args[0]), let seconds = Double(args[2]) else {
    print("usage: recordcheck PORT OUT SECONDS [--start S] [--stop S] [--sound] [--next-display-at S] [--kill-at S] [--free-start B --free-scale K]")
    exit(2)
}
let out = URL(fileURLWithPath: args[1], isDirectory: true)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let net = DispatchQueue(label: "sill.net")
let began = StreamRecorder.hostNow()
func since() -> Double { StreamRecorder.hostNow() - began }
func f2(_ x: Double) -> String { String(format: "%.2f", x) }
func say(_ s: String) { print("[\(f2(since()))] \(s)") }

// MARK: - The session, on `net`

var lastSets: Data?
var lastKeyframe: StreamRecorder.Frame?
var framesSinceKeyframe = 0
var lastFormat: AudioFormat?
var recorder: StreamRecorder?
var recordings: Int?
var frames = 0, keyframes = 0, packets = 0, worstRttMs: Int?

func message(_ kind: StreamMessageKind, _ payload: Data) -> Data {
    StreamMessage(kind: kind, timestamp: Date().timeIntervalSince1970, isKeyframe: false, payload: payload).serialized()
}

let tcp = NWProtocolTCP.Options()
tcp.noDelay = true
let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: NWParameters(tls: nil, tcp: tcp))
func send(_ kind: StreamMessageKind, _ payload: Data = Data()) {
    connection.send(content: message(kind, payload), completion: .contentProcessed { _ in })
}

func took(_ header: StreamHeader, _ payload: Data) {
    let arrival = StreamRecorder.hostNow()
    switch header.kind {
    case .parameterSets:
        if payload != lastSets { framesSinceKeyframe += 1 }   // a new source: the kept keyframe is not its picture
        lastSets = payload
        recorder?.parameterSets(payload, arrival: arrival)
    case .frame:
        frames += 1
        if header.isKeyframe {
            keyframes += 1
            lastKeyframe = StreamRecorder.Frame(id: -1, data: payload, stamp: header.timestamp, arrival: arrival, isKeyframe: true)
            framesSinceKeyframe = 0
        } else {
            framesSinceKeyframe += 1
        }
        recorder?.frame(payload, stamp: header.timestamp, isKeyframe: header.isKeyframe, arrival: arrival)
    case .audio:
        guard let m = AudioMessage.parse(payload) else { return }
        if case .format(let f) = m { lastFormat = f } else { packets += 1 }
        recorder?.audio(m, stamp: header.timestamp)
    case .windowList:
        if let list = Wire.decode(WindowList.self, from: payload) { recordings = list.recordings }
    case .pong:
        guard payload.count == 8 else { return }
        let sent = Double(bitPattern: payload.readBigEndian(UInt64.self, at: 0))
        let ms = Int(((StreamRecorder.hostNow() - sent) * 1000).rounded())
        worstRttMs = max(worstRttMs ?? 0, ms)
    default:
        break
    }
}

func readNext() {
    connection.receive(minimumIncompleteLength: StreamMessage.headerLength, maximumLength: StreamMessage.headerLength) { data, _, done, error in
        guard let data, let header = StreamMessage.parseHeader(data) else {
            if done || error != nil { DispatchQueue.main.async { say("the host closed the connection"); stopRecording(.sessionEnded) } }
            return
        }
        if header.payloadLength == 0 { took(header, Data()); readNext(); return }
        connection.receive(minimumIncompleteLength: header.payloadLength, maximumLength: header.payloadLength) { payload, _, done, error in
            guard let payload, payload.count == header.payloadLength else {
                if done || error != nil { DispatchQueue.main.async { stopRecording(.sessionEnded) } }
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
        var hello: [String: Any] = ["appVersion": "0.7.0", "protocol": 1, "device": "recordcheck"]
        if withSound { hello["audio"] = ["aac-eld"] }
        send(.hello, try! JSONSerialization.data(withJSONObject: hello))
        send(.selectSource, Data(#"{"desktop":{}}"#.utf8))
        readNext()
    case .failed(let e), .waiting(let e):
        print("connection: \(e)"); exit(3)
    default:
        break
    }
}
connection.start(queue: net)

// MARK: - The recording, on the main queue (StreamClient+Recording's part)

var phase = RecordingPolicy.Phase.idle
var lastAsk: Double?
var heldAsk = false
var startAsks = 0, lastStartAsk: Double?, lightAt: Double?
var start: RecordingPolicy.StartPoint?
var asks: [Double] = []
var startedAt: Double?
var progress: [[String: Any]] = []
var ending: String?
var lowSaid = false
var lastBytes: Int64 = 0
let bytesLock = NSLock()

/// The recording's ask (rule 2): now, at its second (never two held at once; a start's held ask goes on with
/// "Starting…" once it has gone), as StreamClient+Recording's. True when it went now. Main queue.
@discardableResult
func ask(forStart: Bool) -> Bool {
    let now = ProcessInfo.processInfo.systemUptime
    switch RecordingPolicy.keyframeAsk(now: now, lastAsk: lastAsk, recoveryDueUntil: nil) {
    case .now:
        send(.keyframeRequest)
        lastAsk = now
        asks.append(since())
        if forStart { startAsks += 1; lastStartAsk = now }
        say("asked for a keyframe\(forStart ? " (the start's \(startAsks))" : " (the chain broke)")")
        return true
    case .at(let t):
        guard !heldAsk else { return false }
        heldAsk = true
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, t - now)) {
            heldAsk = false
            if ask(forStart: forStart), forStart, phase == .starting { scheduleStarting() }
        }
        return false
    case .awaitRecovery:
        return true
    }
}

/// While "Starting…": the next ask or the give-up, one step pending at a time.
var startingStep = 0
func scheduleStarting() {
    guard phase == .starting, let lightAt else { return }
    startingStep += 1
    let step = startingStep
    let now = ProcessInfo.processInfo.systemUptime
    let wait = KeyframeRecovery.answerWait(worstRttMs: net.sync { worstRttMs })
    switch RecordingPolicy.starting(now: now, lightAt: lightAt, asks: startAsks, lastAsk: lastStartAsk, wait: wait) {
    case .askAt(let t):
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, t - now)) {
            guard phase == .starting, startingStep == step else { return }
            if ask(forStart: true) { scheduleStarting() }
        }
    case .giveUpAt(let t):
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, t - now)) {
            if phase == .starting, startingStep == step { stopRecording(.gaveUp) }
        }
    case .giveUp:
        stopRecording(.gaveUp)
    }
}

func one() {
    let (sets, kept, format) = net.sync { (lastSets, lastKeyframe, lastFormat) }
    var setup = StreamRecorder.Setup(folder: out, start: Date(), withSound: withSound)
    setup.device = "Mac"
    if let freeStart {
        setup.freeSpace = { freeStart - Int64(freeScale * Double(bytesLock.withLock { lastBytes })) }
    }
    let rec = StreamRecorder(setup)
    rec.onEvent = { event in
        switch event {
        case .started:
            phase = .recording
            startedAt = since()
            say("the movie's 0:00 is known: recording")
        case .progress(let s, let bytes, let space):
            bytesLock.withLock { lastBytes = bytes }
            var p: [String: Any] = ["at": since(), "bytes": bytes, "light": RecordingPolicy.Copy.light(seconds: s, bytes: bytes, minutesLeft: nil)]
            if let s { p["seconds"] = s }
            switch space {
            case .fine: p["space"] = "fine"
            case .low(let m):
                p["space"] = "low \(m)"
                if !lowSaid { lowSaid = true; say("space low: \(RecordingPolicy.Copy.lowSpoken(m))") }
            case .stop:
                p["space"] = "stop"
                stopRecording(.space)
            }
            progress.append(p)
        case .askKeyframe:
            ask(forStart: false)
        case .failed(let why):
            say("the writer failed: \(why)")
            stopRecording(.writerFailed(why))
        }
    }
    net.sync {
        rec.begin(sets: sets, lastKeyframe: kept, audioFormat: format)
        recorder = rec
    }
    phase = .counting(1)
    say("\"1\": the recorder taps the stream; \(kept == nil ? "no keyframe kept" : "the last keyframe kept")")
    ask(forStart: true)
}

func light() {
    guard let rec = net.sync(execute: { recorder }) else { return }
    lightAt = ProcessInfo.processInfo.systemUptime
    phase = .starting   // the light: the stats say `recording` from here ("Starting…" included)
    let decided = net.sync { rec.light(arrival: StreamRecorder.hostNow(), lastKeyframe: lastKeyframe, framesSinceKeyframe: framesSinceKeyframe) }
    start = decided
    say("the light: \(decided)")
    if case .atNextKeyframe = decided { scheduleStarting() }
}

func stopRecording(_ why: RecordingPolicy.Ending) {
    guard ending == nil else { return }
    ending = "\(why)"
    guard let rec = net.sync(execute: { () -> StreamRecorder? in
        let r = recorder
        r?.closeTaps()
        recorder = nil
        return r
    }) else {
        finish(nil); return
    }
    let at = StreamRecorder.hostNow()
    phase = .finishing
    say("stop: \(why)")
    rec.stop(arrival: at) { outcome in finish(outcome) }
}

func finish(_ outcome: StreamRecorder.Outcome?) {
    let summary: [String: Any] = [
        "start": start.map { s -> String in
            switch s { case .atLight(.sinceAsk): return "sinceAsk"; case .atLight(.lastKeyframe): return "lastKeyframe"; case .atNextKeyframe: return "nextKeyframe" }
        } ?? "none",
        "ending": ending ?? "none",
        "startedAt": startedAt ?? -1,
        "asks": asks,
        "movies": outcome?.movies.map(\.path) ?? [],
        "partStarts": outcome?.partStarts ?? [],
        "failure": outcome?.failure ?? NSNull(),
        "frames": net.sync { frames }, "keyframes": net.sync { keyframes }, "packets": net.sync { packets },
        "recordings": net.sync { recordings } ?? NSNull(),
        "progress": progress,
    ]
    let data = try! JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
    try? data.write(to: out.appendingPathComponent("summary.json"))
    say("done: \(outcome?.movies.count ?? 0) movie(s)\(outcome?.failure.map { ", failure: \($0)" } ?? "")")
    connection.cancel()
    exit(0)
}

// Pings four a second and stats once a second, as a device sends them; `recording` from the light until the movie
// is closed (RecordingPolicy.recordingField).
var pings = 0
let pinger = DispatchSource.makeTimerSource(queue: .main)
pinger.schedule(deadline: .now() + 0.25, repeating: 0.25)
pinger.setEventHandler {
    var stamp = StreamRecorder.hostNow().bitPattern.bigEndian
    send(.ping, Data(bytes: &stamp, count: 8))
    pings += 1
    guard pings % 4 == 0 else { return }
    let field = RecordingPolicy.recordingField(RecordingPolicy.reports(phase))
    let stats = ClientStats(fps: 0, frameAgeMs: 0, rttMs: 0, device: "recordcheck", recording: field)
    send(.clientStats, Wire.encode(stats))
}
pinger.resume()

DispatchQueue.main.asyncAfter(deadline: .now() + startAt) { phase = .counting(3); say("Start: 3") }
DispatchQueue.main.asyncAfter(deadline: .now() + startAt + 2) { one() }
DispatchQueue.main.asyncAfter(deadline: .now() + startAt + 3) { light() }
DispatchQueue.main.asyncAfter(deadline: .now() + stopAt) { stopRecording(.stop) }
if let nextDisplayAt { DispatchQueue.main.asyncAfter(deadline: .now() + nextDisplayAt) { send(.nextDisplay); say("sent kind 47") } }
if let killAt { DispatchQueue.main.asyncAfter(deadline: .now() + killAt) { say("SIGKILL"); kill(getpid(), SIGKILL) } }
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { stopRecording(.sessionEnded) }
dispatchMain()
