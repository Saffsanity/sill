import CoreGraphics
import Foundation

// The pointer on the device (docs/pointer-visibility-plan.md §7). Noah, 2026-09-25: "When the Mac is
// controlling the mouse pointer, it should show the real mouse pointer on the desktop on Sill. When
// Sill is controlling the Mac, continue to hide the real pointer and only render the client side one
// in portrait mode when the trackpad is used." So the one sprite shows the Mac's pointer while the Mac
// (its own mouse or trackpad, or an app warping it) or another device moved it last, and this device's
// own only on the portrait trackpad. The Mac tells where its pointer is with kind 26 (MacPointer),
// sent to every device but the one moving it.
//
// Pure: Foundation and CoreGraphics only, so it is checked on its own with swiftc
// (Tests/checks/pointer-presence). Three parts:
// • PointerPresence (main): what the sprite shows, the trackpad's linger (Q1's flip), and the rules a
//   report from the Mac is judged by.
// • PointerFeedState (the network queue): who moved the pointer last as this device knows it, where
//   the Mac's pointer is, the anchor, what this device sent in the last 3 s, and a hand-over's
//   carry-over; PointerFeed keeps it under a lock for main to read.
// • PadCursor (the portrait pad): where a stroke, and a move after the Mac took over, carry on from.

/// What the device's one pointer sprite shows (§7.2):
///
///     Who moved the pointer last             Layout      The sprite
///     the Mac, or another device             any         the Mac's pointer while it is over the stream
///     this device, the on-screen trackpad    portrait    this device's own, until another input takes over (Q1)
///     this device, the on-screen trackpad    landscape   hidden
///     this device, a finger on the stream,   any         hidden
///       typing, a hardware key, the iPad's
///       own trackpad or mouse
///     this device, the Pencil                any         hidden (Q2)
///
/// Nothing shows while nothing streams. The shape is kind 14's in every row. A value; main thread.
struct PointerPresence: Equatable {
    /// Who moved the pointer last: this device, or the Mac or another device.
    enum Control: Equatable { case here, elsewhere }
    /// What drew this device's own pointer.
    enum Origin: Equatable { case trackpad, pencil, none }

    /// A new session: the Mac has the pointer until this device's first input (Q6).
    var control: Control = .elsewhere
    /// The Mac's position from the last fresh report that was over the stream (a fraction of the
    /// frame), and whether the last fresh report was.
    var mac: CGPoint?
    var macInside = false
    /// This device's own pointer (StreamClient.localPointer), and what drew it.
    var own: CGPoint?
    var origin: Origin = .none
    /// The laptop layout: inner or outer portrait.
    var portrait = false
    /// Something streams (`client.active != .none`).
    var streaming = false
    /// Q2: the Pencil draws no pointer, hovering or touching (the request, by its letter). True draws
    /// it again, in any layout (the harness's `-SillPencilPointer 1`).
    var pencilShowsPointer = PointerPresence.pencilShowsPointerByDefault
    /// Q1: the trackpad's pointer stays until another input takes over: in the laptop layout it is the
    /// only way to aim a tap. A number of seconds hides it that long after the last finger lifts.
    var trackpadLinger = PointerPresence.trackpadLingerByDefault
    /// Fingers on the portrait pad, and when the last of them lifted (nil while one is down): only the
    /// linger reads them.
    private(set) var fingersOnTrackpad = 0
    private(set) var trackpadLiftedAt: Double?

    static let pencilShowsPointerByDefault = false
    static let trackpadLingerByDefault: Double? = nil

    /// Where the sprite's tip goes, a fraction of the frame, or nil to hide it.
    func sprite(now: Double) -> CGPoint? {
        guard streaming else { return nil }
        switch control {
        case .elsewhere:
            return macInside ? mac : nil
        case .here:
            switch origin {
            case .trackpad:
                guard portrait else { return nil }
                if let ends = lingerEnds, now > ends { return nil }
                return own
            case .pencil:
                return pencilShowsPointer ? own : nil
            case .none:
                return nil
            }
        }
    }

    /// When the linger hides the trackpad's pointer, for the one timer that re-renders then; nil
    /// while there is nothing to hide (no linger, a finger down, or the sprite not the pad's).
    var lingerEnds: Double? {
        guard let linger = trackpadLinger, streaming, control == .here, origin == .trackpad, portrait,
              let lifted = trackpadLiftedAt else { return nil }
        return lifted + linger
    }

    /// This device's own pointer and what drew it: the pad's cursor, the Pencil's position, or nil (a
    /// finger on the stream, typing, a key, the iPad's own pointer).
    mutating func setOwn(_ p: CGPoint?, from origin: Origin) {
        own = p
        self.origin = origin
    }

    /// How many fingers are on the portrait pad: the last one lifting starts the linger.
    mutating func fingers(_ n: Int, now: Double) {
        let wasDown = fingersOnTrackpad > 0
        fingersOnTrackpad = max(0, n)
        if fingersOnTrackpad > 0 {
            trackpadLiftedAt = nil
        } else if wasDown {
            trackpadLiftedAt = now
        }
    }

    /// Who has the pointer and where the Mac's is, as the network queue's feed has them.
    mutating func follow(_ feed: PointerFeedState) {
        control = feed.control
        mac = feed.mac
        macInside = feed.macInside
    }

    /// §3.3: a report (kind 26) counts only if the Mac had read every input this device sent on the
    /// connection (`seen` at least what SessionLink counted; nil counts as 0) and no coalesced move is
    /// still waiting to go out. Otherwise the Mac built it before it read this device's latest input.
    static func isFresh(seen: Int?, sentOnSession: Int, movePending: Bool) -> Bool {
        !movePending && (seen ?? 0) >= sentOnSession
    }

    /// How close, on each axis, a report must come to a position of this device's own to be it (§7.3).
    static let restatementTolerance = 0.002

    /// §7.3, the carry-over: a report over the stream within `restatementTolerance` of the anchor, or
    /// of a position this device sent lately, is this device's own doing reported back.
    static func isRestatement(x: Double, y: Double, inside: Bool, anchor: CGPoint?, recent: [CGPoint]) -> Bool {
        guard inside else { return false }
        let near = { (p: CGPoint) in
            abs(Double(p.x) - x) <= restatementTolerance && abs(Double(p.y) - y) <= restatementTolerance
        }
        return anchor.map(near) == true || recent.contains(where: near)
    }
}

/// The network queue's half of the pointer (§7.3). Who moved it last, as this device knows it: its
/// own input (every kind 8 it sends, coalesced moves included) makes it `.here`; a fresh report from
/// the Mac (kind 26) makes it `.elsewhere`, with where the Mac's pointer is. The anchor, where a
/// trackpad stroke carries on from, is the newer of this device's last pointer event and the Mac's
/// last position over the stream. `takeovers` counts the reports that took the pointer from this
/// device, and only grows.
///
/// A hand-over (the session moving to a new connection: from AWDL to the network, to the cable and
/// back) is a new device to the Mac, which reports the pointer to it at once, having read nothing on
/// it (`seen` 0): fresh by the count, and it would show the Mac's arrow where this device left the
/// pointer, in landscape too, at every move. So when this device had the pointer as the new
/// connection took the session, and until its first input there (or news), a report within
/// `PointerPresence.restatementTolerance` of the anchor or of a position it sent in the last 3 s is
/// its own doing reported back, and changes nothing (the carry-over).
///
/// A value; PointerFeed keeps it under a lock.
struct PointerFeedState: Equatable {
    /// What this device sent, as the feed needs it: a pointer event's position (the anchor, and the
    /// last 3 s), a scroll's location (the last 3 s), or anything else (a key, typed text).
    enum Sent: Equatable { case pointer(CGPoint), scroll(CGPoint), other }
    /// What became of a report.
    enum Report: Equatable {
        /// Built before the Mac read this device's latest input: dropped.
        case stale
        /// During a carry-over, this device's own position reported back: dropped.
        case restatement
        /// The Mac's, or another device's, news: the pointer is elsewhere. `tookOver` when it was this
        /// device's; `changed` when anything the sprite follows changed.
        case news(tookOver: Bool, changed: Bool)
    }
    struct Recent: Equatable {
        let at: Double
        let point: CGPoint
    }

    private(set) var control: PointerPresence.Control = .elsewhere
    private(set) var mac: CGPoint?
    private(set) var macInside = false
    private(set) var anchor: CGPoint?
    private(set) var takeovers = 0
    private(set) var carrying = false
    private(set) var recent: [Recent] = []

    /// How long a position this device sent counts as its own, and how many are kept at most (moves
    /// go out at 125 a second at most, scroll steps about as often).
    static let recentFor = 3.0
    static let recentLimit = 1_024

    /// Every input this device sends (in StreamClient.sendInput's block on the network queue,
    /// coalesced moves included). True when the pointer came here with it: main needs telling then.
    mutating func sent(_ input: Sent, now: Double) -> Bool {
        let came = control != .here
        control = .here
        carrying = false
        switch input {
        case .pointer(let p):
            anchor = p
            remember(p, now: now)
        case .scroll(let p):
            remember(p, now: now)
        case .other:
            break
        }
        return came
    }

    /// A report (kind 26): `position` is where the Mac's pointer is over the stream (MacPointer's
    /// `position`), nil when it is off it; `seen` is the report's, `sentOnSession` what SessionLink
    /// counted, `movePending` whether a coalesced move still waits to go out. Judged by freshness,
    /// then by the carry-over; news takes the pointer.
    mutating func report(at position: CGPoint?, seen: Int?, sentOnSession: Int, movePending: Bool, now: Double) -> Report {
        guard PointerPresence.isFresh(seen: seen, sentOnSession: sentOnSession, movePending: movePending) else { return .stale }
        if carrying, let p = position,
           PointerPresence.isRestatement(x: Double(p.x), y: Double(p.y), inside: true, anchor: anchor, recent: recentPoints(now: now)) {
            return .restatement
        }
        carrying = false
        let tookOver = control == .here
        let before = (control, mac, macInside)
        control = .elsewhere
        macInside = position != nil
        if let position {
            mac = position
            anchor = position
        }
        if tookOver { takeovers += 1 }
        return .news(tookOver: tookOver, changed: before != (control, mac, macInside))
    }

    /// The session moved to a new connection (a hand-over). True when this device had the pointer:
    /// its control carries over until its first input there.
    mutating func handedOver() -> Bool {
        carrying = control == .here
        return carrying
    }

    /// The session ended (tearDown): the Mac has the pointer, nowhere yet, with no anchor and nothing
    /// sent. `takeovers` stays: a pad that saw an older count never takes a new session's for its own.
    mutating func reset() {
        control = .elsewhere
        mac = nil
        macInside = false
        anchor = nil
        carrying = false
        recent = []
    }

    /// The positions this device sent in the last `recentFor` seconds.
    func recentPoints(now: Double) -> [CGPoint] {
        recent.filter { now - $0.at <= Self.recentFor }.map(\.point)
    }

    private mutating func remember(_ p: CGPoint, now: Double) {
        recent.removeAll { now - $0.at > Self.recentFor }
        if recent.count >= Self.recentLimit { recent.removeFirst(recent.count - Self.recentLimit + 1) }
        recent.append(Recent(at: now, point: p))
    }
}

/// PointerFeedState under a lock: written on the network queue (StreamClient's sendInput block, its
/// kind 26 handler and a move's hand-over), read by main (the presence, the anchor, the pad's
/// takeovers).
final class PointerFeed {
    private let lock = NSLock()
    private var state = PointerFeedState()

    var current: PointerFeedState {
        lock.lock(); defer { lock.unlock() }
        return state
    }

    func sent(_ input: PointerFeedState.Sent, now: Double) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return state.sent(input, now: now)
    }

    func report(at position: CGPoint?, seen: Int?, sentOnSession: Int, movePending: Bool, now: Double) -> PointerFeedState.Report {
        lock.lock(); defer { lock.unlock() }
        return state.report(at: position, seen: seen, sentOnSession: sentOnSession, movePending: movePending, now: now)
    }

    func handedOver() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return state.handedOver()
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        state.reset()
    }
}

/// The portrait pad's virtual cursor (TrackpadView), a fraction of the frame clamped to 0…1, and the
/// feed's `takeovers` it last saw (§7.3, §7.5). A stroke's first finger, and the pad joining a window,
/// carry on from the anchor (`adopt`). A move, a scroll or a drag first catches up (`catchUp`): when
/// the Mac or another device took the pointer since the pad last looked, it carries on from the
/// anchor too, so a finger resting on the pad while the Mac took over carries on from the Mac's
/// pointer instead of pulling it back to where the finger stopped. The pad's moves are absolute, so
/// its first after either lands at the anchor plus the finger's travel: a still Mac pointer does not
/// jump.
struct PadCursor: Equatable {
    private(set) var cursor = CGPoint(x: 0.5, y: 0.5)
    private(set) var takeoversSeen = 0

    /// A stroke's first finger, or the pad joining a window: from the anchor when there is one.
    mutating func adopt(anchor: CGPoint?, takeovers: Int) {
        if let anchor { cursor = Self.clamped(anchor) }
        takeoversSeen = takeovers
    }

    /// Before a move, a scroll or a drag reads the cursor: from the anchor when the pointer was taken
    /// since the pad last looked.
    mutating func catchUp(anchor: CGPoint?, takeovers: Int) {
        guard takeovers != takeoversSeen else { return }
        adopt(anchor: anchor, takeovers: takeovers)
    }

    /// A finger's travel, as fractions of the frame; the cursor stops at the edges.
    mutating func move(dx: Double, dy: Double) {
        cursor = Self.clamped(CGPoint(x: Double(cursor.x) + dx, y: Double(cursor.y) + dy))
    }

    static func clamped(_ p: CGPoint) -> CGPoint {
        CGPoint(x: min(max(p.x, 0), 1), y: min(max(p.y, 0), 1))
    }
}
