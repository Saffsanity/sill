// Away from home on the host (docs/remote-bundle-plan.md §5, the rules under H7–H9 and H13):
// HostConfig's away pair, DeviceSettings' view of it and AwayPolicy, compiled as one module with
// StreamProtocol's HostSettings.swift (build.sh strips `import StreamProtocol`):
//
//   Tests/checks/away-quality/build.sh . .build/checks/away-quality/check && .build/checks/away-quality/check
//
// What it checks: `standard` starts away at Low · Standard; `validated()` bounds the away pair as the
// home one; `changes(to:)` names the away pair's changes as the log does ("away bitrate 4 → 15 Mbps
// per 60 fps", "away points → Retina"); `effective(away:)`; a device's state shows the pair its
// connection controls, and a change from away lands on the away pair and never on the home one, the
// rest as at home; the whitelist is the same from both routes; who counts as away; when the away
// quality is the target (and that the flag stays with nobody connected); and the two lines.
import CoreGraphics
import Foundation

var failures = 0
func check(_ ok: Bool, _ what: String) {
    print("\(ok ? "ok" : "FAIL") \(what)")
    if !ok { failures += 1 }
}
func eq<T: Equatable>(_ a: T, _ b: T, _ what: String) { check(a == b, "\(what): \(a)" + (a == b ? "" : " (want \(b))")) }

let standard = HostConfig.standard

// MARK: HostConfig

eq(standard.awayBitrate, 4_000_000, "standard: away at Low")
eq(standard.awayCaptureScale, 1, "standard: away at Standard")
eq(standard.bitrate, 15_000_000, "standard: home at Balanced, as before")
eq(standard.captureScale, 2, "standard: home at Retina, as before")
check(standard.validated() == standard, "standard is valid as it is")

do {
    var c = standard
    c.awayBitrate = 0; c.awayCaptureScale = 0
    eq(c.validated().awayBitrate, 1_000_000, "validated: an away bitrate under 1 Mbps is 1 Mbps")
    eq(c.validated().awayCaptureScale, 1, "validated: an away scale of 0 is Standard")
    c.awayBitrate = 250_000_000; c.awayCaptureScale = 3
    eq(c.validated().awayBitrate, 200_000_000, "validated: an away bitrate over 200 Mbps is 200 Mbps")
    eq(c.validated().awayCaptureScale, 2, "validated: an away scale of 3 is Retina")
    c.awayBitrate = 12_345_678; c.awayCaptureScale = 1.5
    eq(c.validated().awayBitrate, 12_345_678, "validated: a hand-set away bitrate inside the bounds stays")
    eq(c.validated().awayCaptureScale, 2, "validated: 1.5 is Retina")
    c.awayCaptureScale = 1.49
    eq(c.validated().awayCaptureScale, 1, "validated: 1.49 is Standard")
    // The two pairs are bounded apart: one never borrows the other's value.
    c = standard
    c.captureScale = 1; c.awayCaptureScale = 2
    eq(c.validated().captureScale, 1, "validated: the home scale is its own")
    eq(c.validated().awayCaptureScale, 2, "validated: the away scale is its own")
    c.bitrate = 250_000_000; c.awayBitrate = 4_000_000
    eq(c.validated().awayBitrate, 4_000_000, "validated: the away bitrate is its own")
}

do {
    var to = standard
    to.awayBitrate = 15_000_000
    eq(standard.changes(to: to), "away bitrate 4 → 15 Mbps per 60 fps", "changes: the away bitrate")
    to = standard
    to.awayCaptureScale = 2
    eq(standard.changes(to: to), "away points → Retina", "changes: the away scale")
    var from = standard
    from.awayBitrate = 15_000_000
    to = from
    to.awayBitrate = 8_000_000; to.awayCaptureScale = 2
    eq(from.changes(to: to), "away bitrate 15 → 8 Mbps per 60 fps, away points → Retina", "changes: both (H9's line)")
    to = standard
    to.bitrate = 8_000_000; to.captureScale = 1; to.awayBitrate = 15_000_000; to.awayCaptureScale = 2
    eq(standard.changes(to: to), "bitrate 15 → 8 Mbps per 60 fps, Retina → points, away bitrate 4 → 15 Mbps per 60 fps, away points → Retina",
       "changes: the home pair, then the away pair")
    to = standard
    to.awayBitrate = 8_500_000
    eq(standard.changes(to: to), "away bitrate 4 → 8.5 Mbps per 60 fps", "changes: a bitrate that is not whole megabits")
}

do {
    var c = standard
    c.bitrate = 40_000_000; c.captureScale = 2
    check(c.effective(away: true) == (4_000_000, 1), "effective(away: true) is the away pair")
    check(c.effective(away: false) == (40_000_000, 2), "effective(away: false) is the home pair")
}

// MARK: DeviceSettings

do {
    var c = standard
    c.bitrate = 40_000_000; c.captureScale = 2; c.maxFPS = 60; c.prioritizeSpeed = true; c.directWireless = true
    let away = c.streamSettings(away: true)
    eq(away.bitrate, 4_000_000, "a device away sees the away bitrate")
    eq(away.captureScale, 1, "…and the away scale")
    let home = c.streamSettings(away: false)
    eq(home.bitrate, 40_000_000, "a device at home sees the home bitrate")
    eq(home.captureScale, 2, "…and the home scale")
    for (s, route) in [(away, "away"), (home, "home")] {
        check(s.maxFPS == 60 && s.prioritizeSpeed && !s.virtualDisplay && s.directWireless == true,
              "\(route): the other four are shared")
    }
}

do {
    var c = standard
    c.bitrate = 40_000_000; c.captureScale = 2
    let change = HostSettingsChange(token: 3, maxFPS: 60, bitrate: 15_000_000, captureScale: 2, prioritizeSpeed: true, virtualDisplay: true,
                                    directWireless: nil)
    let away = c.applyingAway(change)
    eq(away.awayBitrate, 15_000_000, "applyingAway: the bitrate lands on the away pair")
    eq(away.awayCaptureScale, 2, "applyingAway: the scale lands on the away pair")
    eq(away.bitrate, 40_000_000, "applyingAway: the home bitrate stays")
    eq(away.captureScale, 2, "applyingAway: the home scale stays")
    check(away.maxFPS == 60 && away.prioritizeSpeed && away.virtualDisplay, "applyingAway: the rest as at home")
    let home = c.applying(change)
    eq(home.bitrate, 15_000_000, "applying: the bitrate lands on the home pair")
    check(home.awayBitrate == 4_000_000 && home.awayCaptureScale == 1, "applying: the away pair stays")
    // Only a bitrate: the away scale is left alone, and the state answers in the field asked about.
    let only = c.applyingAway(HostSettingsChange(bitrate: 25_000_000))
    check(only.awayCaptureScale == 1 && only.awayBitrate == 25_000_000, "applyingAway of a bitrate alone keeps the away scale")
    eq(only.streamSettings(away: true).bitrate, 25_000_000, "…and the state a device away is sent answers with it")
    eq(only.streamSettings(away: false).bitrate, 40_000_000, "…while a device at home still sees the home bitrate")
    let scaleOnly = c.applyingAway(HostSettingsChange(captureScale: 2))
    check(scaleOnly.awayCaptureScale == 2 && scaleOnly.awayBitrate == 4_000_000 && scaleOnly.captureScale == 2,
          "applyingAway of a scale alone keeps the away bitrate and the home pair")
    var retinaAway = c
    retinaAway.awayCaptureScale = 2
    let standardPick = retinaAway.applyingAway(HostSettingsChange(captureScale: 1))
    check(standardPick.awayCaptureScale == 1 && standardPick.captureScale == 2,
          "applyingAway of Standard from Retina away keeps the home Retina")
    let empty = c.applyingAway(HostSettingsChange(token: 9))
    check(empty == c, "applyingAway of nothing changes nothing")
    let dw = c.applyingAway(HostSettingsChange(directWireless: true))
    check(dw.directWireless && dw.awayBitrate == 4_000_000, "applyingAway lays a shared field as applying does")
}

do {
    // The whitelist is the same whichever pair the change lands on.
    let change = HostSettingsChange(bitrate: 12_000_000, captureScale: 1.5, directWireless: true)
    let (ok, refused) = DeviceSettings.accepted(change, virtualDisplayAvailable: true, fromRemote: true)
    check(ok.bitrate == nil && ok.captureScale == nil && ok.directWireless == nil, "accepted: a hand-set bitrate, 1.5 and Direct Wireless from afar are refused")
    eq(refused.count, 3, "accepted: three refusals named")
    let (fine, none) = DeviceSettings.accepted(HostSettingsChange(bitrate: 150_000_000, captureScale: 1), virtualDisplayAvailable: false, fromRemote: true)
    check(fine.bitrate == 150_000_000 && fine.captureScale == 1 && none.isEmpty, "accepted: every preset and both scales from afar")
}

// MARK: AwayPolicy

do {
    for (origin, want) in [(OriginPolicy.Origin.vpn, true), (.internet, true), (.lan, false), (.loopback, false), (.direct, false)] {
        eq(AwayPolicy.isAway(remoteDoor: true, origin: origin), want, "the remote door from \(origin) is away: \(want)")
        eq(AwayPolicy.isAway(remoteDoor: false, origin: origin), false, "the home door from \(origin) is at home")
    }
}

do {
    eq(AwayPolicy.wanted(devicesAway: [], current: true), true, "nobody connected: the flag stays on")
    eq(AwayPolicy.wanted(devicesAway: [], current: false), false, "nobody connected: the flag stays off")
    eq(AwayPolicy.wanted(devicesAway: [true], current: false), true, "one device, away: the away quality")
    eq(AwayPolicy.wanted(devicesAway: [false], current: true), false, "one device, at home: the home quality")
    eq(AwayPolicy.wanted(devicesAway: [true, true], current: false), true, "two away: the away quality")
    eq(AwayPolicy.wanted(devicesAway: [true, false], current: true), false, "one away, one at home: the home quality")
    eq(AwayPolicy.wanted(devicesAway: [false, true, true], current: true), false, "any at home brings the home quality")
}

do {
    var c = standard
    c.bitrate = 40_000_000
    eq(AwayPolicy.awayLine(c),
       "Away from home: every connected device is away; streaming at Low · Standard (4 Mbps per 60 fps, points). The home quality stays Pro · Retina.",
       "the away line")
    eq(AwayPolicy.homeLine(c, endpoint: "fe80::1c2d:3e4f:5a6b:7c8d%en0.51447"),
       "Home quality again: a device connected at home (fe80::1c2d:3e4f:5a6b:7c8d%en0.51447); streaming at Pro · Retina.",
       "the home line")
    c.awayBitrate = 25_000_000; c.awayCaptureScale = 2; c.bitrate = 12_000_000; c.captureScale = 1
    eq(AwayPolicy.awayLine(c),
       "Away from home: every connected device is away; streaming at High · Retina (25 Mbps per 60 fps, Retina). The home quality stays 12 Mbps · Standard.",
       "the away line at High · Retina, home at a hand-set 12 Mbps")
}

print(failures == 0 ? "away-quality: all passed" : "away-quality: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
