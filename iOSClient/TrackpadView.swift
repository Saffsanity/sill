import SwiftUI
import UIKit
import StreamProtocol

/// The portrait trackpad: the well, its dot grid, the hint, and the touch surface itself.
///
/// The opposite input model to `InputOverlay`, which is direct-touch — there the pointer goes where
/// you touch. Here the pad is relative, like a Mac's, so this side has to remember where the
/// pointer is; the wire format is unchanged, an absolute position in frame coordinates.
struct Trackpad: View {
    let send: (InputEvent) -> Void
    let latched: KeyModifiers
    let onModifiersConsumed: () -> Void

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 22, style: .continuous) }

    var body: some View {
        ZStack {
            Palette.trackpad
            DotGrid().allowsHitTesting(false)
            TrackpadView(send: send, latched: latched, onModifiersConsumed: onModifiersConsumed)
            VStack {
                Spacer(minLength: 0)
                Text("Drag to move the pointer. Tap to click, two fingers to scroll.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.muted)
                    .multilineTextAlignment(.center)
            }
            .padding(18)
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
    }
}

/// 1 pt dots on an 18 pt grid, the board's texture for "this surface is the one you drag on".
private struct DotGrid: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 18
            let radius: CGFloat = 1
            let dot = GraphicsContext.Shading.color(.white.opacity(0.07))
            var y = step / 2
            while y < size.height {
                var x = step / 2
                while x < size.width {
                    context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius,
                                                        width: radius * 2, height: radius * 2)),
                                 with: dot)
                    x += step
                }
                y += step
            }
        }
    }
}

// MARK: - Surface

struct TrackpadView: UIViewRepresentable {
    let send: (InputEvent) -> Void
    let latched: KeyModifiers
    let onModifiersConsumed: () -> Void

    func makeUIView(context: Context) -> TrackpadSurface { TrackpadSurface(frame: .zero) }

    func updateUIView(_ uiView: TrackpadSurface, context: Context) {
        uiView.send = send
        uiView.latchedModifiers = latched
        // Called from a gesture callback, never from inside a SwiftUI update, so the binding write
        // it performs needs no hop to the next runloop turn.
        uiView.onModifiersConsumed = onModifiersConsumed
    }
}

final class TrackpadSurface: UIView, UIGestureRecognizerDelegate {
    var send: (InputEvent) -> Void = { _ in }
    /// Modifiers the key row is holding for the next click. Cleared here when one is spent.
    var latchedModifiers: KeyModifiers = []
    var onModifiersConsumed: (() -> Void)?

    /// The virtual cursor, in frame coordinates (0…1), starting in the middle. Clamped, so pushing
    /// past an edge parks the pointer there instead of losing it.
    private var cursor = CGPoint(x: 0.5, y: 0.5)

    /// How far the pointer travels for a full swipe across the pad. The client does not know the
    /// Mac's size, so a real trackpad's pt-for-pt acceleration is not available to copy; 1.25
    /// frames per swipe lands close enough to reach any corner in one comfortable stroke.
    private static let travel: CGFloat = 1.25

    private var lastTranslation: CGPoint = .zero
    private var panTouches = 0
    /// True between a long press's start and the finger lifting: the button is down and moves drag.
    private var dragging = false
    /// Modifier bits currently pressed down around a click, so the ups can mirror the downs.
    private var held: KeyModifiers = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = true

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 2
        pan.delegate = self
        addGestureRecognizer(pan)

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        tap.numberOfTapsRequired = 1
        tap.numberOfTouchesRequired = 1
        addGestureRecognizer(tap)

        let twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap))
        twoFingerTap.numberOfTapsRequired = 1
        twoFingerTap.numberOfTouchesRequired = 2
        addGestureRecognizer(twoFingerTap)

        // Press and hold, then drag: the left button goes down and stays down, so a window or a
        // selection can be dragged from the pad. It has to run alongside the pan, which is what
        // actually moves the pointer while the button is held.
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        longPress.minimumPressDuration = 0.45
        longPress.numberOfTouchesRequired = 1
        longPress.delegate = self
        addGestureRecognizer(longPress)
    }

    required init?(coder: NSCoder) { fatalError() }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    // MARK: - Pointer

    private func moveCursor(dx: CGFloat, dy: CGFloat) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        cursor.x = min(max(cursor.x + dx / bounds.width * Self.travel, 0), 1)
        cursor.y = min(max(cursor.y + dy / bounds.height * Self.travel, 0), 1)
        // No rate limit needed here: sendInput coalesces moves to one every 8 ms.
        send(.pointer(.move, x: cursor.x, y: cursor.y))
    }

    /// One or two fingers. The touch count is re-read every callback, so dropping a second finger
    /// onto the pad mid-stroke turns a move into a scroll without lifting off first.
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            lastTranslation = .zero
            panTouches = gesture.numberOfTouches
        case .changed:
            let translation = gesture.translation(in: self)
            guard gesture.numberOfTouches == panTouches else {
                // A finger joined or left: rebase, or the jump in the translation becomes a jolt.
                panTouches = gesture.numberOfTouches
                lastTranslation = translation
                return
            }
            let dx = translation.x - lastTranslation.x
            let dy = translation.y - lastTranslation.y
            lastTranslation = translation
            guard dx != 0 || dy != 0 else { return }
            if panTouches >= 2 {
                guard bounds.width > 0, bounds.height > 0 else { return }
                // Natural sign, same as the direct-touch overlay: fingers down, content down.
                send(.scroll(x: cursor.x, y: cursor.y,
                             dx: dx / bounds.width, dy: dy / bounds.height))
            } else {
                moveCursor(dx: dx, dy: dy)
            }
        default:
            lastTranslation = .zero
            panTouches = 0
        }
    }

    @objc private func handleTap() { click(down: .leftDown, up: .leftUp) }

    /// Two fingers is the right button, the way a Mac trackpad's secondary click works.
    @objc private func handleTwoFingerTap() { click(down: .rightDown, up: .rightUp) }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            dragging = true
            pressModifiers()
            send(.pointer(.leftDown, x: cursor.x, y: cursor.y))
        case .ended, .cancelled, .failed:
            guard dragging else { return }
            dragging = false
            send(.pointer(.leftUp, x: cursor.x, y: cursor.y))
            releaseModifiers()
            consumeLatch()
        default:
            break
        }
    }

    /// The click itself carries no position beyond the cursor and no modifiers: pointer events have
    /// no modifier field at all, which is why the latched ones are pressed around it below.
    private func click(down: PointerAction, up: PointerAction) {
        pressModifiers()
        send(.pointer(down, x: cursor.x, y: cursor.y))
        send(.pointer(up, x: cursor.x, y: cursor.y))
        releaseModifiers()
        consumeLatch()
    }

    // MARK: - Latched modifiers

    // A ⌘-click has to be exactly that on the Mac: the command key physically down while the mouse
    // button goes down and up. `InputEvent.pointer` has nowhere to put a modifier, so each latched
    // modifier's own key (ctrl 0xE0, shift 0xE1, opt 0xE2, cmd 0xE3) is pressed before the click and
    // released after it, each event carrying the flags in force at that moment.

    private func pressModifiers() {
        held = []
        for key in latchedModifiers.keys {
            held.insert(key.flag)
            send(.key(hidUsage: key.usage, down: true, modifiers: held.rawValue))
        }
    }

    private func releaseModifiers() {
        for key in held.keys.reversed() {
            held.remove(key.flag)
            send(.key(hidUsage: key.usage, down: false, modifiers: held.rawValue))
        }
        held = []
    }

    private func consumeLatch() {
        guard !latchedModifiers.isEmpty else { return }
        latchedModifiers = []
        onModifiersConsumed?()
    }
}
