import CoreGraphics

/// The Full-Screen Viewer's camera (ViewerScreen, docs/iphone-viewer-plan.md): where the Mac's
/// picture sits on an iPhone's whole screen. `zoom` is how far it is magnified beyond fitting the
/// screen (1 fits it, letterboxed; at most `maxZoom`), `center` the point of the frame, as a
/// fraction, that sits at the screen's centre. Pure (CoreGraphics only): `Tests/checks/viewer-camera`.
///
/// The rules: along an axis where the picture is smaller than the screen it is centred; along one
/// where it is larger it never leaves a gap at either end, so the frame's edge stops at the screen's.
/// `center` is written back after every change (`settle`), so it never holds a value the clamp
/// would undo, and a later pan starts from what the screen shows.
struct ViewerCamera: Equatable {
    var zoom: CGFloat = 1
    var center = CGPoint(x: 0.5, y: 0.5)
    /// The stream screen's size, in points.
    var screen: CGSize = .zero
    /// The frame's size as the Mac sends it (pixels; only its shape counts).
    var video: CGSize = .zero

    static let maxZoom: CGFloat = 8
    /// How close to the screen's edge the pointer comes before the picture moves under it (at most
    /// a quarter of the screen, so a small screen keeps a middle where nothing moves).
    static let edge: CGFloat = 44
    /// A zoom above this counts as zoomed in: the bar's button offers Fit rather than Fill.
    static let zoomedIn: CGFloat = 1.01
    /// A picture no more than this larger than the screen along an axis is as large as it: fitting
    /// leaves a fraction of a point in floating point, which must not move the picture.
    static let slack: CGFloat = 0.5

    var isZoomedIn: Bool { zoom > Self.zoomedIn }

    /// The frame aspect-fitted into the screen, at zoom 1. Before the first frame (or with no
    /// screen) the screen itself.
    var fitted: CGSize {
        guard screen.width > 0, screen.height > 0, video.width > 0, video.height > 0 else { return screen }
        let s = min(screen.width / video.width, screen.height / video.height)
        return CGSize(width: video.width * s, height: video.height * s)
    }

    /// The zoom at which the picture covers the whole screen (no bars): the bar's Fill.
    var fillZoom: CGFloat {
        let f = fitted
        guard f.width > 0, f.height > 0 else { return 1 }
        return min(Self.maxZoom, max(1, max(screen.width / f.width, screen.height / f.height)))
    }

    /// The picture's rectangle on the screen.
    var rect: CGRect {
        let f = fitted
        let size = CGSize(width: f.width * zoom, height: f.height * zoom)
        func origin(_ screen: CGFloat, _ size: CGFloat, _ center: CGFloat) -> CGFloat {
            if size <= screen + ViewerCamera.slack { return (screen - size) / 2 }
            return min(0, max(screen - size, screen / 2 - center * size))
        }
        return CGRect(x: origin(screen.width, size.width, center.x),
                      y: origin(screen.height, size.height, center.y),
                      width: size.width, height: size.height)
    }

    /// Where a point of the frame (a fraction) is on the screen.
    func onScreen(_ p: CGPoint) -> CGPoint {
        let r = rect
        return CGPoint(x: r.minX + p.x * r.width, y: r.minY + p.y * r.height)
    }

    /// `center` from a rectangle the picture would take, then from the clamped `rect` it gives.
    private mutating func settle(_ r: CGRect) {
        guard r.width > 0, r.height > 0 else { return }
        center = CGPoint(x: (screen.width / 2 - r.minX) / r.width, y: (screen.height / 2 - r.minY) / r.height)
        let clamped = rect
        center = CGPoint(x: (screen.width / 2 - clamped.minX) / clamped.width,
                         y: (screen.height / 2 - clamped.minY) / clamped.height)
    }

    /// The screen turned or resized, or the Mac's frame changed shape: the same zoom, the picture
    /// clamped to the new rectangle and `center` written back from it.
    mutating func layout(screen: CGSize, video: CGSize) {
        self.screen = screen
        self.video = video
        let r = rect
        if r.width > 0, r.height > 0 { settle(r) }
    }

    /// The pointer moved to `p` (a fraction of the frame): once it is within `edge` of the screen's
    /// side, along an axis where the picture is larger than the screen, the picture moves under it
    /// until the pointer is `edge` from that side again, or the frame's own edge is reached.
    mutating func follow(_ p: CGPoint) {
        var r = rect
        let wide = r.width > screen.width + Self.slack, high = r.height > screen.height + Self.slack
        guard wide || high else { return }
        let at = onScreen(p)
        let edgeX = min(Self.edge, screen.width / 4), edgeY = min(Self.edge, screen.height / 4)
        var moved = false
        if wide {
            if at.x < edgeX { r.origin.x += edgeX - at.x; moved = true }
            else if at.x > screen.width - edgeX { r.origin.x -= at.x - (screen.width - edgeX); moved = true }
        }
        if high {
            if at.y < edgeY { r.origin.y += edgeY - at.y; moved = true }
            else if at.y > screen.height - edgeY { r.origin.y -= at.y - (screen.height - edgeY); moved = true }
        }
        if moved { settle(r) }
    }

    /// One step of a pinch: `zoom × scale` (kept within 1 and `maxZoom`), with the point of the frame
    /// that was under `from` (the fingers' centroid before the step) under `to` (after it), as far as
    /// the frame's edges allow: the fingers zoom and pan at once.
    mutating func pinch(scale: CGFloat, from: CGPoint, to: CGPoint) {
        let before = rect
        guard before.width > 0, before.height > 0, scale > 0 else { return }
        let fx = (from.x - before.minX) / before.width, fy = (from.y - before.minY) / before.height
        zoom = min(Self.maxZoom, max(1, zoom * scale))
        let f = fitted
        let size = CGSize(width: f.width * zoom, height: f.height * zoom)
        settle(CGRect(x: to.x - fx * size.width, y: to.y - fy * size.height, width: size.width, height: size.height))
    }

    /// The bar's Fill and Fit: zoomed in, back to the whole picture; else to `fillZoom`, centred on
    /// `focus` (the pointer, a fraction of the frame) when there is one.
    mutating func toggleFill(focus: CGPoint?) {
        if isZoomedIn {
            zoom = 1
        } else {
            zoom = fillZoom
            if let focus { center = focus }
        }
        settle(rect)
    }
}
