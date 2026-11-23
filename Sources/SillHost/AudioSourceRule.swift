import Foundation

// The Mac's sound before SillAudio's packetizer (docs/audio-plan.md §4.3), the host's own: what
// `AudioPipeline.follow` does with the source it has and the one it is asked for (`AudioSourceRule`),
// how a delivered buffer becomes the interleaved stereo the encoder takes (`PCMLayout`), and the
// first minute's tally of the buffers' time stamps (`AudioBufferTally`, the line P2 records). The
// packetizer itself (PCMChunk, AudioBlock, AudioPacketizer) is Sources/SillAudio/AudioPacketizer.swift.
//
// Pure: Foundation only, so it is checked with swiftc beside SillAudio's AudioPacketizer.swift
// (Tests/checks/audio-packetizer). Every time here is seconds of the host clock (mach absolute time,
// the clock ScreenCaptureKit stamps its buffers with).

/// What the sound should be of, as `AudioPipeline.follow` is asked for it: one app's (by pid, and the
/// ID of the display its capture is built on, 0 for none; the name is for the log and the format),
/// the whole Mac's (the Desktop), the test tone (a synthetic host's Desktop), or none.
enum AudioKey: Equatable, CustomStringConvertible {
    case none
    case desktop
    case test
    case app(pid: Int32, display: UInt32 = 0, name: String)

    /// The same source: an app is the same by its pid and the display its capture is built on
    /// (the name is only shown; when its window moves to Sill's virtual display, or Sill's display
    /// is remade under a new ID, #365, it is a new capture).
    static func == (a: AudioKey, b: AudioKey) -> Bool {
        switch (a, b) {
        case (.none, .none), (.desktop, .desktop), (.test, .test): return true
        case (.app(let p, let d1, _), .app(let q, let d2, _)): return p == q && d1 == d2
        default: return false
        }
    }

    var description: String {
        switch self {
        case .none: return "none"
        case .desktop: return "desktop"
        case .test: return "test"
        case .app(let pid, _, let name): return "\(name) (pid \(pid))"
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
    /// The longest the pipeline waits, after a start, before it tries a source that keeps failing
    /// again by itself (`retryIn`).
    static let retryCap: TimeInterval = 160

    /// The same source (an app by its pid and its display) running or starting: keep it (a resize, a
    /// rotation, another window of the same app on the same display). The same one ended by itself or
    /// failed: start it again, at most once every `retryInterval` since its last start. Another app,
    /// the same app on another display, the Desktop, the test tone: a new stream and a new epoch.
    /// None: stop.
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

    /// How long from `now` until the pipeline tries a source that ended by itself or failed to start
    /// again on its own (issue #365): `retryInterval` after its last start (`lastStartAt`), twice as
    /// long for each failure in a row before the last (`failures`, at least 1), at most `retryCap`:
    /// 10, 20, 40, 80, then 160 s, so a source that keeps failing is not started and logged every
    /// 10 s for the rest of a stream. 0 once that time has passed, never more than the whole wait (a
    /// start stamped after `now`). Nil unless the source ended (`phase == .ended`) and one is still
    /// wanted.
    static func retryIn(phase: Phase, wanted: AudioKey, lastStartAt: TimeInterval, failures: Int,
                        now: TimeInterval) -> TimeInterval? {
        guard phase == .ended, wanted != .none else { return nil }
        let doublings = min(max(failures, 1), 8) - 1
        let wait = min(retryCap, retryInterval * Double(1 << doublings))
        return max(0, wait - max(0, now - lastStartAt))
    }

    /// The failures in a row once a try of a source has failed to start (`ranFor` nil) or ended by
    /// itself after `ranFor` seconds: one more than `previous`, but an end after `retryInterval` or
    /// more of running is the first of a new run of them.
    static func failures(after previous: Int, ranFor: TimeInterval?) -> Int {
        if let ranFor, ranFor >= retryInterval { return 1 }
        return max(previous, 0) + 1
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
