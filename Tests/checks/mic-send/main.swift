import AVFAudio
import Foundation

// The device's microphone on its way to the Mac (docs/microphone-plan.md §3.4, §5.6): MicrophoneSender (a capture
// buffer in, kind 48's messages out) and MicrophoneCapture (a tap's buffers, at 48 kHz or another rate, and the
// test tone), compiled with SillAudio and StreamProtocol as one module (module.txt). On the Mac, with no audio
// device: every buffer is made here. The format; ten packets a capture buffer, the seq and the segment flag; each
// stamp the capture time of its packet's first decoded sample; every click of the tone decoded at its whole
// second ±2 frames; a gap a clean new segment; other buffer sizes; epochs and their wrap; the messages the wire
// takes and the Mac's limits take at their pace; and the capture's conversion of 16 and 24 kHz buffers.
var failures = 0, checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
let rate = 48_000.0
let clickN = Int((0.004 * rate).rounded())
let click: [Float] = (0..<clickN).map { i in
    let x = Double(i)
    return Float(pow(10, -6.0 / 20) * (0.5 - 0.5 * cos(2 * .pi * x / Double(clickN))) * sin(2 * .pi * 2_000 * x / rate))
}
let clickEnergy = click.reduce(0.0) { $0 + Double($1) * Double($1) }

/// Each whole second's click in `samples` (a timeline from wall time `wall0`): its offset in frames from where the
/// second is, searched ±300 frames.
func clicks(_ samples: [Float], wall0: Double, seconds: ClosedRange<Int>) -> [Int: Int] {
    var found: [Int: Int] = [:]
    for s in seconds {
        let want = Int(((Double(s) - wall0) * rate).rounded())
        guard want - 300 >= 0, want + 300 + clickN <= samples.count else { continue }
        var best = -Double.infinity, at = 0
        for lag in -300...300 {
            var acc = 0.0
            for j in 0..<clickN { acc += Double(click[j]) * Double(samples[want + lag + j]) }
            if acc > best { best = acc; at = lag }
        }
        if best > 0.3 * clickEnergy { found[s] = at }
    }
    return found
}

/// The messages a sender makes of `seconds` of the tone in `chunk`-frame buffers from host time `h0`, the wall
/// clock `w0` then; buffers whose index is in `gaps` are lost.
func record(_ sender: MicrophoneSender, seconds: Double, chunk: Int, h0: Double, w0: Double, gaps: Set<Int> = []) -> [StreamMessage] {
    var out: [StreamMessage] = []
    for k in 0..<Int(seconds * rate) / chunk {
        if gaps.contains(k) { continue }
        let host = h0 + Double(k * chunk) / rate
        out += sender.push(MicrophoneCapture.tone(frames: chunk, wallStart: w0 + (host - h0)), hostTime: host, wallOffset: w0 - h0)
    }
    return out
}

/// The messages decoded as the Mac would, each packet placed by its stamp on a timeline from `w0`: (timeline,
/// packets, the first packet of each segment's error against the tone in dB).
func decode(_ messages: [StreamMessage], format f: MicrophoneFormat, w0: Double, seconds: Double) -> (samples: [Float], packets: Int, ok: Bool) {
    guard let dec = try? AudioDecoder(framesPerPacket: f.format.framesPerPacket ?? 480, cookie: f.format.cookie ?? Data(), channels: 1) else { return ([], 0, false) }
    let F = f.format.framesPerPacket ?? 480, P = f.format.primingFrames ?? 0
    var timeline = [Float](repeating: 0, count: Int((seconds + 1) * rate))
    var n = 0, ok = true
    for m in messages {
        guard case .packets(let p)? = MicrophoneMessage.parse(m.payload) else { ok = false; continue }
        for (i, data) in p.packets.enumerated() {
            let segmentStart = p.segmentStart && i == 0
            if segmentStart { dec.reset() }
            guard let (l, _) = dec.decode(data), l.count == F else { ok = false; continue }
            n += 1
            let stamp = m.timestamp + Double(i * F) / rate
            let at = Int(((stamp - w0) * rate).rounded())
            let skip = segmentStart ? P : 0
            for j in skip..<l.count where at + j >= 0 && at + j < timeline.count { timeline[at + j] = l[j] }
        }
    }
    return (timeline, n, ok)
}

// MARK: - The format and the first recording

let h0 = 1_000.0, w0 = 1_800_000_000.0
let sender = MicrophoneSender(lastEpoch: 41)
check(sender.format == nil && sender.push([0.1, 0.2], hostTime: 1, wallOffset: 0).isEmpty, "no recording: nothing made")
guard let f = sender.start() else { print("FAIL: no encoder: \(sender.failure ?? "?")"); exit(1) }
check(sender.epoch == 42 && f.format.epoch == 42, "the next epoch: 42")
check(f.isValid && f.isEpoch && f.format.codec == "aac-eld" && f.format.sampleRate == 48_000 && f.format.channels == 1
      && f.format.framesPerPacket == 480 && f.format.primingFrames == 240 && f.claim == nil && f.pause == nil,
      "an epoch's format: AAC-ELD 48 kHz mono, 480 frames, priming 240: \(f)")
check((56_000...72_000).contains(f.format.bitrate ?? 0), "about 64 kbps (\(f.format.bitrate ?? 0))")
check(sender.format == f && MicrophoneMessage.format(f).serialized().flatMap(MicrophoneMessage.parse) == .format(f), "the format is kept and goes on the wire")
let messages = record(sender, seconds: 6.5, chunk: 4_800, h0: h0, w0: w0)
check(messages.count == 65, "one message a capture buffer: \(messages.count)")
var seqOK = true, flagsOK = true, stampsOK = true, sizesOK = true, kindOK = true
var expectSeq: UInt32 = 0
for (k, m) in messages.enumerated() {
    kindOK = kindOK && m.kind == .microphone && !m.isKeyframe
    guard case .packets(let p)? = MicrophoneMessage.parse(m.payload) else { sizesOK = false; continue }
    seqOK = seqOK && p.seq == expectSeq && p.epoch == 42 && p.packets.count == 10
    expectSeq &+= UInt32(p.packets.count)
    flagsOK = flagsOK && p.segmentStart == (k == 0)
    // Packet n decodes to input frames n·480 − 240 on: its stamp is that frame's capture time on the wall clock.
    let want = w0 + (Double(Int(p.seq) * 480) - 240) / rate
    stampsOK = stampsOK && abs(m.timestamp - want) < 1e-6
    sizesOK = sizesOK && m.payload.count <= MicrophoneMessage.maxPacketsPayload
}
check(kindOK, "kind 48, never a keyframe")
check(seqOK, "ten packets a message, the seq counting packets through epoch 42")
check(flagsOK, "the segment flag on the first message alone")
check(stampsOK, "each stamp the capture time of its first packet's first decoded sample")
check(sizesOK, "every message parses, within 16 KB")
let d = decode(messages, format: f, w0: w0, seconds: 6.5)
check(d.ok && d.packets == 650, "every packet decodes on the Mac's mono decoder: \(d.packets)")
let c = clicks(d.samples, wall0: w0, seconds: 1_800_000_001...1_800_000_006)
check(c.count == 6 && c.values.allSatisfy { abs($0) <= 2 }, "every click at its whole second ±2 frames: \(c.sorted { $0.key < $1.key })")
let bits = messages.reduce(0) { $0 + $1.payload.count } * 8
check(Double(bits) / 6.5 / 1000 < 80, "under 80 kbps with the messages' own bytes (\(Double(bits) / 6.5 / 1000))")

// MARK: - The Mac takes them at their pace

var host = MicrophonePolicy.Host()
_ = host.handle(.switchChanged(true), at: 0); _ = host.handle(.readyChanged(true), at: 0); _ = host.handle(.unlockedChanged(true), at: 0)
_ = host.handle(.appChanged(true), at: 0)
_ = host.handle(.joined(1, key: "k", paired: true, name: "iPad"), at: 0)
_ = host.handle(.format(1, MicrophoneFormat(claim: true)), at: 0)
_ = host.handle(.format(1, f), at: 0.05)
var taken = 0
for (k, m) in messages.enumerated() {
    guard case .packets(let p)? = MicrophoneMessage.parse(m.payload) else { continue }
    if host.takesPackets(1, epoch: p.epoch, packets: p.packets.count, framesPerPacket: 480, at: 0.1 * Double(k + 1)).take { taken += 1 }
}
check(taken == messages.count, "the Mac takes every message at a capture buffer's pace (\(taken) of \(messages.count))")

// MARK: - A lost buffer: a new segment

let gapSender = MicrophoneSender(lastEpoch: 7)
guard let gf = gapSender.start() else { print("FAIL: no encoder"); exit(1) }
let gapped = record(gapSender, seconds: 6.5, chunk: 4_800, h0: h0, w0: w0, gaps: [25])
let flags = gapped.compactMap { m -> Bool? in if case .packets(let p)? = MicrophoneMessage.parse(m.payload) { return p.segmentStart }; return nil }
check(gapped.count == 64 && flags.filter { $0 }.count == 2 && flags[25] == true, "the buffer after a gap starts a segment: \(flags.enumerated().filter { $0.element }.map(\.offset))")
let seqs = gapped.compactMap { m -> UInt32? in if case .packets(let p)? = MicrophoneMessage.parse(m.payload) { return p.seq }; return nil }
check(seqs[24] == 240 && seqs[25] == 250, "the seq goes on through the gap (a segment, not a lost packet): \(seqs[24]), \(seqs[25])")
let gd = decode(gapped, format: gf, w0: w0, seconds: 6.5)
let gc = clicks(gd.samples, wall0: w0, seconds: 1_800_000_001...1_800_000_006)
check(gd.ok && gc.count == 6 && gc.values.allSatisfy { abs($0) <= 2 }, "across the gap every click at its second: \(gc.sorted { $0.key < $1.key })")

// MARK: - Other buffer sizes, and the cap

for chunk in [4_096, 1_024, 19_200] {
    let s = MicrophoneSender(lastEpoch: 0)
    guard let sf = s.start() else { check(false, "an encoder"); continue }
    let ms = record(s, seconds: 6.4, chunk: chunk, h0: h0, w0: w0)
    let counts = ms.compactMap { m -> Int? in if case .packets(let p)? = MicrophoneMessage.parse(m.payload) { return p.packets.count }; return nil }
    let total = counts.reduce(0, +)
    check(counts.allSatisfy { $0 <= MicrophoneSender.maxPacketsPerMessage } && total == (Int(6.4 * rate) / chunk * chunk) / 480,
          "\(chunk)-frame buffers: every packet sent, at most \(MicrophoneSender.maxPacketsPerMessage) a message (\(total) in \(counts.count) messages)")
    let sd = decode(ms, format: sf, w0: w0, seconds: 6.4)
    let sc = clicks(sd.samples, wall0: w0, seconds: 1_800_000_001...1_800_000_005)
    check(sd.ok && sc.count == 5 && sc.values.allSatisfy { abs($0) <= 2 }, "\(chunk)-frame buffers: the clicks at their seconds: \(sc.sorted { $0.key < $1.key })")
}

// MARK: - Epochs: the next, the wrap, and stopping

let wrap = MicrophoneSender(lastEpoch: 65_535)
check(wrap.start()?.format.epoch == 0, "after 65,535: epoch 0")
check(wrap.start()?.format.epoch == 1, "the next recording: 1")
wrap.stop()
check(wrap.format == nil && wrap.push(MicrophoneCapture.tone(frames: 4_800, wallStart: w0), hostTime: h0, wallOffset: w0 - h0).isEmpty, "stopped: no format, nothing made")
check(wrap.push([], hostTime: 1, wallOffset: 0).isEmpty, "an empty buffer: nothing")
_ = wrap.start()
check(wrap.push(MicrophoneCapture.tone(frames: 4_800, wallStart: w0), hostTime: .nan, wallOffset: 0).isEmpty, "a buffer with no time: nothing")

// MARK: - The capture: a tap's buffers at 48, 24 and 16 kHz

final class Collected: @unchecked Sendable {
    let lock = NSLock()
    var items: [(StreamMessage, MicrophoneCapture.Kind)] = []
    func add(_ m: StreamMessage, _ k: MicrophoneCapture.Kind) { lock.withLock { items.append((m, k)) } }
}
check(MicrophoneCapture.source == .microphone, "on the Mac (no simulator, no tone asked): the microphone's source")
for inRate in [48_000.0, 24_000.0, 16_000.0] {
    let capture = MicrophoneCapture()
    let got = Collected()
    capture.onMessage = { m, k in got.add(m, k) }
    capture.start()
    capture.queue.sync {}
    let fmt = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inRate, channels: 1, interleaved: false)!
    let per = Int(inRate * 0.1)
    var hostTicks = mach_absolute_time()
    var info = mach_timebase_info_data_t(); mach_timebase_info(&info)
    let ticksPerBuffer = UInt64(0.1 * 1e9 * Double(info.denom) / Double(info.numer))
    for k in 0..<30 {
        let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(per))!
        b.frameLength = AVAudioFrameCount(per)
        for i in 0..<per { b.floatChannelData![0][i] = Float(0.1 * sin(2 * .pi * 440 * Double(k * per + i) / inRate)) }
        capture.tap(b, AVAudioTime(hostTime: hostTicks))
        hostTicks += ticksPerBuffer
    }
    capture.queue.sync {}
    let items = got.lock.withLock { got.items }
    let firstIsFormat = items.first.map { m, k in k == .format && MicrophoneMessage.parse(m.payload).map { if case .format(let f) = $0 { return f.isEpoch } else { return false } } == true } ?? false
    let packets = items.dropFirst().reduce(0) { n, item in
        if case .packets(let p)? = MicrophoneMessage.parse(item.0.payload) { return n + p.packets.count }
        return n
    }
    check(firstIsFormat, "\(Int(inRate)) Hz: the epoch's format first")
    check(items.dropFirst().allSatisfy { $0.1 == .packets }, "\(Int(inRate)) Hz: then packets only")
    // 3 s of sound: 300 packets of 10 ms, less what a resampler holds back (a few ms) and the priming's tail.
    check((290...300).contains(packets), "\(Int(inRate)) Hz: about 3 s of packets at 48 kHz (\(packets))")
    check(capture.format?.isEpoch == true, "\(Int(inRate)) Hz: the recording's format readable for a move's offer")
    capture.stop()
    capture.queue.sync {}
    check(capture.format == nil, "\(Int(inRate)) Hz: stopped, no format")
    let before = got.lock.withLock { got.items.count }
    let b = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(per))!
    b.frameLength = AVAudioFrameCount(per)
    capture.tap(b, AVAudioTime(hostTime: hostTicks))
    capture.queue.sync {}
    check(got.lock.withLock { got.items.count } == before, "\(Int(inRate)) Hz: a buffer after the stop sends nothing")
}

// MARK: - The test tone

let tone = MicrophoneCapture.tone(frames: 48_000, wallStart: 1_800_000_000.5)
let tc = clicks(tone, wall0: 1_800_000_000.5, seconds: 1_800_000_001...1_800_000_001)
check(tc[1_800_000_001] == 0, "the tone's click on the whole second exactly: \(tc)")
let quiet = tone[0..<20_000].map { abs($0) }.max() ?? 1
check(quiet < 0.04 && quiet > 0.025, "between clicks, 440 Hz at −30 dBFS (peak \(quiet))")

print(failures == 0 ? "mic-send: all \(checks) checks passed" : "mic-send: \(failures) of \(checks) checks FAILED")
exit(failures == 0 ? 0 : 1)
