import AppKit
import CoreGraphics
import Darwin

// Privacy mode, part 2 (docs/privacy-mode-plan.md; DarkenPolicy, PrivacyScreen): what Sill.app itself does to this Mac
// while its screen is dark. Its black windows (WindowCurtain), the pointer hidden over them (PointerHider, through
// PointerCalls' two private calls), its watch on this Mac's own keys, clicks and pointer (MonitorInput) and its watch on
// the displays (DisplayChanges). Only PrivacyScreen makes them, and only with `real` (DarkenPolicy.darkensForReal: Sill.app's
// own executable, never with --synthetic): the CLI, the bare SillMenuBar binary and every test host never make one, and
// their dry run says what it would do. Made as the probe G0 measured on Noah's Mac on 2026-11-23
// (docs/steps/2026-11-18-privacy-darken.md): #184's recipe at DarkenPolicy.windowLevel, opaque.

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
    /// Rule 15: the pointer over the black.
    private let hider = PointerHider()
    /// While raised: the Mac's wake, at which the pointer's hide is made again (PointerHider.reassert).
    private var wakeObservers: [NSObjectProtocol] = []

    func raise(_ screens: [UInt32]) {
        raised = true
        resync(screens)
        if wakeObservers.isEmpty {
            let center = NSWorkspace.shared.notificationCenter
            wakeObservers = [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification].map { name in
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.hider.reassert() }
                }
            }
        }
    }

    func lift() {
        raised = false
        // The rule shows the pointer before every lift; this is the floor under it: never a pointer left hidden.
        hider.show()
        for observer in wakeObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        wakeObservers = []
        fading?.cancel()
        fading = nil
        hintUntil = nil
        for window in windows.values { window.orderOut(nil) }
        windows = [:]
    }

    func pointer(hidden: Bool) {
        if hidden, raised { hider.hide() } else { hider.show() }
    }

    func renewPointer(_ cause: DarkenPolicy.PointerCause) {
        if raised { hider.renew(cause) }
    }

    func pointerShowing() -> Bool? { hider.showing() }

    var pointerHeld: Bool { hider.hidden }

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
            let rect = Self.frame(of: id)
            if window.frame != rect { window.setFrame(rect, display: true) }
        }
        for (id, window) in windows where !screens.contains(id) {
            window.orderOut(nil)
            windows[id] = nil
        }
    }

    private static func makeWindow(on display: UInt32) -> NSWindow {
        let rect = Self.frame(of: display)
        let window = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
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
        window.contentView = CurtainView(frame: NSRect(origin: .zero, size: rect.size))
        window.setFrame(rect, display: false)
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
/// draw it offscreen (`privacy-hint-lock.png`, `privacy-hint-pass.png`, `privacy-hint-left.png`), never in a window.
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
        label.stringValue = DarkenPolicy.Words.hintFirst(hint) + "\n" + DarkenPolicy.Words.hintSecond(hint)
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

/// This Mac's pointer while its screens are black (DarkenPolicy rule 15; Noah, 2026-11-24: "The cursor is still shown
/// when darkened", the plan's open decision 14 decided). macOS has one pointer: CoreGraphics' public CGDisplayHideCursor
/// and CGDisplayShowCursor hide and show it on every screen at once (their header: "The `display' parameter is ignored")
/// and count the hides, but act only for the app in front unless the app's own connection to the window server says it
/// may set the pointer from the background: the connection property "SetsCursorInBackground", set with the private
/// CGSSetConnectionProperty on Sill's own connection (PointerCalls). macOS 27.2's own ViewBridge sets it the same way.
/// Sill.app is in the background while a device uses the Mac, and must stay there (activating it would take the keys from
/// the app the device uses), and its black windows ignore the mouse, so no cursor of theirs could do it: nothing public
/// hides the pointer of an app in the background. One hide at most is outstanding (`hidden`); the property is set just
/// before it and taken back just after its show. Shown again at the rule's `.pointer(hidden: false)` (before every lift,
/// at the lock screen, at another user's session, at a quit), at every lift whatever the rule said (WindowCurtain), and
/// by the window server when Sill's process ends (a crash, a kill, the watchdog's end): the hide is its connection's.
/// Missing calls or a refusal: the pointer stays visible, darkening goes on, and the log says so once. Sill.app's alone
/// (WindowCurtain): a test host or the bare binary never makes one, and their dry run (DryCurtain) only says what it would
/// do. Never tried on an agent's Mac: Noah's trial is the first.
///
/// Made again while hidden (`renew`, run 7; Noah, 2026-11-26: the pointer showed on the black after his iPhone stepped to
/// a Virtual Desktop and back): the rule says when (DarkenPolicy.pointerCheck: after the displays changed, a step, Sill's
/// warp, or a look that reads it as showing), and this does it: the property set again, then a show and a hide back to
/// back in the same turn, so the window server applies the hide afresh on every display (its count, which never goes
/// below zero, passes zero and is back at one: one hide still outstanding, which the lift's show ends). CoreGraphics'
/// CGDisplayHideCursor and CGDisplayShowCursor always return success on macOS 27.2.1 (SkyLight's SLDisplayHideCursor and
/// SLDisplayShowCursor end with `mov w0, #0x0`, `dyld_info -disassemble`), so a refusal never shows in them: only the
/// property's answer and the read (`showing`, CGCursorIsVisible) tell. The read is the window server's own shared state
/// (SkyLight's SLCursorIsVisible reads the CGSScoreboard, no connection, no message), the same for every app: not
/// Sill's own count; it reads hidden while the pointer is obscured by typing too.
@MainActor
final class PointerHider {
    /// Sill's own hide is outstanding (one at most).
    private(set) var hidden = false
    /// Each failure is said once a run.
    private var saidUnavailable = false
    private var saidRefused = false
    private var saidNoLook = false

    /// Hides the pointer now, once: the property first, then the hide; a hide that fails takes the property back.
    func hide() {
        guard !hidden else { return }
        guard let calls = PointerCalls.found else {
            if !saidUnavailable { saidUnavailable = true; print(DarkenPolicy.Words.pointerUnavailable) }
            return
        }
        let connection = calls.main()
        let property = PointerCalls.property as CFString
        let set = calls.set(connection, connection, property, kCFBooleanTrue)
        guard set == 0 else { refused(set); return }
        let hid = CGDisplayHideCursor(CGMainDisplayID())
        guard hid == .success else {
            _ = calls.set(connection, connection, property, kCFBooleanFalse)
            refused(hid.rawValue)
            return
        }
        hidden = true
        Stats.shared.bump("priv.pointerHide")
        print(DarkenPolicy.Words.pointerHidden)
        if PointerCalls.isVisible == nil, !saidNoLook { saidNoLook = true; print(DarkenPolicy.Words.pointerNoLook) }
    }

    /// Rule 15, renewed: while Sill's hide is outstanding, the property set again, then a show and a hide back to back,
    /// now. Nothing if Sill has not hidden it; nothing but the refusal's line (once a run) if macOS refuses the property,
    /// so a show never goes out that no hide can follow. Counted by its cause.
    func renew(_ cause: DarkenPolicy.PointerCause) {
        guard hidden, let calls = PointerCalls.found else { return }
        let connection = calls.main()
        let set = calls.set(connection, connection, PointerCalls.property as CFString, kCFBooleanTrue)
        guard set == 0 else { refused(set); return }
        _ = CGDisplayShowCursor(CGMainDisplayID())
        _ = CGDisplayHideCursor(CGMainDisplayID())
        Stats.shared.bump(cause.statsKey)
    }

    /// Whether the pointer reads as showing now (CGCursorIsVisible: the window server's shared state, no message); nil
    /// when this macOS has no such call.
    func showing() -> Bool? {
        PointerCalls.isVisible.map { $0() != 0 }
    }

    /// Shows it again now, if Sill hid it: the show (tried twice), then the property back. A show that fails leaves the
    /// property set, so nothing stops a later show; the hide ends with Sill's process anyway.
    func show() {
        guard hidden else { return }
        var shown = CGDisplayShowCursor(CGMainDisplayID())
        if shown != .success { shown = CGDisplayShowCursor(CGMainDisplayID()) }
        hidden = false
        Stats.shared.bump("priv.pointerShow")
        guard shown == .success else {
            print(DarkenPolicy.Words.pointerShowFailed(Int(shown.rawValue)))
            return
        }
        if let calls = PointerCalls.found {
            let connection = calls.main()
            _ = calls.set(connection, connection, PointerCalls.property as CFString, kCFBooleanFalse)
        }
        print(DarkenPolicy.Words.pointerShown)
    }

    /// At a wake while hidden: a show and a hide, so the count stays at one, in case the window server let the hide go.
    func reassert() {
        guard hidden else { return }
        _ = CGDisplayShowCursor(CGMainDisplayID())
        _ = CGDisplayHideCursor(CGMainDisplayID())
    }

    private func refused(_ code: Int32) {
        guard !saidRefused else { return }
        saidRefused = true
        print(DarkenPolicy.Words.pointerRefused(Int(code)))
    }
}

/// The two private calls PointerHider makes (rule 15), looked up by name once, in the frameworks the process already has
/// loaded (dlopen, RTLD_NOLOAD first, then dlsym), never linked: a macOS without them gives nil, the pointer stays visible
/// and darkening goes on. On macOS 27.2.1 CoreGraphics re-exports both from SkyLight (`dyld_info -exports`, run 6 of
/// PR #400: `_CGSMainConnectionID` and `_CGSSetConnectionProperty`, from `_SLSMainConnectionID` and
/// `_SLSSetConnectionProperty`); SkyLight's own names are the second place looked. With the virtual display's surface
/// (VirtualDisplay.privateAPISurface), the lock's SACLockScreenImmediate (ScreenLocker) and the shortcuts' two getters
/// (SymbolicHotKeys), these are the private calls Sill makes. A dry run (DryCurtain) only looks them up, to say whether
/// they are there.
enum PointerCalls {
    /// `CGSConnectionID CGSMainConnectionID(void)`: this process's own connection to the window server.
    typealias MainConnectionID = @convention(c) () -> Int32
    /// `CGError CGSSetConnectionProperty(CGSConnectionID, CGSConnectionID, CFStringRef key, CFTypeRef value)`, called
    /// with a CFBoolean.
    typealias SetConnectionProperty = @convention(c) (Int32, Int32, CFString, CFBoolean) -> Int32

    /// Where each is looked for, in order, and its names there.
    static let places: [(image: String, main: String, set: String)] = [
        ("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", "CGSMainConnectionID", "CGSSetConnectionProperty"),
        ("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", "SLSMainConnectionID", "SLSSetConnectionProperty"),
    ]
    /// The property that lets an app in the background set the pointer, hidden included (ViewBridge's
    /// "CGSSetConnectionProperty (SetsCursorInBackground)" in macOS 27.2's dyld shared cache).
    static let property = "SetsCursorInBackground"

    static let found: (main: MainConnectionID, set: SetConnectionProperty)? = {
        for place in places {
            guard let handle = dlopen(place.image, RTLD_LAZY | RTLD_NOLOAD) ?? dlopen(place.image, RTLD_LAZY),
                  let main = dlsym(handle, place.main), let set = dlsym(handle, place.set) else { continue }
            return (unsafeBitCast(main, to: MainConnectionID.self), unsafeBitCast(set, to: SetConnectionProperty.self))
        }
        return nil
    }()

    /// `boolean_t CGCursorIsVisible(void)`: public, deprecated since macOS 10.9 ("No longer supported") and still there
    /// in 27.2.1 (CoreGraphics re-exports SkyLight's SLCursorIsVisible), looked up by name rather than called by name, so
    /// the build has no deprecation warning and a macOS without it gives nil (no look). Read only: it never hides or
    /// shows anything.
    typealias CursorIsVisible = @convention(c) () -> Int32

    /// Where it is looked for, in order, and its name there.
    static let readPlaces: [(image: String, name: String)] = [
        ("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", "CGCursorIsVisible"),
        ("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", "SLCursorIsVisible"),
    ]

    static let isVisible: CursorIsVisible? = {
        for place in readPlaces {
            guard let handle = dlopen(place.image, RTLD_LAZY | RTLD_NOLOAD) ?? dlopen(place.image, RTLD_LAZY),
                  let read = dlsym(handle, place.name) else { continue }
            return unsafeBitCast(read, to: CursorIsVisible.self)
        }
        return nil
    }()
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
