import CoreGraphics
import Foundation

// MARK: - Wire

/// Where a `PenBatch` lands on the Mac (`PenBatch.target`).
public enum PenTarget {
    /// The window or Desktop currently streaming (`currentSourceRect`).
    public static let source = 0
    /// The Mac's main display (`catalog.display?.frame`), even when nothing streams (Pad mode).
    public static let display = 1
}

/// A `PenSample`'s phase (`PenSample.phase`). Plain numbers on the wire.
public enum PenPhase {
    public static let hover = 0
    public static let down  = 1
    public static let drag  = 2
    public static let up    = 3
    public static let leave = 4
}

/// One sample of an Apple Pencil stroke or hover (inside `PenBatch.samples`).
public struct PenSample: Codable, Equatable, Sendable {
    public var phase: Int        // PenPhase
    public var x: Double         // 0…1 across the target
    public var y: Double         // 0…1 down the target
    public var pressure: Double  // 0…1 (0 while hovering or lifting)
    public var altitude: Double  // radians: 0 flat on the glass, π/2 upright
    public var azimuth: Double   // radians in the view's plane: 0 right, π/2 down
    public var t: Double?        // device timestamp in seconds (UITouch.timestamp)

    public init(phase: Int, x: Double, y: Double, pressure: Double = 0,
                altitude: Double = .pi / 2, azimuth: Double = 0, t: Double? = nil) {
        self.phase = phase
        self.x = x
        self.y = y
        self.pressure = pressure
        self.altitude = altitude
        self.azimuth = azimuth
        self.t = t
    }
}

/// Kind 45 (`StreamMessageKind.pen`) payload: coalesced Pencil samples from one UIKit frame.
public struct PenBatch: Codable, Equatable, Sendable {
    public var target: Int       // PenTarget
    public var samples: [PenSample]

    public init(target: Int = PenTarget.source, samples: [PenSample]) {
        self.target = target
        self.samples = samples
    }
}

/// Carried on `WindowList.pen`: tells the iPad this Mac accepts kind 45 and gives the main
/// display's aspect ratio for Pad mode when nothing is streaming.
public struct PenCapability: Codable, Equatable, Sendable {
    public var generation: Int
    public var displayWidth: Double
    public var displayHeight: Double

    public init(generation: Int = Pen.generation, displayWidth: Double, displayHeight: Double) {
        self.generation = generation
        self.displayWidth = displayWidth
        self.displayHeight = displayHeight
    }
}

// MARK: - Rules

/// Pure rules for `PenBatch` validation, tilt conversion, aspect-fit tablet geometry, and
/// per-device proximity/tip state. Checked by `Tests/checks/pen`.
public enum Pen {
    public static let generation = 1
    public static let maxSamples = 64

    /// What a single sample asks the Mac's tablet injector to post.
    public enum Post: Equatable, Sendable {
        case enter, leave, move, down, drag, up
    }

    /// Validates and clamps a decoded `PenBatch`. Returns `nil` when `target` is unknown.
    public static func accepted(_ batch: PenBatch) -> [PenSample]? {
        guard batch.target == PenTarget.source || batch.target == PenTarget.display else {
            return nil
        }
        var out: [PenSample] = []
        out.reserveCapacity(min(batch.samples.count, maxSamples))
        for raw in batch.samples {
            guard out.count < maxSamples else { break }
            guard (PenPhase.hover...PenPhase.leave).contains(raw.phase),
                  raw.x.isFinite, raw.y.isFinite,
                  raw.pressure.isFinite, raw.altitude.isFinite, raw.azimuth.isFinite else {
                continue
            }
            let x = min(max(raw.x, 0), 1)
            let y = min(max(raw.y, 0), 1)
            let touching = raw.phase == PenPhase.down || raw.phase == PenPhase.drag
            let pressure = touching ? min(max(raw.pressure, 0), 1) : 0
            let altitude = min(max(raw.altitude, 0), .pi / 2)
            let t = (raw.t?.isFinite == true && (raw.t ?? 0) >= 0) ? raw.t : nil
            out.append(PenSample(
                phase: raw.phase, x: x, y: y,
                pressure: pressure, altitude: altitude, azimuth: raw.azimuth, t: t))
        }
        return out
    }

    /// Converts Apple Pencil `altitude` (0 flat, π/2 upright) and `azimuth` (0 right, π/2 down)
    /// to Quartz tablet tilt (`-1…1` on each axis).
    public static func tilt(altitude: Double, azimuth: Double) -> (x: Double, y: Double) {
        let magnitude = max(0, min(1, cos(altitude)))
        let tx = max(-1, min(1, magnitude * cos(azimuth)))
        let ty = max(-1, min(1, magnitude * sin(azimuth)))
        return (tx, ty)
    }

    /// Places a normalized sample inside `rect`.
    public static func point(_ sample: PenSample, in rect: CGRect) -> CGPoint {
        let x = min(max(sample.x, 0), 1)
        let y = min(max(sample.y, 0), 1)
        return CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
    }

    /// Aspect-fits a display of `aspect` inside `bounds` (used by Pad mode's matte surface).
    public static func fit(_ aspect: CGSize, in bounds: CGSize) -> CGRect {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }
        guard aspect.width > 0, aspect.height > 0 else {
            return CGRect(origin: .zero, size: bounds)
        }
        let scale = min(bounds.width / aspect.width, bounds.height / aspect.height)
        let w = aspect.width * scale
        let h = aspect.height * scale
        return CGRect(x: (bounds.width - w) * 0.5, y: (bounds.height - h) * 0.5, width: w, height: h)
    }

    /// Normalized `(0…1, 0…1)` coordinates of `point` inside `rect`, clamped to the edges.
    public static func fraction(_ point: CGPoint, in rect: CGRect) -> (x: Double, y: Double)? {
        guard rect.width > 0, rect.height > 0 else { return nil }
        let fx = min(max(Double((point.x - rect.minX) / rect.width), 0), 1)
        let fy = min(max(Double((point.y - rect.minY) / rect.height), 0), 1)
        return (fx, fy)
    }

    /// Maps raw UIKit Apple Pencil force (`0…maximumPossibleForce`, typically `0…6.667`) to a
    /// natural drawing tablet pressure (`0…1`) with temporal low-pass smoothing and protection
    /// against unconfirmed UIKit coalesced force estimates (`isEstimated`).
    public static func mapPressure(force: Double, maxForce: Double, previous: Double = 0, isEstimated: Bool = false) -> Double {
        guard maxForce > 0, force.isFinite, maxForce.isFinite else { return 0.5 }
        guard force > 0 else { return previous > 0 ? max(0.02, previous * 0.5) : 0.02 }
        let effectiveMax = max(maxForce * 0.80, 0.5)
        let normalized = min(max(force / effectiveMax, 0), 1)
        let curved = pow(normalized, 0.90)
        guard previous > 0 else { return min(max(curved, 0.02), 1.0) }
        // When UIKit marks the force on the trailing coalesced touch as an estimate awaiting update,
        // weight heavily toward `previous` so frame boundaries never pulse the stroke width.
        let alpha = isEstimated ? 0.15 : 0.35
        let smoothed = alpha * curved + (1.0 - alpha) * previous
        return min(max(smoothed, 0.02), 1.0)
    }

    /// Velocity-adaptive anti-jitter EMA filter for normalized `(0…1, 0…1)` coordinates.
    /// Strong smoothing (`alpha = 0.42`) damps hand/digitizer micro-jitter when moving slowly,
    /// ramping smoothly up to `0.92` for fast strokes with negligible latency.
    public static func smooth(raw: (x: Double, y: Double),
                              previous: (x: Double, y: Double)?) -> (x: Double, y: Double) {
        guard let previous else { return raw }
        let dist = hypot(raw.x - previous.x, raw.y - previous.y)
        let alpha = min(0.92, max(0.42, 0.42 + dist * 38.0))
        return (previous.x + alpha * (raw.x - previous.x),
                previous.y + alpha * (raw.y - previous.y))
    }
}

/// 1€ Filter (Casiez et al., CHI 2012) for Apple Pencil high-frequency input (240 Hz).
/// Eliminates slow digitizer capacitive grid ripple (wobble/jitter) with a low cutoff frequency at low speed,
/// while dynamically opening cutoff with movement velocity to eliminate tracking lag at high speed.
public struct PenFilter: Sendable, Equatable {
    public var minCutoff: Double
    public var beta: Double
    public var dCutoff: Double

    private var xPrev: Double?
    private var yPrev: Double?
    private var rawXPrev: Double?
    private var rawYPrev: Double?
    private var tPrev: Double?
    private var dxPrev: Double = 0
    private var dyPrev: Double = 0

    public init(minCutoff: Double = 1.10, beta: Double = 11.0, dCutoff: Double = 4.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }

    public mutating func reset() {
        xPrev = nil
        yPrev = nil
        rawXPrev = nil
        rawYPrev = nil
        tPrev = nil
        dxPrev = 0
        dyPrev = 0
    }

    private func alpha(rate: Double, cutoff: Double) -> Double {
        let tau = 1.0 / (2.0 * .pi * cutoff)
        let te = 1.0 / rate
        return 1.0 / (1.0 + tau / te)
    }

    public mutating func apply(rawX: Double, rawY: Double, timestamp: Double? = nil, rate: Double = 240.0) -> (x: Double, y: Double) {
        let effectiveRate: Double
        if let t = timestamp, let tp = tPrev, t > tp {
            let dt = t - tp
            effectiveRate = min(max(1.0 / dt, 60.0), 480.0)
        } else {
            effectiveRate = rate
        }
        tPrev = timestamp

        guard let xp = xPrev, let yp = yPrev, let rxp = rawXPrev, let ryp = rawYPrev else {
            xPrev = rawX
            yPrev = rawY
            rawXPrev = rawX
            rawYPrev = rawY
            dxPrev = 0
            dyPrev = 0
            return (rawX, rawY)
        }

        // 1. Raw displacement rate in normalized (0...1) coordinates per second
        let dx = (rawX - rxp) * effectiveRate
        let dy = (rawY - ryp) * effectiveRate
        rawXPrev = rawX
        rawYPrev = rawY

        // 2. Low-pass filter the derivative to eliminate high-frequency ripple from velocity estimate
        let aD = alpha(rate: effectiveRate, cutoff: dCutoff)
        let dxHat = aD * dx + (1.0 - aD) * dxPrev
        let dyHat = aD * dy + (1.0 - aD) * dyPrev
        dxPrev = dxHat
        dyPrev = dyHat

        // 3. Dynamic cutoff based on true movement speed
        let speed = hypot(dxHat, dyHat)
        let cutoff = minCutoff + beta * speed
        let a = alpha(rate: effectiveRate, cutoff: cutoff)

        // 4. Smooth coordinate
        let xHat = a * rawX + (1.0 - a) * xp
        let yHat = a * rawY + (1.0 - a) * yp
        xPrev = xHat
        yPrev = yHat
        return (xHat, yHat)
    }
}

/// Tracks one connected device's Pencil proximity and tip state so every stroke posts a balanced
/// sequence of proximity and mouse/tablet events even across drops or disconnects.
public struct PenState: Equatable, Sendable {
    public private(set) var near = false
    public private(set) var down = false

    public init() {}

    public mutating func posts(for phase: Int) -> [Pen.Post] {
        switch phase {
        case PenPhase.hover:
            var out: [Pen.Post] = []
            if down { down = false; out.append(.up) }
            if !near { near = true; out.append(.enter) }
            out.append(.move)
            return out
        case PenPhase.down:
            var out: [Pen.Post] = []
            if !near { near = true; out.append(.enter) }
            if !down {
                down = true
                out.append(.down)
            } else {
                out.append(.drag)
            }
            return out
        case PenPhase.drag:
            var out: [Pen.Post] = []
            if !near { near = true; out.append(.enter) }
            if !down {
                down = true
                out.append(.down)
            } else {
                out.append(.drag)
            }
            return out
        case PenPhase.up:
            guard down else { return [] }
            down = false
            return [.up]
        case PenPhase.leave:
            var out: [Pen.Post] = []
            if down { down = false; out.append(.up) }
            if near { near = false; out.append(.leave) }
            return out
        default:
            return []
        }
    }

    /// True when `samples` is non-empty, this pen is currently `down`, and every sample only
    /// lifts or leaves (so `LockPolicy` and `RevokedInput` can let an in-flight stroke release).
    public func onlyLifts(_ samples: [PenSample]) -> Bool {
        guard down, !samples.isEmpty else { return false }
        return samples.allSatisfy { $0.phase == PenPhase.up || $0.phase == PenPhase.leave }
    }

    /// Releases any held tip and proximity when a device disconnects or is cut off.
    public mutating func letGo() -> [Pen.Post] {
        var out: [Pen.Post] = []
        if down { down = false; out.append(.up) }
        if near { near = false; out.append(.leave) }
        return out
    }
}
