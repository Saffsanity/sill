import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Full screen's two edge recognizers (docs/full-screen-plan.md), both on Sill's window: the hide's flick off
/// the left edge while the interface shows, and the swipe in from the left bezel while it is hidden. UIKit and
/// FullScreenPolicy.swift's rules only, so the touch rig (Tests/touchrig) compiles them with the stream's
/// real surfaces.
///
/// Every other recognizer in the window that takes fingers waits for whichever of the two is listening to
/// fail (`shouldBeRequiredToFail(by:)`): the picture's tap, long press and scroll, the trackpad's tracker,
/// taps, pan and long press, the bars' buttons and the strip's scroll. A touch outside the edge fails them at
/// its landing, so nothing waits; a touch at the edge is held only until the rule has decided, and then either
/// is the hide (or the swipe in) and nothing else, or goes on whole, the waiting recognizers recognizing it
/// as they would have: UIKit holds their recognition back, not the touches, so no travel is lost and nothing
/// is reordered (the touch rig's EDGE strokes show it). Recognizers that only watch (the stroke observer, the
/// trackpad's finger counter, the tour's touch watch) never recognize, so they never wait; the Pencil's and
/// the iPad pointer's touches never reach these two (`allowedTouchTypes`), and the pointer's own recognizers
/// (hover, its scrolls) take no finger, so they never wait either.
/// A recognizer that only watches touches and never recognizes (the trackpad's finger counter, the stroke
/// observer on both surfaces): it has nothing to hold back, so it never waits for the edge recognizers.
protocol WatchesTouchesOnly: UIGestureRecognizer {}

enum EdgeRecognizers {
    /// Whether `other` waits for `edge` (the flick or the swipe in) to fail: it is in the same window, below
    /// the window itself (the system's own recognizers on the window are left alone), takes fingers, and is
    /// not one of the edge recognizers, a hover or a recognizer that only watches.
    static func waits(_ other: UIGestureRecognizer, for edge: UIGestureRecognizer) -> Bool {
        guard other !== edge, let window = edge.view, let view = other.view, view !== window,
              view.isDescendant(of: window) else { return false }
        if other is EdgeFlickRecognizer || other is RevealEdgePan || other is UIHoverGestureRecognizer
            || other is WatchesTouchesOnly { return false }
        return other.allowedTouchTypes.contains(NSNumber(value: UITouch.TouchType.direct.rawValue))
    }

    /// Whether one of `window`'s edge recognizers has just let a touch go at its lift (within `lately` of now:
    /// the same lift's handling). A recognizer that waited for it, and that UIKit lets begin only then, begins
    /// and ends with no change between; the picture's scroll and the trackpad's tracker then carry the finger's
    /// travel at their end (InputOverlay, TrackpadView), so a stroke held until its lift loses nothing. Nothing
    /// else ever sees this: a touch away from the edge lets them go at its landing.
    /// UIKit's pan hysteresis: a finger's pan begins once it has moved this far, and counts its translation
    /// from there, so a scroll's first 10 pt never reach the Mac (main's way, which a held stroke keeps). The
    /// touch rig measured it: main's overlay scrolled a slow drag's travel less exactly 10 pt.
    static let panHysteresis: CGFloat = 10

    /// Where the stroke the flick has just let go (within `lately`) landed, in the window, when it held it while
    /// it judged it (a stroke at the left edge that is not a flick, of one finger): a pan that UIKit lets begin
    /// only now counts its translation from here and now, not from 10 pt past the landing as it would have,
    /// so the picture's scroll carries the difference (InputOverlay's `carryHeldTravel`). Nil otherwise.
    static func heldLanding(in window: UIWindow?, lately: TimeInterval = 0.05) -> CGPoint? {
        let now = ProcessInfo.processInfo.systemUptime
        for recognizer in window?.gestureRecognizers ?? [] {
            if let flick = recognizer as? EdgeFlickRecognizer, let held = flick.heldLanding, abs(now - held.at) < lately {
                return held.point
            }
        }
        return nil
    }

    static func releasedAtLift(in window: UIWindow?, lately: TimeInterval = 0.05) -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        for recognizer in window?.gestureRecognizers ?? [] {
            if let flick = recognizer as? EdgeFlickRecognizer, abs(now - flick.liftReleaseTime) < lately { return true }
            if let reveal = recognizer as? RevealEdgePan, abs(now - reveal.liftReleaseTime) < lately { return true }
        }
        return false
    }
}

/// The hide's flick: EdgeFlick on each finger that lands while nothing else is down (EdgeFlickGate). It
/// recognizes at the lift of a flick (`onFlick`) and fails at once for anything else, and by EdgeFlick's
/// `duration` at the latest (its own clock: a still finger sends no events).
final class EdgeFlickRecognizer: UIGestureRecognizer {
    /// Whether it listens (FullScreenPolicy.flickArmed); off, every touch fails it at its landing.
    var armed = false
    /// A flick was recognized: hide.
    var onFlick: (() -> Void)?
    /// Each judged stroke's verdict and numbers, for the console (Debug) and the touch rig.
    var onJudged: ((EdgeFlick.Verdict, String) -> Void)?
    /// The touch rig's trace of each touch the recognizer sees and what it does with it (nil in the app).
    var trace: ((String) -> Void)?

    private var rule = EdgeFlick()
    private weak var tracked: UITouch?
    private var clock: Timer?
    /// When it last let a touch go at that touch's lift (the lift's time; EdgeRecognizers.releasedAtLift).
    private(set) var liftReleaseTime: TimeInterval = -1
    /// The last stroke of one finger it held and then let go: where it landed (the window's space) and when
    /// (EdgeRecognizers.heldLanding).
    private(set) var heldLanding: (point: CGPoint, at: TimeInterval)?

    init() {
        super.init(target: nil, action: nil)
        // Fingers only: a Pencil is the Mac's mouse and the iPad's pointer has its own way back.
        allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        cancelsTouchesInView = true      // a flick's touch is the hide's alone
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        addTarget(self, action: #selector(recognized))
    }

    override func shouldBeRequiredToFail(by other: UIGestureRecognizer) -> Bool {
        EdgeRecognizers.waits(other, for: self)
    }
    /// It never waits for anything, and never runs beside another recognizer's recognition of its touch.
    override func shouldRequireFailure(of other: UIGestureRecognizer) -> Bool { false }

    /// The touch's place, from the screen's left edge: the window's own space (the window covers the screen
    /// while full screen is offered; FullScreenPolicy.offered).
    private func point(_ touch: UITouch) -> CGPoint { touch.location(in: view) }

    // Each of these calls super first: UIKit's subclassing contract ("if you override one you must call super",
    // UIGestureRecognizerSubclass.h). Without it the touch rig showed the recognizer judging the first stroke and
    // never another, the trackpad's recognizers waiting on it for good.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        trace?("began: \(touches.count) touch(es), state \(state.rawValue), armed \(armed), tracking \(tracked != nil)")
        guard state == .possible else { return }
        guard armed else { state = .failed; return }
        if tracked != nil {
            // Another finger while one is judged: two fingers are a scroll, a zoom or a gesture.
            finish(rule.another())
            return
        }
        let down = (event.allTouches ?? touches).filter { $0.phase != .ended && $0.phase != .cancelled && !touches.contains($0) }
        guard touches.count == 1, let touch = touches.first,
              EdgeFlickGate.judges(direct: touch.type == .direct, alreadyDown: down.count) else {
            state = .failed
            return
        }
        tracked = touch
        let p = point(touch)
        let verdict = rule.began(x: Double(p.x), y: Double(p.y), t: touch.timestamp)
        if verdict.decided { finish(verdict); return }
        // A finger that stays still sends nothing: the rule's own clock lets it go.
        clock = Timer.scheduledTimer(withTimeInterval: EdgeFlick.duration + 0.005, repeats: false) { [weak self] _ in
            self?.trace?("clock: state \(self?.state.rawValue ?? -1), tracking \(self?.tracked != nil)")
            guard let self, self.state == .possible, self.tracked != nil else { return }
            self.finish(self.rule.tick(t: ProcessInfo.processInfo.systemUptime))
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        guard state == .possible, let touch = tracked, touches.contains(touch) else { return }
        for sample in event.coalescedTouches(for: touch) ?? [touch] {
            let p = point(sample)
            let verdict = rule.moved(x: Double(p.x), y: Double(p.y), t: sample.timestamp)
            if verdict.decided { finish(verdict); return }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        trace?("ended: state \(state.rawValue), tracking \(tracked != nil), its touch \(tracked.map { touches.contains($0) } ?? false)")
        guard state == .possible else { return }
        guard let touch = tracked, touches.contains(touch) else {
            // Another touch of this event lifted while the judged one stays: not ours to judge.
            return
        }
        let samples = event.coalescedTouches(for: touch) ?? [touch]
        for sample in samples.dropLast() where !rule.verdict.decided {
            let p = point(sample)
            _ = rule.moved(x: Double(p.x), y: Double(p.y), t: sample.timestamp)
        }
        if !rule.verdict.decided {
            let last = samples.last ?? touch
            let p = point(last)
            _ = rule.ended(x: Double(p.x), y: Double(p.y), t: last.timestamp)
        }
        // Let go at the lift: whatever waited begins and ends now (EdgeRecognizers.releasedAtLift).
        if rule.verdict != .hide { liftReleaseTime = ProcessInfo.processInfo.systemUptime }
        finish(rule.verdict)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        guard state == .possible else { return }
        finish(rule.cancelled())
    }

    /// The rule decided: recognized (the hide) or failed (the waiting recognizers go on).
    private func finish(_ verdict: EdgeFlick.Verdict) {
        guard state == .possible, verdict.decided else { return }
        clock?.invalidate()
        clock = nil
        onJudged?(verdict, rule.numbers)
        // A stroke of one finger that was held while judged (not one let go at its landing, nor two fingers).
        if case .notAFlick(let why) = verdict, why != .outsideBand, why != .secondTouch, why != .cancelled,
           let first = rule.samples.first {
            heldLanding = (CGPoint(x: first.x, y: first.y), ProcessInfo.processInfo.systemUptime)
        }
        state = verdict == .hide ? .recognized : .failed
    }

    @objc private func recognized() {
        if state == .recognized || state == .ended { onFlick?() }
    }

    override func reset() {
        super.reset()
        trace?("reset")
        clock?.invalidate()
        clock = nil
        tracked = nil
        rule = EdgeFlick()
    }
}

/// The swipe in from the left bezel while the interface is hidden: the system's own edge recognizer (it
/// decides that the finger started at the bezel, and the stream screen defers iPadOS's own left-edge gesture
/// to it while hidden: `defersSystemGestures(on:)`), with every finger recognizer of the window waiting for it
/// to fail, so a swipe in reaches the Mac not at all, and anything else (it fails a touch that does not start
/// at the edge) not late.
final class RevealEdgePan: UIScreenEdgePanGestureRecognizer {
    /// A touch that lands further in than this cannot be a swipe in from the bezel: it fails at once, so a
    /// tap or a scroll on the hidden picture never waits for the system's own judgement (which may want to
    /// see the touch move first). The system's edge region is narrower than this.
    static let landsWithin: CGFloat = 40

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        edges = .left
        allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
    }

    override func shouldBeRequiredToFail(by other: UIGestureRecognizer) -> Bool {
        EdgeRecognizers.waits(other, for: self)
    }

    /// When it last let a touch go at that touch's lift (EdgeRecognizers.releasedAtLift).
    private(set) var liftReleaseTime: TimeInterval = -1
    /// Lets a touch go that has not begun to swipe in by EdgeReveal.decideWithin (a still finger sends no
    /// events, and the system's recognizer would hold it until it moves or lifts).
    private var clock: Timer?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        if state == .possible, let view, touches.contains(where: { $0.location(in: view).x > Self.landsWithin }) {
            state = .failed
            return
        }
        if state == .possible, clock == nil {
            clock = Timer.scheduledTimer(withTimeInterval: EdgeReveal.decideWithin, repeats: false) { [weak self] _ in
                guard let self else { return }
                self.clock = nil
                if self.state == .possible { self.state = .failed }
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        let held = state == .possible
        super.touchesEnded(touches, with: event)
        if held, state == .possible || state == .failed { liftReleaseTime = ProcessInfo.processInfo.systemUptime }
    }

    override func reset() {
        super.reset()
        clock?.invalidate()
        clock = nil
    }
}
