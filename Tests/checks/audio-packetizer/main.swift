import Foundation

// H3 of docs/audio-plan.md (the packetizer): Sources/SillHost/AudioPacketizer.swift compiled on its own
// with this file:
//   swiftc -O Sources/SillHost/AudioPacketizer.swift Tests/checks/audio-packetizer/main.swift -o check
// The packet size from the first chunk; the stamps against the anchors (±1 µs); the continuity
// tolerance at a quarter chunk ± 0.1 ms, later and earlier; a whole chunk missing; a format change;
// a segment ended with nothing flushed and nothing filled; each block out with the chunk that
// completes it; AudioSourceRule's table; PCMLayout's conversions; the first minute's tally.
var failures = 0
var checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
func near(_ a: Double, _ b: Double, _ within: Double = 1e-6) -> Bool { abs(a - b) <= within }

let rate = 48_000.0
/// A chunk of `frames` stereo frames whose samples count on from `first` (left) and its negative
/// (right), so every block says exactly which input frames it holds.
func chunk(_ frames: Int, at time: Double, first: Int, channels: Int = 2, rate: Double = rate) -> PCMChunk {
    var s: [Float] = []
    s.reserveCapacity(frames * channels)
    for f in 0..<frames {
        s.append(Float(first + f))
        if channels == 2 { s.append(-Float(first + f)) }
    }
    return PCMChunk(samples: s, channels: channels, sampleRate: rate, hostTime: time)
}
/// The input frames a block holds (its left channel).
func frames(_ b: AudioBlock) -> [Int] { stride(from: 0, to: b.samples.count, by: 2).map { Int(b.samples[$0]) } }
func contiguous(_ b: AudioBlock, from first: Int, count: Int) -> Bool { frames(b) == Array(first..<(first + count)) }

// MARK: - The packet size, from the first chunk

for (n, want) in [(480, 480), (1024, 512), (441, 480), (960, 480), (512, 512), (1536, 512), (2048, 512), (768, 480), (0, 480), (256, 480)] {
    check(AudioPacketizer.packetSize(firstChunkFrames: n) == want, "a first chunk of \(n) frames gives \(want)-frame packets")
}

// MARK: - Stamps against the anchors

do {   // 480-frame chunks, F 480, P 240: one block a chunk, block n at the host time of input frame 480 n − 240
    var p = AudioPacketizer(framesPerPacket: 480, priming: 240, channels: 2, sampleRate: rate)
    let t0 = 1000.0
    var ok = true, stamps = true, starts: [Bool] = []
    for n in 0..<50 {
        let out = p.push(chunk(480, at: t0 + Double(n) * 0.01, first: 480 * n))
        ok = ok && out.count == 1 && contiguous(out[0], from: 480 * n, count: 480) && out[0].index == n
        stamps = stamps && near(out.first?.hostTime ?? 0, t0 + Double(480 * n - 240) / rate)
        starts.append(out.first?.segmentStart ?? false)
    }
    check(ok, "480-frame chunks: one block a chunk, holding exactly its frames in order")
    check(stamps, "480-frame chunks: block n stamped at input frame 480 n − 240 (±1 µs)")
    check(starts == [true] + Array(repeating: false, count: 49), "only the first block starts a segment")
    check(p.gaps == 0, "no gap counted")
}
do {   // the first block starts the priming before the chunk: its sign
    var p = AudioPacketizer(framesPerPacket: 480, priming: 240, channels: 2, sampleRate: rate)
    let out = p.push(chunk(480, at: 50, first: 0))
    check(out.count == 1 && near(out[0].hostTime, 50 - 0.005), "the first block's stamp is 5 ms (240 frames) before its chunk: \(out.first?.hostTime ?? -1)")
}
do {   // 1024-frame chunks, F 512, P 256: two blocks a chunk
    var p = AudioPacketizer(framesPerPacket: 512, priming: 256, channels: 2, sampleRate: rate)
    let t0 = 7.25
    var ok = true, stamps = true
    for n in 0..<40 {
        let out = p.push(chunk(1024, at: t0 + Double(n * 1024) / rate, first: 1024 * n))
        ok = ok && out.count == 2 && contiguous(out[0], from: 1024 * n, count: 512) && contiguous(out[1], from: 1024 * n + 512, count: 512)
        for (k, b) in out.enumerated() { stamps = stamps && near(b.hostTime, t0 + Double((2 * n + k) * 512 - 256) / rate) }
    }
    check(ok, "1024-frame chunks: two blocks a chunk")
    check(stamps, "1024-frame chunks: block n stamped at input frame 512 n − 256")
}
do {   // 441-frame chunks, F 480: each block goes out with the chunk that completes it
    var p = AudioPacketizer(framesPerPacket: 480, priming: 240, channels: 2, sampleRate: rate)
    var counts: [Int] = [], made = 0, ok = true, stamps = true
    for n in 0..<40 {
        let out = p.push(chunk(441, at: 3 + Double(441 * n) / rate, first: 441 * n))
        counts.append(out.count)
        for b in out {
            ok = ok && contiguous(b, from: 480 * made, count: 480) && b.index == made
            stamps = stamps && near(b.hostTime, 3 + Double(480 * made - 240) / rate)
            made += 1
        }
        // Everything up to the frames this chunk brings is in a block, and nothing more.
        ok = ok && made == 441 * (n + 1) / 480
    }
    check(ok, "441-frame chunks: blocks as soon as they are complete, frames in order: \(counts)")
    check(stamps, "441-frame chunks: stamps from the anchors")
    check(counts.prefix(3) == [0, 1, 1], "441 frames complete no block, 882 one, 1323 two: \(counts.prefix(3))")
}
do {   // 960-frame chunks with 480-frame packets
    var p = AudioPacketizer(framesPerPacket: 480, priming: 240, channels: 2, sampleRate: rate)
    let a = p.push(chunk(960, at: 0, first: 0)), b = p.push(chunk(960, at: 0.02, first: 960))
    check(a.count == 2 && b.count == 2 && near(b[1].hostTime, Double(3 * 480 - 240) / rate), "960-frame chunks: two 480-frame blocks each")
}

// MARK: - Jitter: the stamps follow each chunk's own anchor

do {
    var p = AudioPacketizer(framesPerPacket: 480, priming: 240, channels: 2, sampleRate: rate)
    _ = p.push(chunk(480, at: 10, first: 0))
    // The next chunk 2 ms later than contiguous (within 2.5 ms): the same segment, stamped by its own time.
    let out = p.push(chunk(480, at: 10.012, first: 480))
    check(out.count == 1 && !out[0].segmentStart && p.gaps == 0, "2 ms late is jitter: the same segment")
    // Block 1's first frame is input frame 240, in the first chunk (frames 0–479): the first anchor.
    check(near(out[0].hostTime, 10 + 240 / rate), "a block whose frame falls in the first chunk takes the first chunk's anchor: \(out.first?.hostTime ?? -1)")
    let next = p.push(chunk(480, at: 10.022, first: 960))
    // Block 2's frame 720 falls in the second chunk (480–959), anchored at 10.012.
    check(next.count == 1 && near(next[0].hostTime, 10.012 + 240 / rate), "a block whose frame falls in the second chunk takes its anchor: \(next.first?.hostTime ?? -1)")
    check(contiguous(next[0], from: 960, count: 480), "the samples never move for the jitter")
}
do {   // a steady 2 ms late every chunk: each within the tolerance of the chunk before it, one segment
    var p = AudioPacketizer(framesPerPacket: 480, priming: 240, channels: 2, sampleRate: rate)
    var t = 0.0, starts = 0
    for n in 0..<30 {
        starts += p.push(chunk(480, at: t, first: 480 * n)).filter(\.segmentStart).count
        t += 0.012
    }
    check(starts == 1 && p.gaps == 0, "each chunk 2 ms later than the one before ended: one segment (\(starts) starts, \(p.gaps) gaps)")
}
// Jitter everywhere: every block is stamped from the chunk its first decoded frame falls in (an oracle
// over 441- and 1024-frame chunks, each chunk up to ±1 or ±1.5 ms off, well within the tolerance).
for (chunkFrames, packet, priming, spread) in [(441, 480, 240, 0.001), (1024, 512, 256, 0.0015), (480, 480, 240, 0.001)] {
    var p = AudioPacketizer(framesPerPacket: packet, priming: priming, channels: 2, sampleRate: rate)
    var seed: UInt64 = 0x5EED_0000 &+ UInt64(chunkFrames)
    func jitter() -> Double {   // a fixed pseudo-random sequence in ±spread
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return (Double(seed >> 11) / Double(1 << 53) * 2 - 1) * spread
    }
    var times: [Double] = []
    var made = 0, wrong = 0, starts = 0
    for k in 0..<200 {
        let t = 100 + Double(k * chunkFrames) / rate + jitter()
        times.append(t)
        for b in p.push(chunk(chunkFrames, at: t, first: k * chunkFrames)) {
            let x = made * packet - priming
            let c = max(0, x) / chunkFrames
            let want = times[c] + Double(x - c * chunkFrames) / rate
            if !near(b.hostTime, want) || !contiguous(b, from: made * packet, count: packet) { wrong += 1 }
            if b.segmentStart { starts += 1 }
            made += 1
        }
    }
    check(wrong == 0 && starts == 1 && p.gaps == 0,
          "\(chunkFrames)-frame chunks with jitter: every one of \(made) blocks stamped from the chunk its frame falls in (\(wrong) wrong)")
}
// The tolerance: a quarter of the chunk, ± 0.1 ms, later and earlier.
for (offset, gap) in [(0.0024, false), (0.0026, true), (-0.0024, false), (-0.0026, true), (0.0, false), (0.010, true), (-0.010, true)] {
    var p = AudioPacketizer(framesPerPacket: 480, priming: 240, channels: 2, sampleRate: rate)
    _ = p.push(chunk(480, at: 20, first: 0))
    let out = p.push(chunk(480, at: 20.01 + offset, first: 480))
    check((out.first?.segmentStart ?? false) == gap && p.gaps == (gap ? 1 : 0),
          "480 frames \(offset >= 0 ? "+" : "")\(offset * 1000) ms from contiguous: \(gap ? "a new segment" : "jitter")")
}
for (offset, gap) in [(0.0052, false), (0.0054, true), (-0.0052, false), (-0.0054, true)] {   // 1024 frames: 5.33 ms
    var p = AudioPacketizer(framesPerPacket: 512, priming: 256, channels: 2, sampleRate: rate)
    _ = p.push(chunk(1024, at: 20, first: 0))
    let out = p.push(chunk(1024, at: 20 + 1024 / rate + offset, first: 1024))
    check((out.first?.segmentStart ?? false) == gap, "1024 frames \(offset * 1000) ms from contiguous: \(gap ? "a new segment" : "jitter")")
}

// MARK: - Gaps end the segment: nothing flushed, nothing filled

do {   // a whole chunk missing
    var p = AudioPacketizer(framesPerPacket: 480, priming: 240, channels: 2, sampleRate: rate)
    _ = p.push(chunk(480, at: 0, first: 0))
    _ = p.push(chunk(480, at: 0.01, first: 480))
    let out = p.push(chunk(480, at: 0.03, first: 1440))   // the chunk at 0.02 never came
    check(out.count == 1 && out[0].segmentStart && out[0].index == 0 && p.gaps == 1, "a missing chunk: the next starts a segment")
    check(contiguous(out[0], from: 1440, count: 480), "no zeros for the gap: the new segment's block is the new chunk's frames")
    check(near(out[0].hostTime, 0.03 - 240 / rate), "the new segment is stamped from its own first chunk, priming before it")
}
do {   // what was short of a block when the gap came is dropped, not flushed
    var p = AudioPacketizer(framesPerPacket: 480, priming: 240, channels: 2, sampleRate: rate)
    var made: [AudioBlock] = []
    made += p.push(chunk(441, at: 0, first: 0))
    made += p.push(chunk(441, at: 441 / rate, first: 441))          // 882 frames: one block, 402 wait
    let late = p.push(chunk(441, at: 0.5, first: 100_000))          // a gap
    made += late
    check(made.count == 1 && late.isEmpty, "the tail of 402 frames is dropped with the gap, and the 441 after it make no block yet")
    let next = p.push(chunk(441, at: 0.5 + 441 / rate, first: 100_441))
    check(next.count == 1 && next[0].segmentStart && contiguous(next[0], from: 100_000, count: 480),
          "the segment's first block holds only its own frames: \(frames(next.first ?? AudioBlock(samples: [], index: 0, segmentStart: false, hostTime: 0)).prefix(3))")
    check(near(next[0].hostTime, 0.5 - 240 / rate), "and is stamped from its own anchor")
}
do {   // a chunk early (an overlap) ends the segment too
    var p = AudioPacketizer(framesPerPacket: 480, priming: 240, channels: 2, sampleRate: rate)
    _ = p.push(chunk(480, at: 5, first: 0))
    let out = p.push(chunk(480, at: 5.004, first: 480))
    check(out.count == 1 && out[0].segmentStart && p.gaps == 1, "a chunk 6 ms early: a new segment")
}
do {   // the gaps count, and a new segment after each
    var p = AudioPacketizer(framesPerPacket: 480, priming: 240, channels: 2, sampleRate: rate)
    var starts = 0, t = 0.0
    for n in 0..<20 {
        if n == 5 || n == 12 { t += 0.05 }
        starts += p.push(chunk(480, at: t, first: 480 * n)).filter(\.segmentStart).count
        t += 0.01
    }
    check(starts == 3 && p.gaps == 2, "two gaps: three segments, two counted (\(starts), \(p.gaps))")
}

// MARK: - A format change

do {
    var p = AudioPacketizer(framesPerPacket: 480, priming: 240, channels: 2, sampleRate: rate)
    _ = p.push(chunk(480, at: 0, first: 0))
    check(!p.takes(chunk(480, at: 0.01, first: 480, rate: 44_100)), "another rate is another epoch")
    check(!p.takes(chunk(480, at: 0.01, first: 480, channels: 1)), "another channel count is another epoch")
    check(p.push(chunk(480, at: 0.01, first: 480, rate: 44_100)).isEmpty, "a chunk of another format is ignored")
    let out = p.push(chunk(480, at: 0.01, first: 480))
    check(out.count == 1 && !out[0].segmentStart && p.gaps == 0, "and changes nothing for the next chunk of this format")
    check(p.push(PCMChunk(samples: [], channels: 2, sampleRate: rate, hostTime: 9)).isEmpty && p.gaps == 0, "an empty chunk is ignored")
}

// MARK: - AudioSourceRule

typealias R = AudioSourceRule
let safari = AudioKey.app(pid: 501, name: "Safari"), safariRenamed = AudioKey.app(pid: 501, name: "Safari Technology Preview")
let music = AudioKey.app(pid: 777, name: "Music")
func rule(_ current: AudioKey, _ phase: R.Phase, since: Double = 0, _ wanted: AudioKey) -> R.Action {
    R.decide(current: current, phase: phase, lastStartAt: 100, wanted: wanted, now: 100 + since)
}
check(rule(.none, .idle, .none) == .keep, "none, and none wanted: nothing")
check(rule(.none, .idle, safari) == .start, "none, an app wanted: start")
check(rule(safari, .running, safariRenamed) == .keep, "the same app (by pid), running: kept (a resize, a rotation, another window of it)")
check(rule(safari, .starting, safari) == .keep, "the same app starting: kept")
check(rule(safari, .ended, since: 5, safari) == .keep, "the same app ended 5 s after its start: not yet")
check(rule(safari, .ended, since: 9.99, safari) == .keep, "…9.99 s: not yet")
check(rule(safari, .ended, since: 10, safari) == .start, "…10 s: started again")
check(rule(safari, .ended, since: 60, safari) == .start, "…a minute: started again")
check(rule(safari, .running, music) == .start, "another app: a new stream")
check(rule(safari, .ended, since: 1, music) == .start, "another app after one that ended: at once")
check(rule(safari, .running, .desktop) == .start, "the Desktop after an app: a new stream")
check(rule(.desktop, .running, .desktop) == .keep && rule(.test, .running, .test) == .keep, "the Desktop and the tone kept while running")
check(rule(.desktop, .running, .test) == .start && rule(.test, .running, .desktop) == .start, "the tone and the Desktop are different sources")
check(rule(safari, .running, .none) == .stop && rule(safari, .starting, .none) == .stop && rule(safari, .ended, .none) == .stop,
      "none wanted: stop, whatever the phase")
check(R.retryInterval == 10, "the retry is 10 s")
check(safari == safariRenamed && safari != music && AudioKey.desktop != .test && AudioKey.none != .desktop, "keys: an app by its pid")

// MARK: - PCMLayout

let floatPlanar = PCMLayout.from(formatID: PCMLayout.linearPCM, flags: 1 | 8 | 32, bitsPerChannel: 32, channels: 2)
check(floatPlanar == PCMLayout(sample: .float32, channels: 2, interleaved: false) && floatPlanar?.description == "32-bit float, non-interleaved",
      "ScreenCaptureKit's documented buffer: 32-bit float, a buffer per channel")
check(PCMLayout.from(formatID: PCMLayout.linearPCM, flags: 4 | 8, bitsPerChannel: 16, channels: 2) == PCMLayout(sample: .int16, channels: 2, interleaved: true),
      "16-bit signed integers, interleaved")
check(PCMLayout.from(formatID: PCMLayout.linearPCM, flags: 4, bitsPerChannel: 32, channels: 1) == PCMLayout(sample: .int32, channels: 1, interleaved: true),
      "32-bit signed integers, mono")
check(PCMLayout.from(formatID: PCMLayout.linearPCM, flags: 1 | 2, bitsPerChannel: 32, channels: 2) == nil, "big endian: not converted")
check(PCMLayout.from(formatID: PCMLayout.linearPCM, flags: 1, bitsPerChannel: 64, channels: 2) == nil, "64-bit float: not converted")
check(PCMLayout.from(formatID: PCMLayout.linearPCM, flags: 4, bitsPerChannel: 24, channels: 2) == nil, "24-bit integers: not converted")
check(PCMLayout.from(formatID: PCMLayout.linearPCM, flags: 8, bitsPerChannel: 16, channels: 2) == nil, "unsigned integers: not converted")
check(PCMLayout.from(formatID: 0x6161_6320, flags: 0, bitsPerChannel: 0, channels: 2) == nil, "AAC: not PCM")
check(PCMLayout.from(formatID: PCMLayout.linearPCM, flags: 1, bitsPerChannel: 32, channels: 0) == nil, "no channels")
func raw<T>(_ values: [T]) -> Data { values.withUnsafeBytes { Data($0) } }
do {
    let left: [Float] = [0.5, -0.25, 1], right: [Float] = [-0.5, 0.25, -1]
    let l = raw(left), r = raw(right)
    let out = l.withUnsafeBytes { lb in r.withUnsafeBytes { rb in floatPlanar?.stereo(frames: 3, buffers: [lb, rb]) } }
    check(out == [0.5, -0.5, -0.25, 0.25, 1, -1], "planar float → interleaved stereo: \(out ?? [])")
    let short = l.withUnsafeBytes { lb in r.withUnsafeBytes { rb in floatPlanar?.stereo(frames: 4, buffers: [lb, rb]) } }
    check(short == nil, "buffers shorter than the frames: nil")
    let one = l.withUnsafeBytes { lb in floatPlanar?.stereo(frames: 3, buffers: [lb]) }
    check(one == nil, "one buffer for two planar channels: nil")
    let mono = PCMLayout(sample: .float32, channels: 1, interleaved: false)
    check(l.withUnsafeBytes { mono.stereo(frames: 3, buffers: [$0]) } == [0.5, 0.5, -0.25, -0.25, 1, 1], "mono doubled into both channels")
    let six = PCMLayout(sample: .float32, channels: 6, interleaved: true)
    let sixFrames = raw((0..<12).map { Float($0) })
    check(sixFrames.withUnsafeBytes { six.stereo(frames: 2, buffers: [$0]) } == [0, 1, 6, 7], "six channels: the first two")
    let ints = PCMLayout(sample: .int16, channels: 2, interleaved: true)
    let i16 = raw([Int16.max, Int16.min, 16_384, 0] as [Int16])
    let got = i16.withUnsafeBytes { ints.stereo(frames: 2, buffers: [$0]) } ?? []
    check(got.count == 4 && near(Double(got[0]), 32_767.0 / 32_768) && got[1] == -1 && got[2] == 0.5 && got[3] == 0,
          "16-bit integers scaled by 32,768: \(got)")
    let i32 = raw([Int32.min, Int32.max / 2 + 1] as [Int32])
    let got32 = i32.withUnsafeBytes { PCMLayout(sample: .int32, channels: 1, interleaved: true).stereo(frames: 2, buffers: [$0]) } ?? []
    check(got32 == [-1, -1, 0.5, 0.5], "32-bit integers scaled by 2^31, mono doubled: \(got32)")
}

// MARK: - The first minute's tally

do {
    var t = AudioBufferTally()
    var time = 0.0
    for n in 0..<100 {
        let jitter = n == 40 ? 0.0003 : 0
        t.add(frames: 480, sampleRate: rate, hostTime: time + jitter, silent: n % 2 == 0)
        time += 0.01
        if n == 70 { time += 0.01 }   // a buffer lost
    }
    check(t.buffers == 100 && t.gaps == 1 && t.silent == 50, "100 buffers, one lost, half silent: \(t.buffers) \(t.gaps) \(t.silent)")
    check(near(t.worstJitter, 0.0003, 1e-9), "the worst jitter is the 0.3 ms one: \(t.worstJitter)")
    check(t.line == "Audio: first minute: 100 buffers, time stamps at most 0.3 ms from contiguous, 1 gap, 50 silent.", "the line: \(t.line)")
    var q = AudioBufferTally()
    q.add(frames: 1024, sampleRate: rate, hostTime: 0, silent: false)
    q.add(frames: 1024, sampleRate: rate, hostTime: 1024 / rate + 0.005, silent: false)
    check(q.gaps == 0 && near(q.worstJitter, 0.005) && q.line.hasSuffix("5.0 ms from contiguous, 0 gaps, 0 silent."),
          "1024-frame buffers take 5.3 ms of jitter: \(q.line)")
}

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
