import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Whether screen sharing shows the pairing window (issue #108): Settings › Devices' "Show the
/// pairing window to screen sharing", saved as `showPairingWindowToScreenSharing` (HostSettings).
/// Pure, so `Tests/checks/pairing-sharing` runs it with swiftc, the window's `NSWindow.SharingType`
/// for each answer included (`windowSharingType`, below, which PairDeviceWindowController sets: the
/// check imports AppKit for that enum alone, and makes no window).
///
/// The pairing window is the one window Sill keeps out of what other apps see of the screen
/// (`.none`): Screen Sharing, Apple Remote Desktop and VNC apps such as Screens leave it out
/// (issues #108 and #137), so its QR code and its 12 digits stay with whoever sits at the Mac. A Mac
/// used only through them, one with no display or one at home used from afar, could then pair a
/// device over the USB cable alone. The switch, off by default, shows the window to them as any
/// window is shown (`.readOnly`, AppKit's default), whoever opened it: the Mac's user from the menu
/// or a pane, or a device by asking. A device pairs by tapping the Mac, which asks, and the window
/// that ask opens is the one read over Screen Sharing. Nothing else changes (Noah, 2026-10-19: the
/// pairing window only, as a switch): the cable notice and Sill's other windows keep AppKit's
/// default, as before, and no device streaming this Mac sees any of Sill's windows either way (the
/// Desktop stream leaves them out, and a picked window is never one of them).
///
/// `.none` was a best effort to begin with: ScreenCaptureKit is reported to ignore it from macOS
/// 15, so an app allowed to record the screen can read the code whatever this says. What it keeps
/// out is the remote viewers above. So the switch lives in UserDefaults, not beside Require pairing
/// in the keychain: it lets no device in, and only lets a remote viewer see what anyone at the Mac
/// sees.
enum PairingWindowSharing: Equatable {
    /// Left out of what other apps capture of the screen (`NSWindow.SharingType.none`).
    case hidden
    /// Captured as any window is (`NSWindow.SharingType.readOnly`).
    case shown

    /// The pairing window, opened on this Mac or by a device's ask (`byDevice`, the offer's): shown
    /// exactly while the switch is on, whoever opened it.
    static func pairingWindow(switchOn: Bool, byDevice: Bool) -> PairingWindowSharing {
        switchOn ? .shown : .hidden
    }

    /// The Log's line when the switch changes, and at launch while it is on.
    static func line(on: Bool) -> String {
        on ? "Pairing window: shown to screen sharing (Settings › Devices); anyone who can see this Mac’s screen remotely can read its code."
           : "Pairing window: hidden from screen sharing (Settings › Devices)."
    }
}

#if canImport(AppKit)
extension PairingWindowSharing {
    /// What the window server is told (`NSWindow.sharingType`): `.none` hidden, so Screen Sharing,
    /// Apple Remote Desktop and VNC apps leave the window out; `.readOnly`, AppKit's default for any
    /// window, shown.
    var windowSharingType: NSWindow.SharingType {
        switch self {
        case .hidden: .none
        case .shown: .readOnly
        }
    }
}
#endif
