import Foundation
import Network
import StreamProtocol

/// The remote door (docs/remote-access-plan.md §4.7): a TLS 1.3 listener on a fixed port, for
/// paired devices only, running while Remote Access is on or a pairing window is open. Both sides
/// present self-signed P-256 certificates and pin each other's key (RemoteTLS). No Bonjour.
///
/// Before admission a connection is cheap to refuse: at most 8 pending in all and 2 per source,
/// a source with 5 failures in 60 s is refused for 300 s, and 10 s from accept to admission (TLS,
/// plus the one kind 19 of a pairing connection). Sources the Mac's internet switch does not admit
/// are cancelled before TLS. The verify block decides trust from the lock-protected TrustSnapshot
/// and the negotiated ALPN: `sill/1` only for a paired key, `sill-pair/1` only while a pairing
/// window is open. Refusals are counted and reported at most once a minute.
///
/// Admitted sessions go to `StreamServer.serve` with their route; a pairing connection carries
/// exactly one PairRequest, judged on the main actor (RemoteAccess), and one PairResult back.
///
/// Threading: everything here runs on StreamServer's network queue, which the listener, the
/// connections, their verify blocks and the timers share. Callbacks out are on that queue.
///
/// TEST ONLY: SILL_TEST_BACKOFF_SECONDS=<s> replaces the 300 s backoff on a host that does not
/// advertise.
final class RemoteServer {
    /// One pairing attempt, for RemoteAccess to judge on the main actor.
    struct PairAttempt: Sendable {
        let request: PairRequest
        /// From the TLS session, never from the message.
        let deviceFingerprint: Data
        /// The connection's address, for the per-source rule and the log.
        let source: String
    }

    static let maxPending = 8
    static let maxPendingPerSource = 2
    static let maxSessions = 8
    static let admissionDeadline: TimeInterval = 10
    static let failureWindow: TimeInterval = 60
    static let failuresForBackoff = 5
    static let retryInterval: TimeInterval = 30

    private let queue: DispatchQueue
    private unowned let server: StreamServer
    private let identity: HostIdentity
    private let trust: TrustBox
    private let backoff: TimeInterval

    /// The listener's port and state are called back on the network queue.
    var onListener: ((RemoteStatus.Listener) -> Void)?
    /// A pairing attempt; the reply may be called from any thread.
    var onPairAttempt: ((PairAttempt, @escaping @Sendable (PairResult) -> Void) -> Void)?

    // On `queue`.
    private var listener: NWListener?
    private var wanted = false
    private var port = HostConfig.defaultRemotePort
    private var retryItem: DispatchWorkItem?
    private var reportedFailure = false

    private struct Pending {
        let connection: NWConnection
        let source: String
        var origin: OriginPolicy.Origin?
        var interface: String?
        /// Counted in the minute's summary already.
        var reported = false
        var deadline: DispatchWorkItem?
    }
    private var pending: [ObjectIdentifier: Pending] = [:]
    private var failures: [String: [CFAbsoluteTime]] = [:]
    private var backoffUntil: [String: CFAbsoluteTime] = [:]

    private lazy var refusals = RefusalSummary(queue: queue, categories: ["unpaired", "internet", "limit"]) { c in
        let n = c.values.reduce(0, +)
        return "Remote access refused \(n) connection\(n == 1 ? "" : "s") in the last minute: \(c["unpaired", default: 0]) unpaired, "
            + "\(c["internet", default: 0]) from the internet (internet access off), \(c["limit", default: 0]) over the limit."
    }

    init(server: StreamServer, identity: HostIdentity, trust: TrustBox) {
        self.server = server
        queue = server.queue
        self.identity = identity
        self.trust = trust
        var b: TimeInterval = 300
        if server.isTestHost, let v = ProcessInfo.processInfo.environment["SILL_TEST_BACKOFF_SECONDS"], let s = Double(v), s > 0 { b = s }
        backoff = b
    }

    // MARK: The listener

    /// Runs the door on `port` (0: any free port) while `wanted`. A new port replaces the listener
    /// (accepted connections are independent of it, so sessions carry on). Thread-safe.
    func set(wanted: Bool, port: Int) {
        queue.async { [self] in
            let portChanged = port != self.port
            self.wanted = wanted
            self.port = port
            guard wanted else {
                stopListener()
                onListener?(.off)
                return
            }
            if listener != nil, !portChanged { return }
            stopListener()
            startListener()
        }
    }

    /// A network change: if the door should run and does not (the port was in use), try now.
    func retryNow() {
        queue.async { [self] in
            if wanted, listener == nil { startListener() }
        }
    }

    private func stopListener() {
        retryItem?.cancel(); retryItem = nil
        listener?.cancel()
        listener = nil
    }

    private func startListener() {
        retryItem?.cancel(); retryItem = nil
        let tls = RemoteTLS.options(identity: identity.remote.tls, role: .server, queue: queue) { [weak self] fp, alpn in
            self?.verify(fp, alpn) ?? false
        }
        let params = RemoteTLS.parameters(tls: tls, dialing: false)
        let l: NWListener
        do {
            if port == 0 {
                l = try NWListener(using: params)
            } else {
                guard let p = NWEndpoint.Port(rawValue: UInt16(port)) else { failed(.posix(.EINVAL)); return }
                l = try NWListener(using: params, on: p)
            }
        } catch {
            failed(error as? NWError ?? .posix(.EINVAL))
            return
        }
        listener = l
        l.newConnectionHandler = { [weak self, weak l] c in
            guard let self, let l, l === self.listener else { c.cancel(); return }
            self.accept(c)
        }
        l.stateUpdateHandler = { [weak self, weak l] state in
            guard let self, let l, l === self.listener else { return }
            switch state {
            case .ready:
                let bound = Int(l.port?.rawValue ?? 0)
                reportedFailure = false
                print("Remote access: listening on port \(bound) (TLS, paired devices only; \(trust.snapshot.paired.count) paired).")
                onListener?(.listening(bound))
            case .failed(let e):
                l.cancel()
                listener = nil
                failed(e)
            case .waiting(let e):
                if case .posix(.EADDRINUSE) = e {
                    l.cancel()
                    listener = nil
                    failed(e)
                }
            default:
                break
            }
        }
        l.start(queue: queue)
    }

    /// Never another port by itself: saved addresses depend on this one. Retried every 30 s and
    /// on network changes; the door never exits the process.
    private func failed(_ e: NWError) {
        if case .posix(.EADDRINUSE) = e {
            if !reportedFailure { print("Remote access: port \(port) is in use by another app; trying again every 30 s.") }
            onListener?(.portInUse(port))
        } else {
            if !reportedFailure { print("Remote access couldn’t start (\(e)); trying again every 30 s.") }
            onListener?(.failed("\(e)"))
        }
        reportedFailure = true
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.wanted, self.listener == nil else { return }
            self.startListener()
        }
        retryItem = item
        queue.asyncAfter(deadline: .now() + Self.retryInterval, execute: item)
    }

    // MARK: Admission

    /// On `queue`, in the TLS handshake: trust is the pin and the protocol, nothing else.
    private func verify(_ fp: Data?, _ alpn: String?) -> Bool {
        guard let fp else { return false }
        let t = trust.snapshot
        switch alpn {
        case RemoteTLS.sessionALPN?: return t.paired[fp] != nil
        case RemoteTLS.pairingALPN?: return t.pairingOpen
        default: return false
        }
    }

    private func sourceText(_ c: NWConnection) -> String {
        guard case .hostPort(let host, _) = c.endpoint else { return "\(c.endpoint)" }
        return StreamServer.addressText(host).text
    }

    private func accept(_ c: NWConnection) {
        let now = CFAbsoluteTimeGetCurrent()
        let source = sourceText(c)
        prune(now)
        if let until = backoffUntil[source], now < until {
            c.cancel()
            refusals.count("limit")
            return
        }
        let fromSource = pending.values.filter { $0.source == source }.count
        guard pending.count < Self.maxPending, fromSource < Self.maxPendingPerSource else {
            c.cancel()
            refusals.count("limit")
            return
        }
        let id = ObjectIdentifier(c)
        let deadline = DispatchWorkItem { [weak self] in self?.deadlinePassed(id) }
        pending[id] = Pending(connection: c, source: source, deadline: deadline)
        queue.asyncAfter(deadline: .now() + Self.admissionDeadline, execute: deadline)
        c.stateUpdateHandler = { [weak self] state in self?.stateChanged(id, c, state) }
        c.start(queue: queue)
    }

    private func stateChanged(_ id: ObjectIdentifier, _ c: NWConnection, _ state: NWConnection.State) {
        switch state {
        case .preparing:
            _ = checkOrigin(id, c)
        case .ready:
            readyArrived(id, c)
        case .failed:
            c.cancel()
            endedBeforeAdmission(id)
        case .cancelled:
            endedBeforeAdmission(id)
        default:
            break
        }
    }

    /// At the first state with a path: a source the door does not admit is cancelled before TLS
    /// gets anywhere. False when it was refused.
    private func checkOrigin(_ id: ObjectIdentifier, _ c: NWConnection) -> Bool {
        guard var p = pending[id] else { return false }
        if p.origin != nil { return true }
        let (origin, interface) = server.arrival(of: c)
        p.origin = origin
        p.interface = interface
        pending[id] = p
        guard OriginPolicy.remoteAdmits(origin, internetAccess: trust.snapshot.internetAccess) else {
            report(id, "internet")
            c.cancel()
            return false
        }
        return true
    }

    private func readyArrived(_ id: ObjectIdentifier, _ c: NWConnection) {
        guard pending[id] != nil, checkOrigin(id, c) else { return }
        let fp = RemoteTLS.peerFingerprint(c)
        switch RemoteTLS.negotiatedALPN(c) {
        case RemoteTLS.sessionALPN?: admitSession(id, c, fp)
        case RemoteTLS.pairingALPN?: readPairRequest(id, c, fp)
        default:
            report(id, "unpaired")
            c.cancel()
        }
    }

    /// `sill/1`: a paired key (checked again), Remote Access on, fewer than 8 sessions.
    private func admitSession(_ id: ObjectIdentifier, _ c: NWConnection, _ fp: Data?) {
        let t = trust.snapshot
        guard let fp, let name = t.paired[fp] else {
            report(id, "unpaired")
            c.cancel()
            return
        }
        guard let p = pending.removeValue(forKey: id) else { return }
        p.deadline?.cancel()
        guard t.remoteAccess else {
            StreamServer.sayGoodbye(Goodbye.remoteOff, on: c, queue: queue)
            return
        }
        guard server.remoteSessionCount < Self.maxSessions else {
            refusals.count("limit")
            StreamServer.sayGoodbye(Goodbye.busy, on: c, queue: queue)
            return
        }
        let origin = p.origin ?? .loopback
        let label = OriginPolicy.label(origin, interface: p.interface, serviceName: p.interface.flatMap { t.serviceNames[$0] }) ?? "by address"
        server.serve(c, route: .remote(origin: origin, label: label, fingerprint: fp, name: name))
        print("Remote client connected: \(name) \(label) (\(c.endpoint))")
    }

    /// `sill-pair/1`: exactly one kind 19 of at most 4 KB within the admission deadline, judged on
    /// the main actor, answered with one kind 20, then closed once that is sent (or after 250 ms).
    private func readPairRequest(_ id: ObjectIdentifier, _ c: NWConnection, _ fp: Data?) {
        guard trust.snapshot.pairingOpen, let fp else {
            report(id, "unpaired")
            c.cancel()
            return
        }
        c.receive(minimumIncompleteLength: StreamMessage.headerLength, maximumLength: StreamMessage.headerLength) { [weak self] data, _, _, _ in
            guard let self else { return }
            guard let data, let h = StreamMessage.parseHeader(data), h.kind == .pairRequest,
                  h.payloadLength > 0, h.payloadLength <= StreamMessage.maxPairingPayload else {
                self.report(id, "unpaired")
                c.cancel()
                return
            }
            c.receive(minimumIncompleteLength: h.payloadLength, maximumLength: h.payloadLength) { [weak self] data, _, _, _ in
                guard let self else { return }
                guard let data, let request = Wire.decode(PairRequest.self, from: data), var p = self.pending.removeValue(forKey: id) else {
                    self.report(id, "unpaired")
                    c.cancel()
                    return
                }
                p.deadline?.cancel()
                p.deadline = nil
                guard let judge = self.onPairAttempt else { c.cancel(); return }
                let queue = self.queue
                judge(PairAttempt(request: request, deviceFingerprint: fp, source: p.source)) { result in
                    queue.async {
                        let reply = StreamMessage(kind: .pairResult, timestamp: Date().timeIntervalSince1970, isKeyframe: false,
                                                  payload: Wire.encode(result)).serialized()
                        c.send(content: reply, completion: .contentProcessed { _ in c.cancel() })
                        queue.asyncAfter(deadline: .now() + 0.25) { c.cancel() }
                    }
                }
            }
        }
    }

    /// Counts one refusal for the minute's summary, once per connection.
    private func report(_ id: ObjectIdentifier, _ category: String) {
        guard var p = pending[id], !p.reported else { return }
        p.reported = true
        pending[id] = p
        refusals.count(category)
    }

    private func deadlinePassed(_ id: ObjectIdentifier) {
        guard let p = pending[id] else { return }
        report(id, "unpaired")
        p.connection.cancel()        // `.cancelled` then counts the failure
    }

    /// A connection that ended before it was admitted: one failure for its source (5 in 60 s → a
    /// backoff), and a refusal for the summary unless one was counted already.
    private func endedBeforeAdmission(_ id: ObjectIdentifier) {
        guard let p = pending.removeValue(forKey: id) else { return }
        p.deadline?.cancel()
        if !p.reported { refusals.count("unpaired") }
        let now = CFAbsoluteTimeGetCurrent()
        var list = (failures[p.source] ?? []).filter { now - $0 < Self.failureWindow }
        list.append(now)
        if list.count >= Self.failuresForBackoff {
            backoffUntil[p.source] = now + backoff
            list = []
        }
        failures[p.source] = list
    }

    /// Forgets stale per-source records, so a scan from many addresses cannot grow them for ever.
    private func prune(_ now: CFAbsoluteTime) {
        if failures.count > 256 { failures = failures.filter { $0.value.contains { now - $0 < Self.failureWindow } } }
        if backoffUntil.count > 256 { backoffUntil = backoffUntil.filter { $0.value > now } }
    }

    // MARK: Closing sessions

    /// Every admitted remote session whose route matches gets goodbye `reason` and is closed; `line`
    /// names one (from its paired name and endpoint) for the log, and `done` gets how many there
    /// were. Thread-safe.
    func closeSessions(_ reason: String, matching: @escaping @Sendable (ClientRoute) -> Bool,
                       line: (@Sendable (String, String) -> String)? = nil, done: (@Sendable (Int) -> Void)? = nil) {
        queue.async { [self] in
            let list = server.sessions { $0.isRemote && matching($0) }
            for (c, route) in list {
                if let line { print(line(route.pairedName ?? "a device", "\(c.endpoint)")) }
                server.goodbye(reason, to: c)
            }
            done?(list.count)
        }
    }
}
