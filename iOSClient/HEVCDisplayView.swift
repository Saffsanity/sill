import UIKit
import AVFoundation
import Combine
import CoreMedia
import SwiftUI
import StreamProtocol

/// A UIView whose layer is an AVSampleBufferDisplayLayer, which decodes HEVC in hardware itself;
/// the decoding is `HEVCSampleFeed`'s, shared with the Mac client's view.
final class HEVCDisplayView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
    private var displayLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }
    private lazy var feed: HEVCSampleFeed = {
        let feed = HEVCSampleFeed(layer: displayLayer)
        feed.onVideoSize = { [weak self] size in
            guard let self else { return }
            self.pointerVideoSize = size
            self.onVideoSize?(size)
            self.placeCursor()
            self.onVideoSizeForPointer?(size)
        }
        feed.onCleared = { [weak self] in
            // The pointer's copy of the size is main-thread state; the client zeroes its own alongside.
            self?.pointerVideoSize = .zero
            self?.placeCursor()
        }
        return feed
    }()

    /// The streamed frame's pixel size, reported on main whenever new parameter sets arrive.
    /// Input needs it: touches are normalized against the video, not against this view.
    var onVideoSize: ((CGSize) -> Void)?
    /// The same event, fired on main right after `onVideoSize`. `StreamClient` owns `onVideoSize`
    /// (it feeds `videoSize`); `StreamView` owns this one and tells the client's pointer on it
    /// (`StreamClient.pointerFrameChanged`). Two hooks instead of a chain, so re-hosting after a
    /// rotation cannot stack closures.
    var onVideoSizeForPointer: ((CGSize) -> Void)?

    // MARK: The pointer sprite
    //
    // The Mac's cursor is never in the video (the host captures without it), so every pointer the
    // device shows is this sprite, in the Mac's live shape (kind 14). It is one of two things
    // (docs/pointer-visibility-plan.md, "What the device draws"; `StreamClient.renderPointer` decides):
    // the Mac's own pointer, while the Mac or another device moved it last, placed where kind 26
    // says it is and moved at the rate those reports come; or this device's own, for the portrait
    // trackpad (and the Pencil, with Q2's flip), placed at touch rate rather than a network round
    // trip behind, which is where the Mac's cursor in the video would be. All of it main thread.

    private let cursorLayer = HEVCDisplayView.makeCursorLayer()
    /// Where the sprite's tip is, a fraction of the video frame, or nil when hidden: what
    /// `StreamClient.renderPointer` last handed over.
    private var pointer: CGPoint?
    /// Main-thread copy of the frame size the layer draws. `apply` runs on the network queue and
    /// hops here with it; `clear` zeroes it. Zero hides the sprite: there is no frame to point into.
    private var pointerVideoSize: CGSize = .zero
    /// Stacking inside this view's layer, which is the video layer: sibling sublayers draw in
    /// zPosition order, so the sprite sits above the picture whatever the display layer adds
    /// underneath, and the DEBUG readout sits above the sprite.
    private static let cursorZ: CGFloat = 100
    private static let hudZ: CGFloat = 200

    #if DEBUG
    /// The `-SillHUD 1` readout and its subscriptions to the client. nil unless that argument is set.
    private var hud: DiagnosticsHUDView?
    private var hudSubscriptions = Set<AnyCancellable>()
    #endif

    /// Where `resizeAspect` actually draws a `videoSize` frame inside `bounds`: the same letterboxed
    /// rect the layer uses, which is what maps a touch to a fraction of the frame.
    /// Returns `.zero` while the video size is unknown, so callers can tell "no video" from "top left".
    static func videoRect(in bounds: CGRect, videoSize: CGSize) -> CGRect {
        HEVCSampleFeed.videoRect(in: bounds, videoSize: videoSize)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        _ = feed   // made on main, before the network queue's first `apply`
        layer.addSublayer(cursorLayer)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // A standalone layer renders at 1× unless told otherwise; the arrow should be crisp.
        if let scale = window?.screen.scale { cursorLayer.contentsScale = scale }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        placeCursor()   // rotation and letterbox changes move the video rect under it
        #if DEBUG
        if let debugFrame {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            debugFrame.frame = Self.videoRect(in: bounds, videoSize: pointerVideoSize)
            CATransaction.commit()
        }
        if let hud {
            // Rotation reparents this view into a new SwiftUI host; keep the readout above anything
            // added since and pinned to the new bounds.
            bringSubviewToFront(hud)
            hud.place(in: bounds)
        }
        #endif
    }

    #if DEBUG
    /// Shows the diagnostics readout fed by `client`, when launched with `-SillHUD 1`. Idempotent:
    /// the view is shared across layouts, so every re-host calls this and only the first one counts.
    func attachDiagnostics(to client: StreamClient) {
        guard DiagnosticsHUDView.isEnabled, hud == nil else { return }
        let hud = DiagnosticsHUDView(frame: .zero)
        hud.layer.zPosition = Self.hudZ   // above the pointer sprite
        addSubview(hud)
        self.hud = hud
        // [weak hud]: the view owns the subscriptions, the subscriptions must not own the view.
        Publishers.CombineLatest(client.$linkStats, client.$videoSize)
            .receive(on: DispatchQueue.main)
            .sink { [weak hud] stats, size in hud?.update(stats: stats, videoSize: size) }
            .store(in: &hudSubscriptions)
        setNeedsLayout()
    }
    #endif

    /// Shows the sprite at `p` (a fraction of the video frame) or hides it (nil): the Mac's pointer
    /// or this device's own, whichever `StreamClient.renderPointer` says. Up to 120 times a second.
    /// Main thread.
    func setPointer(_ p: CGPoint?) {
        pointer = p
        placeCursor()
    }

    #if DEBUG
    /// The layout harness (`-SillPointer`): the frame size the sprite needs, as the host's parameter
    /// sets would give it, for a mock that never streams; and a dim rectangle where that frame is
    /// drawn, so a photo shows what the sprite points into (the mock's picture is black).
    func debugFrameSize(_ size: CGSize) {
        pointerVideoSize = size
        if debugFrame == nil {
            let frame = CALayer()
            frame.backgroundColor = UIColor(white: 0.16, alpha: 1).cgColor
            frame.zPosition = Self.cursorZ - 1
            layer.addSublayer(frame)
            debugFrame = frame
        }
        setNeedsLayout()
        placeCursor()
    }

    /// `debugFrameSize`'s rectangle; nil unless the harness asked for it.
    private var debugFrame: CALayer?
    #endif

    /// Gives the sprite the Mac's current cursor image (I-beam, hand, resize…) with its hotspot at
    /// the layer's anchor, or falls back to the built-in arrow when nil. Sizes are Mac points, drawn
    /// 1:1 in device points. Main thread, never animated.
    func setCursorShape(_ shape: StreamClient.CursorShape?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if let shape, let cg = shape.image.cgImage, shape.size.width > 0, shape.size.height > 0 {
            cursorLayer.path = nil
            cursorLayer.shadowPath = nil
            cursorLayer.shadowOpacity = 0
            cursorLayer.contents = cg
            cursorLayer.contentsGravity = .resize
            cursorLayer.bounds = CGRect(origin: .zero, size: shape.size)
            cursorLayer.anchorPoint = CGPoint(x: shape.hotspot.x / shape.size.width, y: shape.hotspot.y / shape.size.height)
        } else {
            let arrow = Self.arrowPath
            cursorLayer.contents = nil
            cursorLayer.path = arrow
            cursorLayer.shadowPath = arrow
            cursorLayer.shadowOpacity = 0.3
            cursorLayer.bounds = arrow.boundingBox
            cursorLayer.anchorPoint = .zero
        }
        placeCursor()
    }

    /// Puts the sprite's tip on the pointer inside the letterboxed video rect, or hides it when
    /// there is no pointer or no video yet. Never animated: an implicit 0.25 s action on a
    /// standalone layer is exactly the lag the sprite exists to remove. Main thread.
    private func placeCursor() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let rect = Self.videoRect(in: bounds, videoSize: pointerVideoSize)
        guard let p = pointer, rect.width > 0, rect.height > 0 else {
            cursorLayer.isHidden = true
            return
        }
        let x = min(max(p.x, 0), 1), y = min(max(p.y, 0), 1)
        cursorLayer.position = CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        cursorLayer.isHidden = false
    }

    /// A macOS-style arrow, about 20 pt tall: white, 1 pt black outline, a soft shadow. Its tip is
    /// the hotspot and sits at the layer's origin, so `position` is the point being pointed at.
    static var arrowPath: CGPath { HEVCSampleFeed.arrowPath }

    private static func makeCursorLayer() -> CAShapeLayer {
        let arrow = arrowPath
        let shape = CAShapeLayer()
        shape.path = arrow
        shape.fillColor = UIColor.white.cgColor
        shape.strokeColor = UIColor.black.cgColor
        shape.lineWidth = 1
        shape.lineJoin = .round        // a mitred 45° tip would poke 1.3 pt past the hotspot
        shape.bounds = arrow.boundingBox
        shape.anchorPoint = .zero
        shape.shadowPath = arrow       // spares Core Animation an offscreen pass to find the shape
        shape.shadowColor = UIColor.black.cgColor
        shape.shadowOpacity = 0.3
        shape.shadowRadius = 1
        shape.shadowOffset = CGSize(width: 0, height: 1)
        shape.zPosition = cursorZ
        shape.isHidden = true
        return shape
    }

    /// Thread-safe: AVSampleBufferDisplayLayer's enqueue/flush are documented as safe off main.
    func apply(_ ps: ParameterSets) { feed.apply(ps) }

    /// Session over: drop the picture and forget the format so the next Mac starts clean.
    func clear() { feed.clear() }

    func enqueue(_ data: Data, isKeyframe: Bool) { feed.enqueue(data, isKeyframe: isKeyframe) }
}

struct StreamView: UIViewRepresentable {
    let client: StreamClient

    /// Hosts the client's single display view. SwiftUI may build the new layout's host before it
    /// dismantles the old one, so detach the view from wherever it was first.
    func makeUIView(context: Context) -> HEVCDisplayView {
        let view = client.displayView
        view.removeFromSuperview()
        #if DEBUG
        view.attachDiagnostics(to: client)
        #endif
        wirePointer(view)
        return view
    }

    /// Connects the client's pointer to the sprite, with no SwiftUI in between (a re-render per move
    /// is the lag this avoids). Runs on every re-host, rotation included: the hooks are plain
    /// assignments, so the newest replaces the last instead of stacking. This is the only place that
    /// sets `onPointerChange`. Main thread, like everything the closures touch.
    private func wirePointer(_ view: HEVCDisplayView) {
        let client = self.client
        client.onCursorShapeChange = { [weak view] shape in view?.setCursorShape(shape) }
        view.setCursorShape(client.cursorShape)
        client.onPointerChange = { [weak view] p in view?.setPointer(p) }
        // A new frame size (another source, an Aa resize) changes what a fraction means: this
        // device's own pointer, while it shows, starts again in the middle and the Mac's goes there
        // too (after the tour, while one shows: `pointerFrameChanged`); the Mac's arrow follows the
        // host's next report.
        view.onVideoSizeForPointer = { [weak client] _ in client?.pointerFrameChanged() }
        // Catch up with what the sprite shows now (a pointer set before this view was hosted).
        client.renderPointer()
    }

    func updateUIView(_ uiView: HEVCDisplayView, context: Context) {}
}
