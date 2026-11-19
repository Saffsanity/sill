import Foundation

// TEST ONLY (docs/microphone-plan.md §10.2, gates M2 to M9): where each click of Scripts/mic-check/tone.swift's
// tone was heard in a test host's file sink (SILL_TEST_MIC_SINK=file:PATH, 48 kHz mono 32-bit float), against
// the whole second it was stamped at. Compiled by build.sh with TestTone.swift (its click).
//
//   analyze WAV SAMPLE0 SPANS
//
// SAMPLE0: the wall-clock time of the file's sample 0 (the host's "Test microphone: the file's sample 0 is at"
// line). SPANS: the recordings the client sent, "FROM:TO[,FROM:TO…]" in wall-clock seconds (each epoch's sample
// 0 and the end of its last message): each whole second inside one, half a second clear of its ends, has a click.
// Prints one line per click (its delay: where it was heard minus the second it was stamped at), then
// "CLICKS found N of M; delay median D ms, min, max; after the first 2 s of each span within ±X ms of the
// median; zero runs over 2 ms between the first and last click: K".
let args = CommandLine.arguments
guard args.count == 4, let sample0 = Double(args[2]) else {
    FileHandle.standardError.write(Data("usage: analyze WAV SAMPLE0 FROM:TO[,FROM:TO…]\n".utf8)); exit(2)
}
guard let data = FileManager.default.contents(atPath: args[1]), data.count > 44 else {
    print("CLICKS found 0 of 0: no file"); exit(1)
}
let rate = 48_000.0
var samples = [Float](repeating: 0, count: (data.count - 44) / 4)
data.withUnsafeBytes { raw in
    for i in samples.indices { samples[i] = Float(bitPattern: UInt32(littleEndian: raw.load(fromByteOffset: 44 + 4 * i, as: UInt32.self))) }
}
let spans: [(Double, Double)] = args[3].split(separator: ",").compactMap { part in
    let p = part.split(separator: ":"); guard p.count == 2, let a = Double(p[0]), let b = Double(p[1]) else { return nil }
    return (a, b)
}
let click = TestTone.click(sampleRate: rate)
let energy = click.reduce(0.0) { $0 + Double($1) * Double($1) }
var delays: [(second: Double, span: Double, delay: Double)] = []
var expected = 0
for (from, to) in spans {
    var s = (from + 0.5).rounded(.up)
    while s <= to - 0.5 {
        expected += 1
        // Heard 20 to 600 ms after it was stamped.
        let lo = Int(((s + 0.020) - sample0) * rate), hi = Int(((s + 0.600) - sample0) * rate)
        if lo >= 0, hi + click.count < samples.count {
            var best = -Double.infinity, at = 0
            for i in lo...hi {
                var acc = 0.0
                for j in 0..<click.count { acc += Double(click[j]) * Double(samples[i + j]) }
                if acc > best { best = acc; at = i }
            }
            if best > 0.3 * energy {
                let d = sample0 + Double(at) / rate - s
                delays.append((s, from, d))
                print(String(format: "click %.0f: heard %.1f ms after its stamp", s, d * 1000))
            } else {
                print(String(format: "click %.0f: not found", s))
            }
        }
        s += 1
    }
}
func ms(_ x: Double) -> String { String(format: "%.1f", x * 1000) }
let sorted = delays.map(\.delay).sorted()
let median = sorted.isEmpty ? .nan : sorted[sorted.count / 2]
let settled = delays.filter { $0.second - $0.span >= 2 }.map(\.delay)
let spread = settled.map { abs($0 - median) }.max() ?? .nan
// Silence inside the sound: runs of exact zeros over 2 ms between the first and last click found.
var runs = 0
if let first = delays.first, let last = delays.last {
    let a = max(0, Int((first.second + first.delay - sample0) * rate)), b = min(samples.count, Int((last.second + last.delay - sample0) * rate))
    var run = 0
    if a < b {
        for i in a..<b {
            if samples[i] == 0 { run += 1 } else { if run > 96 { runs += 1 }; run = 0 }
        }
    }
}
print("CLICKS found \(delays.count) of \(expected); delay median \(ms(median)) ms, min \(ms(sorted.first ?? .nan)), max \(ms(sorted.last ?? .nan)); "
      + "after the first 2 s of each span within ±\(ms(spread)) ms of the median; zero runs over 2 ms between the first and last click: \(runs)")
exit(delays.count == expected && expected > 0 ? 0 : 1)
