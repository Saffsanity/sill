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
    /// (it feeds `videoSize`); `StreamView` owns this one and tells the client's pointer on it
    /// (`StreamClient.pointerFrameChanged`). Two hooks instead of a chain, so re-hosting after a
    /// rotation cannot stack closures.
    var onVideoSizeForPointer: ((CGSize) -> Void)?
    /// The queue `apply` and `enqueue` run on (the client's network queue): the layer's own
    /// notifications, which come on whatever thread AVFoundation posts them, are looked at there.
    var renderQueue: DispatchQueue?
    /// The picture was interrupted: the layer was flushed and waits for a keyframe (`checkLayer`),
    /// which a still window on the Mac never sends by itself. The client asks for one
    /// (KeyframeRecovery). On `renderQueue`.
    var onNeedsKeyframe: (() -> Void)?
    /// A keyframe ended a wait: the picture is back (after an interruption, or a new source's first).
    /// When the layer still read interrupted at that keyframe, `checkLayer` throws it away with its
    /// flush and says so first, then `onNeedsKeyframe`: for the client the picture came back and was
    /// lost again at once, so it asks again, as for a repeat (KeyframeRecovery). On `renderQueue`.
    var onPictureBack: (() -> Void)?
    /// The layer's notifications (`observeLayer`).
    private var layerObservers: [NSObjectProtocol] = []
    /// When a keyframe last ended a wait (`CACurrentMediaTime`): a decode failure posted before then
    /// is about a frame from before the picture came back. On `renderQueue`.
    private var resumedAt: CFTimeInterval = 0

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
    /// The picture's zoom (StreamZoom; ZoomedStreamView scales this whole view by it): the sprite is
    /// drawn at the zoomed place by that, and at its own size by the inverse scale about its hotspot,
    /// as iPadOS's pointer and the Mac's own stay their size over a zoomed picture.
    private var zoom = StreamZoom()
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
        // The picture takes no touch: the input view over it takes every one. Zoomed (StreamZoom) it is
        // drawn far past its pane, and a clip does not clip hit testing: sideways, where the bar comes
        // before the picture, UIKit's hit test on the bar's buttons found this view at 5× (-SillHitTest).
        isUserInteractionEnabled = false
        displayLayer.videoGravity = .resizeAspect
        layer.addSublayer(cursorLayer)
        observeLayer()
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { layerObservers.forEach(NotificationCenter.default.removeObserver) }

    /// The layer says it could not decode a frame, or that it needs a flush before it decodes again
    /// (iOS says so when Sill goes to the background, or another app takes the decoder): looked at on
    /// `renderQueue` at once, since a still window sends no frame that would show it (`checkLayer`).
    private func observeLayer() {
        let center = NotificationCenter.default
        layerObservers.append(center.addObserver(forName: .AVSampleBufferDisplayLayerFailedToDecode, object: displayLayer,
                                                 queue: nil) { [weak self] note in
            let error = note.userInfo?[AVSampleBufferDisplayLayerFailedToDecodeNotificationErrorKey] as? Error
            let postedAt = CACurrentMediaTime()
            self?.renderQueue?.async { [weak self] in
                // A frame enqueued before the picture came back failed: the flush that preceded the
                // keyframe already dealt with it, and acting now would throw the new picture away.
                guard let self, postedAt >= self.resumedAt else { return }
                self.checkLayer("(its notification)", failedToDecode: error)
            }
        })
        layerObservers.append(center.addObserver(forName: .AVSampleBufferDisplayLayerRequiresFlushToResumeDecodingDidChange,
                                                 object: displayLayer, queue: nil) { [weak self] _ in
            self?.renderQueue?.async { [weak self] in self?.checkLayer("(its notification)") }
        })
    }

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
            // added since and pinned to the new bounds (the part of them the zoom shows).
            bringSubviewToFront(hud)
            hud.place(in: zoom.visibleRect(in: bounds.size), scale: zoom.scale)
        }
        #endif
    }

    /// The picture's zoom changed (ZoomedStreamView, as it scales this view): the sprite keeps its size,
    /// and the DEBUG readout its corner. Main thread.
    func setZoom(_ new: StreamZoom) {
        guard new != zoom else { return }
        zoom = new
        placeCursor()
        #if DEBUG
        if hud != nil { setNeedsLayout() }
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
        // About the anchor, which is the hotspot: the tip stays on the point.
        let unscale = 1 / max(StreamZoom.minScale, zoom.scale)
        cursorLayer.setAffineTransform(zoom.isZoomed ? CGAffineTransform(scaleX: unscale, y: unscale) : .identity)
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
        #if DEBUG
        interruptedAt = nil
        #endif
        displayLayer.flushAndRemoveImage()
        // The pointer's copy of the size is main-thread state; the client zeroes its own alongside.
        DispatchQueue.main.async { [weak self] in
            self?.pointerVideoSize = .zero
            self?.placeCursor()
        }
    }

    func enqueue(_ data: Data, isKeyframe: Bool) {
        guard let desc = formatDescription else { return }
        let resuming = waitingForKeyframe
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

        var lost: Error?
        #if DEBUG
        if resuming, interruptedAt != nil, keyframesToLose > 0 {     // -SillKeyframeLost
            keyframesToLose -= 1
            print("display: -SillKeyframeLost: the keyframe that ends the wait is thrown away, as though the layer still read failed (\(keyframesToLose) more)")
            lost = NSError(domain: "SillKeyframeLost", code: 0)
        }
        #endif
        if checkLayer("at a frame", failedToDecode: lost, droppingKeyframe: resuming) { return }
        if resuming { resumedAt = CACurrentMediaTime() }
        displayLayer.enqueue(sample)
        if resuming {
            #if DEBUG
            if let at = interruptedAt {
                print("display: the picture is back, \(Int(((CACurrentMediaTime() - at) * 1000).rounded())) ms after it was interrupted")
                interruptedAt = nil
            }
            armLayerFailure()
            #endif
            onPictureBack?()
        }
    }

    /// Whether the picture was interrupted: the layer failed (its `status`, with its `error`), could
    /// not decode a frame (`failedToDecode`, from its notification), or needs a flush before it
    /// decodes again (Sill was in the background, or another app took the decoder). If so the layer
    /// is flushed (it keeps the last image it showed), waits for a keyframe, and `onNeedsKeyframe` is
    /// told, since a still window on the Mac sends none. The Mac sends its parameter sets before
    /// every keyframe and every sample carries the format, so nothing else needs sending again. From
    /// each frame let through, the layer's notifications, and the picture's window becoming active
    /// (StreamClient). `droppingKeyframe`: the frame is the keyframe that ends the wait, which the
    /// flush throws away: `onPictureBack` is told first, so the client counts the picture back and
    /// lost again and asks again at a repeat's spacing (KeyframeRecovery), rather than taking the
    /// layer's word as part of an interruption whose keyframe already came. On `renderQueue`. True
    /// when it flushed.
    @discardableResult
    func checkLayer(_ why: String, failedToDecode: Error? = nil, droppingKeyframe: Bool = false) -> Bool {
        guard formatDescription != nil else { return false }    // no picture yet: nothing to lose
        let failed = displayLayer.status == .failed || displayLayer.error != nil
        let needsFlush = displayLayer.requiresFlushToResumeDecoding
        guard failed || needsFlush || failedToDecode != nil else { return false }
        #if DEBUG
        let what = failedToDecode.map { "could not decode a frame (\(($0 as NSError).code))" }
            ?? (failed ? "failed (\(displayLayer.error.map { "\(($0 as NSError).domain) \(($0 as NSError).code)" } ?? "no error"))"
                       : "needs a flush to decode again")
        print("display: the picture was interrupted \(why): the layer \(what)\(needsFlush && failed ? " and needs a flush" : ""); flushed"
              + (droppingKeyframe ? " with the keyframe it waited for" : "") + ", waiting for a keyframe")
        if interruptedAt == nil { interruptedAt = CACurrentMediaTime() }
        #endif
        displayLayer.flush()
        waitingForKeyframe = true
        if droppingKeyframe { onPictureBack?() }    // first: both reach the client in this order
        onNeedsKeyframe?()
        return true
    }

    #if DEBUG
    /// When the picture was first interrupted, for the console's "back, N ms after" line.
    private var interruptedAt: CFTimeInterval?
    /// `-SillKeyframeLost <n>` (ContentView's harness contract): the first n keyframes that end a wait
    /// after an interruption are thrown away by `checkLayer`'s flush, as though the layer still read
    /// failed when they came (as it can while another app holds the decoder), so the client's next
    /// ask runs for real.
    private var keyframesToLose = UserDefaults.standard.integer(forKey: "SillKeyframeLost")
    /// `-SillLayerFail <s>[,<s>…]` (ContentView's harness contract): at each of these seconds after the
    /// launch's first picture, a frame that cannot decode goes onto the layer, so the recovery runs for
    /// real: the layer's notification, the flush, the client's one ask (kind 44) and the Mac's keyframe.
    private static let layerFailTimes: [Double] = (UserDefaults.standard.string(forKey: "SillLayerFail") ?? "")
        .split(whereSeparator: { $0 == "," || $0 == " " }).compactMap { Double($0) }.filter { $0 > 0 }
    private var layerFailArmed = true

    /// On the first picture of the launch (`enqueue`, on `renderQueue`).
    private func armLayerFailure() {
        guard layerFailArmed, !Self.layerFailTimes.isEmpty, let queue = renderQueue else { return }
        layerFailArmed = false
        print("display: -SillLayerFail: a frame that cannot decode goes onto the layer at \(Self.layerFailTimes) s")
        for time in Self.layerFailTimes {
            queue.asyncAfter(deadline: .now() + time) { [weak self] in self?.breakLayer() }
        }
    }

    /// A sample of noise behind an HEVC NAL length far longer than the sample, marked a keyframe to be
    /// shown at once, in the stream's own format: the decoder refuses it.
    private func breakLayer() {
        guard let desc = formatDescription else { print("display: -SillLayerFail: no picture to break"); return }
        var bytes: [UInt8] = [0x7F, 0xFF, 0xFF, 0xFF, 0x26, 0x01]
        bytes += (0..<506).map { _ in UInt8.random(in: 0...255) }
        var block: CMBlockBuffer?
        var sample: CMSampleBuffer?
        var size = bytes.count
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid)
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes.count, blockAllocator: nil,
                                                 customBlockSource: nil, offsetToData: 0, dataLength: bytes.count, flags: 0,
                                                 blockBufferOut: &block) == noErr, let block,
              CMBlockBufferReplaceDataBytes(with: bytes, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes.count) == noErr,
              CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: desc, sampleCount: 1,
                                        sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 1,
                                        sampleSizeArray: &size, sampleBufferOut: &sample) == noErr, let sample else {
            print("display: -SillLayerFail: could not make the frame"); return
        }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as NSArray?,
           let first = attachments.firstObject as? NSMutableDictionary {
            first[kCMSampleAttachmentKey_DisplayImmediately as String] = true
        }
        print("display: -SillLayerFail: a frame that cannot decode goes onto the layer now")
        displayLayer.enqueue(sample)
    }
    #endif
}

struct StreamView: UIViewRepresentable {
    let client: StreamClient
    /// The picture's zoom, which the sprite counters (`HEVCDisplayView.setZoom`).
    var zoom = StreamZoom()

    /// Hosts the client's single display view. SwiftUI may build the new layout's host before it
    /// dismantles the old one, so detach the view from wherever it was first.
    func makeUIView(context: Context) -> HEVCDisplayView {
        let view = client.displayView
        view.removeFromSuperview()
        #if DEBUG
        view.attachDiagnostics(to: client)
        #endif
        wirePointer(view)
        view.setZoom(zoom)
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

    func updateUIView(_ uiView: HEVCDisplayView, context: Context) { uiView.setZoom(zoom) }
}

// MARK: - The picture's zoom

/// The picture's zoom for one stream screen (StreamZoom; issue #65): StreamScreen's, so a turn keeps it
/// and the next session starts at 1×. The input view reads it for every touch and writes it while two
/// fingers pinch or move the picture (InputOverlay's `readZoom` and `writeZoom`); only
/// `ZoomedStreamView` watches it, so a pinch redraws the picture's transform and nothing else of the
/// stream screen.
final class StreamZoomModel: ObservableObject {
    @Published private(set) var zoom = StreamZoom()

    func set(_ new: StreamZoom) {
        if new != zoom { zoom = new }
    }

    /// Another source, whoever picked it: the whole picture.
    func reset() {
        var z = zoom
        z.reset()
        set(z)
    }

    /// The picture's pane is another size: the zoom stays on the same point of the picture.
    func paneResized(to size: CGSize) {
        var z = zoom
        z.resized(to: size)
        set(z)
    }
}

/// The stream's view as the picture's zoom shows it: scaled about the pane's middle and moved
/// (`.scaleEffect(scale).offset(offset)`, which `StreamZoom`'s mapping is the inverse of), inside the
/// pane's clip; the pointer sprite at its own size (`StreamView.zoom`).
struct ZoomedStreamView: View {
    let client: StreamClient
    @ObservedObject var zoom: StreamZoomModel

    var body: some View {
        StreamView(client: client, zoom: zoom.zoom)
            .onGeometryChange(for: CGSize.self, of: { $0.size }) { zoom.paneResized(to: $0) }
            .scaleEffect(zoom.zoom.scale)
            .offset(zoom.zoom.offset)
            // Drawn past the pane when zoomed, and a clip does not clip hit testing: never a touch's target
            // (sideways the bar comes before the picture, and its buttons' touches must stay theirs).
            .allowsHitTesting(false)
    }
}
