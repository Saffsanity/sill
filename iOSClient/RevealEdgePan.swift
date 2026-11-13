import UIKit
import UIKit.UIGestureRecognizerSubclass

/// A recognizer that only watches touches and never recognizes (the stroke observer on the picture): it has
/// nothing to hold back, so it never waits for the swipe in.
protocol WatchesTouchesOnly: UIGestureRecognizer {}

/// Full screen's swipe in from the left edge (docs/full-screen-plan.md), on Sill's window while the interface
/// is hidden, and off (`isEnabled` false) while it shows: then nothing of full screen's listens to a touch,
/// nothing waits for it and every stroke is main's. UIKit and FullScreenPolicy.swift's rules only, so the touch
/// rig (Tests/touchrig) compiles it with the stream's real surfaces.
///
/// While it listens, every other recognizer in the window that takes fingers (the picture's tap, long press and
/// scroll: the controls are gone) waits for it to fail (`shouldBeRequiredToFail(by:)`). A touch further in than
/// the band fails it at its landing, so nothing waits; a touch in the band is held only until EdgeSwipe has
/// judged it (8 pt of travel, 0.3 s at most), and then either is the swipe in and nothing else or goes on whole,
/// the waiting recognizers recognizing it as they would have, in order. UIKit holds their recognition back, not
/// the touches; but a pan held past its own start counts its translation from where it is let go, so the
/// picture's scroll carries the held travel as an unheld pan counts it (`heldLanding`, `panHysteresis`), and a
/// stroke held until its lift ends with its travel (`releasedAtLift`). With EdgeSwipe judging at 8 pt, before a
/// pan's own 10, and letting a finger go by 0.3 s, a pan rarely starts while held: only when one sample carries
/// the finger past both (iPad mini's 60 Hz touch at speed). Recognizers that only watch (the stroke observer:
/// `WatchesTouchesOnly`; the tour's touch watch is on the window) never recognize, so they never wait: made to
/// wait for the first build's flick, UIKit never reset them or it after the first stroke it held, and the
/// trackpad answered nothing more (the touch rig, 2026-11-12). The Pencil's and the iPad pointer's touches never
/// reach it (`allowedTouchTypes`), and the pointer's own recognizers (hover, its scrolls) take no finger.
enum EdgeRecognizers {
    /// Whether `other` waits for `edge` (the swipe in) to fail: it is in the same window, below the window
    /// itself (the system's own recognizers on the window are left alone), takes fingers, and is not the swipe
    /// in, a hover or a recognizer that only watches.
    static func waits(_ other: UIGestureRecognizer, for edge: UIGestureRecognizer) -> Bool {
        guard other !== edge, let window = edge.view, let view = other.view, view !== window,
              view.isDescendant(of: window) else { return false }
        if other is RevealEdgePan || other is UIHoverGestureRecognizer || other is WatchesTouchesOnly { return false }
        return other.allowedTouchTypes.contains(NSNumber(value: UITouch.TouchType.direct.rawValue))
    }

    /// UIKit's pan hysteresis: a finger's pan begins once it has moved this far, and counts its translation
    /// from there, so a scroll's first 10 pt never reach the Mac (main's way, which a held stroke keeps). The
    /// touch rig measured it: main's picture scrolled a slow drag's travel less exactly 10 pt.
    static let panHysteresis: CGFloat = 10

    /// Where the stroke the swipe in has just let go (within `lately`) landed, in the window, when it held it
    /// while it judged it: a pan that UIKit lets begin only now counts its translation from here and now, not
    /// from 10 pt past the landing as it would have, so the picture's scroll carries the difference
    /// (InputOverlay's `carryHeldTravel`). Nil otherwise.
    static func heldLanding(in window: UIWindow?, lately: TimeInterval = 0.05) -> CGPoint? {
        let now = ProcessInfo.processInfo.systemUptime
        for recognizer in window?.gestureRecognizers ?? [] {
            if let reveal = recognizer as? RevealEdgePan, let held = reveal.heldLanding, abs(now - held.at) < lately {
                return held.point
            }
        }
        return nil
    }

    /// Whether the swipe in has just let a touch go at its lift (within `lately` of now: the same lift's
    /// handling). A recognizer that waited for it, and that UIKit lets begin only then, begins and ends with no
    /// change between; the picture's scroll then carries the finger's travel at its end (InputOverlay), so a
    /// stroke held until its lift loses nothing. Nothing else ever sees this: a touch away from the edge lets it
    /// go at its landing.
    static func releasedAtLift(in window: UIWindow?, lately: TimeInterval = 0.05) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        for recognizer in window?.gestureRecognizers ?? [] {
            if let reveal = recognizer as? RevealEdgePan, abs(now - reveal.liftReleaseTime) < lately { return true }
        }
        return false
    }
}

/// The swipe in from the left edge while the interface is hidden: a pan of one finger whose start EdgeSwipe
/// judges (it lands within the band and sets off to the right, no steeper than 45°), in the window's own space,
/// the interface's left edge whichever way the device is held. Not UIScreenEdgePanGestureRecognizer, which on
/// the window read the device's upright left edge as "left" (Noah's iPhone and iPad on their side, 2026-11-12:
/// every swipe from the interface's left edge failed). Once begun, it is the system's pan: its translation and
/// velocity feed EdgeReveal, which says at the lift whether the interface comes in.
final class RevealEdgePan: UIPanGestureRecognizer {
    /// The touch rig's trace of each stroke it judges (nil in the app); a Debug build prints the same as
    /// `reveal:` lines on Xcode's console.
    var trace: ((String) -> Void)?

    /// When it last let a touch go at that touch's lift (the lift's time; EdgeRecognizers.releasedAtLift).
    private(set) var liftReleaseTime: TimeInterval = -1
    /// The last stroke it held and then let go: where it landed (the window's space) and when
    /// (EdgeRecognizers.heldLanding).
    private(set) var heldLanding: (point: CGPoint, at: TimeInterval)?

    private var rule = EdgeSwipe()
    private weak var tracked: UITouch?
    /// Lets a finger go that has not begun to swipe in by EdgeSwipe.decideWithin (a still finger sends no
    /// events, and a pan would hold it until it moves or lifts).
    private var clock: Timer?
    private var began = false

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        maximumNumberOfTouches = 1
        allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
    }

    override func shouldBeRequiredToFail(by other: UIGestureRecognizer) -> Bool {
        EdgeRecognizers.waits(other, for: self)
    }
    /// It never waits for anything.
    override func shouldRequireFailure(of other: UIGestureRecognizer) -> Bool { false }

    /// The band in this window: EdgeSwipe's, or the window's own left margin where that is wider.
    private var band: Double { EdgeSwipe.reach(leftInset: Double(view?.safeAreaInsets.left ?? 0)) }

    private func say(_ what: String) {
        trace?(what)
        #if DEBUG
        print("reveal: " + what)
        #endif
    }

    // Each calls super first: UIKit's subclassing contract ("if you override one you must call super").
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard state == .possible, let view else { return }
        if tracked != nil {
            // Another finger while one is judged: two fingers are a scroll, a zoom or a gesture.
            letGo(rule.another())
            return
        }
        let down = (event.allTouches ?? touches).filter { $0.phase != .ended && $0.phase != .cancelled }
        guard let touch = touches.first else { return }
        let p = touch.location(in: view)
        let verdict = rule.began(x: Double(p.x), y: Double(p.y), t: touch.timestamp, band: band,
                                 alone: touches.count == 1 && down.count == 1)
        if verdict.decided {
            // Landed further in than the band (said for the touches near it only: every touch on the picture
            // comes here), or beside another finger.
            if verdict != .notASwipe(.outsideBand) || p.x <= 120 { say("not a swipe in: \(reason(verdict)) (\(rule.numbers), the band \(Int(band)) pt)") }
            state = .failed
            return
        }
        tracked = touch
        say("a finger landed \(String(format: "%.1f", p.x)) pt from the left edge (y \(Int(p.y))), inside the \(Int(band)) pt band")
        clock?.invalidate()
        clock = Timer.scheduledTimer(withTimeInterval: EdgeSwipe.decideWithin + 0.005, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.clock = nil
            guard self.state == .possible, self.tracked != nil else { return }
            let verdict = self.rule.tick(t: ProcessInfo.processInfo.systemUptime)
            // Judged a swipe in but not begun (the finger stopped between 8 and 10 pt) is let go too: nothing
            // near the edge is held longer than this.
            self.letGo(verdict == .undecided || verdict == .swipe ? .notASwipe(.tooLong) : verdict)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .possible, !rule.verdict.decided, let touch = tracked, touches.contains(touch), let view {
            for sample in event.coalescedTouches(for: touch) ?? [touch] {
                let p = sample.location(in: view)
                let verdict = rule.moved(x: Double(p.x), y: Double(p.y), t: sample.timestamp)
                if case .notASwipe = verdict {
                    // Before the pan's own processing, so it never begins: the stroke goes on to the Mac.
                    letGo(verdict)
                    super.touchesMoved(touches, with: event)
                    return
                }
                if verdict == .swipe { say("a swipe in: \(rule.numbers)"); break }
            }
        }
        super.touchesMoved(touches, with: event)
        if !began, state == .began || state == .changed, let landing = rule.landing, let view, let touch = tracked ?? touches.first {
            began = true
            say(String(format: "began at %.1f pt, %.0f ms after the landing", touch.location(in: view).x, (touch.timestamp - landing.t) * 1000))
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        let held = state == .possible
        if held, !rule.verdict.decided, let touch = tracked, touches.contains(touch), let view {
            let p = touch.location(in: view)
            _ = rule.ended(x: Double(p.x), y: Double(p.y), t: touch.timestamp)
            noteHeld(rule.verdict)
            say("not a swipe in: \(reason(rule.verdict)) (\(rule.numbers))")
        }
        super.touchesEnded(touches, with: event)
        // Let go at the lift: whatever waited begins and ends now (EdgeRecognizers.releasedAtLift).
        if held, state == .possible || state == .failed { liftReleaseTime = ProcessInfo.processInfo.systemUptime }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .possible, tracked != nil, !rule.verdict.decided {
            _ = rule.cancelled()
            say("not a swipe in: \(reason(rule.verdict))")
        }
        super.touchesCancelled(touches, with: event)
    }

    /// The rule said it is not a swipe in: the stroke goes on to the Mac, as it would have.
    private func letGo(_ verdict: EdgeSwipe.Verdict) {
        guard state == .possible else { return }
        clock?.invalidate()
        clock = nil
        noteHeld(verdict)
        if tracked != nil { say("not a swipe in: \(reason(verdict)) (\(rule.numbers))") }
        state = .failed
    }

    /// A stroke of one finger that was held while judged (not one let go at its landing, nor two fingers).
    private func noteHeld(_ verdict: EdgeSwipe.Verdict) {
        guard tracked != nil, case .notASwipe(let why) = verdict, why != .outsideBand, why != .secondTouch, why != .cancelled,
              let landing = rule.landing else { return }
        heldLanding = (CGPoint(x: landing.x, y: landing.y), ProcessInfo.processInfo.systemUptime)
    }

    private func reason(_ verdict: EdgeSwipe.Verdict) -> String {
        if case .notASwipe(let why) = verdict { return why.rawValue }
        return verdict == .swipe ? "a swipe in" : "undecided"
    }

    override func reset() {
        super.reset()
        clock?.invalidate()
        clock = nil
        tracked = nil
        rule = EdgeSwipe()
        began = false
    }
}
