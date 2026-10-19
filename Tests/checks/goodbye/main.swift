import Foundation
import CoreServices
// H3 (GoodbyePolicy): every row of the plan's §7.3 table, the cleaning of a host's message, and the
// reconnect rule; then the Mac's own going (issue #105): the goodbye the host chooses as it or the Mac
// goes (Sources/SillHost/HostGoodbye.swift, its quit reasons against the SDK's), the words each says
// for a device from before it, and how this build reads it. Compiled with Sources/StreamProtocol,
// iOSClient/GoodbyePolicy.swift and Sources/SillHost/HostGoodbye.swift (their `import StreamProtocol`
// dropped, `-package-name sill`).
var failures = 0, checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
typealias O = GoodbyePolicy.Outcome
func out(_ g: Goodbye?, saved: Bool = false, mac: String = "Mac mini", device: String = "iPad", remote: Bool = false) -> O {
    GoodbyePolicy.outcome(g, mac: mac, device: device, saved: saved, remote: remote)
}
func g(_ reason: String, _ message: String? = nil, min: String? = nil, reconnect: Bool? = nil) -> Goodbye {
    Goodbye(reason: reason, message: message, minimumVersion: min, reconnect: reconnect)
}

// No goodbye: the connection just ended.
check(out(nil, saved: true) == O(text: "Mac mini disconnected. Sill will reconnect when it can reach it.", reconnect: true, remoteAllowed: true, isNotice: false), "none, saved")
check(out(nil) == O(text: "Mac mini disconnected. It will reconnect when the Mac is back.", reconnect: true, remoteAllowed: false, isNotice: false), "none, unsaved")
// Today's five, their words and reconnects unchanged.
check(out(g("quit"), saved: true) == O(text: "Mac mini quit Sill. This iPad reconnects when it’s back.", reconnect: true, remoteAllowed: true, isNotice: false,
                                     went: .quit), "quit, saved: its row left alone for quitWait (went)")
check(out(g("quit"), saved: true, remote: true) == out(g("quit"), saved: true), "quit: the same through the remote door")
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
// Only "quit" and the Mac's own going say how the Mac went: every other end leaves the reconnect's
// waits as they were.
for r in ["removed", "remoteOff", "internetOff", "busy", "pairingRequired", "update", "pairAgain", ""] {
    check(out(g(r, "x", reconnect: true), saved: true).went == nil, "\(r.isEmpty ? "unreadable" : r): no went")
}
check(out(nil, saved: true).went == nil, "no goodbye: no went")

// The Mac's own going (issue #105): this build's words, notices (said whatever the session's state, a
// remote dial's before its first window list too, where RemoteDialPolicy would read them as "refused"),
// always a reconnect, which waits as `went` says (DiscoveryPolicy), and the remote door only for a
// session that came through it, as before for a saved Mac (at home, a remote dial would only replace
// the words while the Mac is asleep or down; its row brings it back).
let mini = "Mac mini"
check(out(Goodbye.asleep(mac: mini), saved: true) == O(text: "Mac mini went to sleep. This iPad reconnects when it wakes.", reconnect: true,
                                                       remoteAllowed: false, isNotice: true, went: .asleep), "sleep, a saved Mac at home")
check(out(Goodbye.asleep(mac: mini), saved: true, remote: true) == O(text: "Mac mini went to sleep. This iPad reconnects when it wakes.", reconnect: true,
                                                                     remoteAllowed: true, isNotice: true, went: .asleep), "sleep, through the remote door")
check(!out(Goodbye.asleep(mac: mini), remote: true).remoteAllowed, "sleep: an unsaved Mac is never dialled remotely")
check(out(Goodbye.asleep(mac: "x"), mac: "Studio", device: "iPhone").text == "Studio went to sleep. This iPhone reconnects when it wakes.",
      "sleep: this device's name for the Mac, and its own word")
check(out(Goodbye.shuttingDown(mac: mini), saved: true) == O(text: "Mac mini is shutting down. This iPad reconnects when it’s back.", reconnect: true,
                                                             remoteAllowed: false, isNotice: true, went: .off), "shutdown, a saved Mac at home")
check(out(Goodbye.shuttingDown(mac: mini), saved: true, remote: true).remoteAllowed && !out(Goodbye.shuttingDown(mac: mini), remote: true).remoteAllowed,
      "shutdown: the remote door for a saved Mac's remote session only")
check(out(Goodbye.restarting(mac: mini), saved: true) == O(text: "Mac mini is restarting. This iPad reconnects when it’s back.", reconnect: true,
                                                           remoteAllowed: false, isNotice: true, went: .off), "restart, a saved Mac at home")
check(out(Goodbye.restarting(mac: mini), saved: true, remote: true).remoteAllowed && !out(Goodbye.restarting(mac: mini), remote: true).remoteAllowed,
      "restart: the remote door for a saved Mac's remote session only")
check(out(Goodbye.restarting(mac: "x"), mac: "Studio", device: "iPhone").text == "Studio is restarting. This iPhone reconnects when it’s back."
      && out(Goodbye.shuttingDown(mac: "x"), mac: "Studio", device: "iPhone").text == "Studio is shutting down. This iPhone reconnects when it’s back.",
      "shutdown and restart: this device's name for the Mac, and its own word")
for r in ["sleep", "shutdown", "restart"] {
    check(GoodbyePolicy.isNotice(g(r)), "\(r) is a notice")
    check(out(g(r, "x", reconnect: false)).reconnect && out(g(r, "x", reconnect: false), saved: true).isNotice, "\(r): this build's reconnect, whatever the Mac adds")
    check(!out(g(r, "Some other words.")).text.contains("Some other words"), "\(r): this build's words, not the Mac's")
    check(!out(g(r)).storeLink, "\(r): no App Store link")
}

// What the Mac sends (Goodbye.asleep, .shuttingDown, .restarting): the reason, a reconnect, and words
// that say what happened in plain words, which a device from before these reasons shows: it reads a
// reason it does not know by its message and follows its reconnect (an older GoodbyePolicy's
// `default`, the same as this build's for a reason it does not know).
let asleep = Goodbye.asleep(mac: "Noah’s MacBook Pro"), down = Goodbye.shuttingDown(mac: "Noah’s MacBook Pro"),
    again = Goodbye.restarting(mac: "Noah’s MacBook Pro")
check(asleep == Goodbye(reason: "sleep", message: "Noah’s MacBook Pro is going to sleep.", reconnect: true), "the sleep goodbye")
check(down == Goodbye(reason: "shutdown", message: "Noah’s MacBook Pro is shutting down.", reconnect: true), "the shutdown goodbye")
check(again == Goodbye(reason: "restart", message: "Noah’s MacBook Pro is restarting.", reconnect: true), "the restart goodbye")
check(Goodbye.sleep == "sleep" && Goodbye.shutdown == "shutdown" && Goodbye.restart == "restart", "the reasons on the wire")
for host in [asleep, down, again] {
    // An older build: the reason unknown to it, so its default branch: the message, and the reconnect asked for.
    let older = out(Goodbye(reason: "some reason \(host.reason)", message: host.message, reconnect: host.reconnect), saved: true)
    check(older == O(text: host.message!, reconnect: true, remoteAllowed: true, isNotice: true), "an older build: \(host.reason)'s words, and a reconnect")
    check(GoodbyePolicy.message(host) == host.message, "\(host.reason): its message survives the cleaning whole")
    // Additive: the JSON a device from 2026-09-25 on decodes, nil fields left out.
    let json = String(decoding: Wire.encode(host), as: UTF8.self)
    check(Wire.decode(Goodbye.self, from: Data(json.utf8)) == host && !json.contains("minimumVersion"), "\(host.reason): round trip, \(json)")
}

// The host's choice at a Quit (HostGoodbye.forQuit): the reason macOS gives the quit Apple event
// (kAEQuitReason), held to the SDK's own constants.
check(HostGoodbye.restartReasons == [UInt32(kAERestart), UInt32(kAEShowRestartDialog)], "restart: kAERestart and kAEShowRestartDialog")
check(HostGoodbye.shutdownReasons == [UInt32(kAEShutDown), UInt32(kAEShowShutdownDialog)], "shut down: kAEShutDown and kAEShowShutdownDialog")
check(HostGoodbye.logOutReasons == [UInt32(kAEReallyLogOut), UInt32(kAELogOut)], "log out: kAEReallyLogOut and kAELogOut")
check(HostGoodbye.forQuit(reason: UInt32(kAERestart), mac: mini) == Goodbye.restarting(mac: mini)
      && HostGoodbye.forQuit(reason: UInt32(kAEShowRestartDialog), mac: mini) == Goodbye.restarting(mac: mini), "a restart's quit says restart")
check(HostGoodbye.forQuit(reason: UInt32(kAEShutDown), mac: mini) == Goodbye.shuttingDown(mac: mini)
      && HostGoodbye.forQuit(reason: UInt32(kAEShowShutdownDialog), mac: mini) == Goodbye.shuttingDown(mac: mini), "a shut down's quit says shutdown")
let quit = Goodbye(reason: "quit")
check(HostGoodbye.forQuit(reason: nil, mac: mini) == quit, "a quit from the menu, or a signal: quit, byte for byte as before")
check(HostGoodbye.forQuit(reason: UInt32(kAEReallyLogOut), mac: mini) == quit && HostGoodbye.forQuit(reason: UInt32(kAELogOut), mac: mini) == quit,
      "a log out: quit (the Mac stays up)")
check([0, UInt32(kAEQuitApplication), 0x7175_6961, .max].allSatisfy { HostGoodbye.forQuit(reason: $0, mac: mini) == quit }, "any other reason: quit")
check(String(decoding: Wire.encode(HostGoodbye.forQuit(reason: nil, mac: mini)), as: UTF8.self) == #"{"reason":"quit"}"#,
      "the quit goodbye's JSON as Macs have sent it since remote access")
// What this build then says for each, and the wait it takes.
check(out(HostGoodbye.forQuit(reason: UInt32(kAERestart), mac: mini)).text == "Mac mini is restarting. This iPad reconnects when it’s back."
      && out(HostGoodbye.forQuit(reason: UInt32(kAERestart), mac: mini)).went == .off, "restart, end to end: its words and the wait for a fresh listing")
check(out(HostGoodbye.forQuit(reason: UInt32(kAEShutDown), mac: mini)).went == .off && out(HostGoodbye.forQuit(reason: nil, mac: mini)).went == .quit
      && out(HostGoodbye.forQuit(reason: UInt32(kAELogOut), mac: mini)).went == .quit, "shut down and quit, end to end")
// The log's lines.
check(HostGoodbye.line(asleep, devices: 1) == "The Mac is going to sleep: 1 device told."
      && HostGoodbye.line(asleep, devices: 2) == "The Mac is going to sleep: 2 devices told.", "the sleep's line")
check(HostGoodbye.line(down, devices: 3) == "The Mac is shutting down: 3 devices told."
      && HostGoodbye.line(again, devices: 1) == "The Mac is restarting: 1 device told.", "the shut down's and the restart's lines")
check(HostGoodbye.line(asleep, devices: 0) == nil && HostGoodbye.line(again, devices: 0) == nil, "no line when no device was connected")
check(HostGoodbye.line(quit, devices: 2) == nil && HostGoodbye.line(g("removed"), devices: 1) == nil, "no line for a quit (its Quit has its own), nor any other")
check(HostGoodbye.quitLine(reason: nil) == nil, "a quit with no reason: no line")
check(HostGoodbye.quitLine(reason: UInt32(kAERestart)) == "Quit: macOS asked Sill to quit for a restart."
      && HostGoodbye.quitLine(reason: UInt32(kAEShutDown)) == "Quit: macOS asked Sill to quit for a shut down."
      && HostGoodbye.quitLine(reason: UInt32(kAEReallyLogOut)) == "Quit: macOS asked Sill to quit for a log out.", "the quit's reason in the log")
check(HostGoodbye.quitLine(reason: 0x7175_6961) == "Quit: macOS asked Sill to quit (reason 'quia')."
      && HostGoodbye.quitLine(reason: 7) == "Quit: macOS asked Sill to quit (reason 7).", "another reason: its four characters, or its number")
print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
