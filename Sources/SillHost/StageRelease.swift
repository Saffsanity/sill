import CoreGraphics
import Foundation

/// The stage's way out (VirtualStage.releaseHome): the staged window goes home through Accessibility, and Sill's display
/// is removed only once the window server shows the window off it, or after `commitDeadline`; once the display has gone,
/// the window is watched for `afterLook` and put back once if macOS moved it.
///
/// Why (Noah's test of PR #355, 2026-11-12, 04:30, Virtual Display on): Google Chrome, filling the Dell to the left of the
/// main display, was picked, staged, then sent home as the Desktop was picked, and Sill's display was removed in the same
/// millisecond. The window list shows an Accessibility move only once the app commits it, a few to tens of milliseconds
/// after the writes return (VirtualStage's `lastReleased`, 2026-09-23). So when the display went, the window server still
/// had Chrome on it and moved it to the main display, where Chrome, which had filled its screen, filled the main one
/// (2560×1410 at 0,30); the next pick took that for its home. Noah: "Windows should return to the display, size and
/// position they were in before windowed mode". Earlier the same night the same order left Chrome home: a race.
///
/// Pure (CoreGraphics' rectangles only): checked by `Tests/checks/stage-release`.
enum StageRelease {
    /// The longest Sill's display waits for the window to leave it. Then it goes all the same (an app that never commits
    /// the move, a hung one) and the look after the removal puts the window back. Prepare's own wait for a move is 1 s.
    static let commitDeadline: Double = 1.0
    /// How often the window list is read while the display waits.
    static let pollInterval: Double = 0.01
    /// After the removal, how long the window is watched, and how often: macOS and the app handle a display's going within
    /// a few hundred milliseconds (Chrome had handled it 200 ms after, 2026-11-12).
    static let afterLook: Double = 1.5
    static let afterPoll: Double = 0.1
    /// Two frames this close (points, on every edge) are the same place.
    static let tolerance: CGFloat = 2

    /// Whether the window server shows the window off Sill's display (`stage`, global points): listed at its home, or
    /// listed nowhere on the display (its home display unplugged meanwhile, so the stage's restore kept it on the main
    /// display), or not listed at all (closed). The commit moves a window in one step, so a listed frame still touching
    /// the display is the frame from before the move.
    static func leftStage(listed: CGRect?, home: CGRect, stage: CGRect) -> Bool {
        guard let listed else { return true }
        if same(listed, home) { return true }
        let overlap = listed.intersection(stage)
        return overlap.isNull || overlap.width <= 0 || overlap.height <= 0
    }

    /// While Sill's display waits, `elapsed` seconds after the window was sent home.
    enum Wait: Equatable {
        case wait
        /// Remove the display now; `left`: the window is off it.
        case remove(left: Bool)
    }

    static func decide(elapsed: Double, listed: CGRect?, home: CGRect, stage: CGRect) -> Wait {
        if leftStage(listed: listed, home: home, stage: stage) { return .remove(left: true) }
        return elapsed >= commitDeadline ? .remove(left: false) : .wait
    }

    /// After the removal, what the window's listing now asks for.
    enum After: Equatable {
        case stay
        /// macOS moved it (or it never left the display in time): put it back once.
        case putBack
        /// Not listed any more (closed): nothing to watch.
        case gone
    }

    /// `settled`: where the window was listed once it was off the display (nil when it never left in time); it is
    /// expected there, else at its home.
    static func afterRemoval(listed: CGRect?, settled: CGRect?, home: CGRect) -> After {
        guard let listed else { return .gone }
        return same(listed, settled ?? home) ? .stay : .putBack
    }

    static func same(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}
