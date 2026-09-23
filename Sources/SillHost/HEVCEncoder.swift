import Foundation
import QuartzCore
import VideoToolbox
import CoreMedia
import StreamProtocol

/// HEVC encoder tuned for low latency: real time, no B-frames, keyframes on demand.
///
/// Threading, by hand and deliberately:
/// - `encode()` is called on the capture queue (and `requestKeyframe()` on the network queue). It
///   never touches VideoToolbox itself: it drops the frame into a one-slot mailbox and returns, so
///   ScreenCaptureKit is never blocked by the encoder. A newer frame replaces an older unsent one.
/// - `encodeQueue` (serial) hands frames to VideoToolbox one at a time: the next frame goes in when
///   the previous one's output handler has run. At most one frame is ever inside VT.
/// - A watchdog on its own queue declares the session dead when a frame has been inside VT for
///   `hangAfter` seconds without an output. 2026-09-22 the Mac's hardware encoder wedged system-wide
///   (a fresh session in a fresh process never returned a single frame); with the old direct call
///   that froze the capture queue, then `stopCapture`, then every later source switch. Now the
///   owner is told (`onHung`) and can start over on the software encoder.
final class HEVCEncoder {
    let width: Int
    let height: Int
    let software: Bool
    private var session: VTCompressionSession?

    /// Called on VideoToolbox's callback thread with one access unit (length-prefixed NALs).
    var onEncoded: ((_ data: Data, _ isKeyframe: Bool, _ parameterSets: ParameterSets?) -> Void)?
    /// The session stopped returning frames. Called once, on `encodeQueue`. The encoder is dead
    /// afterwards: it drops every further frame.
    var onHung: (() -> Void)?

    // Mailbox and in-flight state, guarded by `lock`.
    private let lock = NSLock()
    private var pending: (CVPixelBuffer, CMTime)?
    private var inFlight = false
    private var submittedAt: CFTimeInterval = 0
    private var dead = false
    private var forceKeyframe = false
    /// Forced keyframes VideoToolbox dropped and we asked for again (bounded, see `submit`).
    private var forcedRetries = 0
    /// Increments per frame handed to VideoToolbox, so a duplicate "returned" notice for the same
    /// frame (an error status *and* a handler call) cannot free the slot twice.
    private var submissionID = 0
    /// The frame currently inside VideoToolbox, 0 when none. The first notice for it clears this,
    /// so a second notice for the same frame cannot free the slot again.
    private var outstandingID = 0
    /// Most recent captured frame. ScreenCaptureKit only delivers frames when the window repaints,
    /// so a client that connects while the window is static would otherwise never get a keyframe.
    private var lastFrame: CVPixelBuffer?
    /// Presentation timestamps must never go backwards (frame reordering is off); see `submit`.
    private var lastPTS: CMTime = .invalid
    private var lastFrameAt: CFTimeInterval = 0

    private let encodeQueue = DispatchQueue(label: "sill.encode", qos: .userInteractive)
    /// The watchdog must not share `encodeQueue`: when VideoToolbox hangs, it hangs *inside*
    /// `submit` on that queue, and a timer queued behind it would never fire (seen in the self-test).
    private let watchdogQueue = DispatchQueue(label: "sill.encode.watchdog", qos: .utility)
    private var watchdog: DispatchSourceTimer?
    static let hangAfter: CFTimeInterval = 1.5

    init(width: Int, height: Int, fps: Int, bitrate: Int, prioritizeSpeed: Bool, software: Bool = false) throws {
        self.width = width
        self.height = height
        self.software = software
        var s: VTCompressionSession?
        var spec: [CFString: Any] = [:]
        if software { spec[kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder] = false }
        let status = VTCompressionSessionCreate(
            allocator: nil, width: Int32(width), height: Int32(height),
            codecType: kCMVideoCodecType_HEVC, encoderSpecification: spec.isEmpty ? nil : spec as CFDictionary,
            imageBufferAttributes: nil, compressedDataAllocator: nil,
            outputCallback: nil, refcon: nil, compressionSessionOut: &s)
        guard status == noErr, let session = s else { throw EncoderError.create(status) }
        self.session = session

        func set(_ key: CFString, _ value: CFTypeRef) { VTSessionSetProperty(session, key: key, value: value) }
        set(kVTCompressionPropertyKey_RealTime, kCFBooleanTrue)
        set(kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_HEVC_Main_AutoLevel)
        set(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse)      // no B-frames
        // Keyframes are requested on demand (new client, dropped delta, source switch); this is
        // only a safety interval. Longer intervals cut the periodic IDR hitch; 4 s is the value
        // every working stream so far has used.
        set(kVTCompressionPropertyKey_MaxKeyFrameInterval, (fps * 4) as CFNumber)
        set(kVTCompressionPropertyKey_ExpectedFrameRate, fps as CFNumber)
        set(kVTCompressionPropertyKey_AverageBitRate, bitrate as CFNumber)
        set(kVTCompressionPropertyKey_DataRateLimits, [bitrate / 8, 1] as CFArray)
        if prioritizeSpeed || software, #available(macOS 14.0, *) {
            set(kVTCompressionPropertyKey_PrioritizeEncodingSpeedOverQuality, kCFBooleanTrue)
        }
        VTCompressionSessionPrepareToEncodeFrames(session)

        let t = DispatchSource.makeTimerSource(queue: watchdogQueue)
        t.schedule(deadline: .now() + 0.5, repeating: 0.5, leeway: .milliseconds(100))
        t.setEventHandler { [weak self] in self?.checkWatchdog() }
        t.resume()
        watchdog = t
    }

    /// The watchdog gave up on this session. The owner checks this after installing an encoder,
    /// because a hang report that arrived mid-switch was ignored (see StreamCoordinator).
    var isDead: Bool { lock.lock(); defer { lock.unlock() }; return dead }

    /// Give up on this session quietly: no watchdog report, no `enc.hung`. The launch probe calls
    /// this when its frame never comes back, since the owner already knows.
    func abandon() {
        lock.lock(); dead = true; pending = nil; lastFrame = nil; lock.unlock()
        watchdog?.cancel()
    }

    deinit {
        watchdog?.cancel()
        guard let session else { return }
        lock.lock(); let outstanding = inFlight && !dead; lock.unlock()
        // Never tear a live session down with a frame still inside the hardware encoder. The system
        // log for 2026-09-22 shows every wedge began with a session whose first frame never came
        // back after the session was invalidated under it (the encoder service then logs "Frame
        // POC 0 timed out" every 4 s for good, and two such orphans stalled the hardware for every
        // later session until a reboot). Draining first costs a few ms on a healthy session. A dead
        // session is not drained: that call would never return. Invalidating a wedged session can
        // itself block, so none of this runs on the caller's thread.
        DispatchQueue.global(qos: .utility).async {
            if outstanding { VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid) }
            VTCompressionSessionInvalidate(session)
        }
    }

    /// Next frame becomes a keyframe (client connected, a delta was dropped, source switched).
    /// While frames are flowing the next captured frame simply carries the flag. Only when the
    /// window is static (no frame in the last 50 ms) is the last frame re-encoded.
    func requestKeyframe() {
        lock.lock()
        forceKeyframe = true
        let recent = CACurrentMediaTime() - lastFrameAt < 0.05
        let last = lastFrame
        let pts = lastPTS.isValid ? CMTimeAdd(lastPTS, CMTime(value: 1, timescale: 1000)) : CMClockGetTime(CMClockGetHostTimeClock())
        lock.unlock()
        if !recent, let last { enqueue(last, pts: pts, fromCapture: false) }
    }

    /// Capture queue. Returns at once.
    func encode(_ pixelBuffer: CVPixelBuffer, pts: CMTime) { enqueue(pixelBuffer, pts: pts, fromCapture: true) }

    private func enqueue(_ pixelBuffer: CVPixelBuffer, pts: CMTime, fromCapture: Bool) {
        lock.lock()
        guard !dead else { lock.unlock(); Stats.shared.bump("enc.deadDrop"); return }
        lastFrame = pixelBuffer
        // A re-encode of the last frame is not a repaint: it must not make the window look live
        // to the next requestKeyframe, or a retry after a dropped keyframe would do nothing.
        if fromCapture { lastFrameAt = CACurrentMediaTime() }
        if inFlight {
            if pending != nil { Stats.shared.bump("enc.mailboxDrop") }   // newer frame wins
            pending = (pixelBuffer, pts)
            lock.unlock()
            return
        }
        inFlight = true
        submittedAt = CACurrentMediaTime()
        lock.unlock()
        encodeQueue.async { [weak self] in self?.submit(pixelBuffer, pts: pts) }
    }

    /// encodeQueue. Exactly one frame inside VideoToolbox at a time.
    private func submit(_ pixelBuffer: CVPixelBuffer, pts requested: CMTime) {
        guard let session else { return }
        lock.lock()
        guard !dead else { lock.unlock(); return }   // a frame queued just before the watchdog gave up
        let forced = forceKeyframe
        let props: CFDictionary? = forced ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary : nil
        forceKeyframe = false
        var pts = requested
        if lastPTS.isValid, CMTimeCompare(pts, lastPTS) <= 0 {
            pts = CMTimeAdd(lastPTS, CMTime(value: 1, timescale: 1000))
            Stats.shared.bump("enc.ptsFixed")
        }
        lastPTS = pts
        submittedAt = CACurrentMediaTime()
        submissionID += 1
        let id = submissionID
        outstandingID = id
        lock.unlock()

        let status = VTCompressionSessionEncodeFrame(session, imageBuffer: pixelBuffer, presentationTimeStamp: pts,
                                                     duration: .invalid, frameProperties: props, infoFlagsOut: nil) { [weak self] status, _, sampleBuffer in
            guard let self else { return }
            // A session the watchdog gave up on may still cough up late output. Its clients have
            // moved on to a new session (new size, new parameter sets): never forward it.
            guard self.frameReturned(id) else { return }
            guard status == noErr, let sampleBuffer else {
                Stats.shared.bump("enc.error")
                // VideoToolbox dropped the frame (real-time mode over its data-rate cap). A forced
                // keyframe must not go with it: on a static window nothing would ask again and a
                // client waiting for a keyframe would wait for good.
                if forced { self.retryKeyframe() }
                return
            }
            Stats.shared.bump("enc.out")
            self.handle(sampleBuffer)
        }
        if status != noErr {
            // Refused outright; the handler may never run. Free the slot ourselves, or the watchdog
            // would call a transient error a hang and drop the stream to the software encoder.
            Stats.shared.bump("enc.refused")
            if forced { retryKeyframe() }
            frameReturned(id)
        }
    }

    /// The forced keyframe was dropped: ask again, a bounded number of times per request.
    private func retryKeyframe() {
        lock.lock()
        let again = forcedRetries < 3
        if again { forcedRetries += 1 }
        lock.unlock()
        if again { requestKeyframe() }
    }

    /// VT callback thread (or `submit` on a refusal): the slot is free; send the pending frame if
    /// there is one. Returns false when the session is dead, so late output is not forwarded.
    @discardableResult
    private func frameReturned(_ id: Int) -> Bool {
        lock.lock()
        guard !dead else { lock.unlock(); return false }
        guard id == outstandingID else { lock.unlock(); return true }   // duplicate notice for a frame already handled
        outstandingID = 0
        if let (pb, pts) = pending {
            pending = nil
            submittedAt = CACurrentMediaTime()
            lock.unlock()
            encodeQueue.async { [weak self] in self?.submit(pb, pts: pts) }
        } else {
            inFlight = false
            lock.unlock()
        }
        return true
    }

    /// watchdogQueue, every 0.5 s. `encodeQueue` may be blocked inside VideoToolbox for good at this
    /// point; that thread is abandoned with the session.
    private func checkWatchdog() {
        lock.lock()
        let hung = inFlight && !dead && CACurrentMediaTime() - submittedAt > Self.hangAfter
        if hung { dead = true; pending = nil; lastFrame = nil }   // lastFrame: 8+ MB at Retina size, no longer needed
        lock.unlock()
        guard hung else { return }
        watchdog?.cancel()
        Stats.shared.bump("enc.hung")
        print("Encoder (\(software ? "software" : "hardware") HEVC \(width)×\(height)) returned nothing for \(Int(Self.hangAfter * 1000)) ms: giving up on this session")
        onHung?()
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
            lock.lock(); forcedRetries = 0; lock.unlock()
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
