import Foundation
import CoreVideo
import CoreMedia

/// Pushes one small frame through a hardware HEVC session: at launch (`hardwareResponds`), and
/// while the host streams on the software encoder, to find out when it can go back
/// (StreamCoordinator's re-check). About 100 ms when the encoder is healthy.
///
/// A probe that gets no answer is one of two things. On 2026-09-22 the Mac's hardware encoder was
/// stuck system-wide for about three hours: every session took a frame and never answered, and
/// each such session keeps a thread blocked for good (nothing can free it; the fallback path
/// leaks the same). On 2026-09-24 it was busy: the iOS Simulator's screen recorder held the one
/// encoder engine at a higher firmware priority, and frames of real-time sessions waited seconds,
/// then came back. A small probe can answer even then (256×256 answered within 270 ms while a
/// stream-size session beside it was still starved), so an answer is a good sign, not a promise.
/// A probe frame that comes back late is counted out again (`stuckProbes`), so only a stuck
/// encoder piles them up.
enum EncoderProbe {
    /// Probe sessions whose frame has not come back. Each holds a blocked thread while it lasts;
    /// the re-check stops probing while too many are out (StreamCoordinator.maxStuckProbes).
    static var stuckProbes: Int { lock.lock(); defer { lock.unlock() }; return stuck }
    private static let lock = NSLock()
    private static var stuck = 0
    /// TEST ONLY. `SILL_TEST_PROBE_HOLD=S`: every probe's frame waits S seconds before it goes in,
    /// so with S over the 1 s timeout a probe gets no answer, and its frame comes back S seconds
    /// later (a busy encoder) or, with a huge S, never (a stuck one). Read once; 0 without it.
    private static let testHold = TimeInterval(ProcessInfo.processInfo.environment["SILL_TEST_PROBE_HOLD"] ?? "") ?? 0

    /// True when a hardware session returns a frame within `timeout`. The launch probe and the
    /// self-test: prints its one line and counts `enc.probeOK` or `enc.probeHung`, as it always did.
    static func hardwareResponds(timeout: TimeInterval = 1.0) -> Bool {
        probe(timeout: timeout, quiet: false).ok
    }

    /// One frame through a new hardware session; `ms` is how long the answer took (or the wait,
    /// without one). `quiet`: no line, no counter, and a quiet encoder, so a re-check while
    /// streaming leaves the stats line and the log as they were. Blocks the calling thread for up
    /// to `timeout`: never call it on the main actor.
    static func probe(timeout: TimeInterval = 1.0, quiet: Bool) -> (ok: Bool, ms: Int) {
        let started = CFAbsoluteTimeGetCurrent()
        func elapsed() -> Int { Int((CFAbsoluteTimeGetCurrent() - started) * 1000) }
        let done = DispatchSemaphore(value: 0)
        guard let enc = try? HEVCEncoder(width: 256, height: 256, fps: 30, bitrate: 1_000_000, prioritizeSpeed: true, quiet: quiet) else {
            return (false, elapsed())   // no hardware session at all: the software encoder is the only option
        }
        enc.onEncoded = { _, _, _ in done.signal() }
        enc.testHoldFirstFrame = testHold
        let attrs: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                                      kCVPixelBufferWidthKey: 256, kCVPixelBufferHeightKey: 256,
                                      kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
        var pb: CVPixelBuffer?
        CVPixelBufferCreate(nil, 256, 256, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange, attrs as CFDictionary, &pb)
        guard let pb else { return (true, elapsed()) }   // cannot test; assume healthy
        CVPixelBufferLockBaseAddress(pb, [])
        if let y = CVPixelBufferGetBaseAddressOfPlane(pb, 0) { memset(y, 128, CVPixelBufferGetBytesPerRowOfPlane(pb, 0) * 256) }
        if let uv = CVPixelBufferGetBaseAddressOfPlane(pb, 1) { memset(uv, 128, CVPixelBufferGetBytesPerRowOfPlane(pb, 1) * 128) }
        CVPixelBufferUnlockBaseAddress(pb, [])
        enc.encode(pb, pts: CMTime(value: 0, timescale: 30))
        let ok = done.wait(timeout: .now() + timeout) == .success
        let ms = elapsed()
        // Its watchdog would otherwise report a hang 1.5 s from now. A frame still inside counts as
        // stuck until the session lets go of it.
        if !ok, enc.abandon() {
            lock.lock(); stuck += 1; lock.unlock()
            enc.onStalledFrameBack = { _ in lock.lock(); stuck -= 1; lock.unlock() }
        }
        if !quiet {
            Stats.shared.bump(ok ? "enc.probeOK" : "enc.probeHung")
            print("Hardware encoder probe: \(ok ? "responding" : "no answer") after \(ms) ms")
        }
        withExtendedLifetime(enc) {}
        return (ok, ms)
    }
}
