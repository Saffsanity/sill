import Foundation
import Metal
import QuartzCore
import CoreMedia
import CoreVideo
import VideoToolbox

/// Picture Smoothing's renderer, for every level but Automatic (PictureSmoothing): the stream decoded
/// here with VideoToolbox, to BGRA, and each frame drawn with Metal as soon as it decodes, scaled by
/// the level's filter in two passes (StreamShader: across into an intermediate texture, then down into
/// the picture's aspect-fit rectangle, as the system layer's `.resizeAspect`). Nil from `init` when
/// this device has no Metal or the shader does not build: the system layer draws then, as before.
///
/// Threads: `decode`, `setFormat` and `clear` run on the stream's serial queue (HEVCDisplayView's
/// enqueue); `layout` and `setFilter` are called from main and hop to a serial render queue for any
/// redraw, so `nextDrawable()` never blocks the main thread and every decode + Metal draw runs in
/// strict frame order with no async reordering.
final class MetalStreamRenderer {
    let layer = CAMetalLayer()
    /// Called when an invalidated decoder (after backgrounding) was recreated and needs a keyframe.
    var onNeedsKeyframe: (() -> Void)?

    private let queue: MTLCommandQueue
    private let toIntermediate: MTLRenderPipelineState
    private let toDrawable: MTLRenderPipelineState
    private let textures: CVMetalTextureCache
    private let device: MTLDevice

    private let lock = NSLock()
    private var session: VTDecompressionSession?
    private var format: CMVideoFormatDescription?
    private var filter: PictureSmoothing.Filter
    /// The picture's rectangle in the drawable's pixels, and the drawable's size (`layout`).
    private var target: (rect: CGRect, size: CGSize)?
    /// The last frame decoded, drawn again when the layout or the filter changes.
    private var last: CVPixelBuffer?
    /// A frame of this stream did not decode, and that was said: once a stream, not every frame.
    private var decodeFailureSaid = false
    private var intermediate: MTLTexture?
    private var colorSpaceSet = false

    init?(filter: PictureSmoothing.Filter) {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            print("smoothing: no Metal device")
            return nil
        }
        do {
            let library = try device.makeLibrary(source: StreamShader.source, options: nil)
            func pipeline(_ format: MTLPixelFormat) throws -> MTLRenderPipelineState {
                let d = MTLRenderPipelineDescriptor()
                d.vertexFunction = library.makeFunction(name: StreamShader.vertex)
                d.fragmentFunction = library.makeFunction(name: StreamShader.fragment)
                d.colorAttachments[0].pixelFormat = format
                return try device.makeRenderPipelineState(descriptor: d)
            }
            toIntermediate = try pipeline(.rgba16Float)      // ringing kept between the passes
            toDrawable = try pipeline(.bgra8Unorm)
        } catch {
            print("smoothing: the shader did not build: \(error)")
            return nil
        }
        var cache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(nil, nil, device, nil, &cache) == kCVReturnSuccess, let cache else {
            print("smoothing: no texture cache")
            return nil
        }
        self.device = device
        self.queue = queue
        self.textures = cache
        self.filter = filter
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.isOpaque = true
        layer.backgroundColor = CGColor(gray: 0, alpha: 1)
    }

    deinit {
        if let session { VTDecompressionSessionInvalidate(session) }
    }

    /// On main (or any thread); redraws off the main thread so `nextDrawable()` never stalls UI.
    func setFilter(_ filter: PictureSmoothing.Filter, on renderQueue: DispatchQueue) {
        renderQueue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.filter = filter
            let frame = self.last
            self.lock.unlock()
            if let frame { self.draw(frame) }
        }
    }

    /// A new stream's format: a decoder for it (the old one goes) and the old picture cleared.
    /// On the stream's queue.
    func setFormat(_ format: CMVideoFormatDescription) {
        lock.lock()
        let old = session
        session = nil
        self.format = format
        decodeFailureSaid = false
        lock.unlock()
        if let old { VTDecompressionSessionInvalidate(old) }
        let made = Self.makeSession(format)
        lock.lock()
        session = made
        last = nil
        lock.unlock()
        drawBlack()
    }

    private static func makeSession(_ format: CMVideoFormatDescription) -> VTDecompressionSession? {
        let attributes: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                                            kCVPixelBufferMetalCompatibilityKey: true]
        var made: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(allocator: nil, formatDescription: format, decoderSpecification: nil,
                                                  imageBufferAttributes: attributes as CFDictionary, outputCallback: nil,
                                                  decompressionSessionOut: &made)
        if status != noErr { print("smoothing: no decoder for this stream (\(status))") }
        return made
    }

    /// One frame of the stream, decoded synchronously on the stream's queue so frames draw in strict
    /// arrival order. If iOS invalidated the session in the background, recreates it and asks for a
    /// keyframe.
    func decode(_ sample: CMSampleBuffer) {
        lock.lock()
        var current = session
        let fmt = format
        lock.unlock()
        if current == nil, let fmt {
            current = Self.makeSession(fmt)
            lock.lock(); session = current; lock.unlock()
        }
        guard let current else { return }
        var decoded: CVPixelBuffer?
        let status = VTDecompressionSessionDecodeFrame(current, sampleBuffer: sample,
                                                       flags: [._1xRealTimePlayback],
                                                       infoFlagsOut: nil) { status, _, image, _, _ in
            if status == noErr { decoded = image }
        }
        if let decoded {
            draw(decoded)
            return
        }
        if PictureSmoothing.sessionBroken(status) {
            print("smoothing: decoder session invalidated (\(status)); recreating and asking for a keyframe")
            VTDecompressionSessionInvalidate(current)
            let rebuilt = fmt.flatMap(Self.makeSession)
            lock.lock()
            session = rebuilt
            last = nil
            decodeFailureSaid = false
            lock.unlock()
            onNeedsKeyframe?()
            return
        }
        guard status != noErr else { return }
        lock.lock(); let said = decodeFailureSaid; decodeFailureSaid = true; lock.unlock()
        if !said { print("smoothing: a frame of this stream did not decode (\(status)); said once a stream") }
    }

    /// Where the picture goes: the view's size in points, its scale, and the video's size in pixels.
    /// Called on main; drawable sizing and redraw run on `renderQueue` so they serialize with `decode`.
    func layout(bounds: CGRect, scale: CGFloat, videoSize: CGSize, on renderQueue: DispatchQueue) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = bounds
        layer.contentsScale = scale
        CATransaction.commit()
        let size = CGSize(width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded())
        let fit = HEVCDisplayView.videoRect(in: CGRect(origin: .zero, size: size), videoSize: videoSize).integral
        renderQueue.async { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.target = (size.width > 0 && size.height > 0 && fit.width > 0 && fit.height > 0) ? (fit, size) : nil
            let frame = self.last
            self.lock.unlock()
            if let frame { self.draw(frame) }
        }
    }

    /// The session ended: no decoder, no frame, black. On the stream's queue.
    func clear() {
        lock.lock()
        let old = session
        session = nil
        format = nil
        decodeFailureSaid = false
        lock.unlock()
        if let old { VTDecompressionSessionInvalidate(old) }
        lock.lock()
        last = nil
        intermediate = nil
        lock.unlock()
        drawBlack()
    }

    /// Clears the Metal layer to black without resetting `layer.contents` (which breaks CAMetalLayer's
    /// drawable presentation). On the stream's serial queue.
    private func drawBlack() {
        lock.lock(); let target = self.target; lock.unlock()
        guard let target else { return }
        if layer.drawableSize != target.size { layer.drawableSize = target.size }
        guard let drawable = layer.nextDrawable(), let buffer = queue.makeCommandBuffer() else { return }
        let d = MTLRenderPassDescriptor()
        d.colorAttachments[0].texture = drawable.texture
        d.colorAttachments[0].loadAction = .clear
        d.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        d.colorAttachments[0].storeAction = .store
        if let encoder = buffer.makeRenderCommandEncoder(descriptor: d) { encoder.endEncoding() }
        buffer.present(drawable)
        buffer.commit()
    }

    /// Draws one frame on the stream's serial queue.
    private func draw(_ image: CVPixelBuffer) {
        lock.lock()
        last = image
        let filter = self.filter, target = self.target
        let needColorSpace = !colorSpaceSet
        lock.unlock()
        guard let target else { return }
        if needColorSpace, let attachments = CVBufferCopyAttachments(image, .shouldPropagate),
           let space = CVImageBufferCreateColorSpaceFromAttachments(attachments)?.takeRetainedValue() {
            lock.lock(); colorSpaceSet = true; lock.unlock()
            DispatchQueue.main.async { [layer] in layer.colorspace = space }
        }
        if layer.drawableSize != target.size {
            layer.drawableSize = target.size
        }
        let width = CVPixelBufferGetWidth(image), height = CVPixelBufferGetHeight(image)
        var cvTexture: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(nil, textures, image, nil, .bgra8Unorm, width, height, 0, &cvTexture) == kCVReturnSuccess,
              let cvTexture, let source = CVMetalTextureGetTexture(cvTexture) else { return }
        let across = Int(target.rect.width)
        if intermediate?.width != across || intermediate?.height != height {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: across, height: height, mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]
            d.storageMode = .private
            intermediate = device.makeTexture(descriptor: d)
        }
        guard let intermediate, let drawable = layer.nextDrawable(), let buffer = queue.makeCommandBuffer() else { return }

        func pass(into texture: MTLTexture, pipeline: MTLRenderPipelineState, from src: MTLTexture, viewport: CGRect,
                  axis: Int32, clampOut: Bool, clear: Bool) {
            let d = MTLRenderPassDescriptor()
            d.colorAttachments[0].texture = texture
            d.colorAttachments[0].loadAction = clear ? .clear : .dontCare
            d.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
            d.colorAttachments[0].storeAction = .store
            guard let encoder = buffer.makeRenderCommandEncoder(descriptor: d) else { return }
            encoder.setRenderPipelineState(pipeline)
            encoder.setViewport(MTLViewport(originX: viewport.minX, originY: viewport.minY, width: viewport.width,
                                            height: viewport.height, znear: 0, zfar: 1))
            var p = StreamShader.Params(origin: SIMD2(Float(viewport.minX), Float(viewport.minY)),
                                        size: SIMD2(Float(viewport.width), Float(viewport.height)),
                                        filter: filter.shaderMode, axis: axis, clampOut: clampOut ? 1 : 0)
            encoder.setFragmentBytes(&p, length: MemoryLayout<StreamShader.Params>.stride, index: 0)
            encoder.setFragmentTexture(src, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }
        pass(into: intermediate, pipeline: toIntermediate, from: source,
             viewport: CGRect(x: 0, y: 0, width: across, height: height), axis: 0, clampOut: false, clear: false)
        pass(into: drawable.texture, pipeline: toDrawable, from: intermediate, viewport: target.rect, axis: 1, clampOut: true, clear: true)
        buffer.present(drawable)
        buffer.addCompletedHandler { _ in _ = cvTexture }     // the frame's texture lives until the GPU is done with it
        buffer.commit()
    }
}
