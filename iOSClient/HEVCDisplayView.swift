import UIKit
import AVFoundation
import Combine
import CoreMedia
import SwiftUI
import StreamProtocol

/// A UIView whose layer is an AVSampleBufferDisplayLayer, which decodes HEVC in hardware itself.
/// No VTDecompressionSession needed for the spike.
final class HEVCDisplayView: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
    private var displayLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }

    private var formatDescription: CMVideoFormatDescription?
    private var waitingForKeyframe = true
    private var lastParameterSets: Data?

    /// The streamed frame's pixel size, reported on main whenever new parameter sets arrive.
    /// Input needs it: touches are normalized against the video, not against this view.
    var onVideoSize: ((CGSize) -> Void)?
    /// The same event, fired on main right after `onVideoSize`. `StreamClient` owns `onVideoSize`
    /// (it feeds `videoSize`); `StreamView` owns this one and re-centres the pointer on it. Two
    /// hooks instead of a chain, so re-hosting after a rotation cannot stack closures.
    var onVideoSizeForPointer: ((CGSize) -> Void)?

    // MARK: Client-drawn pointer
    //
    // The Mac cursor in the video arrives a round trip late and in bursts, so the trackpad and
    // Pencil hover drive a sprite drawn here instead (`StreamClient.localPointer`), and the host
    // leaves its cursor out of the video while every client draws its own. All of it main thread.

    private let cursorLayer = HEVCDisplayView.makeCursorLayer()
    /// Fraction of the video frame, or nil when hidden. Mirrors `StreamClient.localPointer`.
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
        guard videoSize.width > 0, videoSize.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = min(bounds.width / videoSize.width, bounds.height / videoSize.height)
        let size = CGSize(width: videoSize.width * scale, height: videoSize.height * scale)
        return CGRect(x: bounds.minX + (bounds.width - size.width) / 2,
                      y: bounds.minY + (bounds.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        displayLayer.videoGravity = .resizeAspect
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

    /// Shows the pointer at `p` (a fraction of the video frame) or hides it (nil). Called for every
    /// `StreamClient.localPointer` write, up to 120 times a second. Returns true when the pointer
    /// went from hidden to shown or back, which is when the host needs telling. Main thread.
    @discardableResult
    func setLocalPointer(_ p: CGPoint?) -> Bool {
        let flipped = (p == nil) != (pointer == nil)
        pointer = p
        placeCursor()
        return flipped
    }

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
    static let arrowPath: CGPath = {
        let arrow = CGMutablePath()
        arrow.addLines(between: [
            CGPoint(x: 0, y: 0),        // tip
            CGPoint(x: 0, y: 16.8),     // down the straight left edge
            CGPoint(x: 4.0, y: 12.8),   // in to the tail
            CGPoint(x: 6.8, y: 19.2),   // tail, lower left
            CGPoint(x: 9.6, y: 18.0),   // tail, lower right
            CGPoint(x: 6.9, y: 12.0),   // back up to the head
            CGPoint(x: 12.0, y: 12.0),  // right wing
        ])
        arrow.closeSubpath()
        return arrow
    }()

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
    func apply(_ ps: ParameterSets) {
        // The host repeats the parameter sets with every keyframe. Only a real change (a new source,
        // a resize) needs a new format description and a blank layer; a repeat must not flicker.
        let encoded = ps.encoded()
        if encoded == lastParameterSets, formatDescription != nil { return }
        lastParameterSets = encoded
        let buffers = ps.sets.map { set -> UnsafeMutablePointer<UInt8> in
            let p = UnsafeMutablePointer<UInt8>.allocate(capacity: set.count)
            set.copyBytes(to: p, count: set.count)
            return p
        }
        defer { buffers.forEach { $0.deallocate() } }
        let pointers = buffers.map { UnsafePointer($0) }
        let sizes = ps.sets.map(\.count)

        var desc: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(
            allocator: nil, parameterSetCount: pointers.count, parameterSetPointers: pointers,
            parameterSetSizes: sizes, nalUnitHeaderLength: Int32(ps.nalUnitHeaderLength),
            extensions: nil, formatDescriptionOut: &desc)
        guard status == noErr, let desc else { print("format description failed: \(status)"); return }
        formatDescription = desc
        waitingForKeyframe = true
        let dimensions = CMVideoFormatDescriptionGetDimensions(desc)
        let size = CGSize(width: CGFloat(dimensions.width), height: CGFloat(dimensions.height))
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pointerVideoSize = size
            self.onVideoSize?(size)
            self.placeCursor()
            self.onVideoSizeForPointer?(size)
        }
        // Remove the last frame too: switching sources should show black until the new keyframe,
        // not the previous window frozen in place.
        displayLayer.flushAndRemoveImage()
    }

    /// Session over: drop the picture and forget the format so the next Mac starts clean.
    func clear() {
        formatDescription = nil
        lastParameterSets = nil
        waitingForKeyframe = true
        displayLayer.flushAndRemoveImage()
        // The pointer's copy of the size is main-thread state; the client zeroes its own alongside.
        DispatchQueue.main.async { [weak self] in
            self?.pointerVideoSize = .zero
            self?.placeCursor()
        }
    }

    func enqueue(_ data: Data, isKeyframe: Bool) {
        guard let desc = formatDescription else { return }
        if waitingForKeyframe {
            guard isKeyframe else { return }
            waitingForKeyframe = false
        }

        let count = data.count
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: count, blockAllocator: nil,
                                                 customBlockSource: nil, offsetToData: 0, dataLength: count, flags: 0,
                                                 blockBufferOut: &block) == noErr, let block,
              CMBlockBufferAssureBlockMemory(block) == noErr else { return }
        let replaced = data.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: count)
        }
        guard replaced == noErr else { return }

        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid)
        var size = count
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: desc, sampleCount: 1,
                                        sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                        sampleSizeEntryCount: 1, sampleSizeArray: &size,
                                        sampleBufferOut: &sample) == noErr, let sample else { return }

        // Show each frame as soon as it decodes instead of scheduling by timestamp.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as NSArray?,
           let first = attachments.firstObject as? NSMutableDictionary {
            first[kCMSampleAttachmentKey_DisplayImmediately as String] = true
        }

        if displayLayer.status == .failed {
            print("display layer failed: \(String(describing: displayLayer.error))")
            displayLayer.flush()
            waitingForKeyframe = true
            return
        }
        displayLayer.enqueue(sample)
    }
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

    /// Connects `client.localPointer` to the sprite, with no SwiftUI in between (a re-render per
    /// move is the lag this avoids). Runs on every re-host, rotation included: both hooks are plain
    /// assignments, so the newest replaces the last instead of stacking. This is the only place
    /// that sets `onLocalPointerChange`. Main thread, like everything the closures touch.
    private func wirePointer(_ view: HEVCDisplayView) {
        let client = self.client
        client.onCursorShapeChange = { [weak view] shape in view?.setCursorShape(shape) }
        view.setCursorShape(client.cursorShape)
        client.onLocalPointerChange = { [weak view, weak client] p in
            // Hidden ↔ shown is when the host should take its cursor out of the video or put it
            // back; `setLocalCursor` debounces that, so hover flapping costs nothing on the wire.
            guard let view, view.setLocalPointer(p) else { return }
            client?.setLocalCursor(p != nil)
        }
        // A new frame size (another source, an Aa resize) invalidates where the pointer was. If it
        // is showing, start it in the middle and move the Mac cursor there too, so the two agree
        // (after the tour, while one shows: `recentrePointer`).
        view.onVideoSizeForPointer = { [weak client] _ in
            guard let client, client.localPointer != nil else { return }
            client.recentrePointer()
        }
        // Catch up with a pointer set before this view was hosted; a no-op on re-hosts.
        client.onLocalPointerChange?(client.localPointer)
    }

    func updateUIView(_ uiView: HEVCDisplayView, context: Context) {}
}
