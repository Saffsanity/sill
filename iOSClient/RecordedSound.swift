import Foundation

/// The movie's sound track (#284, docs/recording-plan.md, rule 7): which of the Mac's sound packets are decoded,
/// which of their frames are written where, and the silence between, so the track has no gap and no overlap and
/// keeps the picture's sync. Its own decoder (one per epoch) on the recorder's queue: this device's playout, its
/// engine, Mute, Picture in Picture and a call change nothing (decision 5).
///
/// - Ignored: packets of an epoch without a format, and an (epoch, seq) already seen.
/// - A segment start (the Mac's encoder started clean): the decoder reset, the format's priming frames dropped,
///   5 ms faded in, placed by its stamp (its first kept frame at T + priming ÷ 48,000).
/// - The next seq of the epoch: right after the last, sample-exact; placed by stamp with a fade instead when
///   its stamp puts it more than `driftLimit` away.
/// - Any other packet (a skipped seq, the first one this recording sees, another epoch without the segment
///   flag): the decoder reset, the packet decoded and dropped whole (the first packet after a join decodes to
///   noise: AudioDecoder), and the next placed by stamp, faded in.
/// - Silence fills every gap between the track's end and the next placement; a packet that would overlap the
///   track's end loses its overlapping frames, faded in where it now starts, or is dropped if all of them do.
/// - The newest packet's last 5 ms stay in hand (`held`) until the next placement says whether it follows;
///   anything else (a placement by stamp, silence, the stop) fades them out first.
/// - The track follows the picture: at each picture written at T, silence up to T − `soundLag` if nothing has
///   come that far (Send Audio off mid-recording, a Mac sending no sound), so neither track waits on the other.
/// - At the stop, silence to the stop's time.
///
/// Positions are frames at 48 kHz from the part's 0:00 (movie time × 48,000); the track starts at 0, so
/// anything before it is trimmed. Pure: Foundation only, checked by Tests/checks/recording.
struct RecordedSound {
    static let rate = 48_000
    static let driftLimit = 0.020
    static let soundLag = 0.5
    /// Fades in and out: 5 ms.
    static let fadeFrames = 240
    /// (epoch, seq) pairs remembered for duplicates.
    static let dedupeCount = 256

    /// An epoch's format, as its kind 43 type 1 says.
    struct Format: Equatable {
        var framesPerPacket: Int
        var primingFrames: Int
    }

    /// One write onto the track, in order.
    enum Write: Equatable {
        /// This many frames of silence.
        case silence(Int)
        /// The held tail of the last packet written, faded out or not.
        case tail(fadeOut: Bool)
        /// Frames of the message's packet `index` as decoded: from `from`, `count` of them, faded in when
        /// `fadeIn`; their last `hold` stay in hand as the new tail.
        case packet(index: Int, from: Int, count: Int, fadeIn: Bool, hold: Int)
    }

    /// What one codec packet needs from the decoder.
    enum Decode: Equatable {
        /// Not decoded: no format for its epoch, or a duplicate.
        case skip
        /// Decoded, after resetting the decoder when `reset`.
        case decode(reset: Bool)
    }

    private(set) var formats: [Int: Format] = [:]
    /// The track's end in frames, the held tail included.
    private(set) var end: Int64 = 0
    /// Frames at the end not yet committed: the last packet's tail.
    private(set) var held = 0
    /// The last packet placed: its epoch, seq, and where its frames end (or would have).
    private(set) var last: (epoch: Int, seq: UInt32, end: Int64)?
    /// The last packet decoded per epoch: a seq that does not follow it is a gap. The packet after a join then
    /// never follows the last one placed (the join's own seq was not placed), so it goes by its stamp.
    private var decoded: [Int: UInt32] = [:]
    /// The last `dedupeCount` (epoch, seq) pairs, and their order for forgetting the oldest.
    private var seen = Set<Int64>()
    private var seenOrder: [Int64] = []
    private var seenNext = 0
    /// Frames of silence written, for the checks.
    private(set) var silenceFrames: Int64 = 0

    init() {}

    /// A format for `epoch` (kind 43 type 1). Packets of an epoch without one are ignored.
    mutating func format(epoch: Int, _ format: Format) {
        formats[epoch] = format
    }

    /// One codec packet of a message: packet `index` of `count` with seq `seq`, the message's segment flag
    /// counting only for its first, `time` the movie time of its first decoded frame (nil before the anchor:
    /// decoded for the decoder's state, never placed). Returns what to decode and what to write.
    mutating func packet(epoch: Int, seq: UInt32, index: Int, segmentStart: Bool, time: Double?) -> (Decode, [Write]) {
        guard let format = formats[epoch] else { return (.skip, []) }
        let key = Int64(epoch & 0xFFFF) << 32 | Int64(seq)
        guard !seen.contains(key) else { return (.skip, []) }
        seen.insert(key)
        if seenOrder.count < Self.dedupeCount {
            seenOrder.append(key)
        } else {
            seen.remove(seenOrder[seenNext])
            seenOrder[seenNext] = key
            seenNext = (seenNext + 1) % Self.dedupeCount
        }

        let fpp = format.framesPerPacket
        let follows = decoded[epoch].map { seq == $0 &+ 1 } ?? false
        decoded[epoch] = seq
        let start = segmentStart && index == 0
        guard start || follows else {
            // A join: decoded to noise, dropped whole; the next is placed by stamp.
            return (.decode(reset: true), [])
        }
        guard let time else { return (.decode(reset: start), []) }

        var from = 0, count = fpp
        var position: Int64
        var byStamp: Bool
        if start {
            from = min(max(format.primingFrames, 0), fpp)
            count = fpp - from
            position = RecordingClock.frames(time) + Int64(from)
            byStamp = true
        } else {
            position = RecordingClock.frames(time)
            if let last, last.epoch == epoch, last.seq &+ 1 == seq,
               abs(Double(position - last.end)) <= Self.driftLimit * Double(Self.rate) {
                position = last.end
                byStamp = false
            } else {
                byStamp = true
            }
        }
        let natural = position + Int64(count)
        last = (epoch, seq, natural)
        var writes: [Write] = []
        if held > 0 {
            writes.append(.tail(fadeOut: byStamp || position != end))
            held = 0
        }
        var fadeIn = byStamp
        if position > end {
            writes.append(.silence(Int(position - end)))
            silenceFrames += position - end
            end = position
        } else if position < end {
            let overlap = Int(end - position)
            guard overlap < count else { return (.decode(reset: start), writes) }
            from += overlap
            count -= overlap
            fadeIn = true
        }
        let hold = min(Self.fadeFrames, count)
        writes.append(.packet(index: index, from: from, count: count, fadeIn: fadeIn, hold: hold))
        end += Int64(count)
        held = hold
        return (.decode(reset: start), writes)
    }

    /// A picture was written at movie time `time`: silence up to `time − soundLag` if the sound has not come
    /// that far.
    mutating func follow(picture time: Double) -> [Write] {
        fill(to: RecordingClock.frames(time - Self.soundLag))
    }

    /// The stop at movie time `time`: the tail faded out, silence to it.
    mutating func stop(at time: Double) -> [Write] {
        var writes = fill(to: RecordingClock.frames(time))
        if held > 0 {
            writes.append(.tail(fadeOut: true))
            held = 0
        }
        return writes
    }

    private mutating func fill(to target: Int64) -> [Write] {
        guard target > end else { return [] }
        var writes: [Write] = []
        if held > 0 {
            writes.append(.tail(fadeOut: true))
            held = 0
        }
        writes.append(.silence(Int(target - end)))
        silenceFrames += target - end
        end = target
        return writes
    }
}
