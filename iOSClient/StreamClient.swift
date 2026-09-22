import Foundation
import Network
import UIKit
import StreamProtocol

/// Finds Macs over Bonjour, connects, and splits the byte stream into messages.
/// Frame callbacks fire on the network queue; published state hops to main.
final class StreamClient: ObservableObject {
    // Connection
    @Published var status = "Looking for Macs on this network"
    @Published var hosts: [NWBrowser.Result] = []
    @Published var connected = false

    // Switcher catalog, as the host sends it. Published on main.
    @Published var macName = ""
    @Published var windows: [WindowInfo] = []          // front to back, in the host's order
    @Published var active: StreamSource = .none
    @Published var thumbnails: [UInt32: UIImage] = [:] // by window ID
    @Published var icons: [String: UIImage] = [:]      // by bundle ID
    @Published var apps: [AppInfo] = []                // installed apps, for "All apps"

    var onParameterSets: ((ParameterSets) -> Void)? {
        didSet {
            // The display view is only created once the UI switches to the stream screen, which
            // can land after the host's parameter sets have already arrived. Replay the last ones
            // so a stream that is already running is not stuck waiting for the next set.
            let callback = onParameterSets
            queue.async { [weak self] in
                guard let self, let ps = self.lastParameterSets else { return }
                callback?(ps)
            }
        }
    }
    var onFrame: ((_ data: Data, _ isKeyframe: Bool) -> Void)?

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "sill.net", qos: .userInteractive)
    private var frameCounter = 0
    private var frameAgeMs = 0
    private var lastParameterSets: ParameterSets?
    private var fpsTimer: Timer?

    func startBrowsing() {
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_sill._tcp", domain: nil), using: params)
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
        queue.async { self.lastParameterSets = nil }
        DispatchQueue.main.async {
            self.fpsTimer?.invalidate()
            self.fpsTimer = nil
            self.connected = false
            self.macName = ""
            self.windows = []
            self.active = .none
            self.thumbnails = [:]
            self.icons = [:]
            self.apps = []
        }
    }

    // MARK: - Client → host

    /// Ask the host to stream this source. The host answers with a fresh window list.
    func select(_ source: StreamSource) {
        send(.selectSource, Wire.encode(source))
    }

    /// Ask the host to launch an installed app; the host selects its first window itself.
    func launch(bundleID: String) {
        send(.launchApp, Wire.encode(LaunchApp(bundleID: bundleID)))
    }

    private func send(_ kind: StreamMessageKind, _ payload: Data) {
        let message = StreamMessage(kind: kind, timestamp: Date().timeIntervalSince1970,
                                    isKeyframe: false, payload: payload)
        connection?.send(content: message.serialized(), completion: .contentProcessed { _ in })
    }

    // MARK: - Host → client

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
        // A zero-length payload is legal (an empty window list, say); receive() rejects length 0.
        guard header.payloadLength > 0 else {
            handle(header, Data())
            readHeader()
            return
        }
        connection?.receive(minimumIncompleteLength: header.payloadLength, maximumLength: header.payloadLength) { [weak self] data, _, _, _ in
            guard let self, let data else { return }
            self.handle(header, data)
            self.readHeader()
        }
    }

    /// On the network queue.
    private func handle(_ header: StreamHeader, _ data: Data) {
        switch header.kind {
        case .parameterSets:
            if let ps = ParameterSets(encoded: data) {
                lastParameterSets = ps
                onParameterSets?(ps)
            }
        case .frame:
            onFrame?(data, header.isKeyframe)
            frameCounter += 1
            if frameCounter % 15 == 0 {
                // Approximate: both devices' clocks are NTP-synced, so this is glass-to-glass minus decode/display.
                frameAgeMs = Int((Date().timeIntervalSince1970 - header.timestamp) * 1000)
            }
        case .windowList:
            guard let list = Wire.decode(WindowList.self, from: data) else { return }
            DispatchQueue.main.async {
                self.macName = list.macName
                self.windows = list.windows
                self.active = list.active
                // Forget thumbnails for windows that are gone.
                let live = Set(list.windows.map(\.id))
                self.thumbnails = self.thumbnails.filter { live.contains($0.key) }
            }
        case .thumbnail:
            guard let (windowID, jpeg) = ImageBlob.decodeThumbnail(data),
                  let image = UIImage(data: jpeg) else { return }
            DispatchQueue.main.async { self.thumbnails[windowID] = image }
        case .appIcon:
            guard let (bundleID, png) = ImageBlob.decodeIcon(data),
                  let image = UIImage(data: png) else { return }
            DispatchQueue.main.async { self.icons[bundleID] = image }
        case .appList:
            guard let apps = Wire.decode([AppInfo].self, from: data) else { return }
            DispatchQueue.main.async { self.apps = apps }
        default:
            break // client → host kinds, and anything a newer host invents
        }
    }

    private func startFpsTimer() {
        fpsTimer?.invalidate()
        fpsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.queue.async {
                let n = self.frameCounter
                self.frameCounter = 0
                // No overlay in the UI any more; the console is where the numbers live.
                print("client: \(n) fps · frame age ≈ \(self.frameAgeMs) ms")
            }
        }
    }
}
