import AVFoundation
import CoreMedia
import QuartzCore
import StreamProtocol

/// The stream's decoding, shared by the iOS app's and the Mac client's display views: the host's
/// HEVC parameter sets become a format description, each frame a sample buffer shown as soon as it
/// decodes, into an AVSampleBufferDisplayLayer, which decodes HEVC in hardware itself. Nothing
/// here draws; the views own the layer, the pointer sprite and the layout.
///
/// `apply`, `enqueue` and `clear` run on the network queue (AVSampleBufferDisplayLayer's enqueue and
/// flush are documented as safe off main); `onVideoSize` is called on main.
final class HEVCSampleFeed {
    let layer: AVSampleBufferDisplayLayer
    /// The streamed frame's pixel size, on main, whenever new parameter sets arrive.
    var onVideoSize: ((CGSize) -> Void)?
    /// The session ended (`clear`), on main: the frame size is zero again.
    var onCleared: (() -> Void)?

    private var formatDescription: CMVideoFormatDescription?
    private var waitingForKeyframe = true
    private var lastParameterSets: Data?

    init(layer: AVSampleBufferDisplayLayer) {
        self.layer = layer
        layer.videoGravity = .resizeAspect
    }

    /// Where `resizeAspect` draws a `videoSize` frame inside `bounds`: the letterboxed rect, which
    /// is what maps a touch or a click to a fraction of the frame. `.zero` while the video size is
    /// unknown, so callers can tell "no video" from "top left".
    static func videoRect(in bounds: CGRect, videoSize: CGSize) -> CGRect {
        guard videoSize.width > 0, videoSize.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let scale = min(bounds.width / videoSize.width, bounds.height / videoSize.height)
        let size = CGSize(width: videoSize.width * scale, height: videoSize.height * scale)
        return CGRect(x: bounds.minX + (bounds.width - size.width) / 2,
                      y: bounds.minY + (bounds.height - size.height) / 2,
                      width: size.width, height: size.height)
    }

    /// A macOS-style arrow, about 20 pt tall, its tip at the origin (y down): the pointer sprite's
    /// shape when the Mac has sent no cursor shape.
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
        DispatchQueue.main.async { [weak self] in self?.onVideoSize?(size) }
        // Remove the last frame too: switching sources should show black until the new keyframe,
        // not the previous window frozen in place.
        layer.flushAndRemoveImage()
    }

    /// Session over: drop the picture and forget the format so the next Mac starts clean.
    func clear() {
        formatDescription = nil
        lastParameterSets = nil
        waitingForKeyframe = true
        layer.flushAndRemoveImage()
        DispatchQueue.main.async { [weak self] in self?.onCleared?() }
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

        if layer.status == .failed {
            print("display layer failed: \(String(describing: layer.error))")
            layer.flush()
            waitingForKeyframe = true
            return
        }
        layer.enqueue(sample)
    }
}
