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
/// Following the device (phase 2b, plan §5; `Follow`, `followStep`): the matched device's room, turned, folded or resized,
/// is taken after 1 s steady and at most once every 3 s, in the way probe P2's verdict allows (`followWay`, one line: by
/// default not at all until the display is made again, the one way that rests on nothing unmeasured).
///
/// Pure (CoreGraphics); checked by Tests/checks/virtual-desktop.
enum VirtualDesktopSize {
    /// A display's size in points and its scale (pixels a point).
    struct Size: Equatable {
        var widthPt: Int
        var heightPt: Int
        var scale: Int

        /// The same size a quarter turned: the device held the other way.
        var turned: Size { Size(widthPt: heightPt, heightPt: widthPt, scale: scale) }
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

    // MARK: Following the device (phase 2b, docs/virtual-desktop-plan.md §5 as revised 2026-11-18)

    /// How the Virtual Desktop follows its matched device's room (a turn, the Duo's fold, a Stage Manager window resized,
    /// Full Screen's Room choice changed): the verdict of probe P2 (`Scripts/display-modes-probe/run.sh --make`, on a Mac
    /// at rest; PR #408), which only Noah can run, since it makes a display.
    enum FollowWay: Equatable, CaseIterable {
        /// Not at all: the size waits for the next time the display is made (the plan's "else, in 2b"). It makes the
        /// display with one mode, as every display Sill has made, so it rests on nothing P2 has not measured.
        case nextMake
        /// In place, among the modes it was made with: the room both ways (`otherModes`), switched with public
        /// CoreGraphics (VirtualDisplay.switchMode). P2's "in place by the modes listed at creation: yes".
        case listedModes
        /// In place, the live display given the new mode (VirtualDisplay.applyModes, then switchMode), made with the room
        /// both ways so its backing holds a turn. P2's "new modes on the live display: yes".
        case newModes
        /// Removed and made again at the new size, its windows kept by DesktopWindowLedger (phase 3's way); never the
        /// headless display, the Mac's only screen (plan §2: no display to fall back to).
        case remake
    }

    /// P2's verdict, the one line that chooses (plan §5): `.nextMake` until Noah has run the probe, the way that is safe
    /// without it. P2 "yes" by the listed modes is `.listedModes`, by new modes `.newModes`.
    static let followWay: FollowWay = .nextMake

    /// The modes the Desktop's display is made with besides `size` (VirtualDisplay's `otherModes`): its turn for a way in
    /// place, so a device turning needs no new mode and the backing holds both (VirtualDisplay.maxPixels); none for the
    /// others: one mode, as every display Sill has made.
    static func otherModes(_ size: Size, way: FollowWay) -> [Size] {
        switch way {
        case .listedModes, .newModes: return size.turned == size ? [] : [size.turned]
        case .nextMake, .remake: return []
        }
    }

    /// What one follow does.
    enum FollowStep: Equatable {
        /// The display is that size already.
        case nothing
        /// The Mac is locked: nothing changes the displays at a locked screen (plan §2 and §10); asked again at the unlock.
        case later
        /// The live display switched to a mode it was made with (VirtualDisplay.switchMode).
        case switchMode
        /// The live display given the new mode, then switched to it (VirtualDisplay.applyModes).
        case newModes
        /// Removed and made again at the new size, its windows kept (DesktopWindowLedger).
        case remake
        /// Left as it is: the next one made has the new size.
        case nextMake
    }

    /// How the display at `display`, made with the modes `listed`, follows the room's new size `to` in the way `way`:
    /// nothing locked; the headless display (the Mac's only screen) only in place, never removed and made again.
    static func followStep(to: Size, display: Size, listed: [Size], way: FollowWay, headless: Bool, locked: Bool) -> FollowStep {
        if to == display { return .nothing }
        if locked { return .later }
        switch way {
        case .nextMake: return .nextMake
        case .listedModes: return listed.contains(to) ? .switchMode : .nextMake
        case .newModes: return .newModes
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

    /// The follow's line: "Virtual Desktop: iPad mini turned; 800×1218 pt in place.", "…; the next one is made at 800×1218
    /// pt." (no way in place), "…; made again at …" (`.remake`); nil when nothing is done. `display` names whose (the
    /// headless display's: "Headless display").
    static func followLine(_ display: String = "Virtual Desktop", device: String, from: Size, to: Size, step: FollowStep) -> String? {
        let what = to == from.turned ? "turned" : "changed its room"
        let size = "\(to.widthPt)×\(to.heightPt) pt"
        switch step {
        case .nothing, .later: return nil
        case .switchMode, .newModes: return "\(display): \(device) \(what); \(size) in place."
        case .remake: return "\(display): \(device) \(what); made again at \(size)."
        case .nextMake: return "\(display): \(device) \(what); the next one is made at \(size)."
        }
    }
}
