import Foundation

/// When the device also looks for Macs over peer-to-peer Wi-Fi (AWDL), how a nearby result is told
/// from a network one, the word each row shows for how its Mac is reachable and the one the
/// Settings panel shows for the session's own connection, which interface a "Wired" row is dialled
/// on, when a reconnect may take a Direct row, when a session over AWDL moves to the network,
/// when a live session at home moves to the cable that came or off the one that went (`pathPlan`),
/// and, for the Macs this device paired with, when they show as Remote rows and when a lost one is
/// dialed away from home; at home, what a row of a Mac whose door speaks TLS says and what a tap
/// on it does, whether a connection runs over the USB cable as this device sees it, the key each
/// connection of a session at home is pinned to and what its end means, what the Mac's answer to
/// an ask means, where a pairing link goes, and the words for all of it.
/// AWDL takes the radio off its Wi-Fi channel (CLAUDE.md, trackpad stutter), so the device asks for
/// it only when a Mac it has seen with Direct Wireless Connection on is missing from the network,
/// or when the user taps Search Nearby, never while connected, and leaves it once the network lists
/// that Mac again.
///
/// Pure logic, Foundation only: it is checked on its own with swiftc (H13 in
/// docs/direct-wireless-plan.md), and StreamClient feeds it what its two browsers see.
enum DiscoveryPolicy {
    /// A Mac on the LAN answers mDNS well within this: the network gets the first word, so at home
    /// the nearby search never starts.
    static let networkFirst = 3.0
    /// Macs remembered with Direct Wireless on, most recent first.
    static let memoryCap = 16

    // An automatic reconnect and a direct session, against a network view that blinks. What the
    // network browser lists at one moment is not enough to choose AWDL on: turning Direct Wireless
    // on or off replaces the Mac's listener, which drops its Bonjour registration and makes it
    // again 1.5 s later, so its network row can go for a few seconds (the goodbye, the new
    // registration, and the announcement's own delay and loss); multicast on Wi-Fi is lost to a
    // dozing or hopping radio; and a Mac back on the network registers there and over AWDL
    // together, the nearby browser sometimes first. On 2026-09-24 the iPad twice reconnected over
    // AWDL at home (15:37:25 and 15:43:17, 23 s and 12 s after the Mac dropped its Wi-Fi
    // connection), which happens only while the network browser lists no such Mac, and stayed on
    // AWDL for minutes: rtt ~75 ms typical, the worst of each report ~265 ms typical and up to 2.4 s.

    /// An automatic reconnect takes a Direct row only once it has stayed Direct this long: past a
    /// listener swap's blink and a lost announcement or two (mDNS repeats an announcement 1 s later,
    /// then at doubling intervals).
    static let directWait = 6.0
    /// Nor within this long of the network browser last listing that Mac: a Mac the network listed
    /// moments ago is taken to be coming back there.
    static let networkGrace = 10.0
    /// After the Mac said it quit (goodbye `quit`), a row listed since before the goodbye is left
    /// alone for this long (`reconnectRow`): it is the registration that is going. A receiver keeps
    /// a record about 1 s past its goodbye packet (RFC 6762 §10.1), so the row outlives the
    /// connection, which closes at once (a stand-in for Sill.app's Quit, browsed on the Mac itself:
    /// the row went 1.05–1.22 s after the connection ended, 11 of 11). After this long such a row
    /// counts as usual: a Sill relaunched within that second renews the record, so its row never
    /// leaves, and a goodbye packet can be lost.
    static let quitWait = 3.0
    /// A session over AWDL moves to the network once the network has listed the same Mac this long
    /// without a break (a blink restarts it).
    static let moveAfter = 2.0
    /// After a move that did not complete (its last network connection failed, had not shown its
    /// host within 5 s, or reached another Mac; a move to a row that says Wired tries its wired
    /// interface first, StreamClient.move), the wait before the next try, counted from the
    /// move's start.
    static let moveRetry = 10.0

    struct Input: Equatable {
        /// ProcessInfo.systemUptime.
        var now: Double
        /// A connection is ready, over either route.
        var connected: Bool
        /// The names the network browser lists.
        var onNetwork: Set<String>
        /// Macs whose last state on this device said Direct Wireless is on.
        var remembered: Set<String>
        /// Launch, or the last connection ending.
        var searchingSince: Double
        /// Search Nearby tapped since the last connection.
        var askedNearby: Bool
        /// The nearby browser runs; sticky until a connection is ready.
        var nearbyRunning: Bool
        /// Rows on the connect screen.
        var listed: Int
        /// The network browser reports Local Network access denied. Every Bonjour browse is then
        /// refused, the nearby one too (TN3179), so there is nothing to look for, and the hint's
        /// advice about the network would send the user to the wrong fix: the status line says what
        /// to do instead.
        var localNetworkDenied = false
    }

    struct Output: Equatable {
        var browseNearby: Bool
        /// The hint sentence; its Search Nearby button shows only while `!browseNearby`.
        var showHint: Bool
        /// When to decide again (the network's 3 s mark), or nil when nothing changes by itself.
        var recheckAt: Double?
    }

    static func decide(_ i: Input) -> Output {
        if i.connected || i.localNetworkDenied { return Output(browseNearby: false, showHint: false, recheckAt: nil) }
        let due = i.searchingSince + networkFirst
        let missing = !i.remembered.subtracting(i.onNetwork).isEmpty
        // Sticky once started: rows found nearby must not vanish because another Mac turned up.
        let browse = i.askedNearby || i.nearbyRunning || (missing && i.now >= due)
        return Output(browseNearby: browse, showHint: i.listed == 0 && i.now >= due,
                      recheckAt: i.now < due ? due : nil)
    }

    /// awdl0 and llw0 report the interface type .wifi like en0; only the name tells them apart.
    static func isPeerToPeer(_ interfaceName: String) -> Bool {
        interfaceName.hasPrefix("awdl") || interfaceName.hasPrefix("llw")
    }

    /// The connect screen's rows, in order: every network name (reached over the network even when
    /// the nearby browser sees it too), then each nearby name seen on peer-to-peer interfaces alone.
    /// A nearby result also on a network interface is left out: the network browser lists it a
    /// moment later, and a Mac at home must never be reached over AWDL (an automatic reconnect
    /// waits for that moment: `reconnectRow`). One with no interface reported is left out too:
    /// nothing says it is direct.
    static func rows(network: [String], nearby: [(name: String, interfaces: [String])]) -> [(name: String, direct: Bool)] {
        var seen = Set<String>()
        var out: [(name: String, direct: Bool)] = []
        for name in network where seen.insert(name).inserted {
            out.append((name, false))
        }
        for n in nearby where !n.interfaces.isEmpty && n.interfaces.allSatisfy(isPeerToPeer) && seen.insert(n.name).inserted {
            out.append((n.name, true))
        }
        return out
    }

    /// An interface a Bonjour result was seen on, as NWInterface gives it: its name (en0, awdl0) and
    /// its type, spelled here so that this file needs Foundation only (StreamClient maps
    /// NWInterface.InterfaceType case for case, a type newer than this code as `other`).
    struct Interface: Equatable {
        enum Kind: Equatable { case wifi, wiredEthernet, cellular, loopback, other }
        var name: String
        var type: Kind
    }

    /// How a row's Mac is reachable: the one word at the end of its row.
    enum Method: Hashable {
        case wired, wifi, direct

        var word: String {
            switch self {
            case .wired: return "Wired"
            case .wifi: return "Wi\u{2011}Fi"   // a non-breaking hyphen: never "Wi-" and "Fi" on two lines
            case .direct: return "Direct"
            }
        }

        /// The order a session prefers its paths in (`pathPlan`): the cable over Wi-Fi over Direct.
        var rank: Int {
            switch self {
            case .wired: return 2
            case .wifi: return 1
            case .direct: return 0
            }
        }
    }

    /// A row's method, from the interfaces its own browser saw its Mac on (Noah, 2026-09-24). A
    /// Direct row is Direct: seen over peer-to-peer Wi-Fi alone, the one kind connected with it. A
    /// network row takes the best of the network browser's interfaces: Wired for a wired Ethernet
    /// one (an Ethernet adapter, and the USB cable to the Mac, whose ends iPadOS names anpi0 and en2
    /// and types so, 2026-09-25: the DEBUG console's "discovery:" lines show what it reports),
    /// else Wi-Fi for a Wi-Fi one that is not peer-to-peer (awdl0 and llw0 report .wifi too), else
    /// nothing: a VPN, loopback, cellular, a type this code does not know, or no interface
    /// reported. A row says nothing rather than something it cannot tell. A Mac seen on several
    /// paths shows one word, Wired over Wi-Fi over Direct: a Mac the network lists is a network
    /// row (`rows`), so a network row is never Direct, whatever the nearby browser sees (its tap
    /// connects without peer-to-peer), and the nearby browser only ever makes Direct rows. The
    /// word names the kind of link, never the Wi-Fi network: reading the network's name (SSID)
    /// needs the Access Wi-Fi Information entitlement and Location access, and Sill asks for
    /// neither.
    static func method(direct: Bool, interfaces: [Interface]) -> Method? {
        if direct { return .direct }
        let network = interfaces.filter { !isPeerToPeer($0.name) }
        if network.contains(where: { $0.type == .wiredEthernet }) { return .wired }
        if network.contains(where: { $0.type == .wifi }) { return .wifi }
        return nil
    }

    /// A wired dial (`dialInterface`) not ready within this long is cancelled, and the row dialled
    /// unconstrained instead, once; one that cannot go on (it fails, or waits) gives way at once.
    /// Over the cable one was ready in 8–134 ms (Noah's iPad, 2026-09-25).
    static let wiredWait = 2.5

    /// The interface a row's Mac is dialled on, by a tap, an automatic reconnect or a session's move
    /// to the network (Noah, 2026-09-25: a row that says Wired connects over the cable): the first
    /// wired Ethernet interface its browser saw it on, so exactly when `method` says Wired, else nil,
    /// and the row is dialled as listed, the system picking the link. Unconstrained, with the cable
    /// and Wi-Fi both up, the same tap went either way (the Mac saw the iPad on %en0 at 7 ms, or on
    /// %en14 at 1 ms). Over the cable iPadOS lists the Mac on anpi0 and en2, both wired Ethernet,
    /// and either reaches it at 1–2 ms (the Mac sees %anri0 or %en14). A Direct row never: it is
    /// dialled peer-to-peer, as listed.
    static func dialInterface(direct: Bool, interfaces: [Interface]) -> String? {
        guard !direct else { return nil }
        return interfaces.first { $0.type == .wiredEthernet && !isPeerToPeer($0.name) }?.name
    }

    /// The interface a network row's Mac is dialled on when a session over the cable loses it
    /// (`pathPlan`'s move to Wi-Fi): the first Wi-Fi interface its browser saw it on that is not
    /// peer-to-peer (awdl0 and llw0 report .wifi too), nil for none and for a Direct row. Pinned
    /// there, as a Wired row's dial is pinned to the cable, rather than dialled as listed while
    /// what the system knows of the Mac may still include the cable that just went.
    static func wifiInterface(direct: Bool, interfaces: [Interface]) -> String? {
        guard !direct else { return nil }
        return interfaces.first { $0.type == .wifi && !isPeerToPeer($0.name) }?.name
    }

    /// How the session's own connection reaches the Mac: the word the Settings panel's readout
    /// ends in (Noah, 2026-09-24), where a row's `method` says where the browser saw the Mac. A
    /// session can run over another link than its row's word (a Wired row's dial is pinned to the
    /// cable, `dialInterface`, but the unconstrained dial it can give way to may take Wi-Fi, and a
    /// session made before the cable came is on Wi-Fi until it moves, `pathPlan`), so this reads
    /// the connection's path:
    /// the interface the Mac's address is scoped to when it is a link-local one, which is all the
    /// USB cable and AWDL carry (over the cable this device sees the Mac's address on en2, and the
    /// Mac logs the device's on en14 or anri0; over AWDL the Mac logs "fe80::…%awdl0"), else the
    /// path's interfaces when they all say the same, else nothing: the simulator's path to its own
    /// Mac lists lo0 alone, and a word for a path that says two things would be a guess. Which
    /// readings count, and this device's own address as a witness between the two: `sessionRoute`.
    /// The Mac's card names its own side by the same rule (ClientLink.route), so the two can
    /// differ: this device on Wi-Fi, the Mac on Ethernet.
    static func route(scope: Interface?, path: [Interface]) -> Method? {
        if let scope { return method(of: scope) }
        let each = path.map(method(of:))
        guard let first = each.first, each.allSatisfy({ $0 == first }) else { return nil }
        return first
    }

    /// Whether a reading of the session connection's path describes that connection, and so may
    /// change the session's word (`sessionRoute`): the reading taken when the connection becomes
    /// ready or takes a move's session over (`fresh`) always does, a later path update only when it
    /// is satisfied and names the Mac by its IP address. A connection to a Bonjour row also gets
    /// updates that describe the service's resolution instead: they name the service, not an
    /// address, and list the interfaces it resolves on, each twice, "en0 (wifi), en0 (wifi)" (the
    /// device's default route) after the connection is ready (Noah's iPad, 2026-09-25). That day,
    /// on the cable with Wi-Fi on, the first reading said Wired (the Mac's address on en2) and such
    /// updates then made it Wi-Fi, while the connection stayed on en2 for its whole life (the Mac
    /// saw it on en14 at 1–3 ms throughout). An update naming nothing is ignored the same way.
    static func describesFlow(fresh: Bool, hasAddress: Bool, satisfied: Bool) -> Bool {
        fresh || (hasAddress && satisfied)
    }

    /// The session's word after one reading of its connection's path: `current` when the reading
    /// does not describe the connection (`describesFlow`), else `route` over it whatever `current`
    /// was (a move's hand-over replaces the direct connection's word, with none if it must). The
    /// witness is the interface the Mac's address is scoped to, else the one this device's own
    /// address is on (`local`: an IPv4 connection's remote address carries no scope), else the
    /// path's interfaces.
    static func sessionRoute(current: Method?, scope: Interface?, local: Interface?, path: [Interface], describesFlow: Bool) -> Method? {
        guard describesFlow else { return current }
        return route(scope: scope ?? local, path: path)
    }

    /// One interface's word: Direct for peer-to-peer Wi-Fi (by name: awdl0 and llw0 report .wifi),
    /// Wired for wired Ethernet (the USB cable to the Mac, which iPadOS names anpi0 and en2, and an
    /// adapter), Wi-Fi for the rest of Wi-Fi, and nothing for loopback, cellular, a VPN or an
    /// unknown type.
    static func method(of interface: Interface) -> Method? {
        if isPeerToPeer(interface.name) { return .direct }
        switch interface.type {
        case .wiredEthernet: return .wired
        case .wifi: return .wifi
        case .cellular, .loopback, .other: return nil
        }
    }

    /// When each Direct row was first seen as one: kept for a row that is still Direct, `now` for a
    /// new one, dropped for one that is gone or that the network lists now, so a row that comes
    /// back Direct starts again.
    static func directSince(_ previous: [String: Double], rows: [(name: String, direct: Bool)], now: Double) -> [String: Double] {
        var next: [String: Double] = [:]
        for row in rows where row.direct { next[row.name] = previous[row.name] ?? now }
        return next
    }

    /// What the network browser has shown of each Mac, for the decisions that must not trust one
    /// moment's view of it: by Bonjour name for a reconnect's Direct row and the move
    /// (StreamClient.sightings), by Mac ID for a saved Mac's remote dial (StreamClient.savedSightings).
    struct NetworkSightings: Equatable {
        /// Listed now, each since when without a break.
        var since: [String: Double] = [:]
        /// Not listed now: when each was last listed, which is the moment it went. Kept for
        /// `networkGrace`, after which it no longer matters.
        var leftAt: [String: Double] = [:]
    }

    /// The sightings after the network browser's list changed (or was looked at again) at `now`.
    static func sightings(_ previous: NetworkSightings, listed: Set<String>, now: Double) -> NetworkSightings {
        var next = NetworkSightings()
        for name in listed { next.since[name] = previous.since[name] ?? now }
        for name in previous.since.keys where !listed.contains(name) { next.leftAt[name] = now }
        for (name, at) in previous.leftAt where !listed.contains(name) && next.leftAt[name] == nil && now - at < networkGrace {
            next.leftAt[name] = at
        }
        return next
    }

    /// The row an automatic reconnect takes now, or when to look again. The Mac's network row at
    /// once, whenever there is one; its Direct row only once that row has stayed Direct for
    /// `directWait` and the network last listed the Mac at least `networkGrace` ago (never listed:
    /// no wait for it, the café case). Taking the Direct row while the Mac is on the network would
    /// run the session at home over AWDL; if it happens anyway (the network stayed silent longer),
    /// `moveToNetwork` brings the session back. A tap on a Direct row is the user's choice and is
    /// not held back.
    /// After a goodbye `quit` (`quitAt`, the moment the session ended), a row listed since then or
    /// before (`networkSince`, `directSince`) is the Mac's old registration, which outlives the
    /// goodbye by about a second: it is not taken until `quitWait` has passed, so the words "‹Mac›
    /// quit Sill…" stay instead of a dial to a Mac that is going. A row listed again since the quit
    /// (Sill is back) is taken by the rules above.
    static func reconnectRow<Row>(network: Row?, networkSince: Double? = nil, direct: Row?, directSince: Double?, networkLeftAt: Double?,
                                  quitAt: Double? = nil, now: Double) -> (take: Row?, recheckAt: Double?) {
        if let quitAt, now < quitAt + quitWait {
            let fresh = { (since: Double?) -> Bool in since.map { $0 > quitAt } ?? false }
            let choice = reconnectRow(network: fresh(networkSince) ? network : nil, direct: fresh(directSince) ? direct : nil,
                                      directSince: directSince, networkLeftAt: networkLeftAt, now: now)
            let heldBack = (network != nil && !fresh(networkSince)) || (direct != nil && !fresh(directSince))
            guard choice.take == nil, heldBack else { return choice }
            return (nil, min(choice.recheckAt ?? .infinity, quitAt + quitWait))
        }
        if let network { return (network, nil) }
        guard let direct, let since = directSince else { return (nil, nil) }
        var due = since + directWait
        if let left = networkLeftAt { due = max(due, left + networkGrace) }
        return now >= due ? (direct, nil) : (nil, due)
    }

    /// While this device's session runs over AWDL: whether to move it now to the same Mac's network
    /// row, listed since `listedSince` (nil: not listed), or when to look again. Once the network
    /// has listed the Mac for `moveAfter` without a break, and not within `moveRetry` of a try that
    /// did not complete. The device is then on the Mac's network, where AWDL only costs: both
    /// radios leave the channel, and over it the stream's worst rtt per report was ~265 ms
    /// typical against ~11 ms on the LAN with AWDL off. Never again for a listing that turned out
    /// to be another Mac (`refusedListing`, the `listedSince` it had; see `sameHost`): each try
    /// would connect to that Mac and fetch its whole catalog. A new listing (the row went and came
    /// back) is tried afresh.
    static func moveToNetwork(listedSince: Double?, lastAttempt: Double?, refusedListing: Double?, now: Double) -> (move: Bool, recheckAt: Double?) {
        guard let since = listedSince, since != refusedListing else { return (false, nil) }
        var due = since + moveAfter
        if let last = lastAttempt { due = max(due, last + moveRetry) }
        return now >= due ? (true, nil) : (false, due)
    }

    /// Whether the network connection a move opened reaches the host this session runs on: both
    /// window lists carry the same `WindowList.launchID`, a random ID a host picks at launch. The
    /// Bonjour name the move went by cannot tell: two Macs can share one when they share no link
    /// (one reached over AWDL, the other on the network), and mDNS then renames neither. Hosts from
    /// before the ID (nil and nil) are taken at their name, as before; one with and one without are
    /// two hosts.
    static func sameHost(_ session: String?, _ network: String?) -> Bool {
        session == network
    }

    // MARK: Following the best path

    // An established connection keeps the interface it was made on for life: TCP does not move.
    // Noah's tests on 2026-09-25: a session made over Wi-Fi stayed there after he plugged the cable
    // in, until he disconnected and connected again, and one over the cable, unplugged, hung a
    // while, fell to the connect screen and came back over Wi-Fi. A live session now follows the
    // best path its Mac is reachable on, the cable over Wi-Fi over Direct (`Method.rank`), with the
    // make-before-break hand-over of the move from AWDL (StreamClient.followBestPath): up to the
    // cable once the network browser has listed the Mac on it for `cableSettle`, down to Wi-Fi at
    // once when the cable's path is gone. Never from Wi-Fi to Wi-Fi, never off a cable that works
    // (a connection the Mac closed while the cable stays listed is made again over the cable),
    // never off a Direct session but to the network (`moveToNetwork`), never a remote session (only
    // the remote reconnect moves one, and not home: remote access's merge left that for later), and
    // at most one move per `pathHysteresis` each way; a cable listing that reaches another Mac is not
    // tried again, and one whose moves do not complete is tried less and less often (`upWait`).

    /// A wired interface must stay listed this long before a session over Wi-Fi moves to it: a
    /// cable comes up in steps (iPadOS brings up anpi0 and en2, and the Mac's records follow on
    /// each). A move off the cable starts the wait again, for a browser that still lists a cable
    /// whose path is gone.
    static let cableSettle = 2.0
    /// At most one move per this long each way, up to the cable and down to Wi-Fi, counted from the
    /// start of the last move that way: a loose cable cannot make the session flap.
    static let pathHysteresis = 5.0
    /// How long the network browser's last listing of the Mac on Wi-Fi still counts once it is gone:
    /// a Mac's result can drop and come back while the cable's interfaces leave.
    static let wifiFresh = 5.0
    /// Over the cable, once the network browser no longer lists the Mac on a wired interface, a
    /// connection that has brought back no pong for this long has lost its path, whatever iOS says
    /// of it: a ping goes every 0.25 s, and over the cable its pong is back in 1–2 ms.
    static let pongSilence = 1.0
    /// The longest wait between two moves up to one listing of the cable (`upWait`).
    static let upBackoffCap = 60.0

    /// How long after the last move up the next may start, when the last `failures` moves up to this
    /// listing of the cable in a row did not complete (the wired dial not ready within `wiredWait`,
    /// waiting or failing, or no window list within 5 s): `pathHysteresis`, doubled for each, up to
    /// `upBackoffCap` (5, 10, 20, 40, then 60 s). A cable the browser lists but that does not carry
    /// the Mac is then not dialled every 5 s for as long as it stays in; a move up that completes,
    /// or a new listing (the cable out and in again), starts again at `pathHysteresis`.
    static func upWait(failures: Int) -> Double {
        min(pathHysteresis * Double(1 << min(max(failures, 0), 4)), upBackoffCap)
    }

    /// What the network browser has shown of each Mac's paths, by Bonjour name.
    struct PathSightings: Equatable {
        /// Listed on a wired interface now: the first one (`dialInterface`), and since when one has
        /// been listed without a break.
        var wired: [String: String] = [:]
        var wiredSince: [String: Double] = [:]
        /// Listed on Wi-Fi now: the first Wi-Fi interface (`wifiInterface`).
        var wifi: [String: String] = [:]
        /// Not on Wi-Fi now: the interface it was last listed on and the moment it went, kept for
        /// `wifiFresh`.
        var wifiLeft: [String: WifiLeft] = [:]

        struct WifiLeft: Equatable {
            var interface: String
            var at: Double
        }
    }

    /// The sightings after the network browser's list changed (or was looked at again) at `now`:
    /// each name with the interfaces its result lists, the first result of a name counting, as in
    /// `rows`.
    static func pathSightings(_ previous: PathSightings, network: [(name: String, interfaces: [Interface])], now: Double) -> PathSightings {
        var next = PathSightings()
        var seen = Set<String>()
        for entry in network where seen.insert(entry.name).inserted {
            if let wired = dialInterface(direct: false, interfaces: entry.interfaces) {
                next.wired[entry.name] = wired
                next.wiredSince[entry.name] = previous.wiredSince[entry.name] ?? now
            }
            if let wifi = wifiInterface(direct: false, interfaces: entry.interfaces) {
                next.wifi[entry.name] = wifi
            }
        }
        for (name, wifi) in previous.wifi where next.wifi[name] == nil {
            next.wifiLeft[name] = PathSightings.WifiLeft(interface: wifi, at: now)
        }
        for (name, left) in previous.wifiLeft where next.wifi[name] == nil && next.wifiLeft[name] == nil && now - left.at < wifiFresh {
            next.wifiLeft[name] = left
        }
        return next
    }

    /// The Wi-Fi interface a session that lost the cable dials its Mac on: the one the network
    /// browser lists it on now, else the one it listed it on within `wifiFresh`; nil for neither.
    static func freshWifi(_ s: PathSightings, name: String, now: Double) -> String? {
        if let wifi = s.wifi[name] { return wifi }
        if let left = s.wifiLeft[name], now - left.at < wifiFresh { return left.interface }
        return nil
    }

    /// The session as `pathPlan` reads it.
    struct PathInput: Equatable {
        /// ProcessInfo.systemUptime.
        var now: Double
        /// The path the session runs on: its word (`sessionRoute`), and Direct while it is connected
        /// over AWDL; nil when its path does not say, and then it never moves.
        var route: Method?
        /// The session's connection failed or closed.
        var dead = false
        /// iOS says the connection's path is gone: not viable, back to waiting, or a path update
        /// that is not satisfied and names the Mac's address (`describesFlow`'s kind).
        var pathReported = false
        /// A path update that is not satisfied but names the service instead of an address: it
        /// describes the service's resolution (`describesFlow`), so it counts only beside the
        /// network browser's word that the cable is gone.
        var pathHinted = false
        /// When the connection last brought back a pong, or became the session's.
        var lastPong: Double
        /// The session's Mac as the network browser lists it (`PathSightings`): the first wired
        /// interface and since when one has been listed (nil while none is), and the Wi-Fi interface
        /// listed now or within `wifiFresh` (`freshWifi`).
        var wired: String?
        var wiredSince: Double?
        var wifi: String?
        /// When this session's last move up (to the cable; one from AWDL counts, and so does a
        /// reconnect over the cable) and down (to Wi-Fi) started.
        var lastUp: Double?
        var lastDown: Double?
        /// The listing of the cable (its `wiredSince`) a move up found to reach another Mac, or
        /// another launch of Sill: not tried again while it lasts, as `moveToNetwork`'s
        /// `refusedListing`. A new listing (the cable out and in again) is tried afresh.
        var refusedCable: Double? = nil
        /// Moves up to the listing of the cable now listed that did not complete, in a row (`upWait`).
        var upFailures = 0
        /// The session runs through the remote door (a saved Mac dialed away from home): it never
        /// moves here, whatever its path and the browser say, as a Direct session does not; it
        /// moves only by the remote reconnect's rules (StreamClient+Remote), and never home to the
        /// network (docs/remote-access-plan.md).
        var remote = false
    }

    /// Why a session stays on its path, for the DEBUG console's "kept: …".
    enum Keep: Equatable {
        case routeUnknown, direct, remote, cable, cableUnlisted, wifi, cableSettling, upTooSoon, cableFailing, cableRefused, noWifi, downTooSoon, lost

        var text: String {
            switch self {
            case .routeUnknown: return "the session's path is not known"
            case .direct: return "over Direct, the session moves only to the network"
            case .remote: return "a remote session moves only by the remote reconnect"
            case .cable: return "on the cable"
            case .cableUnlisted: return "on the cable, which the network no longer lists; its pongs say it works"
            case .wifi: return "on Wi\u{2011}Fi, and the Mac is on no cable"
            case .cableSettling: return "the cable appeared; waiting for it to settle"
            case .upTooSoon: return "the cable is up, but the last move to it was under 5 s ago"
            case .cableFailing: return "the cable is up, but the last move to it did not complete; the next waits longer"
            case .cableRefused: return "the cable reaches another Mac, or another launch of Sill; not tried again until it is plugged in again"
            case .noWifi: return "the cable went away, and the Mac is not on Wi\u{2011}Fi"
            case .downTooSoon: return "the cable went away, but the last move to Wi\u{2011}Fi was under 5 s ago"
            case .lost: return "Wi\u{2011}Fi's path is gone, and there is no cable"
            }
        }
    }

    enum PathPlan: Equatable {
        /// Keep the session where it is, and look again at `recheckAt` (nil: when something changes).
        case stay(Keep, recheckAt: Double?)
        /// Dial the Mac on `interface` beside the session and hand the session over: up to the
        /// cable with the fence, down to Wi-Fi without one (nothing on the old path comes back).
        case moveTo(Method, interface: String)
        /// The connection is dead, and it ran over the cable: dial the Mac now, not after the
        /// reconnect's retry timer. Over the cable again on `interface` (`.wired`: the browser still
        /// lists it and nothing said its path went, so the Mac closed the connection, the row as
        /// listed as the fallback, as a tap on a Wired row), or on Wi-Fi on `interface` (`.wifi`).
        case reconnectNow(Method, interface: String)
    }

    /// Whether the session connection's path is gone: it is dead, iOS says so (`pathReported`), or,
    /// over the cable, the network browser no longer lists the Mac on a wired interface and either
    /// iOS hints it (`pathHinted`) or no pong has come back for `pongSilence`. A browser that stops
    /// listing a working cable for a moment never takes the session off it: its pongs keep coming.
    static func pathGone(_ i: PathInput) -> Bool {
        if i.dead || i.pathReported { return true }
        guard i.route == .wired, i.wired == nil else { return false }
        return i.pathHinted || i.now - i.lastPong >= pongSilence
    }

    /// What a live session does about its path now (Noah, 2026-09-25): move up to the cable, down to
    /// Wi-Fi, reconnect at once, or stay. Up, from Wi-Fi only, once the cable has been listed for
    /// `cableSettle` (counted again from a move off it) and not within `upWait` of the last move up
    /// (`pathHysteresis`, longer after moves up that did not complete), never to a listing found to
    /// reach another Mac (`refusedCable`); the connection's own state does not matter, as the cable
    /// is better either way, unless it is dead. Down, from the cable only, and only once its path is
    /// gone (`pathGone`), to the Wi-Fi the Mac is listed on now or was within `wifiFresh`, not within
    /// `pathHysteresis` of the last move down. A dead connection over the cable is made again at
    /// once instead: over the cable when the browser still lists it and iOS said nothing of the
    /// path (the Mac closed it: it evicts a device that stops reading, one suspended in the
    /// background, say; over Wi-Fi the session would be back on the cable 2 s later), else over
    /// Wi-Fi. Nothing ever moves a session to Direct or off it (the reconnect and `moveToNetwork`
    /// do), from Wi-Fi to Wi-Fi, or off a cable that works, and nothing here moves a remote session
    /// (`remote`), whatever its path says.
    static func pathPlan(_ i: PathInput) -> PathPlan {
        if i.remote { return .stay(.remote, recheckAt: nil) }
        guard let route = i.route else { return .stay(.routeUnknown, recheckAt: nil) }
        if route == .direct { return .stay(.direct, recheckAt: nil) }
        if !i.dead, Method.wired.rank > route.rank, let wired = i.wired, let since = i.wiredSince {
            if since == i.refusedCable { return .stay(.cableRefused, recheckAt: nil) }
            let settled = max(since, i.lastDown ?? since) + cableSettle
            let due = max(settled, (i.lastUp ?? -.infinity) + upWait(failures: i.upFailures))
            if i.now >= due { return .moveTo(.wired, interface: wired) }
            return .stay(due > settled ? (i.upFailures > 0 ? .cableFailing : .upTooSoon) : .cableSettling, recheckAt: due)
        }
        let gone = pathGone(i)
        if route == .wifi { return .stay(gone ? .lost : .wifi, recheckAt: nil) }
        guard gone else {
            // Over the cable, which the browser no longer lists: its pongs decide, at the silence mark.
            if i.wired == nil { return .stay(.cableUnlisted, recheckAt: i.lastPong + pongSilence) }
            return .stay(.cable, recheckAt: nil)
        }
        if i.dead, !i.pathReported, let wired = i.wired { return .reconnectNow(.wired, interface: wired) }
        guard let wifi = i.wifi else { return .stay(.noWifi, recheckAt: nil) }
        if i.dead { return .reconnectNow(.wifi, interface: wifi) }
        if let last = i.lastDown, i.now < last + pathHysteresis {
            return .stay(.downTooSoon, recheckAt: last + pathHysteresis)
        }
        return .moveTo(.wifi, interface: wifi)
    }

    /// The memory after a state from `mac`: true moves it to the front, false removes it, nil (an
    /// older host) keeps the list; capped at `memoryCap`; an empty name changes nothing.
    static func remember(_ list: [String], mac: String, directWireless: Bool?) -> [String] {
        guard !mac.isEmpty, let on = directWireless else { return list }
        var next = list.filter { $0 != mac }
        if on { next.insert(mac, at: 0) }
        return Array(next.prefix(memoryCap))
    }

    // MARK: Saved Macs away from home (docs/remote-access-plan.md §7.3–7.4)

    /// A saved Mac that no browser lists shows as a Remote row once the network has had this long.
    static let remoteWait = 3.0
    /// After a session ends by itself, automatic remote dials stop this long after the loss.
    static let redialWindow = 120.0
    /// A failed automatic remote dial is tried again after 2, 4, 8, then every 10 s.
    static let remoteRetry: [Double] = [2, 4, 8, 10]

    /// The Remote rows: saved Macs that neither browser lists, in the order given, once the
    /// network has had its `networkFirst` seconds, or at once when Local Network access is denied
    /// (then they are the only route left).
    static func remoteRows(saved: [(macID: String, name: String)], listedIDs: Set<String>, now: Double,
                           searchingSince: Double, localNetworkDenied: Bool) -> [(macID: String, name: String)] {
        guard localNetworkDenied || now >= searchingSince + networkFirst else { return [] }
        return saved.filter { !listedIDs.contains($0.macID) }
    }

    /// Whether an automatic remote dial of a lost saved Mac is due now, or when to look again. Never
    /// while a network or Direct row lists it (the row takes it), never once `redialWindow` has
    /// passed. Due `remoteWait` after the loss (`directWait`, the wait an automatic reconnect gives
    /// a Direct row, for a Mac remembered with Direct Wireless on), and not within `networkGrace` of
    /// the network last listing it, the moment its row went (`NetworkSightings.leftAt`; a Mac the
    /// network listed moments ago is taken to be blinking, not gone) unless this device's path
    /// changed since the loss (it left home, or Wi‑Fi became cellular).
    static func remoteDialDue(listed: Bool, lostAt: Double, networkLeftAt: Double?, rememberedDirect: Bool,
                              pathChangedSinceLoss: Bool, now: Double) -> (dial: Bool, recheckAt: Double?) {
        guard !listed, now < lostAt + redialWindow else { return (false, nil) }
        var due = lostAt + (rememberedDirect ? directWait : remoteWait)
        if !pathChangedSinceLoss, let left = networkLeftAt { due = max(due, left + networkGrace) }
        return now >= due ? (true, nil) : (false, due)
    }

    /// The wait before the next automatic remote dial after `failures` failed ones.
    static func remoteRetryDelay(afterFailures failures: Int) -> Double {
        remoteRetry[min(max(failures, 1), remoteRetry.count) - 1]
    }

    // MARK: Pairing at home (docs/home-pairing-plan.md §7.3–7.5)

    /// A home door as its Bonjour TXT record's `p` says (HomeDoorTXT.Door, spelled here so that this
    /// file needs Foundation only; StreamClient maps it case for case): no `p` is a plain door,
    /// "0" a TLS door open to any device, anything else a TLS door for paired devices only.
    enum HomeDoor: Hashable { case plain, pairingRequired, open }

    /// The saved Mac a network or Direct row is (§7.3): the one its TXT tag names (`tagged`, the
    /// tag this device resolved), else, for a row whose tag names none, the saved Mac last reached
    /// under the row's Bonjour name (`saved`: each saved Mac's ID and that name, most recently used
    /// first), taken by name alone (`tagNamed` false). The automatic reconnect has always taken
    /// such a row as that Mac, dialed pinned to its key; a tap does the same (the security review,
    /// 2026-09-27: a tap dialed a tagless look-alike with any key, or in plain TCP in DEBUG, while
    /// its row read exactly like the paired Mac's). A host always advertises its tag, so a row
    /// under a saved Mac's name without it is a stranger's until its key says otherwise: its pin
    /// then fails (-9808), and nothing of this device reaches it. The price: another Mac of the
    /// same name, reached only while the saved one is not listed, cannot be tapped until the saved
    /// one is forgotten.
    static func rowMac(tagged: String?, name: String, saved: [(macID: String, bonjourName: String?)]) -> (macID: String, tagNamed: Bool)? {
        if let tagged { return (tagged, true) }
        return saved.first { $0.bonjourName == name }.map { ($0.macID, false) }
    }

    /// What a network or Direct row of a Mac at home ends in, and what VoiceOver says for it (§7.3).
    enum RowWord: Hashable {
        /// How the Mac is reachable (`method`), as before: a saved Mac on a TLS door, a plain door
        /// in a DEBUG build. Nil when its interfaces do not say.
        case method(Method?)
        /// Not saved (or it removed this device) and pairing is required: a tap asks, and the Mac
        /// shows a code.
        case notPaired
        /// Not saved, on an open door (`p=0`: the Mac's Require pairing is off): a tap connects
        /// without pairing, with any Mac key. "Not paired" too, so it never reads like a paired
        /// Mac's row (the security review, 2026-09-27: it read "Wi‑Fi" as the paired Mac's did).
        case openDoor
        /// The same over the USB cable: a tap asks, and the Mac pairs this device by itself. Its
        /// word is "Wired".
        case pairsOverCable
        /// No `p`: the Mac's Sill is from before pairing at home, and this build (a Release one, or
        /// one that has seen that Mac over TLS) dials no plain door. Nothing is dialed.
        case updateSill

        /// The word at the end of the row.
        var word: String? {
            switch self {
            case .method(let m): return m?.word
            case .notPaired, .openDoor: return "Not paired"
            case .pairsOverCable: return Method.wired.word
            case .updateSill: return "Update Sill"
            }
        }

        /// VoiceOver's label: "Mac mini, Wired", "Mac mini, not paired"; the name alone without a word.
        func label(name: String) -> String {
            if self == .notPaired || self == .openDoor { return "\(name), not paired" }
            return word.map { "\(name), \($0)" } ?? name
        }

        /// VoiceOver's hint; `device` is this device's kind ("iPad"). A row that says how its Mac
        /// is reachable keeps the hint it had ("" but for a Direct row).
        func hint(name: String, device: String, direct: Bool) -> String {
            switch self {
            case .method: return direct ? "Connects without a shared Wi\u{2011}Fi network" : ""
            case .notPaired: return "Pairs with a code \(name) shows, then connects."
            case .openDoor: return "Connects without pairing: \(name) lets any device in."
            case .pairsOverCable: return "Pairs over the USB cable, then connects."
            case .updateSill: return "\(name)\u{2019}s Sill is too old for this \(device)."
            }
        }
    }

    /// A row's word (§7.3). `saved`: the row is a saved Mac (`rowMac`: its TXT tag named one, or,
    /// without a tag of a saved Mac's, its Bonjour name did); `revoked`: that Mac removed this device or refused
    /// its key (SavedMac.revoked); `homeTLS`: this device has seen that Mac's home door speak TLS
    /// (SavedMac.homeTLS; false for an unsaved Mac); `debug`: a DEBUG build, the only kind that
    /// dials a plain door; `cable`: the row's wired interface carries only link-local addresses on
    /// this device (`carriesOnlyLinkLocal`), which counts only for a row that says Wired.
    static func rowWord(door: HomeDoor, saved: Bool, revoked: Bool, homeTLS: Bool, debug: Bool,
                        method: Method?, cable: Bool) -> RowWord {
        switch door {
        case .plain:
            // No downgrade: once a Mac was seen over TLS, a row of it without `p` is not dialed.
            return debug && !homeTLS ? .method(method) : .updateSill
        case .pairingRequired, .open:
            if saved && !revoked { return .method(method) }
            if !saved && door == .open { return .openDoor }
            return method == .wired && cable ? .pairsOverCable : .notPaired
        }
    }

    /// What a connection to a Mac at home is (§7.4).
    enum HomeDial: Equatable {
        /// `sill/1`, pinned to the saved Mac's key; connected at its first window list.
        case pinned
        /// `sill/1` taking any Mac key: an unsaved Mac on an open door (`p=0`). Nothing is saved.
        case anyKey
        /// The ask (`sill-pair/1`, kind 19 "ask"): pinned to the saved key for a saved Mac that
        /// removed this device (only its trust in this device changed, so no look-alike can answer
        /// and a typed code goes only to the real Mac), else taking any key and remembering it.
        case ask(pinned: Bool)
        /// Plain TCP, as before pairing at home: a DEBUG build, a Mac never seen over TLS.
        case plain
        /// Nothing dialed: the Mac's Sill is too old for this build (`updateSillStatus`).
        case updateSill
        /// Nothing dialed: an automatic reconnect never asks; an ask is a tap's.
        case waitForTap
    }

    /// A tap on a row (`tap`), or an automatic reconnect of it, which follows the same table but
    /// never asks: a saved Mac that removed this device, and an unsaved one that requires pairing,
    /// wait for a tap.
    static func homeDial(door: HomeDoor, saved: Bool, revoked: Bool, homeTLS: Bool, debug: Bool, tap: Bool) -> HomeDial {
        switch door {
        case .plain:
            return debug && !homeTLS ? .plain : .updateSill
        case .pairingRequired, .open:
            if saved { return revoked ? (tap ? .ask(pinned: true) : .waitForTap) : .pinned }
            if door == .open { return .anyKey }
            return tap ? .ask(pinned: false) : .waitForTap
        }
    }

    /// The status line after a tap that dialed nothing because the Mac's Sill is too old.
    static func updateSillStatus(mac: String) -> String {
        "\(mac) runs an older Sill. Update Sill on the Mac to connect."
    }

    /// Whether this device's connection runs over the USB cable to the Mac, as this device sees it
    /// (§7.5): what the ask's `cable: true` says. All of: the Mac's address is IPv6 link-local
    /// (IPv4 never counts, 169.254/16 included, as on the Mac) and scoped to a wired interface
    /// (the iPad saw the Mac on en2, 2026-09-25); it is none of this device's own addresses
    /// (another app here, listening on this device's own en2 address behind a look-alike row,
    /// would otherwise be "the Mac"); and that interface carries no address but link-local ones:
    /// the USB link to a Mac has only those, while a USB Ethernet adapter on the LAN, which iPadOS
    /// also types as wired Ethernet and whose row also says Wired, has the network's DHCP or SLAAC
    /// address, and a look-alike Mac on that LAN could otherwise be pinned without a code. So could
    /// an iPhone sharing its connection over USB, whose end carries 172.20.10.1. `mac` is the
    /// Mac's address (4 or 16 bytes); `scope` the interface it is scoped to; `own` this device's
    /// addresses (getifaddrs), each with its interface.
    static func onCable(mac: [UInt8], scope: Interface?, own: [(interface: String, address: [UInt8])]) -> CableCheck {
        guard mac.count == 16, isLinkLocal(mac) else {
            return CableCheck(cable: false, console: "cable: no, the Mac\u{2019}s address \(addressText(mac)) is not IPv6 link-local")
        }
        guard let scope else {
            return CableCheck(cable: false, console: "cable: no, the Mac\u{2019}s address names no interface")
        }
        guard scope.type == .wiredEthernet, !isPeerToPeer(scope.name) else {
            return CableCheck(cable: false, console: "cable: no, \(scope.name) is not wired Ethernet")
        }
        let m = unscoped(mac)
        guard !own.contains(where: { unscoped($0.address) == m }) else {
            return CableCheck(cable: false, console: "cable: no, \(addressText(mac)) is this device\u{2019}s own address")
        }
        let mine = own.filter { $0.interface == scope.name }.map(\.address)
        guard !mine.isEmpty else {
            return CableCheck(cable: false, console: "cable: no, \(scope.name) has no address")
        }
        if let routable = mine.first(where: { !isLinkLocal($0) }) {
            return CableCheck(cable: false, console: "cable: no, \(scope.name) has \(addressText(routable))")
        }
        return CableCheck(cable: true, console: "cable: yes, \(scope.name) carries only link-local addresses")
    }

    /// `onCable`'s answer, with what it read for the DEBUG console ("cable: yes, en2 carries only
    /// link-local addresses"; "cable: no, en3 has 10.128.0.52").
    struct CableCheck: Equatable {
        var cable: Bool
        var console: String
    }

    /// Whether `interface` carries addresses on this device and only link-local ones: a row that
    /// says Wired over such an interface pairs over the cable (`rowWord`'s `cable`); over a USB
    /// Ethernet adapter on the LAN it does not.
    static func carriesOnlyLinkLocal(_ interface: String, own: [(interface: String, address: [UInt8])]) -> Bool {
        let mine = own.filter { $0.interface == interface }.map(\.address)
        return !mine.isEmpty && mine.allSatisfy(isLinkLocal)
    }

    /// fe80::/10 or 169.254/16; anything but 4 or 16 bytes is not.
    static func isLinkLocal(_ a: [UInt8]) -> Bool {
        if a.count == 4 { return a[0] == 169 && a[1] == 254 }
        if a.count == 16 { return a[0] == 0xFE && a[1] & 0xC0 == 0x80 }
        return false
    }

    /// An IPv6 link-local address without the scope the kernel embeds in bytes 2–3 of the ones
    /// getifaddrs returns; any other address as it is.
    static func unscoped(_ a: [UInt8]) -> [UInt8] {
        guard a.count == 16, isLinkLocal(a) else { return a }
        var b = a
        b[2] = 0; b[3] = 0
        return b
    }

    /// "10.128.0.52", "fe80::1c0f:2a:6e1:9b3": for the console only.
    static func addressText(_ a: [UInt8]) -> String {
        var buffer = [CChar](repeating: 0, count: 64)
        if a.count == 4 {
            var v4 = in_addr()
            withUnsafeMutableBytes(of: &v4) { $0.copyBytes(from: a) }
            return inet_ntop(AF_INET, &v4, &buffer, socklen_t(buffer.count)).map { String(cString: $0) } ?? "?"
        }
        guard a.count == 16 else { return "?" }
        var v6 = in6_addr()
        withUnsafeMutableBytes(of: &v6) { $0.copyBytes(from: unscoped(a)) }
        return inet_ntop(AF_INET6, &v6, &buffer, socklen_t(buffer.count)).map { String(cString: $0) } ?? "?"
    }

    // MARK: Sessions and pairing at home over TLS (docs/home-pairing-plan.md §7.2, §7.5–7.7)

    /// What a session at home trusts, which decides how every connection it opens is dialed (§7.2):
    /// its first, and each move's (from AWDL, up to the cable, down to Wi-Fi, a reconnect over the
    /// cable), so no hop of the session ever lands on another key.
    enum HomeTrust: Equatable {
        /// A plain door (`homeDial`'s `.plain`: a DEBUG build, a Mac never seen with `p`): no TLS.
        case plain
        /// A saved Mac: every connection `sill/1`, pinned to its key.
        case saved(pin: Data)
        /// An unsaved Mac on an open door (`p=0`): the session's first connection takes any key,
        /// and every later one pins the key that one saw (`seen`).
        case open(seen: Data?)

        /// The session speaks TLS: connected at its first window list, not at `.ready`, since with
        /// TLS 1.3 a connection is ready before the Mac has judged this device's key.
        var tls: Bool { self != .plain }
    }

    /// What a new connection of a session checks the Mac's key against (`pin`).
    enum Pin: Equatable {
        /// Plain TCP: no key at all.
        case plainTCP
        /// Any P-256 key.
        case anyKey
        /// This key only.
        case key(Data)
    }

    /// The pin of the session's next connection.
    static func pin(_ trust: HomeTrust) -> Pin {
        switch trust {
        case .plain: return .plainTCP
        case .saved(let pin): return .key(pin)
        case .open(let seen?): return .key(seen)
        case .open(nil): return .anyKey
        }
    }

    /// The session a tap or an automatic reconnect starts (§7.4): the trust `homeDial`'s answer
    /// gives it; nil when that answer dials no session (the ask, a Mac too old for this build, a
    /// reconnect that waits for a tap) or a saved Mac's pin cannot be read.
    static func sessionTrust(_ dial: HomeDial, savedPin: Data?) -> HomeTrust? {
        switch dial {
        case .pinned: return savedPin.map { .saved(pin: $0) }
        case .anyKey: return .open(seen: nil)
        case .plain: return .plain
        case .ask, .updateSill, .waitForTap: return nil
        }
    }

    /// The trust once the session's first connection is ready: an open session keeps the key that
    /// connection saw for the rest of the session. Any other trust, and an open session that has
    /// seen a key already, is unchanged.
    static func trust(_ trust: HomeTrust, readyWith fingerprint: Data?) -> HomeTrust {
        if case .open(nil) = trust, let fingerprint { return .open(seen: fingerprint) }
        return trust
    }

    /// How a session at home ended (§7.6), from its trust, the goodbye the Mac sent (Goodbye's
    /// `reason`: "removed", "pairingRequired"…) and the TLS status its end carried.
    enum HomeEnd: Equatable {
        /// The Mac removed this device: goodbye `removed`, or a saved Mac's key refused right after
        /// `.ready` (-9825, -9829). The saved Mac is revoked, nothing reconnects, and a tap asks.
        case removed
        /// Require pairing turned on while this unpaired device was connected: goodbye
        /// `pairingRequired`, or an open session's key refused (its TXT record was stale). Nothing
        /// reconnects; the row reads Not paired once the Mac's new record arrives.
        case pairingRequired
        /// Another key answered as the saved Mac (-9808: this device's pin refused it): the other
        /// rows its tag names are dialed, pinned, before any words; never a plain retry.
        case wrongKey
        /// Anything else: the words and the reconnect as before.
        case other
    }

    /// The Mac refused this device's key (-9825), or its certificate (-9829).
    static let keyRefused: Set<Int32> = [-9825, -9829]
    /// This device's pin refused the Mac's key.
    static let pinRefused: Int32 = -9808

    static func homeEnd(trust: HomeTrust?, goodbye: String?, tls: Int32?) -> HomeEnd {
        guard let trust, trust.tls else { return .other }   // a remote session, or a plain door (no keys)
        if goodbye == "removed" { return .removed }
        if goodbye == "pairingRequired" { return .pairingRequired }
        guard goodbye == nil, let tls else { return .other }
        switch trust {
        case .saved:
            if keyRefused.contains(tls) { return .removed }
            return tls == pinRefused ? .wrongKey : .other
        case .open:
            return keyRefused.contains(tls) ? .pairingRequired : .other
        case .plain:
            return .other
        }
    }

    /// After a pinned dial of a saved Mac failed its pin (-9808): the next row to dial, pinned,
    /// among the rows its TXT tag names (`rows`: each row's id and the saved Mac its tag named), in
    /// the connect screen's order, leaving out those tried; nil once none is left (§7.6). A stranger
    /// replaying the Mac's tag makes a row that looks like it, so the words that tell the user to
    /// forget the Mac wait until every such row has failed.
    static func nextPinnedRow(macID: String, tried: [String], rows: [(id: String, macID: String?)]) -> String? {
        rows.first { $0.macID == macID && !tried.contains($0.id) }?.id
    }

    /// What the device makes of the Mac's answer to its ask (kind 20, §7.5).
    enum AskAnswer: Equatable {
        /// Paired by itself over the USB cable: an ok without a proof, `method` "cable", to an ask
        /// that said `cable: true`, naming the key this connection saw (its Mac ID), with a 32-byte
        /// recognition key. Nothing else ever pairs without a proof.
        case pairedOverCable
        /// The Mac shows its code now: the home card, to scan it or type it.
        case shown
        /// The Mac showed no code by itself: choose Pair iPhone or iPad… on the Mac.
        case openOnMac
        /// The Mac is locked.
        case locked
        /// Busy: one silent retry, after this many seconds.
        case busy(Double)
        /// Any other refusal, or a reason this build does not know: as `openOnMac`.
        case refused
        /// An ok this device does not take (no cable claimed, a proof it cannot check, another Mac
        /// ID, no recognition key): nothing is saved ("Pairing didn't finish…").
        case invalid
    }

    static func askAnswer(ok: Bool, method: String?, hasProof: Bool, reason: String?, retryAfter: Double?,
                          askedCable: Bool, macIDMatches: Bool, recognitionKeyBytes: Int?) -> AskAnswer {
        if ok {
            guard method == "cable", askedCable, !hasProof, macIDMatches, recognitionKeyBytes == 32 else { return .invalid }
            return .pairedOverCable
        }
        switch reason {
        case "shown"?: return .shown
        case "openOnMac"?: return .openOnMac
        case "locked"?: return .locked
        case "busy"?: return .busy(min(max(retryAfter ?? 1, 0.2), 10))
        default: return .refused
        }
    }

    /// What the home card says for a proof the Mac refused (kind 20's `reason`, §7.7). The words
    /// follow what the Mac does next (AskLimits, PairingWindow.closedReason): a window the Mac's
    /// user cancelled, or one five wrong codes stopped, keeps this device quiet for 10 minutes, so a
    /// tap alone would get no new code, and those words send the person to the Sill menu on the Mac
    /// first ("stopped"; "closed", which is also a code another device used, where the menu's way
    /// works as well). A window that ran out quiets nobody, so "tap it for a new one" holds
    /// ("expired"). Anything else ("busy" a second time, or a reason this build does not know that
    /// came without the Mac's own words) reads as "closed".
    enum HomeRefusal: Equatable {
        case wrongCode(triesLeft: Int)
        case stopped
        case expired
        case closed
    }

    static func homeRefusal(reason: String?, triesLeft: Int?) -> HomeRefusal {
        switch reason {
        case "code"?: return .wrongCode(triesLeft: max(0, triesLeft ?? 0))
        case "stopped"?: return .stopped
        case "expired"?: return .expired
        default: return .closed
        }
    }

    /// Where a pairing link goes at home (§7.5): nil for the connection the ask reached, when the
    /// link's key is the one that connection saw (`askedKey`); else every home row with `p`, in the
    /// connect screen's order, each to be dialed pinned to the link's key, one at a time (the Mac
    /// whose code it is answers; a look-alike that answered the ask cannot), leaving out the asked
    /// row, whose key is known to be another. None answering, the link's own addresses follow (the
    /// caller's). `rows`: each row's id and door.
    static func linkRows(linkKey: Data, askedKey: Data?, askedRow: String?, rows: [(id: String, door: HomeDoor)]) -> [String]? {
        if let askedKey, askedKey == linkKey { return nil }
        return rows.filter { $0.door != .plain && !(askedKey != nil && $0.id == askedRow) }.map(\.id)
    }

    /// Whether a kind 18 whose signature checked, signed by `signer`, speaks for this session's Mac
    /// (§7.6): only when that is the key the connection it came on showed in its TLS handshake
    /// (`connectionKey`; nil on a plain connection). Only then may it name the session's Mac, make
    /// the panel say "Paired", or refresh or rename a saved Mac. Its signature alone proves only
    /// that the Mac signed it once: a Mac hands its kind 18 to every session (an open door's
    /// included, and in plaintext at a plain door), so another Mac can replay it on a connection of
    /// its own (the security review, 2026-09-27).
    static func macInfoNamesSession(signer: Data, connectionKey: Data?) -> Bool {
        connectionKey == signer
    }

    /// Whether goodbye "removed" (or a saved Mac's key refused right after `.ready`) revokes the
    /// saved Mac whose key is `savedKey` (§7.6): only from a session that Mac's own key answered, a
    /// remote one (always pinned to it) or one at home whose connections are pinned to it
    /// (`pin(trust)`). Never from a plain session, which has no key, nor from an open one that saw
    /// another key: a look-alike's goodbye must not revoke the real Mac.
    static func removalRevokes(remote: Bool, trust: HomeTrust?, savedKey: Data?) -> Bool {
        guard let savedKey else { return false }
        if remote { return true }
        guard let trust else { return false }
        return pin(trust) == .key(savedKey)
    }

    /// The Settings panel's last group, Away from home (§7.6): "Paired" for a Mac this device saved,
    /// with how it is reached from afar under it; else Pair This iPad… wherever a pairing can start.
    enum AwayFromHome: Equatable {
        /// This device saved this Mac (its kind 18 verified against the saved key): "Paired".
        case paired(PairedReach)
        /// Not saved: Pair This iPad…. `atHome`: over a session at home that speaks TLS, which
        /// pairs at that session's own door whatever the Mac's Remote Access says (such a session
        /// is unpaired only while the Mac lets any device in: Require pairing off); otherwise over
        /// a plain one, through the remote door, which needs Remote Access on.
        case pairThisDevice(atHome: Bool)
        /// Not saved, over a plain session, with Remote Access off: nothing to pair with; how to
        /// turn it on.
        case turnOnRemoteAccess

        /// What the footnote under "Paired" says.
        enum PairedReach: Equatable {
            /// This session came through the remote door: "Connected through Tailscale."
            case connected
            /// "Away from home, Sill reaches Mac mini through Tailscale (…)."
            case reaches
            /// Remote Access is off on the Mac: how to turn it on (a Mac paired at home).
            case turnOnRemoteAccess
        }
    }

    /// `saved`: this session's Mac is one this device saved; `remoteSession`: the session came
    /// through the remote door; `remoteAccess`: the Mac's kind 18 says Remote Access is on;
    /// `tlsAtHome`: the session runs at home over TLS.
    static func awayFromHome(saved: Bool, remoteSession: Bool, remoteAccess: Bool, tlsAtHome: Bool) -> AwayFromHome {
        if saved { return .paired(remoteSession ? .connected : remoteAccess ? .reaches : .turnOnRemoteAccess) }
        if tlsAtHome && !remoteSession { return .pairThisDevice(atHome: true) }
        return remoteAccess ? .pairThisDevice(atHome: false) : .turnOnRemoteAccess
    }

    /// The connect screen's words for pairing and sessions at home (§7.7). `mac` is what the row
    /// calls the Mac; `device` this device's kind ("iPad").
    enum HomeCopy {
        static func pairing(mac: String, cable: Bool) -> String {
            cable ? "Pairing with \(mac) over the cable\u{2026}" : "Pairing with \(mac)\u{2026}"
        }
        static func pairedOverCable(mac: String) -> String { "Paired with \(mac) over the cable." }
        /// The status line while the home card is up, and the card's scan line.
        static func showing(mac: String, device: String) -> String { "\(mac) is showing a code. Point this \(device) at it." }
        /// The home card (§7.7): its title, a heading; its typed path's line, which is also the
        /// line it collapses to while the code has the keyboard; the viewfinder's caption, and
        /// what VoiceOver says for the viewfinder.
        static func cardTitle(mac: String) -> String { "Pair with \(mac)" }
        static func typeCode(mac: String) -> String { "Type the code \(mac) shows." }
        static func viewfinderCaption(mac: String) -> String { "Point at the code on \(mac)" }
        static func viewfinderLabel(mac: String) -> String { "Camera. Point it at the code on \(mac)." }
        /// Pair This iPad… over a session at home that needs no pairing (the Settings panel's
        /// footnote, `AwayFromHome.pairThisDevice(atHome: true)`).
        static func pairThisDeviceAtHome(mac: String, device: String) -> String {
            "\(mac) lets devices connect without pairing. Pair this \(device) once to keep connecting if that changes, and to reach \(mac) away from home while Remote Access is on. \(mac) shows a code; scan it with this \(device)."
        }
        /// Pair This iPad…'s errors over a stream at home, where no row can be tapped: the Mac
        /// could not prove it knows the code; nothing answered the pairing connection. (A refused
        /// code says what the remote path's does: choose Pair iPhone or iPad… on the Mac.)
        static func proofFailedOverStream(mac: String) -> String {
            "Pairing didn\u{2019}t finish: \(mac) couldn\u{2019}t show it knows the code."
        }
        static func noAnswerOverStream(mac: String) -> String { "\(mac) didn\u{2019}t answer. Try again." }
        static func openOnMac(mac: String) -> String {
            "\(mac) didn\u{2019}t show a code. On the Mac, choose Pair iPhone or iPad\u{2026} in the Sill menu, then tap \(mac) again."
        }
        static func locked(mac: String) -> String { "Unlock \(mac), then tap it again." }
        static func removed(mac: String, device: String) -> String { "\(mac) removed this \(device). Tap it to pair again." }
        static func pairingRequired(mac: String, device: String) -> String {
            "\(mac) now asks devices to pair. Tap it to pair this \(device)."
        }
        /// The home card's errors, under its field or in its place (`homeRefusal`). After a stop
        /// or a closed code the Mac keeps this device quiet (a cancel on the Mac, a stop), so the
        /// words send the person to its menu first; after an expiry a tap is enough.
        static func stopped(mac: String) -> String {
            "\(mac) stopped pairing after too many wrong codes. On the Mac, choose Pair iPhone or iPad\u{2026} in the Sill menu, then tap \(mac) again."
        }
        static func expired(mac: String) -> String { "That code expired. Tap \(mac) for a new one." }
        static func closed(mac: String) -> String {
            "That code no longer works. On the Mac, choose Pair iPhone or iPad\u{2026} in the Sill menu, then tap \(mac) again."
        }
        static func proofFailed(mac: String) -> String {
            "Pairing didn\u{2019}t finish: \(mac) couldn\u{2019}t show it knows the code. Tap it to try again."
        }
        /// Nothing answered the ask or a proof at the row (it went, or Sill quit meanwhile).
        static func noAnswer(mac: String) -> String { "\(mac) didn\u{2019}t answer. Check that Sill is open on it, then tap it again." }
    }
}
