import AppKit
import SwiftUI
import StreamProtocol

/// The stream on screen and everything this Mac's mouse, trackpad and keyboard do over it.
///
/// It hosts the client's one display view and turns AppKit's events into the protocol's input:
/// positions as fractions of the letterboxed video (as the iOS overlay does for touches), the
/// mouse buttons, scrolls with the trackpad's own phases and momentum (the host stamps them on the
/// Mac's scroll events, so the streamed app rubber-bands and coasts as under a real trackpad), and
/// every key by its position (MacKeyForwarder).
///
/// While it has the keyboard, keys go to the streamed Mac before this app's menus see them, ⌘
/// shortcuts included (an event monitor, since AppKit gives ⌘ chords to the menus first and sends
/// no key up for them), unless `sendsShortcuts` is off. ⌃⌥⌘ chords always stay here: they are the
/// viewer's own (StreamCommands). The system cursor takes the streamed Mac's cursor shape over the
/// picture, so the pointer looks and lands as it would there.
final class StreamInputView: NSView {
    weak var client: StreamClient? {
        didSet { if client !== oldValue { attachDisplay() } }
    }
    /// The size of the picture's area changed (points): the viewport to send.
    var onSizeChange: ((CGSize) -> Void)?
    /// ⌘ shortcuts go to the streamed Mac while this view has the keyboard.
    var sendsShortcuts = true

    private var keys = MacKeyForwarder()
    private var keyMonitor: Any?
    private var leftDown = false
    private var rightDown = false
    private var scrollInGesture = false
    private var scrollInMomentum = false
    private var lastReportedSize: CGSize = .zero
    private var cursor: NSCursor?
    private var observers: [NSObjectProtocol] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    /// The first click on an inactive window also reaches the streamed Mac, as it would there.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: The display view

    /// Hosts the client's single display view, wherever it was before (a new window's surface takes
    /// it, as a rotation re-hosts it on iOS), and wires the pointer sprite and the cursor shape.
    private func attachDisplay() {
        guard let client else { return }
        let display = client.displayView
        display.removeFromSuperview()
        display.frame = bounds
        display.autoresizingMask = [.width, .height]
        addSubview(display)

        client.onCursorShapeChange = { [weak self, weak display] shape in
            display?.setCursorShape(shape)
            self?.cursorShapeChanged(shape)
        }
        display.setCursorShape(client.cursorShape)
        cursorShapeChanged(client.cursorShape)
        client.onPointerChange = { [weak display] p in display?.setPointer(p) }
        display.onVideoSizeForPointer = { [weak client] _ in client?.pointerFrameChanged() }
        client.renderPointer()
    }

    override func layout() {
        super.layout()
        let size = bounds.size
        guard size.width > 0, size.height > 0, size != lastReportedSize else { return }
        lastReportedSize = size
        onSizeChange?(size)
        window?.invalidateCursorRects(for: self)
    }

    // MARK: Focus

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        guard let window else {
            stopKeys()
            MacMenuHub.shared.unregister(self)
            return
        }
        MacMenuHub.shared.register(self)
        // Another window or app takes the keyboard: AppKit sends this view no ups after that.
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            self?.letGo()
        })
        DispatchQueue.main.async { [weak self] in
            guard let self, self.window != nil else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func becomeFirstResponder() -> Bool {
        startKeys()
        return true
    }

    override func resignFirstResponder() -> Bool {
        letGo()
        stopKeys()
        return true
    }

    /// Every key and button this view holds down on the Mac goes up.
    private func letGo() {
        for event in keys.releaseAll() { client?.sendInput(event) }
        if leftDown || rightDown, let p = lastPoint {
            if leftDown { client?.sendInput(.pointer(.leftUp, x: p.x, y: p.y)) }
            if rightDown { client?.sendInput(.pointer(.rightUp, x: p.x, y: p.y)) }
        }
        leftDown = false
        rightDown = false
        endScroll()
    }

    // MARK: Keys

    private func startKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            guard let self else { return event }
            return self.handleKey(event) ? nil : event
        }
    }

    private func stopKeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// True when the key went to the streamed Mac (AppKit then never sees it).
    private func handleKey(_ event: NSEvent) -> Bool {
        guard let client, client.connected, event.window === window, window?.isKeyWindow == true,
              window?.firstResponder === self else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.type == .keyDown || event.type == .keyUp {
            // The viewer's own commands, and ⌘ chords when shortcuts stay here.
            if flags.isSuperset(of: [.command, .option, .control]) { return false }
            if !sendsShortcuts, flags.contains(.command) { return false }
        }
        let events: [InputEvent]
        switch event.type {
        case .keyDown: events = keys.keyDown(event)
        case .keyUp: events = keys.keyUp(event)
        case .flagsChanged: events = keys.flagsChanged(event)
        default: return false
        }
        events.forEach(client.sendInput)
        // A modifier's change also reaches AppKit, so the menus see ⌘ go up; nothing is typed by it.
        return event.type != .flagsChanged
    }

    // MARK: The mouse

    /// The last position sent, a fraction of the frame.
    private var lastPoint: (x: Double, y: Double)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate,
                                                               .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    /// Where `event` is, as a fraction of the frame the picture shows; nil outside the picture
    /// (unless `clamp`: a drag that leaves it keeps going, held at its edge) or with no picture.
    private func fraction(_ event: NSEvent, clamp: Bool = false) -> (x: Double, y: Double)? {
        guard let client else { return nil }
        let rect = HEVCDisplayView.videoRect(in: bounds, videoSize: client.videoSize)
        guard rect.width > 0, rect.height > 0 else { return nil }
        let p = convert(event.locationInWindow, from: nil)
        var x = (p.x - rect.minX) / rect.width
        var y = (p.y - rect.minY) / rect.height
        if clamp {
            x = min(max(x, 0), 1)
            y = min(max(y, 0), 1)
        } else if x < 0 || x >= 1 || y < 0 || y >= 1 {
            return nil
        }
        return (Double(x), Double(y))
    }

    private func send(_ action: PointerAction, _ event: NSEvent, clamp: Bool = false) {
        guard let client, client.connected, let p = fraction(event, clamp: clamp) else { return }
        lastPoint = p
        client.sendInput(.pointer(action, x: p.x, y: p.y))
    }

    override func mouseMoved(with event: NSEvent) { send(.move, event) }
    override func mouseDragged(with event: NSEvent) { send(.move, event, clamp: true) }
    override func rightMouseDragged(with event: NSEvent) { send(.move, event, clamp: true) }

    override func mouseDown(with event: NSEvent) {
        if window?.firstResponder !== self { window?.makeFirstResponder(self) }
        // ⌃-click is a right click on a Mac with a one-button mouse or a trackpad set so; the streamed
        // Mac gets the control key and decides, as it would at its own trackpad.
        guard fraction(event) != nil else { return }
        send(.move, event)
        send(.leftDown, event)
        leftDown = true
    }

    override func mouseUp(with event: NSEvent) {
        guard leftDown else { return }
        leftDown = false
        send(.leftUp, event, clamp: true)
    }

    override func rightMouseDown(with event: NSEvent) {
        if window?.firstResponder !== self { window?.makeFirstResponder(self) }
        guard fraction(event) != nil else { return }
        send(.move, event)
        send(.rightDown, event)
        rightDown = true
    }

    override func rightMouseUp(with event: NSEvent) {
        guard rightDown else { return }
        rightDown = false
        send(.rightUp, event, clamp: true)
    }

    // MARK: Scrolling

    /// A trackpad's scroll goes with its phases (began, changed, ended, then the system's own
    /// momentum), a wheel's as bare deltas. Deltas are fractions of the picture, so content under
    /// the pointer moves with the fingers at whatever size the picture is drawn; AppKit's deltas
    /// already follow this Mac's natural-scrolling setting, which is the protocol's sign.
    override func scrollWheel(with event: NSEvent) {
        guard let client, client.connected else { return }
        let rect = HEVCDisplayView.videoRect(in: bounds, videoSize: client.videoSize)
        guard rect.width > 0, rect.height > 0 else { return }
        let at = fraction(event, clamp: true) ?? (0.5, 0.5)

        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            endScroll()
            if event.phase.contains(.began) {
                client.sendInput(.scrollGesture(.began, x: at.x, y: at.y))
                scrollInGesture = true
            }
        }
        if event.momentumPhase.contains(.began) {
            if scrollInGesture { client.sendInput(.scrollGesture(.ended, x: at.x, y: at.y)); scrollInGesture = false }
            client.sendInput(.scrollGesture(.momentumBegan, x: at.x, y: at.y))
            scrollInMomentum = true
        }

        // A wheel's deltas are lines; give each about what a Mac scrolls for one notch.
        let perLine: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 12
        let dx = event.scrollingDeltaX * perLine, dy = event.scrollingDeltaY * perLine
        if dx != 0 || dy != 0 {
            client.sendInput(.scroll(x: at.x, y: at.y, dx: Double(dx / rect.width), dy: Double(dy / rect.height)))
        }

        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            if scrollInGesture { client.sendInput(.scrollGesture(.ended, x: at.x, y: at.y)) }
            scrollInGesture = false
        }
        if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) {
            if scrollInMomentum { client.sendInput(.scrollGesture(.momentumEnded, x: at.x, y: at.y)) }
            scrollInMomentum = false
        }
    }

    /// Closes a gesture or a coast still open (the view losing focus mid-scroll).
    private func endScroll() {
        let at = lastPoint ?? (0.5, 0.5)
        if scrollInGesture { client?.sendInput(.scrollGesture(.ended, x: at.x, y: at.y)) }
        if scrollInMomentum { client?.sendInput(.scrollGesture(.momentumEnded, x: at.x, y: at.y)) }
        scrollInGesture = false
        scrollInMomentum = false
    }

    // MARK: The cursor

    /// The streamed Mac's cursor shape (kind 14) as this Mac's own cursor, at its size in points.
    private func cursorShapeChanged(_ shape: StreamClient.CursorShape?) {
        if let shape, shape.size.width > 0, shape.size.height > 0 {
            let image = shape.image.copy() as! NSImage
            image.size = shape.size
            cursor = NSCursor(image: image, hotSpot: shape.hotspot)
        } else {
            cursor = nil
        }
        window?.invalidateCursorRects(for: self)
        if let window, window.isKeyWindow, let p = window.mouseLocationOutsideOfEventStream as NSPoint?,
           bounds.contains(convert(p, from: nil)) {
            (cursor ?? .arrow).set()
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        (cursor ?? .arrow).set()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor ?? .arrow)
    }
}

/// The stream view in SwiftUI.
struct StreamSurface: NSViewRepresentable {
    let client: StreamClient
    var sendsShortcuts: Bool
    var onSizeChange: (CGSize) -> Void

    func makeNSView(context: Context) -> StreamInputView {
        let view = StreamInputView(frame: .zero)
        view.client = client
        view.sendsShortcuts = sendsShortcuts
        view.onSizeChange = onSizeChange
        return view
    }

    func updateNSView(_ view: StreamInputView, context: Context) {
        view.client = client
        view.sendsShortcuts = sendsShortcuts
        view.onSizeChange = onSizeChange
    }
}
