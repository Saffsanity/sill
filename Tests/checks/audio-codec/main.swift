import Foundation

// H4 of docs/audio-plan.md: the host's encoder and the device's decoder in memory, with the host's
// packetizer and the test tone between them, and nothing but AudioToolbox:
//   swiftc -O Sources/SillHost/AudioEncoder.swift Sources/SillHost/AudioPacketizer.swift Sources/SillHost/TestTone.swift \
//       iOSClient/AudioDecoder.swift Tests/checks/audio-codec/main.swift -o check
// The tone goes through the packetizer and the encoder in capture-sized chunks (480 and 1024 frames),
// each packet is decoded at once, and every decoded sample is placed by its packet's stamp (the host
// time of the frame it decodes to first): each click must land at its whole second ±2 frames, a
// segment's first packet starting clean after a gap and the encoder's reset included. Then the
// packet size, the priming and the cookie read back, one packet per block from the first, a late
// join's first packet, and 5 s of a busy signal at 120–140 kbps.
var failures = 0
var checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
    else if CommandLine.arguments.contains("-v") { print("ok   \(what())") }
}

let rate = 48_000.0
let click = TestTone.click(sampleRate: rate)

/// Where each whole second's click is in a decoded timeline: the lag of the best match of the click
/// against the samples, searched ±600 frames around where the stamps put the second.
func clickOffsets(samples: [Float], firstFrameWall: Double, seconds: ClosedRange<Int>) -> [Int: Int] {
    var found: [Int: Int] = [:]
    for second in seconds {
        let want = Int(((Double(second) - firstFrameWall) * rate).rounded())
        guard want - 600 >= 0, want + 600 + click.count <= samples.count else { continue }
        var best = -Double.infinity, at = 0
        for lag in -600...600 {
            var acc = 0.0
            let start = want + lag
            for j in 0..<click.count { acc += Double(click[j]) * Double(samples[start + j]) }
            if acc > best { best = acc; at = lag }
        }
        found[second] = at
    }
    return found
}

struct Run {
    var packets = 0
    var bytes = 0
    /// The first packet after each segment start: how far its kept frames are from the tone, in dB of
    /// the difference against the signal (the codec's own error is far below −20 dB; a segment that
    /// does not start clean on both ends is about −5).
    var segmentStartErrors: [Double] = []
    var perBlock = true
    var decodedPerPacket = true
    var clicks: [Int: Int] = [:]
    var framesPerPacket = 0
    var priming = 0
    var cookie = Data()
}

/// The tone from wall time `wall0` for `seconds`, in `chunk`-frame chunks, through the packetizer and
/// the encoder, each packet decoded at once and placed on a timeline by its stamp. `gapAt`: chunks
/// dropped there (a gap of `gapChunks`), so a new segment starts; the encoder is reset for it as the
/// pipeline does, and the decoder as the device does for a segment's first packet.
func run(chunk: Int, seconds: Double, gapAt: Int? = nil, gapChunks: Int = 0) -> Run {
    var r = Run()
    let F = AudioPacketizer.packetSize(firstChunkFrames: chunk)
    guard let enc = try? AudioEncoder(framesPerPacket: F) else { check(false, "the encoder at \(F) frames"); return r }
    r.framesPerPacket = enc.framesPerPacket
    r.priming = enc.priming
    r.cookie = enc.cookie
    guard let dec = try? AudioDecoder(framesPerPacket: enc.framesPerPacket, cookie: enc.cookie) else { check(false, "the decoder"); return r }
    var packetizer = AudioPacketizer(framesPerPacket: enc.framesPerPacket, priming: enc.priming, channels: 2, sampleRate: rate)
    // The host clock and the wall clock, as SyntheticAudio maps them: frame 0 is at both.
    let host0 = 5_000.0, wall0 = 1_790_000_000.25
    let tone = TestTone(sampleRate: rate, wallAtFrame0: wall0)
    let total = Int(seconds * rate) / chunk
    // The decoded timeline, in wall-clock frames from wall0: each packet's samples at their stamp.
    var timeline = [Float](repeating: 0, count: Int((seconds + 1) * rate))
    var segmentStarts: [Int] = []
    for k in 0..<total {
        if let g = gapAt, k >= g, k < g + gapChunks { continue }
        if k == 0 || k == (gapAt ?? -1) + gapChunks { segmentStarts.append(k * chunk) }
        let c = PCMChunk(samples: tone.samples(from: k * chunk, frames: chunk), channels: 2, sampleRate: rate,
                         hostTime: host0 + Double(k * chunk) / rate)
        let blocks = packetizer.push(c)
        for b in blocks {
            if b.segmentStart { enc.reset(); dec.reset() }
            guard let packet = enc.encode(b.samples) else { r.perBlock = false; continue }
            r.packets += 1
            r.bytes += packet.count
            guard let (left, _) = dec.decode(packet) else { r.decodedPerPacket = false; continue }
            if left.count != enc.framesPerPacket { r.decodedPerPacket = false }
            // The stamp: the host time of the packet's first decoded frame, on the wall clock.
            let stamp = wall0 + (b.hostTime - host0)
            let at = Int(((stamp - wall0) * rate).rounded())
            // A segment's first `priming` frames are the codec's own, before its first captured frame.
            let skip = b.segmentStart ? enc.priming : 0
            for i in skip..<left.count where at + i >= 0 && at + i < timeline.count { timeline[at + i] = left[i] }
        }
    }
    r.clicks = clickOffsets(samples: timeline, firstFrameWall: wall0, seconds: Int(wall0.rounded(.up))...Int((wall0 + seconds).rounded(.down)))
    // Each segment's first packet, after its priming: the tone's own frames, the timeline being indexed
    // by the tone's frame (frame k at wall0 + k ÷ rate).
    for start in segmentStarts {
        let from = start, to = start + enc.framesPerPacket - enc.priming
        let want = tone.samples(from: from, frames: to - from)
        var e = 0.0, sig = 0.0
        for i in 0..<(to - from) {
            let d = Double(timeline[from + i]) - Double(want[2 * i])
            e += d * d
            sig += Double(want[2 * i]) * Double(want[2 * i])
        }
        r.segmentStartErrors.append(10 * log10(max(e, 1e-30) / max(sig, 1e-30)))
    }
    return r
}

// MARK: - 480-frame chunks: ELD 480

let a = run(chunk: 480, seconds: 6.5)
check(a.framesPerPacket == 480 && a.priming == 240, "480-frame chunks: 480 frames a packet, 240 frames of priming (\(a.framesPerPacket), \(a.priming))")
check(!a.cookie.isEmpty && a.cookie.count <= 64, "the magic cookie is there (\(a.cookie.count) bytes)")
check(a.perBlock && a.packets == 650, "one packet for every block, from the first (\(a.packets))")
check(a.decodedPerPacket, "each packet decodes on its own to 480 frames")
check(a.clicks.count == 6 && a.clicks.values.allSatisfy { abs($0) <= 2 }, "every click at its whole second ±2 frames: \(a.clicks.sorted { $0.key < $1.key })")

// MARK: - 1024-frame chunks: ELD 512

let b = run(chunk: 1024, seconds: 6.5)
check(b.framesPerPacket == 512 && b.priming == 256, "1024-frame chunks: 512 frames a packet, 256 frames of priming (\(b.framesPerPacket), \(b.priming))")
check(b.perBlock && b.decodedPerPacket, "one packet a block, 512 frames each")
check(b.clicks.count == 6 && b.clicks.values.allSatisfy { abs($0) <= 2 }, "every click at its whole second ±2 frames: \(b.clicks.sorted { $0.key < $1.key })")

// MARK: - A gap: a new segment, the encoder reset, placed by its own stamps

let g = run(chunk: 480, seconds: 6.5, gapAt: 230, gapChunks: 5)   // 50 ms missing at 2.3 s
check(g.clicks.count == 6 && g.clicks.values.allSatisfy { abs($0) <= 2 }, "after a 50 ms gap: every click still at its second ±2 frames: \(g.clicks.sorted { $0.key < $1.key })")
check(g.packets == 645, "nothing made for the gap, nothing flushed: 645 packets (\(g.packets))")
check(g.segmentStartErrors.count == 2 && g.segmentStartErrors.allSatisfy { $0 < -20 },
      "both segments start clean (the encoder and the decoder reset): the first packet's kept frames within -20 dB of the tone: \(g.segmentStartErrors.map { Int($0) })")
let g2 = run(chunk: 1024, seconds: 6.5, gapAt: 180, gapChunks: 23)   // ~0.5 s missing across a second
check(g2.clicks.values.allSatisfy { abs($0) <= 2 } && g2.clicks.count >= 5, "after a 0.5 s gap (512-frame packets): clicks at their seconds: \(g2.clicks.sorted { $0.key < $1.key })")

// MARK: - A late join: the first packet on a fresh decoder is not the signal

do {
    let enc = try! AudioEncoder(framesPerPacket: 480)
    let tone = TestTone(sampleRate: rate, wallAtFrame0: 0.5)
    var packets: [Data] = []
    for k in 0..<60 { packets.append(enc.encode(tone.samples(from: k * 480, frames: 480))!) }
    let whole = try! AudioDecoder(framesPerPacket: 480, cookie: enc.cookie)
    var reference: [[Float]] = []
    for p in packets { reference.append(whole.decode(p)!.left) }
    let late = try! AudioDecoder(framesPerPacket: 480, cookie: enc.cookie)
    func error(_ x: [Float], _ y: [Float]) -> Double {   // dB of the difference against the signal
        let e = zip(x, y).reduce(0.0) { $0 + Double(($1.0 - $1.1) * ($1.0 - $1.1)) }
        let s = y.reduce(0.0) { $0 + Double($1 * $1) }
        return 10 * log10(max(e, 1e-30) / max(s, 1e-30))
    }
    let errs = (37..<43).map { error(late.decode(packets[$0])!.left, reference[$0]) }
    check(errs[0] > -20, "a decoder joining at packet 37: its first packet is noise (\(Int(errs[0])) dB)")
    check(errs[3] < -100, "…and its fourth exact (\(Int(errs[3])) dB): the device drops the first and fades in the next")
}

// MARK: - The busy signal's rate: 5 s at 120–140 kbps

do {
    let enc = try! AudioEncoder(framesPerPacket: 480)
    var seed: UInt64 = 42
    func noise() -> Float {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Float(Double(seed >> 11) / Double(1 << 53) * 2 - 1)
    }
    var bytes = 0, packets = 0
    let n: Float = 0.063   // −24 dBFS
    for k in 0..<500 {
        var block = [Float](repeating: 0, count: 960)
        for i in 0..<480 {
            let t = Double(k * 480 + i) / rate
            let low: Double = 0.1 * sin(2 * .pi * 220 * t)
            let mid: Double = 0.07 * sin(2 * .pi * 1_375 * t)
            let high: Double = 0.05 * sin(2 * .pi * 5_100 * t)
            let tones = Float(low + mid + high)
            block[2 * i] = tones + n * noise()
            block[2 * i + 1] = tones + n * noise()
        }
        if let p = enc.encode(block) { bytes += p.count; packets += 1 }
    }
    let kbps = Double(bytes * 8) / 5 / 1000
    check(packets == 500 && (120...140).contains(kbps), "5 s of a busy signal: \(packets) packets, \(String(format: "%.1f", kbps)) kbps")
    check(enc.bitrate == 128_000, "the encoder reads back 128 kbps (\(enc.bitrate))")
}

// MARK: - What the encoder and decoder refuse

check(AudioEncoder.sampleRate == 48_000 && AudioEncoder.channels == 2 && AudioEncoder.bitrate == 128_000, "48 kHz stereo at 128 kbps")
check((try? AudioEncoder(framesPerPacket: 480))?.encode([Float](repeating: 0, count: 959)) == nil, "a block of the wrong size makes no packet")
check((try? AudioDecoder(framesPerPacket: 0, cookie: Data())) == nil, "a decoder for 0-frame packets is refused")
check(AudioDecoder.codecs == ["aac-eld"], "the decoder plays aac-eld")
check((try? AudioDecoder(framesPerPacket: 480, cookie: a.cookie))?.decode(Data()) == nil, "an empty packet decodes to nothing")

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
