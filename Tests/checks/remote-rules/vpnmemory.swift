// A Mac's VPN addresses kept when a later list from it lacks them (2026-11-11, branch `keep-vpn-addresses`;
// docs/remote-access-plan.md §7.2 and §7.5), in the remote-rules check: SavedMacs.remembering and what calls
// it (`refreshed`, `adding`), SavedMacs.remembered, RemoteDialPolicy.order's second group, `classify` and
// `successors` at a remembered address, `failed` and RemoteCopy's words. Noah's night: Tailscale was off on
// his Mac for about ten minutes while his iPad connected at home; that session's kind 18 listed the Mac's
// Wi‑Fi address alone, the iPad replaced its saved list with it, and away on a hotspot it had nothing it
// could reach, Tailscale on again or not, and said "‹Mac› didn’t answer. It may be asleep." A function
// main.swift calls.
import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// SavedMac as it is on main at 9ea2e41, field for field: what a build from before this change decodes.
struct MainSavedMac: Codable, Equatable {
    var macID: String; var fingerprint: String; var name: String; var recognitionKey: String; var remotePort: Int
    var addresses: [MacAddress]; var typedAddresses: [MacAddress]?; var infoIssuedAt: Double; var bonjourName: String?
    var lastWorked: String?; var pairedAt: Date; var method: String; var lastConnectedAt: Date?; var lastRoute: String?
    var homeTLS: Bool?; var revoked: Bool?; var newKey: Bool?
}

func vpnMemory() {
    let day = 86_400.0
    let tsName = MacAddress(host: "mac-mini.tail1234.ts.net", kind: MacAddress.vpn, via: "Tailscale")
    let ts4 = MacAddress(host: "100.101.102.103", kind: MacAddress.vpn, via: "Tailscale")
    let ts6 = MacAddress(host: "fd7a:115c:a1e0::1234", kind: MacAddress.vpn, via: "Tailscale")
    let wifi = MacAddress(host: "192.168.1.20", kind: MacAddress.lan, via: "Wi‑Fi")
    let hotspot: [(address: [UInt8], prefix: Int)] = [([172, 20, 10, 2], 28)]
    let fp = Data((0..<32).map { UInt8($0 &+ 41) })
    let id = MacID.make(fingerprint: fp)
    func info(_ list: [MacAddress], issued: Double, remoteAccess: Bool = true, port: Int = 7455) -> MacInfo {
        MacInfo(macID: id, name: "Mac mini", issuedAt: issued, remoteAccess: remoteAccess, remotePort: port, internet: false, addresses: list)
    }
    // A kind 18 taken at `now` (this device's clock); the Mac's clock runs 7 s behind it (`issuedAt`).
    // Never a crash, whatever a mutant does (a crash loses the FAIL lines printed before it): a refused
    // refresh leaves the record as it was, which the checks after it then find wrong.
    func refresh(_ m: SavedMac, _ list: [MacAddress], at now: Double, remoteAccess: Bool = true, port: Int = 7455) -> SavedMac {
        SavedMacs.refreshed(m, info: info(list, issued: now - 7, remoteAccess: remoteAccess, port: port), fingerprint: fp,
                            allowLoopback: false, now: now) ?? m
    }
    func hosts(_ m: SavedMac) -> [String] { (m.rememberedAddresses ?? []).map(\.address.host) }
    func times(_ m: SavedMac) -> [Double] { (m.rememberedAddresses ?? []).map(\.listedAt) }
    func dial(_ m: SavedMac, at now: Double, local: [(address: [UInt8], prefix: Int)]) -> [R.Candidate] {
        R.order(m.allAddresses, remembered: SavedMacs.remembered(m, now: now), remotePort: m.remotePort, lastWorked: m.lastWorked, localIPv4: local)
    }
    func keys(_ cs: [R.Candidate]) -> [String] { cs.map { $0.remembered ? "\($0.key) r" : $0.key } }
    // RemoteConnector's verdict when every attempt ended as `end` says, and the words remoteDialFailed shows.
    func outcome(_ m: SavedMac, at now: Double, _ end: (R.Candidate) -> (R.End, Bool?)) -> (failure: R.Failure, candidate: R.Candidate?) {
        let cs = dial(m, at: now, local: hotspot)
        let results = cs.compactMap { c -> (R.Failure, R.Candidate)? in
            let (e, tunnel) = end(c)
            return R.classify(e, candidate: c, usedTunnel: tunnel).map { ($0, c) }
        }
        return R.failed(results, candidates: cs)
    }
    func words(_ o: (failure: R.Failure, candidate: R.Candidate?), _ m: SavedMac, at now: Double) -> String {
        RemoteCopy.dialFailure(o.failure, mac: "Mac mini", candidate: o.candidate,
                               vpnName: RemoteCopy.vpnName(m.allAddresses + SavedMacs.remembered(m, now: now)), device: "iPad")
    }
    // A winner that ended before its window list, as sessionEnded classifies it (no path known).
    func winnerWords(_ m: SavedMac, at now: Double, winner: R.Candidate, _ end: R.End) -> String {
        words((R.classify(end, candidate: winner, usedTunnel: nil) ?? .noAnswer, winner), m, at: now)
    }

    // MARK: Noah's night, as a model: listed with the VPN, without it, away, the remembered address dialed, listed again

    let t0 = 1_794_000_000.0
    var m = SavedMac(macID: id, fingerprint: Base64URL.encode(fp), name: "Mac mini", recognitionKey: Base64URL.encode(Data(repeating: 9, count: 32)),
                     remotePort: 7455, addresses: [tsName, ts4, ts6, wifi], typedAddresses: nil, infoIssuedAt: 0, bonjourName: nil,
                     lastWorked: "mac-mini.tail1234.ts.net|7455", pairedAt: Date(timeIntervalSince1970: t0), method: "qr",
                     lastConnectedAt: nil, lastRoute: nil)
    let t1 = t0 + 2 * day
    m = refresh(m, [tsName, ts4, ts6, wifi], at: t1)
    check("night 1: at home with Tailscale on: the Mac's list, nothing remembered, listed at this device's time",
          m.addresses == [tsName, ts4, ts6, wifi] && m.rememberedAddresses == nil && m.addressesListedAt == t1)
    let before = m
    let t2 = t1 + day
    m = refresh(m, [wifi], at: t2)
    check("night 2: at home while Tailscale is off on the Mac: the list is the Wi‑Fi address, its Tailscale name and addresses remembered as last listed at night 1",
          m.addresses == [wifi] && hosts(m) == [tsName.host, ts4.host, ts6.host] && times(m) == [t1, t1, t1] && m.addressesListedAt == t2)
    check("night 2: typed addresses and the address that last worked kept", m.typedAddresses == nil && m.lastWorked == before.lastWorked)
    let t3 = t2 + 600
    check("night 3: away (a hotspot), 10 minutes later: the Mac's list first, then the remembered Tailscale name, IPv4, IPv6, marked",
          keys(dial(m, at: t3, local: hotspot)) == ["192.168.1.20|7455", "mac-mini.tail1234.ts.net|7455 r", "100.101.102.103|7455 r",
                                                    "fd7a:115c:a1e0::1234|7455 r"])
    // Before this change the iPad had the Wi‑Fi address alone, and said only that the Mac may be asleep.
    let old = R.order(m.allAddresses, remotePort: m.remotePort, lastWorked: m.lastWorked, localIPv4: hotspot)
    let oldFailure = R.failed(old.compactMap { c in R.classify(.timeout, candidate: c, usedTunnel: false).map { ($0, c) } }, candidates: old)
    check("night 3, as main dialed it: the Wi‑Fi address alone, and “didn’t answer. It may be asleep.” (what Noah saw)",
          keys(old) == ["192.168.1.20|7455"]
          && RemoteCopy.dialFailure(oldFailure.failure, mac: "Mac mini", candidate: oldFailure.candidate, vpnName: RemoteCopy.vpnName(m.allAddresses), device: "iPad")
             == "Mac mini didn’t answer. It may be asleep.")
    let stillOff = outcome(m, at: t3) { c in (.timeout, c.remembered) }       // the remembered ones through the tunnel, the Wi‑Fi one not
    check("night 3, Tailscale still off on the Mac: no answer, and the words name Tailscale on the Mac (#309's hint)",
          stillOff.failure == .noAnswer && words(stillOff, m, at: t3) == "Mac mini didn’t answer. It may be asleep, or Tailscale may be off on the Mac.")
    let offHere = outcome(m, at: t3) { c in c.isName && c.remembered ? (.dns(R.dnsNoSuchRecord), nil) : (.timeout, false) }
    check("night 3, Tailscale off on the iPad: the remembered addresses go through no tunnel: “Tailscale looks off on this iPad or on Mac mini”",
          offHere.failure == .vpnOff && offHere.candidate?.host == ts4.host
          && words(offHere, m, at: t3) == "Tailscale looks off on this iPad or on Mac mini. Turn it on for both, then tap Mac mini.")
    // Tailscale on again on the Mac: the remembered name answers and wins (RemoteConnector: the first .ready).
    let winner = dial(m, at: t3 + 60, local: hotspot).dropFirst().first
    check("night 3, Tailscale on again on the Mac: the first remembered address is the one dialed next, pinned to the Mac's key alone",
          winner?.host == tsName.host && winner?.remembered == true
          && winner.map { R.successors(of: m, at: $0, in: [m], allowLoopback: false).isEmpty } == true)
    m.lastWorked = winner?.key                                               // remoteSessionReady
    let t4 = t3 + 61
    m = refresh(m, [tsName, ts4, ts6, wifi], at: t4)
    check("night 4: the session's kind 18 lists Tailscale again: back in the Mac's list, nothing remembered",
          m.addresses == [tsName, ts4, ts6, wifi] && m.rememberedAddresses == nil && m.addressesListedAt == t4)
    let t5 = t4 + 30 * day
    m = refresh(m, [wifi], at: t5)
    check("night 5, a month on, Tailscale off on the Mac again at home: remembered as last listed at night 4 (a list that has one refreshes it)",
          hosts(m) == [tsName.host, ts4.host, ts6.host] && times(m) == [t4, t4, t4])
    check("night 5: the address that last worked first among the remembered, never before the Mac's list",
          keys(dial({ var x = m; x.lastWorked = ts4.host + "|7455"; return x }(), at: t5, local: hotspot))
          == ["192.168.1.20|7455", "100.101.102.103|7455 r", "mac-mini.tail1234.ts.net|7455 r", "fd7a:115c:a1e0::1234|7455 r"])
    check("night 5: dialed until 90 days after the Mac last listed them, then not",
          SavedMacs.remembered(m, now: t4 + 90 * day).count == 3 && SavedMacs.remembered(m, now: t4 + 90 * day + 1).isEmpty
          && SavedMacs.remembered(m, now: t4 + 60 * day).count == 3)
    check("night 5: a later list still keeps them at 90 days to the second", times(refresh(m, [wifi], at: t4 + 90 * day)) == [t4, t4, t4])
    let aged = refresh(m, [wifi], at: t4 + 90 * day + 1)
    check("night 5: a later list forgets them once 90 days have passed", aged.rememberedAddresses == nil && aged.addresses == [wifi])

    // MARK: What is remembered

    let router = MacAddress(host: "203.0.113.9", kind: MacAddress.internet, via: "Router")
    let v6 = MacAddress(host: "2001:db8::20", kind: MacAddress.internet, via: "IPv6")
    let named = MacAddress(host: "home.example.net", port: 17455, kind: MacAddress.internet, via: "Address name")
    let wg = MacAddress(host: "10.8.0.6", kind: MacAddress.vpn, via: "VPN (utun6)")
    let ethernet = MacAddress(host: "10.0.5.9", kind: MacAddress.lan, via: "Ethernet")
    func record(_ addresses: [MacAddress], listedAt: Double? = nil, remembered: [RememberedAddress]? = nil, issued: Double = 0,
                paired: Double? = nil, port: Int = 7455) -> SavedMac {
        var r = SavedMac(macID: id, fingerprint: Base64URL.encode(fp), name: "Mac mini", recognitionKey: Base64URL.encode(Data(repeating: 9, count: 32)),
                         remotePort: port, addresses: addresses, typedAddresses: nil, infoIssuedAt: issued, bonjourName: nil, lastWorked: nil,
                         pairedAt: Date(timeIntervalSince1970: paired ?? t0), method: "qr", lastConnectedAt: nil, lastRoute: nil)
        r.addressesListedAt = listedAt
        r.rememberedAddresses = remembered
        return r
    }
    let full = record([tsName, ts4, wg, wifi, ethernet, router, v6, named], listedAt: t1)
    check("only VPN addresses: the Tailscale and the other VPN's ones; never the Wi‑Fi, Ethernet, router, IPv6 or address name a new list drops",
          hosts(refresh(full, [MacAddress(host: "192.168.1.21", kind: MacAddress.lan, via: "Wi‑Fi")], at: t2))
          == [tsName.host, ts4.host, wg.host])
    check("the kind decides, the Mac's own word: a Tailscale-shaped address it listed as internet is not remembered",
          hosts(refresh(record([MacAddress(host: "100.100.1.1", kind: MacAddress.internet, via: "")], listedAt: t1), [wifi], at: t2)).isEmpty)
    check("an address still listed is not remembered, its host's case and an explicit usual port aside",
          hosts(refresh(record([tsName, ts4], listedAt: t1), [MacAddress(host: "MAC-MINI.tail1234.TS.net", kind: MacAddress.vpn, via: "Tailscale"),
                                                             MacAddress(host: ts4.host, port: 7455, kind: MacAddress.vpn, via: "Tailscale")], at: t2)).isEmpty)
    check("the same host on another port is another destination: remembered",
          hosts(refresh(record([MacAddress(host: ts4.host, port: 7460, kind: MacAddress.vpn, via: "Tailscale")], listedAt: t1), [ts4], at: t2)) == [ts4.host])
    let six = (1...6).map { MacAddress(host: "100.64.0.\($0)", kind: MacAddress.vpn, via: "Tailscale") }
    check("at most four, in the Mac's order when listed together", hosts(refresh(record(six, listedAt: t1), [wifi], at: t2)) == six.prefix(4).map(\.host))
    let olderTwo = [RememberedAddress(address: six[4], listedAt: t0), RememberedAddress(address: six[5], listedAt: t0 + 1)]
    let mixed = refresh(record([tsName, ts4, ts6], listedAt: t1, remembered: olderTwo), [wifi], at: t2)
    check("the newest first: the three just dropped, then the most recent of those remembered before",
          hosts(mixed) == [tsName.host, ts4.host, ts6.host, six[5].host] && times(mixed) == [t1, t1, t1, t0 + 1])
    let twice = refresh(record([ts4], listedAt: t1, remembered: [RememberedAddress(address: ts4, listedAt: t0),
                                                                 RememberedAddress(address: MacAddress(host: tsName.host.uppercased(), kind: MacAddress.vpn, via: "Tailscale"), listedAt: t0),
                                                                 RememberedAddress(address: tsName, listedAt: t0 + 9)]), [wifi], at: t2)
    check("one destination once (its host's case aside), with its newest time", hosts(twice) == [ts4.host, tsName.host] && times(twice) == [t1, t0 + 9])
    // Lists kept as they are (an empty one, Remote Access off, nothing keepable): the Mac's list and its time stay;
    // the remembered ones only age.
    let kept = record([wifi], listedAt: t2, remembered: [RememberedAddress(address: tsName, listedAt: t1), RememberedAddress(address: ts4, listedAt: t0 - 100 * day)])
    for (label, list, on) in [("an empty list", [MacAddress](), true), ("Remote Access off", [ts6, wifi], false),
                              ("nothing keepable", [MacAddress(host: "fe80::1", kind: MacAddress.lan, via: "Wi‑Fi")], true)] {
        let r = refresh(kept, list, at: t3, remoteAccess: on)
        check("\(label): the Mac's list and its time kept, what is remembered only aged (90 days)",
              r.addresses == [wifi] && r.addressesListedAt == t2 && hosts(r) == [tsName.host] && times(r) == [t1])
    }
    check("Remote Access off, then on again with Tailscale off: remembered as last listed before it went off",
          times(refresh(refresh(record([tsName, wifi], listedAt: t1), [], at: t2, remoteAccess: false), [wifi], at: t3)) == [t1])
    // When the Mac last listed a record's addresses, for one no kind 18 has set them on (from before this change, or
    // just paired with its link's addresses): its newest kind 18's time or its pairing's, never after now.
    check("a record from before: the newest kind 18's time (the Mac's clock), else the pairing's",
          times(refresh(record([tsName], issued: t1 - 7), [wifi], at: t2)) == [t1 - 7]
          && times(refresh(record([tsName], issued: 0, paired: t0), [wifi], at: t2)) == [t0])
    let ahead = SavedMacs.refreshed(record([tsName], issued: t3 + 5 * day), info: info([wifi], issued: t3 + 6 * day), fingerprint: fp,
                                    allowLoopback: false, now: t3)
    check("a Mac clock ahead of this device's: read as now", ahead.map(times) == [t3])
    let future = refresh(record([wifi], listedAt: t1, remembered: [RememberedAddress(address: tsName, listedAt: t3 + 400 * day)]), [], at: t3)
    check("a time after now (this device's clock set back since): read as now, so it never outlives 90 days from here", times(future) == [t3]
          && SavedMacs.remembered(future, now: t3 + 91 * day).isEmpty)

    // MARK: The dial

    var both = record([wifi, router], listedAt: t2, remembered: [RememberedAddress(address: tsName, listedAt: t1), RememberedAddress(address: ts4, listedAt: t1)])
    both.typedAddresses = [MacAddress(host: "home.example.net", kind: MacAddress.internet, via: "")]
    check("the Mac's list and the typed ones first, in their order (the shared LAN, names, addresses, other LANs); the remembered after, even VPN ones",
          keys(dial(both, at: t3, local: hotspot)) == ["home.example.net|7455", "203.0.113.9|7455", "192.168.1.20|7455",
                                                       "mac-mini.tail1234.ts.net|7455 r", "100.101.102.103|7455 r"])
    both.lastWorked = "203.0.113.9|7455"
    check("the address that last worked first in the Mac's list as before", keys(dial(both, at: t3, local: hotspot)).first == "203.0.113.9|7455")
    var dup = record([ts4], listedAt: t2, remembered: [RememberedAddress(address: MacAddress(host: "Mac-Mini.tail1234.ts.net", kind: MacAddress.vpn, via: "Tailscale"), listedAt: t1),
                                                       RememberedAddress(address: ts6, listedAt: t1)])
    dup.typedAddresses = [tsName]
    check("an address both typed and remembered: dialed once, in the first group, unmarked",
          keys(dial(dup, at: t3, local: hotspot)) == ["mac-mini.tail1234.ts.net|7455", "100.101.102.103|7455", "fd7a:115c:a1e0::1234|7455 r"])
    check("a remembered address takes the Mac's port now (the door moved for every address)",
          dial(refresh(record([tsName], listedAt: t1), [wifi], at: t2, port: 7460), at: t3, local: hotspot).map(\.port) == [7460, 7460])
    check("nothing remembered: the dial as before", keys(dial(record([wifi, tsName], listedAt: t2), at: t3, local: hotspot))
          == keys(R.order([wifi, tsName], remotePort: 7455, lastWorked: nil, localIPv4: hotspot)))

    // MARK: A remembered address may be another machine's by now: only the Mac's own answers and silence count there

    let remembered = R.Candidate(host: ts4.host, port: 7455, kind: MacAddress.vpn, via: "Tailscale", remembered: true)
    let listedC = R.Candidate(host: ts4.host, port: 7455, kind: MacAddress.vpn, via: "Tailscale")
    let rememberedName = R.Candidate(host: tsName.host, port: 7455, kind: MacAddress.vpn, via: "Tailscale", remembered: true)
    check("another key (the pin refused): counts for nothing there, a wrong Mac at an address the Mac lists",
          R.classify(.tls(-9808), candidate: remembered, usedTunnel: true) == nil && R.classify(.tls(-9808), candidate: listedC, usedTunnel: true) == .wrongMac)
    check("a name that no longer resolves: nothing there (the Mac renamed), the VPN off at a listed name",
          R.classify(.dns(R.dnsNoSuchRecord), candidate: rememberedName, usedTunnel: nil) == nil
          && R.classify(.dns(R.dnsNoSuchName), candidate: rememberedName, usedTunnel: nil) == nil
          && R.classify(.dns(-65537), candidate: rememberedName, usedTunnel: nil) == nil
          && R.classify(.dns(R.dnsNoSuchRecord), candidate: R.Candidate(host: tsName.host, port: 7455, kind: MacAddress.vpn, via: "Tailscale"), usedTunnel: nil) == .vpnOff)
    check("a TLS that is not Sill's: nothing there", R.classify(.tls(-9836), candidate: remembered, usedTunnel: true) == nil
          && R.classify(.tls(-9836), candidate: listedC, usedTunnel: true) == .notSill)
    check("the Mac's own answers count as anywhere: our key refused, its goodbyes, its door's refusal",
          R.classify(.tls(-9825), candidate: remembered, usedTunnel: true) == .revoked && R.classify(.tls(-9829), candidate: remembered, usedTunnel: true) == .revoked
          && R.classify(.tlsAfterReady(-9825), candidate: remembered, usedTunnel: nil) == .revoked
          && R.classify(.goodbye(Goodbye.remoteOff), candidate: remembered, usedTunnel: nil) == .remoteOff
          && R.classify(.goodbye(Goodbye.busy), candidate: remembered, usedTunnel: nil) == .busy
          && R.classify(.tls(-9816), candidate: remembered, usedTunnel: true) == .refused && R.classify(.tls(-9806), candidate: remembered, usedTunnel: true) == .refused
          && R.classify(.posix(ECONNREFUSED), candidate: remembered, usedTunnel: true) == .refused
          && R.classify(.tlsAfterReady(-9836), candidate: remembered, usedTunnel: nil) == .notSill)
    check("silence counts as anywhere: no answer through the tunnel, this device's VPN off without one",
          R.classify(.timeout, candidate: remembered, usedTunnel: true) == .noAnswer && R.classify(.timeout, candidate: remembered, usedTunnel: false) == .vpnOff
          && R.classify(.posix(EHOSTUNREACH), candidate: remembered, usedTunnel: false) == .vpnOff && R.classify(.noWindowList, candidate: remembered, usedTunnel: nil) == .noAnswer)
    // A Mac set up again, and the device paired again (main.swift's superseding): no other key is taken at a remembered address.
    var oldRecord = record([wifi], listedAt: t2, remembered: [RememberedAddress(address: ts4, listedAt: t1)])
    oldRecord.lastConnectedAt = Date(timeIntervalSince1970: t1)
    let fpNew = Data((0..<32).map { UInt8(200 &- $0) })
    let newRecord = SavedMac(macID: MacID.make(fingerprint: fpNew), fingerprint: Base64URL.encode(fpNew), name: "Mac mini",
                             recognitionKey: Base64URL.encode(Data(repeating: 8, count: 32)), remotePort: 7455, addresses: [ts4],
                             typedAddresses: nil, infoIssuedAt: 0, bonjourName: nil, lastWorked: nil,
                             pairedAt: Date(timeIntervalSince1970: t3), method: "qr", lastConnectedAt: nil, lastRoute: nil)
    check("another saved Mac's key: taken at the address the Mac lists, never at a remembered one",
          R.successors(of: oldRecord, at: listedC, in: [oldRecord, newRecord], allowLoopback: false).map(\.macID) == [newRecord.macID]
          && R.successors(of: oldRecord, at: remembered, in: [oldRecord, newRecord], allowLoopback: false).isEmpty)

    // MARK: The words with only remembered addresses to dial (the Mac's list empty, or none of it answering)

    let only = record([], listedAt: t1, remembered: [RememberedAddress(address: tsName, listedAt: t1), RememberedAddress(address: ts4, listedAt: t1),
                                                     RememberedAddress(address: ts6, listedAt: t1)])
    check("only remembered addresses: all three dialed, marked", keys(dial(only, at: t2, local: hotspot))
          == ["mac-mini.tail1234.ts.net|7455 r", "100.101.102.103|7455 r", "fd7a:115c:a1e0::1234|7455 r"])
    let silent = "Mac mini didn’t answer. It may be asleep, or Tailscale may be off on the Mac."
    let table: [(String, (R.Candidate) -> (R.End, Bool?), R.Failure, String)] = [
        ("silence through the tunnel (the Mac's Tailscale off, or the Mac asleep)", { _ in (.timeout, true) }, .noAnswer, silent),
        ("this iPad's Tailscale off (no tunnel; the name not found)", { c in c.isName ? (.dns(R.dnsNoSuchRecord), nil) : (.timeout, false) }, .vpnOff,
         "Tailscale looks off on this iPad or on Mac mini. Turn it on for both, then tap Mac mini."),
        ("the name gone (the Mac renamed), the addresses silent", { c in c.isName ? (.dns(R.dnsNoSuchRecord), nil) : (.timeout, true) }, .noAnswer, silent),
        ("another key at every address", { _ in (.tls(-9808), true) }, .noAnswer, silent),
        ("something that is not Sill at every address", { _ in (.tls(-9836), true) }, .noAnswer, silent),
        ("a refusal (nothing listening on the Mac's port)", { _ in (.posix(ECONNREFUSED), true) }, .refused,
         "Mac mini answered, but Sill isn’t accepting remote connections there. Check that Sill is open and Remote Access is on. If you changed its port, connect at home once."),
    ]
    for (label, end, failure, text) in table {
        for m in [only, record([wifi], listedAt: t1, remembered: only.rememberedAddresses)] {
            let o = outcome(m, at: t2) { c in c.remembered ? end(c) : (.timeout, false) }
            check("words, \(m.addresses.isEmpty ? "only remembered" : "the Wi‑Fi address silent first"): \(label)", o.failure == failure && words(o, m, at: t2) == text)
        }
    }
    let rememberedWinner = dial(only, at: t2, local: hotspot).first ?? R.Candidate(host: "", port: 0, kind: "", via: "")
    let winnerTable: [(String, R.End, String)] = [
        ("the Mac refused this iPad's key", .tlsAfterReady(-9825), "Mac mini no longer accepts this iPad. Pair it again from Sill’s Settings on the Mac."),
        ("Remote Access off", .goodbye(Goodbye.remoteOff), "Mac mini turned off Remote Access."),
        ("eight devices already", .goodbye(Goodbye.busy), "Mac mini is already serving 8 devices."),
        ("no window list", .noWindowList, silent),
        ("closed after the handshake", .posix(ECONNRESET),
         "Mac mini answered, but Sill isn’t accepting remote connections there. Check that Sill is open and Remote Access is on. If you changed its port, connect at home once."),
    ]
    for (label, end, text) in winnerTable {
        check("words, a remembered winner that ended before its window list: \(label)", winnerWords(only, at: t2, winner: rememberedWinner, end) == text)
    }
    check("failed: the first attempt that ended with the worst failure names the address; none counted: the first dialed",
          R.failed([(.noAnswer, listedC), (.noAnswer, remembered)], candidates: [remembered]).candidate == listedC
          && R.failed([], candidates: [rememberedName, remembered]).candidate == rememberedName && R.failed([], candidates: []).failure == .noAnswer
          && R.failed([(.noAnswer, listedC), (.vpnOff, remembered)], candidates: [listedC]).failure == .vpnOff)
    check("the hint's VPN: the first address with a service name, typed or remembered", RemoteCopy.vpnName([wifi, router, wg, ts4]) == "Tailscale"
          && RemoteCopy.vpnName([wifi]) == nil && RemoteCopy.vpnName([wifi, MacAddress(host: "10.8.0.6", kind: MacAddress.vpn, via: "Home WireGuard"), ts4]) == "Home WireGuard")

    // MARK: The records: a new pairing, a key change, Forget, the Remote rows, older builds

    let paired = record([tsName, ts4, wifi], listedAt: t1, remembered: [RememberedAddress(address: ts6, listedAt: t0)])
    let again = record([wifi], paired: t3)                          // the same Mac paired again from its link while Tailscale is off on it
    let carried = SavedMacs.adding(again, to: [paired]).first { $0.macID == id } ?? again
    check("a new pairing of the same Mac (one key) keeps what the old record had and the new list lacks, as a kind 18 would",
          carried.addresses == [wifi] && hosts(carried) == [tsName.host, ts4.host, ts6.host] && times(carried) == [t1, t1, t0])
    check("a new pairing ages them against its own time", SavedMacs.adding(record([wifi], paired: t1 + 91 * day), to: [paired])
          .first { $0.macID == id }?.rememberedAddresses == nil)
    let otherMac = SavedMacs.adding(newRecord, to: [paired]).first { $0.macID == newRecord.macID }
    check("another Mac's pairing (another key) takes nothing", otherMac != nil && otherMac?.rememberedAddresses == nil)
    var oldWithMemory = oldRecord
    oldWithMemory.name = "Mac mini"
    let retired = SavedMacs.superseding(old: oldWithMemory.macID, by: newRecord.macID, proof: "100.101.102.103|7455", in: [oldWithMemory, newRecord])
    check("superseding: the old record goes with what it remembered; the newer keeps its own (none)",
          retired.map(\.macID) == [newRecord.macID] && retired.first?.rememberedAddresses == nil)
    var marked = oldWithMemory; marked.newKey = true
    check("a re-pairing in place of a Mac with a new key: the old record and its memory go",
          SavedMacs.replacingNewKey(old: marked.macID, new: newRecord.macID, in: [marked, newRecord]).map(\.rememberedAddresses) == [nil])
    let forgotten = [paired, newRecord].filter { $0.macID != id }      // StreamClient.forget: the record only
    check("Forget: nothing of it left in the list written", !SavedMacs.encode(forgotten).contains(ts6.host)
          && !SavedMacs.encode(forgotten).contains("rememberedAddresses"))
    let rows = P.remoteRows(saved: SavedMacs.remoteOrder([only]).map { (macID: $0.macID, name: $0.name) }, listedIDs: [], now: 10,
                            searchingSince: 0, localNetworkDenied: false)
    check("a saved Mac whose only addresses are remembered ones has its Remote row", rows.map(\.macID) == [id])

    let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970; enc.outputFormatting = [.sortedKeys]
    let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
    let mainRecord = MainSavedMac(macID: id, fingerprint: Base64URL.encode(fp), name: "Mac mini", recognitionKey: Base64URL.encode(Data(repeating: 9, count: 32)),
                                  remotePort: 7455, addresses: [tsName, wifi], typedAddresses: nil, infoIssuedAt: t1 - 7, bonjourName: "Mac mini",
                                  lastWorked: nil, pairedAt: Date(timeIntervalSince1970: t0), method: "qr", lastConnectedAt: nil, lastRoute: "Tailscale",
                                  homeTLS: true, revoked: nil, newKey: nil)
    let mainText = String(data: try! enc.encode([mainRecord]), encoding: .utf8)!
    let read = SavedMacs.decode(mainText)
    check("a record written before this change decodes, nothing remembered, and is written back byte for byte",
          read.count == 1 && read.first?.rememberedAddresses == nil && read.first?.addressesListedAt == nil && SavedMacs.encode(read) == mainText)
    let newer = refresh(read.first ?? m, [wifi], at: t2)
    let newerText = SavedMacs.encode([newer])
    check("a record this build wrote round-trips, its new fields included", SavedMacs.decode(newerText) == [newer]
          && newerText.contains("\"rememberedAddresses\":[{\"address\":") && newerText.contains("\"addressesListedAt\":\(Int(t2))"))
    var expected = mainRecord; expected.addresses = [wifi]; expected.infoIssuedAt = t2 - 7
    check("a build from before this change reads it (the new keys ignored)", (try? dec.decode([MainSavedMac].self, from: Data(newerText.utf8))) == [expected])

    vpnMemoryModel()
}

/// SplitMix64: the random model's lives are the same at every run.
struct VPNMemoryRandom: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// 2,000 random lives of one saved Mac against an independent bookkeeping of when each of its VPN addresses
/// was last listed: kind 18s with any mix of its addresses (Tailscale's, a second Tailscale set, another VPN's,
/// a LAN and an internet one), Remote Access off, empty lists, a port change, the clock on by a minute to a
/// season or back by an hour, and new pairings of the same Mac. After every step the rule's promises hold: at
/// most four, only VPN addresses, none the Mac lists, each destination once, none timed after now or older than
/// 90 days, newest first, nil rather than empty; every VPN address a list had, not listed now and last listed
/// within 90 days, remembered unless four as new or newer are (and once dropped for the cap or its age, gone
/// until a list has it again), with the time it was last listed; and the dial puts them after the Mac's list,
/// each once. Written never to crash, whatever a mutant does: its verdict is one check, printed at its end.
func vpnMemoryModel() {
    var random = VPNMemoryRandom(state: 2026_11_11)
    func r(_ n: Int) -> Int { Int.random(in: 0..<n, using: &random) }
    let fp = Data((0..<32).map { UInt8($0 &+ 77) })
    let id = MacID.make(fingerprint: fp)
    let pool: [MacAddress] = [
        MacAddress(host: "mac.tail1.ts.net", kind: MacAddress.vpn, via: "Tailscale"), MacAddress(host: "100.64.0.9", kind: MacAddress.vpn, via: "Tailscale"),
        MacAddress(host: "fd7a:115c:a1e0::9", kind: MacAddress.vpn, via: "Tailscale"), MacAddress(host: "mac2.tail1.ts.net", kind: MacAddress.vpn, via: "Tailscale"),
        MacAddress(host: "100.64.0.10", kind: MacAddress.vpn, via: "Tailscale"), MacAddress(host: "10.8.0.6", kind: MacAddress.vpn, via: "VPN (utun6)"),
        MacAddress(host: "192.168.1.20", kind: MacAddress.lan, via: "Wi‑Fi"), MacAddress(host: "203.0.113.9", kind: MacAddress.internet, via: "Router"),
    ]
    // No pool address has a port of its own, so a destination is its host whatever the Mac's port.
    func host(_ a: MacAddress) -> String { a.host.lowercased() }
    func record(_ addresses: [MacAddress], port: Int, at t: Double) -> SavedMac {
        SavedMac(macID: id, fingerprint: Base64URL.encode(fp), name: "M", recognitionKey: Base64URL.encode(Data(repeating: 1, count: 32)),
                 remotePort: port, addresses: addresses, typedAddresses: nil, infoIssuedAt: 0, bonjourName: nil, lastWorked: nil,
                 pairedAt: Date(timeIntervalSince1970: t), method: "qr", lastConnectedAt: nil, lastRoute: nil)
    }
    var broken: [String] = []
    var steps = 0, seen = 0, capped = 0, aged = 0
    for life in 0..<2_000 {
        var now = 1_790_000_000.0 + Double(r(1_000_000))
        var m = record((0..<pool.count).filter { _ in r(2) == 0 }.map { pool[$0] }, port: 7455, at: now)
        var lastListed: [String: Double] = [:]
        for a in m.addresses where a.kind == MacAddress.vpn { lastListed[host(a)] = now }
        var issued = 0.0
        for _ in 0..<(5 + r(25)) {
            steps += 1
            now += [60.0, 3600, 86_400, 20 * 86_400, 45 * 86_400, 100 * 86_400, -3600][r(7)]
            issued += 1
            let list = (0..<pool.count).filter { _ in r(2) == 0 }.map { pool[$0] }
            if r(12) == 0 {
                let fresh = record(list, port: m.remotePort, at: now)
                m = SavedMacs.adding(fresh, to: [m]).first { $0.macID == id } ?? fresh
                issued = 0
                for a in m.addresses where a.kind == MacAddress.vpn { lastListed[host(a)] = now }
            } else {
                let on = r(8) != 0
                let info = MacInfo(macID: id, name: "M", issuedAt: issued, remoteAccess: on, remotePort: r(10) == 0 ? 7460 : m.remotePort,
                                   internet: false, addresses: list)
                guard let next = SavedMacs.refreshed(m, info: info, fingerprint: fp, allowLoopback: false, now: now) else {
                    broken.append("life \(life): a newer kind 18 refused"); continue
                }
                m = next
                if on && !list.isEmpty { for a in list where a.kind == MacAddress.vpn { lastListed[host(a)] = now } }
            }
            let rem = m.rememberedAddresses ?? []
            let current = Set(m.addresses.map(host))
            // As the rule does at every look: a time after now read as now; a listed address keeps its list's time.
            for (k, t) in lastListed where !current.contains(k) { lastListed[k] = min(t, now) }
            func fail(_ why: String) { broken.append("life \(life): \(why)") }
            if rem.count > SavedMacs.rememberCap { fail("over the cap") }
            if rem.contains(where: { $0.address.kind != MacAddress.vpn }) { fail("a LAN or internet address remembered") }
            if rem.contains(where: { current.contains(host($0.address)) }) { fail("an address the Mac lists remembered") }
            if Set(rem.map { host($0.address) }).count != rem.count { fail("a destination twice") }
            if rem.contains(where: { $0.listedAt > now || now - $0.listedAt > SavedMacs.rememberFor }) { fail("a time after now or older than 90 days") }
            if zip(rem, rem.dropFirst()).contains(where: { $0.listedAt < $1.listedAt }) { fail("not newest first") }
            if m.rememberedAddresses == [] { fail("an empty list kept") }
            let have = Set(rem.map { host($0.address) })
            for (k, t) in lastListed where !current.contains(k) && !have.contains(k) {
                if now - t > SavedMacs.rememberFor { aged += 1; lastListed[k] = nil; continue }
                if rem.filter({ $0.listedAt >= t }).count < SavedMacs.rememberCap { fail("\(k), last listed \(Int(now - t)) s ago, forgotten with room left") }
                capped += 1
                lastListed[k] = nil
            }
            for x in rem where lastListed[host(x.address)].map({ abs($0 - x.listedAt) > 0.001 }) ?? true {
                fail("\(x.address.host) at \(Int(x.listedAt)), last listed at \(lastListed[host(x.address)].map { Int($0) } ?? -1)")
            }
            let dial = RemoteDialPolicy.order(m.allAddresses, remembered: SavedMacs.remembered(m, now: now), remotePort: m.remotePort,
                                              lastWorked: nil, localIPv4: [])
            if let i = dial.firstIndex(where: { $0.remembered }), dial[i...].contains(where: { !$0.remembered }) { fail("a remembered address before the Mac's list") }
            if Set(dial.map { $0.key.lowercased() }).count != dial.count || dial.filter(\.remembered).count != rem.count { fail("the dial: each once, every remembered one") }
            seen += rem.count
        }
    }
    for line in broken.prefix(5) { print("     \(line)") }
    check("model: 2,000 random lives (\(steps) kind 18s and pairings, \(seen) remembered addresses seen, \(capped) dropped for the cap, \(aged) aged out): every promise of the rule kept",
          broken.isEmpty && steps > 30_000 && seen > 50_000 && capped > 500 && aged > 1_000)
}
