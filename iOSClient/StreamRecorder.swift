import AudioToolbox
import AVFoundation
import CoreMedia
import Foundation
import SillAudio
import StreamProtocol

/// The stream recorded on this device (#284, docs/recording-plan.md; addhumal's #303 began it): the HEVC frames as
/// they came, never re-encoded, written with AVAssetWriter into a QuickTime movie, with the Mac's sound decoded on
/// its own and encoded to AAC (which plays everywhere, as AAC-ELD may not). Every decision is RecordingTimeline's
/// (pure, Tests/checks/recording): this class carries out its actions. One recorder per recording.
///
/// - Taps, on the network queue `sill.net` (StreamClient's `queue`), before the display sees anything: the
///   parameter sets, each frame with the Mac's stamp and its arrival, the sound's messages. From "1" until the
///   light they make the pre-roll; from the light on they go to `sill.recorder`, at most `pendingLimit` bytes of
///   frames waiting there (latency before quality: a frame past it is dropped in its place, and the chain waits
///   for a keyframe).
/// - `sill.recorder` (its own serial queue): the timeline, the format descriptions and samples, the sound's
///   decoders (one per epoch), every AVAssetWriter call, the light's numbers and space once a second. What its
///   owner needs to know goes to the main queue (`onEvent`).
/// - Each part is a movie of its own ("Sill 2026-11-18 at 14.03.12.mov", " (2)" and so on), written in fragments
///   every `fragmentInterval`, so an interruption loses at most its last seconds; its session ends at the stop's
///   time, so a still window's last picture lasts until Stop. A failed writer keeps what it wrote (never
///   `cancelWriting`, which deletes the file).
///
/// AVFoundation, CoreMedia and AudioToolbox only, never UIKit: the folder, the protection and the free space come
/// from the caller, so `Scripts/recording-check` compiles this file on the Mac and records a test host's stream
/// into a folder of its own. Arrivals are the host clock's seconds (CACurrentMediaTime, `hostNow`).
final class StreamRecorder: @unchecked Sendable {
    /// What a recorder needs from its caller.
    struct Setup {
        /// Where its movies go: SillDocuments' Sill Recordings on the device.
        var folder: URL
        /// The light's moment on this device's clock, for the names.
        var start: Date
        var timeZone: TimeZone = .current
        /// The movie gets a sound track (RecordingPolicy.recordsSound, at "1").
        var withSound: Bool
        /// Gives a new movie its folder's protection.
        var protect: (URL) -> Void = { _ in }
        /// The folder's volume's available capacity for important usage; nil when it cannot be read.
        var freeSpace: () -> Int64? = { nil }
        /// "iPad", "iPhone": the writer's reason in words names it.
        var device = "device"
        var fragmentInterval: TimeInterval = RecordingPolicy.fragmentInterval
        var pendingLimit = RecordingPolicy.pendingLimit
        var prerollLimit = RecordingPolicy.prerollLimit
    }

    /// What the owner hears, on the main queue.
    enum Event {
        /// The first part opened: the movie's 0:00 is known ("Starting…" is over).
        case started
        /// Once a second from the light: the movie's time so far (nil while "Starting…"), the bytes the light
        /// says, and space's word (rule 9, looked at every 5 s).
        case progress(seconds: Double?, bytes: Int64, space: RecordingPolicy.Space)
        /// The chain broke: ask the Mac for a keyframe (rule 2's spacing).
        case askKeyframe
        /// The writer failed: its reason in words (the recording ends).
        case failed(String)
    }

    /// The end: the movies written (finished, or kept by their fragments), each one's 0:00 on the Mac's clock as
    /// the recording kept it (the rig finds the test tone's clicks by it), and the writer's reason if it failed.
    struct Outcome {
        var movies: [URL]
        var partStarts: [Double]
        var failure: String?
    }

    /// One frame as it came.
    struct Frame {
        var id: Int
        var data: Data
        var stamp: Double
        var arrival: Double
        var isKeyframe: Bool
    }

    /// Set on the main queue before the light; read where events are posted.
    var onEvent: ((Event) -> Void)?
    let setup: Setup

    /// The host clock in seconds: CACurrentMediaTime's, through CoreMedia.
    static func hostNow() -> Double { CMClockGetTime(CMClockGetHostTimeClock()).seconds }

    private let queue = DispatchQueue(label: "sill.recorder", qos: .userInitiated)

    // MARK: On `sill.net`

    /// The pre-roll, from "1" until the light; nil after it.
    private var preroll: RecordingPolicy.Preroll<Frame>?
    /// Every frame since "1" (and the last keyframe), for the clock's floor: in their order.
    private var seeds: [(stamp: Double, arrival: Double)] = []
    /// The newest parameter sets, encoded.
    private var tapSets: Data?
    private var nextID = 0
    /// The light has come: frames go to `sill.recorder`.
    private var live = false
    /// Stopped: nothing more is taken.
    private var tapStopped = false
    /// Frames handed to `sill.recorder` and not yet taken there (bytes); written on both queues.
    private let pendingLock = NSLock()
    private var pendingBytes = 0

    // MARK: On `sill.recorder`

    private var timeline: RecordingTimeline<Data>
    private var part: Part?
    private var movies: [URL] = []
    private var partStarts: [Double] = []
    private var failure: String?
    /// The frames an action may name, by id, while the timeline's call that named them is carried out.
    private var frames: [Int: (data: Data, key: Bool)] = [:]
    /// The sound's decoders, by epoch.
    private var decoders: [Int: AudioDecoder] = [:]
    private let pcmFormat: CMAudioFormatDescription?
    private var frameBytes: Int64 = 0
    private var soundFrames: Int64 = 0
    private var byteSamples: [(time: TimeInterval, bytes: Int64)] = []
    private var timer: DispatchSourceTimer?
    private var space = RecordingPolicy.Space.fine
    private var ticksToSpace = 0
    private var finished = false
    /// Parts closing (their `finishWriting` running), and what waits for them.
    private var closing = 0
    private var whenClosed: [() -> Void] = []

    init(_ setup: Setup) {
        self.setup = setup
        timeline = RecordingTimeline(withSound: setup.withSound)
        var asbd = AudioStreamBasicDescription(mSampleRate: Double(RecordedSound.rate), mFormatID: kAudioFormatLinearPCM,
                                               mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                                               mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8,
                                               mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        var layout = AudioChannelLayout()
        layout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
        var made: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: MemoryLayout<AudioChannelLayout>.size, layout: &layout,
                                       magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &made)
        pcmFormat = made
        preroll = RecordingPolicy.Preroll(limit: setup.prerollLimit)
    }

    // MARK: - The taps (sill.net)

    /// At "1": the newest parameter sets, the session's last keyframe (its stamp and arrival seed the clock) and
    /// its latest sound format (the Mac sends one per epoch, before its packets). On `sill.net`.
    func begin(sets: Data?, lastKeyframe: Frame?, audioFormat: AudioFormat?) {
        tapSets = sets
        if let k = lastKeyframe { seeds.append((k.stamp, k.arrival)) }
        if let f = audioFormat, setup.withSound { queue.async { [self] in takeFormat(f) } }
    }

    /// A kind 0. On `sill.net`.
    func parameterSets(_ encoded: Data, arrival: Double) {
        guard !tapStopped else { return }
        if encoded != tapSets { preroll?.newSource() }
        tapSets = encoded
        guard live else { return }
        queue.async { [self] in run(timeline.parameterSets(encoded, arrival: arrival), now: arrival) }
    }

    /// A kind 1, with the header's stamp and keyframe flag and its arrival. On `sill.net`.
    func frame(_ data: Data, stamp: Double, isKeyframe: Bool, arrival: Double) {
        guard !tapStopped else { return }
        nextID += 1
        let id = nextID
        guard live else {
            preroll?.take(Frame(id: id, data: data, stamp: stamp, arrival: arrival, isKeyframe: isKeyframe), bytes: data.count,
                          isKeyframe: isKeyframe)
            seeds.append((stamp, arrival))
            return
        }
        let size = data.count
        let taken = pendingLock.withLock { () -> Bool in
            guard pendingBytes + size <= setup.pendingLimit else { return false }
            pendingBytes += size
            return true
        }
        guard taken else {
            // Dropped before it queues: in its place, the chain waits for a keyframe.
            queue.async { [self] in run(timeline.lost(), now: arrival) }
            return
        }
        queue.async { [self] in
            pendingLock.withLock { pendingBytes -= size }
            frames[id] = (data, isKeyframe)
            run(timeline.frame(id: id, stamp: stamp, isKeyframe: isKeyframe, arrival: arrival), now: arrival)
            frames[id] = nil
        }
    }

    /// A kind 43, parsed, with the header's stamp. On `sill.net`.
    func audio(_ message: AudioMessage, stamp: Double) {
        guard !tapStopped, setup.withSound else { return }
        switch message {
        case .format(let f):
            queue.async { [self] in takeFormat(f) }
        case .packets(let p):
            guard live else { return }
            queue.async { [self] in takePackets(p, stamp: stamp) }
        }
    }

    /// The light, at `arrival`: where the movie starts (RecordingPolicy.start), and from here on every frame goes
    /// to the recorder. `lastKeyframe`: the session's (id −1), with `framesSinceKeyframe` frames since it (new
    /// parameter sets count as one). On `sill.net`.
    func light(arrival: Double, lastKeyframe: Frame?, framesSinceKeyframe: Int) -> RecordingPolicy.StartPoint {
        let pre = preroll ?? RecordingPolicy.Preroll(limit: setup.prerollLimit)
        let start = RecordingPolicy.start(keyframeSinceAsk: pre.holdsKeyframe, lastKeyframeKept: lastKeyframe != nil,
                                          framesSinceKeyframe: framesSinceKeyframe)
        let kept = pre.holdsKeyframe ? pre.frames : [], seeds = self.seeds, sets = tapSets
        preroll = nil
        self.seeds = []
        live = true
        queue.async { [self] in
            for f in kept { frames[f.id] = (f.data, f.isKeyframe) }
            if let k = lastKeyframe { frames[k.id] = (k.data, true) }
            let actions = timeline.begin(start, sets: sets,
                                         preroll: kept.map { .init(id: $0.id, stamp: $0.stamp, arrival: $0.arrival, isKeyframe: $0.isKeyframe) },
                                         lastKeyframe: lastKeyframe.map { .init(id: $0.id, stamp: $0.stamp, arrival: $0.arrival, isKeyframe: true) },
                                         seeds: seeds, light: arrival)
            run(actions, now: arrival)
            frames = [:]
            startTimer()
        }
        return start
    }

    /// Stops the taps at once (on `sill.net`, before `stop`): nothing is taken after this.
    func closeTaps() { tapStopped = true }

    /// The end, at `arrival` (the stop's moment on the host clock): the open movie closed at the stop's time, its
    /// writer finished; `done` gets the outcome on the main queue. From any thread.
    func stop(arrival: Double, done: @escaping (Outcome) -> Void) {
        queue.async { [self] in
            timer?.cancel(); timer = nil
            finished = true
            run(timeline.stop(arrival: arrival), now: arrival)
            finishAll { [self] in
                let outcome = Outcome(movies: movies, partStarts: partStarts, failure: failure)
                DispatchQueue.main.async { done(outcome) }
            }
        }
    }

    // MARK: - The actions (sill.recorder)

    /// One movie being written.
    private final class Part {
        let writer: AVAssetWriter
        let video: AVAssetWriterInput
        let audio: AVAssetWriterInput?
        let format: CMVideoFormatDescription
        var lastTicks: Int64?
        var heldLeft: [Float] = []
        var heldRight: [Float] = []
        /// The sound track's frames so far.
        var soundAt: Int64 = 0
        init(writer: AVAssetWriter, video: AVAssetWriterInput, audio: AVAssetWriterInput?, format: CMVideoFormatDescription) {
            self.writer = writer; self.video = video; self.audio = audio; self.format = format
        }
    }

    private func run(_ actions: [RecordingTimeline<Data>.Action], now: Double, decoded: [Int: (left: [Float], right: [Float])] = [:]) {
        var skipping = false
        for action in actions {
            switch action {
            case .open(let n, let sets):
                skipping = false
                open(n, sets: sets)
            case .picture(let id, let at):
                guard !skipping else { continue }
                if let f = frames[id], write(f.data, isKeyframe: f.key, at: at) { continue }
                // Not written: every delta waits for a keyframe, the rest of this batch with it.
                skipping = true
                run(timeline.notWritten(), now: now)
            case .sound(let writes):
                sound(writes, decoded: decoded)
            case .close(_, let at):
                close(at: at)
            case .askKeyframe:
                post(.askKeyframe)
            }
        }
    }

    private func post(_ event: Event) {
        let onEvent = self.onEvent
        DispatchQueue.main.async { onEvent?(event) }
    }

    private func open(_ n: Int, sets: Data) {
        guard failure == nil else { return }
        guard let ps = ParameterSets(encoded: sets), let format = Self.formatDescription(ps) else {
            fail("the picture’s format couldn’t be read")
            return
        }
        let fm = FileManager.default
        try? fm.createDirectory(at: setup.folder, withIntermediateDirectories: true)
        let folder = setup.folder
        let name = RecordingPolicy.fileName(start: setup.start, part: n, timeZone: setup.timeZone) {
            fm.fileExists(atPath: folder.appendingPathComponent($0).path)
        }
        let url = folder.appendingPathComponent(name)
        do {
            let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
            writer.movieFragmentInterval = CMTime(seconds: setup.fragmentInterval, preferredTimescale: 600)
            let video = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: format)
            video.expectsMediaDataInRealTime = true
            guard writer.canAdd(video) else { fail("the picture couldn’t be added to the movie"); return }
            writer.add(video)
            var audio: AVAssetWriterInput?
            if setup.withSound {
                var layout = AudioChannelLayout()
                layout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
                let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: RecordedSound.rate,
                                               AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: RecordingPolicy.soundBitrate,
                                               AVChannelLayoutKey: Data(bytes: &layout, count: MemoryLayout<AudioChannelLayout>.size)]
                let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings, sourceFormatHint: pcmFormat)
                input.expectsMediaDataInRealTime = true
                if writer.canAdd(input) { writer.add(input); audio = input }
            }
            guard writer.startWriting() else { fail(reason(writer.error)); return }
            writer.startSession(atSourceTime: Self.videoTime(0))
            setup.protect(url)
            movies.append(url)
            partStarts.append((timeline.clock.anchor ?? 0) + timeline.partStart)
            part = Part(writer: writer, video: video, audio: audio, format: format)
            if n == 1 { post(.started) }
        } catch {
            fail(reason(error))
        }
    }

    /// A frame at part time `at`: its own sample (never the display's), a delta marked as one. False when it was
    /// not written.
    private func write(_ data: Data, isKeyframe: Bool, at: Double) -> Bool {
        guard let part, failure == nil else { return false }
        var ticks = RecordingClock.ticks(at + RecordingTimeline<Data>.sourceBase)
        if let last = part.lastTicks, ticks <= last { ticks = last + 1 }
        guard part.video.isReadyForMoreMediaData,
              let sample = Self.sample(data, format: part.format, ticks: ticks, isKeyframe: isKeyframe) else { return false }
        guard part.video.append(sample) else {
            if part.writer.status == .failed { fail(reason(part.writer.error)) }
            return false
        }
        part.lastTicks = ticks
        frameBytes += Int64(data.count)
        return true
    }

    private func close(at: Double) {
        guard let part else { return }
        self.part = nil
        let writer = part.writer
        guard writer.status == .writing else {
            if writer.status == .failed { fail(reason(writer.error)) }
            return
        }
        part.video.markAsFinished()
        part.audio?.markAsFinished()
        writer.endSession(atSourceTime: Self.videoTime(at))
        closing += 1
        writer.finishWriting { [self] in
            queue.async { [self] in
                if writer.status == .failed { fail(reason(writer.error)) }
                closing -= 1
                if closing == 0 { let waiting = whenClosed; whenClosed = []; waiting.forEach { $0() } }
            }
        }
    }

    private func finishAll(_ done: @escaping () -> Void) {
        if closing == 0 { done() } else { whenClosed.append(done) }
    }

    private func fail(_ why: String) {
        guard failure == nil else { return }
        failure = why
        if !finished { post(.failed(why)) }
    }

    private func reason(_ error: Error?) -> String {
        let e = error as NSError?
        return RecordingPolicy.Copy.writerReason(domain: e?.domain ?? "", code: e?.code ?? 0,
                                                 description: e?.localizedDescription ?? "", device: setup.device)
    }

    // MARK: - The sound (sill.recorder)

    private func takeFormat(_ f: AudioFormat) {
        guard setup.withSound, let epoch = f.epoch, let frames = f.framesPerPacket,
              AudioDecoder.codecs.contains(f.codec ?? ""), (f.sampleRate ?? 48_000) == 48_000, (f.channels ?? 2) == 2 else { return }
        if decoders[epoch]?.framesPerPacket == frames, timeline.formats[epoch] != nil { return }   // a repeat
        guard let decoder = try? AudioDecoder(framesPerPacket: frames, cookie: f.cookie ?? Data()) else { return }
        decoders[epoch] = decoder
        timeline.audioFormat(epoch: epoch, RecordedSound.Format(framesPerPacket: frames, primingFrames: f.primingFrames ?? 0))
    }

    private func takePackets(_ p: AudioPackets, stamp: Double) {
        guard let decoder = decoders[p.epoch], let format = timeline.formats[p.epoch] else { return }
        for (i, packet) in p.packets.enumerated() {
            let at = stamp + Double(i * format.framesPerPacket) / Double(RecordedSound.rate)
            let (decode, writes) = timeline.audio(epoch: p.epoch, seq: p.seq &+ UInt32(i), index: i,
                                                  segmentStart: p.segmentStart, stamp: at)
            var pcm: (left: [Float], right: [Float])?
            switch decode {
            case .skip: continue
            case .decode(let reset):
                if reset { decoder.reset() }
                pcm = decoder.decode(packet)
            }
            if !writes.isEmpty { sound(writes, decoded: pcm.map { [i: $0] } ?? [:]) }
        }
    }

    /// Writes onto the open part's track, in order: silence, the held tail, a decoded packet's frames.
    private func sound(_ writes: [RecordedSound.Write], decoded: [Int: (left: [Float], right: [Float])]) {
        guard let part, part.audio != nil else { return }
        for w in writes {
            switch w {
            case .silence(let n):
                var left = n
                while left > 0 {
                    let chunk = min(left, RecordedSound.rate)
                    let zeros = [Float](repeating: 0, count: chunk)
                    appendPCM(zeros, zeros, part)
                    left -= chunk
                }
            case .tail(let fadeOut):
                var l = part.heldLeft, r = part.heldRight
                part.heldLeft = []; part.heldRight = []
                if fadeOut { Self.fade(&l, in: false); Self.fade(&r, in: false) }
                appendPCM(l, r, part)
            case .packet(let index, let from, let count, let fadeIn, let hold):
                // A packet the converter refused is silence in its place: the track keeps its length.
                var l = decoded[index].map { Array($0.left.dropFirst(from).prefix(count)) } ?? []
                var r = decoded[index].map { Array($0.right.dropFirst(from).prefix(count)) } ?? []
                if l.count < count || r.count < count { l = [Float](repeating: 0, count: count); r = l }
                if fadeIn { Self.fade(&l, in: true); Self.fade(&r, in: true) }
                appendPCM(Array(l.prefix(count - hold)), Array(r.prefix(count - hold)), part)
                part.heldLeft = Array(l.suffix(hold)); part.heldRight = Array(r.suffix(hold))
            }
        }
    }

    /// Interleaves and appends `left`/`right` at the track's next frame. An input that is not ready loses these
    /// frames but keeps the track's timeline: the next ones go where they belong.
    private func appendPCM(_ left: [Float], _ right: [Float], _ part: Part) {
        let n = min(left.count, right.count)
        guard n > 0, let input = part.audio, let pcmFormat else { return }
        let at = part.soundAt
        part.soundAt += Int64(n)
        soundFrames += Int64(n)
        guard input.isReadyForMoreMediaData else { return }
        var interleaved = [Float](repeating: 0, count: 2 * n)
        for i in 0..<n { interleaved[2 * i] = left[i]; interleaved[2 * i + 1] = right[i] }
        let bytes = 2 * n * MemoryLayout<Float>.size
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil,
                                                 customBlockSource: nil, offsetToData: 0, dataLength: bytes, flags: 0,
                                                 blockBufferOut: &block) == noErr, let block,
              CMBlockBufferAssureBlockMemory(block) == noErr,
              interleaved.withUnsafeBytes({ CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block,
                                                                         offsetIntoDestination: 0, dataLength: bytes) }) == noErr
        else { return }
        let base = Int64((RecordingTimeline<Data>.sourceBase * Double(RecordedSound.rate)).rounded())
        let pts = CMTime(value: base + at, timescale: CMTimeScale(RecordedSound.rate))
        var sample: CMSampleBuffer?
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block, formatDescription: pcmFormat,
                                                                   sampleCount: n, presentationTimeStamp: pts,
                                                                   packetDescriptions: nil, sampleBufferOut: &sample) == noErr,
              let sample else { return }
        if !input.append(sample), part.writer.status == .failed { fail(reason(part.writer.error)) }
    }

    /// A raised-cosine fade over the first (`in`) or last 5 ms, in place, as the playout's (AudioPlayout.fade).
    static func fade(_ x: inout [Float], in fadeIn: Bool, frames: Int = RecordedSound.fadeFrames) {
        let n = min(frames, x.count)
        guard n > 0 else { return }
        for i in 0..<n {
            let g = Float(0.5 - 0.5 * cos(Double.pi * Double(i + 1) / Double(n + 1)))
            if fadeIn { x[i] *= g } else { x[x.count - 1 - i] *= g }
        }
    }

    // MARK: - The light's numbers and space (sill.recorder)

    private func startTimer() {
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1, repeating: 1)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
        tick()
    }

    /// Once a second: the light's numbers; every `spaceEvery` seconds, space (rule 9).
    private func tick() {
        let now = Self.hostNow()
        let bytes = RecordingPolicy.bytes(frames: frameBytes, soundSeconds: Double(soundFrames) / Double(RecordedSound.rate))
        byteSamples.append((now, bytes))
        byteSamples.removeAll { $0.time <= now - RecordingPolicy.rateWindow - 1 }
        ticksToSpace -= 1
        if ticksToSpace <= 0 {
            ticksToSpace = Int(RecordingPolicy.spaceEvery)
            if let free = setup.freeSpace() {
                space = RecordingPolicy.space(freeBytes: free, bytesPerSecond: RecordingPolicy.rate(byteSamples, now: now))
            }
        }
        post(.progress(seconds: timeline.elapsed(arrival: now), bytes: bytes, space: space))
    }

    // MARK: - Samples

    /// A part time on the writer's clock (`sourceBase` added: the pre-roll lies before 0:00).
    static func videoTime(_ at: Double) -> CMTime {
        CMTime(value: RecordingClock.ticks(at + RecordingTimeline<Data>.sourceBase), timescale: RecordingClock.videoTimescale)
    }

    /// The format description for parameter sets, as the display makes its own (HEVCDisplayView.apply).
    static func formatDescription(_ ps: ParameterSets) -> CMVideoFormatDescription? {
        guard !ps.sets.isEmpty else { return nil }
        let buffers = ps.sets.map { set -> UnsafeMutablePointer<UInt8> in
            let p = UnsafeMutablePointer<UInt8>.allocate(capacity: max(set.count, 1))
            set.copyBytes(to: p, count: set.count)
            return p
        }
        defer { buffers.forEach { $0.deallocate() } }
        var desc: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(
            allocator: nil, parameterSetCount: buffers.count, parameterSetPointers: buffers.map { UnsafePointer($0) },
            parameterSetSizes: ps.sets.map(\.count), nalUnitHeaderLength: Int32(ps.nalUnitHeaderLength),
            extensions: nil, formatDescriptionOut: &desc)
        return status == noErr ? desc : nil
    }

    /// One frame's sample: its bytes copied, its time, no decode time (no B-frames), no duration (the next
    /// sample's time gives it, the session's end the last one's); a delta marked not sync and depending on others
    /// (samples are sync unless marked, and the mark is written into the movie).
    static func sample(_ data: Data, format: CMVideoFormatDescription, ticks: Int64, isKeyframe: Bool) -> CMSampleBuffer? {
        let count = data.count
        var block: CMBlockBuffer?
        guard count > 0,
              CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: count, blockAllocator: nil,
                                                 customBlockSource: nil, offsetToData: 0, dataLength: count, flags: 0,
                                                 blockBufferOut: &block) == noErr, let block,
              CMBlockBufferAssureBlockMemory(block) == noErr,
              data.withUnsafeBytes({ CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block,
                                                                  offsetIntoDestination: 0, dataLength: count) }) == noErr
        else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid,
                                        presentationTimeStamp: CMTime(value: ticks, timescale: RecordingClock.videoTimescale),
                                        decodeTimeStamp: .invalid)
        var size = count
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1,
                                        sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                        sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample) == noErr,
              let sample else { return nil }
        if !isKeyframe, let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as NSArray?,
           let first = attachments.firstObject as? NSMutableDictionary {
            first[kCMSampleAttachmentKey_NotSync as String] = true
            first[kCMSampleAttachmentKey_DependsOnOthers as String] = true
        }
        return sample
    }
}
