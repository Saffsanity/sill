import Foundation

/// Where a window's thumbnail goes in the bar: a window opened since the session began goes first,
/// and one that leaves the list and comes back (minimized, on another Space, briefly off screen)
/// takes its old place again; "new" is the first time it is listed, never each time it returns.
/// Both ends keep it: the host's catalog order (`WindowCatalog`), and a device's own arrangement
/// (`StreamClient.windowOrder`) once it has one. Pure: checked by `Tests/checks/window-order`.
public enum WindowOrder {
    /// The host's first-seen order after a poll listed `listed`: windows never seen before first,
    /// in the order listed, then every window seen before, gone ones included (their place for when
    /// they come back). Past `cap`, the windows that left the longest ago (the end) are forgotten,
    /// never one listed now.
    public static func seen(_ seen: [UInt32], listed: [UInt32], cap: Int) -> [UInt32] {
        let known = Set(seen)
        var order = listed.filter { !known.contains($0) } + seen
        guard order.count > cap else { return order }
        let now = Set(listed)
        var excess = order.count - cap
        order = Array(order.reversed().filter { id in
            guard excess > 0, !now.contains(id) else { return true }
            excess -= 1
            return false
        }.reversed())
        return order
    }

    /// A device's arrangement after a window list (`listed`), when it changes: windows this session
    /// has never seen (`seen`, every id its lists named so far) and the arrangement does not hold go
    /// first, in the order listed. Nil when nothing changes: no arrangement yet (the bar shows the
    /// host's order), the session's first list (`seen` empty: everything in it would read as new), or
    /// nothing new.
    public static func arranged(_ order: [UInt32], seen: Set<UInt32>, listed: [UInt32]) -> [UInt32]? {
        guard !order.isEmpty, !seen.isEmpty else { return nil }
        let held = Set(order)
        let fresh = listed.filter { !seen.contains($0) && !held.contains($0) }
        return fresh.isEmpty ? nil : fresh + order
    }
}
