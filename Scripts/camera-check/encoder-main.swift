// The device's camera stream end to end on the Mac (docs/camera-plan.md §8, §13.2; encoder.sh compiles it with the
// app's own iOSClient/CameraEncoder.swift, CameraPattern.swift, CameraStream.swift and CameraPolicy.swift): pictures of
// CameraPattern through CameraStream into CameraEncoder on VideoToolbox's SOFTWARE HEVC encoder (CameraEncoder refuses a
// hardware session: the Mac's hardware encoder is Noah's stream's), and every frame CameraStream lets go decoded, in
// order, on VideoToolbox's software decoder from its epoch's format, as the Mac's CameraReceiver decodes them. No camera,
// no network, no hardware encoder.
//
// The script: 120 pictures at 30 fps, 640×360 (1.2 Mbit/s), the Mac's keyframe ask at picture 45, a move's fence over
// pictures 60 and 61 (skipped before the encoder), the device turned at picture 90 (360×640 from there: a new epoch).
// Judged: the encoder is software; each epoch's format comes right before its first frame, with valid parameter sets;
// keyframes exactly at each epoch's first frame and at the ask (the infinite GOP: none of the encoder's own); no frame
// held back (each one's output before the next picture goes in); every frame decodes at its epoch's size and shows the
// picture it was made from, in order, the fenced ones absent; every frame under 256 KB; the bitrate within the
// target's ceiling. With OUT given, epoch 0's frames are written as a SILLCAM1 fixture (make-fixture.swift's format),
// for sillclient.py's --camera.
//
//   Scripts/camera-check/encoder.sh [OUT.bin]
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

var failures = 0
func check(_ ok: Bool, _ what: String) {
    print((ok ? "ok   " : "FAIL ") + what)
    if !ok { failures += 1 }
}

let fps = 30
var stream = CameraStream()
let plan = CameraStream.Plan(fps: fps, bitrate: 1_200_000, position: "front")
_ = stream.run(plan, at: 0)
var encoder: CameraEncoder?
var hardwareSeen = false
var made = 0
/// What CameraStream let go, in order: an epoch's format, or a frame with the picture it was made from.
enum Out { case format(CameraFormat), frame(CameraFrame, key: Bool, picture: Int) }
var out: [Out] = []
var encodedKeys: [Int] = []            // the pictures encoded as keyframes, as CameraStream asked
let lock = NSLock()

func run(_ actions: [CameraStream.Action], picture: Int, image: CVPixelBuffer?) {
    for a in actions {
        switch a {
        case .encoder(let e, let bitrate):
            encoder?.flush()
            switch CameraEncoder.make(width: e.width, height: e.height, fps: e.fps, bitrate: bitrate, software: true) {
            case .success(let enc):
                encoder = enc
                made += 1
                if enc.hardware { hardwareSeen = true }
            case .failure(let why):
                print("FAIL no software encoder for \(e.width)x\(e.height): \(why)")
                exit(1)
            }
        case .noEncoder:
            encoder = nil
        case .encode(let key):
            guard let enc = encoder, let image else { continue }
            if key { encodedKeys.append(picture) }
            let serial = stream.encoder?.serial ?? -1
            let pts = CMTime(value: CMTimeValue(picture), timescale: CMTimeScale(fps))
            var result: (OSStatus, CameraEncoder.Output?)?
            let came = DispatchSemaphore(value: 0)
            let status = enc.encode(image, pts: pts, keyframe: key) { s, o in lock.lock(); result = (s, o); lock.unlock(); came.signal() }
            // The encoder holds no frame back (MaxFrameDelayCount 0): this frame's output comes before the next goes in.
            if status == noErr, came.wait(timeout: .now() + 2) == .timedOut { print("FAIL picture \(picture): the encoder held it back past 2 s"); exit(1) }
            lock.lock(); let r = result; lock.unlock()
            guard status == noErr, let (s, o) = r, s == noErr, let o else { stream.encodeFailed(serial: serial); continue }
            run(stream.encoded(serial: serial, data: o.data, keyframe: o.keyframe, parameterSets: o.parameterSets, fenced: false,
                               at: Double(picture) / Double(fps)), picture: picture, image: nil)
        case .format(let f):
            out.append(.format(f))
        case .frame(let f, let key):
            out.append(.frame(f, key: key, picture: picture))
        case .bitrate(let b):
            encoder?.setBitrate(b)
        }
    }
}

for n in 0..<120 {
    let t = Double(n) / Double(fps)
    if n == 45 { stream.keyframeAsked(at: t) }
    let (w, h) = n < 90 ? (640, 360) : (360, 640)
    guard let image = CameraPattern.picture(n, width: w, height: h) else { print("FAIL no picture"); exit(1) }
    let fenced = n == 60 || n == 61
    let acts = stream.picture(width: w, height: h, uplink: CameraStream.Uplink(fenced: fenced, unsent: 0, takenLastSecond: 1_000_000), at: t)
    run(acts, picture: n, image: image)
    if n % 30 == 29 { run(stream.closeSecond(at: t).1, picture: n, image: nil) }
}
encoder?.flush()

check(!hardwareSeen, "every encoder VideoToolbox gave is a software one (\(made) made)")
check(made == 2, "two encoders: the first picture's, and the turned device's (\(made))")
var formats: [CameraFormat] = []
var frames: [(CameraFrame, Bool, Int)] = []
var formatThenKey = true
for (i, o) in out.enumerated() {
    switch o {
    case .format(let f):
        formats.append(f)
        if i + 1 >= out.count { formatThenKey = false } else if case .frame(let fr, let k, _) = out[i + 1] { formatThenKey = formatThenKey && k && fr.epoch == f.epoch && fr.seq == 0 } else { formatThenKey = false }
    case .frame(let f, let k, let p): frames.append((f, k, p))
    }
}
check(formats.count == 2 && formats.allSatisfy { $0.isValid && $0.parameterSets.map(CameraCodec.validParameterSets) == true },
      "two formats, each valid with generation 1's parameter sets: \(formats.map { "\($0.epoch ?? -1): \($0.width ?? 0)x\($0.height ?? 0)" })")
check(formatThenKey, "each format right before its epoch's frame 0, a keyframe")
let keys = frames.filter { $0.1 }.map { $0.2 }
check(keys == [0, 45, 90], "keyframes exactly at the first picture, the Mac's ask and the turn: \(keys)")
check(encodedKeys == [0, 45, 90], "and CameraStream asked the encoder for exactly those: \(encodedKeys)")
let pictures = frames.map { $0.2 }
check(!pictures.contains(60) && !pictures.contains(61) && pictures.count == 118, "the two pictures at the fence skipped before the encoder, the other 118 sent")
check(frames.allSatisfy { $0.0.data.count <= CameraFrame.maxDataBytes && CameraMessage.frame($0.0).serialized() != nil },
      "every frame under 256 KB and on the wire (largest \(frames.map { $0.0.data.count }.max() ?? 0) bytes)")
let bytes0 = frames.filter { $0.0.epoch == 0 }.reduce(0) { $0 + $1.0.data.count }
let kbps = bytes0 * 8 / 3 / 1000
// A ceiling, not a goal: the pattern is simple, so the encoder needs far less than the target.
check(kbps <= 1_800, "epoch 0's three seconds at \(kbps) kbit/s, within one and a half times the 1,200 target")

// Decode each epoch's frames from its format, as CameraReceiver does (its software decoder on a test host).
func decode(_ format: CameraFormat, _ epochFrames: [(CameraFrame, Bool, Int)]) -> (ok: Int, bad: [String]) {
    guard let encoded = format.parameterSets, let ps = ParameterSets(encoded: encoded) else { return (0, ["no parameter sets"]) }
    let pointers = ps.sets.map { s -> UnsafeMutablePointer<UInt8> in
        let p = UnsafeMutablePointer<UInt8>.allocate(capacity: s.count); s.copyBytes(to: p, count: s.count); return p
    }
    defer { pointers.forEach { $0.deallocate() } }
    var desc: CMVideoFormatDescription?
    var status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(allocator: nil, parameterSetCount: ps.sets.count,
        parameterSetPointers: pointers.map { UnsafePointer($0) }, parameterSetSizes: ps.sets.map(\.count),
        nalUnitHeaderLength: Int32(ps.nalUnitHeaderLength), extensions: nil, formatDescriptionOut: &desc)
    guard status == noErr, let desc else { return (0, ["no format (\(status))"]) }
    let attributes: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA, kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
    let spec: [CFString: Any] = [kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder: false]
    var made: VTDecompressionSession?
    status = VTDecompressionSessionCreate(allocator: nil, formatDescription: desc, decoderSpecification: spec as CFDictionary,
                                          imageBufferAttributes: attributes as CFDictionary, outputCallback: nil, decompressionSessionOut: &made)
    guard status == noErr, let session = made else { return (0, ["no software decoder (\(status))"]) }
    defer { VTDecompressionSessionInvalidate(session) }
    var ok = 0, bad: [String] = []
    for (frame, _, picture) in epochFrames {
        let d = frame.data
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: d.count, blockAllocator: nil, customBlockSource: nil,
                                           offsetToData: 0, dataLength: d.count, flags: 0, blockBufferOut: &block)
        CMBlockBufferAssureBlockMemory(block!)
        d.withUnsafeBytes { _ = CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block!, offsetIntoDestination: 0, dataLength: d.count) }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMTime(value: CMTimeValue(picture), timescale: 30), decodeTimeStamp: .invalid)
        var size = d.count
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: desc, sampleCount: 1, sampleTimingEntryCount: 1,
                                  sampleTimingArray: &timing, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample)
        var number: Int?, shape = (0, 0), decoded: OSStatus = -1
        status = VTDecompressionSessionDecodeFrame(session, sampleBuffer: sample!, flags: [], infoFlagsOut: nil) { s, _, image, _, _ in
            decoded = s
            guard s == noErr, let image else { return }
            shape = (CVPixelBufferGetWidth(image), CVPixelBufferGetHeight(image))
            number = CameraPattern.number(in: image)
        }
        VTDecompressionSessionWaitForAsynchronousFrames(session)
        if status == noErr, decoded == noErr, number == picture, shape == (format.width ?? 0, format.height ?? 0) { ok += 1 } else {
            bad.append("seq \(frame.seq) (picture \(picture)): \(status)/\(decoded), \(shape.0)x\(shape.1), reads \(number.map(String.init) ?? "nothing")")
        }
    }
    return (ok, bad)
}
for f in formats {
    let mine = frames.filter { $0.0.epoch == f.epoch }
    let r = decode(f, mine)
    check(r.bad.isEmpty && r.ok == mine.count, "epoch \(f.epoch ?? -1): \(r.ok) of \(mine.count) frames decode at \(f.width ?? 0)x\(f.height ?? 0) on the software decoder, each the picture it was made from\(r.bad.isEmpty ? "" : "; " + r.bad.prefix(3).joined(separator: "; "))")
}

// The fixture: epoch 0's frames as make-fixture.swift writes them.
if CommandLine.arguments.count > 1, let f = formats.first, let ps = f.parameterSets {
    let mine = frames.filter { $0.0.epoch == f.epoch }
    var file = Data("SILLCAM1".utf8)
    func u16(_ v: Int) { file.append(UInt8(v >> 8)); file.append(UInt8(v & 0xFF)) }
    func u32(_ v: Int) { for s in [24, 16, 8, 0] { file.append(UInt8((v >> s) & 0xFF)) } }
    u16(f.width ?? 0); u16(f.height ?? 0); u16(fps); u16(mine.count)
    u32(ps.count); file.append(ps)
    for (frame, key, _) in mine { file.append(key ? 1 : 0); u32(frame.data.count); file.append(frame.data) }
    do {
        try file.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
        print("wrote \(CommandLine.arguments[1]): \(mine.count) frames of epoch 0, \(file.count) bytes")
    } catch {
        check(false, "the fixture could not be written: \(error)")
    }
}
print(failures == 0 ? "PASS" : "FAILED: \(failures)")
exit(failures == 0 ? 0 : 1)
