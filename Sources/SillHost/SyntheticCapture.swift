import Foundation
import CoreVideo
import CoreMedia

/// `SillHost --synthetic`: a moving test pattern stands in for ScreenCaptureKit, so the encoder,
/// its software fallback and the network path can be exercised without Screen Recording.
/// Diagnostics only; the coordinator uses it for the Desktop source in that mode.
/// `pool` and `frameIndex` live on `queue`; `timer` is touched only by the main actor.
final class SyntheticCapture: @unchecked Sendable {   // state is confined to `queue` (see above)
    var onFrame: ((CVPixelBuffer, CMTime) -> Void)?
    private let queue = DispatchQueue(label: "sill.synthetic", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var pool: CVPixelBufferPool?
    private var frameIndex = 0
    private var fps = 60

    func start(width: Int, height: Int, fps: Int) {
        timer?.cancel()
        let attrs: [CFString: Any] = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
                                      kCVPixelBufferWidthKey: width, kCVPixelBufferHeightKey: height,
                                      kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pool)
        queue.async { [weak self] in self?.pool = pool; self?.frameIndex = 0; self?.fps = fps }   // ordered before the timer's first tick
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 1.0 / Double(fps), leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
        print("Synthetic capture: \(width)×\(height) @\(fps) fps")
    }

    /// Returns once no tick is running any more, so no late frame reaches the next encoder.
    func stop() async {
        timer?.cancel(); timer = nil
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            queue.async { [weak self] in self?.pool = nil; c.resume() }
        }
    }

    private func tick() {
        guard let pool else { return }
        var pb: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
        guard let pb else { Stats.shared.bump("syn.noBuffer"); return }
        frameIndex += 1
        CVPixelBufferLockBaseAddress(pb, [])
        let w = CVPixelBufferGetWidthOfPlane(pb, 0), h = CVPixelBufferGetHeightOfPlane(pb, 0)
        if let y = CVPixelBufferGetBaseAddressOfPlane(pb, 0) {
            let stride = CVPixelBufferGetBytesPerRowOfPlane(pb, 0)
            // Grey ground with a bright bar sweeping left to right about once a second: a frozen
            // frame is obvious on the device, and the encoder gets real motion to code.
            memset(y, 96, stride * h)
            let barWidth = max(8, w / 20)
            let x0 = (frameIndex * max(1, w / fps)) % max(1, w - barWidth)   // one sweep a second at any rate
            for row in 0..<h { memset(y.advanced(by: row * stride + x0), 235, barWidth) }
        }
        if let uv = CVPixelBufferGetBaseAddressOfPlane(pb, 1) {
            memset(uv, 128, CVPixelBufferGetBytesPerRowOfPlane(pb, 1) * CVPixelBufferGetHeightOfPlane(pb, 1))
        }
        CVPixelBufferUnlockBaseAddress(pb, [])
        Stats.shared.bump("cap.complete")
        onFrame?(pb, CMClockGetTime(CMClockGetHostTimeClock()))
    }
}
