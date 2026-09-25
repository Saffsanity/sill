import Foundation
import CoreMedia
import CoreVideo

// Encoder-free check of EncoderProbe.throughput's send/wait loop (the real
// Sources/SillHost/EncoderProbe.swift, compiled beside this file with Stats.swift) against a
// stand-in HEVCEncoder whose frames come back after programmable delays in real time. It checks
// that the test keeps exactly as many frames inside as the encoder lets in (never more: a third
// would wait in the mailbox and a fourth would push it out, so the test would wait for a frame
// that never comes), never the same surface inside twice, measures the rate with two inside, and
// gives up and counts a stuck frame as before. Nothing here links VideoToolbox.
//
//   Scripts/encoder-check/run.sh probe      (from the repository's root; also runs the hold case)
// or by hand:
//   swiftc -O -package-name sill Sources/SillHost/EncoderProbe.swift Sources/SillHost/Stats.swift \
//     Scripts/encoder-check/probe/main.swift -o .build/probe-check && .build/probe-check
//   SILL_TEST_PROBE_HOLD=0.08 .build/probe-check hold

struct ParameterSets {}

/// How the stand-in's frames come back.
enum Engine {
    case independent(Double)                 // each frame this long after it goes in
    case serial(Double)                      // one engine: this long a frame, one at a time
}
struct StandInConfig {
    static var limit = 2
    static var engine = Engine.independent(0.030)
    static var stuck: Set<Int> = []          // frame indexes (0-based, per encoder) that never come back
    static var late: [Int: Double] = [:]     // frame index -> seconds it takes instead
    static var inOrder = true                // outputs in decode order, as VideoToolbox gives them
    static var violations: [String] = []
    static var maxInside = 0
    static var encodes = 0
}

/// The parts of HEVCEncoder that EncoderProbe uses, with VideoToolbox replaced.
final class HEVCEncoder {
    var onEncoded: ((_ data: Data, _ isKeyframe: Bool, _ parameterSets: ParameterSets?) -> Void)?
    var onStalledFrameBack: ((TimeInterval) -> Void)?
    var testHoldEachFrame: TimeInterval = 0
    let maxInFlight: Int
    private let lock = NSLock()
    private var inside: [Int: (buffer: CVPixelBuffer, since: Double, back: Double?)] = [:]
    private var dead = false
    private var next = 0
    private var engineFree = 0.0
    private let queue = DispatchQueue(label: "standin.encode")
    private let start = CFAbsoluteTimeGetCurrent()
    private func now() -> Double { CFAbsoluteTimeGetCurrent() - start }

    init(width: Int, height: Int, fps: Int, bitrate: Int, prioritizeSpeed: Bool, software: Bool = false, quiet: Bool = false) throws {
        maxInFlight = software ? 1 : StandInConfig.limit
    }

    func encode(_ pixelBuffer: CVPixelBuffer, pts: CMTime) {
        lock.lock()
        StandInConfig.encodes += 1
        let index = next; next += 1
        if inside.count >= maxInFlight {
            StandInConfig.violations.append("frame \(index) sent with \(inside.count) inside (limit \(maxInFlight)): it would wait in the mailbox")
        }
        if inside.values.contains(where: { $0.buffer === pixelBuffer }) {
            StandInConfig.violations.append("frame \(index): a surface already inside went in again")
        }
        inside[index] = (pixelBuffer, now(), nil)
        StandInConfig.maxInside = max(StandInConfig.maxInside, inside.count)
        lock.unlock()
        let hold = testHoldEachFrame
        queue.async { [self] in                        // encodeQueue: serial, the hold inside it
            if hold > 0 { Thread.sleep(forTimeInterval: hold) }
            lock.lock()
            let t = now()
            var back: Double?
            if !StandInConfig.stuck.contains(index) {
                switch StandInConfig.engine {
                case .independent(let d): back = t + (StandInConfig.late[index] ?? d)
                case .serial(let d):
                    let s = max(t, engineFree); engineFree = s + (StandInConfig.late[index] ?? d); back = engineFree
                }
            }
            inside[index]?.back = back
            lock.unlock()
            guard let back else { return }
            onTime(after: max(0, back - t)) { [weak self] in self?.done(index) }
        }
    }

    private var finished: Set<Int> = []
    /// Frame `index` is encoded; in decode order it waits for every frame that went in before it.
    private func done(_ index: Int) {
        lock.lock()
        finished.insert(index)
        var out: [Int] = []
        if StandInConfig.inOrder {
            while let first = inside.keys.min(), finished.contains(first) { finished.remove(first); inside[first] = nil; out.append(first) }
        } else if inside.removeValue(forKey: index) != nil {
            finished.remove(index); out.append(index)
        }
        let forward = !dead
        lock.unlock()
        if forward { for _ in out { onEncoded?(Data(), false, nil) } }
    }

    func abandon() -> Bool {
        lock.lock(); dead = true; let any = !inside.isEmpty; lock.unlock()
        return any
    }

    deinit {
        // As HEVCEncoder's teardown: a session given up on with frames inside calls back once they
        // are all out (never while one is stuck), with the seconds since the oldest went in.
        guard dead, !inside.isEmpty else { return }
        let backs = inside.values.map(\.back)
        let since = inside.values.map(\.since).min()!
        guard backs.allSatisfy({ $0 != nil }) else { return }
        let last = backs.compactMap { $0 }.max()!
        let t = now(), callback = onStalledFrameBack
        onTime(after: max(0, last - t)) { callback?(last - since) }
    }
}

/// Runs `run` `delay` seconds from now, on time: a strict timer with no leeway. Dispatch's
/// asyncAfter may fire a share of its delay late, which frames going in one at a time add up (the
/// one-inside case read 24 to 29 fps against 33 with it, while Sill.app streamed beside).
let timerQueue = DispatchQueue(label: "standin.timers", qos: .userInteractive, attributes: .concurrent)
func onTime(after delay: Double, _ run: @escaping () -> Void) {
    let timer = DispatchSource.makeTimerSource(flags: .strict, queue: timerQueue)
    timer.schedule(deadline: .now() + delay, leeway: .nanoseconds(0))
    timer.setEventHandler { run(); timer.cancel() }
    timer.resume()
}

var failures = 0, checks = 0
func expect(_ ok: Bool, _ what: String) { checks += 1; if !ok { failures += 1; print("  FAIL: \(what)") } }
func reset(limit: Int = 2, engine: Engine, stuck: Set<Int> = [], late: [Int: Double] = [:], inOrder: Bool = true) {
    StandInConfig.limit = limit; StandInConfig.engine = engine; StandInConfig.stuck = stuck; StandInConfig.late = late
    StandInConfig.inOrder = inOrder
    StandInConfig.violations = []; StandInConfig.maxInside = 0; StandInConfig.encodes = 0
}
func run(_ name: String, width: Int = 1024, height: Int = 640) -> (ok: Bool, fps: Double?, ms: Int) {
    let r = EncoderProbe.throughput(width: width, height: height)
    print(String(format: "%-60@ ok %@  fps %@  %d ms  max inside %d  encodes %d", name as NSString, r.ok ? "yes" : "no",
                 r.fps.map { String(format: "%6.1f", $0) } ?? "     -", r.ms, StandInConfig.maxInside, StandInConfig.encodes))
    for v in StandInConfig.violations { expect(false, "\(name): \(v)") }
    return r
}

var backs: [TimeInterval] = []
let backsLock = NSLock()
EncoderProbe.onStalledProbeBack = { s in backsLock.lock(); backs.append(s); backsLock.unlock() }

if CommandLine.arguments.dropFirst().first == "hold" {
    // SILL_TEST_PROBE_HOLD=0.08: every frame waits 80 ms on the serial queue before it goes in.
    reset(engine: .independent(0.009))
    let r = run("hold 0.08 s a frame, 9 ms each, two inside")
    expect(r.ok && r.fps.map { $0 > 11 && $0 < 13 } == true, "hold 0.08: \(r.fps ?? -1) fps, not ~12")
    print(failures == 0 ? "PASS: \(checks) checks" : "FAIL: \(failures) of \(checks) checks")
    exit(failures == 0 ? 0 : 1)
}

print("== EncoderProbe.throughput against a stand-in encoder (real time)")
do {
    reset(engine: .independent(0.030))
    let r2 = run("30 ms a frame, each on its own, two inside")
    // Two frames back every 30 ms: the 7 timed frames span three or four turnarounds (78 or 58 fps).
    expect(r2.ok && r2.fps.map { $0 > 50 && $0 < 85 } == true, "two inside at 30 ms: \(r2.fps ?? -1) fps, not 50 to 85")
    expect(StandInConfig.maxInside == 2, "two inside at 30 ms: \(StandInConfig.maxInside) inside at most")
    expect(StandInConfig.encodes == 10, "\(StandInConfig.encodes) frames sent, not 10")
    reset(limit: 1, engine: .independent(0.030))
    let r1 = run("30 ms a frame, one inside (the default)")
    expect(r1.ok && r1.fps.map { $0 > 27 && $0 < 35 } == true, "one inside at 30 ms: \(r1.fps ?? -1) fps, not ~33")
    expect(StandInConfig.maxInside == 1, "one inside: \(StandInConfig.maxInside) inside at most")
    reset(engine: .serial(0.015))
    let rs = run("one engine at 15 ms a frame, two inside")
    expect(rs.ok && rs.fps.map { $0 > 58 && $0 < 70 } == true, "serial 15 ms: \(rs.fps ?? -1) fps, not ~66")
    reset(engine: .serial(0.030))
    let rs30 = run("one engine at 30 ms a frame, two inside")
    expect(rs30.ok && rs30.fps.map { $0 > 30 && $0 < 35 } == true, "serial 30 ms: \(rs30.fps ?? -1) fps, not ~33")
}
do {
    // Out of order (VideoToolbox does not do this; the test only counts returns): frames 3, 5 and 7
    // slow, the ones after them fast.
    reset(engine: .independent(0.010), late: [3: 0.040, 5: 0.040, 7: 0.040], inOrder: false)
    let r = run("returns out of order (frames 3, 5, 7 slow)")
    expect(r.ok && r.fps != nil, "out of order: not ok")
    // In decode order, the same slow frames hold the ones behind them.
    reset(engine: .independent(0.010), late: [3: 0.040, 5: 0.040, 7: 0.040])
    let r2 = run("in decode order (frames 3, 5, 7 slow)")
    expect(r2.ok && r2.fps != nil, "decode order: not ok")
}
do {
    // A frame that never comes back: no answer within 1 s, counted as stuck, never back.
    backs = []
    reset(engine: .independent(0.010), stuck: [4])
    let before = EncoderProbe.stuckProbes
    let t0 = CFAbsoluteTimeGetCurrent()
    let r = run("frame 4 never comes back")
    let waited = CFAbsoluteTimeGetCurrent() - t0
    expect(!r.ok && r.fps == nil, "stuck: ok \(r.ok)")
    expect(waited > 0.95 && waited < 1.3, "stuck: gave up after \(waited) s, not ~1 s")
    expect(EncoderProbe.stuckProbes == before + 1, "stuck: stuckProbes \(EncoderProbe.stuckProbes), not \(before + 1)")
    Thread.sleep(forTimeInterval: 0.5)
    expect(backs.isEmpty, "stuck: a stalled frame reported back")
}
do {
    // A frame 1.5 s late (a busy encoder): no answer in time, stuck until it comes back, then
    // onStalledProbeBack with the time the oldest frame inside waited.
    backs = []
    reset(engine: .independent(0.010), late: [4: 1.5])
    let before = EncoderProbe.stuckProbes
    let r = run("frame 4 back after 1.5 s")
    expect(!r.ok, "late: ok")
    expect(EncoderProbe.stuckProbes == before + 1, "late: stuckProbes \(EncoderProbe.stuckProbes), not \(before + 1)")
    Thread.sleep(forTimeInterval: 1.0)
    backsLock.lock(); let got = backs; backsLock.unlock()
    expect(got.count == 1 && got.first.map { $0 > 1.4 && $0 < 1.7 } == true, "late: came back \(got), not once after ~1.5 s")
    expect(EncoderProbe.stuckProbes == before, "late: stuckProbes \(EncoderProbe.stuckProbes) after it came back, not \(before)")
}
do {
    reset(engine: .independent(0.005))
    let ok = EncoderProbe.hardwareResponds()
    expect(ok, "hardwareResponds with a 5 ms frame: false")
}
print(failures == 0 ? "PASS: \(checks) checks" : "FAIL: \(failures) of \(checks) checks")
exit(failures == 0 ? 0 : 1)
