import Foundation

/// When the device also looks for Macs over peer-to-peer Wi-Fi (AWDL), how a nearby result is told
/// from a network one, the word each row shows for how its Mac is reachable and the one the
/// Settings panel shows for the session's own connection, which interface a "Wired" row is dialled
/// on, when a reconnect may take a Direct row, and when a session over AWDL moves to the network.
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

    /// How the session's own connection reaches the Mac: the word the Settings panel's readout
    /// ends in (Noah, 2026-09-24), where a row's `method` says where the browser saw the Mac. A
    /// session can run over another link than its row's word (a Wired row's dial is pinned to the
    /// cable, `dialInterface`, but the unconstrained dial it can give way to may take Wi-Fi, and a
    /// session made before the cable came stays on Wi-Fi), so this reads the connection's path:
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

    /// What the network browser has shown of each Mac, by Bonjour name, for the two decisions that
    /// must not trust one moment's view of it.
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
    static func reconnectRow<Row>(network: Row?, direct: Row?, directSince: Double?, networkLeftAt: Double?, now: Double) -> (take: Row?, recheckAt: Double?) {
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

    /// The memory after a state from `mac`: true moves it to the front, false removes it, nil (an
    /// older host) keeps the list; capped at `memoryCap`; an empty name changes nothing.
    static func remember(_ list: [String], mac: String, directWireless: Bool?) -> [String] {
        guard !mac.isEmpty, let on = directWireless else { return list }
        var next = list.filter { $0 != mac }
        if on { next.insert(mac, at: 0) }
        return Array(next.prefix(memoryCap))
    }
}
