// The camera's test fixture (docs/camera-plan.md §13.2): three seconds of a moving 640×360 test pattern
// at 30 fps, encoded once with VideoToolbox's SOFTWARE HEVC encoder (never the Mac's hardware encoder,
// which Noah's stream owns: the session is refused if VideoToolbox gives a hardware one), as a device's
// camera sends it: HEVC Main, real time, no B-frames, one keyframe first and none after, 400 kbit/s.
// sillclient.py's --camera=FILE plays it to a test host as kind 46.
//
//   swift Scripts/camera/make-fixture.swift Scripts/camera/fixture-640x360.bin
//
// The file: "SILLCAM1", then big endian u16 width, u16 height, u16 fps, u16 frames, u32 and the parameter
// sets (StreamProtocol's ParameterSets.encoded(): u8 NAL length, u8 count, each u16 and its bytes), then
// per frame u8 keyframe, u32 and the access unit (4-byte lengths before each NAL unit). Each frame shows
// the frame's number as 16 blocks along its top (white 1, black 0, most significant first), so a decoded
// picture says which frame it is.
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

let width = 640, height = 360, fps = 30, count = 90
guard CommandLine.arguments.count == 2 else { print("usage: make-fixture.swift OUT.bin"); exit(2) }
let out = URL(fileURLWithPath: CommandLine.arguments[1])

var made: VTCompressionSession?
let spec: [CFString: Any] = [kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder: false,
                             kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: false]
var status = VTCompressionSessionCreate(allocator: nil, width: Int32(width), height: Int32(height), codecType: kCMVideoCodecType_HEVC,
                                        encoderSpecification: spec as CFDictionary, imageBufferAttributes: nil,
                                        compressedDataAllocator: nil, outputCallback: nil, refcon: nil, compressionSessionOut: &made)
guard status == noErr, let session = made else { print("no software HEVC encoder: \(status)"); exit(1) }
var hardware: CFTypeRef?
_ = withUnsafeMutablePointer(to: &hardware) {
    VTSessionCopyProperty(session, key: kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder, allocator: nil, valueOut: $0)
}
if (hardware as? Bool) == true { print("VideoToolbox gave a hardware session; refused (the stream's encoder is Noah's)."); exit(1) }
func set(_ key: CFString, _ value: CFTypeRef) { VTSessionSetProperty(session, key: key, value: value) }
set(kVTCompressionPropertyKey_RealTime, kCFBooleanTrue)
set(kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_HEVC_Main_AutoLevel)
set(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse)
set(kVTCompressionPropertyKey_MaxKeyFrameInterval, 100_000 as CFNumber)
set(kVTCompressionPropertyKey_ExpectedFrameRate, fps as CFNumber)
set(kVTCompressionPropertyKey_AverageBitRate, 400_000 as CFNumber)
VTCompressionSessionPrepareToEncodeFrames(session)

var frames: [(key: Bool, data: Data)] = []
var parameterSets: Data?
let lock = NSLock()

/// One frame of the pattern: diagonal colour bands that move, and the frame's number in blocks.
func picture(_ n: Int) -> CVPixelBuffer {
    var pb: CVPixelBuffer?
    CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pb)
    let buffer = pb!
    CVPixelBufferLockBaseAddress(buffer, [])
    let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    let row = CVPixelBufferGetBytesPerRow(buffer)
    for y in 0..<height {
        for x in 0..<width {
            let p = base + y * row + x * 4
            let band = ((x + y + n * 6) / 40) % 6
            let colours: [(UInt8, UInt8, UInt8)] = [(220, 40, 40), (40, 200, 60), (40, 70, 220), (230, 210, 40), (200, 60, 200), (60, 200, 210)]
            var (r, g, b) = colours[band]
            if y < 24 {   // the frame number, 16 blocks of 40 px
                let bit = (n >> (15 - x / 40)) & 1
                (r, g, b) = bit == 1 ? (255, 255, 255) : (0, 0, 0)
            }
            p[0] = b; p[1] = g; p[2] = r; p[3] = 255
        }
    }
    CVPixelBufferUnlockBaseAddress(buffer, [])
    return buffer
}

for n in 0..<count {
    let pts = CMTime(value: CMTimeValue(n), timescale: CMTimeScale(fps))
    status = VTCompressionSessionEncodeFrame(session, imageBuffer: picture(n), presentationTimeStamp: pts, duration: CMTime(value: 1, timescale: CMTimeScale(fps)),
                                             frameProperties: nil, infoFlagsOut: nil) { st, _, sample in
        guard st == noErr, let sample, let block = CMSampleBufferGetDataBuffer(sample) else { print("encode failed: \(st)"); exit(1) }
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]]
        let key = !(attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false)
        var length = 0
        var pointer: UnsafeMutablePointer<CChar>?
        CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer)
        let data = Data(bytes: pointer!, count: length)
        lock.lock()
        if key, parameterSets == nil, let desc = CMSampleBufferGetFormatDescription(sample) {
            var setCount = 0, nal: Int32 = 0
            CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(desc, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil,
                                                               parameterSetCountOut: &setCount, nalUnitHeaderLengthOut: &nal)
            var ps = Data([UInt8(nal), UInt8(setCount)])
            for i in 0..<setCount {
                var p: UnsafePointer<UInt8>?
                var size = 0
                CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(desc, parameterSetIndex: i, parameterSetPointerOut: &p, parameterSetSizeOut: &size,
                                                                   parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil)
                ps.append(UInt8(size >> 8)); ps.append(UInt8(size & 0xFF))
                ps.append(p!, count: size)
            }
            parameterSets = ps
        }
        frames.append((key, data))
        lock.unlock()
    }
    guard status == noErr else { print("encode failed: \(status)"); exit(1) }
}
VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
VTCompressionSessionInvalidate(session)

guard let ps = parameterSets, frames.count == count, frames.first?.key == true else {
    print("expected \(count) frames, the first a keyframe; got \(frames.count)"); exit(1)
}
var file = Data("SILLCAM1".utf8)
func u16(_ v: Int) { file.append(UInt8(v >> 8)); file.append(UInt8(v & 0xFF)) }
func u32(_ v: Int) { for s in [24, 16, 8, 0] { file.append(UInt8((v >> s) & 0xFF)) } }
u16(width); u16(height); u16(fps); u16(count)
u32(ps.count); file.append(ps)
for f in frames { file.append(f.key ? 1 : 0); u32(f.data.count); file.append(f.data) }
try file.write(to: out)
print("\(out.path): \(count) frames (\(frames.filter(\.key).count) keyframes), \(file.count) bytes, parameter sets \(ps.count) bytes")
