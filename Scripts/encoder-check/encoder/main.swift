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

print(failures == 0 ? "PASS: \(checks) checks" : "FAIL: \(failures) of \(checks) checks")
exit(failures == 0 ? 0 : 1)
