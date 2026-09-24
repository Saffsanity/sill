import Foundation
import Network
import QuartzCore
import UIKit
import StreamProtocol

/// A Mac on the connect screen: one the network browser lists, or one seen only over peer-to-peer
/// Wi-Fi (`direct`: its Direct Wireless Connection is on and no network is shared). Constructible,
/// unlike NWBrowser.Result, so the DEBUG harness can seed the list.
struct FoundMac: Identifiable, Hashable {
    let name: String
    let endpoint: NWEndpoint
    /// Reached over peer-to-peer Wi-Fi alone: the one kind of row connected with includePeerToPeer.
    let direct: Bool
    var id: String { name }   // unique: DiscoveryPolicy.rows lists a name once
}

/// Finds Macs over Bonjour, connects, and splits the byte stream into messages.
/// Frame callbacks fire on the network queue; published state hops to main.
final class StreamClient: ObservableObject {
    // Connection. The setters of what the connect screen shows are internal: the DEBUG harness
    // seeds them.
    @Published var status = StreamClient.lookingOnNetwork
    /// The connect screen's rows (DiscoveryPolicy.rows): every Mac the network browser lists, then
    /// those seen only over peer-to-peer Wi-Fi.
    @Published var macs: [FoundMac] = []
    @Published var connected = false
    /// The nearby (peer-to-peer) browser runs: the status line says so.
    @Published var searchingNearby = false
    /// No Mac listed after the network's first seconds: the connect screen says why, and offers
    /// Search Nearby while the nearby browser is not running.
    @Published var showsNearbyHint = false
    /// This connection runs over peer-to-peer Wi-Fi: the Settings panel says so, and warns that
    /// turning Direct Wireless off can disconnect this device.
    @Published var connectedDirectly = false

    /// The connect screen's idle status lines: only these follow the nearby search.
    static let lookingOnNetwork = "Looking for Macs on this network"
    static let lookingNearby = "Looking for Macs on this network and nearby"

    // Switcher catalog, as the host sends it. Published on main.
    @Published var macName = ""
    @Published var windows: [WindowInfo] = []          // front to back, in the host's order
    /// The device's own arrangement of the bar (press, hold and drag), persisted per Mac. Windows
    /// the user has not arranged follow in the host's order.
    @Published private(set) var windowOrder: [UInt32] = []
    /// When the Desktop was last picked on the device's own initiative (see the window list).
    private var lastAutoDesktop: Date = .distantPast
    /// Picks and launches sent from this device (main thread). The automatic Desktop request that
    /// waits out a closed window stands down if this moved meanwhile: the user chose something,
    /// and the host cannot tell that request from a Desktop tap, so it could replace the choice.
    private var choicesSent = 0
    @Published var active: StreamSource = .none
    @Published var thumbnails: [UInt32: UIImage] = [:] // by window ID
    @Published var icons: [String: UIImage] = [:]      // by bundle ID
    @Published var apps: [AppInfo] = []                // installed apps, for "All apps"

    // The Mac's streaming settings (kinds 16 and 17; see the Host settings section below and
    // HostSettingsLedger.swift). Published on main.
    /// What the Settings panel shows: the Mac's last state on this connection with this device's
    /// unanswered picks laid over it. Internal setter: the DEBUG harness seeds it.
    @Published var settings = SettingsLedger()
    /// "Mac mini didn't answer. Try again.", shown inline in the panel; the next pick or answer clears it.
    @Published var settingsProblem: String?
    /// Bumped once per answer that refused something: the panel plays the warning haptic and
    /// announces it.
    @Published var settingsRefusals = 0
    /// When this connection became ready; nil while disconnected. The panel gives the first state
    /// two seconds before it calls the Mac an older one.
    @Published var connectedAt: Date?
    /// The next pick's token: strictly increasing for the life of the process, never reset, so an
    /// answer can never be taken for one to an earlier connection's pick.
    private var settingsToken = 1
    /// The pending picks' timeout check (one at a time, for the oldest).
    private var settingsExpiry: DispatchWorkItem?
    /// The worst round trip of the last second that had a pong (`linkStats.rtt.max`), for the pick
    /// timeout. Kept across seconds without one: a stalled slow link reports no rtt at all, and
    /// that must not shrink the timeout back to 4 s. Nil until measured; cleared on tear-down.
    private var lastRttMaxMs: Int?
    #if DEBUG
    /// Harness `pending` case: the mock never answers and never times out.
    var mockFrozen = false
    #endif

    /// Pixel size of the frames the host is sending, from the HEVC parameter sets. Input positions
    /// are fractions of this, so the overlay needs it to letterbox touches the way the layer does.
    @Published var videoSize: CGSize = .zero
    /// The client-drawn pointer, as a fraction of the video frame, or nil when hidden. Written by the
    /// trackpad and Pencil hover up to 120 times a second, read by the cursor sprite in the display
    /// view. Deliberately NOT @Published: a SwiftUI re-render per move is the lag it exists to avoid.
    /// Main thread only.
    var localPointer: CGPoint? { didSet { onLocalPointerChange?(localPointer) } }
    var onLocalPointerChange: ((CGPoint?) -> Void)?
    /// The last Viewport sent, so the local-cursor flag can be re-sent without re-measuring. Main thread.
    var lastViewport: Viewport?

    /// The Mac's current cursor image (hotspot and size in points), for the pointer sprite. Not
    /// @Published for the same reason as `localPointer`. Main thread.
    struct CursorShape { let image: UIImage; let hotspot: CGPoint; let size: CGSize }
    var cursorShape: CursorShape? { didSet { onCursorShapeChange?(cursorShape) } }
    var onCursorShapeChange: ((CursorShape?) -> Void)?

    /// What this device measured over the last second: frames, frame age and round trip. The
    /// network queue closes a window every second while connected and publishes it here; nil
    /// before the first one closes and after a disconnect. The HUD shows it, and
    /// `ClientStatsReporter` sends each one to the host exactly once. Main thread.
    @Published private(set) var linkStats: LinkStats?

    /// One second of measurements.
    struct LinkStats: Equatable {
        /// Frames received per second, frames discarded while waiting for a keyframe included.
        var fps: Int
        /// Host encode output → received here, over every frame of the second. Assumes synced
        /// clocks; it is the transport part of latency, not glass-to-glass. nil: no frame arrived.
        var frameAge: MedianMax?
        /// Ping round trips, over the pongs that came back during the second. nil: none did.
        var rtt: MedianMax?
    }

    /// The typical and the worst of one second's samples, in whole milliseconds.
    struct MedianMax: Equatable {
        let median: Int
        let max: Int

        /// nil for no samples: a second without a frame or a pong must not read as a fast one.
        init?(_ samples: [Double]) {
            guard !samples.isEmpty else { return nil }
            let sorted = samples.sorted()
            let mid = sorted.count / 2
            let median = sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
            self.median = Int(median.rounded())
            self.max = Int(sorted[sorted.count - 1].rounded())
        }
    }

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

    // Discovery (main thread). Two browsers: the network one always runs and never uses
    // peer-to-peer; the nearby one runs only when DiscoveryPolicy says, never while connected.
    private static let serviceType = "_sill._tcp"
    private var networkBrowser: NWBrowser?
    private var nearbyBrowser: NWBrowser?
    private var networkResults: [NWBrowser.Result] = []
    private var nearbyResults: [NWBrowser.Result] = []
    /// Launch, or the last connection ending: the network gets its first seconds from here.
    private var searchingSince = ProcessInfo.processInfo.systemUptime
    /// Search Nearby tapped since the last connection.
    private var askedNearby = false
    /// The policy's next look (its 3 s mark).
    private var discoveryRecheck: DispatchWorkItem?
    /// Macs this device last saw with Direct Wireless on, most recent first (DiscoveryPolicy.remember),
    /// keyed by the window list's Mac name like the bar order. A discovery hint only: the panel never
    /// reads it, so a Mac's settings are still only ever the ones it sent on this connection. A launch
    /// argument seeds it for one run: -Sill.directWirelessMacs '("Mac mini")', or '()' to clear it.
    private var directWirelessMacs = UserDefaults.standard.stringArray(forKey: StreamClient.directWirelessMacsKey) ?? []
    private static let directWirelessMacsKey = "Sill.directWirelessMacs"
    #if DEBUG
    /// Harness connect cases: the discovery state is seeded, no browser ever runs, and Search Nearby
    /// or a row's tap only change what is shown.
    var mockDiscovery = false
    #endif

    /// Read on `queue` (receive loop, sends) and written on main (connect, disconnect, loss): a
    /// plain stored property would be a data race on a strong reference.
    private var connection: NWConnection? {
        get { connectionLock.lock(); defer { connectionLock.unlock() }; return storedConnection }
        set { connectionLock.lock(); storedConnection = newValue; connectionLock.unlock() }
    }
    private var storedConnection: NWConnection?
    private let connectionLock = NSLock()
    private let queue = DispatchQueue(label: "sill.net", qos: .userInteractive)
    private var lastParameterSets: ParameterSets?

    // Measurement, all of it on `queue`: the open window's frames, frame ages and round trips, and
    // the two timers. Dispatch timers on the queue that counts the frames rather than main run loop
    // timers, which stop while a scroll is tracked: the numbers froze, and the next tick then
    // counted several seconds of frames as one ("222 fps").
    private var frameCounter = 0
    private var frameAgeSamples: [Double] = []   // ms, one per frame
    private var rttSamples: [Double] = []        // ms, one per pong
    private var windowOpenedAt = 0.0             // CACurrentMediaTime
    private var windowTimer: DispatchSourceTimer?
    private var pingTimer: DispatchSourceTimer?
    /// Four pings per one-second window, so a report has a median and a max: a single sample either
    /// landed in a stall or did not, and said nothing about the rest of the second.
    private static let pingInterval = 0.25
    /// A day. A sample beyond it is a broken clock, and clamping keeps an infinity away from `Int()`.
    private static let sampleCeilingMs = 86_400_000.0

    // Pointer-move coalescing, all touched on `queue` only.
    private static let moveInterval = 0.008   // 125 Hz ceiling; a Pencil can report at 120+ Hz
    private var pendingMove: InputEvent?
    private var lastMoveAt = 0.0              // CACurrentMediaTime
    private var moveFlushScheduled = false

    /// Starts the network browser (once). The nearby one follows the policy (`updateDiscovery`).
    func startBrowsing() {
        guard networkBrowser == nil else { return }
        searchingSince = ProcessInfo.processInfo.systemUptime
        // Network only: includePeerToPeer stays at its default, false. A peer-to-peer browse makes
        // the kernel bring AWDL up, which takes the radio off its Wi-Fi channel up to ~100 ms twice
        // a second (CLAUDE.md, trackpad stutter), and on a shared network AWDL carries nothing of
        // Sill's. Direct Wireless Connection is the Mac's opt-in for that route (the nearby browser).
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: NWParameters())
        browser.browseResultsChangedHandler = { [weak self, weak browser] results, _ in
            DispatchQueue.main.async {
                guard let self, let browser, self.networkBrowser === browser else { return }
                self.networkResults = Array(results)
                self.discoveryChanged()
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed(let e) = state { DispatchQueue.main.async { self?.status = "Browse failed: \(e)" } }
        }
        browser.start(queue: queue)
        networkBrowser = browser
        discoveryChanged()
    }

    /// Peer-to-peer, for a Mac whose Direct Wireless Connection is on and that shares no network
    /// with this device. Started and stopped by `updateDiscovery` only.
    private func startNearbyBrowser() {
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: params)
        browser.browseResultsChangedHandler = { [weak self, weak browser] results, _ in
            DispatchQueue.main.async {
                guard let self, let browser, self.nearbyBrowser === browser else { return }
                self.nearbyResults = Array(results)
                self.discoveryChanged()
            }
        }
        browser.start(queue: queue)
        nearbyBrowser = browser
    }

    /// A browser's results changed, or what the policy reads did. Main thread.
    private func discoveryChanged() {
        recomputeMacs()
        updateDiscovery()
        reconnectIfListed()
    }

    /// The rows, each with the endpoint of the browser that listed it: a network row always the
    /// network browser's, so at home a Mac is never reached over AWDL. Main thread.
    private func recomputeMacs() {
        let network = networkResults.map { (name: Self.serviceName(of: $0), endpoint: $0.endpoint) }
        let nearby = nearbyResults.map { (name: Self.serviceName(of: $0), endpoint: $0.endpoint, interfaces: $0.interfaces.map(\.name)) }
        let rows = DiscoveryPolicy.rows(network: network.map(\.name), nearby: nearby.map { ($0.name, $0.interfaces) })
        let next = rows.compactMap { row -> FoundMac? in
            let endpoint = row.direct ? nearby.first { $0.name == row.name }?.endpoint : network.first { $0.name == row.name }?.endpoint
            return endpoint.map { FoundMac(name: row.name, endpoint: $0, direct: row.direct) }
        }
        if next != macs { macs = next }
    }

    /// Runs the policy on what is known now: starts or stops the nearby browser, shows the hint,
    /// keeps an idle status line in step, and looks again at the network's 3 s mark. Main thread.
    private func updateDiscovery() {
        #if DEBUG
        if mockDiscovery { return }
        #endif
        let now = ProcessInfo.processInfo.systemUptime
        let out = DiscoveryPolicy.decide(DiscoveryPolicy.Input(
            now: now, connected: connected, onNetwork: Set(networkResults.map(Self.serviceName(of:))),
            remembered: Set(directWirelessMacs), searchingSince: searchingSince, askedNearby: askedNearby,
            nearbyRunning: nearbyBrowser != nil, listed: macs.count))
        if out.browseNearby, nearbyBrowser == nil {
            startNearbyBrowser()
            #if DEBUG
            print("discovery: nearby search on")
            #endif
        } else if !out.browseNearby, let browser = nearbyBrowser {
            browser.cancel()
            nearbyBrowser = nil
            nearbyResults = []
            recomputeMacs()
            #if DEBUG
            print("discovery: nearby search off")
            #endif
        }
        if searchingNearby != out.browseNearby { searchingNearby = out.browseNearby }
        if showsNearbyHint != out.showHint { showsNearbyHint = out.showHint }
        if status == Self.lookingOnNetwork || status == Self.lookingNearby {
            let idle = out.browseNearby ? Self.lookingNearby : Self.lookingOnNetwork
            if status != idle { status = idle }
        }
        discoveryRecheck?.cancel()
        discoveryRecheck = nil
        if let at = out.recheckAt {
            let work = DispatchWorkItem { [weak self] in self?.updateDiscovery() }
            discoveryRecheck = work
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0.01, at - now), execute: work)
        }
    }

    /// The connect screen's Search Nearby: also look over peer-to-peer Wi-Fi until a connection is
    /// ready. Main thread.
    func searchNearby() {
        askedNearby = true
        #if DEBUG
        if mockDiscovery {
            searchingNearby = true
            if status == Self.lookingOnNetwork { status = Self.lookingNearby }
            return
        }
        #endif
        updateDiscovery()
    }

    /// Bonjour instance name of the Mac we are connected to (or were, if it dropped).
    private var hostName = "Mac"
    /// Set when the Mac went away on its own; cleared by an explicit disconnect().
    private var reconnectTo: String?

    static func serviceName(of result: NWBrowser.Result) -> String {
        if case .service(let name, _, _, _) = result.endpoint { return name }
        return "\(result.endpoint)"
    }

    /// A row of the connect screen. Only a direct row is connected with peer-to-peer allowed.
    func connect(to mac: FoundMac) {
        #if DEBUG
        if mockDiscovery {
            status = mac.direct ? "Connecting to \(mac.name) directly…" : "Connecting to \(mac.name)…"
            return
        }
        #endif
        connect(to: mac.endpoint, name: mac.name, peerToPeer: mac.direct)
    }

    /// The Mac we were talking to is listed again: reconnect without being asked, to its network row
    /// when there is one. Names match exactly: two Macs can share a computer name ("MacBook Pro" and
    /// "MacBook Pro (2)"), and stripping the suffix would rejoin the wrong one. Main thread.
    @discardableResult
    private func reconnectIfListed() -> Bool {
        guard !connected, connection == nil, let wanted = reconnectTo,
              let mac = macs.first(where: { $0.name == wanted && !$0.direct }) ?? macs.first(where: { $0.name == wanted })
        else { return false }
        connect(to: mac)
        status = mac.direct ? "Reconnecting to \(wanted) directly…" : "Reconnecting to \(wanted)…"
        return true
    }

    /// Connects to a Bonjour result's endpoint, or straight to an address (DEBUG `-SillConnect`,
    /// later "add a Mac by address"). `name` is what the status line calls the Mac until its window
    /// list brings its own name. `peerToPeer` only for a Mac seen over peer-to-peer Wi-Fi alone.
    func connect(to endpoint: NWEndpoint, name: String, peerToPeer: Bool = false) {
        // One connection at a time. A tap on the connect screen racing the reconnect timer used to
        // open two: both then read from whichever `connection` pointed at, interleaving headers
        // and payloads, while the other was never read and the host evicted it after 4 s.
        if let old = connection {
            connection = nil
            old.cancel()      // its .cancelled callback is ignored: connectionLost checks identity
        }
        hostName = name
        status = peerToPeer ? "Connecting to \(name) directly…" : "Connecting to \(name)…"
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let params = NWParameters(tls: nil, tcp: tcp)
        // Peer-to-peer (AWDL) only for a "Direct" row: a Mac the network lists is reached over the
        // network (see startBrowsing), so at home a connection never takes AWDL.
        params.includePeerToPeer = peerToPeer
        // Wi-Fi QoS: video + pointer traffic is latency-sensitive; the access point and the radio
        // treat this class (WMM video) with shorter queues than best-effort.
        params.serviceClass = .interactiveVideo
        let c = NWConnection(to: endpoint, using: params)
        c.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                let direct = peerToPeer && Self.runsPeerToPeer(c.currentPath)
                DispatchQueue.main.async {
                    guard self.connection === c else { c.cancel(); return }   // replaced while connecting
                    self.reconnectTo = nil
                    self.connected = true
                    self.connectedDirectly = direct
                    self.askedNearby = false
                    self.connectedAt = Date()
                    self.status = "Connected to \(name)"
                    self.updateDiscovery()   // stops the nearby browser; the network one keeps running
                }
                self.startMeasuring(c)   // before the first read, so the first window is this connection's alone
                self.readHeader(on: c)
            case .waiting(let e):
                print("connection waiting: \(e)")
                DispatchQueue.main.async { self.status = "Waiting for \(name)…" }
                // A connection that never gets past waiting would block every reconnect path
                // (they all require `connection == nil`): give it five seconds, then let it go.
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                    guard let self, self.connection === c, !self.connected else { return }
                    c.cancel()
                }
            case .failed(let e):
                print("connection failed: \(e)")
                self.connectionLost(c)
                c.cancel()   // Network.framework releases a failed connection only once cancelled
            case .cancelled:
                // Either disconnect() cancelled it (state already cleaned up) or the host closed it.
                self.connectionLost(c)
            default:
                break
            }
        }
        connection = c        // before start: .ready can be delivered before the next line runs
        c.start(queue: queue)
    }

    /// Whether an established connection runs over peer-to-peer Wi-Fi: its remote address is scoped
    /// to an awdl or llw interface (an IPv6 link-local address carries its interface), or, with no
    /// scope to read, its path offers such an interface. On the network queue.
    private static func runsPeerToPeer(_ path: NWPath?) -> Bool {
        guard let path else { return false }
        if case .hostPort(let host, _)? = path.remoteEndpoint, case .ipv6(let address) = host, let interface = address.interface {
            return DiscoveryPolicy.isPeerToPeer(interface.name)
        }
        return path.availableInterfaces.contains { DiscoveryPolicy.isPeerToPeer($0.name) }
    }

    /// The user chose to leave. No reconnect.
    func disconnect() {
        reconnectTo = nil
        let c = connection
        connection = nil
        c?.cancel()
        tearDown(status: Self.lookingOnNetwork)
        updateDiscovery()
    }

    /// The Mac went away (host quit, Wi-Fi dropped, connection reset). Back to the connect screen with
    /// a plain message, and remember the Mac so we rejoin when it shows up again. Any thread.
    private func connectionLost(_ c: NWConnection) {
        DispatchQueue.main.async {
            guard self.connection === c else { return }   // stale callback from a connection we already replaced
            self.connection = nil
            self.reconnectTo = self.hostName
            self.tearDown(status: "\(self.hostName) disconnected. It will reconnect when the Mac is back.")
            self.updateDiscovery()
            self.scheduleReconnectRetry()
        }
    }

    /// The browse-results handlers reconnect when the Mac's Bonjour record comes back. If the record
    /// never left (the host dropped us but kept running), nothing would fire, so also retry on a
    /// timer while the Mac is still listed. Main thread.
    private func scheduleReconnectRetry(after seconds: TimeInterval = 2) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, !self.connected, self.connection == nil, self.reconnectTo != nil else { return }
            if !self.reconnectIfListed() { self.scheduleReconnectRetry(after: min(seconds * 2, 10)) }
        }
    }

    /// Clears everything the session owned. Main thread.
    private func tearDown(status: String) {
        queue.async { self.lastParameterSets = nil; self.pendingMove = nil; self.stopMeasuring() }
        linkStats = nil
        localPointer = nil
        cursorShape = nil
        connected = false
        connectedDirectly = false
        // The network gets its first seconds again before a remembered Mac is looked for nearby; the
        // callers then run the policy (updateDiscovery).
        searchingSince = ProcessInfo.processInfo.systemUptime
        askedNearby = false
        lastAutoDesktop = .distantPast     // the next connection starts on the Desktop again
        self.status = status
        macName = ""
        windows = []
        active = .none
        thumbnails = [:]
        icons = [:]
        apps = []
        videoSize = .zero
        displayView.clear()
        // Nothing of a Mac's settings outlives its connection: the next one sends them afresh.
        settings.reset()
        settingsProblem = nil
        connectedAt = nil
        settingsExpiry?.cancel()
        settingsExpiry = nil
        lastRttMaxMs = nil
    }

    // MARK: - Client → host

    /// Ask the host to stream this source. The host answers with a fresh window list.
    func select(_ source: StreamSource) {
        choicesSent += 1
        send(.selectSource, Wire.encode(source))
        #if DEBUG
        // Layout harness (mock, no connection): show the pick locally so taps can be checked.
        if connection == nil { DispatchQueue.main.async { self.active = source } }
        #endif
    }

    /// The bar's long-press menu: close, minimize or full-screen a window on the Mac.
    func command(_ action: WindowCommand.Action, window id: UInt32) {
        send(.windowCommand, Wire.encode(WindowCommand(id: id, action: action)))
    }

    // MARK: Bar order

    /// `windows` in the device's arrangement: arranged ones first, the rest in the host's order.
    var orderedWindows: [WindowInfo] {
        let byID = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0) })
        let arranged = windowOrder.compactMap { byID[$0] }
        let rest = windows.filter { !windowOrder.contains($0.id) }
        return arranged + rest
    }

    /// Moves a window to `index` of the arranged bar (a drag in progress). Main thread.
    func moveWindow(_ id: UInt32, to index: Int) {
        var order = orderedWindows.map(\.id)
        guard let from = order.firstIndex(of: id), index >= 0, index < order.count, from != index else { return }
        order.remove(at: from)
        order.insert(id, at: index)
        windowOrder = order
    }

    /// Saves the arrangement for this Mac (called when a drag ends). Stale ids are kept: a window
    /// that comes back keeps its place; the list is capped so it cannot grow without bound.
    func persistWindowOrder() {
        guard !macName.isEmpty else { return }
        let live = Set(windows.map(\.id))
        let kept = windowOrder.filter { live.contains($0) } + windowOrder.filter { !live.contains($0) }
        windowOrder = Array(kept.prefix(64))
        UserDefaults.standard.set(windowOrder.map { Int($0) }, forKey: Self.orderKey(for: macName))
    }

    private func loadWindowOrder() {
        let saved = UserDefaults.standard.array(forKey: Self.orderKey(for: macName)) as? [Int] ?? []
        windowOrder = saved.map { UInt32(truncatingIfNeeded: $0) }
    }

    private static func orderKey(for mac: String) -> String { "Sill.windowOrder." + mac }

    /// Ask the host to launch an installed app; the host selects its first window itself.
    func launch(bundleID: String) {
        choicesSent += 1   // the host picks the launched app's window: a choice, like a pick
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

    /// The read loop is bound to one connection: a replaced connection's loop stops at its next
    /// read instead of reading from the new one.
    private func readHeader(on c: NWConnection) {
        guard c === connection else { return }
        c.receive(minimumIncompleteLength: StreamMessage.headerLength, maximumLength: StreamMessage.headerLength) { [weak self] data, _, isComplete, error in
            guard let self, c === self.connection else { return }
            guard let data, let header = StreamMessage.parseHeader(data) else {
                // EOF (the host closed cleanly) or a read error: both mean the Mac is gone.
                if let error { print("read error: \(error)") }
                if isComplete || error != nil { self.connectionLost(c) }
                return
            }
            self.readPayload(header, on: c)
        }
    }

    private func readPayload(_ header: StreamHeader, on c: NWConnection) {
        // A zero-length payload is legal (an empty window list, say); receive() rejects length 0.
        guard header.payloadLength > 0 else {
            handle(header, Data())
            readHeader(on: c)
            return
        }
        c.receive(minimumIncompleteLength: header.payloadLength, maximumLength: header.payloadLength) { [weak self] data, _, _, _ in
            guard let self, c === self.connection, let data else { return }
            self.handle(header, data)
            self.readHeader(on: c)
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
            // Every frame is a sample, stamped on arrival before the hand-off to the display layer:
            // the worst frame of a second is the stutter, and one sample in fifteen missed it.
            // Clocks that disagree can make an age negative; nothing arrives before it was sent, so
            // that reads as 0, which keeps -1 free on the wire for "no frame this second".
            let age = (Date().timeIntervalSince1970 - header.timestamp) * 1000
            if age.isFinite { frameAgeSamples.append(min(max(age, 0), Self.sampleCeilingMs)) }
            frameCounter += 1
            onFrame?(data, header.isKeyframe)
        case .windowList:
            guard let list = Wire.decode(WindowList.self, from: data) else { return }
            DispatchQueue.main.async {
                if self.macName != list.macName { self.macName = list.macName; self.loadWindowOrder() }
                let previous = self.active
                self.windows = list.windows
                self.active = list.active
                // Forget thumbnails for windows that are gone.
                let live = Set(list.windows.map(\.id))
                self.thumbnails = self.thumbnails.filter { live.contains($0.key) }
                // The device starts on the Desktop, never on an empty panel: on the first list of a
                // connection, and again when the window being watched has closed. Not when a pick
                // failed (the host still lists the window): that is the user's to retry. At most
                // once every 10 s, so a host that cannot start the Desktop does not loop.
                if list.active == .none, Date().timeIntervalSince(self.lastAutoDesktop) > 10 {
                    switch previous {
                    case .none:
                        self.lastAutoDesktop = Date()
                        self.select(.desktop)
                    case .window(let id) where !list.windows.contains(where: { $0.id == id }):
                        // A window can drop off the list for a second or two (a Space change,
                        // full screen): only a window still gone after that has really closed.
                        // Not if the user picked or launched something meanwhile: this request
                        // could reach the host after that choice has started and replace it.
                        let choices = self.choicesSent
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                            guard let self, self.connected, self.active == .none, self.choicesSent == choices,
                                  !self.windows.contains(where: { $0.id == id }) else { return }
                            self.lastAutoDesktop = Date()
                            self.select(.desktop)
                        }
                    default:
                        break
                    }
                }
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
        case .cursorShape:
            guard let (hotspot, size, png) = CursorShapeBlob.decode(data), let image = UIImage(data: png) else { return }
            DispatchQueue.main.async { self.cursorShape = CursorShape(image: image, hotspot: hotspot, size: size) }
        case .hostSettings:
            guard let state = Wire.decode(HostSettingsState.self, from: data) else { return }
            let from = connection
            DispatchQueue.main.async {
                // A state from a connection that has since been replaced must not outlive its reset.
                guard self.connection === from else { return }
                self.receiveSettings(state)
            }
        case .pong:
            // The host echoes the ping's payload unchanged: our own monotonic send time.
            guard data.count >= 8 else { return }
            let sent = Double(bitPattern: data.readBigEndianUInt64())
            let rtt = (CACurrentMediaTime() - sent) * 1000
            if rtt.isFinite, rtt >= 0 { rttSamples.append(min(rtt, Self.sampleCeilingMs)) }
        default:
            break // client → host kinds, and anything a newer host invents
        }
    }

    // MARK: - Measurement (on `queue`)

    /// Starts the one-second windows and the pings for `c`, dropping whatever an earlier connection
    /// left behind. On `queue`, from the connection's ready state.
    private func startMeasuring(_ c: NWConnection) {
        guard c === connection else { return }   // replaced while connecting
        stopMeasuring()
        windowOpenedAt = CACurrentMediaTime()
        let window = DispatchSource.makeTimerSource(queue: queue)
        window.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(10))
        window.setEventHandler { [weak self, weak c] in
            guard let self, let c else { return }
            self.closeWindow(of: c)
        }
        window.resume()
        windowTimer = window
        let ping = DispatchSource.makeTimerSource(queue: queue)
        ping.schedule(deadline: .now() + Self.pingInterval, repeating: Self.pingInterval, leeway: .milliseconds(5))
        ping.setEventHandler { [weak self, weak c] in
            guard let self, let c else { return }
            self.sendPing(on: c)
        }
        ping.resume()
        pingTimer = ping
    }

    /// On `queue`.
    private func stopMeasuring() {
        windowTimer?.cancel()
        windowTimer = nil
        pingTimer?.cancel()
        pingTimer = nil
        frameCounter = 0
        frameAgeSamples.removeAll()
        rttSamples.removeAll()
    }

    /// Closes the open window and publishes it. On `queue`, once a second.
    private func closeWindow(of c: NWConnection) {
        guard c === connection else { return }   // replaced or gone: not this session's numbers
        let now = CACurrentMediaTime()
        let elapsed = now - windowOpenedAt
        windowOpenedAt = now
        // Per second of the window's real length, which is a second unless the app was suspended.
        let fps = elapsed > 0 ? Int((Double(frameCounter) / elapsed).rounded()) : frameCounter
        let stats = LinkStats(fps: fps, frameAge: MedianMax(frameAgeSamples), rtt: MedianMax(rttSamples))
        frameCounter = 0
        frameAgeSamples.removeAll(keepingCapacity: true)
        rttSamples.removeAll(keepingCapacity: true)
        DispatchQueue.main.async {
            guard self.connection === c else { return }   // torn down meanwhile: stay nil
            self.linkStats = stats
            if let rtt = stats.rtt { self.lastRttMaxMs = rtt.max }   // for the settings timeout
        }
    }

    /// On `queue`. Stamped with the monotonic clock: a wall-clock correction between a ping and its
    /// pong would otherwise land in the round trip.
    private func sendPing(on c: NWConnection) {
        guard c === connection else { return }
        var payload = Data(capacity: 8)
        var v = CACurrentMediaTime().bitPattern.bigEndian
        Swift.withUnsafeBytes(of: &v) { payload.append(contentsOf: $0) }
        let message = StreamMessage(kind: .ping, timestamp: Date().timeIntervalSince1970, isKeyframe: false, payload: payload)
        c.send(content: message.serialized(), completion: .contentProcessed { _ in })
    }
}

// MARK: - Host settings

extension StreamClient {
    /// A control's action: its field set to an absolute value. Sends only what changes what is
    /// shown, and nothing before this connection's first state (an older Mac never sends one).
    /// Nothing else ever sends a change: not a connect, not a broadcast, not an `onChange`. Main thread.
    func changeSettings(_ change: HostSettingsChange) {
        guard let out = settings.pick(change, token: settingsToken, now: ProcessInfo.processInfo.systemUptime) else { return }
        settingsToken += 1
        settingsProblem = nil
        send(.changeSettings, payload: Wire.encode(out))
        scheduleSettingsExpiry()
        #if DEBUG
        if connection == nil { mockAnswer(out) }
        #endif
    }

    /// A state from the Mac: a broadcast, or the answer to one of this device's picks. Main thread.
    private func receiveSettings(_ state: HostSettingsState) {
        let refused = settings.receive(state)
        if state.answering != nil { settingsProblem = nil }
        if !refused.isEmpty { settingsRefusals += 1 }
        scheduleSettingsExpiry()
        rememberDirectWireless(state)
    }

    /// Direct Wireless as this Mac last reported it, for discovery (DiscoveryPolicy.remember): every
    /// state carries it, and the window list, which names the Mac, comes first. Never from the DEBUG
    /// mock's answers (no connection). Main thread.
    private func rememberDirectWireless(_ state: HostSettingsState) {
        guard connection != nil, !macName.isEmpty else { return }
        let next = DiscoveryPolicy.remember(directWirelessMacs, mac: macName, directWireless: state.settings.directWireless)
        guard next != directWirelessMacs else { return }
        directWirelessMacs = next
        UserDefaults.standard.set(next, forKey: Self.directWirelessMacsKey)
        updateDiscovery()
    }

    /// How long a pick waits for its answer: 4 s, or four round trips on a slow link (a Mac
    /// reached from afar), counting the worst round trip of the last second that measured one; an
    /// RTT not measured yet counts as 4 s.
    private var settingsTimeout: Double { lastRttMaxMs.map { max(4, 4 * Double($0) / 1000) } ?? 4 }

    /// Arms the timeout check for the oldest pending pick, replacing any armed one.
    private func scheduleSettingsExpiry() {
        settingsExpiry?.cancel()
        settingsExpiry = nil
        guard let oldest = settings.pending.values.map(\.sentAt).min() else { return }
        let work = DispatchWorkItem { [weak self] in self?.expireSettings() }
        settingsExpiry = work
        let due = oldest + settingsTimeout + 0.05 - ProcessInfo.processInfo.systemUptime
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.05, due), execute: work)
    }

    /// Picks the Mac never answered go back to its value, with the problem shown inline.
    private func expireSettings() {
        #if DEBUG
        if mockFrozen { return }
        #endif
        if settings.expire(now: ProcessInfo.processInfo.systemUptime, timeout: settingsTimeout) {
            settingsProblem = "\(macName.isEmpty ? "The Mac" : macName) didn’t answer. Try again."
        }
        scheduleSettingsExpiry()   // a later pick, or a timeout that grew with the RTT
    }

    #if DEBUG
    /// The layout harness has no Mac: answer a pick after 0.35 s the way a host would, over the
    /// mock's state at that moment, refusing the virtual display where the mock has none. The
    /// readout follows as a restart would make it. Nothing under `mockFrozen`.
    private func mockAnswer(_ out: HostSettingsChange) {
        guard !mockFrozen else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.connection == nil, var state = self.settings.host else { return }
            var ok = out
            if ok.virtualDisplay == true, !state.virtualDisplayAvailable { ok.virtualDisplay = nil }
            let before = state.settings
            state.settings = ok.applied(to: before)
            if var stream = state.stream {
                stream.mbps = state.settings.bitrate * stream.fps / 60 / 1_000_000
                if !state.softwareEncoder, state.settings.captureScale != before.captureScale {
                    let f = state.settings.captureScale / before.captureScale
                    stream.width = Int(Double(stream.width) * f) & ~1
                    stream.height = Int(Double(stream.height) * f) & ~1
                }
                state.stream = stream
            }
            state.answering = out.token
            self.receiveSettings(state)
        }
    }

    /// `-SillConnect host:port`: connect straight to an address. The synthetic test hosts stay off
    /// Bonjour, so this is how the simulator reaches `SillHost --synthetic` and the bare
    /// `SillMenuBar --synthetic`. If such a connection drops, the reconnect timer looks for it on
    /// Bonjour, never finds it and backs off to 10 s: harmless in a debug build.
    func connectFromLaunchArgument() {
        guard let raw = UserDefaults.standard.string(forKey: "SillConnect"),
              let colon = raw.lastIndex(of: ":"),
              let number = UInt16(raw[raw.index(after: colon)...]),
              let port = NWEndpoint.Port(rawValue: number) else { return }
        connect(to: .hostPort(host: NWEndpoint.Host(String(raw[..<colon])), port: port), name: raw)
    }
    #endif
}

private extension Data {
    func readBigEndianUInt64() -> UInt64 {
        var v: UInt64 = 0
        _ = Swift.withUnsafeMutableBytes(of: &v) { copyBytes(to: $0, from: startIndex..<(startIndex + 8)) }
        return UInt64(bigEndian: v)
    }
}
