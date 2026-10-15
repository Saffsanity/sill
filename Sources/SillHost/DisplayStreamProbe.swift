import CoreGraphics
import CoreMedia
import Foundation
import ScreenCaptureKit

/// Whether WindowServer delivers display streams at all: a tiny stream of the main display (32×32,
/// one frame a second) for a moment, which passes on its first sample buffer of any status, a notice
/// that nothing changed included. A display removed while it was being captured has left WindowServer
/// delivering nothing to any display stream, for every app, until it restarted (macOS 27.0.1;
/// window capture went on working), and ScreenCaptureKit raises no error then: no buffer is the only
/// sign. Run only once a desk display's capture has delivered nothing, and while that state lasts.
final class DisplayStreamProbe: NSObject, SCStreamOutput, @unchecked Sendable {   // `signalled` on `queue` alone; the semaphore is thread-safe
    private let got = DispatchSemaphore(value: 0)
    private let queue = DispatchQueue(label: "sill.displayprobe")
    private var signalled = false

    /// True when a buffer came within `timeout`; nil when it could not tell (no display listed, the
    /// stream would not start).
    static func delivers(timeout: TimeInterval = 2) async -> Bool? {
        guard let content = await WindowCatalog.shareableContent(excludingDesktopWindows: true, onScreenWindowsOnly: true, timeout: 2),
              let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) ?? content.displays.first
        else { return nil }
        let c = SCStreamConfiguration()
        c.width = 32
        c.height = 32
        c.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        c.showsCursor = false
        c.queueDepth = 3
        let probe = DisplayStreamProbe()
        let stream = SCStream(filter: SCContentFilter(display: display, excludingWindows: []), configuration: c, delegate: nil)
        do {
            try stream.addStreamOutput(probe, type: .screen, sampleHandlerQueue: probe.queue)
            try await stream.startCapture()
        } catch { return nil }
        let came = await withCheckedContinuation { (k: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global().async { k.resume(returning: probe.got.wait(timeout: .now() + timeout) == .success) }
        }
        try? await stream.stopCapture()
        return came
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, !signalled else { return }
        signalled = true
        got.signal()
    }
}
