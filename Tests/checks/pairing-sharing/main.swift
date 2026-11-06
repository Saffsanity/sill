import AppKit
import Foundation

// Checks PairingWindowSharing (Sources/SillMenuBar, issue #108): whether screen sharing (Screen
// Sharing, Apple Remote Desktop, VNC apps) shows the pairing window. Settings › Devices' "Show the
// pairing window to screen sharing" decides it alone: hidden while off, as before the switch; shown
// while on, whoever opened the window, the Mac's user from the menu or a pane, or a device by asking
// (a Mac used only through Screen Sharing pairs through the window a device's tap opens). Then what
// the window server is told for each answer (`windowSharingType`, which PairDeviceWindowController
// sets on the window): `.none` hidden, `.readOnly`, AppKit's default, shown. And the Log's lines,
// which never carry a code. Pure: AppKit is imported for `NSWindow.SharingType` alone, so it runs
// with no window and no screen.

var failures = 0
var checks = 0
func check<T: Equatable>(_ desc: String, _ got: T, _ want: T) {
    checks += 1
    if got == want { print("ok: \(desc)"); return }
    failures += 1
    print("FAIL: \(desc): got \(got), want \(want)")
}

// The switch off, the default: hidden, as the window always was before it.
check("off, a window the Mac's user opened (the menu, a pane, New Code) → hidden",
      PairingWindowSharing.pairingWindow(switchOn: false, byDevice: false), .hidden)
check("off, a window a device's ask opened → hidden",
      PairingWindowSharing.pairingWindow(switchOn: false, byDevice: true), .hidden)

// The switch on: shown, whoever opened it.
check("on, a window the Mac's user opened → shown",
      PairingWindowSharing.pairingWindow(switchOn: true, byDevice: false), .shown)
check("on, a window a device's ask opened → shown (the device's tap is how a Mac seen over Screen Sharing pairs)",
      PairingWindowSharing.pairingWindow(switchOn: true, byDevice: true), .shown)

// One window through a session, asked as PairDeviceWindowController asks (as the window is made,
// before any offer: no opener yet; as each offer shows; at each change of the switch): every answer
// follows the switch alone, so a window open when it changes follows it, and an offer from the
// other opener changes nothing.
var switchOn = false
var byDevice = false
let steps: [(String, () -> Void, PairingWindowSharing)] = [
    ("made with the switch off", {}, .hidden),
    ("a device asks: its offer shows", { byDevice = true }, .hidden),
    ("the switch on while that window is open", { switchOn = true }, .shown),
    ("the Mac's user opens a window over it", { byDevice = false }, .shown),
    ("a device asks again while it is open", { byDevice = true }, .shown),
    ("the switch off while it is open", { switchOn = false }, .hidden),
    ("the Mac's user's offer again", { byDevice = false }, .hidden),
    ("the switch on with the window closed, then a device's ask", { switchOn = true; byDevice = true }, .shown),
]
for (what, change, want) in steps {
    change()
    check("one window: \(what)", PairingWindowSharing.pairingWindow(switchOn: switchOn, byDevice: byDevice), want)
}

// What the window server is told: the part of the rule that reaches Screen Sharing. A swap here
// would hide the window with the switch on and show it with the switch off, every case above
// passing. By name, since `NSWindow.SharingType` prints its type's name alone.
func sharingName(_ type: NSWindow.SharingType) -> String {
    switch type {
    case .none: "none"
    case .readOnly: "readOnly"
    default: "rawValue \(type.rawValue)"
    }
}
check("hidden → NSWindow.SharingType.none (Screen Sharing and other remote viewers leave the window out)",
      sharingName(PairingWindowSharing.hidden.windowSharingType), "none")
check("shown → NSWindow.SharingType.readOnly (AppKit's default: shown as any window is)",
      sharingName(PairingWindowSharing.shown.windowSharingType), "readOnly")

// The Log's lines: what the switch does, in the house words, and never a code (no digit at all).
let onLine = PairingWindowSharing.line(on: true)
let offLine = PairingWindowSharing.line(on: false)
check("the line when it turns on",
      onLine, "Pairing window: shown to screen sharing (Settings › Devices); anyone who can see this Mac’s screen remotely can read its code.")
check("the line when it turns off", offLine, "Pairing window: hidden from screen sharing (Settings › Devices).")
check("the two lines differ", onLine == offLine, false)
check("neither line carries a digit (never a code)",
      (onLine + offLine).contains(where: { $0.isNumber }), false)

print(failures == 0 ? "PASS: \(checks) checks" : "FAIL: \(failures) of \(checks) checks")
exit(failures == 0 ? 0 : 1)
