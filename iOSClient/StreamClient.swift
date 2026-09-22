import Foundation
import Network
import QuartzCore
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

    /// Pixel size of the frames the host is sending, from the HEVC parameter sets. Input positions
    /// are fractions of this, so the overlay needs it to letterbox touches the way the layer does.
    @Published var videoSize: CGSize = .zero
    /// Round trip to the host in ms, from a ping every second while connected. -1 until measured.
    @Published var rttMs: Int = -1
    private var pingTimer: Timer?

    /// The one display view for the whole session. Landscape and portrait both host it, so a
    /// rotation reparents the same layer (and its last decoded image) instead of creating a fresh
    /// view that would sit black until the next keyframe, up to 4 s later. Main thread.
    private(set) lazy var displayView: HEVCDisplayView = {
        let view = HEVCDisplayView(frame: .zero)
        view.onVideoSize = { [weak self] size in self?.videoSize = size }
        onParameterSets = { ps in view.apply(ps) }
        onFrame = { data, isKey in view.enqueue(data, isKeyframe: isKey) }
        return view
    }()

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
    /// Frames received in the last second (main thread). Counts frames discarded while waiting for a keyframe too.
    @Published var fps = 0
    /// Host encode-output timestamp → received here, sampled every 15th frame. Assumes synced clocks;
    /// it is the transport part of latency, not glass-to-glass.
    @Published var frameAgeMs = 0
    private var latestFrameAgeMs = 0   // network queue copy, published from the 1 s timer
    private var lastParameterSets: ParameterSets?
    private var fpsTimer: Timer?

    // Pointer-move coalescing, all touched on `queue` only.
    private static let moveInterval = 0.008   // 125 Hz ceiling; a Pencil can report at 120+ Hz
    private var pendingMove: InputEvent?
    private var lastMoveAt = 0.0              // CACurrentMediaTime
    private var moveFlushScheduled = false

    func startBrowsing() {
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: "_sill._tcp", domain: nil), using: params)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.hosts = Array(results)
                // The Mac we were talking to came back (its Bonjour record vanished when the host
                // died and reappeared when it restarted): reconnect without being asked.
                if !self.connected, self.connection == nil, let wanted = self.reconnectTo,
                   let again = self.hosts.first(where: { Self.serviceName(of: $0) == wanted }) {
                    self.status = "Reconnecting to \(wanted)…"
                    self.connect(to: again)
                }
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed(let e) = state { DispatchQueue.main.async { self?.status = "Browse failed: \(e)" } }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    /// Bonjour instance name of the Mac we are connected to (or were, if it dropped).
    private var hostName = "Mac"
    /// Set when the Mac went away on its own; cleared by an explicit disconnect().
    private var reconnectTo: String?

    static func serviceName(of result: NWBrowser.Result) -> String {
        if case .service(let name, _, _, _) = result.endpoint { return name }
        return "\(result.endpoint)"
    }

    func connect(to result: NWBrowser.Result) {
        let name = Self.serviceName(of: result)
        hostName = name
        status = "Connecting to \(name)…"
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let params = NWParameters(tls: nil, tcp: tcp)
        params.includePeerToPeer = true
        let c = NWConnection(to: result.endpoint, using: params)
        c.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                DispatchQueue.main.async {
                    self.reconnectTo = nil
                    self.connected = true
                    self.status = "Connected to \(name)"
                    self.startFpsTimer()
                    self.startPingTimer()
                }
                self.readHeader()
            case .waiting(let e):
                print("connection waiting: \(e)")
                DispatchQueue.main.async { self.status = "Waiting for \(name)…" }
            case .failed(let e):
                print("connection failed: \(e)")
                self.connectionLost(c)
            case .cancelled:
                // Either disconnect() cancelled it (state already cleaned up) or the host closed it.
                self.connectionLost(c)
            default:
                break
            }
        }
        c.start(queue: queue)
        connection = c
    }

    /// The user chose to leave. No reconnect.
    func disconnect() {
        reconnectTo = nil
        let c = connection
        connection = nil
        c?.cancel()
        tearDown(status: "Looking for Macs on this network")
    }

    /// The Mac went away (host quit, Wi-Fi dropped, connection reset). Back to the connect screen with
    /// a plain message, and remember the Mac so we rejoin when it shows up again. Any thread.
    private func connectionLost(_ c: NWConnection) {
        DispatchQueue.main.async {
            guard self.connection === c else { return }   // stale callback from a connection we already replaced
            self.connection = nil
            self.reconnectTo = self.hostName
            self.tearDown(status: "\(self.hostName) disconnected. It will reconnect when the Mac is back.")
        }
    }

    /// Clears everything the session owned. Main thread.
    private func tearDown(status: String) {
        queue.async { self.lastParameterSets = nil; self.pendingMove = nil }
        fpsTimer?.invalidate()
        fpsTimer = nil
        pingTimer?.invalidate()
        pingTimer = nil
        rttMs = -1
        fps = 0
        frameAgeMs = 0
        queue.async { self.frameCounter = 0; self.latestFrameAgeMs = 0 }
        connected = false
        self.status = status
        macName = ""
        windows = []
        active = .none
        thumbnails = [:]
        icons = [:]
        apps = []
        videoSize = .zero
        displayView.clear()
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

    /// Send one input event to the Mac. Safe to call from the main thread; the work hops to the
    /// network queue, which is serial, so the host sees events in the order they were produced.
    ///
    /// Each event is its own small TCP message (noDelay is on), which is fine at click and keystroke
    /// rates. Pointer moves are not: a Pencil drag reports at 120+ Hz, so moves are coalesced to one
    /// every 8 ms, keeping only the latest position — an intermediate cursor position is worthless
    /// once a newer one exists, and queuing them would add latency to everything behind them.
    /// Nothing else is ever dropped, and a down/up/scroll/text/key first flushes any move still
    /// waiting, so the cursor is always where it should be before the button goes down.
    /// Any client → host message. Extensions (viewport, client stats) use this; frames never go this way.
    func send(_ kind: StreamMessageKind, payload: Data) {
        let message = StreamMessage(kind: kind, timestamp: Date().timeIntervalSince1970, isKeyframe: false, payload: payload)
        connection?.send(content: message.serialized(), completion: .contentProcessed { _ in })
    }

    func sendInput(_ event: InputEvent) {
        queue.async { [weak self] in
            guard let self else { return }
            guard case .pointer(.move, _, _) = event else {
                self.flushPendingMove()
                self.send(.input, Wire.encode(event))
                return
            }
            let now = CACurrentMediaTime()
            let due = self.lastMoveAt + Self.moveInterval
            if now >= due {
                self.pendingMove = nil
                self.lastMoveAt = now
                self.send(.input, Wire.encode(event))
            } else {
                self.pendingMove = event   // replaces any older pending move
                if !self.moveFlushScheduled {
                    self.moveFlushScheduled = true
                    self.queue.asyncAfter(deadline: .now() + (due - now)) { [weak self] in
                        guard let self else { return }
                        self.moveFlushScheduled = false
                        self.flushPendingMove()
                    }
                }
            }
        }
    }

    /// On `queue`.
    private func flushPendingMove() {
        guard let move = pendingMove else { return }
        pendingMove = nil
        lastMoveAt = CACurrentMediaTime()
        send(.input, Wire.encode(move))
    }

    private func send(_ kind: StreamMessageKind, _ payload: Data) {
        let message = StreamMessage(kind: kind, timestamp: Date().timeIntervalSince1970,
                                    isKeyframe: false, payload: payload)
        connection?.send(content: message.serialized(), completion: .contentProcessed { _ in })
    }

    // MARK: - Host → client

    private func readHeader() {
        guard let c = connection else { return }
        c.receive(minimumIncompleteLength: StreamMessage.headerLength, maximumLength: StreamMessage.headerLength) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            guard let data, let header = StreamMessage.parseHeader(data) else {
                // EOF (the host closed cleanly) or a read error: both mean the Mac is gone.
                if let error { print("read error: \(error)") }
                if isComplete || error != nil { self.connectionLost(c) }
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
                latestFrameAgeMs = Int((Date().timeIntervalSince1970 - header.timestamp) * 1000)
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
        case .pong:
            guard data.count >= 8 else { return }
            let sent = Double(bitPattern: data.readBigEndianUInt64())
            let rtt = Int((Date().timeIntervalSince1970 - sent) * 1000)
            DispatchQueue.main.async { self.rttMs = rtt }
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
                let age = self.latestFrameAgeMs
                DispatchQueue.main.async { self.fps = n; self.frameAgeMs = age }
            }
        }
    }
}

extension StreamClient {
    private func startPingTimer() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, let connection = self.connection else { return }
            var payload = Data(capacity: 8)
            var v = Date().timeIntervalSince1970.bitPattern.bigEndian
            Swift.withUnsafeBytes(of: &v) { payload.append(contentsOf: $0) }
            let message = StreamMessage(kind: .ping, timestamp: Date().timeIntervalSince1970, isKeyframe: false, payload: payload)
            connection.send(content: message.serialized(), completion: .contentProcessed { _ in })
        }
    }
}

private extension Data {
    func readBigEndianUInt64() -> UInt64 {
        var v: UInt64 = 0
        _ = Swift.withUnsafeMutableBytes(of: &v) { copyBytes(to: $0, from: startIndex..<(startIndex + 8)) }
        return UInt64(bigEndian: v)
    }
}
