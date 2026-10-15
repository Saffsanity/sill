import Foundation
import CoreMedia
import ScreenCaptureKit

/// The Mac's sound from ScreenCaptureKit (docs/audio-plan.md §4.2): a second, audio-only SCStream, so
/// the picture's restarts (a resize, a rotation, an Aa step, a rate or quality change, the encoder
/// fallback) never touch the sound, and a failure of the sound ends only the sound. ScreenCaptureKit
/// filters sound per application (WWDC22 sessions 10155 and 10156): the filter is the streamed
/// window's app, or every app but Sill's for the Desktop, made by the coordinator and never changed
/// on a running stream (another app is another stream). No permission beyond Screen Recording.
///
/// The stream's picture, which ScreenCaptureKit always makes, is 2×2 at one frame a second and thrown
/// away as it comes (without a screen output ScreenCaptureKit logs every frame it drops). Sill's own
/// sound never goes out (`excludesCurrentProcessAudio`). Each buffer's layout is read from its own
/// description, never assumed (`PCMLayout`), and becomes interleaved stereo for the pipeline; its
/// time stamp is on the host clock, as the picture's frames are. Starting and stopping are bounded (2
/// s each), as every other ScreenCaptureKit call of the host is.
///
/// Not run by any test here: the tests never capture a person's sound (the test tone, SyntheticAudio,
/// stands in for it). The device tests P1–P16 are Noah's.
final class AudioCapture: NSObject, AudioSource, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    var onPCM: ((PCMChunk) -> Void)?
    var onStopped: ((String) -> Void)?

    struct Failure: AudioSourceFailure {
        let description: String
    }

    private let filter: SCContentFilter
    /// The pipeline's `sill.audio`: the buffers, and the thrown-away picture.
    private let queue: DispatchQueue
    /// Main actor (start, stop); read by the delegate to tell a replaced stream's stop from this one's.
    private var stream: SCStream?
    // On `queue`.
    private var firstLogged = false
    private var tally = AudioBufferTally()
    private var tallyStart: Double?
    private var tallyDone = false
    private var clockWarned = false
    private var layoutWarned = false

    static let startStopTimeout: TimeInterval = 2

    init(filter: SCContentFilter, queue: DispatchQueue) {
        self.filter = filter
        self.queue = queue
    }

    func start() async throws {
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        config.excludesCurrentProcessAudio = true
        // The picture ScreenCaptureKit makes anyway: as small and as rare as it takes.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.queueDepth = 3
        config.showsCursor = false
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        self.stream = stream
        do {
            try await Self.bounded("start", after: Self.startStopTimeout, { done in stream.startCapture(completionHandler: done) }) {
                // Started after all, once the start was given up on: stopped again, never left running.
                stream.stopCapture { _ in }
            }
        } catch {
            if self.stream === stream { self.stream = nil }
            throw error
        }
    }

    func stop() async {
        guard let stream else { return }
        self.stream = nil
        try? await Self.bounded("stop", after: Self.startStopTimeout, { done in stream.stopCapture(completionHandler: done) }) {}
        // stopCapture returning does not mean the handler queue has drained.
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in queue.async { c.resume() } }
    }

    /// One of SCStream's completion-handler calls, given up on after `seconds` (a failure then); `late`
    /// runs when it succeeds after that.
    private static func bounded(_ what: String, after seconds: TimeInterval,
                                _ call: @escaping (@escaping @Sendable (Error?) -> Void) -> Void,
                                late: @escaping @Sendable () -> Void) async throws {
        final class Once: @unchecked Sendable {
            private let lock = NSLock()
            private var done = false
            func first() -> Bool { lock.lock(); defer { lock.unlock() }; if done { return false }; done = true; return true }
        }
        let once = Once()
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            call { error in
                if once.first() {
                    if let error { c.resume(throwing: error) } else { c.resume() }
                } else if error == nil {
                    late()
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                if once.first() { c.resume(throwing: Failure(description: "the stream did not \(what) within \(Int(seconds)) s")) }
            }
        }
    }

    // MARK: SCStreamOutput, SCStreamDelegate (on `queue`, and ScreenCaptureKit's own queue)

    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }   // the 2×2 picture
        guard CMSampleBufferIsValid(buffer), CMSampleBufferDataIsReady(buffer),
              let description = CMSampleBufferGetFormatDescription(buffer),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else { return }
        let frames = CMSampleBufferGetNumSamples(buffer)
        guard frames > 0 else { return }
        guard let layout = PCMLayout.from(formatID: asbd.mFormatID, flags: asbd.mFormatFlags,
                                          bitsPerChannel: asbd.mBitsPerChannel, channels: asbd.mChannelsPerFrame) else {
            if !layoutWarned {
                layoutWarned = true
                print("Audio: a buffer in a layout Sill does not read (format \(asbd.mFormatID), flags \(asbd.mFormatFlags), \(asbd.mBitsPerChannel) bits, \(asbd.mChannelsPerFrame) channels); it is skipped.")
            }
            return
        }
        guard let samples = Self.stereo(buffer, frames: frames, layout: layout) else { return }
        let rate = asbd.mSampleRate
        let now = CMTimeGetSeconds(CMClockGetTime(CMClockGetHostTimeClock()))
        var time = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(buffer))
        if !time.isFinite || abs(now - time) > 1 {
            // Not on the host clock: taken as having just arrived.
            if !clockWarned {
                clockWarned = true
                print("Audio: a buffer's time stamp is not on the host clock (\(String(format: "%.3f", time)) against \(String(format: "%.3f", now))); arrival times are used instead.")
            }
            time = now - Double(frames) / rate
        }
        if !firstLogged {
            firstLogged = true
            print("Audio: first buffer \(frames) frames, \(Int(rate)) Hz, \(asbd.mChannelsPerFrame) channels, \(layout), "
                  + "\(Int(((now - time) * 1000).rounded())) ms after its time stamp.")
            tallyStart = time
        }
        if !tallyDone, let start = tallyStart {
            tally.add(frames: frames, sampleRate: rate, hostTime: time, silent: !samples.contains { $0 != 0 })
            if time - start >= 60 {
                tallyDone = true
                print(tally.line)
            }
        }
        onPCM?(PCMChunk(samples: samples, channels: 2, sampleRate: rate, hostTime: time))
    }

    /// The buffer's samples as interleaved stereo Float32, read in place (the block buffer kept alive
    /// while they are read).
    private static func stereo(_ buffer: CMSampleBuffer, frames: Int, layout: PCMLayout) -> [Float]? {
        var needed = 0
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(buffer, bufferListSizeNeededOut: &needed, bufferListOut: nil,
                                                                      bufferListSize: 0, blockBufferAllocator: nil,
                                                                      blockBufferMemoryAllocator: nil, flags: 0,
                                                                      blockBufferOut: nil) == noErr, needed > 0 else { return nil }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: needed, alignment: 16)
        defer { raw.deallocate() }
        let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        var block: CMBlockBuffer?
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(buffer, bufferListSizeNeededOut: nil, bufferListOut: list,
                                                                      bufferListSize: needed, blockBufferAllocator: nil,
                                                                      blockBufferMemoryAllocator: nil,
                                                                      flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
                                                                      blockBufferOut: &block) == noErr else { return nil }
        return withExtendedLifetime(block) {
            let buffers = UnsafeMutableAudioBufferListPointer(list).map {
                UnsafeRawBufferPointer(start: $0.mData, count: $0.mData == nil ? 0 : Int($0.mDataByteSize))
            }
            return layout.stereo(frames: frames, buffers: buffers)
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard stream === self.stream else { return }   // a stream already replaced or stopped
        self.stream = nil
        onStopped?(Self.describe(error))
    }

    /// The error's words, with ScreenCaptureKit's code for the ones the plan names (−3818 the sound
    /// failing to start, −3819 to stop, −3821 the system stopping the stream).
    private static func describe(_ error: Error) -> String {
        let e = error as NSError
        return "\(e.localizedDescription) (\(e.domain) \(e.code))"
    }
}
