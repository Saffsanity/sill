import Foundation
import CoreMedia

/// HEVCEncoder's frames on their way into VideoToolbox, kept apart from VideoToolbox itself: the
/// frames inside it (at most `places`), the one-slot mailbox behind them (a newer frame replaces a
/// waiting one), the watchdog's clock, and what the next frame to go in carries (a timestamp
/// later than the last one's, a requested keyframe). No locking and no dispatching: HEVCEncoder
/// keeps it under its lock, makes the VideoToolbox calls and queues the hand-overs on its serial
/// `encodeQueue`.
///
/// Foundation and CoreMedia only, so it is checked on its own with swiftc against a stand-in for
/// VideoToolbox that returns frames after programmable delays, in any order, in virtual time
/// (`Scripts/encoder-check/run.sh mailbox mutants`; its scenarios and mutants: CLAUDE.md, "The 33
/// fps plateau").
struct EncoderMailbox<Frame> {
    /// Frames VideoToolbox may hold at once: one (HEVCEncoder), two on the hardware encoder under
    /// the plateau experiment's switch (`SILL_TEST_ENCODER_IN_FLIGHT=2`).
    let limit: Int
    /// The frames let in and not yet back, by id, each with the time its watchdog clock started:
    /// when it was let in, again when `submit` hands it to VideoToolbox, and again when a frame
    /// handed over before it comes back (`returned`). A dead session never clears this.
    private(set) var inside: [Int: CFTimeInterval] = [:]
    /// The frames inside that `submit` has handed to VideoToolbox; the others are on `encodeQueue`.
    private(set) var handed: Set<Int> = []
    /// The newest frame that found every place taken.
    private(set) var waiting: Frame?
    /// The watchdog gave up on this session, or its owner did: nothing goes in or out any more.
    private(set) var dead = false
    /// VideoToolbox has let go of a frame of this session (an output, or a refusal).
    private(set) var anyReturned = false
    /// The last timestamp handed to VideoToolbox. Timestamps never go backwards (frame reordering
    /// is off): see `handOver`.
    private(set) var lastPTS: CMTime = .invalid
    /// The next frame to go in becomes a keyframe.
    var keyframeRequested = false
    /// The last id given out: 1 for the first frame let in, 2 for the next, and so on.
    private var lastID = 0

    /// `limit` frames inside at once, one at least. With one, the next goes in when the last came
    /// back; with more, a frame goes in while others are still inside (HEVCEncoder says when).
    init(limit: Int) {
        self.limit = max(1, limit)
    }

    /// Frames that may be inside now: one until the session has let go of a frame, `limit` from
    /// then on. A session stuck on its first frame, as every session was through the 2026-09-22
    /// wedge, then holds that one surface for good and not `limit` of them: a stuck encoder never
    /// lets go of what it holds.
    var places: Int { anyReturned ? limit : 1 }

    enum Admission: Equatable {
        /// Let in as frame `id`: hand it to VideoToolbox (`handOver`, then the encode call).
        case goesIn(id: Int)
        /// Every place is taken: it waits in the mailbox. `replaced`: it pushed out an older
        /// waiting frame, which is dropped (the newer frame wins).
        case waits(replaced: Bool)
        /// The session is dead: dropped.
        case dropped
    }

    /// A new frame, from the capture or a keyframe's re-encode.
    mutating func admit(_ frame: Frame, now: CFTimeInterval) -> Admission {
        guard !dead else { return .dropped }
        if inside.count < places { return .goesIn(id: letIn(now: now)) }
        let replaced = waiting != nil
        waiting = frame
        return .waits(replaced: replaced)
    }

    private mutating func letIn(now: CFTimeInterval) -> Int {
        lastID += 1
        inside[lastID] = now
        return lastID
    }

    struct HandOver: Equatable {
        let pts: CMTime
        let keyframe: Bool
        /// The frame's own timestamp was not later than the last one handed over.
        let ptsFixed: Bool
    }

    /// `submit`, on the serial `encodeQueue`, is about to hand frame `id` to VideoToolbox: its
    /// clock starts again, its timestamp is made later than the last one handed over (a keyframe's
    /// re-encode is stamped just after the last frame that went in, and a frame let in before it
    /// may go in first), and a requested keyframe goes with it. Nil when the session died after
    /// the frame was let in.
    mutating func handOver(_ id: Int, pts requested: CMTime, now: CFTimeInterval) -> HandOver? {
        guard !dead else { return nil }
        if inside[id] != nil { inside[id] = now; handed.insert(id) }
        var pts = requested
        var fixed = false
        if lastPTS.isValid, CMTimeCompare(pts, lastPTS) <= 0 {
            pts = CMTimeAdd(lastPTS, CMTime(value: 1, timescale: 1000))
            fixed = true
        }
        lastPTS = pts
        let keyframe = keyframeRequested
        keyframeRequested = false
        return HandOver(pts: pts, keyframe: keyframe, ptsFixed: fixed)
    }

    enum Return {
        /// The session is dead: its late output must never be forwarded (its devices have moved on
        /// to a new session, with a new size and new parameter sets).
        case late
        /// A second notice for a frame already back (an error status and a handler call for the
        /// same frame): nothing is freed twice.
        case duplicate
        /// Its place is free.
        case freed
        /// The waiting frame takes its place as frame `id`: hand it to VideoToolbox.
        case next(Frame, id: Int)
    }

    /// VideoToolbox let go of frame `id`: its output came, or the encode call refused it. Frames
    /// may come back in any order.
    ///
    /// A frame handed over after this one may have waited behind it inside VideoToolbox (one engine
    /// works on one frame at a time), so its clock starts again now: the watchdog then gives each
    /// frame `hangAfter` of its own, as with one inside. Without this, two inside on a serial
    /// engine fired it at ~0.77 s a frame instead of 1.5 s. A frame handed over before this one
    /// keeps its clock, so one stuck ahead of the others still fires the watchdog `hangAfter`
    /// after it went in, whatever order the rest come back in; so does one still on `encodeQueue`
    /// (an encode call that never returns holds it there).
    mutating func returned(_ id: Int, now: CFTimeInterval) -> Return {
        guard !dead else { return .late }
        guard inside.removeValue(forKey: id) != nil else { return .duplicate }
        handed.remove(id)
        for other in handed where other > id { inside[other] = now }
        anyReturned = true
        guard let frame = waiting else { return .freed }
        waiting = nil
        return .next(frame, id: letIn(now: now))
    }

    /// When the oldest watchdog clock of the frames inside started.
    var oldest: CFTimeInterval? { inside.values.min() }

    /// The watchdog: true, once, when a frame's clock has run more than `after` seconds without it
    /// coming back. The session is dead from then on.
    mutating func giveUpIfHung(now: CFTimeInterval, after: CFTimeInterval) -> Bool {
        guard !dead, let oldest, now - oldest > after else { return false }
        giveUp()
        return true
    }

    /// Nothing more goes in, and the waiting frame is dropped. True when a frame is still inside.
    @discardableResult
    mutating func giveUp() -> Bool {
        dead = true; waiting = nil
        return !inside.isEmpty
    }

    enum Teardown: Equatable {
        /// Nothing inside: invalidate the session.
        case idle
        /// A live session with frames inside: let VideoToolbox finish them first.
        case drain
        /// Given up on with frames inside: never wait for them (a stuck encoder never lets go).
        /// The oldest clock among them started at `since`.
        case stalled(since: CFTimeInterval)
    }

    /// What the session's teardown does (HEVCEncoder's deinit).
    var teardown: Teardown {
        guard let oldest else { return .idle }
        return dead ? .stalled(since: oldest) : .drain
    }
}
