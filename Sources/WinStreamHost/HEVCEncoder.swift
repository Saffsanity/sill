import Foundation
import VideoToolbox
import CoreMedia
import StreamProtocol

/// Hardware HEVC encoder tuned for low latency: real time, no B-frames, long GOP.
final class HEVCEncoder {
    private var session: VTCompressionSession?
    private var forceKeyframe = false
    /// Most recent captured frame. ScreenCaptureKit only delivers frames when the window repaints,
    /// so a client that connects while the window is static would otherwise never get a keyframe.
    private var lastFrame: CVPixelBuffer?
    /// Serializes encode() calls from the capture queue and requestKeyframe() from the network queue.
    private let lock = NSLock()

    /// Called on VideoToolbox's callback thread with one access unit (length-prefixed NALs).
    var onEncoded: ((_ data: Data, _ isKeyframe: Bool, _ parameterSets: ParameterSets?) -> Void)?

    init(width: Int, height: Int, fps: Int, bitrate: Int, prioritizeSpeed: Bool) throws {
        var s: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: nil, width: Int32(width), height: Int32(height),
            codecType: kCMVideoCodecType_HEVC, encoderSpecification: nil,
            imageBufferAttributes: nil, compressedDataAllocator: nil,
            outputCallback: nil, refcon: nil, compressionSessionOut: &s)
        guard status == noErr, let session = s else { throw EncoderError.create(status) }
        self.session = session

        func set(_ key: CFString, _ value: CFTypeRef) { VTSessionSetProperty(session, key: key, value: value) }
        set(kVTCompressionPropertyKey_RealTime, kCFBooleanTrue)
        set(kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_HEVC_Main_AutoLevel)
        set(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse)      // no B-frames
        set(kVTCompressionPropertyKey_MaxKeyFrameInterval, (fps * 4) as CFNumber) // keyframe every 4 s
        set(kVTCompressionPropertyKey_ExpectedFrameRate, fps as CFNumber)
        set(kVTCompressionPropertyKey_AverageBitRate, bitrate as CFNumber)
        set(kVTCompressionPropertyKey_DataRateLimits, [bitrate / 8, 1] as CFArray)
        if prioritizeSpeed, #available(macOS 14.0, *) {
            set(kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality, kCFBooleanTrue)
        }
        VTCompressionSessionPrepareToEncodeFrames(session)
    }

    deinit {
        if let session { VTCompressionSessionInvalidate(session) }
    }

    /// Next frame becomes a keyframe (call when a client connects). If we already have a frame,
    /// re-encode it immediately so the client sees the window even if it never repaints.
    func requestKeyframe() {
        lock.lock()
        forceKeyframe = true
        let last = lastFrame
        lock.unlock()
        if let last { encode(last, pts: CMClockGetTime(CMClockGetHostTimeClock())) }
    }

    /// Called on the capture queue with ScreenCaptureKit's host-clock timestamps, and from
    /// requestKeyframe() on the network queue. The lock covers the VT call so those never overlap;
    /// the output handler runs later on VideoToolbox's own thread, outside the lock.
    func encode(_ pixelBuffer: CVPixelBuffer, pts: CMTime) {
        guard let session else { return }
        lock.lock(); defer { lock.unlock() }
        lastFrame = pixelBuffer
        let props: CFDictionary? = forceKeyframe ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary : nil
        forceKeyframe = false

        VTCompressionSessionEncodeFrame(session, imageBuffer: pixelBuffer, presentationTimeStamp: pts,
                                        duration: .invalid, frameProperties: props, infoFlagsOut: nil) { [weak self] status, _, sampleBuffer in
            guard let self else { return }
            guard status == noErr, let sampleBuffer else { Stats.shared.bump("enc.error"); return }
            Stats.shared.bump("enc.out")
            self.handle(sampleBuffer)
        }
    }

    private func handle(_ sb: CMSampleBuffer) {
        var isKey = true
        if let arr = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false) as? [[CFString: Any]],
           let first = arr.first, let notSync = first[kCMSampleAttachmentKey_NotSync] as? Bool {
            isKey = !notSync
        }
        var ps: ParameterSets?
        if isKey, let desc = CMSampleBufferGetFormatDescription(sb) {
            ps = Self.parameterSets(from: desc)
        }
        guard let block = CMSampleBufferGetDataBuffer(sb) else { return }
        let length = CMBlockBufferGetDataLength(block)
        var data = Data(count: length)
        let copied = data.withUnsafeMutableBytes { raw -> OSStatus in
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: raw.baseAddress!)
        }
        guard copied == noErr else { return }
        onEncoded?(data, isKey, ps)
    }

    static func parameterSets(from desc: CMFormatDescription) -> ParameterSets? {
        var count = 0
        var nalLen: Int32 = 0
        guard CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(desc, parameterSetIndex: 0, parameterSetPointerOut: nil,
                                                                 parameterSetSizeOut: nil, parameterSetCountOut: &count,
                                                                 nalUnitHeaderLengthOut: &nalLen) == noErr else { return nil }
        var sets: [Data] = []
        for i in 0..<count {
            var ptr: UnsafePointer<UInt8>?
            var size = 0
            guard CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(desc, parameterSetIndex: i, parameterSetPointerOut: &ptr,
                                                                     parameterSetSizeOut: &size, parameterSetCountOut: nil,
                                                                     nalUnitHeaderLengthOut: nil) == noErr, let ptr else { return nil }
            sets.append(Data(bytes: ptr, count: size))
        }
        return ParameterSets(nalUnitHeaderLength: Int(nalLen), sets: sets)
    }

    enum EncoderError: Error { case create(OSStatus) }
}
