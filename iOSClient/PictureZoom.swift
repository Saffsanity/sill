import CoreGraphics
import Combine
import Foundation

/// The picture's zoom: the streamed frame magnified on this device alone, with the Mac's pointer
/// held in the middle of the picture as macOS's own Zoom does (Raffael, 2026-10-21). Nothing goes to
/// the Mac: the window keeps its size, and a touch is mapped back through the zoom, so a click lands
/// where the finger is. Offered in a phone's row 1, under Aa (`TextScaleControl`'s second ruler);
/// it applies only while that arrangement shows (`allowed`), so a turn sideways shows the whole frame.
///
/// One object per client (`StreamClient.zoom`), main thread: the display view draws through `rect`,
/// the touch overlay maps through it, and the trackpad slows by `effectiveScale` so a stroke moves
/// the pointer as far on the glass as without zoom.
final class PictureZoom: ObservableObject {
    /// The ruler's detents.
    static let steps: [Double] = [1, 1.5, 2, 3, 4]
    /// What a tap on Aa zooms to when the picture is not zoomed, before any other value was chosen.
    static let defaultZoom: Double = 2

    /// The zoom chosen, 1 for none.
    @Published var scale: Double = 1 { didSet { if scale != oldValue { if scale > 1 { last = scale }; changed(animated: true) } } }
    /// The last zoom above 1, which a tap on Aa brings back.
    private(set) var last: Double = PictureZoom.defaultZoom
    /// Whether the arrangement that offers it is on screen: the phone held upright.
    private(set) var allowed = false { didSet { if allowed != oldValue { changed(animated: false) } } }
    /// The arrangements on screen that offer it: counted, since SwiftUI may show the new one before
    /// it lets the old one go.
    private var offering = 0 { didSet { allowed = offering > 0 } }
    func offered() { offering += 1; settleTouches() }
    func withdrawn() { offering = max(0, offering - 1); settleTouches() }
    /// The scale that applies now.
    var effectiveScale: CGFloat {
        guard allowed else { return 1 }
        return scale > 1 ? CGFloat(scale) : 1
    }

    /// The zoom each source had (`source`): a window keeps its own, the Desktop its own.
    private var perSource: [String: Double] = [:]
    private var sourceKey = ""

    /// The point of the frame held in the picture's middle, as fractions of the frame: where the
    /// Mac's pointer is, or where a finger last touched.
    private(set) var focus = CGPoint(x: 0.5, y: 0.5)
    /// Fingers on the picture: while any is down the view holds still, or the content would slide
    /// under a finger that is dragging on the Mac and the drag would chase itself.
    private var touching = 0
    /// A focus that came while a finger was down, taken when the last one lifts.
    private var pendingFocus: CGPoint?
    /// How long after the last finger lifts its click's focus is taken: past the Mac's double-click
    /// time, so a second tap lands on the picture the first saw (a finger on the glass in between
    /// waits again). The Mac's arrow and the trackpad's are followed at once.
    var touchFollowDelay: TimeInterval = 0.5
    private var touchFollow: DispatchWorkItem?
    /// When the last finger lifted from the picture.
    private var lastLift: TimeInterval = -.infinity

    /// The display view, told to draw again; `animated` for a jump (a zoom chosen, a tap elsewhere).
    var onChange: ((_ animated: Bool) -> Void)?

    /// A tap on Aa: zoomed out, back to the last zoom; zoomed in, out.
    func toggle() { scale = scale > 1 ? 1 : last }

    /// The pointer is at `p` (a fraction of the frame): the Mac's arrow, this device's own, or a
    /// finger's touch.
    func follow(_ p: CGPoint) {
        let clamped = CGPoint(x: min(max(p.x, 0), 1), y: min(max(p.y, 0), 1))
        if touching > 0 { pendingFocus = clamped; return }
        // A click whose recognizer answers after the finger lifted waits out the same time.
        let sinceLift = ProcessInfo.processInfo.systemUptime - lastLift
        if touchFollowDelay > 0, sinceLift < touchFollowDelay {
            pendingFocus = clamped
            if touchFollow == nil { schedule(after: touchFollowDelay - sinceLift) }
            return
        }
        let jump = hypot(clamped.x - focus.x, clamped.y - focus.y) * effectiveScale > 0.25
        focus = clamped
        if effectiveScale > 1 { onChange?(jump) }
    }

    /// Another source streams (`key`: "desktop", or a window's id): the zoom it had, none for a new
    /// one, and the focus back in the middle until the pointer says where it is.
    func source(_ key: String) {
        guard key != sourceKey else { return }
        perSource[sourceKey] = scale
        sourceKey = key
        focus = CGPoint(x: 0.5, y: 0.5)
        let next = perSource[key] ?? 1
        if next != scale { scale = next } else { changed(animated: false) }
    }

    func touchesBegan(_ count: Int) {
        touching += count
        touchFollow?.cancel()
        touchFollow = nil
    }
    func touchesEnded(_ count: Int) {
        touching = max(0, touching - count)
        guard touching == 0 else { return }
        lastLift = ProcessInfo.processInfo.systemUptime
        guard pendingFocus != nil else { return }
        guard touchFollowDelay > 0 else { takePending(); return }
        schedule(after: touchFollowDelay)
    }

    private func schedule(after delay: TimeInterval) {
        touchFollow?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.takePending() }
        touchFollow = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func takePending() {
        touchFollow = nil
        guard touching == 0, let p = pendingFocus else { return }
        pendingFocus = nil
        lastLift = -.infinity
        follow(p)
    }

    /// A finger the overlay never saw lift (it left the window mid-touch) holds nothing.
    private func settleTouches() {
        touching = 0
        lastLift = -.infinity
        touchFollow?.cancel()
        touchFollow = nil
        pendingFocus = nil
    }

    /// Where the whole frame is drawn now, for a frame drawn at `video` (aspect-fit) inside `bounds`.
    func rect(video: CGRect, bounds: CGRect) -> CGRect {
        Self.zoomedRect(video: video, bounds: bounds, scale: effectiveScale, focus: focus)
    }

    private func changed(animated: Bool) {
        if effectiveScale <= 1 { settleTouches() }
        onChange?(animated)
    }

    /// Pure: the frame, drawn at `video` without zoom, magnified `scale` times so the point `focus`
    /// (fractions of the frame) sits in the middle of `bounds`, but never leaving bounds uncovered
    /// along an axis the magnified frame is longer than: there it stops at the frame's edge. Along an
    /// axis where it is still shorter than `bounds` it stays centred, as the letterbox was.
    static func zoomedRect(video: CGRect, bounds: CGRect, scale: CGFloat, focus: CGPoint) -> CGRect {
        guard scale > 1, video.width > 0, video.height > 0, bounds.width > 0, bounds.height > 0 else { return video }
        func origin(length: CGFloat, boundsMin: CGFloat, boundsLength: CGFloat, fraction: CGFloat) -> CGFloat {
            guard length > boundsLength else { return boundsMin + (boundsLength - length) / 2 }
            let centred = boundsMin + boundsLength / 2 - fraction * length
            return min(boundsMin, max(boundsMin + boundsLength - length, centred))
        }
        let width = video.width * scale, height = video.height * scale
        return CGRect(x: origin(length: width, boundsMin: bounds.minX, boundsLength: bounds.width, fraction: focus.x),
                      y: origin(length: height, boundsMin: bounds.minY, boundsLength: bounds.height, fraction: focus.y),
                      width: width, height: height)
    }
}

