import Foundation

/// When the device also looks for Macs over peer-to-peer Wi-Fi (AWDL), how a nearby result is told
/// from a network one, and when a reconnect may take one. AWDL takes the radio off its Wi-Fi
/// channel (CLAUDE.md, trackpad stutter), so the device asks for it only when a Mac it has seen
/// with Direct Wireless Connection on is missing from the network, or when the user taps Search
/// Nearby, and never while connected.
///
/// Pure logic, Foundation only: it is checked on its own with swiftc (H13 in
/// docs/direct-wireless-plan.md), and StreamClient feeds it what its two browsers see.
enum DiscoveryPolicy {
    /// A Mac on the LAN answers mDNS well within this: the network gets the first word, so at home
    /// the nearby search never starts.
    static let networkFirst = 3.0
    /// Macs remembered with Direct Wireless on, most recent first.
    static let memoryCap = 16

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

    /// When each Direct row was first seen as one: kept for a row that is still Direct, `now` for a
    /// new one, dropped for one that is gone or that the network lists now, so a row that comes
    /// back Direct starts again.
    static func directSince(_ previous: [String: Double], rows: [(name: String, direct: Bool)], now: Double) -> [String: Double] {
        var next: [String: Double] = [:]
        for row in rows where row.direct { next[row.name] = previous[row.name] ?? now }
        return next
    }

    /// The row an automatic reconnect takes now, or when to look again. The Mac's network row at
    /// once; its Direct row only once that row has stayed Direct for `networkFirst`. A Mac coming
    /// back to the shared network (Sill relaunched, the Mac awake again) registers there and over
    /// AWDL at the same moment, and while the nearby browser runs it can report the awdl0 record
    /// before the network browser reports the Wi‑Fi one: multicast on Wi‑Fi can be lost or held
    /// for a dozing radio's next beacon, and mDNS repeats an announcement only a second or more
    /// later. Taking the Direct row then would run the whole session at home over AWDL. A tap on
    /// a Direct row is the user's choice and is not held back.
    static func reconnectRow<Row>(network: Row?, direct: Row?, directSince: Double?, now: Double) -> (take: Row?, recheckAt: Double?) {
        if let network { return (network, nil) }
        guard let direct, let since = directSince else { return (nil, nil) }
        let due = since + networkFirst
        return now >= due ? (direct, nil) : (nil, due)
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
    /// A Mac last seen with Direct Wireless on gets this long for its Direct row before a remote
    /// dial (the direct-wireless fixes' `directWait`, which has not landed on this base).
    static let directWait = 6.0
    /// A Mac the network listed this recently is taken to be blinking, not gone, unless this
    /// device's own path changed (the fixes' `networkGrace`).
    static let networkGrace = 10.0
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
    /// passed. Due `remoteWait` after the loss (`directWait` for a Mac remembered with Direct
    /// Wireless on), and not within `networkGrace` of the network last listing it unless this
    /// device's path changed since the loss (it left home, or Wi‑Fi became cellular).
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
}
