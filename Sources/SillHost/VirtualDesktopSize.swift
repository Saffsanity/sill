import CoreGraphics

/// The size and refresh rate of Sill's own Desktop display, by default the device's (Noah, 2026-11-18: "should default
/// to resolution and refresh of client device, not what we originally proposed"; docs/virtual-desktop-plan.md §4 as
/// revised that day). Phase 2a, PR #200 finished: the display a Mac with no working screen gets (#61, #298), made at
/// the size of the device whose Desktop asked for it, so the lock screen and the desktop fill that device; phase 2b's
/// Virtual Desktop takes the same default ("This device").
///
/// This device: the device's room (its picture with Sill's controls hidden, phase 2b's `Viewport.room`), else its
/// panel (the viewport's `width` and `height`, which every device build sends as its stream screen appears), in its
/// points, at Retina (2x), so an iPad gets one Mac pixel for each of its own:
/// 1. each side rounded to whole points;
/// 2. no side under `minSide` (800 points): both sides grow by one factor until the shorter is 800, keeping the shape
///    (VirtualDisplaySize.minSide: macOS ran Sill's displays smaller than that at 1x, and most Mac windows do not fit
///    a shorter screen); an iPad mini's 1133 × 744 becomes 1218 × 800;
/// 3. no side over `maxSide` (4096 points, 8192 pixels at 2x: VirtualDisplay's ceiling): both shrink by one factor;
/// 4. a shape longer than 4096 : 800 (5.12 : 1, no device's) gives way: each side held to 800…4096.
///
/// With no viewport from any device when the display is made (a test client that sends none; a device sends one as its
/// stream screen appears, and the display waits at least a second for the displays to settle): `fallback`, #200's
/// 1920 × 1080. The rate: the device's (the viewport's `fps`: 120 on ProMotion, 60 otherwise and in Low Power Mode),
/// held to 24…the Mac's Frame Rate limit; 60 with no viewport.
///
/// Following the device (phase 2b, plan §5; `Follow`, `followStep`, `InPlace`): the matched device's room, turned, folded
/// or resized, or another device's once that one is the matched device, is taken after 1 s steady and at most once every
/// 3 s, in place on the live display as Noah's probes of 2026-11-23 showed it can be (`followWay`; P2b and P2c,
/// Scripts/display-modes-probe), inside the backing it was made with (`backing`), else at its next make.
///
/// Pure (CoreGraphics); checked by Tests/checks/virtual-desktop.
package enum VirtualDesktopSize {
    /// A display's size in points and its scale (pixels a point).
    package struct Size: Equatable {
        package var widthPt: Int
        package var heightPt: Int
        package var scale: Int

        package init(widthPt: Int, heightPt: Int, scale: Int) { self.widthPt = widthPt; self.heightPt = heightPt; self.scale = scale }

        /// The same size a quarter turned: the device held the other way.
        package var turned: Size { Size(widthPt: heightPt, heightPt: widthPt, scale: scale) }
    }

    static let minSide = 800
    static let maxSide = 4096
    static let scale = 2
    /// No viewport from any device: #200's size, at Retina.
    static let fallback = Size(widthPt: 1920, heightPt: 1080, scale: 2)

    /// The display for a device whose room is `room` (nil: it sends none, every build before phase 2b) and whose panel
    /// is `panel`, in device points; nil when neither has two sides that are positive numbers.
    static func device(room: CGSize?, panel: CGSize?) -> Size? {
        guard let source = [room, panel].compactMap({ $0 }).first(where: usable) else { return nil }
        var w = Double(source.width).rounded(), h = Double(source.height).rounded()
        w = max(w, 1); h = max(h, 1)
        let short = min(w, h)
        if short < Double(minSide) {
            let grow = Double(minSide) / short
            w = (w * grow).rounded(); h = (h * grow).rounded()
        }
        let long = max(w, h)
        if long > Double(maxSide) {
            let shrink = Double(maxSide) / long
            w = (w * shrink).rounded(); h = (h * shrink).rounded()
        }
        let side = { (v: Double) in Int(min(max(v, Double(minSide)), Double(maxSide))) }
        return Size(widthPt: side(w), heightPt: side(h), scale: scale)
    }

    /// Two sides that are positive, finite numbers (a host takes only viewports within ViewportBounds anyway).
    static func usable(_ s: CGSize) -> Bool {
        s.width.isFinite && s.height.isFinite && s.width > 0 && s.height > 0
    }

    /// The display's refresh rate: the device's viewport rate (nil before it has sent one: 60), held to 24 and to the
    /// Mac's Frame Rate limit (`limit`, HostConfig.maxFPS).
    static func rate(viewportFPS: Int?, limit: Int) -> Int {
        min(max(24, limit), max(24, viewportFPS ?? 60))
    }

    /// Whose viewport sizes the display: the device that asked for the Desktop (`asker`) when it has sent one, else the
    /// device whose viewport came last (`newest`) when it has, else none (`fallback`).
    static func matched<ID: Hashable>(asker: ID?, newest: ID?, sent: Set<ID>) -> ID? {
        if let asker, sent.contains(asker) { return asker }
        if let newest, sent.contains(newest) { return newest }
        return nil
    }

    /// The refresh rate the Desktop's stream rate is held to (DesktopDisplays.rate): the shown stop's when it reports
    /// one, else, while the Desktop is on Sill's own display (`onSills`; no stop: a Mac with no working screen), that
    /// display's (`sills`), so a 120 Hz device beside the 60 Hz one it was made for streams at 60, at the 60 fps bitrate,
    /// since its capture gives no more (the assessment of 2026-11-18, defect 4); else none.
    static func refreshHeld(stop: Double?, sills: Double?, onSills: Bool) -> Double? {
        stop ?? (onSills ? sills : nil)
    }

    /// The line a made display prints: the mode it came up at (`came`: its points and scale as CoreGraphics reads them,
    /// and its rate), never only the one asked for (`asked`, said too when it differs: a display macOS kept at 1x read
    /// "@2×" in #200's line, defect 6), its ID (nil: a test host's display, said and never made), and whose screen it is
    /// (`device`: nil for none known, `fallback`).
    static func createdLine(came: Size, asked: Size, hz: Int, id: UInt32?, device: String?) -> String {
        let mode = "\(came.widthPt)×\(came.heightPt) pt @\(came.scale)× at \(hz) Hz"
        let askedWords = came == asked ? "" : " (asked \(asked.widthPt)×\(asked.heightPt) @\(asked.scale)×)"
        let what = id.map { "id \($0)" } ?? "TEST ONLY: none made, SILL_TEST_HEADLESS"
        let whose = device.map { "for \($0), its screen" } ?? "at \(fallback.widthPt)×\(fallback.heightPt): no device's screen known yet"
        return "Headless display: created \(mode)\(askedWords) (\(what)) \(whose)."
    }

    // MARK: The person's choice (Noah, 2026-11-18: "allow the user to select resolution"; the plan's §4 choices)

    /// The Virtual Desktop's size as the person chooses it (HostConfig.virtualDesktopSize: Sill for Mac's Settings ›
    /// Displays, the CLI's --virtual-desktop=…; a device's pickers are phase 3's): This device (`deviceChoice`, the
    /// default: `device(room:panel:)`, and it follows the device), the main display's mode (`mainChoice`: `main`), or one
    /// of `offered` by its id ("1920x1080@2"). None but This device follows a device.
    package enum Choice: Equatable {
        case device
        case main
        case fixed(Size)
    }

    package static let deviceChoice = "device"
    package static let mainChoice = "main"

    /// The sizes offered after This device and Same as main display, from the plan's list (§4, the 11-12 plan's §3) held
    /// to Sill's own bounds: at Retina, 1440 × 900 to 2560 × 1440 ("5K"), no side under 800 points; at 1x, 1920 × 1080,
    /// 2560 × 1440 and 3440 × 1440. The 6K and 8K entries and 1280 × 720 wait for phase 3's self test of each size.
    package static let offered: [Size] = [
        Size(widthPt: 1440, heightPt: 900, scale: 2), Size(widthPt: 1512, heightPt: 982, scale: 2),
        Size(widthPt: 1728, heightPt: 1117, scale: 2), Size(widthPt: 1920, heightPt: 1080, scale: 2),
        Size(widthPt: 1920, heightPt: 1200, scale: 2), Size(widthPt: 2560, heightPt: 1440, scale: 2),
        Size(widthPt: 1920, heightPt: 1080, scale: 1), Size(widthPt: 2560, heightPt: 1440, scale: 1),
        Size(widthPt: 3440, heightPt: 1440, scale: 1),
    ]

    /// A size's id: "1920x1080@2" (VirtualDesktopState.size's form).
    package static func id(_ s: Size) -> String { "\(s.widthPt)x\(s.heightPt)@\(s.scale)" }

    /// Every id the person may choose, in the pickers' order.
    package static var choiceIDs: [String] { [deviceChoice, mainChoice] + offered.map(id) }

    /// The choice an id names; nil for anything not offered (HostConfig.validated takes This device then).
    package static func choice(_ id: String) -> Choice? {
        if id == deviceChoice { return .device }
        if id == mainChoice { return .main }
        return offered.first { Self.id($0) == id }.map { .fixed($0) }
    }

    /// The refresh rates offered: 0, the device's (the default), then 30, 60 and 120 Hz.
    package static let rateChoices = [0, 30, 60, 120]

    /// The display's rate for the person's choice `choice` (0: the device's, `rate(viewportFPS:limit:)`), held to 24 and
    /// to the Mac's Frame Rate limit (`limit`); an unknown choice is the device's.
    static func rate(choice: Int, viewportFPS: Int?, limit: Int) -> Int {
        guard choice != 0, rateChoices.contains(choice) else { return rate(viewportFPS: viewportFPS, limit: limit) }
        return min(max(24, limit), choice)
    }

    /// "Same as main display": the main display's mode as the person set it (`points`, its "looks like" size; `scale`, its
    /// pixels a point, 1 or 2), the 11-12 plan's §2: its scale kept, its pixels held inside 3840 × 2160 turned to its
    /// shape (its points shrinking evenly at its scale, whole points), then, at 2x, as Sill's displays are held (no side
    /// under 800 points, none over 4096). Nil with no size. Its rate is the person's rate choice, as for any size.
    package static func main(points: CGSize, scale: Int) -> Size? {
        guard usable(points) else { return nil }
        let s = scale >= 2 ? 2 : 1
        var w = Double(points.width).rounded(), h = Double(points.height).rounded()
        let box = w >= h ? (wide: 3840.0, high: 2160.0) : (wide: 2160.0, high: 3840.0)
        let fit = min(1, box.wide / (w * Double(s)), box.high / (h * Double(s)))
        if fit < 1 { w = (w * fit + 1e-9).rounded(.down); h = (h * fit + 1e-9).rounded(.down) }   // the box's own edge kept whole
        if s == 2 { return device(room: CGSize(width: w, height: h), panel: nil) }
        return Size(widthPt: max(1, Int(w)), heightPt: max(1, Int(h)), scale: 1)
    }

    /// The CLI's `--virtual-desktop=VALUE`: a size choice (`device`, `main` or one of `offered` as "WxH@S"), and a rate
    /// after a colon (`:30`, `:60`, `:120`; none: the device's). Nil for anything else.
    package static func flag(_ value: String) -> (size: String, hz: Int)? {
        let parts = value.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard (1...2).contains(parts.count), choice(parts[0]) != nil else { return nil }
        guard parts.count == 2 else { return (parts[0], 0) }
        guard let hz = Int(parts[1]), hz != 0, rateChoices.contains(hz) else { return nil }
        return (parts[0], hz)
    }

    /// The person's choice in words, for Sill for Mac's pickers and the log: "Match the device", "Same as main display",
    /// "1920 × 1080 (Retina)", "3440 × 1440"; an id not offered reads as This device.
    package static func words(_ id: String) -> String {
        switch choice(id) ?? .device {
        case .device: return "Match the device"
        case .main: return "Same as main display"
        case .fixed(let s): return "\(s.widthPt) × \(s.heightPt)" + (s.scale == 2 ? " (Retina)" : "")
        }
    }

    /// A rate choice in words: "Match the device", "30 Hz", "60 Hz", "120 Hz".
    package static func rateWords(_ hz: Int) -> String { hz == 0 || !rateChoices.contains(hz) ? "Match the device" : "\(hz) Hz" }

    // MARK: Following the device (phase 2b, docs/virtual-desktop-plan.md §5 as revised 2026-11-18; probes P2, P2b, P2c)

    /// How the Virtual Desktop follows its matched device's room (a turn, the Duo's fold, a Stage Manager window resized,
    /// Full Screen's Room choice changed), or another device's once that one is the matched device (plan §5: the one that
    /// stepped onto it or switched it on). Decided by Noah's probes of 2026-11-23 on his Mac (macOS 27.2.1;
    /// Scripts/display-modes-probe, docs/steps/2026-11-18-virtual-desktop-2b.md's fourth part):
    /// - a mode listed beside another, when the display is made or later, is not usable for the desktop, and a CoreGraphics
    ///   switch to it fails (complete 1001; P2 step 1, P2b steps 0 and f): there is no way by the modes listed at creation;
    /// - `applySettings:` with the new size ALONE on the live display takes a size of the display's own orientation at 2x
    ///   in about 300 ms, the same display ID (P2b step e: 1496×800 to 1218×800 and back), and a turn in two steps: the
    ///   turned pixels at 1x, then, once macOS lists the turn at 2x usable (at once), a CoreGraphics switch to it: 650 to
    ///   706 ms in all, the same ID; back to the room by `applySettings:` with it alone, at 2x, in about 320 ms (P2c steps
    ///   1 and 4, the latter on a display made with the room alone);
    /// - a size beyond the backing the display was made with is never taken (P2 step 3, P2b step e).
    enum FollowWay: Equatable, CaseIterable {
        /// Not at all: the size waits for the next time the display is made (the plan's "else, in 2b"; this branch's
        /// way until the probes).
        case nextMake
        /// In place: `applySettings:` with the new size alone, and a CoreGraphics switch to its 2x mode when macOS lands it
        /// at 1x (`InPlace`), inside the backing it was made with (`backing`); a step refused or late falls back to the size
        /// it had, at 2x, and the next make.
        case newModes
        /// Removed and made again at the new size, its windows kept by DesktopWindowLedger (phase 3's way); never the
        /// headless display, the Mac's only screen (plan §2: no display to fall back to).
        case remake
    }

    /// The probes' verdict (P2b and P2c, 2026-11-23): in place.
    static let followWay: FollowWay = .newModes

    /// The display's backing in pixels each way: the descriptor's maximum (VirtualDisplay's `backing`), fixed when it is
    /// made. A size whose pixels do not fit it is never taken in place (P2's step 3 and P2b's step e: listed, never taken).
    package struct Backing: Equatable {
        package var wide: Int
        package var high: Int
        package init(wide: Int, high: Int) { self.wide = wide; self.high = high }
    }

    /// The backing's floor and cap for a display that follows a device, in pixels a side. The floor holds every iPhone's
    /// and iPad's This device size both ways, as far as is known (an iPhone Pro Max held sideways, clear of its Dynamic
    /// Island, about 1510 × 800 points; an iPad Pro 13-inch 1376 × 1032; at 2x under 3072 pixels a side), so the device it
    /// is made for may turn, and another may take it over, though neither was connected when it was made. The cap: no
    /// side past 4096 pixels in place, the widest picture every Mac's encoder takes (#295), and at most 4096 × 4096 × 4
    /// bytes (64 MiB) if macOS keeps the whole backing (not measured).
    static let backingFloor = 3072
    static let backingCap = 4096

    /// The backing a display made at `made` gets: its own pixels; and, when it follows a device (This device: `follows`),
    /// a square of the longest side among it and `devices` (each connected device's This device size, either way round:
    /// each may turn), at least `backingFloor` and at most `backingCap`, never less than its own pixels each way. A
    /// person's chosen size or the main display's never follows, so it is made as every display Sill made: its own pixels.
    static func backing(made: Size, devices: [Size], follows: Bool) -> Backing {
        let own = Backing(wide: made.widthPt * made.scale, high: made.heightPt * made.scale)
        guard follows else { return own }
        let longest = ([made] + devices).map { max($0.widthPt, $0.heightPt) * $0.scale }.max() ?? 0
        let side = min(backingCap, max(backingFloor, longest))
        return Backing(wide: max(own.wide, side), high: max(own.high, side))
    }

    /// Whether `size`'s pixels fit `backing` (a turn landing at 1x first takes the same pixels: P2c).
    static func fits(_ size: Size, _ backing: Backing) -> Bool {
        size.widthPt * size.scale <= backing.wide && size.heightPt * size.scale <= backing.high
    }

    /// What one follow does.
    enum FollowStep: Equatable {
        /// The display is that size already.
        case nothing
        /// The Mac is locked: nothing changes the displays at a locked screen (plan §2 and §10); asked again at the unlock.
        case later
        /// The live display takes it (`InPlace`).
        case inPlace
        /// Its pixels do not fit the backing it was made with: the next one made has it.
        case beyondBacking
        /// Removed and made again at the new size, its windows kept (DesktopWindowLedger; phase 3).
        case remake
        /// Left as it is: the next one made has the new size.
        case nextMake
    }

    /// How the display at `display`, whose backing is `backing`, follows the size `to` in the way `way`: nothing locked;
    /// in place only for a device that sends its room (`sendsRoom`: every build from phase 2b; a device before it, 0.6.2
    /// among them, sends its panel, which may change as its own controls come and go, and is taken at the next make, as
    /// before), and only inside the backing; the headless display (the Mac's only screen) never removed and made again.
    static func followStep(to: Size, display: Size, backing: Backing, sendsRoom: Bool, way: FollowWay, headless: Bool,
                           locked: Bool) -> FollowStep {
        if to == display { return .nothing }
        if locked { return .later }
        switch way {
        case .nextMake: return .nextMake
        case .newModes:
            guard sendsRoom else { return .nextMake }
            return fits(to, backing) ? .inPlace : .beyondBacking
        case .remake: return headless ? .nextMake : .remake
        }
    }

    /// The matched device's room over time, and when the display takes it (plan §5): once the room has kept a new size for
    /// `settle` (1 s), and at most once every `spacing` (3 s) from the display's make or its last follow; a room that comes
    /// back to the size taken within the settle changes nothing, and the newest size wins. A size here is `device`'s for
    /// the room, so a change too small to change the display is none. The room is Full Screen's, so Sill's controls, its
    /// drawer, Settings or the keyboard coming and going never change it. Times are seconds on one clock.
    struct Follow: Equatable {
        static let settle: Double = 1
        static let spacing: Double = 3

        /// The size the display was made at, or last took (or left for its next make).
        private(set) var taken: Size
        /// A size the room has had since `since`, not yet taken.
        private(set) var pending: Size?
        private(set) var since: Double = 0
        /// The display's make or its last follow.
        private(set) var lastChange: Double

        init(made size: Size, at now: Double) {
            taken = size
            lastChange = now
        }

        /// The matched device's room at `now`, as a display size (each of its viewports).
        mutating func saw(_ size: Size, at now: Double) {
            if size == taken { pending = nil; return }
            if size != pending { pending = size; since = now }
        }

        enum Due: Equatable { case nothing, wait(until: Double), follow(Size) }

        /// Whether a follow is due at `now`: the size to follow to, or when to look again.
        func due(now: Double) -> Due {
            guard let pending else { return .nothing }
            let ready = max(since + Self.settle, lastChange + Self.spacing)
            return now >= ready ? .follow(pending) : .wait(until: ready)
        }

        /// The follow to `size` was done at `now` (or left for the next make: `FollowStep.nextMake`); a newer size the room
        /// has meanwhile stays pending.
        mutating func took(_ size: Size, at now: Double) {
            taken = size
            if pending == size { pending = nil }
            lastChange = now
        }
    }

    /// Why a follow changes the size: the device it is for turned, its room changed otherwise, or another device is now
    /// the one it is for (plan §5's matched device: it stepped onto it, or the one it was for left).
    enum FollowWhy: Equatable { case turned, room, device }

    static func followWhy(from: Size, to: Size, newDevice: Bool) -> FollowWhy {
        newDevice ? .device : (to == from.turned ? .turned : .room)
    }

    /// One follow in place, step by step: P2b's and P2c's way as a machine the coordinator drives (a Mac's display through
    /// VirtualDisplay; a test host's said one through `TestDisplay`). Each call takes what the display reads now (its
    /// points and scale, as CoreGraphics has them; nil while it reads none) and says what to do next:
    /// 1. `applySettings:` with the size alone (`apply`);
    /// 2. the display changes: at the size at 2x, done (a size of its own orientation); at the size's pixels at 1x (a
    ///    turn), wait until macOS lists the size at 2x usable for the desktop, then switch to it with CoreGraphics
    ///    (`switchTo`), and wait until it reads the size at 2x;
    /// 3. a step refused (applySettings: NO, the switch's complete not 0, the 2x mode never listed), late (`landWait`,
    ///    `listWait`, `switchWait`) or landing elsewhere: the same two steps back to `from`, unless it reads `from` at 2x
    ///    already (`fellBack`: the size waits for the next make, the letterbox as before);
    /// 4. the way back refused or late too: `remove` (the display goes, and the next step makes it again): a display is
    ///    never left at 1x, nor at a size Sill did not ask for.
    /// Times are seconds on one clock; `ms` counts from `started`.
    struct InPlace: Equatable {
        /// How long each step may take (on macOS 27.2.1: 0.31 to 0.37 s from applySettings:'s call to the display's change,
        /// the 2x mode listed as it lands, 0.33 s from the switch to 2x; P2b and P2c), about five times that.
        static let landWait = 2.0       // after applySettings: answered, for the display to change
        static let listWait = 1.0       // after a 1x landing, for macOS to list the 2x mode usable
        static let switchWait = 1.5     // after the switch answered, for the display at 2x

        let from: Size
        let to: Size
        let started: Double
        /// The size asked for now: `to`, then `from` on the way back.
        private(set) var goal: Size
        private(set) var phase: Phase = .apply
        private(set) var deadline: Double = .infinity
        /// What the display read when the step's `applySettings:` was sent.
        private(set) var before: Size?
        /// Why it fell back, once it does.
        private(set) var failure: Failure?
        /// What it did, in words, for the log's detail line (`traceLine`).
        private(set) var trace: [String] = []

        enum Phase: Equatable { case apply, land, listing, switchAsked, switching, ended }

        enum Failure: Equatable {
            /// applySettings: answered NO (or the call threw).
            case refused
            /// The display never changed.
            case late
            /// It changed to a size other than the one asked for, or its pixels at 1x (nil: CoreGraphics read none).
            case elsewhere(Size?)
            /// Its 2x mode was never listed usable for the desktop.
            case notListed
            /// CoreGraphics refused the switch (P2b's steps 0 and f: complete 1001).
            case switchRefused(Int32)
            /// The switch answered, and the display never reached 2x.
            case switchLate
        }

        enum Action: Equatable {
            /// applySettings: with this size alone.
            case apply(Size)
            /// A CoreGraphics switch to this size at 2x, as macOS lists it usable for the desktop.
            case switchTo(Size)
            /// Look again a moment later.
            case wait
            /// At `to`, at 2x.
            case done(ms: Int)
            /// Back at `from`, at 2x: the size waits for the next make.
            case fellBack(Failure, ms: Int)
            /// Neither: the display goes.
            case remove(Failure)
        }

        init(from: Size, to: Size, at now: Double) {
            self.from = from
            self.to = to
            started = now
            goal = to
            before = from
        }

        /// The first action: `to` alone.
        var first: Action { .apply(to) }

        /// The goal's pixels at 1x, where macOS lands a turn first (P2c: 800×1218 lands at 1600×2436 @1×).
        var goalAtOneX: Size { Size(widthPt: goal.widthPt * goal.scale, heightPt: goal.heightPt * goal.scale, scale: 1) }

        /// applySettings: answered (`answered`: YES; false for NO or a throw); the display reads `reading` now.
        mutating func applied(_ answered: Bool, reading: Size?, at now: Double) -> Action {
            trace.append("applySettings: with \(Self.words(goal)) alone answered \(answered ? "YES" : "NO") at +\(ms(now)) ms")
            guard answered else { return fail(.refused, reading: reading, at: now) }
            phase = .land
            deadline = now + Self.landWait
            return saw(reading, listed: false, at: now)
        }

        /// The display reads `reading` now; `listed`: macOS lists the goal at 2x usable for the desktop (asked only while
        /// it reads the goal's pixels at 1x).
        mutating func saw(_ reading: Size?, listed: Bool, at now: Double) -> Action {
            switch phase {
            case .apply, .switchAsked, .ended:
                return .wait
            case .land:
                if reading == goal { return reached(at: now) }
                if reading == goalAtOneX {
                    trace.append("at \(Self.words(goalAtOneX)) at +\(ms(now)) ms")
                    phase = .listing
                    deadline = now + Self.listWait
                    return listed ? switchNow(at: now) : .wait
                }
                if reading == nil || reading == before { return now >= deadline ? fail(.late, reading: reading, at: now) : .wait }
                return fail(.elsewhere(reading), reading: reading, at: now)
            case .listing:
                if reading == goal { return reached(at: now) }
                if reading != goalAtOneX, reading != nil { return fail(.elsewhere(reading), reading: reading, at: now) }
                if listed { return switchNow(at: now) }
                return now >= deadline ? fail(.notListed, reading: reading, at: now) : .wait
            case .switching:
                if reading == goal { return reached(at: now) }
                return now >= deadline ? fail(.switchLate, reading: reading, at: now) : .wait
            }
        }

        /// The switch answered: CoreGraphics' complete code (0: success), or nil when the 2x mode was not found listed and
        /// nothing was asked; the display reads `reading` now.
        mutating func switched(_ complete: Int32?, reading: Size?, at now: Double) -> Action {
            guard phase == .switchAsked else { return .wait }
            guard let complete else { return fail(.notListed, reading: reading, at: now) }
            trace.append("switch to \(Self.words(goal)) @2×: complete \(complete) at +\(ms(now)) ms")
            guard complete == 0 else { return fail(.switchRefused(complete), reading: reading, at: now) }
            phase = .switching
            deadline = now + Self.switchWait
            return saw(reading, listed: true, at: now)
        }

        private mutating func switchNow(at now: Double) -> Action {
            trace.append("\(Self.words(goal)) @2× listed usable at +\(ms(now)) ms")
            phase = .switchAsked
            return .switchTo(goal)
        }

        private mutating func reached(at now: Double) -> Action {
            phase = .ended
            trace.append("at \(Self.words(goal)) @2× at +\(ms(now)) ms")
            if goal == to { return .done(ms: ms(now)) }
            return .fellBack(failure ?? .late, ms: ms(now))
        }

        /// A step refused, late or elsewhere: on the way to `to`, back to `from` (nothing to do when it reads `from` at 2x
        /// already); on the way back, the display goes.
        private mutating func fail(_ why: Failure, reading: Size?, at now: Double) -> Action {
            trace.append("\(Self.failureWords(why)) at +\(ms(now)) ms")
            guard goal == to else {
                phase = .ended
                return .remove(failure ?? why)
            }
            failure = why
            if reading == from {
                phase = .ended
                return .fellBack(why, ms: ms(now))
            }
            goal = from
            phase = .apply
            before = reading
            deadline = .infinity
            return .apply(from)
        }

        func ms(_ now: Double) -> Int { Int(((now - started) * 1000).rounded()) }

        static func words(_ s: Size) -> String { "\(s.widthPt)×\(s.heightPt)" + (s.scale == 1 ? " @1×" : "") }

        /// A failure in words: "macOS refused the switch to it (complete 1001)".
        static func failureWords(_ f: Failure) -> String {
            switch f {
            case .refused: return "applySettings: answered NO"
            case .late: return "the display did not change in time"
            case .elsewhere(let s): return "the display went to " + (s.map(words) ?? "no mode") + " instead"
            case .notListed: return "macOS did not list its 2x mode as usable"
            case .switchRefused(let code): return "macOS refused the switch to its 2x mode (complete \(code))"
            case .switchLate: return "the switch did not land in time"
            }
        }

        /// The detail line a follow in place prints before its outcome: "Virtual Desktop: in place: applySettings: with
        /// 800×1218 alone answered YES at +285 ms; at 1600×2436 @1× at +318 ms; …". `said`: a test host's, nothing made.
        func traceLine(said: Bool) -> String {
            "Virtual Desktop: in place" + (said ? " (TEST ONLY: said, the display as the probes measured it)" : "") + ": "
                + trace.joined(separator: "; ") + "."
        }
    }

    /// The follow's line once it is decided or done: in place ("Virtual Desktop: iPad mini turned; followed in place in 650
    /// ms: 800×1218 pt @2× at 60 Hz."), fallen back ("…; not followed in place: macOS refused the switch to its 2x mode
    /// (complete 1001); back at 1218×800 pt @2× in 980 ms; the next one is made at 800×1218 pt."), removed (the way back
    /// failed too: made again at the size by the Desktop that still shows its stop), beyond the backing, at the next make (no way in place, a device before phase 2b), made again (phase 3);
    /// nil when nothing is done. `display` names whose (the headless display's: "Headless display"); `device` the device
    /// it is for now.
    static func followLine(_ display: String = "Virtual Desktop", device: String, why: FollowWhy, from: Size, to: Size,
                           step: FollowStep, outcome: InPlace.Action? = nil, hz: Int? = nil, backing: Backing? = nil) -> String? {
        let what: String
        switch why {
        case .turned: what = "\(device) turned"
        case .room: what = "\(device) changed its room"
        case .device: what = "\(device) shows it now"
        }
        let size = "\(to.widthPt)×\(to.heightPt) pt"
        let next = "the next one is made at \(size)."
        switch step {
        case .nothing, .later: return nil
        case .inPlace:
            switch outcome {
            case .done(let ms)?:
                return "\(display): \(what); followed in place in \(ms) ms: \(size) @\(to.scale)×" + (hz.map { " at \($0) Hz" } ?? "") + "."
            case .fellBack(let f, let ms)?:
                return "\(display): \(what); not followed in place: \(InPlace.failureWords(f)); back at \(from.widthPt)×\(from.heightPt) pt "
                    + "@\(from.scale)× in \(ms) ms; \(next)"
            case .remove(let f)?:
                return "\(display): \(what); not followed in place: \(InPlace.failureWords(f)), and it did not come back to "
                    + "\(from.widthPt)×\(from.heightPt) pt @\(from.scale)×; removed it: \(next)"
            default:
                return nil
            }
        case .beyondBacking:
            let b = backing.map { " (\($0.wide)×\($0.high) px)" } ?? ""
            return "\(display): \(what); \(size) @\(to.scale)× is beyond the backing it was made with\(b); \(next)"
        case .remake: return "\(display): \(what); made again at \(size)."
        case .nextMake: return "\(display): \(what); \(next)"
        }
    }

    // MARK: TEST ONLY: a display as the probes measured one (a test host's said Virtual Desktop, and the check)

    /// TEST ONLY: what SILL_TEST_VD_STEPS makes a test host's display do instead of what the probes measured:
    /// `switchRefused`, every CoreGraphics switch answers complete 1001 and changes nothing (as P2b's steps 0 and f);
    /// `stuck`, once a switch was refused no `applySettings:` lands any more (the way back late: the display goes);
    /// `late`, no `applySettings:` lands at all (the display never changes: it falls back where it is).
    struct TestKnobs: Equatable {
        var switchRefused = false
        var stuck = false
        var late = false
        init(switchRefused: Bool = false, stuck: Bool = false, late: Bool = false) {
            self.switchRefused = switchRefused; self.stuck = stuck; self.late = late
        }
    }

    static let testStepsVariable = "SILL_TEST_VD_STEPS"

    /// TEST ONLY: SILL_TEST_VD_STEPS (`switch-refused`, `stuck`, `late`, separated by commas) on a test host whose
    /// Virtual Desktop is only said (`on`: SILL_TEST_VIRTUAL_DESKTOP took): its knobs and the line it prints at start; a
    /// word it does not know, or the variable without the hook, is a line and no knob.
    static func testSteps(environment: [String: String], on: Bool) -> (knobs: TestKnobs, line: String?) {
        guard let raw = environment[testStepsVariable], !raw.isEmpty else { return (TestKnobs(), nil) }
        guard on else { return (TestKnobs(), "\(testStepsVariable) ignored: it needs a test host's Virtual Desktop (\(VirtualDesktopLife.testVariable)=1).") }
        var k = TestKnobs()
        var unknown: [String] = []
        for word in raw.split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) {
            switch word {
            case "switch-refused": k.switchRefused = true
            case "stuck": k.stuck = true
            case "late": k.late = true
            default: unknown.append(word)
            }
        }
        guard unknown.isEmpty else {
            return (TestKnobs(), "\(testStepsVariable)=\(raw) ignored: it takes switch-refused, stuck and late, separated by commas.")
        }
        return (k, "Test Virtual Desktop: its said display's steps: \(raw) (\(testStepsVariable)), not as the probes measured them.")
    }

    /// TEST ONLY: a display of Sill's as Noah's probes measured one (macOS 27.2.1; P2, P2b, P2c), for a test host's said
    /// Virtual Desktop and this policy's check. `applySettings:` with one size answers YES and, `lands` (0.32 s) later: a
    /// size of the made display's orientation (its physical size's) at 2x; another at its pixels at 1x, the 2x mode then
    /// listed usable; a size beyond the backing never. A CoreGraphics switch to the listed 2x mode lands `lands` later. A
    /// change asked while one is on its way replaces it. `knobs` make a step fail.
    struct TestDisplay: Equatable {
        static let lands = 0.32

        let made: Size
        let backing: Backing
        let knobs: TestKnobs
        /// What it reads now (once `read` has let what was on its way land).
        private(set) var now: Size
        /// The 2x mode macOS lists usable after a 1x landing.
        private(set) var listed: Size?
        private var pending: (size: Size, at: Double, lists: Size?)?
        private var refused = false

        init(made: Size, backing: Backing, knobs: TestKnobs = TestKnobs()) {
            self.made = made
            self.backing = backing
            self.knobs = knobs
            now = made
        }

        static func == (a: TestDisplay, b: TestDisplay) -> Bool {
            a.made == b.made && a.backing == b.backing && a.knobs == b.knobs && a.now == b.now && a.listed == b.listed
                && a.pending?.size == b.pending?.size && a.pending?.at == b.pending?.at && a.refused == b.refused
        }

        /// What it reads at `t`.
        mutating func read(at t: Double) -> Size {
            if let p = pending, t >= p.at {
                now = p.size
                listed = p.lists
                pending = nil
            }
            return now
        }

        /// Whether macOS lists `size` at 2x usable for the desktop at `t`.
        mutating func lists(_ size: Size, at t: Double) -> Bool {
            _ = read(at: t)
            return listed == size
        }

        /// applySettings: with `size` alone at `t`: YES, and what it lands at on its way.
        mutating func apply(_ size: Size, at t: Double) -> Bool {
            _ = read(at: t)
            guard !knobs.late, !(knobs.stuck && refused), VirtualDesktopSize.fits(size, backing) else { return true }
            if (size.widthPt >= size.heightPt) == (made.widthPt >= made.heightPt) {
                pending = (size, t + Self.lands, nil)
            } else {
                pending = (Size(widthPt: size.widthPt * size.scale, heightPt: size.heightPt * size.scale, scale: 1), t + Self.lands, size)
            }
            return true
        }

        /// A CoreGraphics switch to `size` at 2x at `t`: the complete code (0 when it is listed and `switchRefused` is
        /// off), or nil when it is not listed (nothing asked).
        mutating func switchTo(_ size: Size, at t: Double) -> Int32? {
            _ = read(at: t)
            guard listed == size else { return nil }
            if knobs.switchRefused { refused = true; return 1001 }
            pending = (size, t + Self.lands, listed)
            return 0
        }
    }
}
