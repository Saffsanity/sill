import Foundation
import CoreAudio
import AudioToolbox

/// The Mac's sound through a Core Audio process tap (QuietMac, docs/audio-plan.md §14): every process but
/// Sill's, made with CATapMutedWhenTapped, so macOS silences it on the Mac while Sill reads it and plays it
/// again the moment the tap goes (stop, or the process ending). A private aggregate device clocked by the
/// default output device carries the tap; its IOProc hands each buffer to the pipeline's queue as
/// interleaved stereo, with its host time, as AudioCapture's are. The permission ("System Audio Recording
/// Only") is read first and asked once; declined, `start` throws and the caller captures through
/// ScreenCaptureKit instead (TapOrScreenCapture).
///
/// Not run by any test here, as AudioCapture is not: the tests never capture a person's sound.
/// shortcut: the aggregate follows the output device it was made on; a change of the Mac's output (headphones
/// plugged into the Mac) keeps the tap on the old one until the sound restarts. Upgrade if it shows.
@available(macOS 14.2, *)
final class ProcessTapCapture: AudioSource, @unchecked Sendable {
    var onPCM: ((PCMChunk) -> Void)?
    var onStopped: ((String) -> Void)?

    struct Failure: AudioSourceFailure {
        let description: String
    }

    private let queue: DispatchQueue
    // Main actor: start and stop.
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    // Set before the IOProc starts, read on `queue`.
    private var layout: PCMLayout?
    private var rate: Double = 48_000
    private var firstLogged = false

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func start() async throws {
        if AudioRecordingPermission.now() == .unknown, await AudioRecordingPermission.request() == false {
            throw Failure(description: "the permission to record this Mac's sound was declined")
        }
        guard AudioRecordingPermission.now() != .denied else {
            throw Failure(description: "the permission to record this Mac's sound is declined (System Settings › Privacy & Security)")
        }
        let tapDescription = CATapDescription(stereoGlobalTapButExcludeProcesses: Self.ownProcessObject().map { [$0] } ?? [])
        tapDescription.name = "Sill"
        tapDescription.isPrivate = true
        tapDescription.muteBehavior = .mutedWhenTapped
        do {
            try Self.check(AudioHardwareCreateProcessTap(tapDescription, &tapID), "make the process tap")
            let format = try Self.format(of: tapID)
            guard let l = PCMLayout.from(formatID: format.mFormatID, flags: format.mFormatFlags,
                                         bitsPerChannel: format.mBitsPerChannel, channels: format.mChannelsPerFrame) else {
                throw Failure(description: "the tap's sound is in a layout Sill does not read (format \(format.mFormatID), \(format.mBitsPerChannel) bits)")
            }
            layout = l
            rate = format.mSampleRate
            let output = try Self.defaultOutputUID()
            let aggregate: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Sill",
                kAudioAggregateDeviceUIDKey: "me.saffer.sill.tap.\(UUID().uuidString)",
                kAudioAggregateDeviceMainSubDeviceKey: output,
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceIsStackedKey: false,
                kAudioAggregateDeviceTapAutoStartKey: true,
                kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: output]],
                kAudioAggregateDeviceTapListKey: [[kAudioSubTapDriftCompensationKey: true,
                                                   kAudioSubTapUIDKey: tapDescription.uuid.uuidString]],
            ]
            try Self.check(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &aggregateID), "make its aggregate device")
            try Self.check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { [weak self] _, input, inputTime, _, _ in
                self?.deliver(input, at: inputTime)
            }, "read it")
            try Self.check(AudioDeviceStart(aggregateID, procID), "start it")
        } catch {
            await stop()
            throw error
        }
    }

    func stop() async {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
        // The IOProc's last buffer may still be on the queue.
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in queue.async { c.resume() } }
    }

    /// On `queue`: one IOProc buffer as interleaved stereo, stamped with its host time.
    private func deliver(_ input: UnsafePointer<AudioBufferList>, at time: UnsafePointer<AudioTimeStamp>) {
        guard let layout else { return }
        let list = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let buffers = list.map { UnsafeRawBufferPointer(start: $0.mData, count: $0.mData == nil ? 0 : Int($0.mDataByteSize)) }
        guard let first = buffers.first else { return }
        let frames = layout.frames(bytes: first.count)
        guard frames > 0, let samples = layout.stereo(frames: frames, buffers: buffers) else { return }
        let stamp = time.pointee
        let hostTime = stamp.mFlags.contains(.hostTimeValid) ? HostClock.seconds(ticks: stamp.mHostTime)
                                                              : HostClock.now() - Double(frames) / rate
        if !firstLogged {
            firstLogged = true
            print("Audio: first buffer from the process tap, \(frames) frames, \(Int(rate)) Hz, \(layout.channels) channels, \(layout).")
        }
        onPCM?(PCMChunk(samples: samples, channels: 2, sampleRate: rate, hostTime: hostTime))
    }

    // MARK: Core Audio's properties

    private static func check(_ status: OSStatus, _ what: String) throws {
        guard status == noErr else { throw Failure(description: "could not \(what) (OSStatus \(status))") }
    }

    /// This process as Core Audio lists it, to leave out of the tap; nil while it has played no sound.
    private static func ownProcessObject() -> AudioObjectID? {
        var pid = getpid()
        var object = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                                UInt32(MemoryLayout<pid_t>.size), &pid, &size, &object)
        return status == noErr && object != kAudioObjectUnknown ? object : nil
    }

    private static func format(of tap: AudioObjectID) throws -> AudioStreamBasicDescription {
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        try check(AudioObjectGetPropertyData(tap, &address, 0, nil, &size, &format), "read the tap's format")
        return format
    }

    private static func defaultOutputUID() throws -> String {
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device), "find the Mac's sound output")
        var uid: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        address.mSelector = kAudioDevicePropertyDeviceUID
        try check(AudioObjectGetPropertyData(device, &address, 0, nil, &size, &uid), "read the sound output's name")
        guard let uid else { throw Failure(description: "the Mac's sound output has no UID") }
        return uid.takeRetainedValue() as String
    }
}

/// macOS's "System Audio Recording Only" permission, read and asked through TCC.framework's preflight and
/// request, as Apple's own process-tap sample does: Core Audio has no public call for either, and a tap
/// made without it records silence (while still silencing the Mac). Both missing: unknown, and the tap is
/// tried (macOS asks by itself as it starts).
enum AudioRecordingPermission {
    private static let tcc = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW)
    private static let service = "kTCCServiceAudioCapture" as CFString

    static func now() -> QuietMac.Permission {
        typealias Preflight = @convention(c) (CFString, CFDictionary?) -> Int
        guard let tcc, let symbol = dlsym(tcc, "TCCAccessPreflight") else { return QuietMac.permission(preflight: nil) }
        return QuietMac.permission(preflight: unsafeBitCast(symbol, to: Preflight.self)(service, nil))
    }

    /// Asks once (macOS shows its prompt); true if granted, nil if TCC's call is not there.
    static func request() async -> Bool? {
        typealias Request = @convention(c) (CFString, CFDictionary?, @escaping (Bool) -> Void) -> Void
        guard let tcc, let symbol = dlsym(tcc, "TCCAccessRequest") else { return nil }
        let call = unsafeBitCast(symbol, to: Request.self)
        return await withCheckedContinuation { (c: CheckedContinuation<Bool, Never>) in call(service, nil) { c.resume(returning: $0) } }
    }
}

/// The process tap, and ScreenCaptureKit when the tap does not start (the permission declined, an error):
/// the iPad hears the sound either way; only the tap keeps the Mac quiet.
final class TapOrScreenCapture: AudioSource, @unchecked Sendable {
    var onPCM: ((PCMChunk) -> Void)? { didSet { tap.onPCM = onPCM; fallback.onPCM = onPCM } }
    var onStopped: ((String) -> Void)? { didSet { tap.onStopped = onStopped; fallback.onStopped = onStopped } }
    private let tap: AudioSource
    private let fallback: AudioSource
    private var running: AudioSource?

    init(tap: AudioSource, fallback: AudioSource) {
        self.tap = tap
        self.fallback = fallback
    }

    func start() async throws {
        do {
            try await tap.start()
            running = tap
        } catch {
            print("Audio: the process tap did not start (\(error)); capturing through ScreenCaptureKit instead, and the Mac keeps playing.")
            try await fallback.start()
            running = fallback
        }
    }

    func stop() async {
        await running?.stop()
        running = nil
    }
}
