import CoreGraphics

/// Where the streamed picture is drawn in its pane: as the video layer's `resizeAspect` draws it (the largest rectangle of
/// the picture's shape inside the pane, in its middle), except where the picture is the pane's own pixels less a hairline,
/// which is drawn one picture pixel on one screen pixel (2026-11-25).
///
/// Why: an iPhone's Virtual Desktop is made pixel for pixel (Noah, 2026-11-24: "middle one for iPhones"): its picture's
/// space counted in the iPhone's pixels, made as a 2x desktop of that many pixels. A 2x desktop has an even number of
/// pixels a side, and an iPhone's side can be odd (an iPhone 15 Pro upright with Full Screen: 393 × 793 points, 1179 ×
/// 2379 pixels; its desktop 589 × 1189 points, 1178 × 2378 pixels). Fitted aspect-fit, that picture would be scaled by
/// 1179/1178, a hair, which resamples every pixel and softens a one-pixel text stem where it lands between two. So a
/// picture whose pixels are at most `spare` fewer than the pane's each way, and never more, is drawn at its own size from
/// the pane's top-left pixel, and the spare pixel is a hairline at its right or bottom edge. Every other picture (a
/// window, a desktop larger than the pane, an iPad's) is fitted as before; one that already fills the pane exactly is the
/// same either way.
///
/// One rule for the picture's drawing and for every touch: the stream view's frame (`ZoomedStreamView`), the pointer
/// sprite (`HEVCDisplayView`) and a touch's place in the picture (`InputOverlay`) all ask `rect`. Pure (CoreGraphics),
/// checked by Tests/checks/picture-fit.
enum PictureFit {
    /// The most pixels a side the picture may be short of its pane and still be drawn one for one: an odd side's one,
    /// and a pane whose points are not whole pixels' fraction.
    static let spare: CGFloat = 2

    /// Whether a picture of `videoSize` pixels is drawn one for one in a pane of `bounds` on a screen of `screenScale`
    /// pixels a point: each side at most the pane's pixels and at most `spare` fewer. False with no picture, no pane or
    /// no scale.
    static func oneToOne(in bounds: CGRect, videoSize: CGSize, screenScale: CGFloat?) -> Bool {
        guard let s = screenScale, s.isFinite, s > 0, usable(videoSize), usable(bounds.size) else { return false }
        let pane = CGSize(width: bounds.width * s, height: bounds.height * s)
        // Within a thousandth of a pixel: a pane's points times its scale need not be a whole number.
        let wide = pane.width + 0.001 - videoSize.width, high = pane.height + 0.001 - videoSize.height
        return wide >= 0 && high >= 0 && wide <= spare + 0.002 && high <= spare + 0.002
    }

    /// The rectangle the picture is drawn in, in `bounds`' coordinates: one for one at the pane's top-left (`oneToOne`),
    /// else the largest of its shape in the pane's middle, as `resizeAspect` draws it. `.zero` while the picture's size
    /// is unknown, so a caller can tell "no video" from "top left".
    static func rect(in bounds: CGRect, videoSize: CGSize, screenScale: CGFloat?) -> CGRect {
        guard usable(videoSize), usable(bounds.size) else { return .zero }
        if oneToOne(in: bounds, videoSize: videoSize, screenScale: screenScale), let s = screenScale {
            return CGRect(x: bounds.minX, y: bounds.minY, width: videoSize.width / s, height: videoSize.height / s)
        }
        let scale = min(bounds.width / videoSize.width, bounds.height / videoSize.height)
        let size = CGSize(width: videoSize.width * scale, height: videoSize.height * scale)
        return CGRect(x: bounds.minX + (bounds.width - size.width) / 2,
                      y: bounds.minY + (bounds.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    private static func usable(_ s: CGSize) -> Bool { s.width.isFinite && s.height.isFinite && s.width > 0 && s.height > 0 }
}
