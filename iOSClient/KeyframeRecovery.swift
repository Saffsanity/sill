import Foundation

/// When the device asks the Mac for a keyframe after its picture was interrupted (issue #101): the
/// display layer failed, could not decode a frame, or needs a flush before it decodes again (iOS
/// sets that when Sill goes to the background). HEVCDisplayView flushes the layer and waits for a
/// keyframe, and a still window on the Mac sends none, so the device asks for one (kind 44,
/// `keyframeRequest`), which the Mac answers by encoding its last frame again. Never a pick of the
/// source again: that restarts every device's stream and, in regular mode, raises the window.
///
/// - One ask per interruption while its keyframe is due; an interruption runs from the picture lost
///   to the next keyframe shown. A keyframe the layer's own flush throws away (the layer still read
///   failed when it came) is the picture back and lost again at once: HEVCDisplayView says both, and
///   the next ask is a repeat's.
/// - An ask whose keyframe has not come within `wait` (`answerWait`: 4 s, or four of the worst
///   round trips) is owed again, as a repeat: a Mac from before kind 44 skips it, and a keyframe can
///   be lost. So a picture never waits for good while Sill stays active, and a Mac that never
///   answers is asked again after 4, 8 and 16 s, then every 32 s, which costs it nothing.
/// - Only while Sill is active and something streams: an interruption seen in the background is
///   asked for on the way back, and a trip to the background owes an ask that was out again (a
///   keyframe that comes meanwhile is lost to it).
/// - At least `spacing` (2 s) after the last ask, whatever interrupted the picture; an ask the
///   spacing holds back is owed until then (`askAt`).
/// - Repeats wait longer, so a decoder that cannot keep up never costs every device a keyframe
///   every 2 s: a picture that fails again within `calm` (10 s) of its keyframe, Sill active
///   throughout, or an ask that went unanswered, doubles the spacing (4, 8, 16, then 32 s at most).
///   A picture back for `calm`, or a trip to the background, starts the spacing at 2 s again; a
///   keyframe that comes while Sill is away never makes the next interruption a repeat (iOS may not
///   decode it there).
///
/// Pure: the client feeds it the view's events and the clock (`ProcessInfo.systemUptime`, seconds).
/// Main thread (StreamClient). `Tests/checks/keyframe-recovery` checks this file alone.
struct KeyframeRecovery {
    /// The least time between two asks.
    static let spacing: TimeInterval = 2
    /// The most, for a picture that fails again right after each keyframe, or a Mac that never answers.
    static let longestSpacing: TimeInterval = 32
    /// A picture back for this long has recovered: the next interruption is a new one, not a repeat.
    static let calm: TimeInterval = 10
    /// The least time an ask waits for its keyframe before it is owed again.
    static let shortestWait: TimeInterval = 4

    /// How long an ask waits for its keyframe: 4 s, or four round trips on a slow link (a keyframe is
    /// the largest thing the Mac sends), counting the worst round trip of the last second that measured
    /// one (StreamClient's `lastRttMaxMs`); none measured yet counts as 4 s.
    static func answerWait(worstRttMs: Int?) -> TimeInterval {
        max(shortestWait, 4 * Double(worstRttMs ?? 0) / 1000)
    }

    enum Decision: Equatable {
        /// Nothing to ask: no interruption, Sill not active, or nothing streams.
        case nothing
        /// Ask now (`consider` has counted the ask).
        case askNow
        /// Owed, held back by the spacing: consider again at this time.
        case askAt(TimeInterval)
        /// The ask is out, and its keyframe is due by this time: consider again then.
        case keyframeDue(TimeInterval)
    }

    /// The picture was lost and no keyframe has been shown since.
    private(set) var open = false
    /// An ask is out for this interruption, waiting for its keyframe (since the interruption opened,
    /// since Sill last came back to it, or since the last ask went unanswered).
    private(set) var asked = false
    /// Asks in a row that did not bring the picture back for good, with Sill in the foreground
    /// throughout: an interruption less than `calm` after the picture came back, or an ask
    /// unanswered within its wait. Each doubles the spacing.
    private(set) var repeats = 0
    /// When the last ask went out.
    private(set) var lastAsk: TimeInterval?
    /// When the picture last came back after an interruption.
    private var backAt: TimeInterval?
    /// Sill left the foreground since the picture last came back while it was active: the next
    /// interruption is the background's, never a repeat.
    private var wentAway = false

    /// The spacing the next ask keeps from the last one.
    var spacingNow: TimeInterval { min(Self.spacing * pow(2, Double(repeats)), Self.longestSpacing) }

    /// The view flushed its layer and waits for a keyframe. Opens an interruption, or is part of the
    /// open one (the layer reads interrupted at every frame until it decodes again).
    mutating func interrupted(now: TimeInterval) {
        guard !open else { return }
        open = true
        asked = false
        if !wentAway, let back = backAt, now >= back, now - back < Self.calm {
            repeats += 1
        } else {
            repeats = 0
        }
    }

    /// A keyframe ended the wait: the picture is back. `active`: Sill is active. A keyframe that comes
    /// while Sill is away is the background's: the trip away still counts, so the next interruption
    /// is not a repeat (iOS may refuse to decode that keyframe, or throw it away at its next flush).
    mutating func pictureBack(now: TimeInterval, active: Bool) {
        guard open else { return }
        open = false
        backAt = now
        if active { wentAway = false }
    }

    /// Sill is no longer active (another app, the background, Control Center). An ask that was out is
    /// owed again: its keyframe may come while Sill is away, and be lost to it. And the spacing starts
    /// at 2 s again: what held asks back was the picture failing while Sill was in front.
    mutating func leftForeground() {
        wentAway = true
        asked = false
        repeats = 0
    }

    /// Whether to ask now. Counts the ask when it says `askNow`. `active`: Sill is the active app;
    /// `streaming`: the session streams a source; `wait`: how long an ask waits for its keyframe
    /// (`answerWait`).
    mutating func consider(now: TimeInterval, active: Bool, streaming: Bool, wait: TimeInterval) -> Decision {
        guard open, active, streaming else { return .nothing }
        if asked {
            // The ask is out: its keyframe is due within `wait` of it.
            if let last = lastAsk, now >= last, now < last + wait { return .keyframeDue(last + wait) }
            // None came (a Mac from before kind 44 skips the ask; a keyframe can be lost): owed again,
            // as a repeat, so a Mac that never answers is asked ever less often.
            asked = false
            repeats += 1
        }
        // Against the time it is due, not `now - last < spacing`: (last + s) - last can round below s,
        // and an ask held until then would be held again at that very time.
        if let last = lastAsk, now >= last, now < last + spacingNow { return .askAt(last + spacingNow) }
        asked = true
        lastAsk = now
        return .askNow
    }
}
