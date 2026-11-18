import Foundation
import StreamProtocol

/// The device's rules for an Apple Pencil as a pen (docs/pencil-pressure-plan.md §5.1): whether a
/// stroke goes to the Mac as a pen's (kind 45) or as the mouse's (kind 8), what each reading of the
/// Pencil becomes on the wire, when the Mac is told the Pencil left, and which finger touches say
/// nothing while it draws (a resting palm). Pure: the stream's overlay feeds it its touch and hover
/// callbacks and sends what it says (InputOverlay.swift).
struct PenStrokes: Equatable {
    /// How a Pencil's stroke goes to the Mac.
    enum Mode: Equatable { case pen, mouse }

    /// After the Pencil stops touching or hovering, how long before the Mac is told it left: a
    /// hover ends as the tip lands and begins again as it lifts, and neither is leaving.
    static let leaveDelay = 0.1
    /// After the Pencil lifts, how long a finger that lands still says nothing.
    static let palmLinger = 0.5

    /// A Pencil goes as a pen when this device's switch is on and the Mac's window list says it
    /// takes one (`WindowList.pencil`, at least this build's generation); else as the mouse.
    static func penMode(switchOn: Bool, connected: Bool, hostPencil: Int?, generation: Int) -> Bool {
        guard switchOn, connected, let takes = hostPencil else { return false }
        return takes >= generation
    }

    // MARK: Readings

    /// One reading of the Pencil as UIKit gives it: where its tip is in the frame (fractions), its
    /// force over the most it can report, its angles, and when (seconds, the touch's clock).
    struct Reading: Equatable {
        var x: Double
        var y: Double
        /// Nil while hovering, and on an up.
        var pressure: Double?
        var altitude: Double?
        var azimuth: Double?
        var time: Double
    }

    /// A touch's force as the wire's pressure: over its maximum, 0…1. A Pencil that reports no
    /// maximum has no pressure to give: 0.
    static func pressure(force: Double, maximum: Double) -> Double {
        guard maximum > 0, force.isFinite, maximum.isFinite else { return 0 }
        return min(max(force / maximum, 0), 1)
    }

    /// A one-sample message: a hover and a down without a time (a down is its stroke's first sample),
    /// an up or a cancel with its time since its stroke's down (`since`, the down's reading's time).
    static func message(_ phase: String, _ reading: Reading, since began: Double? = nil) -> PenInput {
        PenInput(phase: phase, samples: [sample(reading, since: began)])
    }

    /// One touch callback's readings, oldest first, as "move" messages: at most
    /// `PenInput.maxSamples` each (a callback after a stall can bring more), every reading sent,
    /// each sample's `t` the milliseconds since its stroke's down (`since`), the Pencil's own clock,
    /// which the Mac times the stroke's events by (its PenClock: pull request #381's idea).
    static func moves(_ readings: [Reading], since began: Double?) -> [PenInput] {
        var messages: [PenInput] = []
        var start = 0
        while start < readings.count {
            let chunk = readings[start..<min(start + PenInput.maxSamples, readings.count)]
            messages.append(PenInput(phase: PenInput.move, samples: chunk.map { sample($0, since: began) }))
            start += PenInput.maxSamples
        }
        return messages
    }

    /// A reading as the wire's sample; its time only after its stroke's down, an elapsed time (no clock of
    /// this device leaves it).
    private static func sample(_ reading: Reading, since began: Double?) -> PenSample {
        let ms = began.map { (reading.time - $0) * 1000 }
        return PenSample(x: reading.x, y: reading.y, p: reading.pressure, alt: reading.altitude, az: reading.azimuth,
                         t: ms.flatMap { $0 > 0.05 ? $0 : nil })
    }

    // MARK: A stroke, a hover, and leaving

    /// A Pencil touch is down, in this mode. Fixed as the tip lands, so a stroke's up always goes
    /// the way its down did, whatever the switch or the Mac say meanwhile.
    private(set) var stroke: Mode?
    /// When the stroke's tip landed (its down's reading's time), which its samples' times count from;
    /// nil between strokes.
    private(set) var strokeBegan: Double?
    /// The Pencil is over the glass, not touching.
    private(set) var hovering = false
    /// A hover was seen: this Pencil and iPad report one, so its end means the Pencil left. One
    /// that cannot hover says nothing between strokes, and the Mac lets its pen go by itself.
    private(set) var canHover = false
    /// The Mac was sent a pen message since the last leave: it has the pen in range.
    private(set) var told = false
    private var checkAt: Double?

    /// The tip landed, at `time`. The stroke's mode, for all of it.
    mutating func touchBegan(penMode: Bool, at time: Double) -> Mode {
        let mode: Mode = penMode ? .pen : .mouse
        stroke = mode
        strokeBegan = time
        if mode == .pen { told = true }
        return mode
    }

    /// The tip lifted, or the stroke was taken away. The mode it went in; nil when none had begun.
    mutating func touchEnded(now: Double) -> Mode? {
        let mode = stroke
        stroke = nil
        strokeBegan = nil
        checkAt = now + Self.leaveDelay
        return mode
    }

    /// What becomes of a hover callback.
    enum Hover: Equatable {
        /// A pen's hover (kind 45).
        case pen
        /// A pointer move (kind 8): the mouse's, or the iPad's own trackpad or mouse pointer.
        case mouse
        /// Nothing: it came while the Pencil's tip was on the glass.
        case ignore
    }

    /// A hover began or moved; `isPencil` when it is the Pencil's (it reports a height or a tilt).
    /// While a Pencil touch is down, whatever the mode, it is stale and goes nowhere: as the tip
    /// lifts iPadOS sends one more hover, just before the touch ends, carrying where the Pencil
    /// hovered before it landed (an iPad Pro M4 with iPadOS 27.0.1, one in each of six strokes: Hunter
    /// Ahlquist's finding, issue #81; reported again in #322, and main's `pencilTouching` since 0.6.1,
    /// which this rule replaces). Sent as a move, with the Mac's button still down, it drew a line from
    /// the stroke's end back to its start. Otherwise a Pencil's hover goes as a pen's in pen mode, and as
    /// the mouse's else.
    mutating func hover(isPencil: Bool, penMode: Bool) -> Hover {
        guard stroke == nil else { return .ignore }
        guard isPencil else { return .mouse }
        hovering = true
        canHover = true
        guard penMode else { return .mouse }
        told = true
        return .pen
    }

    /// The hover ended: the tip landed, or the Pencil left.
    mutating func hoverEnded(now: Double) {
        hovering = false
        checkAt = now + Self.leaveDelay
    }

    /// Asked `leaveDelay` after each `touchEnded` and `hoverEnded`: true, once, when the Mac should
    /// be told the Pencil left. It was told of the pen, the Pencil can hover, and it is neither
    /// touching nor hovering now.
    mutating func leaveDue(now: Double) -> Bool {
        guard let at = checkAt, now >= at else { return false }
        checkAt = nil
        guard stroke == nil, !hovering, canHover, told else { return false }
        told = false
        return true
    }

    /// The surface is going away. True when the Mac was told of the pen and should hear it left.
    mutating func gone() -> Bool {
        defer { stroke = nil; strokeBegan = nil; hovering = false; told = false; checkAt = nil }
        return told
    }

    // MARK: A resting palm

    /// Which finger touches say nothing because of the Pencil: every finger stroke under way while
    /// its tip is on the glass, to that stroke's end, and one that begins within `palmLinger` of
    /// the tip lifting. A hovering Pencil silences nothing: the other hand may scroll under it.
    struct Palm: Equatable {
        private(set) var touching = false
        private var lastTouchedAt: Double?

        /// The tip landed (`true`) or lifted, at `time`.
        mutating func pencil(touching: Bool, at time: Double) {
            self.touching = touching
            lastTouchedAt = time
        }

        /// Whether a finger stroke whose first finger landed at `began` says nothing.
        func silent(strokeBeganAt began: Double) -> Bool {
            if touching { return true }
            guard let last = lastTouchedAt else { return false }
            return began <= last + PenStrokes.palmLinger
        }
    }
}

/// Smooth Pencil Lines (a switch of this device's, off unless turned on): the 1€ filter (Casiez,
/// Roussel and Vogel, CHI 2012) over a stroke's moves before they reach the Mac, as cubelikeplayDaniel
/// wrote it for Sill in pull request #381, with his numbers: slow, shaky motion is smoothed hard (its
/// cutoff 1.1 Hz), and the cutoff opens as the tip speeds up (11 more hertz for each frame width a
/// second), so a fast stroke follows the tip closely. The line follows the tip a little behind: about
/// 0.1 s on a slow stroke. Never a tap: the stroke's down and its up go where the tip is (`begin` takes
/// the down as it is, and the overlay sends the up unfiltered), only the moves between are smoothed,
/// so a tap, a click and the end of a stroke land where the Pencil touched and lifted. Positions are
/// fractions of the frame; its height over its width (`aspect`) makes the speed a frame width's in
/// every direction. Pure; the stream's overlay keeps one for the stroke under way.
struct PenSmoothing: Equatable {
    /// The cutoff of slow motion (Hz).
    static let minCutoff = 1.1
    /// How much the cutoff opens per frame width a second of the tip's speed (Hz).
    static let beta = 11.0
    /// The cutoff of the speed's own reading (Hz).
    static let derivativeCutoff = 4.0
    /// The Pencil's rate (readings a second), taken when two readings share a time; a measured one
    /// is held to 60…480.
    static let rate = 240.0

    private var x: Double?
    private var y = 0.0
    private var rawX = 0.0
    private var rawY = 0.0
    private var time: Double?
    private var dx = 0.0
    private var dy = 0.0

    /// The frame's height over its width (1 when unknown).
    var aspect = 1.0

    init(aspect: Double = 1) { self.aspect = aspect.isFinite && aspect > 0 ? aspect : 1 }

    /// The stroke's down: the filter starts at the tip, and the down goes as it is.
    mutating func begin(_ reading: PenStrokes.Reading) {
        x = reading.x; y = reading.y; rawX = reading.x; rawY = reading.y
        time = reading.time
        dx = 0; dy = 0
    }

    /// A move's reading, smoothed: its place moves, nothing else does. Before a `begin` it starts there;
    /// a reading that is no number goes on as it is, and the filter starts again at the next one.
    mutating func smooth(_ reading: PenStrokes.Reading) -> PenStrokes.Reading {
        guard reading.x.isFinite, reading.y.isFinite else {
            x = nil
            return reading
        }
        guard let px = x else {
            begin(reading)
            return reading
        }
        var rate = Self.rate
        if let last = time, reading.time > last { rate = min(max(1 / (reading.time - last), 60), 480) }
        time = reading.time
        // The speed, in frame widths a second, read through its own low-pass filter.
        let derivative = Self.alpha(rate: rate, cutoff: Self.derivativeCutoff)
        dx = derivative * (reading.x - rawX) * rate + (1 - derivative) * dx
        dy = derivative * (reading.y - rawY) * rate * aspect + (1 - derivative) * dy
        rawX = reading.x; rawY = reading.y
        let a = Self.alpha(rate: rate, cutoff: Self.minCutoff + Self.beta * (dx * dx + dy * dy).squareRoot())
        x = a * reading.x + (1 - a) * px
        y = a * reading.y + (1 - a) * y
        var out = reading
        out.x = x ?? reading.x
        out.y = y
        return out
    }

    /// How much of a new reading a low-pass filter at `cutoff` takes at `rate`.
    static func alpha(rate: Double, cutoff: Double) -> Double {
        let tau = 1 / (2 * Double.pi * cutoff)
        return 1 / (1 + tau * rate)
    }
}

