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
/// Pure (CoreGraphics); checked by Tests/checks/virtual-desktop.
enum VirtualDesktopSize {
    /// A display's size in points and its scale (pixels a point).
    struct Size: Equatable {
        var widthPt: Int
        var heightPt: Int
        var scale: Int
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
}
