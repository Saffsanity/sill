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

    /// Pan translation already turned into scroll, so each callback sends only the new delta.
    private var lastPanTranslation: CGPoint = .zero

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

    private func sendPointer(_ action: PointerAction, at point: CGPoint, clamped: Bool) -> Bool {
        guard let p = normalized(point, clamped: clamped) else { return false }
        send(.pointer(action, x: p.x, y: p.y))
        return true
    }

    // MARK: - Finger gestures

    /// Single tap: put the pointer there first, then click. The move matters — the Mac's cursor is
    /// wherever the last event left it, and hover state (menus, tooltips) follows it.
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        let point = gesture.location(in: self)
        guard sendPointer(.move, at: point, clamped: false) else { return }
        _ = sendPointer(.leftDown, at: point, clamped: false)
        _ = sendPointer(.leftUp, at: point, clamped: false)
    }

    /// Long press: the right button, since there is no second finger to spare for it.
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: self)
        guard sendPointer(.move, at: point, clamped: false) else { return }
        _ = sendPointer(.rightDown, at: point, clamped: false)
        _ = sendPointer(.rightUp, at: point, clamped: false)
    }

    /// Finger pan: scrolling, not dragging. Deltas are fractions of the video rect, natural sign
    /// (finger down = content down = positive dy), and one event per callback.
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let rect = videoRect
        guard rect.width > 0, rect.height > 0 else { return }
        switch gesture.state {
        case .began:
            lastPanTranslation = .zero
        case .changed:
            let translation = gesture.translation(in: self)
            let dx = (translation.x - lastPanTranslation.x) / rect.width
            let dy = (translation.y - lastPanTranslation.y) / rect.height
            lastPanTranslation = translation
            guard dx != 0 || dy != 0, let p = normalized(gesture.location(in: self), clamped: true) else { return }
            send(.scroll(x: p.x, y: p.y, dx: Double(dx), dy: Double(dy)))
        default:
            lastPanTranslation = .zero
        }
    }

    /// Pencil hover (and a trackpad pointer): cursor only, no buttons.
    @objc private func handleHover(_ gesture: UIHoverGestureRecognizer) {
        switch gesture.state {
        case .began, .changed:
            _ = sendPointer(.move, at: gesture.location(in: self), clamped: true)
        default:
            break
        }
    }

    // MARK: - Pencil

    // The Pencil is the left mouse button held down: touch down clicks, moving drags, lifting
    // releases. It bypasses the gesture recognizers entirely (they are direct-touch only), so the
    // events are built straight from the touches.

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first(where: { $0.type == .pencil }) else {
            super.touchesBegan(touches, with: event); return
        }
        let point = touch.location(in: self)
        guard sendPointer(.move, at: point, clamped: false) else { return }
        _ = sendPointer(.leftDown, at: point, clamped: false)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first(where: { $0.type == .pencil }) else {
            super.touchesMoved(touches, with: event); return
        }
        // A move while the button is down is a drag on the host's side.
        _ = sendPointer(.move, at: touch.location(in: self), clamped: true)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first(where: { $0.type == .pencil }) else {
            super.touchesEnded(touches, with: event); return
        }
        _ = sendPointer(.leftUp, at: touch.location(in: self), clamped: true)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first(where: { $0.type == .pencil }) else {
            super.touchesCancelled(touches, with: event); return
        }
        // Never leave the button stuck down.
        _ = sendPointer(.leftUp, at: touch.location(in: self), clamped: true)
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
        if !latchedModifiers.isDisjoint(with: .shortcutMakers), text.count == 1,
           let character = text.first, let usage = HIDKey.usage(for: character) {
            sendLatched(usage)
            return
        }
        send(.text(text))
        consumeLatch()
    }

    func deleteBackward() {
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
}

struct InputOverlay: UIViewRepresentable {
    let videoSize: CGSize
    let send: (InputEvent) -> Void
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
