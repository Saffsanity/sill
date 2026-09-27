// Pairing at home's rules in the policy check (docs/home-pairing-plan.md §7.2, §7.4–7.7, step 4 of
// its build): the same checks as home-device's step-4 section, as a function main.swift calls after
// its own 286.
import Foundation

func homePolicy() {
    typealias H = DiscoveryPolicy.HomeDial
    let doors: [P.HomeDoor] = [.plain, .pairingRequired, .open]
    let mini = "Mac mini"
    // MARK: Step 4: sessions and pairing at home over TLS (§7.2, §7.5–7.7)

    typealias T = DiscoveryPolicy.HomeTrust
    let k1 = Data(repeating: 0x11, count: 32), k2 = Data(repeating: 0x22, count: 32)

    // The pin of a session's next connection (§7.2).
    check("pin: a plain door's session is plain TCP", P.pin(.plain) == .plainTCP)
    check("pin: a saved Mac's session pins its key", P.pin(.saved(pin: k1)) == .key(k1))
    check("pin: an open door's first connection takes any key", P.pin(.open(seen: nil)) == .anyKey)
    check("pin: every later connection of an open session pins the key the first one saw", P.pin(.open(seen: k2)) == .key(k2))
    check("tls: plain is not TLS; a saved or open session is", !T.plain.tls && T.saved(pin: k1).tls && T.open(seen: nil).tls && T.open(seen: k1).tls)

    // The session a dial starts, over every homeDial answer (§7.4).
    func trustOracle(_ d: H, _ pin: Data?) -> T? {
        switch d {
        case .pinned: return pin.map { T.saved(pin: $0) }
        case .anyKey: return .open(seen: nil)
        case .plain: return .plain
        case .ask, .updateSill, .waitForTap: return nil
        }
    }
    var st = 0, stOK = 0, tlsNeverPlain2 = true, releaseNeverPlain2 = true, asksNoSession = true
    for d in doors { for bits in 0..<32 { for pin in [nil, k1] as [Data?] {
        let b = { (i: Int) in bits & (1 << i) != 0 }
        let dial = P.homeDial(door: d, saved: b(0), revoked: b(1), homeTLS: b(2), debug: b(3), tap: b(4))
        let t = P.sessionTrust(dial, savedPin: pin)
        st += 1
        if t == trustOracle(dial, pin) { stOK += 1 } else { print("  sessionTrust \(dial) \(String(describing: pin)): \(String(describing: t))") }
        if d != .plain, t == .plain { tlsNeverPlain2 = false }
        if !b(3), t == .plain { releaseNeverPlain2 = false }
        if case .ask = dial, t != nil { asksNoSession = false }
        if b(2), t == .plain { tlsNeverPlain2 = false }
    } } }
    check("sessionTrust: \(stOK) of \(st) combinations match §7.4 (pinned → the saved key, any key → open, plain → plain, the rest no session)", st == stOK)
    check("sessionTrust: a door with p, or a Mac seen with it (homeTLS), never gets a plain session", tlsNeverPlain2)
    check("sessionTrust: a Release build never gets a plain session", releaseNeverPlain2)
    check("sessionTrust: an ask starts no session", asksNoSession)
    check("sessionTrust: a saved Mac whose pin cannot be read gets no session (never an unpinned one)", P.sessionTrust(.pinned, savedPin: nil) == nil)
    check("sessionTrust: the saved key exactly", P.sessionTrust(.pinned, savedPin: k2) == .saved(pin: k2))

    // Once the first connection is ready (§7.2).
    check("readyWith: an open session keeps the key its first connection saw", P.trust(.open(seen: nil), readyWith: k1) == .open(seen: k1))
    check("readyWith: never replaced by a later connection's", P.trust(.open(seen: k1), readyWith: k2) == .open(seen: k1))
    check("readyWith: a saved Mac's pin never changes", P.trust(.saved(pin: k1), readyWith: k2) == .saved(pin: k1))
    check("readyWith: plain stays plain", P.trust(.plain, readyWith: k1) == .plain)
    check("readyWith: no key seen, nothing to keep", P.trust(.open(seen: nil), readyWith: nil) == .open(seen: nil))

    // How a session at home ends (§7.6), every combination against the plan's rules.
    typealias E = DiscoveryPolicy.HomeEnd
    let trusts: [T?] = [nil, .plain, .saved(pin: k1), .open(seen: nil), .open(seen: k2)]
    let goodbyes: [String?] = [nil, "removed", "pairingRequired", "quit", "busy", "remoteOff", "internetOff", "somethingNew"]
    let statuses: [Int32?] = [nil, -9825, -9829, -9808, -9806, -9816, -9836, -9858, 0]
    func endOracle(_ t: T?, _ g: String?, _ s: Int32?) -> E {
        guard let t, t != .plain else { return .other }          // a remote session, or a plain door: as before
        if g == "removed" { return .removed }
        if g == "pairingRequired" { return .pairingRequired }
        if g != nil { return .other }                             // quit, busy…: the words as before
        guard let s else { return .other }
        if case .saved = t { return s == -9825 || s == -9829 ? .removed : (s == -9808 ? .wrongKey : .other) }
        return s == -9825 || s == -9829 ? .pairingRequired : .other
    }
    var he = 0, heOK = 0
    for t in trusts { for g in goodbyes { for s in statuses {
        he += 1
        let got = P.homeEnd(trust: t, goodbye: g, tls: s)
        if got == endOracle(t, g, s) { heOK += 1 } else { print("  homeEnd \(String(describing: t)) \(String(describing: g)) \(String(describing: s)): \(got)") }
    } } }
    check("homeEnd: \(heOK) of \(he) combinations match §7.6", he == heOK)
    check("§7.6: goodbye removed ends a saved session as removed (revoked, no reconnect)", P.homeEnd(trust: .saved(pin: k1), goodbye: "removed", tls: nil) == .removed)
    check("§7.6: -9825 and -9829 right after .ready on a pinned home dial: removed", P.homeEnd(trust: .saved(pin: k1), goodbye: nil, tls: -9825) == .removed
          && P.homeEnd(trust: .saved(pin: k1), goodbye: nil, tls: -9829) == .removed)
    check("§7.6: goodbye pairingRequired: pairingRequired, for any TLS session", P.homeEnd(trust: .open(seen: k1), goodbye: "pairingRequired", tls: nil) == .pairingRequired
          && P.homeEnd(trust: .saved(pin: k1), goodbye: "pairingRequired", tls: nil) == .pairingRequired)
    check("§7.6: -9825/-9829 on an unsaved p=0 session: as pairingRequired", P.homeEnd(trust: .open(seen: k1), goodbye: nil, tls: -9825) == .pairingRequired
          && P.homeEnd(trust: .open(seen: nil), goodbye: nil, tls: -9829) == .pairingRequired)
    check("§7.6: -9808 on a pinned home dial: another key as the saved Mac", P.homeEnd(trust: .saved(pin: k1), goodbye: nil, tls: -9808) == .wrongKey)
    check("§7.6: -9808 on an open session is no wrong Mac (it took any key)", P.homeEnd(trust: .open(seen: nil), goodbye: nil, tls: -9808) == .other)
    check("§7.6: a plain door and a remote session end as before", P.homeEnd(trust: .plain, goodbye: "removed", tls: -9825) == .other
          && P.homeEnd(trust: nil, goodbye: "removed", tls: -9825) == .other)
    check("§7.6: goodbye quit at home: the ordinary words and reconnect", P.homeEnd(trust: .saved(pin: k1), goodbye: "quit", tls: -9825) == .other)
    check("keyRefused and pinRefused: -9825, -9829 and -9808", P.keyRefused == [-9825, -9829] && P.pinRefused == -9808)

    // After a pin failure (§7.6): the other rows its tag names, in order, then none.
    let pinRows: [(id: String, macID: String?)] = [("network:A", "M"), ("network:B", nil), ("direct:A", "M"), ("network:C", "N"), ("network:D", "M")]
    check("nextPinnedRow: the first row the tag names", P.nextPinnedRow(macID: "M", tried: [], rows: pinRows) == "network:A")
    check("nextPinnedRow: then the next, leaving out those tried", P.nextPinnedRow(macID: "M", tried: ["network:A"], rows: pinRows) == "direct:A"
          && P.nextPinnedRow(macID: "M", tried: ["network:A", "direct:A"], rows: pinRows) == "network:D")
    check("nextPinnedRow: none left once every row of that Mac was tried", P.nextPinnedRow(macID: "M", tried: ["network:A", "direct:A", "network:D"], rows: pinRows) == nil)
    check("nextPinnedRow: never a row without the tag, nor another Mac's", P.nextPinnedRow(macID: "N", tried: [], rows: pinRows) == "network:C"
          && P.nextPinnedRow(macID: "N", tried: ["network:C"], rows: pinRows) == nil && P.nextPinnedRow(macID: "Z", tried: [], rows: pinRows) == nil)

    // The Mac's answer to the ask (§7.5), every combination: a proof-less ok only for the cable, as asked.
    typealias A = DiscoveryPolicy.AskAnswer
    let reasons: [String?] = [nil, "shown", "openOnMac", "locked", "busy", "closed", "expired", "stopped", "code", "later"]
    func askOracle(ok: Bool, method: String?, proof: Bool, reason: String?, retry: Double?, cable: Bool, id: Bool, rk: Int?) -> A {
        if ok { return method == "cable" && cable && !proof && id && rk == 32 ? .pairedOverCable : .invalid }
        switch reason {
        case "shown": return .shown
        case "openOnMac": return .openOnMac
        case "locked": return .locked
        case "busy": return .busy(min(max(retry ?? 1, 0.2), 10))
        default: return .refused
        }
    }
    var aa = 0, aaOK = 0, proofless = 0
    for ok in [false, true] { for method in [nil, "cable", "qr", "Cable"] as [String?] { for proof in [false, true] { for reason in reasons {
    for retry in [nil, 0.0, 3.0, 99.0] as [Double?] { for cable in [false, true] { for id in [false, true] { for rk in [nil, 31, 32, 33] as [Int?] {
        aa += 1
        let got = P.askAnswer(ok: ok, method: method, hasProof: proof, reason: reason, retryAfter: retry, askedCable: cable, macIDMatches: id, recognitionKeyBytes: rk)
        if got == askOracle(ok: ok, method: method, proof: proof, reason: reason, retry: retry, cable: cable, id: id, rk: rk) { aaOK += 1 }
        else { print("  askAnswer ok=\(ok) \(String(describing: method)) proof=\(proof) \(String(describing: reason)) cable=\(cable) id=\(id) rk=\(String(describing: rk)): \(got)") }
        if got == .pairedOverCable { proofless += 1 }
    } } } } } } } }
    check("askAnswer: \(aaOK) of \(aa) combinations match §7.5", aa == aaOK)
    check("askAnswer: a proof-less ok is taken in exactly one shape of the \(aa) (ok, cable, asked over the cable, no proof, this key's Mac ID, 32 bytes): \(proofless / 40) × 40 retry/reason variants",
          proofless == 40)
    check("askAnswer: an ok to an ask that did not claim the cable is refused (\"Pairing didn't finish…\")",
          P.askAnswer(ok: true, method: "cable", hasProof: false, reason: nil, retryAfter: nil, askedCable: false, macIDMatches: true, recognitionKeyBytes: 32) == .invalid)
    check("askAnswer: another Mac's ID, or no recognition key, is refused", P.askAnswer(ok: true, method: "cable", hasProof: false, reason: nil, retryAfter: nil,
          askedCable: true, macIDMatches: false, recognitionKeyBytes: 32) == .invalid && P.askAnswer(ok: true, method: "cable", hasProof: false, reason: nil,
          retryAfter: nil, askedCable: true, macIDMatches: true, recognitionKeyBytes: nil) == .invalid)
    check("askAnswer: shown, openOnMac, locked", P.askAnswer(ok: false, method: nil, hasProof: false, reason: "shown", retryAfter: nil, askedCable: true, macIDMatches: false, recognitionKeyBytes: nil) == .shown
          && P.askAnswer(ok: false, method: nil, hasProof: false, reason: "openOnMac", retryAfter: nil, askedCable: false, macIDMatches: false, recognitionKeyBytes: nil) == .openOnMac
          && P.askAnswer(ok: false, method: nil, hasProof: false, reason: "locked", retryAfter: nil, askedCable: true, macIDMatches: false, recognitionKeyBytes: nil) == .locked)
    check("askAnswer: busy retries once within 0.2–10 s (1 s without a hint)", P.askAnswer(ok: false, method: nil, hasProof: false, reason: "busy", retryAfter: nil,
          askedCable: false, macIDMatches: false, recognitionKeyBytes: nil) == .busy(1) && P.askAnswer(ok: false, method: nil, hasProof: false, reason: "busy",
          retryAfter: 0, askedCable: false, macIDMatches: false, recognitionKeyBytes: nil) == .busy(0.2) && P.askAnswer(ok: false, method: nil, hasProof: false,
          reason: "busy", retryAfter: 60, askedCable: false, macIDMatches: false, recognitionKeyBytes: nil) == .busy(10))

    // Where a link goes at home (§7.5).
    let linkRowsIn: [(id: String, door: P.HomeDoor)] = [("network:A", .pairingRequired), ("network:B", .plain), ("direct:C", .open), ("network:D", .pairingRequired)]
    check("linkRows: the link names the key the ask saw: the connection the ask reached (nil)", P.linkRows(linkKey: k1, askedKey: k1, askedRow: "network:A", rows: linkRowsIn) == nil)
    check("linkRows: another key: every row with p, in order, not the asked row (its key is another)",
          P.linkRows(linkKey: k2, askedKey: k1, askedRow: "network:A", rows: linkRowsIn) == ["direct:C", "network:D"])
    check("linkRows: no ask: every row with p, in order, plain doors never", P.linkRows(linkKey: k2, askedKey: nil, askedRow: nil, rows: linkRowsIn) == ["network:A", "direct:C", "network:D"])
    check("linkRows: an ask to an address (no row) leaves every row in", P.linkRows(linkKey: k2, askedKey: k1, askedRow: nil, rows: linkRowsIn) == ["network:A", "direct:C", "network:D"])
    check("linkRows: nothing with p listed: none (the link's addresses follow)", P.linkRows(linkKey: k2, askedKey: nil, askedRow: nil, rows: [("network:B", .plain)]) == [])

    // The words (§7.7).
    typealias C = DiscoveryPolicy.HomeCopy
    check("copy: Pairing with Mac mini…, …over the cable…", C.pairing(mac: mini, cable: false) == "Pairing with Mac mini\u{2026}"
          && C.pairing(mac: mini, cable: true) == "Pairing with Mac mini over the cable\u{2026}")
    check("copy: Paired with Mac mini over the cable.", C.pairedOverCable(mac: mini) == "Paired with Mac mini over the cable.")
    check("copy: Mac mini is showing a code. Point this iPad at it.", C.showing(mac: mini, device: "iPad") == "Mac mini is showing a code. Point this iPad at it.")
    check("copy: openOnMac", C.openOnMac(mac: mini) == "Mac mini didn\u{2019}t show a code. On the Mac, choose Pair iPhone or iPad\u{2026} in the Sill menu, then tap Mac mini again.")
    check("copy: locked", C.locked(mac: mini) == "Unlock Mac mini, then tap it again.")
    check("copy: removed", C.removed(mac: mini, device: "iPad") == "Mac mini removed this iPad. Tap it to pair again."
          && C.removed(mac: mini, device: "iPhone") == "Mac mini removed this iPhone. Tap it to pair again.")
    check("copy: pairingRequired", C.pairingRequired(mac: mini, device: "iPad") == "Mac mini now asks devices to pair. Tap it to pair this iPad.")
    check("copy: the home card's errors", C.stopped(mac: mini) == "Mac mini stopped pairing after too many wrong codes. Tap Mac mini for a new code."
          && C.usedOrExpired(mac: mini) == "That code was used or has expired. Tap Mac mini for a new one."
          && C.proofFailed(mac: mini) == "Pairing didn\u{2019}t finish: Mac mini couldn\u{2019}t show it knows the code. Tap it to try again.")
    check("copy: no answer", C.noAnswer(mac: mini) == "Mac mini didn\u{2019}t answer. Check that Sill is open on it, then tap it again.")

}
