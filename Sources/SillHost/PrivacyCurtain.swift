import AppKit
import CoreGraphics
import Darwin

// Privacy mode, part 2 (docs/privacy-mode-plan.md; DarkenPolicy, PrivacyScreen): what Sill.app itself does to this Mac
// while its screen is dark. Its black windows (WindowCurtain), its watch on this Mac's own keys, clicks and pointer
// (MonitorInput) and its watch on the displays (DisplayChanges). Only PrivacyScreen makes them, and only with `real`
// (DarkenPolicy.darkensForReal: Sill.app's own executable, never with --synthetic): the CLI, the bare SillMenuBar binary
// and every test host never make one, and their dry run says what it would do. Made as the probe G0 measured on Noah's
// Mac on 2026-11-23 (docs/steps/2026-11-18-privacy-darken.md): #184's recipe at DarkenPolicy.windowLevel, opaque.

/// The black windows (DarkenPolicy rules 4 and 13): one per screen to cover, borderless, black, opaque, no shadow,
/// ignoring the mouse (clicks reach what is under them, where the observer sees them), on every Space and beside
/// full-screen windows, stationary (Mission Control and Show Desktop leave them in place), out of the window cycle and
/// the Window menu, never hidden with Sill (Hide Others in another app leaves them up), ordered in without activating
/// Sill and without animation. At DarkenPolicy.windowLevel: above everything G0 saw stay hidden and every named level
/// under the lock screen, under the lock screen itself, so a lock shows over them. Every capture of Sill already leaves
/// Sill's own windows out, so no device ever sees them. They go with the process when Sill ends (G0: 14 and 16 ms).
@MainActor
final class WindowCurtain: Curtain {
    private var windows: [UInt32: NSWindow] = [:]
    private var raised = false
    /// The hint's wording and when it fades: a window made meanwhile (a screen plugged in) shows it too.
    private var hint: DarkenPolicy.Hint = .lock
    private var hintUntil: Date?
    private var fading: Task<Void, Never>?

    func raise(_ screens: [UInt32]) {
        raised = true
        resync(screens)
    }

    func lift() {
        raised = false
        fading?.cancel()
        fading = nil
        hintUntil = nil
        for window in windows.values { window.orderOut(nil) }
        windows = [:]
    }

    func hint(_ hint: DarkenPolicy.Hint, for seconds: Double) {
        guard raised else { return }
        self.hint = hint
        hintUntil = Date().addingTimeInterval(seconds)
        for window in windows.values { (window.contentView as? CurtainView)?.showHint(hint) }
        fading?.cancel()
        fading = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled else { return }
            self.hintUntil = nil
            for window in self.windows.values { (window.contentView as? CurtainView)?.fadeHint() }
        }
    }

    /// Rule 13: a new screen's window in first, then every window on its screen's frame now, then the windows of
    /// screens that have gone, so no screen that can be covered is left uncovered while the displays change.
    func resync(_ screens: [UInt32]) {
        guard raised else { return }
        for id in screens where windows[id] == nil {
            let window = Self.makeWindow(on: id)
            if let until = hintUntil, until > Date() { (window.contentView as? CurtainView)?.showHint(hint) }
            window.orderFrontRegardless()
            windows[id] = window
        }
        for id in screens {
            guard let window = windows[id] else { continue }
            let frame = Self.frame(of: id)
            if window.frame != frame { window.setFrame(frame, display: true) }
        }
        for (id, window) in windows where !screens.contains(id) {
            window.orderOut(nil)
            windows[id] = nil
        }
    }

    private static func makeWindow(on display: UInt32) -> NSWindow {
        let frame = frame(of: display)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .black
        window.isOpaque = DarkenPolicy.windowOpaque
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: DarkenPolicy.windowLevel)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        window.canHide = false
        window.animationBehavior = .none
        window.isExcludedFromWindowsMenu = true
        window.tabbingMode = .disallowed
        window.contentView = CurtainView(frame: NSRect(origin: .zero, size: frame.size))
        window.setFrame(frame, display: false)
        return window
    }

    /// A display's frame in AppKit's coordinates (origin at the main display's bottom left, y up) from CoreGraphics'
    /// bounds (origin at its top left, y down), which are current as soon as the reconfiguration callback runs, before
    /// AppKit's list of screens follows.
    static func frame(of display: UInt32) -> NSRect {
        let bounds = CGDisplayBounds(display)
        let main = CGDisplayBounds(CGMainDisplayID())
        return NSRect(x: bounds.minX, y: main.height - bounds.maxY, width: bounds.width, height: bounds.height)
    }
}

/// What each black window shows: black, and while the hint shows its two lines in the middle (15 pt, 35 % white,
/// DarkenPolicy.Words.hintFirst and `hintSecond`), faded out after DarkenPolicy.hintFor. `package`: Sill.app's previews
/// draw it offscreen (`privacy-hint-lock.png`, `privacy-hint-pass.png`), never in a window.
@MainActor
package final class CurtainView: NSView {
    private let label = NSTextField(wrappingLabelWithString: "")

    package override init(frame: NSRect) {
        super.init(frame: frame)
        label.font = .systemFont(ofSize: 15)
        label.textColor = NSColor(white: 1, alpha: 0.35)
        label.alignment = .center
        label.drawsBackground = false
        label.isBezeled = false
        label.isEditable = false
        label.isSelectable = false
        label.alphaValue = 0
        addSubview(label)
    }

    package required init?(coder: NSCoder) { nil }

    package override var isOpaque: Bool { true }

    package override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        dirtyRect.fill()
    }

    package override func layout() {
        super.layout()
        let width = max(0, min(640, bounds.width - 40))
        let height = label.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: 10_000)).height ?? 40
        label.frame = NSRect(x: (bounds.width - width) / 2, y: (bounds.height - height) / 2, width: width, height: height)
    }

    /// The hint's two lines, now.
    package func showHint(_ hint: DarkenPolicy.Hint) {
        label.stringValue = DarkenPolicy.Words.hintFirst + "\n" + DarkenPolicy.Words.hintSecond(hint)
        label.alphaValue = 1
        needsLayout = true
    }

    /// The hint fades out.
    func fadeHint() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.6
            self.label.animator().alphaValue = 0
        }
    }

    /// A view of `size` showing `hint`, laid out, for a preview drawn offscreen.
    package static func preview(size: NSSize, hint: DarkenPolicy.Hint) -> CurtainView {
        let view = CurtainView(frame: NSRect(origin: .zero, size: size))
        view.showHint(hint)
        view.layoutSubtreeIfNeeded()
        return view
    }
}

/// This Mac's own keys, clicks and pointer while it is dark (DarkenPolicy rule 7): NSEvent's global monitor (events on
/// their way to other apps; keys need Accessibility, AXIsProcessTrusted, which Sill.app has to post a device's input)
/// and its local one (events on their way to Sill itself, returned unchanged). An event tells the rule only its kind
/// (`localKind`) and whether Sill posted it (`ownEvent`: InputInjector's tag, or this process as its source); never a
/// key code or a character, and nothing is kept, logged or sent. A monitor only observes: the key or click still
/// reaches its app. A secure text field (a password) and Secure Keyboard Entry withhold keys from it, never a click.
@MainActor
final class MonitorInput: LocalInput {
    private var global: Any?
    private var local: Any?

    func start(_ handler: @escaping @MainActor (DarkenPolicy.Local, Bool) -> Void) {
        stop()
        let mask = NSEvent.EventTypeMask(rawValue: DarkenPolicy.watchedEventTypes.reduce(UInt64(0)) { $0 | (UInt64(1) << UInt64($1)) })
        let pid = Int64(getpid())
        let take: (NSEvent) -> Void = { event in
            guard let kind = DarkenPolicy.localKind(eventType: Int(event.type.rawValue)) else { return }
            let cg = event.cgEvent
            let own = DarkenPolicy.ownEvent(userData: cg?.getIntegerValueField(.eventSourceUserData) ?? 0,
                                            sourcePID: cg?.getIntegerValueField(.eventSourceUnixProcessID) ?? 0, ownPID: pid)
            Task { @MainActor in handler(kind, own) }
        }
        global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: take)
        local = NSEvent.addLocalMonitorForEvents(matching: mask) { event in
            take(event)
            return event
        }
    }

    func stop() {
        if let global { NSEvent.removeMonitor(global) }
        if let local { NSEvent.removeMonitor(local) }
        global = nil
        local = nil
    }
}

/// Sill.app's watch on this Mac's displays while darkening is on (rule 13): the display reconfiguration callback, as
/// early as macOS tells (a display plugged in, removed, re-numbered at a wake or resized), and AppKit's screen parameters
/// notification, each hopping to the main actor to call `onChange` (PrivacyScreen.displaysChanged). The callback is
/// registered once for the process and calls the watch that is on (`current`); with none on it does nothing.
@MainActor
final class DisplayChanges {
    var onChange: (@MainActor () -> Void)?
    private var observer: NSObjectProtocol?
    private static weak var current: DisplayChanges?
    private static var registered = false

    func watch(_ on: Bool) {
        guard on else {
            if Self.current === self { Self.current = nil }
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            return
        }
        Self.current = self
        if !Self.registered {
            Self.registered = true
            _ = CGDisplayRegisterReconfigurationCallback({ _, flags, _ in
                guard !flags.contains(.beginConfigurationFlag) else { return }
                Task { @MainActor in DisplayChanges.current?.changed() }
            }, nil)
        }
        if observer == nil {
            observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                              object: nil, queue: .main) { _ in
                Task { @MainActor in DisplayChanges.current?.changed() }
            }
        }
    }

    private func changed() { onChange?() }
}
