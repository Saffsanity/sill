// Encoder-free check of the real HEVCEncoder.swift (with the real EncoderMailbox.swift and
// EncoderProbe.swift) against the stand-in VideoToolbox in FakeVT.swift, in real time: capture,
// network and callback threads as the host has them. What EncoderMailbox's own check cannot see:
// how many frames the encoder lets in by default and under SILL_TEST_ENCODER_IN_FLIGHT=2.
//
//   Scripts/encoder-check/run.sh encoder      (runs it twice: by default, and with the variable)
import Foundation
import CoreMedia
import CoreVideo
import QuartzCore

setvbuf(stdout, nil, _IOLBF, 0)
Inject.install()

var checks = 0, failures = 0
func expect(_ ok: Bool, _ what: @autoclosure () -> String) {
    checks += 1
    if !ok { failures += 1; print("  FAIL: \(what())") }
}

/// The limit this run expects on the hardware encoder.
let two = ProcessInfo.processInfo.environment["SILL_TEST_ENCODER_IN_FLIGHT"] == "2"
let hardwareLimit = two ? 2 : 1
print("== the real HEVCEncoder against a stand-in VideoToolbox, \(two ? "SILL_TEST_ENCODER_IN_FLIGHT=2 (two inside on the hardware)" : "by default (one inside)")")

func sleepUntil(_ t: CFTimeInterval) {
    let d = t - CACurrentMediaTime()
    if d > 0.002 { Thread.sleep(forTimeInterval: d - 0.0015) }
    while CACurrentMediaTime() < t {}
}

/// Runs `body` with stdout going to a pipe, and returns what it printed (a few lines at most).
func capturingStdout(_ body: () -> Void) -> String {
    fflush(stdout)
    let pipe = Pipe()
    let saved = dup(STDOUT_FILENO)
    dup2(pipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
    body()
    fflush(stdout)
    dup2(saved, STDOUT_FILENO); close(saved)
    pipe.fileHandleForWriting.closeFile()
    return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
}

func makeEncoder(software: Bool = false, quiet: Bool = false) -> HEVCEncoder {
    try! HEVCEncoder(width: 16, height: 16, fps: 60, bitrate: 1_000_000, prioritizeSpeed: false, software: software, quiet: quiet)
}

/// Output times, thread-safe.
final class Outputs {
    private let lock = UnfairLock()
    private var times: [CFTimeInterval] = []
    private var keys = 0
    func add(key: Bool) { lock.run { times.append(CACurrentMediaTime()); if key { keys += 1 } } }
    var all: [CFTimeInterval] { lock.run { times } }
    var keyframes: Int { lock.run { keys } }
}

/// Feeds `count` new frames at `fps` from a capture queue, numbered from `from`. Returns when the
/// last went in, with the time the first did.
@discardableResult
func feed(_ enc: HEVCEncoder, count: Int, fps: Double = 60, from: Int = 0, capture: DispatchQueue) -> CFTimeInterval {
    let start = CACurrentMediaTime() + 0.005
    for i in 0..<count {
        sleepUntil(start + Double(i) / fps)
        let frame = makeFrame(seq: from + i)
        capture.sync { enc.encode(frame, pts: CMTime(value: CMTimeValue(from + i), timescale: 60)) }
    }
    return start
}

// E1 (first: the "TEST:" line is once per process): how many frames each kind of session lets in.
do {
    FakeVT.reset()
    var hardware: HEVCEncoder?, hardware2: HEVCEncoder?, software: HEVCEncoder?, quiet: HEVCEncoder?
    let first = capturingStdout { hardware = makeEncoder() }
    let later = capturingStdout {
        hardware2 = makeEncoder()
        software = makeEncoder(software: true)
        quiet = makeEncoder(quiet: true)
    }
    expect(hardware?.maxInFlight == hardwareLimit, "a hardware session lets \(hardware?.maxInFlight ?? -1) in, not \(hardwareLimit)")
    expect(hardware2?.maxInFlight == hardwareLimit, "a second hardware session lets \(hardware2?.maxInFlight ?? -1) in, not \(hardwareLimit)")
    expect(quiet?.maxInFlight == hardwareLimit, "a probe's session lets \(quiet?.maxInFlight ?? -1) in, not \(hardwareLimit) as a stream's")
    expect(software?.maxInFlight == 1, "a software session lets \(software?.maxInFlight ?? -1) in, not 1")
    let line = "TEST: hardware sessions let up to 2 frames inside the encoder at once (SILL_TEST_ENCODER_IN_FLIGHT)"
    expect(first.contains(line) == two, "the first hardware session printed \(first.debugDescription), \(two ? "not" : "yet") the TEST line")
    expect(!later.contains("TEST"), "later sessions printed \(later.debugDescription)")
    print("limits: hardware \(hardware?.maxInFlight ?? -1), probe \(quiet?.maxInFlight ?? -1), software \(software?.maxInFlight ?? -1); first session printed \(first.isEmpty ? "nothing" : first.debugDescription)")
}

// E2: a stream at 60 fps against frames that each take 30 ms (overlapping, outputs in decode
// order): one inside gives one over the turnaround (~33 fps), two inside the capture rate.
do {
    FakeVT.reset(plan: { _, _, _, _ in .returnAfter(0.030) })
    let enc = makeEncoder()
    let session = FakeVT.lastSession
    let outs = Outputs()
    enc.onEncoded = { _, key, _ in outs.add(key: key) }
    let capture = DispatchQueue(label: "capture", qos: .userInteractive)
    let start = feed(enc, count: 90, capture: capture)
    Thread.sleep(forTimeInterval: 0.2)
    let window = outs.all.filter { $0 >= start + 0.5 && $0 < start + 1.5 }
    let rate = Double(window.count)
    let held = FakeVT.lock.run { FakeVT.maxHeld[session] ?? 0 }
    let calls = FakeVT.callsOf(session)
    let pts = calls.map(\.pts)
    print(String(format: "steady, 30 ms a frame at 60 fps: %.0f fps out, at most %d inside, %d encode calls for 90 frames", rate, held, calls.count))
    expect(held == hardwareLimit, "at most \(held) inside VideoToolbox, not \(hardwareLimit)")
    if two {
        expect(rate >= 54 && rate <= 61, "two inside at 30 ms: \(rate) fps, not ~60")
    } else {
        expect(rate >= 25 && rate <= 34, "one inside at 30 ms: \(rate) fps, not ~32")
    }
    expect(zip(pts, pts.dropFirst()).allSatisfy { CMTimeCompare($0, $1) < 0 }, "timestamps handed to VideoToolbox went backwards")
    expect(outs.keyframes >= 1, "no keyframe (the session's first frame is one)")
    withExtendedLifetime(enc) {}
}

/// A value shared between threads.
final class Shared<T> {
    private let lock = UnfairLock()
    private var v: T
    init(_ v: T) { self.v = v }
    var value: T { get { lock.run { v } } set { lock.run { v = newValue } } }
}

/// A stream fed at 60 fps from a capture queue, each frame a new one numbered from `base`, until
/// the watchdog reports a hang or `seconds` pass; then the owner lets go of the encoder, as the
/// coordinator does when it restarts the source. The frames still alive `settle` seconds later are
/// the ones the encoder (or the stand-in VideoToolbox) never let go of.
func streamThenRelease(base: Int, seconds: Double, settle: Double) -> (hungAt: Double?, alive: [Int]) {
    let t0 = CACurrentMediaTime()
    let hungAt = Shared<Double?>(nil)
    var enc: HEVCEncoder? = makeEncoder()
    enc!.onHung = { hungAt.value = CACurrentMediaTime() - t0 }
    let capture = DispatchQueue(label: "capture", qos: .userInteractive)
    let count = Int(seconds * 60)
    for i in 0..<count {
        sleepUntil(t0 + Double(i) / 60)
        if hungAt.value != nil { break }
        let e = enc!
        // Each in its own pool: the main thread's is never drained here, and would keep frames.
        autoreleasepool { capture.sync { e.encode(makeFrame(seq: base + i), pts: CMTime(value: CMTimeValue(i), timescale: 60)) } }
    }
    enc = nil
    Thread.sleep(forTimeInterval: settle)
    return (hungAt.value, Tracker.alive.filter { $0 >= base && $0 < base + count })
}

/// `n` re-checks' tests in a row; the test frames still alive `settle` seconds after the last.
func probesThenSettle(_ n: Int, settle: Double) -> (ok: [Bool], alive: [Int]) {
    let from = probeSeqNow + 1
    var ok: [Bool] = []
    for _ in 0..<n { autoreleasepool { ok.append(EncoderProbe.throughput(width: 16, height: 16).ok) } }
    let to = probeSeqNow
    Thread.sleep(forTimeInterval: settle)
    return (ok, Tracker.alive.filter { $0 >= from && $0 <= to })
}

// E3: what a stuck encoder keeps for good. A session stuck on its first frame (every session and
// probe through the 2026-09-22 wedge) keeps that one frame whatever the limit: a second goes in
// only once the session has let go of one. Stuck mid-stream it keeps as many as it lets in. A busy
// encoder hands everything back.
do {
    FakeVT.reset(plan: { _, call, _, software in call == 1 && !software ? .stuck : .returnAfter(0.005) })
    let r = streamThenRelease(base: 10_000, seconds: 3, settle: 0.5)
    print("stream stuck on its first frame: hung at \(r.hungAt.map { String(format: "%.2f s", $0) } ?? "never"), frames kept \(r.alive)")
    expect(r.hungAt != nil && r.alive == [10_000], "stuck on its first frame: frames kept \(r.alive), not [10000]")

    FakeVT.reset(plan: { _, call, _, software in call == 1 && !software ? .blockCall : .returnAfter(0.005) })
    let b = streamThenRelease(base: 20_000, seconds: 3, settle: 0.5)
    print("stream whose first encode call never returns: hung at \(b.hungAt.map { String(format: "%.2f s", $0) } ?? "never"), frames kept \(b.alive)")
    expect(b.hungAt != nil && b.alive == [20_000], "first call blocked: frames kept \(b.alive), not [20000]")

    FakeVT.reset(plan: { _, call, _, software in call == 50 && !software ? .stuck : .returnAfter(0.005) })
    let m = streamThenRelease(base: 30_000, seconds: 4, settle: 0.5)
    print("stream stuck at its 50th frame: hung at \(m.hungAt.map { String(format: "%.2f s", $0) } ?? "never"), frames kept \(m.alive)")
    expect(m.hungAt != nil && m.alive.count == hardwareLimit, "stuck mid-stream: \(m.alive.count) frames kept, not \(hardwareLimit)")

    FakeVT.reset(plan: { _, call, _, software in call == 50 && !software ? .returnAfter(2.5) : .returnAfter(0.005) })
    let busy = streamThenRelease(base: 40_000, seconds: 4, settle: 3.0)
    print("stream whose 50th frame comes back after 2.5 s: hung at \(busy.hungAt.map { String(format: "%.2f s", $0) } ?? "never"), frames kept \(busy.alive)")
    expect(busy.hungAt != nil && busy.alive.isEmpty, "busy: frames kept \(busy.alive) after they came back")

    FakeVT.reset(plan: { _, call, _, _ in call == 1 ? .stuck : .returnAfter(0.005) })
    let stuckBefore = EncoderProbe.stuckProbes
    let wedge = probesThenSettle(8, settle: 0.5)
    print("eight re-checks, each stuck on its first frame: ok \(wedge.ok.filter { $0 }.count) of 8, test frames kept \(wedge.alive.count), stuckProbes \(EncoderProbe.stuckProbes - stuckBefore) more")
    expect(wedge.ok.allSatisfy { !$0 } && wedge.alive.count == 8, "eight wedged re-checks keep \(wedge.alive.count) test frames, not 8")
    expect(EncoderProbe.stuckProbes - stuckBefore == 8, "eight wedged re-checks: stuckProbes up by \(EncoderProbe.stuckProbes - stuckBefore), not 8")

    FakeVT.reset(plan: { _, call, _, _ in call == 5 ? .stuck : .returnAfter(0.005) })
    let fifth = probesThenSettle(1, settle: 0.5)
    print("a re-check stuck at its 5th frame: ok \(fifth.ok), test frames kept \(fifth.alive.count)")
    expect(fifth.ok == [false] && fifth.alive.count == hardwareLimit, "a re-check stuck at its 5th frame keeps \(fifth.alive.count), not \(hardwareLimit)")
}

// E4: one engine doing one frame at a time, 0.9 s each: slow, not hung. With two inside the frame
// behind waits 0.9 s for the engine, then takes its own 0.9 s; its watchdog clock starts again when
// the one ahead comes back, so the watchdog stays quiet, as with one inside (it fired at ~2 s
// before: 1.8 s from the hand-over).
do {
    FakeVT.reset(plan: { _, _, _, _ in .returnAfter(0.9) }, serial: true)
    let hungAt = Shared<Double?>(nil)
    let enc = makeEncoder()
    let session = FakeVT.lastSession
    let t0 = CACurrentMediaTime()
    enc.onHung = { hungAt.value = CACurrentMediaTime() - t0 }
    let outs = Outputs()
    enc.onEncoded = { _, key, _ in outs.add(key: key) }
    let capture = DispatchQueue(label: "capture", qos: .userInteractive)
    feed(enc, count: 240, capture: capture)
    let held = FakeVT.lock.run { FakeVT.maxHeld[session] ?? 0 }
    print("serial engine at 0.9 s a frame for 4 s: \(outs.all.count) out, at most \(held) inside, watchdog \(hungAt.value.map { String(format: "at %.2f s", $0) } ?? "quiet")")
    expect(hungAt.value == nil, "serial engine at 0.9 s a frame: the watchdog fired at \(hungAt.value ?? -1) s")
    expect(held == hardwareLimit, "serial engine at 0.9 s a frame: at most \(held) inside, not \(hardwareLimit)")
    withExtendedLifetime(enc) {}
}

/// Frames that went into VideoToolbox after newer content (a lower number after a higher one).
func inversions(_ calls: [Call]) -> Int {
    let seqs = calls.filter { !$0.refused }.map(\.seq)
    return zip(seqs, seqs.dropFirst()).filter { $0.1 < $0.0 }.count
}

// E5: frames reach VideoToolbox in the order they were let in, whichever thread let each in.
// Deschedules are stood in for by `Inject`: the thread sleeps right after its Nth NSLock unlock.
do {
    let capture = DispatchQueue(label: "sill.capture", qos: .userInteractive)
    let network = DispatchQueue(label: "sill.net", qos: .userInteractive)
    // (a) A still window: a keyframe request on the network queue re-encodes the last frame, and a
    // repaint lands 1 ms later. The network thread sleeps 4 ms after its first or second unlock
    // (the decision and the admission were two holds, and the re-encode was queued after the
    // second: either gap let the repaint go in first, then the older picture after it).
    for sleepOn in [1, 2] {
        var inverted = 0, trials = 0
        for t in 1...10 {
            FakeVT.reset(plan: { _, _, _, _ in .returnAfter(0.009) })
            let enc = makeEncoder()
            let session = FakeVT.lastSession
            let base = 100_000 + sleepOn * 10_000 + t * 100
            for i in 1...5 {
                autoreleasepool { capture.sync { enc.encode(makeFrame(seq: base + i), pts: CMClockGetTime(CMClockGetHostTimeClock())) } }
                Thread.sleep(forTimeInterval: 1.0 / 60)
            }
            Thread.sleep(forTimeInterval: 0.08)                    // still: the request re-encodes
            let done = DispatchSemaphore(value: 0)
            network.async {
                Inject.arm(sleepOn: sleepOn, delay: 0.004)
                enc.requestKeyframe()
                Inject.disarm()
                done.signal()
            }
            Thread.sleep(forTimeInterval: 0.001)
            autoreleasepool { capture.sync { enc.encode(makeFrame(seq: base + 6), pts: CMClockGetTime(CMClockGetHostTimeClock())) } }
            done.wait()
            Thread.sleep(forTimeInterval: 0.06)
            let calls = FakeVT.callsOf(session)
            trials += 1
            if inversions(calls) > 0 { inverted += 1 }
            let pts = calls.map(\.pts)
            expect(zip(pts, pts.dropFirst()).allSatisfy { CMTimeCompare($0, $1) < 0 }, "re-encode race: timestamps went backwards")
            expect(calls.last?.seq == base + 6, "re-encode race: the last frame into VideoToolbox is \((calls.last?.seq ?? 0) - base), not the repaint (6)")
            withExtendedLifetime(enc) {}
        }
        print("a re-encode and a repaint 1 ms apart, the network thread held 4 ms after unlock \(sleepOn): older picture into VideoToolbox last in \(inverted) of \(trials)")
        expect(inverted == 0, "re-encode race (after unlock \(sleepOn)): older picture last in \(inverted) of \(trials)")
    }
    // (b) Two inside: frame A's output lets the waiting W in and its thread is held 8 ms; meanwhile
    // K, inside beside A, is refused on encodeQueue, which lets the newer C in. W went in after C.
    if two {
        var inverted = 0, trials = 0
        for t in 1...10 {
            let base = 200_000 + t * 100
            let a = base + 1, k = base + 2, w = base + 3, c = base + 4
            FakeVT.reset(plan: { _, _, seq, _ in seq == k ? .refuse(after: 0.006) : .returnAfter(0.002) })
            FakeVT.lock.run { FakeVT.injectOnOutputOf = [a: (sleepOn: 1, delay: 0.008)] }
            let enc = makeEncoder()
            let session = FakeVT.lastSession
            let outs = Outputs()
            enc.onEncoded = { _, key, _ in outs.add(key: key) }
            // A first frame back, so two may go in.
            autoreleasepool { capture.sync { enc.encode(makeFrame(seq: base), pts: CMClockGetTime(CMClockGetHostTimeClock())) } }
            while outs.all.isEmpty { Thread.sleep(forTimeInterval: 0.001) }
            for (seq, gap) in [(a, 0.0002), (k, 0.0003), (w, 0.0025), (c, 0.0)] {
                autoreleasepool { capture.sync { enc.encode(makeFrame(seq: seq), pts: CMClockGetTime(CMClockGetHostTimeClock())) } }
                if gap > 0 { Thread.sleep(forTimeInterval: gap) }
            }
            Thread.sleep(forTimeInterval: 0.05)
            let calls = FakeVT.callsOf(session)
            trials += 1
            if inversions(calls) > 0 { inverted += 1 }
            expect(calls.contains { $0.seq == k && $0.refused }, "hand-over race: K was not refused (the scenario did not run)")
            withExtendedLifetime(enc) {}
        }
        print("two inside, a waiting frame let in by an output whose thread is held 8 ms while a refusal lets a newer one in: older frame into VideoToolbox after newer in \(inverted) of \(trials)")
        expect(inverted == 0, "hand-over race: older frame after newer in \(inverted) of \(trials)")
    }
    // (c) No stand-in deschedule: four encoders, each a still window where a keyframe request and a
    // repaint are released together at a swept offset, for 2 s.
    FakeVT.reset(plan: { _, _, _, _ in .returnAfter(0.009) })
    let group = DispatchGroup()
    let tally = Shared<(trials: Int, both: Int, inverted: Int)>((0, 0, 0))
    let deadline = CACurrentMediaTime() + 2
    for e in 0..<4 {
        group.enter()
        Thread.detachNewThread {
            let enc = makeEncoder()
            let session = FakeVT.lastSession
            let cap = DispatchQueue(label: "sill.capture.\(e)", qos: .userInteractive)
            let net = DispatchQueue(label: "sill.net.\(e)", qos: .userInitiated)
            var seq = 300_000 + e * 10_000
            autoreleasepool { cap.sync { enc.encode(makeFrame(seq: seq), pts: CMClockGetTime(CMClockGetHostTimeClock())) } }
            var t = 0
            while CACurrentMediaTime() < deadline {
                Thread.sleep(forTimeInterval: 0.052)               // still for over 50 ms
                let before = FakeVT.callsOf(session).count
                seq += 1
                let frame = makeFrame(seq: seq)
                let go = UnsafeMutablePointer<Int>.allocate(capacity: 1); go.initialize(to: 0)
                let spin = (t * 37) % 400
                let pair = DispatchGroup()
                pair.enter(); pair.enter()
                net.async { while go.pointee == 0 { OSMemoryBarrier() }; enc.requestKeyframe(); pair.leave() }
                cap.async {
                    while go.pointee == 0 { OSMemoryBarrier() }
                    var x = 0; for i in 0..<spin { x &+= i }; if x == -1 { print("") }
                    enc.encode(frame, pts: CMClockGetTime(CMClockGetHostTimeClock())); pair.leave()
                }
                Thread.sleep(forTimeInterval: 0.0003)
                go.pointee = 1; OSMemoryBarrier()
                pair.wait()
                Thread.sleep(forTimeInterval: 0.03)
                go.deallocate()
                let calls = Array(FakeVT.callsOf(session).dropFirst(before))
                var v = tally.value
                v.trials += 1
                if calls.count == 2 { v.both += 1; if inversions(calls) > 0 { v.inverted += 1 } }
                tally.value = v
                t += 1
            }
            withExtendedLifetime(enc) {}
            group.leave()
        }
    }
    group.wait()
    let v = tally.value
    print("no stand-in deschedule, 4 encoders for 2 s: \(v.trials) requests beside a repaint, \(v.both) with both going in, older picture last in \(v.inverted)")
    expect(v.inverted == 0, "natural race: older picture into VideoToolbox last in \(v.inverted) of \(v.both)")
}

print(failures == 0 ? "PASS: \(checks) checks" : "FAIL: \(failures) of \(checks) checks")
exit(failures == 0 ? 0 : 1)
