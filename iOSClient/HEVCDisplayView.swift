import UIKit
import AVFoundation
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
    }
    required init?(coder: NSCoder) { fatalError() }

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
        DispatchQueue.main.async { [weak self] in self?.onVideoSize?(size) }
        // Remove the last frame too: switching sources should show black until the new keyframe,
        // not the previous window frozen in place.
        displayLayer.flushAndRemoveImage()
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

    func makeUIView(context: Context) -> HEVCDisplayView {
        let view = HEVCDisplayView(frame: .zero)
        view.onVideoSize = { [weak client] size in client?.videoSize = size }
        client.onParameterSets = { ps in view.apply(ps) }
        client.onFrame = { data, isKey in view.enqueue(data, isKeyframe: isKey) }
        return view
    }

    func updateUIView(_ uiView: HEVCDisplayView, context: Context) {}
}
