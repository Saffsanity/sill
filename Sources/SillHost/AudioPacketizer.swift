import Foundation

// The Mac's sound on its way to the encoder (docs/audio-plan.md §4.3): the chunks of PCM a source
// delivers become blocks of exactly one packet's frames, each stamped with the host time of the
// sample its packet decodes to first, and a gap in the capture ends a segment. Beside it, what
// `AudioPipeline.follow` does with the source it has and the one it is asked for (`AudioSourceRule`),
// how a delivered buffer becomes the interleaved stereo the encoder takes (`PCMLayout`), and the
// first minute's tally of the buffers' time stamps (`AudioBufferTally`, the line P2 records).
//
// Pure: Foundation only, so it is checked on its own with swiftc (Tests/checks/audio-packetizer).
// Every time here is seconds of the host clock (mach absolute time, the clock ScreenCaptureKit stamps
// its buffers with); the pipeline turns a block's into the wall clock as it sends it.

/// PCM from a source: interleaved Float32 frames, and the host time of the first.
struct PCMChunk {
    /// `frames × channels` samples, interleaved.
    var samples: [Float]
    var channels: Int
    var sampleRate: Double
    /// Seconds of the host clock (mach absolute time) of its first frame.
    var hostTime: Double

    var frames: Int { channels > 0 ? samples.count / channels : 0 }
}

/// Exactly one packet's frames, for the encoder.
struct AudioBlock {
    /// `framesPerPacket × channels` samples, interleaved.
    var samples: [Float]
    /// Its number in its segment, from 0.
    var index: Int
    /// The first block of a segment: the encoder starts clean (AudioConverterReset) before it, and
    /// its packet carries the segment flag, so the device drops the codec's priming.
    var segmentStart: Bool
    /// The host time of segment frame `index × framesPerPacket − priming`: the input frame the
    /// packet's first decoded sample is (the codec delays its output by `priming` frames, and hands
    /// the priming out rather than trimming it), from the anchor of the chunk it falls in.
    var hostTime: Double
}

/// Chunks in, blocks out, for one epoch (one encoder: one packet size, one priming, one format).
///
/// Continuity: a chunk is expected where the one before it ended (its time + its frames ÷ the rate).
/// Within a quarter of a chunk of that (2.5 ms for 480 frames, 5.3 ms for 1024), it is appended as it
/// is: that is time stamp jitter, so the stamps follow each chunk's own anchor and the samples never
/// move. A lost buffer is a whole chunk late, so none hides in the tolerance. Anything else, later or
/// earlier, ends the segment where it is, and a new one starts at this chunk: what was still short
/// of a block is dropped, never flushed, padded or filled with zeros (a packet made now for frames of
/// a gap ago would reach the device late by the gap, and raise its jitter cover for 10 s as if the
/// link had jittered), and the encoder is reset before the new segment's first block, which drops
/// what it held too (its lookahead). The device fades the old segment out and places the new one by
/// its stamp.
///
/// Each block goes out with the chunk that completes it; a gap emits nothing.
struct AudioPacketizer {
    let framesPerPacket: Int
    let priming: Int
    let channels: Int
    let sampleRate: Double

    /// Segments begun after a gap (a chunk late or early), for `aud.gap`.
    private(set) var gaps = 0

    /// What is not yet a whole block, interleaved; `buffered` frames.
    private var fifo: [Float] = []
    /// Each chunk's first frame (its number in the segment) and its host time, oldest first; only
    /// those the next stamps can still need are kept.
    private var anchors: [(frame: Int, time: Double)] = []
    /// Frames of this segment appended so far, and blocks made of them.
    private var segmentFrames = 0
    private var blocksMade = 0
    /// Where the next chunk is expected; nil before the first.
    private var expected: Double?

    /// 512 when the first chunk's frames are a whole number of 512-frame packets, else 480: the
    /// packet that divides the capture's chunks is 9–10 ms faster end to end (docs/audio-plan.md,
    /// "Which codec: measured").
    static func packetSize(firstChunkFrames frames: Int) -> Int {
        frames > 0 && frames % 512 == 0 ? 512 : 480
    }

    init(framesPerPacket: Int, priming: Int, channels: Int, sampleRate: Double) {
        self.framesPerPacket = framesPerPacket
        self.priming = priming
        self.channels = channels
        self.sampleRate = sampleRate
    }

    /// The chunk is of this epoch's format (its rate and channels); another format is a new epoch
    /// (a new encoder), which the pipeline starts.
    func takes(_ chunk: PCMChunk) -> Bool {
        chunk.channels == channels && chunk.sampleRate == sampleRate
    }

    /// The blocks this chunk completes, in order. A chunk of another format, or of no frames, is
    /// ignored (`takes`).
    mutating func push(_ chunk: PCMChunk) -> [AudioBlock] {
        let frames = chunk.frames
        guard frames > 0, takes(chunk) else { return [] }
        let tolerance = 0.25 * Double(frames) / sampleRate
        if let expected, abs(chunk.hostTime - expected) <= tolerance {
            // Contiguous: appended as it is.
        } else {
            if expected != nil { gaps += 1 }
            fifo.removeAll(keepingCapacity: true)
            anchors.removeAll(keepingCapacity: true)
            segmentFrames = 0
            blocksMade = 0
        }
        anchors.append((segmentFrames, chunk.hostTime))
        fifo.append(contentsOf: chunk.samples.prefix(frames * channels))
        segmentFrames += frames
        expected = chunk.hostTime + Double(frames) / sampleRate

        var blocks: [AudioBlock] = []
        let blockSamples = framesPerPacket * channels
        while fifo.count >= blockSamples {
            let index = blocksMade
            blocks.append(AudioBlock(samples: Array(fifo[0..<blockSamples]), index: index, segmentStart: index == 0,
                                     hostTime: time(ofFrame: index * framesPerPacket - priming)))
            fifo.removeFirst(blockSamples)
            blocksMade += 1
        }
        // The next stamp is of frame `blocksMade × F − P`: every anchor before the one it falls in goes.
        let next = blocksMade * framesPerPacket - priming
        while anchors.count >= 2, anchors[1].frame <= next { anchors.removeFirst() }
        return blocks
    }

    /// The host time of segment frame `frame`, from the anchor of the chunk it falls in, or from the
    /// first chunk's before it (a segment's first packets start `priming` frames before its first
    /// captured frame).
    private func time(ofFrame frame: Int) -> Double {
        var anchor = anchors[0]
        for a in anchors.dropFirst() where a.frame <= frame { anchor = a }
        return anchor.time + Double(frame - anchor.frame) / sampleRate
    }
}

/// What the sound should be of, as `AudioPipeline.follow` is asked for it: one app's (by pid; the
/// name is for the log and the format), the whole Mac's (the Desktop), the test tone (a synthetic
/// host's Desktop), or none.
enum AudioKey: Equatable, CustomStringConvertible {
    case none
    case desktop
    case test
    case app(pid: Int32, name: String)

    /// The same source: an app is the same by its pid (the name is only shown).
    static func == (a: AudioKey, b: AudioKey) -> Bool {
        switch (a, b) {
        case (.none, .none), (.desktop, .desktop), (.test, .test): return true
        case (.app(let p, _), .app(let q, _)): return p == q
        default: return false
        }
    }

    var description: String {
        switch self {
        case .none: return "none"
        case .desktop: return "desktop"
        case .test: return "test"
        case .app(let pid, let name): return "\(name) (pid \(pid))"
        }
    }
}

/// What `AudioPipeline.follow` does with the source it has and the one it is asked for.
enum AudioSourceRule {
    /// Where the pipeline's source is: none (`idle`), on its way up, running, or ended by itself or
    /// failed to start (then `AudioPipeline` keeps its key, so the same source is not tried again at
    /// once).
    enum Phase: Equatable { case idle, starting, running, ended }
    enum Action: Equatable {
        /// Nothing to do.
        case keep
        /// Stop whatever runs (or ended) and start the wanted source, with a new epoch.
        case start
        /// Stop whatever runs, and have none.
        case stop
    }
    /// A source that ended by itself or failed to start is tried again at most this often.
    static let retryInterval: TimeInterval = 10

    /// The same source (an app by its pid) running or starting: keep it (a resize, a rotation,
    /// another window of the same app). The same one ended by itself or failed: start it again, at
    /// most once every `retryInterval` since its last start. Another app, the Desktop, the test tone:
    /// a new stream and a new epoch. None: stop.
    static func decide(current: AudioKey, phase: Phase, lastStartAt: TimeInterval, wanted: AudioKey,
                       now: TimeInterval) -> Action {
        if wanted == .none { return current == .none && phase == .idle ? .keep : .stop }
        guard wanted == current, phase != .idle else { return .start }
        switch phase {
        case .starting, .running: return .keep
        case .ended: return now - lastStartAt >= retryInterval ? .start : .keep
        case .idle: return .start
        }
    }
}

/// How a delivered buffer's samples are laid out, from its AudioStreamBasicDescription, and the one
/// conversion the encoder needs: interleaved stereo Float32. ScreenCaptureKit documents 48 kHz stereo
/// and Apple's sample code reads it as 32-bit float with a buffer per channel, but the layout is not
/// documented, so it is read from each buffer's description and never assumed.
struct PCMLayout: Equatable, CustomStringConvertible {
    enum Sample: Equatable { case float32, int16, int32 }
    var sample: Sample
    var channels: Int
    var interleaved: Bool

    /// CoreAudioTypes' constants (this file is Foundation only): kAudioFormatLinearPCM ('lpcm'),
    /// kAudioFormatFlagIsFloat, kAudioFormatFlagIsBigEndian, kAudioFormatFlagIsSignedInteger,
    /// kAudioFormatFlagIsNonInterleaved.
    static let linearPCM: UInt32 = 0x6C70_636D
    static let flagIsFloat: UInt32 = 1 << 0
    static let flagIsBigEndian: UInt32 = 1 << 1
    static let flagIsSignedInteger: UInt32 = 1 << 2
    static let flagIsNonInterleaved: UInt32 = 1 << 5

    /// The layout of linear PCM of 32-bit float, or 16- or 32-bit signed integers, native endian,
    /// one channel or more; nil for anything else (the pipeline then says it cannot use the sound).
    static func from(formatID: UInt32, flags: UInt32, bitsPerChannel: UInt32, channels: UInt32) -> PCMLayout? {
        guard formatID == linearPCM, channels >= 1, flags & flagIsBigEndian == 0 else { return nil }
        let sample: Sample
        if flags & flagIsFloat != 0 {
            guard bitsPerChannel == 32 else { return nil }
            sample = .float32
        } else if flags & flagIsSignedInteger != 0 {
            switch bitsPerChannel {
            case 16: sample = .int16
            case 32: sample = .int32
            default: return nil
            }
        } else {
            return nil
        }
        return PCMLayout(sample: sample, channels: Int(channels), interleaved: flags & flagIsNonInterleaved == 0)
    }

    /// "32-bit float, non-interleaved", for the first buffer's line.
    var description: String {
        let kind: String
        switch sample {
        case .float32: kind = "32-bit float"
        case .int16: kind = "16-bit integer"
        case .int32: kind = "32-bit integer"
        }
        return "\(kind), \(interleaved ? "interleaved" : "non-interleaved")"
    }

    private var bytesPerSample: Int { sample == .int16 ? 2 : 4 }

    /// `frames` frames from `buffers` (one per channel when non-interleaved, else one holding every
    /// channel) as interleaved stereo Float32: one channel doubled, the first two of more. Nil when
    /// the buffers are fewer or shorter than the layout says.
    func stereo(frames: Int, buffers: [UnsafeRawBufferPointer]) -> [Float]? {
        guard frames >= 0 else { return nil }
        let stride = bytesPerSample
        if interleaved {
            guard let b = buffers.first, b.count >= frames * channels * stride else { return nil }
        } else {
            guard buffers.count >= channels, buffers.prefix(channels).allSatisfy({ $0.count >= frames * stride }) else { return nil }
        }
        func value(channel c: Int, frame f: Int) -> Float {
            let (buffer, offset) = interleaved ? (buffers[0], (f * channels + c) * stride) : (buffers[c], f * stride)
            switch sample {
            case .float32: return buffer.loadUnaligned(fromByteOffset: offset, as: Float.self)
            case .int16: return Float(buffer.loadUnaligned(fromByteOffset: offset, as: Int16.self)) / 32_768
            case .int32: return Float(Double(buffer.loadUnaligned(fromByteOffset: offset, as: Int32.self)) / 2_147_483_648)
            }
        }
        let right = channels >= 2 ? 1 : 0
        var out = [Float](repeating: 0, count: frames * 2)
        for f in 0..<frames {
            out[2 * f] = value(channel: 0, frame: f)
            out[2 * f + 1] = value(channel: right, frame: f)
        }
        return out
    }
}

/// The first minute of a capture's buffers, for the one line P2 records: how many, how close their
/// time stamps kept to contiguous (a buffer expected where the one before ended), how many were
/// further off than the packetizer's tolerance (a quarter of a buffer: each such one starts a new
/// segment), and how many were silent (every sample zero: does ScreenCaptureKit keep delivering
/// while the app is quiet?).
struct AudioBufferTally: Equatable {
    private(set) var buffers = 0
    private(set) var gaps = 0
    private(set) var silent = 0
    /// The largest distance from contiguous among the buffers within the tolerance, in seconds.
    private(set) var worstJitter = 0.0
    private var expected: Double?

    mutating func add(frames: Int, sampleRate: Double, hostTime: Double, silent isSilent: Bool) {
        buffers += 1
        if isSilent { silent += 1 }
        if let expected {
            let off = abs(hostTime - expected)
            if off <= 0.25 * Double(frames) / sampleRate { worstJitter = max(worstJitter, off) } else { gaps += 1 }
        }
        expected = hostTime + Double(frames) / sampleRate
    }

    /// "Audio: first minute: 2812 buffers, time stamps at most 0.3 ms from contiguous, 0 gaps, 1406 silent."
    var line: String {
        "Audio: first minute: \(buffers) buffers, time stamps at most \(String(format: "%.1f", worstJitter * 1000)) ms from contiguous, "
            + "\(gaps) gap\(gaps == 1 ? "" : "s"), \(silent) silent."
    }
}
