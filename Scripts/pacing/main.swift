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
// Its one door listens on loopback only (below); StreamServer's own listener, which takes
// connections on every interface, is never started.
//
// usage: Harness [--port P] [--kf BYTES] [--delta BYTES] [--fps N] [--gop S] [--icons N]
//                [--icon-bytes B] [--thumbs N] [--thumb-bytes B] [--seconds S] [--log PATH]
//                [--plain | --home] [--sizes-at T:KF:DELTA,…] [--still-at T:D,…]
//                [--restart-at T:D,…] [--bitrate B]
// --plain: the remote door without TLS; --home: plain TCP served as a home client (run.py's
// DOOR=Home).
// --bitrate: the running quality the link's reports speak of (default Pro, 40000000): each change of
//   a device's link (LinkJudge, docs/remote-bundle-plan.md §6) prints "Link: behind (withheld 52 of
//   58; carried 7.9 Mbps; suggesting Low)", the suggestion LinkJudge.suggestion gives for B at the
//   run's fps and Standard (the harness has no resolution). Only the new build prints them: the lines
//   compile under LINK_JUDGE, which build.sh defines for it alone (the base's StreamServer has no
//   onClientLinkChanged).
// --sizes-at: at T seconds the frame sizes change and the stream restarts (a settings change).
// --still-at: from T seconds for D seconds no frame is captured (a still window: the motion stopped).
//   A keyframe asked for meanwhile is the last frame encoded again, once the window has been still
//   for 50 ms, as HEVCEncoder.requestKeyframe does; nothing else is sent. It prints "Still: …" with
//   the stamp of the last frame before it, and "Moving again" after it (summarize.py's still rows).
// --restart-at: D seconds after the first keyframe at or after T seconds, the stream restarts with
//   the same sizes (a window picked, a rotation, a settings change), so its first keyframe goes out
//   while that keyframe may still be crossing the link. It prints "Restart: …".
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
let home = args.contains("--home")
let plain = home || args.contains("--plain")
/// "T:kf:delta,T:kf:delta": at T seconds, the sizes change (a settings change: Pro → Low).
let schedule: [(t: Double, kf: Int, delta: Int)] = value("--sizes-at", "").split(separator: ",").compactMap {
    let p = $0.split(separator: ":"); guard p.count == 3 else { return nil }
    return (Double(p[0])!, Int(p[1])!, Int(p[2])!)
}
/// "T:D,T:D": T and D in seconds (--still-at, --restart-at).
func pairs(_ name: String) -> [(t: Double, d: Double)] {
    value(name, "").split(separator: ",").compactMap {
        let p = $0.split(separator: ":"); guard p.count == 2 else { return nil }
        return (Double(p[0])!, Double(p[1])!)
    }
}
let stills = pairs("--still-at")
let restarts = pairs("--restart-at")
let linkBitrate = Int(value("--bitrate", "40000000"))!

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
    /// Capture queue, while the window is still: whether a keyframe was asked for (the last frame is
    /// then encoded again). No frame comes otherwise, so the periodic count does not move.
    func stillKeyframe() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard forced else { return false }
        forced = false; sinceKey = 0
        return true
    }
}

let encoder = FakeEncoder(kf: keyBytes, delta: deltaBytes)
let server = try StreamServer(advertise: false)
let psPayload = ParameterSets(nalUnitHeaderLength: 4, sets: [Data(count: 24), Data(count: 40), Data(count: 8)]).encoded()

server.onKeyframeNeeded = { encoder.requestKeyframe() }
#if LINK_JUDGE
server.onClientLinkChanged = { _, v in
    let suggestion = LinkJudge.suggestion(carriedKbps: v.carriedKbps, bitrate: linkBitrate, fps: fps, captureScale: 1)
    var parts = ["withheld \(v.withheld) of \(v.offered)"]
    if let carried = v.carriedKbps { parts.append("carried \(LinkJudge.mbps(kbps: carried)) Mbps") }
    if v.state == .stalled { parts.append("\(LinkJudge.bytes(v.waiting)) waiting") }
    if v.state != .fine { parts.append(suggestion.map { "suggesting \(LinkJudge.title($0))" } ?? "nothing lower") }
    print("Link: \(v.state)\(v.reset ? " (reset)" : "") (\(parts.joined(separator: "; ")))")
}
#endif
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

// The door, on loopback only: nothing but the harness's relay ever connects, and a test host must
// never take a connection from another machine (the Application Firewall would ask about it).
// - By default the remote door: RemoteTLS's parameters (TLS 1.3 over tcpOptions: no Nagle,
//   keepalive, connectionDropTime 15; interactiveVideo), any client key accepted, served as a
//   remote session at `.ready`, as RemoteServer admits one.
// - `--plain`: the same remote door without TLS (a device that speaks plain TCP, such as the app
//   dialling it by address).
// - `--home`: plain TCP, each connection served as a home client from this Mac (the home branch of
//   `broadcast` and the home eviction rule, as the home door registers one), where StreamServer's
//   own listener would take connections on every interface. Its `start` builds and starts that
//   listener and nothing else, so it is never called.
let params: NWParameters
if plain {
    params = NWParameters(tls: nil, tcp: RemoteTLS.tcpOptions(dialing: false))
    params.serviceClass = .interactiveVideo
} else {
    guard let key = RemoteKey.generate(), let identity = RemoteIdentity(privateKey: key) else { fatalError("no identity") }
    let tls = RemoteTLS.options(identity: identity.tls, role: .server, queue: server.queue) { _, _ in true }
    params = RemoteTLS.parameters(tls: tls, dialing: false)
}
params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port == 0 ? .any : NWEndpoint.Port(rawValue: port)!)
let doorName = home ? "Home" : "Remote"
let door = try NWListener(using: params)
door.stateUpdateHandler = { state in
    if case .ready = state { print("\(doorName) door listening on port \(door.port!.rawValue) (\(plain ? "TCP" : "TLS 1.3"), loopback)") }
    if case .failed(let e) = state { print("\(doorName) door failed: \(e)"); exit(1) }
}
door.newConnectionHandler = { c in
    c.stateUpdateHandler = { state in
        switch state {
        case .ready:
            if home {
                server.serve(c, route: .home(.loopback))
                print("Home client connected: \(c.endpoint)")
            } else {
                server.serve(c, route: .remote(origin: .vpn, label: "through Tailscale", fingerprint: Data([1, 2, 3]), name: "harness"))
                print("Remote client connected: harness through Tailscale (\(c.endpoint))")
            }
        case .failed:
            c.cancel()
        default: break
        }
    }
    c.start(queue: server.queue)
}
door.start(queue: server.queue)
server.setStreaming(true)

// The fake encoder's output, one frame per 1/fps on its own queue (the VT callback thread's role).
let captureQueue = DispatchQueue(label: "harness.capture", qos: .userInteractive)
let started = Date()
var nextSizes = schedule
var nextRestarts = restarts
var restartDue: Double?            // when the pending --restart-at restart happens
var stillSince: Double?            // when the current still spell began
var lastFrameStamp = 0.0           // the last frame's timestamp (the header's)
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
    if let due = restartDue, t >= due {
        restartDue = nil
        print("Restart: the stream starts again (keyframe \(encoder.kf) B)")
        encoder.requestKeyframe()
        server.resetForNewStream()
    }
    if let spell = stills.first(where: { t >= $0.t && t < $0.t + $0.d }) {
        if stillSince == nil {
            stillSince = t
            print(String(format: "Still: for %g s after the frame of %.3f", spell.d, lastFrameStamp))
        }
        // A keyframe asked for while still: the last frame again, once still for 50 ms.
        guard t - stillSince! >= 0.05, encoder.stillKeyframe() else { return }
        let now = Date().timeIntervalSince1970
        Stats.shared.bump("enc.out")
        server.broadcast(StreamMessage(kind: .parameterSets, timestamp: now, isKeyframe: true, payload: psPayload))
        server.broadcast(StreamMessage(kind: .frame, timestamp: now, isKeyframe: true, payload: Data(count: encoder.kf)))
        lastFrameStamp = now
        print("Still: the last frame again as a keyframe")
        return
    }
    if stillSince != nil { stillSince = nil; print("Moving again") }
    let (key, size) = encoder.next()
    Stats.shared.bump("cap.complete")
    Stats.shared.bump("enc.out")
    let now = Date().timeIntervalSince1970
    if key { server.broadcast(StreamMessage(kind: .parameterSets, timestamp: now, isKeyframe: true, payload: psPayload)) }
    server.broadcast(StreamMessage(kind: .frame, timestamp: now, isKeyframe: key, payload: Data(count: size)))
    lastFrameStamp = now
    if key, restartDue == nil, let r = nextRestarts.first, t >= r.t {
        nextRestarts.removeFirst()
        restartDue = t + r.d
    }
}
frameTimer.resume()

let thumbTimer = DispatchSource.makeTimerSource(queue: .main)
thumbTimer.schedule(deadline: .now() + 6, repeating: 6)
thumbTimer.setEventHandler { sendThumbnails() }
thumbTimer.resume()

DispatchQueue.main.async { Stats.shared.startPrinting() }
DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
    print("Harness done after \(Int(seconds)) s.")
    exit(0)
}
print("Harness: keyframe \(keyBytes) B, delta \(deltaBytes) B, \(fps) fps, gop \(gop) s, \(icons) icons × \(iconBytes) B, \(thumbs) thumbs × \(thumbBytes) B")
dispatchMain()
