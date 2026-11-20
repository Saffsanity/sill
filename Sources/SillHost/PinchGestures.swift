import Foundation
import CoreGraphics
import StreamProtocol

// A device's two-finger pinch and turn, posted to the Mac as its own trackpad's magnify and rotate
// gestures (issue #260, PR #261 by mrandika; the review of 2026-11-18 added the turn). A device sends them
// (`InputEvent.magnify`, `.rotate`) only with its Pinch set to Zoom on ‹Mac› (Rotate on ‹Mac› for the turn),
// and only to a host whose window list says `pinch` 1 (`Pinch.generation`). What InputInjector posts for each:
//   - A gesture's `began` puts the Mac's pointer where it is first, as a hand on a trackpad has it there:
//     apps zoom and turn about the pointer, and a finger sends no move before its pinch. The pointer moves
//     only when it is more than a point away (`pointerSlop`), and only for the first of the two to begin:
//     the second joins the gesture already there.
//   - Every event of a gesture is posted where it began (`at`), as a trackpad's pinch never moves the pointer,
//     whatever place a device sends with the later ones.
//   - A `began` while one of its kind is open closes that one first; a `changed` or an `ended` with none open
//     (its `began` lost, or the watchdog closed it) posts nothing.
//   - Each value is bounded (`maxMagnification`, `maxDegrees`), and a value that is not a number is dropped
//     whole, phase and all.
//   - A gesture its device leaves open (a link lost mid-pinch) would hold the Mac's content in it: after
//     `idleTimeout` with no event of either, InputInjector's watchdog ends what is open (`idle`), and so does
//     the host's end (`releaseAll`), each with a value of 0 where the gesture is.
// The magnify and rotate gestures may be open together, as one hand's pinch that also turns: one place, one
// watchdog.
//
// Pure: Foundation and CoreGraphics, checked with swiftc (Tests/checks/pinch-gestures, with StreamProtocol's
// sources; its `package` access needs -package-name sill). Nothing here posts or sleeps: InputInjector posts
// each `Post` as the window server's gesture event (NSEventTypeGesture, 29) with its subtype, value and phase.
package struct PinchGestures: Equatable, Sendable {
    /// Which of the Mac's two gestures: the magnify (subtype 8, the value in field 113) or the rotate
    /// (subtype 5, the value in field 114), the private numbers AppKit reads for `NSEvent.magnification`
    /// and `NSEvent.rotation`.
    package enum Kind: String, Equatable, Sendable, CaseIterable { case magnify, rotate }

    /// One gesture event to post: its kind and phase, its value (the magnification, a fraction of the size;
    /// or the turn in degrees, counterclockwise positive) and where it goes, in the Mac's points (CG global).
    package struct Post: Equatable, Sendable {
        package var kind: Kind
        package var phase: PinchPhase
        package var value: Double
        package var at: CGPoint
        package init(_ kind: Kind, _ phase: PinchPhase, _ value: Double, at: CGPoint) {
            self.kind = kind; self.phase = phase; self.value = value; self.at = at
        }
    }

    /// What one event of a device does, in order: `ending` posted first (a gesture of its kind left open, ended
    /// where it was), then the pointer moved (nil: it stays), then `posts`.
    package struct Step: Equatable, Sendable {
        package var ending: [Post] = []
        package var movePointerTo: CGPoint?
        package var posts: [Post]
        package static let nothing = Step(movePointerTo: nil, posts: [])
    }

    /// A device's magnification for one event is a fraction of the size: never more than a doubling, nor
    /// less than nothing.
    package static let maxMagnification = 1.0
    /// A device's turn for one event: a quarter turn at most either way (a frame's turn is a few degrees).
    package static let maxDegrees = 90.0
    /// How long an open gesture may go without an event of either kind before the watchdog ends it.
    package static let idleTimeout = 1.0
    /// The pointer goes where a gesture begins only when it is further than this, in points.
    package static let pointerSlop = 1.0

    /// Whether each gesture is open: its `began` posted, its `ended` not yet.
    package private(set) var open: Set<Kind> = []
    /// Where the open gestures are: where the first of them began. Nil while none is open.
    package private(set) var at: CGPoint?

    package init() {}

    /// Whether anything is open, for the watchdog.
    package var isOpen: Bool { !open.isEmpty }

    /// One event of a device: `kind` in `phase` with its `value`, at `location` (the device's place, on the
    /// Mac), the Mac's pointer being at `pointer`.
    package mutating func apply(_ kind: Kind, _ phase: PinchPhase, value raw: Double, at location: CGPoint,
                                pointer: CGPoint) -> Step {
        guard raw.isFinite, location.x.isFinite, location.y.isFinite else { return .nothing }
        let bound = kind == .magnify ? Self.maxMagnification : Self.maxDegrees
        let value = min(max(raw, -bound), bound)
        switch phase {
        case .began:
            var ending: [Post] = []
            if open.contains(kind), let at { ending.append(Post(kind, .ended, 0, at: at)); open.remove(kind) }
            var move: CGPoint? = nil
            if at == nil || open.isEmpty {
                // The first of the two: the gesture is where the device says, and the pointer goes there.
                at = location
                if hypot(pointer.x - location.x, pointer.y - location.y) > Self.pointerSlop { move = location }
            }
            let place = at ?? location
            open.insert(kind)
            return Step(ending: ending, movePointerTo: move, posts: [Post(kind, .began, value, at: place)])
        case .changed:
            guard open.contains(kind), let at else { return .nothing }
            return Step(movePointerTo: nil, posts: [Post(kind, .changed, value, at: at)])
        case .ended:
            guard open.contains(kind), let at else { return .nothing }
            open.remove(kind)
            if open.isEmpty { self.at = nil }
            return Step(movePointerTo: nil, posts: [Post(kind, .ended, value, at: at)])
        }
    }

    /// The watchdog: `idleTimeout` passed with no event while something was open. Each open gesture ends,
    /// with a value of 0, where it is.
    package mutating func idle() -> [Post] { closeAll() }

    /// The host's end: the same, so nothing a device began outlives Sill on the Mac.
    package mutating func releaseAll() -> [Post] { closeAll() }

    private mutating func closeAll() -> [Post] {
        guard let at else { open = []; return [] }
        let posts = Kind.allCases.filter { open.contains($0) }.map { Post($0, .ended, 0, at: at) }
        open = []
        self.at = nil
        return posts
    }
}
