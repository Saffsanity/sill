import Foundation

/// When the device asks the Mac for a fresh picture: its display layer was interrupted (failed, or
/// needs a flush to decode again, as after the app was in the background), so it waits for a
/// keyframe, and a still window sends none. The ask is a pick of the source already streaming
/// (kind 6), which every Mac answers with a restart and a keyframe; at most once per `spacing`, so
/// a layer that keeps failing never turns into a stream of restarts. Main thread.
struct KeyframeRecovery {
    static let spacing: TimeInterval = 2
    private var lastAsked: TimeInterval?

    /// True when the device should re-pick its source now. `now` is the uptime in seconds.
    mutating func shouldAsk(streaming: Bool, now: TimeInterval) -> Bool {
        guard streaming else { return false }
        if let last = lastAsked, now >= last, now - last < Self.spacing { return false }
        lastAsked = now
        return true
    }
}
