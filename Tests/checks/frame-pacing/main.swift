// FramePacing (Sources/SillHost/FramePacing.swift): the frames each device is sent at home and away, the keyframes asked
// for on a device's behalf and who is dropped (docs/steps/2026-11-24-home-backlog.md). Compiled by build.sh:
//   swiftc -O Sources/SillHost/FramePacing.swift Tests/checks/frame-pacing/main.swift
// Four parts: each rule at its edges; the rules as they were at main 644f03b8 (`oldHome`, `oldAway`, written out here)
// against the new ones, step by step on random inputs (away always the same; at home the same wherever the link
// carries the stream); FrameTimes and the lines; and a model of a connection in virtual time (1 ms steps): Sill's own
// queue, the kernel's send buffer, the link, the shared encoder, pongs and the sweep, which shows the backlog of
// issue #359 on the old home rule and none on the new one, the same decisions on fast links and away, the keyframes a
// slow device asks for spaced, and a dead link dropped once.
import Foundation

var failed = 0, passed = 0
func check(_ ok: Bool, _ what: String) {
    if ok { passed += 1; print("ok \(what)") } else { failed += 1; print("FAIL \(what)") }
}
/// A check that runs many times: one line, the first failure named.
func checkAll(_ name: String, _ n: Int, _ body: (Int) -> String?) {
    for i in 0..<n {
        if let why = body(i) { check(false, "\(name): \(why) (case \(i))"); return }
    }
    check(true, "\(name) (\(n) cases)")
}

typealias P = FramePacing
typealias State = FramePacing.State
typealias Queue = FramePacing.Queue
typealias Outcome = FramePacing.Outcome

/// SplitMix64: the same random runs every time.
struct Random {
    var s: UInt64
    mutating func next() -> UInt64 {
        s &+= 0x9E37_79B9_7F4A_7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    mutating func bool() -> Bool { next() & 1 == 1 }
    mutating func double(_ upTo: Double) -> Double { Double(next() % 1_000_000) / 1_000_000 * upTo }
}

func home(_ s: inout State, key: Bool = false, ps: Bool = true, bytes: Int = 0, messages: Int = 0, wait: Double = 0,
          now: Double = 100, due: Bool = true) -> Outcome {
    P.frame(away: false, keyframe: key, parameterSets: ps, state: &s, queue: Queue(bytes: bytes, messages: messages, oldestFrameWait: wait),
            now: now, due: due)
}
func away(_ s: inout State, key: Bool = false, ps: Bool = true, bytes: Int = 0, kfs: Int = 0, kfBytes: Int = 0,
          now: Double = 100, due: Bool = true) -> Outcome {
    P.frame(away: true, keyframe: key, parameterSets: ps, state: &s,
            queue: Queue(bytes: bytes, messages: 0, oldestFrameWait: 0, keyframesTaking: kfs, keyframeBytesTaking: kfBytes), now: now, due: due)
}
/// A device that has had its first keyframe and waits for nothing, as on a link that carries the stream.
func streaming(lastLoss: Double? = nil) -> State {
    State(needsKeyframe: false, awaitingFirstKeyframe: false, keyframeWanted: false, lastLossAt: lastLoss, backlogFloor: 0)
}
/// A device that waits for a keyframe after a loss.
func waiting(wanted: Bool = false, lastLoss: Double? = 99) -> State {
    State(needsKeyframe: true, awaitingFirstKeyframe: false, keyframeWanted: wanted, lastLossAt: lastLoss, backlogFloor: 0)
}

// MARK: - 1. At home

do {
    var s = streaming()
    var o = home(&s, messages: 2)
    check(o == Outcome(verdict: .sent) && s == streaming(), "home: a delta with two messages waiting goes")
    s = streaming()
    o = home(&s, messages: 3, now: 100)
    check(o == Outcome(verdict: .dropped, withheld: true, ask: .atOnce), "home: a delta with three waiting is dropped and its keyframe asked for at once (a one-off)")
    check(s.needsKeyframe && !s.keyframeWanted && s.lastLossAt == 100, "home: …and the device waits, its loss at 100, nothing left to ask")
    s = streaming()
    o = home(&s, key: true, messages: 9)
    check(o == Outcome(verdict: .sent) && !s.needsKeyframe, "home: a keyframe goes whatever the count of messages")
    s = streaming()
    o = home(&s, wait: 1.0)
    check(o == Outcome(verdict: .sent), "home: a delta goes while the oldest frame has waited exactly homeLate (1 s)")
    s = streaming()
    o = home(&s, wait: 1.001, now: 100)
    check(o == Outcome(verdict: .dropped, withheld: true) && s.needsKeyframe && s.keyframeWanted && s.lastLossAt == 100,
          "home: a delta behind a frame that waited 1.001 s is late: dropped, its keyframe asked for later")
    s = streaming()
    o = home(&s, key: true, wait: 1.5)
    check(o == Outcome(verdict: .dropped, withheld: true) && s.needsKeyframe && s.keyframeWanted,
          "home: a keyframe it did not ask for, late, is dropped too")
    s = streaming()
    o = home(&s, key: true, wait: 0.9)
    check(o == Outcome(verdict: .sent), "home: …but goes when not late")

    // A one-off: no loss in the last homeCalmAfter (2 s).
    s = streaming(lastLoss: 98)
    o = home(&s, messages: 3, now: 100)
    check(o.ask == .atOnce && !s.keyframeWanted, "home: a loss 2 s after the last one is a one-off: asked for at once")
    s = streaming(lastLoss: 98.001)
    o = home(&s, messages: 3, now: 100)
    check(o == Outcome(verdict: .dropped, withheld: true) && s.keyframeWanted && s.lastLossAt == 100,
          "home: a loss 1.999 s after the last is a link that cannot carry the stream: no ask now, one wanted")
    s = streaming()
    o = home(&s, messages: 3, wait: 1.5)
    check(o.ask == nil && s.keyframeWanted, "home: a first loss that is late asks later, not at once")
    check(P.calm(streaming(), now: 0) && P.calm(streaming(lastLoss: 10), now: 12) && !P.calm(streaming(lastLoss: 10), now: 11.99),
          "calm: none lost, or the last loss 2 s ago or more")

    // Waiting for a keyframe.
    s = waiting(wanted: false, lastLoss: 50)
    o = home(&s, now: 100)
    check(o == Outcome(verdict: .waiting, withheld: true) && s.lastLossAt == 100, "home: a delta while it waits is withheld, counted, a loss")
    s = waiting(wanted: true)
    o = home(&s, bytes: 16 * 1024, due: true)
    check(o == Outcome(verdict: .waiting, withheld: true, ask: .spaced) && !s.keyframeWanted,
          "home: waiting with one wanted, 16 KB queued and a request due: asked for, spaced")
    s = waiting(wanted: true)
    o = home(&s, bytes: 16 * 1024 + 1, due: true)
    check(o.ask == nil && s.keyframeWanted, "home: …not with 16 KB + 1 queued")
    s = waiting(wanted: true)
    o = home(&s, bytes: 0, due: false)
    check(o.ask == nil && s.keyframeWanted, "home: …nor before a request is due")
    s = waiting(wanted: false)
    o = home(&s, bytes: 0, due: true)
    check(o.ask == nil, "home: …nor when none is wanted (it asked at once)")
    s = waiting(wanted: true)
    o = home(&s, key: true, bytes: 900_000, messages: 9, wait: 0.5)
    check(o == Outcome(verdict: .sent, parameterSets: true) && !s.needsKeyframe && !s.awaitingFirstKeyframe,
          "home: the keyframe it waits for goes with the parameter sets while not late, whatever the bytes")
    s = waiting(wanted: false, lastLoss: 50)
    o = home(&s, key: true, wait: 1.5, now: 100)
    check(o == Outcome(verdict: .waiting, withheld: true) && s.needsKeyframe && s.keyframeWanted && s.lastLossAt == 100,
          "home: the keyframe it waits for, late: withheld, and wanted again once the queue drains")
    s = waiting(wanted: false)
    o = home(&s, key: true, ps: false)
    check(o == Outcome(verdict: .waiting, withheld: true) && s.needsKeyframe, "home: a keyframe without parameter sets is waited past, as a delta")

    // The first keyframe since it was admitted or the stream changed.
    s = State()
    o = home(&s, now: 100)
    check(o == Outcome(verdict: .waiting) && s.lastLossAt == nil, "home: before its first keyframe a delta is withheld, not counted, no loss")
    s = State(needsKeyframe: true, awaitingFirstKeyframe: true, keyframeWanted: true, lastLossAt: nil, backlogFloor: 0)
    o = home(&s, bytes: 0, due: true)
    check(o.ask == nil && s.keyframeWanted, "home: no request while it waits for its first (the coordinator asked)")
    s = State()
    o = home(&s, key: true, bytes: 9_000_000, messages: 40, wait: 30)
    check(o == Outcome(verdict: .sent, parameterSets: true) && !s.needsKeyframe && !s.awaitingFirstKeyframe,
          "home: its first keyframe goes at once, however late")
}

// MARK: - 2. Away (paceRemote until 2026-11-24)

do {
    var s = State(needsKeyframe: false, awaitingFirstKeyframe: false, keyframeWanted: false, lastLossAt: nil, backlogFloor: 500_000)
    var o = away(&s, bytes: 200_000)
    check(o == Outcome(verdict: .sent) && s.backlogFloor == 200_000, "away: the floor follows the backlog down")
    s = State(needsKeyframe: false, awaitingFirstKeyframe: false, keyframeWanted: false, lastLossAt: nil, backlogFloor: 0)
    o = away(&s, bytes: 256 * 1024)
    check(o == Outcome(verdict: .sent), "away: 256 KB queued: the frame goes")
    o = away(&s, bytes: 256 * 1024 + 1)
    check(o == Outcome(verdict: .dropped, withheld: true) && s.needsKeyframe && s.keyframeWanted, "away: 256 KB + 1: dropped, one wanted, no ask")
    s = State(needsKeyframe: false, awaitingFirstKeyframe: false, keyframeWanted: false, lastLossAt: nil, backlogFloor: 300_000)
    o = away(&s, bytes: 300_000 + 128 * 1024)
    check(o == Outcome(verdict: .sent), "away: within the floor and 128 KB of slack: goes")
    s = State(needsKeyframe: false, awaitingFirstKeyframe: false, keyframeWanted: false, lastLossAt: nil, backlogFloor: 300_000)
    o = away(&s, bytes: 300_000 + 128 * 1024 + 1)
    check(o.verdict == .dropped, "away: past the floor and its slack: dropped")
    s = State(needsKeyframe: false, awaitingFirstKeyframe: false, keyframeWanted: false, lastLossAt: nil, backlogFloor: 0)
    o = away(&s, bytes: 1_500_000 + 512 * 1024, kfs: 1, kfBytes: 1_500_000)
    check(o == Outcome(verdict: .sent), "away: behind a keyframe being taken, 512 KB beyond it: goes")
    o = away(&s, bytes: 1_500_000 + 512 * 1024 + 1, kfs: 1, kfBytes: 1_500_000)
    check(o.verdict == .dropped, "away: 512 KB + 1 beyond it: dropped")
    s = State(needsKeyframe: false, awaitingFirstKeyframe: false, keyframeWanted: false, lastLossAt: nil, backlogFloor: 0)
    o = away(&s, key: true, bytes: 300_000)
    check(o.verdict == .dropped, "away: a keyframe it did not ask for over the budget is dropped as a delta is")
    s = State(needsKeyframe: true, awaitingFirstKeyframe: false, keyframeWanted: true, lastLossAt: nil, backlogFloor: 0)
    o = away(&s, bytes: 16 * 1024, due: true)
    check(o == Outcome(verdict: .waiting, withheld: true, ask: .spaced) && !s.keyframeWanted, "away: waiting, drained to 16 KB, due: asked for")
    s = State(needsKeyframe: true, awaitingFirstKeyframe: false, keyframeWanted: true, lastLossAt: nil, backlogFloor: 0)
    o = away(&s, bytes: 16 * 1024 + 1, due: true)
    check(o.ask == nil, "away: …not at 16 KB + 1")
    s = State(needsKeyframe: true, awaitingFirstKeyframe: true, keyframeWanted: true, lastLossAt: nil, backlogFloor: 0)
    o = away(&s, bytes: 0, due: true)
    check(o == Outcome(verdict: .waiting, withheld: false, ask: .spaced), "away: a request even while it waits for its first, as paceRemote made")
    s = State(needsKeyframe: true, awaitingFirstKeyframe: false, keyframeWanted: false, lastLossAt: nil, backlogFloor: 0)
    o = away(&s, key: true, bytes: 256 * 1024)
    check(o == Outcome(verdict: .sent, parameterSets: true) && !s.needsKeyframe, "away: the keyframe it waits for, 256 KB queued: goes")
    s = State(needsKeyframe: true, awaitingFirstKeyframe: false, keyframeWanted: false, lastLossAt: nil, backlogFloor: 0)
    o = away(&s, key: true, bytes: 256 * 1024 + 1)
    check(o == Outcome(verdict: .waiting, withheld: true) && s.keyframeWanted, "away: …256 KB + 1: withheld, wanted again")
    s = State()
    o = away(&s, key: true, bytes: 5_000_000)
    check(o == Outcome(verdict: .sent, parameterSets: true), "away: its first keyframe at once")
    s = State()
    o = away(&s, key: true, ps: false)
    check(o == Outcome(verdict: .waiting, withheld: true) && s.keyframeWanted, "away: a keyframe without parameter sets: withheld and counted")
}

// MARK: - 3. The rules as they were at main 644f03b8, against the new ones

/// StreamServer.broadcast's home branch at main 644f03b8, one frame for one device.
func oldHome(keyframe: Bool, parameterSets: Bool, state s: inout State, queue q: Queue) -> Outcome {
    if s.needsKeyframe {
        guard keyframe, parameterSets else { return Outcome(verdict: .waiting, withheld: !s.awaitingFirstKeyframe) }
        s.needsKeyframe = false
        s.awaitingFirstKeyframe = false
        return Outcome(verdict: .sent, parameterSets: true)
    } else if q.messages > 2 && !keyframe {
        s.needsKeyframe = true
        return Outcome(verdict: .dropped, withheld: true, ask: .atOnce)
    }
    return Outcome(verdict: .sent)
}

/// StreamServer.paceRemote at main 644f03b8, with its constants as numbers.
func oldAway(keyframe: Bool, parameterSets: Bool, state s: inout State, queue q: Queue, due: Bool) -> Outcome {
    s.backlogFloor = min(s.backlogFloor, q.bytes)
    if s.needsKeyframe {
        guard keyframe else {
            var ask: Outcome.Ask?
            if s.keyframeWanted, q.bytes <= 16 * 1024, due { s.keyframeWanted = false; ask = .spaced }
            return Outcome(verdict: .waiting, withheld: !s.awaitingFirstKeyframe, ask: ask)
        }
        guard s.awaitingFirstKeyframe || q.bytes <= 256 * 1024, parameterSets else {
            s.keyframeWanted = true
            return Outcome(verdict: .waiting, withheld: true)
        }
        s.needsKeyframe = false
        s.awaitingFirstKeyframe = false
        return Outcome(verdict: .sent, parameterSets: true)
    }
    let tooMuch = q.keyframesTaking > 0 ? q.bytes - q.keyframeBytesTaking > 512 * 1024
                                        : q.bytes > max(256 * 1024, s.backlogFloor + 128 * 1024)
    if tooMuch {
        s.needsKeyframe = true
        s.keyframeWanted = true
        return Outcome(verdict: .dropped, withheld: true)
    }
    return Outcome(verdict: .sent)
}

/// StreamServer.remoteKeyframeDue at main 644f03b8.
func oldDue(now: Double, last: Double, lastKeyframeAt: Double, home: Bool) -> Bool {
    guard home else { return now - last >= 2 }
    return now - last >= 4 && now - lastKeyframeAt >= 4
}

do {
    var r = Random(s: 359)
    // Byte counts near every edge: the budget, the slack, the hold cap, the idle mark.
    func bytes() -> Int {
        let edges = [0, 16 * 1024, 256 * 1024, 384 * 1024, 512 * 1024, 900_000, 1_600_000]
        return max(0, edges[r.int(edges.count)] + r.int(3) - 1 + (r.bool() ? r.int(200_000) : 0))
    }
    checkAll("away: the same as paceRemote, step by step from random states", 300_000) { i in
        var s = State(needsKeyframe: r.bool(), awaitingFirstKeyframe: r.bool(), keyframeWanted: r.bool(),
                      lastLossAt: r.bool() ? nil : r.double(100), backlogFloor: bytes())
        var t = s
        let kfs = r.int(3), q = Queue(bytes: bytes(), messages: r.int(6), oldestFrameWait: r.double(40), keyframesTaking: kfs,
                                      keyframeBytesTaking: kfs == 0 ? 0 : r.int(2_000_000))
        let key = r.bool(), ps = r.int(10) > 0, due = r.bool()
        let new = P.frame(away: true, keyframe: key, parameterSets: ps, state: &s, queue: q, now: r.double(100), due: due)
        let old = oldAway(keyframe: key, parameterSets: ps, state: &t, queue: q, due: due)
        return new == old && s == t ? nil : "\(new) against \(old)"
    }
    checkAll("home: the same as before wherever the link carries the stream (no frame late, no loss within 2 s)", 300_000) { _ in
        let now = 100.0
        var s = State(needsKeyframe: r.bool(), awaitingFirstKeyframe: r.bool(), keyframeWanted: false,
                      lastLossAt: r.bool() ? nil : now - 2 - r.double(50), backlogFloor: 0)
        if !s.needsKeyframe { s.awaitingFirstKeyframe = false }
        var t = s
        let q = Queue(bytes: bytes(), messages: r.int(7), oldestFrameWait: r.double(1))
        let key = r.bool(), ps = r.int(10) > 0
        let new = P.frame(away: false, keyframe: key, parameterSets: ps, state: &s, queue: q, now: now, due: r.bool())
        let old = oldHome(keyframe: key, parameterSets: ps, state: &t, queue: q)
        let same = new == old && s.needsKeyframe == t.needsKeyframe && s.awaitingFirstKeyframe == t.awaitingFirstKeyframe
            && !s.keyframeWanted
        return same ? nil : "\(new) against \(old)"
    }
    checkAll("the spacing: the same as remoteKeyframeDue with a home client as `beside`", 100_000) { _ in
        let now = 100.0, last = now - r.double(8), kf = now - r.double(8), beside = r.bool()
        return P.keyframeDue(now: now, lastRequest: last, lastKeyframeAt: kf, beside: beside)
            == oldDue(now: now, last: last, lastKeyframeAt: kf, home: beside) ? nil : "differs at \(now - last), \(now - kf)"
    }
}

// MARK: - 4. The spacing, the sweep, the ceiling, the lines, FrameTimes

do {
    check(P.keyframeDue(now: 10, lastRequest: 8, lastKeyframeAt: 9.9, beside: false), "spacing: alone, 2 s after the last request, whatever the last keyframe")
    check(!P.keyframeDue(now: 10, lastRequest: 8.001, lastKeyframeAt: 0, beside: false), "spacing: alone, not at 1.999 s")
    check(P.keyframeDue(now: 10, lastRequest: 6, lastKeyframeAt: 6, beside: true), "spacing: beside a calm device, 4 s after both")
    check(!P.keyframeDue(now: 10, lastRequest: 6.001, lastKeyframeAt: 0, beside: true), "spacing: beside, not 3.999 s after the request")
    check(!P.keyframeDue(now: 10, lastRequest: 0, lastKeyframeAt: 6.001, beside: true), "spacing: beside, not 3.999 s after any keyframe")

    check(P.asksAtSweep(waiting(wanted: true), Queue(bytes: 16 * 1024)), "sweep: waiting, wanted, drained to 16 KB: asks")
    check(!P.asksAtSweep(waiting(wanted: true), Queue(bytes: 16 * 1024 + 1)), "sweep: not at 16 KB + 1")
    check(!P.asksAtSweep(waiting(wanted: false), Queue()), "sweep: not when none is wanted")
    check(!P.asksAtSweep(streaming(), Queue()), "sweep: not when it waits for nothing")
    check(!P.asksAtSweep(State(needsKeyframe: true, awaitingFirstKeyframe: true, keyframeWanted: true, lastLossAt: nil, backlogFloor: 0), Queue()),
          "sweep: not while it waits for its first keyframe")

    let big = Queue(bytes: 64 << 20)
    check(P.eviction(away: false, connectedFor: 8, noFrameTakenFor: nil, queue: big) == nil, "ceiling: 64 MiB queued is not past it")
    let over = Queue(bytes: (64 << 20) + 1, oldestFrameWait: 2.5)
    check(P.eviction(away: false, connectedFor: 0, noFrameTakenFor: nil, queue: over) == .tooFarBehind(bytes: (64 << 20) + 1, wait: 2.5),
          "ceiling: 64 MiB + 1 drops it at once, in its grace too")
    check(P.eviction(away: true, connectedFor: 1, noFrameTakenFor: nil, queue: over) != nil, "ceiling: the same away")
    check(P.eviction(away: false, connectedFor: 8, noFrameTakenFor: 100, queue: Queue(oldestFrameWait: 100)) == nil, "home: nothing within the 8 s grace")
    check(P.eviction(away: false, connectedFor: 8.01, noFrameTakenFor: 4.0, queue: Queue()) == nil, "home: no frame taken for exactly 4 s: kept")
    check(P.eviction(away: false, connectedFor: 8.01, noFrameTakenFor: 4.01, queue: Queue()) == .notDraining(seconds: 4), "home: 4.01 s: not draining")
    check(P.eviction(away: false, connectedFor: 9, noFrameTakenFor: 0.5, queue: Queue(oldestFrameWait: 10)) == nil, "home: the oldest frame 10 s: kept")
    check(P.eviction(away: false, connectedFor: 9, noFrameTakenFor: 0.5, queue: Queue(bytes: 1234, oldestFrameWait: 10.01))
          == .tooFarBehind(bytes: 1234, wait: 10.01), "home: 10.01 s: too far behind, though frames are taken")
    check(P.eviction(away: false, connectedFor: 9, noFrameTakenFor: 5, queue: Queue(oldestFrameWait: 20)) == .notDraining(seconds: 5),
          "home: not draining said first when both hold")
    check(P.eviction(away: true, connectedFor: 15, noFrameTakenFor: 100, queue: Queue(oldestFrameWait: 100)) == nil, "away: nothing within the 15 s grace")
    check(P.eviction(away: true, connectedFor: 15.01, noFrameTakenFor: 15, queue: Queue()) == nil, "away: no frame taken for 15 s: kept")
    check(P.eviction(away: true, connectedFor: 15.01, noFrameTakenFor: 15.01, queue: Queue()) == .notDraining(seconds: 15), "away: 15.01 s: not draining")
    check(P.eviction(away: true, connectedFor: 16, noFrameTakenFor: 1, queue: Queue(oldestFrameWait: 10.01)) == nil, "away: home's 10 s is nothing away")
    check(P.eviction(away: true, connectedFor: 16, noFrameTakenFor: 1, queue: Queue(oldestFrameWait: 30)) == nil, "away: the oldest frame 30 s: kept")
    check(P.eviction(away: true, connectedFor: 16, noFrameTakenFor: 1, queue: Queue(oldestFrameWait: 30.01)) != nil, "away: 30.01 s: too far behind")

    check(P.line(.notDraining(seconds: 4), endpoint: "192.168.1.20:52114") == "Client not draining for 4 s, dropping: 192.168.1.20:52114",
          "line: not draining, word for word as since the first commit")
    check(P.line(.tooFarBehind(bytes: 67_200_000, wait: 12.7), endpoint: "127.0.0.1:5")
          == "Client too far behind (67.2 MB queued for it, its oldest frame waiting 12 s), dropping: 127.0.0.1:5", "line: too far behind")
    check(P.megabytes(0) == "0.0 MB" && P.megabytes(949_999) == "0.9 MB" && P.megabytes(950_000) == "1.0 MB" && P.megabytes(12_168_600_000) == "12168.6 MB",
          "megabytes: tenths of 10^6 bytes")

    var f = P.FrameTimes()
    check(f.count == 0 && f.oldestWait(now: 5) == 0, "frame times: none waiting: 0")
    f.handed(at: 1); f.handed(at: 2)
    check(f.count == 2 && f.oldestWait(now: 5) == 4, "frame times: the oldest of two, 4 s")
    f.taken()
    check(f.count == 1 && f.oldestWait(now: 5) == 3, "frame times: taken in order, the next is the oldest")
    f.taken(); f.taken()
    check(f.count == 0 && f.oldestWait(now: 5) == 0, "frame times: a taken too many changes nothing")
    check(f.oldestWait(now: 0.5) == 0, "frame times: never negative")
    var r = Random(s: 427)
    var g = P.FrameTimes(), ref: [Double] = []
    var clock = 0.0
    checkAll("frame times: against a plain array, 50,000 random hand-overs and takes", 50_000) { _ in
        clock += r.double(0.01)
        if r.int(3) > 0 || ref.isEmpty { g.handed(at: clock); ref.append(clock) } else { g.taken(); ref.removeFirst() }
        let want = ref.first.map { clock - $0 } ?? 0
        return g.count == ref.count && abs(g.oldestWait(now: clock) - want) < 1e-9 ? nil : "count \(g.count)/\(ref.count)"
    }
}

// MARK: - 5. The model: a connection in virtual time

/// One device's connection: Sill's own queue (messages handed over and not taken), the kernel's send buffer of
/// `kernel` bytes and a link of `rate` bytes a second behind it. A message is taken (`.contentProcessed`) once its last
/// byte is in the kernel's buffer; a frame is shown once its last byte has crossed the link. Sill's counts are kept as
/// StreamServer keeps them.
final class Device {
    struct Message { let bytes: Int; var left: Int; let frame: Bool; let keyframe: Bool; let stamp: Double; let seq: Int }
    let name: String, away: Bool, kernel: Int
    var rate: Double
    var changes: [(t: Double, mbps: Double)]
    var sill: [Message] = [], sillHead = 0
    var chunks: [(left: Int, stamp: Double?, keyframe: Bool)] = [], chunkHead = 0
    var kernelBytes = 0, credit = 0.0
    // Sill's counts (StreamServer.Client)
    var pending = 0, messages = 0, inflightFrames = 0, seq = 0
    var oldestUnacked: Double?
    var times = P.FrameTimes()
    var keyframesTaking: [(seq: Int, bytes: Int)] = [], keyframeBytesTaking = 0
    var state = State()
    var connectedAt = 0.0
    var evicted: (t: Double, why: P.Eviction)?
    // What it saw
    var maxPending = 0, maxWait = 0.0
    var shown: [(t: Double, age: Double, keyframe: Bool)] = []
    var sent = 0, dropped = 0, waited = 0
    var decisions: [String] = []

    init(_ name: String, away: Bool = false, mbps: Double, kernel: Int = 512 * 1024, changes: [(t: Double, mbps: Double)] = []) {
        self.name = name; self.away = away; self.kernel = kernel; rate = mbps * 1e6 / 8; self.changes = changes
    }
    func queue(_ t: Double) -> Queue {
        Queue(bytes: pending, messages: messages, oldestFrameWait: times.oldestWait(now: t), keyframesTaking: keyframesTaking.count,
              keyframeBytesTaking: keyframeBytesTaking)
    }
    func hand(_ bytes: Int, at t: Double, frame: Bool = false, keyframe: Bool = false) {
        seq += 1
        pending += bytes; messages += 1
        if frame {
            inflightFrames += 1
            if oldestUnacked == nil { oldestUnacked = t }
            times.handed(at: t)
        }
        if away && keyframe { keyframesTaking.append((seq, bytes)); keyframeBytesTaking += bytes }
        sill.append(Message(bytes: bytes, left: bytes, frame: frame, keyframe: keyframe, stamp: t, seq: seq))
    }
    private func taken(_ m: Message, at t: Double) {
        pending -= m.bytes; messages -= 1
        if away, m.keyframe, let i = keyframesTaking.firstIndex(where: { $0.seq == m.seq }) {
            keyframeBytesTaking -= keyframesTaking.remove(at: i).bytes
            if keyframesTaking.isEmpty { state.backlogFloor = pending }
        }
        if m.frame {
            times.taken()
            inflightFrames -= 1
            oldestUnacked = inflightFrames > 0 ? t : nil
        }
    }
    func step(_ t: Double, _ dt: Double) {
        while let c = changes.first, t >= c.t { rate = c.mbps * 1e6 / 8; changes.removeFirst() }
        credit += rate * dt
        while credit >= 1, chunkHead < chunks.count {
            let n = min(Int(credit), chunks[chunkHead].left)
            chunks[chunkHead].left -= n; kernelBytes -= n; credit -= Double(n)
            if chunks[chunkHead].left == 0 {
                if let stamp = chunks[chunkHead].stamp { shown.append((t, t - stamp, chunks[chunkHead].keyframe)) }
                chunkHead += 1
            }
        }
        if chunkHead == chunks.count { credit = min(credit, rate * dt) }   // an idle link banks nothing
        var room = kernel - kernelBytes
        while room > 0, sillHead < sill.count {
            let n = min(room, sill[sillHead].left)
            sill[sillHead].left -= n; kernelBytes += n; room -= n
            let m = sill[sillHead]
            chunks.append((n, m.left == 0 && m.frame ? m.stamp : nil, m.keyframe))
            if m.left == 0 { taken(m, at: t); sillHead += 1 }
        }
        if sillHead > 4096, sillHead * 2 > sill.count { sill.removeFirst(sillHead); sillHead = 0 }
        if chunkHead > 4096, chunkHead * 2 > chunks.count { chunks.removeFirst(chunkHead); chunkHead = 0 }
        maxPending = max(maxPending, pending)
        maxWait = max(maxWait, times.oldestWait(now: t))
    }
    func ages(_ a: Double, _ b: Double) -> [Double] { shown.filter { $0.t >= a && $0.t < b }.map { $0.age } }
    func worstAge(_ a: Double, _ b: Double) -> Double { ages(a, b).max() ?? .nan }
    func fps(_ a: Double, _ b: Double) -> Double { Double(ages(a, b).count) / (b - a) }
}

/// The host: one encoder for every device (a keyframe when one was asked for since the last frame, or after `gop`
/// seconds), the parameter sets before each keyframe, every device's pongs, the sweep once a second. `new`: FramePacing
/// as StreamServer calls it; otherwise the rules at main 644f03b8 (`oldHome`, `oldAway`, the drain backstop at a
/// frame's send, the sweep's requests for remote devices only).
final class Model {
    let new: Bool, devices: [Device], fps: Double, kf: Int, delta: Int, gop: Double
    var askPending = true, lastKey = -100.0
    var lastKeyframeAt = 0.0, lastRemote = 0.0, lastHome = 0.0
    var encoded = 0, keyframeTimes: [Double] = [], frameTimes: [Double] = []
    var atOnce: [Double] = [], spaced: [Double] = [], swept: [Double] = []
    var stills: [(t: Double, d: Double)] = []
    init(new: Bool, _ devices: [Device], fps: Double = 60, kf: Int, delta: Int, gop: Double = 4) {
        self.new = new; self.devices = devices; self.fps = fps; self.kf = kf; self.delta = delta; self.gop = gop
    }
    var live: [Device] { devices.filter { $0.evicted == nil } }

    func due(_ d: Device, _ t: Double) -> Bool {
        if d.away {
            let home = devices.contains { !$0.away && $0.evicted == nil }
            return new ? P.keyframeDue(now: t, lastRequest: lastRemote, lastKeyframeAt: lastKeyframeAt, beside: home)
                       : oldDue(now: t, last: lastRemote, lastKeyframeAt: lastKeyframeAt, home: home)
        }
        let beside = devices.contains { $0 !== d && !$0.away && $0.evicted == nil && P.calm($0.state, now: t) }
        return P.keyframeDue(now: t, lastRequest: lastHome, lastKeyframeAt: lastKeyframeAt, beside: beside)
    }
    func evict(_ d: Device, _ t: Double) -> Bool {
        guard new, let why = P.eviction(away: d.away, connectedFor: t - d.connectedAt, noFrameTakenFor: d.oldestUnacked.map { t - $0 },
                                         queue: d.queue(t)) else { return false }
        d.evicted = (t, why)
        return true
    }
    func frame(_ t: Double) {
        let key = askPending || t - lastKey >= gop
        askPending = false
        encoded += 1
        frameTimes.append(t)
        if key { lastKey = t; lastKeyframeAt = t; keyframeTimes.append(t) }
        if key { for d in live { d.hand(100, at: t) } }   // the parameter sets, broadcast
        var ask = false
        for d in live {
            if evict(d, t) { continue }
            let o: Outcome
            if new {
                o = P.frame(away: d.away, keyframe: key, parameterSets: true, state: &d.state, queue: d.queue(t), now: t, due: due(d, t))
            } else if d.away {
                o = oldAway(keyframe: key, parameterSets: true, state: &d.state, queue: d.queue(t), due: due(d, t))
            } else {
                o = oldHome(keyframe: key, parameterSets: true, state: &d.state, queue: d.queue(t))
            }
            d.decisions.append("\(encoded) \(o)")
            switch o.verdict {
            case .sent:
                if !new, let oldest = d.oldestUnacked, t - oldest > (d.away ? 15 : 4), t - d.connectedAt > (d.away ? 15 : 8) {
                    d.evicted = (t, .notDraining(seconds: Int(t - oldest)))   // the old backstop, at a frame's send
                    continue
                }
                if o.parameterSets { d.hand(100, at: t) }
                d.hand(key ? kf : delta, at: t, frame: true, keyframe: key)
                d.sent += 1
            case .dropped: d.dropped += 1
            case .waiting: d.waited += 1
            }
            guard let a = o.ask else { continue }
            ask = true
            if a == .atOnce { atOnce.append(t) } else {
                spaced.append(t)
                if d.away { lastRemote = t } else { lastHome = t }
            }
        }
        if ask { askPending = true }
    }
    func sweep(_ t: Double) {
        var awayWaiting: [Device] = [], homeWaiting: [Device] = []
        for d in live {
            if evict(d, t) { continue }
            if P.asksAtSweep(d.state, d.queue(t)) { if d.away { awayWaiting.append(d) } else { homeWaiting.append(d) } }
        }
        var ask = false
        if let first = awayWaiting.first, due(first, t) {
            lastRemote = t
            for d in awayWaiting { d.state.keyframeWanted = false }
            ask = true
        }
        if new, homeWaiting.contains(where: { due($0, t) }) {
            lastHome = t
            for d in homeWaiting { d.state.keyframeWanted = false }
            ask = true
        }
        if ask { swept.append(t); askPending = true }
    }
    @discardableResult
    func run(_ seconds: Double) -> Model {
        var lastFrame = -1
        for i in 0..<Int(seconds * 1000) {
            let t = Double(i) / 1000
            for d in live { d.step(t, 0.001) }
            let f = Int(Double(i) * fps / 1000)
            if f > lastFrame {
                lastFrame = f
                if let spell = stills.first(where: { t >= $0.t && t < $0.t + $0.d }) {
                    // A keyframe asked for while the window is still: its last frame encoded again, once still for 50 ms.
                    if askPending, t - spell.t >= 0.05 { frame(t) }
                } else {
                    frame(t)
                }
            }
            if i % 250 == 0 { for d in live { d.hand(22, at: t) } }   // a pong
            if i % 1000 == 0, i > 0 { sweep(t) }
        }
        return self
    }
    func keyframesPerMinute(_ a: Double, _ b: Double) -> Double {
        Double(keyframeTimes.filter { $0 >= a && $0 < b }.count) * 60 / (b - a)
    }
    /// Every still spell: within `within` of its start the device shows the last frame before it, or a later one (the
    /// last encoded again), as the pacing harness's stillend gate asks.
    func stillsCaughtUp(_ d: Device, within: Double) -> Bool {
        stills.allSatisfy { spell in
            guard let last = frameTimes.last(where: { $0 < spell.t }) else { return true }
            return d.shown.contains { $0.t <= spell.t + within && $0.t - $0.age >= last - 1e-9 }
        }
    }
    var minSpacedGap: Double {
        let all = (spaced + swept).sorted()
        return zip(all, all.dropFirst()).map { $1 - $0 }.min() ?? .infinity
    }
}

func both(_ make: () -> [Device], fps: Double = 60, kf: Int, delta: Int, gop: Double = 4, seconds: Double = 60) -> (old: Model, new: Model) {
    (Model(new: false, make(), fps: fps, kf: kf, delta: delta, gop: gop).run(seconds),
     Model(new: true, make(), fps: fps, kf: kf, delta: delta, gop: gop).run(seconds))
}
func mb(_ n: Int) -> String { String(format: "%.2f MB", Double(n) / 1e6) }
func s(_ x: Double) -> String { String(format: "%.2f s", x) }

let K = 512 * 1024
do {
    // Issue #359's case, one connection: Balanced-sized frames at 60 fps on a 6 Mbit/s link at home.
    let (old, new) = both({ [Device("ipad", mbps: 6)] }, kf: 100_000, delta: 25_000)
    let o = old.devices[0], n = new.devices[0]
    print("   model, 6 Mbit/s, old: \(mb(o.pending)) queued at 60 s, frame age \(s(o.worstAge(50, 60))) at the end, "
          + "keyframes \(Int(old.keyframesPerMinute(0, 60)))/min, sent \(o.sent) dropped \(o.dropped)")
    print("   model, 6 Mbit/s, new: at most \(mb(n.maxPending)) queued, oldest frame \(s(n.maxWait)), frame age \(s(n.worstAge(50, 60))) "
          + "at the end, keyframes \(Int(new.keyframesPerMinute(0, 60)))/min, \(String(format: "%.1f", n.fps(10, 60))) fps shown")
    check(o.pending > 50_000_000 && o.worstAge(50, 60) > 30 && o.worstAge(50, 60) > o.worstAge(20, 30) + 15,
          "model, old home rule on 6 Mbit/s: the backlog grows without bound (issue #359)")
    check(abs(o.sent - o.dropped) < o.sent / 10 && old.keyframesPerMinute(10, 60) > 1500,
          "model, old home rule: sent ≈ dropped and half the frames keyframes, as the reporter's log")
    check(n.maxPending < 400_000 && n.maxWait < 0.5, "model, new: Sill's queue stays under 400 KB, its oldest frame under 0.5 s")
    check(n.worstAge(0, 60) < 1.5 && abs(n.worstAge(50, 60) - n.worstAge(20, 30)) < 0.3, "model, new: the frame age settles under 1.5 s")
    check(new.keyframesPerMinute(0, 60) <= 33 && new.minSpacedGap >= 2, "model, new: a keyframe asked for at most every 2 s")
    check(n.fps(10, 60) > 15 && n.evicted == nil, "model, new: frames keep coming (over 15 a second), nobody dropped")
}
do {
    // Five connections from one device (the reporter's), each on its own 4–9 Mbit/s.
    let rates = [4.0, 5.0, 6.0, 7.0, 9.0]
    let (old, new) = both({ rates.enumerated().map { Device("window \($0.offset + 1)", mbps: $0.element) } }, kf: 100_000, delta: 25_000)
    let oldQueued = old.devices.map(\.pending).reduce(0, +), newMost = new.devices.map(\.maxPending).max()!
    print("   model, five connections, old: \(mb(oldQueued)) queued at 60 s, keyframes \(Int(old.keyframesPerMinute(0, 60)))/min; "
          + "new: at most \(mb(newMost)) on one, frame age at most \(s(new.devices.map { $0.worstAge(0, 60) }.max()!)), "
          + "keyframes \(Int(new.keyframesPerMinute(0, 60)))/min")
    check(oldQueued > 200_000_000 && old.devices.allSatisfy { $0.worstAge(50, 60) > 20 }, "model, old: five backlogs, each growing")
    check(new.devices.allSatisfy { $0.maxPending < 700_000 && $0.worstAge(0, 60) < 2.5 && $0.evicted == nil && $0.fps(10, 60) > 10 },
          "model, new: each of the five under 700 KB queued and 2.5 s behind, each with frames")
    check(new.keyframesPerMinute(0, 60) <= 36 && new.minSpacedGap >= 2,
          "model, new: the five share one spaced request every 2 s (and a one-off each): the stream stays deltas")
}
do {
    // Links that carry the stream, a cable's included: every decision as before.
    for (label, mbps, kernel, fps, kf, delta) in [("Balanced on 50 Mbit/s Wi-Fi", 50.0, K, 60.0, 200_000, 31_000),
                                                 ("Low on 20 Mbit/s", 20.0, K, 60.0, 150_000, 8_000),
                                                 ("Pro Retina on a 400 Mbit/s cable", 400.0, K, 60.0, 1_500_000, 83_000),
                                                 ("Extreme at 120 fps on a 600 Mbit/s cable", 600.0, 4 << 20, 120.0, 2_000_000, 312_500)] {
        let (old, new) = both({ [Device("d", mbps: mbps, kernel: kernel)] }, fps: fps, kf: kf, delta: delta)
        check(old.devices[0].decisions == new.devices[0].decisions && new.devices[0].dropped == 0 && new.devices[0].waited == 0
              && new.atOnce.isEmpty && new.spaced.isEmpty && new.swept.isEmpty && new.devices[0].evicted == nil,
              "model, \(label): every decision as before, nothing dropped or asked for")
    }
    // Where the old rule turned one loss into keyframes for good (the kernel's buffer at 512 KB: a 2 MB keyframe does
    // not fit), the new one settles.
    let (old, new) = both({ [Device("d", mbps: 600, kernel: K)] }, fps: 120, kf: 2_000_000, delta: 312_500)
    print("   model, Extreme at 120 fps on 600 Mbit/s behind a 512 KB send buffer: old \(mb(old.devices[0].pending)) queued, "
          + "\(Int(old.keyframesPerMinute(0, 60))) keyframes/min; new \(String(format: "%.0f", new.devices[0].fps(10, 60))) fps, "
          + "\(Int(new.keyframesPerMinute(0, 60))) keyframes/min")
    check(old.devices[0].pending > 500_000_000 && new.devices[0].maxPending < 4_000_000 && new.devices[0].fps(10, 60) > 100,
          "model, Extreme 120 fps behind a small send buffer: the old rule's storm, the new one at over 100 fps")
}
do {
    // A slow device beside a fast one: the fast one gets no more keyframes than the encoder's own interval.
    let (old, new) = both({ [Device("slow", mbps: 6), Device("fast", mbps: 400, kernel: 4 << 20)] }, kf: 100_000, delta: 25_000)
    print("   model, a slow device beside a fast one: keyframes after 10 s, old \(Int(old.keyframesPerMinute(10, 60)))/min, "
          + "new \(Int(new.keyframesPerMinute(10, 60)))/min")
    check(old.keyframesPerMinute(10, 60) > 1000 && new.keyframesPerMinute(10, 60) <= 16,
          "model, beside a fast device: one keyframe every 4 s at most, the encoder's own interval")
    check(new.devices[1].dropped == 0 && new.devices[1].fps(10, 60) > 59 && new.devices[0].worstAge(0, 60) < 1.5,
          "model, beside a fast device: the fast one loses nothing, the slow one stays current")
}
do {
    // A dip: 50 Mbit/s, then 3 from 30 s to 40 s. The old rule's storm outlives the dip; the new one recovers.
    let (old, new) = both({ [Device("d", mbps: 50, changes: [(30, 3), (40, 50)])] }, kf: 200_000, delta: 31_000, seconds: 70)
    check(old.devices[0].worstAge(60, 70) > 2 && new.devices[0].worstAge(55, 70) < 0.1 && new.devices[0].fps(55, 70) > 59,
          "model, a 10 s dip to 3 Mbit/s: back to a current picture at 60 fps within 15 s (the old rule still trailed)")
}
do {
    // One 1.5 s stall on a 50 Mbit/s Wi-Fi at Balanced: on the old rule the storm it starts outlives it (a keyframe every
    // other frame is more than the link carries); the new one is current again at once.
    let (old, new) = both({ [Device("d", mbps: 50, changes: [(30, 0), (31.5, 50)])] }, kf: 200_000, delta: 31_000)
    print("   model, one 1.5 s stall on 50 Mbit/s: keyframes a minute from 40 s, old \(Int(old.keyframesPerMinute(40, 60))), "
          + "new \(Int(new.keyframesPerMinute(40, 60))); frame age from 40 s, old \(s(old.devices[0].worstAge(40, 60))), new \(s(new.devices[0].worstAge(40, 60)))")
    check(old.keyframesPerMinute(40, 60) > 600 && new.keyframesPerMinute(40, 60) <= 16 && new.devices[0].worstAge(40, 60) < 0.1
          && new.devices[0].fps(40, 60) > 59, "model, one 1.5 s stall on 50 Mbit/s: the old rule's storm for good, the new one back at 60 fps")
}
do {
    // Away: every decision as paceRemote made it, on the pacing harness's links.
    for (label, mbps, fps, kf, delta, gop) in [("Low on 8 Mbit/s", 8.0, 60.0, 150_000, 8_000, 4.0),
                                               ("1.6 MB keyframes on 2 Mbit/s", 2.0, 60.0, 1_600_000, 1_000, 30.0),
                                               ("real24", 24.0, 60.0, 1_500_000, 30_000, 4.0),
                                               ("bigger than the link (16 Mbit/s, 60 KB deltas)", 16.0, 60.0, 1_500_000, 60_000, 4.0)] {
        let (old, new) = both({ [Device("r", away: true, mbps: mbps)] }, fps: fps, kf: kf, delta: delta, gop: gop)
        check(old.devices[0].decisions == new.devices[0].decisions && old.spaced == new.spaced && old.swept == new.swept,
              "model, away, \(label): every decision and request as paceRemote's")
    }
    let (old, new) = both({ [Device("r", away: true, mbps: 16), Device("h", mbps: 400, kernel: 4 << 20)] }, kf: 1_500_000, delta: 60_000)
    check(old.devices[0].decisions == new.devices[0].decisions && old.devices[1].decisions == new.devices[1].decisions,
          "model, away beside a device at home: the same decisions for both")
    let still = Model(new: true, [Device("r", away: true, mbps: 16)], kf: 1_500_000, delta: 60_000)
    still.stills = [(12, 8), (27, 8), (42, 8)]
    still.run(55)
    check(still.swept.count >= 3 && still.stillsCaughtUp(still.devices[0], within: 5),
          "model, away, a still window after a drop: the sweep asks, the last picture shows within 5 s")
}
do {
    // A still window right after a loss at home: the sweep asks, the last picture arrives.
    let m = Model(new: true, [Device("d", mbps: 6)], kf: 100_000, delta: 25_000)
    m.stills = [(20, 8), (35, 8)]
    m.run(50)
    check(m.swept.count >= 1 && m.stillsCaughtUp(m.devices[0], within: 3),
          "model, home, the window still after a loss: the last picture shows within 3 s (the sweep asks)")
}
do {
    // A link that dies at 20 s: dropped once, 4 s after its last frame was taken, nothing queued for it after.
    let m = Model(new: true, [Device("dead", mbps: 6, changes: [(20, 0)])], kf: 100_000, delta: 25_000).run(40)
    let d = m.devices[0]
    if case .notDraining? = d.evicted?.why, let t = d.evicted?.t {
        check(t > 20 && t < 26, "model, a dead link at 20 s: dropped as not draining at \(s(t))")
    } else {
        check(false, "model, a dead link at 20 s: not dropped as not draining (\(String(describing: d.evicted)))")
    }
    // The old rule kept a slow but live link for good: frames were taken now and then.
    let (old, _) = both({ [Device("slow", mbps: 6)] }, kf: 100_000, delta: 25_000)
    check(old.devices[0].evicted == nil && old.devices[0].worstAge(50, 60) > 30, "model, old: a slow but live link is never dropped, its picture 30 s and more behind")
}

print(failed == 0 ? "frame-pacing: all \(passed) checks passed" : "frame-pacing: \(failed) of \(passed + failed) checks FAILED")
exit(failed == 0 ? 0 : 1)
