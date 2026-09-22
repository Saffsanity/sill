import Foundation
import ScreenCaptureKit
import CoreMedia

/// Captures one Mac window with ScreenCaptureKit and hands out 420f pixel buffers.
final class WindowCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private let queue = DispatchQueue(label: "winstream.capture", qos: .userInteractive)
    var onFrame: ((CVPixelBuffer, CMTime) -> Void)?

    /// Picks the first on-screen window whose app name or title contains `match` (case-insensitive).
    /// With no match given, prints the list and picks the frontmost app's first window.
    static func findWindow(matching match: String?) async throws -> SCWindow {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let candidates = content.windows.filter { w in
            guard let app = w.owningApplication, w.frame.width > 100, w.frame.height > 100 else { return false }
            return app.bundleIdentifier != Bundle.main.bundleIdentifier
        }
        print("On-screen windows:")
        for w in candidates {
            print("  \(w.owningApplication?.applicationName ?? "?") — \(w.title ?? "(untitled)")  \(Int(w.frame.width))×\(Int(w.frame.height))")
        }
        if let match = match?.lowercased() {
            if let w = candidates.first(where: {
                ($0.owningApplication?.applicationName.lowercased().contains(match) ?? false) ||
                ($0.title?.lowercased().contains(match) ?? false)
            }) { return w }
            throw CaptureError.noWindow("Nothing matched \"\(match)\"")
        }
        guard let w = candidates.first else { throw CaptureError.noWindow("No windows on screen") }
        return w
    }

    func start(window: SCWindow, scale: CGFloat, fps: Int) async throws {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = evenPixels(window.frame.width * scale)
        config.height = evenPixels(window.frame.height * scale)
        config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.queueDepth = 3
        config.showsCursor = true
        config.colorSpaceName = CGColorSpace.sRGB

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async {
        try? await stream?.stopCapture()
        stream = nil
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let statusRaw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: statusRaw)
        else { Stats.shared.bump("cap.noStatus"); return }
        // .idle frames (nothing changed) are skipped, which is what we want.
        guard status == .complete else { Stats.shared.bump(status == .idle ? "cap.idle" : "cap.status\(statusRaw)"); return }
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { Stats.shared.bump("cap.noPixels"); return }
        Stats.shared.bump("cap.complete")
        onFrame?(pixelBuffer, CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("Capture stopped: \(error.localizedDescription)")
        exit(1)
    }

    enum CaptureError: Error, CustomStringConvertible {
        case noWindow(String)
        var description: String { if case .noWindow(let s) = self { return s }; return "capture error" }
    }
}

/// HEVC wants even dimensions.
func evenPixels(_ v: CGFloat) -> Int { Int(v.rounded(.down)) & ~1 }
