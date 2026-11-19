import Foundation

// MicrophoneTestHook (Sources/SillHost/MicrophoneTestHook.swift; docs/microphone-plan.md §5.3, §10.2): a test
// host's Sill Microphone, TEST ONLY. Which variables it reads and when it refuses them, their words, what its
// files say, and the file sink's WAV header byte for byte:
//   swiftc -O Sources/SillHost/MicrophoneTestHook.swift Tests/checks/mic-host/main.swift -o check
var failures = 0, checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
typealias T = MicrophoneTestHook

check(T.sinkVariable == "SILL_TEST_MIC_SINK" && T.appVariable == "SILL_TEST_MIC_APP" && T.setupVariable == "SILL_TEST_MIC_SETUP"
      && T.logVariable == "SILL_TEST_MIC_LOG", "the four variables' names")
// Nothing set: nothing, and no line (every other output stays as it was).
var r = T.read(testHost: true, environment: [:])
check(r.hook == nil && r.line == nil, "no variable: no hook, no line")
r = T.read(testHost: false, environment: [:])
check(r.hook == nil && r.line == nil, "no variable on a real host: no line either")
// Only a test host takes it.
r = T.read(testHost: false, environment: ["SILL_TEST_MIC_SINK": "dry"])
check(r.hook == nil && r.line == "SILL_TEST_MIC_SINK ignored: only a --synthetic test host takes it, never Sill.app.", "a real host refuses it with one line: \(r.line ?? "")")
r = T.read(testHost: true, environment: ["SILL_TEST_MIC_SINK": "dry"])
check(r.hook == T.Hook(sink: .dry, appFile: nil, setupFile: nil, log: false), "dry")
check(r.line == "TEST: this host takes devices' microphones (SILL_TEST_MIC_SINK): its Sill Microphone counts what it would play; an app always uses it.",
      "dry's line: \(r.line ?? "")")
r = T.read(testHost: true, environment: ["SILL_TEST_MIC_SINK": "file:/tmp/x.wav", "SILL_TEST_MIC_APP": "/tmp/app", "SILL_TEST_MIC_SETUP": "/tmp/setup",
                                         "SILL_TEST_MIC_LOG": "1"])
check(r.hook == T.Hook(sink: .file("/tmp/x.wav"), appFile: "/tmp/app", setupFile: "/tmp/setup", log: true), "file, the two files and the log")
check(r.line == "TEST: this host takes devices' microphones (SILL_TEST_MIC_SINK): its Sill Microphone writes what it would play to /tmp/x.wav; an app uses it while /tmp/app says so; set up while /tmp/setup does not say missing.",
      "file's line: \(r.line ?? "")")
check(T.read(testHost: true, environment: ["SILL_TEST_MIC_SINK": "dry", "SILL_TEST_MIC_LOG": "yes"]).hook?.log == false, "the log only with 1")
// Refused values.
for bad in ["speaker", "file:", "FILE:/x", "files:/x", "file/x", "dry ", "file:" + String(repeating: "a", count: 1025)] {
    let rb = T.read(testHost: true, environment: ["SILL_TEST_MIC_SINK": bad])
    check(rb.hook == nil && rb.line?.hasSuffix("ignored: it takes dry, or file:PATH.") == true, "\(bad.prefix(20)) refused")
}
check(T.parseSink("file:" + String(repeating: "a", count: 1024)) != nil, "a path of 1,024 bytes is taken")
// The others need the sink.
for v in [T.appVariable, T.setupVariable, T.logVariable] {
    let ro = T.read(testHost: true, environment: [v: "1"])
    check(ro.hook == nil && ro.line == "\(v) ignored: it needs SILL_TEST_MIC_SINK.", "\(v) alone: one line")
}
check(T.read(testHost: true, environment: ["SILL_TEST_MIC_SINK": ""]).line == nil, "an empty sink is not set")
// What the files say.
check(!T.appUses(nil) && !T.appUses("0") && !T.appUses("0\n") && !T.appUses("  ") && T.appUses("1") && T.appUses("zoom"), "an app uses it unless the file is missing, empty or 0")
check(T.setUp(nil) && T.setUp("ok") && T.setUp("") && !T.setUp("missing") && !T.setUp("notloaded\n") && !T.setUp("MISSING"), "set up unless missing or notloaded")
// The WAV header: 48 kHz mono 32-bit float, little endian.
let h = T.wavHeader(frames: 48_000)
check(h.count == 44, "44 bytes")
check(Array(h[0..<4]) == Array("RIFF".utf8) && Array(h[8..<16]) == Array("WAVEfmt ".utf8) && Array(h[36..<40]) == Array("data".utf8), "RIFF, WAVE, fmt and data")
func u32(_ at: Int) -> UInt32 { h[at..<(at + 4)].enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * $1.offset) } }
func u16(_ at: Int) -> UInt16 { UInt16(h[at]) | UInt16(h[at + 1]) << 8 }
check(u32(4) == 36 + 192_000 && u32(16) == 16 && u16(20) == 3 && u16(22) == 1 && u32(24) == 48_000 && u32(28) == 192_000
      && u16(32) == 4 && u16(34) == 32 && u32(40) == 192_000, "the sizes, float format 3, one channel, 48 kHz, 4 bytes a frame")
check(T.wavHeader(frames: 0).count == 44 && T.wavHeader(frames: -5) == T.wavHeader(frames: 0), "no frames, or fewer: an empty file's header")
check(T.wavHeader(frames: Int.max).count == 44, "a header never traps")

print(failures == 0 ? "mic-host: all \(checks) checks passed" : "mic-host: \(failures) of \(checks) checks FAILED")
exit(failures == 0 ? 0 : 1)
