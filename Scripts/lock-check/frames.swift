// TEST ONLY (docs/locked-mac-plan.md): decodes the keyframes `sillclient.py --dump=DIR` saved, each with
// the parameter sets it came after, on VideoToolbox's software HEVC decoder (never the Mac's media engine),
// and prints each one's size and its luma: the mean, the largest value, and the share of pixels above 16.
// A locked Mac's placeholder is black (mean and max near 0, nothing above 16); the synthetic test pattern
// is grey with a bright bar (mean near 96), and with SILL_TEST_PATTERN=noise a square of noise besides.
// Compiled with Sources/StreamProtocol (its ParameterSets) by build.sh.
//   frames DIR      one line per keyframe in DIR/index.tsv, in arrival order
import Foundation
import CoreMedia
import CoreVideo
import VideoToolbox

guard CommandLine.arguments.count == 2 else {
    print("usage: frames DIR (a sillclient.py --dump directory)")
    exit(2)
}
let dir = CommandLine.arguments[1]
guard let index = try? String(contentsOfFile: dir + "/index.tsv", encoding: .utf8) else {
    print("frames: no \(dir)/index.tsv")
    exit(2)
}

struct Stats { var width = 0, height = 0; var mean = 0.0; var max = 0; var above16 = 0.0 }

/// The luma plane's statistics of a decoded frame.
func stats(_ buffer: CVPixelBuffer) -> Stats {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    var s = Stats()
    s.width = CVPixelBufferGetWidthOfPlane(buffer, 0)
    s.height = CVPixelBufferGetHeightOfPlane(buffer, 0)
    guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return s }
    let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
    var sum = 0, bright = 0, top = 0
    for row in 0..<s.height {
        let p = base.advanced(by: row * stride).assumingMemoryBound(to: UInt8.self)
        for x in 0..<s.width {
            let v = Int(p[x])
            sum += v
            if v > 16 { bright += 1 }
            if v > top { top = v }
        }
    }
    let n = max(1, s.width * s.height)
    s.mean = Double(sum) / Double(n)
    s.max = top
    s.above16 = Double(bright) / Double(n) * 100
    return s
}

/// One keyframe decoded with its parameter sets, synchronously; nil and why when it does not decode.
func decode(key: Data, sets: ParameterSets) -> (Stats?, String?) {
    let buffers = sets.sets.map { set -> UnsafeMutablePointer<UInt8> in
        let p = UnsafeMutablePointer<UInt8>.allocate(capacity: set.count)
        set.copyBytes(to: p, count: set.count)
        return p
    }
    defer { buffers.forEach { $0.deallocate() } }
    var format: CMVideoFormatDescription?
    let made = CMVideoFormatDescriptionCreateFromHEVCParameterSets(
        allocator: nil, parameterSetCount: buffers.count, parameterSetPointers: buffers.map { UnsafePointer($0) },
        parameterSetSizes: sets.sets.map(\.count), nalUnitHeaderLength: Int32(sets.nalUnitHeaderLength),
        extensions: nil, formatDescriptionOut: &format)
    guard made == noErr, let format else { return (nil, "format description \(made)") }
    let spec: [CFString: Any] = [kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder: false]
    let output: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
    var session: VTDecompressionSession?
    let opened = VTDecompressionSessionCreate(allocator: nil, formatDescription: format, decoderSpecification: spec as CFDictionary,
                                              imageBufferAttributes: output as CFDictionary, outputCallback: nil,
                                              decompressionSessionOut: &session)
    guard opened == noErr, let session else { return (nil, "decoder \(opened)") }
    defer { VTDecompressionSessionInvalidate(session) }
    var block: CMBlockBuffer?
    guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: key.count, blockAllocator: nil,
                                             customBlockSource: nil, offsetToData: 0, dataLength: key.count, flags: 0,
                                             blockBufferOut: &block) == noErr, let block,
          CMBlockBufferAssureBlockMemory(block) == noErr else { return (nil, "block") }
    let copied = key.withUnsafeBytes { CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: key.count) }
    guard copied == noErr else { return (nil, "copy \(copied)") }
    var sample: CMSampleBuffer?
    var size = key.count
    guard CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1, sampleTimingEntryCount: 0,
                                    sampleTimingArray: nil, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample) == noErr,
          let sample else { return (nil, "sample") }
    var result: Stats?
    var problem: String?
    let decoded = VTDecompressionSessionDecodeFrame(session, sampleBuffer: sample, flags: [], infoFlagsOut: nil) { status, _, image, _, _ in
        if status != noErr { problem = "decode \(status)"; return }
        guard let image else { problem = "no image"; return }
        result = stats(image)
    }
    VTDecompressionSessionWaitForAsynchronousFrames(session)
    if decoded != noErr { return (nil, "decode \(decoded)") }
    return (result, problem)
}

var lines = 0
for line in index.split(separator: "\n") {
    let parts = line.split(separator: "\t").map(String.init)
    guard parts.count >= 3 else { continue }
    let at = parts[2]
    guard let key = FileManager.default.contents(atPath: dir + "/" + parts[0]),
          let psData = FileManager.default.contents(atPath: dir + "/" + parts[1]),
          let sets = ParameterSets(encoded: psData) else {
        print("\(parts[0]) at \(at) s: missing or undecodable files")
        continue
    }
    let (s, problem) = decode(key: key, sets: sets)
    lines += 1
    if let s {
        print(String(format: "%@ at %@ s: %d×%d, %d bytes, luma mean %.2f, max %d, %.3f%% above 16", parts[0], at, s.width, s.height, key.count,
                     s.mean, s.max, s.above16))
    } else {
        print("\(parts[0]) at \(at) s: did not decode (\(problem ?? "?"))")
    }
}
if lines == 0 { print("frames: no keyframe in \(dir)") }
