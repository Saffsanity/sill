import Foundation

/// Whether a capture may be built from the catalog's last look at the windows and displays, or the
/// catalog looks again first; and the Desktop's one more try after a start that failed.
///
/// Found 2026-10-28 (sill-handoff's triage, glitch-wired-black-2026-10-28.md): Sill.app had run 36.5
/// hours with no device connected, and the catalog looks only while one is (WindowCatalog: "idle
/// means idle"), so its last look was from the session before. Meanwhile the dock's two displays had
/// turned off and on with the Mac's sleeps and come back under new IDs (21 at that look, 53 and 52
/// then). The first device's Desktop was built on display 21's SCDisplay, ScreenCaptureKit refused
/// it ("Start stream failed … The stream is nil"), the host sent "nothing streams", and the device,
/// which had just asked, did not ask again: a black screen. Any second pick would have streamed.
///
/// So before a capture is built from the catalog, `lookAgain` says whether the last look will do.
/// Not when its display is no longer among the displays macOS has active (gone: a dock, a monitor
/// switched off or plugged in again under a new ID; asleep counts too, which costs one look of about
/// 50 ms and nothing else), or there is none while macOS has one; not when there was no look yet;
/// not when the look is older than `staleAfterPolls` poll intervals (the catalog polls every 2 s
/// while a device is connected, so an older look means a spell with none, whatever the displays did
/// meanwhile). The age is on the clock that counts sleep (WindowCatalog's `lookAge`): a look from
/// before a night asleep is a night old. An empty list of displays (none active, or the call failed)
/// says nothing about the display, and the age decides.
///
/// Pure: Foundation only, checked on its own with swiftc (Tests/checks/catalog-look).
enum CatalogLook {
    /// Why the catalog looks again before a capture is built from it.
    enum Why: Equatable {
        /// The last look's display is not among the active displays now: gone, or asleep.
        case displayGone(UInt32)
        /// The last look had no display, and macOS has one now.
        case noDisplay
        /// No look yet: Screen Recording not granted at launch, or the first look still under way.
        case never
        /// The last look is this many seconds old: a spell with no device connected.
        case old(TimeInterval)
    }

    /// A look older than this many poll intervals is from a spell with no device: one late pass (a
    /// slow look, many thumbnails due) is not.
    static let staleAfterPolls: Double = 2

    /// Nil when the last look will do; else why the catalog looks again first. `age`: seconds since the
    /// last look (nil: none yet); `display`: its display's ID (nil: it had none); `displaysNow`: the
    /// displays macOS has active now; `pollInterval`: the catalog's, in seconds.
    static func lookAgain(age: TimeInterval?, display: UInt32?, displaysNow: [UInt32], pollInterval: TimeInterval) -> Why? {
        if !displaysNow.isEmpty {
            guard let display else { return .noDisplay }
            if !displaysNow.contains(display) { return .displayGone(display) }
        }
        guard let age else { return .never }
        return age > staleAfterPolls * pollInterval ? .old(age) : nil
    }

    /// The line when the look before the Desktop's start gave another display than the last look had:
    /// "Desktop: display 21 → 53 (the displays changed since the last look, 36 h ago)." Nil when it gave
    /// the same display, or none (that start has nothing to stream, as before), or the last look had
    /// none (nothing changed that a line could name).
    static func desktopLine(was: UInt32?, now: UInt32?, age: TimeInterval?) -> String? {
        guard let was, let now, was != now else { return nil }
        let since = age.map { "the displays changed since the last look, \(ageWords($0)) ago" } ?? "the displays changed since the last look"
        return "Desktop: display \(was) → \(now) (\(since))."
    }

    /// The one line before the Desktop's one more try, after a start that failed: "Could not start
    /// streaming the whole desktop: ‹error›. Looked at the displays again: trying once more on display
    /// 53." `display`: the display of the new look (nil: the test pattern, which has none). A second
    /// failure is the line as before ("Could not start streaming ‹source›: ‹error›"), and nothing streams.
    static func retryLine(source: String, error: String, display: UInt32?) -> String {
        let next = display.map { "Looked at the displays again: trying once more on display \($0)." } ?? "Trying once more."
        return "Could not start streaming \(source): \(error). \(next)"
    }

    /// An age as the lines give it: "0.4 s" under 10 s, then "12 s", "5 min", "36 h", "3 days".
    static func ageWords(_ seconds: TimeInterval) -> String {
        let s = max(0, seconds)
        if s < 10 { return "\((s * 10).rounded(.down) / 10) s" }
        if s < 60 { return "\(Int(s)) s" }
        if s < 3600 { return "\(Int(s / 60)) min" }
        if s < 48 * 3600 { return "\(Int(s / 3600)) h" }
        return "\(Int(s / 86400)) days"
    }

    /// A Duration in seconds (the catalog's clock and its poll interval are Durations).
    static func seconds(_ d: Duration) -> TimeInterval {
        Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18
    }
}
