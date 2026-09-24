import Foundation
import Network
import StreamProtocol

/// Advertises _sill._tcp over Bonjour and pushes messages to every connected client.
/// Slow clients drop delta frames rather than building a queue (that queue is latency).
///
/// Test only, read once from the environment, never set outside a test and not in the README:
/// `SILL_TEST_SERVICE_TYPE=_silltest._tcp` registers a host that otherwise does not advertise (the
/// `--synthetic` hosts) as "Sill test ‹pid›" under that type, with the listener's own peer-to-peer
/// flag, so a dns-sd browse can check whether the registration includes AWDL while no device (they
/// browse `_sill._tcp` only) ever finds it. `SILL_TEST_SWAP_FAIL=port` makes a Direct Wireless
/// replacement's same-port bind fail as EADDRINUSE without binding, and `=all` its any-port bind
/// too, so the fallback and the listener-failure rule can be exercised without a real conflict.
/// Both are honoured only on a host that does not advertise, so a stray variable can never touch
/// a real host.
final class StreamServer {
    private final class Client {
        let connection: NWConnection
        var inflight = 0          // every message still unacknowledged (backpressure for delta drops)
        var inflightFrames = 0    // video frames only
        var oldestUnackedFrameAt: TimeInterval?   // last time a frame was drained, or queued from 0 (dead-peer detection)
        let connectedAt = Date().timeIntervalSince1970
        var needsKeyframe = true
        var lastStatsPrint = 0.0  // CFAbsoluteTime of the last clientStats line, to rate-limit the log
        /// The worst frame age and rtt reported since that line, -1 for none. The next line prints
        /// them, so a report the rate limit skips still shows its spike. Only newer clients send maxima.
        var worstFrameAgeSincePrint = -1
        var worstRttSincePrint = -1
        init(_ c: NWConnection) { connection = c }
    }

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
    /// The listener failed. Called on the network queue after "Listener failed: …" is printed.
    /// Unset, the process exits(1) as it always has (the CLI); the menu bar app sets it and keeps
    /// running with the failure in its menu. Set it only before `start()`.
    var onListenerFailed: ((NWError) -> Void)?
    /// Every listener state change (ready, waiting, failed…). Called on the network queue.
    var onListenerState: ((NWListener.State) -> Void)?
    /// The name Bonjour actually registered, which differs from the Mac's name after a clash
    /// ("… (2)"); nil when that registration went away. Called on the network queue.
    var onServiceRegistered: ((String?) -> Void)?
    /// Every ClientStats report, about once a second per device (the log prints every other one).
    /// Called on the network queue.
    var onClientStats: ((NWConnection, ClientStats) -> Void)?

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

    // MARK: The listener, and Direct Wireless (peer-to-peer Wi-Fi)
    //
    // includePeerToPeer on the listener makes its Bonjour registration include AWDL, which is what
    // turns the Mac's AWDL on: the kernel counts that registration as an AWDL service ("Enabling AWDL
    // due to Mdns"); a peer-to-peer listener without a service counts as none. Off by default (Direct
    // Wireless Connection, HostConfig): AWDL takes the Mac's one radio off its Wi-Fi channel up to
    // ~97 ms every 524 ms, and on a shared network it carries none of Sill's data.
    //
    // NWListener fixes its parameters at creation, so a change replaces the listener. Measured
    // 2026-09-24: connections the old listener accepted are independent of it and keep streaming;
    // `.cancelled` follows `cancel()` within 2 ms, and a new listener binds the same port right after
    // it even while accepted connections hold the port (binding before it fails with EADDRINUSE);
    // re-registering the same name within milliseconds of dropping an AWDL registration orphaned the
    // awdl0 record for minutes (5 of 5), while 0.25 s and more removed it cleanly (6 of 6). So:
    // cancel, wait for `.cancelled`, bind the same port at once without a service (a device
    // connecting in those milliseconds is refused and retries), and advertise `advertiseDelay` later.
    //
    // From `start()` on, the listener's whole life is the network queue's: its creation, start,
    // handlers and replacement, and `readyPort`, which the main actor reads through `portLock`.

    private var listener: NWListener                 // replaced whole, never reconfigured
    /// The Mac's name under `_sill._tcp`, a test registration (SILL_TEST_SERVICE_TYPE), or nil (the
    /// synthetic hosts, which devices must never find).
    private let service: NWListener.Service?
    /// A test registration is announced once in the log and never reaches `onServiceRegistered`.
    private let serviceIsTest: Bool
    /// A host that does not advertise (the synthetic ones): the only kind the TEST ONLY hooks touch.
    private let testHost: Bool
    private var peerToPeer = false                   // what `listener` was built with
    private var wantedPeerToPeer = false             // the newest request
    /// A replacement under way, numbered so a late callback or timer of an earlier one is a no-op:
    /// the old listener cancelling, then the new one bound and waiting to be advertised.
    private enum Swap: Equatable { case idle, cancelling(Int), settling(Int) }
    private var swap = Swap.idle
    private var swapCount = 0
    private var replacementPort: NWEndpoint.Port?    // the port the current replacement tried; nil = any port
    private var started = false
    private let portLock = NSLock()                  // `port` is read on the main actor
    private var readyPort: UInt16?
    /// 6× the shortest clean pause measured, and past the ~1 s the old record's removal takes to show.
    private static let advertiseDelay: TimeInterval = 1.5
    /// `.cancelled` came within 2 ms in every measurement; without it the replacement takes any port.
    private static let cancelTimeout: TimeInterval = 1.0

    /// `advertise: false` keeps the host off Bonjour (the synthetic test mode), unless a test asks
    /// for its test registration (SILL_TEST_SERVICE_TYPE, above).
    init(serviceType: String = "_sill._tcp", advertise: Bool = true) throws {
        // The synthetic test host does not advertise: a device would otherwise find it, connect,
        // and show the test pattern (Noah saw "a white moving wall", 2026-09-23). Test clients
        // connect to it by port.
        if advertise {
            service = NWListener.Service(name: Host.current().localizedName ?? "Mac", type: serviceType)
            serviceIsTest = false
        } else if let type = Self.testServiceType {
            service = NWListener.Service(name: "Sill test \(getpid())", type: type)
            serviceIsTest = true
        } else {
            service = nil
            serviceIsTest = false
        }
        testHost = !advertise
        listener = try Self.makeListener(peerToPeer: false, port: nil)
        listener.service = service
        wire(listener)
    }

    /// TEST ONLY: SILL_TEST_SERVICE_TYPE (see the type's doc comment). Read once. Only a
    /// `_name._tcp` other than Sill's own is taken, so a device can never find a test host; anything
    /// else is ignored with one line.
    private static let testServiceType: String? = {
        guard let type = ProcessInfo.processInfo.environment["SILL_TEST_SERVICE_TYPE"], !type.isEmpty else { return nil }
        let name = type.hasPrefix("_") && type.hasSuffix("._tcp") ? type.dropFirst().dropLast(5) : ""
        let valid = (1...15).contains(name.count) && type != "_sill._tcp"
            && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        if !valid { print("SILL_TEST_SERVICE_TYPE=\(type) ignored: a test type is _name._tcp, and never _sill._tcp.") }
        return valid ? type : nil
    }()

    /// TEST ONLY: SILL_TEST_SWAP_FAIL (see the type's doc comment). Read once; "port" or "all".
    private static let testSwapFail: String? = ProcessInfo.processInfo.environment["SILL_TEST_SWAP_FAIL"]

    /// A listener with Sill's TCP options and service class, peer-to-peer or not, on `port` when
    /// given (a replacement keeps the port that test clients and resolved devices know).
    private static func makeListener(peerToPeer: Bool, port: NWEndpoint.Port?) throws -> NWListener {
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
        params.includePeerToPeer = peerToPeer     // Direct Wireless Connection only (see the MARK above)
        if let port { return try NWListener(using: params, on: port) }
        return try NWListener(using: params)
    }

    /// The listener's handlers. Each first checks that `l` is still the listener, so the callbacks
    /// of one that has been replaced change nothing.
    private func wire(_ l: NWListener) {
        l.stateUpdateHandler = { [weak self, weak l] state in
            guard let self, let l, l === self.listener else { return }
            switch state {
            case .ready:
                portLock.lock(); readyPort = l.port?.rawValue; portLock.unlock()
            case .failed(let e):
                if case .settling(let n) = swap {
                    // A replacement failed after binding: its own fallback (another port, else the
                    // rule below), reported from there.
                    l.cancel()
                    replacementFailed(e, swap: n)
                    return
                }
                print("Listener failed: \(e)")
                guard let handler = onListenerFailed else { exit(1) }   // the CLI, as always
                handler(e)
            default:
                break
            }
            onListenerState?(state)
        }
        l.serviceRegistrationUpdateHandler = { [weak self, weak l] change in
            guard let self, let l, l === self.listener else { return }
            if serviceIsTest {
                // TEST ONLY: one line a test can read, from the listener's own parameters. Never
                // forwarded, so the app keeps its "Test Pattern Mode … port N" status.
                if case .add(let endpoint) = change, case .service(let name, _, _, _) = endpoint {
                    let p2p = l.parameters.includePeerToPeer ? "on" : "off"
                    print("Test service registered as \"\(name)\" (\(service?.type ?? "?"), peer-to-peer \(p2p)); no device browses this type.")
                }
                return
            }
            if case .add(let endpoint) = change, case .service(let name, _, _, _) = endpoint {
                onServiceRegistered?(name)
            } else if case .remove = change {
                onServiceRegistered?(nil)
            }
        }
        // A connection no longer depends on the listener that accepted it, so it is served
        // whichever listener it came from.
        l.newConnectionHandler = { [weak self] c in self?.accept(c) }
    }

    /// Direct Wireless Connection, from the coordinator. Before `start()` the listener is built with
    /// it; after, the listener is replaced (see the MARK above). Thread-safe; returns at once.
    /// Requests during a replacement coalesce, and the newest wins.
    func setPeerToPeer(_ on: Bool) {
        queue.async { [self] in
            wantedPeerToPeer = on
            if started { beginSwap() }
        }
    }

    /// On `queue`. Starts replacing the listener when the wanted flag differs from the one it was
    /// built with, unless a replacement is under way: that one looks again when it settles.
    private func beginSwap() {
        guard started, swap == .idle, wantedPeerToPeer != peerToPeer else { return }
        swapCount += 1
        let n = swapCount
        swap = .cancelling(n)
        let old = listener
        let oldPort = old.port   // nil for a listener that failed or was never ready: any port then
        // Its registration ending is not the Mac leaving: the status keeps the name through the
        // replacement, whose own registration brings it back.
        old.serviceRegistrationUpdateHandler = nil
        old.stateUpdateHandler = { [weak self] state in
            guard let self, case .cancelled = state, swap == .cancelling(n) else { return }
            bindReplacement(on: oldPort, swap: n)
        }
        old.cancel()
        queue.asyncAfter(deadline: .now() + Self.cancelTimeout) { [weak self] in
            guard let self, swap == .cancelling(n) else { return }
            bindReplacement(on: nil, swap: n)   // no `.cancelled`: the old socket may still hold the port
        }
    }

    /// On `queue`, once the old listener is gone (or said nothing for `cancelTimeout`): binds the
    /// replacement at once, on `port` when given, with the newest wanted flag and no service. It is
    /// advertised `advertiseDelay` later (`settled`).
    private func bindReplacement(on port: NWEndpoint.Port?, swap n: Int) {
        swap = .settling(n)
        replacementPort = port
        // TEST ONLY: the fallbacks without a real port conflict (SILL_TEST_SWAP_FAIL).
        if testHost, Self.testSwapFail == "all" || (Self.testSwapFail == "port" && port != nil) {
            replacementFailed(.posix(.EADDRINUSE), swap: n)
            return
        }
        let l: NWListener
        do {
            l = try Self.makeListener(peerToPeer: wantedPeerToPeer, port: port)
        } catch {
            replacementFailed(error as? NWError ?? .posix(.EINVAL), swap: n)
            return
        }
        wire(l)
        listener = l
        peerToPeer = wantedPeerToPeer
        l.start(queue: queue)
        queue.asyncAfter(deadline: .now() + Self.advertiseDelay) { [weak self, weak l] in
            guard let self, let l else { return }
            settled(l, swap: n)
        }
    }

    /// On `queue`, `advertiseDelay` after the replacement was bound: advertise it, or, when the
    /// setting moved again meanwhile, replace it once more (it was never advertised, so the last
    /// registration dropped is already that old). A retry or a newer replacement makes it a no-op.
    private func settled(_ l: NWListener, swap n: Int) {
        guard swap == .settling(n), l === listener else { return }
        swap = .idle
        if wantedPeerToPeer != peerToPeer { beginSwap(); return }
        l.service = service
        let at = l.port.map { " on port \($0.rawValue)" } ?? ""
        print("Direct wireless \(peerToPeer ? "on" : "off"): listening\(at) again" + (service == nil ? "." : ", advertised again."))
    }

    /// On `queue`: a replacement could not be bound, or failed once bound. Refused on its old port,
    /// it takes any port. Refused there too, the listener has failed and the existing rule applies
    /// (the app shows it and keeps running; the CLI exits). It never goes back to the old flag: the
    /// listener runs what the setting says, or has visibly failed. `peerToPeer` takes the wanted
    /// value, so the next change either way replaces the dead listener: a toggle is also a retry.
    private func replacementFailed(_ e: NWError, swap n: Int) {
        guard swap == .settling(n) else { return }
        if let port = replacementPort {
            print("Direct wireless \(wantedPeerToPeer ? "on" : "off"): port \(port.rawValue) unavailable (\(e)); trying another port.")
            bindReplacement(on: nil, swap: n)
            return
        }
        swap = .idle
        peerToPeer = wantedPeerToPeer
        print("Listener failed: \(e)")
        guard let handler = onListenerFailed else { exit(1) }   // the CLI, as always
        handler(e)
        onListenerState?(.failed(e))
    }

    /// Starts listening and advertising. Thread-safe: from here on the listener lives on `queue`.
    func start() {
        queue.async { [self] in
            // Set before start (the setting at launch): build the listener with it, nothing to replace.
            if wantedPeerToPeer != peerToPeer {
                do {
                    let l = try Self.makeListener(peerToPeer: wantedPeerToPeer, port: nil)
                    l.service = service
                    wire(l)
                    listener = l
                    peerToPeer = wantedPeerToPeer
                } catch {
                    print("Direct wireless \(wantedPeerToPeer ? "on" : "off"): the listener could not be built (\(error)); listening with it \(peerToPeer ? "on" : "off").")
                }
            }
            started = true
            listener.start(queue: queue)
        }
    }

    /// The port the listener got, once it is ready: how test clients reach the synthetic host.
    var port: UInt16? {
        portLock.lock(); defer { portLock.unlock() }
        return readyPort
    }

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
                    // A skipped report's maxima still reach the next line.
                    // Every report goes to `onClientStats` (the app's menu shows it live).
                    if let stats = Wire.decode(ClientStats.self, from: payload) {
                        client.worstFrameAgeSincePrint = max(client.worstFrameAgeSincePrint, stats.frameAgeMaxMs ?? -1)
                        client.worstRttSincePrint = max(client.worstRttSincePrint, stats.rttMaxMs ?? -1)
                        let now = CFAbsoluteTimeGetCurrent()
                        if now - client.lastStatsPrint >= 1.5 {
                            client.lastStatsPrint = now
                            let age = Self.medianAndWorst(stats.frameAgeMs, worst: stats.frameAgeMaxMs.map { _ in client.worstFrameAgeSincePrint })
                            let rtt = Self.medianAndWorst(stats.rttMs, worst: stats.rttMaxMs.map { _ in client.worstRttSincePrint })
                            print("client \(stats.device): \(stats.fps) fps, frame age \(age), rtt \(rtt)")
                            client.worstFrameAgeSincePrint = -1
                            client.worstRttSincePrint = -1
                        }
                        self.onClientStats?(c, stats)
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

    /// One number of a client stats line. A current client reports each second's median and max:
    /// "7/80 ms" is the last second's median over the worst since the previous line, "–" a second
    /// without a sample (no frame arrived, no pong came back), "–/80 ms" such a second after one
    /// that had samples. An older client sends one sample and no max (`worst` nil): "7 ms", as the
    /// line always read.
    private static func medianAndWorst(_ median: Int, worst: Int?) -> String {
        guard let worst else { return "\(median) ms" }
        if median < 0 { return worst < 0 ? "–" : "–/\(worst) ms" }
        return "\(median)/\(max(worst, median)) ms"
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
