// Pairing at home's model in the remote-rules check (docs/home-pairing-plan.md §7.2–7.7, step 4 of its
// build): home-model's checks (DiscoveryPolicy and SavedMacs against StreamProtocol's own values,
// pairing at home end to end) and the saved Macs' home fields, as a function main.swift calls after
// its own 64.
import Foundation

func homeRemote() {
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
    let named = P.rowMac(tagged: SavedMacs.recognize(tag: nil, in: saved), name: "Mac mini", saved: byName)
    check("9 a tagless row under M's Bonjour name is M, by its name alone", named.map { $0.macID == macM && !$0.tagNamed } == true)
    let lookMac = named.flatMap { n in saved.first { $0.macID == n.macID } }
    let lookTap = P.homeDial(door: .open, saved: lookMac != nil, revoked: lookMac?.revoked == true, homeTLS: lookMac?.homeTLS == true, debug: true, tap: true)
    check("9 a tap on it dials M pinned (never any key), as the reconnect does", lookTap == .pinned
          && P.sessionTrust(lookTap, savedPin: lookMac?.fingerprintData) == .saved(pin: fpM))
    check("9 the stranger's key fails that pin (-9808): another key as M, never a session", P.homeEnd(trust: .saved(pin: fpM), goodbye: nil, tls: -9808) == .wrongKey)
    check("9 without p, M seen over TLS: nothing dialed, in DEBUG too", P.homeDial(door: .plain, saved: true, revoked: false, homeTLS: lookMac?.homeTLS == true,
          debug: true, tap: true) == .updateSill)
    check("9 a tagless row under another name is no saved Mac: an open door's reads Not paired", P.rowMac(tagged: nil, name: "Office", saved: byName) == nil
          && P.rowWord(door: .open, saved: false, revoked: false, homeTLS: false, debug: true, method: .wifi, cable: false) == .openDoor)


    // MARK: The saved Macs' home fields
    let fpA2 = Data((0..<32).map { UInt8($0 &+ 9) }), fpB2 = Data((0..<32).map { UInt8($0 &+ 77) })
    func rec(_ fp: Data, tls: Bool? = nil, revoked: Bool? = nil) -> SavedMac {
        SavedMac(macID: MacID.make(fingerprint: fp), fingerprint: Base64URL.encode(fp), name: "M", recognitionKey: Base64URL.encode(Data(repeating: 3, count: 32)),
                 remotePort: 7455, addresses: [], typedAddresses: nil, infoIssuedAt: 0, bonjourName: nil, lastWorked: nil,
                 pairedAt: Date(timeIntervalSince1970: 1_790_000_000), method: "qr", lastConnectedAt: nil, lastRoute: nil, homeTLS: tls, revoked: revoked)
    }
    let two = [rec(fpA2), rec(fpB2)]
    let idA = MacID.make(fingerprint: fpA2), idB = MacID.make(fingerprint: fpB2)
    check("seenOverTLS: marks only the Macs named, nil when nothing changes", SavedMacs.seenOverTLS([idA], in: two)?.map { $0.homeTLS } == [true, nil]
          && SavedMacs.seenOverTLS([idA], in: [rec(fpA2, tls: true)]) == nil && SavedMacs.seenOverTLS([], in: two) == nil)
    check("revoking: marks only that Mac, nil when not saved or already revoked", SavedMacs.revoking(idB, in: two)?.map { $0.revoked } == [nil, true]
          && SavedMacs.revoking("NOTSAVED00000000", in: two) == nil && SavedMacs.revoking(idA, in: [rec(fpA2, revoked: true)]) == nil)
    check("forgettingHomeTLS: every homeTLS gone, nothing else", SavedMacs.forgettingHomeTLS([rec(fpA2, tls: true, revoked: true), rec(fpB2, tls: true)])
          .map { "\($0.homeTLS as Any)|\($0.revoked as Any)" } == ["nil|Optional(true)", "nil|nil"])
    check("a revoked record and its homeTLS survive the round trip; a new pairing clears revoked and keeps homeTLS",
          SavedMacs.decode(SavedMacs.encode([rec(fpA2, tls: true, revoked: true)])).first.map { $0.homeTLS == true && $0.revoked == true } == true
          && SavedMacs.adding(rec(fpA2), to: [rec(fpA2, tls: true, revoked: true)]).first.map { $0.homeTLS == true && $0.revoked == nil } == true)
}
