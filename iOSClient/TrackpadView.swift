import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass
import StreamProtocol

/// The portrait trackpad: the well, its dot grid, the hint, and the touch surface itself.
///
/// The opposite input model to `InputOverlay`, which is direct-touch — there the pointer goes where
/// you touch. Here the pad is relative, like a Mac's, so this side has to remember where the
/// pointer is; the wire format is unchanged, an absolute position in frame coordinates.
struct Trackpad: View {
    let send: (InputEvent) -> Void
    /// Writes this device's own pointer, the pad's cursor (`StreamClient.setOwnPointer`, from the
    /// trackpad): a fraction of the frame.
    let setPointer: (CGPoint) -> Void
    /// The feed's anchor and re-seeds, from one look (`StreamClient.pointerFeedState`), so the pad
    /// carries on from wherever the pointer is: where the Mac's arrow shows, or where something else
    /// on this device left it.
    let feed: () -> (anchor: CGPoint?, reseeds: Int)
    /// Fingers on the pad (`StreamClient.trackpadFingers`); only Q1's flip reads them.
    let onFingers: (Int) -> Void
    let latched: KeyModifiers
    let onModifiersConsumed: () -> Void
    /// What the pad's vertical motion is measured against: nil is its own height (see
    /// `TrackpadSurface.verticalSpan`).
    var verticalSpan: CGFloat? = nil
    /// A three- or four-finger gesture, for the Mac (`StreamClient.sendGesture`). True when it went.
    var sendGesture: (TrackpadGestures.Gesture, Int) -> Bool = { _, _ in false }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 22, style: .continuous) }

    var body: some View {
        ZStack {
            Palette.trackpad
            DotGrid().allowsHitTesting(false)
            TrackpadView(send: send, setPointer: setPointer, feed: feed, onFingers: onFingers,
                         latched: latched, onModifiersConsumed: onModifiersConsumed,
                         verticalSpan: verticalSpan, sendGesture: sendGesture)
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
    let setPointer: (CGPoint) -> Void
    let feed: () -> (anchor: CGPoint?, reseeds: Int)
    let onFingers: (Int) -> Void
    let latched: KeyModifiers
    let onModifiersConsumed: () -> Void
    var verticalSpan: CGFloat? = nil
    var sendGesture: (TrackpadGestures.Gesture, Int) -> Bool = { _, _ in false }

    func makeUIView(context: Context) -> TrackpadSurface {
        let view = TrackpadSurface(frame: .zero)
        // The pointer closures go in before the first update as well: the surface reads the feed as
        // it joins the window, and that need not wait for `updateUIView`.
        view.setPointer = setPointer
        view.feed = feed
        view.onFingers = onFingers
        return view
    }

    func updateUIView(_ uiView: TrackpadSurface, context: Context) {
        uiView.send = send
        uiView.setPointer = setPointer
        uiView.feed = feed
        uiView.onFingers = onFingers
        uiView.latchedModifiers = latched
        uiView.verticalSpan = verticalSpan
        uiView.sendGesture = sendGesture
        // Called from a gesture callback, never from inside a SwiftUI update, so the binding write
        // it performs needs no hop to the next runloop turn.
        uiView.onModifiersConsumed = onModifiersConsumed
    }
}

final class TrackpadSurface: UIView, UIGestureRecognizerDelegate {
    var send: (InputEvent) -> Void = { _ in }
    /// Writes this device's own pointer (`StreamClient.setOwnPointer`, from the trackpad: a fraction
    /// of the frame). Called with the virtual cursor on every move, click, drag and scroll, so the
    /// sprite follows the finger at touch rate rather than a network round trip behind it. Never
    /// cleared when the pad leaves the screen: the pointer outlives a rotation (in landscape it
    /// hides, and comes back in portrait).
    var setPointer: (CGPoint) -> Void = { _ in }
    /// The feed's anchor and re-seeds (`StreamClient.pointerFeedState`). See `pad`.
    var feed: () -> (anchor: CGPoint?, reseeds: Int) = { (nil, 0) }
    /// Fingers on the pad, whenever the count changes (`StreamClient.trackpadFingers`).
    var onFingers: (Int) -> Void = { _ in }
    /// Modifiers the key row is holding for the next click. Cleared here when one is spent.
    var latchedModifiers: KeyModifiers = []
    var onModifiersConsumed: (() -> Void)?
    /// How far a finger travels down the pad for the share of the frame that the pad's width is
    /// across: nil is the pad's own height. A phone's pad is far taller than the picture's shape,
    /// so it passes its width ÷ 1.6 (PhonePortraitLayout.trackpadSpan): a stroke then moves the
    /// pointer as far down as across on a 16:10 picture, and the extra height is room, not a slower
    /// pointer. Pointer motion, two-finger scrolling and its coast all use it.
    var verticalSpan: CGFloat?
    /// `verticalSpan`, or the pad's height.
    private var ySpan: CGFloat { verticalSpan.flatMap { $0 > 0 ? $0 : nil } ?? bounds.height }
    /// A three- or four-finger gesture the pad decided, for the Mac (`StreamClient.sendGesture`,
    /// which checks this device's switch and the Mac's `gestures`, and shows the Desktop first while
    /// a window streams). True when it went, which the light tick follows.
    var sendGesture: (TrackpadGestures.Gesture, Int) -> Bool = { _, _ in false }
    /// Every direct touch, for three-finger strokes: from the moment three fingers are down, nothing
    /// of the stroke reaches the Mac but its gesture (`strokes.silent`, each finger handler's first
    /// line).
    private let strokes = StrokeObserver()

    /// The virtual cursor, in frame coordinates (0…1), starting in the middle, clamped, so pushing
    /// past an edge parks the pointer there instead of losing it (PadCursor, pure, checked in
    /// Tests/checks/pointer-presence). The source of truth for where a click lands. The feed only
    /// re-seeds it: a stroke's first finger, and the pad joining a window, carry on from the anchor
    /// (`adoptAnchor`), where the Mac's arrow is or where something else on this device (a Pencil,
    /// a tap, the pad this one replaced across a rotation) left the pointer; and a move, a click, a
    /// scroll or a drag first catches up (`catchUp`), so after the Mac took the pointer, or moved
    /// it on, under a resting finger the next move carries on from the Mac's pointer instead of
    /// pulling it back.
    private var pad = PadCursor()
    private var cursor: CGPoint { pad.cursor }
    /// Counts the fingers on the pad for `onFingers`, whatever the other recognizers take.
    private let fingerCounter = FingerCounter(target: nil, action: nil)

    /// How far the pointer travels for a full swipe across the pad. The client does not know the
    /// Mac's size, so a real trackpad's pt-for-pt acceleration is not available to copy; 1.25
    /// frames per swipe lands close enough to reach any corner in one comfortable stroke.
    private static let travel: CGFloat = 1.25

    // One-finger pointer motion: the tracker, from touch-down.

    private let tracker = FingerTracker(target: nil, action: nil)
    /// How far a finger travels from where it landed before the pointer starts to follow. Small
    /// enough to feel instant, big enough that a clean tap clicks without nudging the pointer
    /// first. Past it the whole distance from touch-down counts, so no travel is lost to it.
    private static let trackSlop: CGFloat = 2
    /// Where the tracked finger was at the last move turned into pointer motion (its touch-down
    /// point until it clears the slop), in this view's points.
    private var trackLast: CGPoint = .zero
    /// True once the tracked finger has cleared the slop.
    private var trackLive = false
    /// Set when the pan turned this stroke into a two-finger scroll; cleared when the tracker begins
    /// the next stroke. Backs up the tracker's own second-finger check (`FingerTracker`).
    private var trackSuspended = false

    // Two-finger scrolling, and one-finger motion whenever the tracker is not driving: the pan.

    private var lastTranslation: CGPoint = .zero
    private var panTouches = 0
    /// True while two fingers are scrolling: between the `.scrollGesture(.began)` and `.ended`
    /// this view sent.
    private var scrolling = false
    /// Pad velocity at the last two-finger callback. When one finger of two lifts first the scroll
    /// ends there, and the recognizer's velocity at that moment is polluted by the centroid jump.
    private var scrollVelocity: CGPoint = .zero
    /// The coast after a two-finger flick. Shared engine with the direct-touch overlay.
    private let momentum = ScrollMomentum()
    /// True between a long press's start and the finger lifting: the button is down and moves drag.
    private var dragging = false
    /// Modifier bits currently pressed down around a click, so the ups can mirror the downs.
    private var held: KeyModifiers = []

    /// The click you feel, as on a Force Touch trackpad: `.rigid` is the stock impact closest to
    /// its short, hard tick. It fires for a click and for arming and releasing a drag, never for a
    /// move, a scroll or a coast. iPads have no Taptic Engine; there every call is a silent no-op,
    /// which is UIKit's doing, so there is deliberately no device check here.
    private let clickHaptic = UIImpactFeedbackGenerator(style: .rigid)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = true

        // One finger moves the pointer from its first point of travel; see `FingerTracker`. It only
        // watches (cancelsTouchesInView off), so it takes nothing from the recognizers below or
        // from touchesBegan.
        tracker.addTarget(self, action: #selector(handleTrack))
        tracker.minimumPressDuration = 0
        tracker.allowableMovement = .greatestFiniteMagnitude
        tracker.cancelsTouchesInView = false
        tracker.delegate = self
        addGestureRecognizer(tracker)

        // Two fingers scroll. The pan moves the pointer with one finger only when the tracker is
        // not driving, typically after a scroll when one finger of the two lifts and the other
        // carries on, as it can on a Mac.
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
        // selection can be dragged from the pad. It has to run alongside the tracker, which is what
        // actually moves the pointer while the button is held.
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress))
        longPress.minimumPressDuration = 0.45
        longPress.numberOfTouchesRequired = 1
        longPress.delegate = self
        addGestureRecognizer(longPress)

        // Only counts: it never recognizes, takes no touch from anyone and delays nothing.
        fingerCounter.onCount = { [weak self] n in self?.onFingers(n) }
        fingerCounter.delegate = self
        addGestureRecognizer(fingerCounter)

        // Three fingers or more: a gesture for the Mac, never a click, a drag or a scroll
        // (StrokeObserver, TrackpadGestures). It only watches, as the counter does; no stroke goes
        // silent while the press-and-hold drag holds the button, which must still come up.
        strokes.holding = { [weak self] in self?.dragging ?? false }
        strokes.onSilenced = { [weak self] in self?.strokeSilenced() }
        strokes.onGesture = { [weak self] gesture, fingers in self?.gestureDecided(gesture, fingers: fingers) }
        addGestureRecognizer(strokes)
    }

    required init?(coder: NSCoder) { fatalError() }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

    // MARK: - Pointer

    private func moveCursor(dx: CGFloat, dy: CGFloat) {
        guard bounds.width > 0, bounds.height > 0 else { return }
        catchUp()
        pad.move(dx: Double(dx / bounds.width * Self.travel), dy: Double(dy / ySpan * Self.travel))
        // The sprite first, since it is the feedback the finger is waiting for; then the Mac, whose
        // cursor still has to follow for clicks to land there. No rate limit needed here:
        // sendInput coalesces moves to one every 8 ms.
        setPointer(cursor)
        send(.pointer(.move, x: cursor.x, y: cursor.y))
    }

    /// A stroke's first finger, or the pad joining a window: the cursor carries on from the anchor,
    /// where the pointer is now (the Mac's arrow, or where this device last put it). Carrying on from
    /// there keeps the next move from jumping back to the pad's stale idea of it, and makes a tap
    /// click where the pointer is seen. No anchor yet (nothing known this session): it stays.
    private func adoptAnchor() {
        let f = feed()
        pad.adopt(anchor: f.anchor, reseeds: f.reseeds)
    }

    /// Before a move, a click, a scroll or a drag reads the cursor: when the Mac or another device
    /// took the pointer, or moved it on, since the pad last looked, the cursor carries on from the
    /// anchor (the Mac's pointer).
    private func catchUp() {
        let f = feed()
        pad.catchUp(anchor: f.anchor, reseeds: f.reseeds)
    }

    /// True while the tracker owns one-finger motion: its finger is down, and the stroke has not
    /// become a two-finger one. Otherwise the pan moves the pointer.
    private var trackerDriving: Bool {
        (tracker.state == .began || tracker.state == .changed)
            && !tracker.sawSecondFinger && !trackSuspended
    }

    /// One finger, from touch-down: the pointer follows as soon as the finger clears the slop.
    /// Once a second finger joins, this stroke's motion belongs to the pan (scroll, then one-finger
    /// moves after a lift, with its own rebase) until every finger is up.
    @objc private func handleTrack() {
        guard !strokes.silent else { return }
        switch tracker.state {
        case .began:
            trackSuspended = false
            trackLive = false
            trackLast = tracker.location(in: self)
        case .changed:
            guard trackerDriving else { return }
            let location = tracker.location(in: self)
            if !trackLive {
                guard hypot(location.x - trackLast.x, location.y - trackLast.y) > Self.trackSlop else { return }
                trackLive = true
            }
            let dx = location.x - trackLast.x
            let dy = location.y - trackLast.y
            trackLast = location
            guard dx != 0 || dy != 0 else { return }
            moveCursor(dx: dx, dy: dy)
        default:
            trackLive = false
        }
    }

    /// One or two fingers. The touch count is re-read every callback, so dropping a second finger
    /// onto the pad mid-stroke turns a move into a scroll without lifting off first.
    ///
    /// Two fingers are a Mac-trackpad scroll gesture: `.began` when the second finger is down,
    /// deltas, `.ended` when either finger lifts, then momentum if it was a flick. One finger only
    /// moves the pointer and leaves a coasting scroll alone, as on a Mac — and only when the
    /// tracker is not already doing it, which it normally is: the pan begins ~10 pt into a stroke,
    /// the tracker at touch-down.
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard !strokes.silent else { return }
        switch gesture.state {
        case .began:
            panTouches = gesture.numberOfTouches
            if panTouches >= 2 {
                lastTranslation = .zero
                beginScroll()
            } else {
                // The pan has already held back its ~10 pt of hysteresis. Rebase past it, and if
                // this stroke is the pan's to drive, move by it now instead of as a jump on the
                // next callback.
                let translation = gesture.translation(in: self)
                lastTranslation = translation
                if !trackerDriving, translation != .zero {
                    moveCursor(dx: translation.x, dy: translation.y)
                }
            }
        case .changed:
            let translation = gesture.translation(in: self)
            guard gesture.numberOfTouches == panTouches else {
                // A finger joined or left: rebase, or the jump in the translation becomes a jolt.
                panTouches = gesture.numberOfTouches
                lastTranslation = translation
                if panTouches >= 2, !scrolling {
                    beginScroll()
                } else if panTouches < 2, scrolling {
                    // Fingers rarely lift together, so this is usually the flick's lift-off.
                    endScroll(momentumVelocity: scrollVelocity)
                }
                return
            }
            let dx = translation.x - lastTranslation.x
            let dy = translation.y - lastTranslation.y
            lastTranslation = translation
            if panTouches >= 2 { scrollVelocity = gesture.velocity(in: self) }
            guard dx != 0 || dy != 0 else { return }
            if panTouches >= 2 {
                guard bounds.width > 0, bounds.height > 0 else { return }
                catchUp()
                // Natural sign, same as the direct-touch overlay: fingers down, content down.
                send(.scroll(x: cursor.x, y: cursor.y,
                             dx: dx / bounds.width, dy: dy / ySpan))
            } else if !trackerDriving {
                moveCursor(dx: dx, dy: dy)
            }
        case .ended:
            if scrolling { endScroll(momentumVelocity: gesture.velocity(in: self)) }
            lastTranslation = .zero
            panTouches = 0
        default:
            // Cancelled or failed: the system took the touches, so close the gesture but no coast.
            if scrolling { endScroll(momentumVelocity: nil) }
            lastTranslation = .zero
            panTouches = 0
        }
    }

    /// A new two-finger gesture ends any coast still running first (its `.momentumEnded` goes out
    /// before this `.began`), so the host never has two scrolls open.
    private func beginScroll() {
        momentum.stop()
        scrolling = true
        // From here the tracker must not move the pointer under the scroll, even if UIKit never
        // showed it the second finger.
        trackSuspended = true
        scrollVelocity = .zero
        // The scroll hands this device the pointer where the cursor is: the sprite shows it there
        // (after the Mac took the pointer, the Mac's arrow becomes the pad's).
        catchUp()
        setPointer(cursor)
        send(.scrollGesture(.began, x: cursor.x, y: cursor.y))
    }

    /// Closes the gesture and, given a lift-off velocity fast enough to be a flick, coasts. The
    /// coast stays at the cursor where the scroll ended, even if one finger then moves the
    /// pointer: the Mac routes a whole gesture, momentum included, to the view it began in.
    private func endScroll(momentumVelocity velocity: CGPoint?) {
        scrolling = false
        let at = cursor
        send(.scrollGesture(.ended, x: at.x, y: at.y))
        guard let velocity else { return }
        // Begin and end capture the send closure rather than self, so the end still goes out if
        // this view is torn down mid-coast.
        let send = self.send
        momentum.start(
            velocity: velocity,
            onBegin: { send(.scrollGesture(.momentumBegan, x: at.x, y: at.y)) },
            onStep: { [weak self] step in
                // Converted to frame fractions exactly as live two-finger deltas are.
                guard let self, self.bounds.width > 0, self.bounds.height > 0 else { return }
                self.send(.scroll(x: at.x, y: at.y,
                                  dx: step.x / self.bounds.width, dy: step.y / self.ySpan))
            },
            onEnd: { send(.scrollGesture(.momentumEnded, x: at.x, y: at.y)) })
    }

    /// Two fingers resting on the pad stop a coasting scroll, as on a Mac trackpad, before the pan
    /// has even recognized. One finger does not: that is the pointer, and it may move freely
    /// while the content coasts.
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        let down = event?.touches(for: self)?
            .filter { $0.phase != .ended && $0.phase != .cancelled }.count ?? 0
        // The first finger of a new stroke: carry on from wherever the pointer is now.
        if down == touches.count { adoptAnchor() }
        // Spin the Taptic Engine up now, so a tap's click lands without its start-up delay.
        clickHaptic.prepare()
        if down >= 2 { momentum.stop() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            // This device's pointer is left alone: it outlives this view across a rotation.
            momentum.stop()
            #if DEBUG
            if InputScript.pad === self { InputScript.pad = nil }
            #endif
        } else {
            adoptAnchor()
            #if DEBUG
            InputScript.pad = self
            runInputTest()
            #endif
        }
    }

    @objc private func handleTap() {
        guard !strokes.silent else { return }
        click(down: .leftDown, up: .leftUp)
    }

    /// Two fingers is the right button, the way a Mac trackpad's secondary click works.
    @objc private func handleTwoFingerTap() {
        guard !strokes.silent else { return }
        click(down: .rightDown, up: .rightUp)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard !strokes.silent else { return }
        switch gesture.state {
        case .began:
            dragging = true
            // Firmer than a click: the button is now held down.
            clickHaptic.impactOccurred(intensity: 1.0)
            catchUp()
            setPointer(cursor)
            pressModifiers()
            send(.pointer(.leftDown, x: cursor.x, y: cursor.y))
        case .ended, .cancelled, .failed:
            guard dragging else { return }
            dragging = false
            // Softer: the button coming back up.
            clickHaptic.impactOccurred(intensity: 0.5)
            catchUp()
            setPointer(cursor)
            send(.pointer(.leftUp, x: cursor.x, y: cursor.y))
            releaseModifiers()
            consumeLatch()
        default:
            break
        }
    }

    // MARK: - Three fingers

    /// A stroke just went silent (TrackpadGestures: three fingers down): a two-finger scroll already
    /// under way ends here, with no coast. Pointer motion before the third finger stays (at most
    /// `chordTravel`); nothing else of the stroke goes out but its gesture.
    private func strokeSilenced() {
        if scrolling { endScroll(momentumVelocity: nil) }
    }

    /// The stroke's gesture, decided as one of its three fingers lifts: to the Mac, with a light tick
    /// when it went (an iPhone's; an iPad has no Taptic Engine). A latched modifier stays latched: a
    /// gesture is not a keystroke.
    private func gestureDecided(_ gesture: TrackpadGestures.Gesture, fingers: Int) {
        if sendGesture(gesture, fingers) { clickHaptic.impactOccurred(intensity: 0.7) }
    }

    /// The click itself carries no position beyond the cursor and no modifiers: pointer events have
    /// no modifier field at all, which is why the latched ones are pressed around it below.
    private func click(down: PointerAction, up: PointerAction) {
        clickHaptic.impactOccurred(intensity: 0.8)
        catchUp()
        setPointer(cursor)
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

    #if DEBUG
    // MARK: - The input script (`-SillInputScript`, ContentView)

    /// A stroke the script started and has not lifted.
    private var scriptStroke = false

    /// `down`: a finger lands, as the first finger of a stroke does: the cursor carries on from the
    /// anchor, and the pad has a finger on it.
    func scriptDown() {
        guard !scriptStroke else { return }
        scriptStroke = true
        adoptAnchor()
        onFingers(1)
    }

    /// `pad DX,DY`: that finger moves DX, DY points (a stroke starts first if none is down), through
    /// the pad's own move path.
    func scriptMove(dx: CGFloat, dy: CGFloat) {
        scriptDown()
        moveCursor(dx: dx, dy: dy)
    }

    /// `lift`: the finger comes up.
    func scriptLift() {
        guard scriptStroke else { return }
        scriptStroke = false
        onFingers(0)
    }

    /// `click`: a tap on the pad, which clicks where the cursor is.
    func scriptClick() { click(down: .leftDown, up: .leftUp) }
    #endif
}

// MARK: - Finger counter

/// Counts the fingers on the pad for Q1's flip (`StreamClient.trackpadFingers`). The view's own
/// touch callbacks cannot: the pan and the taps cancel its touches as they recognize, after which it
/// never hears a finger lift. This recognizer sees every touch and never recognizes (it stays
/// possible, so UIKit ends it with the last finger), takes none from the view (`cancelsTouchesInView`
/// off) and delays none (`delaysTouchesEnded` off); the pad's delegate lets it run beside the rest.
private final class FingerCounter: UIGestureRecognizer {
    var onCount: ((Int) -> Void)?
    private var down = Set<UITouch>()

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        down.formUnion(touches)
        onCount?(down.count)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        down.subtract(touches)
        onCount?(down.count)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        down.subtract(touches)
        onCount?(down.count)
    }

    override func reset() {
        super.reset()
        guard !down.isEmpty else { return }
        down.removeAll()
        onCount?(0)
    }
}

// MARK: - Finger tracker

/// A long press that begins at touch-down (`minimumPressDuration` 0) and never fails on travel
/// (`allowableMovement` unbounded): a one-finger tracker with no hysteresis. A pan recognizer holds
/// back ~10 pt before it begins, which on a trackpad is a dead patch at the start of every stroke
/// followed by a jump; this reports the finger from its first point of travel.
///
/// It also records whether a second finger landed while it was tracking. What UIKit's long press
/// does with a touch beyond `numberOfTouchesRequired` (adopt it, ignore it, end) is not specified,
/// so the count is taken here, from the view's own touches, before the superclass sees the new one.
private final class FingerTracker: UILongPressGestureRecognizer {
    private(set) var sawSecondFinger = false

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if let view,
           let down = event.touches(for: view)?.filter({ $0.phase != .ended && $0.phase != .cancelled }),
           down.count >= 2 {
            sawSecondFinger = true
        }
        super.touchesBegan(touches, with: event)
    }

    override func reset() {
        super.reset()
        sawSecondFinger = false
    }
}

#if DEBUG

// MARK: - Input test (DEBUG)

/// DEBUG `-SillInputTest 1` (ContentView's contract): a scripted run through the key row's and the
/// trackpad's own code, once per launch, so a gate can see what they send without anything driving
/// the UI. Only for a session `-SillConnect` dialed on this Mac's loopback, and even there each
/// event reaches the Mac's host: a synthetic host counts it as `in.dry` and posts nothing, a real
/// one posts it on this Mac, so point it only at a synthetic host, or put a relay that drops kind 8
/// (input) in front of the host. The key row taps cmd, esc, shift and ctrl (KeyRow.runInputTest);
/// the trackpad then strokes, taps and scrolls (`TrackpadSurface.runInputTest`).
enum InputTest {
    static let enabled: Bool = {
        guard UserDefaults.standard.bool(forKey: "SillInputTest") else { return false }
        let host = (UserDefaults.standard.string(forKey: "SillConnect") ?? "").lowercased()
        guard host.hasPrefix("127.0.0.1:") || host.hasPrefix("[::1]:") || host.hasPrefix("localhost:") else {
            print("input test: not run: -SillInputTest needs a session -SillConnect dials on this Mac's loopback")
            return false
        }
        return true
    }()
    private static var claimed: Set<String> = []

    /// True the first time `part` asks, while the test is on.
    static func claim(_ part: String) -> Bool {
        guard enabled, !claimed.contains(part) else { return false }
        claimed.insert(part)
        return true
    }

    static func describe(_ m: KeyModifiers) -> String {
        let names = [(KeyModifiers.control, "ctrl"), (.option, "opt"), (.command, "cmd"), (.shift, "shift")]
            .filter { m.contains($0.0) }.map(\.1)
        return names.isEmpty ? "nothing" : names.joined(separator: "+")
    }
}

extension TrackpadSurface {
    /// The trackpad's half of `InputTest`, 2.6 s after the pad joins a window (after the key row's
    /// taps): a touch at the pad's centre is checked to land on the pad itself, then a stroke of 12
    /// moves (60 pt right and 40 down, through `moveCursor`, which the tracker and the pan call),
    /// a tap (`click`: the latched shift and ctrl go down around it and the latch is spent), and a
    /// two-finger scroll of five 8 pt steps down with its begin and end, no coast.
    fileprivate func runInputTest() {
        guard InputTest.claim("trackpad") else { return }
        let start = DispatchTime.now()
        func at(_ seconds: Double, _ step: @escaping () -> Void) {
            DispatchQueue.main.asyncAfter(deadline: start + seconds, execute: step)
        }
        at(2.6) { [weak self] in
            guard let self, let window = self.window else { return }
            let centre = self.convert(CGPoint(x: self.bounds.midX, y: self.bounds.midY), to: window)
            let hit = window.hitTest(centre, with: nil)
            let reached = hit === self ? "the pad" : hit.map { String(describing: type(of: $0)) } ?? "nothing"
            print("input test: the pad is " + String(format: "%.0f×%.0f pt", self.bounds.width, self.bounds.height)
                  + String(format: ", its vertical span %.1f pt; a touch at its centre reaches ", self.ySpan) + reached)
            for _ in 0..<12 { self.moveCursor(dx: 5, dy: 40.0 / 12) }
            print("input test: stroke done, the pointer at " + String(format: "(%.3f, %.3f)", self.cursor.x, self.cursor.y))
        }
        at(3.2) { [weak self] in
            guard let self else { return }
            print("input test: tap with " + InputTest.describe(self.latchedModifiers) + " latched")
            self.handleTap()
        }
        at(3.8) { [weak self] in
            guard let self else { return }
            self.beginScroll()
            for _ in 0..<5 {
                self.send(.scroll(x: self.cursor.x, y: self.cursor.y, dx: 0, dy: 8 / self.ySpan))
            }
            self.endScroll(momentumVelocity: nil)
            print("input test: two-finger scroll done (5 steps of 8 pt down)")
        }
    }
}
#endif
