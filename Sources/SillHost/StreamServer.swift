import Foundation
import Network
import StreamProtocol

/// Advertises _sill._tcp over Bonjour and pushes messages to every connected client.
/// Slow clients drop delta frames rather than building a queue (that queue is latency).
final class StreamServer {
    private final class Client {
        let connection: NWConnection
        var inflight = 0
        var needsKeyframe = true
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

    init(serviceType: String = "_sill._tcp") throws {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let params = NWParameters(tls: nil, tcp: tcp)
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
                self?.clients[id] = nil
            default: break
            }
        }
        clients[id] = client
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
            guard let client = clients[ObjectIdentifier(connection)] else { return }
            send(data, to: client)
        }
    }

    /// Client → host messages share the same framing. Small and rare, so read them one at a time.
    private func receiveLoop(_ client: Client) {
        let c = client.connection
        c.receive(minimumIncompleteLength: StreamMessage.headerLength, maximumLength: StreamMessage.headerLength) { [weak self] data, _, _, _ in
            guard let self, let data, let header = StreamMessage.parseHeader(data) else { return }
            let deliver = { (payload: Data) in
                self.onMessage?(StreamMessage(kind: header.kind, timestamp: header.timestamp, isKeyframe: header.isKeyframe, payload: payload), c)
                self.receiveLoop(client)
            }
            if header.payloadLength == 0 { deliver(Data()); return }
            c.receive(minimumIncompleteLength: header.payloadLength, maximumLength: header.payloadLength) { data, _, _, _ in
                guard let data else { return }
                deliver(data)
            }
        }
    }

    /// Thread-safe: hops onto the network queue.
    func broadcast(_ message: StreamMessage) {
        let data = message.serialized()
        queue.async { [self] in
            if message.kind == .parameterSets { lastParameterSets = data }
            for client in clients.values where client.connection.state == .ready {
                if message.kind == .frame {
                    if client.needsKeyframe {
                        guard message.isKeyframe, let ps = lastParameterSets else { Stats.shared.bump("net.waitKey"); continue }
                        send(ps, to: client)
                        client.needsKeyframe = false
                    } else if client.inflight > 2 && !message.isKeyframe {
                        Stats.shared.bump("net.dropped")
                        continue   // drop the delta; the next keyframe will resync
                    }
                    Stats.shared.bump("net.sent")
                }
                send(data, to: client)
            }
        }
    }

    private func send(_ data: Data, to client: Client) {
        client.inflight += 1
        client.connection.send(content: data, completion: .contentProcessed { [weak client] _ in
            client?.inflight -= 1
        })
    }
}
