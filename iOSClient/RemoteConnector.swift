import Foundation
import Network
import StreamProtocol

/// One dial of a Mac through the remote door (docs/remote-access-plan.md §7.5): its addresses in
/// RemoteDialPolicy's order, TLS 1.3 from RemoteTLS with this device's certificate, and the first
/// attempt to reach `.ready` as the winner. The others are cancelled at once, so the Mac never
/// serves a second catalog.
///
/// - A session dial (`.session`): attempts start `stagger` apart, or at once when the one before
///   fails; each connect gives up after RemoteTLS.dialTimeout; the whole dial after `wholeDial`.
///   Pinned to the saved Mac's key.
/// - A pairing dial (`.pairing`): one address at a time (pairing is single-use: two attempts
///   reaching the Mac would spend two of its tries), each with the connect timeout. The QR path is
///   pinned to the link's key, so a relay is refused before a byte is sent; the typed path takes
///   any P-256 key and binds the one it saw into its proof.
///
/// `.waiting(e)` ends an attempt at once (Network.framework would wait for a better path; a dial
/// with other addresses to try should not). Every callback arrives on `queue`, the client's
/// network queue, which the winner keeps.
final class RemoteConnector {
    enum Mode {
        case session(pin: Data)
        case pairing(pin: Data?)
    }

    struct Winner {
        let connection: NWConnection
        let candidate: RemoteDialPolicy.Candidate
        /// The Mac's key as this connection saw it (the pin, or on the typed path whatever it was).
        let fingerprint: Data
        /// The path went through a tunnel interface (a VPN).
        let usedTunnel: Bool
    }

    /// Every attempt failed (or the dial ran out of time): the most telling failure, with the
    /// address it came from.
    struct Failed {
        let failure: RemoteDialPolicy.Failure
        let candidate: RemoteDialPolicy.Candidate?
    }

    private final class Attempt {
        let candidate: RemoteDialPolicy.Candidate
        let connection: NWConnection
        var ended = false
        init(_ candidate: RemoteDialPolicy.Candidate, _ connection: NWConnection) {
            self.candidate = candidate; self.connection = connection
        }
    }

    private let queue: DispatchQueue
    private let candidates: [RemoteDialPolicy.Candidate]
    private let mode: Mode
    private let identity: RemoteIdentity
    // On `queue`.
    private var attempts: [Attempt] = []
    private var next = 0
    private var results: [(RemoteDialPolicy.Failure, RemoteDialPolicy.Candidate)] = []
    private var finished = false
    private var staggerItem: DispatchWorkItem?
    private var wholeItem: DispatchWorkItem?

    /// On `queue`. The winner's state handler is the caller's to replace.
    var onWinner: ((Winner) -> Void)?
    /// On `queue`, once, when no attempt won.
    var onFailed: ((Failed) -> Void)?

    init(candidates: [RemoteDialPolicy.Candidate], mode: Mode, identity: RemoteIdentity, queue: DispatchQueue) {
        self.candidates = candidates
        self.mode = mode
        self.identity = identity
        self.queue = queue
    }

    private var sequential: Bool { if case .pairing = mode { return true }; return false }

    func start() {
        queue.async { [self] in
            guard !finished else { return }
            if candidates.isEmpty { finish(); return }
            if !sequential {
                let item = DispatchWorkItem { [weak self] in self?.outOfTime() }
                wholeItem = item
                queue.asyncAfter(deadline: .now() + RemoteDialPolicy.wholeDial, execute: item)
            }
            startNext()
        }
    }

    /// Stops every attempt; nothing is called back afterwards. Any thread.
    func cancel() {
        queue.async { [self] in
            guard !finished else { return }
            finished = true
            staggerItem?.cancel(); wholeItem?.cancel()
            for a in attempts where !a.ended { a.ended = true; a.connection.cancel() }
        }
    }

    // MARK: On `queue`

    private func startNext() {
        guard !finished else { return }
        staggerItem?.cancel(); staggerItem = nil
        guard next < candidates.count else {
            if attempts.allSatisfy(\.ended) { finish() }
            return
        }
        let candidate = candidates[next]
        next += 1
        guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: candidate.port)), candidate.port > 0 else {
            results.append((.noAnswer, candidate))
            startNext()
            return
        }
        let alpn = sequential ? RemoteTLS.pairingALPN : RemoteTLS.sessionALPN
        let pin: Data? = { switch mode { case .session(let p): return p; case .pairing(let p): return p } }()
        // The whole of trust: the pin, or on the typed pairing path any P-256 key (nil is no P-256).
        let tls = RemoteTLS.options(identity: identity.tls, role: .client(alpn: alpn), verify: { fp in
            guard let fp else { return false }
            return pin.map { $0 == fp } ?? true
        }, queue: queue)
        let connection = NWConnection(host: NWEndpoint.Host(candidate.host), port: port,
                                      using: RemoteTLS.parameters(tls: tls, dialing: true))
        let attempt = Attempt(candidate, connection)
        attempts.append(attempt)
        connection.stateUpdateHandler = { [weak self, weak attempt] state in
            guard let self, let attempt else { return }
            self.stateChanged(attempt, state)
        }
        connection.start(queue: queue)
        if !sequential {
            let item = DispatchWorkItem { [weak self] in self?.startNext() }
            staggerItem = item
            queue.asyncAfter(deadline: .now() + RemoteDialPolicy.stagger, execute: item)
        }
    }

    private func stateChanged(_ attempt: Attempt, _ state: NWConnection.State) {
        guard !attempt.ended else { return }
        switch state {
        case .ready:
            guard !finished else { attempt.ended = true; attempt.connection.cancel(); return }
            finished = true
            attempt.ended = true
            staggerItem?.cancel(); wholeItem?.cancel()
            for other in attempts where other !== attempt && !other.ended {
                other.ended = true
                other.connection.cancel()
            }
            let c = attempt.connection
            c.stateUpdateHandler = nil
            let fp: Data? = RemoteTLS.peerFingerprint(c) ?? { if case .session(let p) = mode { return p }; return nil }()
            guard let fp else { c.cancel(); onFailed?(Failed(failure: .notSill, candidate: attempt.candidate)); return }
            onWinner?(Winner(connection: c, candidate: attempt.candidate, fingerprint: fp,
                             usedTunnel: c.currentPath?.usesInterfaceType(.other) ?? false))
        case .waiting(let error), .failed(let error):
            end(attempt, Self.end(of: error))
        case .cancelled:
            end(attempt, nil)
        default:
            break
        }
    }

    /// An attempt is over: its failure counts (unless it does not, a stranger at a LAN address),
    /// and the next address starts at once.
    private func end(_ attempt: Attempt, _ how: RemoteDialPolicy.End?) {
        attempt.ended = true
        let usedTunnel = attempt.connection.currentPath.map { $0.usesInterfaceType(.other) }
        attempt.connection.cancel()
        if let how, let failure = RemoteDialPolicy.classify(how, candidate: attempt.candidate, usedTunnel: usedTunnel) {
            results.append((failure, attempt.candidate))
        }
        #if DEBUG
        print("remote dial: \(attempt.candidate.host):\(attempt.candidate.port) ended \(how.map { "\($0)" } ?? "cancelled")")
        #endif
        guard !finished else { return }
        startNext()
    }

    private func outOfTime() {
        guard !finished else { return }
        for a in attempts where !a.ended {
            a.ended = true
            a.connection.cancel()
            results.append((RemoteDialPolicy.classify(.timeout, candidate: a.candidate, usedTunnel: a.connection.currentPath.map { $0.usesInterfaceType(.other) }) ?? .noAnswer, a.candidate))
        }
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        staggerItem?.cancel(); wholeItem?.cancel()
        let worst = RemoteDialPolicy.worst(results.map(\.0)) ?? .noAnswer
        onFailed?(Failed(failure: worst, candidate: results.first { $0.0 == worst }?.1 ?? candidates.first))
    }

    /// Network.framework's error as the policy reads it.
    static func end(of error: NWError) -> RemoteDialPolicy.End {
        switch error {
        case .posix(let code): return code == .ETIMEDOUT ? .timeout : .posix(code.rawValue)
        case .dns(let code): return .dns(code)
        case .tls(let status): return .tls(status)
        default: return .notSill
        }
    }
}
