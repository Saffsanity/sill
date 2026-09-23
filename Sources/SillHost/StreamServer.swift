import Foundation
import Network
import StreamProtocol

/// Advertises _sill._tcp over Bonjour and pushes messages to every connected client.
/// Slow clients drop delta frames rather than building a queue (that queue is latency).
final class StreamServer {
    private final class Client {
        let connection: NWConnection
        var inflight = 0          // every message still unacknowledged (backpressure for delta drops)
        var inflightFrames = 0    // video frames only
        var oldestUnackedFrameAt: TimeInterval?   // last time a frame was drained, or queued from 0 (dead-peer detection)
        let connectedAt = Date().timeIntervalSince1970
        var needsKeyframe = true
        var lastStatsPrint = 0.0  // CFAbsoluteTime of the last clientStats line, to rate-limit the log
        init(_ c: NWConnection) { connection = c }
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "sill.net", qos: .userInteractive)
    private var clients: [ObjectIdentifier: Client] = [:]
    private var lastParameterSets: Data?
    /// A client finished connecting. Called on the network queue.
    var onClientConnected: ((NWConnection) -> Void)?
    /// A message from a client (selectSource, launchApp). Called on the network queue.
    var onMessage: ((StreamMessage, NWConnection) -> Void)?
    /// A client fell behind and lost a delta frame; the encoder should produce a keyframe now
    /// rather than in up to 4 s. Called on the network queue.
    var onKeyframeNeeded: (() -> Void)?
    /// Number of connected clients changed. Called on the network queue. Zero means the host can idle.
    var onClientCountChanged: ((Int) -> Void)?
    /// One connection ended (before `onClientCountChanged`), for per-client state such as its rate.
    var onClientDisconnected: ((NWConnection) -> Void)?

    // MARK: Link keepalive
    //
    // Measured 2026-09-22: with nothing streaming, the iPad's ping round trip climbs 5 → 100 → 200 →
    // 300 ms in a sawtooth every few seconds while a simulator on the same Mac stays at 0 ms. That is
    // the device's Wi-Fi radio dozing whenever the downlink goes quiet; every next packet waits for a
    // wake window. During a steady video stream it never happens. A trackpad stroke over a static
    // window starts from a quiet link, so its first frames arrive 100–300 ms late and then bunch up:
    // the stutter. While a session is live we keep the downlink lightly busy with an empty 14-byte
    // tick every 30 ms (~0.5 KB/s). "Live" = the coordinator says a source is streaming, or a client
    // sent input in the last 3 s. Idle sessions tick nothing and let the radio sleep.
    private var tickTimer: DispatchSourceTimer?
    private var lastInputAt: TimeInterval = 0
    private var streaming = false
    private static let tickInterval = 0.030
    private static let inputRecency = 3.0

    /// The coordinator flips this with the active source. Thread-safe.
    func setStreaming(_ on: Bool) {
        queue.async { [self] in streaming = on; updateTicking() }
    }

    /// On the network queue.
    private func updateTicking() {
        let wanted = !clients.isEmpty && (streaming || Date().timeIntervalSince1970 - lastInputAt < Self.inputRecency)
        if wanted, tickTimer == nil {
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now(), repeating: Self.tickInterval, leeway: .milliseconds(5))
            t.setEventHandler { [weak self] in self?.tick() }
            t.resume()
            tickTimer = t
        } else if !wanted, let t = tickTimer {
            t.cancel(); tickTimer = nil
        }
    }

    /// On the network queue. Re-evaluates the recency rule so the timer stops itself after a quiet spell.
    private func tick() {
        let live = streaming || Date().timeIntervalSince1970 - lastInputAt < Self.inputRecency
        guard live, !clients.isEmpty else { updateTicking(); return }
        let data = StreamMessage(kind: .tick, timestamp: Date().timeIntervalSince1970, isKeyframe: false, payload: Data()).serialized()
        for client in clients.values where client.connection.state == .ready {
            client.connection.send(content: data, completion: .contentProcessed { _ in })   // not counted as inflight
        }
        Stats.shared.bump("net.tick")
    }

    init(serviceType: String = "_sill._tcp") throws {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        // A client that vanishes without closing (app killed, Wi-Fi gone) would otherwise stay
        // "ready" until TCP gives up minutes later, eating a keyframe per drop. Probe it instead.
        tcp.enableKeepalive = true
        tcp.keepaliveIdle = 5
        tcp.keepaliveInterval = 2
        tcp.keepaliveCount = 3
        let params = NWParameters(tls: nil, tcp: tcp)
        params.serviceClass = .interactiveVideo   // WMM video class on Wi-Fi: shorter queues, higher priority
        params.includePeerToPeer = true
        listener = try NWListener(using: params)
        listener.service = NWListener.Service(name: Host.current().localizedName ?? "Mac", type: serviceType)
        listener.stateUpdateHandler = { state in
            if case .failed(let e) = state { print("Listener failed: \(e)"); exit(1) }
        }
        listener.newConnectionHandler = { [weak self] c in self?.accept(c) }
    }

    func start() { listener.start(queue: queue) }

    private func accept(_ connection: NWConnection) {
        let client = Client(connection)
        let id = ObjectIdentifier(connection)
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                print("Client connected: \(connection.endpoint)")
                self?.receiveLoop(client)
                self?.onClientConnected?(connection)
            case .failed, .cancelled:
                print("Client left: \(connection.endpoint)")
                guard let self else { return }
                self.clients[id] = nil
                self.onClientDisconnected?(connection)
                self.onClientCountChanged?(self.clients.count)
                self.updateTicking()
            default: break
            }
        }
        clients[id] = client
        onClientCountChanged?(clients.count)
        updateTicking()
        connection.start(queue: queue)
    }

    /// The source is changing: forget the old parameter sets and make every client wait for
    /// the next keyframe, so nobody decodes frames of the new window with the old format.
    func resetForNewStream() {
        queue.async { [self] in
            lastParameterSets = nil
            for client in clients.values { client.needsKeyframe = true }
        }
    }

    /// One message to one client (catalog on connect). Thread-safe.
    func send(_ message: StreamMessage, to connection: NWConnection) {
        let data = message.serialized()
        queue.async { [self] in
            guard let client = clients[ObjectIdentifier(connection)] else {
                print("send: no client for \(connection.endpoint) (\(clients.count) known)")
                return
            }
            send(data, to: client)
        }
    }

    /// Client → host messages share the same framing. Small and rare, so read them one at a time.
    private func receiveLoop(_ client: Client) {
        let c = client.connection
        c.receive(minimumIncompleteLength: StreamMessage.headerLength, maximumLength: StreamMessage.headerLength) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            guard let data, let header = StreamMessage.parseHeader(data) else {
                // EOF or a read error: the client closed (or was killed). Nothing else would notice
                // while no frames are being sent, so cancel here; the state handler prints and forgets it.
                if isComplete || error != nil { c.cancel() }
                return
            }
            let deliver = { (payload: Data) in
                if header.kind == .input {
                    self.lastInputAt = Date().timeIntervalSince1970
                    if self.tickTimer == nil { self.updateTicking() }
                }
                if header.kind == .ping {
                    // Echo straight back from the network queue: the round trip should measure the
                    // network and nothing else.
                    self.send(StreamMessage(kind: .pong, timestamp: header.timestamp, isKeyframe: false, payload: payload).serialized(), to: client)
                } else if header.kind == .clientStats {
                    // What the device sees, printed here so the latency number is in the Mac's log.
                    // The client reports every second; every other report (~2 s) is enough. The gate
                    // is 1.5 s, not 2, so arrival jitter on a 1 s cadence cannot stretch it to 3 s.
                    let now = CFAbsoluteTimeGetCurrent()
                    if now - client.lastStatsPrint >= 1.5, let stats = Wire.decode(ClientStats.self, from: payload) {
                        client.lastStatsPrint = now
                        print("client \(stats.device): \(stats.fps) fps, frame age \(stats.frameAgeMs) ms, rtt \(stats.rttMs) ms")
                    }
                } else {
                    self.onMessage?(StreamMessage(kind: header.kind, timestamp: header.timestamp, isKeyframe: header.isKeyframe, payload: payload), c)
                }
                self.receiveLoop(client)
            }
            if header.payloadLength == 0 { deliver(Data()); return }
            c.receive(minimumIncompleteLength: header.payloadLength, maximumLength: header.payloadLength) { data, _, isComplete, error in
                guard let data else {
                    if isComplete || error != nil { c.cancel() }
                    return
                }
                deliver(data)
            }
        }
    }

    /// Thread-safe: hops onto the network queue.
    func broadcast(_ message: StreamMessage) {
        let data = message.serialized()
        queue.async { [self] in
            if message.kind == .parameterSets { lastParameterSets = data }
            var wantKeyframe = false
            defer { if wantKeyframe { onKeyframeNeeded?() } }
            for client in clients.values where client.connection.state == .ready {
                if message.kind == .frame {
                    if client.needsKeyframe {
                        guard message.isKeyframe, let ps = lastParameterSets else { Stats.shared.bump("net.waitKey"); continue }
                        send(ps, to: client)
                        client.needsKeyframe = false
                    } else if client.inflight > 2 && !message.isKeyframe {
                        // Drop the delta. Every later delta references it, so this client now waits for
                        // a keyframe (sending deltas anyway is what showed up as flicker on the iPad).
                        Stats.shared.bump("net.dropped")
                        client.needsKeyframe = true
                        wantKeyframe = true
                        continue
                    }
                    Stats.shared.bump("net.sent")
                }
                send(data, to: client, isFrame: message.kind == .frame)
            }
        }
    }

    /// A peer that has not drained a single video frame for this long stopped reading (app killed,
    /// device asleep). Time-based rather than a frame count: a slow decoder (the simulator at full
    /// Retina) or the connect burst can hold many frames unacked and still be alive.
    private static let deadAfter: TimeInterval = 4.0
    /// No eviction while the connect burst (catalog + first keyframe) is still draining.
    private static let graceAfterConnect: TimeInterval = 8.0

    private func send(_ data: Data, to client: Client, isFrame: Bool = false) {
        let now = Date().timeIntervalSince1970
        if isFrame, let oldest = client.oldestUnackedFrameAt,
           now - oldest > Self.deadAfter, now - client.connectedAt > Self.graceAfterConnect {
            print("Client not draining for \(Int(now - oldest)) s, dropping: \(client.connection.endpoint)")
            client.connection.cancel()   // its state handler removes it from `clients`
            return
        }
        client.inflight += 1
        if isFrame {
            client.inflightFrames += 1
            if client.oldestUnackedFrameAt == nil { client.oldestUnackedFrameAt = now }
        }
        client.connection.send(content: data, completion: .contentProcessed { [weak client] _ in
            guard let client else { return }
            client.inflight -= 1
            if isFrame {
                client.inflightFrames -= 1
                if client.inflightFrames <= 0 {
                    client.inflightFrames = 0; client.oldestUnackedFrameAt = nil
                } else {
                    // Progress: a slow but live peer on a saturated link never drains to zero.
                    client.oldestUnackedFrameAt = Date().timeIntervalSince1970
                }
            }
        })
    }
}
