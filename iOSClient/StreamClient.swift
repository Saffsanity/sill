import Foundation
import Network
import QuartzCore
import UIKit
import StreamProtocol

/// A Mac on the connect screen: one the network browser lists, one seen only over peer-to-peer
/// Wi-Fi (Direct: its Direct Wireless Connection is on and no network is shared), or a saved Mac
/// that neither browser lists (Remote: dialed at its saved addresses through the remote door).
/// Constructible, unlike NWBrowser.Result, so the DEBUG harness can seed the list.
struct FoundMac: Identifiable, Hashable {
    enum Route: String, Hashable { case network, direct, remote }

    let name: String
    /// The browser's endpoint; nil for a Remote row.
    let endpoint: NWEndpoint?
    let route: Route
    /// The saved Mac this row is: a network or Direct row whose TXT tag this device resolved, or
    /// a Remote row. Nil for any other Mac.
    let macID: String?
    /// How the Mac is reachable, the word at the end of a network or Direct row ("Wired", "Wi-Fi",
    /// "Direct"), or nil when the interfaces it was seen on do not say (DiscoveryPolicy.method), and
    /// for a Remote row. Only shown: which route a tap takes is `route`'s and `wired`'s.
    let method: DiscoveryPolicy.Method?
    /// The wired Ethernet interface the network browser saw the Mac on, which a tap, an automatic
    /// reconnect and a move dial it on first (DiscoveryPolicy.dialInterface, `wiredDial`): set
    /// exactly when a network row says "Wired", nil for the rest, which are dialled as listed.
    let wired: NWInterface?

    init(name: String, endpoint: NWEndpoint?, route: Route, macID: String? = nil,
         method: DiscoveryPolicy.Method? = nil, wired: NWInterface? = nil) {
        self.name = name; self.endpoint = endpoint; self.route = route; self.macID = macID
        self.method = method; self.wired = wired
    }

    /// Reached over peer-to-peer Wi-Fi alone: the one kind of row connected with includePeerToPeer.
    var direct: Bool { route == .direct }
    /// A network "Mac mini" and a Remote "Mac mini" are two rows. Names are unique per route
    /// (DiscoveryPolicy.rows lists a name once), Mac IDs among Remote rows.
    var id: String { route == .remote ? "remote:\(macID ?? name)" : "\(route.rawValue):\(name)" }
    /// The word at the end of its row: "Remote" for a saved Mac dialed away from home, else how
    /// its Mac is reachable (`method`), or nil.
    var word: String? { route == .remote ? "Remote" : method?.word }
}

/// How the current connection runs (`Session.route`): set when it starts, again at `.ready` and by
/// a move to the network. A remote one's way in becomes `remoteRoute` (the Settings panel's route
/// line) and the saved Mac's `lastRoute` at its first window list; the rest reads `isRemote`.
enum SessionRoute: Equatable {
    case network
    /// Over peer-to-peer Wi-Fi (Direct Wireless).
    case direct
    /// Through the remote door.
    case remote(RemoteRoute)

    var isRemote: Bool { if case .remote = self { return true }; return false }
}

/// A remote session's way in, from the winning address and the path it took.
enum RemoteRoute: Equatable {
    /// The path went through a tunnel: the VPN's service name when the address carried one.
    case vpn(String?)
    /// An internet-kind address (a port forward).
    case internet
    /// Anything else: an address reached directly (the tests' 127.0.0.1, a LAN address).
    case address

    /// Through a VPN or over the internet this device asks for at most 60 fps (§7.6): half the data
    /// of a 120 fps stream, on the link that is usually the slow part. By address (a LAN address,
    /// the tests' loopback) runs as at home.
    var capsFrameRate: Bool { self != .address }

    /// "through Tailscale", "through your VPN", "over the internet", "by address".
    var phrase: String {
        switch self {
        case .vpn(let name?): return "through \(name)"
        case .vpn(nil): return "through your VPN"
        case .internet: return "over the internet"
        case .address: return "by address"
        }
    }

    /// What `SavedMac.lastRoute` keeps: "Tailscale", "your VPN", "the internet", "by address".
    var saved: String {
        switch self {
        case .vpn(let name?): return name
        case .vpn(nil): return "your VPN"
        case .internet: return "the internet"
        case .address: return "by address"
        }
    }
}

/// Finds Macs over Bonjour, connects, and splits the byte stream into messages.
/// Frame callbacks fire on the network queue; published state hops to main.
final class StreamClient: ObservableObject {
    // Connection. The setters of what the connect screen shows are internal: the DEBUG harness
    // seeds them.
    @Published var status = StreamClient.lookingOnNetwork {
        didSet {
            #if DEBUG
            if status != oldValue { print("status: \(status)") }    // the simulator tests read the status line here
            #endif
        }
    }
    /// The connect screen's rows (DiscoveryPolicy.rows): every Mac the network browser lists, then
    /// those seen only over peer-to-peer Wi-Fi.
    @Published var macs: [FoundMac] = []
    @Published var connected = false
    /// The nearby (peer-to-peer) browser runs: the status line says so, or under the hint the line
    /// in Search Nearby's place.
    @Published var searchingNearby = false
    /// No Mac listed after the network's first seconds: the connect screen says why, and offers
    /// Search Nearby while the nearby browser is not running.
    @Published var showsNearbyHint = false
    /// This connection runs over peer-to-peer Wi-Fi: the Settings panel warns that turning Direct
    /// Wireless off disconnects this device. It lasts only while the network does not list the
    /// Mac: once it has for 2 s the session moves there (`moveToNetworkIfListed`).
    @Published var connectedDirectly = false
    /// How the session's connection reaches the Mac, the word the Settings panel's readout ends in
    /// (DiscoveryPolicy.route): "Wired", "Wi-Fi" or "Direct", nil when its path does not say and
    /// while disconnected. It follows the connection that carries the session: read when it is
    /// ready, again when a move hands the session over, and on each path update of that
    /// connection that describes it (`followRoute`; the others keep the word). Only shown;
    /// `connectedDirectly` is what routing reads. Never set on a remote session: its route line
    /// says how instead (`remoteRoute`).
    @Published var route: DiscoveryPolicy.Method?
    /// A remote session's way in (the panel's route line, "Connected through Tailscale · 48 ms",
    /// the 60 fps request and the slow-link callout); nil at home and while disconnected. Set at
    /// its first window list, with `connected`.
    @Published var remoteRoute: RemoteRoute?

    // Remote access (StreamClient+Remote.swift). Published on main; the DEBUG harness seeds them.
    /// The Macs this device paired with (SavedMacs), persisted in `SavedMacs.defaultsKey`.
    @Published var savedMacs: [SavedMac] = []
    /// This connection's latest kind 18: who the Mac is and how to reach it from afar. Verified
    /// against the pin when the Mac is a saved one; otherwise decoded unverified, shown in the
    /// panel's Away from home group and never saved.
    @Published var macInfo: MacInfo?
    /// This connection's Mac is a saved one: its kind 18 verified against the saved pin.
    @Published var macInfoSaved = false
    /// This connection's latest kind 18 when its signature checked, with the key that signed it:
    /// what tells a pairing made over this session (the overlay) whether it paired this very Mac.
    var macInfoVerified: (info: MacInfo, fingerprint: Data)?
    /// When this connection's first kind 18 arrived (the panel hides Away from home without one).
    @Published var macInfoAt: Date?
    /// Pairing, as the Add a Mac card and the overlay show it.
    @Published var pairing = PairingPhase.idle
    /// A sill://pair link from outside the app (Camera, Messages, simctl openurl): never acted on
    /// until the person confirms it.
    @Published var pendingLink: PairLink?

    /// The connect screen's idle status lines: only these follow the nearby search and Local Network
    /// access (updateDiscovery); any other status (a disconnect, a failure) stays as it was set.
    static let lookingOnNetwork = "Looking for Macs on this network"
    static let lookingNearby = "Looking for Macs on this network and nearby"
    static let allowLocalNetwork = "To find your Mac, allow Local Network for Sill in Settings."

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
    /// When this connection became ready (a remote one: its first window list, since with TLS 1.3
    /// the device is ready before the Mac has judged its certificate); nil while disconnected. The
    /// panel gives the first state two seconds before it calls the Mac an older one.
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
    /// The harness's remote cases: one second's numbers, as the network queue would publish them,
    /// and whether five of them made a slow link.
    func showMockLinkStats(_ stats: LinkStats, slow: Bool = false) { linkStats = stats; slowLink = slow }
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

    /// The Settings panel's slow-link callout (docs/remote-access-plan.md §7.11): on a remote route,
    /// the median of the last five one-second round-trip medians is over 250 ms
    /// (`isSlowLink`). Main thread.
    @Published private(set) var slowLink = false
    /// The last five seconds' round-trip medians that had a pong, oldest first. Main thread.
    private var recentRttMedians: [Int] = []

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
    // Both read the TXT record, whose `r` tag names a saved Mac whatever its Bonjour name.
    static let serviceType = "_sill._tcp"
    private var networkBrowser: NWBrowser?
    private var nearbyBrowser: NWBrowser?
    private var networkResults: [NWBrowser.Result] = []
    private var nearbyResults: [NWBrowser.Result] = []
    /// Launch, the last connection ending, or Local Network access coming back: the network gets its
    /// first seconds from here.
    var searchingSince = ProcessInfo.processInfo.systemUptime
    /// Search Nearby tapped since the last connection.
    var askedNearby = false
    /// The network browser waits with PolicyDenied: Local Network access is off for Sill.
    var localNetworkDenied = false
    /// The policy's next look (its 3 s mark).
    private var discoveryRecheck: DispatchWorkItem?
    /// When each Direct row was first seen as one (DiscoveryPolicy.directSince): an automatic
    /// reconnect takes a Direct row only once it has stayed Direct for `directWait`.
    var directSince: [String: Double] = [:]
    /// What the network browser has shown of each Mac, by Bonjour name (DiscoveryPolicy.sightings):
    /// an automatic reconnect does not take a Mac's Direct row within `networkGrace` of the network
    /// last listing it, and a session over AWDL moves to the network once it has listed the Mac for
    /// `moveAfter`.
    var sightings = DiscoveryPolicy.NetworkSightings()
    /// A session over AWDL moving to the network: the network connection opened beside it, until it
    /// has shown it reaches this session's host and takes over (`finishMove`), or gives up
    /// (`moveEnded`).
    private var moving: NWConnection?
    /// When this session's last move started, so one that did not complete waits `moveRetry`.
    private var lastMoveAttempt: Double?
    /// The move's look at the moment the network row has been listed for `moveAfter`.
    private var moveCheck: DispatchWorkItem?
    /// This connection has delivered a window list, and the host's launch ID it carried
    /// (`WindowList.launchID`; nil from an older host): a move hands the session only to a
    /// connection whose first list names the same host (`moveProbed`), so none starts before.
    private var sessionListed = false
    private var sessionHost: String?
    /// The network listing (its `sightings.since`) a move found to be another Mac: not tried again
    /// while it lasts (DiscoveryPolicy.moveToNetwork).
    private var refusedListing: Double?
    /// How long a move's hand-over waits for the Mac to have read everything sent on the direct
    /// connection before what waits goes out anyway (SessionLink): past the worst direct round trip
    /// of Noah's sessions on 2026-09-24 (2.4 s), and no longer, since input waits meanwhile.
    private static let fenceTimeout = 3.0
    #if DEBUG
    /// `-SillMoveTest` with `-SillConnect host:port`: rows the network browser did not list, so the
    /// move to the network runs against synthetic hosts, which no browser lists and which are not
    /// on AWDL (see `beginMoveTest`).
    private var testNetworkRows: [(name: String, endpoint: NWEndpoint)] = []
    #endif
    /// Macs this device last saw with Direct Wireless on, most recent first (DiscoveryPolicy.remember),
    /// keyed by the Bonjour name the connection was made to, the name both browsers list the Mac
    /// under. A discovery hint only: the panel never reads it, so a Mac's settings are still only ever
    /// the ones it sent on this connection. A launch argument seeds it for one run:
    /// -Sill.directWirelessMacs '("Mac mini")', or '()' to clear it.
    var directWirelessMacs = UserDefaults.standard.stringArray(forKey: StreamClient.directWirelessMacsKey) ?? []
    private static let directWirelessMacsKey = "Sill.directWirelessMacs"
    /// What the network browser has shown of each saved Mac, by Mac ID (DiscoveryPolicy.sightings,
    /// the rule `sightings` follows by Bonjour name; the ID outlasts a rename to "Mac mini (2)"): a
    /// lost saved Mac gets no remote dial within `networkGrace` of the moment its network row went,
    /// since a Mac the network listed moments ago is taken to be blinking, not gone
    /// (DiscoveryPolicy.remoteDialDue).
    var savedSightings = DiscoveryPolicy.NetworkSightings()
    #if DEBUG
    /// Harness connect cases: the discovery state is seeded, no browser ever runs, and Search Nearby
    /// or a row's tap only change what is shown.
    var mockDiscovery = false
    #endif

    // Sessions and reconnecting (main thread; StreamClient+Remote.swift).
    /// Why a remote dial was made: its failure copy and its retries depend on it.
    enum DialReason: Equatable { case tap, automatic, connectRemotely, afterPairing, launchArgument }

    /// The current connection's facts: set when it starts, cleared when it ends.
    struct Session {
        var route: SessionRoute
        /// The saved Mac it is with: its row's, its dial's, or learned from a verified kind 18.
        var macID: String?
        /// The Bonjour name it was made to (network and Direct rows).
        var bonjourName: String?
        /// Remote: the address that won, and why it was dialed.
        var candidate: RemoteDialPolicy.Candidate?
        var why: DialReason?
    }
    var session: Session?

    /// An automatic reconnect after a session ended on its own (docs/remote-access-plan.md §7.4).
    struct Reconnect {
        /// A saved Mac: its network row, its Direct row, then its saved addresses. Nil: today's
        /// rules, by exact Bonjour name.
        var macID: String?
        var bonjourName: String?
        /// What the status line calls the Mac.
        var name: String
        /// systemUptime of the loss, and this device's path then.
        var lostAt: Double
        var pathAtLoss: String
        /// False after goodbye `remoteOff` or `internetOff`: the rows only.
        var remoteAllowed: Bool
        var rememberedDirect: Bool
        var remoteFailures = 0
        var nextRemoteAt = 0.0
    }
    var reconnect: Reconnect?
    /// The dial in flight, remote or pairing: one at a time each.
    var remoteDial: RemoteConnector?
    var pairingDial: RemoteConnector?
    /// The next look at the reconnect (a Direct row's `directWait` and `networkGrace`, a remote
    /// dial's due time, the end of `redialWindow`).
    var reconnectCheck: DispatchWorkItem?
    /// A remote session's first window list must come within 10 s of `.ready`.
    var firstListDeadline: DispatchWorkItem?
    /// A kind 22 on the current connection: why the Mac is about to close it, and what to do then
    /// (GoodbyePolicy). One that does not decode reads as reason "", a reason this build does not know.
    var goodbye: Goodbye?
    /// The Mac's own words from the goodbye that ended the last session, when it was a notice
    /// ("update", or a reason this build does not know): the connect screen's status line
    /// (GoodbyePolicy), and for "update" the App Store link under it, shown while the status line
    /// still says it: the next status (a tap, a dial, Forget) takes the link away. Cleared by the
    /// next session's tear-down.
    struct Notice: Equatable {
        let text: String
        var storeLink = false
    }
    @Published var notice: Notice?
    /// The Mac's version and protocol from this session's window lists (`WindowList.hostVersion`,
    /// `protocol`): nil from SillHost and from Macs before 2026-09-25. Shown nowhere yet; kept so a
    /// later device can tell a Mac from the first public build from what it needs (§14). Cleared
    /// with the session.
    @Published var hostVersion: String?
    @Published var hostProtocol: Int?
    /// This device's path (status, interfaces, cost), for "did it leave home since the loss".
    var pathSignature = ""
    var pathMonitor: NWPathMonitor?
    /// After a pairing: no session within 10 s leaves the Mac as a saved row.
    var afterPairingWatch: DispatchWorkItem?
    /// The secret of the code the scanner last started a pairing with: after that pairing failed,
    /// the scanner's own re-readings of the same code are ignored (StreamClient.scanned).
    var lastScannedSecret: Data?
    /// Counts pairings started and cancelled: the silent retry after a "busy" answer runs only if
    /// no other pairing started, and nobody cancelled, while it waited.
    var pairingAttempt = 0

    /// The session's connection, kept by `link`: read on `queue` (receive loop, sends) and written
    /// on main (connect, disconnect, loss, a move's hand-over), so it is locked there.
    var connection: NWConnection? {
        get { link.connection }
        set { link.connection = newValue }
    }
    /// Where every message to the Mac goes, in the order sent, also across a move's hand-over from
    /// the direct connection to the network one (SessionLink).
    private let link = SessionLink()
    let queue = DispatchQueue(label: "sill.net", qos: .userInteractive)
    private var lastParameterSets: ParameterSets?

    // Liveness, on `queue` (docs/remote-access-plan.md §7.6). The host answers every ping, so a
    // live connection never goes quiet for long; a dead path used to keep a frozen picture.
    /// The last completed receive with data (CACurrentMediaTime).
    private var lastReceivedAt = 0.0
    /// The worst round trip of the last second that measured one, ms.
    private var worstRecentRttMs: Double?
    /// A remote connection's path stopped being viable at this time; nil while viable.
    private var unviableSince: Double?
    /// The current connection is a remote one (the viability rule applies).
    private var remoteOnQueue = false
    /// No byte for this long (or four times the worst recent round trip) is a lost connection.
    static let livenessFloor = 6.0
    /// A remote path that is not viable for this long is a lost connection.
    static let viabilityLimit = 3.0

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

    /// DEBUG: saved Macs seeded for this run by `-Sill.savedMacs '<JSON>'`; nothing is written back.
    private(set) var savedMacsSeeded = false

    init() {
        // The hello is built here, on the main thread: it reads UIDevice (the device's name), which
        // the network queue, where connections become ready and send it, must not be first to touch.
        _ = Self.helloPayload
        #if DEBUG
        // Read from the command line itself: the argument domain drops a value that starts like a
        // property list but is not one, and JSON's "[" is such a start.
        let arguments = CommandLine.arguments
        if let i = arguments.firstIndex(of: "-" + SavedMacs.defaultsKey), i + 1 < arguments.count {
            savedMacs = SavedMacs.decode(arguments[i + 1])
            savedMacsSeeded = true
        } else {
            savedMacs = SavedMacs.decode(UserDefaults.standard.string(forKey: SavedMacs.defaultsKey))
        }
        #else
        savedMacs = SavedMacs.decode(UserDefaults.standard.string(forKey: SavedMacs.defaultsKey))
        #endif
        // Back from the background: the pings stopped while the app was suspended, which is no loss.
        NotificationCenter.default.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            self?.resetLiveness()
        }
    }

    /// Starts the network browser (once). The nearby one follows the policy (`updateDiscovery`).
    func startBrowsing() {
        guard networkBrowser == nil else { return }
        searchingSince = ProcessInfo.processInfo.systemUptime
        startPathMonitor()
        // Network only: includePeerToPeer stays at its default, false. A peer-to-peer browse makes
        // the kernel bring AWDL up, which takes the radio off its Wi-Fi channel up to ~100 ms twice
        // a second (CLAUDE.md, trackpad stutter), and on a shared network AWDL carries nothing of
        // Sill's. Direct Wireless Connection is the Mac's opt-in for that route (the nearby browser).
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: Self.serviceType, domain: nil), using: NWParameters())
        browser.browseResultsChangedHandler = { [weak self, weak browser] results, _ in
            DispatchQueue.main.async {
                guard let self, let browser, self.networkBrowser === browser else { return }
                self.networkResults = Array(results)
                self.discoveryChanged()
            }
        }
        browser.stateUpdateHandler = { [weak self, weak browser] state in
            DispatchQueue.main.async {
                guard let self, let browser, self.networkBrowser === browser else { return }
                self.networkBrowserChanged(state)
            }
        }
        browser.start(queue: queue)
        networkBrowser = browser
        discoveryChanged()
    }

    /// The network browser's state. Local Network access denied shows as waiting with PolicyDenied
    /// (TN3179), at launch or after Don't Allow, and every Bonjour browse is refused then, the nearby
    /// one too: the status says what to do instead of the hint, whose advice about the network would
    /// be wrong. The browser becomes ready once Settings allows it. Main thread.
    private func networkBrowserChanged(_ state: NWBrowser.State) {
        switch state {
        case .failed(let e):
            status = "Browse failed: \(e)"
        case .waiting(let e):
            guard case .dns(let code) = e, code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied), !localNetworkDenied else { return }
            localNetworkDenied = true
            updateDiscovery()
        case .ready:
            guard localNetworkDenied else { return }
            localNetworkDenied = false
            searchingSince = ProcessInfo.processInfo.systemUptime   // no hint before the network answers
            updateDiscovery()
        default:
            break
        }
    }

    /// Peer-to-peer, for a Mac whose Direct Wireless Connection is on and that shares no network
    /// with this device. Started and stopped by `updateDiscovery` only.
    private func startNearbyBrowser() {
        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: Self.serviceType, domain: nil), using: params)
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

    /// A browser's results changed, or what the policy reads did (the saved Macs, the network's
    /// 3 s mark). Main thread.
    func discoveryChanged() {
        recomputeMacs()
        updateDiscovery()
        reconnectIfListed()
        moveToNetworkIfListed()
    }

    /// The rows, each with the endpoint of the browser that listed it: a network row always the
    /// network browser's, so at home a Mac is never reached over AWDL. Each row's word comes from
    /// the interfaces that same browser saw its Mac on (DiscoveryPolicy.method), and so does the
    /// wired interface a "Wired" row is dialled on (DiscoveryPolicy.dialInterface): a browser reports
    /// one result per Mac with every interface it is seen on, and reports it again when one comes
    /// or goes, so plugging the cable in or out changes both. A row whose TXT tag this device
    /// resolves is that saved Mac, whatever its Bonjour name; a result without a tag is no saved Mac
    /// (an older host, or briefly during a re-registration: the reconnect still finds it by the
    /// Bonjour name last used with it). Then a Remote row for each saved Mac neither browser lists,
    /// once the network has had its 3 s. Main thread.
    func recomputeMacs() {
        #if DEBUG
        if mockDiscovery { return }
        #endif
        var network = networkResults.map { (name: Self.serviceName(of: $0), endpoint: $0.endpoint, interfaces: $0.interfaces,
                                            tag: Self.tag(of: $0)) }
        #if DEBUG
        network += testNetworkRows.map { (name: $0.name, endpoint: $0.endpoint, interfaces: [NWInterface](), tag: String?.none) }
        #endif
        let nearby = nearbyResults.map { (name: Self.serviceName(of: $0), endpoint: $0.endpoint, interfaces: $0.interfaces,
                                          tag: Self.tag(of: $0)) }
        let rows = DiscoveryPolicy.rows(network: network.map(\.name), nearby: nearby.map { ($0.name, $0.interfaces.map(\.name)) })
        let now = ProcessInfo.processInfo.systemUptime
        directSince = DiscoveryPolicy.directSince(directSince, rows: rows, now: now)
        sightings = DiscoveryPolicy.sightings(sightings, listed: Set(network.map(\.name)), now: now)
        var next = rows.compactMap { row -> FoundMac? in
            guard let seen = (row.direct ? nearby : network).first(where: { $0.name == row.name }) else { return nil }
            let interfaces = seen.interfaces.map(Self.policyInterface)
            let wired = DiscoveryPolicy.dialInterface(direct: row.direct, interfaces: interfaces)
            return FoundMac(name: row.name, endpoint: seen.endpoint, route: row.direct ? .direct : .network,
                            macID: SavedMacs.recognize(tag: seen.tag, in: savedMacs),
                            method: DiscoveryPolicy.method(direct: row.direct, interfaces: interfaces),
                            wired: wired.flatMap { name in seen.interfaces.first { $0.name == name } })
        }
        // The moment a saved Mac's network row goes is what holds back its remote dial; the last
        // look while it was listed can be the connect, hours before the loss.
        let networkIDs = Set(next.filter { $0.route == .network }.compactMap(\.macID))
        savedSightings = DiscoveryPolicy.sightings(savedSightings, listed: networkIDs, now: now)
        let names = SavedMacs.displayNames(savedMacs)
        let saved = savedMacs.sorted { $0.pairedAt < $1.pairedAt }.map { (macID: $0.macID, name: names[$0.macID] ?? $0.name) }
        let remote = DiscoveryPolicy.remoteRows(saved: saved, listedIDs: Set(next.compactMap(\.macID)), now: now,
                                                searchingSince: searchingSince, localNetworkDenied: localNetworkDenied)
        next += remote.map { FoundMac(name: $0.name, endpoint: nil, route: .remote, macID: $0.macID) }
        guard next != macs else { return }
        #if DEBUG
        // What each row's word was read from, to check it on a device (the cable in and out).
        for mac in next where mac.route != .remote {
            let seen = (mac.direct ? nearby : network).first { $0.name == mac.name }?.interfaces ?? []
            print("discovery: \(mac.name): \(mac.method?.word ?? "no word"), seen on \(seen.map { "\($0.name) (\($0.type))" }.joined(separator: ", "))")
        }
        #endif
        macs = next
    }

    /// A result's recognition tag (TXT `r`), if it carries one.
    static func tag(of result: NWBrowser.Result) -> String? {
        if case .bonjour(let txt) = result.metadata { return txt[RecognitionTag.txtKey] }
        return nil
    }

    /// An interface as DiscoveryPolicy spells it, case for case.
    private static func policyInterface(_ interface: NWInterface) -> DiscoveryPolicy.Interface {
        let type: DiscoveryPolicy.Interface.Kind
        switch interface.type {
        case .wifi: type = .wifi
        case .wiredEthernet: type = .wiredEthernet
        case .cellular: type = .cellular
        case .loopback: type = .loopback
        case .other: type = .other
        @unknown default: type = .other   // a type newer than this code: no word rather than a wrong one
        }
        return DiscoveryPolicy.Interface(name: interface.name, type: type)
    }

    /// Runs the policy on what is known now: starts or stops the nearby browser, shows the hint,
    /// keeps an idle status line in step, and looks again at the network's 3 s mark. Main thread.
    func updateDiscovery() {
        #if DEBUG
        if mockDiscovery { return }
        #endif
        let now = ProcessInfo.processInfo.systemUptime
        let out = DiscoveryPolicy.decide(DiscoveryPolicy.Input(
            now: now, connected: connected, onNetwork: Set(networkResults.map(Self.serviceName(of:))),
            remembered: Set(directWirelessMacs), searchingSince: searchingSince, askedNearby: askedNearby,
            nearbyRunning: nearbyBrowser != nil, listed: macs.count, localNetworkDenied: localNetworkDenied))
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
        // "…and nearby" while the nearby search runs, but not under the hint: the line in Search
        // Nearby's place says it there (ConnectScreen), and the status would only repeat it.
        if [Self.lookingOnNetwork, Self.lookingNearby, Self.allowLocalNetwork].contains(status) {
            let idle = localNetworkDenied ? Self.allowLocalNetwork
                : (out.browseNearby && !out.showHint ? Self.lookingNearby : Self.lookingOnNetwork)
            if status != idle { status = idle }
        }
        discoveryRecheck?.cancel()
        discoveryRecheck = nil
        if let at = out.recheckAt {
            // The whole look, not only the policy: the Remote rows appear at the same mark.
            let work = DispatchWorkItem { [weak self] in self?.discoveryChanged() }
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
            // The button shows only under the hint, where updateDiscovery leaves the status alone.
            searchingNearby = true
            return
        }
        #endif
        updateDiscovery()
    }

    /// What the status line calls the Mac we are connected to (or were, if it dropped): its Bonjour
    /// name, its saved name, or the address dialed.
    var hostName = "Mac"

    static func serviceName(of result: NWBrowser.Result) -> String {
        if case .service(let name, _, _, _) = result.endpoint { return name }
        return "\(result.endpoint)"
    }

    /// A row of the connect screen. Only a Direct row is connected with peer-to-peer allowed; a row
    /// that says "Wired" is dialled over its wired interface first (`wiredDial`); a Remote row dials
    /// the saved Mac's addresses through the remote door.
    func connect(to mac: FoundMac) {
        #if DEBUG
        if mockDiscovery {
            switch mac.route {
            case .direct: status = "Connecting to \(mac.name) directly…"
            case .remote: status = "Connecting to \(mac.name) remotely…"
            case .network: status = "Connecting to \(mac.name)…"
            }
            return
        }
        #endif
        reconnect = nil      // a tap starts afresh
        if mac.route == .remote, let id = mac.macID {
            dialSaved(id, why: .tap)
            return
        }
        dial(mac, macID: mac.macID)
    }

    /// A network or Direct row's dial, a tap's or the automatic reconnect's (which keeps its
    /// `reconnect` until the connection is ready): over the row's wired interface first when it
    /// says "Wired" (`wiredDial`), else as listed. `macID`: the saved Mac it is. Main thread.
    func dial(_ mac: FoundMac, macID: String?) {
        guard let endpoint = mac.endpoint else { return }
        if let wired = wiredDial(for: mac) {
            #if DEBUG
            print("dialing \(mac.name) on \(wired.via)")
            #endif
            connect(to: wired.endpoint, name: mac.name, macID: macID, fallback: endpoint)
        } else {
            connect(to: endpoint, name: mac.name, peerToPeer: mac.direct, macID: macID)
        }
    }

    /// Where a row whose Mac the network browser saw on a wired interface (`FoundMac.wired`, the
    /// row says "Wired") is dialled first: its Bonjour service resolved on that interface alone, so
    /// the connection runs over the cable (with Wi-Fi up too, an unconstrained dial took either,
    /// 2026-09-25), and how the DEBUG console names it. Nil for any other row, dialled as listed.
    /// Main thread.
    private func wiredDial(for mac: FoundMac) -> (endpoint: NWEndpoint, via: String)? {
        guard mac.route == .network else { return nil }
        #if DEBUG
        if let test = Self.wiredTest { return (test, "\(test) (wired test)") }
        #endif
        guard let wired = mac.wired, case .service(let name, let type, let domain, _)? = mac.endpoint else { return nil }
        return (.service(name: name, type: type, domain: domain, interface: wired), "\(wired.name) (wired)")
    }

    /// Connects to a Bonjour result's endpoint through the home door, or straight to an address
    /// (DEBUG `-SillConnect`). `name` is what the status line calls the Mac until its window list
    /// brings its own name. `peerToPeer` only for a Mac seen over peer-to-peer Wi-Fi alone. `macID`:
    /// the saved Mac the row is, when its tag said so. With a `fallback` this is a wired dial
    /// (`wiredDial`): not ready within DiscoveryPolicy.wiredWait, or unable to go on, it gives way
    /// to `fallback`, the row as listed, dialled unconstrained (`dialUnconstrained`).
    func connect(to endpoint: NWEndpoint, name: String, peerToPeer: Bool = false, macID: String? = nil, fallback: NWEndpoint? = nil) {
        // One connection at a time. A tap on the connect screen racing the reconnect timer used to
        // open two: both then read from whichever `connection` pointed at, interleaving headers
        // and payloads, while the other was never read and the host evicted it after 4 s.
        if let old = connection {
            connection = nil
            old.cancel()      // its .cancelled callback is ignored: connectionLost checks identity
        }
        cancelRemoteDial()
        abandonMove()         // a new session: an old one's move to the network is moot
        sessionListed = false // …and its host is not yet known
        sessionHost = nil
        refusedListing = nil
        hostName = name
        var bonjourName: String?
        if case .service(let service, _, _, _) = endpoint { bonjourName = service }
        session = Session(route: peerToPeer ? .direct : .network, macID: macID, bonjourName: bonjourName)
        goodbye = nil
        status = peerToPeer ? "Connecting to \(name) directly…" : "Connecting to \(name)…"
        let c = NWConnection(to: endpoint, using: Self.connectionParameters(peerToPeer: peerToPeer))
        c.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.sendHello(on: c)   // first, before the pings (startMeasuring) and anything the session sends
                let direct = peerToPeer && Self.runsPeerToPeer(c.currentPath)
                let path = c.currentPath
                DispatchQueue.main.async {
                    guard self.connection === c else { c.cancel(); return }   // replaced while connecting
                    self.reconnect = nil
                    self.connected = true
                    self.connectedDirectly = direct
                    self.session?.route = direct ? .direct : .network
                    self.setRoute(from: path, fresh: true)
                    self.askedNearby = false
                    self.connectedAt = Date()
                    self.status = "Connected to \(name)"
                    self.updateDiscovery()   // stops the nearby browser; the network one keeps running
                    #if DEBUG
                    if let test = UserDefaults.standard.string(forKey: "SillMoveTest") {
                        self.beginMoveTest(endpoint: endpoint, name: name, mode: test)
                    }
                    #endif
                    self.moveToNetworkIfListed()   // over AWDL: the network may list this Mac already
                }
                self.startMeasuring(c, remote: false)   // before the first read, so the first window is this connection's alone
                self.readHeader(on: c)
            case .waiting(let e):
                print("connection waiting: \(e)")
                if let fallback {   // a wired dial that cannot go on (the cable just pulled, say)
                    DispatchQueue.main.async { self.dialUnconstrained(after: c, fallback, name: name, macID: macID, why: "is waiting (\(e))") }
                    return
                }
                DispatchQueue.main.async { self.status = "Waiting for \(name)…" }
                // A connection that never gets past waiting would block every reconnect path
                // (they all require `connection == nil`): give it five seconds, then let it go.
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                    guard let self, self.connection === c, !self.connected else { return }
                    c.cancel()
                }
            case .failed(let e):
                print("connection failed: \(e)")
                if let fallback {
                    // Queued before the cancel's .cancelled, whose connectionLost then finds `c`
                    // replaced by the unconstrained dial.
                    DispatchQueue.main.async { self.dialUnconstrained(after: c, fallback, name: name, macID: macID, why: "failed (\(e))") }
                } else {
                    self.connectionLost(c, error: e)
                }
                c.cancel()   // Network.framework releases a failed connection only once cancelled
            case .cancelled:
                // Either disconnect() cancelled it (state already cleaned up) or the host closed it.
                self.connectionLost(c)
            default:
                break
            }
        }
        followRoute(of: c)
        connection = c        // before start: .ready can be delivered before the next line runs
        c.start(queue: queue)
        if let fallback {
            DispatchQueue.main.asyncAfter(deadline: .now() + DiscoveryPolicy.wiredWait) { [weak self] in
                self?.dialUnconstrained(after: c, fallback, name: name, macID: macID, why: "did not connect in \(DiscoveryPolicy.wiredWait) s")
            }
        }
    }

    /// A wired dial, `c`, that has not connected: cancelled, and `fallback`, the row as listed,
    /// dialled unconstrained, as it was before the wired preference, once (it has no fallback of
    /// its own), under the status line the dial showed ("Reconnecting…" stays). Only while `c` is
    /// still the connection and not ready: a tap may have replaced it meanwhile, or it connected at
    /// the last moment. Main thread.
    private func dialUnconstrained(after c: NWConnection, _ fallback: NWEndpoint, name: String, macID: String?, why: String) {
        guard connection === c, !connected, c.state != .ready else { return }
        #if DEBUG
        print("wired dial \(why); dialing unconstrained")
        #endif
        let shown = status
        connect(to: fallback, name: name, macID: macID)   // cancels `c`, whose .cancelled finds it replaced
        status = shown
    }

    /// This device's hello (kind 23): its version, build, protocol and name, built once. DEBUG:
    /// `-SillHelloVersion <v>` replaces the version, for a host's device floor under test.
    private static let helloPayload: Data = {
        var version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        #if DEBUG
        if let v = UserDefaults.standard.string(forKey: "SillHelloVersion"), !v.isEmpty { version = v }
        #endif
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return Wire.encode(Hello(appVersion: version, build: build, protocol: SillProtocol.current, device: ClientStatsReporter.deviceName))
    }()

    /// The hello, the first thing on every session connection (a tap's, a reconnect's, a wired dial
    /// and its fallback, a move's network connection, a remote dial's winner), written straight to
    /// `c` before anything else goes out on it: a Mac with a device floor judges the device by its
    /// first message. Never on a pairing connection, whose one message is kind 19. Older Macs skip
    /// it. Any thread.
    private func sendHello(on c: NWConnection) {
        let message = StreamMessage(kind: .hello, timestamp: Date().timeIntervalSince1970, isKeyframe: false, payload: Self.helloPayload)
        c.send(content: message.serialized(), completion: .contentProcessed { _ in })
        #if DEBUG
        if let hello = Wire.decode(Hello.self, from: Self.helloPayload) {
            print("hello: sent Sill \(hello.appVersion ?? "?") (\(hello.build ?? "?")), protocol \(hello.protocol ?? 0)")
        }
        #endif
    }

    /// Every connection to a Mac: TCP without Nagle, the interactive video class, and peer-to-peer
    /// (AWDL) only for a "Direct" row. A Mac the network lists is reached over the network (see
    /// startBrowsing), so at home a connection never takes AWDL.
    private static func connectionParameters(peerToPeer: Bool) -> NWParameters {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        let params = NWParameters(tls: nil, tcp: tcp)
        params.includePeerToPeer = peerToPeer
        // Wi-Fi QoS: video + pointer traffic is latency-sensitive; the access point and the radio
        // treat this class (WMM video) with shorter queues than best-effort.
        params.serviceClass = .interactiveVideo
        return params
    }

    // MARK: Moving a session over AWDL to the network

    /// This session runs over peer-to-peer Wi-Fi and the network lists the same Mac by its Bonjour
    /// name: once it has for `moveAfter` without a break, move the session there
    /// (DiscoveryPolicy.moveToNetwork). The device is then on the Mac's network, where AWDL only
    /// costs; a reconnect can land on AWDL at home when the network browser stays silent for a
    /// while (2026-09-24, twice). Not before this connection's first window list, which names the
    /// host the move must reach again (`moveProbed`). Main thread.
    private func moveToNetworkIfListed() {
        moveCheck?.cancel()
        moveCheck = nil
        guard connected, connectedDirectly, sessionListed, moving == nil, connection != nil,
              let mac = macs.first(where: { $0.name == hostName && $0.route == .network }) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let decision = DiscoveryPolicy.moveToNetwork(listedSince: sightings.since[mac.name], lastAttempt: lastMoveAttempt,
                                                     refusedListing: refusedListing, now: now)
        if decision.move {
            move(to: mac)
        } else if let at = decision.recheckAt {
            let work = DispatchWorkItem { [weak self] in self?.moveToNetworkIfListed() }
            moveCheck = work
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0.01, at - now), execute: work)
        }
    }

    /// Opens a network connection to `mac` beside the direct one, and hands the session over once
    /// its first window list shows it reaches the same host (`moveProbed`, `finishMove`): make
    /// before break. The Mac keeps a connected device throughout, so it never stops the stream,
    /// which it does at zero devices (a staged window would go home), and the new connection is
    /// sent the running stream: no connect screen, no Desktop restart. A network connection that
    /// fails, has not shown its host within 5 s, or reaches another Mac changes nothing: the
    /// session stays direct and the next try waits `moveRetry` (after another Mac, a new listing
    /// too). A row that says "Wired" is dialled over its wired interface first (`wiredDial`), as a
    /// tap on it is; the wired connection, not ready within DiscoveryPolicy.wiredWait (2.5 s), or
    /// failing or waiting (at once), does not end the move but gives way to the row as listed,
    /// dialled unconstrained with 5 s of its own (`moveUnconstrained`), so a move whose wired dial
    /// did not connect can take up to 7.5 s in all. Main thread.
    private func move(to mac: FoundMac) {
        guard let endpoint = mac.endpoint else { return }
        lastMoveAttempt = ProcessInfo.processInfo.systemUptime
        status = "Switching to Wi\u{2011}Fi…"
        if let wired = wiredDial(for: mac) {
            #if DEBUG
            print("discovery: moving the session to the network on \(wired.via)")
            #endif
            startMove(to: wired.endpoint, fallback: endpoint)
        } else {
            #if DEBUG
            print("discovery: moving the session to the network")
            #endif
            startMove(to: endpoint, fallback: nil)
        }
    }

    /// The move's network connection, to `endpoint`, with its own 5 s. With a `fallback` it is a
    /// wired dial, which gives way to `fallback` dialled unconstrained when not ready within
    /// DiscoveryPolicy.wiredWait, or unable to go on (`moveUnconstrained`). Main thread.
    private func startMove(to endpoint: NWEndpoint, fallback: NWEndpoint?) {
        let c = NWConnection(to: endpoint, using: Self.connectionParameters(peerToPeer: false))
        moving = c
        // One handler for both lives of `c`: until it takes over, `moveEnded` acts (it checks
        // `moving`); after, `connectionLost` does (it checks `connection`).
        c.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                // Its own hello first: nothing else goes out on it before the hand-over, and the
                // fence (SessionLink) holds only what the session sends.
                self.sendHello(on: c)
                self.probeMove(c)
            case .waiting(let e):
                guard let fallback else { break }
                DispatchQueue.main.async { self.moveUnconstrained(after: c, fallback, why: "is waiting (\(e))") }
            case .failed(let e):
                print("move to the network failed: \(e)")
                if let fallback {   // queued first: the moveEnded below then finds the move gone on
                    DispatchQueue.main.async { self.moveUnconstrained(after: c, fallback, why: "failed (\(e))") }
                }
                c.cancel()
                self.connectionLost(c, error: e)
                DispatchQueue.main.async { self.moveEnded(c) }
            case .cancelled:
                self.connectionLost(c)
                DispatchQueue.main.async { self.moveEnded(c) }
            default:
                break
            }
        }
        followRoute(of: c)   // from the hand-over on
        c.start(queue: queue)
        if let fallback {
            DispatchQueue.main.asyncAfter(deadline: .now() + DiscoveryPolicy.wiredWait) { [weak self] in
                self?.moveUnconstrained(after: c, fallback, why: "did not connect in \(DiscoveryPolicy.wiredWait) s")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.moving === c else { return }
            // Not taken over in 5 s: stay direct. The move ends before `c` is cancelled: a `.ready`
            // can still be delivered after the cancel, and a list read meanwhile must find the move
            // over (`moveProbed` checks `moving`) rather than hand the session to a dead connection.
            self.moveEnded(c)
            c.cancel()
        }
    }

    /// The move's wired dial, `c`, has not connected: the move goes on over the network row as
    /// listed, dialled unconstrained, once, with 5 s of its own, and `c` is cancelled. Only while
    /// `c` is still the move's and not ready. Main thread.
    private func moveUnconstrained(after c: NWConnection, _ fallback: NWEndpoint, why: String) {
        guard moving === c, c.state != .ready else { return }
        #if DEBUG
        print("discovery: the wired move \(why); moving unconstrained")
        #endif
        startMove(to: fallback, fallback: nil)   // `moving` from here: `c`'s moveEnded does nothing
        c.cancel()
    }

    /// On `queue`, once the network connection is ready: reads it up to its first window list,
    /// keeping every message for the session's read loop to replay should it take over, and hands
    /// the list's host to `moveProbed`. Ticks, frames or a broadcast can come before the list: the
    /// Mac adds a connection to its broadcasts before its catalog goes out. A read that fails, a
    /// message cut short, or one bigger than the session's reader takes (`readHeader`), cancels
    /// `c`, which ends the move (`moveEnded`).
    private func probeMove(_ c: NWConnection, kept: [(header: StreamHeader, payload: Data)] = []) {
        c.receive(minimumIncompleteLength: StreamMessage.headerLength, maximumLength: StreamMessage.headerLength) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            guard let data, let header = StreamMessage.parseHeader(data) else {
                if isComplete || error != nil { c.cancel() }
                return
            }
            // The session reader's caps (docs/remote-access-plan.md §3.7): nothing a Sill host sends
            // is bigger, and waiting for what such a header announces would hold whatever follows
            // until the move's 5 s run out.
            let cap = header.kind == .frame ? StreamMessage.maxFramePayload : StreamMessage.maxOtherHostPayload
            guard header.payloadLength <= cap else {
                print("move to the network: closing, the host announced a \(header.payloadLength)-byte message (kind \(header.kind.rawValue))")
                c.cancel()
                return
            }
            let next = { (payload: Data) in
                let kept = kept + [(header, payload)]
                guard header.kind == .windowList else { self.probeMove(c, kept: kept); return }
                guard let list = Wire.decode(WindowList.self, from: payload) else { c.cancel(); return }
                DispatchQueue.main.async { self.moveProbed(c, kept: kept, host: list.launchID) }
            }
            if header.payloadLength == 0 { next(Data()); return }
            c.receive(minimumIncompleteLength: header.payloadLength, maximumLength: header.payloadLength) { data, _, isComplete, error in
                // As in readPayload: fewer bytes than announced is the connection ending mid-message,
                // never a message to keep.
                guard let data, data.count == header.payloadLength else {
                    if isComplete || error != nil || data != nil { c.cancel() }
                    return
                }
                next(data)
            }
        }
    }

    /// The network connection's first window list is in: the session goes over if the list comes
    /// from the host this session runs on (DiscoveryPolicy.sameHost). Main thread.
    private func moveProbed(_ c: NWConnection, kept: [(header: StreamHeader, payload: Data)], host: String?) {
        guard moving === c else { c.cancel(); return }   // given up meanwhile (its 5 s, a new session)
        // Failed since its list came: its handler's `moveEnded` follows, so `moving` is left for it.
        guard c.state == .ready else { c.cancel(); return }
        guard DiscoveryPolicy.sameHost(sessionHost, host) else {
            // Another Mac of this name, on the network while this one is reached over AWDL: the two
            // share no link, so mDNS renamed neither. Not tried again while that listing lasts.
            print("move to the network refused: \(hostName) on the network is another Mac")
            refusedListing = sightings.since[hostName]
            c.cancel()   // moveEnded, from .cancelled
            return
        }
        finishMove(c, kept: kept)
    }

    /// The network connection reaches this session's host: it takes the session over and the
    /// direct one closes. The session reads it at once (first what `probeMove` kept), while what
    /// this device sends waits until the Mac has read everything sent on the direct connection
    /// (SessionLink's fence): a release sent now must not overtake its press still on the slow
    /// link. What any new connection starts afresh starts afresh here too, the screen aside: the
    /// Mac's settings come again on this connection (the ledger's rule 7), the Desktop rule starts
    /// over, and the panel gives the first state its two seconds. Main thread.
    private func finishMove(_ c: NWConnection, kept: [(header: StreamHeader, payload: Data)]) {
        moving = nil
        // The direct session ended meanwhile: its own reconnect runs, and takes the network row.
        guard connected, connectedDirectly, let old = connection else { c.cancel(); return }
        // From here `c` is the session's: the direct connection's pings and one-second windows stop
        // at their next turn, since each checks that it is still `connection`, and its read loop
        // goes on only until the fence's pong (`deliver`).
        let nonce = withUnsafeBytes(of: UInt64.random(in: .min ... .max)) { Data($0) }
        let fencePing = StreamMessage(kind: .ping, timestamp: Date().timeIntervalSince1970, isKeyframe: false, payload: nonce)
        link.handOver(from: old, to: c, fencePing: fencePing.serialized(), nonce: nonce)
        connectedDirectly = false
        session?.route = .network
        setRoute(from: c.currentPath, fresh: true)   // the network connection's, which carries the session now
        status = "Connected to \(hostName)"
        settings.reset()
        settingsProblem = nil
        settingsExpiry?.cancel()
        settingsExpiry = nil
        lastRttMaxMs = nil
        connectedAt = Date()
        lastAutoDesktop = .distantPast
        #if DEBUG
        print("discovery: the session moved to the network")
        #endif
        queue.async {
            self.startMeasuring(c, remote: false)
            for m in kept { self.handle(m.header, m.payload) }
            self.readHeader(on: c)
        }
        // The Mac keeps a frame rate per connection: this one's viewport is the first thing the
        // network connection carries once the fence is down, and the direct one closes half a
        // second after that (`fenceEnded`), so the stream's rate never falls back to the default.
        if let v = lastViewport { sendViewport(v) }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.fenceTimeout) { [weak self] in
            guard let self, let released = self.link.release(old) else { return }
            self.fenceEnded(old, released, why: "no pong on the direct connection")
        }
        updateDiscovery()
    }

    /// A move's fence is down: the Mac has read everything sent on the direct connection (or it
    /// closed, or never answered), and what waited has gone out on the network connection. The
    /// direct one closes half a second later, once the viewport, which went first, has reached the
    /// Mac. Any thread.
    private func fenceEnded(_ old: NWConnection, _ released: SessionLink.Released, why: String) {
        #if DEBUG
        print("discovery: fence down (\(why)) after \(Int((released.seconds * 1000).rounded())) ms; \(released.held) held messages went out over the network")
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { old.cancel() }
    }

    /// The network connection closed before it took the session over, or reached another Mac: the
    /// session stays direct, and the next try waits `moveRetry`. Main thread.
    private func moveEnded(_ c: NWConnection) {
        guard moving === c else { return }
        moving = nil
        if connected { status = "Connected to \(hostName)" }
        #if DEBUG
        print("discovery: the move did not complete; the session stays direct")
        #endif
        moveToNetworkIfListed()
    }

    /// Stops a move under way and its timer (a new session, or none), and drops a hand-over still
    /// waiting for its fence: what it held belonged to the session that ended. Main thread.
    private func abandonMove() {
        moveCheck?.cancel()
        moveCheck = nil
        if let c = moving {
            moving = nil
            c.cancel()
        }
        link.dropHandOver()?.cancel()
    }

    #if DEBUG
    /// `-SillMoveTest <mode>` with `-SillConnect host:port`: the address connection counts as a
    /// direct one, and a second later an address is listed as that Mac's network row, so the move
    /// runs for real (policy, timer, second connection, its first window list, the fence, the
    /// hand-over) against synthetic hosts. `1` lists the same address. `refused` lists port 1 of
    /// that host, where nothing listens: every try waits, is given up after 5 s, and the session
    /// stays direct. `other:PORT` lists that port of the same host address: another synthetic host
    /// there is another launch (one try, refused at its first list, none again while it stays
    /// listed); the same host's own port, with `-SillConnect` through a proxy that delays each
    /// direction, is the same launch behind a slow direct link (moved once the fence has waited out
    /// the proxy's round trip). `to:HOST:PORT` lists that address: the same host reached another
    /// way, so the route can change at the hand-over (from 127.0.0.1, no word, to this Mac's
    /// fe80::…%en0 address, "Wi-Fi"). Main thread.
    private func beginMoveTest(endpoint: NWEndpoint, name: String, mode: String) {
        guard case .hostPort(let host, _) = endpoint, testNetworkRows.isEmpty else { return }
        let listed: NWEndpoint
        if mode == "1" {
            listed = endpoint
        } else if mode == "refused" {
            listed = .hostPort(host: host, port: 1)
        } else if mode.hasPrefix("other:"), let number = UInt16(mode.dropFirst(6)), let port = NWEndpoint.Port(rawValue: number) {
            listed = .hostPort(host: host, port: port)
        } else if mode.hasPrefix("to:"), let colon = mode.lastIndex(of: ":"), mode.distance(from: mode.startIndex, to: colon) > 3,
                  let number = UInt16(mode[mode.index(after: colon)...]), let port = NWEndpoint.Port(rawValue: number) {
            listed = .hostPort(host: NWEndpoint.Host(String(mode[mode.index(mode.startIndex, offsetBy: 3)..<colon])), port: port)
        } else {
            return
        }
        connectedDirectly = true
        print("discovery: move test: this session counts as direct")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self, self.connected else { return }
            self.testNetworkRows = [(name, listed)]
            print("discovery: move test: \(name) listed on the network at \(listed)")
            self.discoveryChanged()
        }
    }
    #endif

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

    /// The interface a link-local address of the Mac is scoped to (the USB cable, AWDL, a Wi-Fi
    /// link-local address); nil for IPv4 and a global IPv6 address, which carry none.
    private static func scopedInterface(_ path: NWPath) -> NWInterface? {
        guard case .hostPort(let host, _)? = path.remoteEndpoint, case .ipv6(let address) = host else { return nil }
        return address.interface
    }

    /// Whether the path names the Mac by its IP address, as the connection's own path does. A path
    /// update of a connection to a Bonjour row can name the service instead, or nothing: that path
    /// describes the service's resolution, not the connection (DiscoveryPolicy.describesFlow).
    private static func namesAddress(_ path: NWPath) -> Bool {
        switch path.remoteEndpoint {
        case .hostPort(.ipv4, _)?, .hostPort(.ipv6, _)?: return true
        default: return false
        }
    }

    /// The interface this device's own address on the connection is on, when the path's local
    /// endpoint names one (either family): the session route's witness after the Mac's scope, for
    /// a connection whose remote address carries none (IPv4, a global IPv6 address).
    private static func localInterface(_ path: NWPath) -> NWInterface? {
        guard case .hostPort(let host, _)? = path.localEndpoint else { return nil }
        return host.interface
    }

    /// `route` after a reading of the session connection's path (DiscoveryPolicy.sessionRoute):
    /// `fresh` for a connection that has just come to carry the session (ready, or handed a move),
    /// which always counts, else a path update, which counts only when it describes the connection
    /// (DiscoveryPolicy.describesFlow: satisfied, and naming the Mac's IP address); any other update
    /// keeps the word. The witness: the Mac's scoped address, else this device's own address's
    /// interface, else the path's interfaces, each as the address or path itself types it. Main
    /// thread.
    private func setRoute(from path: NWPath?, fresh: Bool = false) {
        let describes = DiscoveryPolicy.describesFlow(fresh: fresh, hasAddress: path.map(Self.namesAddress) ?? false,
                                                      satisfied: path?.status == .satisfied)
        let scope = path.flatMap(Self.scopedInterface)
        let local = path.flatMap(Self.localInterface)
        let next = DiscoveryPolicy.sessionRoute(current: route, scope: scope.map(Self.policyInterface),
                                                local: local.map(Self.policyInterface),
                                                path: path?.availableInterfaces.map(Self.policyInterface) ?? [],
                                                describesFlow: describes)
        #if DEBUG
        // What the word was read from, or why an update was not read, to check it on a device (the
        // cable in and out).
        let interfaces = path.map { Self.listed($0.availableInterfaces) } ?? "none"
        if !describes, let path {
            let status = path.status == .satisfied ? "" : " (\(path.status))"
            let endpoint = Self.namesAddress(path) ? ""
                : path.remoteEndpoint.map { " without an address (for \($0))" } ?? " without an endpoint"
            print("session: kept \(route?.word ?? "no word"); ignored a path update\(status)\(endpoint): \(interfaces)")
        } else if fresh || next != route {
            let witness = scope.map { "the Mac's address on \(Self.listed([$0])); " }
                ?? local.map { "this device's address on \(Self.listed([$0])); " } ?? ""
            print("session: \(next?.word ?? "no word"), read from \(witness)path \(interfaces)")
        }
        #endif
        if next != route { route = next }
    }

    #if DEBUG
    /// Interfaces as the DEBUG console names them: "en2 (wiredEthernet), en0 (wifi)", or "none".
    private static func listed(_ interfaces: [NWInterface]) -> String {
        interfaces.isEmpty ? "none" : interfaces.map { "\($0.name) (\($0.type))" }.joined(separator: ", ")
    }
    #endif

    /// Keeps `route` in step with `c`'s path while `c` carries the session: a move's network
    /// connection only from its hand-over on, the direct one it replaced no longer. Only an update
    /// that describes the connection may change the word (`setRoute`): iPadOS also sends ones that
    /// describe a Bonjour row's resolution instead, naming the service rather than the Mac's address
    /// ("en0 (wifi), en0 (wifi)" for a session on the cable's en2, 2026-09-25), and those keep it;
    /// the DEBUG console logs each.
    /// An established TCP connection keeps its interface, so an update that counts rarely changes
    /// anything: a cable pulled mid-session ends the connection instead, and the reconnect reads
    /// its own route when ready.
    private func followRoute(of c: NWConnection) {
        c.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self, self.connected, self.connection === c else { return }
                self.setRoute(from: path)
            }
        }
    }

    /// A remote dial's winner, already `.ready` and pinned (StreamClient+Remote): the session
    /// connection from now on. `connected` waits for its first window list. Main thread.
    func adopt(_ c: NWConnection, session s: Session) {
        if let old = connection {
            connection = nil
            old.cancel()
        }
        abandonMove()
        sessionListed = false
        sessionHost = nil
        refusedListing = nil
        session = s
        goodbye = nil
        // Its way in is its route line's (`remoteRoute`, at its first window list), never a link word.
        if route != nil { route = nil }
        c.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .failed(let e):
                print("connection failed: \(e)")
                self.connectionLost(c, error: e)
                c.cancel()
            case .cancelled:
                self.connectionLost(c)
            default:
                break
            }
        }
        // A remote path that stops being viable for 3 s is gone (the Wi‑Fi dropped, the VPN went
        // down): the ping timer reads this.
        c.viabilityUpdateHandler = { [weak self] viable in
            guard let self else { return }
            self.unviableSince = viable ? nil : (self.unviableSince ?? CACurrentMediaTime())
        }
        // The winner is `.ready` already: its hello goes out before anything the session sends,
        // which only starts once it is `connection`.
        sendHello(on: c)
        connection = c
        queue.async { [weak self] in
            self?.startMeasuring(c, remote: true)
            self?.readHeader(on: c)
        }
    }

    /// The user chose to leave. No reconnect.
    func disconnect() {
        reconnect = nil
        cancelRemoteDial()
        let c = connection
        connection = nil
        c?.cancel()
        tearDown(status: Self.lookingOnNetwork)
        updateDiscovery()
    }

    /// The connection ended: the Mac went away (host quit, Wi-Fi dropped, connection reset, a
    /// goodbye), or a remote dial's winner failed before its window list. `end` overrides what the
    /// error says (a message no Sill sends). StreamClient+Remote decides the words and whether and
    /// how to reconnect. Any thread.
    func connectionLost(_ c: NWConnection, error: NWError? = nil, end: RemoteDialPolicy.End? = nil) {
        // The direct connection of a move ended before its fence came back: nothing more of it can
        // reach the Mac, so what waited goes out on the network connection now.
        if let released = link.release(c) { fenceEnded(c, released, why: "the direct connection closed") }
        DispatchQueue.main.async {
            guard self.connection === c else { return }   // stale callback from a connection we already replaced
            self.connection = nil
            self.sessionEnded(error: error, end: end)
        }
    }

    /// The browse-results handlers reconnect when the Mac's Bonjour record comes back. If the record
    /// never left (the host dropped us but kept running), nothing would fire, so also retry on a
    /// timer while a reconnect is wanted. Main thread.
    func scheduleReconnectRetry(after seconds: TimeInterval = 2) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, !self.connected, self.reconnect != nil else { return }
            if !self.reconnectIfListed() { self.scheduleReconnectRetry(after: min(seconds * 2, 10)) }
        }
    }

    /// Clears everything the session owned. `restartSearch` false for a remote dial whose winner
    /// never delivered its window list: the connect screen never left, and its Remote rows must not
    /// vanish for another 3 s. Main thread.
    func tearDown(status: String, restartSearch: Bool = true) {
        abandonMove()
        lastMoveAttempt = nil
        sessionListed = false
        sessionHost = nil
        refusedListing = nil
        queue.async { self.lastParameterSets = nil; self.pendingMove = nil; self.stopMeasuring() }
        firstListDeadline?.cancel()
        firstListDeadline = nil
        session = nil
        goodbye = nil
        notice = nil
        hostVersion = nil
        hostProtocol = nil
        remoteRoute = nil
        macInfo = nil
        macInfoSaved = false
        macInfoVerified = nil
        macInfoAt = nil
        linkStats = nil
        recentRttMedians = []
        slowLink = false
        localPointer = nil
        cursorShape = nil
        connected = false
        connectedDirectly = false
        route = nil
        // The network gets its first seconds again before a remembered Mac is looked for nearby; the
        // callers then run the policy (updateDiscovery).
        if restartSearch {
            searchingSince = ProcessInfo.processInfo.systemUptime
            askedNearby = false
        }
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
        link.send(message.serialized())
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
        link.send(message.serialized())
    }

    // MARK: - Host → client

    /// The read loop is bound to one connection: a replaced connection's loop stops at its next
    /// read instead of reading from the new one. The direct connection a move is leaving is read on
    /// until its fence's pong (`deliver`): the same loop, so no message is split between two.
    private func readHeader(on c: NWConnection) {
        guard link.reads(c) else { return }
        c.receive(minimumIncompleteLength: StreamMessage.headerLength, maximumLength: StreamMessage.headerLength) { [weak self] data, _, isComplete, error in
            guard let self, self.link.reads(c) else { return }
            guard let data, let header = StreamMessage.parseHeader(data) else {
                // EOF (the host closed cleanly) or a read error: both mean the Mac is gone.
                if let error { print("read error: \(error)") }
                if isComplete || error != nil { self.connectionLost(c, error: error) }
                return
            }
            self.lastReceivedAt = CACurrentMediaTime()
            // Nothing a Sill host sends is bigger than these (docs/remote-access-plan.md §3.7). A
            // reader that waited for whatever a header announces could be held for ever, or read
            // an SSH banner as a 1.7 GB payload: closed, and on a remote dial that is "not Sill".
            let cap = header.kind == .frame ? StreamMessage.maxFramePayload : StreamMessage.maxOtherHostPayload
            guard header.payloadLength <= cap else {
                print("closing: the host announced a \(header.payloadLength)-byte message (kind \(header.kind.rawValue))")
                self.connectionLost(c, end: .notSill)
                c.cancel()
                return
            }
            self.readPayload(header, on: c)
        }
    }

    private func readPayload(_ header: StreamHeader, on c: NWConnection) {
        // A zero-length payload is legal (an empty window list, say); receive() rejects length 0.
        guard header.payloadLength > 0 else {
            deliver(header, Data(), from: c)
            readHeader(on: c)
            return
        }
        c.receive(minimumIncompleteLength: header.payloadLength, maximumLength: header.payloadLength) { [weak self] data, _, isComplete, error in
            guard let self, self.link.reads(c) else { return }
            // EOF or an error mid-message is the Mac gone, as it is between messages: ignoring it
            // left a dead connection on screen with a frozen picture.
            guard let data, data.count == header.payloadLength else {
                if let error { print("read error: \(error)") }
                if isComplete || error != nil || data != nil { self.connectionLost(c, error: error) }
                return
            }
            self.lastReceivedAt = CACurrentMediaTime()
            self.deliver(header, data, from: c)
            self.readHeader(on: c)
        }
    }

    /// On the network queue. A message from the session's connection is handled. One from the
    /// direct connection a move is leaving only matters if it is the fence's pong, which says the
    /// Mac has read everything sent there; the network connection brings all the rest.
    private func deliver(_ header: StreamHeader, _ data: Data, from c: NWConnection) {
        if c === connection {
            handle(header, data)
        } else if header.kind == .pong, let released = link.fenceReturned(data, on: c) {
            fenceEnded(c, released, why: "the Mac has read all the direct connection carried")
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
            let from = connection
            DispatchQueue.main.async {
                // Only from the current connection: a list queued by a replaced one must not
                // describe the next session.
                guard self.connection === from else { return }
                // A remote session is connected at its first window list, not at `.ready`.
                self.remoteSessionReady()
                // The host this session runs on, which a move to the network must reach again
                // (`moveProbed`); its first list is what lets a move start.
                self.sessionHost = list.launchID
                if self.hostVersion != list.hostVersion { self.hostVersion = list.hostVersion }
                if self.hostProtocol != list.protocol { self.hostProtocol = list.protocol }
                if !self.sessionListed {
                    self.sessionListed = true
                    #if DEBUG
                    switch (list.hostVersion, list.protocol) {
                    case (nil, nil): print("host: no version (a Mac from before 2026-09-25)")
                    case (nil, let p?): print("host: no version, protocol \(p)")
                    case (let v?, let p): print("host: Sill \(v), protocol \(p.map(String.init) ?? "?")")
                    }
                    #endif
                    self.moveToNetworkIfListed()
                }
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
                        // Two seconds plus the worst recent round trip: from afar the host's next
                        // list, which would bring the window back, takes that much longer.
                        let choices = self.choicesSent
                        let wait = 2 + Double(self.lastRttMaxMs ?? 0) / 1000
                        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
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
        case .macInfo:
            // Who this Mac is and how to reach it from afar (StreamClient+Remote).
            guard let signed = Wire.decode(SignedMacInfo.self, from: data) else { return }
            let from = connection
            DispatchQueue.main.async {
                guard self.connection === from else { return }
                self.receiveMacInfo(signed, endpoint: from?.endpoint)
            }
        case .goodbye:
            // Why the Mac is about to close this connection: the words, and whether to reconnect
            // (GoodbyePolicy, when the connection ends). One that does not decode is a reason this
            // build does not know: its own words, and no reconnect.
            let goodbye = Wire.decode(Goodbye.self, from: data) ?? Goodbye(reason: "")
            let from = connection
            DispatchQueue.main.async {
                guard self.connection === from else { return }
                self.goodbye = goodbye
            }
        default:
            break // client → host kinds, and anything a newer host invents
        }
    }

    // MARK: - Measurement (on `queue`)

    /// Starts the one-second windows and the pings for `c`, dropping whatever an earlier connection
    /// left behind, and its liveness from now. On `queue`, from the connection's ready state.
    private func startMeasuring(_ c: NWConnection, remote: Bool) {
        guard c === connection else { return }   // replaced while connecting
        stopMeasuring()
        windowOpenedAt = CACurrentMediaTime()
        lastReceivedAt = windowOpenedAt
        worstRecentRttMs = nil
        unviableSince = nil
        remoteOnQueue = remote
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
        if let rtt = stats.rtt { worstRecentRttMs = Double(rtt.max) }
        DispatchQueue.main.async {
            guard self.connection === c else { return }   // torn down meanwhile: stay nil
            self.linkStats = stats
            if let rtt = stats.rtt {
                self.lastRttMaxMs = rtt.max   // for the settings timeout
                self.recentRttMedians = Array((self.recentRttMedians + [rtt.median]).suffix(5))
            }
            let slow = self.remoteRoute != nil && Self.isSlowLink(self.recentRttMedians)
            if slow != self.slowLink { self.slowLink = slow }
        }
    }

    /// The slow-link test: five seconds' round-trip medians whose median is over 250 ms. Judged by
    /// round trip, because a still window legitimately sends no frames; seconds without a pong do
    /// not count either way.
    static func isSlowLink(_ medians: [Int]) -> Bool {
        guard medians.count >= 5 else { return false }
        return medians.suffix(5).sorted()[2] > 250
    }

    /// Liveness, on every route: nothing received for `livenessFloor` seconds, or four times the
    /// worst recent round trip on a slow link, and the connection is gone; a remote path that has
    /// not been viable for `viabilityLimit` seconds too. Checked at each ping. On `queue`.
    private func checkLiveness(_ c: NWConnection) -> Bool {
        let now = CACurrentMediaTime()
        let limit = max(Self.livenessFloor, 4 * (worstRecentRttMs ?? 0) / 1000)
        let silent = now - lastReceivedAt > limit
        let unviable = remoteOnQueue && unviableSince.map { now - $0 > Self.viabilityLimit } == true
        guard silent || unviable else { return true }
        print(silent ? "connection silent for \(Int(now - lastReceivedAt)) s: lost" : "connection not viable for 3 s: lost")
        connectionLost(c)
        c.cancel()
        return false
    }

    /// Returning to the foreground is never a loss by itself: the pings stopped while suspended.
    /// Main thread.
    func resetLiveness() {
        queue.async { [weak self] in
            guard let self else { return }
            self.lastReceivedAt = CACurrentMediaTime()
            self.unviableSince = nil
        }
    }

    /// On `queue`. Stamped with the monotonic clock: a wall-clock correction between a ping and its
    /// pong would otherwise land in the round trip.
    private func sendPing(on c: NWConnection) {
        guard c === connection, checkLiveness(c) else { return }
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
    /// state carries it. Keyed by the Bonjour name this connection was made to, which is what the
    /// policy compares with the browsers' results, not the window list's Mac name: Bonjour renames
    /// a registration that clashes ("Mac (2)") while the window list still says "Mac", and that Mac
    /// would then look missing from the network at every launch. A connection by address
    /// (-SillConnect) has no such name and teaches nothing, and neither do the DEBUG mock's answers
    /// (no connection). Main thread.
    private func rememberDirectWireless(_ state: HostSettingsState) {
        guard let c = connection, case .service(let name, _, _, _) = c.endpoint else { return }
        let next = DiscoveryPolicy.remember(directWirelessMacs, mac: name, directWireless: state.settings.directWireless)
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

    /// `-SillConnect host:port`: connect straight to an address, through the home door. The
    /// synthetic test hosts stay off Bonjour, so this is how the simulator reaches `SillHost
    /// --synthetic` and the bare `SillMenuBar --synthetic` (`address(argument:)` reads it). It never
    /// saves anything. If such a connection drops, the reconnect timer looks for it on Bonjour,
    /// never finds it and backs off to 10 s (or, when its kind 18 named a saved Mac, dials that Mac
    /// remotely).
    func connectFromLaunchArgument() {
        guard let raw = UserDefaults.standard.string(forKey: "SillConnect"),
              let address = Self.address(argument: "SillConnect") else { return }
        if let test = Self.wiredTest {
            print("dialing \(raw) on \(test) (wired test)")
            connect(to: test, name: raw, fallback: address)
        } else {
            connect(to: address, name: raw)
        }
    }

    /// `-SillWiredTest host:port`: the fallback of a wired dial, under test in the simulator against
    /// a synthetic host. `-SillConnect`'s dial, a network row's (any row not Direct counts as
    /// Wired) and a move's under `-SillMoveTest` go to that address first, the way a "Wired" row's
    /// goes to its cable, with the address they would have dialled as the fallback: `192.0.2.1:9`
    /// (TEST-NET-1, never answers) is given up after DiscoveryPolicy.wiredWait, `127.0.0.1:1`
    /// (nothing listens) at once.
    private static let wiredTest = address(argument: "SillWiredTest")

    /// A `host:port` launch argument as an address: by the strict address parser, so `[::1]:P`
    /// works (a split at the last colon broke IPv6), else, for what the parser refuses, split at
    /// the last colon as before, so a scoped link-local address works too (`fe80::…%en0:P`: a zone
    /// means nothing to a saved address, which the parser is for, and everything to a test on this
    /// Mac's own link).
    private static func address(argument key: String) -> NWEndpoint? {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        if case .success(let address) = AddressParser.parse(raw), let number = address.port,
           let port = NWEndpoint.Port(rawValue: UInt16(number)) {
            return .hostPort(host: NWEndpoint.Host(address.host), port: port)
        }
        guard let colon = raw.lastIndex(of: ":"),
              let number = UInt16(raw[raw.index(after: colon)...]),
              let port = NWEndpoint.Port(rawValue: number) else { return nil }
        return .hostPort(host: NWEndpoint.Host(String(raw[..<colon])), port: port)
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
