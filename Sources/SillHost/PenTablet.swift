import Foundation
import StreamProtocol

/// One sample as macOS wants it: pressure 0…1, tilt −1…1 on each axis (x positive to the right, y
/// positive away from the user).
package struct PenPoint: Equatable, Sendable {
    package var pressure: Double
    package var tiltX: Double
    package var tiltY: Double
    /// The tip is on the glass: the pen's first button, as a tablet driver reports it.
    package var tipDown: Bool
    /// The sample's own time, as the device sent it (`PenSample.t`): milliseconds since its stroke's
    /// first sample. Nil for a hover and for what the host makes (the up of a pen it lets go). The
    /// stroke clock (`PenClock`) times a stroke's events by it.
    package var elapsed: Double?

    package init(pressure: Double, tiltX: Double = 0, tiltY: Double = 0, tipDown: Bool, elapsed: Double? = nil) {
        self.pressure = min(max(pressure, 0), 1)
        self.tiltX = min(max(tiltX, -1), 1)
        self.tiltY = min(max(tiltY, -1), 1)
        self.tipDown = tipDown
        self.elapsed = elapsed
    }
}

/// An Apple Pencil's messages (kind 45, Pen.swift) as what the Mac posts for them
/// (docs/pencil-pressure-plan.md §4.1): the pen coming into range and leaving it, and each sample as
/// a move, the left button down or the button up with a tablet pen's pressure and tilt. Pure: it
/// decides, InputInjector posts (through its pointer path, with a button state of the pen's own).
///
/// The pen is a device of its own, as Sidecar's Pencil is on a Mac (recorded on macOS 27 with an
/// iPad Pro, docs/pencil-pressure-plan.md §13): its down goes whoever else holds the left button,
/// its stroke drags until its own up whoever else lets go meanwhile, and mouse input (kind 8: a
/// finger, a trackpad, another device, the Mac's own mouse) neither ends the stroke nor takes the
/// pen out of range. A mouse event never reads as a pen's: it carries no tablet fields.
///
/// What it keeps true, whatever arrives and in whatever order:
/// - every point lies between an enter and a leave;
/// - a down it posted gets exactly one up: its own, a cancel's, a leave's, the device leaving, or
///   the host's end;
/// - the pen leaves by itself `idleLeave` seconds after its last message, when that was neither
///   a hover nor with the tip down (an iPad whose Pencil cannot hover says nothing after a stroke's
///   up). A hovering pen stays in range, however long it is held still, until its leave: Sidecar
///   keeps its Pencil in range so, and a device sends the leave as its Pencil goes out of range.
package struct PenTablet: Sendable {
    /// A connection, as KeyStrokes names one.
    package typealias Device = ObjectIdentifier

    /// A position as the device sent it: a fraction of the streamed frame.
    package struct Place: Equatable, Sendable {
        package var x: Double
        package var y: Double
    }

    package enum Post: Equatable, Sendable {
        /// The pen comes into range.
        case enter
        /// The pen goes out of range.
        case leave
        /// The pointer moves: a drag while the button is down.
        case move(Place, PenPoint)
        /// The left button goes down.
        case down(Place, PenPoint)
        /// The left button comes up; without a place, where the pointer is.
        case up(Place?, PenPoint)
    }

    /// Seconds after the last pen message, when it was neither a hover nor with the tip down, at
    /// which the pen leaves by itself.
    package static let idleLeave = 1.0
    /// The least pressure a point carries while the tip is down: an app may read 0 as no contact.
    package static let pressureFloor = 0.01

    /// Between an enter and a leave.
    package private(set) var inProximity = false
    /// A down this posted has not had its up.
    package private(set) var tipDown = false
    /// The last message taken was a hover: the Pencil is over the glass, and leaves only by its leave.
    package private(set) var hovering = false
    /// Whose pen it is: the device of the last message taken.
    private var owner: Device?
    private var lastPenAt = 0.0

    package init() {}

    /// One pen message from `device`. A message that is not usable (`PenInput.checked`) posts nothing.
    package mutating func take(_ input: PenInput, from device: Device, now: Double) -> [Post] {
        guard let input = input.checked() else { return [] }
        // While one device draws, another's pen is not this tablet's.
        if tipDown, let owner, owner != device { return [] }
        let samples = input.samples ?? []
        var posts: [Post] = []
        func enter(_ posts: inout [Post]) {
            if !inProximity { inProximity = true; posts.append(.enter) }
        }
        lastPenAt = now
        switch input.phase {
        case PenInput.hover:
            guard let sample = samples.first else { return [] }
            owner = device
            hovering = true
            if tipDown {
                // A hover with the tip down: its up was lost. The button comes up here.
                tipDown = false
                posts.append(.up(Self.place(sample), Self.point(sample, tipDown: false)))
            } else {
                enter(&posts)
                posts.append(.move(Self.place(sample), Self.point(sample, tipDown: false)))
            }
        case PenInput.down:
            // A down while this pen's tip is down is a repeat. Another source holding the left
            // button does not stop it: the pen's button is its own.
            guard let sample = samples.first, !tipDown else { return [] }
            owner = device
            hovering = false
            enter(&posts)
            tipDown = true
            posts.append(.down(Self.place(sample), Self.point(sample, tipDown: true)))
        case PenInput.move:
            owner = device
            hovering = false
            enter(&posts)
            for sample in samples { posts.append(.move(Self.place(sample), Self.point(sample, tipDown: tipDown))) }
        case PenInput.up, PenInput.cancel:
            guard tipDown else { return [] }
            tipDown = false
            posts.append(.up(samples.first.map(Self.place), samples.first.map { Self.point($0, tipDown: false) } ?? Self.lifted))
        case PenInput.leave:
            guard owner == nil || owner == device else { return [] }   // another device's pen is still here
            posts = letGo()
        default:
            return []
        }
        return posts
    }

    /// `device` left: its pen's button comes up and the pen leaves.
    package mutating func deviceLeft(_ device: Device) -> [Post] {
        guard owner == device else { return [] }
        return letGo()
    }

    /// The host is going: the button up, the pen out of range.
    package mutating func releaseAll() -> [Post] { letGo() }

    /// Seconds until the pen leaves by itself; nil while it is out of range, its tip is down, or it
    /// hovers.
    package func leavesIn(now: Double) -> Double? {
        guard inProximity, !tipDown, !hovering else { return nil }
        return max(0, lastPenAt + Self.idleLeave - now)
    }

    /// The pen leaves when nothing came from it for `idleLeave` seconds with the tip up.
    package mutating func idle(now: Double) -> [Post] {
        guard let wait = leavesIn(now: now), wait <= 0 else { return [] }
        return letGo()
    }

    private mutating func letGo() -> [Post] {
        var posts: [Post] = []
        if tipDown { tipDown = false; posts.append(.up(nil, Self.lifted)) }
        if inProximity { inProximity = false; posts.append(.leave) }
        owner = nil
        hovering = false
        return posts
    }

    private static let lifted = PenPoint(pressure: 0, tipDown: false)

    private static func place(_ sample: PenSample) -> Place { Place(x: sample.x, y: sample.y) }

    /// A sample as a point: its pressure only while the tip is down (never under `pressureFloor`
    /// then; full, as a mouse's, when the device sent none), its angles as tilt.
    package static func point(_ sample: PenSample, tipDown: Bool) -> PenPoint {
        let tilt = tilt(altitude: sample.alt, azimuth: sample.az)
        return PenPoint(pressure: tipDown ? max(sample.p ?? 1, pressureFloor) : 0, tiltX: tilt.x, tiltY: tilt.y, tipDown: tipDown,
                        elapsed: sample.t)
    }

    /// The Pencil's angles as macOS's tilt. With θ the lean from upright (π/2 − altitude), the tilt
    /// is θ's sine along the azimuth: x toward +x of the frame, y positive away from the user, so
    /// against the frame's y, which grows downward. Upright is 0,0; flat on the glass has length 1.
    /// Without both angles: no tilt.
    package static func tilt(altitude: Double?, azimuth: Double?) -> (x: Double, y: Double) {
        guard let altitude, let azimuth else { return (0, 0) }
        let lean = sin(.pi / 2 - min(max(altitude, 0), .pi / 2))
        return (lean * cos(azimuth) + 0, -lean * sin(azimuth) + 0)   // + 0: never −0
    }

    /// The pointer event a message amounts to, for the rules kind 8 goes through before it is
    /// posted (what closes a gesture's view, what brings a window forward): a down the left
    /// button's, an up or a cancel its release, a hover or a move a move, each at the message's last
    /// sample; nil for a leave. A cancel without a sample has no place, and none of those rules
    /// reads a release's.
    package static func pointerEvent(for input: PenInput) -> InputEvent? {
        let last = input.samples?.last
        switch input.phase {
        case PenInput.hover, PenInput.move: return last.map { .pointer(.move, x: $0.x, y: $0.y) }
        case PenInput.down: return last.map { .pointer(.leftDown, x: $0.x, y: $0.y) }
        case PenInput.up, PenInput.cancel: return .pointer(.leftUp, x: last?.x ?? 0, y: last?.y ?? 0)
        default: return nil
        }
    }

    /// Whether a message can move the Mac's pointer, and so opens PointerControl's settle as kind 8's
    /// pointer events do: one with a sample. A leave, and a cancel without a sample, move nothing
    /// (the pen goes out of range, or its button comes up, where the pointer is), as a pen leaving a
    /// Mac tablet, or Sidecar's Pencil, moves no cursor. Either still hands its device the pointer, as
    /// every input does. A message that does not decode moves nothing.
    package static func movesPointer(_ input: PenInput) -> Bool {
        guard let checked = input.checked() else { return false }
        return !(checked.samples ?? []).isEmpty
    }

    /// The same for a kind 45 payload as the host reads it.
    package static func movesPointer(payload: Data) -> Bool {
        Wire.decode(PenInput.self, from: payload).map(movesPointer) ?? false
    }

    /// Whether a message still goes when it has nowhere to land (nothing streams): an up or a
    /// cancel while the pen's tip is down (`tipDown`), which this then lets up where the pointer is,
    /// and a leave. A hover, a down and a move never do.
    package static func stillGoes(_ input: PenInput, tipDown: Bool) -> Bool {
        switch input.phase {
        case PenInput.up, PenInput.cancel: return tipDown
        case PenInput.leave: return true
        default: return false
        }
    }

    /// What a revoked session's receive loop still hands on (StreamServer, on its network queue,
    /// which knows nothing of the tablet), as RevokedInput.mayLetGo does for kind 8: an up, a cancel
    /// and a leave, which the coordinator then posts only as `stillGoes` says and the tablet takes
    /// only from the device whose pen it is. A hover, a down and a move go no further.
    package static func mayLetGo(_ input: PenInput) -> Bool { stillGoes(input, tipDown: true) }
}

/// The stroke clock: each event of a stroke timed by the Pencil's own clock, not by when its message
/// reached the Mac. The idea and its first form are cubelikeplayDaniel's (pull request #381, "hardware
/// timestamp sync"): samples that cross Wi-Fi in a burst would otherwise reach an app at once, and an app
/// that reads a stroke's speed from its events' times (a brush that thins as it speeds up) drew beads
/// where the burst landed. The device sends each sample's `t`, the milliseconds since its stroke's first
/// sample, an elapsed time only (no clock of the device's leaves it); the stroke's down is timed as it is
/// posted, and every later point of the stroke at the down's time plus its own `t`, so the stroke keeps
/// the spacing the Pencil drew it with.
///
/// Its rules, whatever arrives:
/// - never later than now: a point the down's time would put in the future (the down came later than
///   the rest) is timed now, and the stroke's clock moves back with it;
/// - in order: each time at least `minStep` after the last one given, unless that would pass now;
/// - only a stroke the Mac has down: a hover, a move with the tip up, a proximity event and a point
///   without its time keep the time macOS gives them as they are posted (`nil`).
///
/// AppKit reads a CGEvent's timestamp as nanoseconds since the Mac started, the clock of
/// `CLOCK_UPTIME_RAW` and of `NSEvent.timestamp` (measured on Apple silicon, whose mach clock ticks 41.7
/// times slower: `SillHost --pen-selftest`'s "Event clock" readings). Its times are seconds on that clock.
/// TEST ONLY: `SILL_TEST_PEN_CLOCK=arrival` turns it off for a run (`mode`), every event then timed as it
/// is posted, as before it, so the two can be compared in drawing apps. Pure: the injector posts.
package struct PenClock: Sendable {
    /// Two times given are at least this far apart (seconds), so samples that share a time stay in
    /// their order. A Pencil's samples are 4.2 ms apart (240 a second).
    package static let minStep = 0.0005
    /// The time (seconds, the event clock) the stroke's first sample, `t` 0, is timed at; nil between
    /// strokes.
    package private(set) var anchor: Double?
    /// The last time given.
    package private(set) var last = 0.0

    package init() {}

    /// The stroke's down, posted at `now`: timed now (never before the last time given), and the
    /// stroke's clock starts from it, less its own `t` (0 from a device, which sends none on a down).
    package mutating func down(_ point: PenPoint, now: Double) -> Double {
        let time = max(now, last)
        anchor = time - (point.elapsed ?? 0) / 1000
        last = time
        return time
    }

    /// A point of the stroke after its down (each drag, and its up), posted at `now`: the down's time
    /// plus its own `t`, held to the rules above. Nil while no stroke is down, or for a point without
    /// its time: the event then keeps the time it is posted at.
    package mutating func during(_ point: PenPoint, now: Double) -> Double? {
        guard var anchor, let elapsed = point.elapsed else { return nil }
        var time = anchor + elapsed / 1000
        if time > now {
            anchor = now - elapsed / 1000
            self.anchor = anchor
            time = now
        }
        time = min(max(time, last + Self.minStep), max(now, last))
        last = time
        return time
    }

    /// The stroke ended: its up was posted, or the pen was let go.
    package mutating func end() { anchor = nil }

    /// TEST ONLY: the variable that turns the stroke clock off for a run, read by every host (Sill.app
    /// too: it changes only the times of a Pencil's events, so it lets no one in), and the one line it
    /// prints at start; nil when it is not set. The value is never echoed.
    package static let variable = "SILL_TEST_PEN_CLOCK"

    package static func mode(environment: [String: String]) -> (arrival: Bool, line: String?) {
        guard let value = environment[variable], !value.isEmpty else { return (false, nil) }
        switch value {
        case "arrival":
            return (true, "TEST: an Apple Pencil's events are timed as they are posted, not by the Pencil's own clock (\(variable)=arrival).")
        case "stroke":
            return (false, "TEST: an Apple Pencil's events are timed by the Pencil's own clock, as without \(variable).")
        default:
            return (false, "\(variable) ignored: it takes arrival or stroke; a Pencil's events are timed by its own clock.")
        }
    }

    /// A time as a CGEvent's timestamp: nanoseconds on the event clock. Only times this gave (between
    /// `minStep` and a real now) reach it, so it never traps; anything else is 0, which macOS replaces
    /// with the time it posts the event at.
    package static func timestamp(_ time: Double) -> UInt64 {
        guard time.isFinite, time > 0, time < 1e9 else { return 0 }
        return UInt64((time * 1_000_000_000).rounded())
    }
}
