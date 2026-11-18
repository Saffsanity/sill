import CoreGraphics
import Foundation

/// The picture's touch and hold in Direct Touch (issue #178): one finger held `press` and lifted where it
/// was pressed is a right click, at the lift; held and then moved past `slop` it drags with the left
/// button, from where it was pressed to where it lifts, so a window or a control moves under the finger.
/// A tap still clicks and a finger that moves before the hold still scrolls (InputOverlay's recognizers).
/// The right click came at the hold itself before this, 0.45 s in; it waits for the lift now, as only the
/// lift tells a right click from a drag.
///
/// Pure: CoreGraphics only, checked in Tests/checks/touch-hold. InputOverlay's long press feeds it and
/// sends what it returns.
struct TouchHold {
    /// How long a finger is held before it right-clicks or drags (`UILongPressGestureRecognizer`'s
    /// `minimumPressDuration`).
    static let press: TimeInterval = 0.45
    /// How far the held finger moves, in points, before it drags rather than right-clicks.
    static let slop: CGFloat = 8

    /// What goes to the Mac, in the overlay's points.
    enum Send: Equatable {
        case leftDown(CGPoint)
        case move(CGPoint)
        case leftUp(CGPoint)
        case rightClick(CGPoint)
    }

    private var start: CGPoint?
    private var last = CGPoint.zero
    private(set) var isDragging = false

    var isHeld: Bool { start != nil }

    /// The hold recognized at `point`, where the overlay has already put the Mac's pointer.
    mutating func began(at point: CGPoint) {
        start = point
        last = point
    }

    mutating func moved(to point: CGPoint) -> [Send] {
        guard let start else { return [] }
        last = point
        if isDragging { return [.move(point)] }
        guard hypot(point.x - start.x, point.y - start.y) > Self.slop else { return [] }
        isDragging = true
        return [.leftDown(start), .move(point)]
    }

    mutating func ended(at point: CGPoint) -> [Send] {
        guard let start else { return [] }
        defer { reset() }
        return isDragging ? [.leftUp(point)] : [.rightClick(start)]
    }

    /// The hold was cancelled, or a three-finger stroke silenced it: a drag's button goes up where the
    /// finger was last, and nothing is clicked.
    mutating func cancelled() -> [Send] {
        guard start != nil else { return [] }
        defer { reset() }
        return isDragging ? [.leftUp(last)] : []
    }

    private mutating func reset() {
        start = nil
        isDragging = false
    }
}
