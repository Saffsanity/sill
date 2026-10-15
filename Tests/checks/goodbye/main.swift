import Foundation
// H3 (GoodbyePolicy): every row of the plan's §7.3 table, the cleaning of a host's message, and the
// reconnect rule. Compiled with Sources/StreamProtocol and iOSClient/GoodbyePolicy.swift (its
// `import StreamProtocol` dropped).
var failures = 0, checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
typealias O = GoodbyePolicy.Outcome
func out(_ g: Goodbye?, saved: Bool = false, mac: String = "Mac mini", device: String = "iPad",
         away: GoodbyePolicy.Away? = nil) -> O {
    GoodbyePolicy.outcome(g, mac: mac, device: device, saved: saved, away: away)
}
func g(_ reason: String, _ message: String? = nil, min: String? = nil, reconnect: Bool? = nil) -> Goodbye {
    Goodbye(reason: reason, message: message, minimumVersion: min, reconnect: reconnect)
}

// No goodbye: the connection just ended.
check(out(nil, saved: true) == O(text: "Mac mini disconnected. Sill will reconnect when it can reach it.", reconnect: true, remoteAllowed: true, isNotice: false), "none, saved")
check(out(nil) == O(text: "Mac mini disconnected. It will reconnect when the Mac is back.", reconnect: true, remoteAllowed: false, isNotice: false), "none, unsaved")
// Today's five, their words and reconnects unchanged.
check(out(g("quit"), saved: true) == O(text: "Mac mini quit Sill. This iPad reconnects when it’s back.", reconnect: true, remoteAllowed: true, isNotice: false), "quit, saved")
check(out(g("quit"), device: "iPhone").text == "Mac mini quit Sill. This iPhone reconnects when it’s back." && !out(g("quit")).remoteAllowed, "quit, an unsaved iPhone")
check(out(g("removed"), saved: true) == O(text: "Mac mini removed this iPad. To use it again, pair it again.", reconnect: false, remoteAllowed: false, isNotice: false), "removed")
check(out(g("remoteOff"), saved: true) == O(text: "Mac mini turned off Remote Access.", reconnect: true, remoteAllowed: false, isNotice: false), "remoteOff")
check(out(g("internetOff"), saved: true) == O(text: "Mac mini stopped accepting connections from the internet. Connect through your VPN.", reconnect: true, remoteAllowed: false, isNotice: false), "internetOff")
check(out(g("busy"), saved: true) == O(text: "Mac mini is already serving 8 devices.", reconnect: true, remoteAllowed: true, isNotice: false), "busy, saved")
check(!out(g("busy")).remoteAllowed, "busy, unsaved: rows only")
// The five ignore a message and reconnect a newer host might add: their rules are this build's.
check(out(g("quit", "x", reconnect: false), saved: true).text.hasPrefix("Mac mini quit Sill") && out(g("quit", reconnect: false)).reconnect, "quit keeps its rule")
check(!out(g("removed", reconnect: true)).reconnect, "removed never reconnects")
for r in ["quit", "removed", "remoteOff", "internetOff", "busy", "pairingRequired"] { check(!GoodbyePolicy.isNotice(g(r)), "\(r) is not a notice") }
// "pairingRequired" (pairing at home, docs/home-pairing-plan.md §7.6): Require pairing was turned on
// while this unpaired device was connected at home. Its own words and no reconnect, whatever the
// host adds: a tap on the Mac's row asks to pair.
check(out(g("pairingRequired"), saved: true) == O(text: "Mac mini now asks devices to pair. Tap it to pair this iPad.", reconnect: false,
                                                  remoteAllowed: false, isNotice: false), "pairingRequired")
check(out(g("pairingRequired", "x", reconnect: true), device: "iPhone") == O(text: "Mac mini now asks devices to pair. Tap it to pair this iPhone.",
                                                                          reconnect: false, remoteAllowed: false, isNotice: false),
      "pairingRequired keeps its rule")
// A reason this build does not know: the Mac's words, a reconnect only when asked.
let later = g("pairAgain", "Pair this iPad with Mac mini again: choose Pair iPhone or iPad… on the Mac.", reconnect: false)
check(out(later, saved: true) == O(text: "Pair this iPad with Mac mini again: choose Pair iPhone or iPad… on the Mac.", reconnect: false, remoteAllowed: true, isNotice: true), "a later reason, reconnect false")
check(out(g("later", "Back soon.", reconnect: true), saved: true) == O(text: "Back soon.", reconnect: true, remoteAllowed: true, isNotice: true), "a later reason, reconnect true")
check(out(g("later", "Back soon.")).reconnect == false, "reconnect nil is false")
check(out(g("later")).text == "Mac mini closed the connection. Tap it to try again.", "no message, no reconnect")
check(out(g("later", reconnect: true)).text == "Mac mini closed the connection. Sill will reconnect when it can.", "no message, reconnect")
check(out(g("")) == O(text: "Mac mini closed the connection. Tap it to try again.", reconnect: false, remoteAllowed: false, isNotice: true), "a kind 22 that did not decode")
check(GoodbyePolicy.isNotice(g("")) && GoodbyePolicy.isNotice(g("Quit")) && GoodbyePolicy.isNotice(later), "notices")
// The host's message, cleaned: one line, no control or bidi characters, at most 300 characters.
check(out(g("x", "Line one\nLine two\u{2028}three\ttab")).text == "Line one Line two three tab", "whitespace becomes one space")
check(out(g("x", "\u{202E}Mac mini\u{202C} says \u{200B}hi\u{0007}")).text == "Mac mini says hi", "bidi, zero-width and control characters go")
check(out(g("x", String(repeating: "a", count: 1000))).text.count == 300, "1,000 characters shown as 300")
check(out(g("x", String(repeating: "é", count: 400))).text.count == 300, "by characters, not bytes")
check(out(g("x", " \n\u{202E}\u{200B} ")).text == "Mac mini closed the connection. Tap it to try again.", "empty after cleaning counts as absent")
check(out(g("x", "")).text == "Mac mini closed the connection. Tap it to try again.", "an empty message counts as absent")
check(out(g("x", "**Update** [here](https://evil.example)")).text == "**Update** [here](https://evil.example)", "kept as plain text (shown verbatim, never as Markdown)")
check(GoodbyePolicy.messageLimit == 300, "the limit")
// "update": the host's words, the App Store link, a reconnect only when asked.
let refusal = g("update", "Update Sill on your iPad to keep using Mac mini. It needs version 1.2 or later.", min: "1.2", reconnect: false)
check(out(refusal, saved: true) == O(text: "Update Sill on your iPad to keep using Mac mini. It needs version 1.2 or later.", reconnect: false,
                                     remoteAllowed: true, storeLink: true, isNotice: true), "update, with its message")
check(GoodbyePolicy.isNotice(refusal), "update is a notice")
check(out(g("update", min: "1.2")).text == "Update Sill on this iPad to keep using Mac mini. It needs version 1.2 or later.", "update without a message")
check(out(g("update", min: "v2.0.0"), device: "iPhone").text == "Update Sill on this iPhone to keep using Mac mini. It needs version 2.0 or later.", "the version as SillVersion shows it")
check(out(g("update", min: "soon")).text == "Update Sill on this iPad to keep using Mac mini.", "a minimumVersion that does not parse is left out")
check(out(g("update")).text == "Update Sill on this iPad to keep using Mac mini.", "no minimumVersion")
check(!out(g("update")).reconnect && !out(g("update", reconnect: false)).reconnect, "update: no reconnect unless asked")
check(out(g("update", reconnect: true), saved: true).reconnect && out(g("update", reconnect: true), saved: true).remoteAllowed, "update with reconnect true (a host bug §3.7 forbids): reconnects")
check(out(g("update", "\u{202E}Update\nnow")).text == "Update now", "update's message cleaned too")
check(out(g("update", " ")).storeLink && out(g("update", " ")).text.hasPrefix("Update Sill on this iPad"), "update, message empty after cleaning")
check(!out(later).storeLink && !out(g("quit")).storeLink && !out(nil).storeLink && !out(g("")).storeLink, "only update links the App Store")
// The Mac went to sleep, or is shutting down or restarting (roadmap, why a session ended): this
// build's words and a reconnect, the remote door allowed for a saved Mac, as after "quit".
check(out(Goodbye.asleep(mac: "Mac mini"), saved: true) == O(text: "Mac mini went to sleep. This iPad reconnects when it wakes.", reconnect: true, remoteAllowed: true, isNotice: true), "sleep, saved")
check(out(Goodbye.asleep(mac: "x"), mac: "Studio", device: "iPhone").text == "Studio went to sleep. This iPhone reconnects when it wakes." && !out(Goodbye.asleep(mac: "x")).remoteAllowed, "sleep: the device's own name for the Mac, an unsaved iPhone")
check(out(Goodbye.shuttingDown(mac: "Mac mini"), saved: true) == O(text: "Mac mini is shutting down, restarting or logging out. This iPad reconnects when it’s back.", reconnect: true, remoteAllowed: true, isNotice: true), "shutdown, saved: macOS says the same for a log out")
// Notices, as "update" is: said whatever the session's state, a remote dial's before its first window
// list included, where the remote rules would read any other goodbye as "refused".
check(GoodbyePolicy.isNotice(g("sleep")) && GoodbyePolicy.isNotice(g("shutdown")), "sleep and shutdown are notices")
check(out(g("sleep", reconnect: false)).reconnect && out(g("shutdown", reconnect: false)).reconnect, "both keep this build's reconnect")
// What a Mac sends: its own words and a reconnect, so a device from before these reasons shows them
// and reconnects (an unknown reason is a notice that follows `reconnect`).
let asleep = Goodbye.asleep(mac: "Mac mini"), down = Goodbye.shuttingDown(mac: "Mac mini")
check(asleep.reason == "sleep" && asleep.reconnect == true && asleep.message == "Mac mini went to sleep. Sill reconnects when it wakes.", "the sleep goodbye's fields")
check(down.reason == "shutdown" && down.reconnect == true && down.message == "Mac mini is shutting down, restarting or logging out. Sill reconnects when it’s back.", "the shutdown goodbye's fields")
check(GoodbyePolicy.message(asleep) == asleep.message, "an older build shows the Mac's message (a notice there too)")
// This device was away (roadmap 4b): Sill went to the background, or the device locked, while
// connected, and the session ended with no goodbye before a pong for a ping sent after the return.
typealias S = GoodbyePolicy.AwaySpell
var spell = GoodbyePolicy.enteredBackground(connected: true, current: nil)
check(spell == S(locked: false, returnedAt: nil, heardSince: false), "entering the background while connected starts a spell")
check(GoodbyePolicy.enteredBackground(connected: false, current: spell) == nil, "not connected: no spell")
spell?.locked = true
check(GoodbyePolicy.enteredBackground(connected: true, current: spell) == S(locked: true, returnedAt: nil, heardSince: false),
      "a second background before the Mac answered keeps locked and clears returnedAt")
spell?.returnedAt = 100
GoodbyePolicy.heardPong(pingSentAt: 99.9, spell: &spell)
check(spell?.heardSince == false, "a pong for a ping sent before the return (buffered) does not clear the spell")
GoodbyePolicy.heardPong(pingSentAt: 100.0, spell: &spell)
check(spell?.heardSince == true, "a pong for a ping sent at or after the return marks the Mac heard")
check(GoodbyePolicy.enteredBackground(connected: true, current: spell) == S(locked: false, returnedAt: nil, heardSince: false),
      "a later background after the session survived starts a fresh spell")
check(GoodbyePolicy.awayEnd(goodbye: nil, spell: S(locked: false, heardSince: false)) == .background, "away: in the background")
check(GoodbyePolicy.awayEnd(goodbye: nil, spell: S(locked: true, heardSince: false)) == .locked, "away: locked")
check(GoodbyePolicy.awayEnd(goodbye: nil, spell: S(locked: true, heardSince: true)) == nil, "the Mac was heard after the return: not away")
check(GoodbyePolicy.awayEnd(goodbye: nil, spell: nil) == nil, "never away: not away")
check(GoodbyePolicy.awayEnd(goodbye: g("quit"), spell: S(locked: true, heardSince: false)) == nil, "a goodbye says why: not away")
check(out(nil, saved: true, away: .locked) == O(text: "The connection to Mac mini ended while this iPad was locked. Sill will reconnect when it can reach it.",
                                                reconnect: true, remoteAllowed: true, isNotice: false), "away locked, saved")
check(out(nil, device: "iPhone", away: .background) == O(text: "The connection to Mac mini ended while Sill was in the background. It will reconnect when the Mac is back.",
                                                          reconnect: true, remoteAllowed: false, isNotice: false), "away in the background, an unsaved iPhone")
check(out(g("quit"), saved: true, away: .locked) == out(g("quit"), saved: true), "a goodbye's words win over away")
check(GoodbyePolicy.awayNote(.locked, device: "iPad") == "(the connection ended while this iPad was locked)", "the reconnect line's note, locked")
check(GoodbyePolicy.awayNote(.background, device: "iPhone") == "(the connection ended while Sill was in the background)", "the note, in the background")
check(GoodbyePolicy.awayNote(nil, device: "iPad") == nil, "no note when not away")
print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
