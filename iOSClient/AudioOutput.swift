import AVFAudio
import Foundation
import QuartzCore
import StreamProtocol
import UIKit

/// The Mac's sound on this device (docs/audio-plan.md §7.3, §7.4): kind 29's formats and packets in,
/// through the playout model (AudioPlayout, which decides) and the decoder (AudioDecoder), onto an
/// AVAudioPlayerNode → the main mixer → the output. Every line of Sill's runs on `queue`: the player
/// node schedules, and the real-time code is Apple's (AVAudioSourceNode's real-time block is not for
/// Swift, AVAudioSourceNode.h).
///
/// The engine runs while a format has come, sound is not muted, the app is in the foreground and a
/// packet came within 10 s; the audio session (.playback, mixing with other audio, so it never stops
/// the person's music and plays with the silent switch on, as a video app does) is active only while
/// it runs. It stops on mute (after a short fade), in the background, at the session's end and after
/// 10 s without a packet, and the next packet starts it again. Interruptions, route changes, a media
/// services reset and the engine's configuration change are handled here; headphones taken out mute
/// the sound and say so (`onRouteMuted`), as a video app pauses.
///
/// In the simulator, and in a DEBUG build asked with `-SillSoundSink manual`, the engine renders in
/// manual (offline) mode instead: it never opens an output device and never activates the session, so
/// nothing can reach a speaker, the Mac's included. A timer on `queue` pulls what a real output would,
/// as the clock goes, with a stand-in IO buffer (5 ms) and output latency (10 ms), and the console says
/// where each click of the test tone was heard. DEBUG `-SillSoundVolume 0` sets the player's volume to
/// 0 besides. (`-SillSoundSink device` in a DEBUG simulator build opens the output, for a person at
/// the simulator who wants to hear it.)
///
/// Threads: the client hands everything over from the network queue (formats, packets, frames,
/// stamped there) and the main thread (mute, the session, the route); the player's completion handlers
/// return buffers to the pool under its lock; the once-a-second stats are read under `statsLock`.
final class AudioOutput {
    let queue = DispatchQueue(label: "sill.audio", qos: .userInteractive)

    /// Headphones taken out (the route's old device unavailable): the client mutes and says so. Main thread.
    var onRouteMuted: (() -> Void)?

    // On `queue`.
    private var model = AudioPlayout()
    private var decoder: AudioDecoder?
    /// The epoch playing: its format, and whether this device plays its codec.
    private var playing: (epoch: Int, framesPerPacket: Int, codec: String, playable: Bool)?
    /// Each kept packet's frames (after its priming), by the model's id.
    private var kept: [Int: (left: [Float], right: [Float])] = [:]
    private var engine: SoundEngine?
    private var muted = false
    private var foreground = true
    /// The session's connection is live (between `sessionStarted` and `sessionEnded`).
    private var sessionLive = false
    /// A session activation failed (a call): no start until the interruption ends or the app comes back.
    private var activationBlocked = false
    private var lastPacketAt: Double?
    private var deadlineTimer: DispatchSourceTimer?
    private var secondTimer: DispatchSourceTimer?
    private var refresh = 1.0 / 60
    private var streamFPS = 60.0
    private var away = false
    /// The route's name as last read, for a route change's line.
    private var routeSeen: String?
    #if DEBUG
    private var clicks = ClickFinder()
    #endif

    // The last closed second, for the client's stats (its network queue) and the HUD.
    private let statsLock = NSLock()
    private var lastSecond: AudioPlayout.Second?
    private var lateSinceTaken = 0
    private var anyPlayed = false

    /// Idle: no packet for this long stops the engine (rule 14).
    static let idleAfter = 10.0

    init(refresh: Double) {
        self.refresh = refresh
        let center = NotificationCenter.default
        center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in
            self?.queue.async { self?.foregroundChanged(false) }
        }
        center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil) { [weak self] _ in
            self?.queue.async { self?.foregroundChanged(true) }
        }
        center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) { [weak self] _ in
            self?.queue.async { self?.activationBlocked = false }
        }
        center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: nil) { [weak self] note in
            self?.queue.async { self?.interrupted(note) }
        }
        center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: nil) { [weak self] note in
            self?.queue.async { self?.routeChanged(note) }
        }
        center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: nil) { [weak self] _ in
            self?.queue.async { self?.servicesReset() }
        }
    }

    // MARK: - From the client

    /// A new session connection (a connect, a reconnect): nothing of the last one's sound is kept. A
    /// move's hand-over is not one. Any thread.
    func sessionStarted(away: Bool) {
        queue.async { [self] in
            stopEngine(reason: nil)
            _ = model.reset(.session)
            kept = [:]
            decoder = nil
            playing = nil
            sessionLive = true
            self.away = away
            model.away(away)
            statsLock.withLock { lastSecond = nil; lateSinceTaken = 0; anyPlayed = false }
            #if DEBUG
            clicks = ClickFinder()
            #endif
        }
    }

    /// The session ended (a tear-down): the engine stops. Any thread.
    func sessionEnded() {
        queue.async { [self] in
            sessionLive = false
            stopEngine(reason: nil)
            _ = model.reset(.session)
            kept = [:]
            decoder = nil
            playing = nil
            lastPacketAt = nil
            secondTimer?.cancel()
            secondTimer = nil
            statsLock.withLock { lastSecond = nil; lateSinceTaken = 0 }
        }
    }

    /// This device's mute (the Sound button and switch): at once, locally; the Mac keeps sending, and
    /// each packet still counts for the floor and the cover, so unmuting is quick. Any thread.
    func setMuted(_ on: Bool) {
        queue.async { [self] in
            guard muted != on else { return }
            muted = on
            model.mute(on)
            if on {
                stopEngine(reason: "muted", fade: true)
            } else {
                // The decoder's state is stale: the next packet starts it afresh (rule 9).
                apply(model.reset(.playback))
                #if DEBUG
                print("audio: unmuted")
                #endif
            }
        }
    }

    /// The session goes away from home or comes home (the cover's start and bounds). Any thread.
    func setAway(_ on: Bool) { queue.async { [self] in away = on; model.away(on) } }

    /// The stream's frame rate, for the guard's one frame. Any thread.
    func setStreamFPS(_ fps: Int) { queue.async { [self] in if fps > 0 { streamFPS = Double(fps); readLatencies() } } }

    /// The pings' median round trip of the last second (rule 13's threshold). Any thread.
    func rtt(median ms: Int?) { queue.async { [self] in model.rtt(median: ms.map { Double($0) / 1000 }) } }

    /// A video frame, stamped as the network queue took it (rule 3).
    func frame(stamp: Double, arrival: Double) {
        queue.async { [self] in model.frame(stamp: stamp, arrival: arrival) }
    }

    /// A kind 29 format.
    func format(_ f: AudioFormat) {
        queue.async { [self] in receive(f) }
    }

    /// A kind 29 packets message and its header's stamp.
    func packets(_ p: AudioPackets, stamp: Double) {
        queue.async { [self] in receive(p, stamp: stamp) }
    }

    /// For the stats sent to the Mac once a second (`ClientStats.audioBehindMs`, `audioLate`): the last
    /// closed second's median of how far the sound trailed the picture (nil: none played in it) and the
    /// packets too late to play since the last call; nil before anything played this session. The two
    /// seconds (this queue's and the client's) are not aligned: a report carries the latest. Any thread.
    func takeSecond() -> (behindMs: Int?, late: Int)? {
        statsLock.withLock {
            guard anyPlayed else { return nil }
            defer { lateSinceTaken = 0 }
            return (lastSecond?.behindMs, lateSinceTaken)
        }
    }

    /// The last second's numbers, for the HUD. Any thread.
    var latestSecond: AudioPlayout.Second? { statsLock.withLock { lastSecond } }

    // MARK: - Formats and packets

    private func receive(_ f: AudioFormat) {
        guard sessionLive, let epoch = f.epoch, let frames = f.framesPerPacket else { return }
        let codec = f.codec ?? ""
        let cookie = f.cookie ?? Data()
        guard model.format(epoch: epoch, framesPerPacket: frames, primingFrames: f.primingFrames ?? 0, cookie: cookie) else { return }
        let playable = AudioDecoder.codecs.contains(codec) && (f.sampleRate ?? 48_000) == 48_000 && (f.channels ?? 2) == 2
        decoder = playable ? try? AudioDecoder(framesPerPacket: frames, cookie: cookie) : nil
        playing = (epoch, frames, codec, playable && decoder != nil)
        #if DEBUG
        if playable, decoder != nil {
            let what = f.app ?? (f.source == AudioFormat.sourceDesktop ? "the whole Mac" : f.source == AudioFormat.sourceTest ? "a test tone" : "?")
            print("audio: format \(codec) \(f.sampleRate ?? 0) Hz \(f.channels ?? 0) ch, \(frames) frames (priming \(f.primingFrames ?? 0)), epoch \(epoch), \(what)")
        } else {
            print("audio: cannot play \(codec.isEmpty ? "an unnamed codec" : codec)\(playable ? " (its cookie was refused)" : "")")
        }
        #endif
    }

    private func receive(_ p: AudioPackets, stamp: Double) {
        guard sessionLive, let fmt = playing, p.epoch == fmt.epoch, fmt.playable, let decoder else { return }
        let now = CACurrentMediaTime()
        lastPacketAt = now
        startSecondTimer()
        if !muted, foreground, !activationBlocked, engine == nil { startEngine() }
        for (i, data) in p.packets.enumerated() {
            let now = CACurrentMediaTime()
            feedReading(now)
            let plan = model.packet(epoch: p.epoch, seq: p.seq &+ UInt32(i), stamp: stamp + Double(i * fmt.framesPerPacket) / AudioPlayout.rate,
                                    segmentStart: p.segmentStart && i == 0, now: now)
            if plan.decode {
                if plan.resetFirst { decoder.reset() }
                let decoded = decoder.decode(data)
                if let id = plan.id {
                    let keep = fmt.framesPerPacket - plan.dropFront
                    if let (l, r) = decoded, l.count == fmt.framesPerPacket, r.count == fmt.framesPerPacket {
                        kept[id] = (Array(l.suffix(keep)), Array(r.suffix(keep)))
                    } else {
                        // Silence in its place; the decoder starts afresh at the next packet.
                        model.decodeFailed()
                        kept[id] = ([Float](repeating: 0, count: keep), [Float](repeating: 0, count: keep))
                    }
                }
            }
            apply(plan.output)
        }
        armDeadline()
    }

    /// What the model says: schedule, or forget.
    private func apply(_ out: AudioPlayout.Output) {
        for id in out.discards { kept[id] = nil }
        for s in out.schedules { schedule(s) }
    }

    private func schedule(_ s: AudioPlayout.Schedule) {
        guard let pcm = kept[s.id] else { return }
        defer { if s.part == .tail { kept[s.id] = nil } }
        guard let engine else { return }
        let end = min(s.offset + s.count, pcm.left.count)
        guard s.offset < end else { return }
        var l = Array(pcm.left[s.offset..<end])
        var r = Array(pcm.right[s.offset..<end])
        if s.change != 0 { AudioPlayout.change(&l, &r, by: s.change) }
        if s.fadeIn { AudioPlayout.fade(&l, in: true); AudioPlayout.fade(&r, in: true) }
        if s.fadeOut { AudioPlayout.fade(&l, in: false); AudioPlayout.fade(&r, in: false) }
        engine.schedule(left: l, right: r, at: s.at)
        #if DEBUG
        clicks.scheduled(start: s.start, frames: l.count, stamp: s.stamp + Double(s.offset) / AudioPlayout.rate)
        #endif
    }

    /// The player's timeline as the engine last rendered it.
    private func feedReading(_ now: Double) {
        guard let engine, let (sample, time) = engine.reading() else { return }
        apply(model.played(sample: sample, at: time, now: now))
    }

    // MARK: - The tail's deadline and the second

    private func armDeadline() {
        deadlineTimer?.cancel()
        deadlineTimer = nil
        guard let d = model.deadline else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + max(0, d - CACurrentMediaTime()), leeway: .nanoseconds(0))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let now = CACurrentMediaTime()
            self.feedReading(now)
            // Its deadline as the fresh reading has it, and no later than now.
            self.apply(self.model.tick(now: max(now, self.model.deadline ?? now)))
            self.armDeadline()
        }
        t.resume()
        deadlineTimer = t
    }

    /// Once a second while sound comes: the model's second closed for the stats, the console's line,
    /// and the idle test (rule 14).
    private func startSecondTimer() {
        guard secondTimer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(20))
        t.setEventHandler { [weak self] in self?.closeSecond() }
        t.resume()
        secondTimer = t
    }

    private func closeSecond() {
        let now = CACurrentMediaTime()
        let s = model.takeSecond(now: now)
        statsLock.withLock {
            lastSecond = s
            lateSinceTaken += s.late
            if s.placed > 0 { anyPlayed = true }
        }
        #if DEBUG
        if engine != nil || s.placed > 0 || s.duplicates > 0 {
            let behind = s.behindMs.map { "\($0) ms behind the picture" } ?? "nothing played"
            print("audio: \(behind); need \(Self.ms(s.need)) (jitter \(Self.ms(s.cover))); late \(s.late); error \(s.error.map { Self.signed($0) } ?? "–"); "
                  + "frames +\(s.framesAdded) -\(s.framesDropped); jumps \(s.jumps)" + (s.duplicates > 0 ? "; duplicates \(s.duplicates)" : "")
                  + (s.joins > 0 ? "; joins \(s.joins)" : ""))
        }
        #endif
        if let last = lastPacketAt, now - last >= Self.idleAfter {
            if engine != nil {
                stopEngine(reason: "idle")
                #if DEBUG
                print("audio: idle, engine off")
                #endif
            }
            secondTimer?.cancel()
            secondTimer = nil
            lastPacketAt = nil
        }
    }

    // MARK: - The engine

    private func startEngine() {
        let sink = SoundEngine.sinkFromLaunchArguments
        let made = SoundEngine(manual: sink == .manual, queue: queue)
        switch made.start() {
        case .success:
            engine = made
            _ = model.reset(.playback)   // a new timeline
            readLatencies()
            routeSeen = made.routeName
            #if DEBUG
            made.onRendered = { [weak self] samples, from in self?.clicks.rendered(samples, from: from, engine: made, model: self?.model) }
            let lag = model.pictureLag(now: CACurrentMediaTime())
            let need = model.need(now: CACurrentMediaTime())
            print("audio: engine on, \(made.routeName), output \(Self.ms(made.outputLatency)), IO \(Self.ms(made.ioBuffer)), "
                  + "delay \(Self.ms(model.delay(now: CACurrentMediaTime(), lag: lag))) (need \(Self.ms(need)): jitter \(Self.ms(model.cover(now: CACurrentMediaTime()))), "
                  + "packet \(Self.ms(Double(model.framesPerPacket) / AudioPlayout.rate)), IO \(Self.ms(made.ioBuffer)), output \(Self.ms(made.outputLatency)), margin 2; "
                  + "picture \(lag.map { Self.ms($0) } ?? "none") + 1 frame \(Self.ms(1 / streamFPS)))")
            #endif
        case .failure(let reason):
            activationBlocked = true
            print("audio: no sound: \(reason)")
        }
    }

    /// Stops the engine and lets the session go; `fade` turns the player down first (a mute), and the
    /// engine stops 20 ms later. The session is let go only once the engine has stopped (with it
    /// running, deactivating fails as busy), and not if another engine has started meanwhile (a mute
    /// undone at once).
    private func stopEngine(reason: String?, fade: Bool = false) {
        deadlineTimer?.cancel()
        deadlineTimer = nil
        apply(model.reset(.playback))
        kept = [:]
        guard let e = engine else { return }
        engine = nil
        let release = { [weak self] in
            e.stop()
            guard let self, self.engine == nil, !e.manual else { return }
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
        if fade {
            e.turnDown()
            queue.asyncAfter(deadline: .now() + 0.02, execute: release)
        } else {
            release()
        }
        #if DEBUG
        if let reason, reason != "idle" { print("audio: engine off (\(reason))") }
        #endif
    }

    private func readLatencies() {
        guard let e = engine else { return }
        model.latency(output: e.outputLatency, io: e.ioBuffer, refresh: refresh, streamFPS: streamFPS)
    }

    private func foregroundChanged(_ on: Bool) {
        foreground = on
        if !on { stopEngine(reason: "in the background") }
    }

    private func interrupted(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            // The system has stopped the engine; nothing starts it again until the interruption ends.
            activationBlocked = true
            stopEngine(reason: "interrupted")
            #if DEBUG
            print("audio: interrupted")
            #endif
        case .ended:
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map { AVAudioSession.InterruptionOptions(rawValue: $0) } ?? []
            // With "should resume" the next packet starts it; without, once the app is active again.
            activationBlocked = !options.contains(.shouldResume)
            #if DEBUG
            print(options.contains(.shouldResume) ? "audio: resumed" : "audio: interruption over; waiting for the app to be active")
            #endif
        @unknown default:
            break
        }
    }

    private func routeChanged(_ note: Notification) {
        guard let e = engine, !e.manual,
              let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        if reason == .oldDeviceUnavailable {
            // Headphones out: muted, as a video app pauses, and said (the client).
            #if DEBUG
            print("audio: muted (headphones disconnected)")
            #endif
            DispatchQueue.main.async { [weak self] in self?.onRouteMuted?() }
            return
        }
        _ = reason
        let before = (route: routeSeen ?? e.routeName, output: model.outputLatency, io: model.ioBuffer)
        readLatencies()
        routeSeen = e.routeName
        // The need follows the route's latency, whatever it is (AirPlay's can be 2 s): the output
        // latency moves the need and the ear alike, the IO buffer only the need, so the next packet is
        // placed by time. A change that moved neither (the session's own category) is nothing.
        guard e.routeName != before.route || abs(model.outputLatency - before.output) > 0.001
                || abs(model.ioBuffer - before.io) > 0.001 else { return }
        apply(model.reset(.jump))
        #if DEBUG
        let change = model.outputLatency - before.output
        print("audio: route \(before.route) → \(e.routeName) (\(change >= 0 ? "+" : "")\(Int((change * 1000).rounded())) ms)")
        #endif
    }

    private func servicesReset() {
        // Every object of the old media services is gone: the next packet builds a new engine and session.
        engine?.abandon()
        engine = nil
        apply(model.reset(.playback))
        kept = [:]
        #if DEBUG
        print("audio: media services were reset")
        #endif
    }

    // MARK: - Words

    static func ms(_ s: Double) -> String { "\(Int((s * 1000).rounded())) ms" }
    static func signed(_ s: Double) -> String { String(format: "%+.1f ms", s * 1000) }
}

// MARK: - The engine and its sink

/// One AVAudioEngine with its player node: rendering to the device's output (the session active), or
/// in manual rendering mode, which opens no output device (DEBUG, and every simulator build). Its
/// methods run on the output's queue; its completion handlers return buffers to the pool.
private final class SoundEngine {
    enum Sink { case device, manual }
    enum Started { case success, failure(String) }

    let manual: Bool
    private let queue: DispatchQueue
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: AudioPlayout.rate, channels: 2)!
    private let pool = BufferPool()
    private(set) var running = false

    // Manual rendering: the stand-in output's clock (engine sample 0 goes out at t0), and what has been
    // rendered. The player starts with the engine, so its timeline is the engine's.
    private var t0 = 0.0
    private var rendered: AVAudioFramePosition = 0
    private var renderTimer: DispatchSourceTimer?
    private var renderBuffer: AVAudioPCMBuffer?
    /// The player's own output (the left channel) and the sample it starts at, from a tap on it: the
    /// click finder's, and unaffected by the player's volume, which the mixer applies after it. On `queue`.
    var onRendered: (([Float], AVAudioFramePosition) -> Void)?
    static let standInIO = 0.005
    static let standInOutput = 0.010

    init(manual: Bool, queue: DispatchQueue) {
        self.manual = manual
        self.queue = queue
    }

    /// Which sink: the simulator never opens an output unless a DEBUG build asks (`-SillSoundSink
    /// device`); a device opens it unless a DEBUG build asks for `manual`.
    static var sinkFromLaunchArguments: Sink {
        #if DEBUG
        switch UserDefaults.standard.string(forKey: "SillSoundSink") {
        case "manual"?: return .manual
        case "device"?: return .device
        default: break
        }
        #endif
        #if targetEnvironment(simulator)
        return .manual
        #else
        return .device
        #endif
    }

    func start() -> Started {
        engine.attach(player)
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: "SillSoundVolume"), let v = Float(raw) { player.volume = v }
        #endif
        if manual {
            do {
                try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
            } catch {
                return .failure("manual rendering: \(error.localizedDescription)")
            }
            engine.connect(player, to: engine.mainMixerNode, format: format)
            #if DEBUG
            player.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, when in
                guard let self, let ch = buffer.floatChannelData, when.isSampleTimeValid else { return }
                let samples = Array(UnsafeBufferPointer(start: ch[0], count: Int(buffer.frameLength)))
                let from = when.sampleTime
                self.queue.async { self.onRendered?(samples, from) }
            }
            #endif
            do { try engine.start() } catch { return .failure("the engine: \(error.localizedDescription)") }
            renderBuffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)
            player.play()
            t0 = CACurrentMediaTime() + Self.standInIO
            rendered = 0
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now(), repeating: 0.005, leeway: .microseconds(500))
            t.setEventHandler { [weak self] in self?.render() }
            t.resume()
            renderTimer = t
            running = true
            return .success
        }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try? session.setPreferredSampleRate(AudioPlayout.rate)
            try? session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)
        } catch {
            return .failure("the audio session: \(error.localizedDescription)")
        }
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            return .failure("the engine: \(error.localizedDescription)")
        }
        player.play()
        running = true
        return .success
    }

    /// The player down at once (the mixer applies it at its next render), before a stop.
    func turnDown() { player.volume = 0 }

    /// Stops the player and the engine; the output lets the session go.
    func stop() {
        renderTimer?.cancel()
        renderTimer = nil
        guard running else { return }
        running = false
        #if DEBUG
        if manual { player.removeTap(onBus: 0) }
        #endif
        player.stop()
        engine.stop()
    }

    /// The media services went away: nothing of this engine may be touched again.
    func abandon() {
        renderTimer?.cancel()
        renderTimer = nil
        running = false
    }

    /// The player's timeline: a sample of it and the device time it goes out at.
    func reading() -> (Double, Double)? {
        guard running else { return nil }
        if manual {
            // The next sample to render goes out at t0 + its place ÷ rate.
            return (Double(rendered), t0 + Double(rendered) / AudioPlayout.rate)
        }
        guard let node = player.lastRenderTime, node.isSampleTimeValid, node.isHostTimeValid,
              let playerTime = player.playerTime(forNodeTime: node), playerTime.isSampleTimeValid else { return nil }
        return (Double(playerTime.sampleTime), AVAudioTime.seconds(forHostTime: node.hostTime))
    }

    /// The output latency as the model takes it: the session's, or the player's presentation latency
    /// downstream if more. That one includes the output's own presentation latency (AVAudioNode.h),
    /// which is what the session reports: added to it, it counted the device twice.
    var outputLatency: Double {
        manual ? Self.standInOutput : max(AVAudioSession.sharedInstance().outputLatency, player.outputPresentationLatency)
    }

    var ioBuffer: Double { manual ? Self.standInIO : AVAudioSession.sharedInstance().ioBufferDuration }

    var routeName: String {
        manual ? "manual rendering (no output device)" : AVAudioSession.sharedInstance().currentRoute.outputs.first?.portName ?? "no output"
    }

    func schedule(left: [Float], right: [Float], at: Double?) {
        guard running, let buffer = pool.take(format: format, frames: left.count) else { return }
        let n = min(left.count, right.count, Int(buffer.frameCapacity))
        if let ch = buffer.floatChannelData, n > 0 {
            left.withUnsafeBufferPointer { ch[0].update(from: $0.baseAddress!, count: n) }
            right.withUnsafeBufferPointer { ch[1].update(from: $0.baseAddress!, count: n) }
        }
        buffer.frameLength = AVAudioFrameCount(n)
        let when = at.map { AVAudioTime(sampleTime: AVAudioFramePosition($0.rounded()), atRate: AudioPlayout.rate) }
        let pool = self.pool
        player.scheduleBuffer(buffer, at: when, options: []) { pool.give(buffer) }
    }

    /// Manual rendering: what a real output would have pulled by now, the stand-in IO buffer ahead.
    private func render() {
        guard running, let buffer = renderBuffer else { return }
        let target = AVAudioFramePosition(((CACurrentMediaTime() + Self.standInIO - t0) * AudioPlayout.rate).rounded(.down))
        while rendered < target {
            let n = AVAudioFrameCount(min(target - rendered, AVAudioFramePosition(buffer.frameCapacity)))
            guard (try? engine.renderOffline(n, to: buffer)) == .success else { return }
            rendered += AVAudioFramePosition(n)
        }
    }

    /// When an engine sample goes out (manual rendering).
    func outTime(ofEngineSample e: AVAudioFramePosition) -> Double { t0 + Double(e) / AudioPlayout.rate }
}

/// AVAudioPCMBuffers of the player's format, a packet and a frame long (a frame gained fits), 32 to
/// start and more when all are out (the guard has no bound, and a picture a second late holds a
/// hundred in the player). Returned by the player's completion handlers, on an AVFAudio queue.
private final class BufferPool {
    private let lock = NSLock()
    private var free: [AVAudioPCMBuffer] = []
    static let capacity: AVAudioFrameCount = 1024

    init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: AudioPlayout.rate, channels: 2)!
        free = (0..<32).compactMap { _ in AVAudioPCMBuffer(pcmFormat: format, frameCapacity: Self.capacity) }
    }

    func take(format: AVAudioFormat, frames: Int) -> AVAudioPCMBuffer? {
        lock.lock()
        if let b = free.popLast(), b.frameCapacity >= AVAudioFrameCount(frames) { lock.unlock(); return b }
        lock.unlock()
        return AVAudioPCMBuffer(pcmFormat: format, frameCapacity: max(Self.capacity, AVAudioFrameCount(frames)))
    }

    func give(_ b: AVAudioPCMBuffer) {
        lock.lock()
        free.append(b)
        lock.unlock()
    }
}

#if DEBUG
// MARK: - The test tone's clicks (DEBUG)

/// Where each click of a synthetic host's test tone (a 4 ms 2 kHz burst at each whole second of the
/// stamps' clock, Sources/SillHost/TestTone.swift) was heard, from what the manual rendering produced:
/// the console's "audio: click …" lines, the simulator gate's measure (docs/audio-plan.md S2).
private struct ClickFinder {
    /// The parts scheduled lately: where on the player's timeline, how long, and the stamp of their
    /// first frame (for a sample's stamp).
    private var parts: [(start: Double, frames: Int, stamp: Double)] = []
    /// The rendered left channel and the engine sample it starts at (the last 2 s).
    private var history: [Float] = []
    private var historyStart: AVAudioFramePosition = 0
    private var checked = Set<Int>()
    private static let click: [Float] = {
        let rate = AudioPlayout.rate, n = Int((0.004 * rate).rounded())
        return (0..<n).map { i in
            let x = Double(i)
            return Float(pow(10, -6.0 / 20) * (0.5 - 0.5 * cos(2 * .pi * x / Double(n))) * sin(2 * .pi * 2000 * x / rate))
        }
    }()

    mutating func scheduled(start: Double, frames: Int, stamp: Double) {
        parts.append((start, frames, stamp))
        if parts.count > 400 { parts.removeFirst(parts.count - 400) }
    }

    mutating func rendered(_ samples: [Float], from: AVAudioFramePosition, engine: SoundEngine, model: AudioPlayout?) {
        if history.isEmpty { historyStart = from }
        history += samples
        let keep = Int(2 * AudioPlayout.rate)
        if history.count > keep {
            let drop = history.count - keep
            history.removeFirst(drop)
            historyStart += AVAudioFramePosition(drop)
        }
        let end = historyStart + AVAudioFramePosition(history.count)
        let window = Int(0.020 * AudioPlayout.rate)
        for p in parts {
            // Each whole second of the stamps this part carries.
            let first = Int(p.stamp.rounded(.up)), last = p.stamp + Double(p.frames) / AudioPlayout.rate
            guard Double(first) < last, !checked.contains(first) else { continue }
            let expected = p.start + (Double(first) - p.stamp) * AudioPlayout.rate
            let lo = AVAudioFramePosition(expected) - AVAudioFramePosition(window)
            let hi = AVAudioFramePosition(expected) + AVAudioFramePosition(window) + AVAudioFramePosition(Self.click.count)
            guard lo >= historyStart, hi <= end else { continue }
            checked.insert(first)
            var best = -Double.infinity, at = 0
            for lag in -window...window {
                let base = Int(AVAudioFramePosition(expected) + AVAudioFramePosition(lag) - historyStart)
                var acc = 0.0
                for j in 0..<Self.click.count { acc += Double(Self.click[j]) * Double(history[base + j]) }
                if acc > best { best = acc; at = lag }
            }
            let energy = Self.click.reduce(0.0) { $0 + Double($1) * Double($1) }
            guard best > 0.3 * energy else {
                print("audio: click :\(String(format: "%02d", first % 60)) not found near its place (volume 0?)")
                continue
            }
            let heardSample = AVAudioFramePosition(expected) + AVAudioFramePosition(at)
            let ear = engine.outTime(ofEngineSample: heardSample) + SoundEngine.standInOutput
            var due = ""
            if let m = model, let floor = m.floor {
                let now = CACurrentMediaTime()
                let d = Double(first) + floor + m.delay(now: now, lag: m.pictureLag(now: now))
                due = ", \(AudioOutput.signed(ear - d)) from due now"
            }
            print("audio: click :\(String(format: "%02d", first % 60)) heard \(AudioOutput.signed(Double(at) / AudioPlayout.rate)) from where it was placed\(due)")
        }
        if checked.count > 200 { checked = Set(checked.sorted().suffix(100)) }
    }
}
#endif
