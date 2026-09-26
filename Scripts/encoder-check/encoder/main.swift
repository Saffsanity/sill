// Encoder-free check of the real HEVCEncoder.swift (with the real EncoderMailbox.swift and
// EncoderProbe.swift) against the stand-in VideoToolbox in FakeVT.swift, in real time: capture,
// network and callback threads as the host has them. What EncoderMailbox's own check cannot see:
// the glue's threads, locks and queues, the frames a stuck encoder keeps, the keyframe's second
// look on the watchdog's queue.
//
//   Scripts/encoder-check/run.sh encoder
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

print("== the real HEVCEncoder against a stand-in VideoToolbox")

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

// E1: every kind of session (a stream's on the hardware, a probe's, the software encoder's) lets
// one frame in at a time, and none prints anything when it is made.
do {
    var held: [String: Int] = [:]
    var printed = ""
    for (name, software, quiet) in [("hardware", false, false), ("probe", false, true), ("software", true, false)] {
        FakeVT.reset(plan: { _, _, _, _ in .returnAfter(0.030) })
        var enc: HEVCEncoder?
        printed += capturingStdout { enc = makeEncoder(software: software, quiet: quiet) }
        let session = FakeVT.lastSession
        let capture = DispatchQueue(label: "capture.e1", qos: .userInteractive)
        feed(enc!, count: 12, capture: capture)
        Thread.sleep(forTimeInterval: 0.1)
        held[name] = FakeVT.lock.run { FakeVT.maxHeld[session] ?? 0 }
        withExtendedLifetime(enc) {}
    }
    print("inside at most: hardware \(held["hardware"] ?? -1), probe \(held["probe"] ?? -1), software \(held["software"] ?? -1); printed \(printed.isEmpty ? "nothing" : printed.debugDescription)")
    expect(held.values.allSatisfy { $0 == 1 } && held.count == 3, "frames inside at most: \(held), not 1 each")
    expect(printed.isEmpty, "making the sessions printed \(printed.debugDescription)")
}

// E2: a stream at 60 fps against frames that each take 30 ms, then 9 ms (outputs in decode
// order): one over the turnaround (~33 fps), then the capture rate.
for (turnaround, low, high) in [(0.030, 25.0, 34.0), (0.009, 55.0, 61.0)] {
    FakeVT.reset(plan: { _, _, _, _ in .returnAfter(turnaround) })
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
    print(String(format: "steady, %.0f ms a frame at 60 fps: %.0f fps out, at most %d inside, %d encode calls for 90 frames", turnaround * 1000, rate, held, calls.count))
    expect(held == 1, "\(Int(turnaround * 1000)) ms a frame: at most \(held) inside VideoToolbox, not 1")
    expect(rate >= low && rate <= high, "\(Int(turnaround * 1000)) ms a frame: \(rate) fps, not \(low) to \(high)")
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

// E3: what a stuck encoder keeps for good: the one frame inside it, whether it stuck on its first
// frame (every session and probe through the 2026-09-22 wedge) or mid-stream. A busy encoder
// hands everything back.
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
    expect(m.hungAt != nil && m.alive.count == 1, "stuck mid-stream: \(m.alive.count) frames kept, not 1")

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
    expect(fifth.ok == [false] && fifth.alive.count == 1, "a re-check stuck at its 5th frame keeps \(fifth.alive.count), not 1")
}

// E4: one engine doing one frame at a time, 0.9 s each: slow, not hung, so the watchdog stays
// quiet.
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
    expect(held == 1, "serial engine at 0.9 s a frame: at most \(held) inside, not 1")
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
    // (b) No stand-in deschedule: four encoders, each a still window where a keyframe request and a
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

// E6: a keyframe asked for within 50 ms of the last repaint of a window that then stays still (a
// device joining, or one whose delta was dropped). No captured frame is coming to carry the flag,
// so the request is looked at again 60 ms after that repaint (`keyframeCheck`, on the watchdog's
// queue) and the last frame re-encoded; before, nothing went in until the window next repainted.
// While repaints go on, the next one carries the flag and nothing is re-encoded, and a last
// repaint still waiting in the mailbox at the second look carries it itself.
do {
    let capture = DispatchQueue(label: "sill.capture.e6", qos: .userInteractive)
    let network = DispatchQueue(label: "sill.net.e6", qos: .userInteractive)
    /// Twelve repaints at 60 fps numbered from `base`, a keyframe request from the network queue
    /// `gap` after the last one's encode call, repaints at `repaintsAfter` seconds after it, then
    /// `watch` seconds. The session's encode calls, the forced ones among those made at or after
    /// the request, and when the last of the twelve went in.
    func run(turnaround: Double, gap: Double, repaintsAfter: [Double] = [], watch: Double = 0.5, base: Int)
        -> (calls: [Call], forced: [Call], lastAt: CFTimeInterval) {
        FakeVT.reset(plan: { _, _, _, _ in .returnAfter(turnaround) })
        let enc = makeEncoder()
        let session = FakeVT.lastSession
        var lastAt: CFTimeInterval = 0
        let start = CACurrentMediaTime() + 0.005
        for i in 0..<12 {
            sleepUntil(start + Double(i) / 60)
            autoreleasepool { capture.sync { enc.encode(makeFrame(seq: base + i), pts: CMTime(value: CMTimeValue(i), timescale: 60)) } }
            lastAt = CACurrentMediaTime()
        }
        sleepUntil(lastAt + gap)
        var requestAt: CFTimeInterval = 0
        network.sync { requestAt = CACurrentMediaTime(); enc.requestKeyframe() }
        for (k, offset) in repaintsAfter.enumerated() {
            sleepUntil(lastAt + offset)
            autoreleasepool { capture.sync { enc.encode(makeFrame(seq: base + 12 + k), pts: CMTime(value: CMTimeValue(12 + k), timescale: 60)) } }
        }
        Thread.sleep(forTimeInterval: watch)
        let calls = FakeVT.callsOf(session)
        withExtendedLifetime(enc) {}
        return (calls, calls.filter { $0.forced && $0.at >= requestAt }, lastAt)
    }
    func ms(_ t: Double) -> String { String(format: "%.0f ms", t * 1000) }
    var delays: [String] = []
    for (k, gap) in [0.005, 0.020, 0.040].enumerated() {
        let base = 400_000 + k * 100
        let r = run(turnaround: 0.009, gap: gap, base: base)
        let f = r.forced.first
        delays.append(f.map { ms($0.at - r.lastAt) } ?? "none")
        expect(r.forced.count == 1, "keyframe \(ms(gap)) after the last repaint, then still: \(r.forced.count) forced frames went in, not 1")
        expect(f?.seq == base + 11, "keyframe \(ms(gap)) after the last repaint: the forced frame is \(f.map { "\($0.seq - base)" } ?? "none"), not the last picture (11)")
        if let f { expect(f.at - r.lastAt < 0.3, "keyframe \(ms(gap)) after the last repaint: the forced frame went in \(ms(f.at - r.lastAt)) after it, not about 60 ms") }
    }
    print("a keyframe 5, 20 and 40 ms after the last repaint, then still: forced frame in \(delays.joined(separator: ", ")) after the repaint")
    // 150 ms a frame: the last repaint still waits in the mailbox at the second look, 60 ms after it.
    do {
        let base = 400_500
        let r = run(turnaround: 0.150, gap: 0.010, base: base)
        let f = r.forced.first
        print("a keyframe 10 ms after the last repaint, which waits in the mailbox behind a 150 ms frame: \(r.forced.count) forced, " +
              (f.map { "picture \($0.seq - base) with its own timestamp: \(CMTimeCompare($0.pts, CMTime(value: 11, timescale: 60)) == 0 ? "yes" : "no"), in \(ms($0.at - r.lastAt)) after the repaint" } ?? "none"))
        expect(r.forced.count == 1 && f?.seq == base + 11, "waiting in the mailbox: forced \(r.forced.map { $0.seq - base }), not the last picture (11) once")
        expect(f.map { CMTimeCompare($0.pts, CMTime(value: 11, timescale: 60)) == 0 } == true,
               "waiting in the mailbox: the forced frame went in with \(f.map { CMTimeGetSeconds($0.pts) } ?? -1) s, not the repaint's own 11/60 s (a re-encode replaced it)")
    }
    // Repaints go on after a request 5 ms after one: the next repaint carries it, nothing is re-encoded.
    do {
        let base = 400_600
        let r = run(turnaround: 0.009, gap: 0.005, repaintsAfter: (1...12).map { Double($0) / 60 }, watch: 0.3, base: base)
        let seqs = r.calls.map(\.seq)
        print("a keyframe 5 ms after a repaint while repaints go on: \(r.forced.count) forced (picture \(r.forced.map { "\($0.seq - base)" }.joined(separator: ", "))), \(seqs.count - Set(seqs).count) re-encodes")
        expect(r.forced.count == 1 && (r.forced.first?.seq ?? 0) > base + 11, "while repaints go on: forced \(r.forced.map { $0.seq - base }), not one later repaint")
        expect(Set(seqs).count == seqs.count, "while repaints go on: a picture went in twice (a re-encode)")
    }
}

print(failures == 0 ? "PASS: \(checks) checks" : "FAIL: \(failures) of \(checks) checks")
exit(failures == 0 ? 0 : 1)
