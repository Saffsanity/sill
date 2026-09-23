import Foundation
import CoreVideo
import CoreMedia

/// Pushes one small frame through a hardware HEVC session at launch. On 2026-09-22 the Mac's
/// hardware encoder wedged system-wide until a reboot: every session took a frame and never
/// answered. Finding that out here costs about 100 ms when the encoder is healthy, and when it is
/// not it saves the first stream a 1.5 s hang and a restart. A wedged probe session leaks one
/// blocked thread; nothing can free it, and the fallback path leaks the same.
enum EncoderProbe {
    /// True when a hardware session returns a frame within `timeout`.
    static func hardwareResponds(timeout: TimeInterval = 1.0) -> Bool {
        let started = CFAbsoluteTimeGetCurrent()
        let done = DispatchSemaphore(value: 0)
        guard let enc = try? HEVCEncoder(width: 256, height: 256, fps: 30, bitrate: 1_000_000, prioritizeSpeed: true) else {
            return false   // no hardware session at all: the software encoder is the only option
        }
        enc.onEncoded = { _, _, _ in done.signal() }
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
        if !ok { enc.abandon() }   // its watchdog would otherwise report a hang 1.5 s from now
        Stats.shared.bump(ok ? "enc.probeOK" : "enc.probeHung")
        print("Hardware encoder probe: \(ok ? "responding" : "no answer") after \(Int((CFAbsoluteTimeGetCurrent() - started) * 1000)) ms")
        withExtendedLifetime(enc) {}
        return ok
    }
}
