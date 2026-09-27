import Foundation
import StreamProtocol

/// A source of the Mac's sound: ScreenCaptureKit's audio-only stream (AudioCapture), or a synthetic
/// host's test tone (SyntheticAudio). Both deliver on the pipeline's queue.
protocol AudioSource: AnyObject {
    /// On the pipeline's queue: PCM as delivered, its format, and the host time of its first frame.
    var onPCM: ((PCMChunk) -> Void)? { get set }
    /// It ended by itself; why, for the log and the Mac's status. Not called by `stop()`.
    var onStopped: ((String) -> Void)? { get set }
    func start() async throws
    /// Returns once no chunk is in flight.
    func stop() async
}

/// Seconds of the host clock: mach absolute time, the clock ScreenCaptureKit stamps its buffers with
/// (CMClockGetHostTimeClock counts the same ticks).
enum HostClock {
    private static let scale: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()

    static func now() -> Double { Double(mach_absolute_time()) * scale }
}

/// The Mac's sound, from its source to the server (docs/audio-plan.md §4.5): the source, the
/// packetizer and the AAC-ELD encoder on `sill.audio`, the epochs, and what the coordinator and the
/// Mac's status see of them. It never imports ScreenCaptureKit (the coordinator's `make` builds the
/// source), so the encoder-free harness (Scripts/audio) compiles it with the test tone.
///
/// Main actor: which source is wanted and which runs (`follow`, one transition at a time in a Task, a
/// newer request replacing one not yet begun, as `setTarget`'s changes do), and the status. The
/// pipeline's queue: the chunks, the blocks, the encoder, the stamps and the messages, handed to the
/// server (`onFormat`, `onPackets`) the moment they exist. Nothing of the sound touches the picture's
/// queues or counters, and a failure of the sound never stops, restarts or delays the picture: it
/// sets `status.problem`, prints one line and waits for the next `follow`.
///
/// Epochs: a new encoder is a new epoch (0 to 65535, wrapping): another source, a source started
/// again, a new PCM format. Its format message goes to the server before the epoch's first packet, and
/// the packets' seq counts from 0 in each.
final class AudioPipeline: @unchecked Sendable {   // main-actor state, and state confined to `queue`, as marked
    /// Where the sound is made: the source's buffers, the tone's timer, the packetizer, the encoder.
    let queue = DispatchQueue(label: "sill.audio", qos: .userInteractive)

    /// A whole kind 29 message: the format of an epoch (type 1), on `queue`, before that epoch's first
    /// packet; the server keeps it for the devices that join the epoch later.
    var onFormat: ((Data, Int) -> Void)?
    /// A whole kind 29 message of one packet (type 2) of an epoch, on `queue`, the moment it is made.
    var onPackets: ((Data, Int) -> Void)?

    /// What the Mac shows of the sound while it is wanted: its source ("Safari", "Whole Mac", "Test
    /// Tone"), whether it is captured, and why not.
    struct Status: Equatable {
        var source: String
        var capturing: Bool
        /// "couldn’t capture the sound of Safari: …"; nil while all is well.
        var problem: String?
    }
    /// Nil while no sound is wanted. Main actor.
    private(set) var status: Status? { didSet { if status != oldValue { onStatus?(status) } } }
    /// Main actor: every change of `status`.
    var onStatus: ((Status?) -> Void)?
    /// The status of the source there is (running, starting, failed or ended), whatever is wanted:
    /// `status` shows it while a source is wanted. Main actor.
    private var sourceStatus: Status? { didSet { if wanted != .none { status = sourceStatus } } }
    /// The newest source asked for. Main actor.
    private var wanted = AudioKey.none

    /// What `make` gives: a source, and the line that says what it captures, printed as it starts; or
    /// why there is none.
    enum Made {
        case source(AudioSource, line: String)
        case failed(String)
    }

    // Main actor.
    private var current: AudioKey = .none
    private var phase = AudioSourceRule.Phase.idle
    private var lastStartAt: TimeInterval = -.infinity
    private var source: AudioSource?
    private var generation = 0
    private struct Request {
        let key: AudioKey
        let reason: String
        let make: @MainActor (AudioKey) async -> Made
    }
    private var requested: Request?
    private var worker: Task<Void, Never>?
    /// AAC-ELD could not be made (`encoderProblem`): no sound this run.
    private var encoderGone = false
    /// "Audio stopped" was said for the source that runs.
    private var stopSaid = false

    // On `queue`.
    private var live = 0                 // the generation whose chunks count
    private var info = (source: AudioFormat.sourceTest, app: String?.none)
    private var packetizer: AudioPacketizer?
    private var encoder: AudioEncoder?
    private var epoch = 0
    private var seq: UInt32 = 0
    private var gapsSeen = 0
    private var encoderUnavailable = false
    private var formatRefused = false

    init() {}

    // MARK: The source (main actor)

    /// The sound should be of `key` (`.none`: no sound, `reason` saying why for the log's "Audio
    /// stopped" line: "nothing streams", "no connected device plays sound", "Send Audio is off").
    /// Returns at once; the work runs in a Task, and a newer call replaces one not yet begun. The same
    /// source running is kept; one that ended by itself or failed is started again at most every 10 s
    /// (`AudioSourceRule`); anything else stops what runs and starts the wanted one, with a new epoch.
    /// `make` builds the source when one is to start.
    @MainActor
    func follow(_ key: AudioKey, reason: String = "", make: @escaping @MainActor (AudioKey) async -> Made) {
        requested = Request(key: key, reason: reason, make: make)
        wanted = key
        if key == .none { status = nil }
        if worker == nil { worker = Task { @MainActor in await self.run() } }
    }

    /// Sill is quitting: said now, while the process still runs (the stop itself may not come before
    /// it ends, and needs nothing: the process's end takes the capture with it).
    @MainActor
    func shutdown() {
        if !stopSaid, current != .none, phase == .starting || phase == .running {
            stopSaid = true
            print("Audio stopped: Sill is quitting.")
        }
        requested = Request(key: .none, reason: "Sill is quitting", make: { _ in .failed("quitting") })
        wanted = .none
        status = nil
        if worker == nil { worker = Task { @MainActor in await self.run() } }
    }

    @MainActor
    private func run() async {
        while let r = requested {
            requested = nil
            switch AudioSourceRule.decide(current: current, phase: phase, lastStartAt: lastStartAt, wanted: r.key,
                                          now: HostClock.now()) {
            case .keep:
                // The source there is stays (a stop asked for and taken back before it ran included).
                if r.key != .none { status = sourceStatus }
                continue
            case .stop:
                if !stopSaid, phase == .starting || phase == .running { print("Audio stopped: \(r.reason).") }
                await stopSource()
                current = .none
                phase = .idle
                sourceStatus = nil
            case .start:
                await stopSource()
                await startSource(r.key, make: r.make)
            }
        }
        worker = nil
    }

    /// On the main actor: the source goes, and its chunks with it (a stopped source delivers none, and
    /// a late one is of an old generation).
    @MainActor
    private func stopSource() async {
        generation += 1
        let g = generation
        queue.async { self.live = g; self.packetizer = nil; self.encoder = nil }
        guard let s = source else { return }
        source = nil
        s.onPCM = nil
        s.onStopped = nil
        await s.stop()
    }

    @MainActor
    private func startSource(_ key: AudioKey, make: @MainActor (AudioKey) async -> Made) async {
        current = key
        phase = .starting
        stopSaid = false
        lastStartAt = HostClock.now()
        sourceStatus = Status(source: Self.shown(key), capturing: false, problem: nil)
        generation += 1
        let g = generation
        // One transition at a time (`run`): nothing else starts or stops a source while this one is made
        // and started. A request that comes meanwhile is decided once this start is done.
        let made = await make(key)
        guard case .source(let s, let line) = made else {
            if case .failed(let why) = made { failed(key, why) }
            return
        }
        let (formatSource, app) = Self.formatSource(key)
        queue.async {
            self.live = g
            self.info = (formatSource, app)
            self.packetizer = nil
            self.encoder = nil
            self.formatRefused = false
        }
        s.onPCM = { [weak self] chunk in self?.took(chunk, generation: g) }
        s.onStopped = { [weak self] why in Task { @MainActor in self?.ended(generation: g, why: why) } }
        source = s
        print(line)   // before its first buffer and the epoch's encoder line; a failure says so after it
        do {
            try await s.start()
        } catch {
            guard g == generation else { return }
            source = nil
            s.onPCM = nil
            s.onStopped = nil
            await s.stop()
            failed(key, "\(error)")
            return
        }
        guard g == generation else { return }   // it ended by itself meanwhile (`ended` has said so)
        phase = .running
        guard !encoderGone else { return }   // no sound this run: the status says why
        sourceStatus = Status(source: Self.shown(key), capturing: true, problem: nil)
    }

    /// A source that could not start: one line, the problem shown, and the key kept (`.ended`), so the
    /// same source is tried again only after `AudioSourceRule.retryInterval`.
    @MainActor
    private func failed(_ key: AudioKey, _ why: String) {
        phase = .ended
        print("Audio: could not capture \(Self.said(key)): \(why). The picture is unaffected.")
        sourceStatus = Status(source: Self.shown(key), capturing: false, problem: "couldn’t capture \(Self.soundOf(key)): \(why)")
    }

    /// The source ended by itself (the permission revoked, the system stopping the stream).
    @MainActor
    private func ended(generation g: Int, why: String) {
        guard g == generation, phase == .running || phase == .starting else { return }
        phase = .ended
        source = nil
        print("Audio capture ended: \(why). The picture is unaffected.")
        sourceStatus = Status(source: Self.shown(current), capturing: false, problem: "couldn’t capture \(Self.soundOf(current)): \(why)")
        generation += 1
        let next = generation
        queue.async { self.live = next; self.packetizer = nil; self.encoder = nil }
    }


    /// The Mac's status: "Safari", "Whole Mac", "Test Tone".
    static func shown(_ key: AudioKey) -> String {
        switch key {
        case .app(_, let name): return name
        case .desktop: return "Whole Mac"
        case .test: return "Test Tone"
        case .none: return ""
        }
    }

    /// The log's words: "Safari's sound", "the whole Mac's sound", "the test tone".
    static func said(_ key: AudioKey) -> String {
        switch key {
        case .app(_, let name): return "\(name)'s sound"
        case .desktop: return "the whole Mac's sound"
        case .test: return "the test tone"
        case .none: return "no sound"
        }
    }

    /// The Mac's and the device's words: "the sound of Safari", "the sound of the whole Mac".
    static func soundOf(_ key: AudioKey) -> String {
        switch key {
        case .app(_, let name): return "the sound of \(name)"
        case .desktop: return "the sound of the whole Mac"
        case .test: return "the test tone"
        case .none: return "no sound"
        }
    }

    private static func formatSource(_ key: AudioKey) -> (String, String?) {
        switch key {
        case .app(_, let name): return (AudioFormat.sourceApp, SafeText.label(name))
        case .desktop: return (AudioFormat.sourceDesktop, nil)
        case .test, .none: return (AudioFormat.sourceTest, nil)
        }
    }

    // MARK: The sound (on `queue`)

    /// A chunk from the source of generation `g`: into the packetizer, each block it completes through
    /// the encoder, each packet stamped and handed to the server. The first chunk of a source, or of a
    /// new format, makes the epoch's encoder and its format message.
    private func took(_ chunk: PCMChunk, generation g: Int) {
        guard g == live, !encoderUnavailable else { return }
        Stats.shared.bump("aud.in")
        if packetizer.map({ !$0.takes(chunk) }) ?? true {
            guard newEpoch(for: chunk) else { return }
        }
        guard var p = packetizer, let enc = encoder else { return }
        let blocks = p.push(chunk)
        if p.gaps > gapsSeen { Stats.shared.bump("aud.gap"); gapsSeen = p.gaps }
        packetizer = p
        for block in blocks {
            if block.segmentStart { enc.reset() }
            guard let packet = enc.encode(block.samples) else { continue }
            Stats.shared.bump("aud.out")
            // The host clock's time to the wall clock, as the video's stamps are (StreamMessage): at the
            // moment it goes, so a step of the Mac's wall clock shows in the sound as in the picture.
            let stamp = Date().timeIntervalSince1970 - (HostClock.now() - block.hostTime)
            let payload = AudioPackets(epoch: epoch, seq: seq, segmentStart: block.segmentStart, packets: [packet]).serialized()
            seq &+= 1
            onPackets?(StreamMessage(kind: .audio, timestamp: stamp, isKeyframe: false, payload: payload).serialized(), epoch)
        }
    }

    /// A new epoch for `chunk`'s format: its encoder (the packet size from this first chunk), its
    /// packetizer, and its format message to the server. False when there is no sound to make.
    private func newEpoch(for chunk: PCMChunk) -> Bool {
        guard chunk.sampleRate == AudioEncoder.sampleRate, chunk.channels == AudioEncoder.channels else {
            if !formatRefused {
                formatRefused = true
                let why = "the capture delivered \(Int(chunk.sampleRate)) Hz with \(chunk.channels) channel\(chunk.channels == 1 ? "" : "s"), and Sill encodes 48 kHz stereo only"
                print("Audio: \(why).")
                Task { @MainActor in self.formatProblem(why) }
            }
            return false
        }
        let packet = AudioPacketizer.packetSize(firstChunkFrames: chunk.frames)
        let enc: AudioEncoder
        do {
            enc = try AudioEncoder(framesPerPacket: packet)
        } catch {
            encoderUnavailable = true
            print("Audio encoder: AAC-ELD unavailable: \(error)")
            Task { @MainActor in self.encoderProblem("\(error)") }
            return false
        }
        epoch = (epoch + 1) & 0xFFFF
        seq = 0
        gapsSeen = 0
        encoder = enc
        packetizer = AudioPacketizer(framesPerPacket: enc.framesPerPacket, priming: enc.priming, channels: chunk.channels,
                                     sampleRate: chunk.sampleRate)
        let format = AudioFormat(codec: AudioCodec.aacELD, sampleRate: Int(AudioEncoder.sampleRate), channels: AudioEncoder.channels,
                                 framesPerPacket: enc.framesPerPacket, primingFrames: enc.priming, bitrate: enc.bitrate, epoch: epoch,
                                 cookie: enc.cookie, source: info.source, app: info.app)
        let ms = String(format: "%.1f", Double(enc.framesPerPacket) / AudioEncoder.sampleRate * 1000)
        print("Audio encoder: AAC-ELD 48 kHz stereo, \(enc.framesPerPacket) frames a packet (\(ms) ms), \(enc.bitrate / 1000) kbps, codec delay \(enc.priming) frames.")
        onFormat?(StreamMessage(kind: .audio, timestamp: Date().timeIntervalSince1970, isKeyframe: false,
                                payload: AudioMessage.format(format).serialized()).serialized(), epoch)
        return true
    }

    @MainActor
    private func encoderProblem(_ why: String) {
        encoderGone = true
        guard var s = sourceStatus else { return }
        s.capturing = false
        s.problem = "couldn’t encode the sound: AAC-ELD is unavailable (\(why))"
        sourceStatus = s
    }

    @MainActor
    private func formatProblem(_ why: String) {
        guard var s = sourceStatus else { return }
        s.capturing = false
        s.problem = "couldn’t use the sound: \(why)"
        sourceStatus = s
    }
}
