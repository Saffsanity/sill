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
///   `hangAfter` seconds without an output. The owner is told (`onHung`) and starts over on the
///   software encoder, and leaves it again once a re-check finds the hardware keeping up with the
///   stream (StreamCoordinator, EncoderProbe). It has fired for two different reasons:
///   - Stuck. 2026-09-22 the Mac's hardware encoder wedged system-wide for about three hours: a
///     fresh session in a fresh process never returned a single frame. With the old direct call
///     that froze the capture queue, then `stopCapture`, then every later source switch.
///   - Busy. 2026-09-24, twice: the iOS Simulator's screen recorder runs its hardware session at
///     the encoder firmware's priority 80, a real-time session like this one at 0, and the one
///     encoder engine served the recorder while this session's frame waited 1.8 s and 8.6 s. Both
///     frames came back, and fresh sessions answered at once. The kernel's AppleAVE2 log showed it
///     (CLAUDE.md, "Frozen stream").
///   A session given up on reports on its way out whether its stalled frame ever came back
///   (`deinit`): a busy encoder hands it back, a stuck one never does.
final class HEVCEncoder {
    let width: Int
    let height: Int
    let software: Bool
    /// A probe's session: no counters and no lines, so a re-check while streaming leaves the
    /// stats line (whose `enc.out` is the menu's encoded fps) and the log as they were.
    let quiet: Bool
    /// Increases with every encoder this process creates, so the owner can tell an encoder made
    /// before some moment from one made after it (`latestSerial` then).
    let serial: Int
    private var session: VTCompressionSession?

    /// Called on VideoToolbox's callback thread with one access unit (length-prefixed NALs).
    var onEncoded: ((_ data: Data, _ isKeyframe: Bool, _ parameterSets: ParameterSets?) -> Void)?
    /// The session stopped returning frames. Called once, on the watchdog's queue. The encoder is
    /// dead afterwards: it drops every further frame.
    var onHung: (() -> Void)?
    /// For a session given up on (the watchdog, or `abandon`) with a frame still inside: called on a
    /// utility queue once VideoToolbox has let go of that frame, with the seconds since it went in.
    /// Never called while the frame stays inside, which is what a stuck encoder does. Set it before
    /// the encoder is released.
    var onStalledFrameBack: ((TimeInterval) -> Void)?
    /// TEST ONLY (EncoderProbe's SILL_TEST_PROBE_HOLD): every frame waits this long on
    /// `encodeQueue` before it goes in, as in a starved encoder (tens of ms), a busy one (seconds)
    /// or a stuck one (for good).
    var testHoldEachFrame: TimeInterval = 0

    private static let serialLock = NSLock()
    private static var lastSerial = 0
    /// The serial of the newest encoder created so far.
    static var latestSerial: Int { serialLock.lock(); defer { serialLock.unlock() }; return lastSerial }

    // Guarded by `lock`.
    private let lock = NSLock()
    /// The frames inside VideoToolbox, the one waiting behind them, whether the session is dead,
    /// and what the next frame to go in carries (its timestamp, a requested keyframe).
    private var mailbox: EncoderMailbox<(CVPixelBuffer, CMTime)>
    /// Forced keyframes VideoToolbox dropped and we asked for again (bounded, see `submit`).
    private var forcedRetries = 0
    /// Most recent captured frame. ScreenCaptureKit only delivers frames when the window repaints,
    /// so a client that connects while the window is static would otherwise never get a keyframe.
    private var lastFrame: CVPixelBuffer?
    private var lastFrameAt: CFTimeInterval = 0
    /// The watchdog gave up on this session (not `abandon`): its deinit says whether the frame came back.
    private var hungReported = false

    private let encodeQueue = DispatchQueue(label: "sill.encode", qos: .userInteractive)
    /// The watchdog must not share `encodeQueue`: when VideoToolbox hangs, it hangs *inside*
    /// `submit` on that queue, and a timer queued behind it would never fire (seen in the self-test).
    private let watchdogQueue = DispatchQueue(label: "sill.encode.watchdog", qos: .utility)
    private var watchdog: DispatchSourceTimer?
    static let hangAfter: CFTimeInterval = 1.5

    init(width: Int, height: Int, fps: Int, bitrate: Int, prioritizeSpeed: Bool, software: Bool = false,
         quiet: Bool = false) throws {
        self.width = width
        self.height = height
        self.software = software
        self.quiet = quiet
        mailbox = EncoderMailbox(software: software)
        Self.serialLock.lock(); Self.lastSerial += 1; serial = Self.lastSerial; Self.serialLock.unlock()
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
    var isDead: Bool { lock.lock(); defer { lock.unlock() }; return mailbox.dead }

    /// Give up on this session quietly: no watchdog report, no `enc.hung`. A probe calls this when
    /// its frame has not come back in time, since the owner already knows. True when that frame
    /// is still inside VideoToolbox (then `onStalledFrameBack` tells when it comes out); false
    /// when it came back just now.
    @discardableResult
    func abandon() -> Bool {
        lock.lock(); let inside = mailbox.giveUp(); lastFrame = nil; lock.unlock()
        watchdog?.cancel()
        return inside
    }

    deinit {
        watchdog?.cancel()
        guard let session else { return }
        lock.lock()
        // Drain a live session with a frame inside. One given up on with a frame inside VideoToolbox
        // (the watchdog, or a probe's `abandon`) is stalled: a dead session never clears its
        // frames, and `since` is when the one inside longest went in.
        let teardown = mailbox.teardown
        let report = hungReported && !quiet
        lock.unlock()
        let described = "\(software ? "software" : "hardware") HEVC \(width)×\(height)"
        let back = onStalledFrameBack
        // Never tear a live session down with a frame still inside the hardware encoder. The system
        // log for 2026-09-22 shows every wedge began with a session whose first frame never came
        // back after the session was invalidated under it (the encoder service then logs "Frame
        // POC 0 timed out" every 4 s for good, and two such orphans stalled the hardware for every
        // later session until a reboot). Draining first costs a few ms on a healthy session. A dead
        // session is not drained: that call would never return if the encoder is stuck. Invalidating
        // it can itself block, so none of this runs on the caller's thread.
        //
        // The invalidate waits for a frame still inside (measured 2026-09-25: 17 ms for a 3024×1898
        // frame in flight, whose output handler ran just before it returned; 2026-09-24 the encoder
        // service's own invalidate waited 0.17 s and 7.06 s for the stalled frames, which then
        // completed). So its return is when a stalled frame came back: a busy encoder, not a stuck
        // one, which never lets go and leaves this thread blocked for good.
        DispatchQueue.global(qos: .utility).async {
            if teardown == .drain { VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid) }
            VTCompressionSessionInvalidate(session)
            guard case .stalled(let since) = teardown else { return }
            let seconds = CACurrentMediaTime() - since
            if report {
                print("Encoder (\(described)): the stalled frame came back after \(String(format: "%.1f", seconds)) s; the encoder was busy, not stuck.")
            }
            back?(seconds)
        }
    }

    /// Next frame becomes a keyframe (client connected, a delta was dropped, source switched).
    /// While frames are flowing the next captured frame simply carries the flag. Only when the
    /// window is static (no frame in the last 50 ms) is the last frame re-encoded.
    func requestKeyframe() {
        lock.lock()
        mailbox.keyframeRequested = true
        let recent = CACurrentMediaTime() - lastFrameAt < 0.05
        let last = lastFrame
        let lastPTS = mailbox.lastPTS
        let pts = lastPTS.isValid ? CMTimeAdd(lastPTS, CMTime(value: 1, timescale: 1000)) : CMClockGetTime(CMClockGetHostTimeClock())
        lock.unlock()
        if !recent, let last { enqueue(last, pts: pts, fromCapture: false) }
    }

    /// Capture queue. Returns at once.
    func encode(_ pixelBuffer: CVPixelBuffer, pts: CMTime) { enqueue(pixelBuffer, pts: pts, fromCapture: true) }

    private func enqueue(_ pixelBuffer: CVPixelBuffer, pts: CMTime, fromCapture: Bool) {
        lock.lock()
        let now = CACurrentMediaTime()
        let admission = mailbox.admit((pixelBuffer, pts), now: now)
        if admission != .dropped {
            lastFrame = pixelBuffer
            // A re-encode of the last frame is not a repaint: it must not make the window look live
            // to the next requestKeyframe, or a retry after a dropped keyframe would do nothing.
            if fromCapture { lastFrameAt = now }
        }
        lock.unlock()
        switch admission {
        case .goesIn(let id): encodeQueue.async { [weak self] in self?.submit(pixelBuffer, pts: pts, id: id) }
        case .waits(let replaced): if replaced { bump("enc.mailboxDrop") }   // newer frame wins
        case .dropped: bump("enc.deadDrop")
        }
    }

    /// encodeQueue: frames go into VideoToolbox one after another, in the order they were let in.
    private func submit(_ pixelBuffer: CVPixelBuffer, pts requested: CMTime, id: Int) {
        guard let session else { return }
        lock.lock()
        let handOver = mailbox.handOver(id, pts: requested, now: CACurrentMediaTime())
        lock.unlock()
        guard let handOver else { return }   // a frame queued just before the watchdog gave up
        if handOver.ptsFixed { bump("enc.ptsFixed") }
        let forced = handOver.keyframe
        let props: CFDictionary? = forced ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary : nil
        let pts = handOver.pts

        if testHoldEachFrame > 0 { Thread.sleep(forTimeInterval: testHoldEachFrame) }
        if id == TestHang.frame, !quiet, !software, TestHang.take() {
            // TEST ONLY (SILL_TEST_ENCODER_HANG): this frame waits here, then goes in late and comes
            // back, as frames did in a busy engine on 2026-09-24. The watchdog fires meanwhile.
            print("TEST: holding frame \(id) of the hardware HEVC \(width)×\(height) session for \(Int(TestHang.hold)) s before it goes in (SILL_TEST_ENCODER_HANG)")
            Thread.sleep(forTimeInterval: TestHang.hold)
        }
        let status = VTCompressionSessionEncodeFrame(session, imageBuffer: pixelBuffer, presentationTimeStamp: pts,
                                                     duration: .invalid, frameProperties: props, infoFlagsOut: nil) { [weak self] status, _, sampleBuffer in
            guard let self else { return }
            // A session the watchdog gave up on may still cough up late output. Its clients have
            // moved on to a new session (new size, new parameter sets): never forward it.
            guard self.frameReturned(id) else { return }
            guard status == noErr, let sampleBuffer else {
                self.bump("enc.error")
                // VideoToolbox dropped the frame (real-time mode over its data-rate cap). A forced
                // keyframe must not go with it: on a static window nothing would ask again and a
                // client waiting for a keyframe would wait for good.
                if forced { self.retryKeyframe() }
                return
            }
            self.bump("enc.out")
            self.handle(sampleBuffer)
        }
        if status != noErr {
            // Refused outright; the handler may never run. Free the slot ourselves, or the watchdog
            // would call a transient error a hang and drop the stream to the software encoder.
            bump("enc.refused")
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

    /// VT callback thread (or `submit` on a refusal): the frame's place is free; the waiting frame,
    /// if there is one, takes it. Returns false when the session is dead, so late output is not
    /// forwarded. A duplicate notice for a frame already back (an error status *and* a handler
    /// call) frees nothing.
    @discardableResult
    private func frameReturned(_ id: Int) -> Bool {
        lock.lock()
        let outcome = mailbox.returned(id, now: CACurrentMediaTime())
        lock.unlock()
        switch outcome {
        case .late: return false
        case .duplicate, .freed: return true
        case .next(let (pb, pts), let next):
            encodeQueue.async { [weak self] in self?.submit(pb, pts: pts, id: next) }
            return true
        }
    }

    /// watchdogQueue, every 0.5 s. `encodeQueue` may be blocked inside VideoToolbox for good at this
    /// point; that thread is abandoned with the session.
    private func checkWatchdog() {
        lock.lock()
        let hung = mailbox.giveUpIfHung(now: CACurrentMediaTime(), after: Self.hangAfter)
        if hung { hungReported = true; lastFrame = nil }   // lastFrame: 8+ MB at Retina size, no longer needed
        lock.unlock()
        guard hung else { return }
        watchdog?.cancel()
        bump("enc.hung")
        if !quiet {
            print("Encoder (\(software ? "software" : "hardware") HEVC \(width)×\(height)) returned nothing for \(Int(Self.hangAfter * 1000)) ms: giving up on this session")
        }
        onHung?()
    }

    /// Every counter this encoder keeps goes through here: a quiet one (a probe) keeps none.
    private func bump(_ key: String) {
        if !quiet { Stats.shared.bump(key) }
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

    /// TEST ONLY. `SILL_TEST_ENCODER_HANG=N`: the first N hardware stream sessions of this process
    /// each hold their 90th frame on `encodeQueue` for 3 s before handing it to VideoToolbox, so
    /// the watchdog fires at 1.5 s, the owner falls back to the software encoder, and the frame
    /// then goes in and comes back late, as in a busy engine (2026-09-24). N = 2 makes the return
    /// to the hardware hang once more, for the re-check's backoff. Probes (quiet, one frame) never
    /// take one. Read once; nothing else changes without the variable.
    private enum TestHang {
        static let frame = 90
        static let hold: TimeInterval = 3
        private static let lock = NSLock()
        private static var left = Int(ProcessInfo.processInfo.environment["SILL_TEST_ENCODER_HANG"] ?? "") ?? 0
        static func take() -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard left > 0 else { return false }
            left -= 1
            return true
        }
    }
}
