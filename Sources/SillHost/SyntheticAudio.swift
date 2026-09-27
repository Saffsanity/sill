import Foundation

/// A synthetic host's sound (`--synthetic`, docs/audio-plan.md §4.2): the test tone (TestTone), paced
/// as a capture would deliver it, so the whole path from the source to the device runs without
/// ScreenCaptureKit, a permission, or anything a person hears on the Mac. Foundation only.
///
/// A 10 ms timer on the pipeline's queue makes 480-frame chunks of 48 kHz stereo. A chunk's host time
/// is the first chunk's plus the frames made before it ÷ 48 kHz, never the timer's firing time, and a
/// chunk goes out once the clock has passed its last frame (as a capture delivers a buffer): a late
/// timer makes two chunks at once, never a gap. The samples follow the frame index (TestTone), and the
/// wall clock's second for each frame is taken from one mapping made as the tone starts, so every
/// click is at a whole second of the stamps the pipeline puts on it.
///
/// TEST ONLY, read once, honoured wherever this source runs (a synthetic host, the harness), which
/// no device finds: `SILL_TEST_AUDIO_CHUNK=1024` makes 1024-frame chunks every 21.3 ms (the 512-frame
/// packets, headless); `SILL_TEST_AUDIO_PAUSE=S@T[,S@T…]` makes nothing for S seconds from T seconds
/// after the tone starts, then goes on from where the clock is (a gap: a new segment). Each prints one
/// line as the tone starts; a value that does not parse is ignored with one line.
final class SyntheticAudio: AudioSource, @unchecked Sendable {   // its state is confined to `queue`
    var onPCM: ((PCMChunk) -> Void)?
    var onStopped: ((String) -> Void)?

    static let sampleRate = 48_000.0

    private let queue: DispatchQueue
    private let pitch: Double
    private let chunkFrames: Int
    private let pauses: [(at: Double, seconds: Double)]
    private let testLines: [String]
    // On `queue`.
    private var timer: DispatchSourceTimer?
    private var tone: TestTone?
    private var hostAtFrame0 = 0.0
    private var startHost = 0.0
    private var nextFrame = 0
    private var pausing = false

    /// `queue`: the pipeline's, where the chunks are delivered. `pitch`: 440 Hz, or another for a
    /// second source in the harness.
    init(queue: DispatchQueue, pitch: Double = TestTone.pitch, environment env: [String: String] = ProcessInfo.processInfo.environment) {
        self.queue = queue
        self.pitch = pitch
        var lines: [String] = []
        var chunk = 480
        if let raw = env["SILL_TEST_AUDIO_CHUNK"], !raw.isEmpty {
            if raw == "1024" {
                chunk = 1024
                lines.append("Test audio: 1024-frame chunks every 21.3 ms (SILL_TEST_AUDIO_CHUNK).")
            } else {
                lines.append("SILL_TEST_AUDIO_CHUNK=\(raw) ignored: 1024 is the one other chunk.")
            }
        }
        chunkFrames = chunk
        var pauses: [(Double, Double)] = []
        if let raw = env["SILL_TEST_AUDIO_PAUSE"], !raw.isEmpty {
            let parsed = raw.split(separator: ",").map { part -> (Double, Double)? in
                let p = part.split(separator: "@")
                guard p.count == 2, let s = Double(p[0]), let t = Double(p[1]), s > 0, s.isFinite, t >= 0, t.isFinite else { return nil }
                return (t, s)
            }
            if parsed.contains(where: { $0 == nil }) {
                lines.append("SILL_TEST_AUDIO_PAUSE=\(raw) ignored: S@T[,S@T…], seconds.")
            } else {
                pauses = parsed.compactMap { $0 }.sorted { $0.0 < $1.0 }
                lines.append("Test audio: the tone pauses " + pauses.map { "\(Self.seconds($0.1)) s at \(Self.seconds($0.0)) s" }.joined(separator: ", ")
                             + " (SILL_TEST_AUDIO_PAUSE).")
            }
        }
        self.pauses = pauses.map { (at: $0.0, seconds: $0.1) }
        testLines = lines
    }

    private static func seconds(_ s: Double) -> String { s == s.rounded() ? "\(Int(s))" : "\(s)" }

    func start() async throws {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                for line in testLines { print(line) }
                // The host time ↔ wall clock mapping, taken once: frame 0 is now on both.
                let host = HostClock.now()
                let wall = Date().timeIntervalSince1970
                hostAtFrame0 = host
                startHost = host
                nextFrame = 0
                pausing = false
                tone = TestTone(sampleRate: Self.sampleRate, wallAtFrame0: wall, pitch: pitch)
                let t = DispatchSource.makeTimerSource(queue: queue)
                let every = Double(chunkFrames) / Self.sampleRate
                t.schedule(deadline: .now() + every, repeating: every, leeway: .milliseconds(1))
                t.setEventHandler { [weak self] in self?.tick() }
                t.resume()
                timer = t
                c.resume()
            }
        }
    }

    /// Returns once no chunk is being made or delivered.
    func stop() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                timer?.cancel()
                timer = nil
                tone = nil
                c.resume()
            }
        }
    }

    /// On `queue`: every chunk whose last frame the clock has passed, unless a pause holds them.
    private func tick() {
        guard let tone else { return }
        let now = HostClock.now()
        let since = now - startHost
        if pauses.contains(where: { since >= $0.at && since < $0.at + $0.seconds }) {
            pausing = true
            return
        }
        if pausing {
            // From where the clock is: the next chunk starts now.
            pausing = false
            nextFrame = Int(((now - hostAtFrame0) * Self.sampleRate).rounded(.up))
        }
        while hostAtFrame0 + Double(nextFrame + chunkFrames) / Self.sampleRate <= now {
            let chunk = PCMChunk(samples: tone.samples(from: nextFrame, frames: chunkFrames), channels: 2,
                                 sampleRate: Self.sampleRate, hostTime: hostAtFrame0 + Double(nextFrame) / Self.sampleRate)
            nextFrame += chunkFrames
            onPCM?(chunk)
        }
    }
}
