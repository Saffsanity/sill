// H3 (step 5): DiscoveryPolicy's remote rules, RemoteDialPolicy and SavedMacs, pure, compiled with
// StreamProtocol's sources as one module (build.sh strips `import StreamProtocol`).
import Foundation
#if canImport(Darwin)
import Darwin
#endif
var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) { if ok { passes += 1; print("ok   \(name)") } else { fails += 1; print("FAIL \(name)") } }
typealias P = DiscoveryPolicy
typealias R = RemoteDialPolicy

// MARK: Remote rows
let saved: [(macID: String, name: String)] = [("A", "Mac mini"), ("B", "Studio")]
check("remote rows: none before the network's 3 s", P.remoteRows(saved: saved, listedIDs: [], now: 2.99, searchingSince: 0, localNetworkDenied: false).isEmpty)
check("remote rows: both at 3 s", P.remoteRows(saved: saved, listedIDs: [], now: 3.0, searchingSince: 0, localNetworkDenied: false).map(\.macID) == ["A", "B"])
check("remote rows: a listed Mac has no Remote row", P.remoteRows(saved: saved, listedIDs: ["A"], now: 10, searchingSince: 0, localNetworkDenied: false).map(\.macID) == ["B"])
check("remote rows: at once with Local Network denied", P.remoteRows(saved: saved, listedIDs: [], now: 0.1, searchingSince: 0, localNetworkDenied: true).count == 2)
check("remote rows: the 3 s count from the last search start", P.remoteRows(saved: saved, listedIDs: [], now: 12, searchingSince: 10, localNetworkDenied: false).isEmpty)

// MARK: Automatic remote dial timing
func due(_ now: Double, listed: Bool = false, lost: Double = 100, left: Double? = nil, direct: Bool = false, changed: Bool = false) -> (Bool, Double?) {
    let d = P.remoteDialDue(listed: listed, lostAt: lost, networkLeftAt: left, rememberedDirect: direct, pathChangedSinceLoss: changed, now: now)
    return (d.dial, d.recheckAt)
}
check("dial due: not at 2.99 s after the loss, recheck at 3 s", due(102.99) == (false, 103))
check("dial due: at 3 s", due(103).0)
check("dial due: never while a row lists the Mac", !due(103, listed: true).0 && due(103, listed: true).1 == nil)
check("dial due: a remembered Direct Mac waits 6 s", due(105.9, direct: true) == (false, 106) && due(106, direct: true).0)
check("dial due: the network listed it 1 s before the loss: not until 10 s after that", due(103, left: 99) == (false, 109) && due(109, left: 99).0)
check("dial due: the path changed since the loss: the grace is skipped", due(103, left: 99, changed: true).0)
check("dial due: a network sighting long ago changes nothing", due(103, left: 50).0)
check("dial due: stops 120 s after the loss", !due(219.9 + 0.2).0 && due(220.1).1 == nil && due(219.9).0)
check("retry delays 2, 4, 8, then 10 s", (1...6).map { P.remoteRetryDelay(afterFailures: $0) } == [2, 4, 8, 10, 10, 10])

// A saved Mac's sightings by Mac ID, as StreamClient.recomputeMacs keeps them (savedSightings) and
// reconnectIfListed passes them (review fix, 2026-09-25): the Mac listed at the connect and at one
// more browser change, then no change for an hour; its row goes at 3600, another Mac's comes, and
// the loss is seen at 3600.2. The grace counts from the moment the row went (the old input, the
// last look while it was listed, made the dial due 3 s after the loss).
var byID = P.NetworkSightings()
for t in [0.5, 5.1] { byID = P.sightings(byID, listed: ["A"], now: t) }
byID = P.sightings(byID, listed: ["B"], now: 3600)
check("sightings by Mac ID: the moment the row went, not the last look while it was listed",
      byID.leftAt == ["A": 3600] && byID.since == ["B": 3600])
check("dial due: a Mac listed since the connect whose row went at the loss waits until 10 s after it went",
      due(3603.2, lost: 3600.2, left: byID.leftAt["A"]) == (false, 3610) && due(3609.99, lost: 3600.2, left: byID.leftAt["A"]).0 == false
      && due(3610, lost: 3600.2, left: byID.leftAt["A"]).0)
byID = P.sightings(byID, listed: ["B"], now: 3605)
check("sightings by Mac ID: still gone 5 s later: the moment it went is kept", byID.leftAt["A"] == 3600)
byID = P.sightings(byID, listed: ["A", "B"], now: 3606)
check("sightings by Mac ID: back on the network: listed afresh, no dial", byID.leftAt["A"] == nil && byID.since["A"] == 3606
      && due(3606, listed: true, lost: 3600.2, left: byID.leftAt["A"]) == (false, nil))

// MARK: Dial order
func a(_ host: String, _ kind: String, _ via: String, port: Int? = nil) -> MacAddress { MacAddress(host: host, port: port, kind: kind, via: via) }
let mac = [a("192.168.1.20", "lan", "Wi-Fi"), a("mac-mini.tail1234.ts.net", "vpn", "Tailscale"), a("100.101.102.103", "vpn", "Tailscale"),
           a("fd7a:115c:a1e0::1234", "vpn", "Tailscale"), a("10.0.5.9", "lan", "Ethernet"), a("home.example.net", "internet", "Address name", port: 17455),
           a("203.0.113.9", "internet", "Router"), a("2001:db8::20", "internet", "IPv6"), a("100.101.102.103", "vpn", "Tailscale")]
let home: [(address: [UInt8], prefix: Int)] = [([192, 168, 1, 77], 24)]
let o1 = R.order(mac, remotePort: 7455, lastWorked: nil, localIPv4: home).map { "\($0.host):\($0.port)" }
check("order: VPN names, VPN v4, VPN v6, the shared LAN, internet names, internet IPs, other LANs; once each (\(o1))",
      o1 == ["mac-mini.tail1234.ts.net:7455", "100.101.102.103:7455", "fd7a:115c:a1e0::1234:7455", "192.168.1.20:7455",
             "home.example.net:17455", "203.0.113.9:7455", "2001:db8::20:7455", "10.0.5.9:7455"])
let away = R.order(mac, remotePort: 7455, lastWorked: nil, localIPv4: [([172, 20, 10, 2], 28)]).map(\.host)
check("order: away, the LAN addresses go last", Array(away.suffix(2)) == ["192.168.1.20", "10.0.5.9"])
check("order: the address that last worked first", R.order(mac, remotePort: 7455, lastWorked: "203.0.113.9|7455", localIPv4: home).first?.host == "203.0.113.9")
check("order: a stale lastWorked changes nothing", R.order(mac, remotePort: 7455, lastWorked: "1.2.3.4|7455", localIPv4: home).map { "\($0.host):\($0.port)" } == o1)
check("order: the Mac's port for addresses without one", R.order([a("100.64.0.1", "vpn", "Tailscale")], remotePort: 7460, lastWorked: nil, localIPv4: []).first?.port == 7460)
check("order: a test host's loopback address first (the simulator on the same Mac), whatever came before it",
      R.order([a("100.64.0.2", "vpn", "Tailscale"), a("127.0.0.1", "lan", "This Mac"), a("192.168.1.20", "lan", "Wi-Fi")], remotePort: 7455,
              lastWorked: nil, localIPv4: home).map(\.host) == ["127.0.0.1", "100.64.0.2", "192.168.1.20"])
check("order: a Tailscale-shaped address saved as internet is still a VPN address",
      R.order([a("203.0.113.9", "internet", "Router"), a("100.100.1.1", "internet", "")], remotePort: 7455, lastWorked: nil, localIPv4: []).first?.host == "100.100.1.1")

// MARK: Address shapes
check("Tailscale shapes", R.isVPNAddress("100.64.0.1") && R.isVPNAddress("100.127.255.254") && !R.isVPNAddress("100.128.0.1")
      && !R.isVPNAddress("100.63.255.255") && R.isVPNAddress("fd7a:115c:a1e0::9") && R.isVPNAddress("Mac.Tail1.TS.net") && !R.isVPNAddress("ts.net.example.com"))
check("kinds of addresses without one", R.kind(ofHost: "192.168.0.4") == "lan" && R.kind(ofHost: "10.1.2.3") == "lan" && R.kind(ofHost: "172.31.0.1") == "lan"
      && R.kind(ofHost: "172.32.0.1") == "internet" && R.kind(ofHost: "203.0.113.9") == "internet" && R.kind(ofHost: "127.0.0.1") == "lan"
      && R.kind(ofHost: "fd12::1") == "lan" && R.kind(ofHost: "2001:db8::1") == "internet" && R.kind(ofHost: "100.90.1.1") == "vpn"
      && R.kind(ofHost: "home.example.net") == "internet")
check("shared subnet", R.IPv4.sameNetwork([192, 168, 1, 20], [192, 168, 1, 77], prefix: 24) && !R.IPv4.sameNetwork([192, 168, 2, 20], [192, 168, 1, 77], prefix: 24)
      && R.IPv4.sameNetwork([10, 1, 200, 3], [10, 1, 7, 9], prefix: 16) && !R.IPv4.sameNetwork([10, 1, 2, 3], [10, 1, 2, 3], prefix: 0))

// MARK: Failures
let vpnC = R.Candidate(host: "100.101.102.103", port: 7455, kind: "vpn", via: "Tailscale")
let tsName = R.Candidate(host: "mac.tail1.ts.net", port: 7455, kind: "vpn", via: "Tailscale")
let lanC = R.Candidate(host: "192.168.1.20", port: 7455, kind: "lan", via: "Wi-Fi")
let netC = R.Candidate(host: "203.0.113.9", port: 7455, kind: "internet", via: "Router")
let nameC = R.Candidate(host: "home.example.net", port: 17455, kind: "internet", via: "Address name")
check("pin failed: wrong Mac", R.classify(.tls(-9808), candidate: vpnC, usedTunnel: true) == .wrongMac && R.classify(.tls(-9808), candidate: netC, usedTunnel: false) == .wrongMac)
check("pin failed on a LAN address: does not count", R.classify(.tls(-9808), candidate: lanC, usedTunnel: false) == nil)
check("the Mac refused our key: revoked", R.classify(.tlsAfterReady(-9825), candidate: vpnC, usedTunnel: true) == .revoked
      && R.classify(.tlsAfterReady(-9829), candidate: netC, usedTunnel: nil) == .revoked && R.classify(.goodbye("removed"), candidate: netC, usedTunnel: nil) == .revoked)
check("refused, and closed before TLS", R.classify(.posix(ECONNREFUSED), candidate: netC, usedTunnel: false) == .refused
      && R.classify(.posix(ECONNRESET), candidate: vpnC, usedTunnel: true) == .refused && R.classify(.tls(-9816), candidate: netC, usedTunnel: nil) == .refused)
check("goodbyes: remoteOff and busy", R.classify(.goodbye("remoteOff"), candidate: vpnC, usedTunnel: true) == .remoteOff && R.classify(.goodbye("busy"), candidate: vpnC, usedTunnel: true) == .busy)
check("names: not found; a .ts.net name that does not resolve is the VPN off",
      R.classify(.dns(-65554), candidate: nameC, usedTunnel: nil) == .nameNotFound && R.classify(.dns(-65538), candidate: tsName, usedTunnel: nil) == .vpnOff)
check("Local Network on a LAN address", R.classify(.dns(-65570), candidate: lanC, usedTunnel: false) == .localNetwork)
check("not Sill", R.classify(.tls(-9836), candidate: netC, usedTunnel: nil) == .notSill && R.classify(.notSill, candidate: netC, usedTunnel: nil) == .notSill
      && R.classify(.tls(-9810), candidate: vpnC, usedTunnel: true) == .notSill)
check("silence: didn't answer; on a VPN address with no tunnel in the path, the VPN is off here",
      R.classify(.timeout, candidate: netC, usedTunnel: false) == .noAnswer && R.classify(.posix(ETIMEDOUT), candidate: vpnC, usedTunnel: false) == .vpnOff
      && R.classify(.posix(ENETUNREACH), candidate: vpnC, usedTunnel: true) == .noAnswer && R.classify(.posix(EHOSTUNREACH), candidate: vpnC, usedTunnel: nil) == .noAnswer
      && R.classify(.noWindowList, candidate: netC, usedTunnel: nil) == .noAnswer)
check("priority", R.worst([.noAnswer, .wrongMac, .refused]) == .wrongMac && R.worst([.notSill, .refused]) == .refused
      && R.worst([.nameNotFound, .vpnOff]) == .vpnOff && R.worst([.noAnswer, .notSill]) == .notSill && R.worst([.revoked, .refused]) == .revoked
      && R.worst([.noAnswer]) == .noAnswer && R.worst([]) == nil && R.worst([.localNetwork, .noAnswer]) == .localNetwork)
check("the plan's order is kept", R.priority.firstIndex(of: .wrongMac)! < R.priority.firstIndex(of: .revoked)!
      && R.priority.firstIndex(of: .revoked)! < R.priority.firstIndex(of: .refused)! && R.priority.firstIndex(of: .refused)! < R.priority.firstIndex(of: .vpnOff)!
      && R.priority.firstIndex(of: .vpnOff)! < R.priority.firstIndex(of: .nameNotFound)! && R.priority.firstIndex(of: .nameNotFound)! < R.priority.firstIndex(of: .notSill)!
      && R.priority.firstIndex(of: .notSill)! < R.priority.firstIndex(of: .noAnswer)!)

// MARK: Saved Macs
func key(_ seed: UInt8) -> Data { Data(repeating: seed, count: 32) }
func savedMac(_ seed: UInt8, name: String = "Mac mini", paired: Double = 1000, last: Double? = nil) -> SavedMac {
    let fp = key(seed)
    return SavedMac(macID: MacID.make(fingerprint: fp), fingerprint: Base64URL.encode(fp), name: name, recognitionKey: Base64URL.encode(key(seed &+ 100)),
                    remotePort: 7455, addresses: [a("100.64.0.9", "vpn", "Tailscale")], typedAddresses: [a("home.example.net", "internet", "")],
                    infoIssuedAt: 50, bonjourName: nil, lastWorked: "100.64.0.9|7455", pairedAt: Date(timeIntervalSince1970: paired), method: "qr",
                    lastConnectedAt: last.map { Date(timeIntervalSince1970: $0) }, lastRoute: nil)
}
let m1 = savedMac(1)
check("encode/decode round trip", SavedMacs.decode(SavedMacs.encode([m1, savedMac(2)])) == [m1, savedMac(2)])
var forged = savedMac(3); forged.macID = m1.macID
check("a record whose Mac ID is not its key's is dropped", SavedMacs.decode(SavedMacs.encode([forged, m1])) == [m1])
check("garbage decodes to nothing", SavedMacs.decode("{") == [] && SavedMacs.decode(nil) == [] && SavedMacs.decode("[]") == [])
check("never saved: link-local, zones; loopback only when allowed",
      !SavedMacs.keepable("169.254.3.4", allowLoopback: true) && !SavedMacs.keepable("fe80::1", allowLoopback: true) && !SavedMacs.keepable("fe80::1%en0", allowLoopback: true)
      && !SavedMacs.keepable("127.0.0.1", allowLoopback: false) && SavedMacs.keepable("127.0.0.1", allowLoopback: true) && !SavedMacs.keepable("::1", allowLoopback: false)
      && SavedMacs.keepable("100.64.0.9", allowLoopback: false) && SavedMacs.keepable("fd7a:115c:a1e0::1", allowLoopback: false))
var list: [SavedMac] = []
for i in 0..<16 { list = SavedMacs.adding(savedMac(UInt8(10 + i), paired: Double(2000 + i), last: i == 0 ? 9000 : nil), to: list) }
list = SavedMacs.adding(savedMac(40, paired: 5000), to: list)
check("the cap: 16, the one used longest ago dropped (the oldest pairing, not the oldest-paired-but-used)",
      list.count == 16 && !list.contains { $0.macID == savedMac(11).macID } && list.contains { $0.macID == savedMac(10).macID })
var re = savedMac(12); re.name = "Renamed"
check("re-pairing replaces the record", SavedMacs.adding(re, to: list).filter { $0.macID == re.macID }.map(\.name) == ["Renamed"] && SavedMacs.adding(re, to: list).count == 16)
let info = MacInfo(macID: m1.macID, name: "Studio\u{202E}", issuedAt: 60, remoteAccess: true, remotePort: 7460, internet: false,
                   addresses: [a("mac.tail1.ts.net", "vpn", "Tailscale"), a("fe80::1", "lan", "Wi-Fi"), a("127.0.0.1", "lan", "This Mac"), a("192.168.1.5", "lan", "Wi-Fi")])
let r1 = SavedMacs.refreshed(m1, info: info, fingerprint: key(1), allowLoopback: false)
check("refresh: name (clean), port and the Mac's addresses; typed and lastWorked kept; link-local and loopback dropped",
      r1?.name == "Studio" && r1?.remotePort == 7460 && r1?.addresses.map(\.host) == ["mac.tail1.ts.net", "192.168.1.5"]
      && r1?.typedAddresses == m1.typedAddresses && r1?.lastWorked == m1.lastWorked && r1?.infoIssuedAt == 60)
check("refresh: loopback kept when allowed (DEBUG)", SavedMacs.refreshed(m1, info: info, fingerprint: key(1), allowLoopback: true)?.addresses.map(\.host).contains("127.0.0.1") == true)
check("refresh: another key, another Mac ID, or not newer: nothing",
      SavedMacs.refreshed(m1, info: info, fingerprint: key(2), allowLoopback: false) == nil
      && SavedMacs.refreshed(m1, info: { var i = info; i.macID = savedMac(2).macID; return i }(), fingerprint: key(1), allowLoopback: false) == nil
      && SavedMacs.refreshed(m1, info: { var i = info; i.issuedAt = 50; return i }(), fingerprint: key(1), allowLoopback: false) == nil)
// Review fixes: a kind 18 with no addresses (Remote Access off, or before the Mac's first look at
// its networks) keeps the saved ones; the name, the port and issuedAt still refresh.
let empty18 = { () -> MacInfo in var i = info; i.addresses = []; i.issuedAt = 70; return i }()
let rEmpty = SavedMacs.refreshed(m1, info: empty18, fingerprint: key(1), allowLoopback: false)
check("refresh: an empty list keeps the saved addresses (name, port and issuedAt still refresh)",
      rEmpty?.addresses == m1.addresses && rEmpty?.name == "Studio" && rEmpty?.remotePort == 7460 && rEmpty?.infoIssuedAt == 70
      && rEmpty?.typedAddresses == m1.typedAddresses)
let off18 = { () -> MacInfo in var i = info; i.remoteAccess = false; i.issuedAt = 71; return i }()
let rOff = SavedMacs.refreshed(m1, info: off18, fingerprint: key(1), allowLoopback: false)
check("refresh: a list from a Mac with Remote Access off keeps the saved addresses", rOff?.addresses == m1.addresses && rOff?.infoIssuedAt == 71)
let onlyLocal18 = { () -> MacInfo in var i = info; i.addresses = [a("fe80::1", "lan", "Wi-Fi"), a("127.0.0.1", "lan", "This Mac")]; i.issuedAt = 72; return i }()
check("refresh: a list with nothing keepable (link-local, loopback in Release) keeps the saved addresses",
      SavedMacs.refreshed(m1, info: onlyLocal18, fingerprint: key(1), allowLoopback: false)?.addresses == m1.addresses)
check("refresh: a list with something in it replaces the saved one (Remote Access on)",
      SavedMacs.refreshed(m1, info: { var i = info; i.addresses = [a("100.101.102.103", "vpn", "Tailscale")]; i.issuedAt = 73; return i }(),
                          fingerprint: key(1), allowLoopback: false)?.addresses.map(\.host) == ["100.101.102.103"])
// Then a pairing made over the overlay's typed path (no addresses but the typed one), refreshed by
// this session's kind 18: the Mac's own list, the typed one kept.
var typedOnly = savedMac(1); typedOnly.addresses = []; typedOnly.infoIssuedAt = 0
check("refresh: a typed pairing takes the session's kind 18 list", SavedMacs.refreshed(typedOnly, info: info, fingerprint: key(1), allowLoopback: false)?.allAddresses.map(\.host)
      == ["mac.tail1.ts.net", "192.168.1.5", "home.example.net"])

// MARK: The scanner's gate (RemoteDialPolicy.scanStartsPairing)
let s1 = Data([1, 2, 3]), s2 = Data([4, 5, 6])
check("scan: never while a pairing runs or has just succeeded, tapped or not",
      !R.scanStartsPairing(busy: true, failed: false, secret: s1, lastScanned: nil, tapped: false)
      && !R.scanStartsPairing(busy: true, failed: false, secret: s2, lastScanned: s1, tapped: true))
check("scan: after a failure the same code, found again by itself, is held",
      !R.scanStartsPairing(busy: false, failed: true, secret: s1, lastScanned: s1, tapped: false))
check("scan: after a failure a tap on the same code tries again", R.scanStartsPairing(busy: false, failed: true, secret: s1, lastScanned: s1, tapped: true))
check("scan: after a failure another code starts at once", R.scanStartsPairing(busy: false, failed: true, secret: s2, lastScanned: s1, tapped: false))
check("scan: after a failure that no scan started (typed, a link), a code starts", R.scanStartsPairing(busy: false, failed: true, secret: s1, lastScanned: nil, tapped: false))
check("scan: idle, any code starts (a card opened again)", R.scanStartsPairing(busy: false, failed: false, secret: s1, lastScanned: s1, tapped: false))

let names = SavedMacs.displayNames([savedMac(5, name: "Mac mini", paired: 30), savedMac(6, name: "Mac mini", paired: 20), savedMac(7, name: "Studio", paired: 10)])
check("two Macs of one name: by pairing date", names[savedMac(6).macID] == "Mac mini" && names[savedMac(5).macID] == "Mac mini (2)" && names[savedMac(7).macID] == "Studio")
let tag = RecognitionTag.make(recognitionKey: key(1 &+ 100))!
check("a tag names its Mac", SavedMacs.recognize(tag: tag, in: [savedMac(2), m1]) == m1.macID)
check("a tag of an unknown Mac, none, or garbage: nothing", SavedMacs.recognize(tag: RecognitionTag.make(recognitionKey: key(99))!, in: [m1]) == nil
      && SavedMacs.recognize(tag: nil, in: [m1]) == nil && SavedMacs.recognize(tag: "zzzz", in: [m1]) == nil)
var wrong = 0
for _ in 0..<2000 {
    var k = [UInt8](repeating: 0, count: 32); _ = SecRandomCopyBytes(kSecRandomDefault, 32, &k)
    if SavedMacs.recognize(tag: RecognitionTag.make(recognitionKey: Data(k))!, in: [m1, savedMac(2)]) != nil { wrong += 1 }
}
check("2,000 tags of random keys match no saved Mac", wrong == 0)
let parsed = try! AddressParser.parse("100.101.102.103:7460").get()
check("a linked address gets its kind and Tailscale's name", R.address(for: parsed) == MacAddress(host: "100.101.102.103", port: 7460, kind: "vpn", via: "Tailscale"))

print("\(passes) passed, \(fails) failed")
exit(fails == 0 ? 0 : 1)
