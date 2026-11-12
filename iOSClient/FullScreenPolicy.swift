import CoreGraphics
import Foundation

/// Full screen (docs/full-screen-plan.md): Sill's whole interface on the device hidden, so the Mac's picture
/// gets the screen, with nothing of Sill's left on it. Noah's design after trying the first build on his iPad
/// mini and iPhone 15 Pro (2026-11-12): Settings › Full Screen is the one way in ("remove the side swipe to
/// start full screen and just have it be invoked from the button in settings"); a swipe in from the left edge
/// brings the interface back, and so does a shake while Shake to Show Controls is on ("a toggle in settings to
/// enable/disable shake to revert"); and the ways back that need no hand at the edge (VoiceOver's action and
/// escape gesture, the pointer held at the edge, the interface coming back by itself whenever it is needed).
/// While the interface shows nothing of full screen listens to a touch.
///
/// The rules here, pure (Foundation and CoreGraphics only, with DuoPosture.swift's split and PhonePortraitLayout.swift
/// for the preview's cut; Tests/checks/full-screen): `ChromeLevel`, how much
/// shows; `EdgeSwipe`, which touch at the left edge is a swipe in and when it is let go; `EdgeReveal`, how far
/// the interface has come and whether it finishes or springs back; `RevealCut`, the preview's cut over the
/// picture's place in each layout; `EdgeDwell`, the pointer at the left edge; `FullScreenPolicy`, when it is offered, when the
/// interface comes back by itself, the shake, the hint, the Settings rows' place, where the picture goes, and
/// every word. The glue is RevealEdgePan.swift (the swipe in's recognizer on the window) and FullScreen.swift;
/// StreamScreen and PortraitStreamScreen draw it.

// MARK: - How much of the interface shows

/// How much of Sill's interface shows. One level: everything, or nothing but the picture (Noah, 2026-11-12).
/// His earlier idea (issue #279) has two upright: first the trackpad goes (the picture grows into its room,
/// #280), then the rest. That level would go between these two, its own raw value 1, and the two functions
/// below are the only places that step: a hide from `.shown` upright would give it, a hide from it `.hidden`;
/// the swipe in from `.hidden` gives it back, and from it `.shown`. Each layout draws the levels it knows
/// (StreamScreen's `chromeHidden`).
enum ChromeLevel: Int, Comparable, CaseIterable {
    /// Every control, as before.
    case shown = 0
    /// Nothing of Sill's: the picture alone, in `FullScreenPolicy.room`.
    case hidden = 2

    static func < (a: ChromeLevel, b: ChromeLevel) -> Bool { a.rawValue < b.rawValue }

    /// The level Settings › Full Screen leads to from this one.
    var afterHide: ChromeLevel { .hidden }

    /// The level the swipe in from the left edge (or a shake, an action, the pointer) leads to from this one.
    var afterReveal: ChromeLevel { .shown }
}

// MARK: - The show: a swipe in from the left edge

/// The swipe in's start (RevealEdgePan): which touch at the left edge of Sill's window is a swipe in, judged
/// as early as it can be, fed one touch's samples from its landing (x from the window's left edge, y down, t in
/// seconds). Sill's own rule, not the system's edge recognizer: on the window, UIScreenEdgePanGestureRecognizer
/// read the device's upright left edge as "left" whichever way it was held, and failed every swipe from the
/// interface's left edge on its side (Noah's iPad mini and iPhone 15 Pro, 2026-11-12); in the window's own
/// space this is the interface's left edge in every orientation.
///
/// One finger, alone, that lands within `band` of the left edge (or within the window's left safe-area inset,
/// where that is wider: an iPhone on its side keeps 59 pt clear of the picture there, and a thumb coming over
/// the bezel is first seen anywhere in it), and once it has moved `judgeAfter` sets off to the right, no
/// steeper than 45°. Anything else is let go and goes on to the Mac whole: a touch further in at its landing,
/// a second finger, a drag left, up or down, a finger still or not yet judged `decideWithin` after it landed.
/// The cost: a drag to the right that starts inside the band while the interface is hidden brings it in and
/// never reaches the Mac (the system's recognizer took only fingers that came over the bezel).
///
/// The numbers (docs/full-screen-plan.md, "The numbers"): `band` 24 pt, where Noah's swipes in were first seen
/// (0 to 9 pt upright, up to 21 pt at speed on the iPad on its side); `judgeAfter` 8 pt, before a pan's own
/// 10 pt, so a drag that is let go is not even late; `decideWithin` 0.3 s, before a long press's 0.45 s.
struct EdgeSwipe: Equatable {
    static let band: Double = 24
    static let judgeAfter: Double = 8
    static let decideWithin: Double = 0.3

    /// The band for a window whose left safe-area inset is `leftInset`.
    static func reach(leftInset: Double) -> Double { max(band, leftInset) }

    /// Why a touch is not a swipe in, for the console and the check.
    enum Reason: String, Equatable {
        /// It landed further in than the band.
        case outsideBand = "landed further in than the band"
        /// Another finger came down, or was down already.
        case secondTouch = "a second finger"
        /// It set off to the left, or straight up or down.
        case notRightward = "did not set off to the right"
        /// To the right, but steeper than 45°.
        case steep = "set off steeper than 45°"
        /// Not judged `decideWithin` after it landed (a still finger, a press).
        case tooLong = "had not set off by 0.3 s"
        /// It lifted before it was judged (a tap at the edge).
        case lifted = "lifted before it set off"
        /// The system took the touch.
        case cancelled = "cancelled"
    }

    enum Verdict: Equatable {
        case undecided
        case swipe
        case notASwipe(Reason)

        var decided: Bool { self != .undecided }
    }

    private(set) var landing: (x: Double, y: Double, t: Double)?
    private(set) var last: (x: Double, y: Double, t: Double)?
    private(set) var verdict: Verdict = .undecided

    init() {}

    static func == (a: EdgeSwipe, b: EdgeSwipe) -> Bool {
        a.verdict == b.verdict && a.landing?.x == b.landing?.x && a.landing?.y == b.landing?.y && a.landing?.t == b.landing?.t
    }

    /// One finger landed `x` from the left edge, with nothing else down (`alone`), in a window whose band is
    /// `band` (`EdgeSwipe.reach(leftInset:)`).
    mutating func began(x: Double, y: Double, t: Double, band: Double, alone: Bool = true) -> Verdict {
        guard verdict == .undecided, landing == nil else { return verdict }
        landing = (x, y, t)
        last = (x, y, t)
        if !alone { verdict = .notASwipe(.secondTouch) } else if x > band { verdict = .notASwipe(.outsideBand) }
        return verdict
    }

    /// It moved (each coalesced sample, in order): judged once it is `judgeAfter` from its landing on either
    /// axis.
    mutating func moved(x: Double, y: Double, t: Double) -> Verdict {
        guard verdict == .undecided, let landing else { return verdict }
        last = (x, y, t)
        if t - landing.t > Self.decideWithin { verdict = .notASwipe(.tooLong); return verdict }
        let dx = x - landing.x, dy = y - landing.y
        guard max(abs(dx), abs(dy)) >= Self.judgeAfter else { return verdict }
        if dx <= 0 { verdict = .notASwipe(.notRightward) } else if abs(dy) > dx { verdict = .notASwipe(.steep) } else { verdict = .swipe }
        return verdict
    }

    /// It lifted before it was judged.
    mutating func ended(x: Double, y: Double, t: Double) -> Verdict {
        guard verdict == .undecided, landing != nil else { return verdict }
        last = (x, y, t)
        verdict = .notASwipe(.lifted)
        return verdict
    }

    /// Another finger came down.
    mutating func another() -> Verdict {
        if verdict == .undecided { verdict = .notASwipe(.secondTouch) }
        return verdict
    }

    /// The system took the touch.
    mutating func cancelled() -> Verdict {
        if verdict == .undecided { verdict = .notASwipe(.cancelled) }
        return verdict
    }

    /// The clock, with no new sample: a finger not judged `decideWithin` after it landed is let go.
    mutating func tick(t: Double) -> Verdict {
        if verdict == .undecided, let landing, t - landing.t > Self.decideWithin { verdict = .notASwipe(.tooLong) }
        return verdict
    }

    /// The console's numbers: where it landed, where it was last seen, how long after (Debug builds, `reveal:`
    /// lines).
    var numbers: String {
        guard let landing, let last else { return "no samples" }
        return String(format: "landed %.1f pt from the left edge (y %.0f), last seen %.1f pt right and %.1f pt %@ of it, %.0f ms",
                      landing.x, landing.y, last.x - landing.x, abs(last.y - landing.y), last.y >= landing.y ? "below" : "above",
                      (last.t - landing.t) * 1000)
    }
}

/// The rest of the swipe in, once it has begun: the interface follows the finger, its progress the finger's
/// travel across the screen, and at the lift it finishes or springs back by distance and speed, as a
/// navigation's swipe back does. The travel is the pan's translation, which counts from where the pan began
/// (10 pt and more past the landing: 13 to 65 pt on Noah's devices), the feel he tried and kept.
enum EdgeReveal {
    /// The interface comes all the way by itself past a third of the screen's width (with the lift's speed
    /// carrying it on for `coast`)...
    static let share: Double = 1.0 / 3
    static let coast: Double = 0.15
    /// ...and never further than this: a third of an iPad's width, or of an iPhone's on its side, is further
    /// than a thumb at the edge reaches (Noah's devices, 2026-11-12: the first build's swipe in came in on the
    /// iPhone upright, 131 pt, and nowhere else: 284 pt on its side, 248 and 378 pt on the iPad mini).
    static let pull: Double = 80
    /// ...or at a flick in: this fast to the right, once it has moved `flickTravel`.
    static let flickSpeed: Double = 300
    static let flickTravel: Double = 12
    /// Moving back toward the edge at the lift this fast springs back, however far it came.
    static let backSpeed: Double = 200

    /// How far the interface has come in, 0…1: the finger's travel over the screen's width.
    static func progress(translation: Double, width: Double) -> Double {
        guard width > 0 else { return 0 }
        return min(max(translation / width, 0), 1)
    }

    /// How far the finger comes before the interface finishes by itself: a third of the width, `pull` at most.
    static func distance(width: Double) -> Double { min(share * width, pull) }

    /// At the lift: whether the interface comes the rest of the way in (true) or springs back out.
    static func finishes(translation: Double, velocity: Double, width: Double) -> Bool {
        guard width > 0 else { return false }
        if velocity <= -backSpeed { return false }
        if velocity >= flickSpeed, translation >= flickTravel { return true }
        return translation + coast * max(velocity, 0) >= distance(width: width)
    }
}

/// The swipe in's preview (StreamScreen's `revealPreview`) is the shown interface coming in with the finger over
/// the hidden picture. Until the controls land it draws them with the background they sit on and nothing of the
/// picture's place: no pane, rim, margin or room's black over the hidden picture (Noah,
/// 2026-11-12, on the try builds: "a bezel for the virtual display that shows above the controls as you swipe
/// in", "the bottom of it has a small black bar below it", "Ideally, no bezel gets rendered above or below the
/// controls until they are fully summoned", and on an iPhone upright "just a touch of black above the UI buttons
/// on iPhone in portrait to make it look uniform"). Each layout gives its place from its own geometry, never from
/// the picture: a pane at the video's shape is narrower or shorter than its room (an iPhone upright with Larger
/// Picture and a tall window showed the room's black beside it, 2026-11-12). The layouts draw nothing in the place
/// and their black only at `shown`, by construction: no mask over a drawn pane, which a measurement a frame late
/// let flash (Noah, on an iPhone on its side: "something quickly renders below the UI … very jarring").
/// - Landscape: everything under the top bar, which carries its own background (`Palette.bar`), so the cut ends
///   at its bottom edge, and the pane, its margin and the black round it all go.
/// - The halves (an iPad upright, the Duo's inner display upright, the laptop pose): everything over the
///   controls' block (`DuoPosture.PortraitSplit.controls`): the picture's half with the pane's margin, and the
///   laptop pose's fold. The block's own top margin, the black above the window bar, stays, as once they land.
/// - A phone upright and the Duo's cover upright (`PhonePortraitLayout`): everything over the bottom of the
///   picture's room (`picture`, Larger Picture's room too, whatever the video). The gap above row 1 stays black,
///   24 pt to the buttons, the shown layout's own.
enum RevealCut {
    /// Where the picture's place is in a layout: everything under a line (a bar's bottom edge), or over one
    /// (where the black the controls sit on begins).
    enum Place: Equatable {
        case under(CGFloat)
        case over(CGFloat)
    }

    /// Landscape: under the top bar, `barHeight` tall (StreamScreen's `BarMetrics.height`, the fold cleared).
    static func landscape(barHeight: CGFloat) -> Place { .under(barHeight) }
    /// The halves: over the controls' block.
    static func halves(_ split: DuoPosture.PortraitSplit) -> Place { .over(split.controls) }
    /// A phone upright: over the bottom of the picture's room.
    static func phone(_ layout: PhonePortraitLayout) -> Place { .over(layout.picture.maxY) }

    /// The cut in a preview of `size`: the place across the whole width, from its line to the far edge.
    static func cut(_ place: Place, in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        switch place {
        case .under(let line):
            let top = min(max(line, 0), size.height)
            return CGRect(x: 0, y: top, width: size.width, height: size.height - top)
        case .over(let line):
            let bottom = min(max(line, 0), size.height)
            return CGRect(x: 0, y: 0, width: size.width, height: bottom)
        }
    }

    /// What the preview draws: the rest of it, the controls with the background they sit on (the upright layouts
    /// draw their black exactly here; landscape's bar carries its own).
    static func shown(_ place: Place, in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let cut = cut(place, in: size)
        switch place {
        case .under: return CGRect(x: 0, y: 0, width: size.width, height: cut.minY)
        case .over: return CGRect(x: 0, y: cut.maxY, width: size.width, height: size.height - cut.maxY)
        }
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
        /// Sill's window no longer covers the screen (Split View, Stage Manager, Slide Over): its left edge is
        /// not the screen's, and iPadOS's windowing and the other app share it.
        case window = "the window no longer fills the screen"
    }

    /// Full screen is offered only while Sill's window covers the screen (within half a point): a window that
    /// does not reach the screen's edges shares its left edge with iPadOS's windowing (the window's own
    /// handles, Stage Manager's strip) and with the other app, where a swipe in would be a guess. The Settings
    /// row says so and is dimmed (open question 3).
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

    /// Whether the interface may hide now (Settings › Full Screen): nothing that would bring it straight back,
    /// and nothing open over the stream (the row closes the panel first).
    static func hideAllowed(_ s: Situation) -> Bool {
        mustShow(s) == nil && !s.somethingOpen
    }

    // MARK: The shake

    /// Shake to Show Controls (Settings › This iPad), a Bool on this device, on unless turned off.
    static let shakeKey = "Sill.shakeToShowControls"

    /// Whether a shake brings the interface back: while it is hidden and the switch is on. Off, a shake does
    /// nothing of Sill's.
    static func shakeShows(_ level: ChromeLevel, switchOn: Bool) -> Bool { level != .shown && switchOn }

    /// Whether iOS's Shake to Undo is off for the app: only while the interface is hidden and a shake is
    /// Sill's, so the shake never brings an Undo alert; otherwise it stays as it is.
    static func shakeToUndoOff(_ level: ChromeLevel, switchOn: Bool) -> Bool { shakeShows(level, switchOn: switchOn) }

    // MARK: The Settings rows

    /// Where Settings shows Full Screen and Shake to Show Controls: right after Frame Rate and its words while
    /// the Mac's settings show (Noah, 2026-11-12: "move the fullscreen and shake toggle up to be after the
    /// frame rate setting"), in This iPad's group while they do not (loading, or a Mac without them).
    enum RowsPlace: Equatable { case afterFrameRate, thisDevice }

    static func rowsPlace(macSettingsShown: Bool) -> RowsPlace { macSettingsShown ? .afterFrameRate : .thisDevice }

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
        static let footnote = "Hides Sill’s controls, so only the picture shows. Swipe in from the left edge to bring them back."
        /// Settings › This iPad › Shake to Show Controls, and the line under it.
        static let shakeTitle = "Shake to Show Controls"
        static func shakeFootnote(device: String) -> String { "Shaking your \(device) brings the controls back too." }
        /// Under the row while Sill's window does not fill the screen.
        static let notOffered = "Full Screen works while Sill fills the screen."
    }
}
