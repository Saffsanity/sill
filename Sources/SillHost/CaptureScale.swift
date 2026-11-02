import CoreGraphics
import Foundation

/// The pixel scale a capture runs at: the Resolution knob, never more than the display's own.
///
/// Found 2026-10-27 on a Mac whose main display is an external 2560×1440 at 1x (Sill.app from
/// 74d099c2): a window picked there showed in the top-left quarter of the device's picture, black
/// around it, and Aa changed nothing; the Desktop looked right. The knob (HostConfig's
/// `captureScale`, or `awayCaptureScale` while the away pair runs: 2 Retina, 1 Standard; 1 at most
/// on the software encoder) asks for that many pixels a point, and ScreenCaptureKit draws a window
/// at its display's own pixel scale and never scales it up: asked for 2234×1220 of a 1117×610-point
/// window on that display, it drew the window's 1117×610 pixels into the top-left of the buffer and
/// left the rest black (Sill.log: "Capture started: 2234×1220 … filter (1117.0, 610.0) scale 1.0").
/// A display it does scale up to fill the buffer, so the Desktop looked right, at four times the
/// pixels to encode for nothing (5120×2880 for 2560×1440 points, where the encoder ran at 1–2 fps
/// that night). So a capture runs at the lesser of the knob and the display's own scale: on a 1x
/// display Retina and Standard both capture at 1x and nothing is upscaled; on a 2x display nothing
/// changes, and Standard there still captures at 1x (ScreenCaptureKit scales a 2x picture down).
///
/// The display's scale is ScreenCaptureKit's own for the filter being captured,
/// `SCContentFilter.pointPixelScale` (macOS 14), not one worked out here from the display's
/// CGDisplayMode (its pixel width over its point width). For one display both read 1 or 2, but only
/// the filter's is the scale ScreenCaptureKit draws that very content at: a window across two
/// displays counts as on the one ScreenCaptureKit picks for it (the one it is mostly on), and no
/// rule of Sill's own can disagree with that pick (one that did would ask for a size the capture
/// never fills, or restart the stream at every poll). It is what the capture line has always
/// printed ("scale 1.0" above). Sill's own virtual display is made at 2x (VirtualStage's
/// `VirtualDisplay(…, scale: 2)`, at a size macOS keeps at 2x: VirtualDisplaySize), so a window staged
/// there captures at the knob, as before.
///
/// Pure: Foundation and CoreGraphics, checked on its own with swiftc (Tests/checks/capture-scale).
enum CaptureScale {
    /// The scale of Sill's own virtual display, which VirtualStage makes at 2x (HiDPI): what a staged
    /// window's capture is held to, decided before the display exists. macOS kept it at 2x for every
    /// size but one with both sides under 800 points, five times in Sill.log an 800×832-point display at
    /// 1x, where a staged window was captured at the knob, scaled up; VirtualDisplaySize keeps every
    /// side at 800 or more since 2026-10-27. VirtualStage still keeps a display that comes up at
    /// another mode ("online but not at … @2×"), and a window staged there still captures at the knob.
    static let virtualDisplay: CGFloat = 2

    /// The pixels a point that a capture of a source on a display of scale `displayScale` runs at:
    /// the knob, held to the display's own. Nil (no display: the test pattern), or a scale that is
    /// none (0, negative, not finite), keeps the knob.
    static func effective(knob: CGFloat, displayScale: CGFloat?) -> CGFloat {
        guard let d = usable(displayScale) else { return knob }
        return min(knob, d)
    }

    /// A filter's `pointPixelScale` (a Float) as a display scale: nil when it is none.
    static func displayScale(pointPixelScale: Float) -> CGFloat? {
        usable(CGFloat(pointPixelScale))
    }

    /// One side of a window's capture in pixels, even (HEVC wants even sides): the window's `points`
    /// on that side at the capture's scale (`effective`). What `select` asks ScreenCaptureKit for a
    /// window in regular mode, and so what `windowsChanged` compares the running encoder with
    /// (`windowNeedsRestart`).
    ///
    /// ScreenCaptureKit draws a window at its display's own scale into the top-left of the buffer and
    /// only ever scales it down to fit (`SCStreamConfiguration.scalesToFit` left false: "When false,
    /// the output only scales down", SCStream.h). A window captured at its display's own scale is
    /// therefore drawn 1:1, and an odd side rounds up: a 1117×610-point window on a 1x display asks
    /// 1118×610 and is drawn whole, one black column past its right edge, where 1116×610 (`evenPixels`,
    /// every capture's rule until 2026-10-27) had ScreenCaptureKit shrink its 1117 columns into 1116,
    /// up to half a pixel of blur mid-picture, where a text stem is one pixel wide. Odd sides are
    /// routine at Aa 1x (Sill.log: 1117×610, 818×565, 728×535, 377×235) and in any window sized by
    /// hand. A whole number of points at 2x is always even; a window at a half point rounds up the
    /// same way. A device draws the frame aspect-fit on black: the column joins a letterbox beside it,
    /// or is a black hairline at the picture's edge where the frame fills the panel. A device's
    /// position lands as the same fraction of the window (InputLanding), so at most a pixel nearer
    /// the window's origin than the frame shows it, at the far side. Held below its display's scale
    /// (Standard on a 2x display) a window is scaled down whatever the buffer, so it rounds down as
    /// before; so does one with no display scale. A display (scaled to fill any buffer), a staged
    /// window's crop of Sill's virtual display and the test pattern keep `evenPixels`.
    static func windowPixels(_ points: CGFloat, knob: CGFloat, displayScale: CGFloat?) -> Int {
        let e = effective(knob: knob, displayScale: displayScale)
        guard let d = usable(displayScale), e == d else { return evenPixels(points * e) }
        // Within a thousandth of a pixel of a whole number is that number: no black column for a
        // product's rounding.
        let whole = Int((points * e - 0.001).rounded(.up))
        return whole + (whole & 1)
    }

    /// `windowPixels` for both sides of a window `points` big.
    static func windowSize(_ points: CGSize, knob: CGFloat, displayScale: CGFloat?) -> (width: Int, height: Int) {
        (windowPixels(points.width, knob: knob, displayScale: displayScale),
         windowPixels(points.height, knob: knob, displayScale: displayScale))
    }

    /// Whether a window whose capture runs at `encoder` pixels needs a new pipeline now that it is
    /// `points` big (`windowsChanged`, at each catalog poll): only when the size `select` would ask
    /// for it now differs, by the same rule. So a window whose odd side was rounded up (1117 points,
    /// asked 1118) never restarts at every poll, and a change within the rounding (1117 to 1118
    /// points) needs none: the buffer already holds the window whole.
    static func windowNeedsRestart(encoder: (width: Int, height: Int), points: CGSize, knob: CGFloat,
                                   displayScale: CGFloat?) -> Bool {
        let want = windowSize(points, knob: knob, displayScale: displayScale)
        return want.width != encoder.width || want.height != encoder.height
    }

    /// One pixel of a display of scale `displayScale`, in points: half a point at 2x, a point at 1x,
    /// and a point when there is no scale (InputLanding's last row and column).
    static func pixel(displayScale: CGFloat?) -> CGFloat {
        1 / (usable(displayScale) ?? 1)
    }

    private static func usable(_ s: CGFloat?) -> CGFloat? {
        guard let s, s.isFinite, s > 0 else { return nil }
        return s
    }

    /// The capture line's words for its scale ("Capture started: … scale 1.0, capturing at 1x, the
    /// display's own (2x asked)"): "capturing at 2x", and when the display held the knob down, what
    /// the knob asked for.
    static func words(knob: CGFloat, displayScale: CGFloat?) -> String {
        let e = effective(knob: knob, displayScale: displayScale)
        let base = "capturing at \(times(e))"
        return e < knob ? base + ", the display's own (\(times(knob)) asked)" : base
    }

    /// 1 → "1x", 2 → "2x", 1.5 → "1.5x".
    static func times(_ s: CGFloat) -> String {
        s.isFinite && s == s.rounded() && abs(s) < 1_000 ? "\(Int(s))x" : "\(Double(s))x"
    }
}

/// The size of Sill's virtual display in points, as VirtualStage asks VirtualDisplay for it: no side
/// under 800 points, the least macOS keeps at 2x, the scale a staged window's capture counts on
/// (`CaptureScale.virtualDisplay`).
///
/// Found in Sill.log (2026-09-26 to 2026-10-15): of every display Sill made, five came up at 1x, each
/// asked with both sides under 800 points, 754×784 (four times) or 762×792: the envelope of an iPhone
/// held upright, its picture 377 or 381 points wide, doubled for Aa's smallest step, with the menu bar.
/// Each came up at 800×832 points at 1x. macOS listed the mode asked for ("754×784 pt @ 1508×1568 px"),
/// VirtualDisplay.waitUntilOnline asked for it every half second, and the display stayed at 1x until
/// the stage's 3 s wait ran out ("Virtual display is online but not at 754×784 @2×: backing 800×832
/// px", "online 3312 ms"): the pick waited 3 s more, and a window staged there was captured at the knob
/// from a 1x display, scaled up ("Capture started: 1480×768 … filter (800.0, 832.0) scale 1.0").
/// Every display with a side of 800 points or more came up at 2x within about half a second, one
/// side under 800 or not (754×979, 838×792, 1000×784, 900×800, 848×878). The main display's scale
/// played no part: those five were made beside the Mac's own Retina display, and on 2026-10-27,
/// beside an external 2560×1440 display at 1x, every one came up at 2x ("filter (2560.0, 2264.0)
/// scale 2.0"). So every side is held to 800 points or more, which macOS kept at 2x whatever the
/// other side: the smallest display Sill makes is 800×830 (800 and a 30-point menu bar).
///
/// Pure, with CaptureScale (Tests/checks/capture-scale).
enum VirtualDisplaySize {
    /// The least side, in points.
    static let minSide: CGFloat = 800
    /// 4096 keeps the 2x backing store at or under 8192 pixels, VirtualDisplay's ceiling.
    static let maxSide: CGFloat = 4096

    /// Each side held to `minSide`…`maxSide`.
    static func clamp(_ s: CGSize) -> CGSize {
        CGSize(width: min(max(s.width, minSide), maxSide), height: min(max(s.height, minSide), maxSide))
    }

    /// The display's size below its menu bar that fits a device's panel of `panel` points at every Aa
    /// scale and in both orientations: a square of the panel's longer edge ÷ 0.5 (the slider's smallest
    /// step). No panel (no viewport yet), or one with no area: the window's own size. Held by `clamp`
    /// either way (VirtualStage.envelope).
    static func envelope(panel: CGSize?, windowSize: CGSize) -> CGSize {
        guard let panel, panel.width > 0, panel.height > 0 else { return clamp(windowSize) }
        let side = ceil(max(panel.width, panel.height) / 0.5)
        return clamp(CGSize(width: side, height: side))
    }

    /// The most a window is asked for on the virtual display, a side: the largest viewport a host takes,
    /// 16384 points at a text scale of 0.25 (ViewportBounds), so the hold changes no size a host asked
    /// for before. Not the display's `maxSide`: the placement fits the window to the display anyway
    /// (VirtualStage.prepare's `dest`), and a full-screen window's crop takes the shape of this size,
    /// which is the panel's only while no side is held. Held at 4096, a 2560×1400 panel at 0.5x (an iPad's
    /// Stage Manager window on a large display) was asked 4096×2800, and a full-screen window's crop came
    /// out 1.46:1 for a 1.83:1 panel, black bars on the device (the review of finding 4, 2026-10-29).
    static let maxWindowSide: CGFloat = 65536

    /// The size a window should have on the virtual display, in Mac points: a device's panel of `panel`
    /// points divided by its text scale (none, or one that is not a positive number, counts as 1), each
    /// side held to 1…`maxWindowSide` (VirtualStage.windowSize). Until 2026-10-29 nothing held it: a
    /// viewport of 1e300 points, or a scale of 1e-300, gave a side no Int holds, and the "insists on …"
    /// line's Int() trapped (security scan, finding 4; hosts now refuse such a viewport, ViewportBounds,
    /// and the line prints through ViewportBounds.whole). Every viewport a host takes is asked for as
    /// before, but for a side under half a point, now 1 rather than 0. No panel, or one whose sides are
    /// not positive numbers: the window's own size, as before.
    static func windowSize(panel: CGSize?, scale: CGFloat?, own: CGSize) -> CGSize {
        guard let panel, panel.width.isFinite, panel.height.isFinite, panel.width > 0, panel.height > 0 else { return own }
        let s = scale.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 1
        return CGSize(width: min(max((panel.width / s).rounded(), 1), maxWindowSide),
                      height: min(max((panel.height / s).rounded(), 1), maxWindowSide))
    }
}

/// HEVC wants even sides: a capture's size in pixels rounded down to even. Every capture's rule until
/// 2026-10-27, and still a display's, a staged window's crop's and the test pattern's; a window that
/// ScreenCaptureKit draws 1:1 rounds up instead (`CaptureScale.windowPixels`). Here rather than in
/// WindowCapture.swift, which needs ScreenCaptureKit, so the check compiles it.
func evenPixels(_ v: CGFloat) -> Int { Int(v.rounded(.down)) & ~1 }

/// Where a device's position lands on the Mac: its fraction of the streamed source's rectangle, at
/// most on the rectangle's last row and column of pixels.
///
/// A device sends positions as fractions of the picture, 0 to 1 with both ends in: the portrait
/// trackpad's cursor stops at 1 (PadCursor.clamped), and the iPad's own pointer, a Pencil or a drag
/// past the picture's edge is held to it (InputOverlay.normalized). Mapped as `minY + y × height`,
/// the bottom edge is `rect.maxY`, the row past the last: no row of the source (CGRect's
/// containment and PointerControl.fraction's inside test both leave it out) but the next display's
/// first, or what lies below a window. A drag to the bottom of the Desktop's picture of a 2560×1440
/// display was posted at y = 1440.0, one row past the last (1439): where the window server puts the
/// cursor then is its choice (onto a display arranged below, if there is one), never the last row
/// for certain, and an auto-hidden Dock shows only for a pointer at the display's bottom edge
/// (Noah, 2026-10-27: it never came up). So each fraction is held to 0…1 and lands no further than
/// `maxX - 1/scale` and `maxY - 1/scale`, the top-left of the last pixel column and row at the
/// display's own scale (`displayScale`, as CaptureScale has it; one point when there is none): on a
/// 1x display 1439 of 1440, on a 2x one 981.5 of 982, Sill's virtual display 2x.
///
/// Pure: Foundation and CoreGraphics, checked with CaptureScale (Tests/checks/capture-scale).
enum InputLanding {
    /// `x` and `y` as fractions of `rect` (top-left global points, InputInjector's), held to 0…1 (a
    /// NaN to 0) and to the last pixel column and row, never left of or above the rectangle (one
    /// narrower than a pixel keeps its origin).
    static func point(x: Double, y: Double, in rect: CGRect, displayScale: CGFloat?) -> CGPoint {
        let pixel = CaptureScale.pixel(displayScale: displayScale)
        let px = rect.minX + CGFloat(unit(x)) * rect.width
        let py = rect.minY + CGFloat(unit(y)) * rect.height
        return CGPoint(x: max(rect.minX, min(px, rect.maxX - pixel)),
                       y: max(rect.minY, min(py, rect.maxY - pixel)))
    }

    /// A fraction held to 0…1; NaN (which no JSON carries) to 0.
    static func unit(_ v: Double) -> Double {
        v.isNaN ? 0 : min(max(v, 0), 1)
    }
}
