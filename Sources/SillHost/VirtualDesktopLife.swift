import Foundation

/// When the Virtual Desktop exists (docs/virtual-desktop-plan.md §6 and §10 as revised 2026-11-18, phase 2b): a clock and
/// what the coordinator sees in, make, keep or remove out. Noah, 2026-11-11 and 11-12: off by default, "only while a
/// device shows it, plus 30 s", windows left on it moved to the main display and back (DesktopWindowLedger). Sill's
/// display for the Desktop is one display in two roles (plan §1, SillDisplays' `.desktop`):
/// - **headless**: a Mac with no working screen gets it by itself (PR #200, phase 2a): made and released by
///   `HeadlessDesktopPolicy.Watch` alone (its settle, its 2 s, the screens' sleep), never by this; kept between
///   connections while no real screen works. A display that exists while no real screen works is in this role.
/// - **virtualDesktop**: the person's Virtual Desktop (HostConfig.virtualDesktop), the last of the Desktop's stops,
///   made here when a device shows its stop and kept by the rules below.
///
/// The rules (each look's answer, `look`):
/// - **Made** when a device shows its stop (a step onto it, a device switching it on, the Desktop coming back to it within
///   the session span: the coordinator's `shown`), with the switch on, Sill able to make it (`available`: the private API,
///   the AppKit loop, Screen Recording, not a synthetic host but under its TEST ONLY hook), a real screen working (with
///   none, the headless role is the one), unlocked, on the console, and the guard for #380 clear. Never a second one:
///   only when none exists.
/// - **Kept** while a device shows it, and `grace` (30 s) after the last one stops; kept while locked, past those 30 s,
///   until the unlock, and then 30 s from the unlock (a switch changed meanwhile waits for the unlock too).
/// - **Removed** 30 s after; when switched off (the Desktop first to the main display, the coordinator's); at once off
///   console (it would join the other user's displays); at Quit and when macOS removes it (the coordinator's, not
///   asked here). Its windows move first (DesktopWindowLedger).
/// - **Never the main display beside a real screen** (open decision 7 (a); the 2026-11-12 build 1411 night's shape,
///   #357's suspect): once a real screen has worked `mainAfter` (2 s, as Watch's hysteresis), Sill's display in this role
///   that is still the main display (CGMainDisplayID) goes, locked or not, as the headless release does. One that macOS
///   left as an extra display stays while it is the Virtual Desktop and a device shows it.
/// - **The roles change hands without a second display**: the last real screen goes while it exists, and it is the
///   headless one (macOS makes it main); a real screen comes back while a device shows it with the switch on and it is
///   not the main display, and it is the Virtual Desktop again; otherwise the headless release (Watch's).
/// - **Spacing** (a device must not churn the Mac's displays; #333's monitors switch off at a display change): at most
///   one make or removal every `spacing` (3 s) and `perMinute` (10) in a minute, counting every change of the Desktop's
///   display, the headless role's too. A make or removal due sooner waits (`spaced`), and the newest request wins: the
///   answer is the look's, so a request that a later look no longer makes is dropped. Off console's removal never waits.
///
/// Times are seconds on one clock (the coordinator's); nothing here reads a clock or a display. Pure; checked by
/// Tests/checks/virtual-desktop (5,000 random sessions against the plan's invariants).
struct VirtualDesktopLife: Equatable {
    /// How long it stays once no device shows it (Noah, 2026-11-11).
    static let grace: Double = 30
    /// The least time between two changes of the Desktop's display (a make or a removal), and how many a minute.
    static let spacing: Double = 3
    static let perMinute = 10
    static let minute: Double = 60
    /// How long a real screen has worked before Sill's display, still the main display, goes: the headless role's
    /// hysteresis (HeadlessDesktopPolicy.Watch.hysteresis), so both roles leave a real screen's return alike.
    static let mainAfter: Double = 2

    /// What the coordinator sees at a look.
    struct Seen: Equatable {
        /// The Virtual Desktop's switch (HostConfig.virtualDesktop: Settings › Displays, the menu, a paired device).
        var switchOn = false
        /// A device streams the Desktop on the Virtual Desktop's stop, or asks for it there now: a step onto it, the
        /// switch turned on from a device (which shows it at once, open decision 12), the Desktop coming back to its
        /// stop within the session span.
        var shown = false
        /// This session's screen is locked (this user on the console).
        var locked = false
        /// Another user has the screen (or the off-console view streams).
        var offConsole = false
        /// Sill can make it: the private API, the AppKit loop, Screen Recording, not a synthetic host (but under its TEST
        /// ONLY hook, where it is only said to be made).
        var available = true
        /// The guard for #380 holds (DisplayMakeGuard): Sill makes no display by itself until Try Again.
        var guardHolds = false
        /// Sill's Desktop display exists (SillDisplays' `.desktop`, in either role).
        var exists = false
        /// It is the main display (CGMainDisplayID).
        var isMain = false
        /// The real screens that work, as HeadlessDesktopPolicy.realDisplays counts them (macOS's stand-in and Sill's
        /// own are none; an asleep monitor counts). None: Sill's display is the headless one.
        var realScreens = 1
    }

    enum Role: Equatable { case headless, virtualDesktop }

    /// Why it goes.
    enum Why: Equatable {
        /// No device has shown it for `grace` (from the unlock, after a lock).
        case grace
        /// Its switch was turned off.
        case switchedOff
        /// This session is off the console.
        case offConsole
        /// It was the main display, and a real screen has worked `mainAfter`.
        case main
    }

    enum Change: Equatable {
        case make
        case remove(Why)
    }

    /// One look's answer.
    enum Decision: Equatable {
        /// No display, and none to make now (with no real screen, the headless role's Watch decides).
        case idle
        /// It exists in the headless role: HeadlessDesktopPolicy.Watch makes and releases it, nothing here.
        case headless
        /// It exists and stays; look again `until` then (the grace's end, a real screen's 2 s), or nil: until something
        /// changes (shown, locked).
        case keep(until: Double?)
        /// Make it now (SillDisplays' `.desktop`, at VirtualDesktopSize's size), then `made(.virtualDesktop, at:)`.
        case make
        /// Remove it now, its windows first (DesktopWindowLedger), then `removed(at:)`.
        case remove(Why)
        /// A make or a removal is due, but waits for the spacing until then; look again then.
        case spaced(Change, until: Double)
    }

    /// The role of the display that exists (nil: none).
    private(set) var role: Role?
    /// When it was last made.
    private(set) var madeAt: Double?
    /// When a device last showed it: the look that found it shown, or the first look after that found it no longer
    /// shown (a step away, a window picked, the last device gone: the coordinator looks at each).
    private(set) var lastShown: Double?
    private(set) var wasShown = false
    /// The last look that found the screen unlocked after locked.
    private(set) var unlockedAt: Double?
    private(set) var wasLocked = false
    /// When real screens last went from none to some (the first look with some counts as their start); nil while none.
    private(set) var realSince: Double?
    private var lastReal: Int?
    /// The times of the last changes of the Desktop's display, the newest last, at most `perMinute`.
    private(set) var changes: [Double] = []
    /// How long it stays once no device shows it, for this coordinator: `grace`, or a test host's (SILL_TEST_VD_GRACE,
    /// `testHook`), so a live gate runs the grace in seconds.
    let graceSeconds: Double

    init(grace: Double = VirtualDesktopLife.grace) { graceSeconds = grace }

    /// A look at `now`: what the coordinator sees, and what to do. Call it at each display change, show, step, switch,
    /// lock and unlock, and again at a `keep`'s or a `spaced`'s time.
    mutating func look(_ s: Seen, at now: Double) -> Decision {
        if s.shown || wasShown { lastShown = now }
        wasShown = s.shown
        if wasLocked, !s.locked { unlockedAt = now }
        wasLocked = s.locked
        if s.realScreens > 0 {
            if (lastReal ?? 0) == 0 { realSince = now }
        } else {
            realSince = nil
        }
        lastReal = s.realScreens

        if !s.exists {
            role = nil
        } else if s.realScreens == 0 || role == nil {
            // No real screen: the headless display, whatever it was made as. One Sill was not told it made: Watch's too,
            // never removed here.
            role = .headless
        } else if role == .headless, s.switchOn, s.shown, !s.isMain, !s.locked, !s.offConsole {
            // A real screen back while a device shows it with the switch on, and macOS left it an extra display: it stays
            // as the Virtual Desktop (plan §1); otherwise the headless release, Watch's.
            role = .virtualDesktop
        }

        guard s.exists else {
            guard s.realScreens > 0, s.shown, s.switchOn, s.available, !s.locked, !s.offConsole, !s.guardHolds else { return .idle }
            return spaced(.make, now: now)
        }
        guard role == .virtualDesktop else { return .headless }
        if s.offConsole { return .remove(.offConsole) }
        if s.isMain {
            let due = (realSince ?? now) + Self.mainAfter
            return now >= due ? spaced(.remove(.main), now: now) : .keep(until: due)
        }
        if s.locked { return .keep(until: nil) }
        if !s.switchOn { return spaced(.remove(.switchedOff), now: now) }
        if s.shown { return .keep(until: nil) }
        let end = max(lastShown ?? madeAt ?? now, unlockedAt ?? -Double.infinity) + graceSeconds
        return now >= end ? spaced(.remove(.grace), now: now) : .keep(until: end)
    }

    /// The coordinator made the Desktop's display in `role` at `now` (the Virtual Desktop on a `.make`, or the headless
    /// one by Watch).
    mutating func made(_ role: Role, at now: Double) {
        self.role = role
        madeAt = now
        record(now)
    }

    /// The Desktop's display went at `now`: removed by Sill (any reason, either role, Quit) or by macOS.
    mutating func removed(at now: Double) {
        role = nil
        record(now)
    }

    /// The earliest time the next make or removal may be: `spacing` after the last change, and a minute after the
    /// `perMinute`-th last.
    var nextAllowed: Double {
        var t = -Double.infinity
        if let last = changes.last { t = last + Self.spacing }
        if changes.count >= Self.perMinute { t = max(t, changes[changes.count - Self.perMinute] + Self.minute) }
        return t
    }

    private func spaced(_ c: Change, now: Double) -> Decision {
        let next = nextAllowed
        guard now >= next else { return .spaced(c, until: next) }
        switch c {
        case .make: return .make
        case .remove(let why): return .remove(why)
        }
    }

    private mutating func record(_ t: Double) {
        changes.append(t)
        if changes.count > Self.perMinute { changes.removeFirst(changes.count - Self.perMinute) }
    }

    // MARK: The lines (Sill.log; each names no window)

    /// Why it went, in the removal's line; `grace`: the grace it had (a test host's may be shorter).
    static func words(_ why: Why, grace: Double = VirtualDesktopLife.grace) -> String {
        switch why {
        case .grace: return "no device has shown it for \(Int(grace)) s"
        case .switchedOff: return "turned off"
        case .offConsole: return "this session is off the console"
        case .main: return "it was the main display and a real screen works again"
        }
    }

    /// "Virtual Desktop: no device has shown it for 30 s; moved 3 windows to Built-in Retina Display and removed it.":
    /// `moved` of `of` windows on it went to `to` (the main display's name) first.
    static func removedLine(_ why: Why, moved: Int, of: Int, to: String, grace: Double = VirtualDesktopLife.grace) -> String {
        let windows: String
        if of == 0 {
            windows = ""
        } else if moved == of {
            windows = "moved \(of) window\(of == 1 ? "" : "s") to \(to) and "
        } else {
            windows = "moved \(moved) of \(of) windows to \(to) (the rest go where macOS puts them) and "
        }
        return "Virtual Desktop: \(words(why, grace: grace)); \(windows)removed it."
    }

    /// The grace ended while the Mac is locked: once a lock.
    static let keptLockedLine = lockedLine(grace: grace)

    /// The same for a grace of `grace` seconds (a test host's).
    static func lockedLine(grace: Double) -> String {
        "Virtual Desktop: kept while this Mac is locked; it goes \(Int(grace)) s after the unlock unless a device shows it."
    }

    /// The make's line: "Virtual Desktop 1089×800 pt @2× at 60 Hz id 7: made in 412 ms for iPad mini (its picture: 728×535
    /// pt).": the mode it came up at (`came`, its points and scale as CoreGraphics reads them, and its rate), the one asked
    /// for too when it differs, its ID, how long the make took, and the device it is for (`device`: nil for none known,
    /// VirtualDesktopSize.fallback) with the space its picture has (`space`, rule A: its panel, in its points; nil for a size
    /// the person chose). `id` nil: a test host's, said and never made (SILL_TEST_VIRTUAL_DESKTOP).
    static func madeLine(came: VirtualDesktopSize.Size, asked: VirtualDesktopSize.Size, hz: Int, id: UInt32?, ms: Int,
                         device: String?, space: CGSize? = nil) -> String {
        let mode = "\(came.widthPt)×\(came.heightPt) pt @\(came.scale)× at \(hz) Hz"
        let askedWords = came == asked ? "" : " (asked \(asked.widthPt)×\(asked.heightPt) @\(asked.scale)×)"
        let f = VirtualDesktopSize.fallback
        // Whole points (a host takes no side outside 1…16384, ViewportBounds; a side that is no number prints none).
        let picture = space.flatMap { s -> String? in
            guard s.width.isFinite, s.height.isFinite, abs(s.width) < 1e6, abs(s.height) < 1e6 else { return nil }
            return " (its picture: \(Int(s.width.rounded()))×\(Int(s.height.rounded())) pt)"
        } ?? ""
        let whose = device.map { "for \($0)\(picture)" } ?? "at \(f.widthPt)×\(f.heightPt): no device's screen known yet"
        guard let id else { return "Virtual Desktop \(mode)\(askedWords): said, never made (TEST ONLY, \(testVariable)), \(whose)." }
        return "Virtual Desktop \(mode)\(askedWords) id \(id): made in \(ms) ms \(whose)."
    }

    // MARK: TEST ONLY (a --synthetic host: the rules run for real, and nothing is made)

    static let testVariable = "SILL_TEST_VIRTUAL_DESKTOP"
    static let testGraceVariable = "SILL_TEST_VD_GRACE"

    /// TEST ONLY: `SILL_TEST_VIRTUAL_DESKTOP=1` on a test host (`--synthetic`, never Sill.app's own executable:
    /// DoorPolicy.isTestHost) with SILL_TEST_DISPLAYS (`stops`), whose stops are its screens: this host can have the
    /// Virtual Desktop, which it only says it makes (SillDisplays.say, as SILL_TEST_HEADLESS's display), listed as one more
    /// stop after them; and `SILL_TEST_VD_GRACE=<s>` (1 to 120) its grace in place of 30 s. Whether it is on, the grace,
    /// and the lines it prints at start (none without the variables; anywhere else one line says they are ignored).
    static func testHook(environment: [String: String], testHost: Bool, stops: Bool) -> (on: Bool, grace: Double?, lines: [String]) {
        let asked = environment[testVariable].map { !$0.isEmpty && $0 != "0" } ?? false
        let raw = environment[testGraceVariable] ?? ""
        guard asked || !raw.isEmpty else { return (false, nil, []) }
        guard testHost else {
            return (false, nil, ["\(testVariable) and \(testGraceVariable) ignored: only a --synthetic test host takes them, never Sill.app."])
        }
        guard asked, stops else {
            return (false, nil, ["\(testVariable) and \(testGraceVariable) ignored: they need SILL_TEST_DISPLAYS, whose stops are the screens, and \(testVariable)=1."])
        }
        var lines: [String] = []
        var g: Double?
        if !raw.isEmpty {
            if let v = Double(raw), v.isFinite, v >= 1, v <= 120 { g = v } else { lines.append("\(testGraceVariable)=\(raw) ignored: seconds from 1 to 120.") }
        }
        lines.append("Test Virtual Desktop: this host can have it and only says it makes it, never makes one (\(testVariable)); "
                     + "its grace \(Int(g ?? grace)) s.")
        return (true, g, lines)
    }

    /// A make or a removal that waited for the spacing, once done: "Virtual Desktop: waited 2.1 s before making it (3 s
    /// since the last change)."; `perMinute` changes in the last minute say so instead.
    static func waitedLine(_ c: Change, waited: Double, fullMinute: Bool) -> String {
        let what: String
        switch c {
        case .make: what = "making it"
        case .remove: what = "removing it"
        }
        let why = fullMinute ? "\(perMinute) changes in a minute" : "\(Int(spacing)) s since the last change"
        return "Virtual Desktop: waited \(String(format: "%.1f", waited)) s before \(what) (\(why))."
    }
}
