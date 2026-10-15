import AppKit

/// The focused window's own controls, in a pill just above its top edge: close, minimize and zoom
/// (this Mac's window, not the other Mac's), the app's icon and the window's title. Dragging the
/// pill moves the window. Inside the window the other Mac's title bar is the other Mac's (a drag in
/// its strip moves this window too: StreamInputView), and its buttons, with that Mac's own
/// green-button menu, are that Mac's. A child window of the focused one, so it moves with it; shown
/// only while that window is key and the app is in front; over the window's top-left corner when
/// there is no room above it. At its end, where the other Mac has hidden displays, a refresh button:
/// the other Mac starts their captures again, for a picture that came out black or wrong (`onRefresh`).
/// Main thread.
final class WindowPill: NSPanel {
    private weak var parentStream: StreamWindow?
    private let label = NSTextField(labelWithString: "")
    private let icon = NSImageView()
    private let refresh = NSButton()
    private static let height: CGFloat = 26
    /// The refresh button pressed.
    var onRefresh: (() -> Void)?
    /// What the refresh button takes at the pill's end, when it shows.
    private var tail: CGFloat { refresh.isHidden ? 14 : 34 }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 200, height: Self.height),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        becomesKeyOnlyIfNeeded = true
        isReleasedWhenClosed = false
        let effect = PillBackground(frame: NSRect(x: 0, y: 0, width: 200, height: Self.height))
        effect.material = .hudWindow
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = Self.height / 2
        effect.layer?.masksToBounds = true
        effect.onDrag = { [weak self] event in self?.parentStream?.performDrag(with: event) }
        effect.onDoubleClick = { [weak self] in self?.parentStream?.zoom(nil) }
        contentView = effect

        let buttons = [TrafficLight(kind: .close), TrafficLight(kind: .minimize), TrafficLight(kind: .zoom)]
        for (i, b) in buttons.enumerated() {
            b.frame = NSRect(x: 10 + CGFloat(i) * 20, y: (Self.height - 12) / 2, width: 12, height: 12)
            b.onPress = { [weak self] kind in self?.press(kind) }
            effect.addSubview(b)
        }
        icon.frame = NSRect(x: 72, y: (Self.height - 16) / 2, width: 16, height: 16)
        effect.addSubview(icon)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: 94, y: (Self.height - 16) / 2, width: 100, height: 16)
        effect.addSubview(label)
        refresh.isBordered = false
        refresh.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh Picture")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold))
        refresh.contentTintColor = .secondaryLabelColor
        refresh.toolTip = "Refresh the picture: the other Mac makes Sill's hidden displays again (for a picture that stays black or wrong)."
        refresh.setAccessibilityLabel("Refresh Picture")
        refresh.target = self
        refresh.action = #selector(refreshPressed)
        refresh.isHidden = true
        effect.addSubview(refresh)
    }

    @objc private func refreshPressed() { onRefresh?() }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Shows the pill over `window`, or hides it (nil). `refresh`: the refresh button shows.
    func show(over window: StreamWindow?, title: String, image: NSImage?, refresh canRefresh: Bool = false) {
        #if DEBUG
        FileHandle.standardError.write(Data("pill: \(window.map { "over \($0.title) \($0.frame)" } ?? "hidden")\n".utf8))
        #endif
        if let old = parentStream, old !== window { old.removeChildWindow(self) }
        guard let window, !window.isMiniaturized else {
            parentStream = nil
            orderOut(nil)
            return
        }
        parentStream = window
        label.stringValue = title
        icon.image = image
        refresh.isHidden = !canRefresh
        place()
        if parent !== window { window.addChildWindow(self, ordered: .above) }
        orderFront(nil)
    }

    /// Above the window's top-left corner, as wide as its title needs (at most the window's width).
    func place() {
        guard let window = parentStream else { return }
        let titleWidth = min(ceil(label.intrinsicContentSize.width), 360)
        let width = min(94 + titleWidth + tail, max(window.frame.width, 120))
        label.frame.size.width = width - 94 - tail
        refresh.frame = NSRect(x: width - 28, y: (Self.height - 20) / 2, width: 20, height: 20)
        let screenTop = (window.screen ?? NSScreen.main)?.visibleFrame.maxY ?? .greatestFiniteMagnitude
        var origin = NSPoint(x: window.frame.minX + 6, y: window.frame.maxY + 4)
        // No room above (full screen, or a window at the top): inside its top-left corner, where the
        // other Mac's traffic lights are, so its green light always takes the window out of full screen.
        if window.styleMask.contains(.fullScreen) || origin.y + Self.height > screenTop { origin.y = window.frame.maxY - Self.height - 4 }
        setFrame(NSRect(origin: origin, size: NSSize(width: width, height: Self.height)), display: true)
    }

    private func press(_ kind: TrafficLight.Kind) {
        guard let window = parentStream else { return }
        switch kind {
        case .close: window.performClose(nil)
        case .minimize: window.miniaturize(nil)
        case .zoom: window.toggleFullScreen(nil)
        }
    }
}

/// The pill's background: a drag on it moves the window it belongs to; a double click zooms it.
private final class PillBackground: NSVisualEffectView {
    var onDrag: ((NSEvent) -> Void)?
    var onDoubleClick: (() -> Void)?
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onDoubleClick?() } else { onDrag?(event) }
    }
    override var mouseDownCanMoveWindow: Bool { false }
}

/// A traffic light: a coloured circle, its symbol shown while the pointer is over it.
final class TrafficLight: NSView {
    enum Kind { case close, minimize, zoom }
    let kind: Kind
    var onPress: ((Kind) -> Void)?
    private var hovering = false { didSet { needsDisplay = true } }

    init(kind: Kind) {
        self.kind = kind
        super.init(frame: .zero)
        setAccessibilityRole(.button)
        setAccessibilityLabel(kind == .close ? "Close" : kind == .minimize ? "Minimize" : "Full Screen")
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds.insetBy(dx: -4, dy: -6), options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress?(kind) }
    }
    override func accessibilityPerformPress() -> Bool { onPress?(kind); return true }

    override func draw(_ dirtyRect: NSRect) {
        let color: NSColor = kind == .close ? .systemRed : kind == .minimize ? .systemYellow : .systemGreen
        color.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5)).fill()
        guard hovering else { return }
        let symbol = kind == .close ? "xmark" : kind == .minimize ? "minus" : "arrow.up.left.and.arrow.down.right"
        let config = NSImage.SymbolConfiguration(pointSize: 6.5, weight: .bold)
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
        let tinted = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            NSColor.black.withAlphaComponent(0.6).set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: NSRect(x: (bounds.width - image.size.width) / 2, y: (bounds.height - image.size.height) / 2,
                               width: image.size.width, height: image.size.height))
    }
}
