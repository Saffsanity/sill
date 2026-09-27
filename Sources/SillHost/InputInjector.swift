import Foundation
import QuartzCore
import CoreGraphics
import ApplicationServices
import Darwin
import StreamProtocol

/// Turns client input into CGEvents aimed at the streamed source.
///
/// The client sends positions as fractions of the video frame (0…1); everything here maps them
/// onto `rect`, the source's current screen rectangle in CG global coordinates (points, top-left
/// origin — the same space CGEvent uses), so the phone never learns anything about Mac geometry
/// and a window that moves or resizes just changes `rect`.
///
/// Threading: main actor. Input arrives on the network queue and hops here through the
/// coordinator, and posting CGEvents from the main thread is fine.
@MainActor
final class InputInjector {
    /// Two downs of the same button within this time and distance are a double (then triple) click.
    private static let multiClickInterval: CFTimeInterval = 0.35
    private static let multiClickSlop: CGFloat = 12

    private struct ButtonState {
        var isDown = false
        var clicks: Int64 = 1
        var lastDownAt: CFAbsoluteTime = -1_000
        var lastDownPoint: CGPoint = .zero
    }

    /// `.hidSystemState` merges with the real HID state, so a modifier physically held on the Mac
    /// still applies to an injected click. Keyboard events below set their flags explicitly anyway.
    private let source = CGEventSource(stateID: .hidSystemState)
    private var lastMoveArrival: CFTimeInterval = 0   // jitter probe, see apply()
    private var left = ButtonState()
    private var right = ButtonState()

    // MARK: Entry point

    func apply(_ event: InputEvent, in rect: CGRect) {
        remindAboutAccessibilityIfNeeded()
        switch event {
        case .pointer(let action, let x, let y):
            // Jitter probe: how evenly do pointer moves arrive? A Pencil or trackpad drag should
            // land every 8–16 ms; buckets above that are the stutter the device user feels.
            if action == .move {
                let now = CACurrentMediaTime()
                let gap = now - lastMoveArrival
                lastMoveArrival = now
                if gap < 1.0 {
                    if gap > 0.100 { Stats.shared.bump("in.gap>100ms") }
                    else if gap > 0.050 { Stats.shared.bump("in.gap>50ms") }
                    else if gap > 0.025 { Stats.shared.bump("in.gap>25ms") }
                }
            }
            pointer(action, at: point(x, y, in: rect))
        case .scroll(let x, let y, let dx, let dy):
            scroll(at: point(x, y, in: rect), dx: dx * rect.width, dy: dy * rect.height)
        case .text(let string):
            type(string)
        case .scrollGesture(let phase, let x, let y):
            scrollGesture(phase, at: point(x, y, in: rect))
        case .key(let hidUsage, let down, let modifiers):
            key(hidUsage: hidUsage, down: down, modifiers: modifiers)
        }
    }

    private func point(_ x: Double, _ y: Double, in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + CGFloat(x) * rect.width, y: rect.minY + CGFloat(y) * rect.height)
    }

    // MARK: Pointer

    private func pointer(_ action: PointerAction, at location: CGPoint) {
        let type: CGEventType
        let button: CGMouseButton
        var clicks: Int64 = 1

        switch action {
        case .move:
            // A move with a button held is a drag; sending .mouseMoved instead would break
            // text selection and window dragging.
            if left.isDown { type = .leftMouseDragged; button = .left; clicks = left.clicks }
            else if right.isDown { type = .rightMouseDragged; button = .right; clicks = right.clicks }
            else { type = .mouseMoved; button = .left }
        case .leftDown:
            beginClick(&left, at: location)
            type = .leftMouseDown; button = .left; clicks = left.clicks
        case .leftUp:
            left.isDown = false
            type = .leftMouseUp; button = .left; clicks = left.clicks   // the up carries the down's count
        case .rightDown:
            beginClick(&right, at: location)
            type = .rightMouseDown; button = .right; clicks = right.clicks
        case .rightUp:
            right.isDown = false
            type = .rightMouseUp; button = .right; clicks = right.clicks
        }

        guard let event = CGEvent(mouseEventSource: source, mouseType: type,
                                  mouseCursorPosition: location, mouseButton: button) else { return }
        if type != .mouseMoved { event.setIntegerValueField(.mouseEventClickState, value: clicks) }
        // One synthetic "finger": a constant event number keeps a down/drag/up sequence coherent.
        event.setIntegerValueField(.mouseEventNumber, value: 0)
        event.post(tap: .cghidEventTap)
        Stats.shared.bump("in.pointer")
    }

    private func beginClick(_ state: inout ButtonState, at location: CGPoint) {
        let now = CFAbsoluteTimeGetCurrent()
        let moved = hypot(location.x - state.lastDownPoint.x, location.y - state.lastDownPoint.y)
        if now - state.lastDownAt <= Self.multiClickInterval && moved <= Self.multiClickSlop {
            state.clicks += 1            // 2 = double-click, 3 = triple, and on up from there
        } else {
            state.clicks = 1
        }
        state.isDown = true
        state.lastDownAt = now
        state.lastDownPoint = location
    }

    // MARK: Scroll

    /// `dx`/`dy` are already in points of the source rectangle, with the protocol's natural sign:
    /// positive dy means the content should move down the screen.
    ///
    /// That matches kCGScrollWheelEventDeltaAxis1 as-is: a positive axis-1 delta is "scroll up",
    /// i.e. the viewport moves toward the top of the document and the content slides down — the
    /// same result as a natural-scrolling trackpad swipe downwards. Axis 2 works the same way
    /// (positive scrolls left, so the content slides right), so neither value is negated. The
    /// system's natural-scrolling preference flips the hardware driver's deltas, not ours, so a
    /// synthetic event means the same thing whichever way the Mac is set.
    ///
    /// Inside a gesture the delta is stamped with the phase the Mac expects from a trackpad (see
    /// `ScrollState`); outside one it goes out exactly as before, a bare pixel wheel event.
    private func scroll(at location: CGPoint, dx: Double, dy: Double) {
        // The wheel fields are whole points. Carry the rounding remainder into the next event, or
        // a slow drag (and the end of every momentum tail) made of sub-point steps scrolls nothing.
        // Int(Double) traps on NaN, infinity and anything past Int's range, so a malformed delta
        // from the wire is dropped and a huge one clamped before converting.
        guard dx.isFinite, dy.isFinite else { return }
        let limit = Double(Int32.max)
        let exact = CGPoint(x: dx + scrollRemainder.x, y: dy + scrollRemainder.y)
        let wheel1 = min(max(exact.y.rounded(), -limit), limit)
        let wheel2 = min(max(exact.x.rounded(), -limit), limit)
        scrollRemainder = CGPoint(x: exact.x - wheel2, y: exact.y - wheel1)
        if abs(scrollRemainder.x) >= 1 || abs(scrollRemainder.y) >= 1 { scrollRemainder = .zero }  // after a clamp
        let w1 = Int32(wheel1), w2 = Int32(wheel2)

        switch scrollState {
        case .idle:
            postScroll(at: location, wheel1: w1, wheel2: w2, phase: nil, momentum: nil)
        case .gesture(let begun):
            postScroll(at: location, wheel1: w1, wheel2: w2,
                       phase: begun ? .changed : .began, momentum: nil)
            scrollState = .gesture(begun: true)
        case .momentum(let begun):
            postScroll(at: location, wheel1: w1, wheel2: w2,
                       phase: nil, momentum: begun ? .continuous : .begin)
            scrollState = .momentum(begun: true)
        }
        lastScrollLocation = location
        rearmScrollWatchdog()
        Stats.shared.bump("in.scroll")
    }

    /// Where the scroll gesture in progress is. One at a time: the client has one scroll surface
    /// in use, and its gestures never overlap (it ends momentum before beginning a new gesture).
    ///
    /// A Mac trackpad scroll is not a stream of wheel ticks but a phased gesture, and AppKit keys
    /// its behaviour off the phases: it rubber-bands past an edge only while a gesture is under
    /// way, springs back on Ended unless momentum follows, and treats momentum events as the
    /// coast after lift-off. The client brackets its deltas with `.scrollGesture` messages; this
    /// turns them into the phase fields:
    ///
    ///   began          → nothing yet; the first delta goes out as kCGScrollPhaseBegan (1)
    ///   deltas         → kCGScrollPhaseChanged (2)
    ///   ended          → one zero-delta event, kCGScrollPhaseEnded (4)
    ///   momentumBegan  → nothing yet; the first delta is kCGMomentumScrollPhaseBegin (1)
    ///   deltas         → kCGMomentumScrollPhaseContinue (2), scroll phase 0
    ///   momentumEnded  → one zero-delta event, kCGMomentumScrollPhaseEnd (3)
    ///
    /// A boundary with no delta inside it (a gesture that never moved) posts nothing, so the Mac
    /// never sees an Ended without its Began.
    private enum ScrollState {
        case idle                     // bare wheel deltas: an older client, or a lone tick
        case gesture(begun: Bool)     // fingers down; begun once the Began event is out
        case momentum(begun: Bool)    // fingers up, client-generated coast
    }

    private var scrollState = ScrollState.idle
    private var scrollRemainder = CGPoint.zero
    /// Where the last scroll event went, for the closing event the watchdog posts.
    private var lastScrollLocation = CGPoint.zero
    private var scrollWatchdog: Task<Void, Never>?

    /// A gesture or coast whose closing message never comes (the client dropped off mid-scroll)
    /// would leave the Mac's content stretched past its edge indefinitely. If a gesture goes this
    /// long with no traffic it is closed here. Fingers resting mid-scroll send nothing, so the
    /// gesture limit is generous; momentum ticks at 60 Hz, so a half-second gap means it died.
    private static let gestureIdleTimeout: Double = 2
    private static let momentumIdleTimeout: Double = 0.5

    private func scrollGesture(_ phase: ScrollPhase, at location: CGPoint) {
        Stats.shared.bump("in.scrollPhase")
        switch phase {
        case .began:
            closeScroll(at: location)   // defensive: anything still open ends first
            scrollState = .gesture(begun: false)
            scrollRemainder = .zero
        case .ended:
            if case .gesture(begun: true) = scrollState {
                postScroll(at: location, wheel1: 0, wheel2: 0, phase: .ended, momentum: nil)
            }
            scrollState = .idle
        case .momentumBegan:
            closeScroll(at: location)
            scrollState = .momentum(begun: false)
        case .momentumEnded:
            if case .momentum(begun: true) = scrollState {
                postScroll(at: location, wheel1: 0, wheel2: 0, phase: nil, momentum: .end)
            }
            scrollState = .idle
        }
        lastScrollLocation = location
        rearmScrollWatchdog()
    }

    /// Posts the closing event for whatever phase is open, then goes idle.
    private func closeScroll(at location: CGPoint) {
        switch scrollState {
        case .gesture(begun: true):
            postScroll(at: location, wheel1: 0, wheel2: 0, phase: .ended, momentum: nil)
        case .momentum(begun: true):
            postScroll(at: location, wheel1: 0, wheel2: 0, phase: nil, momentum: .end)
        default:
            break
        }
        scrollState = .idle
    }

    private func rearmScrollWatchdog() {
        scrollWatchdog?.cancel()
        let timeout: Double
        switch scrollState {
        case .idle: scrollWatchdog = nil; return
        case .gesture: timeout = Self.gestureIdleTimeout
        case .momentum: timeout = Self.momentumIdleTimeout
        }
        // Main actor, inherited from this method: the state it touches is never shared.
        scrollWatchdog = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.scrollWentQuiet()
        }
    }

    /// Closes the open phase on the Mac but keeps the gesture's shape, un-begun: if the client
    /// was only resting and deltas resume, they start a fresh Began (or momentum Begin) rather
    /// than continuing a phase the Mac has already seen end.
    private func scrollWentQuiet() {
        let state = scrollState
        closeScroll(at: lastScrollLocation)
        switch state {
        case .gesture: scrollState = .gesture(begun: false)
        case .momentum: scrollState = .momentum(begun: false)
        case .idle: break
        }
        Stats.shared.bump("in.scrollTimeout")
    }

    /// One scroll-wheel CGEvent. With neither phase set it is the plain pixel wheel event this
    /// injector always sent; with either, the trackpad fields go on top.
    ///
    /// What the pixel-unit constructor already fills in (checked by reading the fields back):
    /// IsContinuous = 1, PointDeltaAxis1/2 = wheel1/2, DeltaAxis1/2 = a line count, and
    /// FixedPtDeltaAxis1/2 = the same motion in *lines* (pixels / 10, 16.16 fixed point — 7 px
    /// reads back as 0.7). So:
    ///   • IsContinuous and PointDelta are set explicitly anyway: they are what makes this a
    ///     precise trackpad scroll to AppKit (`hasPreciseScrollingDeltas`, `scrollingDeltaY`), and
    ///     the gesture must not depend on a constructor default.
    ///   • FixedPtDelta is deliberately left as the constructor made it. It backs NSEvent's legacy
    ///     line-based `deltaY`; writing the point deltas there would inflate that tenfold for
    ///     every app still reading it. (`setDoubleValueField` would do the 16.16 conversion if it
    ///     ever needs setting — CGEventField exposes all of these in Swift, nothing is missing.)
    private func postScroll(at location: CGPoint, wheel1: Int32, wheel2: Int32,
                            phase: CGScrollPhase?, momentum: CGMomentumScrollPhase?) {
        guard let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2,
                                  wheel1: wheel1, wheel2: wheel2, wheel3: 0) else { return }
        // A scroll event carries its own location; without it the scroll lands wherever the
        // cursor happens to be rather than under the client's finger. Every event, the closing
        // zero-delta ones included, so the whole gesture is routed to the same window.
        event.location = location
        if phase != nil || momentum != nil {
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(wheel1))
            event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: Int64(wheel2))
            // Exactly one of the two is non-zero: momentum events carry scroll phase 0.
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase?.rawValue ?? 0))
            event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(momentum?.rawValue ?? 0))
        }
        event.post(tap: .cghidEventTap)
    }

    // MARK: Text

    private func type(_ string: String) {
        for character in string {
            switch character {
            case "\n": tap(virtualKey: 36)          // Return
            case "\t": tap(virtualKey: 48)          // Tab
            case "\u{8}": tap(virtualKey: 51)       // Delete (backspace)
            default:
                // Virtual key 0 with a Unicode string: the character arrives whatever the Mac's
                // keyboard layout is, which is what a software keyboard on the phone means.
                let units = Array(character.utf16)
                guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                      let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { continue }
                down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
                // No modifiers, explicitly: the character carries its own case, and an event made
                // from this source after a ⌘Space (the Spotlight key) could otherwise inherit ⌘,
                // which Spotlight's field ignores (typing into Spotlight did nothing, 2026-09-23).
                down.flags = []
                up.flags = []
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
            }
            Stats.shared.bump("in.text")
        }
    }

    private func tap(virtualKey: CGKeyCode) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: down) else { continue }
            event.flags = []       // plain Return, Tab, Delete: never a leftover modifier
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: Keys

    private func key(hidUsage: UInt16, down: Bool, modifiers: UInt64) {
        guard let virtualKey = Self.virtualKeys[hidUsage] else {
            Stats.shared.bump("in.unknownKey")
            return
        }
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: down) else { return }
        event.flags = Self.flags(from: modifiers)
        event.post(tap: .cghidEventTap)
        Stats.shared.bump("in.key")
    }

    // MARK: Gestures

    /// A trackpad gesture's shortcut (kind 28, docs/trackpad-gestures-plan.md §7.3): the key down
    /// and up with exactly the flags the Mac stored for it (GestureChords), fn included, which the
    /// key path above cannot carry. Keycodes 160 and 131 are the Mission Control and Launchpad keys
    /// of Apple keyboards, which no HID usage from a device names. Accessibility, as all input.
    func chord(keyCode: UInt16, flags: UInt64) {
        remindAboutAccessibilityIfNeeded()
        // Both made before either is posted, so a key never goes down without its up.
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(keyCode), keyDown: false) else { return }
        down.flags = CGEventFlags(rawValue: flags)
        up.flags = CGEventFlags(rawValue: flags)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        Stats.shared.bump("in.gesture")
    }

    /// The client sends UIKeyModifierFlags bits. They sit at the same bit positions as the
    /// CGEventFlags masks, but build the flags explicitly rather than reinterpreting the number:
    /// anything else in there (numeric pad, iOS-only bits) has no business reaching the Mac.
    private static func flags(from modifiers: UInt64) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers & (1 << 16) != 0 { flags.insert(.maskAlphaShift) }
        if modifiers & (1 << 17) != 0 { flags.insert(.maskShift) }
        if modifiers & (1 << 18) != 0 { flags.insert(.maskControl) }
        if modifiers & (1 << 19) != 0 { flags.insert(.maskAlternate) }
        if modifiers & (1 << 20) != 0 { flags.insert(.maskCommand) }
        return flags
    }

    /// USB HID usage (UIKeyboardHIDUsage on the client) → macOS virtual keycode (Carbon kVK_*).
    /// Only the keys a phone keyboard can send; anything else is dropped and counted.
    private static let virtualKeys: [UInt16: CGKeyCode] = [
        // Letters, 0x04…0x1D = A…Z
        0x04: 0, 0x05: 11, 0x06: 8, 0x07: 2, 0x08: 14, 0x09: 3, 0x0A: 5, 0x0B: 4, 0x0C: 34,
        0x0D: 38, 0x0E: 40, 0x0F: 37, 0x10: 46, 0x11: 45, 0x12: 31, 0x13: 35, 0x14: 12,
        0x15: 15, 0x16: 1, 0x17: 17, 0x18: 32, 0x19: 9, 0x1A: 13, 0x1B: 7, 0x1C: 16, 0x1D: 6,
        // Digits, 0x1E…0x27 = 1…9 then 0
        0x1E: 18, 0x1F: 19, 0x20: 20, 0x21: 21, 0x22: 23, 0x23: 22, 0x24: 26, 0x25: 28,
        0x26: 25, 0x27: 29,
        // Editing and punctuation
        0x28: 36,   // Return
        0x29: 53,   // Escape
        0x2A: 51,   // Delete (backspace)
        0x2B: 48,   // Tab
        0x2C: 49,   // Space
        0x2D: 27,   // -
        0x2E: 24,   // =
        0x2F: 33,   // [
        0x30: 30,   // ]
        0x31: 42,   // \
        0x33: 41,   // ;
        0x34: 39,   // '
        0x35: 50,   // `
        0x36: 43,   // ,
        0x37: 47,   // .
        0x38: 44,   // /
        0x39: 57,   // Caps Lock
        // F1…F12
        0x3A: 122, 0x3B: 120, 0x3C: 99, 0x3D: 118, 0x3E: 96, 0x3F: 97,
        0x40: 98, 0x41: 100, 0x42: 101, 0x43: 109, 0x44: 103, 0x45: 111,
        // Navigation
        0x4A: 115,  // Home
        0x4B: 116,  // Page Up
        0x4C: 117,  // Forward Delete
        0x4D: 119,  // End
        0x4E: 121,  // Page Down
        0x4F: 124,  // Right
        0x50: 123,  // Left
        0x51: 125,  // Down
        0x52: 126,  // Up
        // Modifiers, in case the client sends them as keys as well as flags
        0xE0: 59,   // Left Control
        0xE1: 56,   // Left Shift
        0xE2: 58,   // Left Option
        0xE3: 55,   // Left Command
        0xE4: 62,   // Right Control
        0xE5: 60,   // Right Shift
        0xE6: 61,   // Right Option
        0xE7: 54,   // Right Command
    ]

    // MARK: Accessibility permission

    private static var lastReminder: CFAbsoluteTime = 0

    /// Without Accessibility trust the window server drops every event we post, silently: no
    /// error, no callback, just a cursor that never moves. Ask once at startup, and say plainly
    /// which app has to be ticked (the permission belongs to whatever launched this process).
    static func ensureAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) { return }
        print("""
        Input needs Accessibility permission, and it is not granted yet: CGEvents will be \
        dropped silently until it is.
        System Settings › Privacy & Security › Accessibility, then enable \(launchingAppName()) \
        (the app this host was launched from — Terminal, iTerm, or the Claude app's terminal — \
        not SillHost itself). Restart the host afterwards.
        """)
    }

    /// One line every 30 s while input is arriving and still going nowhere, so the phone tapping
    /// at a dead Mac is visible in the host's log instead of looking like a network problem.
    private func remindAboutAccessibilityIfNeeded() {
        guard !AXIsProcessTrusted() else { return }
        let now = CFAbsoluteTimeGetCurrent()
        guard now - Self.lastReminder > 30 else { return }
        Self.lastReminder = now
        print("Input is arriving but Accessibility is still off: enable \(Self.launchingAppName()) "
              + "in System Settings › Privacy & Security › Accessibility.")
    }

    /// The parent process, which is the app the permission actually attaches to. Launched by
    /// LaunchServices (Finder, `open`, a login item) the parent is launchd and the permission
    /// belongs to the app bundle itself: name it ("Sill") rather than "launchd".
    private static func launchingAppName() -> String {
        if getppid() == 1, let name = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
            return "\"\(name)\""
        }
        let fallback = "the app that launched this host"
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, ProcessInfo.processInfo.processIdentifier]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return fallback }
        let parent = info.kp_eproc.e_ppid
        var buffer = [CChar](repeating: 0, count: 1024)
        guard proc_name(parent, &buffer, UInt32(buffer.count)) > 0 else { return fallback }
        let name = String(cString: buffer)
        return name.isEmpty ? fallback : "\"\(name)\""
    }
}
