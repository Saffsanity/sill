import Foundation
import Network
import StreamProtocol

/// Reach from Anywhere's door (docs/relay-plan.md): a TLS 1.3 listener on 127.0.0.1, on a port the
/// system picks, that only sill-net's tailnet node dials (RelaySupervisor tells it the port). It is
/// the remote door in all but where it listens: the same `Door(.remote)` admission (paired keys
/// while Remote Access is on, 8 sessions at most, pairing only in a window the Mac's user opened),
/// the same TLS identity and pins. Every connection here comes from 127.0.0.1, so its origin is
/// fixed: `.vpn` (a device away from home, the away quality), its label "through Sill Relay", and
/// never `.loopback`, which the rules treat as this Mac itself.
///
/// Who reaches this port: anything on this Mac that can dial 127.0.0.1 (as it can dial the remote
/// door), and devices on the Mac's own tailnet, whose ACL admits only tagged devices, to its port
/// 7455 alone. Neither gets further than a paired key would.
///
/// Runs while Remote Access and Reach from Anywhere are both on. Threading: StreamServer's network
/// queue, as RemoteServer.
final class RelayDoor {
    private let queue: DispatchQueue
    private unowned let server: StreamServer
    private let door: Door
    private var listener: NWListener?
    private var wanted = false
    private var retryItem: DispatchWorkItem?

    /// The bound port (on the network queue), or nil when it is not listening.
    var onPort: ((Int?) -> Void)?

    init(server: StreamServer, identity: HostIdentity, trust: TrustBox) {
        self.server = server
        queue = server.queue
        door = Door(.remote, queue: server.queue, identity: identity, trust: trust, testHost: server.isTestHost,
                    fixedArrival: (.vpn, "through \(RelayPolicy.serviceName)"))
        door.server = server
    }

    /// A pairing attempt here (a window the Mac's user opened); the reply may come from any thread.
    var onPairAttempt: ((Door.PairAttempt, @escaping @Sendable (PairResult) -> Void) -> Void)? {
        get { door.onPairAttempt }
        set { door.onPairAttempt = newValue }
    }

    /// Runs the door while `wanted`. Thread-safe.
    func set(wanted: Bool) {
        queue.async { [self] in
            self.wanted = wanted
            if !wanted {
                retryItem?.cancel(); retryItem = nil
                listener?.cancel(); listener = nil
                onPort?(nil)
            } else if listener == nil {
                start()
            }
        }
    }

    private func start() {
        retryItem?.cancel(); retryItem = nil
        let params = RemoteTLS.parameters(tls: door.tlsOptions(), dialing: false)
        StreamServer.bindToLoopback(params, port: nil)
        let l: NWListener
        do { l = try NWListener(using: params) } catch {
            print("Reach from Anywhere: its door couldn’t start (\(error)); trying again in 30 s.")
            retry()
            return
        }
        listener = l
        l.newConnectionHandler = { [weak self, weak l] c in
            guard let self, let l, l === self.listener else { c.cancel(); return }
            self.door.accept(c)
        }
        l.stateUpdateHandler = { [weak self, weak l] state in
            guard let self, let l, l === self.listener else { return }
            switch state {
            case .ready:
                self.onPort?(Int(l.port?.rawValue ?? 0))
            case .failed(let e):
                l.cancel()
                self.listener = nil
                self.onPort?(nil)
                print("Reach from Anywhere: its door stopped (\(e)); trying again in 30 s.")
                self.retry()
            default:
                break
            }
        }
        l.start(queue: queue)
    }

    private func retry() {
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.wanted, self.listener == nil else { return }
            self.start()
        }
        retryItem = item
        queue.asyncAfter(deadline: .now() + 30, execute: item)
    }
}
