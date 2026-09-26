import Foundation

// Encoder-free check of EncoderSlowState (the real Sources/SillHost/EncoderSlowState.swift, compiled
// beside this file): when a hardware stream's session is replaced for the slow state, and how the
// new session is judged. Part one feeds it events by hand at its edges; part two runs streams in
// virtual time through a stand-in for HEVCEncoder's glue (one frame inside, a one-slot mailbox, a
// new session made `makeDelay` after it is asked for and taken at the next hand-over) against an
// engine whose turnaround is scripted per session. Nothing here links VideoToolbox.
//
//   Scripts/encoder-check/run.sh slowstate mutants-slowstate

var checks = 0, failures = 0
var scenarioName = ""
func expect(_ ok: Bool, _ what: @autoclosure () -> String) {
    checks += 1
    if !ok { failures += 1; if failures <= 40 { print("  FAIL [\(scenarioName)]: \(what())") } }
}
typealias W = EncoderSlowState
func isReplace(_ e: W.Event?) -> Bool { if case .replace = e { return true }; return false }
func report(_ e: W.Event?) -> W.Report? { if case .judged(let r) = e { return r }; return nil }

// MARK: - Part one: the edges, by hand

/// A watch started at `started` (by default exactly `window` before `at`, so nothing is decided before
/// `at`) that has run fast (a frame back in 9 ms then), with the given captures in each of the two
/// seconds before `at` and `returns` frames back in them at `turnaround`; then one more frame back at
/// `at` with `last`: what that one says.
func probe(started: Double? = nil, perSecondEarlier: Int = 57, perSecondRecent: Int = 57, returns: Int = 60,
           turnaround: Double = 0.029, last: Double = 0.029, at: Double = 10, ranFast: Bool = true) -> W.Event? {
    let started = started ?? at - W.window
    var w = W(now: started)
    if ranFast { _ = w.returned(turnaround: 0.009, bytes: 1, at: started) }
    var ev: [(Double, Int)] = []   // (time, 0 capture / 1 return)
    for i in 0..<perSecondEarlier { ev.append((at - 2 + 0.001 + Double(i) * (0.998 / Double(max(perSecondEarlier, 1))), 0)) }
    for i in 0..<perSecondRecent { ev.append((at - 1 + 0.001 + Double(i) * (0.998 / Double(max(perSecondRecent, 1))), 0)) }
    for i in 0..<returns { ev.append((at - 2 + 0.002 + Double(i) * (1.99 / Double(max(returns, 1))), 1)) }
    ev.sort { $0.0 < $1.0 }
    for (t, k) in ev {
        if k == 0 { w.captured(at: t) } else { expect(w.returned(turnaround: turnaround, bytes: 1, at: t) == nil, "an event before the probe's own frame, at \(t)") }
    }
    return w.returned(turnaround: last, bytes: 1, at: at)
}

scenarioName = "edges"
expect(isReplace(probe()), "57 fps in, 29 ms back, for 2 s: no replace")
expect(!isReplace(probe(perSecondEarlier: 44)), "44 captures in the window's first second: a replace")
expect(isReplace(probe(perSecondEarlier: 45)), "45 captures in the window's first second: no replace")
expect(!isReplace(probe(perSecondRecent: 44)), "44 captures in the window's last second: a replace")
expect(isReplace(probe(perSecondRecent: 45)), "45 captures in the window's last second: no replace")
expect(!isReplace(probe(returns: 8)), "9 frames back in the window: a replace")
expect(isReplace(probe(returns: 9)), "10 frames back in the window: no replace")
expect(isReplace(probe(turnaround: 0.025, last: 0.025)), "a median of exactly 25 ms: no replace")
expect(!isReplace(probe(turnaround: 0.0249, last: 0.0249)), "a median of 24.9 ms: a replace")
expect(!isReplace(probe(turnaround: 0.029, last: 0.020)), "the frame just back under 25 ms: a replace (the decision waits for a slow one)")
expect(!isReplace(probe(turnaround: 0.016, last: 0.029)), "one slow frame among fast ones (16 ms): a replace (the median decides)")
expect(!isReplace(probe(ranFast: false)), "a session that never ran fast: a replace")
expect(!isReplace(probe(started: 8.01)), "under 2 s of evidence since the stream began: a replace")
expect(isReplace(probe(started: 8.0)), "2 s of evidence since the stream began: no replace")
do {
    // Old captures drop out of the window: 57 fps until 4 s, nothing, then 57 fps from 6.5 s with
    // every frame back at 29 ms. Until 7.9 s the window's first second holds under 45 captures.
    var w = W(now: 0)
    _ = w.returned(turnaround: 0.009, bytes: 1, at: 0.01)
    let caps = Array(stride(from: 0.02, to: 4.0, by: 1.0 / 57)) + Array(stride(from: 6.5, to: 7.9, by: 1.0 / 57))
    let rets = Array(stride(from: 6.52, to: 7.9, by: 0.029))
    var i = 0, j = 0, any = false
    while i < caps.count || j < rets.count {
        if j >= rets.count || (i < caps.count && caps[i] <= rets[j]) { w.captured(at: caps[i]); i += 1 }
        else { if isReplace(w.returned(turnaround: 0.029, bytes: 1, at: rets[j])) { any = true }; j += 1 }
    }
    expect(!any, "captures older than the window still counted: a replace with under 45 frames in the window's first second")
}
do {
    // One replace, then nothing while the new session is made; a swap when not making is ignored.
    var w = W(now: 0)
    _ = w.returned(turnaround: 0.009, bytes: 1, at: 0)
    w.swapped(at: 0.5)
    for i in 0..<(57 * 3) { w.captured(at: 0.5 + Double(i) / 57) }
    var replaces = 0, others = 0
    for i in 0..<100 {
        let e = w.returned(turnaround: 0.029, bytes: 1, at: 0.5 + Double(i) * 0.029)
        if isReplace(e) { replaces += 1 } else if e != nil { others += 1 }
    }
    expect(replaces == 1 && others == 0, "a stream slow for 2.9 s gave \(replaces) replaces and \(others) other events, not one replace")
}
do {
    // Judging: the first frame (the keyframe) is left out; judged on 30 after it; gap from the old
    // session's last frame back.
    var w = W(now: 0)
    _ = w.returned(turnaround: 0.009, bytes: 1, at: 0)
    for i in 0..<(57 * 3) { w.captured(at: Double(i) / 57) }
    var t = 0.0, replaced = false
    while !replaced { t += 0.029; replaced = isReplace(w.returned(turnaround: 0.029, bytes: 500, at: t)) }
    let lastOld = t
    let s = w.returned(turnaround: 0.029, bytes: 500, at: t + 0.029)   // the old session's last frame, while making
    expect(s == nil, "an event while the new session is made")
    w.swapped(at: t + 0.030)
    expect(w.returned(turnaround: 0.040, bytes: 250_000, at: t + 0.070) == nil, "the new session's first frame judged it")
    var judged: W.Report?
    for k in 1...30 {
        let e = w.returned(turnaround: 0.009, bytes: 30_000, at: t + 0.070 + Double(k) * 0.0175)
        if let r = report(e) { judged = r; expect(k == 30, "judged after \(k) frames, not 30") }
    }
    if let r = judged {
        expect(abs((r.turnaround ?? 0) - 0.009) < 1e-9 && r.judged == 30, "judged at \(r.turnaround ?? -1) on \(r.judged), not 9 ms on 30")
        expect(r.keyframeBytes == 250_000 && abs(r.firstTurnaround - 0.040) < 1e-9, "the keyframe: \(r.keyframeBytes) bytes, \(r.firstTurnaround) s")
        expect(abs(r.gap - (t + 0.070 - (lastOld + 0.029))) < 1e-9, "the gap \(r.gap), not from the old session's last frame back")
        expect(!r.noFaster && !w.gaveUp, "a new session at 9 ms counted no faster")
    } else { expect(false, "never judged") }
}
do {
    // Judged at `judgeWithin` on at least `minJudged` (n frames, then the one that comes back at
    // `judgeWithin`); fewer: no verdict on its speed, and no giving up.
    for (n, expectTurnaround) in [(4, true), (3, false)] {
        var w = W(now: 0)
        _ = w.returned(turnaround: 0.009, bytes: 1, at: 0)
        for i in 0..<(57 * 3) { w.captured(at: Double(i) / 57) }
        var t = 0.0
        while !isReplace(w.returned(turnaround: 0.029, bytes: 1, at: t + 0.029)) { t += 0.029 }
        w.swapped(at: t + 0.05)
        _ = w.returned(turnaround: 0.03, bytes: 9, at: t + 0.08)
        var r: W.Report?
        for k in 0..<n { if let x = report(w.returned(turnaround: 0.030, bytes: 1, at: t + 0.1 + Double(k) * 0.01)) { r = x } }
        expect(r == nil, "judged before \(W.judgeWithin) s on \(n) frames")
        r = report(w.returned(turnaround: 0.030, bytes: 1, at: t + 0.05 + W.judgeWithin))
        expect(r != nil, "not judged at \(W.judgeWithin) s")
        if let r {
            expect((r.turnaround != nil) == expectTurnaround, "\(n + 1) frames by \(W.judgeWithin) s: turnaround \(String(describing: r.turnaround))")
            expect(r.noFaster == expectTurnaround && w.gaveUp == expectTurnaround, "\(n + 1) frames at 30 ms by \(W.judgeWithin) s: noFaster \(r.noFaster), gaveUp \(w.gaveUp)")
        }
    }
}
do {
    // A new session that could not be made: nothing to judge, and the next try 10 s on.
    var w = W(now: 0)
    _ = w.returned(turnaround: 0.009, bytes: 1, at: 0)
    var t = 0.0, captureAt = 0.0
    func tick(_ until: Double) -> [W.Event] {
        var out: [W.Event] = []
        while t < until {
            while captureAt <= t { w.captured(at: captureAt); captureAt += 1.0 / 57 }
            t += 0.029
            if let e = w.returned(turnaround: 0.029, bytes: 1, at: t) { out.append(e) }
        }
        return out
    }
    let first = tick(3)
    expect(first.count == 1 && isReplace(first.first), "slow for 3 s: \(first.count) events, not one replace")
    w.replacementFailed(at: t)
    let failedAt = t
    let during = tick(failedAt + 9.9)
    expect(during.isEmpty, "\(during.count) events within 10 s of a failed attempt")
    let after = tick(failedAt + 10.2)
    expect(after.count == 1 && isReplace(after.first), "no replace 10 s after a failed attempt")
    w.replacementFailed(at: t)
    w.swapped(at: t)   // not making: ignored
    expect(tick(t + 1).isEmpty, "a swap or failure while not making changed something")
}

// MARK: - Part two: streams in virtual time

/// The glue around the watch: capture at scripted times, one frame inside, a one-slot mailbox (the
/// newest waiting frame goes in when the place frees), a new session ready `makeDelay` after the
/// replace (or never, if `makeFails`) and taken at the next hand-over. `turnaround(session, since
/// the session took over, now)` scripts the engine.
struct Stream {
    var watch: W
    var makeDelay = 0.04
    var makeFails = false
    var turnaround: (_ session: Int, _ sinceStart: Double, _ now: Double) -> Double
    var session = 1
    var sessionStart = 0.0
    private(set) var replaces: [Double] = []
    private(set) var swaps: [Double] = []
    private(set) var reports: [(Double, W.Report)] = []
    private(set) var outputs: [(at: Double, session: Int)] = []
    private var readyAt: Double?
    private var inside: (out: Double, turn: Double, session: Int)?
    private var waiting = false

    init(start: Double = 0, turnaround: @escaping (Int, Double, Double) -> Double) {
        watch = W(now: start); sessionStart = start; self.turnaround = turnaround
    }
    private mutating func handOver(at h: Double) {
        if let r = readyAt, h >= r { readyAt = nil; session += 1; sessionStart = h; swaps.append(h); watch.swapped(at: h) }
        let d = turnaround(session, h - sessionStart, h)
        inside = (h + d, d, session)
    }
    /// Frames back up to `t`, each followed by the waiting frame's hand-over.
    private mutating func drain(to t: Double) {
        while let i = inside, i.out <= t {
            inside = nil
            outputs.append((i.out, i.session))
            switch watch.returned(turnaround: i.turn, bytes: i.session == session && outputs.filter({ $0.session == i.session }).count == 1 ? 250_000 : 30_000, at: i.out) {
            case .replace?:
                replaces.append(i.out)
                if makeFails { watch.replacementFailed(at: i.out + makeDelay) } else { readyAt = i.out + makeDelay }
            case .judged(let r)?: reports.append((i.out, r))
            case nil: break
            }
            if waiting { waiting = false; handOver(at: i.out) }
        }
    }
    mutating func capture(at t: Double) {
        drain(to: t)
        watch.captured(at: t)
        if inside == nil { handOver(at: t) } else { waiting = true }
    }
    mutating func run(_ captures: [Double], until end: Double) {
        for c in captures { capture(at: c) }
        drain(to: end)
    }
    func outRate(_ a: Double, _ b: Double) -> Double { Double(outputs.filter { $0.at >= a && $0.at < b }.count) / (b - a) }
}

/// Capture times: `fps` from `a` to `b`.
func motion(_ a: Double, _ b: Double, fps: Double = 57) -> [Double] { stride(from: a, to: b, by: 1 / fps).map { $0 } }
func quiet(_ a: Double, _ b: Double) -> [Double] { stride(from: a + 0.5, to: b, by: 1.0).map { $0 } }

/// The solo measurement's engine: a session is 9 ms a frame until it has been fed sparse frames for
/// 1.4 s (no two captures within 0.2 s), then 29 ms for good; `newSlow`: every new session 29 ms.
func soloEngine(quietFrom: Double, quietTo: Double, newSlow: Bool = false) -> (Int, Double, Double) -> Double {
    return { session, _, now in
        if session > 1 { return newSlow ? 0.029 : 0.009 }
        return now >= quietFrom + 1.4 ? 0.029 : (now >= quietFrom ? 0.016 : 0.009)
    }
}

scenarioName = "the solo schedule"
do {
    // motion 4 s, still 10 s, motion 35 s: slow from 5.4 s; replaced about 2 s into the motion.
    var s = Stream(turnaround: soloEngine(quietFrom: 4, quietTo: 14))
    s.run(motion(0, 4) + quiet(4, 14) + motion(14, 49), until: 49.5)
    expect(s.replaces.count == 1, "\(s.replaces.count) replaces, not 1")
    if let r = s.replaces.first { expect(r > 15.7 && r < 16.2, "replaced at \(r - 14) s into the motion, not about 2 s") }
    if let sw = s.swaps.first, let r = s.replaces.first { expect(sw - r < 0.1, "the swap came \(sw - r) s after the replace") }
    expect(s.reports.count == 1, "\(s.reports.count) verdicts, not 1")
    if let (_, r) = s.reports.first {
        expect(abs((r.turnaround ?? 0) - 0.009) < 1e-9 && !r.noFaster, "the new session judged at \(r.turnaround ?? -1)")
        expect(abs(r.slow.turnaround - 0.029) < 1e-9, "the slow session's median \(r.slow.turnaround), not 29 ms")
        expect(r.gap < 0.03, "a gap of \(r.gap) s across the swap")
    }
    let before = s.outRate(15, 15.8), after = s.outRate(17, 49)
    print(String(format: "solo schedule: replaced %.2f s into the motion, swap +%.0f ms; %.1f fps before, %.1f after (57 captured); verdict %@",
                 (s.replaces.first ?? 0) - 14, ((s.swaps.first ?? 0) - (s.replaces.first ?? 0)) * 1000, before, after,
                 s.reports.first.map { String(format: "%.0f ms", ($0.1.turnaround ?? 0) * 1000) } ?? "none"))
    expect(before < 36 && after > 56, "out \(before) fps before the swap and \(after) after, not about 34 and 57")
}

scenarioName = "a new session no faster"
do {
    var s = Stream(turnaround: soloEngine(quietFrom: 4, quietTo: 14, newSlow: true))
    s.run(motion(0, 4) + quiet(4, 14) + motion(14, 80), until: 80.5)
    expect(s.replaces.count == 1, "\(s.replaces.count) replaces over 66 s of motion after a new session no faster, not 1")
    expect(s.reports.count == 1 && s.reports.first?.1.noFaster == true && s.watch.gaveUp, "not judged no faster, or not given up")
    print("a new session no faster: \(s.replaces.count) replace over 66 s, then kept (gave up: \(s.watch.gaveUp))")
}

scenarioName = "gave up for good"
do {
    // The new session runs fast for 0.1 s, then as slow as the old one: judged no faster on its 30
    // frames, and never replaced again, though it has run fast and the motion lasts a minute.
    var s = Stream(turnaround: { session, since, now in
        if session == 1 { return now >= 5.4 ? 0.029 : 0.009 }
        return since < 0.1 ? 0.009 : 0.029
    })
    s.run(motion(0, 4) + quiet(4, 14) + motion(14, 80), until: 80.5)
    expect(s.replaces.count == 1 && s.reports.count == 1 && s.reports.first?.1.noFaster == true && s.watch.gaveUp,
           "a new session fast for 0.1 s then slow: \(s.replaces.count) replaces, verdicts \(s.reports.map { $0.1.turnaround ?? -1 })")
}

scenarioName = "a slow frame now and then"
do {
    // The fast state with one frame in 60 at 30 ms (a keyframe, say): never replaced.
    var s = Stream(turnaround: { _, since, now in Int((now * 57).rounded()) % 60 == 0 ? 0.030 : (since < 4 ? 0.009 : 0.016) })
    s.run(motion(0, 40), until: 40.5)
    expect(s.replaces.isEmpty, "\(s.replaces.count) replaces for one slow frame in 60")
}

scenarioName = "never fast"
do {
    // A frame size the engine is simply slow at: 30 ms from the first frame.
    var s = Stream(turnaround: { _, _, _ in 0.030 })
    s.run(motion(0, 30), until: 30.5)
    expect(s.replaces.isEmpty, "\(s.replaces.count) replaces for a session that never ran fast")
}

scenarioName = "fast throughout"
do {
    var s = Stream(turnaround: { _, since, _ in since < 4 ? 0.009 : 0.016 })
    s.run(motion(0, 40), until: 40.5)
    expect(s.replaces.isEmpty, "\(s.replaces.count) replaces in the fast state")
    expect(s.outRate(1, 39) > 56, "the fast state out at \(s.outRate(1, 39)) fps")
}

scenarioName = "slow, input under 45 fps"
do {
    var s = Stream(turnaround: soloEngine(quietFrom: 4, quietTo: 14))
    s.run(motion(0, 4) + quiet(4, 14) + motion(14, 40, fps: 40), until: 40.5)
    expect(s.replaces.isEmpty, "\(s.replaces.count) replaces at 40 fps in")
    var t = Stream(turnaround: soloEngine(quietFrom: 4, quietTo: 14))
    t.run(motion(0, 4) + quiet(4, 14) + motion(14, 40, fps: 44.5), until: 40.5)
    expect(t.replaces.isEmpty, "\(t.replaces.count) replaces at 44.5 fps in")
}

scenarioName = "bursts"
do {
    // 1.2 s of motion every 3 s on a slow session: never 45 frames in each second of a 2 s window.
    var caps: [Double] = motion(0, 4) + quiet(4, 14)
    var t0 = 14.0
    while t0 < 60 { caps += motion(t0, t0 + 1.2); t0 += 3 }
    var s = Stream(turnaround: soloEngine(quietFrom: 4, quietTo: 14))
    s.run(caps, until: 61)
    expect(s.replaces.isEmpty, "\(s.replaces.count) replaces for 1.2 s bursts")
}

scenarioName = "spacing"
do {
    // The new session goes slow again 3 s after it took over (another quiet spell): the second
    // replace waits for 10 s after the first swap.
    var swapAt = Double.infinity
    var s = Stream(turnaround: { session, since, now in
        if session == 1 { return now >= 5.4 ? 0.029 : 0.009 }
        if session == 2 { return since >= 3 ? 0.029 : 0.009 }
        return 0.009
    })
    s.run(motion(0, 4) + quiet(4, 14) + motion(14, 40), until: 40.5)
    swapAt = s.swaps.first ?? .infinity
    expect(s.replaces.count == 2, "\(s.replaces.count) replaces, not 2")
    if s.replaces.count == 2 { expect(s.replaces[1] - swapAt >= 10 && s.replaces[1] - swapAt < 10.3, "the second replace \(s.replaces[1] - swapAt) s after the first swap, not just over 10") }
    print(String(format: "spacing: replaces at %@ s", s.replaces.map { String(format: "%.2f", $0) }.joined(separator: ", ")))
}

scenarioName = "a new session that cannot be made"
do {
    var s = Stream(turnaround: soloEngine(quietFrom: 4, quietTo: 14))
    s.makeFails = true
    s.run(motion(0, 4) + quiet(4, 14) + motion(14, 40), until: 40.5)
    expect(s.swaps.isEmpty && s.reports.isEmpty, "a swap or a verdict without a new session")
    expect(s.replaces.count == 3, "\(s.replaces.count) tries over 26 s of slow motion, not 3 (every 10 s)")
    if s.replaces.count >= 2 { expect(s.replaces[1] - s.replaces[0] >= 10, "tries \(s.replaces[1] - s.replaces[0]) s apart") }
}

scenarioName = "still right after the swap"
do {
    // The picture stops as the new session is asked for, so it takes over with the next repaint and
    // gets two more before `judgeWithin`: no verdict on its speed, and no giving up. The new session,
    // which never runs fast, is slow when motion comes back 20 s later: no second replace, however
    // long the motion lasts.
    var s = Stream(turnaround: { session, _, now in session == 1 ? (now >= 5.4 ? 0.029 : 0.009) : 0.029 })
    for c in motion(0, 4) + quiet(4, 14) + motion(14, 20) {
        s.capture(at: c)
        if !s.replaces.isEmpty { break }
    }
    let replacedAt = s.replaces.first ?? 99
    s.run(quiet(replacedAt, replacedAt + 20) + motion(replacedAt + 20, replacedAt + 50), until: replacedAt + 51)
    expect(s.swaps.count == 1, "\(s.swaps.count) swaps")
    expect(s.reports.count == 1 && s.reports.first?.1.turnaround == nil && !s.watch.gaveUp,
           "went still after the swap: \(s.reports.map { String(describing: $0.1.turnaround) }), gave up \(s.watch.gaveUp)")
    expect(s.replaces.count == 1, "\(s.replaces.count) replaces: a session that never ran fast was replaced")
}

print(failures == 0 ? "PASS: \(checks) checks" : "FAIL: \(failures) of \(checks) checks")
exit(failures == 0 ? 0 : 1)
