// H3 (step 4, device): DiscoveryPolicy's home rules and SavedMacs against StreamProtocol's own
// values (the wire's strings, a real kind 20, a real TXT tag), then pairing at home walked end to end
// through the pure rules, as StreamClient chains them: a Mac's row, a tap, the ask and its answer, the
// record saved, the pinned session, a removal, a new pairing, an older Sill.app, an open door, a
// look-alike. docs/home-pairing-plan.md §7.2–7.7.
import Foundation
var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) { if ok { passes += 1; print("ok   \(name)") } else { fails += 1; print("FAIL \(name)") }; fflush(stdout) }
typealias P = DiscoveryPolicy

// MARK: The literals DiscoveryPolicy spells (it is compiled alone elsewhere) are the wire's

check("homeEnd reads Goodbye's removed and pairingRequired", Goodbye.removed == "removed" && Goodbye.pairingRequired == "pairingRequired"
      && P.homeEnd(trust: .saved(pin: Data([1])), goodbye: Goodbye.removed, tls: nil) == .removed
      && P.homeEnd(trust: .open(seen: nil), goodbye: Goodbye.pairingRequired, tls: nil) == .pairingRequired)
check("homeEnd: every other goodbye the Mac sends is the ordinary end", [Goodbye.quit, Goodbye.busy, Goodbye.remoteOff, Goodbye.internetOff]
      .allSatisfy { P.homeEnd(trust: .saved(pin: Data([1])), goodbye: $0, tls: nil) == .other })
check("askAnswer reads PairResult's reasons and method", PairResult.shown == "shown" && PairResult.openOnMac == "openOnMac" && PairResult.locked == "locked"
      && PairResult.busy == "busy" && PairResult.cable == "cable")
check("askAnswer: closed, expired, stopped and code after an ask are refusals (the Mac's menu)", [PairResult.closed, PairResult.expired, PairResult.stopped, PairResult.code]
      .allSatisfy { P.askAnswer(ok: false, method: nil, hasProof: false, reason: $0, retryAfter: nil, askedCable: true, macIDMatches: true, recognitionKeyBytes: 32) == .refused })
// The TXT record's door, as StreamClient.door(of:) maps it case for case.
func mapped(_ d: HomeDoorTXT.Door) -> P.HomeDoor { switch d { case .plain: return .plain; case .pairingRequired: return .pairingRequired; case .open: return .open } }
check("the door: no p plain, p=1 and any other value pairing required, p=0 open", mapped(HomeDoorTXT.door([:])) == .plain
      && mapped(HomeDoorTXT.door(["p": "1"])) == .pairingRequired && mapped(HomeDoorTXT.door(["p": "0"])) == .open
      && mapped(HomeDoorTXT.door(["p": "yes"])) == .pairingRequired && mapped(HomeDoorTXT.door(["r": "x"])) == .plain)

// MARK: A real kind 20 from the Mac, as the device decodes it

let fpM = Data((0..<32).map { UInt8($0 &* 3) }), fpX = Data((0..<32).map { UInt8(200 &- $0) })
let macM = MacID.make(fingerprint: fpM)
let rkM = Data(repeating: 0x5A, count: 32)
func answer(_ json: String, askedCable: Bool, key: Data) -> P.AskAnswer {
    let r = Wire.decode(PairResult.self, from: Data(json.utf8))!
    return P.askAnswer(ok: r.ok, method: r.method, hasProof: r.proof != nil, reason: r.reason, retryAfter: r.retryAfter, askedCable: askedCable,
                       macIDMatches: r.macID == MacID.make(fingerprint: key), recognitionKeyBytes: r.recognitionKey.flatMap(Base64URL.decode)?.count)
}
let cableOK = "{\"ok\":true,\"method\":\"cable\",\"macID\":\"\(macM)\",\"name\":\"Mac mini\",\"recognitionKey\":\"\(Base64URL.encode(rkM))\"}"
check("kind 20 (§3.1's example): the cable's ok to an ask that claimed the cable, from the key the connection saw: paired",
      answer(cableOK, askedCable: true, key: fpM) == .pairedOverCable)
check("kind 20: the same ok to an ask without the claim: refused (a look-alike on a USB adapter's LAN)", answer(cableOK, askedCable: false, key: fpM) == .invalid)
check("kind 20: the same ok on a connection whose key is another: refused", answer(cableOK, askedCable: true, key: fpX) == .invalid)
let withProof = "{\"ok\":true,\"method\":\"cable\",\"proof\":\"AAAA\",\"macID\":\"\(macM)\",\"recognitionKey\":\"\(Base64URL.encode(rkM))\"}"
check("kind 20: an ok with a proof to an ask (nothing to check it with): refused", answer(withProof, askedCable: true, key: fpM) == .invalid)
let remoteStyle = "{\"ok\":true,\"proof\":\"AAAA\",\"macID\":\"\(macM)\",\"recognitionKey\":\"\(Base64URL.encode(rkM))\"}"
check("kind 20: a proof's ok (no method) to an ask: refused", answer(remoteStyle, askedCable: true, key: fpM) == .invalid)
let shortKey = "{\"ok\":true,\"method\":\"cable\",\"macID\":\"\(macM)\",\"recognitionKey\":\"\(Base64URL.encode(Data(repeating: 1, count: 16)))\"}"
check("kind 20: a 16-byte recognition key: refused", answer(shortKey, askedCable: true, key: fpM) == .invalid)
check("kind 20: {\"ok\":false,\"reason\":\"shown\"}, openOnMac, locked, busy", answer("{\"ok\":false,\"reason\":\"shown\"}", askedCable: false, key: fpM) == .shown
      && answer("{\"ok\":false,\"reason\":\"openOnMac\"}", askedCable: true, key: fpM) == .openOnMac
      && answer("{\"ok\":false,\"reason\":\"locked\"}", askedCable: true, key: fpM) == .locked
      && answer("{\"ok\":false,\"reason\":\"busy\",\"retryAfter\":2}", askedCable: true, key: fpM) == .busy(2))

// MARK: Pairing at home, end to end through the pure rules

var saved: [SavedMac] = []
/// A row of Mac M as recomputeMacs builds it: its tag recognised, its word from what the device knows.
func row(door: P.HomeDoor, method: P.Method?, cable: Bool = false, tag: String?, debug: Bool = true) -> (word: P.RowWord, tap: P.HomeDial, reconnect: P.HomeDial, id: String?) {
    let id = SavedMacs.recognize(tag: tag, in: saved)
    let mac = id.flatMap { i in saved.first { $0.macID == i } }
    let word = P.rowWord(door: door, saved: mac != nil, revoked: mac?.revoked == true, homeTLS: mac?.homeTLS == true, debug: debug, method: method, cable: cable)
    let tap = P.homeDial(door: door, saved: mac != nil, revoked: mac?.revoked == true, homeTLS: mac?.homeTLS == true, debug: debug, tap: true)
    let again = P.homeDial(door: door, saved: mac != nil, revoked: mac?.revoked == true, homeTLS: mac?.homeTLS == true, debug: debug, tap: false)
    return (word, tap, again, id)
}
/// What recomputeMacs remembers: a saved Mac seen with p.
func sawRow(door: P.HomeDoor, tag: String?) {
    if door != .plain, let id = SavedMacs.recognize(tag: tag, in: saved), let next = SavedMacs.seenOverTLS([id], in: saved) { saved = next }
}
let tagM = RecognitionTag.make(recognitionKey: rkM)!
let strangerTag = RecognitionTag.make(recognitionKey: Data(repeating: 0x77, count: 32))!

// 1. Unpaired: the row asks.
var r = row(door: .pairingRequired, method: .wifi, tag: tagM)
check("1 unpaired on Wi-Fi: Not paired; a tap asks with any key; the reconnect waits for a tap", r.word == .notPaired && r.tap == .ask(pinned: false)
      && r.reconnect == .waitForTap && P.sessionTrust(r.tap, savedPin: nil) == nil)
r = row(door: .pairingRequired, method: .wired, cable: true, tag: tagM)
check("1 unpaired on the cable: Wired; a tap asks", r.word == .pairsOverCable && r.word.word == "Wired" && r.tap == .ask(pinned: false))
// 2. The ask over the cable, claimed, answered with the cable's ok: saved (method cable, homeTLS), then a pinned session.
check("2 the Mac's cable ok to the claimed ask: paired", answer(cableOK, askedCable: true, key: fpM) == .pairedOverCable)
saved = SavedMacs.adding(SavedMac(macID: macM, fingerprint: Base64URL.encode(fpM), name: "Mac mini", recognitionKey: Base64URL.encode(rkM),
                                  remotePort: 7455, addresses: [], typedAddresses: nil, infoIssuedAt: 0, bonjourName: "Mac mini", lastWorked: nil,
                                  pairedAt: Date(timeIntervalSince1970: 1_790_000_000), method: PairResult.cable, lastConnectedAt: nil, lastRoute: nil,
                                  homeTLS: true, revoked: nil), to: saved)
r = row(door: .pairingRequired, method: .wired, cable: true, tag: tagM)
check("2 then its row: its tag names the saved Mac, it reads Wired as a method, a tap dials pinned to its key", r.id == macM && r.word == .method(.wired)
      && r.tap == .pinned && P.sessionTrust(r.tap, savedPin: saved[0].fingerprintData) == .saved(pin: fpM))
check("2 the automatic reconnect dials it pinned too", r.reconnect == .pinned)
check("2 every connection of that session (a move, a hop to Wi-Fi) is pinned to the Mac's key", P.pin(.saved(pin: fpM)) == .key(fpM))
// 3. Removed on the Mac: goodbye removed.
check("3 goodbye removed: removed", P.homeEnd(trust: .saved(pin: fpM), goodbye: Goodbye.removed, tls: nil) == .removed)
saved = SavedMacs.revoking(macM, in: saved)!
r = row(door: .pairingRequired, method: .wifi, tag: tagM)
check("3 revoked: Not paired on Wi-Fi; a tap asks pinned to the saved key; no reconnect", r.word == .notPaired && r.tap == .ask(pinned: true) && r.reconnect == .waitForTap)
r = row(door: .pairingRequired, method: .wired, cable: true, tag: tagM)
check("3 revoked, on the cable: Wired (it pairs by itself again)", r.word == .pairsOverCable)
// 4. Paired again with the code: revoked cleared, homeTLS kept.
var again = saved[0]; again.method = PairRequest.code; again.revoked = nil; again.homeTLS = nil; again.pairedAt = Date(timeIntervalSince1970: 1_790_100_000)
saved = SavedMacs.adding(again, to: saved)
r = row(door: .pairingRequired, method: .wifi, tag: tagM)
check("4 paired again: pinned, not revoked, homeTLS kept by the new record", r.tap == .pinned && saved[0].revoked == nil && saved[0].homeTLS == true)
// 5. An older Sill.app on the Mac (no p, same tag): nothing dialed, in DEBUG too; -SillForgetHomeTLS lets DEBUG dial it plain.
r = row(door: .plain, method: .wifi, tag: tagM, debug: true)
check("5 an older Sill.app: Update Sill and nothing dialed, in DEBUG too (no downgrade)", r.word == .updateSill && r.tap == .updateSill && r.reconnect == .updateSill)
saved = SavedMacs.forgettingHomeTLS(saved)
r = row(door: .plain, method: .wifi, tag: tagM, debug: true)
check("5 after -SillForgetHomeTLS 1: DEBUG dials it plain, as before pairing at home", r.tap == .plain && P.sessionTrust(r.tap, savedPin: nil) == .plain)
r = row(door: .plain, method: .wifi, tag: tagM, debug: false)
check("5 a Release build never does", r.tap == .updateSill && r.word == .updateSill)
sawRow(door: .pairingRequired, tag: tagM)
r = row(door: .plain, method: .wifi, tag: tagM, debug: true)
check("5 seen with p once more: homeTLS again, and the plain row is refused again", saved[0].homeTLS == true && r.tap == .updateSill)
// 6. An open door (Require pairing off), another Mac, not saved: any key, then that key for the session.
r = row(door: .open, method: .wifi, tag: strangerTag)
check("6 an open door's unsaved Mac: Not paired (never a paired Mac's word); a tap connects with any key", r.id == nil && r.word == .openDoor
      && r.word.word == "Not paired" && r.tap == .anyKey && P.sessionTrust(r.tap, savedPin: nil) == .open(seen: nil))
let seenTrust = P.trust(.open(seen: nil), readyWith: fpX)
check("6 its moves pin the key the first connection saw", P.pin(seenTrust) == .key(fpX))
check("6 Require pairing turned on: goodbye pairingRequired, or the key refused after a stale record: pairingRequired",
      P.homeEnd(trust: seenTrust, goodbye: Goodbye.pairingRequired, tls: nil) == .pairingRequired && P.homeEnd(trust: seenTrust, goodbye: nil, tls: -9825) == .pairingRequired)
sawRow(door: .open, tag: strangerTag)
check("6 an unsaved Mac's row teaches nothing", saved.count == 1)
// 7. A look-alike replaying M's tag with another key: the pinned dial refuses it (-9808); the other rows of M next; then the words.
check("7 -9808 on the pinned dial: another key as the saved Mac", P.homeEnd(trust: .saved(pin: fpM), goodbye: nil, tls: -9808) == .wrongKey)
let rows: [(id: String, macID: String?)] = [("network:Mac mini", macM), ("network:Mac mini (2)", macM), ("network:Other", nil)]
check("7 the look-alike's row first (it came first), then the real one, then none", P.nextPinnedRow(macID: macM, tried: [], rows: rows) == "network:Mac mini"
      && P.nextPinnedRow(macID: macM, tried: ["network:Mac mini"], rows: rows) == "network:Mac mini (2)"
      && P.nextPinnedRow(macID: macM, tried: ["network:Mac mini", "network:Mac mini (2)"], rows: rows) == nil)
// 8. A link at home: the Mac whose code it is.
check("8 a link naming the key the ask saw: the connection the ask reached", P.linkRows(linkKey: fpM, askedKey: fpM, askedRow: "network:Mac mini", rows: [("network:Mac mini", .pairingRequired)]) == nil)
check("8 a link naming another key after a look-alike answered the ask: the other rows with p, not the look-alike's",
      P.linkRows(linkKey: fpM, askedKey: fpX, askedRow: "network:Look", rows: [("network:Look", .pairingRequired), ("network:Mac mini", .pairingRequired), ("network:Old", .plain)])
      == ["network:Mac mini"])

// 9. A look-alike that takes M's Bonjour name without its tag, on an open door (the security review,
// 2026-09-27): the row is M by its name alone (as the reconnect always took it), dialed pinned to
// M's key, so the stranger's key fails the pin; a tap once dialed it with any key.
let byName = saved.map { (macID: $0.macID, bonjourName: $0.bonjourName) }
let named = P.rowMac(tagged: SavedMacs.recognize(tag: nil, in: saved), carriesTag: false, name: "Mac mini", saved: byName)
check("9 a tagless row under M's Bonjour name is M, by its name alone", named.map { $0.macID == macM && !$0.tagNamed } == true)
let lookMac = named.flatMap { n in saved.first { $0.macID == n.macID } }
let lookTap = P.homeDial(door: .open, saved: lookMac != nil, revoked: lookMac?.revoked == true, homeTLS: lookMac?.homeTLS == true, debug: true, tap: true)
check("9 a tap on it dials M pinned (never any key), as the reconnect does", lookTap == .pinned
      && P.sessionTrust(lookTap, savedPin: lookMac?.fingerprintData) == .saved(pin: fpM))
check("9 the stranger's key fails that pin (-9808): another key as M, never a session", P.homeEnd(trust: .saved(pin: fpM), goodbye: nil, tls: -9808) == .wrongKey)
check("9 without p, M seen over TLS: nothing dialed, in DEBUG too", P.homeDial(door: .plain, saved: true, revoked: false, homeTLS: lookMac?.homeTLS == true,
      debug: true, tap: true) == .updateSill)
check("9 a tagless row under another name is no saved Mac: an open door's reads Not paired", P.rowMac(tagged: nil, carriesTag: false, name: "Office", saved: byName) == nil
      && P.rowWord(door: .open, saved: false, revoked: false, homeTLS: false, debug: true, method: .wifi, cable: false) == .openDoor)

// MARK: The Mac's quiet rule and the device's words, together (the security review, 2026-09-27)

// A device-opened window closes; a later proof hears kind 20's reason (PairingWindow.closedReason);
// the home card shows DiscoveryPolicy.homeRefusal's words for it. Where the close keeps the asker
// quiet (AskLimits.quiets: its next tap gets no new code), the words must send the person to the
// Sill menu on the Mac first; "Tap it for a new one" is for a close that quiets nobody. A reason
// several closes share ("closed": the Mac's Cancel, and a code another device used) takes the words
// of the strictest.
func cardWords(_ reason: String) -> String {
    switch P.homeRefusal(reason: reason, triesLeft: 3) {
    case .wrongCode: return "wrong code"
    case .stopped: return P.HomeCopy.stopped(mac: "Mac mini")
    case .expired: return P.HomeCopy.expired(mac: "Mac mini")
    case .closed: return P.HomeCopy.closed(mac: "Mac mini")
    }
}
let closes: [PairingWindow.CloseReason] = [.used, .expired, .stopped, .cancelled, .withdrawn, .none]
var quietHonest = 0, quietAll = 0
for close in closes { for byThisProof in [true, false] {
    quietAll += 1
    let reason = PairingWindow.closedReason(close, stoppedByThisProof: byThisProof)
    let words = cardWords(reason)
    let menuFirst = words.contains("choose Pair iPhone or iPad\u{2026} in the Sill menu, then tap Mac mini again")
    if AskLimits.quiets(close) ? menuFirst : (menuFirst || words.hasSuffix("for a new one.")) { quietHonest += 1 }
    else { print("  \(close) (\(byThisProof)): \(reason) → \(words)") }
} }
check("every close (\(quietHonest) of \(quietAll)): the card never says a tap alone gets a new code where the Mac keeps the device quiet",
      quietHonest == quietAll)
check("after a window ran out, the card's \"Tap Mac mini for a new one.\" holds: an expiry quiets nobody",
      cardWords(PairingWindow.closedReason(.expired, stoppedByThisProof: false)) == P.HomeCopy.expired(mac: "Mac mini") && !AskLimits.quiets(.expired))
check("the literals homeRefusal reads are the wire's", PairResult.code == "code" && PairResult.stopped == "stopped" && PairResult.expired == "expired")

// MARK: 11. The reconnect meets a door that now asks devices to pair (the security review, 2026-09-27)

// An unsaved Mac on an open door, its session lost without a goodbye (or a DEBUG device's plain
// session with main's Sill.app, which then became this one): GoodbyePolicy's words promise a
// reconnect. Require pairing is on when the row comes back (p=1): the reconnect never asks, so it
// waits for a tap; it ends there with the goodbye's own words, not "…reconnects when it's back".
let lost = GoodbyePolicy.outcome(nil, mac: "Office", device: "iPad", saved: false)
let officeBack = P.homeDial(door: .pairingRequired, saved: false, revoked: false, homeTLS: false, debug: true, tap: false)
check("11 the session lost without a goodbye: its words promise a reconnect", lost.reconnect && lost.text.contains("reconnect"))
check("11 the row back with p=1: the reconnect waits for a tap, and ends with \"now asks devices to pair\"",
      officeBack == .waitForTap && P.reconnectEnd(officeBack, saved: false) == .pairingRequired
      && P.HomeCopy.pairingRequired(mac: "Office", device: "iPad") == "Office now asks devices to pair. Tap it to pair this iPad.")
check("11 the same row, still an open door: the reconnect dials it with any key, and nothing ends",
      P.homeDial(door: .open, saved: false, revoked: false, homeTLS: false, debug: true, tap: false) == .anyKey
      && P.reconnectEnd(.anyKey, saved: false) == nil)

// MARK: 10. A kind 18 replayed on a look-alike's connection (the security review, 2026-09-27)

// Mac M signs its kind 18 (a real signature, SignedMacInfo, with a real key); a look-alike with key X
// replays it on an open door's session. It verifies (M signed it), but the connection's key is X: it
// names nothing, so the session is not M's, M's record is not refreshed or renamed, the panel does
// not say "Paired", and a goodbye "removed" from that session revokes nothing. On M's own
// connection (pinned to M, or an open one that saw M's key) it speaks for M, and so does its goodbye.
if let keyM = RemoteKey.generate(), let idM = RemoteIdentity(privateKey: keyM), let keyX = RemoteKey.generate(),
   let idX = RemoteIdentity(privateKey: keyX),
   let signed = SignedMacInfo.signing(MacInfo(macID: MacID.make(fingerprint: idM.fingerprint), name: "Mac mini", issuedAt: 1_790_000_000,
                                              remoteAccess: true, remotePort: 7455, internet: false, addresses: []), with: keyM),
   let (info, signer) = signed.verified() {
    let fM = idM.fingerprint, fX = idX.fingerprint
    check("10 M's kind 18 verifies, signed by M's key", signer == fM && info.macID == MacID.make(fingerprint: fM))
    check("10 replayed on X's connection it names nothing", !P.macInfoNamesSession(signer: signer, connectionKey: fX))
    check("10 on a plain connection it names nothing", !P.macInfoNamesSession(signer: signer, connectionKey: nil))
    check("10 on M's own connection it speaks for M", P.macInfoNamesSession(signer: signer, connectionKey: fM))
    let lookAlike = P.trust(.open(seen: nil), readyWith: fX)
    check("10 goodbye removed from the look-alike's open session: removed, but M is not revoked",
          P.homeEnd(trust: lookAlike, goodbye: Goodbye.removed, tls: nil) == .removed
          && !P.removalRevokes(remote: false, trust: lookAlike, savedKey: fM))
    check("10 from M's pinned session, or an open one that saw M's key, M is revoked",
          P.removalRevokes(remote: false, trust: .saved(pin: fM), savedKey: fM)
          && P.removalRevokes(remote: false, trust: P.trust(.open(seen: nil), readyWith: fM), savedKey: fM))
} else {
    check("10 two P-256 keys and M's signed kind 18", false)
}

print(fails == 0 ? "ALL PASS (\(passes))" : "\(fails) FAIL, \(passes) pass")
if fails > 0 { exit(1) }
