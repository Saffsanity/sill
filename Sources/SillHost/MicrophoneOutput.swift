import Darwin
import Foundation

/// Where a device's microphone goes once it is decoded and timed (docs/microphone-plan.md §3.2, §5.3): the
/// seam where Sill Microphone takes it. Sill.app's feed (an AVAudioEngine whose output is Sill Microphone's
/// hidden feed device, found by its UID, never the default output) comes with Sill Microphone itself, the
/// plan's next part; until then only a test host has one, MicrophoneTestOutput. With none, nothing of a
/// device's microphone is played anywhere: the Mac's speakers never play it.
///
/// Everything here is called on the receiver's queue `sill.mic`, but `onReady` and `onApp`, which the output
/// calls on that queue too.
protocol MicrophoneOutput: AnyObject {
    /// Sill Microphone is set up, and an app reads from it, now; `onReady` and `onApp` say every change.
    var ready: Bool { get }
    var appUses: Bool { get }
    var onReady: ((Bool) -> Void)? { get set }
    var onApp: ((Bool) -> Void)? { get set }
    /// Starts watching Sill Microphone (its setup, the apps that read it).
    func watch()
    /// Starts the player's timeline; false when it cannot (no feed). Then `reading` gives its place.
    func start() -> Bool
    /// Stops it, once what was scheduled has played out (the receiver waits for the playout's tail).
    func stop()
    var running: Bool { get }
    /// The timeline: a sample of it and the host time it goes out at (seconds of the host clock,
    /// `MicrophoneClock.now`), nil before the first render after a start.
    func reading() -> (sample: Double, time: Double)?
    /// The IO buffer and the output latency, for the playout's need.
    var ioBuffer: Double { get }
    var outputLatency: Double { get }
    /// 48 kHz mono 32-bit float: at timeline sample `at`, or right after what was scheduled last (nil).
    func schedule(_ samples: [Float], at: Double?)
}

/// The host clock the microphone's playout and its output read: seconds of mach_absolute_time, the clock
/// AVAudioTime's host time counts (CACurrentMediaTime's), never set back.
enum MicrophoneClock {
    private static let scale: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()
    static func now() -> Double { Double(mach_absolute_time()) * scale }
}

/// TEST ONLY (MicrophoneTestHook, `SILL_TEST_MIC_SINK`): a test host's Sill Microphone. It reads its setup and
/// its apps from the hook's files once a second, and stands in for the feed's output: a timeline that renders
/// as a real one would (sample n goes out at t0 + n ÷ 48,000, rendered `ioBuffer` ahead), counting what it
/// renders (`mic.dry`, and `mic.dryLate` for frames scheduled after their place went out) and, with
/// `file:PATH`, writing it to a WAV, silence where nothing was scheduled. Once started its timeline runs until
/// the host quits, so the file is one continuous recording whose sample 0's wall-clock time is printed once.
/// Opens no audio device, plays nothing.
final class MicrophoneTestOutput: MicrophoneOutput {
    private let hook: MicrophoneTestHook.Hook
    private let queue: DispatchQueue
    private(set) var ready = true
    private(set) var appUses = true
    var onReady: ((Bool) -> Void)?
    var onApp: ((Bool) -> Void)?
    private(set) var running = false
    let ioBuffer = 0.010
    let outputLatency = 0.0
    private var watchTimer: DispatchSourceTimer?
    private var renderTimer: DispatchSourceTimer?
    /// Sample 0 goes out at `t0` (host clock); `rendered` samples have gone out.
    private var t0: Double?
    private var rendered = 0
    /// What is scheduled from `rendered` on.
    private var pending: [Float] = []
    private var lastEnd: Int?
    private var file: FileHandle?
    private var written = 0
    private var headerAt = 0.0

    init(hook: MicrophoneTestHook.Hook, queue: DispatchQueue) {
        self.hook = hook
        self.queue = queue
        ready = Self.setUp(hook)
        appUses = Self.apps(hook)
    }

    deinit {
        watchTimer?.cancel()
        renderTimer?.cancel()
        try? file?.close()
    }

    private static func read(_ path: String?) -> String? {
        guard let path else { return nil }
        return try? String(contentsOfFile: path, encoding: .utf8)
    }
    private static func setUp(_ hook: MicrophoneTestHook.Hook) -> Bool {
        hook.setupFile == nil || MicrophoneTestHook.setUp(read(hook.setupFile))
    }
    private static func apps(_ hook: MicrophoneTestHook.Hook) -> Bool {
        hook.appFile == nil || MicrophoneTestHook.appUses(read(hook.appFile))
    }

    func watch() {
        guard watchTimer == nil, hook.appFile != nil || hook.setupFile != nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 0.25, repeating: 0.25, leeway: .milliseconds(50))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let r = Self.setUp(self.hook), a = Self.apps(self.hook)
            if r != self.ready { self.ready = r; self.onReady?(r) }
            if a != self.appUses { self.appUses = a; self.onApp?(a) }
        }
        t.resume()
        watchTimer = t
    }

    func start() -> Bool {
        running = true
        guard t0 == nil else { return true }
        let now = MicrophoneClock.now()
        t0 = now + ioBuffer
        if case .file(let path) = hook.sink {
            FileManager.default.createFile(atPath: path, contents: MicrophoneTestHook.wavHeader(frames: 0))
            file = FileHandle(forWritingAtPath: path)
            _ = try? file?.seekToEnd()
            let wall = Date().timeIntervalSince1970 + (t0! - now)
            print("Test microphone: the file's sample 0 is at \(String(format: "%.6f", wall)) (wall clock), 48 kHz mono float: \(path)")
        }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: 0.005, leeway: .microseconds(500))
        t.setEventHandler { [weak self] in self?.render() }
        t.resume()
        renderTimer = t
        return true
    }

    func stop() { running = false }

    func reading() -> (sample: Double, time: Double)? {
        guard let t0 else { return nil }
        return (Double(rendered), t0 + Double(rendered) / 48_000)
    }

    func schedule(_ samples: [Float], at: Double?) {
        guard t0 != nil, !samples.isEmpty else { return }
        let start = at.map { Int($0.rounded()) } ?? lastEnd ?? rendered
        lastEnd = start + samples.count
        Stats.shared.bump("mic.dry", by: samples.count)
        var from = 0
        if start < rendered {
            from = min(samples.count, rendered - start)
            Stats.shared.bump("mic.dryLate", by: from)
        }
        let offset = max(0, start - rendered)
        if pending.count < offset + samples.count - from {
            pending.append(contentsOf: repeatElement(0, count: offset + samples.count - from - pending.count))
        }
        for i in from..<samples.count { pending[offset + i - from] = samples[i] }
    }

    /// What a real output would have pulled by now, `ioBuffer` ahead.
    private func render() {
        guard let t0 else { return }
        let target = Int(((MicrophoneClock.now() + ioBuffer - t0) * 48_000).rounded(.down))
        guard target > rendered else { return }
        let n = target - rendered
        var out = [Float](repeating: 0, count: n)
        let take = min(n, pending.count)
        if take > 0 {
            out.replaceSubrange(0..<take, with: pending[0..<take])
            pending.removeFirst(take)
        }
        rendered = target
        guard let file else { return }
        out.withUnsafeBufferPointer { p in
            file.write(Data(bytes: p.baseAddress!, count: n * 4))   // Float32, little endian on every Mac Sill runs on
        }
        written += n
        // The header's sizes, at most once a second: a host killed mid-run leaves a file that reads to then.
        let now = MicrophoneClock.now()
        if now - headerAt >= 1 {
            headerAt = now
            try? file.seek(toOffset: 0)
            file.write(MicrophoneTestHook.wavHeader(frames: written))
            _ = try? file.seekToEnd()
        }
    }
}
