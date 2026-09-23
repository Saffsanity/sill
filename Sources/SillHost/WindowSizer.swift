import Foundation
import StreamProtocol
import AppKit
import ApplicationServices
import ScreenCaptureKit

/// Milestone 3's fallback scaling: instead of a virtual display per device, resize the real window
/// through Accessibility so it fits the client's panel at the text scale the client asked for.
///
/// Main actor, like the coordinator that calls it. The AX calls are synchronous IPC into the target
/// app, so each app element *and* the matched window element get a short messaging timeout (a
/// timeout set on one element covers that element only, per AXUIElement.h): a hung app costs a
/// second per call, not the host.
@MainActor
final class WindowSizer {
    /// AX refuses everything while the host is untrusted; say so once, not on every viewport.
    private var warnedUntrusted = false

    /// How far apart (in points) the SCWindow's frame and an AX window's frame may be and still be
    /// the same window. Covers rounding between the two APIs, not a window that moved.
    private static let frameTolerance: CGFloat = 4

    /// Resizes `window` to `size` in Mac points (top-left anchored), nudging it back onto its
    /// display if the new size would hang off the edge. Returns the size the app actually took —
    /// apps enforce minimums and some snap to a grid — or nil if Accessibility is off, the window
    /// cannot be found through AX, or the app refused.
    func resize(window: SCWindow, to size: CGSize) -> CGSize? {
        guard AXIsProcessTrusted() else {
            if !warnedUntrusted {
                warnedUntrusted = true
                print("Window sizing needs Accessibility permission (the same one input needs); leaving windows at their size.")
            }
            return nil
        }
        guard let pid = window.owningApplication?.processID else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        guard let ax = Self.axWindow(matching: window, in: app) else {
            print("Window sizing: no Accessibility window matches \"\(window.title ?? "")\"; not resizing.")
            return nil
        }
        AXUIElementSetMessagingTimeout(ax, 1.0)

        // Move first if the target frame would leave the display, so an app that clamps its frame
        // to the screen does not shrink the window instead of letting it move.
        let area = Self.visibleArea(around: Self.frame(of: ax) ?? window.frame)
        if let origin = Self.position(of: ax), let area {
            let fitted = Self.keep(CGRect(origin: origin, size: size), in: area)
            if fitted != origin { _ = Self.set(ax, position: fitted) }   // a window that will not move may still resize
        }

        var wanted = size
        guard let value = AXValueCreate(.cgSize, &wanted) else { return nil }
        let err = AXUIElementSetAttributeValue(ax, kAXSizeAttribute as CFString, value)
        guard err == .success else {
            print("Window sizing: AX refused the size (error \(err.rawValue)).")
            return nil
        }
        guard let actual = Self.size(of: ax) else { return nil }

        // The app may have taken a different size than asked (a minimum, usually larger): check
        // again with what it actually is.
        if let origin = Self.position(of: ax), let area {
            let fitted = Self.keep(CGRect(origin: origin, size: actual), in: area)
            if fitted != origin { _ = Self.set(ax, position: fitted) }
        }
        return actual
    }

    // MARK: Placing a window on the virtual display (--virtual-display)

    /// A window the host has taken hold of through Accessibility, with where it came from. The
    /// element is resolved once, at placement time: matching by title/frame again after the move
    /// would fail (the frame changed) and the element stays valid as long as the window exists.
    struct Placement {
        let windowID: CGWindowID
        let pid: pid_t
        let element: AXUIElement
        /// Where the window was before the host touched it (CG global points).
        let originalFrame: CGRect
        let appName: String
        let title: String
    }

    /// Resolves `window` to its AX element and records its current frame, without moving it.
    /// Nil if Accessibility is off or the window cannot be matched (see `axWindow`).
    /// Brings `window` to the front of its app's windows (Accessibility raise; activation is the
    /// coordinator's job, through Launch Services). Used by the regular path when another app's
    /// window covers the spot the device clicked: otherwise the click lands on the cover, and a
    /// covered window stops repainting anyway. Never called on select.
    /// Close, minimize or toggle full screen on a window, as its own traffic lights would.
    static func perform(_ action: WindowCommand.Action, element: AXUIElement) -> Bool {
        switch action {
        case .close:
            var button: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXCloseButtonAttribute as CFString, &button) == .success,
                  let button else { return false }
            return AXUIElementPerformAction(button as! AXUIElement, kAXPressAction as CFString) == .success
        case .minimize:
            return AXUIElementSetAttributeValue(element, kAXMinimizedAttribute as CFString, kCFBooleanTrue) == .success
        case .fullScreen:
            let leaving = isFullScreen(element)
            return AXUIElementSetAttributeValue(element, "AXFullScreen" as CFString, leaving ? kCFBooleanFalse : kCFBooleanTrue) == .success
        }
    }

    /// `perform` for a window known only by its ScreenCaptureKit description.
    func perform(_ action: WindowCommand.Action, on window: SCWindow) -> Bool {
        guard AXIsProcessTrusted(), let pid = window.owningApplication?.processID else { return false }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        guard let ax = Self.axWindow(matching: window, in: app) else { return false }
        return Self.perform(action, element: ax)
    }

    /// Whether the window is in a full-screen Space (the AXFullScreen attribute AppKit windows expose).
    static func isFullScreen(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXFullScreen" as CFString, &value) == .success else { return false }
        return (value as? Bool) ?? false
    }

    /// Makes an app window its app's main and key window (Accessibility), so a click into it acts
    /// instead of merely focusing it. Cheap: two attribute writes on an element already matched.
    static func makeKey(_ element: AXUIElement) {
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    /// `makeKey` for a window known only by its ScreenCaptureKit description.
    func makeKey(window: SCWindow) {
        guard AXIsProcessTrusted(), let pid = window.owningApplication?.processID else { return }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        if let ax = Self.axWindow(matching: window, in: app) { Self.makeKey(ax) }
    }

    @discardableResult
    func raise(window: SCWindow) -> Bool {
        guard AXIsProcessTrusted(), let pid = window.owningApplication?.processID else { return false }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        guard let ax = Self.axWindow(matching: window, in: app) else { return false }
        return AXUIElementPerformAction(ax, kAXRaiseAction as CFString) == .success
    }

    func placement(for window: SCWindow) -> Placement? {
        guard AXIsProcessTrusted() else {
            if !warnedUntrusted {
                warnedUntrusted = true
                print("Window sizing needs Accessibility permission (the same one input needs); leaving windows at their size.")
            }
            return nil
        }
        guard let pid = window.owningApplication?.processID else { return nil }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 1.0)
        guard let ax = Self.axWindow(matching: window, in: app) else {
            print("Window placement: no Accessibility window matches \"\(window.title ?? "")\"; not moving it.")
            return nil
        }
        // Every later move/restore (and the atexit emergency restore) goes through this element.
        AXUIElementSetMessagingTimeout(ax, 1.0)
        // The AX frame is live; the SCWindow's can be two seconds stale (the catalog's poll).
        let original = Self.frame(of: ax) ?? Self.liveBounds(of: window.windowID) ?? window.frame
        return Placement(windowID: window.windowID, pid: pid, element: ax, originalFrame: original,
                         appName: window.owningApplication?.applicationName ?? "?", title: window.title ?? "")
    }

    /// Moves and resizes the window to `frame`, wherever that is: no on-screen clamping here, the
    /// destination is off the real displays by design. Position, size, position: an app that
    /// clamps the size may shift the origin (the probe's order). Returns the first AX error.
    @discardableResult
    func move(_ p: Placement, to frame: CGRect) -> AXError {
        var first = AXError.success
        func note(_ e: AXError) { if first == .success, e != .success { first = e } }
        note(Self.set(p.element, position: frame.origin))
        note(Self.set(p.element, size: frame.size))
        note(Self.set(p.element, position: frame.origin))
        return first
    }

    /// Puts the window back where `placement(for:)` found it. True when it is back, or there is
    /// nothing left to restore (window closed, app quit). Never leaves a live window off every
    /// real display: if its original display has gone meanwhile, it is nudged onto the main one.
    @discardableResult
    func restore(_ p: Placement) -> Bool {
        var err = move(p, to: p.originalFrame)
        if err == .invalidUIElement { return true }   // gone: nothing to restore
        if err == .cannotComplete {
            // Also what a messaging timeout returns, so ask the window server whether the window
            // still exists before treating it as gone; a busy app gets one more try.
            guard Self.liveBounds(of: p.windowID) != nil else { return true }
            err = move(p, to: p.originalFrame)
        }
        if let live = Self.liveBounds(of: p.windowID), !Self.onAnyScreen(live),
           let area = Self.visibleArea(around: CGDisplayBounds(CGMainDisplayID())) {
            // The original display was unplugged while the window was away: keep it reachable.
            let origin = Self.keep(live, in: area)
            _ = Self.set(p.element, position: origin)
            print("Window placement: \(p.appName)'s original display is gone; moved it onto the main display at \(Int(origin.x)),\(Int(origin.y)).")
        }
        return err == .success
    }

    /// AXError for the log.
    nonisolated static func axErrorName(_ e: AXError) -> String {
        switch e {
        case .success: return "success"
        case .apiDisabled: return "apiDisabled (Accessibility not granted)"
        case .cannotComplete: return "cannotComplete"
        case .attributeUnsupported: return "attributeUnsupported"
        case .illegalArgument: return "illegalArgument"
        case .invalidUIElement: return "invalidUIElement"
        case .notImplemented: return "notImplemented"
        case .failure: return "failure"
        default: return "AXError \(e.rawValue)"
        }
    }

    /// Does `rect` touch any display NSScreen knows (CG coordinates)? The virtual display counts
    /// while it exists, which is what `restore` wants: a stale read of the window still on it is
    /// not "off every screen".
    private static func onAnyScreen(_ rect: CGRect) -> Bool {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return true }
        return NSScreen.screens.contains { screen in
            let f = screen.frame
            return CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height).intersects(rect)
        }
    }

    // MARK: Finding the AX window

    /// There is no public way to go from a CGWindowID to its AXUIElement (`_AXUIElementGetWindow`
    /// is private), so match on what both APIs can see:
    ///
    /// 1. Title. If exactly one of the app's AX windows has the SCWindow's title, that is it — the
    ///    title is live on both sides, while the SCWindow's frame can be two seconds stale.
    /// 2. Frame. With several windows sharing the title ("Untitled", or a browser's two windows on
    ///    the same page) or none matching (an empty title, or it changed since the catalog polled),
    ///    pick the one whose origin and size are within a few points of the window's live bounds,
    ///    among the title matches if there were any, else among all of the app's windows.
    /// 3. Otherwise nil: resizing the wrong window is worse than not resizing.
    private static func axWindow(matching window: SCWindow, in app: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let candidates = value as? [AXUIElement], !candidates.isEmpty else { return nil }
        // The timeout on `app` does not carry over to its windows: a busy app would otherwise hold
        // the main thread for the ~1.5 s default per candidate.
        for c in candidates { AXUIElementSetMessagingTimeout(c, 0.5) }

        let title = window.title ?? ""
        let titled = title.isEmpty ? [] : candidates.filter { string(of: $0, kAXTitleAttribute) == title }
        if titled.count == 1 { return titled[0] }

        let bounds = liveBounds(of: window.windowID) ?? window.frame
        let pool = titled.isEmpty ? candidates : titled
        return pool.first { candidate in
            guard let f = frame(of: candidate) else { return false }
            return abs(f.minX - bounds.minX) <= frameTolerance && abs(f.minY - bounds.minY) <= frameTolerance
                && abs(f.width - bounds.width) <= frameTolerance && abs(f.height - bounds.height) <= frameTolerance
        }
    }

    /// The window server's current bounds (CG global, top-left origin — the same space AX uses).
    static func liveBounds(of id: CGWindowID) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]],
              let bounds = list.first?[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: bounds as CFDictionary)
    }

    // MARK: Staying on screen

    /// The visible frame (menu bar and Dock excluded) of the display holding most of `rect`, in
    /// CG global coordinates. NSScreen is bottom-left based on the primary display; flip it.
    private static func visibleArea(around rect: CGRect) -> CGRect? {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        let areas = NSScreen.screens.map { screen -> CGRect in
            let v = screen.visibleFrame
            return CGRect(x: v.minX, y: primaryHeight - v.maxY, width: v.width, height: v.height)
        }
        let overlap = { (area: CGRect) -> CGFloat in
            let i = area.intersection(rect)
            return i.isNull ? 0 : i.width * i.height
        }
        return areas.max { overlap($0) < overlap($1) }
    }

    /// The origin that keeps `frame` inside `area`, moving it as little as possible. A window
    /// bigger than the area keeps its top-left corner in it, so the title bar stays reachable.
    private static func keep(_ frame: CGRect, in area: CGRect) -> CGPoint {
        var origin = frame.origin
        if frame.maxX > area.maxX { origin.x = area.maxX - frame.width }
        if frame.maxY > area.maxY { origin.y = area.maxY - frame.height }
        origin.x = max(origin.x, area.minX)
        origin.y = max(origin.y, area.minY)
        return origin
    }

    // MARK: AX attribute plumbing

    private static func string(of element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private static func position(of element: AXUIElement) -> CGPoint? {
        var point = CGPoint.zero
        guard let value = axValue(of: element, kAXPositionAttribute),
              AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    private static func size(of element: AXUIElement) -> CGSize? {
        var size = CGSize.zero
        guard let value = axValue(of: element, kAXSizeAttribute),
              AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }

    private static func frame(of element: AXUIElement) -> CGRect? {
        guard let origin = position(of: element), let size = size(of: element) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private static func axValue(of element: AXUIElement, _ attribute: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }

    private static func set(_ element: AXUIElement, position: CGPoint) -> AXError {
        var point = position
        guard let value = AXValueCreate(.cgPoint, &point) else { return .failure }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
    }

    private static func set(_ element: AXUIElement, size: CGSize) -> AXError {
        var s = size
        guard let value = AXValueCreate(.cgSize, &s) else { return .failure }
        return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value)
    }
}
