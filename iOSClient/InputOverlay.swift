import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass
import GameController
import StreamProtocol

/// The touch layer over the streamed video. Direct-touch model: where you touch is where the Mac's
/// pointer goes, and the Apple Pencil is the mouse. Everything leaves here as an `InputEvent` whose
/// position is a fraction of the *video frame*, not of this view — the video is drawn aspect-fit by
/// `HEVCDisplayView`, so the letterbox has to be taken out before normalizing.
///
/// It is also where the keyboard goes: keys and typed text reach the Mac only while this view is first
/// responder, which its `InputOverlayProxy` decides (HardwareKeyboardPolicy: by itself whenever a
/// hardware keyboard is attached, else with the Keyboard button), and a trackpad's or a mouse's
/// scrolling over the picture comes here too (docs/hardware-keyboard-plan.md).
final class InputOverlayView: UIView, UIKeyInput, UIGestureRecognizerDelegate {
    /// Pixel size of the streamed frame. Zero until the host's parameter sets arrive; input is
    /// ignored until then, since there is nothing on screen to aim at.
    var videoSize: CGSize = .zero
    var send: (InputEvent) -> Void = { _ in }
    /// Who decides when this view holds the keyboard, told when it joins or leaves a window and when it
    /// becomes or resigns first responder (only the proxy's current view counts).
    weak var keyboardProxy: InputOverlayProxy?
    /// This view holds the keyboard for a hardware keyboard, not as the person's own: an empty input
    /// view, so iPadOS draws no keyboard and no shortcuts bar over the stream (`inputView`).
    private(set) var holdsForHardwareKeyboard = false
    /// What the proxy asked for (`take`), while UIKit makes this view first responder; nil when UIKit
    /// does it by itself.
    private var askedAutomatic: Bool?
    /// The input view while the hardware keyboard holds the keyboard: nothing, zero tall.
    private lazy var emptyInputView = UIView(frame: .zero)
    /// The assistant item's groups, put back when the person's own keyboard holds it.
    private var assistantGroups: (leading: [UIBarButtonItemGroup], trailing: [UIBarButtonItemGroup])?

    /// Modifiers the portrait key row is holding down for the next keystroke. Empty in landscape
    /// unless the user latched one before rotating.
    var latchedModifiers: KeyModifiers = []
    /// Fires once a latch has been spent, so the key row can un-highlight itself.
    var onModifiersConsumed: (() -> Void)?

    /// Writes this device's own pointer and what drew it (`StreamClient.setOwnPointer`: a fraction of
    /// the video frame, nil for none). Only ever alongside what is sent anyway; it never sends
    /// anything itself. Everything here hands this device the pointer, and none of it shows an arrow
    /// by default (docs/pointer-visibility-plan.md, "What the device draws"): a finger is its own
    /// feedback and has just moved the Mac's cursor out from under it; the iPad's own trackpad or
    /// mouse has iPadOS's pointer; typing and keys stand in for the Mac hiding its cursor while you
    /// type. The Pencil's position is kept, from `.pencil`, and drawn only with Q2's flip
    /// (`PointerPresence.pencilShowsPointer`), in any layout, as a Pencil here is a mouse.
    var setOwnPointer: (CGPoint?, PointerPresence.Origin) -> Void = { _, _ in }

    /// Pan translation already turned into scroll, so each callback sends only the new delta.
    private var lastPanTranslation: CGPoint = .zero
    /// True between the `.scrollGesture(.began)` this view sent and its `.ended`, so an end is
    /// never sent for a pan that could not begin (no video yet).
    private var scrollGestureOpen = false
    /// The coast after a flick.
    private let momentum = ScrollMomentum()
    /// True once the hover in progress has shown itself to be a Pencil. Sticky for the session so a
    /// Pencil reading zero for a moment at the bottom of its range does not flicker the pointer.
    private var hoverIsPencil = false
    /// A three- or four-finger gesture this view decided, for the Mac (`StreamClient.sendGesture`,
    /// which checks this device's switch and the Mac's `gestures`, and shows the Desktop first while
    /// a window streams). True when it went.
    var sendGesture: (TrackpadGestures.Gesture, Int) -> Bool = { _, _ in false }
    /// Every direct touch, for three-finger strokes: from the moment three fingers are down, nothing
    /// of the stroke reaches the Mac but its gesture (`strokes.silent`, each finger handler's first
    /// line).
    private let strokes = StrokeObserver()
    /// The finger pan, for where a scroll that a stroke's silence closes ends.
    private weak var scrollPan: UIPanGestureRecognizer?
    /// The iPad's trackpad (two fingers) or a Magic Mouse, and a mouse's wheel: scroll events over the
    /// picture, which carry no touch (`handleTrackpadScroll`, `handleWheel`).
    private weak var trackpadScroll: UIPanGestureRecognizer?
    private weak var wheelScroll: UIPanGestureRecognizer?
    /// The Pencil's hover and the iPad's pointer, which the pointer's scrolls recognize alongside.
    private weak var hover: UIHoverGestureRecognizer?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = true

        // Every finger recognizer is direct-touch only. Two reasons: a Pencil drag must never also
        // scroll, and a recognizer that does not track a touch does not cancel it, so Pencil touches
        // reach touchesBegan/Moved/Ended below intact.
        let directOnly = [NSNumber(value: UITouch.TouchType.direct.rawValue)]

        // One tap recognizer, no double-tap recognizer, and deliberately no `require(toFail:)`.
        // Requiring a double tap to fail first delays *every* click by UIKit's double-tap window
        // (~0.35 s), which is the worst thing you can do to the primary interaction of a remote
        // desktop. Instead each tap sends its own down/up immediately; two quick taps therefore
        // arrive as two quick down/up pairs and the host's own click timing turns them into a
        // double-click, exactly as it would for a real mouse.
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.numberOfTapsRequired = 1
        tap.allowedTouchTypes = directOnly
        addGestureRecognizer(tap)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        longPress.minimumPressDuration = 0.45
        longPress.allowedTouchTypes = directOnly
        addGestureRecognizer(longPress)

        // One or two fingers scroll; the Mac gets the content delta, not a drag.
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 2
        pan.allowedTouchTypes = directOnly
        pan.delegate = self
        addGestureRecognizer(pan)

        // Pencil hover on the iPads that support it, and the trackpad/mouse pointer everywhere.
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover))
        addGestureRecognizer(hover)
        self.hover = hover

        // The iPad's own trackpad and mouse scroll with scroll events, not touches, which only a pan
        // that allows them gets (#68): one for a trackpad's two fingers (continuous: a gesture with a
        // lift, then Sill's own coast, as a finger's), one for a wheel (discrete: plain deltas). Scroll
        // events only: no touch, so a click or a drag with the trackpad stays the pointer's
        // (`touchesBegan`), and a finger stays the finger pan's.
        let pointerOnly = [NSNumber(value: UITouch.TouchType.indirectPointer.rawValue)]
        for (mask, action) in [(UIScrollTypeMask.continuous, #selector(handleTrackpadScroll)),
                               (UIScrollTypeMask.discrete, #selector(handleWheel))] {
            let scroll = UIPanGestureRecognizer(target: self, action: action)
            scroll.allowedScrollTypesMask = mask
            scroll.maximumNumberOfTouches = 0
            scroll.allowedTouchTypes = pointerOnly
            scroll.delegate = self
            addGestureRecognizer(scroll)
            if mask == .continuous { trackpadScroll = scroll } else { wheelScroll = scroll }
        }

        // Three fingers or more: a gesture for the Mac, never a click, a right click or a scroll
        // (StrokeObserver, TrackpadGestures). It only watches: it takes no touch from the
        // recognizers above and delays none.
        scrollPan = pan
        strokes.onSilenced = { [weak self] in self?.strokeSilenced() }
        strokes.onGesture = { [weak self] gesture, fingers in _ = self?.sendGesture(gesture, fingers) }
        addGestureRecognizer(strokes)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Coordinates

    /// Where the layer actually draws the video inside this view.
    private var videoRect: CGRect { HEVCDisplayView.videoRect(in: bounds, videoSize: videoSize) }

    /// A point in this view as a fraction of the video frame. Points in the letterbox are clamped to
    /// the video's edge when `clamped` (moves and drags should keep working past the edge) and
    /// rejected otherwise (a tap on the black bars is not a click on the Mac).
    private func normalized(_ point: CGPoint, clamped: Bool) -> (x: Double, y: Double)? {
        let rect = videoRect
        guard rect.width > 0, rect.height > 0 else { return nil }
        let x = (point.x - rect.minX) / rect.width
        let y = (point.y - rect.minY) / rect.height
        if x < 0 || x > 1 || y < 0 || y > 1 {
            guard clamped else { return nil }
            return (Double(min(max(x, 0), 1)), Double(min(max(y, 0), 1)))
        }
        return (Double(x), Double(y))
    }

    /// Sends `action` at `point` and returns the frame fraction it went out at, or nil when the point
    /// was rejected (the letterbox, or no video yet) and nothing was sent.
    @discardableResult
    private func sendPointer(_ action: PointerAction, at point: CGPoint, clamped: Bool) -> CGPoint? {
        guard let p = normalized(point, clamped: clamped) else { return nil }
        send(.pointer(action, x: p.x, y: p.y))
        return CGPoint(x: p.x, y: p.y)
    }

    // MARK: - Finger gestures

    /// Single tap: put the pointer there first, then click. The move matters — the Mac's cursor is
    /// wherever the last event left it, and hover state (menus, tooltips) follows it.
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard !strokes.silent else { return }
        tap(at: gesture.location(in: self))
    }

    /// A finger's tap at `point`, in this view: the pointer goes there, then clicks.
    private func tap(at point: CGPoint) {
        setOwnPointer(nil, .none)
        guard sendPointer(.move, at: point, clamped: false) != nil else { return }
        sendPointer(.leftDown, at: point, clamped: false)
        sendPointer(.leftUp, at: point, clamped: false)
    }

    /// Long press: the right button, since there is no second finger to spare for it.
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard !strokes.silent else { return }
        guard gesture.state == .began else { return }
        setOwnPointer(nil, .none)
        let point = gesture.location(in: self)
        guard sendPointer(.move, at: point, clamped: false) != nil else { return }
        sendPointer(.rightDown, at: point, clamped: false)
        sendPointer(.rightUp, at: point, clamped: false)
    }

    /// Finger pan: scrolling, not dragging, shaped like a Mac trackpad gesture so the Mac
    /// rubber-bands at the edges and coasts after a flick:
    /// `.began` → one `.scroll` per callback → `.ended`, then maybe momentum (`startMomentum`).
    /// Deltas are fractions of the video rect, natural sign (finger down = content down =
    /// positive dy).
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard !strokes.silent else { return }
        scroll(gesture, .finger)
    }

    /// The iPad's trackpad (two fingers) or a Magic Mouse over the picture: the finger pan's path, at
    /// the pointer, with its lift's coast. iPadOS hands a pan no momentum of its own (a scroll view
    /// decelerates by itself; in the simulator, scroll events marked as momentum after a scroll's end
    /// never reached a pan), so the coast is Sill's alone, as a finger's.
    @objc private func handleTrackpadScroll(_ gesture: UIPanGestureRecognizer) { scroll(gesture, .trackpad) }

    /// A mouse's wheel over the picture: plain deltas at the pointer, no gesture around them and no
    /// coast, which the Mac posts as a wheel's.
    @objc private func handleWheel(_ gesture: UIPanGestureRecognizer) { scroll(gesture, .wheel) }

    /// Where a scroll on the picture comes from: a finger, the iPad's trackpad, or a wheel.
    enum ScrollSource: String {
        case finger, trackpad, wheel
        /// A gesture with phases around its deltas (the Mac rubber-bands and springs back), and a
        /// lift that coasts: a finger and a trackpad. A wheel's deltas are plain.
        var phased: Bool { self != .wheel }
    }

    private func scroll(_ gesture: UIPanGestureRecognizer, _ source: ScrollSource) {
        scroll(gesture.state, at: gesture.location(in: self), translation: gesture.translation(in: self),
               velocity: gesture.state == .ended ? gesture.velocity(in: self) : .zero, from: source)
    }

    /// Every scroll on the picture, finger, trackpad or wheel: `state`, where it is (the finger, or the
    /// pointer), its translation since it began and, at its end, its velocity (points per second).
    func scroll(_ state: UIGestureRecognizer.State, at location: CGPoint, translation: CGPoint,
                velocity: CGPoint, from source: ScrollSource) {
        switch state {
        case .began:
            setOwnPointer(nil, .none)
            lastPanTranslation = .zero
            // A new pan while the last flick is still coasting ends the coast first, so the Mac
            // sees momentumEnded before this gesture's began. (touchesBegan has usually done it.)
            momentum.stop()
            guard let p = normalized(location, clamped: true) else { return }
            if source.phased {
                send(.scrollGesture(.began, x: p.x, y: p.y))
                scrollGestureOpen = true
            }
            // A trackpad's or a wheel's first scroll event begins the pan with its delta already in the
            // translation, and a wheel's single notch has no change after it (measured in the iOS 27
            // simulator: began at 3 pt, ended 0.2 s later at 3 pt): sent here. A finger's pan begins
            // once it has moved, and its first change carries that, as always.
            if source != .finger { scrolled(to: translation, at: location) }
        case .changed:
            scrolled(to: translation, at: location)
        case .ended, .cancelled:
            // What a trackpad's or a wheel's last event moved, if its change never came.
            if source != .finger, state == .ended { scrolled(to: translation, at: location) }
            lastPanTranslation = .zero
            // A wheel never opened a gesture: nothing to close, and no coast.
            guard scrollGestureOpen else { return }
            scrollGestureOpen = false
            let p = normalized(location, clamped: true) ?? (x: 0.5, y: 0.5)
            send(.scrollGesture(.ended, x: p.x, y: p.y))
            // Only a real lift coasts. A cancel means the system took the touch (an alert, a
            // system gesture), and flinging the Mac's content then would be a surprise.
            if state == .ended { startMomentum(velocity: velocity, at: p) }
        default:
            lastPanTranslation = .zero
        }
    }

    /// The scroll from the last translation sent to `translation`, as fractions of the picture, at
    /// `location`: nothing when it has not moved, or before there is a picture.
    private func scrolled(to translation: CGPoint, at location: CGPoint) {
        let rect = videoRect
        guard rect.width > 0, rect.height > 0 else { return }
        let dx = (translation.x - lastPanTranslation.x) / rect.width
        let dy = (translation.y - lastPanTranslation.y) / rect.height
        lastPanTranslation = translation
        guard dx != 0 || dy != 0, let p = normalized(location, clamped: true) else { return }
        send(.scroll(x: p.x, y: p.y, dx: Double(dx), dy: Double(dy)))
    }

    // MARK: Which recognizer may scroll

    /// One scroll at a time: none of the finger pan, the trackpad's and the wheel's begins while
    /// another's gesture is open, so the Mac never gets two gestures' phases interleaved. Nothing else
    /// changes for the finger pan: no other scroll was ever open before these.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === scrollPan || gestureRecognizer === trackpadScroll || gestureRecognizer === wheelScroll {
            return !scrollGestureOpen
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    /// The pointer's scrolls take scroll events only: no touch at all (UIKit asks this for touches, not
    /// for scroll events).
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        !(gestureRecognizer === trackpadScroll || gestureRecognizer === wheelScroll)
    }

    /// The pointer's scrolls and its hover run together: the pointer rests over the picture while two
    /// fingers scroll.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        let scrolls = [trackpadScroll, wheelScroll].compactMap { $0 }
        return (scrolls.contains { $0 === gestureRecognizer } && other === hover)
            || (scrolls.contains { $0 === other } && gestureRecognizer === hover)
    }

    /// A stroke just went silent (TrackpadGestures: three fingers down): a scroll it had begun (a first
    /// finger that slid before the others landed) ends here, with no coast; the Mac got deltas of less
    /// than `chordTravel`. Nothing else of the stroke goes out but its gesture.
    private func strokeSilenced() {
        lastPanTranslation = .zero
        guard scrollGestureOpen else { return }
        scrollGestureOpen = false
        let p = scrollPan.flatMap { normalized($0.location(in: self), clamped: true) } ?? (x: 0.5, y: 0.5)
        send(.scrollGesture(.ended, x: p.x, y: p.y))
    }

    /// The coast after a flick, at the point the finger lifted. Steps are converted to fractions
    /// of the video rect exactly as live pan deltas are, so the coast continues at the speed the
    /// content was moving under the finger.
    private func startMomentum(velocity: CGPoint, at p: (x: Double, y: Double)) {
        // Begin and end capture the send closure rather than self, so the end still goes out if
        // this view is torn down mid-coast.
        let send = self.send
        momentum.start(
            velocity: velocity,
            onBegin: { send(.scrollGesture(.momentumBegan, x: p.x, y: p.y)) },
            onStep: { [weak self] step in
                guard let self else { return }
                let rect = self.videoRect
                guard rect.width > 0, rect.height > 0 else { return }
                self.send(.scroll(x: p.x, y: p.y,
                                  dx: Double(step.x / rect.width), dy: Double(step.y / rect.height)))
            },
            onEnd: { send(.scrollGesture(.momentumEnded, x: p.x, y: p.y)) })
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { momentum.stop(); releaseForwardedKeys() }
        // A session's start, a rotation's other layout, a reconnect's new screen: the proxy takes the
        // keyboard for a hardware keyboard (on the next turn, once this view is settled in the window).
        if window != nil { keyboardProxy?.joined(self) } else { keyboardProxy?.left(self) }
        #if DEBUG
        if window != nil {
            InputScript.overlay = self
            runInputTest()
        } else if InputScript.overlay === self {
            InputScript.overlay = nil
        }
        #endif
    }

    #if DEBUG
    /// `-SillInputScript`'s `tap X,Y` (ContentView): a finger's tap at that fraction of the video
    /// frame, through the tap's own path.
    func scriptTap(x: Double, y: Double) {
        let rect = videoRect
        guard rect.width > 0, rect.height > 0 else { return }
        tap(at: CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height))
    }

    /// `key USAGE`: a hardware key, down and up with no modifier, as `pressesBegan` and
    /// `pressesEnded` send a raw key: this device's pointer hides.
    func scriptKey(_ usage: UInt16) {
        setOwnPointer(nil, .none)
        send(.key(hidUsage: usage, down: true, modifiers: 0))
        send(.key(hidUsage: usage, down: false, modifiers: 0))
    }

    /// `esc [MODS]`: Esc as its key command reaches this view, only while it takes Esc (it holds the
    /// keyboard and no EscapeKey is on screen in its window). False when it does not.
    func scriptEscape(_ modifiers: UIKeyModifierFlags) -> Bool {
        guard takesEscape, let command = Self.escapeCommands.first(where: { $0.modifierFlags == modifiers }) else { return false }
        escapeKeyCommand(command)
        return true
    }

    /// `scroll DX,DY` and `wheel DX,DY`: the iPad's trackpad (a gesture of five steps to DX, DY points
    /// at the picture's middle, lifted at 600 pt/s along it, so it coasts) or a wheel (plain deltas),
    /// through the scroll path the recognizers take.
    func scriptScroll(dx: Double, dy: Double, from source: ScrollSource) {
        let rect = videoRect
        guard rect.width > 0, rect.height > 0 else { return }
        let at = CGPoint(x: rect.midX, y: rect.midY)
        scroll(.began, at: at, translation: .zero, velocity: .zero, from: source)
        for step in 1...5 {
            scroll(.changed, at: at, translation: CGPoint(x: dx * Double(step) / 5, y: dy * Double(step) / 5),
                   velocity: .zero, from: source)
        }
        let length = hypot(dx, dy)
        let velocity = length > 0 ? CGPoint(x: dx / length * 600, y: dy / length * 600) : .zero
        scroll(.ended, at: at, translation: CGPoint(x: dx, y: dy), velocity: velocity, from: source)
    }

    /// `-SillInputTest 1`'s third part (InputTest), in every layout, 4.4 s after the overlay joins a
    /// window (after the portrait key row's and trackpad's): Esc and ⇧Esc through the key command's own
    /// action, each only while this view takes Esc; at 5 s a trackpad's two-finger scroll of 40 pt down
    /// with its lift's coast; at 7.2 s a wheel's 30 pt up, plain deltas.
    private func runInputTest() {
        guard InputTest.claim("overlay") else { return }
        let start = DispatchTime.now()
        func at(_ seconds: Double, _ step: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: start + seconds, execute: step)
        }
        at(4.4) { [weak self] in
            guard let self else { return }
            for flags: UIKeyModifierFlags in [[], .shift] {
                let name = flags.isEmpty ? "Esc" : "⇧Esc"
                print("input test: \(name) " + (self.scriptEscape(flags) ? "through the key command"
                    : "not taken: " + (self.isFirstResponder ? "an EscapeKey is on screen in its window" : "this view does not hold the keyboard")))
            }
        }
        at(5.0) { [weak self] in
            self?.scriptScroll(dx: 0, dy: 40, from: .trackpad)
            print("input test: a trackpad's two-finger scroll done (40 pt down in five steps, lifted at 600 pt/s: it coasts)")
        }
        at(7.2) { [weak self] in
            self?.scriptScroll(dx: 0, dy: -30, from: .wheel)
            print("input test: a wheel's scroll done (30 pt up in five steps, plain deltas, no coast)")
        }
    }
    #endif

    /// Pencil hover (and a trackpad pointer): cursor only, no buttons.
    ///
    /// Both send the same moves; they differ only in what drew this device's pointer: the Pencil's
    /// position is kept (drawn only with Q2's flip), the iPad's own pointer keeps none, as iPadOS
    /// draws it. Only a Pencil reports a height or a tilt (a trackpad or mouse pointer reads 0 for
    /// both), which is how the two are told apart here.
    @objc private func handleHover(_ gesture: UIHoverGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            if gesture.state == .began { hoverIsPencil = false }
            if gesture.zOffset > 0 || gesture.altitudeAngle > 0 { hoverIsPencil = true }
            let at = sendPointer(.move, at: gesture.location(in: self), clamped: true)
            if hoverIsPencil { setOwnPointer(at, .pencil) } else { setOwnPointer(nil, .none) }
        default:
            hoverIsPencil = false
        }
    }

    // MARK: - Pencil

    // The Pencil is the left mouse button held down: touch down clicks, moving drags, lifting
    // releases. It bypasses the gesture recognizers entirely (they are direct-touch only), so the
    // events are built straight from the touches.

    /// Pencil and iPad trackpad/mouse touches are handled here as a pointer: move, then a click.
    /// Finger touches stay with the gesture recognizers above (tap, long-press, pan).
    private static func pointerTouch(in touches: Set<UITouch>) -> UITouch? {
        touches.first { $0.type == .pencil || $0.type == .indirectPointer }
    }

    /// This device's own pointer after a pointer touch at `at`: the Pencil's position, from
    /// `.pencil`; none for the iPad's own trackpad or mouse, whose pointer iPadOS draws.
    private func ownPointer(_ at: CGPoint?, for touch: UITouch) {
        if touch.type == .pencil { setOwnPointer(at, .pencil) } else { setOwnPointer(nil, .none) }
    }
    /// Which button the current pointer press holds down, so the up matches the down.
    private var pointerButtonIsSecondary = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Any new touch stops a coasting flick, the way touching a moving list does on iOS (and
        // before the Pencil clicks on content that is still sliding).
        momentum.stop()
        guard let touch = Self.pointerTouch(in: touches) else {
            super.touchesBegan(touches, with: event); return
        }
        let point = touch.location(in: self)
        guard let at = sendPointer(.move, at: point, clamped: false) else { return }
        ownPointer(at, for: touch)
        // A trackpad's secondary click (two fingers, or right button) is a right click on the Mac.
        pointerButtonIsSecondary = touch.type == .indirectPointer && (event?.buttonMask.contains(.secondary) ?? false)
        sendPointer(pointerButtonIsSecondary ? .rightDown : .leftDown, at: point, clamped: false)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = Self.pointerTouch(in: touches) else {
            super.touchesMoved(touches, with: event); return
        }
        // A move while the button is down is a drag on the host's side.
        if let at = sendPointer(.move, at: touch.location(in: self), clamped: true) { ownPointer(at, for: touch) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = Self.pointerTouch(in: touches) else {
            super.touchesEnded(touches, with: event); return
        }
        if let at = sendPointer(pointerButtonIsSecondary ? .rightUp : .leftUp, at: touch.location(in: self), clamped: true) { ownPointer(at, for: touch) }
        pointerButtonIsSecondary = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = Self.pointerTouch(in: touches) else {
            super.touchesCancelled(touches, with: event); return
        }
        // Never leave the button stuck down.
        if let at = sendPointer(pointerButtonIsSecondary ? .rightUp : .leftUp, at: touch.location(in: self), clamped: true) { ownPointer(at, for: touch) }
        pointerButtonIsSecondary = false
    }

    // MARK: - Keyboard

    override var canBecomeFirstResponder: Bool { true }

    /// None of iPadOS's three-finger editing gestures (undo and redo, copy, cut and paste, the edit
    /// bar): three fingers here are the Mac's (docs/trackpad-gestures-plan.md §6.5). This view is the
    /// one responder Sill makes first, in every layout, and holds no text of its own; the Mac's undo
    /// is ⌘Z.
    override var editingInteractionConfiguration: UIEditingInteractionConfiguration { .none }

    @objc var keyboardType: UIKeyboardType = .default
    @objc var autocorrectionType: UITextAutocorrectionType = .no
    @objc var autocapitalizationType: UITextAutocapitalizationType = .none
    @objc var smartQuotesType: UITextSmartQuotesType = .no
    @objc var smartDashesType: UITextSmartDashesType = .no

    /// Always true: there is text on the Mac, and the delete key has to keep working even though
    /// this view holds no text of its own.
    var hasText: Bool { true }

    // The latched-modifier rule, which decides which of the two keyboard paths a character takes:
    //
    //   • Shift alone changes what character the software keyboard produces, and it already did:
    //     `insertText` receives the shifted text. So a shift latch sends plain `.text`, exactly
    //     like ordinary typing, but for return and tab, whose "\n" and "\t" carry no shift: those
    //     go out as ⇧Return and ⇧Tab keys, as a hardware keyboard's do. (It earns its keep on the
    //     arrows and on clicks too, where it rides along in the modifier bits instead.)
    //
    //   • Control, option and command never produce characters on a Mac — they make shortcuts —
    //     and the software keyboard has no way to express them. While one of them is latched a
    //     typed character therefore goes out as a raw `.key` down/up carrying the latched bits
    //     (⌘S), not as `.text`, which is the same split the hardware-key path makes below.
    //
    // Either way the latch is spent afterwards: it is a one-shot, like a sticky key.

    func insertText(_ text: String) {
        setOwnPointer(nil, .none)
        if !latchedModifiers.isDisjoint(with: .shortcutMakers), text.count == 1,
           let character = text.first, let usage = HIDKey.usage(for: character) {
            sendLatched(usage)
            return
        }
        // The key row's shift latched, then a return or tab from the text system (the software
        // keyboard's, or a hardware one's without shift): ⇧Return and ⇧Tab as keys, as a hardware
        // keyboard sends them with shift held (ForwardedKeys.shiftedKeyUsages), since "\n" and "\t"
        // as text carry no shift.
        if latchedModifiers.contains(.shift), text == "\n" || text == "\t",
           let character = text.first, let usage = HIDKey.usage(for: character),
           ForwardedKeys.shiftedKeyUsages.contains(usage) {
            sendLatched(usage)
            return
        }
        send(.text(text))
        consumeLatch()
    }

    func deleteBackward() {
        setOwnPointer(nil, .none)
        if !latchedModifiers.isDisjoint(with: .shortcutMakers) {
            sendLatched(HIDKey.deleteBackward)
            return
        }
        send(.text("\u{8}"))
        consumeLatch()
    }

    /// One key, down and up, carrying the latched modifier bits, then the latch is spent.
    private func sendLatched(_ usage: UInt16) {
        KeyChord.press(usage, with: latchedModifiers).forEach(send)
        consumeLatch()
    }

    private func consumeLatch() {
        guard !latchedModifiers.isEmpty else { return }
        latchedModifiers = []
        onModifiersConsumed?()
    }

    // MARK: Who holds the keyboard (InputOverlayProxy, HardwareKeyboardPolicy)

    /// The proxy's `take`: first responder, for the hardware keyboard (`automatic`) or as the person's.
    func take(automatic: Bool) {
        askedAutomatic = automatic
        _ = becomeFirstResponder()
        askedAutomatic = nil
    }

    /// The proxy's `makeOwn` and `makeAutomatic`: the same first responder, now the person's (the
    /// system keyboard: the software one, or with a hardware keyboard iPadOS's own small bar) or the
    /// hardware keyboard's (no keyboard drawn).
    func setHoldsForHardwareKeyboard(_ automatic: Bool) {
        guard automatic != holdsForHardwareKeyboard else { return }
        applyInputViews(automatic: automatic)
        if isFirstResponder { reloadInputViews() }
    }

    override func becomeFirstResponder() -> Bool {
        // Before UIKit reads `inputView`: what this holding is, asked or (UIKit's own) as the rule says.
        let automatic = askedAutomatic ?? (keyboardProxy?.unpromptedKindIsAutomatic(for: self) ?? false)
        let before = holdsForHardwareKeyboard
        applyInputViews(automatic: automatic)
        let became = super.becomeFirstResponder()
        if became {
            keyboardProxy?.became(self, automatic: askedAutomatic)
        } else {
            applyInputViews(automatic: before)
        }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            releaseForwardedKeys()
            keyboardProxy?.resigned(self)
        }
        return resigned
    }

    /// Nothing drawn while the hardware keyboard holds the keyboard: an empty input view (iPadOS then
    /// shows no software keyboard, even for a keyboard it counts as gone a moment before GameController
    /// does) and no assistant groups; the system keyboard and its groups for the person's own.
    override var inputView: UIView? { holdsForHardwareKeyboard ? emptyInputView : nil }

    private func applyInputViews(automatic: Bool) {
        holdsForHardwareKeyboard = automatic
        let item = inputAssistantItem
        if automatic {
            if assistantGroups == nil { assistantGroups = (item.leadingBarButtonGroups, item.trailingBarButtonGroups) }
            item.leadingBarButtonGroups = []
            item.trailingBarButtonGroups = []
        } else if let groups = assistantGroups {
            item.leadingBarButtonGroups = groups.leading
            item.trailingBarButtonGroups = groups.trailing
        }
    }

    // MARK: Esc (#67)

    /// Esc with each of the sixteen combinations of ⌃, ⌥, ⇧ and ⌘, asking for priority over the focus
    /// and text-editing systems, which iPadOS can let take a hardware Escape before pressesBegan. No
    /// title: listed in neither iPadOS's shortcut overlay nor the menu bar. In the iOS 27 simulator a
    /// virtual keyboard's Esc reaches pressesBegan, which keeps it, and the command never fires; a device
    /// that keeps it from pressesBegan fires the command instead (ForwardedKeys: one key press, sent
    /// once, whichever comes).
    private static let escapeCommands: [UIKeyCommand] = (0..<16).map { mask in
        var flags = UIKeyModifierFlags()
        for (bit, flag) in [UIKeyModifierFlags.shift, .control, .alternate, .command].enumerated() where mask & (1 << bit) != 0 {
            flags.insert(flag)
        }
        let command = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: flags,
                                   action: #selector(InputOverlayView.escapeKeyCommand(_:)))
        command.wantsPriorityOverSystemBehavior = true
        return command
    }

    /// This view takes Esc: it is first responder (it holds the keyboard), and no EscapeKey is on screen
    /// in its window (the tour, the pairing overlay, the Settings panel, whose Esc closes them). Only its
    /// own window's: Settings open in another Sill window, behind this one, never sees a key pressed
    /// here. A leaf view is in the responder chain only while it is first responder, so this says again
    /// what the chain does.
    private var takesEscape: Bool { isFirstResponder && !EscapeKey.onScreen(in: window) }

    override var keyCommands: [UIKeyCommand]? {
        guard takesEscape else { return super.keyCommands }
        return (super.keyCommands ?? []) + Self.escapeCommands
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(InputOverlayView.escapeKeyCommand(_:)) { return takesEscape }
        return super.canPerformAction(action, withSender: sender)
    }

    /// Esc to the Mac, down and up at once with the command's modifiers, through `ForwardedKeys` as a
    /// pressed key goes; nothing when its press came first (its own up follows).
    @objc private func escapeKeyCommand(_ command: UIKeyCommand) {
        guard takesEscape else { return }
        let modifiers = UInt64(command.modifierFlags.rawValue)
        let events = forwarded.commanded(HIDKey.escape, modifiers: modifiers, at: ProcessInfo.processInfo.systemUptime)
        Self.hwkey(HIDKey.escape, down: true, via: "keyCommand", modifiers: modifiers,
                   to: events.isEmpty ? "already down through pressesBegan" : "to the Mac")
        guard !events.isEmpty else { return }
        setOwnPointer(nil, .none)
        events.forEach(send)
    }

    /// DEBUG: every hardware key this view sees, and which way it went ("hwkey: usage 41 down via
    /// keyCommand (shift): to the Mac"), so a device shows which channel delivered Esc.
    static func hwkey(_ usage: UInt16, down: Bool, via channel: String, modifiers: UInt64? = nil, to outcome: String? = nil) {
        #if DEBUG
        var line = "hwkey: usage \(usage) \(down ? "down" : "up") via \(channel)"
        if let modifiers { line += " (" + InputOverlayView.modifierNames(modifiers) + ")" }
        if let outcome { line += ": " + outcome }
        print(line)
        #endif
    }

    #if DEBUG
    static func modifierNames(_ modifiers: UInt64) -> String {
        let names = [(KeyModifiers.control, "control"), (.option, "option"), (.shift, "shift"), (.command, "command")]
            .filter { modifiers & $0.0.rawValue != 0 }.map(\.1)
        return names.isEmpty ? "none" : names.joined(separator: "+")
    }
    #endif

    // MARK: - Hardware keys

    // The split between the two keyboard paths, which must not overlap or everything is typed twice:
    //
    //   • Text path (`insertText` / `deleteBackward`) owns every key that produces characters:
    //     letters, digits, punctuation, space and backspace, with or without shift, and return and
    //     tab without it. Those arrive already composed — shifted, dead-keyed, from a Japanese IME,
    //     from dictation — which is exactly what we want to send as `.text`.
    //
    //   • Raw path (`.key`) owns only what the text path never delivers: the arrows, escape, the
    //     function keys, home/end/page up/down, forward delete, ⌘, ⌃ and ⌥ themselves, *any* key
    //     while command, control or option is held, because those combinations are shortcuts (⌘S,
    //     ⌃A, ⌥←) and never reach `insertText`, and return and tab with shift, which the text path
    //     would hand over as a bare "\n" and "\t" (⇧Return a plain Return on the Mac). Shift alone
    //     is not otherwise in that list: shift makes characters. (ForwardedKeys.goesAsKey.)
    //
    // Which path a key takes is decided when it goes down, and its up takes the same one whatever the
    // flags say by then (ForwardedKeys): ⌘'s own release and a key let go after ⌘ reach the Mac, and
    // a key the text system took never sends a stray up. Presses we do not take are handed to super
    // so the text input system still sees them.

    /// The hardware keys down on the Mac, so each one's up follows its down.
    private var forwarded = ForwardedKeys()
    /// This device's switch: the left Option key is Command on the Mac (ForwardedKeys), since iPadOS
    /// keeps ⌘Space and ⌘Tab for itself. Off unless turned on; never sent to the Mac.
    static let leftOptionAsCommandKey = "Sill.leftOptionAsCommand"
    static var leftOptionAsCommand: Bool { UserDefaults.standard.bool(forKey: leftOptionAsCommandKey) }

    private func forward(_ presses: Set<UIPress>, down: Bool, via channel: String) -> Set<UIPress> {
        var unhandled: Set<UIPress> = []
        for press in presses {
            guard let key = press.key else { unhandled.insert(press); continue }
            let usage = UInt16(key.keyCode.rawValue)
            let modifiers = UInt64(key.modifierFlags.rawValue)
            #if DEBUG
            // `-SillEscViaCommand 1`: this view leaves Esc to the text system, as a device that keeps it
            // from pressesBegan does, so the simulator's Esc fires the key command instead.
            if usage == HIDKey.escape, Self.escViaCommand {
                Self.hwkey(usage, down: down, via: channel, modifiers: modifiers, to: "handed on (-SillEscViaCommand)")
                unhandled.insert(press)
                continue
            }
            #endif
            if down { forwarded.leftOptionAsCommand = Self.leftOptionAsCommand }
            let outcome = down ? forwarded.pressed(usage, modifiers: modifiers, at: press.timestamp) : forwarded.released(usage)
            switch outcome {
            case .send(let event):
                send(event)
                Self.hwkey(usage, down: down, via: channel, modifiers: modifiers, to: "to the Mac")
            case .text:
                unhandled.insert(press)
                Self.hwkey(usage, down: down, via: channel, modifiers: modifiers, to: "the text system's")
            case .swallow:
                Self.hwkey(usage, down: down, via: channel, modifiers: modifiers, to: "the key command sent it")
            }
        }
        return unhandled
    }

    #if DEBUG
    private static let escViaCommand = UserDefaults.standard.bool(forKey: "SillEscViaCommand")
    #endif

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        // A hardware key hides this device's pointer, as typing does (`setOwnPointer`).
        if presses.contains(where: { $0.key != nil }) { setOwnPointer(nil, .none) }
        let unhandled = forward(presses, down: true, via: "pressesBegan")
        if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandled = forward(presses, down: false, via: "pressesEnded")
        if !unhandled.isEmpty { super.pressesEnded(unhandled, with: event) }
    }

    /// A press cancelled (the app going to the background, the keyboard disconnected): its key comes
    /// up on the Mac as if released, so neither it nor a modifier stays down there.
    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandled = forward(presses, down: false, via: "pressesCancelled")
        if !unhandled.isEmpty { super.pressesCancelled(unhandled, with: event) }
    }

    /// Every hardware key still down on the Mac comes up: this view no longer takes keys (the Settings
    /// panel took the keyboard, the tour showed) or is leaving the screen, and UIKit sends it no
    /// release for them.
    private func releaseForwardedKeys() {
        for up in forwarded.releaseAll() { send(up) }
    }
}

/// Who holds the keyboard on the stream screen: the stream screen's Keyboard button, the Settings
/// panel, the tour and the pairing overlay reach the overlay's first responder through this, and it
/// takes the keyboard by itself while a hardware keyboard is attached (HardwareKeyboardPolicy, which it
/// owns; docs/hardware-keyboard-plan.md §2). One per stream screen, so it outlives a rotation (whose
/// other layout's input view becomes `view`); a new session's screen makes a new one.
final class InputOverlayProxy {
    /// The current input view: the one the layout on screen made last. Another's events (a rotation's
    /// old view resigning on its way out) change nothing here.
    weak var view: InputOverlayView?
    /// The rule, and what it was told.
    private(set) var policy = HardwareKeyboardPolicy(attached: HardwareKeyboardMonitor.shared.attached)
    /// The person's own keyboard came up or went: the Keyboard button lights, the tour counts it.
    /// The hardware keyboard's holding never calls it.
    var onOwnChange: ((Bool) -> Void)?

    /// The Keyboard button (and the portrait key row's keyboard cap).
    func toggleKeyboard() { change("the Keyboard button") { $0.toggled() } }
    /// Takes the keyboard down or puts the person's back, and with it hardware-key forwarding to the
    /// Mac: the overlay forwards keys only while it is first responder. The Settings panel takes it
    /// down while open, so Esc reaches its Done button instead of the Mac, and puts the person's back
    /// after (a hardware keyboard's hold comes back by itself, `takers`).
    func setKeyboard(shown: Bool) { change(shown ? "the person's keyboard back" : "taken down") { $0.shown(shown) } }
    /// A hardware keyboard attached or the last one went (HardwareKeyboardMonitor).
    func update(attached: Bool) { change(attached ? "a keyboard attached" : "the keyboard went") { $0.keyboard(attached: attached) } }
    /// What is open over the stream that takes the keyboard (StreamScreen).
    func update(takers: Set<HardwareKeyboardPolicy.Taker>) {
        change(takers.isEmpty ? "nothing open" : takers.map(\.rawValue).sorted().joined(separator: ", ") + " open") { $0.takers(takers) }
    }

    // From the view (only the current one counts)

    func joined(_ view: InputOverlayView) {
        guard view === self.view else { return }
        // A turn later: SwiftUI is still placing the view, and a first responder taken mid-update can
        // be lost to the old layout's teardown.
        DispatchQueue.main.async { [weak self, weak view] in
            guard let self, let view, view === self.view, view.window != nil else { return }
            self.change("an input view in a window") { $0.joined() }
        }
    }

    func left(_ view: InputOverlayView) {
        guard view === self.view else { return }
        change("the input view left its window") { $0.left(); return [] }
    }

    func unpromptedKindIsAutomatic(for view: InputOverlayView) -> Bool {
        view === self.view && policy.unpromptedKind == .automatic
    }

    func became(_ view: InputOverlayView, automatic: Bool?) {
        guard view === self.view else { return }
        change(automatic == nil ? "UIKit gave the keyboard back" : "took the keyboard") { $0.became(automatic: automatic) }
    }

    func resigned(_ view: InputOverlayView) {
        guard view === self.view else { return }
        change("let go of the keyboard") { $0.resigned(); return [] }
    }

    /// What `onOwnChange` last said.
    private var reportedOwn = false

    /// One event: the rule's answer done in order, and the person's own keyboard reported when that
    /// changed. Re-entrant: the view's first responder changes report back here as they happen.
    private func change(_ event: String, _ step: (inout HardwareKeyboardPolicy) -> [HardwareKeyboardPolicy.Action]) {
        let before = policy.hold
        let actions = step(&policy)
        #if DEBUG
        if !actions.isEmpty || before != policy.hold {
            print("keyboard: \(event): \(before.rawValue) → \(policy.hold.rawValue)"
                  + (actions.isEmpty ? "" : "; " + actions.map(\.description).joined(separator: ", ")))
        }
        #endif
        for action in actions {
            switch action {
            case .take(let automatic): view?.take(automatic: automatic)
            case .makeOwn: view?.setHoldsForHardwareKeyboard(false)
            case .makeAutomatic: view?.setHoldsForHardwareKeyboard(true)
            case .letGo: if view?.isFirstResponder == true { _ = view?.resignFirstResponder() }
            }
        }
        if policy.isOwn != reportedOwn {
            reportedOwn = policy.isOwn
            onOwnChange?(reportedOwn)
        }
    }
}

/// Whether a hardware keyboard is attached: GameController's coalesced keyboard, and its connect and
/// disconnect notifications (all keyboards count as one). DEBUG `-SillHardwareKeyboard 1|0` says so
/// instead for a run (the harness, the gates), and `-SillKeyProbe 1` prints every key GameController
/// sees ("hwkey: usage 41 down via GameController"), beside UIKit's own channels. Main thread.
final class HardwareKeyboardMonitor: ObservableObject {
    static let shared = HardwareKeyboardMonitor()
    @Published private(set) var attached: Bool

    private init() {
        attached = Self.override ?? (GCKeyboard.coalesced != nil)
        let center = NotificationCenter.default
        center.addObserver(forName: .GCKeyboardDidConnect, object: nil, queue: .main) { [weak self] _ in self?.connected(true) }
        center.addObserver(forName: .GCKeyboardDidDisconnect, object: nil, queue: .main) { [weak self] _ in self?.connected(false) }
        #if DEBUG
        installProbe()
        #endif
    }

    private func connected(_ now: Bool) {
        #if DEBUG
        print("keyboard: GameController says a keyboard is \(now ? "attached" : "gone")"
              + (Self.override.map { " (-SillHardwareKeyboard \($0 ? 1 : 0) keeps it \($0 ? "attached" : "gone"))" } ?? ""))
        if now { installProbe() }
        #endif
        guard Self.override == nil, now != attached else { return }
        attached = now
    }

    private static var override: Bool? {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "SillHardwareKeyboard") { return raw == "1" }
        #endif
        return nil
    }

    #if DEBUG
    /// `-SillInputScript`'s `keyboard attach|detach`: as GameController's notifications would say.
    func scriptSet(attached now: Bool) {
        print("keyboard: the input script says a keyboard is \(now ? "attached" : "gone")")
        attached = now
    }

    private func installProbe() {
        guard UserDefaults.standard.bool(forKey: "SillKeyProbe") else { return }
        GCKeyboard.coalesced?.keyboardInput?.keyChangedHandler = { _, _, code, pressed in
            InputOverlayView.hwkey(UInt16(truncatingIfNeeded: code.rawValue), down: pressed, via: "GameController")
        }
    }
    #endif
}

struct InputOverlay: UIViewRepresentable {
    let videoSize: CGSize
    let send: (InputEvent) -> Void
    /// `StreamClient.setOwnPointer`; see `InputOverlayView.setOwnPointer`.
    let setOwnPointer: (CGPoint?, PointerPresence.Origin) -> Void
    let proxy: InputOverlayProxy
    /// The person's own keyboard is up (the proxy's `onOwnChange`): never the hardware keyboard's hold.
    @Binding var isKeyboardShown: Bool
    var latchedModifiers: KeyModifiers = []
    var onModifiersConsumed: () -> Void = {}
    /// `StreamClient.sendGesture`; see `InputOverlayView.sendGesture`.
    var sendGesture: (TrackpadGestures.Gesture, Int) -> Bool = { _, _ in false }

    func makeUIView(context: Context) -> InputOverlayView {
        let view = InputOverlayView(frame: .zero)
        view.keyboardProxy = proxy
        proxy.view = view
        return view
    }

    func updateUIView(_ uiView: InputOverlayView, context: Context) {
        uiView.videoSize = videoSize
        uiView.send = send
        uiView.setOwnPointer = setOwnPointer
        uiView.latchedModifiers = latchedModifiers
        uiView.sendGesture = sendGesture
        // Called straight from a UIKit text-input callback, never from inside a SwiftUI update,
        // so writing the binding here needs no hop.
        uiView.onModifiersConsumed = onModifiersConsumed
        proxy.onOwnChange = { shown in
            // Hops to the next runloop turn: resigning can happen inside a SwiftUI update
            // (a teardown, say), and writing the binding there is a "modifying state during
            // view update" warning waiting to happen.
            DispatchQueue.main.async { isKeyboardShown = shown }
        }
    }
}

// MARK: - Stroke observer

/// Feeds a surface's `TrackpadGestures` with every direct touch, so a stroke that has three fingers
/// down before any has moved sends the Mac nothing but its gesture, if it makes one
/// (docs/trackpad-gestures-plan.md §6.2). One on each glass surface: the portrait trackpad and the
/// stream.
///
/// An observer, not the view's own touch callbacks: the pans, taps and long presses cancel the
/// view's touches as they recognize, after which the view hears no more of the stroke. This one sees
/// every direct touch and never recognizes (it stays possible, so UIKit ends it with the last
/// finger), takes none (`cancelsTouchesInView` off), delays none, can neither prevent another
/// recognizer nor be prevented by one, and is its own delegate so it runs beside all of them.
/// Only direct touches are fingers: a Pencil is the mouse, and a Magic Keyboard trackpad's click is
/// one indirect touch. Those only end a finished stroke's silence (`otherTouch`), since the
/// portrait trackpad's recognizers take them too.
final class StrokeObserver: UIGestureRecognizer, UIGestureRecognizerDelegate {
    private var strokes = TrackpadGestures()
    /// From three fingers down until the next stroke's first touch: the surface sends nothing.
    var silent: Bool { strokes.silent }
    /// A button the surface pressed is held (the trackpad's press-and-hold drag); asked as each
    /// finger lands, and no stroke goes silent while it is (its button must still come up).
    var holding: () -> Bool = { false }
    /// The stroke just went silent: close what it had opened (a scroll).
    var onSilenced: () -> Void = {}
    /// The decision, at the first lift of a finger that armed the stroke: the gesture and its
    /// fingers, 3 or 4.
    var onGesture: (TrackpadGestures.Gesture, Int) -> Void = { _, _ in }
    /// Each touch of the stroke, numbered as it lands.
    private var ids: [ObjectIdentifier: Int] = [:]
    private var nextID = 0

    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    /// Several touches of one event in a fixed order (by where they are), so the same touches always
    /// make the same stroke.
    private func ordered(_ touches: Set<UITouch>) -> [UITouch] {
        touches.sorted { a, b in
            let p = a.location(in: view), q = b.location(in: view)
            return p.x != q.x ? p.x < q.x : p.y < q.y
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in ordered(touches) {
            guard touch.type == .direct else { strokes.otherTouch(); continue }
            let id = nextID
            nextID += 1
            ids[ObjectIdentifier(touch)] = id
            if strokes.down(id, at: touch.location(in: view), time: touch.timestamp, holding: holding()) == .silenced { onSilenced() }
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in ordered(touches) {
            guard let id = ids[ObjectIdentifier(touch)] else { continue }
            strokes.moved(id, to: touch.location(in: view), time: touch.timestamp)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in ordered(touches) {
            guard let id = ids.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            if case .gesture(let gesture, let fingers) = strokes.up(id, at: touch.location(in: view), time: touch.timestamp) {
                onGesture(gesture, fingers)
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        for touch in ordered(touches) {
            guard let id = ids.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
            strokes.cancelled(id)
        }
    }

    /// UIKit ends the observer with the stroke's last finger, after its touches have ended. A touch
    /// it never heard end (the observer ended early) counts as cancelled, so the next stroke starts
    /// clean and this one decides nothing more.
    override func reset() {
        super.reset()
        for id in ids.values.sorted() { strokes.cancelled(id) }
        ids.removeAll()
    }
}

// MARK: - Scroll momentum

/// The coast after a flicked scroll, generated here because the Mac will not make one: macOS adds
/// momentum in its trackpad driver, below the point where injected CGEvents enter, so a synthetic
/// gesture that ends simply stops. After a fast enough lift this emits one delta per display frame,
/// starting at the lift-off velocity and decaying exponentially, until the step is too small to
/// matter or `stop()` is called (a new touch).
///
/// Steps are in the owner's view points; the owner converts them to frame fractions exactly as it
/// does live pan deltas and brackets the run with `.momentumBegan` / `.momentumEnded` via the
/// callbacks. One run at a time: `start` stops any run still going (firing its end) first, and
/// `stop` always fires the end of a run that was going, so the host never sees an unclosed coast.
///
/// Main thread only (display link and gesture callbacks).
final class ScrollMomentum: NSObject {
    /// Lift-off speed, in points per second, below which a pan just stops. Anything slower is a
    /// placement, not a flick — roughly where UIScrollView's own coast stops being noticeable.
    private static let minimumSpeed: CGFloat = 150
    /// The rate the decay is defined at, and the rate the link is pinned to: a 120 Hz display
    /// would otherwise double the message rate for no visible gain on a 60 fps stream.
    private static let tickRate: Double = 60
    /// Velocity kept per 1/60 s tick. At 0.96 a coast travels ≈ 0.42 s × lift-off speed, and a
    /// typical 1000–3000 pt/s flick coasts for ~1.6–2.1 s before `stopBelow` (a gentle 300 pt/s
    /// one for ~1.1 s), inside the 1.5–2.5 s tail of a Mac trackpad. By the same arithmetic 0.95
    /// gives ~1.3–1.7 s, short of it, and 0.97 ~2.2–2.8 s, past it. Tune here after trying it.
    private static let decayPerTick: Double = 0.96
    /// Stop once a tick would move less than this many points: past here the tail is invisible,
    /// and still sending it would only hold the Mac's gesture open.
    private static let stopBelow: Double = 0.3

    private var link: CADisplayLink?
    /// Points per second, decaying.
    private var velocity = CGPoint.zero
    private var lastTimestamp: CFTimeInterval = 0
    private var onStep: ((CGPoint) -> Void)?
    private var onEnd: (() -> Void)?

    /// Starts a coast if `velocity` (points per second, from the pan recognizer) is a flick, and
    /// does nothing otherwise. `onBegin` and the first step fire straight away, so the momentum
    /// follows the gesture's end without waiting a frame, as a real trackpad's does.
    func start(velocity: CGPoint, onBegin: () -> Void,
               onStep: @escaping (CGPoint) -> Void, onEnd: @escaping () -> Void) {
        stop()
        guard hypot(velocity.x, velocity.y) > Self.minimumSpeed else { return }
        self.velocity = velocity
        self.onStep = onStep
        self.onEnd = onEnd
        onBegin()
        let tick = 1 / Self.tickRate
        onStep(CGPoint(x: velocity.x * tick, y: velocity.y * tick))

        // The link retains this object until it is invalidated, which `stop` always does, and a
        // run always ends on its own within a few seconds.
        let link = CADisplayLink(target: self, selector: #selector(advance))
        let rate = Float(Self.tickRate)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: rate, maximum: rate, preferred: rate)
        link.add(to: .main, forMode: .common)
        self.link = link
        lastTimestamp = CACurrentMediaTime()
    }

    /// Ends the run in progress, if any, firing its `onEnd`. Safe to call at any time.
    func stop() {
        guard let link else { return }
        link.invalidate()
        self.link = nil
        let end = onEnd
        onStep = nil
        onEnd = nil
        end?()
    }

    @objc private func advance(_ link: CADisplayLink) {
        // Real elapsed time rather than an assumed 1/60 s, so a skipped frame does not slow the
        // coast; clamped so a long stall (the app switcher) cannot turn into one big jump.
        let now = link.targetTimestamp
        let dt = min(now - lastTimestamp, 0.1)
        guard dt > 0 else { return }
        lastTimestamp = now

        let decay = CGFloat(pow(Self.decayPerTick, dt * Self.tickRate))
        velocity.x *= decay
        velocity.y *= decay
        // The stop rule is per 60 Hz tick whatever the actual frame interval was.
        guard Double(hypot(velocity.x, velocity.y)) / Self.tickRate >= Self.stopBelow else {
            stop()
            return
        }
        onStep?(CGPoint(x: velocity.x * dt, y: velocity.y * dt))
    }
}
