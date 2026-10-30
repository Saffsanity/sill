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

// MARK: Still served (security scan finding 10, the review of PR #254)
//
// The coordinator asks, as it registers a session, whether the Mac still serves it: a session the door
// admitted while the Mac was deciding a change that cuts it off (Remove, Require pairing turned on, Remote
// Access or internet access turned off: the decision saves it first, a keychain write or its prompt)
// registers on the main actor only behind that decision, which could not name it. Judged as afterGate
// judges a session the device gate held, the remote door's limit no cut, and a plain session (no key: the
// plain home door) never cut off.
var ss = 0, ssOK = 0
for door in [D.Door.home, .remote] { for w in [false, true] { for o in origins { for t in allTrusts() { for enc in [false, true] {
    ss += 1
    let want = !enc || afterGateOracle(door, wasPaired: w, o, t, 0) == nil
    if D.stillServes(door, encrypted: enc, wasPaired: w, origin: o, t) == want { ssOK += 1 }
    else { print("  stillServes \(door) encrypted \(enc) wasPaired \(w) \(o) \(t): \(!want)") }
} } } } }
check("still served: \(ssOK) of \(ss) combinations (both doors, TLS or plain, paired at admission or not, every origin) match", ss == ssOK)
check("still served: Remove at home cuts the key off, with Require pairing on or off",
      !D.stillServes(.home, encrypted: true, wasPaired: true, origin: .lan, T(paired: false, requirePairing: true))
      && !D.stillServes(.home, encrypted: true, wasPaired: true, origin: .lan, T(paired: false, requirePairing: false)))
check("still served: the same key admitted again as an unpaired one at the open door (Require pairing off) is served",
      D.stillServes(.home, encrypted: true, wasPaired: false, origin: .lan, T(paired: false, requirePairing: false)))
check("still served: Require pairing turned on cuts an unpaired key off, never a paired one",
      !D.stillServes(.home, encrypted: true, wasPaired: false, origin: .direct, T(paired: false, requirePairing: true))
      && D.stillServes(.home, encrypted: true, wasPaired: true, origin: .direct, T(paired: true, requirePairing: true)))
check("still served: Remove, Remote Access off and internet access off at the remote door",
      !D.stillServes(.remote, encrypted: true, wasPaired: true, origin: .vpn, T(paired: false, remoteAccess: true))
      && !D.stillServes(.remote, encrypted: true, wasPaired: true, origin: .vpn, T(paired: true, remoteAccess: false))
      && !D.stillServes(.remote, encrypted: true, wasPaired: true, origin: .internet, T(paired: true, remoteAccess: true, internetAccess: false))
      && [OriginPolicy.Origin.loopback, .lan, .vpn].allSatisfy { D.stillServes(.remote, encrypted: true, wasPaired: true, origin: $0, T(paired: true, remoteAccess: true, internetAccess: false)) })
check("still served: nothing changed, at either door, and the remote door's limit is no cut",
      D.stillServes(.remote, encrypted: true, wasPaired: true, origin: .internet, full)
      && D.stillServes(.home, encrypted: true, wasPaired: true, origin: .lan, full))
check("still served: a plain session (no key), whatever the switches", allTrusts().allSatisfy { t in origins.allSatisfy { o in
    D.stillServes(.home, encrypted: false, wasPaired: false, origin: o, T(hasKey: false, paired: false, requirePairing: t.requirePairing, remoteAccess: t.remoteAccess)) } })

// MARK: The one kind 19

check("kind 19 at home: ask → the ask rule", D.pairing(.home, method: "ask", version: 1) == .ask)
check("kind 19 at home: qr and code → the window", D.pairing(.home, method: "qr", version: 1) == .window && D.pairing(.home, method: "code", version: 1) == .window)
check("kind 19 at home: an unknown method → the window, which counts it as a wrong proof (the remote door's rule)",
      ["icloud", "", "ASK", "Ask", "ask "].allSatisfy { D.pairing(.home, method: $0, version: 1) == .window })
check("kind 19 at the remote door: ask → closed, never the window and never the ask rule", D.pairing(.remote, method: "ask", version: 1) == .closed)
check("kind 19 at the remote door: qr, code and unknown methods → the window, as before",
      ["qr", "code", "icloud", "", "ASK"].allSatisfy { D.pairing(.remote, method: $0, version: 1) == .window })
check("PairRequest.ask is the method the door looks for", PairRequest.ask == "ask")
// The device's own Cancel (the security review, 2026-09-27): at home the window its ask opened is
// withdrawn; the remote door answers it closed; never the window, which would count a wrong code.
check("kind 19 cancel at home: withdraw, never the window", D.pairing(.home, method: "cancel", version: 1) == .withdraw)
check("kind 19 cancel at the remote door: closed", D.pairing(.remote, method: "cancel", version: 1) == .closed)
check("kind 19 cancel of another generation: closed at both doors",
      D.pairing(.home, method: "cancel", version: 2) == .closed && D.pairing(.remote, method: "cancel", version: 2) == .closed)
check("PairRequest.cancel is the method the door looks for, spelled exactly", PairRequest.cancel == "cancel"
      && ["Cancel", "CANCEL", "cancel "].allSatisfy { D.pairing(.home, method: $0, version: 1) == .window })
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

// The menu's "An iPhone or iPad Needs Sill Updated" (the security review, 2026-09-27): a TLS 1.2
// client fails with -9836 too, but tries once; an older Sill tries again and again (a tap, then its
// reconnect every 2 to 10 s). The item waits for a source's third plain try within a minute.
check("older Sill: 3 tries in 60 s", D.olderSillTries == 3 && D.olderSillSpan == 60)
var tries: [Double] = []
var shown: [Bool] = []
for t in [100.0, 102, 106] { let r = D.olderSillTry(tries, now: t); tries = r.tries; shown.append(r.shown) }
check("older Sill: one try (a TLS 1.2 scanner) shows nothing, nor a second; the third within a minute does", shown == [false, false, true])
check("older Sill: every later try shows it too, while three are within the minute", D.olderSillTry(tries, now: 116).shown && D.olderSillTry(tries, now: 150).shown)
check("older Sill: tries a minute apart never add up", D.olderSillTry(D.olderSillTry(D.olderSillTry([], now: 0).tries, now: 60).tries, now: 120) == ([120], false))
check("older Sill: a try exactly 60 s old no longer counts", D.olderSillTry([0, 30], now: 60) == ([30, 60], false)
      && D.olderSillTry([0.1, 30], now: 60) == ([0.1, 30, 60], true))
check("older Sill: an older Sill's reconnect (2, 4, 8, 10 s apart) shows it at its third try",
      { var t: [Double] = []; var at = 0.0; var n = 0
        for gap in [0.0, 2, 4, 8, 10] { at += gap; n += 1; let r = D.olderSillTry(t, now: at); t = r.tries; if r.shown { return n == 3 } }
        return false }())

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

// MARK: The places waiting for admission (finding 9 of the security scan of 2026-10-18)
//
// A door held 8 connections waiting for admission, 2 per address, for up to 10 s each, and counted
// only its own refusals toward an address's backoff: a client closing each connection at 9.9 s from
// four addresses kept every place full for good, and a paired device got "limit". Now waiting costs
// its source, the handshake has 4 s, an IPv6 address answers for its /64 too, and 2 more places are
// kept for addresses that recently proved a paired key. The model further down runs the scan's
// attack and its variants against DoorPolicy.Places and against the rule before it (`OldPlaces`,
// Door.swift at 150479b5), with a paired device trying every 2 s.

typealias Places = DoorPolicy.Places
typealias Src = DoorPolicy.Source
func near(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }
func v4(_ a: String) -> Src { Src(address: a, group: a) }
func src(_ s: String, _ scope: String? = nil) -> Src { D.source(ip(s), scope: scope) }
check("places: 8 for anyone, 2 more for known addresses, 2 per source",
      D.sharedPlaces == 8 && D.reservedPlaces == 2 && D.placesPerSource == 2)
check("places: 4 s to be ready (10 s from a known address), then 4 s for the kind 19, 10 s at most from accept",
      D.handshakeDeadline == 4 && D.requestDeadline == 4 && D.admissionDeadline == 10)
check("places: 2 s waited for a tenth of a failure, a tenth a second at least; 5 failures in 60 s → an address refused for 300 s, 12 in 300 s → its /64; known for a day",
      D.freeHold == 2 && D.endCost == 0.1 && D.waitCost == 0.1 && D.failureWindow == 60 && D.failuresForBackoff == 5 && D.groupFailureWindow == 300
      && D.groupFailuresForBackoff == 12 && D.backoffSeconds == 300 && D.knownFor == 86_400)

// What a connection that ends unadmitted costs.
check("charge: ended within a second → a tenth (0 s, 0.5 s, 1 s)",
      near(D.charge(held: 0, refused: false), 0.1) && near(D.charge(held: 0.5, refused: false), 0.1) && near(D.charge(held: 1, refused: false), 0.1))
// The review of 2026-10-29, its second pass: a tenth for each second waited at least. With the tenth
// alone, a connection closed at 2 s cost a twentieth a second, 3 a minute, under an address's 5: one
// connection at a time from each of eight addresses held every shared place for good.
check("charge: a tenth a second at least between 1 and 2.25 s (1.5 s 0.15, 1.99 s 0.199, 2 s 0.2, 2.25 s 0.225; 2.5 s 0.35 as before)",
      near(D.charge(held: 1.5, refused: false), 0.15) && near(D.charge(held: 1.99, refused: false), 0.199) && near(D.charge(held: 2, refused: false), 0.2)
      && near(D.charge(held: 2.25, refused: false), 0.225) && near(D.charge(held: 2.5, refused: false), 0.35))
check("charge: a place held costs a tenth a second at least, however long its connections (every 0.05 s up to 10 s)",
      stride(from: 0.05, through: 10, by: 0.05).allSatisfy { D.charge(held: $0, refused: false) + 1e-12 >= $0 * D.waitCost })
check("charge: one failure for every 2 s beyond the first 2: 3 s 0.6, 4 s 1.1, 9.9 s 4.05",
      near(D.charge(held: 3, refused: false), 0.6) && near(D.charge(held: 4, refused: false), 1.1) && near(D.charge(held: 9.9, refused: false), 4.05))
check("charge: a refusal costs at least one failure, as before, and more for a place held long (3.9 s 1.05, 9.9 s 4.05)",
      near(D.charge(held: 0, refused: true), 1) && near(D.charge(held: 2.5, refused: true), 1)
      && near(D.charge(held: 3.9, refused: true), 1.05) && near(D.charge(held: 9.9, refused: true), 4.05))
let heldSteps = stride(from: 0.0, through: 12, by: 0.25).map { D.charge(held: $0, refused: false) }
check("charge: a place never costs less the longer it is held", heldSteps == heldSteps.sorted())

// When a waiting connection is refused.
check("deadline: 4 s to be ready; a known address 10 s", D.deadline(known: false, readyAfter: nil) == 4 && D.deadline(known: true, readyAfter: nil) == 10)
check("deadline: once ready, 4 s for the kind 19 (ready at 0.05 s → 4.05, at 3 s → 7), never past 10 s",
      near(D.deadline(known: false, readyAfter: 0.05), 4.05) && near(D.deadline(known: false, readyAfter: 3), 7)
      && near(D.deadline(known: true, readyAfter: 1), 5) && near(D.deadline(known: true, readyAfter: 8), 10) && near(D.deadline(known: false, readyAfter: 9.5), 10))

// A source: its address, and its group.
check("source: an IPv4 address is its own group", src("10.128.0.41") == v4("10.128.0.41") && src("127.0.0.1") == v4("127.0.0.1")
      && src("169.254.219.184", "en14") == v4("169.254.219.184"))
check("source: an IPv4-mapped address given as 16 bytes is its IPv4 address", D.source(mapped(ip("10.128.0.41")), scope: nil) == v4("10.128.0.41"))
check("source: an IPv6 address, and its /64 (two privacy addresses of one host share it; the next /64 is another)",
      src("2601:600:1:2:aaaa:bbbb:cccc:dddd") == Src(address: "2601:600:1:2:aaaa:bbbb:cccc:dddd", group: "2601:600:1:2::/64")
      && src("2601:600:1:2::41").group == "2601:600:1:2::/64" && src("2601:600:1:3::41").group == "2601:600:1:3::/64")
check("source: a ULA, Tailscale's IPv6 and ::1 by their /64", src("fd4e:4f6b:37dc:4a0f::34").group == "fd4e:4f6b:37dc:4a0f::/64"
      && src("fd7a:115c:a1e0::453a:8e38").group == "fd7a:115c:a1e0::/64" && src("::1") == Src(address: "::1", group: "::/64"))
check("source: a link-local address with its interface, its /64 with it too (fe80::/64 is every link's)",
      src("fe80::18fe:abff:febb:459f", "en0") == Src(address: "fe80::18fe:abff:febb:459f%en0", group: "fe80::/64%en0")
      && src("fe80::1", "anpi0") == Src(address: "fe80::1%anpi0", group: "fe80::/64%anpi0") && src("fe80::1") == Src(address: "fe80::1%", group: "fe80::/64%"))
check("source: a link-local address with the kernel's embedded scope is the same source",
      D.source(embedded, scope: "en0") == Src(address: "fe80::cafe:1%en0", group: "fe80::/64%en0"))
check("source: an address never reads as a group (their records never meet)",
      [src("10.0.0.1"), src("2601:600:1:2::1"), src("fe80::1", "en0"), src("::1")].allSatisfy { !$0.address.contains("/") }
      && [src("2601:600:1:2::1"), src("fe80::1", "en0"), src("::1")].allSatisfy { $0.group.contains("/64") })

// Arrivals: the shared places, the reserved ones, one source's two.
var pl = Places()
var takenAll = true
for (i, a) in ["10.0.0.1", "10.0.0.2", "10.0.0.3", "10.0.0.4"].enumerated() {
    for j in 0..<2 { takenAll = takenAll && pl.arrive(i * 2 + j, v4(a), now: 0) == .taken(known: false) }
}
check("arrive: 8 waiting from 4 addresses take the 8 shared places", takenAll && pl.pending.count == 8)
check("arrive: a 9th from a new address is refused, every place it may take held", pl.arrive(100, v4("10.0.0.5"), now: 0) == .full)
var one = Places()
_ = one.arrive(1, v4("10.0.0.1"), now: 0); _ = one.arrive(2, v4("10.0.0.1"), now: 0)
check("arrive: a third from one address is refused (it waits in 2)", one.arrive(3, v4("10.0.0.1"), now: 0) == .source)
var v6 = Places()
check("arrive: two IPv6 addresses of one /64 take its 2 places; a third address in it is refused; another /64 is not",
      v6.arrive(1, src("2601:600:1:2::a"), now: 0) == .taken(known: false) && v6.arrive(2, src("2601:600:1:2::b"), now: 0) == .taken(known: false)
      && v6.arrive(3, src("2601:600:1:2::c"), now: 0) == .source && v6.arrive(4, src("2601:600:1:3::c"), now: 0) == .taken(known: false))
var ll = Places()
check("arrive: link-local addresses on one interface share 2 places; on another interface they have their own",
      ll.arrive(1, src("fe80::a", "en0"), now: 0) == .taken(known: false) && ll.arrive(2, src("fe80::b", "en0"), now: 0) == .taken(known: false)
      && ll.arrive(3, src("fe80::c", "en0"), now: 0) == .source && ll.arrive(4, src("fe80::c", "awdl0"), now: 0) == .taken(known: false))

// Known: a paired key at `.ready` makes its address known for a day.
var kn = Places()
_ = kn.arrive("d", v4("10.0.0.9"), now: 0)
check("known: not before it proves a paired key", !kn.isKnown("10.0.0.9", now: 0))
kn.leave("d", .admitted(paired: true), now: 0.05)
check("known: a paired key at .ready makes its address known", kn.isKnown("10.0.0.9", now: 1))
check("known: for a day, by its address only", kn.isKnown("10.0.0.9", now: 0.05 + 86_399.9) && !kn.isKnown("10.0.0.9", now: 0.05 + 86_400) && !kn.isKnown("10.0.0.8", now: 1))
var ku = Places()
_ = ku.arrive("u", v4("10.0.0.7"), now: 0)
ku.leave("u", .admitted(paired: false), now: 0.05)
check("known: an unpaired key admitted (Require pairing off) makes nobody known", !ku.isKnown("10.0.0.7", now: 1))
var kq = Places()
_ = kq.arrive("q", v4("10.0.0.8"), now: 0)
kq.leave("q", .request, now: 0.05)
check("known: a pairing connection's kind 19 makes nobody known", !kq.isKnown("10.0.0.8", now: 1))
for (i, a) in ["10.0.1.1", "10.0.1.2", "10.0.1.3", "10.0.1.4"].enumerated() {
    for j in 0..<2 { _ = kn.arrive("s\(i)\(j)", v4(a), now: 2) }
}
check("arrive: with the 8 shared places held, a known address takes the 2 reserved ones",
      kn.arrive("k1", v4("10.0.0.9"), now: 2) == .taken(known: true) && kn.arrive("k2", v4("10.0.0.9"), now: 2) == .taken(known: true))
check("arrive: no 11th place, even for a known address", kn.arrive("k3", v4("10.0.0.9"), now: 2) == .full)
check("arrive: no reserved place for an address that is not known", kn.arrive("x", v4("10.0.0.6"), now: 2) == .full)
var kc = Places()
_ = kc.arrive("p", v4("10.0.0.9"), now: 0); kc.leave("p", .admitted(paired: true), now: 0)
_ = kc.arrive(1, v4("10.0.0.9"), now: 1); _ = kc.arrive(2, v4("10.0.0.9"), now: 1)
check("arrive: a known address waits in 2 at most, too", kc.arrive(3, v4("10.0.0.9"), now: 1) == .source)
// Known connections wait in the reserved places first, leaving the shared ones to everyone.
var kr = Places()
for (n, a) in ["10.0.2.1", "10.0.2.2"].enumerated() { _ = kr.arrive("p\(n)", v4(a), now: 0); kr.leave("p\(n)", .admitted(paired: true), now: 0) }
_ = kr.arrive("ka", v4("10.0.2.1"), now: 1); _ = kr.arrive("kb", v4("10.0.2.2"), now: 1)
var krOK = true
for n in 0..<8 { krOK = krOK && kr.arrive("u\(n)", v4("10.0.3.\(n / 2)"), now: 1) == .taken(known: false) }
check("arrive: 2 known waiting leave all 8 shared places to the others; the 9th other is refused",
      krOK && kr.arrive("u9", v4("10.0.3.9"), now: 1) == .full)
var kr3 = Places()
for (n, a) in ["10.0.2.1", "10.0.2.2"].enumerated() { _ = kr3.arrive("p\(n)", v4(a), now: 0); kr3.leave("p\(n)", .admitted(paired: true), now: 0) }
for n in 0..<3 { _ = kr3.arrive("k\(n)", v4(n < 2 ? "10.0.2.1" : "10.0.2.2"), now: 1) }
var kr3OK = true
for n in 0..<7 { kr3OK = kr3OK && kr3.arrive("u\(n)", v4("10.0.3.\(n / 2)"), now: 1) == .taken(known: false) }
check("arrive: a 3rd known waiting takes a shared place: 7 others then fill them, and the 8th other is refused",
      kr3OK && kr3.arrive("u7", v4("10.0.3.7"), now: 1) == .full && kr3.pending.count == 10)
// Two known devices and a stranger in one /64: the known ones count by their addresses.
var k6 = Places()
for (n, a) in ["2601:600:1:2::a", "2601:600:1:2::b"].enumerated() { _ = k6.arrive("p\(n)", src(a), now: 0); k6.leave("p\(n)", .admitted(paired: true), now: 0) }
var k6ok = true
for (n, a) in ["2601:600:1:2::a", "2601:600:1:2::b"].enumerated() { for j in 0..<2 { k6ok = k6ok && k6.arrive("q\(n)\(j)", src(a), now: 1) == .taken(known: true) } }
check("arrive: two known addresses of one /64 wait in 2 places each; strangers in the /64 still take its 2",
      k6ok && k6.arrive("s1", src("2601:600:1:2::c"), now: 1) == .taken(known: false)
      && k6.arrive("s2", src("2601:600:1:2::d"), now: 1) == .taken(known: false)
      && k6.arrive("s3", src("2601:600:1:2::e"), now: 1) == .source)

// Charges and the backoff.
var bo = Places()
var backedAt: [[String]] = []
for t in 0..<5 { backedAt.append(bo.refusedBeforeStart(v4("10.0.0.2"), now: Double(t))) }
check("backoff: the fifth failure within a minute backs the address off, and says so once", backedAt == [[], [], [], [], ["10.0.0.2"]])
check("backoff: refused for 300 s from the fifth", bo.backedOff(v4("10.0.0.2"), now: 4) && bo.backedOff(v4("10.0.0.2"), now: 303.9)
      && !bo.backedOff(v4("10.0.0.2"), now: 304))
check("backoff: an arrival meanwhile is refused for it, and takes no place", bo.arrive(1, v4("10.0.0.2"), now: 10) == .backedOff && bo.pending.isEmpty)
check("backoff: an arrival refused for it costs nothing more", near(bo.failures("10.0.0.2", now: 10), 0))
var hookSeconds = Places(backoff: 5)
for t in 0..<5 { _ = hookSeconds.refusedBeforeStart(v4("a"), now: Double(t)) }
check("backoff: the test hook's seconds replace the 300", hookSeconds.backedOff(v4("a"), now: 8.9) && !hookSeconds.backedOff(v4("a"), now: 9))
var win = Places()
for t in [0.0, 1, 2, 3] { _ = win.refusedBeforeStart(v4("w"), now: t) }
check("backoff: failures a minute old no longer count (4 at 0–3 s, one at 62 s: 2 within the minute)",
      win.refusedBeforeStart(v4("w"), now: 62).isEmpty && near(win.failures("w", now: 62), 2))
var win2 = Places()
for t in [0.0, 1, 2, 3] { _ = win2.refusedBeforeStart(v4("w"), now: t) }
check("backoff: 5 within 59.9 s do", win2.refusedBeforeStart(v4("w"), now: 59.9) == ["w"])
var tenths = Places()
var tenthAt = -1
for n in 1...50 {
    _ = tenths.arrive(n, v4("t"), now: Double(n))
    if !tenths.leave(n, .ended, now: Double(n) + 0.5).isEmpty, tenthAt < 0 { tenthAt = n }
}
check("backoff: 50 connections that ended within 2 s back the address off at the 50th (a tenth each, summed with a margin)", tenthAt == 50)

// The /64: more than one address's worth backs it off, never one address alone.
var g12 = Places()
var g12At = -1
for n in 0..<12 {
    let s = src("2601:600:1:2::\(n + 1)")
    _ = g12.arrive(n, s, now: 0)
    if g12.leave(n, .refused, now: 0.1).contains("2601:600:1:2::/64"), g12At < 0 { g12At = n + 1 }
}
check("group: twelve addresses of one /64 refused once each back the /64 off at the 12th", g12At == 12
      && g12.backedOff(src("2601:600:1:2::99"), now: 1) && !g12.backedOff(src("2601:600:1:3::1"), now: 1))
check("group: no address of it is backed off itself (1 each)", !(1...12).contains { g12.backedOff(Src(address: "2601:600:1:2::\($0)", group: "nowhere"), now: 1) })
var gOne = Places()
var gOneBacked: [String] = []
for n in 0..<100 {
    let t = Double(n) * 0.5
    if case .taken = gOne.arrive(n, src("2601:600:1:2::7"), now: t) { gOneBacked += gOne.leave(n, .refused, now: t + 0.1) }
}
check("group: one address refused again and again backs itself off at its fifth, never its /64",
      gOneBacked == ["2601:600:1:2::7"] && near(gOne.failures("2601:600:1:2::/64", now: 49.9), 5) && !gOne.backedOff(src("2601:600:1:2::8"), now: 50))
var gTwo = Places()
for a in ["2601:600:1:2::7", "2601:600:1:2::8"] { for n in 0..<20 { if case .taken = gTwo.arrive("\(a)\(n)", src(a), now: Double(n)) { gTwo.leave("\(a)\(n)", .refused, now: Double(n) + 0.1) } } }
check("group: two such addresses (10 failures) leave the /64 open to its others", !gTwo.backedOff(src("2601:600:1:2::9"), now: 21) && near(gTwo.failures("2601:600:1:2::/64", now: 21), 10))
// The most one address not yet known adds: 4.95 in tenths and refusals, then its /64's two places
// waiting for a kind 19 that never comes, cut at 8 s (ready at 3.99 s, then 4 s): 3.1 each.
let a7 = src("2601:600:1:2::7")
var gMostTrim = Places()
for n in 0..<4 { _ = gMostTrim.refusedBeforeStart(a7, now: 0) }
for n in 0..<9 { _ = gMostTrim.arrive("t\(n)", a7, now: 1); gMostTrim.leave("t\(n)", .ended, now: 1.5) }
_ = gMostTrim.arrive("a", a7, now: 2); _ = gMostTrim.arrive("b", a7, now: 2)
gMostTrim.ready("a", now: 5.99); gMostTrim.ready("b", now: 5.99)
let cutAt = gMostTrim.deadline("a") ?? -1
var gMostBacked = gMostTrim.leave("a", .refused, now: cutAt) + gMostTrim.leave("b", .refused, now: cutAt)
for n in 0..<20 { if case .taken = gMostTrim.arrive("c\(n)", a7, now: 11 + Double(n)) { gMostBacked += gMostTrim.leave("c\(n)", .refused, now: 15 + Double(n)) } }
check("group: the most one address not yet known adds before it is backed off (4.9, then its two places cut at 8 s: 11.1) counts for its share, \(String(format: "%.2f", gMostTrim.failures("2601:600:1:2::/64", now: 40))), and leaves its /64 open",
      near(cutAt, 9.99) && gMostBacked == ["2601:600:1:2::7"] && near(gMostTrim.failures("2601:600:1:2::/64", now: 40), D.groupShare)
      && !gMostTrim.backedOff(src("2601:600:1:2::8"), now: 40))
// The review of 2026-10-29, its second pass: an address's own backoff (5 in 60 s) does not bound what
// it adds over the /64's 300 s. Paced under it, one address alone backed its /64 off: an older Sill's
// plain try every 2 s on its link-local address (a tenth each, 3 a minute) backed off its whole link,
// fe80::/64%en0, at 238 s, and a device not yet known there was refused; one refusal every 16 s (4 a
// minute), at 176 s. Now an address counts for `groupShare` (6) at most: it takes two.
check("group: an address counts for 6 at most toward its /64, half the 12", D.groupShare == 6 && D.groupShare * 2 == D.groupFailuresForBackoff)
var gOlder = Places()
var gOlderBacked: [String] = []
for n in 0..<300 { let t = Double(n) * 2; if case .taken = gOlder.arrive(n, src("fe80::30", "en0"), now: t) { gOlderBacked += gOlder.leave(n, .ended, now: t + 0.01) } }
check("group: an older Sill's plain try every 2 s on its link-local address for 10 minutes backs off neither it nor its link (counted for \(String(format: "%.1f", gOlder.failures("fe80::/64%en0", now: 599))))",
      gOlderBacked.isEmpty && near(gOlder.failures("fe80::/64%en0", now: 599), 6) && !gOlder.backedOff(src("fe80::99", "en0"), now: 599))
func refusedEvery16(_ addresses: [String]) -> (backed: [String], at: Double?) {
    var p = Places(), backed: [String] = [], at: Double?
    for n in 0..<38 {
        for (k, a) in addresses.enumerated() {
            let t = Double(n) * 16 + Double(k) * 8
            if case .taken = p.arrive("\(a)-\(n)", src(a), now: t) {
                let b = p.leave("\(a)-\(n)", .refused, now: t + 0.1)
                if b.contains("2601:600:1:2::/64"), at == nil { at = t + 0.1 }
                backed += b
            }
        }
    }
    return (backed, at)
}
let r16one = refusedEvery16(["2601:600:1:2::7"]), r16two = refusedEvery16(["2601:600:1:2::7", "2601:600:1:2::8"])
check("group: one address refused every 16 s for 10 minutes (4 a minute, under its own 5): never backed off, nor its /64",
      r16one.backed.isEmpty)
check("group: two such addresses back the /64 off once both have given their 6 (at \(r16two.at ?? -1) s)",
      (r16two.at.map { near($0, 88.1) } ?? false) && r16two.backed.allSatisfy { $0 == "2601:600:1:2::/64" })
var gKnownPays = Places()
_ = gKnownPays.arrive("p", a7, now: 0); gKnownPays.leave("p", .admitted(paired: true), now: 0)
var gKnownBacked: [String] = []
for n in 0..<5 { _ = gKnownPays.arrive(n, a7, now: Double(n)); gKnownBacked += gKnownPays.leave(n, .ended, now: Double(n) + 9.9) }
check("group: a known address's waits cost it (five 9.9 s, 1.1 each: backed off at the fifth), never its /64",
      gKnownBacked == ["2601:600:1:2::7"] && near(gKnownPays.failures("2601:600:1:2::/64", now: 11), 0))
var gSlow = Places()
for n in 0..<11 { _ = gSlow.refusedBeforeStart(src("2601:600:1:2::\(n + 1)"), now: Double(n) * 15) }
check("group: its failures count for 300 s (11 between 0 and 150 s, the 12th at 299.9 s backs it off; at 300 s the first has gone)",
      { var g = gSlow; return g.refusedBeforeStart(src("2601:600:1:2::99"), now: 299.9) == ["2601:600:1:2::/64"] }()
      && { var g = gSlow; return g.refusedBeforeStart(src("2601:600:1:2::99"), now: 300).isEmpty }())
check("group: an address's own failures still count for 60 s only", { var g = Places()
    for t in [0.0, 1, 2, 3] { _ = g.refusedBeforeStart(src("2601:600:1:2::5"), now: t) }
    return g.refusedBeforeStart(src("2601:600:1:2::5"), now: 61).isEmpty && near(g.failures("2601:600:1:2::5", now: 61), 3)
        && near(g.failures("2601:600:1:2::/64", now: 61), 5) }())
var gKnown = Places()
_ = gKnown.arrive("p", src("2601:600:1:2::a"), now: 0); gKnown.leave("p", .admitted(paired: true), now: 0)
for n in 0..<15 { _ = gKnown.refusedBeforeStart(src("2601:600:1:2::\(n + 10)"), now: 1) }
check("group: a known address in a backed-off /64 is not refused for it; a stranger in it is",
      !gKnown.backedOff(src("2601:600:1:2::a"), now: 2) && gKnown.arrive(9, src("2601:600:1:2::a"), now: 2) == .taken(known: true)
      && gKnown.arrive(10, src("2601:600:1:2::f"), now: 2) == .backedOff)
check("group: proving from an IPv6 address leaves its /64's backoff alone", { var b = gKnown
    _ = b.arrive("again", src("2601:600:1:2::a"), now: 3); b.leave("again", .admitted(paired: true), now: 3)
    return b.backedOff(src("2601:600:1:2::f"), now: 4) }())
var gPart = Places()
for n in 0..<4 { _ = gPart.refusedBeforeStart(src("2601:600:1:2::\(n + 10)"), now: 0) }
_ = gPart.refusedBeforeStart(src("2601:600:1:2::a"), now: 0)
_ = gPart.arrive("p", src("2601:600:1:2::a"), now: 1); gPart.leave("p", .admitted(paired: true), now: 1)
check("group: an IPv6 address that proves a paired key starts clean itself; its /64 keeps what all owed",
      near(gPart.failures("2601:600:1:2::a", now: 2), 0) && near(gPart.failures("2601:600:1:2::/64", now: 2), 5))
// A trade-off of the /64 (the plan's "What stays"): nothing is charged while it is backed off, but a
// stranger in it backs it off again with a dozen refused handshakes from new addresses as each 5
// minutes end (two places at a time), so a device not yet known there waits throughout.
var keep = Places()
var keepOpen = 0.0, keepNext = 0
for tick in 0..<9000 {
    let t = Double(tick) / 10
    if !keep.backedOff(src("2601:600:1:2::999"), now: t) { keepOpen += 0.1 }
    for _ in 0..<2 {
        keepNext += 1
        let a = src("2601:600:1:2::f:" + String(keepNext, radix: 16))
        if case .taken = keep.arrive(keepNext, a, now: t) { keep.leave(keepNext, .refused, now: t + 0.05) }
    }
}
check("group, a trade-off: a stranger in a /64 refused a dozen times from new addresses as each backoff ends keeps it backed off all but \(String(format: "%.1f", keepOpen)) s of 15 minutes",
      keepOpen < 2.5)

// Known addresses pay for what they hold: someone else at a paired device's address (behind its
// NAT, or on its address while it is away) is backed off like anyone.
var ka = Places()
_ = ka.arrive("p", v4("10.0.0.9"), now: 0); ka.leave("p", .admitted(paired: true), now: 0)
var kaBacked: [String] = []
for n in 0..<5 { _ = ka.arrive(n, v4("10.0.0.9"), now: Double(n)); kaBacked += ka.leave(n, .refused, now: Double(n) + 0.2) }
check("known: a known address refused 5 times is backed off like any other", kaBacked == ["10.0.0.9"]
      && ka.backedOff(v4("10.0.0.9"), now: 10) && ka.arrive("late", v4("10.0.0.9"), now: 10) == .backedOff)
var kh = Places()
_ = kh.arrive("p", v4("10.0.0.9"), now: 0); kh.leave("p", .admitted(paired: true), now: 0)
_ = kh.arrive("h", v4("10.0.0.9"), now: 1)
check("known: its 10 s wait costs what an address not known pays at most for its handshake (9.9 s: 1.1; the review of 2026-10-29: it was 4.05)",
      { var k = kh; k.leave("h", .ended, now: 10.9); return near(k.failures("10.0.0.9", now: 11), 1.1) }())
var b4 = Places()
for t in 0..<5 { _ = b4.refusedBeforeStart(v4("10.0.0.3"), now: Double(t)) }
check("backoff: a backed-off address takes no place, even to prove a key", b4.arrive("p", v4("10.0.0.3"), now: 5) == .backedOff && b4.pending.isEmpty)
var f4 = Places()
for t in 0..<4 { _ = f4.refusedBeforeStart(v4("10.0.0.4"), now: Double(t)) }
_ = f4.arrive("p", v4("10.0.0.4"), now: 5); f4.leave("p", .admitted(paired: true), now: 5)
check("backoff: an address that proves a paired key starts clean, as before", near(f4.failures("10.0.0.4", now: 6), 0))

// Leaving a place: what each end costs.
func cost(_ end: Places.End, held: Double, known: Bool = false, readyAfter: Double? = nil) -> Double {
    var p = Places()
    if known { _ = p.arrive("k", v4("s"), now: 0); p.leave("k", .admitted(paired: true), now: 0) }
    _ = p.arrive("c", v4("s"), now: 10)
    if let readyAfter { p.ready("c", now: 10 + readyAfter) }
    p.leave("c", end, now: 10 + held)
    return p.failures("s", now: 10 + held)
}
check("leave: admitted, paired or not, costs nothing", cost(.admitted(paired: true), held: 9) == 0 && cost(.admitted(paired: false), held: 9) == 0)
check("leave: let go by the Mac (Direct Wireless off) costs nothing", cost(.dropped, held: 9) == 0)
check("leave: ended by itself costs charge(held:)", near(cost(.ended, held: 1), 0.1) && near(cost(.ended, held: 3.9), 1.05)
      && near(cost(.ended, held: 7.9, readyAfter: 3.9), 3.05))
check("leave: a pairing connection's kind 19 costs as one that ended then, never a refusal (the review of 2026-10-29: it cost nothing)",
      near(cost(.request, held: 0.1, readyAfter: 0.05), 0.1) && near(cost(.request, held: 1.9, readyAfter: 0.05), 0.19)
      && near(cost(.request, held: 7.9, readyAfter: 3.9), 3.05))
check("leave: refused costs at least one", near(cost(.refused, held: 0.2), 1) && near(cost(.refused, held: 4), 1.1))
check("leave: a known address pays as one not known at most (9.9 s: 1.1; 3 s: 0.6; refused at once: 1)",
      near(cost(.ended, held: 9.9, known: true), 1.1) && near(cost(.ended, held: 3, known: true), 0.6) && near(cost(.refused, held: 0.2, known: true), 1))
check("leave: an IPv6 address's end costs it and its /64 alike", { var p = Places()
    _ = p.arrive("c", src("2601:600:1:2::5"), now: 0); p.leave("c", .ended, now: 3)
    return near(p.failures("2601:600:1:2::5", now: 3), 0.6) && near(p.failures("2601:600:1:2::/64", now: 3), 0.6) }())
check("leave: an id that holds no place changes nothing", { var p = Places(); return p.leave("none", .refused, now: 1).isEmpty && p.failures("x", now: 1) == 0 }())
// The review of 2026-10-29: a wait counts up to its place's deadline at most. The door's clock runs
// on through the Mac's sleep and its deadline timer does not, so a connection waiting as the Mac
// slept ended at the wake, an hour "held": it backed its address off, and an IPv6 address's /64.
check("leave: a wait counts to its deadline at most (the Mac asleep an hour with it waiting: what the cut at 4 s costs, 1.1, refused or ended; a kind 19 read at the wake, ready at 1 s: 1.6)",
      near(cost(.refused, held: 3600), 1.1) && near(cost(.ended, held: 3600), 1.1) && near(cost(.request, held: 3600, readyAfter: 1), 1.6))
check("leave: a pairing connection ready at 3 s, an hour on: what its cut at 7 s costs (2.6)", { var p = Places()
    _ = p.arrive("c", v4("s"), now: 10); p.ready("c", now: 13); p.leave("c", .ended, now: 3610)
    return near(p.failures("s", now: 3610), 2.6) }())
check("leave: a known address's an hour asleep: 1.1, as one not known", near(cost(.ended, held: 3600, known: true), 1.1))
check("leave: a known address's pairing connection ready late (at 9 s), its kind 19 at 9.9 s: 3.1 at most, as one not known can (ready by 4 s, 8 s)",
      near(cost(.request, held: 9.9, known: true, readyAfter: 9), 3.1) && near(cost(.request, held: 5, known: true, readyAfter: 1), 1.6))
var slept = Places()
_ = slept.arrive("a", src("2601:600:1:2::5"), now: 0); _ = slept.arrive("b", src("2601:600:1:2::6"), now: 0)
let sleptBacked = slept.leave("a", .refused, now: 3600) + slept.leave("b", .ended, now: 3600)
check("leave: two connections of one /64 waiting through an hour's sleep back off nothing (2.2 each address and its /64)",
      sleptBacked.isEmpty && near(slept.failures("2601:600:1:2::/64", now: 3600), 2.2) && !slept.backedOff(src("2601:600:1:2::7"), now: 3600))

// Deadlines of one place.
var dl = Places()
_ = dl.arrive("u", v4("10.0.0.1"), now: 10)
check("deadline(id): an unknown address's 4 s from accept", near(dl.deadline("u") ?? -1, 14))
dl.ready("u", now: 10.5)
check("deadline(id): once ready, 4 s from .ready", near(dl.deadline("u") ?? -1, 14.5))
dl.ready("u", now: 13)
check("deadline(id): ready counts once", near(dl.deadline("u") ?? -1, 14.5))
_ = dl.arrive("p", v4("10.0.0.9"), now: 10); dl.leave("p", .admitted(paired: true), now: 10)
_ = dl.arrive("k", v4("10.0.0.9"), now: 11)
check("deadline(id): a known address's 10 s", near(dl.deadline("k") ?? -1, 21))
check("deadline(id): none for a connection without a place", dl.deadline("nobody") == nil)

// Pruning: a scan from many addresses cannot grow the records for ever.
var pr = Places()
for n in 0..<300 { _ = pr.refusedBeforeStart(v4("a\(n)"), now: 0) }
pr.prune(now: 30)
check("prune: within the minute every charged source is kept (300)", pr.records.charged == 300)
pr.prune(now: 60)
check("prune: a minute later none is", pr.records.charged == 0)
var pb = Places(backoff: 10)
for n in 0..<300 { for t in 0..<5 { _ = pb.refusedBeforeStart(v4("b\(n)"), now: Double(t)) } }
pb.prune(now: 5)
let backedBefore = pb.records.backedOff
pb.prune(now: 14)
check("prune: backoffs kept while they run (300), dropped once over (0)", backedBefore == 300 && pb.records.backedOff == 0)
var pk = Places()
for n in 0..<300 { _ = pk.arrive(n, v4("k\(n)"), now: Double(n)); pk.leave(n, .admitted(paired: true), now: Double(n)) }
pk.prune(now: 300)
check("prune: known addresses keep the newest 256", pk.records.known == 256 && pk.isKnown("k299", now: 300) && pk.isKnown("k44", now: 300) && !pk.isKnown("k43", now: 300))
check("prune: nothing pruned at 256 or fewer", { var p = Places(); for n in 0..<256 { _ = p.refusedBeforeStart(v4("c\(n)"), now: 0) }
    p.prune(now: 100); return p.records.charged == 256 }())

// MARK: The attack, modelled
//
// Time in 10 ms ticks. Each holder keeps `placesPerSource` connections going: each connects (from
// the next of its addresses in turn), waits (TCP alone, or TLS completed with any key on the pairing
// ALPN), and closes after `hold` s unless the door's deadline refuses it first, or, with `request`,
// sends its one kind 19 that many seconds after `.ready` (the door's verify block takes the pairing
// ALPN with any key at home; a later generation's `v` is answered `closed` with nothing shown); it
// connects again at once, after an end or a refusal. A device tries every 2 s from its own address:
// its handshake takes 50 ms, then its paired key is admitted.

protocol PlaceRule {
    mutating func arrive(_ id: AnyHashable, _ s: Src, now: Double) -> Places.Arrival
    mutating func ready(_ id: AnyHashable, now: Double)
    func deadline(_ id: AnyHashable) -> Double?
    @discardableResult mutating func leave(_ id: AnyHashable, _ end: Places.End, now: Double) -> [String]
}
extension DoorPolicy.Places: PlaceRule {}

/// The rule before finding 9 (Door.swift at 150479b5): 8 places, 2 per address, 10 s from accept to
/// admission, a failure only for a refusal (the deadline's included), 5 within 60 s → 300 s, and a
/// paired key clears its address.
struct OldPlaces: PlaceRule {
    var pending: [AnyHashable: (address: String, at: Double)] = [:]
    var failures: [String: [Double]] = [:]
    var backoffUntil: [String: Double] = [:]
    mutating func arrive(_ id: AnyHashable, _ s: Src, now: Double) -> Places.Arrival {
        if let until = backoffUntil[s.address], now < until { return .backedOff }
        guard pending.count < 8 else { return .full }
        guard pending.values.filter({ $0.address == s.address }).count < 2 else { return .source }
        pending[id] = (s.address, now)
        return .taken(known: false)
    }
    mutating func ready(_ id: AnyHashable, now: Double) {}
    func deadline(_ id: AnyHashable) -> Double? { pending[id].map { $0.at + 10 } }
    mutating func leave(_ id: AnyHashable, _ end: Places.End, now: Double) -> [String] {
        guard let e = pending.removeValue(forKey: id) else { return [] }
        switch end {
        case .admitted(let paired):
            if paired { failures[e.address] = nil; backoffUntil[e.address] = nil }
            return []
        case .dropped, .ended, .request:      // a kind 19 was admitted: it cost nothing
            return []
        case .refused:
            let list = (failures[e.address] ?? []).filter { now - $0 < 60 } + [now]
            if list.count >= 5 { backoffUntil[e.address] = now + 300; failures[e.address] = []; return [e.address] }
            failures[e.address] = list
            return []
        }
    }
}

struct Holder { var addresses: [Src]; var hold: Double; var readyAfter: Double? = nil; var per = D.placesPerSource; var request: Double? = nil }
struct Device { var source: Src; var handshake: Double = 0.05; var every: Double = 2; var from: Double = 1 }
struct Outcome {
    var backedOffAt: [String: Double] = [:]
    var deviceTries = 0, deviceIn = 0
    var firstIn: Double?
    var maxHolderPlaces = 0
    var holderConnections = 0
    var holderConnectionsAfter: [Double: Int] = [:]
}

struct Conn { var id: Int; var holder: Int; var closeAt: Double; var readyAt: Double?; var ready = false; var requestAt: Double? = nil }

/// `known`: the device proved its key before the attack began.
func simulate<R: PlaceRule>(_ rule: R, holders: [Holder], device: Device?, known: Bool = false, seconds: Double = 120) -> Outcome {
    var r = rule
    var out = Outcome()
    var conns: [Conn] = []
    var nextID = 1
    var free = holders.map(\.per)
    var turn = Array(repeating: 0, count: holders.count)
    if let d = device, known {
        _ = r.arrive(0, d.source, now: -10); r.leave(0, .admitted(paired: true), now: -10)
    }
    var deviceConn: (id: Int, readyAt: Double)?
    var nextTry = device?.from ?? .infinity
    for tick in 0...Int(seconds * 100) {
        let now = Double(tick) / 100
        func note(_ keys: [String]) { for k in keys where out.backedOffAt[k] == nil { out.backedOffAt[k] = now } }
        // The door's deadlines, then the holders' readiness and closes.
        var kept: [Conn] = []
        for var c in conns {
            if let dl = r.deadline(c.id), now >= dl {
                note(r.leave(c.id, .refused, now: now)); free[c.holder] += 1; continue
            }
            if let ra = c.readyAt, !c.ready, now >= ra { r.ready(c.id, now: now); c.ready = true }
            if c.ready, let rq = c.requestAt, now >= rq { note(r.leave(c.id, .request, now: now)); free[c.holder] += 1; continue }
            if now >= c.closeAt { note(r.leave(c.id, .ended, now: now)); free[c.holder] += 1; continue }
            kept.append(c)
        }
        conns = kept
        // The device.
        if let dc = deviceConn {
            if let dl = r.deadline(dc.id), now >= dl, now < dc.readyAt {
                note(r.leave(dc.id, .refused, now: now)); deviceConn = nil
            } else if now >= dc.readyAt {
                r.ready(dc.id, now: now); r.leave(dc.id, .admitted(paired: true), now: now)
                out.deviceIn += 1; if out.firstIn == nil { out.firstIn = now }
                deviceConn = nil
            }
        }
        if let d = device, deviceConn == nil, now >= nextTry {
            out.deviceTries += 1
            nextTry = now + d.every
            let id = nextID; nextID += 1
            if case .taken = r.arrive(id, d.source, now: now) { deviceConn = (id, now + d.handshake) }
        }
        // The holders connect again at once, each from its next address.
        for (h, holder) in holders.enumerated() {
            while free[h] > 0 {
                let id = nextID; nextID += 1
                let s = holder.addresses[turn[h] % holder.addresses.count]
                turn[h] += 1
                guard case .taken = r.arrive(id, s, now: now) else { break }
                out.holderConnections += 1
                free[h] -= 1
                let readyAt = holder.readyAfter.map { now + $0 }
                conns.append(Conn(id: id, holder: h, closeAt: now + holder.hold, readyAt: readyAt,
                                  requestAt: holder.request.flatMap { rq in readyAt.map { $0 + rq } }))
            }
        }
        out.maxHolderPlaces = max(out.maxHolderPlaces, conns.count)
    }
    if deviceConn != nil { out.deviceTries -= 1 }     // a try still in its handshake at the end
    return out
}

let four = ["10.0.0.1", "10.0.0.2", "10.0.0.3", "10.0.0.4"]
func holdersOn(_ addresses: [String], hold: Double, readyAfter: Double? = nil, request: Double? = nil) -> [Holder] {
    addresses.map { Holder(addresses: [v4($0)], hold: hold, readyAfter: readyAfter, request: request) }
}
let paired = Device(source: v4("10.0.0.9"))

// The scan's attack against the rule before: the door full for good, nobody backed off.
let oldScan = simulate(OldPlaces(), holders: holdersOn(four, hold: 9.9), device: paired, known: true)
check("old rule, the scan's attack (4 addresses × 2, closing at 9.9 s): every place held, nobody backed off, the paired device refused at all \(oldScan.deviceTries) tries in 2 minutes",
      oldScan.maxHolderPlaces == 8 && oldScan.backedOffAt.isEmpty && oldScan.deviceIn == 0 && oldScan.deviceTries == 60)
let oldCut = simulate(OldPlaces(), holders: holdersOn(four, hold: 10.5), device: nil)
check("old rule: a holder that waits out the 10 s deadline is backed off at its fifth refusal, 30 s in (the rule saw only refusals)",
      oldCut.backedOffAt.count == 4 && oldCut.backedOffAt.values.allSatisfy { near($0, 30) })

// The scan's attack against the new rule.
let scan = simulate(Places(), holders: holdersOn(four, hold: 9.9), device: paired, known: true)
let scanLast = scan.backedOffAt.values.max() ?? .infinity
check("new rule, the scan's attack: all 4 addresses backed off within 13 s (the handshake's 4 s cuts each connection; last at \(scanLast) s)",
      scan.backedOffAt.count == 4 && scanLast <= 13)
check("new rule, the scan's attack: the paired device admitted at every one of its \(scan.deviceTries) tries (the reserved places)",
      scan.deviceIn == scan.deviceTries && scan.deviceTries == 60)
let scanNew = simulate(Places(), holders: holdersOn(four, hold: 9.9), device: paired, known: false)
check("new rule, the scan's attack: a device not yet known gets in once the holders are backed off (first in at \(scanNew.firstIn ?? -1) s, within 14 s), and at every try after",
      (scanNew.firstIn ?? .infinity) <= 14 && scanNew.deviceIn >= scanNew.deviceTries - 6)
check("new rule, the scan's attack: 3 rounds of 2 from each address, then no place again within the 300 s (\(scan.holderConnections) connections in all)",
      scan.holderConnections == 4 * 6)
// Variants: closing just before a charge or a deadline, and the pairing ALPN's handshake.
for (hold, within) in [(1.9, 27.0), (3.9, 13.0), (0.5, 15.0), (0.05, 5.0)] {
    let o = simulate(Places(), holders: holdersOn(four, hold: hold), device: paired, known: true, seconds: 70)
    let last = o.backedOffAt.values.max() ?? .infinity
    check("new rule, holders closing at \(hold) s: all 4 backed off within \(within) s (last at \(last) s); the paired device admitted at every try",
          o.backedOffAt.count == 4 && last <= within && o.deviceIn == o.deviceTries)
}
let pairingHold = simulate(Places(), holders: holdersOn(four, hold: 30, readyAfter: 0.05), device: paired, known: true, seconds: 60)
check("new rule, holders that complete TLS on the pairing ALPN (any key) and send no kind 19: cut 4 s after .ready, backed off within 14 s",
      pairingHold.backedOffAt.count == 4 && (pairingHold.backedOffAt.values.max() ?? .infinity) <= 14 && pairingHold.deviceIn == pairingHold.deviceTries)
let pairingOld = simulate(OldPlaces(), holders: holdersOn(four, hold: 9.9, readyAfter: 0.05), device: paired, known: true, seconds: 60)
check("old rule, the same on the pairing ALPN closing at 9.9 s: held for good", pairingOld.backedOffAt.isEmpty && pairingOld.deviceIn == 0)
// The review of 2026-10-29: holders that leave each place with a kind 19 instead of closing (TLS on
// the pairing ALPN with any key 3 s after accept, the kind 19 3.47 s later, about the live run's
// tlsholder.py; 6.47 s, so that no place frees on the tick a device tries in). Admitted, it cost
// nothing, and they held every shared place for good, never backed off.
let askOld = simulate(OldPlaces(), holders: holdersOn(four, hold: 30, readyAfter: 3, request: 3.47), device: Device(source: v4("10.0.0.20")), seconds: 120)
check("old rule (and this one before the review), holders leaving each place with a kind 19 6.47 s in: held for good, nobody backed off, a device not yet known refused throughout",
      askOld.maxHolderPlaces == 8 && askOld.backedOffAt.isEmpty && askOld.deviceIn == 0 && askOld.holderConnections > 4 * 2 * 17)
let ask = simulate(Places(), holders: holdersOn(four, hold: 30, readyAfter: 3, request: 3.47), device: paired, known: true)
let askLast = ask.backedOffAt.values.max() ?? .infinity
check("new rule, the same: all 4 backed off at their third kind 19 (2.34 each; last at \(askLast) s); the paired device admitted at every try",
      ask.backedOffAt.count == 4 && askLast > 12.9 && askLast <= 13 && ask.deviceIn == ask.deviceTries && ask.deviceTries == 60)
let askNew = simulate(Places(), holders: holdersOn(four, hold: 30, readyAfter: 3, request: 3.47), device: Device(source: v4("10.0.0.20")), seconds: 60)
check("new rule, the same: a device not yet known gets in once they are backed off (first in at \(askNew.firstIn ?? -1) s), and at every try after",
      (askNew.firstIn ?? .infinity) <= 14 && askNew.deviceIn >= askNew.deviceTries - 6)
let askLate = simulate(Places(), holders: holdersOn(four, hold: 30, readyAfter: 3.9, request: 3.9), device: paired, known: true, seconds: 60)
check("new rule, a kind 19 at the last moment (ready at 3.9 s, the kind 19 3.9 s later, 3.0 each): all 4 backed off at their first two (last at \(askLate.backedOffAt.values.max() ?? -1) s)",
      askLate.backedOffAt.count == 4 && (askLate.backedOffAt.values.max() ?? .infinity) <= 8 && askLate.deviceIn == askLate.deviceTries)
let askCheap = simulate(Places(), holders: holdersOn(four, hold: 30, readyAfter: 0.05, request: 1.85), device: paired, known: true, seconds: 70)
check("new rule, the cheapest kind 19 (1.9 s in, 0.19 each): all 4 backed off within 27 s (last at \(askCheap.backedOffAt.values.max() ?? -1) s), as closing at 1.9 s",
      askCheap.backedOffAt.count == 4 && (askCheap.backedOffAt.values.max() ?? .infinity) <= 27 && askCheap.deviceIn == askCheap.deviceTries)
// The review of 2026-10-29, its second pass: one connection at a time from each of eight addresses,
// each closed at 2 s and made again at once. With a tenth for each end alone (a twentieth a second,
// 3 a minute, under an address's 5) they held every shared place for 10 minutes, none was backed off,
// and a device not yet known was refused at all 300 tries; the rule before held them for good too.
// Now each second held costs a tenth at least (`waitCost`): 6 a minute for a place held without a break.
let eight = (1...8).map { "10.0.5.\($0)" }
for hold in [2.0, 1.9] {
    let o = simulate(Places(), holders: eight.map { Holder(addresses: [v4($0)], hold: hold, per: 1) }, device: Device(source: v4("10.0.0.20")), seconds: 120)
    let last = o.backedOffAt.values.max() ?? .infinity
    check("new rule, eight addresses holding one place each, closing at \(hold) s: all 8 backed off within 52 s (last at \(last) s); a device not yet known in from then on (first at \(o.firstIn ?? -1) s, \(o.deviceIn) of \(o.deviceTries))",
          o.backedOffAt.count == 8 && last <= 52 && (o.firstIn ?? .infinity) <= last + 2.1 && o.deviceIn >= o.deviceTries - 27 && o.maxHolderPlaces == 8)
}
let eightOld = simulate(OldPlaces(), holders: eight.map { Holder(addresses: [v4($0)], hold: 2.0, per: 1) }, device: Device(source: v4("10.0.0.20")), seconds: 120)
check("old rule, the same: every place held for good, nobody backed off, the device refused throughout",
      eightOld.maxHolderPlaces == 8 && eightOld.backedOffAt.isEmpty && eightOld.deviceIn == 0)
// What stays (the plan's "What stays open"): an address keeps about 4/5 of a place for good, so ten
// addresses taking turns could keep the 8 shared places full. One connection held 2 s in every 2.5 s
// (24 ends in any minute, 4.8): never backed off; in every 2.45 s (25 ends, 5.0): backed off.
func paced(every: Double) -> [String] {
    var p = Places(), backed: [String] = [], t = 0.0, n = 0
    while t < 600 { n += 1; _ = p.arrive(n, v4("10.0.6.1"), now: t); backed += p.leave(n, .ended, now: t + 2); t += every }
    return backed
}
check("new rule, a trade-off: one place held 2 s in every 2.5 s (4/5 of a place, 4.8 a minute) is never backed off; in every 2.45 s it is",
      paced(every: 2.5).isEmpty && paced(every: 2.45).first == "10.0.6.1")
// IPv6: any number of addresses in one /64, each trying to keep 2 places.
let g64 = "2601:600:1:2::/64"
let v6holders = (1...8).map { Holder(addresses: [src("2601:600:1:2::\($0)")], hold: 9.9) }
let v6new = simulate(Places(), holders: v6holders, device: Device(source: v4("10.0.0.20")), seconds: 60)
check("new rule, 8 addresses of one /64: 2 places at most, the /64 backed off within 25 s (at \(v6new.backedOffAt[g64] ?? -1) s), an unknown IPv4 device admitted at every try",
      v6new.maxHolderPlaces == 2 && (v6new.backedOffAt[g64] ?? .infinity) <= 25 && v6new.firstIn == 1.05 && v6new.deviceIn == v6new.deviceTries)
let v6churn = simulate(Places(), holders: [Holder(addresses: (1...500).map { src("2601:600:1:2::\($0)") }, hold: 1.9)], device: nil, seconds: 200)
check("new rule, one host taking a new address of its /64 for every connection, closing at 1.9 s: no address ever backed off, the /64 within 62 s (at \(v6churn.backedOffAt[g64] ?? -1) s)",
      v6churn.backedOffAt.keys.sorted() == [g64] && (v6churn.backedOffAt[g64] ?? .infinity) <= 62)
let v6one = simulate(Places(), holders: [Holder(addresses: (1...500).map { src("2601:600:1:2::\($0)") }, hold: 2.0, per: 1)], device: nil, seconds: 320)
check("new rule, the same holding one place at the cheapest (closing at 2.0 s, a tenth a second): the /64 within 121 s (at \(v6one.backedOffAt[g64] ?? -1) s)",
      v6one.backedOffAt.keys.sorted() == [g64] && (v6one.backedOffAt[g64] ?? .infinity) <= 121)
let v6old = simulate(OldPlaces(), holders: v6holders, device: Device(source: v4("10.0.0.20")), seconds: 60)
check("old rule, 8 addresses of one /64: every place held, nobody backed off, the device refused throughout",
      v6old.maxHolderPlaces == 8 && v6old.backedOffAt.isEmpty && v6old.deviceIn == 0)
let v6known = simulate(Places(), holders: v6holders, device: Device(source: src("2601:600:1:2::99")), known: true, seconds: 60)
check("new rule, a known device in the holders' own /64: admitted at every try", v6known.deviceIn == v6known.deviceTries)
let v6stranger = simulate(Places(), holders: v6holders, device: Device(source: src("2601:600:1:2::98")), known: false, seconds: 60)
check("new rule, a device not yet known in the holders' own /64: refused while they hold its 2 places and while the /64 is backed off (a cost of the /64)",
      v6stranger.deviceIn == 0)
// Someone at a paired device's own address (its NAT, or its address while it is away) pays too.
let shared = simulate(Places(), holders: holdersOn(["10.0.0.9"], hold: 9.9), device: paired, known: true, seconds: 60)
check("new rule, a holder at the paired device's own address: that address backed off within 30 s (at \(shared.backedOffAt["10.0.0.9"] ?? -1) s: 1.1 each, as an address not known), the device with it (nothing tells them apart before TLS)",
      (shared.backedOffAt["10.0.0.9"] ?? .infinity) <= 30 && shared.deviceIn < shared.deviceTries)

// Legitimate traffic is never backed off.
func legit(_ ends: [(at: Double, held: Double, end: Places.End)], source: Src = v4("10.0.0.30")) -> Places {
    var p = Places()
    for (n, e) in ends.enumerated() { _ = p.arrive(n, source, now: e.at); p.leave(n, e.end, now: e.at + e.held) }
    return p
}
let losers = legit((0..<100).map { (Double($0) * 6, 1.0, Places.End.ended) })
check("legit: a dial's loser every 6 s for 10 minutes from an address that never wins (held 1 s each): never backed off",
      !losers.backedOff(v4("10.0.0.30"), now: 600) && losers.failures("10.0.0.30", now: 599) < 2)
let older = legit((0..<300).map { (Double($0) * 2, 0.01, Places.End.ended) })
check("legit: an older Sill's plain try every 2 s for 10 minutes: never backed off", !older.backedOff(v4("10.0.0.30"), now: 600))
let older6 = legit((0..<300).map { (Double($0) * 2, 0.01, Places.End.ended) }, source: src("2601:600:1:2::30"))
check("legit: the same from an IPv6 address: never backed off, nor its /64 (the review's second pass: at 238 s before)",
      !older6.backedOff(src("2601:600:1:2::30"), now: 600) && !older6.backedOff(src("2601:600:1:2::31"), now: 600))
let flicker = legit((0..<200).map { (Double($0) * 0.3, 0.01, Places.End.ended) })
check("legit, a trade-off: a plain retry every 0.3 s (a build from before pairing at home) backs its address off within a minute",
      flicker.backedOff(v4("10.0.0.30"), now: 59))
let redial = legit((0..<12).map { (Double($0) * 5, 0.05, Places.End.refused) }, source: src("fe80::30", "en0"))
check("legit: a device redialing with a key the Mac no longer trusts (refused every 5 s) backs off its own address, not its link",
      redial.backedOff(src("fe80::30", "en0"), now: 56) && !redial.backedOff(src("fe80::31", "en0"), now: 56))
var flicker6 = Places()
var flicker6Backed: [String] = []
for n in 0..<4000 {
    let t = Double(n) * 0.3
    if case .taken = flicker6.arrive(n, src("fe80::30", "en0"), now: t) { flicker6Backed += flicker6.leave(n, .ended, now: t + 0.01) }
}
check("legit: one such build flickering for 20 minutes on its link-local address backs its own address off again and again (\(flicker6Backed.count) times), never its link",
      flicker6Backed.count >= 3 && flicker6Backed.allSatisfy { $0 == "fe80::30%en0" } && !flicker6.backedOff(src("fe80::31", "en0"), now: 1200))
let slow = simulate(Places(), holders: [], device: Device(source: v4("10.0.0.40"), handshake: 3.5), seconds: 30)
check("legit: a device whose handshake takes 3.5 s gets in at its first try", slow.firstIn == 4.5 && slow.deviceIn == slow.deviceTries)
let slower = simulate(Places(), holders: [], device: Device(source: v4("10.0.0.41"), handshake: 4.5, every: 10), seconds: 30)
check("legit: one whose handshake takes 4.5 s is cut at 4 s while its address is not known", slower.deviceIn == 0)
let slowKnown = simulate(Places(), holders: [], device: Device(source: v4("10.0.0.41"), handshake: 6, every: 10), known: true, seconds: 30)
check("legit: a known device whose handshake takes 6 s gets in (10 s from a known address)", slowKnown.deviceIn == slowKnown.deviceTries && slowKnown.deviceTries == 3)
// The review of 2026-10-29: a known address is given 10 s for its handshake, and was charged for
// all of it (a cut at 10 s 4.1, its own device letting go at 5 s 1.6), so a paired device whose
// dials stalled after TCP (a path dying mid-handshake, the device suspended) was backed off sooner
// than one not known. The reconnect's dials (at once, then 5, 10, 20 and every 30 s after the last
// started, DiscoveryPolicy.redialRow, 12 at most), each let go after 5 s
// (StreamClient.reconnectDialWait) unless the Mac cut it first: backed off at the fourth, 40 s in.
func stalledReconnect(known: Bool) -> (backedOffAt: Double?, dials: Int, owed: Double) {
    var p = Places()
    let s = v4("10.0.0.50")
    if known { _ = p.arrive("p", s, now: -1); p.leave("p", .admitted(paired: true), now: -1) }
    var start = 0.0, gaps: [Double] = [5, 10, 20], n = 0, owed = 0.0
    var backedAt: Double?
    while n < 12 {
        n += 1
        if case .taken = p.arrive(n, s, now: start), let cut = p.deadline(n) {
            let end = min(cut, start + 5)
            if !p.leave(n, cut <= start + 5 ? .refused : .ended, now: end).isEmpty, backedAt == nil { backedAt = end }
            owed = max(owed, p.failures("10.0.0.50", now: end))
        }
        start += gaps.isEmpty ? 30 : gaps.removeFirst()
    }
    return (backedAt, n, owed)
}
let stalledKnown = stalledReconnect(known: true), stalledNew = stalledReconnect(known: false)
check("legit: a known device whose 12 reconnect dials all stall (each let go at 5 s) is never backed off (\(String(format: "%.1f", stalledKnown.owed)) owed at most)",
      stalledKnown.backedOffAt == nil && stalledKnown.dials == 12)
check("legit: nor one not yet known (each cut at 4 s: \(String(format: "%.1f", stalledNew.owed)) owed at most)", stalledNew.backedOffAt == nil)
var tapped = Places()
_ = tapped.arrive("p", v4("10.0.0.51"), now: -1); tapped.leave("p", .admitted(paired: true), now: -1)
for (n, t) in [0.0, 12, 24, 36].enumerated() { _ = tapped.arrive(n, v4("10.0.0.51"), now: t); tapped.leave(n, .refused, now: t + 10) }
check("legit: a known device's taps whose dials stall to the Mac's 10 s, four in a minute: \(String(format: "%.1f", tapped.failures("10.0.0.51", now: 46))), not backed off",
      !tapped.backedOff(v4("10.0.0.51"), now: 46))

// MARK: Test hooks

check("test host: does not advertise and is not Sill.app's own code (bundled)",
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
