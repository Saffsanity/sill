import CoreGraphics
import Foundation

/// The Desktop's stops: which of the Mac's displays the Desktop streams when it has more than one, and
/// the Desktop button that steps to the next (issue #91, Noah's decision of 2026-10-19: "the tapping
/// method"; the button "must show which desktop the user is on … and make it clear that tapping moves to
/// the next"). addhumal's PR #173, grown by phase 1 of docs/virtual-desktop-plan.md (§1):
///
/// - The stops (`candidates`): the displays macOS lists, never Sill's own (the window stage's virtual
///   display) nor macOS's 1x stand-in for a Mac with no screen, one per mirror set, in the arrangement's
///   order (left to right, then top to bottom, as System Settings › Displays draws them) turned so that
///   the main display (the one with the menu bar) comes first. "Desktop 1" is always the main display;
///   each tap moves one display to the right as they sit on the desk, wrapping to the leftmost after the
///   rightmost, and back to the main display after the last stop. A display's ID changes across a sleep
///   (2026-10-28: 21 became 53 and 52), so the numbers come from the arrangement, never from IDs.
/// - The stop the Desktop shows (`resolve`): the main display while this Mac is locked or another user is
///   on its screen (one stop: the lock screen's own display, and nothing of the others); else the one a
///   device stepped to, by its UUID, while it is connected; else the main display, with Virtual Display on
///   or off (issue #345). The choice is the Mac's, not a device's (there is one stream): kept while a device
///   is connected and for `choiceGrace` after the last one left (`keepsChoice`), so a reconnect or a move
///   to the cable comes back to it, and a session that starts later begins on the main display.
/// - A step (kind 47, `next`): the stop after the one shown. One that does not stream goes back to the
///   choice before it (`afterStep`). Input lands on the stop the capture runs on, never the one just
///   chosen (`landing`), and the Mac's pointer goes to the new stop's centre (`pointerTarget`).
/// - The rate (`rate`): the devices' rate, held to the shown stop's refresh rate when it reports one.
/// - The device's button (`button`): today's with one stop or a Mac from before this; with two or more,
///   the stop's label ("Desktop 2"), a dot per stop with the shown one filled while the Desktop streams
///   ("3/7" from seven stops), and VoiceOver's label, value and hint.
///
/// Pure (CoreGraphics and Foundation); checked by Tests/checks/desktop-displays.
public enum DesktopDisplays {
    /// A display as the host lists it.
    public struct Display: Equatable {
        public var id: UInt32
        /// The same display's across sleeps and replugs (CGDisplayCreateUUIDFromDisplayID), where its
        /// ID may change.
        public var uuid: String
        /// Global points, as CGDisplayBounds.
        public var frame: CGRect
        /// One of Sill's own virtual displays (vendor 0x5111: the window stage's), never a stop.
        public var isSills: Bool
        /// macOS's own 1x stand-in for a Mac with no screen (vendor 'unkn', model 'virt', seen on macOS 27,
        /// PR #200), never a stop: no screen shows it.
        public var isStandIn: Bool
        /// The display this one mirrors (CGDisplayMirrorsDisplay), nil when it mirrors none: a mirror set
        /// is one stop.
        public var mirrors: UInt32?
        /// Its mode's refresh rate in Hz (CGDisplayModeGetRefreshRate), nil when it reports none.
        public var refreshHz: Double?
        /// Its name (NSScreen's localizedName, "DELL U2723QE"), for VoiceOver and the log; nil when not known.
        public var name: String?

        public init(id: UInt32, uuid: String, frame: CGRect, isSills: Bool, isStandIn: Bool = false,
                    mirrors: UInt32? = nil, refreshHz: Double? = nil, name: String? = nil) {
            self.id = id; self.uuid = uuid; self.frame = frame; self.isSills = isSills; self.isStandIn = isStandIn
            self.mirrors = mirrors; self.refreshHz = refreshHz; self.name = name
        }
    }

    // MARK: The stops

    /// The stops, in the cycle's order: every display but Sill's own and macOS's stand-in, one per
    /// mirror set (a display that mirrors another one listed is that one's stop; two that say they mirror
    /// each other are both kept, so no display is ever lost), left to right and then top to bottom (ties
    /// by ID, so the order never flips between looks), turned to start at `main`'s stop: the main display
    /// itself, or the display it mirrors. Without it among them, the arrangement as it is.
    public static func candidates(_ displays: [Display], main: UInt32?) -> [Display] {
        let shown = displays.filter { !$0.isSills && !$0.isStandIn }
        let byID = Dictionary(shown.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let stops = shown.filter { d in
            guard let m = d.mirrors, m != d.id, let primary = byID[m] else { return true }
            return primary.mirrors == d.id
        }
        let sorted = stops.sorted { ($0.frame.minX, $0.frame.minY, $0.id) < ($1.frame.minX, $1.frame.minY, $1.id) }
        let mainStop = sorted.firstIndex { $0.id == main }
            ?? displays.first { $0.id == main }?.mirrors.flatMap { m in sorted.firstIndex { $0.id == m } }
        guard let i = mainStop else { return sorted }
        return Array(sorted[i...] + sorted[..<i])
    }

    /// The stop the Desktop shows: the first (the main display) while `mainOnly` (this Mac locked, or
    /// another user on its screen); else the one chosen by its UUID while it is connected; else the first.
    public static func resolve(chosen: String?, among candidates: [Display], mainOnly: Bool = false) -> Display? {
        if !mainOnly, let chosen, let d = candidates.first(where: { $0.uuid == chosen }) { return d }
        return candidates.first
    }

    /// How long the Mac keeps the stop a device stepped to after the last device left, in seconds: a
    /// Desktop asked for again within it (a reconnect, a move to the cable) comes back to it.
    public static let choiceGrace: Double = 30

    /// Whether the choice still stands: while a device is connected, and for `choiceGrace` after the last
    /// one left (`leftAt`, nil when none has left yet); a clock that went back counts as time passed.
    public static func keepsChoice(devices: Int, leftAt: Double?, now: Double) -> Bool {
        if devices > 0 { return true }
        guard let leftAt else { return true }
        return now >= leftAt && now - leftAt < choiceGrace
    }

    /// The stop after `current`, wrapping round; the first when `current` is not a stop; none with fewer
    /// than two.
    public static func next(after current: UInt32?, in candidates: [Display]) -> Display? {
        guard candidates.count > 1 else { return nil }
        guard let i = candidates.firstIndex(where: { $0.id == current }) else { return candidates[0] }
        return candidates[(i + 1) % candidates.count]
    }

    /// The choice kept after a step: the stepped-to stop's when the Desktop streams on it, else the choice
    /// before the step (ScreenCaptureKit can refuse a display, and the button steps only while the Desktop
    /// streams, so a choice that never streams would leave it black for good).
    public static func afterStep(stepped: String, previous: String?, streamed: Bool) -> String? {
        streamed ? stepped : previous
    }

    /// `current`'s place among the stops, counting from 1.
    public static func number(of current: UInt32?, in candidates: [Display]) -> Int? {
        candidates.firstIndex { $0.id == current }.map { $0 + 1 }
    }

    /// Where the Desktop's input lands and its pointer is judged: the stop its capture was built on, as
    /// the newest look places it, which is what the devices show; not the one a device just chose, which
    /// the catalog moves to before the capture restarts. Nil when that display is gone.
    public static func landing(streaming id: UInt32?, among candidates: [Display]) -> CGRect? {
        candidates.first { $0.id == id }?.frame
    }

    /// Where the Mac's pointer goes after the Desktop moves to `frame`: its centre, so the device's arrow
    /// shows at once; nil when the pointer is already on it.
    public static func pointerTarget(pointer: CGPoint?, on frame: CGRect) -> CGPoint? {
        if let pointer, frame.contains(pointer) { return nil }
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    // MARK: The rate

    /// The Desktop's rate on a stop: what the devices ask (`wanted`, already held to 24 and to the Mac's
    /// Frame Rate limit), held to the stop's refresh rate when its display reports one (above 0): a 60 Hz
    /// monitor's Desktop streams at 60, at the 60 fps bitrate, to a 120 Hz iPad, since its capture gives no
    /// more. Never held under 24; a rate past any display's is no rate at all.
    public static func rate(_ wanted: Int, refreshHz: Double?) -> Int {
        guard let hz = refreshHz, hz > 0, hz < 1000 else { return wanted }    // NaN is not > 0
        return min(wanted, max(24, Int(hz.rounded())))
    }

    // MARK: The device's button

    /// The most dots the button draws; from one more the place is written ("3/7").
    public static let maxDots = 6

    /// VoiceOver's label for today's button: with one stop, and from a Mac before this.
    public static let todaysLabel = "Show the full Mac desktop"

    /// The Desktop button as a device draws it and VoiceOver reads it.
    public struct Button: Equatable {
        /// Under the symbol: "Desktop", or the stop's "Desktop 2".
        public var label: String
        /// One dot per stop, `lit` the shown one (counting from 1), while the Desktop streams on two to
        /// `maxDots` stops; none (0) otherwise.
        public var dots: Int
        public var lit: Int
        /// "3/7" in place of the dots while the Desktop streams on more than `maxDots` stops.
        public var counter: String?
        public var accessibilityLabel: String
        /// "Display 2 of 3, DELL U2723QE"; nil with today's button.
        public var accessibilityValue: String?
        /// "Shows the next display." while a tap steps, else "Shows the Mac’s desktop."; nil with today's.
        public var accessibilityHint: String?
        /// A tap asks the Mac for the next stop (kind 47) rather than picking the Desktop.
        public var steps: Bool
    }

    /// The button for a Mac whose window list says `displays` stops with `current` shown, or that the
    /// Desktop comes back to (`WindowList.desktopDisplays`, `desktopDisplay`, `desktopDisplayNames`), and
    /// whether the Desktop streams now. One stop, which one unknown, or a Mac from before this: today's.
    /// While a window streams the label names the stop a tap brings back, and no dots show: that tap picks
    /// the Desktop, it does not step.
    public static func button(displays: Int?, current: Int?, names: [String]?, desktopStreams: Bool) -> Button {
        guard let n = shown(displays: displays, current: current), let count = displays else {
            return Button(label: "Desktop", dots: 0, lit: 0, counter: nil, accessibilityLabel: todaysLabel,
                          accessibilityValue: nil, accessibilityHint: nil, steps: false)
        }
        let dots = desktopStreams && count <= maxDots ? count : 0
        return Button(label: label(displays: count, current: n), dots: dots, lit: dots > 0 ? n : 0,
                      counter: desktopStreams && count > maxDots ? "\(n)/\(count)" : nil,
                      accessibilityLabel: "Desktop", accessibilityValue: value(n, of: count, names: names),
                      accessibilityHint: desktopStreams ? "Shows the next display." : "Shows the Mac’s desktop.",
                      steps: desktopStreams)
    }

    /// The button's words under its symbol: "Desktop" with one stop, from a Mac before this, or when which
    /// one is not known; else "Desktop 2".
    public static func label(displays: Int?, current: Int?) -> String {
        guard let n = shown(displays: displays, current: current) else { return "Desktop" }
        return "Desktop \(n)"
    }

    /// Whether the Desktop button's tap asks for the next stop (kind 47) rather than picking the Desktop:
    /// only while the Desktop streams, from a Mac that says it has two stops or more and which one shows.
    public static func tapSendsNext(desktopStreams: Bool, displays: Int?, current: Int?) -> Bool {
        button(displays: displays, current: current, names: nil, desktopStreams: desktopStreams).steps
    }

    /// VoiceOver's value: "Display 2 of 3, DELL U2723QE", with the stop's name only when the Mac named
    /// every stop; also what a device says after its own step lands.
    public static func value(_ n: Int, of count: Int, names: [String]?) -> String {
        let name = names.flatMap { $0.count == count && (1...count).contains(n) ? $0[n - 1] : nil }?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Display \(n) of \(count)" : "Display \(n) of \(count), \(name)"
    }

    private static func shown(displays: Int?, current: Int?) -> Int? {
        guard let displays, displays > 1, let current, (1...displays).contains(current) else { return nil }
        return current
    }
}
