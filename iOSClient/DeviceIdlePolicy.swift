import Foundation

/// When Sill holds the device's own auto-lock off (UIApplication.isIdleTimerDisabled; PR #230,
/// towards issue #134): while one of Sill's windows the person can see (its scene foreground active)
/// streams (its session connected, a source streaming), until `idleLimit` after the person last used
/// that window's session: input sent to the Mac, one of the stream screen's controls, or the moment
/// it began streaming. So a picture being read or watched does not lock under the person, and a
/// device left alone still locks by its own Auto-Lock setting, `idleLimit` later than it would have,
/// and its session then ends as before: no device left on a desk keeps the Mac streaming all night.
///
/// The Mac's display sleeps by the Mac's own setting, counted from the device's last input (the
/// host's DisplayWake), and its picture is black then (issue #134): a device held awake shows black
/// for whatever of `idleLimit` outlasts that setting, and a tap brings the picture back (on a Mac
/// with PR #228, without clicking).
///
/// The caller lists the windows afresh at every look, from the windows that are open now, so one
/// that closed counts for nothing, whether or not its stream screen ran its onDisappear, and one
/// window's stream screen going away leaves another's hold alone. Pure: Foundation only, checked
/// with swiftc (Tests/checks/device-idle). Times are systemUptime, which never goes back.
enum DeviceIdlePolicy {
    /// One of Sill's windows as it is now.
    struct Window: Equatable {
        /// Its scene is foreground active: the person can see it.
        var foregroundActive: Bool
        /// Its session is connected and a source streams (StreamClient.connected, active != .none).
        var streaming: Bool
        /// The latest of: the session's last input to the Mac, the last use of one of the stream
        /// screen's controls, and when it began streaming; nil when none is known.
        var lastUsedAt: Double?
    }

    /// How long after the person last used a streaming window auto-lock stays held off: 10 minutes,
    /// long enough to read or watch a picture without touching it, short enough that a device left
    /// alone locks within the quarter hour (a product default, Noah's to change).
    static let idleLimit: Double = 600

    /// When the hold ends: the latest `lastUsedAt + limit` of the windows that hold it, if that is
    /// after `now`; nil when auto-lock is not held off at `now` (the caller looks again then).
    static func holdEnds(_ windows: [Window], now: Double, limit: Double = idleLimit) -> Double? {
        let ends = windows.compactMap { w -> Double? in
            guard w.foregroundActive, w.streaming, let used = w.lastUsedAt else { return nil }
            return used + limit
        }
        guard let end = ends.max(), end > now else { return nil }
        return end
    }
}
