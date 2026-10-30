import Foundation

/// How long a window's thumbnail is touched and held before its lights (close, minimize, full screen)
/// show, and before it can be dragged to another place in the bar (issue #113). A setting of this
/// device's own, the Settings panel's This iPad (or iPhone) group: "Hold to Show Window Controls", a
/// stepper from 0.2 to 2 s in tenths of a second, 0.5 s unless changed (Noah, 2026-10-29; it was a
/// fixed 1.5 s, three times iOS's own long press). Stored as `Sill.thumbnailHold`, a Double in
/// seconds, never sent to the Mac.
///
/// WindowStrip reads it for every thumbnail of every bar (sideways, an iPad's portrait window bar, a
/// phone's row 2) at launch and whenever it changes, so a hold already on screen waits the new length
/// at its next press. The drag's own rules (12 pt before the hold is a scroll of the strip, 8 pt after
/// it lifts the thumbnail) are not this type's, and the picture's long press (the right click, 0.45 s)
/// does not follow it.
///
/// Pure: Foundation only, checked in Tests/checks/thumbnail-hold.
enum ThumbnailHold {
    /// The UserDefaults key (`@AppStorage` in WindowStrip and the Settings panel). `-Sill.thumbnailHold
    /// 0.3` holds it at 0.3 s for one run (the argument domain is read first, so the stepper's changes
    /// are saved for the next run but this one keeps 0.3).
    static let key = "Sill.thumbnailHold"
    /// The shortest and the longest hold, in tenths of a second: the stepper steps a tenth at a time,
    /// in whole tenths, so no sum of steps drifts off the grid.
    static let tenthsRange: ClosedRange<Int> = 2...20
    /// The same in seconds: 0.2 to 2 s.
    static let range: ClosedRange<Double> = 0.2...2.0
    /// The stepper's step: a tenth of a second.
    static let step = 0.1
    /// Unless changed: half a second, iOS's own long press (`UILongPressGestureRecognizer`'s default),
    /// which issue #113's reporter cites.
    static let standard = 0.5
    /// The fixed hold before this setting (issue #113's 1.5 s).
    static let before = 1.5

    // MARK: Lengths

    /// A length in whole tenths of a second, as the stepper counts it: the nearest tenth (a value
    /// halfway between two rounds up), kept in the range (under 0.2 s is 0.2 s, over 2 s is 2 s);
    /// nothing usable (not finite) is the standard half second.
    static func tenths(_ seconds: Double) -> Int {
        guard seconds.isFinite else { return Int((standard * 10).rounded()) }
        // Kept in the range before it becomes an Int, so a huge value never overflows.
        let kept = min(max(seconds, range.lowerBound), range.upperBound)
        let t = Int((kept * 10).rounded(.toNearestOrAwayFromZero))
        return min(max(t, tenthsRange.lowerBound), tenthsRange.upperBound)
    }

    /// The seconds a count of tenths stands for, kept in the range: 5 is 0.5 s, 40 is 2 s.
    static func seconds(tenths: Int) -> Double {
        Double(min(max(tenths, tenthsRange.lowerBound), tenthsRange.upperBound)) / 10
    }

    /// A length as the hold takes it: on the grid of tenths, in the range (`tenths`).
    static func seconds(_ value: Double) -> Double { seconds(tenths: tenths(value)) }

    /// What a stored value means, whatever UserDefaults hands back: a number (a Double, an Int or a
    /// Bool, each an NSNumber there), or a string as a launch argument gives it (`-Sill.thumbnailHold
    /// 0.3`). Nothing stored, or nothing that reads as a number, is the standard half second.
    static func seconds(stored: Any?) -> Double {
        switch stored {
        case let n as NSNumber: return seconds(n.doubleValue)
        case let s as String:
            guard let d = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return standard }
            return seconds(d)
        default: return standard
        }
    }

    /// The length one step up or down from `value`, as the stepper's + and − give it (and VoiceOver's
    /// swipe up or down on it): a tenth of a second, kept in the range (2 s up stays 2 s).
    static func adjusted(_ value: Double, up: Bool) -> Double {
        seconds(tenths: tenths(value) + (up ? 1 : -1))
    }

    // MARK: Words

    /// The row's title in the Settings panel.
    static let title = "Hold to Show Window Controls"
    /// The narrowest the title may be beside the length and the stepper: these three lines, its words in
    /// order, the shortest widest line of any three ("Hold to Show"). Narrower than that, a word would
    /// break ("Win-dow", "Con-trols") or the title run past three lines, so the row stacks the title over
    /// the length and the stepper instead (HostSettingsPanel's ThumbnailHoldRow; the review, 2026-10-29).
    static let titleLines = ["Hold to Show", "Window", "Controls"]
    /// The row's label for VoiceOver ("Hold to show window controls, 0.5 seconds").
    static let spokenTitle = "Hold to show window controls"

    /// The row's value beside the title: "0.5 s", "1.0 s", "2.0 s", always a tenth's digit, so the
    /// value keeps its width as it steps.
    static func valueText(_ value: Double) -> String { String(format: "%.1f s", seconds(value)) }

    /// The value as VoiceOver says it: "0.5 seconds", "1 second", "1.5 seconds", "2 seconds" (no
    /// spoken "point zero").
    static func spokenValue(_ value: Double) -> String {
        let t = tenths(value)
        let number = t % 10 == 0 ? String(t / 10) : String(format: "%.1f", seconds(tenths: t))
        return "\(number) \(t == 10 ? "second" : "seconds")"
    }

    /// Under the row: what the length is for. It agrees with the tour's words ("Touch and hold a window
    /// to close, minimize or go full screen. Keep holding and drag to move it.").
    static let footnote = "How long to hold a window’s thumbnail before its close, minimize and full-screen controls appear, and before it can be dragged to another place."

    /// The Debug console's line when the strip reads a length it had not read before (at launch, and
    /// at each change): "thumbnails: hold 0.3 s".
    static func consoleLine(_ value: Double) -> String { "thumbnails: hold \(valueText(value))" }
}
