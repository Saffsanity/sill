import Foundation
import CoreAudio

/// The Mac's own speakers silent while a device plays its sound, so the sound is heard once, on the
/// device, in time with the picture, as High Performance screen sharing does. ScreenCaptureKit takes
/// each app's sound before the output device, so the device still hears it.
///
/// Only a device this Mac did not have muted already is muted, and only that one is unmuted again
/// (`release`), and only while it is still muted: a mute the person set stays theirs. The device muted
/// is kept in the defaults until it is unmuted, so a Sill that ended without `release` (a crash, a
/// kill) unmutes it at its next start. Another output chosen meanwhile (headphones plugged in) plays
/// as chosen. Main actor, like the coordinator.
@MainActor
final class MacOutputMute {
    private static let leftoverKey = "Sill.mutedOutputDevice"
    private var muted: AudioDeviceID?

    init() {
        let left = UserDefaults.standard.integer(forKey: Self.leftoverKey)
        guard left > 0 else { return }
        UserDefaults.standard.removeObject(forKey: Self.leftoverKey)
        if Self.isMuted(AudioDeviceID(left)) == true, Self.setMuted(AudioDeviceID(left), false) {
            print("Mac's sound: unmuted the output Sill muted before it last ended.")
        }
    }

    /// Muted while `on`, back as it was once not.
    func set(_ on: Bool) { on ? engage() : release() }

    private func engage() {
        guard muted == nil, let device = Self.defaultOutput() else { return }
        guard Self.isMuted(device) == false else { return }   // muted already, or no mute to set
        guard Self.setMuted(device, true) else {
            print("Mac's sound: this Mac's output could not be muted; it plays here too.")
            return
        }
        muted = device
        UserDefaults.standard.set(Int(device), forKey: Self.leftoverKey)
        print("Mac's sound: muted on this Mac while a device plays it.")
    }

    func release() {
        guard let device = muted else { return }
        muted = nil
        UserDefaults.standard.removeObject(forKey: Self.leftoverKey)
        if Self.isMuted(device) == true { _ = Self.setMuted(device, false) }
        print("Mac's sound: playing on this Mac again.")
    }

    // MARK: Core Audio

    private static func defaultOutput() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        return device
    }

    private static func muteAddress() -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput,
                                   mElement: kAudioObjectPropertyElementMain)
    }

    /// Nil when the device has no mute to read.
    private static func isMuted(_ device: AudioDeviceID) -> Bool? {
        var address = muteAddress()
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value != 0
    }

    private static func setMuted(_ device: AudioDeviceID, _ on: Bool) -> Bool {
        var address = muteAddress()
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &address),
              AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else { return false }
        var value: UInt32 = on ? 1 : 0
        return AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }
}
