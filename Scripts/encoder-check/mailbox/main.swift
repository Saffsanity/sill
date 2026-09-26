import Foundation
import CoreMedia

// Encoder-free check of HEVCEncoder's frame bookkeeping. Sources/SillHost/EncoderMailbox.swift (the
// real file) is compiled beside this one; `StandIn` below mirrors HEVCEncoder's glue call for call
// (encode and the re-encode's admission, submit on a serial queue, the encode call, frameReturned
// from the output handler or a refusal, the watchdog every 0.5 s, requestKeyframe and its second
// look, abandon, the deinit's teardown) around a stand-in for VideoToolbox that returns each frame
// after a programmable delay, in virtual time. One frame is inside at a time, as in HEVCEncoder.
// A new session for the slow state (EncoderSlowState) makes no call on the mailbox of its own; it
// is the slow-state check's and the encoder check's (E7). Nothing here links VideoToolbox.
//
//   Scripts/encoder-check/run.sh mailbox mutants      (from the repository's root)
// or by hand:
//   swiftc -O Sources/SillHost/EncoderMailbox.swift Scripts/encoder-check/mailbox/main.swift -o .build/mailbox-check && .build/mailbox-check

// MARK: - Harness

var checks = 0
var failures = 0
var scenarioName = ""
func expect(_ ok: Bool, _ what: @autoclosure () -> String) {
    checks += 1
    if !ok { failures += 1; if failures <= 40 { print("  FAIL [\(scenarioName)]: \(what())") } }
}

/// Virtual time: events run in time order, ties in the order they were scheduled.
final class Clock {
    private(set) var now: Double = 0
    private var events: [(t: Double, seq: Int, run: () -> Void)] = []
    private var seq = 0
    func at(_ t: Double, _ run: @escaping () -> Void) {
        seq += 1
        let t = max(t, now)
        var lo = 0, hi = events.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if events[mid].t < t || (events[mid].t == t && events[mid].seq < seq) { lo = mid + 1 } else { hi = mid }
        }
        events.insert((t, seq, run), at: lo)
    }
    func after(_ dt: Double, _ run: @escaping () -> Void) { at(now + dt, run) }
    func run(until end: Double = .infinity) {
        while let first = events.first, first.t <= end {
            events.removeFirst()
            now = first.t
            first.run()
        }
        if end.isFinite { now = max(now, end) }
    }
}

struct Frame {
    let serial: Int          // unique per frame given to the encoder (a re-encode is a new one)
    let index: Int           // capture index; a re-encode keeps its source's
    let pts: CMTime
    let capturedAt: Double
    let reencode: Bool
}

func cm(_ t: Double) -> CMTime { CMTime(value: CMTimeValue((t * 1_000_000).rounded()), timescale: 1_000_000) }

enum Engine {
    /// Each frame comes back `turnaround` seconds after its encode call (nil: never).
    case independent((Frame) -> Double?)
    /// One engine: `chip` seconds a frame, one frame at a time; `pre` before it and `post` after it.
    case serial(pre: Double, chip: Double, post: Double)
}

typealias Box = EncoderMailbox<Frame>

/// HEVCEncoder with VideoToolbox replaced by `engine`. Every method mirrors the real one.
final class StandIn {
    let clock: Clock
    var box = Box()
    let engine: Engine
    let hangAfter: Double = 1.5      // HEVCEncoder.hangAfter
    let stillAfter: Double = 0.05    // HEVCEncoder.stillAfter
    /// Output in decode order, as VideoToolbox documents it: a frame's output waits for every
    /// frame handed over before it. With one frame inside they come back in order anyway.
    var inOrder = false
    var refuse: (Frame) -> Bool = { _ in false }
    var duplicateAfterRefusal: (Frame) -> Bool = { _ in false }
    var failOutput: (Frame) -> Bool = { _ in false }
    /// TEST ONLY hooks: seconds a frame's submit waits before the encode call, by id.
    var hold: (Int) -> Double = { _ in 0 }
    /// Seconds an encode call takes to return after VideoToolbox took the frame, by id: the
    /// frame's own time inside runs from the call, the queue stays blocked until it returns.
    var callBlocks: (Int) -> Double = { _ in 0 }

    // The stand-in VideoToolbox.
    private(set) var vtHolds: [Int: Frame] = [:]
    private(set) var maxVTHolds = 0
    private var engineFree = 0.0
    private var handOverOrder: [Int] = []                  // ids in encode-call order
    private var ready: [Int: (Frame, EncoderMailbox<Frame>.HandOver, Bool)] = [:]   // decode order: done, not yet delivered

    // encodeQueue: serial, jobs in order.
    private var queue: [(Frame, Int)] = []
    private var queueBusy = false
    private(set) var onQueue: Set<Int> = []
    /// Ids the mailbox handed over (`handOver` returned a hand-over).
    private(set) var handedOver: Set<Int> = []

    // HEVCEncoder's own state.
    var lastFrame: Frame?
    var lastFrameAt = -Double.infinity
    var forcedRetries = 0
    var watchdogOff = false
    var gone = false

    // Stats keys and what the check watches.
    var out = 0, errors = 0, refused = 0, mailboxDrop = 0, deadDrop = 0, ptsFixed = 0, hung = 0
    var late = 0, duplicates = 0, handOversAfterDeath = 0, keyframeChecks = 0
    var hungAt: Double?
    var outputs: [(id: Int, frame: Frame, at: Double)] = []
    var handOvers: [(id: Int, frame: Frame, pts: CMTime, keyframe: Bool, at: Double)] = []   // encode calls
    var handOverLog: [(id: Int, keyframe: Bool, at: Double)] = []   // the mailbox's hand-overs (the flag is taken there)
    var returnOrder: [Int] = []
    var keyframeRequestTimes: [Double] = []
    var keyframeRequestMarks: [Int] = []   // how many frames had been handed over at each request
    var created: [Int: Frame] = [:]
    var fate: [Int: String] = [:]
    private var nextSerial = 0

    init(clock: Clock, engine: Engine) {
        self.clock = clock
        self.engine = engine
    }

    func newFrame(index: Int, pts: CMTime, capturedAt: Double, reencode: Bool) -> Frame {
        nextSerial += 1
        let f = Frame(serial: nextSerial, index: index, pts: pts, capturedAt: capturedAt, reencode: reencode)
        created[f.serial] = f
        return f
    }

    func settle(_ f: Frame, _ what: String) {
        expect(fate[f.serial] == nil, "frame #\(f.serial) (capture \(f.index)) settled twice: \(fate[f.serial] ?? "") then \(what)")
        fate[f.serial] = what
    }

    /// While the session is live, the mailbox's frame inside is exactly the one on encodeQueue or
    /// inside VideoToolbox, it counts as handed over exactly when the mailbox handed it over, and a
    /// frame waits only while the place is taken.
    func invariants(_ at: String) {
        guard !gone else { return }
        if box.waiting != nil { expect(!box.dead && box.inside != nil, "\(at): a frame waits while the place is free or the session is dead") }
        guard !box.dead else { return }
        let bookkept = Set(box.inside.map { [$0.id] } ?? []), real = Set(vtHolds.keys).union(onQueue)
        expect(bookkept == real, "\(at): the mailbox has \(bookkept.sorted()) inside, the queue and VideoToolbox hold \(real.sorted())")
        if let inside = box.inside {
            expect(inside.handed == handedOver.contains(inside.id), "\(at): frame \(inside.id) counts as handed over: \(inside.handed), handed over: \(handedOver.contains(inside.id))")
        }
    }

    // HEVCEncoder.encode(_:pts:)
    func capture(index: Int) {
        let f = newFrame(index: index, pts: cm(clock.now), capturedAt: clock.now, reencode: false)
        admit(f, fromCapture: true)
    }

    // HEVCEncoder.admitLocked and count
    func admit(_ f: Frame, fromCapture: Bool) {
        let before = box.waiting
        let now = clock.now
        let admission = box.admit(f, now: now)
        if admission != .dropped {
            lastFrame = f
            if fromCapture { lastFrameAt = now }
        }
        switch admission {
        case .goesIn(let id): async(f, id)
        case .waits(let replaced):
            if replaced {
                mailboxDrop += 1
                if let before { settle(before, "replaced in the mailbox") } else { expect(false, "replaced, but nothing was waiting") }
            } else {
                expect(before == nil, "a frame was waiting, yet nothing was replaced")
            }
        case .dropped:
            deadDrop += 1
            settle(f, "dropped: dead")
        }
        invariants("admit")
    }

    private func async(_ f: Frame, _ id: Int) {
        queue.append((f, id))
        onQueue.insert(id)
        if !queueBusy { runQueue() }
    }

    private func runQueue() {
        guard !queue.isEmpty else { queueBusy = false; return }
        queueBusy = true
        let (f, id) = queue.removeFirst()
        submit(f, id)
    }

    // HEVCEncoder.submit (encodeQueue)
    private func submit(_ f: Frame, _ id: Int) {
        guard !gone else { onQueue.remove(id); settle(f, "encoder released"); runQueue(); return }   // [weak self]
        guard let h = box.handOver(id, pts: f.pts, now: clock.now) else {
            onQueue.remove(id)
            handOversAfterDeath += 1
            settle(f, "dropped at hand-over: dead")
            runQueue()
            return
        }
        handedOver.insert(id)
        handOverLog.append((id, h.keyframe, clock.now))
        if h.ptsFixed { ptsFixed += 1 }
        let wait = hold(id)
        let call = { [self] in
            encodeCall(f, id, h)
            let blocked = callBlocks(id)
            if blocked > 0 { clock.after(blocked) { [self] in runQueue() } } else { runQueue() }
        }
        if wait > 0 { clock.after(wait, call) } else { call() }
    }

    // VTCompressionSessionEncodeFrame and what follows it in submit.
    private func encodeCall(_ f: Frame, _ id: Int, _ h: Box.HandOver) {
        onQueue.remove(id)
        expect(!gone, "an encode call after the encoder was released")
        handOvers.append((id, f, h.pts, h.keyframe, clock.now))
        handOverOrder.append(id)
        if refuse(f) {
            refused += 1
            settle(f, "refused")
            if h.keyframe { retryKeyframe() }
            _ = frameReturned(id)
            if duplicateAfterRefusal(f) {
                clock.after(0.004) { [self] in handler(id, f, h, ok: false) }
            }
            return
        }
        vtHolds[id] = f
        maxVTHolds = max(maxVTHolds, vtHolds.count)
        expect(vtHolds.count <= 1, "VideoToolbox holds \(vtHolds.count) frames at \(clock.now), not one at most")
        let done: Double?
        switch engine {
        case .independent(let turnaround): done = turnaround(f).map { clock.now + $0 }
        case .serial(let pre, let chip, let post):
            let start = max(clock.now + pre, engineFree)
            engineFree = start + chip
            done = engineFree + post
        }
        guard let done else { return }   // stuck for good
        let ok = !failOutput(f)
        clock.at(done) { [self] in
            if inOrder {
                ready[id] = (f, h, ok)
                deliverInOrder()
            } else {
                deliver(id, f, h, ok: ok)
            }
        }
    }

    private func deliverInOrder() {
        while let first = handOverOrder.first {
            if vtHolds[first] == nil, ready[first] == nil { handOverOrder.removeFirst(); continue }   // refused, or already out
            guard let (f, h, ok) = ready.removeValue(forKey: first) else { return }
            handOverOrder.removeFirst()
            deliver(first, f, h, ok: ok)
        }
    }

    private func deliver(_ id: Int, _ f: Frame, _ h: Box.HandOver, ok: Bool) {
        guard vtHolds.removeValue(forKey: id) != nil else { return }   // drained at teardown
        returnOrder.append(id)
        handler(id, f, h, ok: ok)
    }

    // The output handler.
    private func handler(_ id: Int, _ f: Frame, _ h: Box.HandOver, ok: Bool) {
        guard !gone else { settle(f, "back after release"); return }
        let (forward, duplicate) = frameReturned(id)
        guard forward else { late += 1; settle(f, "late: dead"); return }
        guard ok else {
            errors += 1
            if !duplicate { settle(f, "error") }
            if h.keyframe { retryKeyframe() }
            return
        }
        expect(!duplicate, "a duplicate notice came with an output")
        out += 1
        if h.keyframe { forcedRetries = 0 }
        outputs.append((id, f, clock.now))
        settle(f, "out")
    }

    // HEVCEncoder.frameReturned. Returns (forward, duplicate).
    @discardableResult
    private func frameReturned(_ id: Int) -> (Bool, Bool) {
        let outcome = box.returned(id, now: clock.now)
        var result = (true, false)
        switch outcome {
        case .late: result = (false, false)
        case .duplicate: duplicates += 1; result = (true, true)
        case .freed: break
        case .next(let f, let next): async(f, next)
        }
        invariants("frameReturned")
        return result
    }

    // HEVCEncoder.checkWatchdog, every 0.5 s.
    func startWatchdog(until end: Double) {
        var t = 0.5
        while t <= end + 1e-9 { clock.at(t) { [self] in watchdogTick() }; t += 0.5 }
    }
    private func watchdogTick() {
        guard !gone, !watchdogOff else { return }
        let waitingBefore = box.waiting
        let fired = box.giveUpIfHung(now: clock.now, after: hangAfter)
        if fired {
            if let waitingBefore { settle(waitingBefore, "dropped: watchdog") }
            expect(box.waiting == nil, "a frame still waits after the watchdog gave up")
            lastFrame = nil
            watchdogOff = true
            hung += 1
            hungAt = clock.now
        }
        invariants("watchdog")
    }

    // HEVCEncoder.requestKeyframe (one hold of the lock: atomic here, as everything in virtual time)
    func requestKeyframe() {
        keyframeRequestTimes.append(clock.now)
        keyframeRequestMarks.append(handOverLog.count)
        box.keyframeRequested = true
        if clock.now - lastFrameAt >= stillAfter {
            reencodeLast()
        } else {
            clock.at(lastFrameAt + stillAfter + 0.01) { [self] in keyframeCheck() }
        }
    }

    // HEVCEncoder.keyframeCheck (on the watchdog's queue)
    func keyframeCheck() {
        guard !gone else { return }
        keyframeChecks += 1
        guard box.keyframeRequested, !box.dead, !box.frameOnItsWay, clock.now - lastFrameAt >= stillAfter else { return }
        reencodeLast()
    }

    private func reencodeLast() {
        guard let last = lastFrame else { return }
        let lastPTS = box.lastPTS
        let pts = lastPTS.isValid ? CMTimeAdd(lastPTS, CMTime(value: 1, timescale: 1000)) : cm(clock.now)
        admit(newFrame(index: last.index, pts: pts, capturedAt: last.capturedAt, reencode: true), fromCapture: false)
    }

    private func retryKeyframe() {
        let again = forcedRetries < 3
        if again { forcedRetries += 1 }
        if again { requestKeyframe() }
    }

    // HEVCEncoder.abandon
    func abandon() -> Bool {
        let waitingBefore = box.waiting
        let inside = box.giveUp()
        if let waitingBefore { settle(waitingBefore, "dropped: abandoned") }
        lastFrame = nil
        watchdogOff = true
        invariants("abandon")
        return inside
    }

    // HEVCEncoder.deinit: the teardown, and VideoToolbox finishing what it holds on a drain.
    func release() -> Box.Teardown {
        let teardown = box.teardown
        gone = true
        if let w = box.waiting { settle(w, "waiting at release") }
        if teardown == .drain {
            for (_, f) in vtHolds { settle(f, "drained at release") }
            vtHolds.removeAll()
        }
        return teardown
    }

    /// Frames not settled: those still in flight when a run stops without draining.
    var unsettled: [Frame] { created.values.filter { fate[$0.serial] == nil } }
}

// MARK: - Scenario helpers

func captureTimes(fps: Double, from: Double, to: Double) -> [Double] {
    var t: [Double] = []
    var i = 0
    while true {
        let x = from + Double(i) / fps
        if x >= to - 1e-9 { break }
        t.append(x)
        i += 1
    }
    return t
}

func schedule(_ s: StandIn, captures: [Double]) {
    for (i, t) in captures.enumerated() { s.clock.at(t) { s.capture(index: i) } }
}

func percentile(_ xs: [Double], _ p: Double) -> Double {
    guard !xs.isEmpty else { return .nan }
    let sorted = xs.sorted()
    return sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))]
}

struct Summary {
    let rate: Double, drops: Double, latencyMedian: Double, latencyP95: Double, latencyMax: Double
}

/// Output rate, mailbox drops and capture-to-output latency over [from, to).
func summary(_ s: StandIn, from: Double, to: Double) -> Summary {
    let outs = s.outputs.filter { $0.at >= from && $0.at < to }
    let lat = outs.filter { !$0.frame.reencode }.map { ($0.at - $0.frame.capturedAt) * 1000 }
    let replaced = s.fate.filter { $0.value == "replaced in the mailbox" }.compactMap { s.created[$0.key] }
    let drops = replaced.filter { $0.capturedAt >= from && $0.capturedAt < to }.count
    let span = to - from
    return Summary(rate: Double(outs.count) / span, drops: Double(drops) / span,
                   latencyMedian: percentile(lat, 0.5), latencyP95: percentile(lat, 0.95), latencyMax: lat.max() ?? .nan)
}

func line(_ name: String, _ s: StandIn, _ m: Summary) -> String {
    name.padding(toLength: 62, withPad: " ", startingAt: 0) +
        String(format: " out %5.1f fps  mailboxDrop %5.1f/s  latency median %5.1f p95 %5.1f max %5.1f ms  max inside VT %d  watchdog ",
               m.rate, m.drops, m.latencyMedian, m.latencyP95, m.latencyMax, s.maxVTHolds) +
        (s.hungAt.map { String(format: "%.2f s", $0) } ?? "no")
}

/// Every frame the encoder was given ends exactly one way once the run has drained.
func expectAllSettled(_ s: StandIn) {
    let left = s.unsettled
    expect(left.isEmpty, "\(left.count) frames never settled (first: capture \(left.first?.index ?? -1))")
}

/// A seeded generator, so a failure repeats.
struct LCG {
    var state: UInt64
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(1 << 53)
    }
}

let fps = 60.0

// MARK: - Scenarios

func steady(_ name: String, engine: Engine, seconds: Double = 10) -> (StandIn, Summary) {
    scenarioName = name
    let clock = Clock()
    let s = StandIn(clock: clock, engine: engine)
    schedule(s, captures: captureTimes(fps: fps, from: 0, to: seconds))
    s.startWatchdog(until: seconds + 2)
    clock.run()
    let m = summary(s, from: 2, to: seconds - 1)
    print(line(name, s, m))
    expectAllSettled(s)
    expect(s.hungAt == nil, "the watchdog fired on a healthy pipeline at \(s.hungAt ?? -1)")
    expect(s.late == 0 && s.deadDrop == 0, "late \(s.late) / deadDrop \(s.deadDrop) on a healthy pipeline")
    // Every frame captured is output or pushed out of the mailbox, nothing else.
    expect(s.out + s.mailboxDrop == Int(seconds * fps), "out \(s.out) + mailboxDrop \(s.mailboxDrop) != \(Int(seconds * fps)) captured")
    expect(s.maxVTHolds == 1, "VideoToolbox held \(s.maxVTHolds) frames at most, not 1")
    let pts = s.handOvers.map(\.pts)
    expect(zip(pts, pts.dropFirst()).allSatisfy { CMTimeCompare($0, $1) < 0 }, "timestamps handed to VideoToolbox went backwards")
    return (s, m)
}

print("== EncoderMailbox against a stand-in VideoToolbox, 60 fps capture, one frame inside")

// S1: the fast state (~9 ms a frame): nothing waits.
do {
    let (s, m) = steady("fast state, 9 ms a frame", engine: .independent { _ in 0.009 })
    expect(s.out == 600 && s.mailboxDrop == 0, "fast state: out \(s.out), mailboxDrop \(s.mailboxDrop)")
    expect(m.rate >= 59.5 && m.rate <= 60.5, "fast state: \(m.rate) fps, not 60")
    expect(abs(m.latencyMax - 9) < 0.01, "fast state: latency max \(m.latencyMax) ms, not 9")
}

// S2: the slow state (~30 ms a frame): one over the turnaround, 33.3 fps, the rest mailbox drops.
do {
    let (s, m) = steady("slow state, 30 ms a frame", engine: .independent { _ in 0.030 })
    expect(m.rate >= 32.5 && m.rate <= 34.5, "slow state: \(m.rate) fps, not ~33.3")
    expect(m.drops >= 25 && m.drops <= 28, "slow state: \(m.drops) mailbox drops a second, not ~26.7")
    // The newest frame wins: a frame let in from the mailbox waited at most one capture interval.
    expect(m.latencyMax <= 30 + 1000 / fps + 0.01, "slow state: latency max \(m.latencyMax) ms, over 30 ms plus one frame interval")
    _ = s
}

// S3: 40 ms a frame: 25 fps, 35 mailbox drops a second, counted exactly.
do {
    let (_, m) = steady("40 ms a frame", engine: .independent { _ in 0.040 })
    expect(m.rate >= 24.5 && m.rate <= 25.5, "40 ms: \(m.rate) fps, not ~25")
    expect(m.drops >= 34.5 && m.drops <= 35.5, "40 ms: \(m.drops) drops a second, not ~35")
}

// S4: one engine doing one frame at a time, 30 ms each: the same one over the turnaround.
do {
    let (_, m) = steady("one engine, 30 ms a frame one at a time", engine: .serial(pre: 0, chip: 0.030, post: 0))
    expect(m.rate >= 32.5 && m.rate <= 34.5, "serial engine at 30 ms: \(m.rate) fps, not ~33.3")
}

// S5: turnarounds of 4 to 45 ms, refusals, a duplicate notice after some refusals, rate-control
// drops and keyframe requests.
do {
    scenarioName = "random turnarounds"
    let clock = Clock()
    var rng = LCG(state: 42)
    var delays: [Int: Double] = [:]
    let s = StandIn(clock: clock, engine: .independent { f in
        if let d = delays[f.serial] { return d }
        let d = 0.004 + 0.041 * rng.next()
        delays[f.serial] = d
        return d
    })
    s.refuse = { $0.index % 37 == 5 && !$0.reencode }
    s.duplicateAfterRefusal = { $0.index % 74 == 5 }
    s.failOutput = { $0.index % 50 == 7 && !$0.reencode }
    schedule(s, captures: captureTimes(fps: fps, from: 0, to: 10))
    for t in stride(from: 0.25, to: 10, by: 0.5) { clock.at(t) { s.requestKeyframe() } }
    s.startWatchdog(until: 12)
    clock.run()
    let m = summary(s, from: 2, to: 9)
    print(line("turnarounds 4-45 ms, refusals, errors, keyframes", s, m))
    expectAllSettled(s)
    expect(s.hungAt == nil, "random turnarounds: the watchdog fired at \(s.hungAt ?? -1)")
    let refusals = s.handOvers.filter { s.refuse($0.frame) }.count
    let dupNotices = s.handOvers.filter { s.refuse($0.frame) && s.duplicateAfterRefusal($0.frame) }.count
    expect(s.refused == refusals && refusals >= 5, "refused \(s.refused), handed over refused \(refusals)")
    expect(s.duplicates == dupNotices && dupNotices >= 2, "duplicates \(s.duplicates), expected \(dupNotices)")
    let failed = s.handOvers.filter { s.failOutput($0.frame) }.count
    expect(s.errors == failed + dupNotices && failed >= 5, "errors \(s.errors), expected \(failed) failed outputs and \(dupNotices) duplicate notices")
    expect(Set(s.outputs.map(\.frame.serial)).count == s.outputs.count, "a frame was output twice")
    let pts = s.handOvers.map(\.pts)
    expect(zip(pts, pts.dropFirst()).allSatisfy { CMTimeCompare($0, $1) < 0 }, "random turnarounds: timestamps went backwards")
    expect(s.maxVTHolds == 1, "random turnarounds: VideoToolbox held \(s.maxVTHolds)")
    // Every request, retries of dropped keyframes included, goes with the first frame handed over
    // after it (two requests before one hand-over share it).
    for (mark, r) in zip(s.keyframeRequestMarks, s.keyframeRequestTimes) {
        expect(mark < s.handOverLog.count && s.handOverLog[mark].keyframe, "the first frame handed over after the request at \(r) is not a keyframe")
    }
    expect(s.keyframeRequestTimes.count > 20, "only \(s.keyframeRequestTimes.count) keyframe requests")
}

// S6: a frame stuck for good: everything waits behind it, the watchdog fires 1.5 to 2.0 s after it
// went in, nothing is forwarded, handed over or let in afterwards, and the teardown is stalled.
do {
    scenarioName = "stuck frame"
    let clock = Clock()
    let s = StandIn(clock: clock, engine: .independent { $0.index == 100 ? nil : 0.009 })
    s.inOrder = true
    schedule(s, captures: captureTimes(fps: fps, from: 0, to: 6))
    s.startWatchdog(until: 8)
    clock.run(until: 8)
    let t = s.handOvers.first { $0.frame.index == 100 }?.at ?? -1
    print(line(scenarioName + String(format: ", capture 100 in at %.3f s", t), s, summary(s, from: 0.5, to: t)))
    if let hungAt = s.hungAt {
        expect(hungAt > t + 1.5 && hungAt <= t + 2.0 + 1e-9, "the watchdog fired at \(hungAt), not within (\(t + 1.5), \(t + 2.0)]")
        expect(!s.outputs.contains { $0.at > hungAt }, "output forwarded after the watchdog")
        expect(!s.handOvers.contains { $0.at > hungAt }, "a frame handed to VideoToolbox after the watchdog")
        let capturesAfter = captureTimes(fps: fps, from: 0, to: 6).filter { $0 > hungAt }.count
        expect(s.deadDrop == capturesAfter, "deadDrop \(s.deadDrop), captures after the watchdog \(capturesAfter)")
        expect(s.box.waiting == nil, "a frame waits after the watchdog")
    } else {
        expect(false, "the watchdog never fired on a frame stuck for good")
    }
    expect(s.hung == 1, "the watchdog fired \(s.hung) times")
    let teardown = s.release()
    expect(teardown == .stalled(since: t), "teardown \(teardown), not stalled since \(t)")
}

// S7: SILL_TEST_ENCODER_HANG: frame 90 waits 3 s on encodeQueue after its hand-over, before its
// encode call, then goes in and comes back. The watchdog must fire 1.5 s after it was handed over
// and the late output must not be forwarded.
do {
    scenarioName = "TestHang"
    let clock = Clock()
    let s = StandIn(clock: clock, engine: .independent { _ in 0.009 })
    s.hold = { $0 == 90 ? 3 : 0 }
    schedule(s, captures: captureTimes(fps: fps, from: 0, to: 6))
    s.startWatchdog(until: 8)
    clock.run(until: 8)
    let t = s.handOvers.first { $0.id == 90 }?.at ?? -1
    // The hand-over (the clock) is before the hold; the encode call after it.
    let tIn = s.box.inside?.id == 90 ? s.box.inside!.since : -1
    print(line(scenarioName + String(format: ", id 90 in at %.3f s", tIn), s, summary(s, from: 0.5, to: 1.4)))
    expect(t >= tIn + 3 - 1e-9, "frame 90's encode call at \(t), not 3 s after it went in at \(tIn)")
    if let hungAt = s.hungAt {
        expect(hungAt > tIn + 1.5 && hungAt <= tIn + 2.0 + 1e-9, "watchdog at \(hungAt), not within (\(tIn + 1.5), \(tIn + 2.0)]")
        expect(!s.outputs.contains { $0.at > hungAt }, "output forwarded after the watchdog")
    } else {
        expect(false, "the watchdog never fired on the held frame")
    }
    expect(s.late == 1, "late \(s.late): frame 90's output should come back late, once")
    expect(s.outputs.allSatisfy { $0.id < 90 }, "a frame after 90 was forwarded")
    let teardown = s.release()
    expect(teardown == .stalled(since: tIn), "teardown \(teardown), not stalled since \(tIn)")
}

// S8: slow but healthy: no false alarm at 1.2 s a frame, nor with frames 2 s apart.
do {
    let (_, _) = steady("1.2 s a frame", engine: .independent { _ in 1.2 }, seconds: 8)
    scenarioName = "sparse frames"
    let clock = Clock()
    let s = StandIn(clock: clock, engine: .independent { _ in 0.009 })
    schedule(s, captures: stride(from: 0.0, to: 20, by: 2).map { $0 })
    s.startWatchdog(until: 22)
    clock.run()
    expect(s.hungAt == nil && s.out == 10, "sparse frames: out \(s.out), watchdog \(s.hungAt ?? -1)")
    expectAllSettled(s)
}

// S9: EncoderProbe's giveUp (`abandon`): with the frame inside VideoToolbox (true, and the teardown
// stalled since it went in), with nothing inside (false, idle), and with the frame let in but still
// on encodeQueue behind an encode call that has not returned (false: it never goes in now, and the
// teardown is idle, as at 4fe37d4, which counted only a frame handed over).
do {
    scenarioName = "abandon, the frame inside"
    let clock = Clock()
    let s = StandIn(clock: clock, engine: .independent { $0.index == 0 ? 5 : 0.009 })
    clock.at(0) { s.capture(index: 0) }
    clock.at(0.01) { s.capture(index: 1) }
    clock.at(0.02) { s.capture(index: 2) }
    clock.run(until: 1.0)
    expect(s.vtHolds.count == 1 && s.box.waiting != nil && s.mailboxDrop == 1,
           "abandon: \(s.vtHolds.count) inside, waiting \(s.box.waiting != nil), mailboxDrop \(s.mailboxDrop)")
    expect(s.abandon(), "abandon with the frame inside returned false")
    clock.at(1.1) { s.capture(index: 3) }
    clock.run()
    expect(s.late == 1 && s.out == 0 && s.deadDrop == 1, "abandon: late \(s.late), out \(s.out), deadDrop \(s.deadDrop)")
    expect(s.release() == .stalled(since: 0), "abandon: teardown not stalled since 0")
    expectAllSettled(s)

    scenarioName = "abandon, nothing inside"
    let c2 = Clock()
    let s2 = StandIn(clock: c2, engine: .independent { _ in 0.009 })
    c2.at(0) { s2.capture(index: 0) }
    c2.run()
    expect(!s2.abandon(), "abandon with nothing inside returned true")
    expect(s2.release() == .idle, "abandon, nothing inside: teardown not idle")
    expectAllSettled(s2)

    scenarioName = "abandon, the frame still on encodeQueue"
    let c3 = Clock()
    let s3 = StandIn(clock: c3, engine: .independent { _ in 0.009 })
    s3.callBlocks = { $0 == 1 ? 0.5 : 0 }   // frame 1 is back in 9 ms, its encode call returns at 0.5 s
    c3.at(0) { s3.capture(index: 0) }
    c3.at(0.02) { s3.capture(index: 1) }    // let in as frame 2, queued behind the blocked call
    c3.run(until: 0.1)
    expect(s3.box.inside?.id == 2 && s3.box.inside?.handed == false, "abandon, on encodeQueue: inside \(String(describing: s3.box.inside))")
    expect(!s3.abandon(), "abandon with the frame still on encodeQueue returned true")
    c3.run()
    expect(s3.handOversAfterDeath == 1 && s3.handOvers.count == 1, "abandon, on encodeQueue: \(s3.handOversAfterDeath) dropped at the hand-over, \(s3.handOvers.count) encode calls")
    expect(s3.release() == .idle, "abandon, on encodeQueue: teardown not idle")
    expectAllSettled(s3)
}

// S10: keyframes and timestamps. 9 ms a frame; frame 179's encode call returns 100 ms late (its
// output is back in 9 ms), so capture 179 is let in behind it and handed over at 3.067 s. Requests:
// at 1.0 and 2.0 s while frames flow (only the flag), at 3.06 s on a still window (the last frame
// is re-encoded, stamped just after the last timestamp handed over; it waits behind capture 179,
// which takes the flag, and is then moved past it), at 3.5 s (still, nothing inside). Every
// request's flag goes with the first frame handed over after it.
do {
    scenarioName = "keyframes and timestamps"
    let clock = Clock()
    let s = StandIn(clock: clock, engine: .independent { _ in 0.009 })
    schedule(s, captures: captureTimes(fps: fps, from: 0, to: 3.0 + 1e-6))
    s.callBlocks = { $0 == 179 ? 0.1 : 0 }   // capture 178 is frame 179 (nothing waits at 9 ms)
    var marks: [Int] = []   // how many frames had been handed over at each request
    for t in [1.0, 2.0, 3.06, 3.5] { clock.at(t) { marks.append(s.handOverLog.count); s.requestKeyframe() } }
    s.startWatchdog(until: 5)
    clock.run()
    print(line("keyframes and timestamps", s, summary(s, from: 0.5, to: 2.9)))
    expectAllSettled(s)
    let pts = s.handOvers.map(\.pts)
    expect(zip(pts, pts.dropFirst()).allSatisfy { CMTimeCompare($0, $1) < 0 }, "keyframes: timestamps went backwards")
    expect(s.ptsFixed == 1, "keyframes: \(s.ptsFixed) timestamps fixed, not 1 (the re-encode behind capture 179)")
    let keyed = s.handOvers.filter(\.keyframe)
    expect(keyed.count == s.keyframeRequestTimes.count, "\(keyed.count) keyframes handed over for \(s.keyframeRequestTimes.count) requests")
    for (mark, r) in zip(marks, s.keyframeRequestTimes) {
        expect(mark < s.handOverLog.count && s.handOverLog[mark].keyframe, "the first frame handed over after the request at \(r) is not a keyframe")
    }
    expect(s.handOvers.first { $0.frame.index == 179 && !$0.frame.reencode }?.keyframe == true,
           "capture 179, let in before the request at 3.06 s and handed over after it, is not the keyframe")
    let reencodes = s.handOvers.filter { $0.frame.reencode }.count
    expect(reencodes == 2, "\(reencodes) re-encodes, expected 2 (the two requests on a still window)")
}

// S11: teardown of a live session: the frame inside VideoToolbox drained; a frame let in and still
// on encodeQueue drained too (as at 4fe37d4: nothing is inside, so the drain returns at once);
// nothing inside, idle.
do {
    scenarioName = "teardown"
    let clock = Clock()
    let s = StandIn(clock: clock, engine: .independent { _ in 0.030 })
    schedule(s, captures: captureTimes(fps: fps, from: 0, to: 2))
    clock.run(until: 1.0 + 1.0 / fps / 2)
    expect(s.vtHolds.count == 1, "teardown: \(s.vtHolds.count) inside at 1.008 s, expected 1")
    expect(s.release() == .drain, "teardown with the frame inside is not a drain")
    expect(s.vtHolds.isEmpty, "teardown: the drain left a frame inside")
    let c2 = Clock()
    let s2 = StandIn(clock: c2, engine: .independent { _ in 0.030 })
    schedule(s2, captures: captureTimes(fps: fps, from: 0, to: 1))
    c2.run()
    expect(s2.release() == .idle, "teardown with nothing inside is not idle")
    scenarioName = "teardown, the frame on encodeQueue"
    let c3 = Clock()
    let s3 = StandIn(clock: c3, engine: .independent { _ in 0.009 })
    s3.callBlocks = { $0 == 1 ? 0.5 : 0 }
    c3.at(0) { s3.capture(index: 0) }
    c3.at(0.02) { s3.capture(index: 1) }
    c3.run(until: 0.1)
    expect(s3.box.inside?.handed == false, "teardown, on encodeQueue: inside \(String(describing: s3.box.inside))")
    expect(s3.release() == .drain, "teardown of a live session with a frame on encodeQueue is not a drain")
}

// S12: an encode call that returns 1.3 s after VideoToolbox took its frame (whose output came back
// in 9 ms): the frame let in behind it waits on encodeQueue with its clock running from when it was
// let in, and the clock starts again when it is handed over, as `submittedAt` did; it then takes
// 0.8 s inside: no watchdog, since no frame was inside for 1.5 s. A call blocked for good: the frame
// behind it is timed from when it was let in, so the watchdog fires 1.5 to 2.0 s later, and the
// teardown is idle (it never went in). A call blocked 2.5 s: the watchdog fires the same, and the
// frame reaches the hand-over after it and is dropped there.
do {
    scenarioName = "slow encode call"
    let clock = Clock()
    let s = StandIn(clock: clock, engine: .independent { $0.index == 21 ? 0.8 : 0.009 })
    s.callBlocks = { $0 == 21 ? 1.3 : 0 }   // capture 20 is let in as frame 21
    schedule(s, captures: captureTimes(fps: fps, from: 0, to: 4))
    s.startWatchdog(until: 6)
    clock.run()
    print(line("slow encode call (1.3 s), then 0.8 s inside", s, summary(s, from: 2.5, to: 3.9)))
    expect(s.hungAt == nil, "slow encode call: the watchdog fired at \(s.hungAt ?? -1)")
    let c21 = s.handOverLog.first { $0.id == 22 }?.at ?? -1
    expect(abs(c21 - (20.0 / fps + 1.3)) < 1e-6, "capture 21 handed over at \(c21), not when the blocked call returned")
    expectAllSettled(s)

    for (blocked, name) in [(1_000.0, "encode call blocked for good"), (2.5, "encode call blocked 2.5 s")] {
        scenarioName = name
        let c2 = Clock()
        let s2 = StandIn(clock: c2, engine: .independent { _ in 0.009 })
        s2.callBlocks = { $0 == 30 ? blocked : 0 }   // capture 29 is frame 30; capture 30, let in behind it at 0.5 s, is frame 31
        schedule(s2, captures: captureTimes(fps: fps, from: 0, to: 4))
        s2.startWatchdog(until: 6)
        c2.run(until: 6)
        let admitted = 30.0 / fps
        if let hungAt = s2.hungAt {
            expect(hungAt > admitted + 1.5 && hungAt <= admitted + 2.0 + 1e-9, "\(name): watchdog at \(hungAt), not within 2 s of \(admitted)")
            expect(!s2.handOvers.contains { $0.at > hungAt }, "\(name): a frame handed to VideoToolbox after the watchdog")
        } else {
            expect(false, "\(name): the watchdog never fired")
        }
        expect(s2.handOversAfterDeath == (blocked < 10 ? 1 : 0), "\(name): \(s2.handOversAfterDeath) frames dropped at the hand-over")
        expect(s2.release() == .idle, "\(name): teardown not idle (the frame never went in)")
    }
}

// S13: a session stuck on its very first frame (every session through the 2026-09-22 wedge).
do {
    scenarioName = "stuck on its first frame"
    let clock = Clock()
    let s = StandIn(clock: clock, engine: .independent { $0.index == 0 ? nil : 0.009 })
    s.inOrder = true
    schedule(s, captures: captureTimes(fps: fps, from: 0, to: 4))
    s.startWatchdog(until: 5)
    clock.run(until: 5)
    print(line(scenarioName, s, summary(s, from: 0, to: 1)))
    expect(s.maxVTHolds == 1, "stuck on its first frame: VideoToolbox held \(s.maxVTHolds) frames, not 1")
    expect(s.handOvers.count == 1 && s.out == 0, "stuck on its first frame: \(s.handOvers.count) handed over, \(s.out) out")
    if let hungAt = s.hungAt {
        expect(hungAt > 1.5 && hungAt <= 2.0 + 1e-9, "stuck on its first frame: the watchdog fired at \(hungAt), not within (1.5, 2.0]")
    } else {
        expect(false, "stuck on its first frame: the watchdog never fired")
    }
    expect(s.vtHolds.count == 1, "stuck on its first frame: \(s.vtHolds.count) frames left inside, not 1")
    expect(s.release() == .stalled(since: 0), "stuck on its first frame: teardown not stalled since 0")
}

// S14: one engine doing one frame at a time, T seconds each: the watchdog fires only when a frame
// itself takes over hangAfter.
for (t, fires) in [(1.4, false), (2.0, true)] {
    scenarioName = "serial engine at \(t) s a frame"
    let clock = Clock()
    let s = StandIn(clock: clock, engine: .serial(pre: 0, chip: t, post: 0))
    s.inOrder = true
    schedule(s, captures: captureTimes(fps: fps, from: 0, to: 8))
    s.startWatchdog(until: 10)
    clock.run(until: 10)
    print(line(scenarioName, s, summary(s, from: 0, to: 8)))
    expect((s.hungAt != nil) == fires, "serial engine at \(t) s a frame: watchdog \(s.hungAt.map { "at \($0) s" } ?? "never"), expected \(fires ? "to fire" : "never")")
}

// S15: a keyframe asked for within 50 ms of the last repaint of a window that then stays still
// (a device joining, or one whose delta was dropped). No captured frame is coming to carry the
// flag, so the request is looked at again 60 ms after that repaint and the last frame re-encoded.
// While frames keep coming they carry it, and so does a frame on its way to VideoToolbox (waiting
// in the mailbox, or queued behind an encode call that has not returned): no re-encode then.
for turnaround in [0.009, 0.028] {
    for gap in [0.005, 0.020, 0.045] {
        scenarioName = "keyframe \(Int(gap * 1000)) ms after the last repaint, \(Int(turnaround * 1000)) ms a frame"
        let clock = Clock()
        let s = StandIn(clock: clock, engine: .independent { _ in turnaround })
        s.inOrder = true
        let caps = captureTimes(fps: fps, from: 0, to: 0.5)
        schedule(s, captures: caps)
        let last = caps.last!
        var requestAt = 0.0
        clock.at(last + gap) { requestAt = clock.now; s.requestKeyframe() }
        s.startWatchdog(until: 1.5)
        clock.run(until: 1.5)
        let keyed = s.handOverLog.filter { $0.keyframe && $0.at >= requestAt }
        expect(keyed.count == 1, "\(keyed.count) keyframes handed over after the request, not 1")
        if let k = keyed.first {
            expect(k.at <= last + 0.06 + turnaround + 1e-9, "the keyframe went in at \(k.at), later than 60 ms after the last repaint (\(last)) and a turnaround")
            expect(s.outputs.contains { $0.id == k.id }, "the keyframe (frame \(k.id)) never came out")
        }
        expectAllSettled(s)
    }
}
do {
    // The last repaint is still inside VideoToolbox at the second look (it takes 100 ms): it went in
    // before the request and carries nothing, so the last frame is re-encoded behind it and goes in
    // with the flag when it comes back.
    scenarioName = "keyframe while the last repaint is inside VideoToolbox"
    let clock = Clock()
    let caps = captureTimes(fps: fps, from: 0, to: 0.5)
    let lastIndex = caps.count - 1
    let s = StandIn(clock: clock, engine: .independent { $0.index == lastIndex && !$0.reencode ? 0.100 : 0.009 })
    s.inOrder = true
    schedule(s, captures: caps)
    let last = caps.last!
    clock.at(last + 0.010) { s.requestKeyframe() }
    s.startWatchdog(until: 1.5)
    clock.run()
    let keyed = s.handOvers.filter(\.keyframe)
    let key = keyed.last
    expect(keyed.count == 1 && key?.frame.reencode == true && key?.frame.index == lastIndex,
           "inside VideoToolbox: \(keyed.count) keyframes handed over, not one re-encode of the last repaint (\(key.map { "capture \($0.frame.index)\($0.frame.reencode ? ", a re-encode" : "")" } ?? "none"))")
    if let key { expect(abs(key.at - (last + 0.100)) < 1e-6, "inside VideoToolbox: the re-encode went in at \(key.at), not when the last repaint came back") }
    expectAllSettled(s)
}
do {
    // While frames keep coming, the next capture carries the flag: no re-encode.
    scenarioName = "keyframe while frames keep coming"
    let clock = Clock()
    let s = StandIn(clock: clock, engine: .independent { _ in 0.009 })
    schedule(s, captures: captureTimes(fps: fps, from: 0, to: 2))
    for t in stride(from: 0.51, to: 1.9, by: 0.2) { clock.at(t) { s.requestKeyframe() } }
    s.startWatchdog(until: 3)
    clock.run()
    expect(s.keyframeChecks == 7 && s.handOvers.filter(\.frame.reencode).isEmpty, "while frames keep coming: \(s.keyframeChecks) checks, \(s.handOvers.filter(\.frame.reencode).count) re-encodes")
    expect(s.handOvers.filter(\.keyframe).count == 7, "while frames keep coming: \(s.handOvers.filter(\.keyframe).count) keyframes handed over for 7 requests")
}
do {
    // The last repaint waits in the mailbox behind a slow frame (150 ms a frame) when the request is
    // looked at again: it carries the flag when it goes in.
    scenarioName = "keyframe while the last repaint waits in the mailbox"
    let clock = Clock()
    let s = StandIn(clock: clock, engine: .independent { _ in 0.150 })
    let caps = captureTimes(fps: fps, from: 0, to: 0.5)
    schedule(s, captures: caps)
    clock.at(caps.last! + 0.010) { s.requestKeyframe() }
    s.startWatchdog(until: 1.5)
    clock.run()
    let last = s.handOvers.last
    expect(s.handOvers.filter(\.frame.reencode).isEmpty, "waiting in the mailbox: \(s.handOvers.filter(\.frame.reencode).count) re-encodes, not 0")
    expect(last?.frame.index == caps.count - 1 && last?.keyframe == true, "waiting in the mailbox: the last repaint went in \(last?.keyframe == true ? "as" : "not as") a keyframe")
    expectAllSettled(s)
}
do {
    // The last repaint is let in but queued behind an encode call that has not returned (its frame
    // is already back) when the request is looked at again: it carries the flag when it goes in.
    scenarioName = "keyframe while the last repaint is queued behind a blocked encode call"
    let clock = Clock()
    let s = StandIn(clock: clock, engine: .independent { _ in 0.009 })
    let caps = captureTimes(fps: fps, from: 0, to: 0.5)   // 30 captures; capture 28 goes in as frame 29
    s.callBlocks = { $0 == 29 ? 0.3 : 0 }
    schedule(s, captures: caps)
    clock.at(caps.last! + 0.010) { s.requestKeyframe() }
    s.startWatchdog(until: 1.5)
    clock.run()
    let last = s.handOvers.last
    expect(s.handOvers.filter(\.frame.reencode).isEmpty, "queued: \(s.handOvers.filter(\.frame.reencode).count) re-encodes, not 0")
    expect(last?.frame.index == caps.count - 1 && last?.keyframe == true, "queued: the last repaint went in \(last?.keyframe == true ? "as" : "not as") a keyframe")
    expectAllSettled(s)
}

// S16: two keyframe requests on a still window before the first re-encode is handed over (two
// devices joining at once, or one joining as another's delta is dropped). Both re-encodes are
// stamped just after the last timestamp handed over, so alike, and the second is moved past the
// first at its hand-over. The last capture's encode call blocks encodeQueue for 0.2 s (its frame is
// back in 9 ms), so the first re-encode waits on the queue and the second in the mailbox.
do {
    scenarioName = "two re-encodes stamped alike"
    let clock = Clock()
    let s = StandIn(clock: clock, engine: .independent { _ in 0.009 })
    let caps = captureTimes(fps: fps, from: 0, to: 0.5)   // 30 captures, let in as frames 1 to 30
    s.callBlocks = { $0 == caps.count ? 0.2 : 0 }
    schedule(s, captures: caps)
    clock.at(caps.last! + 0.1) { s.requestKeyframe(); s.requestKeyframe() }
    s.startWatchdog(until: 1.5)
    clock.run()
    let reencodes = s.handOvers.filter(\.frame.reencode)
    expect(reencodes.count == 2, "\(reencodes.count) re-encodes handed over, not 2")
    if reencodes.count == 2 {
        expect(CMTimeCompare(reencodes[0].frame.pts, reencodes[1].frame.pts) == 0,
               "the two re-encodes were stamped \(CMTimeGetSeconds(reencodes[0].frame.pts)) and \(CMTimeGetSeconds(reencodes[1].frame.pts)) s: the scenario does not exercise an equal timestamp")
        expect(CMTimeCompare(reencodes[1].pts, reencodes[0].pts) > 0, "the second re-encode went in at \(CMTimeGetSeconds(reencodes[1].pts)) s, not after the first's \(CMTimeGetSeconds(reencodes[0].pts)) s")
        expect(reencodes[0].keyframe && !reencodes[1].keyframe, "the first re-encode is \(reencodes[0].keyframe ? "" : "not ")the keyframe, the second \(reencodes[1].keyframe ? "is" : "is not") one")
    }
    expect(s.ptsFixed == 1, "\(s.ptsFixed) timestamps fixed, not 1")
    let pts = s.handOvers.map(\.pts)
    expect(zip(pts, pts.dropFirst()).allSatisfy { CMTimeCompare($0, $1) < 0 }, "timestamps handed to VideoToolbox not strictly increasing")
    expectAllSettled(s)
}

// S17: EncoderMailbox on its own.
do {
    typealias B = EncoderMailbox<Int>
    scenarioName = "direct: one place"
    var o = B()
    expect(o.admit(1, now: 0) == .goesIn(id: 1), "the first frame was not let in as frame 1")
    expect(o.admit(2, now: 0.01) == .waits(replaced: false), "the second frame did not wait")
    expect(o.admit(3, now: 0.02) == .waits(replaced: true), "the third frame did not replace the second")
    expect(o.frameOnItsWay, "frames let in and waiting do not count as on their way")
    _ = o.handOver(1, pts: CMTime(value: 1, timescale: 1000), now: 0.03)
    expect(o.frameOnItsWay, "a waiting frame does not count as on its way")
    if case .next(let f, let id) = o.returned(1, now: 0.04) {
        expect(f == 3 && id == 2, "the waiting frame came in as \(f), frame \(id), not 3, frame 2")
    } else {
        expect(false, "the waiting frame did not take the place")
    }
    expect(o.inside == B.Inside(id: 2, since: 0.04, handed: false), "after the return: inside \(String(describing: o.inside))")
    expect(o.frameOnItsWay, "a frame let in and not handed over does not count as on its way")
    _ = o.handOver(2, pts: CMTime(value: 2, timescale: 1000), now: 0.05)
    expect(!o.frameOnItsWay, "a frame handed over counts as on its way")
    if case .freed = o.returned(2, now: 0.06) {} else { expect(false, "the last frame back did not free the place") }
    if case .duplicate = o.returned(2, now: 0.07) {} else { expect(false, "a second notice was not a duplicate") }
    expect(o.inside == nil && o.waiting == nil, "nothing inside and nothing waiting at the end: \(String(describing: o.inside))")

    scenarioName = "direct: an equal timestamp"
    var b = B()
    let p = CMTime(value: 1000, timescale: 1000)
    expect(b.admit(1, now: 0) == .goesIn(id: 1), "the first frame was not let in as frame 1")
    let first = b.handOver(1, pts: p, now: 0)
    expect(first == B.HandOver(pts: p, keyframe: false, ptsFixed: false), "the first hand-over: \(String(describing: first))")
    _ = b.returned(1, now: 0.01)
    expect(b.admit(2, now: 0.02) == .goesIn(id: 2), "the second frame was not let in as frame 2")
    let second = b.handOver(2, pts: p, now: 0.02)
    expect(second?.ptsFixed == true && second.map { CMTimeCompare($0.pts, p) > 0 } == true,
           "a timestamp equal to the last one went in as \(second.map { CMTimeGetSeconds($0.pts) } ?? -1) s (fixed: \(second?.ptsFixed == true)), not after 1 s")
    expect(second.map { CMTimeCompare(b.lastPTS, $0.pts) == 0 } == true, "the last timestamp is \(CMTimeGetSeconds(b.lastPTS)) s, not the one handed over")

    scenarioName = "direct: the watchdog"
    var w = B()
    _ = w.admit(1, now: 0)   // let in at 0, handed over at 1.0, never back
    _ = w.handOver(1, pts: p, now: 1.0)
    expect(!w.giveUpIfHung(now: 2.4, after: 1.5), "the watchdog fired 1.4 s after the hand-over (its clock did not start again there)")
    expect(w.giveUpIfHung(now: 2.6, after: 1.5) && w.dead, "the watchdog did not give up 1.6 s after the hand-over")
    expect(!w.giveUpIfHung(now: 3.0, after: 1.5), "the watchdog fired again on the session it gave up on")
    expect(w.teardown == .stalled(since: 1.0), "given up on with the frame inside: teardown \(w.teardown), not stalled since the hand-over")
    var q = B()
    _ = q.admit(1, now: 0)   // let in, never handed over (an encode call ahead of it never returns)
    expect(q.giveUpIfHung(now: 1.6, after: 1.5), "the watchdog did not fire on a frame let in 1.6 s ago")
    expect(q.teardown == .idle, "given up on with the frame on encodeQueue: teardown \(q.teardown), not idle (it never went in)")
    expect(q.handOver(1, pts: p, now: 2) == nil, "a frame was handed over after the watchdog")

    scenarioName = "direct: giving up"
    var a = B()
    _ = a.admit(1, now: 0)
    _ = a.handOver(1, pts: p, now: 0)
    expect(a.giveUp(), "giving up with the frame inside VideoToolbox returned false")
    expect(!a.giveUpIfHung(now: 5, after: 1.5), "the watchdog fired on a session its owner gave up on")
    expect(a.admit(2, now: 5) == .dropped, "a frame was let into a session given up on")
    if case .late = a.returned(1, now: 6) {} else { expect(false, "the frame back after giving up was not late") }
    expect(a.teardown == .stalled(since: 0), "given up on: teardown \(a.teardown), not stalled since 0")
    var e = B()
    _ = e.admit(1, now: 0)
    expect(!e.giveUp(), "giving up with the frame still on encodeQueue returned true")
    var n = B()
    expect(!n.giveUp() && n.teardown == .idle, "giving up with nothing inside: \(n.teardown)")

    scenarioName = "direct: teardown of a live session"
    var l = B()
    expect(l.teardown == .idle, "a fresh session tears down as \(l.teardown), not idle")
    _ = l.admit(1, now: 0)
    expect(l.teardown == .drain, "a live session with a frame on encodeQueue tears down as \(l.teardown), not a drain")
    _ = l.handOver(1, pts: p, now: 0)
    expect(l.teardown == .drain, "a live session with the frame inside tears down as \(l.teardown), not a drain")
}

print(failures == 0 ? "PASS: \(checks) checks" : "FAIL: \(failures) of \(checks) checks")
exit(failures == 0 ? 0 : 1)
