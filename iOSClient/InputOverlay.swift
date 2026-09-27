import SwiftUI
import UIKit
import StreamProtocol

/// The touch layer over the streamed video. Direct-touch model: where you touch is where the Mac's
/// pointer goes, and the Apple Pencil is the mouse. Everything leaves here as an `InputEvent` whose
/// position is a fraction of the *video frame*, not of this view — the video is drawn aspect-fit by
/// `HEVCDisplayView`, so the letterbox has to be taken out before normalizing.
final class InputOverlayView: UIView, UIKeyInput {
    /// Pixel size of the streamed frame. Zero until the host's parameter sets arrive; input is
    /// ignored until then, since there is nothing on screen to aim at.
    var videoSize: CGSize = .zero
    var send: (InputEvent) -> Void = { _ in }
    /// Fires when this view takes or loses first responder, i.e. when the software keyboard shows
    /// or hides (including when the user dismisses it themselves).
    var onKeyboardShownChange: ((Bool) -> Void)?

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
        addGestureRecognizer(pan)

        // Pencil hover on the iPads that support it, and the trackpad/mouse pointer everywhere.
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover))
        addGestureRecognizer(hover)
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
        let rect = videoRect
        switch gesture.state {
        case .began:
            setOwnPointer(nil, .none)
            lastPanTranslation = .zero
            // A new pan while the last flick is still coasting ends the coast first, so the Mac
            // sees momentumEnded before this gesture's began. (touchesBegan has usually done it.)
            momentum.stop()
            guard let p = normalized(gesture.location(in: self), clamped: true) else { return }
            send(.scrollGesture(.began, x: p.x, y: p.y))
            scrollGestureOpen = true
        case .changed:
            guard rect.width > 0, rect.height > 0 else { return }
            let translation = gesture.translation(in: self)
            let dx = (translation.x - lastPanTranslation.x) / rect.width
            let dy = (translation.y - lastPanTranslation.y) / rect.height
            lastPanTranslation = translation
            guard dx != 0 || dy != 0, let p = normalized(gesture.location(in: self), clamped: true) else { return }
            send(.scroll(x: p.x, y: p.y, dx: Double(dx), dy: Double(dy)))
        case .ended, .cancelled:
            lastPanTranslation = .zero
            guard scrollGestureOpen else { return }
            scrollGestureOpen = false
            let p = normalized(gesture.location(in: self), clamped: true) ?? (x: 0.5, y: 0.5)
            send(.scrollGesture(.ended, x: p.x, y: p.y))
            // Only a real lift coasts. A cancel means the system took the touch (an alert, a
            // system gesture), and flinging the Mac's content then would be a surprise.
            if gesture.state == .ended { startMomentum(velocity: gesture.velocity(in: self), at: p) }
        default:
            lastPanTranslation = .zero
        }
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
        if window == nil { momentum.stop() }
        #if DEBUG
        if window != nil {
            InputScript.overlay = self
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
    //     like ordinary typing. (It earns its keep on the arrows and on clicks, where it rides
    //     along in the modifier bits instead.)
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
        send(.key(hidUsage: usage, down: true, modifiers: latchedModifiers.rawValue))
        send(.key(hidUsage: usage, down: false, modifiers: latchedModifiers.rawValue))
        consumeLatch()
    }

    private func consumeLatch() {
        guard !latchedModifiers.isEmpty else { return }
        latchedModifiers = []
        onModifiersConsumed?()
    }

    /// Show or hide the software keyboard.
    func toggleKeyboard() {
        if isFirstResponder { _ = resignFirstResponder() } else { _ = becomeFirstResponder() }
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { onKeyboardShownChange?(true) }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { onKeyboardShownChange?(false) }
        return resigned
    }

    // MARK: - Hardware keys

    // The split between the two keyboard paths, which must not overlap or everything is typed twice:
    //
    //   • Text path (`insertText` / `deleteBackward`) owns every key that produces characters:
    //     letters, digits, punctuation, space, return, tab and backspace, with or without shift.
    //     Those arrive already composed — shifted, dead-keyed, from a Japanese IME, from dictation —
    //     which is exactly what we want to send as `.text`.
    //
    //   • Raw path (`.key`) owns only what the text path never delivers: the arrows, escape, the
    //     function keys, home/end/page up/down, forward delete, and *any* key while command,
    //     control or option is held, because those combinations are shortcuts (⌘S, ⌃A, ⌥←) and
    //     never reach `insertText`. Shift alone is not in that list: shift makes characters.
    //
    // Presses we do not take are handed to super so the text input system still sees them.

    private static let rawUsages: Set<UIKeyboardHIDUsage> = [
        .keyboardUpArrow, .keyboardDownArrow, .keyboardLeftArrow, .keyboardRightArrow,
        .keyboardEscape, .keyboardDeleteForward,
        .keyboardHome, .keyboardEnd, .keyboardPageUp, .keyboardPageDown,
        .keyboardF1, .keyboardF2, .keyboardF3, .keyboardF4, .keyboardF5, .keyboardF6,
        .keyboardF7, .keyboardF8, .keyboardF9, .keyboardF10, .keyboardF11, .keyboardF12
    ]

    private func isRawKey(_ key: UIKey) -> Bool {
        if !key.modifierFlags.intersection([.command, .control, .alternate]).isEmpty { return true }
        return Self.rawUsages.contains(key.keyCode)
    }

    private func forward(_ presses: Set<UIPress>, down: Bool) -> Set<UIPress> {
        var unhandled: Set<UIPress> = []
        for press in presses {
            guard let key = press.key, isRawKey(key) else { unhandled.insert(press); continue }
            send(.key(hidUsage: UInt16(key.keyCode.rawValue), down: down,
                      modifiers: UInt64(key.modifierFlags.rawValue)))
        }
        return unhandled
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        // A hardware key hides this device's pointer, as typing does (`setOwnPointer`).
        if presses.contains(where: { $0.key != nil }) { setOwnPointer(nil, .none) }
        let unhandled = forward(presses, down: true)
        if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let unhandled = forward(presses, down: false)
        if !unhandled.isEmpty { super.pressesEnded(unhandled, with: event) }
    }
}

/// Lets SwiftUI reach the overlay's first responder from the top bar's Keyboard button.
final class InputOverlayProxy {
    weak var view: InputOverlayView?
    func toggleKeyboard() { view?.toggleKeyboard() }
    /// Takes the keyboard down or puts it back, and with it hardware-key forwarding to the Mac: the
    /// overlay forwards keys only while it is first responder. The Settings panel takes it down
    /// while open, so Esc reaches its Done button instead of the Mac, and puts it back after.
    func setKeyboard(shown: Bool) {
        guard let view else { return }
        if shown {
            _ = view.becomeFirstResponder()
        } else if view.isFirstResponder {
            _ = view.resignFirstResponder()
        }
    }
}

struct InputOverlay: UIViewRepresentable {
    let videoSize: CGSize
    let send: (InputEvent) -> Void
    /// `StreamClient.setOwnPointer`; see `InputOverlayView.setOwnPointer`.
    let setOwnPointer: (CGPoint?, PointerPresence.Origin) -> Void
    let proxy: InputOverlayProxy
    @Binding var isKeyboardShown: Bool
    var latchedModifiers: KeyModifiers = []
    var onModifiersConsumed: () -> Void = {}

    func makeUIView(context: Context) -> InputOverlayView {
        let view = InputOverlayView(frame: .zero)
        proxy.view = view
        return view
    }

    func updateUIView(_ uiView: InputOverlayView, context: Context) {
        uiView.videoSize = videoSize
        uiView.send = send
        uiView.setOwnPointer = setOwnPointer
        uiView.latchedModifiers = latchedModifiers
        // Called straight from a UIKit text-input callback, never from inside a SwiftUI update,
        // so writing the binding here needs no hop.
        uiView.onModifiersConsumed = onModifiersConsumed
        uiView.onKeyboardShownChange = { shown in
            // Hops to the next runloop turn: resigning can happen inside a SwiftUI update
            // (a teardown, say), and writing the binding there is a "modifying state during
            // view update" warning waiting to happen.
            DispatchQueue.main.async { isKeyboardShown = shown }
        }
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
