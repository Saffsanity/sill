import Foundation
import Network
import StreamProtocol

// The pacing harness's host (Scripts/pacing/run.sh says how the harness runs): the real
// StreamServer.swift (build.sh compiles it with its neighbours, from BASE for the base build and
// from the working tree for the new one) serving remote sessions over RemoteTLS's TLS 1.3 server
// parameters, fed FAKE frames of chosen sizes by a timer. Nothing here touches VideoToolbox,
// ScreenCaptureKit or the Mac's encoder, and build.sh refuses a binary that links either.
//
// What it stands in for, from StreamCoordinator:
// - onClientConnected: the catalog (window list, settings, kind 18, N icons, the app list, the
//   cursor), all thumbnails, then a keyframe request;
// - the encoder: one frame per 1/fps (every frame "changed", as a busy window), a keyframe when
//   onKeyframeNeeded asked for one (the next frame carries it, as HEVCEncoder's requestKeyframe
//   does while frames flow) or when fps × gop frames passed since the last one
//   (MaxKeyFrameInterval), parameter sets broadcast before every keyframe;
// - the catalog's thumbnail pass: every thumbnail again every 6 s.
// The home door (StreamServer's own listener, advertise: false) serves `--plain` home runs
// (run.py's DOOR=Home).
//
// usage: Harness [--port P] [--kf BYTES] [--delta BYTES] [--fps N] [--gop S] [--icons N]
//                [--icon-bytes B] [--thumbs N] [--thumb-bytes B] [--seconds S] [--log PATH] [--plain]
//                [--sizes-at T:KF:DELTA,…]
// --sizes-at: at T seconds the frame sizes change and the stream restarts (a settings change).
// --log: the host's lines with Sill.log's timestamps (HostLog), which summarize.py reads.

setvbuf(stdout, nil, _IOLBF, 0)

var args = CommandLine.arguments.dropFirst()
func value(_ name: String, _ fallback: String) -> String {
    if let i = args.firstIndex(of: name), args.index(after: i) < args.endIndex { return args[args.index(after: i)] }
    return fallback
}
let port = UInt16(value("--port", "0"))!
let keyBytes = Int(value("--kf", "150000"))!
let deltaBytes = Int(value("--delta", "8000"))!
let fps = Int(value("--fps", "60"))!
let gop = Double(value("--gop", "4"))!
let icons = Int(value("--icons", "119"))!
let iconBytes = Int(value("--icon-bytes", "6000"))!
let thumbs = Int(value("--thumbs", "11"))!
let thumbBytes = Int(value("--thumb-bytes", "8000"))!
let seconds = Double(value("--seconds", "60"))!
let logPath = value("--log", "")
let plain = args.contains("--plain")
/// "T:kf:delta,T:kf:delta": at T seconds, the sizes change (a settings change: Pro → Low).
let schedule: [(t: Double, kf: Int, delta: Int)] = value("--sizes-at", "").split(separator: ",").compactMap {
    let p = $0.split(separator: ":"); guard p.count == 3 else { return nil }
    return (Double(p[0])!, Int(p[1])!, Int(p[2])!)
}

if !logPath.isEmpty { HostLog.shared.configure(keepLines: 0, fileURL: URL(fileURLWithPath: logPath)) }

final class FakeEncoder {
    private let lock = NSLock()
    private var forced = true
    private var sinceKey = 0
    var kf: Int
    var delta: Int
    init(kf: Int, delta: Int) { self.kf = kf; self.delta = delta }
    /// Network queue (onKeyframeNeeded) or main (connect): the next frame is a keyframe.
    func requestKeyframe() { lock.lock(); forced = true; lock.unlock() }
    /// Capture queue: the next frame's kind and size.
    func next() -> (key: Bool, size: Int) {
        lock.lock(); defer { lock.unlock() }
        let key = forced || sinceKey >= Int(Double(fps) * gop)
        if key { forced = false; sinceKey = 0 } else { sinceKey += 1 }
        return (key, key ? kf : delta)
    }
}

let encoder = FakeEncoder(kf: keyBytes, delta: deltaBytes)
let server = try StreamServer(advertise: false)
let psPayload = ParameterSets(nalUnitHeaderLength: 4, sets: [Data(count: 24), Data(count: 40), Data(count: 8)]).encoded()

server.onKeyframeNeeded = { encoder.requestKeyframe() }
server.onClientCountChanged = { n in Stats.shared.activeClients = n }
server.onClientConnected = { connection, route, _ in
    // The coordinator hops to the main actor first; so does this.
    DispatchQueue.main.async {
        let now = Date().timeIntervalSince1970
        print("Catalog → \(connection.endpoint): 11 windows, \(icons) icons, 119 apps")
        server.send(StreamMessage(kind: .windowList, timestamp: now, isKeyframe: false, payload: Data(count: 3000)), to: connection)
        server.send(StreamMessage(kind: .hostSettings, timestamp: now, isKeyframe: false, payload: Data(count: 400)), to: connection)
        server.send(StreamMessage(kind: .macInfo, timestamp: now, isKeyframe: false, payload: Data(count: 900)), to: connection)
        for _ in 0..<icons {
            server.send(StreamMessage(kind: .appIcon, timestamp: now, isKeyframe: false, payload: Data(count: iconBytes)), to: connection)
        }
        server.send(StreamMessage(kind: .appList, timestamp: now, isKeyframe: false, payload: Data(count: 20000)), to: connection)
        server.send(StreamMessage(kind: .cursorShape, timestamp: now, isKeyframe: false, payload: Data(count: 2000)), to: connection)
        sendThumbnails()
        encoder.requestKeyframe()
    }
}

func sendThumbnails() {
    let now = Date().timeIntervalSince1970
    for _ in 0..<thumbs {
        server.broadcast(StreamMessage(kind: .thumbnail, timestamp: now, isKeyframe: false, payload: Data(count: thumbBytes)))
    }
}

// The remote door: RemoteTLS's parameters (TLS 1.3 over tcpOptions: no Nagle, keepalive,
// connectionDropTime 15; interactiveVideo), any client key accepted, admitted at `.ready`.
// `--plain`: the same door without TLS.
let params: NWParameters
if plain {
    params = NWParameters(tls: nil, tcp: RemoteTLS.tcpOptions(dialing: false))
    params.serviceClass = .interactiveVideo
} else {
    guard let key = RemoteKey.generate(), let identity = RemoteIdentity(privateKey: key) else { fatalError("no identity") }
    let tls = RemoteTLS.options(identity: identity.tls, role: .server, queue: server.queue) { _, _ in true }
    params = RemoteTLS.parameters(tls: tls, dialing: false)
}
let door = try NWListener(using: params, on: port == 0 ? .any : NWEndpoint.Port(rawValue: port)!)
door.stateUpdateHandler = { state in
    if case .ready = state { print("Remote door listening on port \(door.port!.rawValue) (\(plain ? "TCP" : "TLS 1.3"))") }
    if case .failed(let e) = state { print("Remote door failed: \(e)"); exit(1) }
}
door.newConnectionHandler = { c in
    c.stateUpdateHandler = { state in
        switch state {
        case .ready:
            server.serve(c, route: .remote(origin: .vpn, label: "through Tailscale", fingerprint: Data([1, 2, 3]), name: "harness"))
            print("Remote client connected: harness through Tailscale (\(c.endpoint))")
        case .failed:
            c.cancel()
        default: break
        }
    }
    c.start(queue: server.queue)
}
door.start(queue: server.queue)
server.start()
server.setStreaming(true)

// The fake encoder's output, one frame per 1/fps on its own queue (the VT callback thread's role).
let captureQueue = DispatchQueue(label: "harness.capture", qos: .userInteractive)
let started = Date()
var nextSizes = schedule
let frameTimer = DispatchSource.makeTimerSource(queue: captureQueue)
frameTimer.schedule(deadline: .now() + 0.5, repeating: 1.0 / Double(fps), leeway: .milliseconds(1))
frameTimer.setEventHandler {
    let t = Date().timeIntervalSince(started)
    if let s = nextSizes.first, t >= s.t {
        nextSizes.removeFirst()
        encoder.kf = s.kf; encoder.delta = s.delta
        print("Sizes: keyframe \(s.kf) B, delta \(s.delta) B")
        encoder.requestKeyframe()
        server.resetForNewStream()          // a settings change restarts the stream
    }
    let (key, size) = encoder.next()
    Stats.shared.bump("cap.complete")
    Stats.shared.bump("enc.out")
    let now = Date().timeIntervalSince1970
    if key { server.broadcast(StreamMessage(kind: .parameterSets, timestamp: now, isKeyframe: true, payload: psPayload)) }
    server.broadcast(StreamMessage(kind: .frame, timestamp: now, isKeyframe: key, payload: Data(count: size)))
}
frameTimer.resume()

let thumbTimer = DispatchSource.makeTimerSource(queue: .main)
thumbTimer.schedule(deadline: .now() + 6, repeating: 6)
thumbTimer.setEventHandler { sendThumbnails() }
thumbTimer.resume()

DispatchQueue.main.async { Stats.shared.startPrinting() }
DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { print("Home door listening on port \(server.port ?? 0) (TCP, loopback admitted)") }
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
    print("Harness done after \(Int(seconds)) s.")
    exit(0)
}
print("Harness: keyframe \(keyBytes) B, delta \(deltaBytes) B, \(fps) fps, gop \(gop) s, \(icons) icons × \(iconBytes) B, \(thumbs) thumbs × \(thumbBytes) B")
dispatchMain()
