import Foundation
import ScreenCaptureKit
import CoreMedia

/// Runs one ScreenCaptureKit stream (a window or a display) and hands out 420f pixel buffers.
/// The coordinator stops and restarts it whenever the client picks a different source.
final class WindowCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "sill.capture", qos: .userInteractive)
    var onFrame: ((CVPixelBuffer, CMTime) -> Void)?
    /// The stream ended on its own (window closed, permission revoked). Called on an SCK thread.
    var onStopped: ((Error) -> Void)?
    /// The stats line's keys: "cap" for the stream, "side.cap" for a side stream (SideStreams).
    var statsPrefix = "cap"

    /// `showsCursor`: draw the Mac cursor into the frames. The host passes false: the client draws
    /// the pointer itself (with the Mac's current shape, sent separately), so the video never
    /// carries a round-trip-late cursor. Never change this on a running stream:
    /// `SCStream.updateConfiguration` wedged the stream on macOS 27 (frames stopped, the next
    /// `stopCapture` never returned, and the coordinator's switch flag stayed set for good).
    ///
    /// `sourceRect`: the part of a display filter to encode (a window on its hidden display, or cropped
    /// from its own: AppCrop), in points in the display's own coordinate system (origin at its
    /// top-left, SCStream.h), i.e. exactly the window's rectangle, so the device gets the window and
    /// nothing else. Nil (a window or a whole display) leaves the configuration as it was.
    func start(filter: SCContentFilter, width: Int, height: Int, fps: Int, showsCursor: Bool, sourceRect: CGRect? = nil) async throws {
        let config = SCStreamConfiguration()
        config.width = width
        config.height = height
        config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.queueDepth = 5   // headroom: a wedged encoder may keep one buffer forever
        config.showsCursor = showsCursor
        config.colorSpaceName = CGColorSpace.sRGB
        if let sourceRect {
            config.sourceRect = sourceRect
            config.ignoreShadowsDisplay = true                 // the crop is the window's frame; its shadow would be clipped anyway
            config.backgroundColor = Self.black                  // deterministic black behind the rounded corners
        }

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        // Register before starting: a stop error that arrives during start must not be swallowed
        // by the identity check in didStopWithError.
        self.stream = stream
        framesSeen = 0
        anyBuffer.set(false)
        do {
            try await stream.startCapture()
        } catch {
            if self.stream === stream { self.stream = nil }
            throw error
        }
        let crop = sourceRect.map { String(format: " sourceRect (%.0f,%.0f,%.0f,%.0f)", $0.minX, $0.minY, $0.width, $0.height) } ?? ""
        if statsPrefix == "cap" { print("Capture started: \(width)×\(height) @\(fps) fps, cursor \(showsCursor ? "in" : "out"), filter \(filter.contentRect.size) scale \(filter.pointPixelScale)" + crop) }
    }

    private var framesSeen = 0
    /// Whether the stream has delivered anything since it started, a frame or an idle notice: one
    /// that delivers nothing at all is WindowServer's display streams wedged (StreamCoordinator).
    private let anyBuffer = LockedFlag()
    var deliveredAnything: Bool { anyBuffer.get() }
    /// Held by the type: `SCStreamConfiguration.backgroundColor` is unowned(unsafe) and would not keep
    /// a temporary alive.
    private static let black = CGColor(gray: 0, alpha: 1)

    func stop() async {
        guard let stream else { return }
        self.stream = nil
        try? await stream.stopCapture()
        // stopCapture returning does not mean the sample-handler queue has drained. Wait for it,
        // so no late frame reaches the next encoder at the old size.
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in queue.async { c.resume() } }
    }

    /// Stops the capture and waits for ScreenCaptureKit to say it has, at most `timeout`: for the exit
    /// path, which cannot await, and must not remove a display a capture still runs on.
    func stopNow(timeout: TimeInterval) {
        guard let stream else { return }
        self.stream = nil
        let stopped = DispatchSemaphore(value: 0)
        stream.stopCapture { _ in stopped.signal() }
        _ = stopped.wait(timeout: .now() + timeout)
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        anyBuffer.set(true)
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRaw)
        else { Stats.shared.bump("\(statsPrefix).noStatus"); return }
        // .idle frames (nothing changed) are skipped, which is what we want.
        guard status == .complete else { Stats.shared.bump(status == .idle ? "\(statsPrefix).idle" : "\(statsPrefix).status\(statusRaw)"); return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { Stats.shared.bump("\(statsPrefix).noPixels"); return }
        Stats.shared.bump("\(statsPrefix).complete")
        framesSeen += 1
        if framesSeen == 1, statsPrefix == "cap" { print("Capture: first frame \(CVPixelBufferGetWidth(pixelBuffer))×\(CVPixelBufferGetHeight(pixelBuffer))") }
        onFrame?(pixelBuffer, CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let current = stream === self.stream
        print("Capture stream stopped (\(current ? "current" : "replaced")): \(error) — \((error as NSError).userInfo)")
        guard current else { return }   // a stream we already replaced
        self.stream = nil
        onStopped?(error)
    }
}

/// HEVC wants even dimensions.
func evenPixels(_ v: CGFloat) -> Int { Int(v.rounded(.down)) & ~1 }

/// A Bool behind a lock, set on the capture's queue and read on the main actor.
final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set(_ v: Bool) { lock.lock(); value = v; lock.unlock() }
    func get() -> Bool { lock.lock(); defer { lock.unlock() }; return value }
}
