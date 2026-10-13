import AppKit

/// The focused window's own controls, in a pill just above its top edge: close, minimize and zoom
/// (this Mac's window, not the other Mac's), the app's icon and the window's title. Dragging the
/// pill moves the window. Inside the window the other Mac's title bar is the other Mac's (a drag in
/// its strip moves this window too: StreamInputView), and its buttons, with that Mac's own
/// green-button menu, are that Mac's. A child window of the focused one, so it moves with it; shown
/// only while that window is key and the app is in front; over the window's top-left corner when
/// there is no room above it. After the lights, a bolt, where the other Mac streams windows in the
/// background at full speed: lit, this window keeps the main stream's rate when another is in front
/// (StreamWindows.fullSpeed). Main thread.
final class WindowPill: NSPanel {
    private weak var parentStream: StreamWindow?
    private let label = NSTextField(labelWithString: "")
    private let icon = NSImageView()
    private let bolt = BoltButton()
    private static let height: CGFloat = 26
    /// The bolt pressed: full speed on or off for the window under the pill.
    var onFullSpeed: ((StreamWindow) -> Void)?
    /// Where the icon starts: after the lights, and after the bolt when it shows.
    private var lead: CGFloat { bolt.isHidden ? 72 : 92 }
    private var windowTitle = ""
    private var noteUntil: Date?

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
        bolt.frame = NSRect(x: 66, y: (Self.height - 18) / 2, width: 18, height: 18)
        bolt.onPress = { [weak self] in
            guard let self, let window = self.parentStream else { return }
            self.onFullSpeed?(window)
        }
        bolt.isHidden = true
        effect.addSubview(bolt)
        icon.frame = NSRect(x: 72, y: (Self.height - 16) / 2, width: 16, height: 16)
        effect.addSubview(icon)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.frame = NSRect(x: 94, y: (Self.height - 16) / 2, width: 100, height: 16)
        effect.addSubview(label)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Shows the pill over `window`, or hides it (nil). `fullSpeed`: the bolt, lit or not; nil, none
    /// (a host that streams every background window at one rate).
    func show(over window: StreamWindow?, title: String, image: NSImage?, fullSpeed: Bool? = nil) {
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
        windowTitle = title
        if noteUntil.map({ $0 < Date() }) ?? true { noteUntil = nil; label.stringValue = title }
        icon.image = image
        bolt.isHidden = fullSpeed == nil
        bolt.on = fullSpeed == true
        icon.frame.origin.x = lead
        label.frame.origin.x = lead + 22
        place()
        if parent !== window { window.addChildWindow(self, ordered: .above) }
        orderFront(nil)
    }

    /// Above the window's top-left corner, as wide as its title needs (at most the window's width).
    func place() {
        guard let window = parentStream else { return }
        let titleWidth = min(ceil(label.intrinsicContentSize.width), 360)
        let width = min(lead + 22 + titleWidth + 14, max(window.frame.width, 120))
        label.frame.size.width = width - lead - 22 - 14
        let screenTop = (window.screen ?? NSScreen.main)?.visibleFrame.maxY ?? .greatestFiniteMagnitude
        var origin = NSPoint(x: window.frame.minX + 6, y: window.frame.maxY + 4)
        // No room above (full screen, or a window at the top): inside its top-left corner, where the
        // other Mac's traffic lights are, so its green light always takes the window out of full screen.
        if window.styleMask.contains(.fullScreen) || origin.y + Self.height > screenTop { origin.y = window.frame.maxY - Self.height - 4 }
        setFrame(NSRect(origin: origin, size: NSSize(width: width, height: Self.height)), display: true)
    }

    /// A word in the title's place for a few seconds (a window the bolt's limit sent back to 15 fps).
    func note(_ text: String) {
        noteUntil = Date().addingTimeInterval(3)
        label.stringValue = text
        place()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.05) { [weak self] in
            guard let self, let until = self.noteUntil, until <= Date() else { return }
            self.noteUntil = nil
            self.label.stringValue = self.windowTitle
            self.place()
        }
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
        setAccessibilityElement(true)
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

/// The pill's bolt: full speed in the background, lit (the accent colour) or not (grey).
final class BoltButton: NSView {
    var on = false {
        didSet {
            needsDisplay = true
            setAccessibilityValue(on ? "On" : "Off")
            toolTip = on ? "Full speed in the background: this window keeps its full frame rate when another is in front. Click to turn off."
                         : "Full speed in the background: click to keep this window at its full frame rate when another is in front (two at most)."
        }
    }
    var onPress: (() -> Void)?
    private var hovering = false { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.checkBox)
        setAccessibilityLabel("Full Speed in the Background")
        on = false
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onPress?() }
    }
    override func accessibilityPerformPress() -> Bool { onPress?(); return true }

    override func draw(_ dirtyRect: NSRect) {
        let config = NSImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        guard let image = NSImage(systemSymbolName: "bolt.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
        let color: NSColor = on ? .controlAccentColor : (hovering ? .secondaryLabelColor : .tertiaryLabelColor)
        let tinted = NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: NSRect(x: (bounds.width - image.size.width) / 2, y: (bounds.height - image.size.height) / 2,
                               width: image.size.width, height: image.size.height))
    }
}
