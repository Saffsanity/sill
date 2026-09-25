import Foundation
import CoreVideo
import CoreMedia

/// Frames through a new hardware HEVC session, to learn whether the encoder can carry a stream:
/// at launch one small frame (`hardwareResponds`, about 100 ms when healthy), and while the host
/// streams on the software encoder a short run at the stream's own size (`throughput`, the
/// coordinator's re-check).
///
/// A probe that gets no answer is one of two things. On 2026-09-22 the Mac's hardware encoder was
/// stuck system-wide for about three hours: every session took a frame and never answered, and
/// each such session keeps a thread blocked for good (nothing can free it; the fallback path
/// leaks the same). On 2026-09-24 it was busy: the iOS Simulator's screen recorder held the one
/// encoder engine at a higher firmware priority, and frames of real-time sessions waited seconds,
/// then came back. A small frame answers even then (256×256 within 270 ms while a stream-size
/// session beside it was still starved; on 2026-09-25 in 72 ms, and the stream that went back to
/// the hardware on that answer ran at 12 fps), which is why the re-check measures a rate at the
/// stream's size. A probe frame that comes back late is counted out again (`stuckProbes`), so
/// only a stuck encoder piles them up.
enum EncoderProbe {
    /// Probe sessions whose frame has not come back. Each holds a blocked thread while it lasts;
    /// the re-check stops probing while too many are out (StreamCoordinator.maxStuckProbes).
    static var stuckProbes: Int { lock.lock(); defer { lock.unlock() }; return stuck }
    private static let lock = NSLock()
    private static var stuck = 0
    /// TEST ONLY. `SILL_TEST_PROBE_HOLD=S`: every frame of every probe waits S seconds before it
    /// goes in. Over the 1 s timeout a probe gets no answer and its frame comes back S seconds later
    /// (a busy encoder), or with a huge S never (a stuck one); S = 0.08 makes a throughput probe
    /// measure ~12 fps (a starved one). Read once; 0 without it.
    private static let testHold = TimeInterval(ProcessInfo.processInfo.environment["SILL_TEST_PROBE_HOLD"] ?? "") ?? 0

    /// True when a hardware session returns one 256×256 frame within `timeout`. The launch probe
    /// and the self-test: prints its one line and counts `enc.probeOK` or `enc.probeHung`.
    static func hardwareResponds(timeout: TimeInterval = 1.0) -> Bool {
        let started = CFAbsoluteTimeGetCurrent()
        let done = DispatchSemaphore(value: 0)
        guard let enc = try? HEVCEncoder(width: 256, height: 256, fps: 30, bitrate: 1_000_000, prioritizeSpeed: true) else {
            return false   // no hardware session at all: the software encoder is the only option
        }
        enc.onEncoded = { _, _, _ in done.signal() }
        enc.testHoldEachFrame = testHold
        let attrs: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                                      kCVPixelBufferWidthKey: 256, kCVPixelBufferHeightKey: 256,
                                      kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, 256, 256, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, attrs as CFDictionary, &pb)
        guard let pb else { return true }   // cannot test; assume healthy
        CVPixelBufferLockBaseAddress(pb, [])
        if let y = CVPixelBufferGetBaseAddressOfPlane(pb, 0) { memset(y, 128, CVPixelBufferGetBytesPerRowOfPlane(pb, 0) * 256) }
        if let uv = CVPixelBufferGetBaseAddressOfPlane(pb, 1) { memset(uv, 128, CVPixelBufferGetBytesPerRowOfPlane(pb, 1) * 128) }
        CVPixelBufferUnlockBaseAddress(pb, [])
        enc.encode(pb, pts: CMTime(value: 0, timescale: 30))
        let ok = done.wait(timeout: .now() + timeout) == .success
        if !ok { giveUp(enc) }
        Stats.shared.bump(ok ? "enc.probeOK" : "enc.probeHung")
        print("Hardware encoder probe: \(ok ? "responding" : "no answer") after \(Int((CFAbsoluteTimeGetCurrent() - started) * 1000)) ms")
        withExtendedLifetime(enc) {}
        return ok
    }

    /// Whether the hardware keeps up with a stream of this size now: `frames` frames of a moving
    /// test pattern through a quiet hardware session (no line, no counter), one at a time as a
    /// stream sends them (the next goes in when the last came back), and the rate they came back
    /// at, the first frame (a new session's warm-up, ~50 ms at Retina size) left out. `ok` false:
    /// a frame took longer than `timeout` (it then counts as stuck until it comes back). `fps` nil:
    /// nothing could be measured (no pixel buffers), so assume it keeps up. About 70 ms of the
    /// engine at 3024×1904 when it is free (~105–115 fps alone); a starved engine shows as a low
    /// rate, not as no answer. Blocks the calling thread for up to `frames` × `timeout`: never
    /// call it on the main actor.
    static func throughput(width: Int, height: Int, frames: Int = 8, timeout: TimeInterval = 1.0) -> (ok: Bool, fps: Double?, ms: Int) {
        let started = CFAbsoluteTimeGetCurrent()
        func elapsed() -> Int { Int((CFAbsoluteTimeGetCurrent() - started) * 1000) }
        guard let enc = try? HEVCEncoder(width: width, height: height, fps: 60, bitrate: 15_000_000, prioritizeSpeed: false, quiet: true) else {
            return (false, nil, elapsed())
        }
        let done = DispatchSemaphore(value: 0)
        enc.onEncoded = { _, _, _ in done.signal() }
        enc.testHoldEachFrame = testHold
        let attrs: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                                      kCVPixelBufferWidthKey: width, kCVPixelBufferHeightKey: height,
                                      kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pool)
        guard let pool else { return (true, nil, elapsed()) }
        let count = max(2, frames)
        var firstBack: CFAbsoluteTime = 0
        for i in 0..<count {
            var pb: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
            guard let pb else { return (true, nil, elapsed()) }
            // Grey with a bar that moves each frame, like the synthetic source: some motion to code.
            CVPixelBufferLockBaseAddress(pb, [])
            if let y = CVPixelBufferGetBaseAddressOfPlane(pb, 0) {
                let stride = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
                memset(y, 96, stride * height)
                let bar = max(8, width / 20), x0 = (i * width / 10) % max(1, width - bar)
                for row in 0..<height { memset(y.advanced(by: row * stride + x0), 235, bar) }
            }
            if let uv = CVPixelBufferGetBaseAddressOfPlane(pb, 1) {
                memset(uv, 128, CVPixelBufferGetBytesPerRowOfPlane(pb, 1) * CVPixelBufferGetHeightOfPlane(pb, 1))
            }
            CVPixelBufferUnlockBaseAddress(pb, [])
            enc.encode(pb, pts: CMTime(value: CMTimeValue(i), timescale: 60))
            guard done.wait(timeout: .now() + timeout) == .success else {
                giveUp(enc)
                return (false, nil, elapsed())
            }
            if i == 0 { firstBack = CFAbsoluteTimeGetCurrent() }
        }
        let span = CFAbsoluteTimeGetCurrent() - firstBack
        withExtendedLifetime(enc) {}
        return (true, span > 0 ? Double(count - 1) / span : nil, elapsed())
    }

    /// A probe's frame did not come back in time: no watchdog report 1.5 s from now (the caller
    /// knows), and a frame still inside counts as stuck until the session lets go of it.
    private static func giveUp(_ enc: HEVCEncoder) {
        guard enc.abandon() else { return }
        lock.lock(); stuck += 1; lock.unlock()
        enc.onStalledFrameBack = { _ in lock.lock(); stuck -= 1; lock.unlock() }
    }
}
