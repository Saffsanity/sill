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
check(out(Goodbye.shuttingDown(mac: mini), saved: true) == O(text: "Mac mini is shutting down. This iPad reconnects when it’s back.",
                                                             reconnect: true, remoteAllowed: false, isNotice: true, went: .off),
      "shutdown, a saved Mac at home: a shut down the Mac knows (the review of 2026-10-26: one meaning)")
check(out(Goodbye.shuttingDownOrRestarting(mac: mini), saved: true) == O(text: "Mac mini is shutting down or restarting. This iPad reconnects when it’s back.",
                                                                         reconnect: true, remoteAllowed: false, isNotice: true, went: .off),
      "poweroff, a saved Mac at home: worded shutting down or restarting (willPowerOff says neither), the same wait")
check(out(Goodbye.shuttingDown(mac: mini), saved: true).text != out(Goodbye.shuttingDownOrRestarting(mac: mini), saved: true).text,
      "shutdown and poweroff: words of their own")
check(out(Goodbye.shuttingDownOrRestarting(mac: mini), saved: true, remote: true).remoteAllowed
      && !out(Goodbye.shuttingDownOrRestarting(mac: mini), remote: true).remoteAllowed, "poweroff: the remote door for a saved Mac's remote session only")
check(out(Goodbye.shuttingDown(mac: mini), saved: true, remote: true).remoteAllowed && !out(Goodbye.shuttingDown(mac: mini), remote: true).remoteAllowed,
      "shutdown: the remote door for a saved Mac's remote session only")
check(out(Goodbye.restarting(mac: mini), saved: true) == O(text: "Mac mini is restarting. This iPad reconnects when it’s back.", reconnect: true,
                                                           remoteAllowed: false, isNotice: true, went: .off), "restart, a saved Mac at home")
check(out(Goodbye.restarting(mac: mini), saved: true, remote: true).remoteAllowed && !out(Goodbye.restarting(mac: mini), remote: true).remoteAllowed,
      "restart: the remote door for a saved Mac's remote session only")
check(out(Goodbye.restarting(mac: "x"), mac: "Studio", device: "iPhone").text == "Studio is restarting. This iPhone reconnects when it’s back."
      && out(Goodbye.shuttingDown(mac: "x"), mac: "Studio", device: "iPhone").text
          == "Studio is shutting down. This iPhone reconnects when it’s back."
      && out(Goodbye.shuttingDownOrRestarting(mac: "x"), mac: "Studio", device: "iPhone").text
          == "Studio is shutting down or restarting. This iPhone reconnects when it’s back.",
      "shutdown, restart and poweroff: this device's name for the Mac, and its own word")
check(["sleep", "shutdown", "restart", "poweroff"].allSatisfy { GoodbyePolicy.closesAtOnce(g($0)) }, "the Mac's own going: this device closes the connection at once")
check(!["quit", "removed", "remoteOff", "internetOff", "busy", "pairingRequired", "update", "", "later", "Sleep", "powerOff"].contains { GoodbyePolicy.closesAtOnce(g($0)) },
      "every other goodbye: the Mac closes the connection")
for r in ["sleep", "shutdown", "restart", "poweroff"] {
    check(GoodbyePolicy.isNotice(g(r)), "\(r) is a notice")
    check(out(g(r, "x", reconnect: false)).reconnect && out(g(r, "x", reconnect: false), saved: true).isNotice, "\(r): this build's reconnect, whatever the Mac adds")
    check(!out(g(r, "Some other words.")).text.contains("Some other words"), "\(r): this build's words, not the Mac's")
    check(!out(g(r)).storeLink, "\(r): no App Store link")
}

// What the Mac sends (Goodbye.asleep, .shuttingDown, .restarting, .shuttingDownOrRestarting): the reason, a reconnect, and words
// that say what happened in plain words, which a device from before these reasons shows: it reads a
// reason it does not know by its message and follows its reconnect (an older GoodbyePolicy's
// `default`, the same as this build's for a reason it does not know).
let asleep = Goodbye.asleep(mac: "Noah’s MacBook Pro"), down = Goodbye.shuttingDown(mac: "Noah’s MacBook Pro"),
    again = Goodbye.restarting(mac: "Noah’s MacBook Pro"), either = Goodbye.shuttingDownOrRestarting(mac: "Noah’s MacBook Pro")
check(asleep == Goodbye(reason: "sleep", message: "Noah’s MacBook Pro is going to sleep.", reconnect: true), "the sleep goodbye")
check(down == Goodbye(reason: "shutdown", message: "Noah’s MacBook Pro is shutting down.", reconnect: true), "the shutdown goodbye")
check(again == Goodbye(reason: "restart", message: "Noah’s MacBook Pro is restarting.", reconnect: true), "the restart goodbye")
check(either == Goodbye(reason: "poweroff", message: "Noah’s MacBook Pro is shutting down or restarting.", reconnect: true),
      "willPowerOff's goodbye: a reason of its own, poweroff, in the words that say it may be either")
check(Goodbye.sleep == "sleep" && Goodbye.shutdown == "shutdown" && Goodbye.restart == "restart" && Goodbye.poweroff == "poweroff",
      "the reasons on the wire")
for host in [asleep, down, again, either] {
    // An older build: the reason unknown to it, so its default branch: the message, and the reconnect asked for.
    let older = out(Goodbye(reason: "some reason \(host.reason)", message: host.message, reconnect: host.reconnect), saved: true)
    check(older == O(text: host.message!, reconnect: true, remoteAllowed: true, isNotice: true), "an older build: \(host.reason)'s words, and a reconnect")
    check(GoodbyePolicy.message(host) == host.message, "\(host.reason): its message survives the cleaning whole")
    // Additive: the JSON a device from 2026-09-25 on decodes, nil fields left out.
    let json = String(decoding: Wire.encode(host), as: UTF8.self)
    check(Wire.decode(Goodbye.self, from: Data(json.utf8)) == host && !json.contains("minimumVersion"), "\(host.reason): round trip, \(json)")
}

// The host's choice at its end (HostGoodbye.forQuit): the reason macOS gives a quit Apple event
// (kAEQuitReason), held to the SDK's own constants, and whether NSWorkspace's willPowerOff came.
typealias Going = HostGoodbye.Going
let quit = Goodbye(reason: "quit")
check(HostGoodbye.restartReasons == [UInt32(kAERestart), UInt32(kAEShowRestartDialog)], "restart: kAERestart and kAEShowRestartDialog")
check(HostGoodbye.shutdownReasons == [UInt32(kAEShutDown), UInt32(kAEShowShutdownDialog)], "shut down: kAEShutDown and kAEShowShutdownDialog")
check(HostGoodbye.logOutReasons == [UInt32(kAEReallyLogOut), UInt32(kAELogOut)], "log out: kAEReallyLogOut and kAELogOut")
check(HostGoodbye.quitReasonKeyword == UInt32(kAEQuitReason), "the reason's keyword: kAEQuitReason")
for off in [false, true] {
    check(HostGoodbye.forQuit(reason: UInt32(kAERestart), poweringOff: off) == .restart
          && HostGoodbye.forQuit(reason: UInt32(kAEShowRestartDialog), poweringOff: off) == .restart, "a restart's quit says restart (willPowerOff \(off))")
    check(HostGoodbye.forQuit(reason: UInt32(kAEShutDown), poweringOff: off) == .shutDown
          && HostGoodbye.forQuit(reason: UInt32(kAEShowShutdownDialog), poweringOff: off) == .shutDown, "a shut down's quit says shutdown (willPowerOff \(off))")
    check(HostGoodbye.forQuit(reason: UInt32(kAEReallyLogOut), poweringOff: off) == .quit
          && HostGoodbye.forQuit(reason: UInt32(kAELogOut), poweringOff: off) == .quit, "a log out: quit, the Mac stays up (willPowerOff \(off))")
}
check(HostGoodbye.forQuit(reason: nil, poweringOff: false) == .quit && HostGoodbye.forQuit(reason: nil, byMenu: true, poweringOff: false) == .quit,
      "a quit from the menu, or a signal: quit, as before")
check(HostGoodbye.forQuit(reason: nil, poweringOff: true) == .powerOff, "after willPowerOff, a signal or a quit event without a reason: the power-off goodbye, not quit")
check(HostGoodbye.forQuit(reason: nil, byMenu: true, poweringOff: true) == .quit, "after willPowerOff, Sill's own Quit from its menu: quit (a cancelled log out or restart)")
check([0, UInt32(kAEQuitApplication), UInt32(kAEQuitAll), .max].allSatisfy { HostGoodbye.forQuit(reason: $0, poweringOff: false) == .quit },
      "any other reason: quit")
check([0, UInt32(kAEQuitApplication), UInt32(kAEQuitAll), .max].allSatisfy { HostGoodbye.forQuit(reason: $0, poweringOff: true) == .powerOff },
      "any other reason after willPowerOff: the power-off goodbye")
for off in [false, true] {
    check(HostGoodbye.forQuit(reason: UInt32(kAERestart), byMenu: true, poweringOff: off) == .restart
          && HostGoodbye.forQuit(reason: UInt32(kAEShutDown), byMenu: true, poweringOff: off) == .shutDown, "a reason decides whatever ended Sill")
}
// How long willPowerOff counts (HostGoodbye.poweringOff): ten minutes from the last one.
check(HostGoodbye.powerOffStands == 600, "willPowerOff counts ten minutes")
check(!HostGoodbye.poweringOff(since: nil, now: 100), "no willPowerOff: not powering off")
check(HostGoodbye.poweringOff(since: 100, now: 100) && HostGoodbye.poweringOff(since: 100, now: 699.99), "within ten minutes of it: powering off")
check(!HostGoodbye.poweringOff(since: 100, now: 700) && !HostGoodbye.poweringOff(since: 100, now: 1e6), "ten minutes after it (cancelled): not powering off")
check(!HostGoodbye.poweringOff(since: 100, now: 99), "a time before it: not powering off")
// Each choice's goodbye.
check(HostGoodbye.goodbye(.quit, mac: mini) == quit && HostGoodbye.goodbye(.sleep, mac: mini) == Goodbye.asleep(mac: mini)
      && HostGoodbye.goodbye(.shutDown, mac: mini) == Goodbye.shuttingDown(mac: mini) && HostGoodbye.goodbye(.restart, mac: mini) == Goodbye.restarting(mac: mini)
      && HostGoodbye.goodbye(.powerOff, mac: mini) == Goodbye.shuttingDownOrRestarting(mac: mini), "each choice's goodbye")
check(HostGoodbye.goodbye(.shutDown, mac: mini).reason == "shutdown" && HostGoodbye.goodbye(.powerOff, mac: mini).reason == "poweroff"
      && HostGoodbye.goodbye(.restart, mac: mini).reason == "restart" && HostGoodbye.goodbye(.sleep, mac: mini).reason == "sleep",
      "each choice's reason on the wire")
check(String(decoding: Wire.encode(HostGoodbye.goodbye(.quit, mac: mini)), as: UTF8.self) == #"{"reason":"quit"}"#,
      "the quit goodbye's JSON as Macs have sent it since remote access")
// What this build then says for each, and the wait it takes.
func endToEnd(_ reason: UInt32?, off: Bool) -> O { out(HostGoodbye.goodbye(HostGoodbye.forQuit(reason: reason, poweringOff: off), mac: mini)) }
check(endToEnd(UInt32(kAERestart), off: false).text == "Mac mini is restarting. This iPad reconnects when it’s back."
      && endToEnd(UInt32(kAERestart), off: false).went == .off, "restart, end to end: its words and the wait for a fresh listing")
check(endToEnd(nil, off: true).text == "Mac mini is shutting down or restarting. This iPad reconnects when it’s back." && endToEnd(nil, off: true).went == .off,
      "willPowerOff then a SIGTERM, end to end: shutting down or restarting, and the wait")
check(endToEnd(UInt32(kAEShutDown), off: false).went == .off && endToEnd(nil, off: false).went == .quit
      && endToEnd(UInt32(kAELogOut), off: true).went == .quit, "shut down, quit and log out, end to end")
check(endToEnd(UInt32(kAEShutDown), off: true).text == "Mac mini is shutting down. This iPad reconnects when it’s back.",
      "a shut down's quit after willPowerOff, end to end: is shutting down")
// "shutdown" keeps one meaning (the review of 2026-10-26): on every path to Sill's end, the goodbye says
// "shutdown" exactly when a quit's reason said a shut down, and "poweroff" exactly when willPowerOff stands
// and nothing said which (not Sill's own Quit).
var meanings = 0, meaningsWrong = 0
for reason in [nil, 0, UInt32(kAERestart), UInt32(kAEShowRestartDialog), UInt32(kAEShutDown), UInt32(kAEShowShutdownDialog),
               UInt32(kAEReallyLogOut), UInt32(kAELogOut), UInt32(kAEQuitApplication), 0x6162_6364] as [UInt32?] {
    for off in [false, true] { for menu in [false, true] {
        let r = HostGoodbye.goodbye(HostGoodbye.forQuit(reason: reason, byMenu: menu, poweringOff: off), mac: mini).reason
        let shut = reason.map { HostGoodbye.shutdownReasons.contains($0) } ?? false
        let said = reason.map { HostGoodbye.restartReasons.contains($0) || HostGoodbye.shutdownReasons.contains($0) || HostGoodbye.logOutReasons.contains($0) } ?? false
        meanings += 1
        if (r == "shutdown") != shut || (r == "poweroff") != (off && !menu && !said) { meaningsWrong += 1 }
    } }
}
check(meaningsWrong == 0, "shutdown only for a shut down, poweroff only for willPowerOff alone, over \(meanings) paths (\(meaningsWrong) wrong)")
// A quit Apple event's reason (HostGoodbye.quitReason): its parameter (AERegistry.h's word) or its attribute,
// either descriptor type, only in a quit Apple event.
func quitEvent(_ eventID: UInt32 = UInt32(kAEQuitApplication)) -> NSAppleEventDescriptor {
    NSAppleEventDescriptor.appleEvent(withEventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(eventID),
                                      targetDescriptor: NSAppleEventDescriptor.currentProcess(), returnID: AEReturnID(kAutoGenerateReturnID),
                                      transactionID: AETransactionID(kAnyTransactionID))
}
let key = AEKeyword(kAEQuitReason)
check(HostGoodbye.quitReason(in: nil) == nil, "no event (a quit from the menu): no reason")
check(HostGoodbye.quitReason(in: quitEvent()) == nil, "a quit event without a reason: none")
let asAttribute = quitEvent(); asAttribute.setAttribute(NSAppleEventDescriptor(enumCode: OSType(kAERestart)), forKeyword: key)
check(HostGoodbye.quitReason(in: asAttribute) == UInt32(kAERestart), "the reason as an attribute (an enumeration)")
let asParameter = quitEvent(); asParameter.setParam(NSAppleEventDescriptor(enumCode: OSType(kAEShutDown)), forKeyword: key)
check(asParameter.attributeDescriptor(forKeyword: key) == nil && HostGoodbye.quitReason(in: asParameter) == UInt32(kAEShutDown),
      "the reason as a parameter, which no attribute shows")
let asType = quitEvent(); asType.setParam(NSAppleEventDescriptor(typeCode: OSType(kAEReallyLogOut)), forKeyword: key)
check(HostGoodbye.quitReason(in: asType) == UInt32(kAEReallyLogOut), "the reason as a type code")
let both = quitEvent(); both.setParam(NSAppleEventDescriptor(enumCode: OSType(kAERestart)), forKeyword: key)
both.setAttribute(NSAppleEventDescriptor(enumCode: OSType(kAEShutDown)), forKeyword: key)
check(HostGoodbye.quitReason(in: both) == UInt32(kAERestart), "both: the parameter")
let notQuit = quitEvent(UInt32(kAEOpenDocuments)); notQuit.setParam(NSAppleEventDescriptor(enumCode: OSType(kAERestart)), forKeyword: key)
check(HostGoodbye.quitReason(in: notQuit) == nil, "another Apple event's 'why?': not a quit's reason")
let otherClass = NSAppleEventDescriptor.appleEvent(withEventClass: 0x6D69_7363, eventID: AEEventID(kAEQuitApplication),
                                                   targetDescriptor: NSAppleEventDescriptor.currentProcess(), returnID: AEReturnID(kAutoGenerateReturnID),
                                                   transactionID: AETransactionID(kAnyTransactionID))
otherClass.setParam(NSAppleEventDescriptor(enumCode: OSType(kAERestart)), forKeyword: key)
check(HostGoodbye.quitReason(in: otherClass) == nil, "a 'quit' of another event class: not a quit's reason")
let zero = quitEvent(); zero.setParam(NSAppleEventDescriptor(enumCode: 0), forKeyword: key)
check(HostGoodbye.quitReason(in: zero) == nil, "a reason of zero: none")
// The log's lines.
check(HostGoodbye.line(.sleep, devices: 1) == "The Mac is going to sleep: 1 device told."
      && HostGoodbye.line(.sleep, devices: 2) == "The Mac is going to sleep: 2 devices told.", "the sleep's line")
check(HostGoodbye.line(.shutDown, devices: 3) == "The Mac is shutting down: 3 devices told."
      && HostGoodbye.line(.restart, devices: 1) == "The Mac is restarting: 1 device told.", "the shut down's and the restart's lines")
check(HostGoodbye.line(.powerOff, devices: 2) == "The Mac is shutting down or restarting: 2 devices told.", "willPowerOff's goodbye's line")
check([Going.sleep, .shutDown, .restart, .powerOff].allSatisfy { HostGoodbye.line($0, devices: 0) == nil }, "no line when no device was connected")
check(HostGoodbye.line(.quit, devices: 2) == nil, "no line for a quit (its Quit has its own)")
check(HostGoodbye.powerOffLine == "macOS says the Mac is about to log out, restart or shut down.", "willPowerOff's own line")
check(HostGoodbye.quitLine(reason: nil) == nil, "a quit with no reason: no line")
check(HostGoodbye.quitLine(reason: UInt32(kAERestart)) == "Quit: macOS asked Sill to quit for a restart."
      && HostGoodbye.quitLine(reason: UInt32(kAEShutDown)) == "Quit: macOS asked Sill to quit for a shut down."
      && HostGoodbye.quitLine(reason: UInt32(kAEReallyLogOut)) == "Quit: macOS asked Sill to quit for a log out.", "the quit's reason in the log")
check(HostGoodbye.quitLine(reason: 0x7175_6961) == "Quit: macOS asked Sill to quit (reason 'quia')."
      && HostGoodbye.quitLine(reason: 7) == "Quit: macOS asked Sill to quit (reason 7).", "another reason: its four characters, or its number")
// The Mac between its sleep goodbye and its wake (SleepWindow, the verifier's review of 2026-10-26): from
// willSleep until didWake no door admits a session, and one that comes gets the sleep's own goodbye, which
// this build reads as the sleep's (its words and its hold, before a remote dial's failure rules) and an
// older one shows by its words with a reconnect. The window ends at didWake, opens again at a willSleep,
// and lapses ten minutes of awake time after willSleep, so no door stays shut for good.
var sw = SleepWindow()
check(!sw.asleep(at: 0) && !sw.asleep(at: 1e6) && sw.refusal(at: 5, mac: mini) == nil && !sw.lapsed(at: 5) && sw.since == nil,
      "no willSleep: every session admitted")
sw.willSleep(at: 100)
check(sw.since == 100 && sw.asleep(at: 100) && sw.asleep(at: 100.3) && sw.asleep(at: 699.99), "from willSleep: asleep")
check(sw.refusal(at: 100.3, mac: mini) == Goodbye.asleep(mac: mini) && sw.refusal(at: 100.3, mac: mini) == HostGoodbye.goodbye(.sleep, mac: mini),
      "a session 0.3 s after the goodbye gets the sleep goodbye, the one every device heard")
check(Wire.decode(Goodbye.self, from: Wire.encode(sw.refusal(at: 100.3, mac: mini)!))
      == Goodbye(reason: "sleep", message: "Mac mini is going to sleep.", reconnect: true), "the refusal on the wire: the sleep's reason, words and reconnect")
let swHome = out(sw.refusal(at: 100.3, mac: mini), saved: true), swAway = out(sw.refusal(at: 100.3, mac: mini), saved: true, remote: true)
check(swHome == O(text: "Mac mini went to sleep. This iPad reconnects when it wakes.", reconnect: true, remoteAllowed: false, isNotice: true, went: .asleep),
      "this build reads the refusal at home as the sleep: its words, a reconnect, the Mac counted as asleep")
check(swAway.isNotice && swAway.went == .asleep && swAway.remoteAllowed,
      "and on a remote dial before its first window list: a notice (said before the dial's failure rules), the hold, the remote door")
check(GoodbyePolicy.closesAtOnce(sw.refusal(at: 100.3, mac: mini)!), "the device closes its end at once on the refusal")
check(!sw.asleep(at: 700) && sw.lapsed(at: 700) && sw.refusal(at: 700, mac: mini) == nil && sw.lapsed(at: 1e6),
      "ten minutes of awake time without a didWake: lapsed, admitted (no door shut for good)")
check(SleepWindow.limit == 600, "the limit: ten minutes of the Mac's awake time")
check(!sw.asleep(at: 99.9) && sw.lapsed(at: 99.9) && sw.refusal(at: 99.9, mac: mini) == nil, "a clock before willSleep: ended, never a door stuck shut")
var swWoke = sw
swWoke.didWake()
check(swWoke.since == nil && !swWoke.asleep(at: 100.5) && !swWoke.lapsed(at: 100.5) && swWoke.refusal(at: 100.5, mac: mini) == nil,
      "didWake: admitted at once")
var swAgain = sw
swAgain.willSleep(at: 650)
check(swAgain.since == 650 && swAgain.asleep(at: 700) && swAgain.asleep(at: 1249.9) && !swAgain.asleep(at: 1250) && swAgain.lapsed(at: 1250),
      "a willSleep again: the window counts from it")
var swAfterWake = swWoke
swAfterWake.willSleep(at: 2000)
check(swAfterWake.asleep(at: 2000.1) && !swAfterWake.asleep(at: 1999), "a willSleep after a wake: open again")
var swTwice = SleepWindow()
swTwice.didWake()
check(swTwice.since == nil && !swTwice.asleep(at: 5), "a didWake with no willSleep: nothing")
check(SleepWindow.refusedLine(endpoint: "127.0.0.1:50123") == "The Mac is going to sleep: refused a session from 127.0.0.1:50123 with the same goodbye.",
      "the refusal's line")
check(SleepWindow.refusedCountLine(1, source: "10.0.0.5") == "The Mac is going to sleep: refused 1 more session from 10.0.0.5 in the last minute."
      && SleepWindow.refusedCountLine(4, source: "10.0.0.5") == "The Mac is going to sleep: refused 4 more sessions from 10.0.0.5 in the last minute.",
      "the minute's count of the rest")
check(SleepWindow.wokeLine(refused: 0) == "The Mac woke: devices can connect again."
      && SleepWindow.wokeLine(refused: 1) == "The Mac woke: devices can connect again (1 session refused while it slept)."
      && SleepWindow.wokeLine(refused: 3) == "The Mac woke: devices can connect again (3 sessions refused while it slept).", "the wake's line")
check(SleepWindow.lapsedLine == "The Mac said it was going to sleep 10 minutes ago and has not said it woke: devices can connect again.",
      "the lapsed window's line")
// 20,000 random sequences of willSleep, didWake and time passing (backwards now and then), against the rule
// stated here on its own: asleep exactly when the last of willSleep and didWake was a willSleep at t0, and
// 0 <= now - t0 < 600; the refusal exactly then, the sleep's goodbye; lapsed exactly when a willSleep is
// the last and it is not asleep.
var swSeed: UInt64 = 0x51EE_9105
func swNext() -> UInt64 { swSeed &+= 0x9E37_79B9_7F4A_7C15; var z = swSeed; z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9; z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB; return z ^ (z >> 31) }
func swUnit() -> Double { Double(swNext() >> 11) / Double(1 << 53) }
var swDiffer = 0, swSteps = 0, swAsleep = 0, swLapsed = 0
for _ in 0..<20_000 {
    var swRule = SleepWindow(), swT0: Double? = nil, now = swUnit() * 1e6
    for _ in 0..<(2 + Int(swNext() % 30)) {
        let r = swNext() % 100
        if r < 25 { swRule.willSleep(at: now); swT0 = now }
        else if r < 40 { swRule.didWake(); swT0 = nil }
        else if r < 45 { now -= swUnit() * 900 }
        else { now += [swUnit() * 2, swUnit() * 120, swUnit() * 900][Int(swNext() % 3)] }
        let asleep = swT0.map { now >= $0 && now - $0 < 600 } ?? false
        let lapsed = swT0 != nil && !asleep
        swSteps += 1; swAsleep += asleep ? 1 : 0; swLapsed += lapsed ? 1 : 0
        if swRule.asleep(at: now) != asleep || swRule.lapsed(at: now) != lapsed
            || swRule.refusal(at: now, mac: mini) != (asleep ? Goodbye.asleep(mac: mini) : nil) || swRule.since != swT0 {
            swDiffer += 1
        }
    }
}
check(swDiffer == 0 && swAsleep > 1000 && swLapsed > 1000,
      "20,000 random sequences against the rule stated on its own (\(swSteps) steps, \(swAsleep) asleep, \(swLapsed) lapsed, \(swDiffer) differ)")
print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
