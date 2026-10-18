import AppKit
import ScreenCaptureKit
import CoreMedia

// Link the production WindowCapture without the host's statistics service.
final class Stats {
    static let shared = Stats()
    func bump(_ name: String) {}
}

private final class FrameResult {
    private let lock = NSLock()
    private var values: [UInt8]?
    func record(_ pixels: CVPixelBuffer) {
        lock.lock()
        defer { lock.unlock() }
        guard values == nil else { return }
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixels, 0) else { return }
        let width = CVPixelBufferGetWidthOfPlane(pixels, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixels, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pixels, 0)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        values = [0.1, 0.5, 0.9].flatMap { y in
            [0.1, 0.5, 0.9].map { x in bytes[Int(Double(height - 1) * y) * stride + Int(Double(width - 1) * x)] }
        }
    }
    func read() -> [UInt8]? {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 320, height: 200),
                      styleMask: [.borderless], backing: .buffered, defer: false)
window.backgroundColor = .white
window.title = "Sill capture-fit regression fixture"
window.orderFrontRegardless()

Task { @MainActor in
    var failures = 0
    do {
        // The WindowServer must have committed the fixture before SCK can resolve its id.
        try await Task.sleep(for: .milliseconds(300))
        for (name, windowSize, scale) in [
            ("downsample", CGSize(width: 320, height: 200), 1.0),
            ("native Retina", CGSize(width: 320, height: 200), 2.0),
            ("upscale beyond native pixels", CGSize(width: 320, height: 200), 4.0),
            ("resized window", CGSize(width: 400, height: 300), 4.0)
        ] {
            window.setContentSize(windowSize)
            try await Task.sleep(for: .milliseconds(200))
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let own = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
                throw NSError(domain: "CaptureFit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Fixture not in capture list"])
            }
            let capture = WindowCapture()
            let frame = FrameResult()
            capture.onFrame = { pixels, _ in frame.record(pixels) }
            try await capture.start(filter: SCContentFilter(desktopIndependentWindow: own),
                                    width: evenPixels(windowSize.width * scale),
                                    height: evenPixels(windowSize.height * scale), fps: 30, showsCursor: false)
            for _ in 0..<60 {
                if frame.read() != nil { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            await capture.stop()
            // A white fixture must fill the encoded frame, including its bottom and right.
            // Before the fix, the upscale cases contain zeros outside the top-left quarter.
            let samples = frame.read()
            let passed = samples?.allSatisfy { $0 > 200 } == true
            print("\(passed ? "ok" : "FAIL"): \(name), luma samples \(samples ?? [])")
            if !passed { failures += 1 }
        }
    } catch {
        print("FAIL: \(error)")
        failures += 1
    }
    window.orderOut(nil)
    exit(failures == 0 ? 0 : 1)
}
app.run()
