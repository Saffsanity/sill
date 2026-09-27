// H3 (step 1): DoorPolicy, pure, compiled with StreamProtocol's sources, OriginPolicy and
// PairingWindow (AskLimits) as one module (Tests/checks/module.py drops `import StreamProtocol`).
// Every row of docs/home-pairing-plan.md §4.2: both doors, each origin, each ALPN, Require pairing
// on and off, paired or not, a window or not; the ask rule's six steps in order; the test hooks;
// and (the merge with main's update notice) what a session the device gate held is judged by as
// the gate admits it (afterGate).
import Foundation
var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) { if ok { passes += 1; print("ok   \(name)") } else { fails += 1; print("FAIL \(name)") }; fflush(stdout) }
typealias D = DoorPolicy
typealias T = DoorPolicy.Trust
let origins: [OriginPolicy.Origin] = [.loopback, .direct, .vpn, .lan, .internet]
let session = RemoteTLS.sessionALPN, pairing = RemoteTLS.pairingALPN
check("the ALPNs are sill/1 and sill-pair/1", session == "sill/1" && pairing == "sill-pair/1")

// MARK: Before start (the origin gate)

var gate = 0, gateOK = 0
for o in origins {
    for ia in [false, true] {
        gate += 2
        let home = D.admitsBeforeStart(.home, origin: o, internetAccess: ia)
        let remote = D.admitsBeforeStart(.remote, origin: o, internetAccess: ia)
        if home == [.loopback, .direct, .lan].contains(o) { gateOK += 1 } else { print("  home \(o) ia=\(ia): \(home)") }
        if remote == ([.loopback, .lan, .vpn].contains(o) || (o == .internet && ia)) { gateOK += 1 } else { print("  remote \(o) ia=\(ia): \(remote)") }
    }
}
check("before start: \(gateOK) of \(gate) (home: loopback, direct, lan; remote: loopback, lan, vpn, internet with access)", gate == gateOK)
check("before start: home refuses a VPN and the internet whatever the switch",
      !D.admitsBeforeStart(.home, origin: .vpn, internetAccess: true) && !D.admitsBeforeStart(.home, origin: .internet, internetAccess: true))
check("before start: home takes peer-to-peer Wi-Fi (Direct Wireless), the remote door never",
      D.admitsBeforeStart(.home, origin: .direct, internetAccess: false) && !D.admitsBeforeStart(.remote, origin: .direct, internetAccess: true))
check("before start: the remote door takes the internet only with access",
      !D.admitsBeforeStart(.remote, origin: .internet, internetAccess: false) && D.admitsBeforeStart(.remote, origin: .internet, internetAccess: true))
for o in origins {
    for ia in [false, true] {
        let h = D.refusalBeforeStart(.home, origin: o, internetAccess: ia)
        let r = D.refusalBeforeStart(.remote, origin: o, internetAccess: ia)
        let hExp: String? = [.loopback, .direct, .lan].contains(o) ? nil : (o == .vpn ? "vpn" : "internet")
        let rExp: String? = D.admitsBeforeStart(.remote, origin: o, internetAccess: ia) ? nil : "internet"
        check("refusal word: \(o) ia=\(ia): home \(h ?? "admitted"), remote \(r ?? "admitted")", h == hExp && r == rExp)
    }
}

// MARK: The verify block

let alpns: [String?] = [session, pairing, nil, "h2", "sill/2", "SILL/1", ""]
func allTrusts() -> [T] {
    var out: [T] = []
    for bits in 0..<128 {
        out.append(T(hasKey: bits & 1 != 0, paired: bits & 2 != 0, requirePairing: bits & 4 != 0, remoteAccess: bits & 8 != 0,
                     internetAccess: bits & 16 != 0, pairingOpen: bits & 32 != 0, remotePairingOpen: bits & 64 != 0))
    }
    return out
}
func trustOracle(_ door: D.Door, _ alpn: String?, _ t: T) -> Bool {
    guard t.hasKey else { return false }
    if alpn == "sill/1" { return door == .home ? (t.paired || !t.requirePairing) : t.paired }
    if alpn == "sill-pair/1" { return door == .home ? true : t.remotePairingOpen }
    return false
}
var vb = 0, vbOK = 0
for door in [D.Door.home, .remote] { for a in alpns { for t in allTrusts() {
    vb += 1
    if D.trusts(door, alpn: a, t) == trustOracle(door, a, t) { vbOK += 1 } else { print("  verify \(door) \(a ?? "nil") \(t)") }
} } }
check("verify block: \(vbOK) of \(vb) combinations (2 doors × 7 ALPNs × 128 trusts) match §4.2's table", vb == vbOK)
check("verify, home sill/1: a paired key", D.trusts(.home, alpn: session, T(paired: true)))
check("verify, home sill/1: an unpaired key with Require pairing on is refused", !D.trusts(.home, alpn: session, T(paired: false, requirePairing: true)))
check("verify, home sill/1: any key while Require pairing is off", D.trusts(.home, alpn: session, T(paired: false, requirePairing: false)))
check("verify, home sill/1: never a peer without a P-256 key, even with Require pairing off",
      !D.trusts(.home, alpn: session, T(hasKey: false, paired: false, requirePairing: false)))
check("verify, home sill-pair/1: always, with no window open (an ask needs none)", D.trusts(.home, alpn: pairing, T(pairingOpen: false)))
check("verify, remote sill/1: Require pairing off lets no unpaired key in",
      !D.trusts(.remote, alpn: session, T(paired: false, requirePairing: false, remoteAccess: true)))
check("verify, remote sill/1: a paired key (Remote Access is judged at .ready)", D.trusts(.remote, alpn: session, T(paired: true, remoteAccess: false)))
check("verify, remote sill-pair/1: a window only the home door takes (a device opened it) is refused",
      !D.trusts(.remote, alpn: pairing, T(pairingOpen: true, remotePairingOpen: false)))
check("verify, remote sill-pair/1: a window the Mac's user opened", D.trusts(.remote, alpn: pairing, T(pairingOpen: true, remotePairingOpen: true)))
check("verify: another ALPN, none, or a later generation never", [nil, "h2", "sill/2", "SILL/1", ""].allSatisfy { a in
    [D.Door.home, .remote].allSatisfy { !D.trusts($0, alpn: a, T(paired: true, requirePairing: false, remoteAccess: true, pairingOpen: true, remotePairingOpen: true)) } })

// MARK: At .ready

func readyOracle(_ door: D.Door, _ alpn: String?, _ t: T, _ n: Int) -> D.AtReady {
    guard t.hasKey else { return .refuse("unpaired") }
    switch (door, alpn) {
    case (.home, "sill/1"?): return (t.paired || !t.requirePairing) ? .session : .refuse("unpaired")
    case (.home, "sill-pair/1"?): return .pairing
    case (.remote, "sill/1"?):
        if !t.paired { return .refuse("unpaired") }
        if !t.remoteAccess { return .goodbye("remoteOff") }
        if n >= 8 { return .goodbye("busy") }
        return .session
    case (.remote, "sill-pair/1"?): return t.remotePairingOpen ? .pairing : .refuse("unpaired")
    default: return .refuse("unpaired")
    }
}
var rd = 0, rdOK = 0
for door in [D.Door.home, .remote] { for a in alpns { for t in allTrusts() { for n in [0, 7, 8, 9] {
    rd += 1
    if D.atReady(door, alpn: a, t, remoteSessions: n) == readyOracle(door, a, t, n) { rdOK += 1 } else { print("  ready \(door) \(a ?? "nil") \(t) \(n)") }
} } } }
check("at .ready: \(rdOK) of \(rd) combinations (× 0, 7, 8, 9 remote sessions) match §4.2's table", rd == rdOK)
check("at .ready, home sill/1: the session needs no Remote Access and has no session limit",
      D.atReady(.home, alpn: session, T(paired: true, remoteAccess: false), remoteSessions: 100) == .session)
check("at .ready, home sill/1: checked again: a key the list lost since the handshake is refused",
      D.atReady(.home, alpn: session, T(paired: false, requirePairing: true), remoteSessions: 0) == .refuse("unpaired"))
check("at .ready, home sill/1: Require pairing turned on since the handshake refuses an unpaired key",
      D.atReady(.home, alpn: session, T(paired: false, requirePairing: true), remoteSessions: 0) == .refuse("unpaired")
      && D.atReady(.home, alpn: session, T(paired: false, requirePairing: false), remoteSessions: 0) == .session)
check("at .ready, home sill-pair/1: read, with or without a window", D.atReady(.home, alpn: pairing, T(), remoteSessions: 0) == .pairing
      && D.atReady(.home, alpn: pairing, T(pairingOpen: true), remoteSessions: 0) == .pairing)
check("at .ready, remote sill/1, as before: Remote Access off → goodbye remoteOff (before busy)",
      D.atReady(.remote, alpn: session, T(paired: true, remoteAccess: false), remoteSessions: 8) == .goodbye(Goodbye.remoteOff))
check("at .ready, remote sill/1: the 9th session → goodbye busy; the 8th is served",
      D.atReady(.remote, alpn: session, T(paired: true, remoteAccess: true), remoteSessions: 8) == .goodbye(Goodbye.busy)
      && D.atReady(.remote, alpn: session, T(paired: true, remoteAccess: true), remoteSessions: 7) == .session)
check("at .ready, remote sill-pair/1: only while the remote door takes proofs",
      D.atReady(.remote, alpn: pairing, T(pairingOpen: true, remotePairingOpen: false), remoteSessions: 0) == .refuse("unpaired")
      && D.atReady(.remote, alpn: pairing, T(pairingOpen: true, remotePairingOpen: true), remoteSessions: 0) == .pairing)
check("at .ready: no key → refused, whatever the door and ALPN", [D.Door.home, .remote].allSatisfy { d in alpns.allSatisfy { a in
    D.atReady(d, alpn: a, T(hasKey: false, paired: true, requirePairing: false, remoteAccess: true, remotePairingOpen: true), remoteSessions: 0) == .refuse("unpaired") } })
check("maxRemoteSessions is 8, as RemoteServer's", D.maxRemoteSessions == 8)

// MARK: After the device gate (the merge with main's update notice)
//
// With the device floor above "0" a session the door admitted at `.ready` waits (up to 2 s) while the
// gate reads its hello, neither pending nor a client; afterGate judges it again from the switches as
// they are when the gate admits it, the goodbye the change that closes sessions would have sent it.

func afterGateOracle(_ door: D.Door, wasPaired: Bool, _ o: OriginPolicy.Origin, _ t: T, _ n: Int) -> String? {
    switch door {
    case .remote:
        if !t.hasKey || !t.paired { return "removed" }
        if !t.remoteAccess { return "remoteOff" }
        if o == .direct || (o == .internet && !t.internetAccess) { return "internetOff" }
        if n >= 8 { return "busy" }
        return nil
    case .home:
        if t.paired { return nil }
        if wasPaired { return "removed" }
        return t.requirePairing ? "pairingRequired" : nil
    }
}
var ag = 0, agOK = 0
for door in [D.Door.home, .remote] { for w in [false, true] { for o in origins { for t in allTrusts() { for n in [0, 7, 8, 9] {
    ag += 1
    let got = D.afterGate(door, wasPaired: w, origin: o, t, remoteSessions: n)
    if got == afterGateOracle(door, wasPaired: w, o, t, n) { agOK += 1 } else { print("  afterGate \(door) wasPaired \(w) \(o) \(t) \(n): \(got ?? "nil")") }
} } } } }
check("after the gate: \(agOK) of \(ag) combinations (both doors, paired at `.ready` or not, every origin, 0, 7, 8, 9 remote sessions) match", ag == agOK)
let full = T(paired: true, requirePairing: true, remoteAccess: true, internetAccess: true)
check("after the gate, remote: nothing changed → admitted, from every origin the door takes",
      [OriginPolicy.Origin.loopback, .lan, .vpn, .internet].allSatisfy { D.afterGate(.remote, wasPaired: true, origin: $0, full, remoteSessions: 0) == nil })
check("after the gate, remote: removed meanwhile → removed, before any other change",
      D.afterGate(.remote, wasPaired: true, origin: .internet, T(paired: false, remoteAccess: false), remoteSessions: 9) == Goodbye.removed)
check("after the gate, remote: Remote Access off meanwhile → remoteOff, before the internet switch and the limit",
      D.afterGate(.remote, wasPaired: true, origin: .internet, T(paired: true, remoteAccess: false, internetAccess: false), remoteSessions: 9) == Goodbye.remoteOff)
check("after the gate, remote: internet access off meanwhile → internetOff for an internet origin only, before the limit",
      D.afterGate(.remote, wasPaired: true, origin: .internet, T(paired: true, remoteAccess: true, internetAccess: false), remoteSessions: 9) == Goodbye.internetOff
      && [OriginPolicy.Origin.loopback, .lan, .vpn].allSatisfy { D.afterGate(.remote, wasPaired: true, origin: $0, T(paired: true, remoteAccess: true, internetAccess: false), remoteSessions: 0) == nil })
check("after the gate, remote: the limit reached meanwhile → busy at 8 sessions, the 8th served",
      D.afterGate(.remote, wasPaired: true, origin: .lan, full, remoteSessions: 8) == Goodbye.busy
      && D.afterGate(.remote, wasPaired: true, origin: .lan, full, remoteSessions: 7) == nil)
check("after the gate, remote: the words are kind 22's", [Goodbye.removed, Goodbye.remoteOff, Goodbye.internetOff, Goodbye.busy]
      == ["removed", "remoteOff", "internetOff", "busy"])
check("after the gate, home: a paired key → admitted, whatever Require pairing, Remote Access, the origin and the remote sessions",
      origins.allSatisfy { o in [false, true].allSatisfy { rp in [false, true].allSatisfy { ra in
          D.afterGate(.home, wasPaired: true, origin: o, T(paired: true, requirePairing: rp, remoteAccess: ra), remoteSessions: 9) == nil } } })
check("after the gate, home: removed meanwhile → removed, with Require pairing on or off",
      D.afterGate(.home, wasPaired: true, origin: .lan, T(paired: false, requirePairing: true), remoteSessions: 0) == Goodbye.removed
      && D.afterGate(.home, wasPaired: true, origin: .lan, T(paired: false, requirePairing: false), remoteSessions: 0) == Goodbye.removed)
check("after the gate, home: an unpaired key once Require pairing is on → pairingRequired; while it stays off → admitted",
      D.afterGate(.home, wasPaired: false, origin: .direct, T(paired: false, requirePairing: true), remoteSessions: 0) == Goodbye.pairingRequired
      && D.afterGate(.home, wasPaired: false, origin: .direct, T(paired: false, requirePairing: false), remoteSessions: 0) == nil)
check("after the gate, home: an unpaired key paired meanwhile → admitted", D.afterGate(.home, wasPaired: false, origin: .lan, T(paired: true, requirePairing: true), remoteSessions: 0) == nil)
var agSame = 0, agSameOK = 0
for t in allTrusts() where t.hasKey { for o in origins { for n in [0, 8] {
    // Admitted after the gate exactly when `.ready` would admit the session now: at the remote door
    // with an origin its switches take, at home for a key that was not paired at `.ready`.
    agSame += 2
    let remoteNow = D.atReady(.remote, alpn: session, t, remoteSessions: n) == .session && D.admitsBeforeStart(.remote, origin: o, internetAccess: t.internetAccess)
    if (D.afterGate(.remote, wasPaired: true, origin: o, t, remoteSessions: n) == nil) == remoteNow { agSameOK += 1 }
    if (D.afterGate(.home, wasPaired: false, origin: o, t, remoteSessions: n) == nil) == (D.atReady(.home, alpn: session, t, remoteSessions: n) == .session) { agSameOK += 1 }
} } }
check("after the gate: \(agSameOK) of \(agSame) admit exactly what `.ready` and the origin gate would admit now", agSame == agSameOK)

// MARK: The one kind 19

check("kind 19 at home: ask → the ask rule", D.pairing(.home, method: "ask", version: 1) == .ask)
check("kind 19 at home: qr and code → the window", D.pairing(.home, method: "qr", version: 1) == .window && D.pairing(.home, method: "code", version: 1) == .window)
check("kind 19 at home: an unknown method → the window, which counts it as a wrong proof (the remote door's rule)",
      ["icloud", "", "ASK", "Ask", "ask "].allSatisfy { D.pairing(.home, method: $0, version: 1) == .window })
check("kind 19 at the remote door: ask → closed, never the window and never the ask rule", D.pairing(.remote, method: "ask", version: 1) == .closed)
check("kind 19 at the remote door: qr, code and unknown methods → the window, as before",
      ["qr", "code", "icloud", "", "ASK"].allSatisfy { D.pairing(.remote, method: $0, version: 1) == .window })
check("PairRequest.ask is the method the door looks for", PairRequest.ask == "ask")
// The floor: kind 19's generation is `v` (1). A later one (another method, another proof format)
// is answered `closed` without a try at either door, never judged by the window, which would count
// it as a wrong code and use up one of its five.
var laterAll = 0, laterClosed = 0
for d in [D.Door.home, .remote] { for m in ["ask", "qr", "code", "icloud", ""] { for v in [0, 2, 3, -1, Int.max] {
    laterAll += 1
    if D.pairing(d, method: m, version: v) == .closed { laterClosed += 1 }
} } }
check("kind 19 of another generation (v 0, 2, 3, -1, max; every method; both doors): closed, no try (\(laterClosed) of \(laterAll))",
      laterAll == laterClosed)
check("kind 19's generation is 1, and a request made here says so", PairRequest.version == 1
      && PairRequest(method: "qr", proof: "", name: "iPad", model: nil).v == 1)

// MARK: A handshake that failed

let statuses: [Int32] = [-9808, -9863, -9810, -9836, -9858, -9816, -9825, -9829, -9806, 0, 54, 61]
for s in statuses {
    let h = D.handshakeRefusal(.home, status: s), r = D.handshakeRefusal(.remote, status: s)
    let doorRefusal = [-9808, -9863, -9810, -9836, -9858].contains(s)
    let hExp: D.HandshakeRefusal? = s == -9836 ? .olderSill : (doorRefusal ? .refused("unpaired") : nil)
    let rExp: D.HandshakeRefusal? = doorRefusal ? .refused("unpaired") : nil
    check("handshake \(s): home \(h.map { "\($0)" } ?? "not counted"), remote \(r.map { "\($0)" } ?? "not counted")", h == hExp && r == rExp)
}
check("handshake: an older Sill's plain bytes (-9836) at home count toward no backoff; an HTTP request (-9858) does",
      D.handshakeRefusal(.home, status: -9836) == .olderSill && D.handshakeRefusal(.home, status: -9858) == .refused("unpaired"))
check("handshake: the remote door keeps -9836 as unpaired, toward the backoff (unchanged)", D.handshakeRefusal(.remote, status: -9836) == .refused("unpaired"))

// MARK: The ask rule

func askOracle(_ u: Bool, _ seen: Bool, _ claimed: Bool, _ other: Bool, _ w: Bool, _ me: Bool, _ q: Bool, _ n: Int) -> D.Ask {
    if !u { return .locked }
    if seen && claimed && !other { return .pairNow }
    if w { return .shown(opened: false) }
    if me { return .openOnMac("this Mac") }
    if q { return .openOnMac("quiet") }
    if n >= 3 { return .openOnMac("often") }
    return .shown(opened: true)
}
var ak = 0, akOK = 0
for bits in 0..<128 { for n in [0, 1, 2, 3, 4, 7] {
    let b = { (i: Int) in bits & (1 << i) != 0 }
    ak += 1
    let got = D.ask(unlocked: b(0), cableSeen: b(1), cableClaimed: b(2), otherKeyOfDevice: b(3), windowOpen: b(4),
                    fromThisMac: b(5), quiet: b(6), recentDeviceWindows: n)
    if got == askOracle(b(0), b(1), b(2), b(3), b(4), b(5), b(6), n) { akOK += 1 } else { print("  ask \(bits) \(n): \(got)") }
} }
check("the ask rule: \(akOK) of \(ak) combinations match the six steps, first match wins", ak == akOK)
func ask(u: Bool = true, seen: Bool = false, claimed: Bool = false, other: Bool = false, w: Bool = false, me: Bool = false, q: Bool = false, n: Int = 0) -> D.Ask {
    D.ask(unlocked: u, cableSeen: seen, cableClaimed: claimed, otherKeyOfDevice: other, windowOpen: w, fromThisMac: me, quiet: q, recentDeviceWindows: n)
}
check("step 1: locked beats the cable", ask(u: false, seen: true, claimed: true) == .locked)
check("step 1: locked beats an open window, this Mac and the limits", ask(u: false, w: true) == .locked && ask(u: false, me: true) == .locked
      && ask(u: false, q: true, n: 5) == .locked)
check("step 2: the cable pairs when the Mac's rule and the ask's cable: true agree, with no other key", ask(seen: true, claimed: true) == .pairNow)
check("step 2: only with the Mac's rule: a claim alone gets a window", ask(seen: false, claimed: true) == .shown(opened: true))
check("step 2: only with cable: true: the Mac's rule alone gets a window (the device could not tell)", ask(seen: true, claimed: false) == .shown(opened: true))
check("step 2: another key of the device on the list gets a window", ask(seen: true, claimed: true, other: true) == .shown(opened: true))
check("step 2 before 3: the cable pairs even while a window is open", ask(seen: true, claimed: true, w: true) == .pairNow)
check("step 2 before 5: the cable pairs even when quiet or often", ask(seen: true, claimed: true, q: true, n: 9) == .pairNow)
check("step 3: a window open → shown, not opened", ask(w: true) == .shown(opened: false))
check("step 3 before 4: an ask from this Mac while the Mac's user shows a code → shown", ask(w: true, me: true) == .shown(opened: false))
check("step 3 before 5: quiet and often, a window open → shown", ask(w: true, q: true, n: 5) == .shown(opened: false))
check("step 4: from this Mac → openOnMac(this Mac), never a window", ask(me: true) == .openOnMac("this Mac"))
check("step 4 before 5: from this Mac and quiet → this Mac", ask(me: true, q: true, n: 5) == .openOnMac("this Mac"))
check("step 4 with the cable's facts but a claim missing: this Mac", ask(seen: true, claimed: false, me: true) == .openOnMac("this Mac"))
check("step 5: quiet → openOnMac(quiet)", ask(q: true) == .openOnMac("quiet"))
check("step 5: quiet before often", ask(q: true, n: 3) == .openOnMac("quiet"))
check("step 5: 3 device-opened windows in 10 minutes → often; 2 → a window", ask(n: 3) == .openOnMac("often") && ask(n: 2) == .shown(opened: true))
check("step 6: otherwise a window opens", ask() == .shown(opened: true))
check("the often threshold is AskLimits.maxWindows (3)", AskLimits.maxWindows == 3)

// Kind 20 and the menu for each answer.
let answers: [D.Ask] = [.pairNow, .shown(opened: true), .shown(opened: false), .openOnMac("this Mac"), .openOnMac("quiet"), .openOnMac("often"), .locked]
check("kind 20 reasons: pairNow is an ok; shown, openOnMac, locked",
      answers.map { D.reason($0) } == [nil, "shown", "shown", "openOnMac", "openOnMac", "openOnMac", "locked"])
check("kind 20 reason constants are the plan's strings", PairResult.shown == "shown" && PairResult.openOnMac == "openOnMac" && PairResult.locked == "locked")
check("the menu from another device: showing only for a window this ask opened; locked; limit for quiet and often; nothing for a pairing",
      answers.map { D.menuRequest($0, fromThisMac: false) } == [nil, "showing", nil, "limit", "limit", "limit", "locked"])
check("the menu: an ask from this Mac never lights it, whatever the answer (locked included)",
      answers.allSatisfy { D.menuRequest($0, fromThisMac: true) == nil })

// MARK: From this Mac

// The owner table of a Mac like this one (InterfaceSnapshot keeps link-local addresses with the
// scope bytes cleared; one entry here keeps them, as getifaddrs gives them, to check both sides are
// compared without it).
func ip(_ s: String) -> [UInt8] { IPBytes.parse(s)! }
var embedded = ip("fe80::cafe:1"); embedded[2] = 0x00; embedded[3] = 0x0e     // fe80:e::cafe:1, scope 14 embedded
let own: Set<[UInt8]> = [ip("10.128.0.34"), ip("fe80::47b:5945:e0aa:d0ac"), ip("2601:600:1:2::34"), ip("fd4e:4f6b:37dc:4a0f::34"),
                         ip("169.254.178.234"), ip("fe80::18c0:1:2:3"), ip("fe80::aa:bb"), ip("100.101.102.103"), ip("fd7a:115c:a1e0::1234"),
                         ip("192.168.64.1"), embedded]
check("from this Mac: 127.0.0.1, 127.5.5.5, ::1, ::ffff:127.0.0.1",
      ["127.0.0.1", "127.5.5.5", "::1", "::ffff:127.0.0.1"].allSatisfy { D.isFromThisMac(source: ip($0), ownAddresses: own) })
let mapped: ([UInt8]) -> [UInt8] = { [UInt8](repeating: 0, count: 10) + [0xFF, 0xFF] + $0 }
check("from this Mac: an IPv4-mapped source given as 16 bytes (loopback, and this Mac's own IPv4)",
      D.isFromThisMac(source: mapped([127, 0, 0, 1]), ownAddresses: own) && D.isFromThisMac(source: mapped(ip("10.128.0.34")), ownAddresses: own)
      && D.isFromThisMac(source: ip("10.128.0.34"), ownAddresses: [mapped(ip("10.128.0.34"))])
      && !D.isFromThisMac(source: mapped(ip("10.128.0.41")), ownAddresses: own))
check("from this Mac: every one of this Mac's own addresses (\(own.count), IPv4 and IPv6, fe80 and 169.254 on the cable's interface too)",
      own.allSatisfy { D.isFromThisMac(source: $0, ownAddresses: own) })
check("from this Mac: the Simulator's source on en14 (169.254.178.234, 2026-09-24)", D.isFromThisMac(source: ip("169.254.178.234"), ownAddresses: own))
check("from this Mac: an own link-local address stored with its embedded scope matches the source without it",
      D.isFromThisMac(source: ip("fe80::cafe:1"), ownAddresses: own))
check("from this Mac: an own link-local source with an embedded scope matches the stored one", D.isFromThisMac(source: embedded, ownAddresses: [ip("fe80::cafe:1")]))
check("not from this Mac: the iPad on the cable, on Wi-Fi, a LAN peer, a VM behind bridge100",
      ["fe80::18fe:abff:febb:459f", "fe80::18c2:af60:ec0d:47ea", "fe80::8425:bdff:fe62:8930", "10.128.0.41", "192.168.64.5", "2601:600:1:2::41"]
        .allSatisfy { !D.isFromThisMac(source: ip($0), ownAddresses: own) })
check("not from this Mac: an empty or malformed address", !D.isFromThisMac(source: [], ownAddresses: own) && !D.isFromThisMac(source: [127, 0, 0], ownAddresses: own))

// MARK: One key per device over the cable

let list: [(fingerprint: String, cableDevice: String?)] = [("A", "dev1"), ("B", nil), ("C", "dev2")]
check("other key: the same key may pair again", !D.otherKeyOfDevice("dev1", fingerprint: "A", paired: list))
check("other key: a new key from a device another key carries", D.otherKeyOfDevice("dev1", fingerprint: "D", paired: list))
check("other key: a device no key carries", !D.otherKeyOfDevice("dev3", fingerprint: "D", paired: list))
check("other key: a key without a cable ID asking for a device another key carries", D.otherKeyOfDevice("dev2", fingerprint: "B", paired: list))
check("other key: after Remove (the list without A) the device is free", !D.otherKeyOfDevice("dev1", fingerprint: "D", paired: Array(list.dropFirst())))

// MARK: Test hooks

check("test host: does not advertise and is not a .app's executable",
      D.isTestHost(advertises: false, bundled: false) && !D.isTestHost(advertises: false, bundled: true)
      && !D.isTestHost(advertises: true, bundled: false) && !D.isTestHost(advertises: true, bundled: true))
let hook = ["SILL_TEST_ASK_FROM_THIS_MAC": "1"]
check("SILL_TEST_ASK_FROM_THIS_MAC=1: honoured on a test host", D.testAsksAsDevice(testHost: true, environment: hook))
check("SILL_TEST_ASK_FROM_THIS_MAC=1: ignored by a host that is not a test host (the bundle, an advertising host)",
      !D.testAsksAsDevice(testHost: D.isTestHost(advertises: false, bundled: true), environment: hook)
      && !D.testAsksAsDevice(testHost: D.isTestHost(advertises: true, bundled: false), environment: hook))
check("SILL_TEST_ASK_FROM_THIS_MAC: only \"1\"", ["0", "", "yes", "true", " 1", "1 "].allSatisfy { !D.testAsksAsDevice(testHost: true, environment: ["SILL_TEST_ASK_FROM_THIS_MAC": $0]) }
      && !D.testAsksAsDevice(testHost: true, environment: [:]))

// The whole of step 4 as the host will compose it: fromThisMac = isFromThisMac && !testAsksAsDevice.
func composed(_ source: String, testHost: Bool, env: [String: String]) -> (D.Ask, String?) {
    let me = D.isFromThisMac(source: ip(source), ownAddresses: own) && !D.testAsksAsDevice(testHost: testHost, environment: env)
    let a = ask(me: me)
    return (a, D.menuRequest(a, fromThisMac: me))
}
check("composed: an ask from this Mac's own fe80 on Sill.app → openOnMac, no menu", composed("fe80::47b:5945:e0aa:d0ac", testHost: false, env: hook) == (.openOnMac("this Mac"), nil))
check("composed: the same from 127.0.0.1 on a test host with the hook → a window and the menu", composed("127.0.0.1", testHost: true, env: hook) == (.shown(opened: true), "showing"))
check("composed: the same on a test host without the hook → openOnMac, no menu", composed("127.0.0.1", testHost: true, env: [:]) == (.openOnMac("this Mac"), nil))
check("composed: another device → a window and the menu", composed("fe80::18fe:abff:febb:459f", testHost: false, env: [:]) == (.shown(opened: true), "showing"))

// A stranger's asks against the limits, through AskLimits and the rule together.
var limits = AskLimits()
var now = 1000.0
var answersSeen: [D.Ask] = []
for i in 0..<4 {
    let key = Data([UInt8(i)]), src = "10.0.0.\(i)"
    let a = ask(q: limits.quiet(fingerprint: key, source: src, now: now), n: limits.recentWindows(now: now))
    answersSeen.append(a)
    if a == .shown(opened: true) {
        limits.opened(now: now)
        limits.closedUnused(fingerprint: key, source: src, now: now + 10)     // cancelled on the Mac
    }
    now += 60
}
check("a stranger with four keys and four addresses: three windows, then often", answersSeen == [.shown(opened: true), .shown(opened: true), .shown(opened: true), .openOnMac("often")])
check("the first asker, 3 minutes after its window was cancelled: quiet", ask(q: limits.quiet(fingerprint: Data([0]), source: "10.0.0.9", now: 1190), n: 0) == .openOnMac("quiet"))
check("11 minutes after the first window: a new asker gets a window again", ask(q: limits.quiet(fingerprint: Data([9]), source: "10.0.0.9", now: 1000 + 660), n: limits.recentWindows(now: 1000 + 660)) == .shown(opened: true))

print(fails == 0 ? "ALL PASS (\(passes))" : "\(fails) FAIL, \(passes) pass")
if fails > 0 { exit(1) }
