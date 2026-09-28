import Foundation

/// The device's playout of the Mac's sound (docs/audio-plan.md §7.2): which packets are decoded, which
/// are played, and where each goes on the player's timeline, so that the sound is never ahead of the
/// picture and trails it by as little as its own path allows. Pure (Foundation only): the
/// `audio-playout` check runs it on a simulated clock, the harness's device (Scripts/audiocheck.swift)
/// on real arrivals, and AudioOutput on `sill.audio`, doing what it says.
///
/// Clocks. Device times are seconds of the monotonic clock (CACurrentMediaTime, the clock whose ticks
/// AVAudioTime's hostTime counts). Stamps are the Mac's wall clock (seconds since 1970, the header's).
/// The offset between the two is never needed: every comparison goes through the floor. Samples are
/// the player node's timeline at 48 kHz; `played` says which device time a sample of it goes out at
/// (the render's time), and it is heard the output latency later.
///
/// The rules, the plan's numbers:
/// 1. The floor is the smallest (arrival − stamp) of the packets of the last 10 s, kept in 1 s
///    buckets, a packet's arrival being when the playout takes it (`packet`). With no packet for 10 s
///    it keeps its last value.
/// 2. The need is what a packet needs between arriving and being heard: the jitter cover (the largest
///    arrival − stamp − floor of the last 10 s; 40 ms at home and 150 ms away until the session's
///    first 2 s of packets have come, which the window leaves out; home 20–150 ms, away 60–600 ms),
///    one packet (the hand's wait, rule 10), the IO buffer, the output latency and 2 ms. It rises the
///    moment a packet raises the cover, and falls as the window forgets.
/// 3. The picture's lag is the median (arrival − stamp − floor) of the frames of the last 2 s, plus 1.5
///    refreshes and 4 ms (decode and the next vsync). No frames: its last value. It can be negative;
///    it is never clamped.
/// 4. The delay is the need, or the picture's lag and one frame of the stream when that is more. A
///    packet stamped T is due at the ear at T + floor + delay, and goes onto the timeline the output
///    latency before that.
/// 5. The first packet of a segment, and the first after a gap, a late packet, a fade out or a jump,
///    is placed by time (its first frame played where its stamp says: a segment's first packet drops
///    its P frames of priming, so from T + P ÷ rate). The rest follow the packet before them.
/// 6. Late: a packet placed by time less than the IO buffer + 2 ms ahead of its render is decoded (for
///    the decoder's state) and not played. The cover has already taken it (rule 2), so the next one
///    is placed with a need that covers it.
/// 7. Duplicates: a packet whose (epoch, seq) is among the last 256 is dropped before it counts
///    anywhere. A move's hand-over resets nothing, and a format for the epoch playing with the same
///    cookie is ignored.
/// 8. Missing: a seq that skips resets the decoder, and the packet after the gap is a late join.
/// 9. A clean start only where the Mac's encoder started clean (a packet with the segment flag): the
///    decoder resets, the first P decoded frames are dropped and the next 5 ms fade in. Any other
///    first packet on a reset decoder (a join, the packet after a gap, the first after unmuting) is
///    decoded and dropped whole, and the next one fades in.
/// 10. The newest packet's last 5 ms (a fade's length, its tail) stays in hand until the next packet
///    arrives or the tail's deadline passes (its render time − the IO buffer − 2 ms), and goes out
///    then, faded if nothing follows; the rest of the packet goes to the player at once. Only a fade needs to wait
///    for the next packet, and holding only that leaves the next packet the rest of the need's one
///    packet (5 ms) to come in beyond the window's largest excess and still follow: held whole, a
///    packet exactly at the largest raced its predecessor's deadline, and a link sitting there (a
///    path a few ms slower, a step's first second) faded every packet out and in.
/// 11. Drift and small changes: a packet that follows another may gain a frame (the sound is ahead of
///    where it is due) or lose one (behind), one at most: about 2 ms a second.
/// 12. Jumps: an error over 40 ms, or a sound that would lead the picture, is closed at once: packets
///    dropped (behind), or the next one placed later (ahead), with fades.
/// 13. A step: a second of packets all more than max(50 ms, 2 × the rtt median) above the floor (an
///    unbroken run of them lasting a second), or a packet 20 ms under it, is the Mac's clock stepping
///    or the path changing. The floor starts again from that second's packets (or that packet), the
///    picture's window from its next frame, and the difference is closed by a jump.
/// The engine's idle (rule 14) is AudioOutput's.
struct AudioPlayout {
    // MARK: - Constants (§7.2's table)

    /// The player's timeline: 48 kHz, whatever the route (the mixer converts).
    static let rate = 48_000.0
    /// Rule 1: the floor's window, in whole seconds of 1 s buckets.
    static let floorSeconds = 10
    /// Rule 2: the jitter cover's first value, and how long the session's first packets are left out.
    static let coverStartHome = 0.040
    static let coverStartAway = 0.150
    static let coverGrace = 2.0
    static let coverHome: ClosedRange<Double> = 0.020...0.150
    static let coverAway: ClosedRange<Double> = 0.060...0.600
    /// Rule 2's last term, and rule 6's margin beyond the IO buffer.
    static let margin = 0.002
    /// Rule 3.
    static let pictureSeconds = 2.0
    static let pictureRefreshes = 1.5
    static let pictureExtra = 0.004
    /// Rule 11: a frame a packet while the error is past `correctFrom`, until it is back under `correctTo`.
    static let correctFrom = 0.001
    static let correctTo = 0.00025
    /// Rule 12.
    static let jumpOver = 0.040
    /// Rule 13: above the floor (with twice the rtt median, if more), under it; and how many packets
    /// make "a second of packets" (half a second's worth).
    static let stepAbove = 0.050
    static let stepBelow = 0.020
    static let stepPackets = 50
    /// Fades, in and out.
    static let fadeSeconds = 0.005
    /// Rule 7.
    static let dedupeCount = 256
    /// Packets kept while the engine starts, before its first render gives a timeline (a second's).
    static let waitingLimit = 100

    // MARK: - What it says

    /// Where one packet goes, as the model saw it when it placed it: for the console and the checks.
    struct Decision: Equatable {
        /// When the packet's first frame is due at the ear (stamp + floor + delay).
        let due: Double
        /// When it will be heard where it is placed (its render time + the output latency).
        let ear: Double
        /// When the picture of the same stamp shows (stamp + floor + the picture's lag); −∞ before
        /// any frame came.
        let picture: Double
        /// due − ear: positive, the sound is ahead of where it is due; negative, behind.
        var error: Double { due - ear }
    }

    /// A part of a packet to hand to the player now: its body at once, its last 5 ms (the tail) once
    /// the next packet says whether it follows (rule 10).
    struct Schedule: Equatable {
        enum Part: Equatable { case body, tail }
        let id: Int
        let part: Part
        /// Which of the packet's kept frames: from `offset`, `count` of them (before `change`).
        let offset: Int
        let count: Int
        /// Its first frame's place on the player's timeline, or nil: right after the buffer before it.
        let at: Double?
        /// Where it starts either way (planned).
        let start: Double
        /// Its frames once `change` is made.
        let frames: Int
        /// The body's: +1, a frame added; −1, one dropped (rule 11); 0.
        let change: Int
        /// Fade its first 5 ms in (the packet's first part), or its last 5 ms out (the tail).
        let fadeIn: Bool
        let fadeOut: Bool
        /// The stamp of the packet's first kept frame, its seq and epoch.
        let stamp: Double
        let seq: UInt32
        let epoch: Int
        let decision: Decision
        /// When its first frame goes out (renders), as the model reads the timeline now.
        let goesOut: Double
        var end: Double { start + Double(frames) }
    }

    /// What to do with the player and the kept packets.
    struct Output: Equatable {
        var schedules: [Schedule] = []
        /// Kept packets never to be played (late, dropped by a jump, left by a reset).
        var discards: [Int] = []

        mutating func add(_ other: Output) {
            schedules += other.schedules
            discards += other.discards
        }
    }

    /// What to do with one packet.
    struct Plan: Equatable {
        /// Decode it: every packet of the epoch playing that is not a duplicate and does not arrive
        /// while muted, including those not played (rule 6, rule 9).
        var decode = false
        /// Reset the decoder before it (AudioConverterReset).
        var resetFirst = false
        /// Frames dropped from its start once decoded: the codec's priming, or all of them.
        var dropFront = 0
        /// The id its kept frames go by until a Schedule or a discard names it; nil when none are kept.
        var id: Int?
        /// The hand, scheduled or discarded now, and this packet, discarded when late.
        var output = Output()
    }

    /// What a reset throws away. `session`: a new connection after the old one ended (everything).
    /// `playback`: the timeline (the engine restarted or stopped, unmuted, an interruption): the kept
    /// packets, the placement and the decoder's continuity, never the floor, the cover or the dedupe.
    /// `jump`: the next packet is placed by time (a route's new latency).
    enum Reset: Equatable { case session, playback, jump }

    /// One second of what happened, for the console, the HUD and the stats sent to the Mac.
    struct Second: Equatable {
        /// How far the sound trailed the picture, ms, over the packets placed (their ear − their
        /// picture); nil for a second with none.
        var behindMs: Int?
        var placed = 0
        var late = 0
        var duplicates = 0
        var framesAdded = 0
        var framesDropped = 0
        var jumps = 0
        /// Packets decoded and dropped whole (a join, a gap), and packets dropped by a jump.
        var joins = 0
        var jumpDrops = 0
        /// The numbers now, in seconds.
        var need = 0.0
        var cover = 0.0
        var delay = 0.0
        var lag: Double?
        var error: Double?
    }

    // MARK: - State

    // The format.
    private(set) var epoch: Int?
    private(set) var framesPerPacket = 480
    private(set) var primingFrames = 240
    private var cookie = Data()

    // Latencies and the link (AudioOutput's and the client's readings).
    /// The output latency: the session's, or the player's presentation latency if more.
    private(set) var outputLatency = 0.0
    private(set) var ioBuffer = 0.005
    private(set) var refresh = 1.0 / 60
    private(set) var streamFPS = 60.0
    private(set) var rttMedian: Double?
    private(set) var away = false
    private(set) var muted = false

    // Rules 1 and 2: the floor and the cover, by second of arrival.
    private struct Bucket {
        let second: Int
        var min: Double
        /// The cover's: the largest of its packets past the session's first 2 s, if any.
        var max: Double?
        var count: Int
    }
    private var buckets: [Bucket] = []
    private var floorKept: Double?
    private var sessionStart: Double?
    /// Rule 13, above: the packets since the first of an unbroken run above the floor by the step's
    /// threshold, their count, and the smallest and largest of them.
    private var above: (since: Double, count: Int, min: Double, max: Double)?

    // Rule 3: the frames of the last 2 s, in arrival order and sorted by (arrival − stamp).
    private var frameArrivals: [Double] = []
    private var frameRaws: [Double] = []
    private var frameHead = 0
    private var sortedRaws: [Double] = []
    /// The median (arrival − stamp) last seen, for a still window.
    private var lastPictureRaw: Double?

    // Rule 7.
    private var recentKeys: [Int64] = []
    private var recentSet = Set<Int64>()
    private var recentNext = 0

    // Rules 8 and 9: the decoder.
    private var expectedSeq: UInt32?
    private var primingLeft = 0
    private var fadeNext = true

    // Placement.
    private struct Admitted {
        let id: Int
        let epoch: Int
        let seq: UInt32
        /// The stamp of its first kept frame.
        let stamp: Double
        let frames: Int
        let fadeIn: Bool
        let segmentStart: Bool
    }
    private struct Planned {
        let packet: Admitted
        /// Where its first frame goes.
        let start: Double
        /// It follows the packet before it (scheduled with no time).
        let contiguous: Bool
        let change: Int
        let fadeIn: Bool
        let decision: Decision
        /// The last 5 ms, held (all of a packet that short); the body is the rest.
        var tailCount: Int { min(AudioPlayout.fadeFrames, packet.frames) }
        var bodyCount: Int { packet.frames - tailCount }
        var bodyFrames: Int { bodyCount + change }
        var tailStart: Double { start + Double(bodyFrames) }
        var end: Double { tailStart + Double(tailCount) }

        /// Whether `next` can follow it on the timeline: the next packet of its segment, decoded on
        /// the decoder's running state.
        func takes(_ next: Admitted) -> Bool {
            next.epoch == packet.epoch && next.seq == packet.seq &+ 1 && !next.segmentStart && !next.fadeIn
        }

        /// The body, which goes out as the packet is placed; nil for a packet no longer than a fade.
        func body(goesOut: Double) -> Schedule? {
            guard bodyCount > 0 else { return nil }
            return Schedule(id: packet.id, part: .body, offset: 0, count: bodyCount, at: contiguous ? nil : start,
                            start: start, frames: bodyFrames, change: change, fadeIn: fadeIn, fadeOut: false,
                            stamp: packet.stamp, seq: packet.seq, epoch: packet.epoch, decision: decision, goesOut: goesOut)
        }

        /// The tail, once the next packet says whether it follows; it carries the packet's placement when
        /// there is no body.
        func tail(fadeOut: Bool, goesOut: Double) -> Schedule {
            let first = bodyCount == 0
            return Schedule(id: packet.id, part: .tail, offset: bodyCount, count: tailCount,
                            at: first && !contiguous ? start : nil, start: tailStart, frames: tailCount, change: 0,
                            fadeIn: first && fadeIn, fadeOut: fadeOut, stamp: packet.stamp, seq: packet.seq,
                            epoch: packet.epoch, decision: decision, goesOut: goesOut)
        }
    }
    /// The player's timeline: a sample and the device time it goes out at. Nil until the engine's
    /// first render after a start.
    private var mapping: (sample: Double, time: Double)?
    /// The newest packet, placed, its tail not yet handed over (rule 10).
    private var hand: Planned?
    /// Where the last tail handed over ends.
    private var chainEnd: Double?
    /// Packets kept before the timeline is known.
    private var waiting: [Admitted] = []
    private var nextID = 1
    /// Rule 12 or 13 owes a jump: the next packet is placed by time.
    private var jumpOwed = false
    /// Rule 11's direction: +1 adding frames, −1 dropping, 0.
    private var correcting = 0
    /// The error of the last packet that followed another.
    private(set) var lastError: Double?

    // The second being counted.
    private var second = Second()
    private var behind: [Double] = []
    /// A packet was placed this session: the stats say so from then on.
    private(set) var placedThisSession = false

    init() {}

    // MARK: - Inputs

    /// A format message (kind 29, type 1). True for a new epoch (a new decoder); false for the epoch
    /// playing with the same cookie, as a move's new connection sends it again (rule 7): ignored.
    mutating func format(epoch: Int, framesPerPacket: Int, primingFrames: Int, cookie: Data) -> Bool {
        if self.epoch == epoch, self.cookie == cookie, self.framesPerPacket == framesPerPacket,
           self.primingFrames == primingFrames { return false }
        self.epoch = epoch
        self.framesPerPacket = max(1, framesPerPacket)
        self.primingFrames = max(0, primingFrames)
        self.cookie = cookie
        // The new epoch starts clean (its first packet carries the flag); a packet in hand of the old
        // one fades out when that packet comes, since it does not follow it.
        expectedSeq = nil
        primingLeft = 0
        fadeNext = true
        return true
    }

    /// A video frame (kind 1), stamped at arrival: for the picture's lag (rule 3).
    mutating func frame(stamp: Double, arrival: Double) {
        let raw = arrival - stamp
        guard raw.isFinite else { return }
        frameArrivals.append(arrival)
        frameRaws.append(raw)
        let i = Self.insertionIndex(sortedRaws, raw)
        sortedRaws.insert(raw, at: i)
        expireFrames(now: arrival)
    }

    /// The output's latencies as read back once it runs, the panel's refresh, and the stream's rate.
    mutating func latency(output: Double, io: Double, refresh: Double, streamFPS: Double) {
        outputLatency = max(0, output.isFinite ? output : 0)
        ioBuffer = max(0, io.isFinite ? io : 0)
        self.refresh = max(0, refresh.isFinite ? refresh : 0)
        self.streamFPS = streamFPS > 0 && streamFPS.isFinite ? streamFPS : 60
    }

    /// The pings' median round trip of the last second, for the step test (rule 13).
    mutating func rtt(median: Double?) { rttMedian = median.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } }

    /// Whether this session is away from home: the cover's start and bounds (rule 2). A move home
    /// changes them at the hand-over and nothing else.
    mutating func away(_ away: Bool) { self.away = away }

    /// Muted (or in the background): each packet still counts for the floor and the cover, and none
    /// is decoded. Unmuting is a `.playback` reset, which the caller makes.
    mutating func mute(_ muted: Bool) { self.muted = muted }

    /// The player's timeline, read at each schedule: `sample` goes out at device time `time`. The
    /// first reading after a start places what waited for it.
    mutating func played(sample: Double, at time: Double, now: Double) -> Output {
        guard sample.isFinite, time.isFinite else { return Output() }
        let first = mapping == nil
        mapping = (sample, time)
        guard first, !waiting.isEmpty else { return Output() }
        var out = Output()
        let list = waiting
        waiting = []
        for a in list { out.add(place(a, now: now)) }
        return out
    }

    /// One packet of kind 29's type 2, with its own stamp (the message's + its place × F ÷ rate), taken
    /// `now`. Its (arrival − stamp) is taken now too, not when the network queue read it: what the
    /// packet in hand waits for is the next packet reaching the playout (rule 10), so the hop between
    /// the two queues is part of what the cover must cover.
    mutating func packet(epoch: Int, seq: UInt32, stamp: Double, segmentStart: Bool, now: Double) -> Plan {
        let arrival = now
        guard let playing = self.epoch, epoch == playing, stamp.isFinite, arrival.isFinite else { return Plan() }
        // Rule 7: before anything counts.
        let key = Int64(epoch & 0xFFFF) << 32 | Int64(seq)
        if recentSet.contains(key) {
            second.duplicates += 1
            return Plan()
        }
        remember(key)
        record(raw: arrival - stamp, arrival: arrival)
        if muted {
            // Nothing decoded: the decoder's next packet starts afresh.
            expectedSeq = nil
            return Plan()
        }
        var plan = Plan(decode: true)
        let continuous = !segmentStart && expectedSeq == seq
        expectedSeq = seq &+ 1
        if segmentStart {
            // Rule 9: a clean start.
            plan.resetFirst = true
            primingLeft = primingFrames
            fadeNext = true
        } else if !continuous {
            // Rules 8 and 9: a join, the packet after a gap, the first on a reset decoder: decoded for
            // the decoder's state and dropped whole; the next fades in. What is in hand fades out.
            plan.resetFirst = true
            plan.dropFront = framesPerPacket
            primingLeft = 0
            fadeNext = true
            second.joins += 1
            plan.output = handOver(fadeOut: true)
            return plan
        }
        let drop = min(primingLeft, framesPerPacket)
        primingLeft -= drop
        plan.dropFront = drop
        let kept = framesPerPacket - drop
        guard kept > 0 else { return plan }
        let a = Admitted(id: nextID, epoch: epoch, seq: seq, stamp: stamp + Double(drop) / Self.rate, frames: kept,
                         fadeIn: fadeNext, segmentStart: segmentStart)
        nextID += 1
        fadeNext = false
        plan.id = a.id
        guard mapping != nil else {
            waiting.append(a)
            if waiting.count > Self.waitingLimit {
                plan.output.discards.append(waiting.removeFirst().id)
                // What follows the first kept one no longer follows anything: placed by time.
                if let first = waiting.first {
                    waiting[0] = Admitted(id: first.id, epoch: first.epoch, seq: first.seq, stamp: first.stamp,
                                          frames: first.frames, fadeIn: true, segmentStart: first.segmentStart)
                }
            }
            return plan
        }
        plan.output.add(place(a, now: now))
        return plan
    }

    /// The decoder could not decode a packet the plan kept: the caller plays silence in its place,
    /// and the decoder starts afresh at the next packet (rule 9).
    mutating func decodeFailed() {
        expectedSeq = nil
        primingLeft = 0
        fadeNext = true
    }

    /// Time passing: the tail in hand goes out, faded, once its deadline has passed (rule 10).
    mutating func tick(now: Double) -> Output {
        guard hand != nil, let d = deadline, now >= d else { return Output() }
        return handOver(fadeOut: true)
    }

    /// When `tick` next has something to do, or nil.
    var deadline: Double? {
        guard let h = hand else { return nil }
        return time(ofSample: h.tailStart) - ioBuffer - Self.margin
    }

    mutating func reset(_ kind: Reset) -> Output {
        switch kind {
        case .jump:
            owe()
            return Output()
        case .playback, .session:
            var out = Output()
            if let h = hand { out.discards.append(h.packet.id) }
            out.discards += waiting.map(\.id)
            hand = nil
            waiting = []
            chainEnd = nil
            mapping = nil
            jumpOwed = false
            correcting = 0
            expectedSeq = nil
            primingLeft = 0
            fadeNext = true
            if kind == .session {
                epoch = nil
                cookie = Data()
                buckets = []
                floorKept = nil
                sessionStart = nil
                above = nil
                frameArrivals = []
                frameRaws = []
                frameHead = 0
                sortedRaws = []
                lastPictureRaw = nil
                recentKeys = []
                recentSet = []
                recentNext = 0
                lastError = nil
                placedThisSession = false
                second = Second()
                behind = []
            }
            return out
        }
    }

    /// The second that ends now, and the next one starts.
    mutating func takeSecond(now: Double) -> Second {
        expireFrames(now: now)
        var s = second
        s.behindMs = behind.isEmpty ? nil : Int((Self.median(behind.sorted()) * 1000).rounded())
        s.need = need(now: now)
        s.cover = cover(now: now)
        let lag = pictureLag(now: now)
        s.lag = lag
        s.delay = delay(now: now, lag: lag)
        s.error = lastError
        second = Second()
        behind = []
        return s
    }

    // MARK: - The numbers

    /// Rule 1.
    var floor: Double? { buckets.isEmpty ? floorKept : buckets.map(\.min).min() }

    /// Rule 2's cover.
    func cover(now: Double) -> Double {
        let start = away ? Self.coverStartAway : Self.coverStartHome
        guard let begun = sessionStart, now - begun >= Self.coverGrace, let floor,
              let top = buckets.compactMap(\.max).max() else { return start }
        let bounds = away ? Self.coverAway : Self.coverHome
        return min(max(top - floor, bounds.lowerBound), bounds.upperBound)
    }

    /// Rule 2.
    func need(now: Double) -> Double {
        cover(now: now) + Double(framesPerPacket) / Self.rate + ioBuffer + outputLatency + Self.margin
    }

    /// Rule 3: nil before any frame came (or before the floor).
    func pictureLag(now: Double) -> Double? {
        guard let floor else { return nil }
        let raw: Double?
        if !sortedRaws.isEmpty, liveFramesAfterExpiry(now: now) > 0 {
            raw = Self.median(sortedRaws)
        } else {
            raw = lastPictureRaw
        }
        return raw.map { $0 - floor + Self.pictureRefreshes * refresh + Self.pictureExtra }
    }

    /// Rule 4.
    func delay(now: Double, lag: Double?) -> Double {
        let guardDelay = lag.map { $0 + 1 / streamFPS } ?? -.infinity
        return max(need(now: now), guardDelay)
    }

    /// A packet in hand (for the checks and the console).
    var holding: Bool { hand != nil }

    // MARK: - Placement

    private mutating func place(_ a: Admitted, now: Double) -> Output {
        var out = Output()
        guard let floor else { return out }
        expireFrames(now: now)
        let lag = pictureLag(now: now)
        let delay = self.delay(now: now, lag: lag)
        let due = a.stamp + floor + delay
        let picture = lag.map { a.stamp + floor + $0 } ?? -.infinity
        var placed: Planned?
        if let h = hand, !jumpOwed, h.takes(a) {
            // Rule 5: it follows the packet in hand.
            let start = h.end
            let ear = time(ofSample: start) + outputLatency
            let decision = Decision(due: due, ear: ear, picture: picture)
            lastError = decision.error
            if ear >= picture, abs(decision.error) <= Self.jumpOver {
                let change = a.frames - min(Self.fadeFrames, a.frames) >= 4 ? correction(decision.error) : 0
                placed = Planned(packet: a, start: start, contiguous: true, change: change, fadeIn: false, decision: decision)
            } else {
                // Rule 12: too far off, or ahead of the picture: closed at once.
                owe()
            }
        }
        if placed == nil {
            // Rule 5: by time.
            var start = sample(atTime: due - outputLatency)
            if let chain = hand?.end ?? chainEnd, start < chain {
                if jumpOwed, chain - start > Double(framesPerPacket) / 2 {
                    // Behind: dropped, until a packet is due within half a packet of what is already
                    // scheduled (dropping one more would leave it further off the other way).
                    second.jumpDrops += 1
                    out.add(handOver(fadeOut: true))
                    out.discards.append(a.id)
                    return out
                }
                // A new segment a hair early, or a jump's last few ms: right after what is scheduled,
                // faded in; rule 11 closes what is left.
                start = chain
            }
            if time(ofSample: start) - now < ioBuffer + Self.margin {
                // Rule 6.
                second.late += 1
                out.add(handOver(fadeOut: true))
                out.discards.append(a.id)
                return out
            }
            jumpOwed = false
            correcting = 0
            let ear = time(ofSample: start) + outputLatency
            placed = Planned(packet: a, start: start, contiguous: false, change: 0, fadeIn: true,
                             decision: Decision(due: due, ear: ear, picture: picture))
        }
        guard let p = placed else { return out }
        if let h = hand { out.schedules.append(h.tail(fadeOut: !p.contiguous, goesOut: time(ofSample: h.tailStart))) }
        if let body = p.body(goesOut: time(ofSample: p.start)) { out.schedules.append(body) }
        hand = p
        chainEnd = nil
        second.placed += 1
        placedThisSession = true
        if p.change > 0 { second.framesAdded += 1 } else if p.change < 0 { second.framesDropped += 1 }
        if p.decision.picture > -.infinity { behind.append(p.decision.ear - p.decision.picture) }
        return out
    }

    /// The tail in hand goes to the player now.
    private mutating func handOver(fadeOut: Bool) -> Output {
        guard let h = hand else { return Output() }
        hand = nil
        chainEnd = h.end
        return Output(schedules: [h.tail(fadeOut: fadeOut, goesOut: time(ofSample: h.tailStart))])
    }

    /// A jump is owed (rules 12 and 13), counted once, and only where something plays.
    private mutating func owe() {
        guard !jumpOwed else { return }
        jumpOwed = true
        if hand != nil || chainEnd != nil { second.jumps += 1 }
    }

    /// Rule 11: the direction for this packet, with a band so a steady stream does not flutter.
    private mutating func correction(_ error: Double) -> Int {
        if correcting != 0, abs(error) < Self.correctTo {
            correcting = 0
        } else if error > Self.correctFrom {
            correcting = 1
        } else if error < -Self.correctFrom {
            correcting = -1
        } else if correcting != 0, (error > 0) != (correcting > 0) {
            correcting = 0
        }
        return correcting
    }

    private func time(ofSample sample: Double) -> Double {
        guard let m = mapping else { return -.infinity }
        return m.time + (sample - m.sample) / Self.rate
    }

    private func sample(atTime time: Double) -> Double {
        guard let m = mapping else { return 0 }
        return (m.sample + (time - m.time) * Self.rate).rounded()
    }

    // MARK: - The windows

    /// Rules 1, 2 and 13: one packet's (arrival − stamp).
    private mutating func record(raw: Double, arrival: Double) {
        if sessionStart == nil { sessionStart = arrival }
        let now = Int(arrival.rounded(.down))
        buckets.removeAll { $0.second <= now - Self.floorSeconds }
        if let floor {
            // Rule 13, below: a packet 20 ms under the floor.
            if raw < floor - Self.stepBelow {
                restart(from: Bucket(second: now, min: raw, max: coverValue(raw, arrival), count: 1), was: floor)
                return
            }
            // Rule 13, above: a second of packets, every one of them above the floor by the threshold.
            if raw - floor > max(Self.stepAbove, 2 * (rttMedian ?? 0)) {
                var run = above ?? (since: arrival, count: 0, min: raw, max: raw)
                run.count += 1
                run.min = Swift.min(run.min, raw)
                run.max = Swift.max(run.max, raw)
                above = run
                if arrival - run.since >= 1, run.count >= Self.stepPackets {
                    restart(from: Bucket(second: now, min: run.min, max: coverValue(run.max, arrival), count: run.count), was: floor)
                    return
                }
            } else {
                above = nil
            }
        }
        if buckets.last?.second != now { buckets.append(Bucket(second: now, min: raw, max: nil, count: 0)) }
        let i = buckets.count - 1
        buckets[i].min = min(buckets[i].min, raw)
        buckets[i].count += 1
        if let m = coverValue(raw, arrival) { buckets[i].max = max(buckets[i].max ?? m, m) }
        floorKept = floor
    }

    /// A packet's value for the cover's window: none in the session's first 2 s.
    private func coverValue(_ raw: Double, _ arrival: Double) -> Double? {
        guard let begun = sessionStart, arrival - begun >= Self.coverGrace else { return nil }
        return raw
    }

    /// Rule 13: the windows start again from `bucket`, and the difference is closed by a jump. The
    /// picture's window starts again too: a clock step or a path change moves the frames as it moves
    /// the packets, and a window that held frames from both sides of it would put the guard up to the
    /// step away from where it belongs (a second, for a clock stepped back a second). Until the next
    /// frame there is no guard.
    private mutating func restart(from bucket: Bucket, was old: Double) {
        buckets = [bucket]
        floorKept = bucket.min
        above = nil
        frameArrivals = []
        frameRaws = []
        frameHead = 0
        sortedRaws = []
        lastPictureRaw = nil
        owe()
    }

    private mutating func remember(_ key: Int64) {
        if recentKeys.count < Self.dedupeCount {
            recentKeys.append(key)
        } else {
            recentSet.remove(recentKeys[recentNext])
            recentKeys[recentNext] = key
            recentNext = (recentNext + 1) % Self.dedupeCount
        }
        recentSet.insert(key)
    }

    private mutating func expireFrames(now: Double) {
        let from = now - Self.pictureSeconds
        while frameHead < frameArrivals.count, frameArrivals[frameHead] < from {
            let raw = frameRaws[frameHead]
            if sortedRaws.count == 1 { lastPictureRaw = sortedRaws[0] }
            let i = Self.insertionIndex(sortedRaws, raw)
            if i < sortedRaws.count, sortedRaws[i] == raw { sortedRaws.remove(at: i) }
            else if i > 0, sortedRaws[i - 1] == raw { sortedRaws.remove(at: i - 1) }
            frameHead += 1
        }
        if frameHead > 512 {
            frameArrivals.removeFirst(frameHead)
            frameRaws.removeFirst(frameHead)
            frameHead = 0
        }
        if !sortedRaws.isEmpty { lastPictureRaw = Self.median(sortedRaws) }
    }

    /// The frames of the window that are still in it at `now` (without changing it).
    private func liveFramesAfterExpiry(now: Double) -> Int {
        let from = now - Self.pictureSeconds
        var n = 0
        var i = frameArrivals.count - 1
        while i >= frameHead, frameArrivals[i] >= from { n += 1; i -= 1 }
        return n
    }

    private static func insertionIndex(_ sorted: [Double], _ value: Double) -> Int {
        var lo = 0, hi = sorted.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if sorted[mid] < value { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    static func median(_ sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }
}

// MARK: - The samples

extension AudioPlayout {
    /// A fade's frames at the timeline's rate: 5 ms.
    static var fadeFrames: Int { Int((fadeSeconds * rate).rounded()) }

    /// A raised-cosine fade over the first (`in`) or last `frames` frames of `x`, in place.
    static func fade(_ x: inout [Float], in fadeIn: Bool, frames: Int = fadeFrames) {
        let n = min(frames, x.count)
        guard n > 0 else { return }
        for i in 0..<n {
            let g = Float(0.5 - 0.5 * cos(Double.pi * Double(i + 1) / Double(n + 1)))
            if fadeIn { x[i] *= g } else { x[x.count - 1 - i] *= g }
        }
    }

    /// One frame added (+1) or dropped (−1), both channels alike, at the packet's quietest point in its
    /// middle half, blended into its neighbours: an added frame is the mean of the two it goes between,
    /// and a dropped one leaves the mean of itself and the one before it. Nothing for 0, or for a
    /// packet under 4 frames.
    static func change(_ left: inout [Float], _ right: inout [Float], by change: Int) {
        let n = min(left.count, right.count)
        guard change != 0, n >= 4 else { return }
        let from = n / 4, to = max(from + 1, (3 * n) / 4)
        var quietest = from
        var level = Float.infinity
        for i in from..<min(to, n - 1) {
            let l = abs(left[i]) + abs(right[i]) + abs(left[i + 1]) + abs(right[i + 1])
            if l < level { level = l; quietest = i }
        }
        let q = quietest
        if change > 0 {
            left.insert((left[q] + left[q + 1]) / 2, at: q + 1)
            right.insert((right[q] + right[q + 1]) / 2, at: q + 1)
        } else {
            left[q] = (left[q] + left[q + 1]) / 2
            right[q] = (right[q] + right[q + 1]) / 2
            left.remove(at: q + 1)
            right.remove(at: q + 1)
        }
    }
}
