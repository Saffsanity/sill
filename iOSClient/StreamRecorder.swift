import AVFoundation
import CoreMedia
import SwiftUI

/// The stream recorded on this device (#284): the HEVC frames it receives written as they came, never
/// re-encoded, into a QuickTime movie in Files › On My iPhone (iPad) › Sill › Sill Recordings, with the
/// Mac's sound when asked (the decoded sound encoded to AAC, which plays everywhere, as AAC-ELD may
/// not). Each movie starts at a keyframe; a new size (a rotation, an Aa step, another window) closes it,
/// and the next starts at the keyframe that follows. On its own queue; the frames' and the sound's
/// callers hand over and return.
final class StreamRecorder: @unchecked Sendable {
    static var folder: URL {
        URL.documentsDirectory.appending(path: "Sill Recordings", directoryHint: .isDirectory)
    }

    let withSound: Bool
    /// The movies written so far, finished or not.
    private(set) var files: [URL] = []
    private let queue = DispatchQueue(label: "sill.recorder", qos: .userInitiated)
    private var writer: AVAssetWriter?
    private var video: AVAssetWriterInput?
    private var audio: AVAssetWriterInput?
    private var format: CMFormatDescription?
    private var started: CMTime?
    private var lastVideo = CMTime.zero
    private var stopped = false
    private let soundFormat: CMAudioFormatDescription?

    init(withSound: Bool) {
        self.withSound = withSound
        var asbd = AudioStreamBasicDescription(mSampleRate: AudioDecoder.sampleRate, mFormatID: kAudioFormatLinearPCM,
                                               mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                                               mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8,
                                               mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        var made: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0,
                                       magicCookie: nil, extensions: nil, formatDescriptionOut: &made)
        soundFormat = made
    }

    private static var now: CMTime { CMClockGetTime(CMClockGetHostTimeClock()) }

    /// A frame as the display layer gets it (its format the stream's parameter sets).
    func frame(_ sample: CMSampleBuffer, isKeyframe: Bool) {
        queue.async { [self] in
            guard !stopped, let fmt = CMSampleBufferGetFormatDescription(sample) else { return }
            if let format, !CMFormatDescriptionEqual(format, otherFormatDescription: fmt) { finish(then: nil) }
            if writer == nil {
                guard isKeyframe, open(fmt) else { return }
            }
            guard let video, video.isReadyForMoreMediaData, let started else { return }
            var at = CMTimeSubtract(Self.now, started)
            if at <= lastVideo { at = CMTimeAdd(lastVideo, CMTime(value: 1, timescale: 600)) }
            lastVideo = at
            var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: at, decodeTimeStamp: .invalid)
            var copy: CMSampleBuffer?
            guard CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: sample, sampleTimingEntryCount: 1,
                                                        sampleTimingArray: &timing, sampleBufferOut: &copy) == noErr, let copy else { return }
            video.append(copy)
        }
    }

    /// The Mac's sound as this device plays it, 48 kHz stereo.
    func sound(left: [Float], right: [Float]) {
        guard withSound else { return }
        queue.async { [self] in
            guard !stopped, let audio, audio.isReadyForMoreMediaData, let started, let soundFormat else { return }
            let frames = min(left.count, right.count)
            guard frames > 0 else { return }
            var interleaved = [Float](repeating: 0, count: frames * 2)
            for i in 0..<frames { interleaved[2 * i] = left[i]; interleaved[2 * i + 1] = right[i] }
            let bytes = interleaved.count * MemoryLayout<Float>.size
            var block: CMBlockBuffer?
            guard CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil,
                                                     customBlockSource: nil, offsetToData: 0, dataLength: bytes, flags: 0,
                                                     blockBufferOut: &block) == noErr, let block,
                  interleaved.withUnsafeBytes({ CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block,
                                                                             offsetIntoDestination: 0, dataLength: bytes) }) == noErr
            else { return }
            var sample: CMSampleBuffer?
            guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block, formatDescription: soundFormat,
                                                                      sampleCount: frames, presentationTimeStamp: CMTimeSubtract(Self.now, started),
                                                                      packetDescriptions: nil, sampleBufferOut: &sample) == noErr,
                  let sample else { return }
            audio.append(sample)
        }
    }

    /// Finishes the movie; `done` gets every movie written, on the main queue.
    func stop(done: @escaping ([URL]) -> Void) {
        queue.async { [self] in
            stopped = true
            finish { [files] in DispatchQueue.main.async { done(files) } }
        }
    }

    private func open(_ fmt: CMFormatDescription) -> Bool {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let names = DateFormatter()
        names.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"     // this device's own clock, as Screenshots name theirs
        let stamp = names.string(from: Date())
        let url = Self.folder.appending(path: "Sill \(stamp)\(files.isEmpty ? "" : " \(files.count + 1)").mov")
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return false }
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: fmt)
        video.expectsMediaDataInRealTime = true
        guard writer.canAdd(video) else { return false }
        writer.add(video)
        var audio: AVAssetWriterInput?
        if withSound {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                                                                              AVSampleRateKey: AudioDecoder.sampleRate,
                                                                              AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 160_000])
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) { writer.add(input); audio = input }
        }
        guard writer.startWriting() else { return false }
        writer.startSession(atSourceTime: .zero)
        self.writer = writer; self.video = video; self.audio = audio
        format = fmt; started = Self.now; lastVideo = .zero
        files.append(url)
        return true
    }

    /// On `queue`: the movie closed (nothing to close: `then` at once).
    private func finish(then: (() -> Void)?) {
        guard let writer else { then?(); return }
        video?.markAsFinished(); audio?.markAsFinished()
        self.writer = nil; video = nil; audio = nil; format = nil; started = nil
        writer.finishWriting { then?() }
    }
}

extension StreamClient {
    /// Settings' Start Recording: a 3, 2, 1 count, then the recording, from a keyframe the Mac is asked
    /// for. With the sound only while the Mac sends it. Main thread.
    func startRecording(withSound: Bool) {
        guard connected, recorder == nil, recordingCount == nil else { return }
        recordingCount = 3
        func tick() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, let n = self.recordingCount else { return }
                guard n > 1 else { self.recordingCount = nil; self.beginRecording(withSound: withSound); return }
                self.recordingCount = n - 1
                tick()
            }
        }
        tick()
    }

    private func beginRecording(withSound: Bool) {
        guard connected else { return }
        let rec = StreamRecorder(withSound: withSound && settings.displayed?.sendAudio == true)
        recorder = rec
        recordingSince = Date()
        let view = displayView, sound = self.sound
        queue.async { view.recorder = rec }
        sound.queue.async { sound.recorder = rec }
        send(.keyframeRequest, payload: Data())
        // Sill to the background: the movie is finished there, before iOS suspends it.
        recordingBackground = NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                                                     object: nil, queue: .main) { [weak self] _ in self?.stopRecording() }
        UIAccessibility.post(notification: .announcement, argument: "Recording")
    }

    /// Settings' Stop Recording, the session's end, Sill to the background; also a count not yet run out.
    func stopRecording() {
        recordingCount = nil
        guard let rec = recorder else { return }
        recorder = nil
        recordingSince = nil
        if let token = recordingBackground { NotificationCenter.default.removeObserver(token); recordingBackground = nil }
        let view = displayView, sound = self.sound
        queue.async { view.recorder = nil }
        sound.queue.async { sound.recorder = nil }
        let background = UIApplication.shared.beginBackgroundTask(withName: "Finish the recording")
        rec.stop { [weak self] files in
            let words = files.isEmpty ? "Nothing was recorded." : "Saved to Files › Sill Recordings."
            self?.showClipboardNote(words, spoken: words, warning: files.isEmpty)
            UIApplication.shared.endBackgroundTask(background)
        }
    }
}

/// Over the picture: the count before a recording, then its light with the time it has run.
struct RecordingBadge: View {
    @ObservedObject var client: StreamClient

    var body: some View {
        if let n = client.recordingCount {
            Text("\(n)")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(radius: 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .accessibilityLabel("Recording in \(n)")
        } else if let since = client.recordingSince {
            TimelineView(.periodic(from: since, by: 1)) { context in
                let s = Int(context.date.timeIntervalSince(since))
                HStack(spacing: 6) {
                    Circle().fill(Color.red).frame(width: 10, height: 10)
                    Text(String(format: "%d:%02d", s / 60, s % 60)).font(.system(size: 13, weight: .semibold).monospacedDigit())
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(.black.opacity(0.55), in: Capsule())
                .foregroundStyle(.white)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Recording, \(s / 60) minutes \(s % 60) seconds")
            }
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .allowsHitTesting(false)
        }
    }
}
