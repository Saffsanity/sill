import CoreGraphics
import Foundation

/// Full screen (docs/full-screen-plan.md): Sill's whole interface on the device hidden, so the Mac's picture
/// gets the screen, with nothing of Sill's left on it. Noah's design (2026-11-12): a swipe off the left side
/// hides it, a swipe in from the left side shows it, because iOS maps nothing to the left edge (the top is
/// Control Center, Siri and notifications, the bottom the app switcher, the right side on iPadOS the windowed
/// apps); a shake shows it too. With the coordinator's changes: the hide is a short outward flick that starts
/// at the left edge (anywhere else on the picture a leftward swipe is the Mac's scroll, and in Safari its way
/// back), and the ways back that need no hand at the edge (VoiceOver's action and escape gesture, the
/// pointer pushed against the edge, the interface coming back by itself whenever it is needed).
///
/// The rules here, pure (Foundation and CoreGraphics only; Tests/checks/full-screen): `ChromeLevel`, how much
/// shows; `EdgeFlick`, the hide's touch rule; `EdgeReveal`, whether the swipe in finishes or springs back;
/// `EdgeDwell`, the pointer at the left edge; `FullScreenPolicy`, when it is offered and armed, when the
/// interface comes back by itself, the hint, where the picture goes, and every word. The glue is
/// EdgeFlickRecognizer.swift (the flick's recognizer on the window) and FullScreen.swift; StreamScreen and
/// PortraitStreamScreen draw it.

// MARK: - How much of the interface shows

/// How much of Sill's interface shows. One level in this first build: everything, or nothing but the
/// picture. Noah's earlier idea (issue #279) has two upright: first the trackpad goes (the picture grows into
/// its room, #280), then the rest. That level goes between these two, its own raw value 1, and the two
/// functions below are the only places that step: a flick from `.shown` upright would give it, a flick from it
/// `.hidden`; the swipe in from `.hidden` gives it back, and from it `.shown`. Each layout draws the levels it
/// knows (StreamScreen's `chromeHidden`).
enum ChromeLevel: Int, Comparable, CaseIterable {
    /// Every control, as before.
    case shown = 0
    /// Nothing of Sill's: the picture alone, in `FullScreenPolicy.room`.
    case hidden = 2

    static func < (a: ChromeLevel, b: ChromeLevel) -> Bool { a.rawValue < b.rawValue }

    /// The level a hide flick leads to from this one.
    var afterFlick: ChromeLevel { .hidden }

    /// The level the swipe in from the left edge (or a shake, an action, the pointer) leads to from this one.
    var afterReveal: ChromeLevel { .shown }
}

// MARK: - The hide: a flick off the left edge

/// The hide's touch rule: one finger that lands within `band` of the screen's left edge, moves left and
/// leaves the screen, quickly. Fed one touch's samples from its landing (x from the screen's left edge, y
/// down, t in seconds), it answers as soon as it can: `notAFlick` the moment the touch shows it is something
/// else (the stream then gets it whole: the recognizer's failure lets the waiting ones go), `hide` at the lift
/// of a flick, `undecided` meanwhile. Only the touches that land in the band are judged at all, and a
/// touch is held back only while it could still be a flick: a tap, a long press, a drag right, up or down, or
/// a second finger is let go at once or within a few points; a slow drag left at most `duration` after it
/// landed.
///
/// The numbers (docs/full-screen-plan.md, "The numbers"; no finger on glass could be measured here, so each
/// is from the devices' geometry, UIKit's touch sampling and the strokes it must tell apart, and a Debug build
/// prints every judged stroke's numbers, `edge:` on Xcode's console, for the first sessions to measure):
/// - `band` 48 pt: about 7.5 mm on the iPad mini (163 pt an inch) and 8 mm on the iPhone 15 Pro (153), a
///   thumb's contact patch, so a thumb that sets off with its edge at the bezel lands in it; past it a stroke
///   is the Mac's at once, as it always was.
/// - `travel` 12 pt: a flick moves; a grip or a tap that rolls off the edge does not get this far, and a touch
///   that lands nearer the edge than this cannot be one.
/// - `duration` 0.25 s from landing to lifting: a flick takes about a tenth of a second; a resting grip, a
///   long press (0.45 s) and a slow drag are let go by then.
/// - `speed` 300 pt/s left over the last `speedWindow` (50 ms) before the lift: about 5 cm a second, half a
///   brisk flick's slowest; a slow drag to the edge, 100 to 200 pt/s, is not one.
/// - `reach` 24 pt: where the last sample may be. A finger that slides off the glass is last seen up to one
///   sample interval short of the edge (16.7 ms at 60 Hz, 8.3 ms at 120: 5 to 17 pt at 300 to 1,000 pt/s), and a
///   case's raised lip stops the finger's middle some 3 to 4 mm (20 to 24 pt) in, so the finger lifts there.
/// - `projection` 50 ms: a faster flick, last seen further in, counts when its last speed carries it past the
///   edge within this (three samples at 60 Hz).
/// - `rightSlop` 6 pt and `judgeAfter` 8 pt: a drag right is let go after 6 pt, and any stroke steeper than
///   `steepness` (|dy| ≤ 1.2 |dx|, about 50° from straight left) after 8, both before a pan's own 10 pt
///   threshold, so the drags the band lets go are not even late.
struct EdgeFlick: Equatable {
    static let band: Double = 48
    static let travel: Double = 12
    static let duration: Double = 0.25
    static let speed: Double = 300
    static let speedWindow: Double = 0.05
    static let reach: Double = 24
    static let projection: Double = 0.05
    static let rightSlop: Double = 6
    static let judgeAfter: Double = 8
    static let steepness: Double = 1.2

    struct Sample: Equatable {
        var x: Double
        var y: Double
        var t: Double
    }

    /// Why a touch is not a hide flick, for the console and the check.
    enum Reason: String, Equatable {
        /// It landed further in than `band`.
        case outsideBand = "landed outside the band"
        /// Another finger came down, or was down already.
        case secondTouch = "a second finger"
        /// It moved right `rightSlop` or more.
        case movedRight = "moved right"
        /// Up, down or anywhere but left: steeper than `steepness`.
        case steep = "not leftward"
        /// Still down `duration` after it landed.
        case tooLong = "held too long"
        /// Lifted without moving `travel` left.
        case tooShort = "too short"
        /// Lifted moving left slower than `speed`.
        case tooSlow = "too slow"
        /// Lifted further in than `reach`, and its speed would not have carried it off.
        case shortOfEdge = "lifted short of the edge"
        /// The system took the touch.
        case cancelled = "cancelled"
    }

    enum Verdict: Equatable {
        case undecided
        case hide
        case notAFlick(Reason)

        var decided: Bool { self != .undecided }
    }

    /// The touch's samples, from its landing.
    private(set) var samples: [Sample] = []
    private(set) var verdict: Verdict = .undecided

    init() {}

    /// The touch landed `x` from the screen's left edge.
    mutating func began(x: Double, y: Double, t: Double) -> Verdict {
        guard verdict == .undecided, samples.isEmpty else { return verdict }
        samples = [Sample(x: x, y: y, t: t)]
        if x > Self.band { verdict = .notAFlick(.outsideBand) }
        return verdict
    }

    /// It moved (each coalesced sample, in order).
    mutating func moved(x: Double, y: Double, t: Double) -> Verdict {
        guard verdict == .undecided, let first = samples.first else { return verdict }
        samples.append(Sample(x: x, y: y, t: t))
        if t - first.t > Self.duration {
            verdict = .notAFlick(.tooLong)
        } else if let why = Self.wrongWay(from: first, to: Sample(x: x, y: y, t: t)) {
            verdict = .notAFlick(why)
        }
        return verdict
    }

    /// It lifted here.
    mutating func ended(x: Double, y: Double, t: Double) -> Verdict {
        guard verdict == .undecided, let first = samples.first else { return verdict }
        let last = Sample(x: x, y: y, t: t)
        samples.append(last)
        verdict = Self.judge(samples, first: first, last: last)
        return verdict
    }

    /// Another finger came down.
    mutating func another() -> Verdict {
        if verdict == .undecided { verdict = .notAFlick(.secondTouch) }
        return verdict
    }

    /// The system took the touch.
    mutating func cancelled() -> Verdict {
        if verdict == .undecided { verdict = .notAFlick(.cancelled) }
        return verdict
    }

    /// The clock, with no new sample: a touch still down `duration` after it landed is let go.
    mutating func tick(t: Double) -> Verdict {
        if verdict == .undecided, let first = samples.first, t - first.t > Self.duration {
            verdict = .notAFlick(.tooLong)
        }
        return verdict
    }

    /// Right, or steep once it has moved `judgeAfter`: not a flick, whatever comes after.
    private static func wrongWay(from first: Sample, to now: Sample) -> Reason? {
        let dx = now.x - first.x, dy = now.y - first.y
        if dx >= rightSlop { return .movedRight }
        if hypot(dx, dy) >= judgeAfter, abs(dy) > steepness * max(-dx, 0) { return .steep }
        return nil
    }

    /// The verdict at the lift.
    private static func judge(_ samples: [Sample], first: Sample, last: Sample) -> Verdict {
        if last.t - first.t > duration { return .notAFlick(.tooLong) }
        let dx = last.x - first.x, dy = last.y - first.y
        if dx >= rightSlop { return .notAFlick(.movedRight) }
        let left = -dx
        if left < travel { return .notAFlick(.tooShort) }
        if abs(dy) > steepness * left { return .notAFlick(.steep) }
        let v = leftSpeed(samples, at: last)
        if v < speed { return .notAFlick(.tooSlow) }
        if last.x <= reach || last.x - v * projection <= 0 { return .hide }
        return .notAFlick(.shortOfEdge)
    }

    /// Points a second leftward over the last `speedWindow` before `last`: from where the finger was that long
    /// before the lift, in proportion between the samples on either side of that moment (the whole stroke's
    /// average when it is shorter). A still finger sends no samples, so after a rest the next sample is the
    /// motion's first: the proportion across the rest puts the finger at most that one sample's step short of
    /// where it set off. (From the sample before that moment instead, a flick after a rest would count the rest
    /// and read slow: 36 pt in 37 ms after a 0.1 s rest is 250 pt/s over the whole stroke, 600 over its end.)
    static func leftSpeed(_ samples: [Sample], at last: Sample) -> Double {
        guard let first = samples.first else { return 0 }
        let since = last.t - speedWindow
        if first.t >= since {
            let dt = last.t - first.t
            return dt > 0 ? (first.x - last.x) / dt : 0
        }
        var before = first, after = last
        for sample in samples {
            if sample.t <= since { before = sample } else { after = sample; break }
        }
        let span = after.t - before.t
        let x = span > 0 ? before.x + (after.x - before.x) * ((since - before.t) / span) : before.x
        return (x - last.x) / speedWindow
    }

    /// The console's numbers for a judged stroke: where it landed, how far left it went, how fast at the
    /// end, where it lifted, how long it took (Debug builds, `edge:` lines; docs/full-screen-plan.md).
    var numbers: String {
        guard let first = samples.first, let last = samples.last else { return "no samples" }
        let v = Self.leftSpeed(samples, at: last)
        return String(format: "landed %.1f pt from the edge, %.1f pt left and %.1f pt %@, %.0f pt/s at the end, last seen %.1f pt in, %.0f ms, %ld samples",
                      first.x, first.x - last.x, abs(last.y - first.y), last.y >= first.y ? "down" : "up",
                      v, last.x, (last.t - first.t) * 1000, samples.count)
    }
}

/// Which touches the flick's recognizer judges at all (EdgeFlickRecognizer): a finger, never a Pencil or the
/// iPad's own trackpad or mouse, with no other touch down in Sill's window. Any other touch fails the
/// recognizer at once, so nothing waits for it; and a finger that comes down while one is judged ends the
/// judging (`EdgeFlick.another`): two fingers are a scroll, a zoom or the start of a gesture.
enum EdgeFlickGate {
    static func judges(direct: Bool, alreadyDown: Int) -> Bool { direct && alreadyDown == 0 }
}

// MARK: - The show: a swipe in from the left bezel

/// The swipe in from the left edge (UIScreenEdgePanGestureRecognizer: the system decides that it started at
/// the bezel): the interface follows the finger, its progress the finger's travel across the screen, and
/// at the lift it finishes or springs back by distance and speed, as a navigation's swipe back does.
enum EdgeReveal {
    /// The interface comes all the way by itself past a third of the screen's width (with the lift's speed
    /// carrying it on for `coast`)...
    static let share: Double = 1.0 / 3
    static let coast: Double = 0.15
    /// ...or at a flick in: this fast to the right, once it has moved `flickTravel`.
    static let flickSpeed: Double = 400
    static let flickTravel: Double = 12
    /// Moving back toward the edge at the lift this fast springs back, however far it came.
    static let backSpeed: Double = 200

    /// How far the interface has come in, 0…1: the finger's travel over the screen's width.
    static func progress(translation: Double, width: Double) -> Double {
        guard width > 0 else { return 0 }
        return min(max(translation / width, 0), 1)
    }

    /// At the lift: whether the interface comes the rest of the way in (true) or springs back out.
    static func finishes(translation: Double, velocity: Double, width: Double) -> Bool {
        guard width > 0 else { return false }
        if velocity <= -backSpeed { return false }
        if velocity >= flickSpeed, translation >= flickTravel { return true }
        return translation + coast * max(velocity, 0) >= share * width
    }
}

// MARK: - The pointer pushed against the left edge

/// A trackpad's or mouse's pointer on an iPad, held against the left edge while the interface is hidden: it
/// comes back after `dwell` with the pointer at most `edge` from the edge, as iPadOS's own edges reveal what
/// they hold. iPadOS reports no push past the edge (the pointer stops there), so it is a dwell: the pointer
/// came to the edge and stayed. A Pencil's hover never counts.
struct EdgeDwell: Equatable {
    static let edge: Double = 1
    static let dwell: Double = 0.5

    /// Since when the pointer has been at the edge, nil while it is not.
    private(set) var since: Double?
    /// It fired this stay at the edge: the next needs the pointer to leave first.
    private(set) var fired = false

    /// The pointer is at `x` (from the screen's left edge) at `t`. True when the interface should come now
    /// (its `dwell` has run; the glue also asks `check` when no event comes, since a still pointer sends none).
    mutating func hover(x: Double, t: Double, pencil: Bool) -> Bool {
        guard !pencil, x <= Self.edge else {
            since = nil
            fired = false
            return false
        }
        if since == nil { since = t }
        return check(t: t)
    }

    /// The pointer left the picture, or the hover ended.
    mutating func ended() {
        since = nil
        fired = false
    }

    /// Whether the dwell has run by `t`; true once per stay.
    mutating func check(t: Double) -> Bool {
        guard let since, !fired, t - since >= Self.dwell else { return false }
        fired = true
        return true
    }
}

// MARK: - When, where, and the words

enum FullScreenPolicy {
    /// What the stream screen has when it asks.
    struct Situation: Equatable {
        /// Sill's window covers the screen (`offered`).
        var coversScreen = true
        /// A session streams a source (a window or the Desktop), its picture come.
        var streaming = true
        /// Something open over the stream: the Settings panel, the Apps drawer, the Menus pull-down, a
        /// thumbnail's lights, the Aa ruler.
        var somethingOpen = false
        /// The first-run tour on screen (or put aside under the pairing overlay).
        var tour = false
        /// Pair This iPad…'s overlay, or an outside link waiting to be confirmed.
        var pairing = false
        /// The link's line over the stream ("The link can’t keep up…", docs/remote-bundle-plan.md §6.7).
        var linkLine = false
        /// The locked Mac's cover: locked, another user's, unlocking (LockedMac.Shade).
        var lockCover = false
        /// The off-console view: another user's screen shown anyway, with its line (docs/off-console-plan.md).
        var offConsoleView = false
    }

    /// Why the interface comes back by itself.
    enum ShowReason: String, Equatable, CaseIterable {
        /// The tour points at the controls.
        case tour = "the tour"
        /// A pairing's code or an outside link's confirmation.
        case pairing = "a pairing"
        /// The link's line asks for a lower quality, in Settings.
        case linkLine = "the link's line"
        /// The Mac is locked or another user's: no picture, only its cover, and what to do is in the controls.
        case locked = "the Mac's cover"
        /// The off-console view's line says what the picture is.
        case offConsoleView = "the off-console view"
        /// Nothing streams: a window closed, nothing picked; what to stream is in the controls.
        case nothingStreams = "nothing streams"
        /// Sill's window no longer covers the screen (Split View, Stage Manager, Slide Over): no bezel at its
        /// left edge to swipe from.
        case window = "the window no longer fills the screen"
    }

    /// Full screen by gesture is offered only while Sill's window covers the screen (within half a point):
    /// a window that does not reach the screen's edges has no bezel at its left edge to swipe in from, and a
    /// flick at its edge lands on the other app. The Settings row says so and is dimmed (open question 3).
    static func offered(window: CGRect, screen: CGRect) -> Bool {
        guard window.width > 0, window.height > 0 else { return false }
        return abs(window.minX - screen.minX) <= 0.5 && abs(window.minY - screen.minY) <= 0.5
            && abs(window.maxX - screen.maxX) <= 0.5 && abs(window.maxY - screen.maxY) <= 0.5
    }

    /// Why the interface must come back now, if it must (the first reason in `ShowReason`'s order), or nil.
    /// While hidden the stream screen asks at every change; a reason that holds also keeps a hide from
    /// starting (`hideAllowed`).
    static func mustShow(_ s: Situation) -> ShowReason? {
        if s.tour { return .tour }
        if s.pairing { return .pairing }
        if s.linkLine { return .linkLine }
        if s.lockCover { return .locked }
        if s.offConsoleView { return .offConsoleView }
        if !s.streaming { return .nothingStreams }
        if !s.coversScreen { return .window }
        return nil
    }

    /// Whether the interface may hide now (a flick, the Settings row): nothing that would bring it straight
    /// back, and nothing open over the stream (the Settings row closes the panel first).
    static func hideAllowed(_ s: Situation) -> Bool {
        mustShow(s) == nil && !s.somethingOpen
    }

    /// Whether the flick off the left edge is listened for: the interface shown, a hide allowed, and no
    /// assistive technology that keeps one-finger swipes for itself (VoiceOver's own swipes would never
    /// reach it; Settings › Full Screen is the way in then).
    static func flickArmed(_ s: Situation, level: ChromeLevel, voiceOver: Bool) -> Bool {
        level == .shown && !voiceOver && hideAllowed(s)
    }

    // MARK: The hint

    /// The hint as the interface hides ("Swipe in from the left edge…"): the first `hintTimes` times on this
    /// device (`Sill.fullScreenHints`, a count), and every time with DEBUG `-SillFullScreenHint 1`. VoiceOver
    /// hears it every time, as an announcement.
    static let hintTimes = 3
    static let hintSeconds: Double = 2.5

    static func showsHint(shownBefore: Int, forced: Bool) -> Bool {
        forced || shownBefore < hintTimes
    }

    // MARK: The room

    /// The safe area's insets, CoreGraphics' way (top, left, bottom, right in points).
    struct Insets: Equatable {
        var top: CGFloat = 0
        var left: CGFloat = 0
        var bottom: CGFloat = 0
        var right: CGFloat = 0
    }

    /// Where the hidden interface's picture may go. `clearOfHousing` is the default (open question 5, with
    /// photos of the three for Noah).
    enum Room: String, Equatable, CaseIterable {
        /// The whole screen: under the Dynamic Island or the notch and the rounded corners.
        case screen
        /// The screen less the safe area's top, left and right (the Dynamic Island or the notch upright, the
        /// sensor housing's side sideways, the iPhone Duo cover's camera strip), down to the bottom edge
        /// under the home indicator, which fades (`persistentSystemOverlays(.hidden)`). On an iPad with the
        /// status bar hidden that is the whole screen.
        case clearOfHousing = "housing"
        /// The whole safe area: also clear of the home indicator.
        case safeArea = "safe"
    }

    /// The picture's room while hidden, in a space the size of the screen (`size`) whose safe area is
    /// `insets`. `topIsStatusBar`: the top inset is the status bar's alone (an iPad: no sensor housing at its
    /// top), which full screen hides, so it is never counted, even in the moment before the status bar has
    /// gone. `foldTop`: on the iPhone Duo's inner display upright in the laptop pose, where the fold's band
    /// begins; the picture stays above it, the deck below lies flat (nil anywhere else).
    static func room(size: CGSize, insets: Insets, choice: Room, topIsStatusBar: Bool = false, foldTop: CGFloat? = nil) -> CGRect {
        var top: CGFloat = 0, left: CGFloat = 0, bottom: CGFloat = 0, right: CGFloat = 0
        switch choice {
        case .screen: break
        case .clearOfHousing:
            top = insets.top; left = insets.left; right = insets.right
        case .safeArea:
            top = insets.top; left = insets.left; right = insets.right; bottom = insets.bottom
        }
        if topIsStatusBar { top = 0 }
        var rect = CGRect(x: left, y: top, width: max(0, size.width - left - right), height: max(0, size.height - top - bottom))
        if let foldTop, foldTop > rect.minY, foldTop < rect.maxY {
            rect.size.height = foldTop - rect.minY
        }
        return rect
    }

    // MARK: Words

    enum Copy {
        /// The hint's two lines.
        static let hintTitle = "Controls hidden"
        static let hintLine = "Swipe in from the left edge to bring them back."
        /// VoiceOver, every time it hides.
        static let announcement = "Sill’s controls are hidden. Use the Show Controls action, or the escape gesture, to bring them back."
        /// VoiceOver, when they come back.
        static let shownAnnouncement = "Sill’s controls are back."
        /// The hidden picture as one element, for VoiceOver, Switch Control and Voice Control.
        static func pictureLabel(mac: String) -> String { "\(mac)’s picture. Sill’s controls are hidden." }
        static let action = "Show Controls"
        /// Voice Control's names for it.
        static let inputLabels = ["Show Controls", "Show Sill"]
        /// Settings › This iPad › Full Screen.
        static let rowTitle = "Full Screen"
        static let rowHint = "Hides Sill’s controls."
        static func footnote(device: String) -> String {
            "Hides Sill’s controls, so only the picture shows. To bring them back, swipe in from the left edge or shake your \(device). To hide them again, flick off the left edge."
        }
        /// Under the row while Sill's window does not fill the screen.
        static let notOffered = "Full Screen works while Sill fills the screen."
    }
}
