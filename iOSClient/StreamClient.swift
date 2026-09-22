import Foundation
import Network
import StreamProtocol

/// Finds Macs over Bonjour, connects, and splits the byte stream into messages.
/// Frame callbacks fire on the network queue; published state hops to main.
final class StreamClient: ObservableObject {
    @Published var status = "Looking for Macs on this network"
    @Published var hosts: [NWBrowser.Result] = []
    @Published var connected = false
    @Published var fps = 0
    @Published var frameAgeMs = 0

    var onParameterSets: ((ParameterSets) -> Void)?
    var onFrame: ((_ data: Data, _ isKeyframe: Bool) -> Void)?

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "winstream.net", qos: .userInteractive)
    private var frameCounter = 0
    private var fpsTimer: Timer?

    func startBrowsing() {
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_winstream._tcp", domain: nil), using: params)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            DispatchQueue.main.async { self?.hosts = Array(results) }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed(let e) = state { DispatchQueue.main.async { self?.status = "Browse failed: \(e)" } }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    func connect(to result: NWBrowser.Result) {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let params = NWParameters(tls: nil, tcp: tcp)
        params.includePeerToPeer = true
        let c = NWConnection(to: result.endpoint, using: params)
        c.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                DispatchQueue.main.async { self.connected = true; self.status = "Connected"; self.startFpsTimer() }
                self.readHeader()
            case .failed(let e):
                DispatchQueue.main.async { self.connected = false; self.status = "Failed: \(e)" }
            case .cancelled:
                DispatchQueue.main.async { self.connected = false; self.status = "Disconnected" }
            default:
                DispatchQueue.main.async { self.status = "\(state)" }
            }
        }
        c.start(queue: queue)
        connection = c
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
    }

    private func readHeader() {
        connection?.receive(minimumIncompleteLength: StreamMessage.headerLength, maximumLength: StreamMessage.headerLength) { [weak self] data, _, _, error in
            guard let self, let data, let header = StreamMessage.parseHeader(data) else {
                if let error { DispatchQueue.main.async { self?.status = "Read error: \(error)" } }
                return
            }
            self.readPayload(header)
        }
    }

    private func readPayload(_ header: StreamHeader) {
        connection?.receive(minimumIncompleteLength: header.payloadLength, maximumLength: header.payloadLength) { [weak self] data, _, _, _ in
            guard let self, let data else { return }
            switch header.kind {
            case .parameterSets:
                if let ps = ParameterSets(encoded: data) { self.onParameterSets?(ps) }
            case .frame:
                self.onFrame?(data, header.isKeyframe)
                self.frameCounter += 1
                if self.frameCounter % 15 == 0 {
                    // Approximate: both devices' clocks are NTP-synced, so this is glass-to-glass minus decode/display.
                    let age = Int((Date().timeIntervalSince1970 - header.timestamp) * 1000)
                    DispatchQueue.main.async { self.frameAgeMs = age }
                }
            }
            self.readHeader()
        }
    }

    private func startFpsTimer() {
        fpsTimer?.invalidate()
        fpsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.queue.async {
                let n = self.frameCounter
                self.frameCounter = 0
                DispatchQueue.main.async { self.fps = n }
            }
        }
    }
}
