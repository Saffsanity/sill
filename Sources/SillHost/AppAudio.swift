import AVFoundation
import os
import AudioToolbox
import CoreAudio
import Foundation
import StreamProtocol

/// The sound of the apps a Mac client shows (kind 33, SideStreamRequest.audio): one CoreAudio
/// process tap over every process of those apps, their helpers included (browsers and web-based apps
/// play from a helper process), muted on this Mac while it is tapped
/// (`mutedWhenTapped`: the sound goes to the device instead). The tap is read through a private
/// aggregate device; each ~10 ms of it goes out as 16-bit PCM (AudioPacket). The first tap asks for
/// the audio recording permission (NSAudioCaptureUsageDescription). Everything runs on its own
/// queue: CoreAudio's calls wait on coreaudiod, and on that permission's prompt for as long as it is
/// up (on the main actor that froze the host, 2026-10-12). `set` and `stop` return at once.
@available(macOS 14.2, *)
final class AppAudio: @unchecked Sendable {
    /// About 10 ms of sound, packed (AudioPacket), on the IO queue: plain while `plain` (a device asked
    /// for PCM), and compressed (AAC-ELD, `packEncoded`) while `encoded` (a device asked for that).
    var onPacket: ((Data) -> Void)?
    var onEncoded: ((Data) -> Void)?
    private let wants = OSAllocatedUnfairLock(initialState: (plain: true, encoded: false))
    /// Which forms the listening devices asked for. Any thread.
    func set(plain: Bool, encoded: Bool) { wants.withLock { $0 = (plain, encoded) } }

    private var apps: Set<String> = []
    private var tapped: [AudioObjectID] = []
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var poll: DispatchSourceTimer?
    private let ioQueue = DispatchQueue(label: "sill.audio", qos: .userInteractive)
    private let control = DispatchQueue(label: "sill.audio.control", qos: .userInitiated)

    /// The apps (bundle IDs) whose sound goes to the device; empty stops the tap, and their sound
    /// comes back on this Mac. Any thread; returns at once.
    func set(apps: Set<String>) {
        control.async { [self] in
            guard apps != self.apps else { return }
            self.apps = apps
            refresh()
            poll?.cancel()
            poll = nil
            if !apps.isEmpty {
                // An app starts a helper when it starts playing (a tab's video): looked for every second.
                let t = DispatchSource.makeTimerSource(queue: control)
                t.schedule(deadline: .now() + 1, repeating: 1)
                t.setEventHandler { [weak self] in self?.refresh() }
                t.resume()
                poll = t
            }
        }
    }

    /// The tap gone and the apps' sound back on this Mac, before returning (Sill quitting): at most
    /// a second, so a stuck coreaudiod never holds the quit.
    func stop() {
        let done = DispatchSemaphore(value: 0)
        control.async { [self] in
            apps = []
            poll?.cancel(); poll = nil
            teardown()
            done.signal()
        }
        _ = done.wait(timeout: .now() + 1)
    }

    private func refresh() {
        let wanted = apps.isEmpty ? [] : Self.processes(of: apps)
        guard wanted != tapped else { return }
        teardown()
        tapped = wanted
        guard !wanted.isEmpty else { return }
        do {
            try start(wanted)
            print("Audio: \(wanted.count) process\(wanted.count == 1 ? "" : "es") (\(wanted.map { Self.string($0, kAudioProcessPropertyBundleID) ?? "?" }.joined(separator: ", "))) of \(apps.sorted().joined(separator: ", ")) tapped, muted here and sent to the device")
        } catch {
            print("Audio: could not tap \(apps.sorted().joined(separator: ", ")) (\(error)); their sound stays on this Mac")
            teardown()
            tapped = wanted   // not again until the processes change
        }
    }

    // MARK: CoreAudio

    struct Failure: Error, CustomStringConvertible {
        let step: String, status: OSStatus
        var description: String { "\(step): \(status)" }
    }

    private func start(_ processes: [AudioObjectID]) throws {
        let desc = CATapDescription(stereoMixdownOfProcesses: processes)
        desc.name = "Sill"
        desc.muteBehavior = .mutedWhenTapped
        desc.isPrivate = true
        var tap = AudioObjectID(kAudioObjectUnknown)
        var err = AudioHardwareCreateProcessTap(desc, &tap)
        guard err == noErr else { throw Failure(step: "create tap", status: err) }
        tapID = tap

        let output = try Self.defaultOutputUID()
        let aggregate: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Sill",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: output,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: output]],
            kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: desc.uuid.uuidString]],
        ]
        var agg = AudioObjectID(kAudioObjectUnknown)
        err = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &agg)
        guard err == noErr else { throw Failure(step: "create aggregate device", status: err) }
        aggregateID = agg

        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        err = AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format)
        guard err == noErr else { throw Failure(step: "read the tap's format", status: err) }
        guard format.mFormatID == kAudioFormatLinearPCM, format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32
        else { throw Failure(step: "the tap's format is not 32-bit float", status: -1) }

        let packer = Packer(sampleRate: format.mSampleRate, channels: Int(max(1, min(format.mChannelsPerFrame, 8))))
        let plain = onPacket, encodedOut = onEncoded, wants = self.wants
        var encoder: AACEncoder?
        let send: (Data) -> Void = { pcm in
            let want = wants.withLock { $0 }
            if want.plain { plain?(pcm) }
            guard want.encoded, let encodedOut else { return }
            if encoder == nil { encoder = AACEncoder(sampleRate: packer.sampleRate, channels: packer.channels) }
            encoder?.encode(pcm, out: encodedOut)
        }
        var proc: AudioDeviceIOProcID?
        err = AudioDeviceCreateIOProcIDWithBlock(&proc, agg, ioQueue) { _, input, _, _, _ in
            Stats.shared.bump("audio.io")
            packer.add(UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)), send: send)
        }
        guard err == noErr, let proc else { throw Failure(step: "create the IO proc", status: err) }
        procID = proc
        err = AudioDeviceStart(agg, proc)
        guard err == noErr else { throw Failure(step: "start", status: err) }
    }

    private func teardown() {
        if let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        if aggregateID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(aggregateID) }
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        tapID = AudioObjectID(kAudioObjectUnknown)
        if !tapped.isEmpty { print(apps.isEmpty ? "Audio: tap stopped; the apps' sound is back on this Mac" : "Audio: the apps' processes changed; tapping again") }
        tapped = []
    }

    /// The audio process objects of these apps and their helpers (a bundle ID equal to one, or
    /// under it: a browser's helper), never Sill's own. Sorted, so a change is seen.
    static func processes(of apps: Set<String>) -> [AudioObjectID] {
        let own = getpid()
        return processObjects().filter { object in
            guard let bundle = string(object, kAudioProcessPropertyBundleID), !bundle.isEmpty,
                  pid(object) != own else { return false }
            return apps.contains { bundle == $0 || bundle.hasPrefix($0 + ".") }
        }.sorted()
    }

    private static func processObjects() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    private static func pid(_ object: AudioObjectID) -> pid_t {
        var address = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyPID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: pid_t = -1
        var size = UInt32(MemoryLayout<pid_t>.size)
        _ = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
        return value
    }

    private static func defaultOutputUID() throws -> String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let err = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard err == noErr, let uid = string(device, kAudioDevicePropertyDeviceUID) else { throw Failure(step: "the default output", status: err) }
        return uid
    }
}

/// Float frames in, 16-bit packets of about 10 ms out. On the IO queue only.
private final class Packer: @unchecked Sendable {
    let sampleRate: Double
    let channels: Int
    private let framesPerPacket: Int
    private var pending: [Int16] = []

    init(sampleRate: Double, channels: Int) {
        self.sampleRate = sampleRate
        self.channels = channels
        framesPerPacket = max(1, Int(sampleRate / 100))
        pending.reserveCapacity(framesPerPacket * channels * 2)
    }

    func add(_ buffers: UnsafeMutableAudioBufferListPointer, send: ((Data) -> Void)?) {
        guard let send, let first = buffers.first, let data0 = first.mData else { return }
        if buffers.count == 1 {
            // Interleaved: one buffer of every channel's samples.
            let have = Int(first.mNumberChannels)
            let frames = Int(first.mDataByteSize) / (4 * max(1, have))
            let src = data0.assumingMemoryBound(to: Float.self)
            for f in 0..<frames {
                for c in 0..<channels { pending.append(Self.int16(src[f * have + min(c, have - 1)])) }
            }
        } else {
            // One buffer a channel.
            let frames = Int(first.mDataByteSize) / 4
            let srcs = (0..<channels).map { buffers[min($0, buffers.count - 1)].mData?.assumingMemoryBound(to: Float.self) }
            for f in 0..<frames {
                for c in 0..<channels { pending.append(Self.int16(srcs[c]?[f] ?? 0)) }
            }
        }
        let step = framesPerPacket * channels
        while pending.count >= step {
            let packet = pending.withUnsafeBufferPointer {
                AudioPacket.pack(sampleRate: UInt32(sampleRate), channels: UInt8(channels), samples: UnsafeBufferPointer(rebasing: $0[0..<step]))
            }
            pending.removeFirst(step)
            send(packet)
        }
    }

    private static func int16(_ v: Float) -> Int16 { Int16(max(-1, min(1, v)) * 32767) }
}

/// AAC-ELD (low delay) of the tapped sound, for a device that asked for it: about 96 kbit/s at 48 kHz
/// stereo instead of plain PCM's 1.5 Mbit/s, for about 15 ms more delay. Fed the plain packets'
/// samples; each AAC packet (512 frames) goes out with the decoder's magic cookie. On the IO queue.
private final class AACEncoder {
    private let converter: AVAudioConverter
    private let input: AVAudioFormat
    private let output: AVAudioFormat
    private let cookie: Data
    private let sampleRate: UInt32
    private let channels: UInt8
    private var pending: AVAudioPCMBuffer?

    init?(sampleRate: Double, channels: Int) {
        guard let input = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate, channels: AVAudioChannelCount(channels),
                                        interleaved: true) else { return nil }
        var desc = AudioStreamBasicDescription(mSampleRate: sampleRate, mFormatID: kAudioFormatMPEG4AAC_ELD, mFormatFlags: 0,
                                               mBytesPerPacket: 0, mFramesPerPacket: 0, mBytesPerFrame: 0,
                                               mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 0, mReserved: 0)
        guard let output = AVAudioFormat(streamDescription: &desc), let converter = AVAudioConverter(from: input, to: output) else {
            print("Audio: no AAC-ELD encoder; plain PCM only")
            return nil
        }
        converter.bitRate = channels > 1 ? 96_000 : 64_000
        self.input = input; self.output = output; self.converter = converter
        self.cookie = converter.magicCookie ?? Data()
        self.sampleRate = UInt32(sampleRate); self.channels = UInt8(channels)
    }

    /// One plain packet (AudioPacket) in; any AAC packets it completes out.
    func encode(_ pcm: Data, out: (Data) -> Void) {
        guard let (_, _, samples) = AudioPacket.unpack(pcm), !samples.isEmpty else { return }
        let frames = AVAudioFrameCount(samples.count / Int(channels))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: input, frameCapacity: frames) else { return }
        buffer.frameLength = frames
        samples.withUnsafeBufferPointer { src in
            buffer.int16ChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        pending = buffer
        let compressed = AVAudioCompressedBuffer(format: output, packetCapacity: 4, maximumPacketSize: max(converter.maximumOutputPacketSize, 1536))
        var error: NSError?
        let status = converter.convert(to: compressed, error: &error) { [weak self] _, outStatus in
            guard let self, let given = self.pending else { outStatus.pointee = .noDataNow; return nil }
            self.pending = nil
            outStatus.pointee = .haveData
            return given
        }
        guard status != .error, let descriptions = compressed.packetDescriptions else { return }
        for i in 0..<Int(compressed.packetCount) {
            let d = descriptions[i]
            let packet = Data(bytes: compressed.data.advanced(by: Int(d.mStartOffset)), count: Int(d.mDataByteSize))
            out(AudioPacket.packEncoded(sampleRate: sampleRate, channels: channels, cookie: cookie, packet: packet))
        }
    }
}
