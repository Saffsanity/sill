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
/// `VirtualDisplay(…, scale: 2)`), so a window staged there captures at the knob, as before.
///
/// Pure: Foundation and CoreGraphics, checked on its own with swiftc (Tests/checks/capture-scale).
enum CaptureScale {
    /// The scale of Sill's own virtual display, which VirtualStage makes at 2x (HiDPI): what a staged
    /// window's capture is held to, decided before the display exists. VirtualStage keeps a display
    /// that came up at another mode ("online but not at … @2×": five times in Sill.log, each an
    /// 800×832-point display at 1x), and a window staged on it still captures at the knob, scaled up,
    /// as it always has.
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
