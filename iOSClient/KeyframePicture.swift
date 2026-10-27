import Foundation
import CoreGraphics
import CoreMedia
import CoreVideo
import VideoToolbox
import StreamProtocol

/// A saved Mac's tile picture (ConnectionList, issue #116): the session's last keyframe, decoded here
/// with the parameter sets it came with, scaled to the tile's size. Never a snapshot of the screen: on
/// a device the display layer's video is composited outside the app's own drawing, so
/// `drawHierarchy` drew black where the picture was (the simulator composites it in software, which
/// is why every simulator photo of a tile looked right). A VTDecompressionSession of its own, made
/// for one frame and invalidated after it: in hardware on a device, in software in the simulator; the
/// display layer's decoder is never touched.
///
/// Off the main thread, on a queue of its own, one decode at a time, and given up after `bound`: a
/// decoder that never answers holds that queue's thread, never the caller, and every later decode
/// then gives up too. `done` runs once, on an arbitrary queue.
enum KeyframePicture {
    enum Failure: Error, CustomStringConvertible {
        /// The parameter sets made no format (CMVideoFormatDescriptionCreateFromHEVCParameterSets).
        case format(OSStatus)
        /// The frame made no sample.
        case sample(OSStatus)
        /// No decoder for the format (VTDecompressionSessionCreate).
        case session(OSStatus)
        /// The decoder refused the frame, or gave no picture for it.
        case decode(OSStatus)
        /// The picture could not be drawn at the tile's size.
        case image
        /// The decoded picture is black throughout (ConnectionList.looksBlack).
        case black
        /// No answer within the bound.
        case timedOut

        var description: String {
            switch self {
            case .format(let s): return "the parameter sets made no format (\(s))"
            case .sample(let s): return "the keyframe made no sample (\(s))"
            case .session(let s): return "no decoder for it (\(s))"
            case .decode(let s): return "the decode failed (\(s))"
            case .image: return "the picture could not be drawn"
            case .black: return "the decoded picture is black"
            case .timedOut: return "the decode gave no answer in time"
            }
        }
    }

    private static let queue = DispatchQueue(label: "sill.preview", qos: .utility)

    /// Decodes `frame`, one HEVC sample as the Mac sends it (its NAL units each behind a big-endian
    /// length of `parameterSets.nalUnitHeaderLength` bytes), and gives its picture at the tile's size
    /// for the frame's own (ConnectionList.previewPixels), or why there is none.
    static func make(frame: Data, parameterSets: ParameterSets, bound: TimeInterval,
                     done: @escaping (Result<CGImage, Failure>) -> Void) {
        let once = Once(done)
        // The bound is kept on another queue: a decode that never returns holds its own queue.
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + bound) { once.call(.failure(.timedOut)) }
        queue.async { once.call(picture(frame: frame, parameterSets: parameterSets)) }
    }

    /// The whole decode, synchronously.
    static func picture(frame: Data, parameterSets: ParameterSets) -> Result<CGImage, Failure> {
        let format: CMVideoFormatDescription
        switch formatDescription(parameterSets) {
        case .success(let f): format = f
        case .failure(let e): return .failure(e)
        }
        let dimensions = CMVideoFormatDescriptionGetDimensions(format)
        guard let (width, height) = ConnectionList.previewPixels(video: CGSize(width: CGFloat(dimensions.width),
                                                                               height: CGFloat(dimensions.height)))
        else { return .failure(.format(-1)) }
        let sample: CMSampleBuffer
        switch sampleBuffer(frame, format: format) {
        case .success(let s): sample = s
        case .failure(let e): return .failure(e)
        }
        // The decoder's own picture at the tile's size, in BGRA: VideoToolbox scales it, so a 5K frame
        // never has to be held whole in memory as RGB. Should that fail, the frame is decoded once more
        // at its own size, and the drawing below scales it.
        var decoded = decode(sample, format: format, size: (width, height))
        if case .failure = decoded { decoded = decode(sample, format: format, size: nil) }
        let buffer: CVImageBuffer
        switch decoded {
        case .success(let b): buffer = b
        case .failure(let e): return .failure(e)
        }
        var full: CGImage?
        guard VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &full) == noErr, let full else { return .failure(.image) }
        // Drawn into a bitmap of the tile's size: the pixels the black test reads and the JPEG is made of.
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return .failure(.image) }
        context.interpolationQuality = .high
        context.draw(full, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return .failure(.image) }
        // In memory B, G, R, then the skipped byte: the colour first, as looksBlack reads it.
        let pixels = UnsafeRawBufferPointer(start: data, count: context.bytesPerRow * height)
        if ConnectionList.looksBlack(pixels, width: width, height: height, bytesPerRow: context.bytesPerRow) { return .failure(.black) }
        guard let image = context.makeImage() else { return .failure(.image) }
        return .success(image)
    }

    /// The format the parameter sets give, as HEVCDisplayView's `apply` makes it.
    private static func formatDescription(_ ps: ParameterSets) -> Result<CMVideoFormatDescription, Failure> {
        guard !ps.sets.isEmpty, ps.sets.allSatisfy({ !$0.isEmpty }) else { return .failure(.format(-1)) }
        let buffers = ps.sets.map { set -> UnsafeMutablePointer<UInt8> in
            let p = UnsafeMutablePointer<UInt8>.allocate(capacity: set.count)
            set.copyBytes(to: p, count: set.count)
            return p
        }
        defer { buffers.forEach { $0.deallocate() } }
        var desc: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(
            allocator: nil, parameterSetCount: buffers.count, parameterSetPointers: buffers.map { UnsafePointer($0) },
            parameterSetSizes: ps.sets.map(\.count), nalUnitHeaderLength: Int32(ps.nalUnitHeaderLength),
            extensions: nil, formatDescriptionOut: &desc)
        guard status == noErr, let desc else { return .failure(.format(status)) }
        return .success(desc)
    }

    /// The frame as one sample of that format, as HEVCDisplayView's `enqueue` makes it.
    private static func sampleBuffer(_ frame: Data, format: CMVideoFormatDescription) -> Result<CMSampleBuffer, Failure> {
        let count = frame.count
        guard count > 0 else { return .failure(.sample(-1)) }
        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: count, blockAllocator: nil,
                                                        customBlockSource: nil, offsetToData: 0, dataLength: count, flags: 0,
                                                        blockBufferOut: &block)
        guard status == noErr, let block else { return .failure(.sample(status)) }
        status = CMBlockBufferAssureBlockMemory(block)
        guard status == noErr else { return .failure(.sample(status)) }
        status = frame.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: count)
        }
        guard status == noErr else { return .failure(.sample(status)) }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
        var size = count
        var sample: CMSampleBuffer?
        status = CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1,
                                           sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                           sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample)
        guard status == noErr, let sample else { return .failure(.sample(status)) }
        return .success(sample)
    }

    /// One frame through a session made for it: its picture in BGRA, at `size` when given.
    private static func decode(_ sample: CMSampleBuffer, format: CMVideoFormatDescription, size: (Int, Int)?) -> Result<CVImageBuffer, Failure> {
        var attributes: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
                                           kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
        if let size {
            attributes[kCVPixelBufferWidthKey] = size.0
            attributes[kCVPixelBufferHeightKey] = size.1
        }
        var made: VTDecompressionSession?
        var status = VTDecompressionSessionCreate(allocator: nil, formatDescription: format, decoderSpecification: nil,
                                                  imageBufferAttributes: attributes as CFDictionary, outputCallback: nil,
                                                  decompressionSessionOut: &made)
        guard status == noErr, let session = made else { return .failure(.session(status)) }
        defer { VTDecompressionSessionInvalidate(session) }
        let result = Box()
        var info = VTDecodeInfoFlags()
        status = VTDecompressionSessionDecodeFrame(session, sampleBuffer: sample, flags: [], infoFlagsOut: &info) { decodeStatus, flags, image, _, _ in
            result.set(decodeStatus, flags.contains(.frameDropped) ? nil : image)
        }
        guard status == noErr else { return .failure(.decode(status)) }
        // Asked without asynchronous decompression the handler has run by now; waited for all the same.
        VTDecompressionSessionWaitForAsynchronousFrames(session)
        let (decodeStatus, image) = result.get()
        guard decodeStatus == noErr else { return .failure(.decode(decodeStatus)) }
        guard let image else { return .failure(.decode(-1)) }
        return .success(image)
    }

    /// The decoder's answer, from whatever thread its handler runs on.
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var status: OSStatus = -1
        private var image: CVImageBuffer?
        func set(_ s: OSStatus, _ i: CVImageBuffer?) { lock.lock(); status = s; image = i; lock.unlock() }
        func get() -> (OSStatus, CVImageBuffer?) { lock.lock(); defer { lock.unlock() }; return (status, image) }
    }

    /// `done` once: the decode's answer or the bound's, whichever comes first.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done: ((Result<CGImage, Failure>) -> Void)?
        init(_ done: @escaping (Result<CGImage, Failure>) -> Void) { self.done = done }
        func call(_ result: Result<CGImage, Failure>) {
            lock.lock(); let d = done; done = nil; lock.unlock()
            d?(result)
        }
    }
}
