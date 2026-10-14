import Foundation

/// Saved Macs in Spotlight (Windows App puts each PC there): one item per saved Mac this device was
/// not removed from, and a tap on one dials that Mac as a tap on its row would. The tap comes back
/// as a user activity (CSSearchableItemActionType), not a link, so no other app can make Sill dial.
/// Pure; StreamClient indexes and dials.
enum SpotlightMacs {
    /// The items' domain: every write replaces all of it.
    static let domain = "me.saffer.sill.savedMacs"

    struct Mac: Equatable { var macID: String; var name: String; var revoked: Bool }
    enum Route: Equatable { case network, direct, remote }
    enum Choice: Equatable {
        /// Dial the row at this index of the rows given.
        case row(Int)
        /// No row of it after the wait: the saved Mac's own dial (its saved addresses).
        case dialSaved
        /// The network has not had its time yet: look again when the rows change, or after it.
        case wait
    }

    /// One write of the items at a time. A write is a delete of the domain, then the items once the
    /// delete is done; two writes close together would interleave (delete, delete, items, items) and
    /// the older list could land last, as at a launch that indexes the saved Macs and then clears
    /// them. A write while one runs waits, and those waiting run once after it with the list then.
    struct Run: Equatable {
        private var running = false
        private var again = false

        /// A write is asked for: true when it starts now.
        mutating func request() -> Bool {
            if running { again = true; return false }
            running = true
            return true
        }

        /// The running write is done: true when another must run now (a write waited).
        mutating func finished() -> Bool {
            guard again else { running = false; return false }
            again = false
            return true
        }
    }

    static func identifier(_ macID: String) -> String { "mac:" + macID }

    /// The Mac ID in one of Sill's identifiers; nil for anything else.
    static func macID(fromIdentifier identifier: String) -> String? {
        guard identifier.hasPrefix("mac:") else { return nil }
        let id = identifier.dropFirst(4)
        guard !id.isEmpty, id.count <= 128, !id.contains(":") else { return nil }
        return String(id)
    }

    /// The saved Macs to index: not one that removed this device. A Mac without a name is "Mac".
    static func indexed(_ macs: [Mac]) -> [Mac] {
        macs.filter { !$0.revoked }.map { Mac(macID: $0.macID, name: $0.name.isEmpty ? "Mac" : $0.name, revoked: false) }
    }

    /// Which row a tap on `macID`'s item dials: its network row, else its Direct row, at once; its
    /// Remote row only once the network has had its time (`waited`: DiscoveryPolicy.networkFirst),
    /// as the connect screen shows Remote rows only then; with no row of it after that, its own dial.
    static func choice(for macID: String, rows: [(route: Route, macID: String?)], waited: Bool) -> Choice {
        for route in [Route.network, .direct] {
            if let i = rows.firstIndex(where: { $0.route == route && $0.macID == macID }) { return .row(i) }
        }
        guard waited else { return .wait }
        if let i = rows.firstIndex(where: { $0.route == .remote && $0.macID == macID }) { return .row(i) }
        return .dialSaved
    }
}
