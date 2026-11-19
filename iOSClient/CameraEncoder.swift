import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox
import StreamProtocol

/// The device's camera encoder (docs/camera-plan.md §8): one VideoToolbox HEVC session per epoch, HEVC
/// Main, real time, no frame reordering (no B-frames), no frame held back, speed before quality, the bitrate CameraPolicy
/// gives with a data-rate limit, and keyframes only when asked (an infinite GOP, as the Mac's stream:
/// a periodic keyframe costs bitrate for nothing on TCP). Each output is one access unit as kind 1 and
/// kind 46 type 2 carry it: NAL units, each after its 4-byte big-endian length (VideoToolbox's output
/// as it is), with the epoch's parameter sets read from a keyframe's format.
///
/// `software`: VideoToolbox's software encoder, never a hardware one (a hardware session it gives is
/// refused): in the simulator, whose VideoToolbox runs on the Mac, where the hardware encoder is the
/// stream's, and in Scripts/camera-check/encoder.swift, which runs this file on the Mac. On a device,
/// the device's own encoder.
///
/// Foundation, CoreMedia, CoreVideo, VideoToolbox and StreamProtocol only, so it builds for macOS too.
/// Not thread-safe: its owner (DeviceCamera) calls it on one queue; `done` comes on VideoToolbox's.
final class CameraEncoder {
    /// One encoded frame.
    struct Output {
        /// The access unit, 4-byte lengths before each NAL unit.
        let data: Data
        let keyframe: Bool
        /// A keyframe's parameter sets (VPS, SPS, PPS), nil for any other frame.
        let parameterSets: ParameterSets?
        /// The picture's capture time as it went in.
        let pts: CMTime
    }

    enum Failure: Error, Equatable {
        /// VideoToolbox made no session (its status).
        case create(OSStatus)
        /// A software session was asked for and VideoToolbox gave a hardware one.
        case hardwareRefused
    }

    let width: Int
    let height: Int
    let fps: Int
    /// The session runs on a hardware encoder (VideoToolbox's word).
    let hardware: Bool
    private(set) var bitrate: Int
    private let session: VTCompressionSession

    private init(width: Int, height: Int, fps: Int, bitrate: Int, hardware: Bool, session: VTCompressionSession) {
        self.width = width; self.height = height; self.fps = fps; self.bitrate = bitrate
        self.hardware = hardware; self.session = session
    }

    deinit {
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        VTCompressionSessionInvalidate(session)
    }

    /// A session for `width`×`height` (each even) at `fps`, ready for its first frame.
    static func make(width: Int, height: Int, fps: Int, bitrate: Int, software: Bool) -> Result<CameraEncoder, Failure> {
        var spec: [CFString: Any] = [:]
        if software {
            // iOS 17.4's keys (the simulator runs a later iOS; on macOS they are old): without them no software
            // session can be asked for, so none is made rather than risk a hardware one.
            guard #available(iOS 17.4, *) else { return .failure(.hardwareRefused) }
            spec[kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder] = false
            spec[kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder] = false
        }
        var made: VTCompressionSession?
        let status = VTCompressionSessionCreate(allocator: nil, width: Int32(width), height: Int32(height), codecType: kCMVideoCodecType_HEVC,
                                                encoderSpecification: spec.isEmpty ? nil : spec as CFDictionary,
                                                imageBufferAttributes: nil, compressedDataAllocator: nil, outputCallback: nil,
                                                refcon: nil, compressionSessionOut: &made)
        guard status == noErr, let session = made else { return .failure(.create(status)) }
        var hardware = false
        if #available(iOS 17.4, *) {
            var value: CFTypeRef?
            _ = withUnsafeMutablePointer(to: &value) {
                VTSessionCopyProperty(session, key: kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder, allocator: nil, valueOut: $0)
            }
            hardware = (value as? Bool) == true
        }
        if software, hardware {
            VTCompressionSessionInvalidate(session)
            return .failure(.hardwareRefused)
        }
        func set(_ key: CFString, _ v: CFTypeRef) { VTSessionSetProperty(session, key: key, value: v) }
        set(kVTCompressionPropertyKey_RealTime, kCFBooleanTrue)
        set(kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_HEVC_Main_AutoLevel)
        set(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse)          // no B-frames
        set(kVTCompressionPropertyKey_MaxFrameDelayCount, 0 as CFNumber)              // each frame out before the next goes in
        // Keyframes only when asked (`encode`'s `keyframe`): an epoch's first frame, the Mac's ask, a frame
        // dropped at a move's fence. This is only the encoder's own ceiling, never reached at 30 fps.
        set(kVTCompressionPropertyKey_MaxKeyFrameInterval, 1_000_000 as CFNumber)
        set(kVTCompressionPropertyKey_ExpectedFrameRate, fps as CFNumber)
        set(kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality, kCFBooleanTrue)
        let encoder = CameraEncoder(width: width, height: height, fps: fps, bitrate: bitrate, hardware: hardware, session: session)
        encoder.applyBitrate()
        VTCompressionSessionPrepareToEncodeFrames(session)
        return .success(encoder)
    }

    /// A new target (CameraPolicy.bitrate, its steps), in bits a second.
    func setBitrate(_ b: Int) {
        guard b != bitrate, b > 0 else { return }
        bitrate = b
        applyBitrate()
    }

    /// The average, and a ceiling of one and a half times it over any half second, so a keyframe stays a few
    /// frames' bytes and never one past CameraFrame.maxDataBytes at generation 1's bitrates.
    private func applyBitrate() {
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrate as CFNumber)
        let halfSecond = max(1, bitrate * 3 / 4 / 8)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: [NSNumber(value: halfSecond), NSNumber(value: 0.5)] as CFArray)
    }

    /// One picture of `width`×`height`, captured at `pts`; a keyframe when `keyframe`. `done` once for it, on
    /// VideoToolbox's thread: its output, or nil when it was dropped or failed (the status says which). Returns
    /// the call's own status: not noErr means `done` never comes.
    func encode(_ image: CVPixelBuffer, pts: CMTime, keyframe: Bool, done: @escaping (OSStatus, Output?) -> Void) -> OSStatus {
        let properties: [CFString: Any]? = keyframe ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] : nil
        return VTCompressionSessionEncodeFrame(session, imageBuffer: image, presentationTimeStamp: pts,
                                               duration: CMTime(value: 1, timescale: CMTimeScale(max(1, fps))),
                                               frameProperties: properties as CFDictionary?, infoFlagsOut: nil) { status, flags, sample in
            guard status == noErr, !flags.contains(.frameDropped), let sample else { done(status, nil); return }
            done(noErr, Self.output(of: sample, pts: pts))
        }
    }

    /// Waits for every frame in flight (a test's end; an epoch's end lets them go with the session).
    func flush() { VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid) }

    /// The access unit, whether it is a keyframe, and a keyframe's parameter sets.
    static func output(of sample: CMSampleBuffer, pts: CMTime) -> Output? {
        var key = true
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[CFString: Any]],
           let notSync = attachments.first?[kCMSampleAttachmentKey_NotSync] as? Bool {
            key = !notSync
        }
        guard let block = CMSampleBufferGetDataBuffer(sample) else { return nil }
        let length = CMBlockBufferGetDataLength(block)
        guard length > 0 else { return nil }
        var data = Data(count: length)
        let copied = data.withUnsafeMutableBytes { raw -> OSStatus in
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: raw.baseAddress!)
        }
        guard copied == noErr else { return nil }
        var sets: ParameterSets?
        if key, let desc = CMSampleBufferGetFormatDescription(sample) { sets = parameterSets(from: desc) }
        return Output(data: data, keyframe: key, parameterSets: sets, pts: pts)
    }

    /// An HEVC format's VPS, SPS and PPS.
    static func parameterSets(from desc: CMFormatDescription) -> ParameterSets? {
        var count = 0
        var nal: Int32 = 0
        guard CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(desc, parameterSetIndex: 0, parameterSetPointerOut: nil, parameterSetSizeOut: nil,
                                                                 parameterSetCountOut: &count, nalUnitHeaderLengthOut: &nal) == noErr else { return nil }
        var sets: [Data] = []
        for i in 0..<count {
            var p: UnsafePointer<UInt8>?
            var size = 0
            guard CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(desc, parameterSetIndex: i, parameterSetPointerOut: &p, parameterSetSizeOut: &size,
                                                                     parameterSetCountOut: nil, nalUnitHeaderLengthOut: nil) == noErr,
                  let p else { return nil }
            sets.append(Data(bytes: p, count: size))
        }
        return ParameterSets(nalUnitHeaderLength: Int(nal), sets: sets)
    }
}
