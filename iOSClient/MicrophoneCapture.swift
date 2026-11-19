import AVFAudio
import Foundation
import QuartzCore
import StreamProtocol

/// This window's microphone while it records (docs/microphone-plan.md §3.5, §5.6, §6): its buffers in, kind 48's
/// messages out, on a queue of its own, `sill.mic`. The source is the microphone, through a tap on the window's
/// sound engine in its voice mode (AudioOutput.setMicrophone: iOS's voice processing takes what this device plays,
/// the Mac's sound included, out of what it hears), or the test tone: always in the simulator, whose microphone is
/// the Mac's and is never opened, and in a DEBUG build asked with `-SillMicSource tone`. Each tap buffer is copied
/// on the tap's thread (never a real-time one: AVFAudio's tap thread) and handed here, converted to 48 kHz mono if
/// the route gives another rate (Bluetooth's call profile), and given to MicrophoneSender; the epoch's format goes
/// first, then the packets, through `onMessage`, on this queue, so they reach the session's link in that order.
///
/// Threads: `tap` on AVFAudio's tap thread (a copy and a hop, nothing else); everything else on `queue`; `format`
/// under its lock from any thread.
final class MicrophoneCapture {
    enum Source: Equatable { case microphone, tone }
    /// What the capture sends: a type 1 (the epoch's format) or a type 2.
    enum Kind { case format, packets }

    /// The source this process records from: the tone in the simulator and when a DEBUG build asks; else the
    /// microphone.
    static let source: Source = {
        #if targetEnvironment(simulator)
        return .tone
        #else
        #if DEBUG
        if UserDefaults.standard.string(forKey: "SillMicSource") == "tone" { return .tone }
        #endif
        return .microphone
        #endif
    }()

    let queue = DispatchQueue(label: "sill.mic", qos: .userInteractive)
    private let sender = MicrophoneSender(lastEpoch: Int.random(in: 0...65_535))
    /// Each message, on `queue`, in order: the session's link takes it.
    var onMessage: ((StreamMessage, Kind) -> Void)?
    private let formatLock = NSLock()
    private var currentFormat: MicrophoneFormat?
    // On `queue`.
    private var recording = false
    private var converter: AVAudioConverter?
    private var converterRate = 0.0
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(MicrophoneCodec.sampleRate), channels: 1, interleaved: false)!
    private var toneTimer: DispatchSourceTimer?
    private var toneHost = 0.0
    private var toneFrame = 0
    #if DEBUG
    private var bufferSaid: (frames: Int, rate: Double)?
    #endif

    /// The recording's epoch's format, for an offer on a move's new connection. Any thread.
    var format: MicrophoneFormat? { formatLock.withLock { currentFormat } }

    /// The tap's block, which AudioOutput installs on its voice engine's input node: a copy of the buffer's
    /// first channel and its time, handed to `queue`.
    var tap: (AVAudioPCMBuffer, AVAudioTime) -> Void {
        { [weak self] buffer, when in
            guard let self, let ch = buffer.floatChannelData, buffer.frameLength > 0 else { return }
            let n = Int(buffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: ch[0], count: n))
            let rate = buffer.format.sampleRate
            let host = when.isHostTimeValid ? AVAudioTime.seconds(forHostTime: when.hostTime) : CACurrentMediaTime() - Double(n) / max(rate, 1)
            self.queue.async { self.take(samples, rate: rate, hostTime: host) }
        }
    }

    /// A recording starts: a new epoch, whose format goes at once, then its packets as the buffers come.
    func start() { queue.async { [self] in begin() } }

    /// It stops: nothing more is sent, the encoder's state goes.
    func stop() { queue.async { [self] in end() } }

    private func begin() {
        guard !recording else { return }
        guard let f = sender.start() else {
            print("mic: no encoder: \(sender.failure ?? "?")")
            return
        }
        recording = true
        formatLock.withLock { currentFormat = f }
        if let m = MicrophoneMessage.message(.format(f), now: Date().timeIntervalSince1970) { onMessage?(m, .format) }
        #if DEBUG
        print("mic: on (aac-eld \((f.format.bitrate ?? 0) / 1000) kbps, epoch \(f.format.epoch ?? -1), \(Self.source == .tone ? "the test tone" : "the microphone"))")
        bufferSaid = nil
        #endif
        if Self.source == .tone { startTone() }
    }

    private func end() {
        guard recording else { return }
        recording = false
        toneTimer?.cancel()
        toneTimer = nil
        sender.stop()
        converter = nil
        formatLock.withLock { currentFormat = nil }
    }

    /// One buffer, mono at `rate`, from host time `hostTime`: at 48 kHz as it is, else through a converter kept
    /// across buffers (its state carries between them).
    private func take(_ samples: [Float], rate: Double, hostTime: Double) {
        guard recording, rate > 0 else { return }
        #if DEBUG
        if bufferSaid?.frames != samples.count || bufferSaid?.rate != rate {
            bufferSaid = (samples.count, rate)
            print("mic: tap \(samples.count) frames at \(Int(rate)) Hz")
        }
        #endif
        var mono = samples
        if rate != Double(MicrophoneCodec.sampleRate) {
            guard let converted = convert(samples, rate: rate) else { return }
            mono = converted
        }
        let wallOffset = Date().timeIntervalSince1970 - CACurrentMediaTime()
        for m in sender.push(mono, hostTime: hostTime, wallOffset: wallOffset) { onMessage?(m, .packets) }
    }

    private func convert(_ samples: [Float], rate: Double) -> [Float]? {
        if converter == nil || converterRate != rate {
            guard let from = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: 1, interleaved: false) else { return nil }
            converter = AVAudioConverter(from: from, to: target)
            converterRate = rate
        }
        guard let converter, let input = AVAudioPCMBuffer(pcmFormat: converter.inputFormat, frameCapacity: AVAudioFrameCount(samples.count)) else { return nil }
        input.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { input.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        let capacity = AVAudioFrameCount((Double(samples.count) * target.sampleRate / rate).rounded(.up)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var given = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if given { outStatus.pointee = .noDataNow; return nil }
            given = true
            outStatus.pointee = .haveData
            return input
        }
        guard status != .error, let ch = output.floatChannelData, output.frameLength > 0 else { return nil }
        return Array(UnsafeBufferPointer(start: ch[0], count: Int(output.frameLength)))
    }

    // MARK: The test tone (the simulator, and DEBUG's -SillMicSource tone)

    /// A capture buffer's 100 ms at a time, as the tap gives them, generated as the clock goes: 440 Hz at
    /// −30 dBFS and a 4 ms 2 kHz click at −6 dBFS on each whole second of the wall clock, as the host's test tone
    /// is (Sources/SillHost/TestTone.swift), so a test host's file sink shows each click at its stamp.
    private func startTone() {
        toneHost = CACurrentMediaTime()
        toneFrame = 0
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 0.1, repeating: 0.1, leeway: .milliseconds(2))
        t.setEventHandler { [weak self] in self?.toneTick() }
        t.resume()
        toneTimer = t
    }

    private func toneTick() {
        let chunk = 4_800
        let now = CACurrentMediaTime()
        let wallOffset = Date().timeIntervalSince1970 - now
        while recording, toneHost + Double(toneFrame + chunk) / 48_000 <= now {
            let start = toneHost + Double(toneFrame) / 48_000
            let samples = Self.tone(frames: chunk, wallStart: start + wallOffset)
            toneFrame += chunk
            for m in sender.push(samples, hostTime: start, wallOffset: wallOffset) { onMessage?(m, .packets) }
        }
    }

    /// `frames` of the tone from wall-clock time `wallStart`.
    static func tone(frames: Int, wallStart: Double) -> [Float] {
        let rate = 48_000.0
        let tone = pow(10, -30.0 / 20), click = pow(10, -6.0 / 20)
        let clickFrames = 0.004 * rate
        var out = [Float](repeating: 0, count: frames)
        for i in 0..<frames {
            let wall = wallStart + Double(i) / rate
            let within = wall - wall.rounded(.down)
            var v = tone * sin(2 * .pi * 440 * within)
            let into = within * rate
            if into < clickFrames {
                v += click * (0.5 - 0.5 * cos(2 * .pi * into / clickFrames)) * sin(2 * .pi * 2_000 * into / rate)
            }
            out[i] = Float(v)
        }
        return out
    }
}
