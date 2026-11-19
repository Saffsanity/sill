import CoreGraphics
import Foundation

/// Pinch to zoom on the stream picture (issue #65; Noah's decisions of 2026-10-19 and 2026-10-20): two
/// fingers on the picture zoom it from 1× to 5×, centred on the pinch (the midpoint between the
/// fingers) as a photo in Photos is, and move it with that midpoint; no slider, and the Mac's pointer
/// is not involved (no zoom about the cursor, no view following it). A slight pinch out leaves the
/// picture where it is; only a pinch all the way out gives back the whole picture. The zoom is this
/// device's alone: nothing is sent, and the Mac's window and the viewport stay as they are.
///
/// The picture is drawn scaled about the pane's middle, then moved by `offset` (`ZoomedStreamView`:
/// `.scaleEffect(scale).offset(offset)` on the stream's view), so a point `u` of the pane as it is at
/// 1× shows at `c + scale·(u − c) + offset`, `c` the pane's middle. The offset stays within
/// `±size·(scale − 1)/2` on each axis, so the zoomed picture always covers its pane. The input view
/// takes every touch back through `unzoomedPoint` before it makes it a fraction of the frame, and a
/// scroll's movement through `unzoomedDelta`, so a tap, a click, the Pencil, a hover and a scroll land
/// on the pixel shown under the finger, and the content under a scrolling finger moves with it.
///
/// Who a stroke on the picture belongs to, the Mac or the picture, is `Stroke`'s.
/// Pure: CoreGraphics and Foundation (Tests/checks/stream-zoom).
struct StreamZoom: Equatable, Sendable {
    static let minScale: CGFloat = 1
    static let maxScale: CGFloat = 5
    /// A stroke that leaves the picture under this is the whole picture again (`settle`): the 1 % or so
    /// between them shows nothing more, and two fingers on a picture that looks whole would otherwise
    /// move it rather than scroll the Mac (`Stroke`).
    static let wholeBelow: CGFloat = 1.02

    /// 1 to 5.
    private(set) var scale: CGFloat = 1
    /// How far the scaled picture is moved, in the pane's points; zero at 1×.
    private(set) var offset: CGSize = .zero
    /// The pane the offset was made in: the last pinch's, or the last `resized(to:)`.
    private(set) var pane: CGSize = .zero

    var isZoomed: Bool { scale > Self.minScale }

    /// The whole picture.
    mutating func reset() {
        scale = Self.minScale
        offset = .zero
    }

    /// One step of a pinch in a pane of `size`: the scale times `factor` (kept to 1×–5×), and the point
    /// of the picture that was under `from` (the fingers' last midpoint) now under `to` (their midpoint
    /// now), as far as the pane's edges allow. Reaching 1× is the whole picture, centred.
    mutating func pinch(factor: CGFloat, from: CGPoint, to: CGPoint, in size: CGSize) {
        guard size.width > 0, size.height > 0, factor > 0, factor.isFinite else { return }
        pane = size
        let oldScale = max(Self.minScale, scale)
        let nextScale = min(Self.maxScale, max(Self.minScale, oldScale * factor))
        if nextScale <= Self.minScale + 0.001 {
            reset()
            return
        }
        let cx = size.width / 2
        let cy = size.height / 2
        let ratio = nextScale / oldScale
        let rawX = (to.x - cx) - (from.x - cx - offset.width) * ratio
        let rawY = (to.y - cy) - (from.y - cy - offset.height) * ratio
        let maxX = size.width * (nextScale - 1) / 2
        let maxY = size.height * (nextScale - 1) / 2
        scale = nextScale
        offset = CGSize(
            width: min(maxX, max(-maxX, rawX)),
            height: min(maxY, max(-maxY, rawY))
        )
    }

    /// The stroke that zoomed is over: a picture left within `wholeBelow` of the whole is the whole one.
    mutating func settle() {
        if scale < Self.wholeBelow { reset() }
    }

    /// The pane is another size (a turn, the other layout, Split View or Stage Manager, a fold of the
    /// iPhone Duo, Larger Picture's pane at the picture's shape): the zoom stays, and so does the point
    /// of the picture at the pane's middle (the offset in proportion, which keeps it inside the edges).
    mutating func resized(to size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        defer { pane = size }
        guard isZoomed, pane.width > 0, pane.height > 0, pane != size else { return }
        let maxX = size.width * (scale - 1) / 2
        let maxY = size.height * (scale - 1) / 2
        offset = CGSize(width: min(maxX, max(-maxX, offset.width * size.width / pane.width)),
                        height: min(maxY, max(-maxY, offset.height * size.height / pane.height)))
    }

    /// A point of the pane on screen, back to where it is in the picture at 1×: what the input view
    /// takes as a fraction of the frame.
    func unzoomedPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
        guard isZoomed, size.width > 0, size.height > 0 else { return point }
        let cx = size.width / 2
        let cy = size.height / 2
        let s = max(Self.minScale, scale)
        return CGPoint(
            x: cx + (point.x - cx - offset.width) / s,
            y: cy + (point.y - cy - offset.height) / s
        )
    }

    /// Where a point of the picture at 1× shows on screen now (`unzoomedPoint`'s inverse).
    func zoomedPoint(_ point: CGPoint, in size: CGSize) -> CGPoint {
        guard isZoomed, size.width > 0, size.height > 0 else { return point }
        let cx = size.width / 2
        let cy = size.height / 2
        return CGPoint(x: cx + (point.x - cx) * scale + offset.width,
                       y: cy + (point.y - cy) * scale + offset.height)
    }

    /// The part of the picture at 1× that shows in a pane of `size`, in its points.
    func visibleRect(in size: CGSize) -> CGRect {
        let origin = unzoomedPoint(.zero, in: size)
        let s = max(Self.minScale, scale)
        return CGRect(x: origin.x, y: origin.y, width: size.width / s, height: size.height / s)
    }

    /// A scroll's movement on screen, in the picture's points at 1×: the content under the fingers
    /// moves as far as they do (a finger's, a trackpad's and a wheel's alike, as a zoomed scroll view's
    /// on iPadOS), whatever the zoom. Reverse Scrolling turns it around afterwards.
    func unzoomedDelta(_ delta: CGPoint) -> CGPoint {
        let s = max(Self.minScale, scale)
        return CGPoint(x: delta.x / s, y: delta.y / s)
    }
}

extension StreamZoom {
    /// Who a stroke on the picture belongs to. One finger is always the Mac's (a tap, a hold, a drag's
    /// scroll), as before the zoom. Two fingers at 1× are the Mac's scroll, as before, unless they pinch
    /// first: their spacing changes more than their midpoint moves (`pinchTravel`, before the finger
    /// pan begins; when it begins, `panBegan`), and then they are the picture's. On a zoomed picture any
    /// two fingers are the picture's, as in Photos: they pinch it and move it, and one finger still
    /// scrolls the Mac. Three fingers are the Mac's gesture (TrackpadGestures, `silenced`), and the
    /// picture goes back to how the stroke found it. Once decided, a stroke keeps its owner until its
    /// last finger lifts, so a scroll never turns into a zoom halfway, and a pinch's fingers never
    /// scroll the Mac when one of them lifts.
    ///
    /// Fed every direct touch on the picture, in the pane's points, by the input view's stroke observer
    /// (each touch's id as it landed; a touch event's moves together, so one event is one step); told
    /// when the finger pan begins and when three fingers take the stroke. While the picture owns the stroke, the first two fingers down drive it: the factor is
    /// their spacing now over their spacing at the last step, the midpoint theirs, and from the moment
    /// they pinch it catches up from where they landed, so the point of the picture that was under them
    /// stays under them.
    ///
    /// Under Pinch's Zoom on ‹Mac› (PinchRouting, PR #261) the same rule decides, and a pinch is the Mac's
    /// own instead of the picture's (`Target.mac`, `Owner.macPinch`): its steps are the Mac's magnify and,
    /// with Rotate on ‹Mac›, rotate gestures (`macSteps`), and nothing zooms. Then fingers that turn more
    /// than their midpoint moves are a pinch too, as fingers that spread are. One rule for both, so a stroke
    /// is the Mac's scroll or its pinch, never both. On a trackpad of Sill's own the same, at its pointer
    /// (TrackpadSurface).
    struct Stroke: Equatable, Sendable {
        enum Owner: Equatable, Sendable {
            /// No finger down.
            case none
            /// Fingers down, the stroke not decided.
            case undecided
            /// The Mac's: the finger pan scrolls it. The picture stays as it is.
            case mac
            /// The picture's: two fingers pinch and move it. Nothing goes to the Mac.
            case picture
            /// The Mac's own pinch (`Target.mac`): two fingers that pinch, or turn with Rotate on ‹Mac›, pinch
            /// and turn what is under them on the Mac (`macSteps`). Nothing zooms here, and nothing scrolls.
            case macPinch
            /// Three fingers: a gesture for the Mac (TrackpadGestures). The picture as the stroke found it.
            case gesture
        }

        /// What a stroke's pinch is for, taken as its first finger lands (PinchRouting): the picture's zoom
        /// (Zoom Picture, the default, and on every Mac that cannot take a pinch), or the Mac's own pinch,
        /// and its turn with Rotate on ‹Mac› (`turns`).
        enum Target: Equatable, Sendable {
            case picture
            case mac(turns: Bool)
            var turns: Bool { if case .mac(true) = self { return true } else { return false } }
        }

        /// One step of the Mac's pinch or turn, in order, for the caller to send at `macAt` (InputEvent.magnify,
        /// .rotate): each opens once its own measure from where the pair landed passes `pinchTravel` (the
        /// spacing's change; the turn's arc, each finger's travel about their midpoint), catching up from there,
        /// then changes by what moved since its last step, and ends when the pair breaks or the stroke does.
        enum MacStep: Equatable, Sendable {
            enum Phase: Equatable, Sendable { case began, changed, ended }
            /// `amount`: the spacing now over the spacing at the last step, less 1 (NSEvent.magnification's unit).
            case magnify(Phase, amount: Double)
            /// `degrees`: the turn since the last step, counterclockwise positive as the Mac's (the pane's y runs
            /// down, so its own angle turns the other way).
            case rotate(Phase, degrees: Double)
        }

        /// How far two fingers' spacing changes, more than their midpoint moves, before the finger pan
        /// begins, for a pinch: the picture's.
        static let pinchTravel: CGFloat = 12
        /// Two fingers closer than this tell no scale (they are one on the glass).
        static let minSpacing: CGFloat = 1

        private(set) var owner: Owner = .none
        /// What the stroke's pinch is for, from its first finger on.
        private(set) var target: Target = .picture
        /// What the last call gave the Mac's pinch and turn, in order; empty when it gave nothing. Each call
        /// starts it afresh, so the caller sends it after each.
        private(set) var macSteps: [MacStep] = []
        /// Where the Mac's pinch and turn are, in the pane's points: the pair's midpoint where it landed, as
        /// the stroke's first gesture for the Mac opened. Kept for the stroke, as a trackpad keeps its pointer.
        private(set) var macAt: CGPoint? = nil
        /// The Mac's pinch, while open: the pair's spacing at its last step. Its turn, while open: the pair's
        /// angle at its last step (radians, the pane's).
        private var magnifyLast: CGFloat? = nil
        private var rotateLast: CGFloat? = nil
        /// Every finger down, where it is now.
        private var at: [Int: CGPoint] = [:]
        /// The two fingers that drive the picture, in the order they landed.
        private var pair: [Int] = []
        /// Where they were when the second landed, and at the last step taken.
        private var pairFrom: [CGPoint] = []
        private var pairLast: [CGPoint] = []
        /// The zoom as the stroke found it, and as its last step left it.
        private var before: StreamZoom? = nil
        private var made: StreamZoom? = nil

        /// The finger pan may scroll the Mac: the stroke is the Mac's, or no finger of it was seen (as
        /// before the zoom).
        var scrollsMac: Bool { owner == .mac || owner == .none }
        /// Fingers down now.
        var fingers: Int { at.count }

        /// A finger lands at `point`. Two fingers down make the pair; on a zoomed picture they are the
        /// picture's at once, and so are two down again after one of a picture's pair lifted.
        /// `target`: what a pinch of the stroke is for, read at its first finger (PinchRouting).
        mutating func down(_ id: Int, at point: CGPoint, zoom: StreamZoom, target: Target = .picture) {
            macSteps = []
            if owner == .none {
                owner = .undecided
                before = zoom
                self.target = target
            }
            at[id] = point
            guard owner == .undecided || owner == .picture || owner == .macPinch, pair.count < 2, at.count == 2 else { return }
            formPair()
            if owner == .undecided, self.target == .picture, zoom.isZoomed { owner = .picture }
        }

        /// Fingers move, one touch event's together (each id to where it is now): while the picture owns
        /// the stroke, its pair's move is one step of the pinch in a pane of `size`. True when the zoom
        /// changed.
        @discardableResult
        mutating func moved(_ moves: [Int: CGPoint], zoom: inout StreamZoom, in size: CGSize) -> Bool {
            macSteps = []
            var seen = false
            for (id, point) in moves where at[id] != nil {
                at[id] = point
                seen = true
            }
            guard seen, pair.count == 2, pair.contains(where: { moves[$0] != nil }),
                  let a = at[pair[0]], let b = at[pair[1]] else { return false }
            if owner == .undecided {
                let (spacing, travel) = Self.change(from: pairFrom, to: [a, b])
                let pinched = max(spacing, target.turns ? Self.turnTravel(from: pairFrom, to: [a, b]) : 0)
                guard pinched >= Self.pinchTravel, pinched > travel else { return false }
                owner = target == .picture ? .picture : .macPinch   // a pinch: caught up from where the pair landed (pairLast == pairFrom)
            }
            if owner == .macPinch {
                macStep(to: [a, b])
                return false
            }
            guard owner == .picture else { return false }
            let last = pairLast
            pairLast = [a, b]
            let was = Self.distance(last[0], last[1]), now = Self.distance(a, b)
            guard was >= Self.minSpacing, now >= Self.minSpacing else { return false }
            let before = zoom
            zoom.pinch(factor: now / was, from: Self.midpoint(last[0], last[1]), to: Self.midpoint(a, b), in: size)
            made = zoom
            return zoom != before
        }

        /// The finger pan began (its fingers' midpoint moved UIKit's hysteresis): the Mac's scroll, unless
        /// the stroke is already the picture's (a pinch, two fingers on a zoomed picture) or its two
        /// fingers' spacing has changed more than their midpoint moved (a pinch whose midpoint moved
        /// too). A tie is the Mac's, as before the zoom.
        mutating func panBegan() {
            macSteps = []
            guard owner == .undecided else { return }
            if pair.count == 2, let a = at[pair[0]], let b = at[pair[1]] {
                let (spacing, travel) = Self.change(from: pairFrom, to: [a, b])
                let pinched = max(spacing, target.turns ? Self.turnTravel(from: pairFrom, to: [a, b]) : 0)
                if pinched > travel {
                    owner = target == .picture ? .picture : .macPinch
                    if owner == .macPinch { macStep(to: [a, b]) }
                    return
                }
            }
            owner = .mac
        }

        /// A finger lifts, or UIKit cancels it (the system took the touch). One of a picture's pair
        /// lifting leaves the picture where it is (two fingers down again carry on); the last finger
        /// ends the stroke, and a picture left within `wholeBelow` of the whole is the whole one. True
        /// when the zoom changed.
        @discardableResult
        mutating func up(_ id: Int, zoom: inout StreamZoom) -> Bool {
            macSteps = []
            guard at.removeValue(forKey: id) != nil else { return false }
            if pair.contains(id) {
                pair = []
                pairFrom = []
                pairLast = []
                if owner == .picture, at.count == 2 { formPair() }
                // The Mac's pinch and turn end with their pair, as a trackpad's do when a finger lifts; two
                // fingers down again open them afresh from where those landed, at the stroke's place.
                if owner == .macPinch { closeMac(); if at.count == 2 { formPair() } }
            }
            guard at.isEmpty else { return false }
            let steps = macSteps
            let ended = owner
            self = Stroke()
            macSteps = steps
            guard ended == .picture else { return false }
            let before = zoom
            zoom.settle()
            return zoom != before
        }

        /// Three fingers took the stroke for a gesture: the picture goes back to how the stroke found
        /// it, and the stroke's fingers do nothing more here. True when the zoom changed.
        @discardableResult
        mutating func silenced(zoom: inout StreamZoom) -> Bool {
            macSteps = []
            let was = owner
            owner = .gesture
            pair = []
            pairFrom = []
            pairLast = []
            // The Mac's pinch and turn end where they are: what the Mac did with them is its own.
            if was == .macPinch { closeMac() }
            // Only a zoom this stroke made: one changed meanwhile by something else (another source, a
            // new session) stays as it is.
            guard was == .picture, let before, let made, zoom == made, before != zoom else { return false }
            zoom = before
            return true
        }

        /// One step of the Mac's pinch and turn, the pair now at `now` (`macSteps`): each opens once its own
        /// measure from where the pair landed passes `pinchTravel`, with a began and then its catch-up, and
        /// from then on changes by what moved since its last step.
        private mutating func macStep(to now: [CGPoint]) {
            guard pairFrom.count == 2, now.count == 2 else { return }
            let spacing = Self.distance(now[0], now[1])
            guard spacing >= Self.minSpacing else { return }
            let angle = Self.angle(now[0], now[1])
            let landed = Self.distance(pairFrom[0], pairFrom[1])
            if let last = magnifyLast {
                if spacing != last {
                    macSteps.append(.magnify(.changed, amount: Double(spacing / last - 1)))
                    magnifyLast = spacing
                }
            } else if landed >= Self.minSpacing, abs(spacing - landed) >= Self.pinchTravel {
                if macAt == nil { macAt = Self.midpoint(pairFrom[0], pairFrom[1]) }
                macSteps.append(.magnify(.began, amount: 0))
                macSteps.append(.magnify(.changed, amount: Double(spacing / landed - 1)))
                magnifyLast = spacing
            }
            guard target.turns else { return }
            if let last = rotateLast {
                let turn = Self.turned(from: last, to: angle)
                if turn != 0 {
                    macSteps.append(.rotate(.changed, degrees: Self.macDegrees(turn)))
                    rotateLast = angle
                }
            } else if Self.turnTravel(from: pairFrom, to: now) >= Self.pinchTravel {
                if macAt == nil { macAt = Self.midpoint(pairFrom[0], pairFrom[1]) }
                macSteps.append(.rotate(.began, degrees: 0))
                macSteps.append(.rotate(.changed, degrees: Self.macDegrees(Self.turned(from: Self.angle(pairFrom[0], pairFrom[1]), to: angle))))
                rotateLast = angle
            }
        }

        /// The Mac's pinch and turn end, each that is open, the pinch first.
        private mutating func closeMac() {
            if magnifyLast != nil { macSteps.append(.magnify(.ended, amount: 0)); magnifyLast = nil }
            if rotateLast != nil { macSteps.append(.rotate(.ended, degrees: 0)); rotateLast = nil }
        }

        /// The two fingers down, in the order they landed.
        private mutating func formPair() {
            pair = at.keys.sorted()
            pairFrom = pair.compactMap { at[$0] }
            pairLast = pairFrom
        }

        /// How much two fingers' spacing changed, and how far their midpoint moved.
        static func change(from: [CGPoint], to: [CGPoint]) -> (spacing: CGFloat, travel: CGFloat) {
            guard from.count == 2, to.count == 2 else { return (0, 0) }
            let spacing = abs(distance(to[0], to[1]) - distance(from[0], from[1]))
            let travel = distance(midpoint(to[0], to[1]), midpoint(from[0], from[1]))
            return (spacing, travel)
        }

        static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
        /// The pair's angle in the pane (radians; the pane's y runs down, so it grows clockwise on screen).
        static func angle(_ a: CGPoint, _ b: CGPoint) -> CGFloat { atan2(b.y - a.y, b.x - a.x) }
        /// The turn from one angle to another, the shorter way round (-π to π).
        static func turned(from: CGFloat, to: CGFloat) -> CGFloat {
            var d = to - from
            while d > .pi { d -= 2 * .pi }
            while d <= -.pi { d += 2 * .pi }
            return d
        }
        /// How far two fingers' turn moved each of them about their midpoint (the arc at half their spacing
        /// now), to weigh against their spacing's change and their midpoint's travel.
        static func turnTravel(from: [CGPoint], to: [CGPoint]) -> CGFloat {
            guard from.count == 2, to.count == 2 else { return 0 }
            return abs(turned(from: angle(from[0], from[1]), to: angle(to[0], to[1]))) * distance(to[0], to[1]) / 2
        }
        /// A turn in the pane as the Mac's degrees: counterclockwise positive (NSEvent.rotation).
        static func macDegrees(_ turn: CGFloat) -> Double { -Double(turn) * 180 / .pi }
        static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint { CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
    }
}
