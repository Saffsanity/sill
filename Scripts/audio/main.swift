import Foundation
import Network
import StreamProtocol

// The encoder-free sound harness's host (docs/audio-plan.md §11, H5–H8, H12; Scripts/audio/run.sh says
// how the harness runs): the real StreamServer.swift and the sound's host files (AudioPipeline,
// AudioPacketizer, AudioEncoder, SyntheticAudio, TestTone), built by build.sh from the working tree,
// fed FAKE frames of chosen sizes by a timer, and the real test tone through the real pipeline and send
// path. Nothing here touches VideoToolbox, ScreenCaptureKit, CoreMedia or AVFoundation, and build.sh
// refuses a binary that links any of them: no picture is encoded, no sound captured, nothing played.
//
// What it stands in for, from StreamCoordinator: the catalog on connect (a window list, the settings,
// icons, the app list, the cursor) and a keyframe request; the encoder (one frame per 1/fps, a keyframe
// when asked and every gop seconds, parameter sets before each keyframe), as Scripts/pacing/main.swift
// does; and the sound's rule: while Send Audio is on (--audio) and a device plays it, the test tone
// (AudioKey.test), else none, with the coordinator's reasons.
//
// Two doors, on 127.0.0.1 alone: the home door (plain TCP, each connection served as a home client
// from this Mac, as the home door registers one) and the remote door (RemoteTLS's TLS 1.3, any client
// key, served as a remote session; --plain-remote: the same without TLS). StreamServer's own
// listener, which takes connections on every interface, is never started.
//
// usage: Harness [--seconds S] [--fps N] [--kf BYTES] [--delta BYTES] [--gop S] [--audio]
//                [--switch-at T] [--audio-at T:on|off,…] [--plain-remote] [--log PATH]
// --switch-at: at T seconds the sound's source changes to a second tone (660 Hz; AudioKey.app, pid 1,
//   "Second Tone"): a new epoch, as another app's window would be.
// --audio-at: Send Audio turned on or off at T seconds (a device's or the Mac's change).
// SILL_TEST_AUDIO_CHUNK and SILL_TEST_AUDIO_PAUSE reach the tone as they do on a synthetic host.

setvbuf(stdout, nil, _IOLBF, 0)

var args = CommandLine.arguments.dropFirst()
func value(_ name: String, _ fallback: String) -> String {
    if let i = args.firstIndex(of: name), args.index(after: i) < args.endIndex { return args[args.index(after: i)] }
    return fallback
}
let seconds = Double(value("--seconds", "60"))!
let fps = Int(value("--fps", "60"))!
let keyBytes = Int(value("--kf", "300000"))!
let deltaBytes = Int(value("--delta", "30000"))!
let gop = Double(value("--gop", "4"))!
let switchAt = Double(value("--switch-at", "-1"))!
let plainRemote = args.contains("--plain-remote")
let logPath = value("--log", "")
var sendAudio = args.contains("--audio")
let audioAt: [(t: Double, on: Bool)] = value("--audio-at", "").split(separator: ",").compactMap {
    let p = $0.split(separator: ":"); guard p.count == 2, let t = Double(p[0]) else { return nil }
    return (t, p[1] == "on")
}
if !logPath.isEmpty { HostLog.shared.configure(keepLines: 0, fileURL: URL(fileURLWithPath: logPath)) }

// MARK: - The fake encoder (Scripts/pacing/main.swift's, cut to what the sound's gates need)

final class FakeEncoder {
    private let lock = NSLock()
    private var forced = true
    private var sinceKey = 0
    func requestKeyframe() { lock.lock(); forced = true; lock.unlock() }
    func next() -> (key: Bool, size: Int) {
        lock.lock(); defer { lock.unlock() }
        let key = forced || sinceKey >= Int(Double(fps) * gop)
        if key { forced = false; sinceKey = 0 } else { sinceKey += 1 }
        return (key, key ? keyBytes : deltaBytes)
    }
}
let encoder = FakeEncoder()
let server = try StreamServer(advertise: false)
let psPayload = ParameterSets(nalUnitHeaderLength: 4, sets: [Data(count: 24), Data(count: 40), Data(count: 8)]).encoded()

// MARK: - The sound, as the coordinator runs it

let audio = AudioPipeline()
audio.onFormat = { data, epoch in server.broadcastAudio(format: data, epoch: epoch) }
audio.onPackets = { data, epoch in server.broadcastAudio(packets: data, epoch: epoch) }
var listeners = 0
var second = false   // the source switched to the second tone
@MainActor func follow() {
    let (key, reason): (AudioKey, String)
    if !sendAudio { (key, reason) = (.none, "Send Audio is off") }
    else if listeners == 0 { (key, reason) = (.none, "no connected device plays sound") }
    else { (key, reason) = (second ? .app(pid: 1, name: "Second Tone") : .test, "") }
    audio.follow(key, reason: reason) { key in
        switch key {
        case .test:
            return .source(SyntheticAudio(queue: audio.queue), line: "Audio: a test tone (440 Hz at -30 dBFS, a click at each second).")
        case .app:
            return .source(SyntheticAudio(queue: audio.queue, pitch: 660), line: "Audio: a second test tone (660 Hz, a click at each second).")
        default:
            return .failed("no source")
        }
    }
}
server.onAudioListenersChanged = { n in Task { @MainActor in listeners = n; follow() } }

server.onKeyframeNeeded = { encoder.requestKeyframe() }
server.onClientCountChanged = { n in Stats.shared.activeClients = n }
server.onClientConnected = { connection, _, _ in
    DispatchQueue.main.async {
        let now = Date().timeIntervalSince1970
        print("Catalog → \(connection.endpoint): 11 windows, 20 icons, 119 apps")
        server.send(StreamMessage(kind: .windowList, timestamp: now, isKeyframe: false, payload: Data(count: 3000)), to: connection)
        server.send(StreamMessage(kind: .hostSettings, timestamp: now, isKeyframe: false, payload: Data(count: 400)), to: connection)
        for _ in 0..<20 {
            server.send(StreamMessage(kind: .appIcon, timestamp: now, isKeyframe: false, payload: Data(count: 6000)), to: connection)
        }
        server.send(StreamMessage(kind: .appList, timestamp: now, isKeyframe: false, payload: Data(count: 20000)), to: connection)
        server.send(StreamMessage(kind: .cursorShape, timestamp: now, isKeyframe: false, payload: Data(count: 2000)), to: connection)
        encoder.requestKeyframe()
    }
}

// MARK: - The doors, on loopback only

func door(_ name: String, _ params: NWParameters, route: ClientRoute) throws -> NWListener {
    params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
    let l = try NWListener(using: params)
    l.stateUpdateHandler = { state in
        if case .ready = state { print("\(name) door listening on port \(l.port!.rawValue)") }
        if case .failed(let e) = state { print("\(name) door failed: \(e)"); exit(1) }
    }
    l.newConnectionHandler = { c in
        c.stateUpdateHandler = { state in
            switch state {
            case .ready:
                server.serve(c, route: route)
                print("\(name) client connected: \(c.endpoint)")
            case .failed:
                c.cancel()
            default: break
            }
        }
        c.start(queue: server.queue)
    }
    l.start(queue: server.queue)
    return l
}
let homeParams = NWParameters(tls: nil, tcp: RemoteTLS.tcpOptions(dialing: false))
homeParams.serviceClass = .interactiveVideo
let home = try door("Home", homeParams, route: .home(.loopback))
let remoteParams: NWParameters
if plainRemote {
    remoteParams = NWParameters(tls: nil, tcp: RemoteTLS.tcpOptions(dialing: false))
    remoteParams.serviceClass = .interactiveVideo
} else {
    guard let key = RemoteKey.generate(), let identity = RemoteIdentity(privateKey: key) else { fatalError("no identity") }
    let tls = RemoteTLS.options(identity: identity.tls, role: .server, queue: server.queue) { _, _ in true }
    remoteParams = RemoteTLS.parameters(tls: tls, dialing: false)
}
let remote = try door("Remote", remoteParams, route: .remote(origin: .vpn, label: "through Tailscale", fingerprint: Data([1, 2, 3]), name: "harness"))
server.setStreaming(true)

// MARK: - Frames, the schedule, the end

let captureQueue = DispatchQueue(label: "harness.capture", qos: .userInteractive)
let started = Date()
let frameTimer = DispatchSource.makeTimerSource(queue: captureQueue)
frameTimer.schedule(deadline: .now() + 0.5, repeating: 1.0 / Double(fps), leeway: .milliseconds(1))
frameTimer.setEventHandler {
    let (key, size) = encoder.next()
    Stats.shared.bump("cap.complete")
    Stats.shared.bump("enc.out")
    let now = Date().timeIntervalSince1970
    if key { server.broadcast(StreamMessage(kind: .parameterSets, timestamp: now, isKeyframe: true, payload: psPayload)) }
    server.broadcast(StreamMessage(kind: .frame, timestamp: now, isKeyframe: key, payload: Data(count: size)))
}
frameTimer.resume()

if switchAt >= 0 {
    DispatchQueue.main.asyncAfter(deadline: .now() + switchAt) {
        Task { @MainActor in
            print("Switch: the sound's source is now the second tone")
            second = true
            follow()
        }
    }
}
for (t, on) in audioAt {
    DispatchQueue.main.asyncAfter(deadline: .now() + t) {
        Task { @MainActor in
            print("Settings: send audio \(sendAudio ? "on" : "off") → \(on ? "on" : "off")")
            sendAudio = on
            follow()
        }
    }
}

DispatchQueue.main.async { Stats.shared.startPrinting() }
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
    print("Harness done after \(Int(seconds)) s.")
    exit(0)
}
print("Harness: keyframe \(keyBytes) B, delta \(deltaBytes) B, \(fps) fps, gop \(gop) s, Send Audio \(sendAudio ? "on" : "off")")
_ = (home, remote)
dispatchMain()
