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
func out(_ g: Goodbye?, saved: Bool = false, mac: String = "Mac mini", device: String = "iPad") -> O {
    GoodbyePolicy.outcome(g, mac: mac, device: device, saved: saved)
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
for r in ["quit", "removed", "remoteOff", "internetOff", "busy"] { check(!GoodbyePolicy.isNotice(g(r)), "\(r) is not a notice") }
// A reason this build does not know: the Mac's words, a reconnect only when asked.
let later = g("pairingRequired", "Pair this iPad with Mac mini again: choose Pair iPhone or iPad… on the Mac.", reconnect: false)
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
print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
