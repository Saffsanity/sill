// QuietMac (Sources/SillHost/QuietMac.swift) on its own: whether the Mac's sound is captured through a Core
// Audio process tap that silences it on the Mac while devices play it (CATapMutedWhenTapped), or through
// ScreenCaptureKit as before, which leaves the Mac playing too.
//
//   Tests/checks/quiet-mac/run.sh
//
// What it checks: TCC's preflight answers read as granted, declined or not asked yet; the tap only from
// macOS 14.2, only in an app that declares NSAudioCaptureUsageDescription (the CLI has no bundle), never
// on a synthetic host, never once the permission is declined; and every combination against that rule.
import Foundation

var failures = 0, passes = 0
func check(_ ok: Bool, _ what: String) {
    if ok { passes += 1; print("ok   \(what)") } else { failures += 1; print("FAIL \(what)") }
}
func eq<T: Equatable>(_ a: T, _ b: T, _ what: String) { check(a == b, "\(what): \(a)" + (a == b ? "" : " (want \(b))")) }

typealias Q = QuietMac

// MARK: The permission

eq(Q.permission(preflight: 0), .granted, "TCC's preflight 0: granted")
eq(Q.permission(preflight: 1), .denied, "TCC's preflight 1: declined")
eq(Q.permission(preflight: 2), .unknown, "TCC's preflight 2: not asked yet")
eq(Q.permission(preflight: -1), .unknown, "anything else: not known, so asked")
eq(Q.permission(preflight: nil), .unknown, "TCC's call not there: not known, so asked")

// MARK: Whether the tap is used

eq(Q.usesTap(macOS: (14, 2), declared: true, synthetic: false, permission: .granted), true, "macOS 14.2, Sill.app, granted: the tap")
eq(Q.usesTap(macOS: (27, 0), declared: true, synthetic: false, permission: .unknown), true, "not asked yet: the tap, which asks once")
eq(Q.usesTap(macOS: (27, 0), declared: true, synthetic: false, permission: .denied), false, "declined: ScreenCaptureKit, the Mac keeps playing")
eq(Q.usesTap(macOS: (14, 1), declared: true, synthetic: false, permission: .granted), false, "macOS 14.1: no process taps, ScreenCaptureKit")
eq(Q.usesTap(macOS: (13, 9), declared: true, synthetic: false, permission: .granted), false, "macOS 13: ScreenCaptureKit")
eq(Q.usesTap(macOS: (15, 0), declared: true, synthetic: false, permission: .granted), true, "macOS 15.0: the tap")
eq(Q.usesTap(macOS: (27, 0), declared: false, synthetic: false, permission: .granted), false, "no usage string (the CLI): ScreenCaptureKit")
eq(Q.usesTap(macOS: (27, 0), declared: true, synthetic: true, permission: .granted), false, "a synthetic host: its test tone, never a tap")

// MARK: What starts first

// Not asked yet: ScreenCaptureKit at once, so a prompt left unanswered never leaves the device without sound;
// the tap takes over once it is granted.
eq(Q.firstSource(permission: .granted), .tap, "granted: the tap at once")
eq(Q.firstSource(permission: .unknown), .screenWhileAsking, "not asked yet: ScreenCaptureKit while macOS asks")
eq(Q.firstSource(permission: .denied), .screen, "declined: ScreenCaptureKit")

for major in 12...28 { for minor in 0...4 { for declared in [false, true] { for synthetic in [false, true] {
    for p in [Q.Permission.granted, .denied, .unknown] {
        let want = (major > 14 || (major == 14 && minor >= 2)) && declared && !synthetic && p != .denied
        if Q.usesTap(macOS: (major, minor), declared: declared, synthetic: synthetic, permission: p) != want {
            check(false, "macOS \(major).\(minor), declared \(declared), synthetic \(synthetic), \(p): \(want)")
        }
    }
} } } }
check(failures == 0, "every combination of macOS, usage string, host and permission against the rule")

print("\(passes) passed, \(failures) failed")
exit(failures == 0 ? 0 : 1)
