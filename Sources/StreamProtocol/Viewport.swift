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
    /// The client draws its own pointer. Kept for compatibility; the host now always leaves the
    /// Mac cursor out of the video and streams its shape separately (`.cursorShape`).
    public var localCursor: Bool?
    /// The rate this device wants the stream at: its panel's ceiling (120 on ProMotion, 60
    /// elsewhere), or 60 while Low Power Mode caps the panel. nil (an older client) means 60.
    /// The host runs the stream at the highest rate among its connected clients and restarts the
    /// pipeline when that changes.
    public var fps: Int?

    public init(width: Double, height: Double, scale: Double?, localCursor: Bool? = nil, fps: Int? = nil) {
        self.width = width; self.height = height; self.scale = scale; self.localCursor = localCursor; self.fps = fps
    }
}

/// What a host takes from a device's viewport (kind 9): each side from 1 to 16384 points, and a text
/// scale, when there is one, from 0.25 to 4 (the Aa slider's 0.5 to 1.5, with room either way). Any
/// other viewport is refused whole: the host keeps the one before, takes nothing of the message (its
/// rate neither) and says so in a line that names the device (StreamCoordinator). Until 2026-10-29 a
/// host took any number greater than 0: a side of 1e300 points, or a scale of 1e-300 that made a
/// side infinite, reached the Mac window's fit (`fitToViewport`) and the virtual display's window
/// size, whose log lines turned it into an Int, which traps, and the host died with every device's
/// session (security scan, finding 4). JSON itself carries no NaN or infinity: JSONDecoder refuses
/// `NaN`, `Infinity` and `1e999`, and the host refuses a payload that does not decode too.
///
/// Every device build sends its panel, a few hundred to a few thousand points a side, with a scale
/// of 0.5 to 1.5 or none, so no device is refused (the compatibility floor), and a device holds what
/// it sends to the same bounds (`held`). The rate is the host's own rule: `wantedFPS` holds it to 24
/// to the Mac's limit, and a rate JSON cannot give as an Int does not decode.
///
/// Pure: Foundation only. Tests/checks/viewport-bounds.
public enum ViewportBounds {
    /// Each side's range, in device points: an iPad Pro's panel is 1376 points wide, a Stage Manager
    /// window on a large external display a few thousand.
    public static let sides: ClosedRange<Double> = 1...16384
    /// The text scale's range, device points per Mac point.
    public static let scales: ClosedRange<Double> = 0.25...4

    /// Why a host refuses `v`, for its line: "width 1e+300 (1 to 16384 points)", each field out of its
    /// range, joined by ", ". Nil when the host takes `v`. A NaN is in no range.
    public static func refusal(_ v: Viewport) -> String? {
        let points = "(\(number(sides.lowerBound)) to \(number(sides.upperBound)) points)"
        var why: [String] = []
        if !sides.contains(v.width) { why.append("width \(number(v.width)) \(points)") }
        if !sides.contains(v.height) { why.append("height \(number(v.height)) \(points)") }
        if let s = v.scale, !scales.contains(s) {
            why.append("scale \(number(s)) (\(number(scales.lowerBound)) to \(number(scales.upperBound)))")
        }
        return why.isEmpty ? nil : why.joined(separator: ", ")
    }

    /// What a device sends for `v`: each side held to `sides` and a scale to `scales`, so no host
    /// refuses it; a scale that is not a positive number becomes none, the Mac window left alone. Nil,
    /// nothing to send, while a side is not a positive number (a panel not measured yet).
    public static func held(_ v: Viewport) -> Viewport? {
        guard v.width.isFinite, v.height.isFinite, v.width > 0, v.height > 0 else { return nil }
        var held = v
        held.width = min(max(v.width, sides.lowerBound), sides.upperBound)
        held.height = min(max(v.height, sides.lowerBound), sides.upperBound)
        held.scale = v.scale.flatMap { $0.isFinite && $0 > 0 ? min(max($0, scales.lowerBound), scales.upperBound) : nil }
        return held
    }

    /// A number for a log line as `Int(x)` prints it, toward zero ("1512" for 1512.7), without its
    /// trap: one no Int holds (a NaN, an infinity, 1e300) prints as Swift prints the Double ("nan",
    /// "inf", "1e+300"). The host's lines that print a size from a device's viewport use it.
    public static func whole(_ x: Double) -> String {
        if let i = Int(exactly: x.rounded(.towardZero)) { return String(i) }
        return "\(x)"
    }

    public static func whole(_ x: CGFloat) -> String { whole(Double(x)) }

    /// "1512×949", each side as `whole` prints it.
    public static func whole(_ s: CGSize) -> String { "\(whole(s.width))×\(whole(s.height))" }

    /// A number exactly as it came, for a refusal: a whole one without ".0" ("-1", "16385"), any other
    /// as Swift prints the Double ("0.1", "1e-300", "nan").
    public static func number(_ x: Double) -> String {
        if x == x.rounded(), let i = Int(exactly: x) { return String(i) }
        return "\(x)"
    }
}

/// Client → host once a second while connected. Lets the Mac's log show what the device sees,
/// which is how the latency number gets measured without a screenshot of the device.
///
/// A current client measures every frame and several pings a second, and each report covers the
/// second since the one before. The first four fields are the ones every host requires, so they
/// keep carrying the typical value: that second's median, or -1 when the second had no sample
/// (no frame arrived, no pong came back) rather than an older number repeated. The maxima came
/// later as optional fields: an older host ignores them, and nil means an older client, whose
/// frame age and rtt are single samples.
public struct ClientStats: Codable, Hashable {
    public var fps: Int
    public var frameAgeMs: Int      // host encode timestamp → received on the device (clocks assumed synced)
    public var rttMs: Int           // ping round trip
    public var device: String       // model name, so several clients can be told apart
    /// The worst frame age of that second, -1 when no frame arrived. nil from an older client.
    public var frameAgeMaxMs: Int?
    /// The slowest round trip among that second's pongs, -1 when none came back. nil from an older client.
    public var rttMaxMs: Int?
    /// The Mac's sound (kind 43): that second's median of how far the sound trailed the picture as the
    /// device sees it, in ms, -1 for a second in which no sound played. Nil from a device that has
    /// played none this session, and from an older client.
    public var audioBehindMs: Int?
    /// The sound's packets of that second that came too late to play. Nil as `audioBehindMs`.
    public var audioLate: Int?

    public init(fps: Int, frameAgeMs: Int, rttMs: Int, device: String,
                frameAgeMaxMs: Int? = nil, rttMaxMs: Int? = nil, audioBehindMs: Int? = nil, audioLate: Int? = nil) {
        self.fps = fps; self.frameAgeMs = frameAgeMs; self.rttMs = rttMs; self.device = device
        self.frameAgeMaxMs = frameAgeMaxMs; self.rttMaxMs = rttMaxMs
        self.audioBehindMs = audioBehindMs; self.audioLate = audioLate
    }

    /// A host's count of the sound's late packets since its last stats line (StreamServer), with one
    /// report's `audioLate` added: a missing or negative count adds nothing, and the sum stops at
    /// Int.max. The count is the device's own number, and `+` traps past Int.max: until 2026-10-29 two
    /// reports of Int.max within the line's 1.5 s ended Sill and every device's session (found in the
    /// review of the security scan's finding 4). Pure: Tests/checks/viewport-bounds.
    public static func lateSince(_ count: Int, adding late: Int?) -> Int {
        let more = max(0, late ?? 0)
        return count > Int.max - more ? Int.max : count + more
    }
}

/// The Mac's current cursor, so the client can draw the same shape (arrow, I-beam, resize, hand…)
/// under its own pointer. hotspot and size are in Mac points; the PNG is the cursor's best
/// representation (usually 2×). Layout: hotX, hotY, width, height as Float32 big-endian, then PNG.
public enum CursorShapeBlob {
    public static func encode(hotspot: CGPoint, size: CGSize, png: Data) -> Data {
        var d = Data(capacity: 16 + png.count)
        for v in [Float(hotspot.x), Float(hotspot.y), Float(size.width), Float(size.height)] {
            d.appendBigEndian(v.bitPattern)
        }
        d.append(png)
        return d
    }
    public static func decode(_ d: Data) -> (hotspot: CGPoint, size: CGSize, png: Data)? {
        guard d.count > 16 else { return nil }
        func f(_ i: Int) -> CGFloat { CGFloat(Float(bitPattern: d.readBigEndian(UInt32.self, at: i * 4))) }
        return (CGPoint(x: f(0), y: f(1)), CGSize(width: f(2), height: f(3)), d.subdata(in: (d.startIndex + 16)..<d.endIndex))
    }
}
