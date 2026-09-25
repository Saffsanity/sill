import Foundation
import CoreMedia

// Encoder-free check of HEVCEncoder's frame bookkeeping. Sources/SillHost/EncoderMailbox.swift (the
// real file) is compiled beside this one; `StandIn` below mirrors HEVCEncoder's glue call for call
// (enqueue, submit on a serial queue, the encode call, frameReturned from the output handler or a
// refusal, the watchdog every 0.5 s, requestKeyframe, abandon, the deinit's teardown) around a
// stand-in for VideoToolbox that returns each frame after a programmable delay, in any order, in
// virtual time. Nothing here links VideoToolbox.
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
    /// Each frame comes back `turnaround` seconds after its encode call (nil: never), whatever the
    /// others do, so a later frame can come back first.
    case independent((Frame) -> Double?)
    /// One engine: `chip` seconds a frame, one frame at a time; `pre` before it and `post` after
    /// it overlap other frames. pre 0, post 0: the whole turnaround runs one frame at a time.
    case serial(pre: Double, chip: Double, post: Double)
}

typealias Box = EncoderMailbox<Frame>

/// HEVCEncoder with VideoToolbox replaced by `engine`. Every method mirrors the real one.
final class StandIn {
    let clock: Clock
    var box: Box
    let engine: Engine
    let hangAfter: Double = 1.5      // HEVCEncoder.hangAfter
    /// Output in decode order, as VideoToolbox documents it: a frame's output waits for every
    /// frame handed over before it. False: whatever order the delays give.
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
    var created: [Int: Frame] = [:]
    var fate: [Int: String] = [:]
    private var nextSerial = 0

    init(clock: Clock, limit: Int, engine: Engine) {
        self.clock = clock
        self.engine = engine
        box = Box(limit: limit)
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

    /// While the session is live, the mailbox's frames inside are exactly those on encodeQueue or
    /// inside VideoToolbox, never more than the limit, and a waiting frame means all places are taken.
    func invariants(_ at: String) {
        guard !gone else { return }
        expect(box.inside.count <= box.places, "\(at): \(box.inside.count) inside, over the \(box.places) places open")
        expect(box.places == (box.anyReturned ? box.limit : 1), "\(at): \(box.places) places open, returned before: \(box.anyReturned)")
        if box.waiting != nil { expect(!box.dead && box.inside.count == box.places, "\(at): a frame waits while a place is free or the session is dead") }
        expect(box.handed.isSubset(of: Set(box.inside.keys)), "\(at): handed over \(box.handed.sorted()), not all inside \(box.inside.keys.sorted())")
        if !box.dead {
            let bookkept = Set(box.inside.keys), real = Set(vtHolds.keys).union(onQueue)
            expect(bookkept == real, "\(at): the mailbox has \(bookkept.sorted()) inside, the queue and VideoToolbox hold \(real.sorted())")
            expect(Set(vtHolds.keys).isSubset(of: box.handed), "\(at): VideoToolbox holds \(vtHolds.keys.sorted()), handed over \(box.handed.sorted())")
        }
    }

    // HEVCEncoder.encode(_:pts:)
    func capture(index: Int) {
        let f = newFrame(index: index, pts: cm(clock.now), capturedAt: clock.now, reencode: false)
        enqueue(f, fromCapture: true)
    }

    // HEVCEncoder.enqueue
    func enqueue(_ f: Frame, fromCapture: Bool) {
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
        invariants("enqueue")
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
        expect(vtHolds.count <= box.limit, "VideoToolbox holds \(vtHolds.count) frames at \(clock.now), over the limit of \(box.limit)")
        if !box.anyReturned { expect(vtHolds.count <= 1, "VideoToolbox holds \(vtHolds.count) frames before the session let go of one") }
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
        box.keyframeRequested = true
        let recent = clock.now - lastFrameAt < 0.05
        if !recent {
            reencodeLast()
        } else {
            clock.at(lastFrameAt + 0.05 + 0.01) { [self] in keyframeCheck() }
        }
    }

    // HEVCEncoder.keyframeCheck (on the watchdog's queue)
    func keyframeCheck() {
        guard !gone else { return }
        keyframeChecks += 1
        guard box.keyframeRequested, !box.dead, !box.frameOnItsWay, clock.now - lastFrameAt >= 0.05 else { return }
        reencodeLast()
    }

    private func reencodeLast() {
        guard let last = lastFrame else { return }
        let lastPTS = box.lastPTS
        let pts = lastPTS.isValid ? CMTimeAdd(lastPTS, CMTime(value: 1, timescale: 1000)) : cm(clock.now)
        enqueue(newFrame(index: last.index, pts: pts, capturedAt: last.capturedAt, reencode: true), fromCapture: false)
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
/// HEVCEncoder's limits: one frame inside VideoToolbox (the default, both encoders), two on the
/// hardware encoder under the plateau experiment's SILL_TEST_ENCODER_IN_FLIGHT=2.
let oneInside = 1, twoInside = 2

// MARK: - Scenarios

func steady(_ name: String, limit: Int, engine: Engine, seconds: Double = 10) -> (StandIn, Summary) {
    scenarioName = name
    let clock = Clock()
    let s = StandIn(clock: clock, limit: limit, engine: engine)
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
    let pts = s.handOvers.map(\.pts)
    expect(zip(pts, pts.dropFirst()).allSatisfy { CMTimeCompare($0, $1) < 0 }, "timestamps handed to VideoToolbox went backwards")
    return (s, m)
}

scenarioName = "limits"
print("== EncoderMailbox against a stand-in VideoToolbox, 60 fps capture")
expect(Box(limit: 1).limit == 1 && Box(limit: 2).limit == 2, "the limits are \(Box(limit: 1).limit) and \(Box(limit: 2).limit), not 1 and 2")
expect(Box(limit: 0).limit == 1, "a limit of 0 gives \(Box(limit: 0).limit), not 1")

// S1: the fast state (~9 ms a frame): nothing waits, on either limit.
do {
    let (s, m) = steady("fast state, 9 ms, two inside", limit: twoInside, engine: .independent { _ in 0.009 })
    expect(s.out == 600 && s.mailboxDrop == 0, "fast state: out \(s.out), mailboxDrop \(s.mailboxDrop)")
    expect(abs(m.latencyMax - 9) < 0.01, "fast state: latency max \(m.latencyMax) ms, not 9")
    let (s1, _) = steady("fast state, 9 ms, one inside", limit: oneInside, engine: .independent { _ in 0.009 })
    expect(s1.out == 600 && s1.mailboxDrop == 0, "fast state, one inside: out \(s1.out), mailboxDrop \(s1.mailboxDrop)")
}

// S2: the slow state, 30 ms a frame, each frame on its own (the time around the chip overlaps).
do {
    let (s, m) = steady("slow state, 30 ms, two inside", limit: twoInside, engine: .independent { _ in 0.030 })
    expect(m.rate >= 59.5 && m.rate <= 60.5, "slow state, two inside: \(m.rate) fps, not ~60")
    expect(s.out == 600 && s.mailboxDrop == 0, "slow state, two inside: out \(s.out), mailboxDrop \(s.mailboxDrop)")
    expect(s.maxVTHolds == 2, "slow state, two inside: VideoToolbox never held two (\(s.maxVTHolds))")
    expect(abs(m.latencyMedian - 30) < 0.01, "slow state, two inside: latency median \(m.latencyMedian), not 30")
    let (s1, m1) = steady("slow state, 30 ms, one inside", limit: oneInside, engine: .independent { _ in 0.030 })
    expect(m1.rate >= 32.5 && m1.rate <= 34.5, "slow state, one inside: \(m1.rate) fps, not ~33")
    expect(m1.drops >= 25 && m1.drops <= 28, "slow state, one inside: \(m1.drops) mailbox drops a second, not ~26")
    expect(s1.maxVTHolds == 1, "one inside: VideoToolbox held \(s1.maxVTHolds)")
    // The newest frame wins: a promoted frame waited at most one capture interval.
    expect(m1.latencyMax <= 30 + 1000 / fps + 0.01, "one inside: latency max \(m1.latencyMax) ms, over 30 ms plus one frame interval")
}

// S3: 40 ms a frame: two inside carry 50 fps, and the rest are mailbox drops, counted exactly.
do {
    let (s, m) = steady("40 ms, two inside", limit: twoInside, engine: .independent { _ in 0.040 })
    expect(m.rate >= 49.5 && m.rate <= 50.5, "40 ms, two inside: \(m.rate) fps, not ~50")
    expect(m.drops >= 9.5 && m.drops <= 10.5, "40 ms, two inside: \(m.drops) drops a second, not ~10")
    expect(s.maxVTHolds == 2, "40 ms: VideoToolbox held \(s.maxVTHolds)")
}

// S4: what the fix assumes. If the engine did the whole 30 ms one frame at a time, two inside
// could not beat 33 fps and would add up to a turnaround of latency; if half of it is outside the
// chip, two inside reach the capture rate. Not a property of the code: printed for the record, and
// only checked to never do worse than one inside.
do {
    let (sB2, mB2) = steady("serial engine, all 30 ms one at a time, two inside", limit: twoInside, engine: .serial(pre: 0, chip: 0.030, post: 0))
    let (_, mB1) = steady("serial engine, all 30 ms one at a time, one inside", limit: oneInside, engine: .serial(pre: 0, chip: 0.030, post: 0))
    expect(mB2.rate >= mB1.rate - 0.5, "serial engine: two inside \(mB2.rate) fps, below one inside \(mB1.rate)")
    _ = sB2
    let (_, mA2) = steady("serial chip 15 ms, 7.5 ms before and after, two inside", limit: twoInside, engine: .serial(pre: 0.0075, chip: 0.015, post: 0.0075))
    let (_, mA1) = steady("serial chip 15 ms, 7.5 ms before and after, one inside", limit: oneInside, engine: .serial(pre: 0.0075, chip: 0.015, post: 0.0075))
    expect(mA2.rate >= 59.5, "chip 15 ms with overlap: two inside \(mA2.rate) fps, not ~60")
    expect(mA1.rate <= 34.5, "chip 15 ms with overlap: one inside \(mA1.rate) fps, not ~33")
}

// S5: out-of-order returns, refusals, a duplicate notice after some refusals, rate-control drops
// and keyframe requests, on two inside.
do {
    scenarioName = "out of order"
    let clock = Clock()
    var rng = LCG(state: 42)
    var delays: [Int: Double] = [:]
    let s = StandIn(clock: clock, limit: twoInside, engine: .independent { f in
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
    print(line("out of order, 4-45 ms, refusals, errors, keyframes", s, m))
    expectAllSettled(s)
    var inversions = 0
    let position = Dictionary(uniqueKeysWithValues: s.handOvers.enumerated().map { ($0.element.id, $0.offset) })
    for (a, b) in zip(s.returnOrder, s.returnOrder.dropFirst()) where (position[a] ?? 0) > (position[b] ?? 0) { inversions += 1 }
    expect(inversions >= 50, "only \(inversions) frames came back before one handed over earlier: the scenario does not exercise out of order")
    expect(s.hungAt == nil, "out of order: the watchdog fired at \(s.hungAt ?? -1)")
    let refusals = s.handOvers.filter { s.refuse($0.frame) }.count
    let dupNotices = s.handOvers.filter { s.refuse($0.frame) && s.duplicateAfterRefusal($0.frame) }.count
    expect(s.refused == refusals && refusals >= 10, "refused \(s.refused), handed over refused \(refusals)")
    expect(s.duplicates == dupNotices && dupNotices >= 3, "duplicates \(s.duplicates), expected \(dupNotices)")
    expect(s.errors == s.handOvers.filter { s.failOutput($0.frame) }.count + dupNotices, "errors \(s.errors)")
    expect(Set(s.outputs.map(\.frame.serial)).count == s.outputs.count, "a frame was output twice")
    let pts = s.handOvers.map(\.pts)
    expect(zip(pts, pts.dropFirst()).allSatisfy { CMTimeCompare($0, $1) < 0 }, "out of order: timestamps went backwards")
    expect(s.maxVTHolds == 2, "out of order: VideoToolbox held \(s.maxVTHolds)")
}

// S6: one frame stuck for good while the other place keeps flowing (any order), and the same in
// decode order (everything behind the stuck frame waits); with one inside, everything waits.
for (limit, inOrder) in [(twoInside, false), (twoInside, true), (oneInside, true)] {
    scenarioName = "stuck frame, \(limit) inside, \(inOrder ? "decode order" : "any order")"
    let clock = Clock()
    let s = StandIn(clock: clock, limit: limit, engine: .independent { $0.index == 100 ? nil : 0.009 })
    s.inOrder = inOrder
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
    expect(teardown == .stalled(since: t), "teardown \(teardown), not stalled since \(t) (the oldest)")
}

// S7: SILL_TEST_ENCODER_HANG: frame 90 waits 3 s on encodeQueue before its encode call, then goes
// in and comes back. The watchdog must fire 1.5 s after it went in, the frame let in behind it
// must never go in, and the late one must not be forwarded.
for limit in [twoInside, oneInside] {
    scenarioName = "TestHang, \(limit) inside"
    let clock = Clock()
    let s = StandIn(clock: clock, limit: limit, engine: .independent { _ in 0.009 })
    s.hold = { $0 == 90 ? 3 : 0 }
    schedule(s, captures: captureTimes(fps: fps, from: 0, to: 6))
    s.startWatchdog(until: 8)
    clock.run(until: 8)
    let t = s.handOvers.first { $0.id == 90 }?.at ?? -1
    // The hand-over (the clock) is before the hold; the encode call after it.
    let tIn = s.box.inside[90] ?? -1
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
    if limit == twoInside {
        expect(s.handOversAfterDeath == 1, "\(s.handOversAfterDeath) frames reached the hand-over after the watchdog (the one let in behind 90 should)")
    }
    let teardown = s.release()
    expect(teardown == .stalled(since: tIn), "teardown \(teardown), not stalled since \(tIn)")
}

// S8: slow but healthy: no false alarm. 1.2 s a frame each on its own; one engine at 0.7 s a
// frame (a second frame inside waits up to 1.4 s); frames 2 s apart (nothing inside between).
do {
    let (_, _) = steady("1.2 s a frame, two inside", limit: twoInside, engine: .independent { _ in 1.2 }, seconds: 8)
    let (_, _) = steady("one engine at 0.7 s a frame, two inside", limit: twoInside, engine: .serial(pre: 0, chip: 0.7, post: 0), seconds: 8)
    scenarioName = "sparse frames"
    let clock = Clock()
    let s = StandIn(clock: clock, limit: twoInside, engine: .independent { _ in 0.009 })
    schedule(s, captures: stride(from: 0.0, to: 20, by: 2).map { $0 })
    s.startWatchdog(until: 22)
    clock.run()
    expect(s.hungAt == nil && s.out == 10, "sparse frames: out \(s.out), watchdog \(s.hungAt ?? -1)")
    expectAllSettled(s)
}

// S9: EncoderProbe's giveUp (`abandon`) with two inside (after a first frame came back: before
// that one goes in at a time), and with none.
do {
    scenarioName = "abandon"
    let clock = Clock()
    let s = StandIn(clock: clock, limit: twoInside, engine: .independent { $0.index == 1 || $0.index == 2 ? 5 : 0.009 })
    s.clock.at(0) { s.capture(index: 0) }
    s.clock.at(0.05) { s.capture(index: 1) }
    s.clock.at(0.06) { s.capture(index: 2) }
    s.clock.at(0.07) { s.capture(index: 3) }
    clock.run(until: 1.0)
    expect(s.vtHolds.count == 2 && s.box.waiting != nil, "abandon: \(s.vtHolds.count) inside, waiting \(s.box.waiting != nil)")
    expect(s.abandon(), "abandon with two inside returned false")
    s.clock.at(1.1) { s.capture(index: 4) }
    clock.run()
    expect(s.late == 2 && s.out == 1 && s.deadDrop == 1, "abandon: late \(s.late), out \(s.out), deadDrop \(s.deadDrop)")
    expect(s.release() == .stalled(since: 0.05), "abandon: teardown not stalled since 0.05")
    scenarioName = "abandon, nothing inside"
    let c2 = Clock()
    let s2 = StandIn(clock: c2, limit: twoInside, engine: .independent { _ in 0.009 })
    c2.at(0) { s2.capture(index: 0) }
    c2.run()
    expect(!s2.abandon(), "abandon with nothing inside returned true")
    expect(s2.release() == .idle, "abandon, nothing inside: teardown not idle")
    // One inside (the default): the first frame inside, the newest of the others waiting.
    scenarioName = "abandon, one inside"
    let c3 = Clock()
    let s3 = StandIn(clock: c3, limit: oneInside, engine: .independent { $0.index == 0 ? 5 : 0.009 })
    c3.at(0) { s3.capture(index: 0) }
    c3.at(0.01) { s3.capture(index: 1) }
    c3.at(0.02) { s3.capture(index: 2) }
    c3.run(until: 1.0)
    expect(s3.vtHolds.count == 1 && s3.box.waiting != nil && s3.mailboxDrop == 1,
           "abandon, one inside: \(s3.vtHolds.count) inside, waiting \(s3.box.waiting != nil), mailboxDrop \(s3.mailboxDrop)")
    expect(s3.abandon(), "abandon with one inside returned false")
    c3.at(1.1) { s3.capture(index: 3) }
    c3.run()
    expect(s3.late == 1 && s3.out == 0 && s3.deadDrop == 1, "abandon, one inside: late \(s3.late), out \(s3.out), deadDrop \(s3.deadDrop)")
    expect(s3.release() == .stalled(since: 0), "abandon, one inside: teardown not stalled since 0")
    expectAllSettled(s3)
}

// S10: keyframes and timestamps with two inside. Frames every 16.7 ms until 3.0 s, 30 ms each;
// frame 179's encode call waits 100 ms (so 180 is let in behind it, not yet handed over); then a
// still window. Requests: while frames flow (only the flag), at 3.06 s (still: the last frame is
// re-encoded, stamped just after the last timestamp handed over, which 180 then passes), at 3.5 s
// (still, nothing inside). Every request's flag goes with the first frame handed over after it.
do {
    scenarioName = "keyframes"
    let clock = Clock()
    let s = StandIn(clock: clock, limit: twoInside, engine: .independent { _ in 0.030 })
    let caps = captureTimes(fps: fps, from: 0, to: 3.0 + 1e-6)
    schedule(s, captures: caps)
    // Nothing is dropped or re-encoded before it, so capture 179 is let in as frame 180.
    s.hold = { id in id == 180 ? 0.1 : 0 }
    var marks: [Int] = []   // how many frames had been handed over at each request
    for t in [1.0, 2.0, 3.06, 3.5] { clock.at(t) { marks.append(s.handOverLog.count); s.requestKeyframe() } }
    s.startWatchdog(until: 5)
    clock.run()
    print(line("keyframes and timestamps", s, summary(s, from: 0.5, to: 2.9)))
    if ProcessInfo.processInfo.environment["DEBUG_KF"] != nil {
        for h in s.handOvers where h.at > 2.9 { print(String(format: "  hand-over id %d capture %d%@ at %.4f pts %.4f key %@", h.id, h.frame.index, h.frame.reencode ? " (re-encode)" : "", h.at, CMTimeGetSeconds(h.pts), h.keyframe ? "yes" : "no")) }
        print("  marks \(marks) requests \(s.keyframeRequestTimes)")
    }
    expectAllSettled(s)
    let pts = s.handOvers.map(\.pts)
    expect(zip(pts, pts.dropFirst()).allSatisfy { CMTimeCompare($0, $1) < 0 }, "keyframes: timestamps went backwards")
    expect(s.ptsFixed >= 1, "keyframes: no timestamp needed fixing (the scenario does not exercise the fix)")
    let keyed = s.handOvers.filter(\.keyframe)
    expect(keyed.count == s.keyframeRequestTimes.count, "\(keyed.count) keyframes handed over for \(s.keyframeRequestTimes.count) requests")
    for (mark, r) in zip(marks, s.keyframeRequestTimes) {
        expect(mark < s.handOverLog.count && s.handOverLog[mark].keyframe, "the first frame handed over after the request at \(r) is not a keyframe")
    }
    expect(s.handOvers.first { $0.frame.index == 180 && !$0.frame.reencode }?.keyframe == true,
           "capture 180, let in before the request at 3.06 s but handed over after it, is not the keyframe")
    let reencodes = s.handOvers.filter { $0.frame.reencode }.count
    expect(reencodes == 2, "\(reencodes) re-encodes, expected 2 (the two requests on a still window)")
}

// S11: teardown of a live session with two inside drains them; with nothing inside, idle.
do {
    scenarioName = "teardown"
    let clock = Clock()
    let s = StandIn(clock: clock, limit: twoInside, engine: .independent { _ in 0.030 })
    schedule(s, captures: captureTimes(fps: fps, from: 0, to: 2))
    clock.run(until: 1.0 + 1.0 / fps / 2)
    expect(s.vtHolds.count == 2, "teardown: \(s.vtHolds.count) inside at 1.008 s, expected 2")
    expect(s.release() == .drain, "teardown with two inside is not a drain")
    expect(s.vtHolds.isEmpty, "teardown: the drain left frames inside")
    let c2 = Clock()
    let s2 = StandIn(clock: c2, limit: twoInside, engine: .independent { _ in 0.030 })
    schedule(s2, captures: captureTimes(fps: fps, from: 0, to: 1))
    c2.run()
    expect(s2.release() == .idle, "teardown with nothing inside is not idle")
    scenarioName = "teardown, one inside"
    let c3 = Clock()
    let s3 = StandIn(clock: c3, limit: oneInside, engine: .independent { _ in 0.030 })
    schedule(s3, captures: captureTimes(fps: fps, from: 0, to: 2))
    c3.run(until: 1.0 + 1.0 / fps / 2)
    expect(s3.vtHolds.count == 1, "teardown, one inside: \(s3.vtHolds.count) inside at 1.008 s, expected 1")
    expect(s3.release() == .drain, "teardown with one inside is not a drain")
    expect(s3.vtHolds.isEmpty, "teardown, one inside: the drain left a frame inside")
}

// S12: an encode call that returns 1.3 s after VideoToolbox took its frame (whose output came back
// in 9 ms): the two frames let in behind it wait on encodeQueue with their clocks running from when
// they were let in, and each clock starts again when the frame is handed over, as `submittedAt` did.
// The first of them then takes 0.8 s inside: no watchdog, since no frame was inside for 1.5 s.
do {
    scenarioName = "slow encode call"
    let clock = Clock()
    let s = StandIn(clock: clock, limit: twoInside, engine: .independent { $0.index == 21 ? 0.8 : 0.009 })
    s.callBlocks = { $0 == 21 ? 1.3 : 0 }   // capture 20 is let in as frame 21
    schedule(s, captures: captureTimes(fps: fps, from: 0, to: 4))
    s.startWatchdog(until: 6)
    clock.run()
    print(line("slow encode call (1.3 s), then 0.8 s inside", s, summary(s, from: 2.5, to: 3.9)))
    expect(s.hungAt == nil, "slow encode call: the watchdog fired at \(s.hungAt ?? -1)")
    let c21 = s.handOverLog.first { $0.id == 22 }?.at ?? -1
    expect(abs(c21 - (20.0 / fps + 1.3)) < 1e-6, "capture 21 handed over at \(c21), not when the blocked call returned")
    expectAllSettled(s)
    // A call blocked for good behind a frame already back: the frame let in behind it is timed from
    // when it was let in (0.5 s: no older frame's clock, though capture 28, in since 0.467 s for
    // 1.0 s, is inside with it), so the watchdog fires at the 2.5 s tick, not at 2.0.
    scenarioName = "encode call blocked for good"
    let c2 = Clock()
    let s2 = StandIn(clock: c2, limit: twoInside, engine: .independent { $0.index == 28 ? 1.0 : 0.009 })
    s2.callBlocks = { $0 == 30 ? 1_000 : 0 }   // capture 29 is let in as frame 30
    schedule(s2, captures: captureTimes(fps: fps, from: 0, to: 4))
    s2.startWatchdog(until: 6)
    c2.run(until: 6)
    let admitted = 30.0 / fps   // capture 30, let in behind the blocked call
    if let hungAt = s2.hungAt {
        expect(hungAt > admitted + 1.5 && hungAt <= admitted + 2.0 + 1e-9, "blocked call: watchdog at \(hungAt), not within 2 s of \(admitted)")
    } else {
        expect(false, "blocked call: the watchdog never fired")
    }
}

// S13: a session stuck on its very first frame (every session through the 2026-09-22 wedge) keeps
// one frame inside whatever the limit: a second goes in only once the session has let go of one,
// so the stuck encoder holds one surface for good. Stuck mid-stream, it holds as many as the limit.
for limit in [twoInside, oneInside] {
    scenarioName = "stuck on its first frame, \(limit) inside"
    let clock = Clock()
    let s = StandIn(clock: clock, limit: limit, engine: .independent { $0.index == 0 ? nil : 0.009 })
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
    scenarioName = "stuck mid-stream, \(limit) inside"
    let c2 = Clock()
    let s2 = StandIn(clock: c2, limit: limit, engine: .independent { $0.index == 100 ? nil : 0.030 })
    s2.inOrder = true
    schedule(s2, captures: captureTimes(fps: fps, from: 0, to: 6))
    s2.startWatchdog(until: 7)
    c2.run(until: 7)
    expect(s2.hungAt != nil && s2.vtHolds.count == limit, "stuck mid-stream: \(s2.vtHolds.count) frames left inside, not \(limit)")
}

// S14: one engine doing one frame at a time, T seconds each. With two inside, the frame behind
// waits T for the engine and then takes T of its own; its clock starts again when the one ahead
// comes back, so the watchdog fires only when a frame itself takes over hangAfter, as with one
// inside. (Before, two inside fired it at 0.8, 1.0 and 1.4 s a frame: 2T from the hand-over.)
for (limit, t, fires) in [(twoInside, 0.8, false), (twoInside, 1.0, false), (twoInside, 1.4, false), (twoInside, 2.0, true),
                          (oneInside, 1.4, false), (oneInside, 2.0, true)] {
    scenarioName = "serial engine at \(t) s a frame, \(limit) inside"
    let clock = Clock()
    let s = StandIn(clock: clock, limit: limit, engine: .serial(pre: 0, chip: t, post: 0))
    s.inOrder = true
    schedule(s, captures: captureTimes(fps: fps, from: 0, to: 8))
    s.startWatchdog(until: 10)
    clock.run(until: 10)
    print(line(scenarioName, s, summary(s, from: 0, to: 8)))
    expect((s.hungAt != nil) == fires, "serial engine at \(t) s a frame, \(limit) inside: watchdog \(s.hungAt.map { "at \($0) s" } ?? "never"), expected \(fires ? "to fire" : "never")")
    if limit == twoInside, !fires { expect(s.maxVTHolds == 2, "serial engine at \(t) s: VideoToolbox never held two") }
}

// S15: a keyframe asked for within 50 ms of the last repaint of a window that then stays still
// (a device joining, or one whose delta was dropped). No captured frame is coming to carry the
// flag, so the request is looked at again 60 ms after that repaint and the last frame re-encoded.
// While frames keep coming they carry it, and so does a frame on its way to VideoToolbox (waiting
// in the mailbox, or queued behind an encode call that has not returned): no re-encode then.
for (limit, turnaround) in [(oneInside, 0.009), (oneInside, 0.028), (twoInside, 0.009), (twoInside, 0.028)] {
    for gap in [0.005, 0.020, 0.045] {
        scenarioName = "keyframe \(Int(gap * 1000)) ms after the last repaint, \(limit) inside, \(Int(turnaround * 1000)) ms a frame"
        let clock = Clock()
        let s = StandIn(clock: clock, limit: limit, engine: .independent { _ in turnaround })
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
    // While frames keep coming, the next capture carries the flag: no re-encode.
    scenarioName = "keyframe while frames keep coming"
    let clock = Clock()
    let s = StandIn(clock: clock, limit: oneInside, engine: .independent { _ in 0.009 })
    schedule(s, captures: captureTimes(fps: fps, from: 0, to: 2))
    for t in stride(from: 0.51, to: 1.9, by: 0.2) { clock.at(t) { s.requestKeyframe() } }
    s.startWatchdog(until: 3)
    clock.run()
    expect(s.keyframeChecks == 7 && s.handOvers.filter(\.frame.reencode).isEmpty, "while frames keep coming: \(s.keyframeChecks) checks, \(s.handOvers.filter(\.frame.reencode).count) re-encodes")
    expect(s.handOvers.filter(\.keyframe).count == 7, "while frames keep coming: \(s.handOvers.filter(\.keyframe).count) keyframes handed over for 7 requests")
}
do {
    // The last repaint waits in the mailbox behind a slow frame (150 ms a frame, one inside) when
    // the request is looked at again: it carries the flag when it goes in.
    scenarioName = "keyframe while the last repaint waits in the mailbox"
    let clock = Clock()
    let s = StandIn(clock: clock, limit: oneInside, engine: .independent { _ in 0.150 })
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
    let s = StandIn(clock: clock, limit: oneInside, engine: .independent { _ in 0.009 })
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

print(failures == 0 ? "PASS: \(checks) checks" : "FAIL: \(failures) of \(checks) checks")
exit(failures == 0 ? 0 : 1)
