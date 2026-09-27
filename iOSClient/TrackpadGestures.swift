import Foundation
import CoreGraphics

/// Three- and four-finger strokes on the device's glass, for the Mac (docs/trackpad-gestures-plan.md
/// §6.1): which stroke is a gesture, and which gesture it is. Both glass surfaces feed one of these
/// with every direct touch (StrokeObserver, InputOverlay.swift): the portrait trackpad and the stream.
///
/// A stroke runs from its first touch down to its last touch up. It becomes a gesture stroke, is
/// *armed*, when its third finger lands within `chordWindow` of its first, before any finger has
/// moved `chordTravel` from where it landed, and while no button the surface pressed is held (the
/// trackpad's press-and-hold drag). A two-finger scroll that a third finger joins late, or after
/// moving, is never armed and goes on as it always did.
///
/// From arming until the next stroke's first touch the stroke is `silent`: the surfaces send
/// nothing for it, no pointer motion, click, button or scroll (a tap's action runs after its touch
/// has ended, so silence outlasts the last lift). A stroke that never arms is never silent, so one-
/// and two-finger strokes are exactly what they were.
///
/// The decision comes at the first lift after arming, from the three fingers that armed the stroke:
/// their centroid's net travel from where they were at arming, and their mean distance from it. A
/// swipe when the centroid travelled `swipeDistance` (or `flickDistance` while moving at
/// `flickSpeed` over the last `flickWindow`) and one axis beats the other by `axisRatio`; else a
/// pinch or a spread when the mean distance changed by `pinchRatio`; else nothing. At most one
/// decision per stroke. A fourth finger does not change it and makes `fingers` 4; a fifth leaves the
/// stroke silent and deciding nothing; touches the system cancels decide nothing. So a swipe taken
/// back before the lift does nothing, as on a Mac, and a four-finger stroke that iPadOS takes for
/// itself (its touches cancelled) never reaches the Mac.
///
/// Pure: Foundation and CoreGraphics only, checked on its own with swiftc (Tests/checks/gestures).
/// Deterministic: the same touches give the same outputs. Main thread, as the touches come.
struct TrackpadGestures {
    /// The gestures, named as kind 28 names them (TrackpadGesture). Natural direction: fingers
    /// moving left are `swipeLeft`, which brings the Space on the right.
    enum Gesture: String, Equatable, CaseIterable {
        case swipeUp, swipeDown, swipeLeft, swipeRight, pinch, spread
    }

    enum Output: Equatable {
        case none
        /// The stroke just became a gesture stroke: close what it had opened (a scroll).
        case armed
        /// The decision, at the first lift after arming.
        case gesture(Gesture, fingers: Int)
    }

    // The tunables, in the surface's points and seconds (Noah's P1 and P3 tune them on glass).
    /// The third finger lands within this of the stroke's first…
    var chordWindow: TimeInterval = 0.15
    /// …before any finger has moved this far from where it landed.
    var chordTravel: CGFloat = 24
    /// The fingers' centroid, net travel, for a swipe…
    var swipeDistance: CGFloat = 40
    /// …or this much while moving at `flickSpeed` or faster over the last `flickWindow`.
    var flickDistance: CGFloat = 20
    var flickSpeed: CGFloat = 500
    var flickWindow: TimeInterval = 0.05
    /// The swipe's axis beats the other by this.
    var axisRatio: CGFloat = 1.3
    /// The fingers' mean distance from their centroid changed by this fraction: a pinch or a spread.
    var pinchRatio: CGFloat = 0.25

    /// From arming until the next stroke's first touch: the surfaces send nothing.
    private(set) var silent = false

    // MARK: The stroke

    private struct Finger {
        let landed: CGPoint
        var now: CGPoint
    }
    /// The fingers down now, by the caller's id.
    private var fingersDown: [Int: Finger] = [:]
    /// When the stroke's first finger landed.
    private var firstAt: TimeInterval = 0
    /// Some finger moved `chordTravel` from where it landed before the stroke armed.
    private var travelled = false
    /// The system cancelled a touch of this stroke before it armed: it never arms.
    private var cancelledEarly = false
    /// The three fingers that armed the stroke, and where each was at that moment.
    private var armedBy: [Int] = []
    private var armedAt: [Int: CGPoint] = [:]
    /// The most fingers down at once since arming.
    private var fingerCount = 0
    /// The stroke has decided, or can decide nothing more (a fifth finger, a cancel).
    private var done = false
    /// The armed fingers' centroid over time, from arming, for the flick.
    private var track: [(time: TimeInterval, at: CGPoint)] = []

    private var armed: Bool { !armedBy.isEmpty }

    /// A finger lands. `holding`: a button the surface pressed is held (the trackpad's drag).
    /// Returns `.armed` once, when this finger arms the stroke.
    mutating func down(_ id: Int, at point: CGPoint, time: TimeInterval, holding: Bool) -> Output {
        if fingersDown.isEmpty {
            // A new stroke: silence, and everything else of the last one, ends here.
            silent = false
            firstAt = time
            travelled = false
            cancelledEarly = false
            armedBy = []
            armedAt = [:]
            fingerCount = 0
            done = false
            track = []
        }
        fingersDown[id] = Finger(landed: point, now: point)
        if armed {
            fingerCount = max(fingerCount, fingersDown.count)
            if fingersDown.count >= 5 { done = true }     // a fifth finger: silent, deciding nothing
            return .none
        }
        guard fingersDown.count == 3, time - firstAt <= chordWindow, !travelled, !cancelledEarly, !holding else {
            return .none
        }
        armedBy = fingersDown.keys.sorted()
        for id in armedBy { armedAt[id] = fingersDown[id]!.now }
        fingerCount = 3
        silent = true
        track = [(time, centroid(armedAt))]
        return .armed
    }

    /// A finger moves.
    mutating func moved(_ id: Int, to point: CGPoint, time: TimeInterval) {
        guard var finger = fingersDown[id] else { return }
        finger.now = point
        fingersDown[id] = finger
        if !armed {
            if distance(point, finger.landed) >= chordTravel { travelled = true }
        } else if !done, armedBy.contains(id) {
            track.append((time, centroid(nowOfArmed())))
        }
    }

    /// A finger lifts. The first lift after arming decides: `.gesture` at most once a stroke.
    mutating func up(_ id: Int, at point: CGPoint, time: TimeInterval) -> Output {
        guard var finger = fingersDown[id] else { return .none }
        finger.now = point
        fingersDown[id] = finger
        var output = Output.none
        if armed, !done {
            done = true
            if let gesture = decide(liftAt: time) { output = .gesture(gesture, fingers: min(fingerCount, 4)) }
        }
        fingersDown[id] = nil
        return output
    }

    /// A touch that is not a finger (a Pencil, the iPad's own trackpad or mouse) lands. It is never
    /// part of a stroke, but with no finger down it starts something new: the last stroke's silence
    /// ends, so a Pencil on the portrait trackpad right after a gesture is not ignored.
    mutating func otherTouch() {
        if fingersDown.isEmpty { silent = false }
    }

    /// The system took a touch (an iPadOS gesture, an alert): nothing is decided for this stroke,
    /// and one that has not armed never will; an armed one stays silent.
    mutating func cancelled(_ id: Int) {
        guard fingersDown[id] != nil else { return }
        fingersDown[id] = nil
        if armed { done = true } else { cancelledEarly = true }
    }

    // MARK: The decision

    private func nowOfArmed() -> [Int: CGPoint] {
        var out: [Int: CGPoint] = [:]
        for id in armedBy { out[id] = fingersDown[id]?.now ?? armedAt[id] }
        return out
    }

    private func decide(liftAt time: TimeInterval) -> Gesture? {
        let now = nowOfArmed()
        let start = centroid(armedAt), end = centroid(now)
        let dx = end.x - start.x, dy = end.y - start.y
        let travel = hypot(dx, dy)
        if travel >= swipeDistance || (travel >= flickDistance && speed(to: end, at: time) >= flickSpeed) {
            let major = max(abs(dx), abs(dy)), minor = min(abs(dx), abs(dy))
            if major >= axisRatio * minor {
                if abs(dx) > abs(dy) { return dx < 0 ? .swipeLeft : .swipeRight }
                return dy < 0 ? .swipeUp : .swipeDown
            }
        }
        let before = spread(armedAt, around: start), after = spread(now, around: end)
        guard before > 0 else { return nil }
        let change = after / before
        if change <= 1 - pinchRatio { return .pinch }
        if change >= 1 + pinchRatio { return .spread }
        return nil
    }

    /// The centroid's speed over the last `flickWindow` before `time`: from the last place it was at
    /// or before that moment (where it was at arming when the stroke armed later), to `end`.
    private func speed(to end: CGPoint, at time: TimeInterval) -> CGFloat {
        guard let first = track.first else { return 0 }
        var from = first
        for sample in track where sample.time <= time - flickWindow { from = sample }
        let dt = time - from.time
        guard dt > 0 else { return 0 }
        return distance(end, from.at) / CGFloat(dt)
    }

    private func centroid(_ points: [Int: CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        var x: CGFloat = 0, y: CGFloat = 0
        for id in points.keys.sorted() { x += points[id]!.x; y += points[id]!.y }
        return CGPoint(x: x / CGFloat(points.count), y: y / CGFloat(points.count))
    }

    /// The mean distance of `points` from `center`.
    private func spread(_ points: [Int: CGPoint], around center: CGPoint) -> CGFloat {
        guard !points.isEmpty else { return 0 }
        var total: CGFloat = 0
        for id in points.keys.sorted() { total += distance(points[id]!, center) }
        return total / CGFloat(points.count)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    // MARK: Sending

    /// What becomes of a decided gesture (StreamClient.sendGesture): it goes to the Mac only while
    /// this device's switch is on, a session is up, and the Mac's window list said it takes at least
    /// `generation` (`WindowList.gestures`; nil from a Mac before them, which gets none). While a
    /// window streams the Desktop is picked first, as its button does: none of the views a gesture
    /// opens is in a window's picture.
    static func sending(switchOn: Bool, connected: Bool, hostGestures: Int?, generation: Int,
                        windowStreams: Bool) -> (send: Bool, desktopFirst: Bool) {
        guard switchOn, connected, let takes = hostGestures, takes >= generation else { return (false, false) }
        return (true, windowStreams)
    }
}
