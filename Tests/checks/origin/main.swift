// H3 (OriginPolicy): Sources/SillHost/OriginPolicy.swift and InterfaceSnapshot.swift on their own.
//   swiftc -O Sources/SillHost/OriginPolicy.swift Sources/SillHost/InterfaceSnapshot.swift Tests/checks/origin/main.swift -o .build/checks/origin/check
import Foundation
var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) { if ok { passes += 1; print("ok   \(name)") } else { fails += 1; print("FAIL \(name)") } }
typealias P = OriginPolicy
func b(_ s: String) -> [UInt8] { IPBytes.parse(s)! }
// A Mac shaped like Noah's: en0 on 192.168.1.20/24 with a ULA and a global /64, en14 link-local,
// awdl0 and llw0, utun0–3 link-local only, Tailscale on utun4, a WireGuard wg0, lo0.
var ifs = P.Interfaces()
for (n, k) in [("en0", P.InterfaceKind.lan), ("en14", .lan), ("awdl0", .peerToPeer), ("llw0", .peerToPeer), ("utun0", .tunnel),
               ("utun4", .tunnel), ("wg0", .tunnel), ("lo0", .loopback), ("bridge0", .lan), ("gif0", .other)] { ifs.kind[n] = k }
ifs.owner[b("192.168.1.20")] = "en0"; ifs.owner[b("fd4e:4f6b:37dc:4a0f::20")] = "en0"; ifs.owner[b("2001:db8:1::20")] = "en0"
ifs.owner[b("100.88.123.45")] = "utun4"; ifs.owner[b("fd7a:115c:a1e0::abcd:ef01")] = "utun4"; ifs.owner[b("10.99.0.2")] = "wg0"
ifs.owner[b("169.254.172.122")] = "en14"; ifs.owner[b("127.0.0.1")] = "lo0"; ifs.owner[b("::1")] = "lo0"
ifs.owner[b("203.0.113.20")] = "bridge0"
ifs.prefixes = [("en0", b("192.168.1.0"), 24), ("en0", b("fd4e:4f6b:37dc:4a0f::"), 64), ("en0", b("2001:db8:1::"), 64),
                ("en14", b("169.254.0.0"), 16), ("bridge0", b("203.0.113.0"), 24), ("bridge0", b("100.72.0.0"), 16)]
func c(_ remote: String, local: String? = nil, scope: String? = nil) -> P.Origin { P.classify(remote: remote, localAddress: local, scope: scope, interfaces: ifs) }
func expect(_ name: String, _ got: P.Origin, _ want: P.Origin) { check("\(name) → \(got.rawValue)", got == want) }

// 1–2 loopback, mapped IPv4
expect("127.0.0.1", c("127.0.0.1", local: "127.0.0.1"), .loopback)
expect("127.9.9.9 (all of 127/8)", c("127.9.9.9", local: "127.0.0.1"), .loopback)
expect("::1", c("::1", local: "::1"), .loopback)
expect("::ffff:127.0.0.1 (mapped)", c("::ffff:127.0.0.1", local: "::ffff:127.0.0.1"), .loopback)
expect("::ffff:203.0.113.9 on en0 (mapped, then internet)", c("::ffff:203.0.113.9", local: "::ffff:192.168.1.20"), .internet)
expect("::ffff:192.168.1.23 on en0 (mapped, on-link)", c("::ffff:192.168.1.23", local: "192.168.1.20"), .lan)
// 3–4 peer-to-peer: the scope decides
expect("fe80::1 scoped awdl0", c("fe80::8425:bdff:fe62:8930", local: "fe80::1", scope: "awdl0"), .direct)
expect("fe80::1 scoped llw0", c("fe80::1", scope: "llw0"), .direct)
expect("fe80::1 scoped en0", c("fe80::47b:5945:e0aa:d0ac", local: "fe80::2", scope: "en0"), .lan)
expect("fe80::1 scoped anri0 (USB)", c("fe80::18fe:abff:febb:459f", scope: "anri0"), .lan)
// 5 tunnels
expect("100.84.3.2 arriving at the Tailscale address (utun4)", c("100.84.3.2", local: "100.88.123.45"), .vpn)
expect("fd7a:115c:a1e0::1 arriving on utun4", c("fd7a:115c:a1e0::1", local: "fd7a:115c:a1e0::abcd:ef01"), .vpn)
expect("the Mac itself at its Tailscale address", c("100.88.123.45", local: "100.88.123.45"), .vpn)
expect("ULA on utun (a VPN's own range)", c("fd00:aaaa::5", local: "fd7a:115c:a1e0::abcd:ef01"), .vpn)
expect("RFC 1918 on wg0", c("10.99.0.9", local: "10.99.0.2"), .vpn)
expect("a link-local source on a tunnel is still vpn", c("fe80::9", scope: "utun4"), .vpn)
for n in ["ipsec0", "ppp0", "tun0", "tap0", "wg1", "feth3", "zt5", "utun9"] {
    expect("arrival scope \(n) (by name)", c("203.0.113.9", scope: n), .vpn)
}
check("a point-to-point interface of any name is a tunnel", P.interfaceKind(name: "gif0", pointToPoint: true) == .tunnel)
check("awdl and llw are peer-to-peer, en and bridge LAN, lo loopback, gif other",
      P.interfaceKind(name: "awdl0") == .peerToPeer && P.interfaceKind(name: "llw0") == .peerToPeer && P.interfaceKind(name: "en0") == .lan
      && P.interfaceKind(name: "bridge0") == .lan && P.interfaceKind(name: "anpi0") == .lan && P.interfaceKind(name: "anri0") == .lan
      && P.interfaceKind(name: "lo0") == .loopback && P.interfaceKind(name: "gif0") == .other)
// 6 LAN interfaces
expect("192.168.1.23 on en0 (on-link)", c("192.168.1.23", local: "192.168.1.20"), .lan)
expect("192.168.7.9 on en0 (private, routed: a VPN ending on the router)", c("192.168.7.9", local: "192.168.1.20"), .lan)
expect("10.1.2.3 on en0 (private)", c("10.1.2.3", local: "192.168.1.20"), .lan)
expect("172.16.0.1 on en0 (private)", c("172.16.0.1", local: "192.168.1.20"), .lan)
expect("172.31.255.1 on en0 (private)", c("172.31.255.1", local: "192.168.1.20"), .lan)
expect("172.32.0.1 on en0 (public)", c("172.32.0.1", local: "192.168.1.20"), .internet)
expect("172.15.0.1 on en0 (public)", c("172.15.0.1", local: "192.168.1.20"), .internet)
expect("203.0.113.9 on en0", c("203.0.113.9", local: "192.168.1.20"), .internet)
expect("100.72.1.1 on en0, not on-link (carrier space from outside)", c("100.72.1.1", local: "192.168.1.20"), .internet)
expect("100.72.1.1 on bridge0, on-link (a LAN numbered in carrier space)", c("100.72.1.1", local: "203.0.113.20"), .lan)
expect("203.0.113.50 on bridge0 (a LAN numbered from public space)", c("203.0.113.50", local: "203.0.113.20"), .lan)
expect("203.0.113.50 on en0 (that prefix is bridge0's, not en0's)", c("203.0.113.50", local: "192.168.1.20"), .internet)
expect("ULA on en0 (on-link)", c("fd4e:4f6b:37dc:4a0f::99", local: "fd4e:4f6b:37dc:4a0f::20"), .lan)
expect("ULA on en0 (another ULA prefix: private)", c("fd11:2222::1", local: "fd4e:4f6b:37dc:4a0f::20"), .lan)
expect("global IPv6 on-link on en0", c("2001:db8:1::77", local: "2001:db8:1::20"), .lan)
expect("global IPv6 off-link on en0", c("2001:db8:2::77", local: "2001:db8:1::20"), .internet)
expect("169.254.1.2 on en14 (link-local)", c("169.254.1.2", local: "169.254.172.122"), .lan)
expect("169.254.1.2 with nothing known (link-local)", c("169.254.1.2"), .lan)
expect("unknown arrival: on-link of a LAN interface", c("192.168.1.99"), .lan)
expect("unknown arrival: public", c("198.51.100.4"), .internet)
expect("unknown arrival: 100.64/10 on-link of bridge0 (any LAN interface)", c("100.72.9.9"), .lan)
expect("an unparseable source is internet", c("not-an-address"), .internet)
// The doors
let all: [P.Origin] = [.loopback, .direct, .vpn, .lan, .internet]
check("home door: loopback, direct and lan only", all.filter(P.homeAdmits) == [.loopback, .direct, .lan])
check("remote door, internet off: loopback, vpn, lan", all.filter { P.remoteAdmits($0, internetAccess: false) } == [.loopback, .vpn, .lan])
check("remote door, internet on: loopback, vpn, lan, internet; never direct", all.filter { P.remoteAdmits($0, internetAccess: true) } == [.loopback, .vpn, .lan, .internet])
check("labels", P.label(.vpn, interface: "utun4", serviceName: "Tailscale") == "through Tailscale" && P.label(.vpn, interface: "utun6", serviceName: nil) == "through your VPN"
      && P.label(.internet, interface: nil, serviceName: nil) == "over the internet" && P.label(.lan, interface: "en0", serviceName: nil) == "by address"
      && P.label(.loopback, interface: nil, serviceName: nil) == "by address" && P.label(.direct, interface: "awdl0", serviceName: nil) == nil)
// Endpoint scopes (ported from the fixes' ClientLink)
check("scope: fe80::1%awdl0.52397", P.scope(ofEndpoint: "fe80::1%awdl0.52397") == "awdl0")
check("scope: [fe80::1%en0]:52397", P.scope(ofEndpoint: "[fe80::1%en0]:52397") == "en0")
check("scope: none on IPv4", P.scope(ofEndpoint: "127.0.0.1:64431") == nil)
check("scope: numeric %16 names nothing", P.scope(ofEndpoint: "fe80::1%16.5000") == nil)
// IPBytes
check("parse strips brackets and zones", IPBytes.parse("[fe80::1%en0]") == IPBytes.parse("fe80::1"))
check("contains: /0, /32, /12 edges", IPBytes.contains(network: b("0.0.0.0"), bits: 0, address: b("8.8.8.8"))
      && IPBytes.contains(network: b("10.0.0.5"), bits: 32, address: b("10.0.0.5")) && !IPBytes.contains(network: b("10.0.0.5"), bits: 32, address: b("10.0.0.6"))
      && IPBytes.contains(network: b("172.16.0.0"), bits: 12, address: b("172.31.1.1")) && !IPBytes.contains(network: b("172.16.0.0"), bits: 12, address: b("172.32.1.1")))
check("contains: family mismatch is false", !IPBytes.contains(network: b("10.0.0.0"), bits: 8, address: b("fd00::1")))
check("text round trip", IPBytes.text(b("fd7a:115c:a1e0:0:0:0:0:1")) == "fd7a:115c:a1e0::1" && IPBytes.text(b("10.0.0.5")) == "10.0.0.5")
check("carrier-shared 100.64/10", IPBytes.isCarrierShared(b("100.64.0.1")) && IPBytes.isCarrierShared(b("100.127.255.255")) && !IPBytes.isCarrierShared(b("100.128.0.1")))

// The live table (read-only getifaddrs): loopback, and the Mac's own addresses by their owners.
let live = InterfaceSnapshot.shared
let entries = live.entries()
let liveIfs = live.interfaces()
check("live: loopback is loopback", P.classify(remote: "127.0.0.1", localAddress: "127.0.0.1", scope: nil, interfaces: liveIfs) == .loopback)
let tunnelV4 = entries.first { $0.pointToPoint && $0.address.count == 4 && !IPBytes.isLinkLocal($0.address) }
if let t = tunnelV4 {
    let a = IPBytes.text(t.address)
    check("live: a connection arriving at this Mac's own tunnel address (\(t.name)) is vpn",
          P.classify(remote: "100.100.100.100", localAddress: a, scope: nil, interfaces: liveIfs) == .vpn)
} else { print("info live: no point-to-point IPv4 address (no VPN up)") }
if let lan = entries.first(where: { $0.name.hasPrefix("en") && $0.address.count == 4 && !IPBytes.isLinkLocal($0.address) }) {
    let a = IPBytes.text(lan.address)
    check("live: a neighbour on \(lan.name)'s own prefix is lan", P.classify(remote: a, localAddress: a, scope: nil, interfaces: liveIfs) == .lan)
    check("live: a public source arriving on \(lan.name) is internet", P.classify(remote: "198.51.100.7", localAddress: a, scope: nil, interfaces: liveIfs) == .internet)
}
check("live: cached (the second read is the same object's cache)", live.entries() == entries)
print(fails == 0 ? "ALL PASS (\(passes) checks)" : "\(fails) FAILED of \(passes + fails)")
exit(Int32(min(fails, 100)))
