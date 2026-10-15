import AppKit
import AVFoundation
import StreamProtocol

/// The Mac client's picture: an NSView backed by an AVSampleBufferDisplayLayer, decoded by the
/// shared `HEVCSampleFeed`, with the pointer sprite over it. The same API as the iOS app's view,
/// since `StreamClient` (shared) makes and feeds it. Input is `StreamInputView`'s, which hosts this
/// view. Flipped, so y grows down as in the video frame. Main thread but for the feed.
final class HEVCDisplayView: NSView {
    private let displayLayer = AVSampleBufferDisplayLayer()
    private lazy var feed: HEVCSampleFeed = {
        let feed = HEVCSampleFeed(layer: displayLayer)
        feed.onVideoSize = { [weak self] size in
            guard let self else { return }
            self.videoSize = size
            self.onVideoSize?(size)
            self.placeCursor()
            self.onVideoSizeChangedForInput?()
        }
        feed.onCleared = { [weak self] in
            self?.videoSize = .zero
            self?.placeCursor()
        }
        return feed
    }()

    /// The streamed frame's pixel size, on main whenever new parameter sets arrive (`StreamClient`
    /// owns this hook and feeds `videoSize`).
    var onVideoSize: ((CGSize) -> Void)?
    /// The same event for the input view, which owns this hook: the cursor rect and the pointer follow.
    var onVideoSizeChangedForInput: (() -> Void)?
    /// The frame size the layer draws, main-thread copy; zero hides the sprite.
    private(set) var videoSize: CGSize = .zero

    private let cursorLayer = CAShapeLayer()
    private var pointer: CGPoint?

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer = CALayer()
        // Clear: until a stream's first frame, the window's own picture (its thumbnail) shows through.
        layer?.backgroundColor = NSColor.clear.cgColor
        // y down, as in the video frame and the view: every sublayer is placed in view coordinates.
        layer?.isGeometryFlipped = true
        layer?.addSublayer(displayLayer)
        displayLayer.frame = bounds
        _ = feed   // made on main, before the network queue's first `apply`
        let arrow = HEVCSampleFeed.arrowPath
        cursorLayer.path = arrow
        cursorLayer.fillColor = NSColor.white.cgColor
        cursorLayer.strokeColor = NSColor.black.cgColor
        cursorLayer.lineWidth = 1
        cursorLayer.lineJoin = .round
        cursorLayer.bounds = arrow.boundingBox
        cursorLayer.anchorPoint = .zero
        cursorLayer.shadowPath = arrow
        cursorLayer.shadowOpacity = 0.3
        cursorLayer.shadowRadius = 1
        cursorLayer.zPosition = 100
        cursorLayer.isHidden = true
        layer?.addSublayer(cursorLayer)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        displayLayer.frame = bounds
        CATransaction.commit()
        placeCursor()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        layer?.contentsScale = scale
        cursorLayer.contentsScale = scale
    }

    /// The letterboxed rect the frame is drawn in, in this view's (flipped) coordinates.
    var videoRect: CGRect { HEVCSampleFeed.videoRect(in: bounds, videoSize: videoSize) }

    /// Where a point of this view falls in the frame, as a fraction; nil outside it or with no video.
    func fraction(of point: CGPoint, clamped: Bool = false) -> CGPoint? {
        let rect = videoRect
        guard rect.width > 0, rect.height > 0 else { return nil }
        var x = (point.x - rect.minX) / rect.width, y = (point.y - rect.minY) / rect.height
        if clamped { x = min(max(x, 0), 1); y = min(max(y, 0), 1) }
        guard (0...1).contains(x), (0...1).contains(y) else { return nil }
        return CGPoint(x: x, y: y)
    }

    /// Shows the Mac's pointer sprite at `p` (a fraction of the frame) or hides it (nil).
    func setPointer(_ p: CGPoint?) {
        pointer = p
        placeCursor()
    }

    /// The Mac's current cursor image, or the built-in arrow when nil.
    func setCursorShape(_ shape: StreamClient.CursorShape?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if let shape, let cg = shape.image.cgImage(forProposedRect: nil, context: nil, hints: nil),
           shape.size.width > 0, shape.size.height > 0 {
            cursorLayer.path = nil
            cursorLayer.shadowPath = nil
            cursorLayer.shadowOpacity = 0
            cursorLayer.contents = cg
            cursorLayer.contentsGravity = .resize
            cursorLayer.bounds = CGRect(origin: .zero, size: shape.size)
            cursorLayer.anchorPoint = CGPoint(x: shape.hotspot.x / shape.size.width, y: shape.hotspot.y / shape.size.height)
        } else {
            let arrow = HEVCSampleFeed.arrowPath
            cursorLayer.contents = nil
            cursorLayer.path = arrow
            cursorLayer.shadowPath = arrow
            cursorLayer.shadowOpacity = 0.3
            cursorLayer.bounds = arrow.boundingBox
            cursorLayer.anchorPoint = .zero
        }
        placeCursor()
    }

    private func placeCursor() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let rect = videoRect
        guard let p = pointer, rect.width > 0, rect.height > 0 else { cursorLayer.isHidden = true; return }
        let x = min(max(p.x, 0), 1), y = min(max(p.y, 0), 1)
        cursorLayer.position = CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        cursorLayer.isHidden = false
    }

    // Called by StreamClient on the network queue.
    func apply(_ ps: ParameterSets) { feed.apply(ps) }
    func clear() { feed.clear() }
    func enqueue(_ data: Data, isKeyframe: Bool) { feed.enqueue(data, isKeyframe: isKeyframe) }
}
