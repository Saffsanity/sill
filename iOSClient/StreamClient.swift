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
    /// The Wi-Fi interface the network browser saw the Mac on (DiscoveryPolicy.wifiInterface), which
    /// a session that lost the cable dials it on (`wifiDial`); nil for none, for a Direct row and for
    /// a Remote row.
    let wifi: NWInterface?
    /// How the Mac's home door speaks, from its TXT record's `p` (HomeDoorTXT, docs/home-pairing-plan.md
    /// §7.3): plain, TLS for paired devices only, or TLS for any device. What a tap on the row and
    /// the automatic reconnect do follows from it (DiscoveryPolicy.homeDial). `.plain` for a Remote row.
    let door: DiscoveryPolicy.HomeDoor
    /// The row's word, and VoiceOver's label and hint for it (DiscoveryPolicy.rowWord): how the Mac is
    /// reachable, as before, or "Not paired", "Wired" for an unpaired Mac over the cable, "Update Sill".
    let homeWord: DiscoveryPolicy.RowWord

    init(name: String, endpoint: NWEndpoint?, route: Route, macID: String? = nil,
         method: DiscoveryPolicy.Method? = nil, wired: NWInterface? = nil, wifi: NWInterface? = nil,
         door: DiscoveryPolicy.HomeDoor = .plain, homeWord: DiscoveryPolicy.RowWord? = nil) {
        self.name = name; self.endpoint = endpoint; self.route = route; self.macID = macID
        self.method = method; self.wired = wired; self.wifi = wifi
        self.door = door; self.homeWord = homeWord ?? .method(method)
    }

    /// Reached over peer-to-peer Wi-Fi alone: the one kind of row connected with includePeerToPeer.
    var direct: Bool { route == .direct }
    /// A network "Mac mini" and a Remote "Mac mini" are two rows. Names are unique per route
    /// (DiscoveryPolicy.rows lists a name once), Mac IDs among Remote rows.
    var id: String { route == .remote ? "remote:\(macID ?? name)" : "\(route.rawValue):\(name)" }
    /// The word at the end of its row: "Remote" for a saved Mac dialed away from home, else its home
    /// word (`homeWord`): how its Mac is reachable (`method`), "Not paired" or "Update Sill", or nil.
    var word: String? { route == .remote ? "Remote" : homeWord.word }
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
    /// connection that describes it (`followRoute`; the others keep the word). Shown, and read by
    /// `followBestPath` for the path the session runs on (the cable or Wi-Fi); the move from AWDL
    /// reads `connectedDirectly`. Never set on a remote session: its route line says how instead
    /// (`remoteRoute`), and such a session never follows a path here (DiscoveryPolicy.pathPlan).
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
    /// Pairing, as the Add a Mac card, the home card and the overlay show it.
    @Published var pairing = PairingPhase.idle {
        didSet {
            #if DEBUG
            // The simulator gates read what the card or the overlay says here.
            if pairing != oldValue, case .failed(let p) = pairing { print("pairing: \(p.text)") }
            #endif
        }
    }
    /// A sill://pair link from outside the app (Camera, Messages, simctl openurl): never acted on
    /// until the person confirms it.
    @Published var pendingLink: PairLink?

    // Pairing at home (StreamClient+Home.swift). Published on main.
    /// The ask a tap on a row that pairs first made, and what the Mac answered; the home card
    /// follows it.
    @Published var homeAsk: HomeAsk?
    /// The home door's pairing dial in flight (an ask, or a proof): one at a time.
    var homeDialer: HomeDialer?
    /// The Cancel of an ask the Mac answered "shown", on its way to the Mac (`withdrawAsk`): kept
    /// here until it is done, beside whatever the next tap dials.
    var homeWithdrawal: HomeDialer?
    /// Rows the automatic reconnect took by their Bonjour name alone whose key was another's
    /// (-9808): skipped until a session connects (docs/home-pairing-plan.md §7.3).
    var pinRefusedRows = Set<String>()
    #if DEBUG
    /// `-SillTapRow <prefix>`: the first network or Direct row whose name starts so is tapped once,
    /// as soon as it is listed (the gates drive no UI).
    var pendingTapRow = UserDefaults.standard.string(forKey: "SillTapRow")
    /// `-SillOverlayCode` was typed (once per launch).
    var overlayCodeTyped = false
    #endif

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
    /// The harness's settings cases at home over TLS (`paired`, `pairedoff`, `openpair`): the
    /// mock's session counts as one (`sessionAtHomeOverTLS`), having none of its own.
    var mockHomeTLS: Bool?
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
    /// The last Viewport this session sent, so the local-cursor flag can be re-sent without
    /// re-measuring; nil once the session ends (`forgetViewport`). Main thread.
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
    /// `_sill._tcp`. DEBUG `-SillServiceType _silltest._tcp`: the browsers look for that type
    /// instead, so a test host registered with SILL_TEST_SERVICE_TYPE shows as a real row with its
    /// TXT record, and no real Mac is listed (the Debug build's Info.plist declares it).
    static var serviceType: String {
        #if DEBUG
        if let type = UserDefaults.standard.string(forKey: "SillServiceType"), !type.isEmpty { return type }
        #endif
        return "_sill._tcp"
    }
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
    /// A move under way: the connection opened beside the session's, until it has shown it reaches
    /// this session's host and takes over (`finishMove`), or gives up (`moveEnded`), and what the
    /// move is for. Only a session at home moves: a remote one never does (DiscoveryPolicy.pathPlan).
    private var moving: Move?
    private struct Move {
        let connection: NWConnection
        let kind: MoveKind
    }
    /// What a move does: brings a session over AWDL to the network (`fromDirect`,
    /// `moveToNetworkIfListed`), or, `followBestPath`'s, one over Wi-Fi to the cable that came
    /// (`toCable`) or one over the cable that went to Wi-Fi (`toWifi`).
    private enum MoveKind { case fromDirect, toCable, toWifi }
    /// A move is under way, or carries on a session whose connection has gone (`sessionDead`): the
    /// automatic reconnect (StreamClient+Remote's `reconnectIfListed`) never runs meanwhile, so it
    /// cannot dial beside the move. Main thread.
    var moveUnderWay: Bool { moving != nil || sessionDead }
    /// When this session's last move from AWDL started, so one that did not complete waits `moveRetry`.
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

    // Following the best path (DiscoveryPolicy.pathPlan, `followBestPath`). Main thread.
    /// What the network browser has shown of each Mac's paths: on a wired interface since when, on
    /// Wi-Fi now or moments ago.
    private var paths = DiscoveryPolicy.PathSightings()
    /// Each Mac's last network row that listed it on Wi-Fi, which a session that lost the cable dials
    /// while the browser lists no such row for a moment (DiscoveryPolicy.wifiFresh).
    private var lastWifiRow: [String: FoundMac] = [:]
    /// What iOS has said of the session connection's path since it became the session's.
    private var pathSignals = PathSignals()
    /// When the session connection last brought back a pong, or became the session's.
    private var lastPongAt = 0.0
    /// The session connection failed or closed, and a move carries the session on
    /// (DiscoveryPolicy's `reconnectNow`: over the cable again, or to Wi-Fi): the stream screen stays
    /// until the move takes over, and the session ends if it does not (`moveEnded`).
    private var sessionDead = false
    /// When this session's last move up (to the cable, or from AWDL, or a reconnect over the cable)
    /// and down (to Wi-Fi) started.
    private var lastMoveUp: Double?
    private var lastMoveDown: Double?
    /// The listing of the cable (its `paths.wiredSince`) the last move up went to; the one a move
    /// up found to reach another Mac, or another launch of Sill, which is not tried again while it
    /// lasts; and the moves up to one listing that did not complete, in a row, after which the next
    /// waits longer (DiscoveryPolicy.upWait).
    private var upListing: Double?
    private var refusedCable: Double?
    private var failedUps: (listing: Double, count: Int)?
    /// The plan's next look: the cable's 2 s, the hysteresis, the pong silence mark.
    private var pathCheck: DispatchWorkItem?
    /// After a move without a fence, what the session was watching: the Mac may have counted no
    /// device for a moment (the old connection closed before the new one came), and at zero devices
    /// it stops the stream (a staged window goes home). The new connection's first window list picks
    /// it again if nothing streams, the Desktop for a window that has gone. Nil otherwise.
    private var resumeSource: StreamSource?
    #if DEBUG
    /// The reason last printed as "path: kept: …", so that each prints once.
    private var lastKept: DiscoveryPolicy.Keep?
    #endif

    /// What iOS says of the session connection's path. `reported` is DiscoveryPolicy's
    /// `pathReported`: a path update that is not satisfied and names the Mac's address, the
    /// connection not viable, or back to waiting. `hinted` is `pathHinted`: an unsatisfied update
    /// that names only the service. A satisfied update naming the Mac's address, or the connection
    /// viable again, clears what it answers.
    private struct PathSignals {
        var unsatisfied = false
        var notViable = false
        var waiting = false
        var hinted = false
        var reported: Bool { unsatisfied || notViable || waiting }
    }
    #if DEBUG
    /// `-SillMoveTest` with `-SillConnect host:port`: rows the network browser did not list, so the
    /// move to the network runs against synthetic hosts, which no browser lists and which are not
    /// on AWDL (see `beginMoveTest`).
    private var testNetworkRows: [(name: String, endpoint: NWEndpoint)] = []
    /// `-SillPathTest`: the session's Mac as a network row whose interfaces the test changes, and
    /// the addresses its "cable" and "Wi-Fi" are dialled at (see `beginPathTest`).
    private var pathTest: PathTest?
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
        /// At home: how its connections speak to the Mac's door (docs/home-pairing-plan.md §7.2),
        /// plain or TLS, and the key each is pinned to; nil for a remote session.
        var home: DiscoveryPolicy.HomeTrust? = nil
        /// The row it was dialed from, for a pin that fails (§7.6); nil for an address.
        var row: HomeRow? = nil
        /// The endpoint dialed (the DEBUG move and path tests start from it).
        var endpoint: NWEndpoint? = nil
    }
    var session: Session?

    /// The row a session at home was dialed from.
    struct HomeRow: Equatable {
        /// FoundMac.id.
        let id: String
        /// Its TXT tag named the saved Mac; a row the automatic reconnect took by its Bonjour name
        /// alone did not.
        let tagNamed: Bool
        /// Rows of that Mac whose pin already failed in this dial (§7.6).
        var tried: [String] = []
    }

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
        /// The session ended with goodbye `quit`: a row listed since before `lostAt` is the Mac's
        /// registration that is going, left alone for DiscoveryPolicy.quitWait (`reconnectRow`).
        var afterQuit = false
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
        followBestPath()
    }

    /// The rows, each with the endpoint of the browser that listed it: a network row always the
    /// network browser's, so at home a Mac is never reached over AWDL. Each row's word comes from
    /// the interfaces that same browser saw its Mac on (DiscoveryPolicy.method), and so does the
    /// wired interface a "Wired" row is dialled on (DiscoveryPolicy.dialInterface): a browser reports
    /// one result per Mac with every interface it is seen on, and reports it again when one comes
    /// or goes, so plugging the cable in or out changes both. The same results say which paths the
    /// session's Mac is on (DiscoveryPolicy.pathSightings), which `followBestPath` follows. A row
    /// whose TXT tag this device resolves is that saved Mac, whatever its Bonjour name; a result
    /// without a tag is no saved Mac (an older host, or briefly during a re-registration: the
    /// reconnect still finds it by the Bonjour name last used with it). Then a Remote row for each
    /// saved Mac neither browser lists, once the network has had its 3 s. Each row also carries its
    /// home door, from its TXT record's `p`, and the word that follows from it and from what this
    /// device knows of that Mac (DiscoveryPolicy.rowWord: "Not paired", "Update Sill"…); a saved Mac
    /// seen with `p` is remembered as one whose door speaks TLS (`homeTLS`, docs/home-pairing-plan.md
    /// §7.3). Main thread.
    func recomputeMacs() {
        #if DEBUG
        if mockDiscovery { return }
        #endif
        // Each result's interfaces twice, as NWInterface, to dial on, and as the policy spells them,
        // its TXT tag, which names a saved Mac, and its home door (`p`). `stands` is the DEBUG test
        // rows' saved Mac (they carry no tag): the one a `-SillConnect` address counts as.
        typealias Seen = (name: String, endpoint: NWEndpoint, interfaces: [NWInterface], policy: [DiscoveryPolicy.Interface],
                          tag: String?, door: DiscoveryPolicy.HomeDoor, stands: String?)
        var network: [Seen] = networkResults.map {
            (Self.serviceName(of: $0), $0.endpoint, Array($0.interfaces), $0.interfaces.map(Self.policyInterface), Self.tag(of: $0),
             Self.door(of: $0), nil)
        }
        #if DEBUG
        // The move and path tests' rows are the -SillConnect address's Mac: with `-SillHomeDoor`, the
        // one saved Mac when exactly one is saved (docs/home-pairing-plan.md §7.9).
        let stands = Self.testHomeDoor != .plain && savedMacs.count == 1 ? savedMacs[0].macID : nil
        network += testNetworkRows.map { ($0.name, $0.endpoint, [], [], nil, Self.testHomeDoor, stands) }
        if let row = pathTest?.row { network.append((row.name, row.endpoint, [], row.interfaces, nil, Self.testHomeDoor, stands)) }
        #endif
        let nearby: [Seen] = nearbyResults.map {
            (Self.serviceName(of: $0), $0.endpoint, Array($0.interfaces), $0.interfaces.map(Self.policyInterface), Self.tag(of: $0),
             Self.door(of: $0), nil)
        }
        let rows = DiscoveryPolicy.rows(network: network.map(\.name), nearby: nearby.map { ($0.name, $0.policy.map(\.name)) })
        let now = ProcessInfo.processInfo.systemUptime
        directSince = DiscoveryPolicy.directSince(directSince, rows: rows, now: now)
        sightings = DiscoveryPolicy.sightings(sightings, listed: Set(network.map(\.name)), now: now)
        paths = DiscoveryPolicy.pathSightings(paths, network: network.map { ($0.name, $0.policy) }, now: now)
        // A saved Mac seen with `p` has a door that speaks TLS: remembered first, so a row of it
        // without `p` (a replayed tag, or an older Sill.app put back) reads "Update Sill" at once.
        let listed = rows.compactMap { row in (row.direct ? nearby : network).first { $0.name == row.name } }
        let seenTLS = Set(listed.filter { $0.door != .plain }.compactMap { SavedMacs.recognize(tag: $0.tag, in: savedMacs) })
        if let marked = SavedMacs.seenOverTLS(seenTLS, in: savedMacs) {
            savedMacs = marked
            storeSavedMacs()
            #if DEBUG
            print("home: \(seenTLS.sorted()) seen with p: never dialed plain again")
            #endif
        }
        // This device's own addresses: whether a Wired row's interface carries only link-local ones
        // (the USB cable to the Mac) or a network's (a USB Ethernet adapter), for its word.
        let own = Self.ownAddresses()
        var next = rows.compactMap { row -> FoundMac? in
            guard let seen = (row.direct ? nearby : network).first(where: { $0.name == row.name }) else { return nil }
            let wired = DiscoveryPolicy.dialInterface(direct: row.direct, interfaces: seen.policy)
            let wifi = DiscoveryPolicy.wifiInterface(direct: row.direct, interfaces: seen.policy)
            let macID = SavedMacs.recognize(tag: seen.tag, in: savedMacs) ?? seen.stands
            let saved = macID.flatMap { id in savedMacs.first { $0.macID == id } }
            let method = DiscoveryPolicy.method(direct: row.direct, interfaces: seen.policy)
            let word = DiscoveryPolicy.rowWord(door: seen.door, saved: saved != nil, revoked: saved?.revoked == true,
                                               homeTLS: saved?.homeTLS == true, debug: Self.debugBuild, method: method,
                                               cable: wired.map { DiscoveryPolicy.carriesOnlyLinkLocal($0, own: own) } ?? false)
            return FoundMac(name: row.name, endpoint: seen.endpoint, route: row.direct ? .direct : .network,
                            macID: macID, method: method,
                            wired: wired.flatMap { name in seen.interfaces.first { $0.name == name } },
                            wifi: wifi.flatMap { name in seen.interfaces.first { $0.name == name } },
                            door: seen.door, homeWord: word)
        }
        for mac in next where mac.route == .network && paths.wifi[mac.name] != nil { lastWifiRow[mac.name] = mac }
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
            let seen = (mac.direct ? nearby : network).first { $0.name == mac.name }
            let named = seen.map { s in s.interfaces.isEmpty ? s.policy.map { "\($0.name) (\($0.type))" } : s.interfaces.map { "\($0.name) (\($0.type))" } } ?? []
            let door = mac.door == .plain ? "" : " (p=\(mac.door == .open ? "0" : "1")\(mac.homeWord == .method(mac.method) ? "" : ", \(mac.homeWord.word ?? "no word")"))"
            print("discovery: \(mac.name): \(mac.method?.word ?? "no word"), seen on \(named.joined(separator: ", "))\(door)")
        }
        #endif
        macs = next
        #if DEBUG
        if let prefix = pendingTapRow, let mac = macs.first(where: { $0.route != .remote && $0.name.hasPrefix(prefix) }) {
            pendingTapRow = nil
            print("harness: tapping \(mac.name)")
            DispatchQueue.main.async { self.connect(to: mac) }
        }
        #endif
    }

    /// A result's recognition tag (TXT `r`), if it carries one.
    static func tag(of result: NWBrowser.Result) -> String? {
        if case .bonjour(let txt) = result.metadata { return txt[RecognitionTag.txtKey] }
        return nil
    }

    /// An interface as DiscoveryPolicy spells it, case for case.
    static func policyInterface(_ interface: NWInterface) -> DiscoveryPolicy.Interface {
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
    /// the saved Mac's addresses through the remote door. At home the row's door decides the rest
    /// (`dial`): a pinned session, the ask, a session on an open door, a plain one, or nothing.
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
        cancelHomeAsk()      // …and so does an ask still under way
        if mac.route == .remote, let id = mac.macID {
            dialSaved(id, why: .tap)
            return
        }
        dial(mac, macID: mac.macID, tap: true)
    }

    /// A network or Direct row's dial, a tap's or the automatic reconnect's (which keeps its
    /// `reconnect` until the connection is ready), by the row's home door and what this device knows
    /// of its Mac (DiscoveryPolicy.homeDial, docs/home-pairing-plan.md §7.4): a saved Mac's session
    /// pinned to its key; an unsaved Mac's on an open door with any key; the ask (a tap's only) for
    /// a Mac that requires pairing or removed this device; a plain one to a plain door (a DEBUG
    /// build, a Mac never seen with `p`); nothing for a Mac whose Sill is too old for this build.
    /// `macID`: the saved Mac it is (its tag's, or the reconnect's by Bonjour name). True when it
    /// dialed something. Main thread.
    @discardableResult
    func dial(_ mac: FoundMac, macID: String?, tap: Bool) -> Bool {
        let saved = macID.flatMap { savedMac($0) }
        let decision = homeDecision(mac, macID: macID, tap: tap)
        switch decision {
        case .updateSill:
            status = DiscoveryPolicy.updateSillStatus(mac: mac.name)
            return false
        case .waitForTap:
            return false
        case .ask(let pinned):
            ask(mac, savedID: pinned ? saved?.macID : nil, tagNamed: mac.macID != nil)
            return true
        case .pinned, .anyKey, .plain:
            guard let trust = DiscoveryPolicy.sessionTrust(decision, savedPin: saved?.fingerprintData) else { return false }
            return dialRow(mac, macID: saved?.macID, trust: trust, tagNamed: mac.macID != nil)
        }
    }

    /// DiscoveryPolicy.homeDial for a row, from what this device knows of its Mac (`macID`).
    func homeDecision(_ mac: FoundMac, macID: String?, tap: Bool) -> DiscoveryPolicy.HomeDial {
        let saved = macID.flatMap { savedMac($0) }
        return DiscoveryPolicy.homeDial(door: mac.door, saved: saved != nil, revoked: saved?.revoked == true,
                                        homeTLS: saved?.homeTLS == true, debug: Self.debugBuild, tap: tap)
    }

    /// A row's session dial with `trust`: over the row's wired interface first when it says "Wired"
    /// (`wiredDial`), else as listed. `tried`: rows of the same saved Mac whose pin already failed
    /// (§7.6). True when it dialed. Main thread.
    @discardableResult
    func dialRow(_ mac: FoundMac, macID: String?, trust: DiscoveryPolicy.HomeTrust, tagNamed: Bool, tried: [String] = []) -> Bool {
        guard let endpoint = mac.endpoint else { return false }
        let row = HomeRow(id: mac.id, tagNamed: tagNamed, tried: tried)
        if let wired = wiredDial(for: mac) {
            #if DEBUG
            print("dialing \(mac.name) on \(wired.via)")
            #endif
            return connect(to: wired.endpoint, name: mac.name, macID: macID, fallback: endpoint, trust: trust, row: row)
        }
        return connect(to: endpoint, name: mac.name, peerToPeer: mac.direct, macID: macID, trust: trust, row: row)
    }

    /// Where a row whose Mac the network browser saw on a wired interface (`FoundMac.wired`, the
    /// row says "Wired") is dialled first: its Bonjour service resolved on that interface alone, so
    /// the connection runs over the cable (with Wi-Fi up too, an unconstrained dial took either,
    /// 2026-09-25), and how the DEBUG console names it. Nil for any other row, dialled as listed.
    /// Main thread.
    func wiredDial(for mac: FoundMac) -> (endpoint: NWEndpoint, via: String)? {
        guard mac.route == .network else { return nil }
        #if DEBUG
        if let test = Self.wiredTest { return (test, "\(test) (wired test)") }
        if let test = pathTest, mac.name == test.name {
            return mac.method == .wired ? (test.cable, "\(PathTest.cableName) (wired; path test: \(test.cable))") : nil
        }
        #endif
        guard let wired = mac.wired, case .service(let name, let type, let domain, _)? = mac.endpoint else { return nil }
        return (.service(name: name, type: type, domain: domain, interface: wired), "\(wired.name) (wired)")
    }

    /// Where a session that lost the cable dials its Mac (`followBestPath`'s move down): the row's
    /// Bonjour service resolved on the Wi-Fi interface the browser saw it on (`FoundMac.wifi`), the
    /// form a Wired row's cable is dialled in, so nothing races the cable that just went, with the
    /// row as listed, unconstrained, as the fallback (`moveUnconstrained`); the row as listed when it
    /// names no Wi-Fi interface. And how the DEBUG console names it. Nil for a Direct or Remote row,
    /// which a session never moves to. Main thread.
    private func wifiDial(for mac: FoundMac) -> (endpoint: NWEndpoint, via: String, fallback: NWEndpoint?)? {
        guard mac.route == .network, let endpoint = mac.endpoint else { return nil }
        #if DEBUG
        if let test = pathTest, mac.name == test.name { return (test.wifi, "\(PathTest.wifiName) (path test: \(test.wifi))", nil) }
        #endif
        if let wifi = mac.wifi, case .service(let name, let type, let domain, _) = endpoint {
            return (.service(name: name, type: type, domain: domain, interface: wifi), "\(wifi.name) (Wi\u{2011}Fi)", endpoint)
        }
        return (endpoint, "the row as listed", nil)
    }

    /// Connects to a Bonjour result's endpoint through the home door, or straight to an address
    /// (DEBUG `-SillConnect`). `name` is what the status line calls the Mac until its window list
    /// brings its own name. `peerToPeer` only for a Mac seen over peer-to-peer Wi-Fi alone. `macID`:
    /// the saved Mac the row is, when its tag said so. With a `fallback` this is a wired dial
    /// (`wiredDial`): not ready within DiscoveryPolicy.wiredWait, or unable to go on, it gives way
    /// to `fallback`, the row as listed, dialled unconstrained (`dialUnconstrained`). `trust`: how
    /// the session speaks to the door (docs/home-pairing-plan.md §7.2): plain, connected at `.ready`
    /// as before; or TLS, pinned as the trust says, and connected at its first window list
    /// (`homeSessionReady`), since with TLS 1.3 the connection is ready before the Mac has judged
    /// this device's key. `row`: the row it was dialed from. False when a TLS dial finds no key and
    /// none can be made (the status says so).
    @discardableResult
    func connect(to endpoint: NWEndpoint, name: String, peerToPeer: Bool = false, macID: String? = nil, fallback: NWEndpoint? = nil,
                 trust: DiscoveryPolicy.HomeTrust = .plain, row: HomeRow? = nil) -> Bool {
        // A TLS dial's parameters need this device's key, made now at its first one.
        guard let params = sessionParameters(trust, peerToPeer: peerToPeer) else { return false }
        // One connection at a time. A tap on the connect screen racing the reconnect timer used to
        // open two: both then read from whichever `connection` pointed at, interleaving headers
        // and payloads, while the other was never read and the host evicted it after 4 s.
        if let old = connection {
            connection = nil
            old.cancel()      // its .cancelled callback is ignored: connectionLost checks identity
        }
        cancelRemoteDial()
        abandonMove()         // a new session: an old one's move to the network is moot
        resetPath()           // …and so is what the old one knew of its path
        sessionListed = false // …and its host is not yet known
        sessionHost = nil
        refusedListing = nil
        hostName = name
        var bonjourName: String?
        if case .service(let service, _, _, _) = endpoint { bonjourName = service }
        session = Session(route: peerToPeer ? .direct : .network, macID: macID, bonjourName: bonjourName, home: trust, row: row,
                          endpoint: endpoint)
        goodbye = nil
        status = peerToPeer ? "Connecting to \(name) directly…" : "Connecting to \(name)…"
        #if DEBUG
        if trust.tls { print("home: dialing \(name) over TLS, \(DiscoveryPolicy.pin(trust) == .anyKey ? "any key" : "pinned")") }
        #endif
        let c = NWConnection(to: endpoint, using: params)
        // The hello first, written to `c` before it becomes the session's connection below: from
        // then on the session can send through the link before `.ready` (a coast's end as the
        // stream screen goes, the pointer's viewport 200 ms after a tear-down), and a send made
        // before `.ready` goes out once it is ready, in the order made. Sent at `.ready`, the hello
        // came after such a message, and a Mac with a device floor refuses a device whose first
        // message is not its hello. Over TLS (a TLS home door) the send waits for the handshake, so
        // the hello is the first message inside TLS.
        sendHello(on: c)
        var wasReady = false   // the handler runs on `queue`, one state at a time
        c.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                // Ready again after waiting: the session reads `c` already (a second read loop would
                // split its messages), and its path is back.
                guard !wasReady else { self.sessionReadyAgain(c); return }
                wasReady = true
                let direct = peerToPeer && Self.runsPeerToPeer(c.currentPath)
                let path = c.currentPath
                let seen = trust.tls ? RemoteTLS.peerFingerprint(c) : nil
                DispatchQueue.main.async {
                    guard self.connection === c else { c.cancel(); return }   // replaced while connecting
                    self.connectedDirectly = direct
                    self.session?.route = direct ? .direct : .network
                    // An open door's session keeps the key its first connection saw: every later one pins it.
                    if let t = self.session?.home { self.session?.home = DiscoveryPolicy.trust(t, readyWith: seen) }
                    self.setRoute(from: path, fresh: true)
                    self.pathSignals = PathSignals()
                    self.lastPongAt = ProcessInfo.processInfo.systemUptime
                    if trust.tls {
                        self.awaitFirstList(c)   // connected at its first window list (`homeSessionReady`)
                    } else {
                        self.markConnected(endpoint: endpoint, name: name)
                    }
                }
                self.startMeasuring(c, remote: false)   // before the first read, so the first window is this connection's alone
                self.readHeader(on: c)
            case .waiting(let e):
                print("connection waiting: \(e)")
                // Once `c` carries the session (a wired dial's too), waiting again means its path is gone.
                self.sessionWaiting(c)
                if let fallback {   // a wired dial that cannot go on (the cable just pulled, say)
                    DispatchQueue.main.async {
                        self.dialUnconstrained(after: c, fallback, name: name, macID: macID, trust: trust, row: row, why: "is waiting (\(e))")
                    }
                    return
                }
                // A TLS error while connecting (this device's pin refused the Mac's key, -9808): the
                // dial is over at once, and its end says what it means (`homeSessionEnded`).
                if trust.tls, RemoteTLS.status(of: e) != nil {
                    DispatchQueue.main.async {
                        guard self.connection === c, !self.connected else { return }
                        self.connectionLost(c, error: e)
                        c.cancel()
                    }
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
                    DispatchQueue.main.async {
                        self.dialUnconstrained(after: c, fallback, name: name, macID: macID, trust: trust, row: row, why: "failed (\(e))")
                    }
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
                self?.dialUnconstrained(after: c, fallback, name: name, macID: macID, trust: trust, row: row,
                                        why: "did not connect in \(DiscoveryPolicy.wiredWait) s")
            }
        }
        return true
    }

    /// The session is connected: at `.ready` for a plain door, at its first window list over TLS
    /// (`homeSessionReady`). The reconnect ends, the nearby search stops, and a session over AWDL or
    /// on Wi-Fi with the cable listed may move at once. Main thread.
    func markConnected(endpoint: NWEndpoint?, name: String) {
        reconnect = nil
        // Connected: no ask is left waiting (a pairing through a link's addresses leaves one), so the
        // home card never comes back for it with the connect screen.
        cancelHomeAsk(idleStatus: false)
        connected = true
        askedNearby = false
        connectedAt = Date()
        pinRefusedRows = []
        status = "Connected to \(name)"
        updateDiscovery()   // stops the nearby browser; the network one keeps running
        #if DEBUG
        if let endpoint, let test = UserDefaults.standard.string(forKey: "SillMoveTest") {
            beginMoveTest(endpoint: endpoint, name: name, mode: test)
        }
        if let test = UserDefaults.standard.string(forKey: "SillPathTest") {
            beginPathTest(name: name, spec: test)
        }
        #endif
        moveToNetworkIfListed()   // over AWDL: the network may list this Mac already
        followBestPath()
    }

    /// A wired dial, `c`, that has not connected: cancelled, and `fallback`, the row as listed,
    /// dialled unconstrained, as it was before the wired preference, once (it has no fallback of
    /// its own), under the status line the dial showed ("Reconnecting…" stays). Only while `c` is
    /// still the connection and not ready: a tap may have replaced it meanwhile, or it connected at
    /// the last moment. Main thread.
    private func dialUnconstrained(after c: NWConnection, _ fallback: NWEndpoint, name: String, macID: String?,
                                   trust: DiscoveryPolicy.HomeTrust, row: HomeRow?, why: String) {
        guard connection === c, !connected, c.state != .ready else { return }
        #if DEBUG
        print("wired dial \(why); dialing unconstrained")
        #endif
        let shown = status
        // Cancels `c`, whose .cancelled finds it replaced; the same trust, so never plain for a TLS door.
        connect(to: fallback, name: name, macID: macID, trust: trust, row: row)
        status = shown
    }

    /// A move's connection (from AWDL, to the cable, to Wi-Fi, a reconnect over the cable): as the
    /// session's own connections are dialed (`sessionParameters`), never peer-to-peer (a move goes
    /// to the network), pinned to the key the session trusts. Should this device's key be
    /// unreadable (it cannot be: the session's first connection was made with it, and it stays in
    /// memory), parameters that never connect, so the move fails as any failed move does and
    /// nothing goes out plain to a TLS door.
    private func moveParameters() -> NWParameters {
        let trust = session?.home ?? .plain
        if let params = sessionParameters(trust, peerToPeer: false) { return params }
        return DeviceTLS.refusing(peerToPeer: false, queue: queue)
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

    /// The hello, the first thing on every session connection, written straight to `c` before
    /// anything else can go out on it: a Mac with a device floor judges the device by its first
    /// message. A tap's, a reconnect's, a wired dial's and its fallback's as the connection is
    /// made, before it becomes the session's (`connect(to:)`: a send made before `.ready` waits
    /// for it, in order, and over TLS for the handshake, so it is the first message inside TLS); a
    /// move's as it is made (`startMove`: from AWDL, to the cable, to Wi-Fi, a rescue's reconnect,
    /// and each one's fallback; nothing else goes out on it before the hand-over); a remote dial's
    /// winner before it becomes the session's (`adopt`). Never on a pairing connection, whose one
    /// message is kind 19. Older Macs skip it. Any thread.
    private func sendHello(on c: NWConnection) {
        let message = StreamMessage(kind: .hello, timestamp: Date().timeIntervalSince1970, isKeyframe: false, payload: Self.helloPayload)
        c.send(content: message.serialized(), completion: .contentProcessed { _ in })
        #if DEBUG
        if let hello = Wire.decode(Hello.self, from: Self.helloPayload) {
            print("hello: sent Sill \(hello.appVersion ?? "?") (\(hello.build ?? "?")), protocol \(hello.protocol ?? 0)")
        }
        #endif
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
    /// did not connect can take up to 7.5 s in all. It is a move up, so `followBestPath` counts its
    /// hysteresis from it. Main thread.
    private func move(to mac: FoundMac) {
        guard let endpoint = mac.endpoint else { return }
        let now = ProcessInfo.processInfo.systemUptime
        lastMoveAttempt = now
        lastMoveUp = now
        status = "Switching to Wi\u{2011}Fi…"
        if let wired = wiredDial(for: mac) {
            #if DEBUG
            print("discovery: moving the session to the network on \(wired.via)")
            #endif
            startMove(to: wired.endpoint, kind: .fromDirect, fallback: endpoint)
        } else {
            #if DEBUG
            print("discovery: moving the session to the network")
            #endif
            startMove(to: endpoint, kind: .fromDirect, fallback: nil)
        }
    }

    /// The move's connection, to `endpoint`, with its own 5 s. With a `fallback` its first dial is
    /// pinned to an interface (the cable, for a move from AWDL to a Wired row; Wi-Fi, for a move off
    /// the cable), and gives way to `fallback` dialled unconstrained when not ready within
    /// DiscoveryPolicy.wiredWait, or unable to go on (`moveUnconstrained`). A move to the cable has
    /// none (the row as listed could be Wi-Fi again, and never Wi-Fi to Wi-Fi): its wired dial not
    /// ready within wiredWait, or unable to go on, ends the move (`giveUpMove`). Main thread.
    private func startMove(to endpoint: NWEndpoint, kind: MoveKind, fallback: NWEndpoint?) {
        let c = NWConnection(to: endpoint, using: moveParameters())
        // Its own hello first, written to `c` as it is made, as `connect(to:)` does: every move's
        // connection (from AWDL, to the cable, to Wi-Fi, a rescue's, each fallback's) is a new
        // session connection to the Mac, and a Mac with a device floor judges it by its first
        // message (inside TLS at a TLS home door). Nothing else goes out on it before the
        // hand-over: what the session sends meanwhile waits in SessionLink (a fence, a hold), which
        // releases it onto `c` only after.
        sendHello(on: c)
        moving = Move(connection: c, kind: kind)
        // A move up gives up; a reconnect over the cable (`sessionDead`) has the row as listed for
        // its fallback instead, whose own dial has the move's 5 s.
        let givesUp = kind == .toCable && !sessionDead
        var wasReady = false   // the handler runs on `queue`, one state at a time
        // One handler for both lives of `c`: until it takes over, `moveEnded` acts (it checks
        // `moving`); after, `connectionLost` and `sessionWaiting` do (they check `connection`).
        c.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                guard !wasReady else { self.sessionReadyAgain(c); return }   // as in `connect`
                wasReady = true
                self.probeMove(c)
            case .waiting(let e):
                self.sessionWaiting(c)
                if let fallback {
                    DispatchQueue.main.async { self.moveUnconstrained(after: c, fallback, why: "is waiting (\(e))") }
                } else if givesUp {
                    DispatchQueue.main.async { self.giveUpMove(c, why: "is waiting (\(e))") }
                }
            case .failed(let e):
                print(kind == .fromDirect ? "move to the network failed: \(e)" : "path: the move's connection failed: \(e)")
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
        } else if givesUp {
            DispatchQueue.main.asyncAfter(deadline: .now() + DiscoveryPolicy.wiredWait) { [weak self] in
                self?.giveUpMove(c, why: "did not connect in \(DiscoveryPolicy.wiredWait) s")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.moving?.connection === c else { return }
            // Not taken over in 5 s: the session stays where it is. The move ends before `c` is
            // cancelled: a `.ready` can still be delivered after the cancel, and a list read meanwhile
            // must find the move over (`moveProbed` checks `moving`) rather than hand the session to
            // a dead connection.
            self.moveEnded(c)
            c.cancel()
        }
    }

    /// The move's pinned dial, `c`, has not connected: the move goes on over the network row as
    /// listed, dialled unconstrained, once, with 5 s of its own, and `c` is cancelled. Only while
    /// `c` is still the move's and not ready. Main thread.
    private func moveUnconstrained(after c: NWConnection, _ fallback: NWEndpoint, why: String) {
        guard let move = moving, move.connection === c, c.state != .ready else { return }
        #if DEBUG
        switch move.kind {
        case .fromDirect: print("discovery: the wired move \(why); moving unconstrained")
        case .toCable: print("path: the dial on the cable \(why); dialing the row as listed")
        case .toWifi: print("path: the dial on Wi\u{2011}Fi \(why); dialing the row as listed")
        }
        #endif
        startMove(to: fallback, kind: move.kind, fallback: nil)   // `moving` from here: `c`'s moveEnded does nothing
        c.cancel()
    }

    /// A move to the cable whose wired dial, `c`, has not connected: the move ends, the session stays
    /// on Wi-Fi, and `c` is cancelled. Only while `c` is still the move's and not ready. Main thread.
    private func giveUpMove(_ c: NWConnection, why: String) {
        guard moving?.connection === c, c.state != .ready else { return }
        #if DEBUG
        print("path: the dial on the cable \(why)")
        #endif
        moveEnded(c)   // before the cancel, as at the move's 5 s
        c.cancel()
    }

    /// On `queue`, once the network connection is ready: reads it up to its first window list,
    /// keeping every message for the session's read loop to replay should it take over, and hands
    /// the list's host to `moveProbed`. Ticks, frames or a broadcast can come before the list: the
    /// Mac adds a connection to its broadcasts before its catalog goes out. A goodbye (kind 22)
    /// before the list goes to `moveSaidGoodbye`, and the reading goes on to the Mac's close. A read
    /// that fails, a message cut short, or one bigger than the session's reader takes
    /// (`readHeader`), cancels `c`, which ends the move (`moveEnded`).
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
                if header.kind == .goodbye {
                    // Queued on main before the `.cancelled` that the Mac's close brings (read on
                    // below), so `moveEnded` finds what it said. One that does not decode is a
                    // reason this build does not know, as in `handle`.
                    let goodbye = Wire.decode(Goodbye.self, from: payload) ?? Goodbye(reason: "")
                    DispatchQueue.main.async { self.moveSaidGoodbye(c, goodbye) }
                }
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

    /// The move's connection's first window list is in: the session goes over if the list comes
    /// from the host this session runs on (DiscoveryPolicy.sameHost). Main thread.
    private func moveProbed(_ c: NWConnection, kept: [(header: StreamHeader, payload: Data)], host: String?) {
        guard let move = moving, move.connection === c else { c.cancel(); return }   // given up meanwhile (its 5 s, a new session)
        // Failed since its list came: its handler's `moveEnded` follows, so `moving` is left for it.
        guard c.state == .ready else { c.cancel(); return }
        guard DiscoveryPolicy.sameHost(sessionHost, host) else {
            if move.kind == .fromDirect {
                // Another Mac of this name, on the network while this one is reached over AWDL: the
                // two share no link, so mDNS renamed neither. Not tried again while that listing lasts.
                print("move to the network refused: \(hostName) on the network is another Mac")
                refusedListing = sightings.since[hostName]
            } else {
                // Sill relaunched on the Mac, most likely: the session's own connection is to the
                // launch that went, and the reconnect joins the new one when that connection ends.
                // Or another Mac of this name on the cable: a move up does not try that listing of
                // the cable again (DiscoveryPolicy's `refusedCable`).
                print("path: move refused: \(hostName) there is another Mac, or another launch of Sill")
                if move.kind == .toCable, !sessionDead { refusedCable = upListing }
            }
            c.cancel()   // moveEnded, from .cancelled
            return
        }
        finishMove(c, kind: move.kind, kept: kept)
    }

    /// The Mac said goodbye on the move's connection before its first window list: it closes that
    /// connection unserved (a device floor above this build refused it, "update", or Sill is
    /// quitting), and its close ends the move (`moveEnded`) right after this. A session whose own
    /// connection has gone (`sessionDead`: a rescue's reconnect, or a move to Wi-Fi that carries
    /// it) then ends as a refusal on any connection ends (StreamClient+Remote's `sessionEnded`): with
    /// the Mac's words, and without dialling that Mac again unless the goodbye asks for it. A
    /// session still running stays where it is, and a move up does not try the listing that
    /// refused it again while that lasts, as with another Mac (`moveProbed`). Main thread.
    private func moveSaidGoodbye(_ c: NWConnection, _ goodbye: Goodbye) {
        guard let move = moving, move.connection === c else { return }   // given up meanwhile
        let reason = goodbye.reason.isEmpty ? "unreadable" : goodbye.reason
        if sessionDead {
            print("path: the Mac said goodbye (\(reason)) on the new connection: the session ends with its words")
            self.goodbye = goodbye
            return
        }
        switch move.kind {
        case .fromDirect:
            print("move to the network refused: \(hostName) on the network said goodbye (\(reason))")
            refusedListing = sightings.since[hostName]
        case .toCable:
            print("path: move refused: \(hostName) on the cable said goodbye (\(reason))")
            refusedCable = upListing
        case .toWifi:
            print("path: move refused: \(hostName) on Wi\u{2011}Fi said goodbye (\(reason))")
        }
    }

    /// The move's connection reaches this session's host: it takes the session over and the old one
    /// closes. The session reads it at once (first what `probeMove` kept). What this device sends
    /// waits until the Mac has read everything sent on the old connection (SessionLink's fence): a
    /// release sent now must not overtake its press still on the slow link. So for a move up (from
    /// AWDL, or to the cable) even when iOS has said the old connection's path is gone, which can
    /// pass: a fence that never comes back is let go after `fenceTimeout`. Not for a move to Wi-Fi,
    /// whose old path is gone, nor when the old connection is (a reconnect): what waited since the
    /// move began (SessionLink's hold) goes out on the new connection at once, and the old one is
    /// dropped with whatever it still held, which must not reach the Mac late should its path come
    /// back. What any new connection starts afresh starts afresh here too, the screen aside: the
    /// Mac's settings come again on this connection (the ledger's rule 7), the Desktop rule starts
    /// over, and the panel gives the first state its two seconds. Main thread.
    private func finishMove(_ c: NWConnection, kind: MoveKind, kept: [(header: StreamHeader, payload: Data)]) {
        moving = nil
        // The session this move was for must still run: over AWDL for a move from AWDL (a direct
        // session that ended meanwhile reconnects by itself, to the network row), not over it for
        // `followBestPath`'s.
        guard connected, let old = connection, connectedDirectly == (kind == .fromDirect) else { c.cancel(); return }
        // From here `c` is the session's: the old connection's pings and one-second windows stop at
        // their next turn, since each checks that it is still `connection`, and its read loop goes on
        // only until the fence's pong (`deliver`), or stops at once without a fence.
        let reconnected = sessionDead
        let fenced = kind != .toWifi && !reconnected
        if fenced {
            let nonce = withUnsafeBytes(of: UInt64.random(in: .min ... .max)) { Data($0) }
            let fencePing = StreamMessage(kind: .ping, timestamp: Date().timeIntervalSince1970, isKeyframe: false, payload: nonce)
            link.handOver(from: old, to: c, fencePing: fencePing.serialized(), nonce: nonce)
        } else {
            let released = link.adopt(c)
            old.forceCancel()
            closeSoon(released?.close ?? [])
            resumeSource = active == .none ? nil : active
            #if DEBUG
            let waiting = (released?.waiting ?? 0) > 0 ? " (\(released!.waiting) wait for an earlier hand-over's fence)" : ""
            print("path: no fence (the old connection\(reconnected ? " is gone" : "'s path is gone")): \(released?.held ?? 0) held messages went out on the new connection\(waiting)")
            #endif
        }
        if kind == .toCable, !reconnected { failedUps = nil }   // a move up that completed: the back-off starts again
        connectedDirectly = false
        session?.route = .network
        sessionDead = false
        pathSignals = PathSignals()
        lastPongAt = ProcessInfo.processInfo.systemUptime
        setRoute(from: c.currentPath, fresh: true)   // the new connection's, which carries the session now
        status = "Connected to \(hostName)"
        settings.reset()
        settingsProblem = nil
        settingsExpiry?.cancel()
        settingsExpiry = nil
        lastRttMaxMs = nil
        connectedAt = Date()
        lastAutoDesktop = .distantPast
        #if DEBUG
        switch kind {
        case .fromDirect: print("discovery: the session moved to the network")
        case .toCable: print(reconnected ? "path: the session carried on over a new connection (the cable's dial)" : "path: the session moved to the cable")
        case .toWifi: print("path: the session moved to Wi\u{2011}Fi")
        }
        #endif
        queue.async {
            self.startMeasuring(c, remote: false)
            for m in kept { self.handle(m.header, m.payload) }
            self.readHeader(on: c)
        }
        // The Mac keeps a frame rate per connection: this one's viewport is the first thing the new
        // connection carries once the fence is down, and the old one closes half a second after
        // that (`fenceEnded`), so the stream's rate never falls back to the default.
        if let v = lastViewport { sendViewport(v) }
        if fenced {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.fenceTimeout) { [weak self] in
                guard let self, let released = self.link.release(old) else { return }
                self.fenceEnded(old, released, why: kind == .fromDirect ? "no pong on the direct connection" : "no pong on the old connection")
            }
        }
        updateDiscovery()
        followBestPath()
    }

    /// A move's fence is down: the Mac has read everything sent on the direct connection (or it
    /// closed, or never answered), and what waited has gone out on the network connection, unless
    /// another fence or a hold still stands (two hand-overs in a row). The old connections close
    /// once what waited has gone out (`Released.close`). Any thread.
    private func fenceEnded(_ old: NWConnection, _ released: SessionLink.Released, why: String) {
        #if DEBUG
        let waiting = released.waiting > 0 ? " (\(released.waiting) still wait for another fence, or a hold)" : ""
        print("discovery: fence down (\(why)) after \(Int((released.seconds * 1000).rounded())) ms; \(released.held) held messages went out over the network\(waiting)")
        #endif
        closeSoon(released.close)
    }

    /// Old connections whose fences are down, now that what waited has gone out on the session's
    /// connection: each closes half a second later, once the viewport, which went first, has
    /// reached the Mac. Any thread.
    private func closeSoon(_ olds: [NWConnection]) {
        guard !olds.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { for c in olds { c.cancel() } }
    }

    /// The move's connection closed before it took the session over, or reached another Mac or
    /// launch: the session stays where it was. From AWDL, the next try waits `moveRetry`; for
    /// `followBestPath`'s, the plan looks again (its hysteresis; after a move up, longer each time:
    /// DiscoveryPolicy.upWait). A move off the cable gives back what it held to the cable's
    /// connection, whose path may yet come back. A reconnect (the old connection gone) that did not
    /// complete ends the session. Main thread.
    private func moveEnded(_ c: NWConnection) {
        guard let move = moving, move.connection === c else { return }
        moving = nil
        if sessionDead {
            #if DEBUG
            print(move.kind == .toCable ? "path: the reconnect over the cable did not complete, and the old connection is gone: the session ends"
                  : "path: the move to Wi\u{2011}Fi did not complete, and the old connection is gone: the session ends")
            #endif
            endSession()
            return
        }
        if connected { status = "Connected to \(hostName)" }
        switch move.kind {
        case .fromDirect:
            #if DEBUG
            print("discovery: the move did not complete; the session stays direct")
            #endif
            moveToNetworkIfListed()
        case .toCable:
            if let listing = upListing {
                failedUps = (listing, failedUps.map { $0.listing == listing ? $0.count + 1 : 1 } ?? 1)
            }
            #if DEBUG
            print("path: the move to the cable did not complete (\(failedUps?.count ?? 0) in a row); the session stays on Wi\u{2011}Fi")
            #endif
            followBestPath()
        case .toWifi:
            let released = connection.flatMap { link.unhold($0) }
            closeSoon(released?.close ?? [])
            #if DEBUG
            print("path: the move to Wi\u{2011}Fi did not complete; the session stays on the cable (\(released?.held ?? 0) held messages went out on it)")
            #endif
            followBestPath()
        }
    }

    /// Stops a move under way and its timer (a new session, or none), and drops a hand-over still
    /// waiting for its fence, or a hold: what it held belonged to the session that ended. Main thread.
    private func abandonMove() {
        moveCheck?.cancel()
        moveCheck = nil
        if let move = moving {
            moving = nil
            move.connection.cancel()
        }
        for c in link.dropHandOver() { c.cancel() }
    }

    // MARK: Following the best path

    /// Runs DiscoveryPolicy.pathPlan on the session as it stands and acts on it (Noah, 2026-09-25):
    /// a session over Wi-Fi moves to the cable once the network browser has listed its Mac on it for
    /// `cableSettle`, one over the cable moves to Wi-Fi at once when the cable's path is gone, each by
    /// the make-before-break move a session over AWDL takes to the network, and at most once per
    /// `pathHysteresis` each way (up, longer after moves that did not complete, and never again to a
    /// listing of the cable that reached another Mac). A move may start while an earlier hand-over's
    /// fence is still up: SessionLink keeps what waits until every fence is down. Called when the
    /// browsers' results change, when iOS says something of the session connection's path, at the
    /// session's first window list, after a move, and at the plan's own look again. Main thread.
    private func followBestPath() {
        pathCheck?.cancel()
        pathCheck = nil
        guard connected, connection != nil, sessionListed else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let input = pathInput(now: now)
        if let move = moving {
            // A move off the cable whose path has come back meanwhile: the cable works, so the
            // session stays on it, and what waited goes out on it.
            guard move.kind == .toWifi, !sessionDead, !DiscoveryPolicy.pathGone(input) else { return }
            moving = nil
            move.connection.cancel()
            let released = connection.flatMap { link.unhold($0) }
            closeSoon(released?.close ?? [])
            #if DEBUG
            print("path: the cable's path came back: the move to Wi\u{2011}Fi is called off (\(released?.held ?? 0) held messages went out on the cable)")
            #endif
            return
        }
        switch DiscoveryPolicy.pathPlan(input) {
        case .stay(let why, let at):
            #if DEBUG
            if why != lastKept {
                lastKept = why
                print("path: kept: \(why.text)\(at.map { String(format: " (looking again in %.1f s)", $0 - now) } ?? "")")
            }
            #endif
            if let at {
                let work = DispatchWorkItem { [weak self] in self?.followBestPath() }
                pathCheck = work
                DispatchQueue.main.asyncAfter(deadline: .now() + max(0.01, at - now), execute: work)
            }
        case .moveTo(.wired, let interface):
            guard let mac = macs.first(where: { $0.name == hostName && $0.route == .network }), let wired = wiredDial(for: mac) else { return }
            #if DEBUG
            lastKept = nil
            print(input.upFailures > 0 ? "path: the cable is still listed: moving the session to \(interface) again (\(input.upFailures) did not complete)"
                  : "path: the cable appeared: moving the session to \(interface)")
            print("path: dialing \(hostName) on \(wired.via)")
            #endif
            lastMoveUp = now
            upListing = input.wiredSince
            startMove(to: wired.endpoint, kind: .toCable, fallback: nil)
        case .moveTo(.wifi, let interface):
            _ = moveToWifi(interface, now: now, why: "the cable went away: moving to Wi\u{2011}Fi on \(interface)")
        case .reconnectNow(let method, let interface):
            if !reconnectNow(method, interface, now: now) { endSession() }
        case .moveTo(.direct, _):
            break   // never planned: nothing moves a session to Direct
        }
    }

    /// The session as DiscoveryPolicy.pathPlan reads it. Main thread.
    private func pathInput(now: Double) -> DiscoveryPolicy.PathInput {
        let listing = paths.wiredSince[hostName]
        return DiscoveryPolicy.PathInput(now: now, route: connectedDirectly ? .direct : route, dead: sessionDead,
                                         pathReported: pathSignals.reported, pathHinted: pathSignals.hinted, lastPong: lastPongAt,
                                         wired: paths.wired[hostName], wiredSince: listing,
                                         wifi: DiscoveryPolicy.freshWifi(paths, name: hostName, now: now),
                                         lastUp: lastMoveUp, lastDown: lastMoveDown, refusedCable: refusedCable,
                                         upFailures: failedUps.map { $0.listing == listing ? $0.count : 0 } ?? 0,
                                         remote: session?.route.isRemote ?? false)
    }

    /// Moves the session off the cable to Wi-Fi: the Mac's network row, or the last one that listed
    /// it on Wi-Fi while the browser lists none for a moment (DiscoveryPolicy.wifiFresh), dialled on
    /// its Wi-Fi interface (`wifiDial`). From now on what this device sends waits (`holdSends`) and
    /// goes out on the new connection first. False when there is no row to dial. Main thread.
    private func moveToWifi(_ interface: String, now: Double, why: String) -> Bool {
        let listed = macs.first { $0.name == hostName && $0.route == .network && paths.wifi[hostName] != nil }
        guard let mac = listed ?? lastWifiRow[hostName], let old = connection, let dial = wifiDial(for: mac) else { return false }
        #if DEBUG
        lastKept = nil
        print("path: \(why)")
        print("path: dialing \(hostName) on \(dial.via)")
        #endif
        lastMoveDown = now
        holdSends(old)
        startMove(to: dial.endpoint, kind: .toWifi, fallback: dial.fallback)
        return true
    }

    /// Carries a session whose connection has gone on over a new one at once (DiscoveryPolicy's
    /// `reconnectNow`): over the cable again when the browser still lists it and iOS said nothing
    /// of the path (the Mac closed the connection: it evicts a device that stopped reading, one
    /// suspended in the background for 4 s or more, say), dialled as a tap on its Wired row dials
    /// it, the cable first and the row as listed after DiscoveryPolicy.wiredWait or at once when the
    /// cable's dial cannot go on; else to Wi-Fi (`moveToWifi`). A move to Wi-Fi would bring the
    /// session back to the cable 2 s later. False when there is no row to dial. Main thread.
    private func reconnectNow(_ method: DiscoveryPolicy.Method, _ interface: String, now: Double) -> Bool {
        switch method {
        case .wifi:
            return moveToWifi(interface, now: now, why: "the cable went away with the connection: reconnecting over Wi\u{2011}Fi on \(interface) now")
        case .wired:
            guard let mac = macs.first(where: { $0.name == hostName && $0.route == .network }), let wired = wiredDial(for: mac),
                  let fallback = mac.endpoint, let old = connection else { return false }
            #if DEBUG
            lastKept = nil
            print("path: the connection went away, the cable did not: reconnecting over it on \(interface) now")
            print("path: dialing \(hostName) on \(wired.via), then the row as listed")
            #endif
            lastMoveUp = now
            holdSends(old)
            startMove(to: wired.endpoint, kind: .toCable, fallback: fallback)
            return true
        case .direct:
            return false   // never planned
        }
    }

    /// From now on what this device sends waits (SessionLink's hold) for the move that carries the
    /// session on, also past a fence still up from an earlier hand-over. `old` is the session's
    /// connection; were it not, nothing it holds would be sent on it anyway. Main thread.
    private func holdSends(_ old: NWConnection) {
        guard !link.hold(old) else { return }
        #if DEBUG
        print("path: nothing held: the connection moved from is no longer the session's")
        #endif
    }

    /// The session connection, `c`, failed or closed. When it ran over the cable (the plan's
    /// `reconnectNow`), the session is not over: it goes on at once, without the connect screen or
    /// the reconnect's retry timer, over the cable again when the browser still lists it and iOS
    /// said nothing of its path, else over Wi-Fi when the Mac is listed there now or was within
    /// DiscoveryPolicy.wifiFresh (a move to Wi-Fi already under way carries it on), and ends only if
    /// that does not complete (`moveEnded`). False when the ordinary end applies: a remote session
    /// (the plan never moves one; its end is the remote reconnect's), and a connection the Mac said
    /// goodbye on (kind 22: it closed it on purpose, "quit" at home, and the session ends with the
    /// words that goodbye deserves rather than after a dial to a Mac that is going). Main thread.
    private func rescue(from c: NWConnection) -> Bool {
        guard connected, sessionListed, goodbye == nil else { return false }
        let now = ProcessInfo.processInfo.systemUptime
        var input = pathInput(now: now)
        input.dead = true
        guard case .reconnectNow(let method, let interface) = DiscoveryPolicy.pathPlan(input) else { return false }
        sessionDead = true
        if let move = moving {
            if move.kind == .toWifi {
                #if DEBUG
                print("path: the old connection is gone too; the move to Wi\u{2011}Fi under way carries the session")
                #endif
                return true
            }
            moving = nil   // a move to the cable cannot be, over the cable; one from AWDL neither
            move.connection.cancel()
        }
        if reconnectNow(method, interface, now: now) { return true }
        sessionDead = false
        return false
    }

    /// The session connection went back to waiting (any thread): when it is the session's, its path
    /// is gone (DiscoveryPolicy's `pathReported`) until it is ready again (`sessionReadyAgain`).
    private func sessionWaiting(_ c: NWConnection) {
        DispatchQueue.main.async {
            guard self.connected, self.connection === c, !self.pathSignals.waiting else { return }
            self.pathSignals.waiting = true
            #if DEBUG
            print("path: the session's connection is waiting again: its path is gone")
            #endif
            self.followBestPath()
        }
    }

    /// A connection that was ready is ready again, after waiting (any thread): when it is the
    /// session's, its path is back. Nothing else of `.ready` runs again. Main thread from here.
    private func sessionReadyAgain(_ c: NWConnection) {
        DispatchQueue.main.async {
            guard self.connected, self.connection === c, self.pathSignals.waiting else { return }
            self.pathSignals.waiting = false
            #if DEBUG
            print("path: the session's connection is ready again: its path is back")
            #endif
            self.followBestPath()
        }
    }

    /// What a path update of the session connection says of its path: gone when it is not satisfied
    /// (`reported` when it names the Mac's address, only `hinted` when it names the service), back
    /// when it is satisfied (a hint whatever it names; a report only when it names the address). An
    /// update that is satisfied and names only the service says nothing more of the connection
    /// (DiscoveryPolicy.describesFlow). Main thread.
    private func readPath(_ path: NWPath) {
        let before = pathSignals
        let address = Self.namesAddress(path)
        if path.status == .satisfied {
            pathSignals.hinted = false
            if address { pathSignals.unsatisfied = false }
        } else if address {
            pathSignals.unsatisfied = true
        } else {
            pathSignals.hinted = true
        }
        guard pathSignals.reported != before.reported || pathSignals.hinted != before.hinted else { return }
        #if DEBUG
        let interfaces = Self.listed(path.availableInterfaces)
        print("path: iOS says the session's path is \(path.status)\(address ? "" : " (for the service, not the Mac's address)"): \(interfaces)")
        #endif
        followBestPath()
    }

    /// The session connection's viability changed. Not viable: it can neither send nor receive now,
    /// its path is gone (`pathReported`). Main thread.
    private func viabilityChanged(_ viable: Bool) {
        guard pathSignals.notViable == viable else { return }
        pathSignals.notViable = !viable
        #if DEBUG
        print(viable ? "path: the session's connection is viable again" : "path: the session's connection is not viable: its path is gone")
        #endif
        followBestPath()
    }

    /// A pong came back on the session connection at `at` (systemUptime). Main thread.
    private func heardPong(_ at: Double) {
        #if DEBUG
        if pathTest?.muted == true { return }
        #endif
        lastPongAt = max(lastPongAt, at)
    }

    /// Forgets what the session knew of its path (a new session, or none). Main thread.
    private func resetPath() {
        pathCheck?.cancel()
        pathCheck = nil
        pathSignals = PathSignals()
        sessionDead = false
        lastMoveUp = nil
        lastMoveDown = nil
        upListing = nil
        refusedCable = nil
        failedUps = nil
        resumeSource = nil
        #if DEBUG
        lastKept = nil
        #endif
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
    /// the proxy's round trip). `to:HOST:PORT` lists that address, read as `-SillConnect`'s is
    /// (`address(_:)`, so `to:[::1]:P` lists ::1 rather than the name "[::1]", which never
    /// connected): the same host reached another way, so the route can change at the hand-over
    /// (from 127.0.0.1, no word, to this Mac's fe80::…%en0 address, "Wi-Fi"). Main thread.
    private func beginMoveTest(endpoint: NWEndpoint, name: String, mode: String) {
        guard case .hostPort(let host, _) = endpoint, testNetworkRows.isEmpty else { return }
        let listed: NWEndpoint
        if mode == "1" {
            listed = endpoint
        } else if mode == "refused" {
            listed = .hostPort(host: host, port: 1)
        } else if mode.hasPrefix("other:"), let number = UInt16(mode.dropFirst(6)), let port = NWEndpoint.Port(rawValue: number) {
            listed = .hostPort(host: host, port: port)
        } else if mode.hasPrefix("to:"), let address = Self.address(String(mode.dropFirst(3))) {
            listed = address
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

    /// `-SillPathTest '<spec>'` with `-SillConnect HOST:PORT`: the session's Mac is listed as a
    /// network row whose interfaces the test changes, so `followBestPath` runs for real against a
    /// synthetic host (the plan, its timers, the second connection, its first window list, the fence
    /// or the hold, the hand-over). The spec, space-separated: `wifi=HOST:PORT` (the row's endpoint,
    /// where a dial to its Wi-Fi goes) and `cable=HOST:PORT` (where a dial to its cable goes), then
    /// events `SECONDS:WHAT`, counted from the session's first `.ready`: `+cable` (the row gains a
    /// wired interface, anpi0, and a session on the cable has its path back), `-cable` (the row loses
    /// it, and a session on the cable is reported unsatisfied, as iOS reports a pulled cable), `cut`
    /// (the row loses it, and a session on the cable has its connection closed at once, with nothing
    /// reported first), `close` (the session's connection closed at once, the row as it is and
    /// nothing reported: the Mac closing it, as it evicts a device that stopped reading), `-row` (the
    /// row loses it, nothing else), `mute` (the session's pongs stop counting, as over a cable gone
    /// silent), `-wifi` and `+wifi` (the row loses or gains en0). On a Mac with the iPad on its
    /// cable, its own `fe80::…%en14` address reads "Wired" and `fe80::…%en0` "Wi-Fi" (the scope),
    /// so the route word changes at each hand-over as it would. A `cable=` that never answers
    /// (192.0.2.1:9), refuses (127.0.0.1:1), accepts and says nothing, or is another synthetic host
    /// (another launch) makes each move to the cable fail its way. `direct` makes the session count
    /// as one over AWDL (as `-SillMoveTest` does), so the row is where the move from AWDL takes it
    /// once listed for 2 s: behind delay proxies, a move to the cable can then land while that
    /// move's fence is still up.
    struct PathTest {
        static let cableName = "anpi0"
        static let wifiName = "en0"
        let name: String
        let wifi: NWEndpoint
        let cable: NWEndpoint
        var cableListed = false
        var wifiListed = true
        var muted = false

        /// The session's Mac as the network browser would list it now: the cable first, as iPadOS
        /// lists it; nil while it is on neither.
        var row: (name: String, endpoint: NWEndpoint, interfaces: [DiscoveryPolicy.Interface])? {
            var interfaces: [DiscoveryPolicy.Interface] = []
            if cableListed { interfaces.append(DiscoveryPolicy.Interface(name: Self.cableName, type: .wiredEthernet)) }
            if wifiListed { interfaces.append(DiscoveryPolicy.Interface(name: Self.wifiName, type: .wifi)) }
            return interfaces.isEmpty ? nil : (name, wifi, interfaces)
        }
    }

    private func beginPathTest(name: String, spec: String) {
        guard pathTest == nil else { return }
        var wifi: NWEndpoint?, cable: NWEndpoint?
        var events: [(at: Double, what: String)] = []
        var direct = false
        for token in spec.split(separator: " ").map(String.init) {
            if token == "direct" {
                direct = true
            } else if token.hasPrefix("wifi=") {
                wifi = Self.address(String(token.dropFirst(5)))
            } else if token.hasPrefix("cable=") {
                cable = Self.address(String(token.dropFirst(6)))
            } else if let colon = token.firstIndex(of: ":"), let at = Double(token[..<colon]) {
                events.append((at, String(token[token.index(after: colon)...])))
            }
        }
        guard let wifi, let cable else {
            print("path test: needs wifi=HOST:PORT and cable=HOST:PORT")
            return
        }
        pathTest = PathTest(name: name, wifi: wifi, cable: cable)
        print("path test: \(name) listed on \(PathTest.wifiName) (dialled at \(wifi)); its cable dialled at \(cable)")
        if direct {
            connectedDirectly = true
            print("path test: this session counts as direct")
        }
        discoveryChanged()
        for event in events {
            DispatchQueue.main.asyncAfter(deadline: .now() + event.at) { [weak self] in self?.pathTestEvent(event.what) }
        }
    }

    private func pathTestEvent(_ what: String) {
        guard var test = pathTest else { return }
        let onCable = connected && route == .wired
        print("path test: \(what)\(onCable ? " (the session is on the cable)" : "")")
        switch what {
        case "+cable":
            test.cableListed = true
            if onCable { pathSignals.unsatisfied = false }
        case "-cable":
            test.cableListed = false
            if onCable {
                pathSignals.unsatisfied = true
                print("path: iOS says the session's path is unsatisfied (path test)")
            }
        case "cut":
            test.cableListed = false
            if onCable, let c = connection { c.forceCancel() }   // its .cancelled reaches connectionLost
        case "close":
            connection?.forceCancel()   // its .cancelled reaches connectionLost
        case "-row":
            test.cableListed = false
        case "mute":
            test.muted = true
        case "-wifi":
            test.wifiListed = false
        case "+wifi":
            test.wifiListed = true
        default:
            print("path test: unknown event \(what)")
            return
        }
        pathTest = test
        discoveryChanged()   // the row as it is now, then followBestPath
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
    /// the word: a cable pulled mid-session strands the connection instead, and `followBestPath`
    /// moves the session to Wi-Fi, whose connection reads its own word at the hand-over. The same
    /// updates, and the connection's viability, say when its path is gone (`readPath`,
    /// `viabilityChanged`).
    private func followRoute(of c: NWConnection) {
        c.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                guard let self, self.connected, self.connection === c else { return }
                self.setRoute(from: path)
                self.readPath(path)
            }
        }
        c.viabilityUpdateHandler = { [weak self] viable in
            DispatchQueue.main.async {
                guard let self, self.connected, self.connection === c else { return }
                self.viabilityChanged(viable)
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
        resetPath()      // a new session: what an old one knew of its path is moot
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
    /// error says (a message no Sill sends). A session at home whose connection ran over the cable
    /// goes on at once over a new one when it can (`rescue`); otherwise StreamClient+Remote decides
    /// the words and whether and how to reconnect (`endSession`). Any thread.
    func connectionLost(_ c: NWConnection, error: NWError? = nil, end: RemoteDialPolicy.End? = nil) {
        // The direct connection of a move ended before its fence came back: nothing more of it can
        // reach the Mac, so what waited goes out on the network connection now. (A hold is left for
        // the move that carries the session on: SessionLink.release ends fences only.)
        if let released = link.release(c) { fenceEnded(c, released, why: "the direct connection closed") }
        DispatchQueue.main.async {
            guard self.connection === c else { return }   // stale callback from a connection we already replaced
            // A move carries the session on (`rescue`), not when this device closed the connection
            // itself (`end`: a message no Sill sends): that one ends with the words it deserves.
            if self.sessionDead || (end == nil && self.rescue(from: c)) { return }
            self.endSession(error: error, end: end)
        }
    }

    /// The session is over, or a remote dial's winner failed before its window list: the words its
    /// end deserves and the reconnect, the network row, the Direct row, then a saved Mac's
    /// addresses (StreamClient+Remote's `sessionEnded`). From `connectionLost`, and when the move
    /// that was to carry a session whose connection had gone on did not (`moveEnded`,
    /// `followBestPath`). Main thread.
    private func endSession(error: NWError? = nil, end: RemoteDialPolicy.End? = nil) {
        connection = nil
        #if DEBUG
        if connected { print("session: over; back to the connect screen") }
        #endif
        sessionEnded(error: error, end: end)
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
        resetPath()
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
        // After the pointer goes (hiding it re-sends the viewport 200 ms later): nothing of this
        // session's viewport may reach the next connection, which may already be dialling.
        forgetViewport()
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
                // A remote session, and one at home over TLS, is connected at its first window list,
                // not at `.ready`: the Mac has admitted this device's key.
                self.remoteSessionReady()
                self.homeSessionReady()
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
                    self.followBestPath()
                }
                if self.macName != list.macName { self.macName = list.macName; self.loadWindowOrder() }
                let previous = self.active
                self.windows = list.windows
                self.active = list.active
                // Forget thumbnails for windows that are gone.
                let live = Set(list.windows.map(\.id))
                self.thumbnails = self.thumbnails.filter { live.contains($0.key) }
                // The first list after a move without a fence: if the Mac stopped the stream meanwhile,
                // what this device was watching is picked again (`resumeSource`).
                if let resume = self.resumeSource {
                    self.resumeSource = nil
                    if list.active == .none {
                        var pick = resume
                        if case .window(let id) = resume, !list.windows.contains(where: { $0.id == id }) { pick = .desktop }
                        #if DEBUG
                        print("path: nothing streams on the new connection: picking \(pick) again")
                        #endif
                        self.select(pick)
                        return
                    }
                }
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
            // For DiscoveryPolicy.pongSilence: over a cable the browser no longer lists, no pong means
            // no path.
            let at = ProcessInfo.processInfo.systemUptime
            DispatchQueue.main.async { self.heardPong(at) }
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
        // A connection already closed sends nothing, and is not declared lost again at each ping:
        // while a move carries its session on (`rescue`) it stays the session's until the move
        // takes over or ends, and its liveness would otherwise report it lost four times a second.
        // Its own state handler has already reported the close (`connectionLost`).
        switch c.state {
        case .cancelled, .failed: return
        default: break
        }
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
    /// saves anything by itself. If such a connection drops, the reconnect timer looks for it on
    /// Bonjour, never finds it and backs off to 10 s (or, when its kind 18 named a saved Mac, dials
    /// that Mac remotely).
    ///
    /// An address has no TXT record, so `-SillHomeDoor paired|open|plain` says what it counts as
    /// (docs/home-pairing-plan.md §7.9), as a tap on a row with that door: `plain` (the default) a
    /// plain door, as before; `paired` the one saved Mac when exactly one is saved (dialed pinned,
    /// as its row would be; also a later launch), else an unsaved Mac whose door requires pairing
    /// (the ask); `open` that saved Mac, else an unsaved Mac on an open door (any key).
    func connectFromLaunchArgument() {
        guard let raw = UserDefaults.standard.string(forKey: "SillConnect"),
              let address = Self.address(argument: "SillConnect") else { return }
        var trust = DiscoveryPolicy.HomeTrust.plain
        var macID: String?
        if Self.testHomeDoor != .plain {
            let one = savedMacs.count == 1 ? savedMacs[0] : nil
            let decision = DiscoveryPolicy.homeDial(door: Self.testHomeDoor, saved: one != nil, revoked: one?.revoked == true,
                                                    homeTLS: one?.homeTLS == true, debug: true, tap: true)
            print("home: -SillConnect \(raw) counts as a \(Self.testHomeDoor) door\(one.map { " of \($0.name) (saved)" } ?? ""): \(decision)")
            if case .ask(let pinned) = decision {
                startAsk(HomeAsk(target: HomeDialer.Target(endpoint: address, label: raw), name: raw, cableRow: false,
                                 savedID: pinned ? one?.macID : nil, tagNamed: true))
                return
            }
            guard let t = DiscoveryPolicy.sessionTrust(decision, savedPin: one?.fingerprintData) else { return }
            trust = t
            macID = decision == .pinned ? one?.macID : nil
        }
        if let test = Self.wiredTest {
            print("dialing \(raw) on \(test) (wired test)")
            connect(to: test, name: raw, macID: macID, fallback: address, trust: trust)
        } else {
            connect(to: address, name: raw, macID: macID, trust: trust)
        }
    }

    /// `-SillHomeDoor paired|open|plain`: what a `-SillConnect` address, and the rows the move and
    /// path tests list, count as (§7.9). `plain` unless given.
    static var testHomeDoor: DiscoveryPolicy.HomeDoor {
        switch UserDefaults.standard.string(forKey: "SillHomeDoor") {
        case "paired": return .pairingRequired
        case "open": return .open
        default: return .plain
        }
    }

    /// `-SillWiredTest host:port`: the fallback of a wired dial, under test in the simulator against
    /// a synthetic host. `-SillConnect`'s dial, any network row's (each counts as Wired; a Direct or
    /// Remote row's never) and a move's under `-SillMoveTest` go to that address first, the way a
    /// "Wired" row's goes to its cable, with the address they would have dialled as the fallback:
    /// `192.0.2.1:9` (TEST-NET-1, never answers) is given up after DiscoveryPolicy.wiredWait,
    /// `127.0.0.1:1` (nothing listens) at once.
    private static let wiredTest = address(argument: "SillWiredTest")

    /// A `host:port` launch argument as an address (`address(_:)`).
    private static func address(argument key: String) -> NWEndpoint? {
        UserDefaults.standard.string(forKey: key).flatMap(address(_:))
    }

    /// `host:port` as an address (a launch argument's, `-SillPathTest`'s `wifi=` and `cable=`,
    /// `-SillMoveTest`'s `to:`): by the strict address parser, so `[::1]:P` works (a split at the
    /// last colon broke IPv6), else, for what the parser refuses, split at the last colon as
    /// before, so a scoped link-local address works too (`fe80::…%en0:P`: a zone means nothing to a
    /// saved address, which the parser is for, and everything to a test on this Mac's own link).
    private static func address(_ raw: String) -> NWEndpoint? {
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
