import CoreGraphics

/// Which of the Mac's displays the Desktop streams when it has more than one, and the Desktop button
/// that steps to the next (issue #91, "the tapping method"): with two or more it reads "Desktop 1",
/// "Desktop 2"…, and a tap while the Desktop streams asks the host for the next display (kind 47). The
/// host works the next one out from its own newest look, as a display's ID can change across a sleep
/// (2026-10-28: 21 became 53 and 52), and keeps the choice by the display's UUID. Pure; checked by
/// Tests/checks/desktop-displays.
public enum DesktopDisplays {
    /// A display as the host lists it.
    public struct Display: Equatable {
        public var id: UInt32
        /// The same display's across sleeps and replugs (CGDisplayCreateUUIDFromDisplayID), where its
        /// ID may change.
        public var uuid: String
        /// Global points, as CGDisplayBounds.
        public var frame: CGRect
        /// Sill's own virtual display, which the Desktop never streams.
        public var isSills: Bool

        public init(id: UInt32, uuid: String, frame: CGRect, isSills: Bool) {
            self.id = id; self.uuid = uuid; self.frame = frame; self.isSills = isSills
        }
    }

    /// The displays the Desktop can stream, left to right and then top to bottom, as System Settings ›
    /// Displays arranges them (macOS's own order is not guaranteed); never Sill's virtual display.
    public static func candidates(_ displays: [Display]) -> [Display] {
        displays.filter { !$0.isSills }.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }
    }

    /// The display the Desktop streams: the one chosen while it is connected, else the fallback (the
    /// host's choice before this: the main display, or macOS's first), else the first.
    public static func resolve(chosen: String?, among candidates: [Display], fallback: UInt32?) -> Display? {
        if let chosen, let d = candidates.first(where: { $0.uuid == chosen }) { return d }
        return candidates.first { $0.id == fallback } ?? candidates.first
    }

    /// The display after `current`, wrapping round; the first when `current` is not a candidate; none
    /// with fewer than two.
    public static func next(after current: UInt32?, in candidates: [Display]) -> Display? {
        guard candidates.count > 1 else { return nil }
        guard let i = candidates.firstIndex(where: { $0.id == current }) else { return candidates[0] }
        return candidates[(i + 1) % candidates.count]
    }

    /// The choice kept after a step: the stepped-to display's when the Desktop streams on it, else the
    /// one it was on (ScreenCaptureKit can refuse a display, and the button steps only while the Desktop
    /// streams, so a choice that never streams would leave it black for good).
    public static func afterStep(stepped: String, previous: String?, streamed: Bool) -> String? {
        streamed ? stepped : previous
    }

    /// `current`'s place among the candidates, counting from 1.
    public static func number(of current: UInt32?, in candidates: [Display]) -> Int? {
        candidates.firstIndex { $0.id == current }.map { $0 + 1 }
    }

    /// Where the Desktop's input lands and its pointer is judged: the display its capture was built on,
    /// as the newest look places it, which is what the devices show; not the one a device just chose,
    /// which the catalog moves to before the capture restarts. Nil when that display is gone.
    public static func landing(streaming id: UInt32?, among candidates: [Display]) -> CGRect? {
        candidates.first { $0.id == id }?.frame
    }

    /// The Desktop button's words: "Desktop" with one display, with a Mac before this, or when which
    /// one is not known; else "Desktop 2".
    public static func label(displays: Int?, current: Int?) -> String {
        guard let n = shown(displays: displays, current: current) else { return "Desktop" }
        return "Desktop \(n)"
    }

    /// VoiceOver's value for the Desktop button: "Display 1 of 2", nil whenever the label is "Desktop".
    public static func accessibilityValue(displays: Int?, current: Int?) -> String? {
        guard let n = shown(displays: displays, current: current), let displays else { return nil }
        return "Display \(n) of \(displays)"
    }

    /// Whether the Desktop button's tap asks for the next display rather than picking the Desktop: only
    /// while the Desktop streams, from a host that says it has two displays or more.
    public static func tapSendsNext(desktopStreams: Bool, displays: Int?) -> Bool {
        desktopStreams && (displays ?? 0) > 1
    }

    /// Where the Mac's pointer goes after the Desktop moves to `frame`: its centre, so the device's arrow
    /// shows at once; nil when the pointer is already on it.
    public static func pointerTarget(pointer: CGPoint?, on frame: CGRect) -> CGPoint? {
        if let pointer, frame.contains(pointer) { return nil }
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    private static func shown(displays: Int?, current: Int?) -> Int? {
        guard let displays, displays > 1, let current, (1...displays).contains(current) else { return nil }
        return current
    }
}
