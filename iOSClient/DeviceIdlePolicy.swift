import Foundation

/// When Sill holds the device's own auto-lock off (UIApplication.isIdleTimerDisabled; PR #230,
/// towards issue #134): while one of Sill's windows the person can see (its scene foreground active)
/// streams (its session connected, a source streaming), until `idleLimit` after the person last used
/// that window's session (`lastUse`): input the person sent to the Mac, one of the stream screen's
/// controls, the start of a session the person started, or the moment the window came to the front.
/// So a picture being read or watched does not lock under the person, and a device left alone still
/// locks by its own Auto-Lock setting, `idleLimit` later than it would have, and its session then
/// ends as before: no device left on a desk keeps the Mac streaming all night. What the device does
/// by itself never counts (`sessionStart`, the verification's N1): the automatic reconnect, the
/// Desktop it asks for again after the Mac stopped one, its pointer's move to a new frame's middle;
/// a link or a Mac that keeps dropping would otherwise hold a device with nobody at it awake for good.
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
        /// When the person last used it (`lastUse`); nil when never.
        var lastUsedAt: Double?
    }

    /// What the person last did with one window's session, each the latest systemUptime, or nil.
    struct Uses: Equatable {
        /// Input the person sent to the Mac: never the device's own move of its pointer to the middle
        /// of a new frame (StreamClient.pointerFrameChanged), which nobody at the device made.
        var input: Double?
        /// One of the stream screen's controls (StreamClient.noteAction).
        var control: Double?
        /// The start of the session as the person started it (`sessionStart`).
        var session: Double?
        /// The moment the window's scene came to the front (foreground active).
        var front: Double?
    }

    /// A window's last use: the latest of its uses; nil when it has none.
    static func lastUse(_ uses: Uses) -> Double? {
        [uses.input, uses.control, uses.session, uses.front].compactMap { $0 }.max()
    }

    /// What a session's start leaves as `Uses.session`, at `now` as it connects (StreamClient's
    /// markConnected and remoteSessionReady): a session the person started (a tap on a Mac, Connect
    /// Remotely, a pairing) counts from its start; the automatic reconnect's carries the start of the
    /// session it reconnects (`previous`), as the tour's decision does (TourPolicy.nextSession), so a
    /// link that keeps dropping and coming back never counts as use. A stream restarted within a
    /// session (the Desktop the device asks for again after the Mac stopped one) is no session start.
    static func sessionStart(previous: Double?, reconnected: Bool, now: Double) -> Double? {
        reconnected ? previous : now
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
