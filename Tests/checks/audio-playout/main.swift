// H3 (docs/audio-plan.md §7.2, §11): iOSClient/AudioPlayout.swift on its own, on a simulated clock. A Mac
// makes the sound's packets (stamps on its own wall clock, which can drift and step; pauses that start a
// new segment; packets it skips; a new epoch) and the picture's frames; a link carries them (steady,
// keyframe bursts, a stall, away from home, a move's two connections); the device's decoder and player
// node are stood in for (the decoder's state after a reset, the player's timeline on an output clock that
// drifts, read in IO-sized renders). Every scenario and 5,000 random runs hold the plan's invariants:
// nothing plays before it arrives; no two packets overlap; the sound never leads the picture as the model
// sees it; nothing is scheduled less than the IO buffer + 2 ms before its render; a packet decoded on a
// reset decoder in the middle of a segment is never played; no packet plays twice, and a duplicate never
// counts toward the floor or the need; at most one frame added or dropped a packet; every kept packet is
// played or discarded. The scenarios check the rest: a steady link loses nothing as late after its first
// 2 s whatever the output latency and the IO buffer, the error falls at 1.9 ms a second or better, jumps,
// steps, the cover's start and bounds, the picture's lag, fades and a frame gained or lost.
//   swiftc -O iOSClient/AudioPlayout.swift Tests/checks/audio-playout/main.swift -o .build/checks/audio-playout/check
import Foundation

var failures = 0, passes = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    if ok { passes += 1; print("ok   \(what())") } else { failures += 1; print("FAIL \(what()) (line \(line))") }
}
func ms(_ s: Double) -> String { String(format: "%.1f ms", s * 1000) }

let rate = AudioPlayout.rate
let wallBase = 1_790_000_000.0

// MARK: - A random number generator (SplitMix64), so every run is the same run

struct RNG {
    var state: UInt64
    init(_ seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 &+ 1 }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * unit() }
    mutating func chance(_ p: Double) -> Bool { unit() < p }
    mutating func int(_ a: Int, _ b: Int) -> Int { a + Int(next() % UInt64(b - a + 1)) }
}

// MARK: - The simulation

/// One run's world. Times are the device's monotonic clock (the simulation's own); the Mac's wall clock
/// is `wall(τ)`.
struct World {
    var seconds = 20.0
    var F = 480, P = 240
    var outputLatency = 0.010
    var io = 0.005
    var refresh = 1.0 / 60
    var streamFPS = 60.0
    /// The picture's frames a second; 0: a still window (none).
    var videoFPS = 60.0
    var away = false
    /// The Mac's wall clock's rate − 1, and the steps it takes (at device time, by seconds).
    var hostDrift = 0.0
    var hostSteps: [(at: Double, by: Double)] = []
    /// The output's sample clock's rate − 1 against the device's clock.
    var outDrift = 0.0
    /// When a packet produced at τ arrives: τ + transit(τ). The same for frames, and a frame's stamp is
    /// taken this long after its content (the encode).
    var transit: (Double) -> Double = { _ in 0.003 }
    var videoTransit: ((Double) -> Double)? = nil
    var videoEncode = 0.008
    /// The Mac pauses its sound: nothing from `at` for `pause`, then a new segment (the seq goes on).
    var pauses: [(at: Double, pause: Double)] = []
    /// A new epoch starts at these times (a new source), with a new segment and its format first.
    var epochs: [Double] = []
    /// Packets the Mac skipped (by seq of the first epoch).
    var skipped: Set<Int> = []
    /// Packets delivered twice (a move's two connections): seqs from…to of the first epoch, the copy
    /// `extra` seconds after the first delivery (negative: the copy comes first).
    var duplicate: (from: Int, to: Int, extra: Double)? = nil
    /// A move (docs/audio-plan.md §7.2, rule 7): the new connection registers at `register` and is sent
    /// every packet from then on over `newTransit`; what its probe read waits until the hand-over, and
    /// is handled then; the old connection's packets (`oldTransit`) count until the hand-over.
    var move: (register: Double, handOver: Double, oldTransit: Double, newTransit: Double)? = nil
    /// The device's first packet is this seq of the first epoch (joining mid-segment); earlier ones it never sees.
    var joinAt: Int? = nil
    /// The first timeline reading comes this long after the first packet (the engine starting).
    var engineStart = 0.0
    var readingJitter = 0.0
    /// Mute (true) and unmute (false) at these times; each is a `.playback` reset, and unmuting
    /// restarts the engine (engineStart again).
    var mutes: [(at: Double, muted: Bool)] = []
    /// The route changes: the output latency becomes this, and the next packet is placed by time.
    var routes: [(at: Double, outputLatency: Double)] = []
    /// The output latency changes with no reset: it moves the need and the ear alike, so nothing moves.
    var drifts: [(at: Double, outputLatency: Double)] = []
    /// The IO buffer changes with no reset (the error must be closed by frames).
    var ioAt: [(at: Double, io: Double)] = []
    /// Away from home until (a move home at this time).
    var homeAt: Double? = nil
    var rtt: Double? = 0.005
    /// The hop from the network queue to the playout's.
    var processing = 0.00002
    /// A decode fails at these seqs of the first epoch.
    var decodeFails: Set<Int> = []
    var label = ""

    func wall(_ t: Double) -> Double {
        wallBase + t * (1 + hostDrift) + hostSteps.filter { $0.at <= t }.reduce(0) { $0 + $1.by }
    }
}

/// What the run saw: each part of a packet handed to the player (its body, then its held tail).
struct Played {
    let id: Int
    let part: AudioPlayout.Schedule.Part
    /// The packet's first part (its body, or its tail when it has no body): where it was placed.
    let first: Bool
    let seq: UInt32
    let epoch: Int
    let start: Double
    let frames: Int
    let stamp: Double
    let scheduledAt: Double
    let arrival: Double
    let fadeIn: Bool
    let fadeOut: Bool
    let change: Int
    let decision: AudioPlayout.Decision
    /// When its first frame is really heard: the output's clock and the output latency then.
    let ear: Double
    let contiguous: Bool
}

final class Run {
    let w: World
    var model = AudioPlayout()
    var played: [Played] = []
    /// One per packet: its first part; and the tails.
    var packets: [Played] { played.filter(\.first) }
    var tails: [Played] { played.filter { $0.part == .tail } }
    var playedIDs = Set<Int>()
    var partsDone = Set<Int64>()
    var playedKeys = Set<Int64>()
    var delivered = Set<Int64>()
    var discarded = Set<Int>()
    var kept: [Int: (seq: UInt32, epoch: Int, arrival: Double, frames: Int, good: Bool, fadeIn: Bool, firstStamp: Double)] = [:]
    var seconds: [(t: Double, s: AudioPlayout.Second)] = []
    var errors: [(t: Double, e: Double)] = []
    var violations: [String] = []
    var duplicatesSent = 0
    var dupChangedWindows = 0
    var formatsIgnored = 0
    // The output: the timeline starts at t0 (nil: not running), in IO-sized renders.
    var t0: Double?
    var playerEnd: Double?
    var outputLatency: Double
    /// The IO buffer now (the renders are this long).
    var io: Double
    // The decoder's truth.
    var decEpoch = -1, decNext: UInt32 = 0, decBroken = true, decNoise = 0
    var epochNow = 0
    var rng = RNG(7)

    init(_ w: World, seed: UInt64 = 7) {
        self.w = w
        outputLatency = w.outputLatency
        io = w.io
        rng = RNG(seed)
    }

    func violation(_ s: String) { if violations.count < 20 { violations.append(s) } }

    /// The output clock: the device time sample `s` of the timeline goes out at.
    func T(_ s: Double) -> Double { t0! + s / (rate * (1 + w.outDrift)) }

    /// The last render's reading at `now`: (its first sample, the time it goes out).
    func reading(_ now: Double) -> (Double, Double)? {
        guard let t0, now >= t0 - io else { return nil }
        let block = max(1.0, (io * rate).rounded())
        // The latest block rendered by now: rendered at T(kB) − io.
        let k = ((now + io - t0) * rate * (1 + w.outDrift) / block).rounded(.down)
        guard k >= 0 else { return nil }
        let s = k * block
        let jitter = w.readingJitter > 0 ? rng.range(-w.readingJitter, w.readingJitter) : 0
        return (s, T(s) + jitter)
    }

    func feedReading(_ now: Double) {
        if let (s, t) = reading(now) {
            lastReadingAt = now
            apply(model.played(sample: s, at: t, now: now), now)
        }
    }

    func apply(_ out: AudioPlayout.Output, _ now: Double) {
        for d in out.discards {
            if discarded.contains(d) { violation("discarded twice: \(d)") }
            discarded.insert(d)
        }
        for s in out.schedules { schedule(s, now) }
    }

    func schedule(_ s: AudioPlayout.Schedule, _ now: Double) {
        guard let k = kept[s.id] else { violation("scheduled an id never kept: \(s.id)"); return }
        guard t0 != nil else { violation("scheduled with no engine running: seq \(s.seq)"); return }
        if discarded.contains(s.id) { violation("scheduled a discarded packet: seq \(s.seq)") }
        let partKey = Int64(s.id) << 1 | (s.part == .tail ? 1 : 0)
        if !partsDone.insert(partKey).inserted { violation("id \(s.id)'s \(s.part) scheduled twice") }
        let first = playedIDs.insert(s.id).inserted
        if s.part == .body && !first { violation("seq \(s.seq)'s body after its tail") }
        if s.part == .tail && first && s.offset != 0 { violation("seq \(s.seq)'s tail before its body") }
        let tailCount = min(AudioPlayout.fadeFrames, k.frames)
        if s.part == .body ? (s.offset != 0 || s.count != k.frames - tailCount) : (s.offset != k.frames - tailCount || s.count != tailCount) {
            violation("seq \(s.seq)'s \(s.part): frames \(s.offset)+\(s.count) of \(k.frames)")
        }
        if first, !playedKeys.insert(Int64(s.epoch) << 32 | Int64(s.seq)).inserted { violation("seq \(s.seq) of epoch \(s.epoch) played twice") }
        let start: Double
        if let at = s.at {
            start = at
            if let end = playerEnd, at < end - 0.5 { violation("seq \(s.seq) overlaps: at \(at) before the end \(end)") }
            if !first { violation("seq \(s.seq)'s tail placed apart from its body") }
        } else {
            guard let end = playerEnd else { violation("seq \(s.seq) follows nothing"); return }
            start = end
            if abs(end - s.start) > 0.5 { violation("seq \(s.seq) planned at \(s.start), follows at \(end)") }
        }
        // As the model sees the timeline: never less than the IO buffer + 2 ms ahead, but for what its
        // view moved between the reading that set a deadline and the one taken when it came: the output
        // clock's drift over that time (from a reading up to an IO buffer ahead), and each reading's
        // jitter: microseconds, and the jitter the run gives its readings.
        let seen = s.goesOut - now
        let moved = abs(w.outDrift) * (staleness + io + AudioPlayout.margin) + 2 * w.readingJitter + 1e-6
        if seen < io + AudioPlayout.margin - moved { violation("seq \(s.seq)'s \(s.part) scheduled \(String(format: "%.4f", seen * 1000)) ms before it goes out as the model sees it (IO \(String(format: "%.4f", io * 1000)) ms)") }
        // And truly: the model knows the timeline by its readings, extrapolated at 48 kHz from the last
        // one, which an output clock's drift and a reading's jitter put off by as much; far under the 2 ms.
        let ahead = T(start) - now
        let slack = 2e-5 + abs(w.outDrift) * (max(0, ahead) + staleness + io) + 2 * w.readingJitter
        if ahead < io + AudioPlayout.margin - slack { violation("seq \(s.seq)'s \(s.part) scheduled \(String(format: "%.4f", ahead * 1000)) ms before it goes out (IO \(ms(io)))") }
        if T(start) - io < k.arrival { violation("seq \(s.seq) renders before it arrives") }
        if abs(s.change) > 1 || (s.part == .tail && s.change != 0) { violation("seq \(s.seq): \(s.change) frames changed in its \(s.part)") }
        if s.frames != s.count + s.change { violation("seq \(s.seq): \(s.frames) frames, \(s.count) and changed \(s.change)") }
        if !k.good { violation("seq \(s.seq) played though decoded on a reset decoder mid-segment") }
        if abs(s.stamp - k.firstStamp) > 1e-7 { violation("seq \(s.seq) placed by \(s.stamp), its first kept frame's stamp is \(k.firstStamp)") }
        if first, k.fadeIn, !s.fadeIn { violation("seq \(s.seq) after a join played without a fade in") }
        if s.fadeIn && !first { violation("seq \(s.seq): a fade in on its tail after its body") }
        if s.fadeOut && s.part != .tail { violation("seq \(s.seq): a fade out on its body") }
        if first, s.decision.ear < s.decision.picture - 1e-9 { violation("seq \(s.seq) ahead of the picture by \(ms(s.decision.picture - s.decision.ear))") }
        playerEnd = start + Double(s.frames)
        played.append(Played(id: s.id, part: s.part, first: first, seq: s.seq, epoch: s.epoch, start: start, frames: s.frames,
                              stamp: s.stamp, scheduledAt: now, arrival: k.arrival, fadeIn: s.fadeIn, fadeOut: s.fadeOut,
                              change: s.change, decision: s.decision, ear: T(start) + outputLatency, contiguous: s.at == nil))
    }

    /// The events, in time order.
    enum Event { case packet(epoch: Int, seq: UInt32, stamp: Double, segmentStart: Bool, arrival: Double)
                 case format(epoch: Int), frame(stamp: Double), mute(Bool), route(Double), drift(Double), io(Double), home, rttTick, second }

    func run() {
        var events: [(t: Double, order: Int, e: Event)] = []
        var order = 0
        func add(_ t: Double, _ e: Event) { events.append((t, order, e)); order += 1 }
        // The Mac's sound: segments of packets, stamped at input frame n·F − P of the segment.
        let segF = Double(w.F) / rate
        var breaks = w.pauses.map { ($0.at, $0.pause, false) } + w.epochs.map { ($0, 0.0, true) }
        breaks.sort { $0.0 < $1.0 }
        var epoch = 1
        var seq = 0
        var segStart = 0.0
        // One TCP connection delivers in order: nothing arrives before what was sent before it.
        var lastOld = -Double.infinity, lastNew = -Double.infinity, lastDup = -Double.infinity
        var n = 0
        var bi = 0
        let firstSeq = w.joinAt ?? 0
        add(0, .format(epoch: epoch))
        while true {
            let produce = segStart + (Double(n + 1) * segF) - Double(w.P) / rate + 0.010
            if produce > w.seconds { break }
            if bi < breaks.count, produce >= breaks[bi].0 {
                let (at, pause, newEpoch) = breaks[bi]
                bi += 1
                segStart = at + pause
                n = 0
                if newEpoch {
                    epoch += 1
                    seq = 0
                    add(segStart + 0.001, .format(epoch: epoch))
                }
                continue
            }
            let content = segStart + (Double(n * w.F) - Double(w.P)) / rate
            let stamp = w.wall(content)
            if !(epoch == 1 && (w.skipped.contains(seq) || seq < firstSeq)) {
                func deliver(_ arrival: Double) {
                    add(arrival + w.processing, .packet(epoch: epoch, seq: UInt32(seq), stamp: stamp, segmentStart: n == 0, arrival: arrival))
                }
                if let m = w.move {
                    lastOld = max(lastOld, produce + m.oldTransit)
                    if lastOld < m.handOver { deliver(lastOld) }
                    if produce >= m.register { lastNew = max(lastNew, produce + m.newTransit, m.handOver); deliver(lastNew) }
                } else {
                    lastOld = max(lastOld, produce + w.transit(produce))
                    deliver(lastOld)
                }
                if epoch == 1, let d = w.duplicate, seq >= d.from, seq <= d.to {
                    lastDup = max(lastDup, produce + w.transit(produce) + d.extra)
                    deliver(lastDup)
                }
            }
            seq += 1
            n += 1
        }
        // A move's new connection is sent the format first, which its probe keeps until the hand-over.
        if let m = w.move { add(m.handOver + w.processing - 0.0001, .format(epoch: 1)) }
        if w.videoFPS > 0 {
            var t = 0.0
            var last = -Double.infinity
            let vt = w.videoTransit ?? w.transit
            while t < w.seconds {
                let out = t + w.videoEncode
                last = max(last, out + vt(out))
                add(last, .frame(stamp: w.wall(out)))
                t += 1 / w.videoFPS
            }
        }
        for m in w.mutes { add(m.at, .mute(m.muted)) }
        for r in w.routes { add(r.at, .route(r.outputLatency)) }
        for d in w.drifts { add(d.at, .drift(d.outputLatency)) }
        for x in w.ioAt { add(x.at, .io(x.io)) }
        if let h = w.homeAt { add(h, .home) }
        var s = 1.0
        while s < w.seconds + 1 { add(s, .rttTick); add(s + 0.0005, .second); s += 1 }
        events.sort { $0.t != $1.t ? $0.t < $1.t : $0.order < $1.order }

        model.latency(output: outputLatency, io: io, refresh: w.refresh, streamFPS: w.streamFPS)
        model.away(w.away)
        model.rtt(median: w.rtt)
        var engineAt: Double?
        var muted = false
        events.removeAll { $0.t > w.seconds + 1 }
        events.append((w.seconds + 1, order, .second))
        var i = 0
        while i < events.count {
            let (t, _, e) = events[i]
            // The engine's first render, and the hand's deadline, before the next event.
            if let at = engineAt, t0 == nil, at <= t {
                t0 = at
                playerEnd = nil
                feedReading(at)
                continue
            }
            if let d = model.deadline, d < t {
                var now = max(d, lastNow)
                staleness = now - lastReadingAt
                feedReading(now)
                now = max(now, model.deadline ?? now)
                lastNow = now
                apply(model.tick(now: now), now)
                continue
            }
            i += 1
            lastNow = t
            staleness = 0
            switch e {
            case .format(let ep):
                epochNow = ep
                if !model.format(epoch: ep, framesPerPacket: w.F, primingFrames: w.P, cookie: Data([1, 2, UInt8(ep & 0xFF)])) {
                    formatsIgnored += 1
                }
            case .frame(let stamp):
                model.frame(stamp: stamp, arrival: t)
            case .packet(let ep, let sq, let stamp, let start, let arrival):
                // A copy of what this session was already handed is a duplicate: it must count nowhere.
                let dup = !delivered.insert(Int64(ep) << 32 | Int64(sq)).inserted
                if dup { duplicatesSent += 1 }
                let before = (model.floor, model.cover(now: t), model.need(now: t))
                if engineAt == nil, !muted { engineAt = t + w.engineStart }
                feedReading(t)
                let plan = model.packet(epoch: ep, seq: sq, stamp: stamp, segmentStart: start, now: t)
                if dup, (model.floor != before.0 || model.cover(now: t) != before.1 || model.need(now: t) != before.2) { dupChangedWindows += 1 }
                if dup, plan.decode { violation("a duplicate (seq \(sq)) decoded") }
                decode(plan, epoch: ep, seq: sq, segmentStart: start, arrival: arrival, stamp: stamp)
                apply(plan.output, t)
            case .mute(let m):
                muted = m
                model.mute(m)
                apply(model.reset(.playback), t)
                t0 = nil
                playerEnd = nil
                engineAt = m ? nil : t + w.engineStart
            case .route(let ol):
                outputLatency = ol
                model.latency(output: ol, io: io, refresh: w.refresh, streamFPS: w.streamFPS)
                apply(model.reset(.jump), t)
            case .drift(let ol):
                outputLatency = ol
                model.latency(output: ol, io: io, refresh: w.refresh, streamFPS: w.streamFPS)
            case .io(let x):
                io = x
                model.latency(output: outputLatency, io: x, refresh: w.refresh, streamFPS: w.streamFPS)
            case .home:
                model.away(false)
            case .rttTick:
                model.rtt(median: w.rtt)
            case .second:
                let sec = model.takeSecond(now: t)
                seconds.append((t, sec))
                if let e = sec.error { errors.append((t, e)) }
            }
        }
        // The packet in hand when the events end still goes out at its deadline.
        while let d = model.deadline, d <= w.seconds + 1 {
            let now = max(d, lastNow)
            staleness = now - lastReadingAt
            feedReading(now)
            let at = max(now, model.deadline ?? now)
            lastNow = at
            apply(model.tick(now: at), at)
        }
        // What is still held at the end is neither played nor discarded, and that is fine.
        let tailsDone = Set(played.filter { $0.part == .tail }.map(\.id))
        let held = Set(kept.keys).subtracting(discarded).subtracting(tailsDone)
        if held.count > 1 + AudioPlayout.waitingLimit { violation("\(held.count) kept packets never played nor discarded") }
    }
    var lastNow = 0.0
    /// How old the reading was that decided the moment of this call (a deadline set a while ago).
    var staleness = 0.0
    var lastReadingAt = 0.0

    /// The decoder: what the plan asks, and whether what it gives is the signal.
    func decode(_ plan: AudioPlayout.Plan, epoch: Int, seq: UInt32, segmentStart: Bool, arrival: Double, stamp: Double) {
        guard plan.decode else {
            if plan.id != nil { violation("seq \(seq) kept without being decoded") }
            return
        }
        var good: Bool
        if plan.resetFirst {
            decEpoch = epoch
            decNext = seq &+ 1
            decBroken = false
            if segmentStart {
                good = true
                decNoise = 0
                if plan.dropFront != min(w.P, w.F) { violation("seq \(seq): a segment's first packet drops \(plan.dropFront), not its \(w.P) frames of priming") }
            } else {
                good = false    // the first packet on a decoder reset mid-segment is noise
                decNoise = 1    // and the next is within −41 dB: played only faded in
            }
        } else if segmentStart {
            // A new segment was encoded from a reset encoder: on the decoder's old state it is noise.
            decBroken = true
            good = false
        } else if !decBroken, decEpoch == epoch, decNext == seq {
            decNext = seq &+ 1
            good = true
        } else {
            decBroken = true
            good = false
        }
        let fadeRequired = decNoise == 1 && good && !plan.resetFirst
        if good && !plan.resetFirst && decNoise > 0 { decNoise = 0 }
        if epoch == 1, w.decodeFails.contains(Int(seq)), plan.id != nil {
            model.decodeFailed()
            good = true         // silence in its place: never noise
            decBroken = true    // and the decoder's state is gone until it is reset
        }
        if let id = plan.id {
            // The first frame kept is the packet's stamp plus the frames dropped before it.
            kept[id] = (seq, epoch, arrival, w.F - plan.dropFront, good, fadeRequired, stamp + Double(plan.dropFront) / rate)
        } else if plan.dropFront != w.F && !(segmentStart && w.P >= w.F) {
            violation("seq \(seq) decoded and neither kept nor dropped whole")
        }
        if plan.resetFirst && !segmentStart && plan.id != nil { violation("seq \(seq) on a reset decoder mid-segment was kept") }
    }

    // Reading the results.
    func lateAfter(_ t: Double) -> Int { seconds.filter { $0.t > t }.reduce(0) { $0 + $1.s.late } }
    var totalLate: Int { seconds.reduce(0) { $0 + $1.s.late } }
    var totalJumps: Int { seconds.reduce(0) { $0 + $1.s.jumps } }
    func jumps(after t: Double) -> Int { seconds.filter { $0.t > t }.reduce(0) { $0 + $1.s.jumps } }
    func jumps(between a: Double, _ b: Double) -> Int { seconds.filter { $0.t > a && $0.t <= b + 1 }.reduce(0) { $0 + $1.s.jumps } }
    func late(between a: Double, _ b: Double) -> Int { seconds.filter { $0.t > a && $0.t <= b + 1 }.reduce(0) { $0 + $1.s.late } }
    /// Packets placed (their first part scheduled) after `t`.
    func playedAfter(_ t: Double) -> [Played] { packets.filter { $0.scheduledAt > t } }
    /// The truth: how far each played packet's first frame is heard from where the model placed it.
    var worstEarOff: Double { packets.map { abs($0.ear - $0.decision.ear) }.max() ?? 0 }
    /// Gaps in what plays after `t`: a tail that fades out before the stream's own end.
    func underruns(after t: Double) -> Int { tails.filter { $0.scheduledAt > t && $0.scheduledAt < w.seconds - 0.5 && $0.fadeOut }.count }
    func packet(_ seq: UInt32, epoch: Int = 1) -> Played? { packets.first { $0.seq == seq && $0.epoch == epoch } }
    func tail(_ seq: UInt32, epoch: Int = 1) -> Played? { tails.first { $0.seq == seq && $0.epoch == epoch } }
}

@discardableResult
func simulate(_ w: World, seed: UInt64 = 7) -> Run {
    let r = Run(w, seed: seed)
    r.run()
    return r
}

func noViolations(_ r: Run, _ what: String, line: Int = #line) {
    check(r.violations.isEmpty, "\(what): the invariants hold" + (r.violations.isEmpty ? "" : ": " + r.violations.prefix(3).joined(separator: "; ")), line: line)
}

// MARK: - The need, the floor, the cover, the picture's lag: by hand

do {
    var m = AudioPlayout()
    check(m.format(epoch: 3, framesPerPacket: 480, primingFrames: 240, cookie: Data([9])), "a format: a new epoch")
    check(!m.format(epoch: 3, framesPerPacket: 480, primingFrames: 240, cookie: Data([9])), "the same epoch and cookie again (a move's connection): ignored")
    check(m.format(epoch: 3, framesPerPacket: 480, primingFrames: 240, cookie: Data([8])), "the same epoch, another cookie: a new decoder")
    check(m.format(epoch: 4, framesPerPacket: 512, primingFrames: 256, cookie: Data([8])), "another epoch: a new decoder")
    m.latency(output: 0.011, io: 0.005, refresh: 1.0 / 60, streamFPS: 60)
    check(m.floor == nil && abs(m.cover(now: 0) - 0.040) < 1e-12, "no packet yet: no floor, the cover's start 40 ms at home")
    m.away(true)
    check(abs(m.cover(now: 0) - 0.150) < 1e-12, "away: the cover's start 150 ms")
    m.away(false)
    // A packet at arrival 100.0 stamped so that arrival − stamp = 5 ms.
    _ = m.packet(epoch: 4, seq: 0, stamp: 99.995, segmentStart: true, now: 100.0)
    check(abs((m.floor ?? 0) - 0.005) < 1e-9, "the first packet sets the floor")
    let need = m.need(now: 100.0)
    check(abs(need - (0.040 + 512.0 / 48_000 + 0.005 + 0.011 + 0.002)) < 1e-12,
          "the need: the cover 40 + a packet 10.7 + IO 5 + output 11 + 2 ms = \(ms(need))")
    // The cover stays at its start through the first 2 s of packets, whatever they bring.
    _ = m.packet(epoch: 4, seq: 1, stamp: 100.5 - 0.0053, segmentStart: false, now: 100.6)
    check(abs(m.cover(now: 100.6) - 0.040) < 1e-12, "a packet 100 ms over the floor in the first 2 s leaves the cover at 40 ms")
    // Past 2 s the window counts: a packet 30 ms over the floor makes the cover 30 ms at once.
    _ = m.packet(epoch: 4, seq: 2, stamp: 102.3 - 0.035, segmentStart: false, now: 102.3)
    check(abs(m.cover(now: 102.3) - 0.030) < 1e-9, "past the first 2 s a packet 30 ms over the floor makes the cover 30 ms at once: \(ms(m.cover(now: 102.3)))")
    _ = m.packet(epoch: 4, seq: 3, stamp: 102.4 - 0.0051, segmentStart: false, now: 102.4)
    check(abs(m.cover(now: 102.4) - 0.030) < 1e-9, "the largest of the window stays")
    // A packet 1 ms over the floor alone: the lower bound, 20 ms.
    var lone = AudioPlayout()
    _ = lone.format(epoch: 1, framesPerPacket: 480, primingFrames: 240, cookie: Data())
    _ = lone.packet(epoch: 1, seq: 0, stamp: 9.990, segmentStart: true, now: 10)
    _ = lone.packet(epoch: 1, seq: 1, stamp: 12.5 - 0.011, segmentStart: false, now: 12.5)
    check(abs(lone.cover(now: 12.5) - 0.020) < 1e-9, "a cover of 1 ms is held at home's lower bound, 20 ms")
    _ = lone.packet(epoch: 1, seq: 2, stamp: 12.6 - 0.310, segmentStart: false, now: 12.6)
    check(abs(lone.cover(now: 12.6) - 0.150) < 1e-9, "300 ms over the floor at home: held at 150 ms")
    lone.away(true)
    check(abs(lone.cover(now: 12.6) - 0.300) < 1e-9, "the same away: 300 ms (away's bounds 60–600)")
    _ = lone.packet(epoch: 1, seq: 3, stamp: 12.7 - 0.910, segmentStart: false, now: 12.7)
    check(abs(lone.cover(now: 12.7) - 0.600) < 1e-9, "900 ms over away: held at 600 ms")
    // The floor window: 10 s of 1 s buckets, and kept when nothing comes.
    var fl = AudioPlayout()
    _ = fl.format(epoch: 1, framesPerPacket: 480, primingFrames: 240, cookie: Data())
    _ = fl.packet(epoch: 1, seq: 0, stamp: 0.990, segmentStart: true, now: 1)       // 10 ms
    for k in 1...9 { _ = fl.packet(epoch: 1, seq: UInt32(k), stamp: Double(k) + 1.5 - 0.015, segmentStart: false, now: Double(k) + 1.5) }
    check(abs((fl.floor ?? 0) - 0.010) < 1e-9, "the floor: the smallest of the last 10 s")
    _ = fl.packet(epoch: 1, seq: 10, stamp: 11.5 - 0.015, segmentStart: false, now: 11.5)
    check(abs((fl.floor ?? 0) - 0.015) < 1e-9, "10 s on, the smallest has left the window: \(ms(fl.floor ?? 0))")
    check(abs((fl.floor ?? 0) - 0.015) < 1e-9, "with no packet since, it keeps its last value (read at any time)")
    // The picture's lag: the median of 2 s of frames, over the floor, + 1.5 refreshes + 4 ms.
    var pic = AudioPlayout()
    _ = pic.format(epoch: 1, framesPerPacket: 480, primingFrames: 240, cookie: Data())
    pic.latency(output: 0.010, io: 0.005, refresh: 1.0 / 60, streamFPS: 60)
    _ = pic.packet(epoch: 1, seq: 0, stamp: 9.980, segmentStart: true, now: 10)       // floor 20 ms
    for (k, raw) in [0.030, 0.010, 0.050, 0.012, 0.040].enumerated() {
        let a = 10.0 + Double(k) * 0.1
        pic.frame(stamp: a - raw, arrival: a)
    }
    let lag = pic.pictureLag(now: 10.5) ?? .nan
    check(abs(lag - (0.030 - 0.020 + 1.5 / 60 + 0.004)) < 1e-9, "the picture's lag: median 30 − floor 20 + 25 + 4 = \(ms(lag))")
    check(abs(pic.delay(now: 10.5, lag: lag) - pic.need(now: 10.5)) < 1e-12, "the need decides while it is the larger")
    for k in 0..<5 { let a = 12.1 + Double(k) * 0.1; pic.frame(stamp: a - 0.300, arrival: a) }
    let late = pic.pictureLag(now: 12.5) ?? .nan
    check(abs(late - (0.300 - 0.020 + 1.5 / 60 + 0.004)) < 1e-9, "frames 300 ms late: the median follows them: \(ms(late))")
    check(abs(pic.delay(now: 12.5, lag: late) - (late + 1.0 / 60)) < 1e-12, "the guard decides: the picture's lag + one frame")
    let still = pic.pictureLag(now: 20.0) ?? .nan
    check(abs(still - late) < 1e-9, "no frame for 9 s (a still window): the lag keeps its last value")
    let never = AudioPlayout().pictureLag(now: 0)
    check(never == nil, "no frame and no floor: no lag")
}

// MARK: - Fades and a frame gained or lost

do {
    var x = [Float](repeating: 1, count: 480)
    AudioPlayout.fade(&x, in: true)
    check(x[0] < 0.001 && x[239] > 0.99 && x[240] == 1 && zip(x.prefix(240), x.dropFirst().prefix(240)).allSatisfy { $0 <= $1 },
          "a fade in: 5 ms (240 frames) rising from silence, the rest untouched")
    var y = [Float](repeating: 1, count: 480)
    AudioPlayout.fade(&y, in: false)
    check(y[479] < 0.001 && y[240] > 0.99 && y[239] == 1, "a fade out: the last 5 ms falling to silence")
    var short = [Float](repeating: 1, count: 100)
    AudioPlayout.fade(&short, in: true)
    check(short[0] < 0.01 && short[99] > 0.99, "a packet shorter than a fade fades over all of it")
    // A sine: the frame goes in or out at its quietest point in the middle half, blended.
    let sine = (0..<480).map { Float(sin(2 * Double.pi * 440 * Double($0) / 48_000)) }
    var l = sine, r = sine
    AudioPlayout.change(&l, &r, by: 1)
    check(l.count == 481 && r.count == 481 && l == r, "a frame gained: 481 frames, both channels alike")
    let jump = zip(l, l.dropFirst()).map { abs($1 - $0) }.max() ?? 1
    let natural = zip(sine, sine.dropFirst()).map { abs($1 - $0) }.max() ?? 1
    check(jump <= natural * 1.01, "…and no step larger than the sine's own (\(jump) against \(natural))")
    var l2 = sine, r2 = sine
    AudioPlayout.change(&l2, &r2, by: -1)
    check(l2.count == 479 && r2.count == 479, "a frame lost: 479 frames")
    let jump2 = zip(l2, l2.dropFirst()).map { abs($1 - $0) }.max() ?? 1
    check(jump2 <= natural * 1.6, "…and no step much larger than the sine's own (\(jump2))")
    let firstDiff = (0..<min(sine.count, l.count)).first { sine[$0] != l[$0] } ?? -1
    check(firstDiff >= 120 && firstDiff <= 360, "the change is in the packet's middle half (at \(firstDiff))")
    let q = (120..<360).min { abs(sine[$0]) + abs(sine[$0 + 1]) < abs(sine[$1]) + abs(sine[$1 + 1]) } ?? 0
    check(firstDiff == q + 1, "…at its quietest point (\(q))")
    var n0 = sine, n1 = sine
    AudioPlayout.change(&n0, &n1, by: 0)
    check(n0 == sine, "no change for 0")
}

// MARK: - Scenarios

// A steady link at home: nothing late after the first 2 s, whatever the output latency and the IO buffer.
for (ol, io) in [(0.010, 0.005), (0.180, 0.005), (2.0, 0.005), (0.010, 0.023), (0.180, 0.023), (2.0, 0.023)] {
    var w = World()
    w.seconds = 30
    w.outputLatency = ol
    w.io = io
    w.transit = { t in 0.003 + 0.0005 * sin(t * 7.3) }
    let r = simulate(w)
    noViolations(r, "steady, output \(ms(ol)), IO \(ms(io))")
    check(r.lateAfter(2) == 0, "steady, output \(ms(ol)), IO \(ms(io)): nothing late after 2 s (\(r.lateAfter(2)))")
    let tail = r.playedAfter(3)
    check(tail.count >= 2600, "…and every packet after 3 s played (\(tail.count))")
    check(r.jumps(after: 3) == 0 && r.underruns(after: 3) == 0, "…with no jump or fade out after 3 s")
    let settled = r.errors.filter { $0.t > 20 }.map { abs($0.e) }.max() ?? 1
    check(settled < 0.001, "…its error under 1 ms once settled (\(ms(settled)))")
    check(r.worstEarOff < 0.0005, "…each packet heard where the model placed it (within \(ms(r.worstEarOff)))")
}

// The same at 512 frames a packet, and at 120 fps.
do {
    var w = World()
    w.F = 512; w.P = 256
    w.seconds = 25
    let r = simulate(w)
    noViolations(r, "steady, 512 frames a packet")
    check(r.lateAfter(2) == 0 && r.playedAfter(3).count >= 2000, "steady, 512: nothing late, everything played")
    var w2 = World()
    w2.streamFPS = 120; w2.videoFPS = 120; w2.refresh = 1.0 / 120
    let r2 = simulate(w2)
    noViolations(r2, "steady, a 120 fps stream on a 120 Hz panel")
    check(r2.lateAfter(2) == 0, "…nothing late")
}

// How far the sound trails the picture at home: the need decides, and the sound is behind.
do {
    let r = simulate(World())
    let behind = r.seconds.compactMap { $0.s.behindMs }.suffix(10)
    check(!behind.isEmpty && behind.allSatisfy { $0 > 0 && $0 < 100 }, "at home the sound trails the picture by 0–100 ms (\(Array(behind)))")
    let d = r.seconds.last!.s
    check(d.delay >= d.need - 1e-9, "the delay is at least the need")
}

// A 40 ms burst every 4 s (the safety keyframe ahead of the next packets).
do {
    var w = World()
    w.seconds = 40
    w.transit = { t in
        let into = t.truncatingRemainder(dividingBy: 4)
        return 0.003 + (into < 0.040 ? 0.040 - into : 0)
    }
    let r = simulate(w)
    noViolations(r, "a 40 ms burst every 4 s")
    check(r.lateAfter(2) == 0, "…nothing late after 2 s (the cover took the burst)")
    check(r.underruns(after: 9) == 0, "…and once the cover has it, no fade out either (\(r.underruns(after: 9)))")
    let cover = r.seconds.filter { $0.t > 10 }.map(\.s.cover)
    check(cover.allSatisfy { $0 >= 0.030 && $0 <= 0.046 }, "…the cover holds the burst: \(cover.map(ms).prefix(3))")
}

// ±100 ppm between the clocks, for an hour: no drift, no jump after the first minute.
for (host, out) in [(100e-6, 0.0), (-100e-6, 0.0), (0.0, 100e-6), (100e-6, -100e-6)] {
    var w = World()
    w.seconds = 3600
    w.hostDrift = host
    w.outDrift = out
    w.videoFPS = 5     // a sparse picture keeps the hour quick; the guard is not what this is about
    let r = simulate(w)
    noViolations(r, "an hour, the Mac's clock \(host * 1e6) ppm, the output's \(out * 1e6) ppm")
    let errs = r.errors.filter { $0.t > 60 }.map { abs($0.e) }
    check((errs.max() ?? 1) < 0.005, "…its error within ±5 ms after the first minute (worst \(ms(errs.max() ?? 1)))")
    check(r.jumps(after: 60) == 0 && r.lateAfter(60) == 0, "…no jump and nothing late after the first minute")
    let adds = r.seconds.reduce(0) { $0 + $1.s.framesAdded }, drops = r.seconds.reduce(0) { $0 + $1.s.framesDropped }
    check(adds + drops < 3600 * 100 / 10, "…frames added \(adds), dropped \(drops): a trickle")
}

// The Mac's clock steps a second either way: one jump, and back to normal.
for by in [1.0, -1.0] {
    var w = World()
    w.seconds = 25
    w.hostSteps = [(at: 12.0, by: by)]
    let r = simulate(w)
    noViolations(r, "the Mac's clock steps \(by > 0 ? "+" : "")\(by) s")
    check(r.jumps(between: 11, 16) >= 1 && r.jumps(between: 11, 16) <= 2, "…a jump or two (\(r.jumps(between: 11, 16)))")
    check(r.jumps(after: 17) == 0 && r.lateAfter(17) == 0, "…and nothing more after it")
    if by > 0 { check(r.seconds.reduce(0) { $0 + $1.s.jumpDrops } == 0 && r.lateAfter(2) == 0, "…forward: the new floor keeps every packet where it was, none dropped") }
    let tail = r.errors.filter { $0.t > 18 }.map { abs($0.e) }.max() ?? 1
    check(tail < 0.005, "…the error back under 5 ms (\(ms(tail)))")
    let behind = r.seconds.filter { $0.t > 18 }.compactMap(\.s.behindMs)
    check(!behind.isEmpty && behind.allSatisfy { $0 > 0 && $0 < 100 }, "…the sound still trails the picture a little (\(behind.prefix(3)))")
}

// A 2 s stall, then a burst: what is past its time is dropped, and playback returns by a jump.
do {
    var w = World()
    w.seconds = 30
    w.transit = { t in t >= 8 && t < 10 ? 10 - t + 0.003 : 0.003 }
    let r = simulate(w)
    noViolations(r, "a 2 s stall, then a burst")
    check(r.late(between: 9.9, 10.5) > 50, "…the burst's old packets dropped as late (\(r.late(between: 9.9, 10.5)))")
    check(r.jumps(between: 18, 22) == 1, "…and a jump once the window forgets the stall (\(r.jumps(between: 18, 22)))")
    check(r.lateAfter(11.5) == 0, "…nothing late after the burst")
}

// A move: the new connection registers at 10 s and is 30 ms faster; what its probe read is handled at the
// hand-over (10.2 s), the first of it copies of what the old one already brought.
do {
    var w = World()
    w.seconds = 20
    w.move = (register: 10.0, handOver: 10.2, oldTransit: 0.033, newTransit: 0.003)
    let r = simulate(w)
    noViolations(r, "a move's hand-over")
    let dups = r.seconds.reduce(0) { $0 + $1.s.duplicates }
    check(r.duplicatesSent >= 15 && dups == r.duplicatesSent, "…every copy dropped as a duplicate (\(dups) of \(r.duplicatesSent))")
    check(r.dupChangedWindows == 0, "…and none counted toward the floor, the cover or the need")
    check(r.formatsIgnored == 1, "…the new connection's format for the epoch playing ignored")
    check(r.jumps(between: 9, 13) <= 1, "…at most one jump (\(r.jumps(between: 9, 13)))")
    check(r.seconds.reduce(0) { $0 + $1.s.joins } == 0, "…and nothing reset (no join)")
    check(r.lateAfter(2) == 0, "…nothing late")
}
// Copies that come first and copies that come later (a move either way), anywhere in a stream.
for extra in [-0.05, 0.02, 0.3] {
    var w = World()
    w.duplicate = (from: 700, to: 760, extra: extra)
    let r = simulate(w)
    noViolations(r, "61 packets delivered twice, the copy \(ms(extra)) off")
    check(r.duplicatesSent == 61 && r.dupChangedWindows == 0, "…61 duplicates, none counted anywhere")
}

// A move home: away's cover, then home's bounds, nothing reset.
do {
    var w = World()
    w.seconds = 30
    w.away = true
    w.homeAt = 15
    w.transit = { t in t < 15 ? 0.080 + 0.050 * sin(t * 3.1) : 0.004 }
    let r = simulate(w)
    noViolations(r, "away at 80 ± 50 ms, then home")
    check(r.lateAfter(2) == 0, "…nothing late away (the cover's 150 ms start, then the window)")
    let awayCover = r.seconds.filter { $0.t > 5 && $0.t < 15 }.map(\.s.cover)
    check(awayCover.allSatisfy { $0 >= 0.060 }, "…away's lower bound, 60 ms")
    let homeCover = r.seconds.filter { $0.t > 27 }.map(\.s.cover)
    check(homeCover.allSatisfy { $0 <= 0.150 }, "…home's bounds once the window forgets (\(homeCover.map(ms).prefix(2)))")
    check(r.seconds.reduce(0) { $0 + $1.s.joins } == 0, "…nothing reset at the move home")
}

// A seq gap: the Mac skipped three packets.
do {
    var w = World()
    w.skipped = [1000, 1001, 1002]
    let r = simulate(w)
    noViolations(r, "a seq gap")
    check(r.packet(1003) == nil, "…the packet after the gap is decoded and not played")
    check(r.packet(1004)?.fadeIn == true, "…the next fades in")
    check(r.tail(999)?.fadeOut == true, "…the one before it fades out")
    check(r.seconds.reduce(0) { $0 + $1.s.joins } == 1, "…one join")
}

// A device that joins mid-segment.
do {
    var w = World()
    w.joinAt = 777
    let r = simulate(w)
    noViolations(r, "joining mid-segment")
    check(r.packet(777) == nil && r.packets.first?.seq == 778 && r.packets.first?.fadeIn == true,
          "…its first packet is decoded and dropped, the next placed by time and faded in")
}

// The Mac pauses 50 ms and 500 ms: a new segment each, placed by its stamp after the priming.
do {
    var w = World()
    w.seconds = 20
    w.pauses = [(at: 6, pause: 0.05), (at: 12, pause: 0.5)]
    let r = simulate(w)
    noViolations(r, "the Mac pauses 50 and 500 ms")
    let starts = r.packets.filter { !$0.contiguous && $0.scheduledAt > 3 }
    check(starts.count == 2 && starts.allSatisfy { $0.fadeIn }, "…two segment starts placed by time, faded in (\(starts.count))")
    check(starts.allSatisfy { abs($0.decision.error) < 0.0002 }, "…each at its stamp (the first kept frame's, after the priming)")
    let before = r.tails.filter { p in starts.contains { $0.seq == p.seq + 1 } }
    check(before.count == 2 && before.allSatisfy { $0.fadeOut }, "…the packet before each fades out")
    check(r.lateAfter(2) == 0, "…nothing late")
}

// A new epoch (another app): a new decoder, a clean start.
do {
    var w = World()
    w.seconds = 20
    w.epochs = [10]
    let r = simulate(w)
    noViolations(r, "a new epoch")
    check(r.packets.first { $0.epoch == 2 }?.seq == 0, "…its first packet plays, from seq 0")
    check(r.tails.last { $0.epoch == 1 }?.fadeOut == true, "…the old epoch's last fades out")
}

// A still window: no frames at all, and a picture that stops.
do {
    var w = World()
    w.videoFPS = 0
    let r = simulate(w)
    noViolations(r, "no picture at all")
    check(r.lateAfter(2) == 0, "…plays by the need alone")
    var w2 = World()
    w2.seconds = 25
    w2.videoTransit = { t in t > 10 ? 1000 : 0.004 }    // frames stop arriving at 10 s
    let r2 = simulate(w2)
    noViolations(r2, "a picture that stops (a still window)")
    let lags = r2.seconds.filter { $0.t > 13 }.compactMap(\.s.lag)
    check(Set(lags.map { Int(($0 * 1e6).rounded()) }).count == 1, "…the lag keeps its last value")
}

// A picture a second late: the guard decides, and the sound never leads it.
do {
    var w = World()
    w.videoTransit = { _ in 1.0 }
    let r = simulate(w)
    noViolations(r, "a picture a second late")
    let d = r.seconds.last!.s
    check(d.delay > 1.0 && (d.lag ?? 0) > 0.9, "…the delay follows the picture (\(ms(d.delay)))")
    check(r.packets.suffix(100).allSatisfy { $0.decision.ear - $0.decision.picture >= 1.0 / 60 - 0.0002 },
          "…the sound a frame behind it")
}

// The picture's lag rising fast (40 ms over 3 s): the guard's jump keeps the sound behind it.
do {
    var w = World()
    w.seconds = 25
    w.videoTransit = { t in 0.2 + (t > 10 ? min(0.040, (t - 10) * 0.013) : 0) }
    let r = simulate(w)
    noViolations(r, "the picture's lag rising fast")
}

// The output's latency changes: a route (a jump at once), and a drift (frames, 1.9 ms a second or better).
do {
    var w = World()
    w.seconds = 25
    w.routes = [(at: 8, outputLatency: 0.190), (at: 16, outputLatency: 0.010)]
    let r = simulate(w)
    noViolations(r, "a route change to AirPods and back")
    check(r.jumps(between: 7.5, 9) == 1 && r.jumps(between: 15.5, 17) == 1, "…one jump each way")
    check(r.lateAfter(2) == 0, "…nothing late")
    let err = r.errors.filter { $0.t > 10 && $0.t < 16 }.map { abs($0.e) }.max() ?? 1
    check(err < 0.002, "…placed where due at once (error \(ms(err)))")
}
// The error closed by frames: 1.9 ms a second or better while over 5 ms. The IO buffer shrinks by 30 or
// 35 ms with no reset (the sound is behind where it is now due), and one packet 18 ms over the window
// raises the cover (ahead, until the window forgets it and it is behind again).
func errorFalls(_ r: Run, from t0: Double) -> (ok: Bool, worst: Double, first: Double, last: Double) {
    let es = r.errors.filter { $0.t > t0 }.map { (t: $0.t, e: $0.e) }
    var ok = true, worst = 1.0
    for (a, b) in zip(es, es.dropFirst()) where abs(a.e) > 0.005 && (a.e > 0) == (b.e > 0) {
        let fell = abs(a.e) - abs(b.e)
        worst = min(worst, fell)
        if fell < 0.0019 { ok = false }
    }
    return (ok, worst, abs(es.first?.e ?? 0), abs(es.last?.e ?? 1))
}
for (shrink, F) in [(0.030, 480), (0.035, 512)] {
    var w = World()
    w.seconds = 40
    w.F = F; w.P = F / 2
    w.io = 0.005 + shrink
    w.ioAt = [(at: 10, io: 0.005)]
    let r = simulate(w)
    noViolations(r, "the IO buffer shrinks \(ms(shrink)) with no reset, \(F) frames a packet")
    let e = errorFalls(r, from: 10.9)
    check(e.ok && e.first > 0.02 && e.last < 0.005, "…the error (\(ms(e.first)) behind) falls \(ms(e.worst)) a second at worst while over 5 ms, and ends under it (\(ms(e.last)))")
    check(r.jumps(after: 10) == 0 && r.lateAfter(2) == 0, "…with no jump and nothing late")
}
for F in [480, 512] {
    var w = World()
    w.seconds = 40
    w.F = F; w.P = F / 2
    w.transit = { t in abs(t - 5) < 0.004 ? 0.021 : 0.003 }
    let r = simulate(w)
    noViolations(r, "one packet 18 ms over the window's largest, \(F) frames a packet")
    let e = errorFalls(r, from: 5.9)
    check(e.ok && e.last < 0.005, "…the error falls \(ms(e.worst)) a second at worst while over 5 ms, both ways, and ends under it (\(ms(e.last)))")
    check(r.jumps(after: 5) == 0 && r.lateAfter(2) == 0, "…with no jump and nothing late")
}

// Mute and unmute: nothing decoded meanwhile; unmuting plays again within about 0.1 s.
do {
    var w = World()
    w.seconds = 20
    w.engineStart = 0.030
    w.mutes = [(at: 6, muted: true), (at: 12, muted: false)]
    let r = simulate(w)
    noViolations(r, "mute and unmute")
    check(!r.played.contains { $0.scheduledAt > 6 && $0.scheduledAt < 12 }, "…nothing played while muted")
    let back = r.packets.first { $0.scheduledAt > 12 }
    check(back.map { $0.decision.ear - 12 < 0.2 } == true, "…sound again \(ms((back?.decision.ear ?? 99) - 12)) after unmuting")
    check(back?.fadeIn == true, "…faded in")
}

// The engine starting: the first packets wait for its first render; none plays late.
do {
    var w = World()
    w.engineStart = 0.080
    let r = simulate(w)
    noViolations(r, "the engine takes 80 ms to start")
    check(r.packets.count > 1500, "…and plays (\(r.packets.count))")
    check((r.packets.first?.seq ?? 99) < 8, "…from a packet that waited for it (seq \(r.packets.first?.seq ?? 99))")
    var w2 = World()
    w2.engineStart = 2.5
    let r2 = simulate(w2)
    noViolations(r2, "an engine that takes 2.5 s: what waits is capped at a second")
    check(r2.discarded.count >= 100, "…the oldest discarded (\(r2.discarded.count))")
}

// A packet late in the first 2 s (behind the connection's catalog and first keyframe).
do {
    var w = World()
    w.transit = { t in t < 0.1 ? 0.070 : 0.003 }
    let r = simulate(w)
    noViolations(r, "the first packets behind a keyframe")
    check(r.lateAfter(2) == 0, "…nothing late after 2 s")
}

// The need rises at once: a packet 70 ms late after the first 2 s is placed with it, not dropped.
do {
    var w = World()
    w.seconds = 12
    w.transit = { t in abs(t - 6) < 0.005 ? 0.073 : 0.003 }
    let r = simulate(w)
    noViolations(r, "one packet 70 ms late")
    check(r.lateAfter(2) == 0, "…nothing dropped as late: the cover rose with it (\(r.lateAfter(2)))")
}

// A path slower by 80 ms (over the 50 ms step): a step, then steady.
do {
    var w = World()
    w.seconds = 25
    w.transit = { t in t < 10 ? 0.003 : 0.083 }
    let r = simulate(w)
    noViolations(r, "the path 80 ms slower")
    check(r.jumps(between: 10, 13) >= 1, "…a jump (\(r.jumps(between: 10, 13)))")
    check(r.lateAfter(13) == 0 && r.jumps(after: 13) == 0, "…then steady")
    let cover = r.seconds.filter { $0.t > 13 && $0.t < 20 }.map(\.s.cover)
    check(cover.allSatisfy { $0 < 0.030 }, "…the floor started again, so the cover is small again (\(cover.map(ms).prefix(2)))")
}

// Half a second 60 ms slower (a slow keyframe) is no step: a second of packets is.
do {
    var w = World()
    w.seconds = 20
    w.transit = { t in t >= 10 && t < 10.5 ? 0.063 : 0.003 }
    let r = simulate(w)
    noViolations(r, "half a second 60 ms slower")
    check(r.jumps(between: 9, 20) == 0, "…no step and no jump (\(r.jumps(between: 9, 20)))")
    check(r.lateAfter(2) == 0, "…nothing late")
}

// The step's threshold follows the round trip: 2 × 40 ms is over a path 60 ms slower.
do {
    var w = World()
    w.seconds = 25
    w.rtt = 0.040
    w.transit = { t in t < 10 ? 0.003 : 0.063 }
    let r = simulate(w)
    noViolations(r, "a path 60 ms slower with an rtt of 40 ms")
    let cover = r.seconds.filter { $0.t > 13 && $0.t < 19 }.map(\.s.cover)
    check(cover.allSatisfy { $0 >= 0.058 }, "…no step: the cover takes it (\(cover.map(ms).prefix(2)))")
}

// A packet in hand with nothing after it: it goes out at its deadline, faded.
do {
    var w = World()
    w.seconds = 5
    w.transit = { t in t > 3 ? 100 : 0.003 }
    let r = simulate(w)
    noViolations(r, "the Mac stops sending")
    check(r.tails.last?.fadeOut == true, "…the last packet goes out at its deadline, faded")
}

// A decode that fails: silence in its place, and the next packet on a fresh decoder is dropped whole.
do {
    var w = World()
    w.decodeFails = [500]
    let r = simulate(w)
    noViolations(r, "a decode that fails")
    check(r.packet(501) == nil && r.packet(502)?.fadeIn == true, "…the next dropped, the one after faded in")
}

// The timeline read with ±0.2 ms of jitter: no flutter of frames.
do {
    var w = World()
    w.seconds = 30
    w.readingJitter = 0.0002
    let r = simulate(w)
    noViolations(r, "readings with ±0.2 ms of jitter")
    let changes = r.seconds.filter { $0.t > 15 }.reduce(0) { $0 + $1.s.framesAdded + $1.s.framesDropped }
    check(changes < 100, "…few frames changed once settled (\(changes))")
}

// A session reset: a reconnect starts afresh.
do {
    var m = AudioPlayout()
    _ = m.format(epoch: 5, framesPerPacket: 480, primingFrames: 240, cookie: Data([1]))
    _ = m.packet(epoch: 5, seq: 0, stamp: 0.99, segmentStart: true, now: 1)
    _ = m.reset(.session)
    check(m.floor == nil && m.epoch == nil, "a session reset: no floor, no epoch")
    check(m.format(epoch: 5, framesPerPacket: 480, primingFrames: 240, cookie: Data([1])), "…so the same epoch's format is a new decoder")
    let p = m.packet(epoch: 5, seq: 0, stamp: 0.99, segmentStart: true, now: 1.5)
    check(p.decode && p.id != nil, "…and a packet it saw before is no duplicate now")
    var d = AudioPlayout()
    _ = d.format(epoch: 1, framesPerPacket: 480, primingFrames: 240, cookie: Data())
    _ = d.packet(epoch: 1, seq: 0, stamp: 0.99, segmentStart: true, now: 1)
    for k in 1...300 { _ = d.packet(epoch: 1, seq: UInt32(k), stamp: Double(k) * 0.01 + 0.99, segmentStart: false, now: 1 + Double(k) * 0.01) }
    let old = d.packet(epoch: 1, seq: 1, stamp: 1.0, segmentStart: false, now: 5)
    check(old.decode, "a seq older than the last 256 is no longer a duplicate")
    let recent = d.packet(epoch: 1, seq: 299, stamp: 3.98, segmentStart: false, now: 5)
    check(!recent.decode, "one among them is")
    var wrap = AudioPlayout()
    _ = wrap.format(epoch: 65535, framesPerPacket: 480, primingFrames: 240, cookie: Data())
    let a = wrap.packet(epoch: 65535, seq: UInt32.max, stamp: 0.99, segmentStart: true, now: 1)
    let b = wrap.packet(epoch: 65535, seq: 0, stamp: 1.0, segmentStart: false, now: 1.01)
    check(a.id != nil && b.id != nil && !b.resetFirst, "the seq wraps without a reset")
    let orphan = wrap.packet(epoch: 3, seq: 5, stamp: 1, segmentStart: false, now: 1)
    check(!orphan.decode, "a packet of another epoch than the format's is skipped")
}

// Muted: each packet still counts for the floor, and nothing is decoded.
do {
    var m = AudioPlayout()
    _ = m.format(epoch: 1, framesPerPacket: 480, primingFrames: 240, cookie: Data())
    m.mute(true)
    let p = m.packet(epoch: 1, seq: 0, stamp: 0.99, segmentStart: true, now: 1)
    check(!p.decode && p.id == nil && m.floor != nil, "muted: the floor counts it, nothing decoded")
}

// MARK: - 5,000 random runs

var runs = 0, steadyRuns = 0, played = 0
var rng = RNG(20260927)
let total = Int(CommandLine.arguments.dropFirst().first ?? "") ?? 5000
for k in 0..<total {
    var w = World()
    w.label = "random \(k)"
    w.seconds = rng.range(4, 12)
    if rng.chance(0.3) { w.F = 512; w.P = 256 }
    w.outputLatency = rng.chance(0.2) ? rng.range(0.1, 2.0) : rng.range(0.003, 0.03)
    w.io = rng.range(0.002, 0.030)
    w.away = rng.chance(0.25)
    w.hostDrift = rng.range(-200e-6, 200e-6)
    w.outDrift = rng.range(-200e-6, 200e-6)
    w.videoFPS = rng.chance(0.2) ? 0 : (rng.chance(0.3) ? 120 : 60)
    w.streamFPS = w.videoFPS == 120 ? 120 : 60
    w.refresh = rng.chance(0.5) ? 1.0 / 60 : 1.0 / 120
    w.readingJitter = rng.chance(0.3) ? rng.range(0, 0.0005) : 0
    w.engineStart = rng.chance(0.3) ? rng.range(0, 0.2) : 0
    w.rtt = rng.chance(0.2) ? nil : rng.range(0.001, 0.2)
    let base = w.away ? rng.range(0.02, 0.2) : rng.range(0.001, 0.02)
    let jitter = rng.range(0, w.away ? 0.05 : 0.01)
    let seed = rng.next()
    var events = 0
    var burstEvery = 0.0, burstSize = 0.0, stallAt = -1.0, stallFor = 0.0, stepPath = -1.0, stepBy = 0.0
    if rng.chance(0.3) { burstEvery = rng.range(1, 5); burstSize = rng.range(0.01, 0.15); events += 1 }
    if rng.chance(0.15) { stallAt = rng.range(1, w.seconds); stallFor = rng.range(0.05, 2.5); events += 1 }
    if rng.chance(0.15) { stepPath = rng.range(1, w.seconds); stepBy = rng.range(-0.08, 0.12); events += 1 }
    let phase = rng.range(0, 100)
    w.transit = { t in
        var d = base + jitter * (0.5 + 0.5 * sin(t * 13.7 + phase)) * abs(sin(t * 3.1 + phase * 2))
        if burstEvery > 0 { let into = t.truncatingRemainder(dividingBy: burstEvery); if into < burstSize { d += burstSize - into } }
        if stallAt >= 0, t >= stallAt, t < stallAt + stallFor { d += stallAt + stallFor - t }
        if stepPath >= 0, t >= stepPath { d = max(0.0005, d + stepBy) }
        return d
    }
    if rng.chance(0.3) { let lag = rng.range(0, 1.0); w.videoTransit = { t in base + lag + 0.01 * sin(t) } }
    if rng.chance(0.15) { w.hostSteps = [(at: rng.range(1, w.seconds), by: rng.range(-1.5, 1.5))]; events += 1 }
    if rng.chance(0.2) { w.pauses = [(at: rng.range(0.5, w.seconds), pause: rng.range(0.02, 1.0))]; events += 1 }
    if rng.chance(0.1) { w.epochs = [rng.range(0.5, w.seconds)]; events += 1 }
    if rng.chance(0.15) { let s = rng.int(10, 500); w.skipped = Set(s..<(s + rng.int(1, 5))); events += 1 }
    if rng.chance(0.15) { let s = rng.int(10, 400); w.duplicate = (from: s, to: s + rng.int(0, 60), extra: rng.range(-0.05, 0.1)); events += 1 }
    if rng.chance(0.1) { w.joinAt = rng.int(1, 200) }
    if rng.chance(0.15) {
        let a = rng.range(0.5, w.seconds), b = a + rng.range(0.05, 3)
        w.mutes = [(at: a, muted: true), (at: b, muted: false)]; events += 1
    }
    if rng.chance(0.15) { w.routes = [(at: rng.range(0.5, w.seconds), outputLatency: rng.range(0.003, 0.3))]; events += 1 }
    if rng.chance(0.1) { w.drifts = [(at: rng.range(0.5, w.seconds), outputLatency: max(0.003, w.outputLatency + rng.range(-0.03, 0.03)))]; events += 1 }
    if w.away, rng.chance(0.2) { w.homeAt = rng.range(1, w.seconds); events += 1 }
    if rng.chance(0.05) { w.decodeFails = [rng.int(20, 300)]; events += 1 }
    let r = simulate(w, seed: seed)
    runs += 1
    played += r.packets.count
    if !r.violations.isEmpty {
        check(false, "\(w.label): \(r.violations.prefix(3).joined(separator: "; "))")
        if failures > 30 { break }
        continue
    }
    // A steady link: nothing late after its first 2 s, whatever the output latency and the IO buffer.
    if events == 0, jitter < (w.away ? 0.045 : 0.009), w.joinAt == nil, w.videoTransit == nil {
        steadyRuns += 1
        if r.lateAfter(2) != 0 { check(false, "\(w.label): a steady link lost \(r.lateAfter(2)) packets as late after 2 s") }
    }
}
check(failures == 0 || runs > 0, "\(runs) random runs, \(steadyRuns) of them on a steady link, \(played) packets played: every invariant held")

print("\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
