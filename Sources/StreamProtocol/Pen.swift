import Foundation

// Apple Pencil pressure and tilt (docs/pencil-pressure-plan.md §3): kind 45. The rules of
// HostSettings.swift apply (JSON only; no enums on the wire, strings instead; fields added later
// are optional; never rename or retype a field). Later Pencil features (barrel roll, hover
// distance, an eraser) are optional fields of a sample or new phases, which a host that does not
// know them skips.
//
// Pure: Foundation only, so it is checked on its own with swiftc.

/// Device → host (kind 45): an Apple Pencil on the stream, as a pen rather than a mouse. One message
/// is one phase of a stroke with its samples: the Mac posts each as the mouse event it would post
/// for kind 8 (a move, the left button down, a drag, the button up) carrying a tablet pen's pressure
/// and tilt. A device sends it only to a host whose window list says `pencil` 1 or more
/// (`WindowList.pencil`); every other host gets the Pencil as kind 8, as before. A host from before
/// maps kind 45 to `.unknown` and skips it.
///
/// `{"phase":"move","samples":[{"alt":1.05,"az":0.3,"p":0.42,"t":4.2,"x":0.51234,"y":0.4},…]}`,
/// `{"phase":"leave"}`.
public struct PenInput: Codable, Equatable, Sendable {
    /// One of the six below. A string, so a later phase reaches an older host as one it skips.
    public var phase: String
    /// Oldest first. None for "leave".
    public var samples: [PenSample]?

    public init(phase: String, samples: [PenSample]? = nil) {
        self.phase = phase
        self.samples = samples
    }

    /// The Pencil over the glass, not touching: the pointer moves. One sample.
    public static let hover = "hover"
    /// The tip lands: the left button goes down. One sample.
    public static let down = "down"
    /// The tip moves on the glass: a drag. One touch callback's samples, 1 to `maxSamples`.
    public static let move = "move"
    /// The tip lifts: the button comes up. One sample.
    public static let up = "up"
    /// The stroke was taken away (a system gesture, a call): the button comes up, where the sample
    /// says or, without one, where the Pencil last was.
    public static let cancel = "cancel"
    /// The Pencil is out of range. No samples.
    public static let leave = "leave"
    /// Every phase this build sends and takes.
    public static let phases = [hover, down, move, up, cancel, leave]

    /// The most samples one message may carry: a host skips a message with more.
    public static let maxSamples = 32

    /// `WindowList.pencil` from a host that takes kind 45's six phases.
    public static let generation = 1

    /// The message as a host acts on it, or nil for one it skips: a phase it does not know, more
    /// than `maxSamples` samples, a sample that is not usable (`PenSample.checked`), or a count
    /// its phase does not allow (one for "hover", "down" and "up"; one or more for "move"; none or
    /// one for "cancel"; none for "leave", whose samples are dropped). Each sample is cleaned.
    public func checked() -> PenInput? {
        guard Self.phases.contains(phase) else { return nil }
        let given = samples ?? []
        guard given.count <= Self.maxSamples else { return nil }
        if phase == Self.leave { return PenInput(phase: phase) }
        var cleaned: [PenSample] = []
        for sample in given {
            guard let ok = sample.checked() else { return nil }
            cleaned.append(ok)
        }
        switch phase {
        case Self.move: guard cleaned.count >= 1 else { return nil }
        case Self.cancel: guard cleaned.count <= 1 else { return nil }
        default: guard cleaned.count == 1 else { return nil }
        }
        return PenInput(phase: phase, samples: cleaned.isEmpty ? nil : cleaned)
    }
}

/// One reading of the Pencil. The device's own values: the Mac turns them into what macOS wants,
/// so a change to that mapping needs no new device build.
public struct PenSample: Codable, Equatable, Sendable {
    /// Where the tip is, as a fraction of the streamed frame: InputEvent's space (Input.swift), 0…1
    /// across its width and height, 5 decimal places (0.03 px on a 3000 px frame).
    public var x: Double
    public var y: Double
    /// Pressure, 0…1: the touch's force over the most the Pencil can report. Nil while hovering.
    public var p: Double?
    /// Altitude in radians: π/2 with the Pencil upright, 0 with it flat on the glass.
    public var alt: Double?
    /// Azimuth in the frame, in radians: the direction the Pencil's top points, 0 along +x, π/2
    /// along +y (down the frame).
    public var az: Double?
    /// Milliseconds before the message's last sample; 0 or nil for the last one.
    public var t: Double?

    public init(x: Double, y: Double, p: Double? = nil, alt: Double? = nil, az: Double? = nil, t: Double? = nil) {
        self.x = Self.rounded(x, places: 100_000)
        self.y = Self.rounded(y, places: 100_000)
        self.p = p.map { Self.rounded($0, places: 10_000) }
        self.alt = alt.map { Self.rounded($0, places: 10_000) }
        self.az = az.map { Self.rounded($0, places: 10_000) }
        self.t = t.map { Self.rounded($0, places: 10) }
    }

    /// A value as the wire carries it: short JSON, and far finer than a Pencil reports.
    static func rounded(_ v: Double, places: Double) -> Double { (v * places).rounded() / places }

    /// The sample as a host uses it, or nil when a value it has is not finite: the pressure
    /// clamped to 0…1, the altitude to 0…π/2, a time before the last sample never negative. The
    /// position is left as it is: off the frame is off the frame, as for kind 8.
    public func checked() -> PenSample? {
        guard x.isFinite, y.isFinite, [p, alt, az, t].allSatisfy({ $0?.isFinite ?? true }) else { return nil }
        var sample = self
        sample.p = p.map { min(max($0, 0), 1) }
        sample.alt = alt.map { min(max($0, 0), .pi / 2) }
        sample.t = t.map { max($0, 0) }
        return sample
    }
}
