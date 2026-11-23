import CoreGraphics
import Foundation

/// The picture's touch and hold in Direct Touch (issue #178): one finger held `press` and lifted where it
/// was pressed is a right click, at the lift; held and then moved past `slop` it drags with the left
/// button, from where it was pressed to where it lifts, so a window or a control moves under the finger.
/// A tap still clicks and a finger that moves before the hold still scrolls (InputOverlay's recognizers).
/// The right click came at the hold itself before this, 0.45 s in; it waits for the lift now, as only the
/// lift tells a right click from a drag.
///
/// Behind a switch of this device's own, Settings › This iPad (This iPhone) › Hold, Then Drag (`key`), on
/// unless turned off (`defaultOn`; Noah, 2026-11-20, having tried it on his iPad mini: "hold and drag works
/// as expect it, make it on by default", over the rule that new behaviour is off unless turned on;
/// docs/steps/2026-11-19-ready-292.md). It moves the right click from the hold to the lift, so an owner who
/// wants the right click at once turns it off. Off, the hold is a right click at once, as before #178, and
/// the finger's moves and lift send nothing (`began(at:drags:)`).
///
/// Pure: CoreGraphics only, checked in Tests/checks/touch-hold. InputOverlay's long press feeds it, with
/// the switch as each hold begins (`StreamClient.holdThenDragOn`), and sends what it returns.
struct TouchHold {
    /// How long a finger is held before it right-clicks or drags (`UILongPressGestureRecognizer`'s
    /// `minimumPressDuration`).
    static let press: TimeInterval = 0.45
    /// How far the held finger moves, in points, before it drags rather than right-clicks.
    static let slop: CGFloat = 8

    /// The UserDefaults key of Hold, Then Drag (`@AppStorage` in the Settings panel). `-Sill.holdThenDrag 0`
    /// turns it off for one run, `1` on, in the normal app too. Never sent to the Mac.
    static let key = "Sill.holdThenDrag"
    /// The switch's default: on (Noah, 2026-11-20), so a hold that moves drags and one lifted in place
    /// right-clicks at the lift, until this device's owner turns it off; one who turned it off keeps it off.
    /// What the Settings panel and `StreamClient.holdThenDragOn` take while the switch was never set
    /// (`TourFeatures.holdThenDrag`'s own default, for the tour's other callers, is the same).
    static let defaultOn = true

    // MARK: Words

    /// The switch's title in the Settings panel.
    static let title = "Hold, Then Drag"
    /// Under the switch, on or off.
    static let footnote = "Touch and hold a moment, then move your finger to drag what’s under it: a window, a slider or a selection. Lift without moving to right-click. Off, touch and hold right-clicks at once."

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

    /// The hold recognized at `point`, where the overlay has already put the Mac's pointer. With Hold, Then
    /// Drag off (`drags` false), a right click there at once, as before #178, and nothing is held, so the
    /// finger's moves, its lift and a cancel send nothing; on, nothing yet: the moves and the lift decide.
    mutating func began(at point: CGPoint, drags: Bool) -> [Send] {
        guard drags else { return [.rightClick(point)] }
        start = point
        last = point
        return []
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
