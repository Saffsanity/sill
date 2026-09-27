// H3 (steps 1 and 4, device): DiscoveryPolicy's home rules, compiled on their own (Foundation only):
// every row of docs/home-pairing-plan.md §7.3 (rowWord) and §7.4 (homeDial), DEBUG and Release,
// homeTLS, revoked; the device's cable check (§7.5); the rows' VoiceOver labels and hints (S7).
import Foundation
var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) { if ok { passes += 1; print("ok   \(name)") } else { fails += 1; print("FAIL \(name)") }; fflush(stdout) }
typealias P = DiscoveryPolicy
typealias W = DiscoveryPolicy.RowWord
typealias H = DiscoveryPolicy.HomeDial
let doors: [P.HomeDoor] = [.plain, .pairingRequired, .open]
let mini = "Mac mini"
let methods: [P.Method?] = [nil, .wired, .wifi, .direct]

// MARK: §7.3, every combination against the table

func wordOracle(_ door: P.HomeDoor, saved: Bool, revoked: Bool, homeTLS: Bool, debug: Bool, method: P.Method?, cable: Bool) -> W {
    if door == .plain { return debug && !homeTLS ? .method(method) : .updateSill }        // the last two rows
    if saved && !revoked { return .method(method) }                                      // a saved Mac on a TLS door
    if !saved && door == .open { return .openDoor }                                      // unsaved, p=0: Not paired (the review)
    return method == .wired && cable ? .pairsOverCable : .notPaired                      // unsaved or revoked, p=1 (or revoked, p=0)
}
var rw = 0, rwOK = 0
for d in doors { for bits in 0..<32 { for m in methods {
    let b = { (i: Int) in bits & (1 << i) != 0 }
    rw += 1
    let got = P.rowWord(door: d, saved: b(0), revoked: b(1), homeTLS: b(2), debug: b(3), method: m, cable: b(4))
    if got == wordOracle(d, saved: b(0), revoked: b(1), homeTLS: b(2), debug: b(3), method: m, cable: b(4)) { rwOK += 1 }
    else { print("  rowWord \(d) \(bits) \(String(describing: m)): \(got)") }
} } }
check("rowWord: \(rwOK) of \(rw) combinations match §7.3", rw == rwOK)

func word(_ d: P.HomeDoor, saved: Bool = false, revoked: Bool = false, homeTLS: Bool = false, debug: Bool = false, _ m: P.Method? = .wifi, cable: Bool = false) -> W {
    P.rowWord(door: d, saved: saved, revoked: revoked, homeTLS: homeTLS, debug: debug, method: m, cable: cable)
}
for m in [P.Method.wired, .wifi, .direct] {
    check("§7.3: a saved Mac, not revoked, on a TLS door (p=1 and p=0) says \(m.word)", word(.pairingRequired, saved: true, homeTLS: true, m) == .method(m)
          && word(.open, saved: true, m) == .method(m) && word(.pairingRequired, saved: true, m).word == m.word)
}
check("§7.3: unsaved, p=1, not over a cable: Not paired", word(.pairingRequired, .wifi).word == "Not paired" && word(.pairingRequired, .direct).word == "Not paired"
      && word(.pairingRequired, nil).word == "Not paired")
check("§7.3: unsaved, p=1, Wired over a cable: Wired", word(.pairingRequired, .wired, cable: true) == .pairsOverCable
      && word(.pairingRequired, .wired, cable: true).word == "Wired")
check("§7.3: a Wired row through a USB Ethernet adapter on the LAN (not only link-local): Not paired", word(.pairingRequired, .wired, cable: false) == .notPaired)
check("§7.3: the cable counts only for a row that says Wired", word(.pairingRequired, .wifi, cable: true) == .notPaired
      && word(.pairingRequired, .direct, cable: true) == .notPaired && word(.pairingRequired, nil, cable: true) == .notPaired)
check("§7.3: revoked, p=1: Not paired, and Wired over the cable", word(.pairingRequired, saved: true, revoked: true, homeTLS: true, .wifi) == .notPaired
      && word(.pairingRequired, saved: true, revoked: true, homeTLS: true, .wired, cable: true) == .pairsOverCable)
check("§7.3 (§7.6): revoked on an open door (p=0) also reads Not paired: a tap asks", word(.open, saved: true, revoked: true, .wifi) == .notPaired)
check("§7.3: unsaved, p=0: Not paired, over Wi-Fi, the cable or nothing said (the security review: it read as a paired Mac's)",
      word(.open, .wifi) == .openDoor && word(.open, .wired, cable: true) == .openDoor && word(.open, nil) == .openDoor
      && word(.open, .direct).word == "Not paired")
var neverLikePaired = true
for m in methods { for c in [false, true] { for tls in [false, true] {
    let unsaved = P.rowWord(door: .open, saved: false, revoked: false, homeTLS: tls, debug: true, method: m, cable: c)
    for d in [P.HomeDoor.open, .pairingRequired] {
        let paired = P.rowWord(door: d, saved: true, revoked: false, homeTLS: tls, debug: true, method: m, cable: c)
        if unsaved == paired || (unsaved.word == paired.word && unsaved.word != nil) || unsaved.label(name: mini) == paired.label(name: mini) { neverLikePaired = false }
    }
} } }
check("§7.3: an unsaved open door's row never reads like a paired Mac's, in its word or its VoiceOver label", neverLikePaired)
check("§7.3: no p, DEBUG, not homeTLS: its method (a plain door, as today)", word(.plain, debug: true, .wired) == .method(.wired)
      && word(.plain, saved: true, debug: true, .wifi) == .method(.wifi) && word(.plain, debug: true, nil).word == nil)
check("§7.3: no p, Release: Update Sill, saved or not", word(.plain, .wifi) == .updateSill && word(.plain, saved: true, .wifi) == .updateSill
      && word(.plain, .wifi).word == "Update Sill")
check("§7.3: no p and homeTLS: Update Sill, in DEBUG too (no downgrade)", word(.plain, saved: true, homeTLS: true, debug: true, .wifi) == .updateSill
      && word(.plain, saved: true, revoked: true, homeTLS: true, debug: true, .wired, cable: true) == .updateSill)
check("§7.3: every homeTLS combination without p reads Update Sill", (0..<16).allSatisfy { bits in
    methods.allSatisfy { m in P.rowWord(door: .plain, saved: bits & 1 != 0, revoked: bits & 2 != 0, homeTLS: true, debug: bits & 4 != 0,
                                        method: m, cable: bits & 8 != 0) == .updateSill } })

// Words, labels and hints (VoiceOver, S7).
check("words: Not paired, Wired, Update Sill, and the method's own (Wi-Fi with a non-breaking hyphen)",
      W.notPaired.word == "Not paired" && W.pairsOverCable.word == "Wired" && W.updateSill.word == "Update Sill"
      && W.method(.wifi).word == "Wi\u{2011}Fi" && W.method(.direct).word == "Direct" && W.method(nil).word == nil)
check("label: \"Mac mini, not paired\"", W.notPaired.label(name: mini) == "Mac mini, not paired")
check("an open door's row: \"Not paired\", \"Mac mini, not paired\", hint \"Connects without pairing: Mac mini lets any device in.\"",
      W.openDoor.word == "Not paired" && W.openDoor.label(name: mini) == "Mac mini, not paired"
      && W.openDoor.hint(name: mini, device: "iPad", direct: false) == "Connects without pairing: Mac mini lets any device in."
      && W.openDoor.hint(name: mini, device: "iPad", direct: true) == "Connects without pairing: Mac mini lets any device in.")
check("label: \"Mac mini, Wired\" over the cable", W.pairsOverCable.label(name: mini) == "Mac mini, Wired")
check("label: as today for a method (\"Mac mini, Wi‑Fi\"), and the name alone without one",
      W.method(.wifi).label(name: mini) == "Mac mini, Wi\u{2011}Fi" && W.method(nil).label(name: mini) == "Mac mini")
check("label: \"Mac mini, Update Sill\"", W.updateSill.label(name: mini) == "Mac mini, Update Sill")
check("hint: Not paired: \"Pairs with a code Mac mini shows, then connects.\"",
      W.notPaired.hint(name: mini, device: "iPad", direct: false) == "Pairs with a code Mac mini shows, then connects.")
check("hint: over the cable: \"Pairs over the USB cable, then connects.\"",
      W.pairsOverCable.hint(name: mini, device: "iPad", direct: false) == "Pairs over the USB cable, then connects.")
check("hint: Update Sill: \"Mac mini’s Sill is too old for this iPad.\" (a typographic apostrophe; the device's kind)",
      W.updateSill.hint(name: mini, device: "iPad", direct: false) == "Mac mini\u{2019}s Sill is too old for this iPad."
      && W.updateSill.hint(name: mini, device: "iPhone", direct: false) == "Mac mini\u{2019}s Sill is too old for this iPhone.")
check("hint: a method row keeps today's (Direct: \"Connects without a shared Wi‑Fi network\", else none)",
      W.method(.direct).hint(name: mini, device: "iPad", direct: true) == "Connects without a shared Wi\u{2011}Fi network"
      && W.method(.wifi).hint(name: mini, device: "iPad", direct: false) == "")
check("status: \"Mac mini runs an older Sill. Update Sill on the Mac to connect.\"",
      P.updateSillStatus(mac: mini) == "Mac mini runs an older Sill. Update Sill on the Mac to connect.")

// MARK: §7.4, every combination against the table

func dialOracle(_ door: P.HomeDoor, saved: Bool, revoked: Bool, homeTLS: Bool, debug: Bool, tap: Bool) -> H {
    if door == .plain { return debug && !homeTLS ? .plain : .updateSill }
    if saved && !revoked { return .pinned }
    if saved && revoked { return tap ? .ask(pinned: true) : .waitForTap }
    if door == .open { return .anyKey }
    return tap ? .ask(pinned: false) : .waitForTap
}
var hd = 0, hdOK = 0
for d in doors { for bits in 0..<32 {
    let b = { (i: Int) in bits & (1 << i) != 0 }
    hd += 1
    let got = P.homeDial(door: d, saved: b(0), revoked: b(1), homeTLS: b(2), debug: b(3), tap: b(4))
    if got == dialOracle(d, saved: b(0), revoked: b(1), homeTLS: b(2), debug: b(3), tap: b(4)) { hdOK += 1 } else { print("  homeDial \(d) \(bits): \(got)") }
} }
check("homeDial: \(hdOK) of \(hd) combinations match §7.4", hd == hdOK)
func dial(_ d: P.HomeDoor, saved: Bool = false, revoked: Bool = false, homeTLS: Bool = false, debug: Bool = false, tap: Bool = true) -> H {
    P.homeDial(door: d, saved: saved, revoked: revoked, homeTLS: homeTLS, debug: debug, tap: tap)
}
check("§7.4: saved, not revoked, TLS door: sill/1 pinned (p=1 and p=0)", dial(.pairingRequired, saved: true) == .pinned && dial(.open, saved: true) == .pinned)
check("§7.4: saved and revoked: the ask, pinned to the saved key (p=1 and p=0)", dial(.pairingRequired, saved: true, revoked: true) == .ask(pinned: true)
      && dial(.open, saved: true, revoked: true) == .ask(pinned: true))
check("§7.4: unsaved with p=1: the ask, any key", dial(.pairingRequired) == .ask(pinned: false))
check("§7.4: unsaved, p=0: sill/1 with any Mac key", dial(.open) == .anyKey)
check("§7.4: no p, DEBUG, not homeTLS: plain, as today", dial(.plain, debug: true) == .plain && dial(.plain, saved: true, debug: true) == .plain)
check("§7.4: no p otherwise: nothing dialed (Release; homeTLS in DEBUG)", dial(.plain) == .updateSill && dial(.plain, saved: true, homeTLS: true, debug: true) == .updateSill)
check("§7.4: the automatic reconnect follows the table but never asks",
      dial(.pairingRequired, tap: false) == .waitForTap && dial(.pairingRequired, saved: true, revoked: true, tap: false) == .waitForTap
      && dial(.pairingRequired, saved: true, tap: false) == .pinned && dial(.open, tap: false) == .anyKey && dial(.plain, debug: true, tap: false) == .plain)
var neverAsks = true, releaseNeverPlain = true, tlsNeverPlain = true
for d in doors { for bits in 0..<16 {
    let b = { (i: Int) in bits & (1 << i) != 0 }
    let r = P.homeDial(door: d, saved: b(0), revoked: b(1), homeTLS: b(2), debug: b(3), tap: false)
    if case .ask = r { neverAsks = false }
    let t = P.homeDial(door: d, saved: b(0), revoked: b(1), homeTLS: b(2), debug: false, tap: true)
    if t == .plain { releaseNeverPlain = false }
    let h = P.homeDial(door: d, saved: b(0), revoked: b(1), homeTLS: true, debug: b(3), tap: true)
    if h == .plain { tlsNeverPlain = false }
} }
check("no reconnect ever asks", neverAsks)
check("a Release build never dials plain", releaseNeverPlain)
check("no device dials a homeTLS Mac plain", tlsNeverPlain)

// The row's word says what a tap does.
var agree = 0, total = 0
for d in doors { for bits in 0..<32 { for m in methods {
    let b = { (i: Int) in bits & (1 << i) != 0 }
    total += 1
    let w = P.rowWord(door: d, saved: b(0), revoked: b(1), homeTLS: b(2), debug: b(3), method: m, cable: b(4))
    let t = P.homeDial(door: d, saved: b(0), revoked: b(1), homeTLS: b(2), debug: b(3), tap: true)
    let asks: Bool = { if case .ask = t { return true }; return false }()
    let ok: Bool
    switch w {
    case .notPaired, .pairsOverCable: ok = asks
    case .openDoor: ok = t == .anyKey
    case .updateSill: ok = t == .updateSill
    case .method: ok = t == .pinned || t == .plain
    }
    agree += ok ? 1 : 0
} } }
check("the word says what a tap does in \(agree) of \(total) combinations (Not paired and Wired-to-pair ask, an open door's Not paired connects with any key, Update Sill dials nothing, a method connects pinned or, in DEBUG, plain)", agree == total)

// MARK: Which saved Mac a row is (the security review, 2026-09-27)

// A tap is as strict as the automatic reconnect: a row whose tag names no saved Mac, under the
// Bonjour name a saved Mac was last reached by, is that Mac, dialed pinned to its key.
let savedByName: [(macID: String, bonjourName: String?)] = [("RECENT", "Mac mini"), ("OLD", "Mac mini"), ("NONAME", nil), ("STUDIO", "Studio")]
check("rowMac: a tag this device resolved names the row's Mac, whatever its name", P.rowMac(tagged: "OLD", name: "Studio", saved: savedByName)! == ("OLD", true))
check("rowMac: no tag of a saved Mac's, a saved Mac's Bonjour name: that Mac, by name alone",
      P.rowMac(tagged: nil, name: "Studio", saved: savedByName)! == ("STUDIO", false))
check("rowMac: two saved Macs of that name: the most recently used (the first given)", P.rowMac(tagged: nil, name: "Mac mini", saved: savedByName)! == ("RECENT", false))
check("rowMac: another name, a renamed \"Mac mini (2)\", or a case change: no saved Mac",
      P.rowMac(tagged: nil, name: "Office", saved: savedByName) == nil && P.rowMac(tagged: nil, name: "Mac mini (2)", saved: savedByName) == nil
      && P.rowMac(tagged: nil, name: "mac mini", saved: savedByName) == nil)
check("rowMac: a saved Mac with no Bonjour name is never a row's by name", P.rowMac(tagged: nil, name: "", saved: [("NONAME", nil)]) == nil)
check("rowMac: nothing saved, nothing named", P.rowMac(tagged: nil, name: "Mac mini", saved: []) == nil)
// A look-alike: a tagless row under a saved Mac's name. As that Mac, a tap dials it pinned, never
// with any key (p=0) or plain (DEBUG, no p, homeTLS): the stranger's key fails the pin.
func lookAlike(_ d: P.HomeDoor, homeTLS: Bool, debug: Bool) -> H {
    let named = P.rowMac(tagged: nil, name: "Mac mini", saved: savedByName)
    return P.homeDial(door: d, saved: named != nil, revoked: false, homeTLS: homeTLS, debug: debug, tap: true)
}
check("a look-alike on an open door (p=0): pinned to the saved key, not any key", lookAlike(.open, homeTLS: true, debug: false) == .pinned
      && lookAlike(.open, homeTLS: false, debug: true) == .pinned)
check("a look-alike on a door that requires pairing: pinned (the reconnect's rule)", lookAlike(.pairingRequired, homeTLS: true, debug: false) == .pinned)
check("a look-alike with no p, the saved Mac seen over TLS: nothing dialed (Update Sill), in DEBUG too",
      lookAlike(.plain, homeTLS: true, debug: true) == .updateSill && lookAlike(.plain, homeTLS: true, debug: false) == .updateSill)
check("a look-alike's row reads as the saved Mac's does (a tap is the saved Mac's dial), and its word is not an open door's",
      P.rowWord(door: .open, saved: true, revoked: false, homeTLS: true, debug: false, method: .wifi, cable: false) == .method(.wifi))

// MARK: §7.5, the device's cable check

typealias I = DiscoveryPolicy.Interface
func ip(_ s: String) -> [UInt8] {
    var v6 = in6_addr(), v4 = in_addr()
    if s.withCString({ inet_pton(AF_INET, $0, &v4) }) == 1 { return withUnsafeBytes(of: v4) { Array($0) } }
    precondition(s.withCString({ inet_pton(AF_INET6, $0, &v6) }) == 1, s)
    return withUnsafeBytes(of: v6) { Array($0) }
}
let en2 = I(name: "en2", type: .wiredEthernet), anpi0 = I(name: "anpi0", type: .wiredEthernet), en0 = I(name: "en0", type: .wifi)
let awdl0 = I(name: "awdl0", type: .wifi), lo0 = I(name: "lo0", type: .loopback), en3 = I(name: "en3", type: .wiredEthernet)
let macOnCable = ip("fe80::18c2:af60:ec0d:47ea")                     // the Mac's end, as the iPad sees it on en2
// This device's addresses: the cable's ends carry only link-local ones; Wi-Fi the LAN's.
var ownEn2 = ip("fe80::1c0f:2a:6e1:9b3"); ownEn2[2] = 0; ownEn2[3] = 0x07  // as getifaddrs gives it, scope embedded
let iPadOwn: [(interface: String, address: [UInt8])] = [
    ("en2", ownEn2), ("en2", ip("169.254.12.34")), ("anpi0", ip("fe80::c:d:e:f")),
    ("en0", ip("10.128.0.52")), ("en0", ip("fe80::47b:5945:e0aa:d0ac")), ("en0", ip("2601:600:1:2::52")),
    ("lo0", ip("127.0.0.1")), ("lo0", ip("::1")), ("awdl0", ip("fe80::8425:bdff:fe62:8930")),
    ("en3", ip("fe80::3:3:3:3")), ("en3", ip("10.128.0.77")),                // a USB Ethernet adapter on the LAN (DHCP)
]
let yes = P.onCable(mac: macOnCable, scope: en2, own: iPadOwn)
check("cable: the Mac's fe80 scoped to en2, which carries only link-local addresses", yes.cable && yes.console == "cable: yes, en2 carries only link-local addresses")
check("cable: the same over anpi0", P.onCable(mac: macOnCable, scope: anpi0, own: iPadOwn).cable)
let adapter = P.onCable(mac: ip("fe80::99"), scope: en3, own: iPadOwn)
check("cable: a USB Ethernet adapter with a DHCP address is not (\"cable: no, en3 has 10.128.0.77\")", !adapter.cable && adapter.console == "cable: no, en3 has 10.128.0.77")
let slaac: [(interface: String, address: [UInt8])] = [("en2", ip("fe80::1")), ("en2", ip("2601:600:1:2::99"))]
check("cable: the same interface with a SLAAC address is not", !P.onCable(mac: macOnCable, scope: en2, own: slaac).cable)
check("cable: with a unique local address (fd…) it is not", !P.onCable(mac: macOnCable, scope: en2, own: [("en2", ip("fe80::1")), ("en2", ip("fd00::5"))]).cable)
check("cable: an iPhone sharing its connection over USB (its end carries 172.20.10.1) is not",
      !P.onCable(mac: macOnCable, scope: en2, own: [("en2", ip("fe80::1")), ("en2", ip("172.20.10.1"))]).cable)
let mine = P.onCable(mac: ip("fe80::1c0f:2a:6e1:9b3"), scope: en2, own: iPadOwn)
check("cable: the Mac's address is one of this device's own (stored with its embedded scope): not", !mine.cable && mine.console.hasPrefix("cable: no, fe80::1c0f:2a:6e1:9b3 is this device"))
check("cable: an own address given with its embedded scope matches too", !P.onCable(mac: ownEn2, scope: en2, own: [("en2", ip("fe80::1c0f:2a:6e1:9b3"))]).cable)
check("cable: IPv4 link-local never counts", !P.onCable(mac: ip("169.254.1.1"), scope: en2, own: iPadOwn).cable)
check("cable: a routed IPv6 Mac address is not", !P.onCable(mac: ip("2601:600:1:2::34"), scope: en2, own: iPadOwn).cable)
check("cable: Wi-Fi is not", !P.onCable(mac: ip("fe80::5"), scope: en0, own: iPadOwn).cable)
check("cable: Wi-Fi is not even with only link-local addresses (a network without DHCP)",
      !P.onCable(mac: ip("fe80::5"), scope: en0, own: [("en0", ip("fe80::9")), ("en0", ip("169.254.9.9"))]).cable)
check("cable: an interface of unknown type with only link-local addresses is not",
      !P.onCable(mac: ip("fe80::5"), scope: I(name: "en6", type: .other), own: [("en6", ip("fe80::9"))]).cable)
check("cable: AWDL is not, whatever type it reports", !P.onCable(mac: ip("fe80::5"), scope: awdl0, own: iPadOwn).cable
      && !P.onCable(mac: ip("fe80::5"), scope: I(name: "awdl0", type: .wiredEthernet), own: [("awdl0", ip("fe80::6"))]).cable)
check("cable: loopback is not", !P.onCable(mac: ip("fe80::5"), scope: lo0, own: iPadOwn).cable)
check("cable: no interface is not", !P.onCable(mac: macOnCable, scope: nil, own: iPadOwn).cable)
check("cable: an interface with no address here is not (nothing read)", !P.onCable(mac: macOnCable, scope: I(name: "en5", type: .wiredEthernet), own: iPadOwn).cable)
check("cable: a malformed address is not", !P.onCable(mac: [], scope: en2, own: iPadOwn).cable && !P.onCable(mac: [0xFE], scope: en2, own: iPadOwn).cable)
check("console: IPv4 and other interfaces say why", P.onCable(mac: ip("169.254.1.1"), scope: en2, own: iPadOwn).console == "cable: no, the Mac\u{2019}s address 169.254.1.1 is not IPv6 link-local"
      && P.onCable(mac: ip("fe80::5"), scope: en0, own: iPadOwn).console == "cable: no, en0 is not wired Ethernet"
      && P.onCable(mac: macOnCable, scope: nil, own: iPadOwn).console == "cable: no, the Mac\u{2019}s address names no interface")

// The row: Wired over the cable pairs by itself; Wired over an adapter reads Not paired.
check("row: en2 carries only link-local addresses", P.carriesOnlyLinkLocal("en2", own: iPadOwn) && P.carriesOnlyLinkLocal("anpi0", own: iPadOwn))
check("row: en3 (the adapter), en0 (Wi-Fi) do not; an interface with none does not", !P.carriesOnlyLinkLocal("en3", own: iPadOwn)
      && !P.carriesOnlyLinkLocal("en0", own: iPadOwn) && !P.carriesOnlyLinkLocal("en5", own: iPadOwn))
check("row: an unpaired Wired row on en2 reads Wired, on the adapter Not paired",
      word(.pairingRequired, .wired, cable: P.carriesOnlyLinkLocal("en2", own: iPadOwn)).word == "Wired"
      && word(.pairingRequired, .wired, cable: P.carriesOnlyLinkLocal("en3", own: iPadOwn)).word == "Not paired")
check("link-local: fe80::/10 and 169.254/16 only", P.isLinkLocal(ip("fe80::1")) && P.isLinkLocal(ip("febf::1")) && P.isLinkLocal(ip("169.254.0.1"))
      && !P.isLinkLocal(ip("fec0::1")) && !P.isLinkLocal(ip("169.253.0.1")) && !P.isLinkLocal(ip("10.0.0.1")) && !P.isLinkLocal([]) && !P.isLinkLocal([1, 2, 3, 4, 5]))
check("addressText: IPv4, IPv6 without its embedded scope", P.addressText(ip("10.128.0.52")) == "10.128.0.52" && P.addressText(ownEn2) == "fe80::1c0f:2a:6e1:9b3")


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
check("copy: the home card's errors", C.stopped(mac: mini) == "Mac mini stopped pairing after too many wrong codes. On the Mac, choose Pair iPhone or iPad\u{2026} in the Sill menu, then tap Mac mini again."
      && C.expired(mac: mini) == "That code expired. Tap Mac mini for a new one."
      && C.closed(mac: mini) == "That code no longer works. On the Mac, choose Pair iPhone or iPad\u{2026} in the Sill menu, then tap Mac mini again."
      && C.proofFailed(mac: mini) == "Pairing didn\u{2019}t finish: Mac mini couldn\u{2019}t show it knows the code. Tap it to try again.")

// A refused proof at home (the security review, 2026-09-27): kind 20's reason → the card's words.
// After a stop, and after a code closed (the Mac's Cancel, or used by another device), the Mac keeps
// this device quiet, so a tap alone gets no new code: the words send the person to the Sill menu
// first. After an expiry a tap gets one (AskLimits: an expired window quiets nobody).
typealias R = DiscoveryPolicy.HomeRefusal
check("refusal: code → a wrong code, with the tries left (never below 0)", P.homeRefusal(reason: "code", triesLeft: 4) == .wrongCode(triesLeft: 4)
      && P.homeRefusal(reason: "code", triesLeft: nil) == .wrongCode(triesLeft: 0) && P.homeRefusal(reason: "code", triesLeft: -2) == .wrongCode(triesLeft: 0))
check("refusal: stopped, expired", P.homeRefusal(reason: "stopped", triesLeft: nil) == .stopped && P.homeRefusal(reason: "expired", triesLeft: nil) == .expired)
check("refusal: closed, busy (a second time), no reason, or one this build does not know → closed",
      ["closed", "busy", "shown", "later", "Stopped", ""].allSatisfy { P.homeRefusal(reason: $0, triesLeft: nil) == .closed }
      && P.homeRefusal(reason: nil, triesLeft: nil) == .closed)
func refusalWords(_ r: R) -> String {
    switch r {
    case .wrongCode: return "a wrong code"
    case .stopped: return C.stopped(mac: mini)
    case .expired: return C.expired(mac: mini)
    case .closed: return C.closed(mac: mini)
    }
}
check("refusal: stopped and closed send the person to the Sill menu before a tap",
      [R.stopped, .closed].allSatisfy { refusalWords($0).contains("choose Pair iPhone or iPad\u{2026} in the Sill menu, then tap Mac mini again") })
check("refusal: expired, and only expired, says a tap alone gets a new code",
      refusalWords(.expired).hasSuffix("Tap Mac mini for a new one.") && ![R.stopped, .closed].contains { refusalWords($0).contains("for a new") })
check("copy: no answer", C.noAnswer(mac: mini) == "Mac mini didn\u{2019}t answer. Check that Sill is open on it, then tap it again.")

// MARK: Step 5: the Settings panel's Away from home (§7.6) and the words of the home card and the
// overlay at home (§7.7)

typealias Away = DiscoveryPolicy.AwayFromHome
func away(saved: Bool = false, remote: Bool = false, remoteAccess: Bool = false, tls: Bool = false) -> Away {
    P.awayFromHome(saved: saved, remoteSession: remote, remoteAccess: remoteAccess, tlsAtHome: tls)
}
check("away: a saved Mac at home over TLS, Remote Access on: Paired, and how Sill reaches it from afar",
      away(saved: true, remoteAccess: true, tls: true) == .paired(.reaches))
check("away: a saved Mac at home over TLS, Remote Access off: Paired, and how to turn Remote Access on",
      away(saved: true, remoteAccess: false, tls: true) == .paired(.turnOnRemoteAccess))
check("away: a saved Mac through the remote door: Paired, and how this session came (the route)",
      away(saved: true, remote: true, remoteAccess: true) == .paired(.connected) && away(saved: true, remote: true, remoteAccess: false) == .paired(.connected))
check("away: a saved Mac over a plain door (paired before pairing at home): Paired, as over TLS",
      away(saved: true, remoteAccess: true) == .paired(.reaches) && away(saved: true) == .paired(.turnOnRemoteAccess))
check("away: an unpaired session at home over TLS (Require pairing off): Pair This iPad…, at its own door, Remote Access on or off",
      away(remoteAccess: false, tls: true) == .pairThisDevice(atHome: true) && away(remoteAccess: true, tls: true) == .pairThisDevice(atHome: true))
check("away: an unpaired session over a plain door, Remote Access on: Pair This iPad… through the remote door (as before)",
      away(remoteAccess: true) == .pairThisDevice(atHome: false))
check("away: an unpaired session over a plain door, Remote Access off: the Remote Access footnote only (as before)",
      away(remoteAccess: false) == .turnOnRemoteAccess)
var awayAll = 0, pairedNeverOffers = true, offersOnlyUnpaired = true, remoteNeverAtHome = true
for bits in 0..<16 {
    let b = { (i: Int) in bits & (1 << i) != 0 }
    let a = away(saved: b(0), remote: b(1), remoteAccess: b(2), tls: b(3))
    awayAll += 1
    if b(0), case .paired = a {} else if b(0) { pairedNeverOffers = false }
    if case .pairThisDevice = a, b(0) { offersOnlyUnpaired = false }
    if case .pairThisDevice(atHome: true) = a, b(1) { remoteNeverAtHome = false }
}
check("away: over all \(awayAll) inputs, a saved Mac always reads Paired (Pair This iPad… never shows for it)", pairedNeverOffers)
check("away: Pair This iPad… shows only in an unpaired session (§7.5, §7.6)", offersOnlyUnpaired)
check("away: a remote session never pairs at a home door", remoteNeverAtHome && away(remote: true, remoteAccess: true, tls: true) == .pairThisDevice(atHome: false))

check("copy: the home card's title, \"Pair with Mac mini\"", C.cardTitle(mac: mini) == "Pair with Mac mini")
check("copy: the typed path's line (and the collapsed one), \"Type the code Mac mini shows.\"", C.typeCode(mac: mini) == "Type the code Mac mini shows.")
check("copy: the viewfinder's caption and spoken label name the Mac",
      C.viewfinderCaption(mac: mini) == "Point at the code on Mac mini" && C.viewfinderLabel(mac: mini) == "Camera. Point it at the code on Mac mini.")
check("copy: the scan line is the status line while the card is up", C.showing(mac: mini, device: "iPhone") == "Mac mini is showing a code. Point this iPhone at it.")
check("copy: Pair This iPad… over an unpaired session at home",
      C.pairThisDeviceAtHome(mac: mini, device: "iPad") == "Mac mini lets devices connect without pairing. Pair this iPad once to keep connecting if that changes, and to reach Mac mini away from home while Remote Access is on. Mac mini shows a code; scan it with this iPad.")
check("copy: over a stream no row can be tapped: the overlay's words never say Tap",
      C.proofFailedOverStream(mac: mini) == "Pairing didn\u{2019}t finish: Mac mini couldn\u{2019}t show it knows the code."
      && C.noAnswerOverStream(mac: mini) == "Mac mini didn\u{2019}t answer. Try again."
      && ![C.proofFailedOverStream(mac: mini), C.noAnswerOverStream(mac: mini)].contains { $0.contains("Tap") || $0.contains("tap") })
check("copy: the card's own errors (under the field) end at the row, the overlay's do not",
      C.stopped(mac: mini).hasSuffix("tap Mac mini again.") && C.closed(mac: mini).hasSuffix("tap Mac mini again.")
      && C.expired(mac: mini).contains("Tap Mac mini") && C.proofFailed(mac: mini).contains("Tap it"))

// MARK: Kind 18 and a goodbye "removed" speak for the Mac whose key the session has (the security
// review, 2026-09-27)

let kM = Data(repeating: 0x4D, count: 32), kX = Data(repeating: 0x58, count: 32)
check("kind 18 names the session's Mac only when the connection's own key signed it",
      P.macInfoNamesSession(signer: kM, connectionKey: kM) && !P.macInfoNamesSession(signer: kM, connectionKey: kX))
check("kind 18 on a plain connection (no key) names nothing, however well it is signed", !P.macInfoNamesSession(signer: kM, connectionKey: nil))
check("removed revokes the saved Mac from a remote session (pinned to its key)", P.removalRevokes(remote: true, trust: nil, savedKey: kM))
check("removed revokes it from a home session pinned to its key", P.removalRevokes(remote: false, trust: .saved(pin: kM), savedKey: kM))
check("removed revokes it from an open session whose connection showed its key",
      P.removalRevokes(remote: false, trust: .open(seen: kM), savedKey: kM))
check("removed never revokes from a session that another key answered, a plain one, or one that saw no key yet",
      !P.removalRevokes(remote: false, trust: .open(seen: kX), savedKey: kM) && !P.removalRevokes(remote: false, trust: .saved(pin: kX), savedKey: kM)
      && !P.removalRevokes(remote: false, trust: .plain, savedKey: kM) && !P.removalRevokes(remote: false, trust: .open(seen: nil), savedKey: kM)
      && !P.removalRevokes(remote: false, trust: nil, savedKey: kM))
check("removed revokes nothing without a saved key", !P.removalRevokes(remote: true, trust: .saved(pin: kM), savedKey: nil))
// Over every trust a session at home can have: removed revokes exactly when the session's pin is the saved key.
var revokesAsPinned = true
for t in [P.HomeTrust.plain, .saved(pin: kM), .saved(pin: kX), .open(seen: nil), .open(seen: kM), .open(seen: kX)] {
    if P.removalRevokes(remote: false, trust: t, savedKey: kM) != (P.pin(t) == .key(kM)) { revokesAsPinned = false }
}
check("removed revokes at home exactly when the session is pinned to the saved Mac's key, over every trust", revokesAsPinned)

print(fails == 0 ? "ALL PASS (\(passes))" : "\(fails) FAIL, \(passes) pass")
if fails > 0 { exit(1) }
