// Checks the camera's test fixture (make-fixture.swift's) as the Mac's receiver will read it: its parameter sets
// make a format, and each of its frames, in order, decodes on VideoToolbox's SOFTWARE decoder into a 640×360
// picture whose top row of 16 blocks gives its own number (white 1, black 0). No encoder, no hardware decoder.
//
//   swift Scripts/camera/check-fixture.swift Scripts/camera/fixture-640x360.bin
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

guard CommandLine.arguments.count == 2, let file = try? Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])),
      file.prefix(8) == Data("SILLCAM1".utf8) else { print("usage: check-fixture.swift FIXTURE.bin (make-fixture.swift's)"); exit(2) }
func u16(_ at: Int) -> Int { Int(file[at]) << 8 | Int(file[at + 1]) }
func u32(_ at: Int) -> Int { u16(at) << 16 | u16(at + 2) }
let width = u16(8), height = u16(10), count = u16(14)
var at = 16
let psLength = u32(at); let ps = file.subdata(in: at + 4..<at + 4 + psLength); at += 4 + psLength
var frames: [(key: Bool, data: Data)] = []
for _ in 0..<count { let n = u32(at + 1); frames.append((file[at] == 1, file.subdata(in: at + 5..<at + 5 + n))); at += 5 + n }
guard at == file.count else { print("FAIL: \(file.count - at) bytes after the frames"); exit(1) }

// The parameter sets (ParameterSets.encoded()) as a format.
let nal = Int32(ps[0]); var sets: [Data] = []; var p = 2
for _ in 0..<Int(ps[1]) { let n = Int(ps[p]) << 8 | Int(ps[p + 1]); sets.append(ps.subdata(in: p + 2..<p + 2 + n)); p += 2 + n }
var desc: CMVideoFormatDescription?
let pointers = sets.map { s -> UnsafeMutablePointer<UInt8> in let m = UnsafeMutablePointer<UInt8>.allocate(capacity: s.count); s.copyBytes(to: m, count: s.count); return m }
var status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(allocator: nil, parameterSetCount: sets.count,
    parameterSetPointers: pointers.map { UnsafePointer($0) }, parameterSetSizes: sets.map(\.count), nalUnitHeaderLength: nal,
    extensions: nil, formatDescriptionOut: &desc)
guard status == noErr, let desc else { print("FAIL: the parameter sets make no format (\(status))"); exit(1) }
let attributes: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA, kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
let spec: [CFString: Any] = [kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder: false]
var made: VTDecompressionSession?
status = VTDecompressionSessionCreate(allocator: nil, formatDescription: desc, decoderSpecification: spec as CFDictionary,
                                      imageBufferAttributes: attributes as CFDictionary, outputCallback: nil, decompressionSessionOut: &made)
guard status == noErr, let session = made else { print("FAIL: no software decoder (\(status))"); exit(1) }

var failures = 0
for (i, f) in frames.enumerated() {
    var block: CMBlockBuffer?
    CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: f.data.count, blockAllocator: nil, customBlockSource: nil,
                                       offsetToData: 0, dataLength: f.data.count, flags: 0, blockBufferOut: &block)
    CMBlockBufferAssureBlockMemory(block!)
    f.data.withUnsafeBytes { _ = CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block!, offsetIntoDestination: 0, dataLength: f.data.count) }
    var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMTime(value: CMTimeValue(i), timescale: 30), decodeTimeStamp: .invalid)
    var size = f.data.count
    var sample: CMSampleBuffer?
    CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: desc, sampleCount: 1, sampleTimingEntryCount: 1,
                              sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample)
    var number = -1, shape = (0, 0), decodeStatus: OSStatus = -1
    status = VTDecompressionSessionDecodeFrame(session, sampleBuffer: sample!, flags: [], infoFlagsOut: nil) { s, _, image, _, _ in
        decodeStatus = s
        guard s == noErr, let image else { return }
        shape = (CVPixelBufferGetWidth(image), CVPixelBufferGetHeight(image))
        CVPixelBufferLockBaseAddress(image, .readOnly)
        let base = CVPixelBufferGetBaseAddress(image)!.assumingMemoryBound(to: UInt8.self)
        let row = CVPixelBufferGetBytesPerRow(image)
        number = (0..<16).reduce(0) { n, b in
            let px = base + 12 * row + (b * 40 + 20) * 4        // the middle of block b, row 12
            return n << 1 | (Int(px[0]) + Int(px[1]) + Int(px[2]) > 3 * 128 ? 1 : 0)
        }
        CVPixelBufferUnlockBaseAddress(image, .readOnly)
    }
    VTDecompressionSessionWaitForAsynchronousFrames(session)
    if status != noErr || decodeStatus != noErr || number != i || shape != (width, height) {
        failures += 1
        print("FAIL: frame \(i) (key \(f.key)): status \(status)/\(decodeStatus), \(shape.0)×\(shape.1), reads as \(number)")
    }
}
VTDecompressionSessionInvalidate(session)
print(failures == 0 ? "ok: \(count) frames of \(width)×\(height) (\(frames.filter(\.key).count) keyframe) decode in order on the software decoder, each reading its own number"
                    : "\(failures) of \(count) frames FAILED")
exit(failures == 0 ? 0 : 1)
