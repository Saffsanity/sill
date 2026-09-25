import Foundation
import CoreMedia

/// HEVCEncoder's frames on their way into VideoToolbox, kept apart from VideoToolbox itself: the
/// frames inside it (at most `limit`), the one-slot mailbox behind them (a newer frame replaces a
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
    /// Frames VideoToolbox may hold at once.
    let limit: Int
    /// The frames let in and not yet back, by id, each with the time it went in: when it was let
    /// in, and again when `submit` hands it to VideoToolbox. A dead session never clears this.
    private(set) var inside: [Int: CFTimeInterval] = [:]
    /// The newest frame that found `limit` frames inside.
    private(set) var waiting: Frame?
    /// The watchdog gave up on this session, or its owner did: nothing goes in or out any more.
    private(set) var dead = false
    /// The last timestamp handed to VideoToolbox. Timestamps never go backwards (frame reordering
    /// is off): see `handOver`.
    private(set) var lastPTS: CMTime = .invalid
    /// The next frame to go in becomes a keyframe.
    var keyframeRequested = false
    /// The last id given out: 1 for the first frame let in, 2 for the next, and so on.
    private var lastID = 0

    /// Two frames inside on the hardware encoder: a second frame goes in while the first is still
    /// inside, so the time a frame spends around the encoder chip can overlap the next one's (see
    /// HEVCEncoder). One on the software encoder: it is bound by the CPU, and a second frame there
    /// would only wait a whole software encode inside.
    init(software: Bool) {
        limit = software ? 1 : 2
    }

    enum Admission: Equatable {
        /// Let in as frame `id`: hand it to VideoToolbox (`handOver`, then the encode call).
        case goesIn(id: Int)
        /// `limit` frames are inside: it waits in the mailbox. `replaced`: it pushed out an older
        /// waiting frame, which is dropped (the newer frame wins).
        case waits(replaced: Bool)
        /// The session is dead: dropped.
        case dropped
    }

    /// A new frame, from the capture or a keyframe's re-encode.
    mutating func admit(_ frame: Frame, now: CFTimeInterval) -> Admission {
        guard !dead else { return .dropped }
        if inside.count < limit { return .goesIn(id: letIn(now: now)) }
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
        if inside[id] != nil { inside[id] = now }
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
    mutating func returned(_ id: Int, now: CFTimeInterval) -> Return {
        guard !dead else { return .late }
        guard inside.removeValue(forKey: id) != nil else { return .duplicate }
        guard let frame = waiting else { return .freed }
        waiting = nil
        return .next(frame, id: letIn(now: now))
    }

    /// When the frame inside longest went in.
    var oldest: CFTimeInterval? { inside.values.min() }

    /// The watchdog: true, once, when the frame inside longest went in more than `after` seconds
    /// ago. The session is dead from then on.
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
        /// The one inside longest went in at `since`.
        case stalled(since: CFTimeInterval)
    }

    /// What the session's teardown does (HEVCEncoder's deinit).
    var teardown: Teardown {
        guard let oldest else { return .idle }
        return dead ? .stalled(since: oldest) : .drain
    }
}
