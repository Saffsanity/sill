import Foundation

/// A quiet Mac while devices play its sound (docs/audio-plan.md §14): the sound is captured through a Core
/// Audio process tap of every process but Sill's, made with CATapMutedWhenTapped, so macOS silences it on
/// the Mac's own output while Sill reads it, and plays it again the moment Sill stops (the last device
/// stops listening, Send Audio goes off, Sill quits or crashes). While the tap is used a window stream sends
/// the whole Mac's sound too (Noah's choice, 2026-11-02: a tap knows processes, not an app's helpers).
/// Without it (macOS before 14.2, the permission declined, the CLI) ScreenCaptureKit as before, and the Mac
/// keeps playing. Pure; checked by Tests/checks/quiet-mac.
enum QuietMac {
    /// macOS's "System Audio Recording Only" permission (TCC's kTCCServiceAudioCapture).
    enum Permission: Equatable { case granted, denied, unknown }

    /// TCCAccessPreflight's answer: 0 granted, 1 declined, anything else (2: not asked yet) or no answer
    /// (the call not there) unknown, which the tap's start asks about once.
    static func permission(preflight: Int?) -> Permission {
        switch preflight {
        case 0: return .granted
        case 1: return .denied
        default: return .unknown
        }
    }

    enum FirstSource: Equatable { case tap, screenWhileAsking, screen }

    /// What starts: the tap once granted; while not asked yet ScreenCaptureKit at once, with macOS's prompt
    /// meanwhile, so a prompt left unanswered never leaves the devices without sound (the tap takes over
    /// once it is granted); declined, ScreenCaptureKit.
    static func firstSource(permission: Permission) -> FirstSource {
        switch permission {
        case .granted: return .tap
        case .unknown: return .screenWhileAsking
        case .denied: return .screen
        }
    }

    /// Whether the sound goes through the tap: from macOS 14.2 (AudioHardwareCreateProcessTap), in an app
    /// that declares NSAudioCaptureUsageDescription (macOS ends a process that asks without one), never on a
    /// synthetic host, not once the permission is declined, and not while the Mac's user wants it played
    /// on the Mac too (`playOnMac`, 2026-11-02).
    static func usesTap(macOS: (major: Int, minor: Int), declared: Bool, synthetic: Bool, permission: Permission,
                        playOnMac: Bool = false) -> Bool {
        (macOS.major, macOS.minor) >= (14, 2) && declared && !synthetic && permission != .denied && !playOnMac
    }
}
