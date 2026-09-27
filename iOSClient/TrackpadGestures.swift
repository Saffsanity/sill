import Foundation
import CoreGraphics

/// Three- and four-finger strokes on the device's glass, for the Mac (docs/trackpad-gestures-plan.md
/// §6.1): which stroke is a gesture, and which gesture it is. Both glass surfaces feed one of these
/// with every direct touch (StrokeObserver, InputOverlay.swift): the portrait trackpad and the stream.
///
/// A stroke runs from its first touch down to its last touch up. It goes *silent* once three fingers
/// are down, before any finger has moved `chordTravel` from where it landed and while no button the
/// surface pressed is held (the trackpad's press-and-hold drag), however slowly they came down and
/// whatever else rests on the glass. From then until the next stroke's first touch the surfaces send
/// nothing for it, no pointer motion, click, button or scroll (a tap's action runs after its touch
/// has ended, so silence outlasts the last lift). A two-finger scroll that a third finger joins after
/// moving is never silent and goes on as it always did; a stroke that never has three fingers down is
/// never silent, so one- and two-finger strokes are exactly what they were.
///
/// A silent stroke is *armed*, one that can become a gesture, when the three fingers that landed last
/// came down within `chordWindow` of each other, before any finger moved `chordTravel`, with no button
/// held, no touch of the stroke cancelled and at most four fingers down. So a thumb resting on the
/// glass before neither keeps three fingers from arming nor becomes one of them; three fingers placed
/// slowly are silent and decide nothing.
///
/// The decision comes at the first lift of one of those three (another finger lifting only leaves the
/// stroke), from their centroid's net travel since arming, and their spread. A swipe when the centroid
/// travelled `swipeDistance` (or `flickDistance` while moving at `flickSpeed` over the last
/// `flickWindow`), one axis beats the other by `axisRatio`, and the fingers moved together: each of
/// the three at least `swipeShare` of the centroid's way along the swipe, and no other finger that
/// moved (`chordTravel` or more) that share or more against it. In a pinch or a spread some digit
/// moves against the others, however far the centroid goes (a thumb-led pinch drags it along with
/// the thumb). Else a pinch or a spread when the mean distance from the centroid changed by
/// `pinchRatio`, of the three and every other finger that moved (a thumb pinching with three
/// fingers); else nothing. At most one decision per stroke; `fingers` counts the three and the other
/// fingers that moved, 4 at most. A fifth finger down leaves the stroke silent and deciding nothing;
/// touches the system cancels decide nothing. So a swipe taken back before the lift does nothing, as
/// on a Mac, and a four-finger stroke that iPadOS takes for itself (its touches cancelled) never
/// reaches the Mac.
///
/// Pure: Foundation and CoreGraphics only, checked on its own with swiftc (Tests/checks/gestures).
/// Deterministic: the same touches give the same outputs. Main thread, as the touches come.
struct TrackpadGestures {
    /// The gestures, named as kind 28 names them (TrackpadGesture). Natural direction: fingers
    /// moving left are `swipeLeft`, which brings the Space on the right.
    enum Gesture: String, Equatable, CaseIterable {
        case swipeUp, swipeDown, swipeLeft, swipeRight, pinch, spread

        /// The way a swipe's fingers move, as a unit vector in the surface's points (y grows down);
        /// nil for a pinch or a spread.
        var direction: CGVector? {
            switch self {
            case .swipeUp: return CGVector(dx: 0, dy: -1)
            case .swipeDown: return CGVector(dx: 0, dy: 1)
            case .swipeLeft: return CGVector(dx: -1, dy: 0)
            case .swipeRight: return CGVector(dx: 1, dy: 0)
            case .pinch, .spread: return nil
            }
        }
    }

    enum Output: Equatable {
        case none
        /// The stroke just went silent: close what it had opened (a scroll).
        case silenced
        /// The decision, at the first lift of a finger that armed the stroke.
        case gesture(Gesture, fingers: Int)
    }

    // The tunables, in the surface's points and seconds (Noah's P1 and P3 tune them on glass).
    /// The three fingers that arm a stroke land within this of each other…
    var chordWindow: TimeInterval = 0.15
    /// …before any finger has moved this far from where it landed (which also keeps a stroke from
    /// going silent). A finger other than the three that moved this far took part in the gesture.
    var chordTravel: CGFloat = 24
    /// The fingers' centroid, net travel, for a swipe…
    var swipeDistance: CGFloat = 40
    /// …or this much while moving at `flickSpeed` or faster over the last `flickWindow`.
    var flickDistance: CGFloat = 20
    var flickSpeed: CGFloat = 500
    var flickWindow: TimeInterval = 0.05
    /// The swipe's axis beats the other by this.
    var axisRatio: CGFloat = 1.3
    /// A swipe's fingers move together: each of the three this share of the centroid's travel along
    /// the swipe or more, and no other finger that moved this share of it or more the other way.
    var swipeShare: CGFloat = 0.5
    /// The fingers' mean distance from their centroid changed by this fraction: a pinch or a spread.
    var pinchRatio: CGFloat = 0.25

    /// From three fingers down (see above) until the next stroke's first touch: the surfaces send
    /// nothing.
    private(set) var silent = false
    /// The stroke armed: it decides at the first lift of one of its three fingers (for the checks).
    var armed: Bool { !armedBy.isEmpty }

    // MARK: The stroke

    private struct Finger {
        let landed: CGPoint
        let landedAt: TimeInterval
        var now: CGPoint
    }
    /// The fingers down now, by the caller's id.
    private var fingersDown: [Int: Finger] = [:]
    /// Some finger moved `chordTravel` from where it landed before the stroke armed.
    private var travelled = false
    /// The system cancelled a touch of this stroke before it armed: it never arms.
    private var cancelledEarly = false
    /// The three fingers that armed the stroke, and where each was at that moment.
    private var armedBy: [Int] = []
    private var armedAt: [Int: CGPoint] = [:]
    /// Every other finger of an armed stroke: where it was at arming (or landed, after), and where it
    /// is now or lifted. The ones that moved `chordTravel` took part.
    private var others: [Int: (start: CGPoint, now: CGPoint)] = [:]
    /// The stroke has decided, or can decide nothing more (a fifth finger, a cancel).
    private var done = false
    /// The armed fingers' centroid over time, from arming, for the flick.
    private var track: [(time: TimeInterval, at: CGPoint)] = []

    /// A finger lands. `holding`: a button the surface pressed is held (the trackpad's drag).
    /// Returns `.silenced` once, when this finger makes the stroke silent.
    mutating func down(_ id: Int, at point: CGPoint, time: TimeInterval, holding: Bool) -> Output {
        if fingersDown.isEmpty {
            // A new stroke: silence, and everything else of the last one, ends here.
            silent = false
            travelled = false
            cancelledEarly = false
            armedBy = []
            armedAt = [:]
            others = [:]
            done = false
            track = []
        }
        fingersDown[id] = Finger(landed: point, landedAt: time, now: point)
        if fingersDown.count >= 5 { done = true }        // a fifth finger: deciding nothing
        if armed {
            others[id] = (point, point)
            return .none
        }
        guard fingersDown.count >= 3, !travelled, !holding else { return .none }
        var output = Output.none
        if !silent {
            silent = true
            output = .silenced
        }
        // Armed by the three that landed last, when they came down within the window.
        let byLanding = fingersDown.sorted { a, b in
            a.value.landedAt != b.value.landedAt ? a.value.landedAt < b.value.landedAt : a.key < b.key
        }
        let three = byLanding.suffix(3)
        if !done, !cancelledEarly, let first = three.first, time - first.value.landedAt <= chordWindow {
            armedBy = three.map(\.key).sorted()
            for id in armedBy { armedAt[id] = fingersDown[id]!.now }
            for (id, finger) in fingersDown where armedAt[id] == nil { others[id] = (finger.now, finger.now) }
            track = [(time, centroid(armedAt))]
        }
        return output
    }

    /// A finger moves.
    mutating func moved(_ id: Int, to point: CGPoint, time: TimeInterval) {
        guard var finger = fingersDown[id] else { return }
        finger.now = point
        fingersDown[id] = finger
        if !armed {
            if distance(point, finger.landed) >= chordTravel { travelled = true }
            return
        }
        if others[id] != nil { others[id]!.now = point }
        if !done, armedBy.contains(id) { track.append((time, centroid(nowOfArmed()))) }
    }

    /// A finger lifts. The first lift of one of the three that armed the stroke decides: `.gesture` at
    /// most once a stroke. Any other finger lifting only leaves the stroke (where it lifted counts, if
    /// it moved).
    mutating func up(_ id: Int, at point: CGPoint, time: TimeInterval) -> Output {
        guard var finger = fingersDown[id] else { return .none }
        finger.now = point
        fingersDown[id] = finger
        if others[id] != nil { others[id]!.now = point }
        var output = Output.none
        if armed, !done, armedBy.contains(id) {
            done = true
            if let (gesture, fingers) = decide(liftAt: time) { output = .gesture(gesture, fingers: fingers) }
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
    /// and one that has not armed never will; a silent one stays silent.
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

    /// The gesture and its fingers, or nil for none.
    private func decide(liftAt time: TimeInterval) -> (Gesture, Int)? {
        let now = nowOfArmed()
        let start = centroid(armedAt), end = centroid(now)
        let dx = end.x - start.x, dy = end.y - start.y
        let travel = hypot(dx, dy)
        // The other fingers that took part: a thumb pinching, a fourth finger swiping along. One that
        // stayed where it was (a thumb resting) or barely moved did not.
        let movers = others.filter { distance($0.value.start, $0.value.now) >= chordTravel }
        let fingers = min(3 + movers.count, 4)
        if travel >= swipeDistance || (travel >= flickDistance && speed(to: end, at: time) >= flickSpeed) {
            let major = max(abs(dx), abs(dy)), minor = min(abs(dx), abs(dy))
            if major >= axisRatio * minor {
                let swipe: Gesture = abs(dx) > abs(dy) ? (dx < 0 ? .swipeLeft : .swipeRight) : (dy < 0 ? .swipeUp : .swipeDown)
                let axis = swipe.direction!
                let along = dx * axis.dx + dy * axis.dy
                func share(_ from: CGPoint, _ to: CGPoint) -> CGFloat { (to.x - from.x) * axis.dx + (to.y - from.y) * axis.dy }
                let together = armedBy.allSatisfy { share(armedAt[$0]!, now[$0]!) >= swipeShare * along }
                    && movers.values.allSatisfy { share($0.start, $0.now) > -swipeShare * along }
                if together { return (swipe, fingers) }
            }
        }
        // A pinch or a spread: the three and the others that moved, each from where it was at arming
        // (or landed, after) to where it is now or lifted.
        var before = armedAt, after = now
        for (id, other) in movers { before[id] = other.start; after[id] = other.now }
        let r0 = spread(before, around: centroid(before)), r1 = spread(after, around: centroid(after))
        guard r0 > 0 else { return nil }
        let change = r1 / r0
        if change <= 1 - pinchRatio { return (.pinch, fingers) }
        if change >= 1 + pinchRatio { return (.spread, fingers) }
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
