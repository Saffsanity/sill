import Foundation

/// Client → host: the size of the client's stream panel in device points and how it wants the
/// Mac window sized to it. Milestone 3's fallback path: rather than a virtual display, the host
/// resizes the real window through Accessibility.
///
/// `scale` is device points per Mac point for text. nil means "leave the Mac window alone"
/// (the default today). 1.0 fits the window to the panel at 1:1 points; 1.5 makes the window a
/// third smaller in Mac points so its content renders a third larger on the device; 0.8 the
/// reverse. Apps have minimum window sizes; the host clamps and streams whatever it actually got.
public struct Viewport: Codable, Hashable {
    public var width: Double
    public var height: Double
    public var scale: Double?

    public init(width: Double, height: Double, scale: Double?) {
        self.width = width; self.height = height; self.scale = scale
    }
}

/// Client → host once a second while connected. Lets the Mac's log show what the device sees,
/// which is how the latency number gets measured without a screenshot of the device.
public struct ClientStats: Codable, Hashable {
    public var fps: Int
    public var frameAgeMs: Int      // host encode timestamp → decoded on the device (clocks assumed synced)
    public var rttMs: Int           // ping round trip
    public var device: String       // model name, so several clients can be told apart

    public init(fps: Int, frameAgeMs: Int, rttMs: Int, device: String) {
        self.fps = fps; self.frameAgeMs = frameAgeMs; self.rttMs = rttMs; self.device = device
    }
}
