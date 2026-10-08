// iOSClient/AwayCopy.swift on its own (docs/remote-bundle-plan.md §5.8, §6.7, §8; the rules under S1,
// S3 and S6), with StreamProtocol's HostSettings.swift:
//
//   swiftc -O iOSClient/AwayCopy.swift Sources/StreamProtocol/HostSettings.swift \
//     Tests/checks/away-copy/main.swift -o .build/checks/away-copy/check && .build/checks/away-copy/check
//
// What it checks: the panel header's away line and what VoiceOver adds; the footnote's three forms;
// the link's callout, first match wins, its button's title, spoken label and change; that stalled
// shows nothing; the old round-trip callout only for a Mac without `away`; the stream screen's line;
// and LinkLine: shown on arrival, gone 2 s after the report clears, kept through a quick flip, hidden
// while something is open over the stream, gone at once when its report clears (or it is covered) off
// screen, announced once a spell.
import Foundation

setvbuf(stdout, nil, _IOLBF, 0)
var failures = 0
func check(_ ok: Bool, _ what: String) {
    print("\(ok ? "ok" : "FAIL") \(what)")
    if !ok { failures += 1 }
}
func eq<T: Equatable>(_ a: T, _ b: T, _ what: String) { check(a == b, "\(what): \(a)" + (a == b ? "" : " (want \(b))")) }
let nb = "\u{00A0}"

func away(home: (Int, Double) = (40_000_000, 2), away: (Int, Double) = (4_000_000, 1), this: Bool = true, run: Bool = true) -> AwayQuality {
    AwayQuality(homeBitrate: home.0, homeCaptureScale: home.1, awayBitrate: away.0, awayCaptureScale: away.1,
                thisConnectionAway: this, awayRunning: run)
}
func link(_ state: String = LinkReport.behind, bitrate: Int = 40_000_000, suggested: Int? = 4_000_000, scale: Double? = 1) -> LinkReport {
    LinkReport(state: state, withheldPerSecond: 52, bitrate: bitrate, carriedKbps: 6_400, suggestedBitrate: suggested, suggestedCaptureScale: scale)
}

// MARK: The header

check(AwayCopy.headerLine(nil) == nil, "no away (an older Mac): no line")
check(AwayCopy.headerLine(away(this: false, run: true)) == nil, "at home: no line")
eq(AwayCopy.headerLine(away())?.text, "Away: Low\(nb)·\(nb)Standard", "away and running")
eq(AwayCopy.headerLine(away())?.spoken, ", away quality, Low, Standard", "…spoken")
eq(AwayCopy.headerLine(away(run: false))?.text, "Home quality: Pro\(nb)·\(nb)Retina (a device at home is connected)", "away while a device at home is connected")
eq(AwayCopy.headerLine(away(run: false))?.spoken, ", home quality, Pro, Retina, because a device at home is connected", "…spoken")
eq(AwayCopy.headerLine(away(away: (12_000_000, 2)))?.text, "Away: 12\(nb)Mbps\(nb)·\(nb)Retina", "a hand-set away bitrate by its rate, kept whole")
eq(AwayCopy.headerLine(away(away: (12_000_000, 2)))?.spoken, ", away quality, 12 megabits per second, Retina", "…spoken in words")

// MARK: The footnote

eq(AwayCopy.footnote(away(), mac: "Mac mini", remoteAccessOn: true),
   "Away from home, Mac mini streams at what you choose here and keeps it for next time. At home it goes back to Pro\(nb)·\(nb)Retina.",
   "away and running")
eq(AwayCopy.footnote(away(run: false), mac: "Mac mini", remoteAccessOn: true),
   "A device at home is connected, so Mac mini streams at its home quality, Pro\(nb)·\(nb)Retina. What you choose here applies once every device is away.",
   "away while a device at home is connected")
eq(AwayCopy.footnote(away(this: false, run: false), mac: "Mac mini", remoteAccessOn: true),
   "Away from home, Mac mini streams at Low\(nb)·\(nb)Standard.", "at home, Remote Access on")
check(AwayCopy.footnote(away(this: false, run: false), mac: "Mac mini", remoteAccessOn: false) == nil, "at home, Remote Access off: none")
check(AwayCopy.footnote(nil, mac: "Mac mini", remoteAccessOn: true) == nil, "no away: none")
eq(AwayCopy.footnote(away(this: false, run: true), mac: "Mac mini", remoteAccessOn: true),
   "Away from home, Mac mini streams at Low\(nb)·\(nb)Standard.", "at home while the Mac says every device is away (a moment in a move): the at-home form")

// MARK: The callout

check(AwayCopy.callout(link: nil, away: away(), mac: "Mac mini") == nil, "keeping up: no callout")
check(AwayCopy.callout(link: link(LinkReport.stalled), away: away(), mac: "Mac mini") == nil, "stalled: no callout (the Mac's alone)")
check(AwayCopy.callout(link: link("slowish"), away: away(), mac: "Mac mini") == nil, "a state this build does not know: no callout")
do {
    let c = AwayCopy.callout(link: link(), away: away(), mac: "Mac mini")
    eq(c?.text, "The link can’t carry Pro. Low\(nb)·\(nb)Standard is recommended.", "behind with a suggestion")
    eq(c?.button?.title, "Use Low\(nb)·\(nb)Standard", "…its button")
    eq(c?.button?.spoken, "Use Low, Standard", "…spoken")
    eq(c?.button?.change, HostSettingsChange(bitrate: 4_000_000, captureScale: 1), "…sends Low and Standard")
}
do {
    let c = AwayCopy.callout(link: link(bitrate: 150_000_000, suggested: 80_000_000, scale: nil), away: away(away: (150_000_000, 2)), mac: "Mac mini")
    eq(c?.text, "The link can’t carry Extreme. Ultra is recommended.", "a suggestion that keeps the resolution names the preset alone")
    eq(c?.button?.title, "Use Ultra", "…its button")
    eq(c?.button?.spoken, "Use Ultra", "…spoken")
    eq(c?.button?.change, HostSettingsChange(bitrate: 80_000_000), "…sends the bitrate alone")
}
do {
    let c = AwayCopy.callout(link: link(bitrate: 4_000_000, suggested: 4_000_000, scale: 1), away: away(away: (4_000_000, 2)), mac: "Mac mini")
    eq(c?.text, "The link can’t carry Low. Low\(nb)·\(nb)Standard is recommended.", "Low · Retina: the same bitrate at Standard")
    eq(c?.button?.change, HostSettingsChange(bitrate: 4_000_000, captureScale: 1), "…sends both (the ledger sends only what differs)")
}
do {
    let c = AwayCopy.callout(link: link(bitrate: 4_000_000, suggested: nil, scale: nil), away: away(), mac: "Mac mini")
    eq(c?.text, "The link to Mac mini is too slow for a steady picture, even at Low.", "nothing lower")
    check(c?.button == nil, "…no button")
}
do {
    let c = AwayCopy.callout(link: link(), away: away(run: false), mac: "Mac mini")
    eq(c?.text, "The link can’t carry Pro, which Mac mini keeps while a device at home is connected.",
       "away while a device at home is connected, first even with a suggestion")
    check(c?.button == nil, "…no button: nothing here would change it")
}
do {
    let c = AwayCopy.callout(link: link(), away: nil, mac: "Mac mini")
    eq(c?.text, "The link can’t carry Pro. Low\(nb)·\(nb)Standard is recommended.", "at home or from a host without away: the suggestion")
    let home = AwayCopy.callout(link: link(bitrate: 150_000_000, suggested: 80_000_000, scale: nil), away: away(this: false, run: false), mac: "Mac mini")
    eq(home?.button?.title, "Use Ultra", "at home the button lowers the home quality, as a menu click would")
}

// MARK: The old round-trip callout

check(AwayCopy.showsRttCallout(away: nil, remote: true, slowLink: true), "an older Mac, away, a slow round trip: the old callout")
check(!AwayCopy.showsRttCallout(away: away(), remote: true, slowLink: true), "a Mac that sends away judges the link itself: none")
check(!AwayCopy.showsRttCallout(away: nil, remote: false, slowLink: true), "at home: none")
check(!AwayCopy.showsRttCallout(away: nil, remote: true, slowLink: false), "a quick round trip: none")

// MARK: The stream screen's line

eq(AwayCopy.streamLine(link: link(), away: away(), mac: "Mac mini"), "The link can’t keep up with Pro. Lower it in Settings.", "behind with a suggestion")
eq(AwayCopy.streamLine(link: link(), away: away(run: false), mac: "Mac mini"), "The link to Mac mini can’t keep up.",
   "behind while a device at home is connected")
eq(AwayCopy.streamLine(link: link(bitrate: 4_000_000, suggested: nil, scale: nil), away: away(), mac: "Mac mini"), "The link to Mac mini can’t keep up.",
   "behind with nothing lower")
check(AwayCopy.streamLine(link: link(LinkReport.stalled), away: away(), mac: "Mac mini") == nil, "stalled: no line")
check(AwayCopy.streamLine(link: nil, away: away(), mac: "Mac mini") == nil, "keeping up: no line")

// MARK: LinkLine

do {
    var l = LinkLine()
    eq(l.update(report: nil, allowed: true, now: 0), nil, "nothing: nothing")
    check(l.text == nil && !l.visible, "…and no line")
    eq(l.update(report: "A", allowed: true, now: 1), "A", "a report of behind: shown at once, and announced")
    check(l.visible, "…visible")
    eq(l.update(report: "A", allowed: true, now: 2), nil, "…announced once, not on every update")
    eq(l.update(report: "B", allowed: true, now: 3), nil, "…nor when its words change within the spell")
    eq(l.text, "B", "…which shows the new words")
    eq(l.update(report: nil, allowed: true, now: 10), nil, "the report clears: nothing announced")
    check(l.visible && l.text == "B", "…the line lingers")
    eq(l.recheckAt, 12, "…looking again at the linger's end, 2 s after the clear")
    _ = l.update(report: nil, allowed: true, now: 11.9)
    check(l.visible, "…still at 1.9 s")
    _ = l.update(report: nil, allowed: true, now: 12)
    check(!l.visible && l.text == nil, "…gone at 2 s")
    check(l.recheckAt == nil, "…nothing to look at again")
    eq(l.update(report: "C", allowed: true, now: 13), "C", "a new spell is announced again")
}
do {
    var l = LinkLine()
    _ = l.update(report: "A", allowed: true, now: 0)
    _ = l.update(report: nil, allowed: true, now: 1)
    eq(l.update(report: "A", allowed: true, now: 2), nil, "a flip back within the linger: the same spell, no second announcement")
    _ = l.update(report: nil, allowed: true, now: 2.5)
    _ = l.update(report: nil, allowed: true, now: 4)
    check(l.visible, "…and the linger counts from the last clear (1.5 s later: still shown)")
    _ = l.update(report: nil, allowed: true, now: 4.5)
    check(!l.visible, "…gone 2 s after it")
}
do {
    var l = LinkLine()
    eq(l.update(report: "A", allowed: false, now: 0), nil, "a report while the panel, the drawer or the overlay is open: not announced")
    check(!l.visible && l.text == "A", "…and not shown, the spell begun")
    eq(l.update(report: "A", allowed: true, now: 1), "A", "…announced once it shows")
    eq(l.update(report: "A", allowed: false, now: 2), nil, "hidden again")
    check(!l.visible, "…not visible")
    eq(l.update(report: "A", allowed: true, now: 3), nil, "…and shown again without a second announcement")
    var gone = LinkLine()
    _ = gone.update(report: "A", allowed: false, now: 0)
    _ = gone.update(report: nil, allowed: false, now: 1)
    _ = gone.update(report: nil, allowed: true, now: 3)
    check(!gone.visible, "a spell that ended while hidden never shows")
}
do {
    // The review of 2026-09-27: the callout's button in the open panel clears the report at the
    // Mac's answer, and Done a second later must not bring up, or speak, a line that has gone.
    var l = LinkLine()
    eq(l.update(report: "A", allowed: false, now: 0), nil, "a report while the panel is open: not announced")
    eq(l.update(report: nil, allowed: false, now: 0.4), nil, "…cleared while the panel is open (its button)")
    eq(l.update(report: nil, allowed: true, now: 1.0), nil, "…the panel closed within the linger: nothing announced")
    check(!l.visible && l.text == nil, "…and no line: its spell ended as it cleared off screen")
    check(l.recheckAt == nil, "…nothing to look at again")
    eq(l.update(report: "B", allowed: true, now: 5), "B", "a later report is a new spell, announced")
    var covered = LinkLine()
    _ = covered.update(report: "A", allowed: true, now: 0)
    _ = covered.update(report: nil, allowed: true, now: 1)
    check(covered.visible, "a line on screen lingers after its report clears")
    _ = covered.update(report: nil, allowed: false, now: 1.5)
    _ = covered.update(report: nil, allowed: true, now: 2)
    check(!covered.visible && covered.text == nil, "…and something opened over it ends the linger: closed again, no line")
}

print(failures == 0 ? "away-copy: all passed" : "away-copy: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
