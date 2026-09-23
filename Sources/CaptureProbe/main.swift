import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreGraphics

// CaptureProbe <window title/app substring> [seconds]
// Captures one window twice, showsCursor = false then true, and counts the frames ScreenCaptureKit
// delivers. Written to answer: does a window filter stop delivering content frames when the cursor
// is left out of the picture (macOS 27.0)?

_ = CGMainDisplayID()
let match = (CommandLine.arguments.dropFirst().first ?? "Claude").lowercased()
let seconds = Double(CommandLine.arguments.dropFirst(2).first ?? "6") ?? 6

import VideoToolbox

final class ProbeEncoder {
    let session: VTCompressionSession
    var submitted = 0, encoded = 0, errors = 0, maxBlockMs = 0.0
    init(width: Int, height: Int) throws {
        var s: VTCompressionSession?
        let args = CommandLine.arguments
        let codec: CMVideoCodecType = args.contains("--h264") ? kCMVideoCodecType_H264 : kCMVideoCodecType_HEVC
        var spec: [CFString: Any] = [:]
        if args.contains("--software") { spec[kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder] = false }
        if args.contains("--lowres") { /* caller passes a smaller cfg */ }
        print("encoder: \(codec == kCMVideoCodecType_H264 ? "H.264" : "HEVC") \(args.contains("--software") ? "software" : "hardware allowed") \(width)×\(height)")
        let st = VTCompressionSessionCreate(allocator: nil, width: Int32(width), height: Int32(height), codecType: codec,
                                            encoderSpecification: spec.isEmpty ? nil : spec as CFDictionary, imageBufferAttributes: nil, compressedDataAllocator: nil,
                                            outputCallback: nil, refcon: nil, compressionSessionOut: &s)
        guard st == noErr, let s else { throw NSError(domain: "probe", code: Int(st)) }
        session = s
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        if codec == kCMVideoCodecType_HEVC { VTSessionSetProperty(s, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_HEVC_Main_AutoLevel) }
        var encoderID: CFTypeRef?
        VTSessionCopyProperty(s, key: kVTCompressionPropertyKey_EncoderID, allocator: nil, valueOut: &encoderID)
        print("encoder ID: \(encoderID.map { "\($0)" } ?? "?")")
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: 240 as CFNumber)
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: 60 as CFNumber)
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_AverageBitRate, value: 15_000_000 as CFNumber)
        VTSessionSetProperty(s, key: kVTCompressionPropertyKey_DataRateLimits, value: [15_000_000 / 8, 1] as CFArray)
        VTCompressionSessionPrepareToEncodeFrames(s)
    }
    func encode(_ pb: CVPixelBuffer, pts: CMTime) {
        submitted += 1
        let t0 = CFAbsoluteTimeGetCurrent()
        VTCompressionSessionEncodeFrame(session, imageBuffer: pb, presentationTimeStamp: pts, duration: .invalid, frameProperties: nil, infoFlagsOut: nil) { [weak self] status, _, sb in
            if status == noErr, sb != nil { self?.encoded += 1 } else { self?.errors += 1 }
        }
        maxBlockMs = max(maxBlockMs, (CFAbsoluteTimeGetCurrent() - t0) * 1000)
    }
}

final class Counter: NSObject, SCStreamOutput, SCStreamDelegate {
    var complete = 0, idle = 0, other = 0
    var encoder: ProbeEncoder?
    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              let a = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = a.first?[.status] as? Int, let status = SCFrameStatus(rawValue: raw) else { other += 1; return }
        switch status { case .complete: complete += 1; case .idle: idle += 1; default: other += 1 }
        if status == .complete, let e = encoder, let pb = CMSampleBufferGetImageBuffer(sb) {
            e.encode(pb, pts: CMSampleBufferGetPresentationTimeStamp(sb))
        }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) { print("    stream stopped: \(error.localizedDescription)") }
}

/// --synthetic: no capture at all. Generates 420f frames in memory and encodes 60 of them, waiting
/// up to 5 s for the callbacks. Isolates VideoToolbox from ScreenCaptureKit and needs no permission.
func runSynthetic() {
    let w = CommandLine.arguments.contains("--lowres") ? 1512 : 3024, h = CommandLine.arguments.contains("--lowres") ? 949 : 1898
    do {
        let enc = try ProbeEncoder(width: w, height: h)
        var pool: CVPixelBufferPool?
        let attrs: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                                      kCVPixelBufferWidthKey: w, kCVPixelBufferHeightKey: h, kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
        CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pool)
        guard let pool else { print("no pool"); exit(2) }
        let start = CFAbsoluteTimeGetCurrent()
        for i in 0..<60 {
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
            guard let pb else { continue }
            CVPixelBufferLockBaseAddress(pb, [])
            if let base = CVPixelBufferGetBaseAddressOfPlane(pb, 0) {
                memset(base, Int32(16 + (i * 3) % 200), CVPixelBufferGetBytesPerRowOfPlane(pb, 0) * CVPixelBufferGetHeightOfPlane(pb, 0))
            }
            CVPixelBufferUnlockBaseAddress(pb, [])
            enc.encode(pb, pts: CMTime(value: CMTimeValue(i), timescale: 60))
            usleep(16_000)
        }
        let deadline = CFAbsoluteTimeGetCurrent() + 5
        while enc.encoded + enc.errors < enc.submitted, CFAbsoluteTimeGetCurrent() < deadline { usleep(50_000) }
        print("synthetic: \(enc.submitted) submitted, \(enc.encoded) encoded, \(enc.errors) errors in \(String(format: "%.1f", CFAbsoluteTimeGetCurrent() - start)) s; max EncodeFrame block \(String(format: "%.0f", enc.maxBlockMs)) ms")
        exit(enc.encoded > 0 ? 0 : 3)
    } catch { print("encoder create failed: \(error)"); exit(4) }
}
if CommandLine.arguments.contains("--synthetic") { runSynthetic() }

@MainActor
func run() async {
    do {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let w = content.windows.first(where: { win in
            win.windowLayer == 0 && win.frame.width > 100 &&
            ((win.owningApplication?.applicationName.lowercased().contains(match) ?? false) || (win.title?.lowercased().contains(match) ?? false))
        }) else { print("no window matches \(match)"); exit(1) }
        print("window: \(w.owningApplication?.applicationName ?? "?") — \(w.title ?? "") \(Int(w.frame.width))×\(Int(w.frame.height))")
        // --encode: also push the frames through a VideoToolbox HEVC session set up exactly like the
        // host's, to tell a capture problem from an encoder problem.
        let encodeToo = CommandLine.arguments.contains("--encode")
        for showsCursor in encodeToo ? [false] : [false, true, false] {
            let cfg = SCStreamConfiguration()
            let scale = CommandLine.arguments.contains("--lowres") ? 1 : 2
            cfg.width = Int(w.frame.width) * scale; cfg.height = Int(w.frame.height) * scale
            cfg.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
            cfg.minimumFrameInterval = CMTime(value: 1, timescale: 60)
            cfg.queueDepth = 3
            cfg.showsCursor = showsCursor
            cfg.colorSpaceName = CGColorSpace.sRGB
            let counter = Counter()
            if encodeToo { counter.encoder = try ProbeEncoder(width: cfg.width, height: cfg.height) }
            let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: w), configuration: cfg, delegate: counter)
            try stream.addStreamOutput(counter, type: .screen, sampleHandlerQueue: DispatchQueue(label: "probe"))
            try await stream.startCapture()
            try await Task.sleep(for: .seconds(seconds))
            try await stream.stopCapture()
            print("showsCursor=\(showsCursor): \(counter.complete) complete (\(String(format: "%.1f", Double(counter.complete) / seconds)) fps), \(counter.idle) idle, \(counter.other) other over \(Int(seconds)) s")
            if let e = counter.encoder { print("encoder: \(e.submitted) submitted, \(e.encoded) encoded (\(e.errors) errors), blocked in EncodeFrame for \(String(format: "%.0f", e.maxBlockMs)) ms max") }
        }
    } catch { print("error: \(error)") }
    exit(0)
}
Task { await run() }
dispatchMain()
