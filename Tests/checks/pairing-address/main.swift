// The pairing window's address rule (PairingWindowAddress.choose), pure, compiled with
// StreamProtocol's sources and the host's AddressList and OriginPolicy as one module (build.sh).
// Noah's store and the other VPNs' go through the real AddressList.build first, so the kinds are
// the ones the Mac really produces. Only Tailscale's name and addresses take this network's place;
// any other VPN's address goes under this network's (the review of ae7f5c9, 2026-09-25).
import Foundation

var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    if ok { passes += 1; print("ok   \(name)") } else { fails += 1; print("FAIL \(name) \(detail())") }
}
typealias C = PairingWindowAddress.Choice
typealias S = AddressList.Service
typealias V6 = AddressList.IPv6Entry
let D = 7455
func choose(_ a: [MacAddress], lan: String?, port: Int = D) -> C {
    PairingWindowAddress.choose(from: a, lan: lan, port: port, defaultPort: D)
}
func show(_ c: C) -> String { "\(c.primary) | \(c.secondary ?? "nil")" }

// MARK: Noah's store (scutil and the probe, 2026-09-24), Tailscale's name and addresses made up:
// utun0–3 link-local and nameless, Tailscale on utun4 (100.88.123.45, fd7a:115c:a1e0::abcd:ef01,
// MagicDNS tail5678.ts.net), the CoreDevice tunnel's ULA on utun5, en0 10.128.0.34 with a
// deprecated ULA.
let noah: [S] = [
    S(id: "u0", name: "", interface: "utun0", ipv4: [], ipv6: [V6(address: "fe80::a1", flags: 0)]),
    S(id: "u1", name: "", interface: "utun1", ipv4: [], ipv6: [V6(address: "fe80::a2", flags: 0)]),
    S(id: "u2", name: "", interface: "utun2", ipv4: [], ipv6: [V6(address: "fe80::a3", flags: 0)]),
    S(id: "u3", name: "", interface: "utun3", ipv4: [], ipv6: [V6(address: "fe80::a4", flags: 0)]),
    S(id: "ts", name: "Tailscale", interface: "utun4", ipv4: ["100.88.123.45"],
      ipv6: [V6(address: "fd7a:115c:a1e0::abcd:ef01", flags: 0), V6(address: "fe80::dc68:1", flags: 0)], matchDomains: ["", "tail5678.ts.net."]),
    S(id: "cd", name: "", interface: "utun5", ipv4: [], ipv6: [V6(address: "fdab:cdef:1234::1", flags: 0)]),
    S(id: "wifi", name: "Wi-Fi", interface: "en0", ipv4: ["10.128.0.34"],
      ipv6: [V6(address: "fe80::869:a388:779d:7833", flags: 1024), V6(address: "fd4e:4f6b:37dc:4a0f:1083:aa29:4357:c7a9", flags: 1104)]),
]
let magic = "lab-macbook-pro.tail5678.ts.net"
var input = AddressList.Input(services: noah, primaryInterface: "en0", tunnels: [], magicDNS: ["ts": magic])
// With the internet switch on too: an address name, the router's address, a stable global IPv6.
var withInternet = input
withInternet.services[6].ipv6.append(V6(address: "2001:db8::20", flags: 0x400))
withInternet.internet = true
withInternet.addressName = ParsedAddress(host: "home.example.net", port: 17455, kind: .name)
withInternet.routerIPv4 = "203.0.113.9"
let noahList = AddressList.build(input)
let noahInternet = AddressList.build(withInternet)
let lan = AddressList.lanAddress(input)
check("the store as AddressList builds it: name, v4, v6 (vpn), LAN (\(noahList.map { "\($0.host)/\($0.kind)" }))",
      noahList.map { "\($0.host)/\($0.kind)" } == ["\(magic)/vpn", "100.88.123.45/vpn", "fd7a:115c:a1e0::abcd:ef01/vpn", "10.128.0.34/lan"])
check("with the internet switch: also the address name, the router, the IPv6 (internet)",
      noahInternet.filter { $0.kind == MacAddress.internet }.map(\.host) == ["home.example.net", "203.0.113.9", "2001:db8::20"])
check("Noah's store: the MagicDNS name, the Tailscale IPv4 under it (\(show(choose(noahList, lan: lan))))",
      choose(noahList, lan: lan) == C(primary: magic, secondary: "100.88.123.45"))
check("…the same with the internet switch on: no router or address name in the window",
      choose(noahInternet, lan: lan) == C(primary: magic, secondary: "100.88.123.45"), show(choose(noahInternet, lan: lan)))
check("…on port 7456: both with :7456",
      choose(noahList, lan: lan, port: 7456) == C(primary: "\(magic):7456", secondary: "100.88.123.45:7456"), show(choose(noahList, lan: lan, port: 7456)))
check("…on port 17455 with the internet switch: both with :17455, not the address name's port",
      choose(noahInternet, lan: lan, port: 17455) == C(primary: "\(magic):17455", secondary: "100.88.123.45:17455"))
check("…on the default port: no port", !choose(noahList, lan: lan).primary.contains(":") && choose(noahList, lan: lan).secondary?.contains(":") == false)

// MagicDNS not kept (the name did not resolve to the tunnel's address): the IPv4 alone.
var noName = input; noName.magicDNS = [:]
check("no MagicDNS name: the Tailscale IPv4 alone (\(show(choose(AddressList.build(noName), lan: lan))))",
      choose(AddressList.build(noName), lan: lan) == C(primary: "100.88.123.45", secondary: nil))
// Tailscale with IPv4 turned off: IPv6 only.
var v6Only = noName; v6Only.services[4].ipv4 = []
check("Tailscale IPv6 only, no name: that IPv6 alone, in brackets (\(show(choose(AddressList.build(v6Only), lan: lan))))",
      choose(AddressList.build(v6Only), lan: lan) == C(primary: "[fd7a:115c:a1e0::abcd:ef01]", secondary: nil))
check("…on port 7456: [v6]:7456", choose(AddressList.build(v6Only), lan: lan, port: 7456).primary == "[fd7a:115c:a1e0::abcd:ef01]:7456")
var v6Named = input; v6Named.services[4].ipv4 = []
check("VPN name and IPv6 only: the name alone (an IPv6 is never the line under it)",
      choose(AddressList.build(v6Named), lan: lan) == C(primary: magic, secondary: nil), show(choose(AddressList.build(v6Named), lan: lan)))
// No VPN at all: this network's address, as before.
let lanOnlyInput = AddressList.Input(services: [noah[6]], primaryInterface: "en0")
check("LAN only: this network's address (\(show(choose(AddressList.build(lanOnlyInput), lan: AddressList.lanAddress(lanOnlyInput)))))",
      choose(AddressList.build(lanOnlyInput), lan: AddressList.lanAddress(lanOnlyInput)) == C(primary: "10.128.0.34", secondary: nil))
check("LAN only on port 7456", choose(AddressList.build(lanOnlyInput), lan: "10.128.0.34", port: 7456) == C(primary: "10.128.0.34:7456", secondary: nil))
var lanInternet = AddressList.Input(services: [withInternet.services[6]], primaryInterface: "en0")
lanInternet.internet = true; lanInternet.addressName = withInternet.addressName; lanInternet.routerIPv4 = "203.0.113.9"
check("LAN and the internet switch, no VPN: still this network's address",
      choose(AddressList.build(lanInternet), lan: "10.128.0.34") == C(primary: "10.128.0.34", secondary: nil))
// Tailscale down (the service has no address): nothing of it is listed.
var down = input; down.services[4].ipv4 = []; down.services[4].ipv6 = [V6(address: "fe80::dc68:1", flags: 0)]; down.magicDNS = [:]
check("Tailscale down: this network's address", choose(AddressList.build(down), lan: lan) == C(primary: "10.128.0.34", secondary: nil))
// Nothing at all.
check("nothing: “this Mac’s address”", choose([], lan: nil) == C(primary: "this Mac’s address", secondary: nil))
check("nothing on port 7456: still the placeholder, no port", choose([], lan: nil, port: 7456) == C(primary: "this Mac’s address", secondary: nil))

// MARK: Several VPNs
var more = noah
more.append(S(id: "wg", name: "Home WireGuard", interface: "utun7", ipv4: ["10.99.0.2"], ipv6: [V6(address: "fd99::2", flags: 0)]))
let many = AddressList.Input(services: more, primaryInterface: "en0", tunnels: [AddressList.Tunnel(interface: "utun9", ipv4: ["10.8.0.6"])],
                             magicDNS: ["ts": magic])
let manyList = AddressList.build(many)
check("WireGuard's 10.99.0.2 is the first VPN IPv4 in dial order (\(manyList.map(\.host)))",
      manyList.first { $0.kind == MacAddress.vpn && $0.host.hasPrefix("10.") }?.host == "10.99.0.2"
      && manyList.firstIndex { $0.host == "10.99.0.2" }! < manyList.firstIndex { $0.host == "100.88.123.45" }!)
check("WireGuard beside Tailscale: Tailscale's name with Tailscale's IPv4, never WireGuard's",
      choose(manyList, lan: lan) == C(primary: magic, secondary: "100.88.123.45"), show(choose(manyList, lan: lan)))
var manyNoName = many; manyNoName.magicDNS = [:]
check("several VPNs, no name: Tailscale's IPv4 alone, though WireGuard's comes first in dial order",
      choose(AddressList.build(manyNoName), lan: lan) == C(primary: "100.88.123.45", secondary: nil), show(choose(AddressList.build(manyNoName), lan: lan)))
let tunnelOnly = AddressList.Input(services: [noah[6]], primaryInterface: "en0", tunnels: [AddressList.Tunnel(interface: "utun9", ipv4: ["10.8.0.6"])])
check("a point-to-point tunnel, VPN (utun9), beside the LAN: this network's address, the tunnel's IPv4 under it",
      choose(AddressList.build(tunnelOnly), lan: AddressList.lanAddress(tunnelOnly)) == C(primary: "10.128.0.34", secondary: "10.8.0.6"),
      show(choose(AddressList.build(tunnelOnly), lan: AddressList.lanAddress(tunnelOnly))))
// The line under the name is the named VPN's own IPv4: Tailscale v6 only with a name, WireGuard v4.
var namedV6AndWG = more; namedV6AndWG[4].ipv4 = []
let mixed = AddressList.build(AddressList.Input(services: namedV6AndWG, primaryInterface: "en0", magicDNS: ["ts": magic]))
check("a named VPN without IPv4 beside another VPN's IPv4: the name alone (\(show(choose(mixed, lan: lan))))",
      choose(mixed, lan: lan) == C(primary: magic, secondary: nil))
// Two named VPNs (two tailnets): the first name, with its own IPv4.
let twoNames = [MacAddress(host: "a.tail1111.ts.net", kind: "vpn", via: "Tailscale A"), MacAddress(host: "b.tail2222.ts.net", kind: "vpn", via: "Tailscale B"),
                MacAddress(host: "100.64.0.1", kind: "vpn", via: "Tailscale A"), MacAddress(host: "100.64.0.2", kind: "vpn", via: "Tailscale B")]
check("two named VPNs: the first name with its own IPv4", choose(twoNames, lan: nil) == C(primary: "a.tail1111.ts.net", secondary: "100.64.0.1"))
let twoNamesSwapped = [twoNames[0], twoNames[1], twoNames[3], twoNames[2]]
check("…whatever order their IPv4 come in", choose(twoNamesSwapped, lan: nil) == C(primary: "a.tail1111.ts.net", secondary: "100.64.0.1"))

// MARK: VPNs that are not Tailscale (the review's scenarios, through the real AddressList.build)
// Beside Wi-Fi 192.168.1.20. A privacy VPN's address answers from nowhere: NordLynx gives every
// client 10.5.0.2 and WARP 172.16.0.2, so this network's address stays first and theirs goes under it.
let wifi = S(id: "wifi", name: "Wi-Fi", interface: "en0", ipv4: ["192.168.1.20"], ipv6: [V6(address: "fe80::1", flags: 0)])
let tailscale = S(id: "ts", name: "Tailscale", interface: "utun4", ipv4: ["100.88.123.45"],
                  ipv6: [V6(address: "fd7a:115c:a1e0::abcd:ef01", flags: 0)], matchDomains: ["tail5678.ts.net."])
let nord = S(id: "nord", name: "NordVPN", interface: "utun6", ipv4: ["10.5.0.2"], ipv6: [])
let mullvad = S(id: "mv", name: "Mullvad VPN", interface: "utun6", ipv4: ["10.64.12.34"], ipv6: [V6(address: "fc00:bbbb:bbbb:bb01::1:c23", flags: 0)])
let warp = S(id: "warp", name: "Cloudflare WARP", interface: "utun7", ipv4: ["172.16.0.2"], ipv6: [V6(address: "2606:4700:110:8a36::2", flags: 0)])
let work = S(id: "work", name: "Acme VPN", interface: "ipsec0", ipv4: ["10.200.1.5"], ipv6: [])
let wgMesh = S(id: "wg", name: "WireGuard Home", interface: "utun8", ipv4: ["10.99.0.2"], ipv6: [])
let v6VPN = S(id: "v6", name: "Home VPN", interface: "utun9", ipv4: [], ipv6: [V6(address: "fd99::2", flags: 0)])
func window(_ services: [S], primary: String = "en0", tunnels: [AddressList.Tunnel] = [], names: [String: String] = [:], port: Int = D) -> C {
    let input = AddressList.Input(services: services, primaryInterface: primary, tunnels: tunnels, magicDNS: names)
    return choose(AddressList.build(input), lan: AddressList.lanAddress(input), port: port)
}
let home = "192.168.1.20"
for (name, vpnService, expected, primary) in [("NordVPN (its tunnel the primary)", nord, "10.5.0.2", "utun6"), ("Mullvad (10.64, not 100.64)", mullvad, "10.64.12.34", "utun6"),
                                              ("Cloudflare WARP", warp, "172.16.0.2", "en0"), ("a work VPN (IKEv2, ipsec0)", work, "10.200.1.5", "en0"),
                                              ("a WireGuard mesh", wgMesh, "10.99.0.2", "en0")] {
    let c = window([wifi, vpnService], primary: primary)
    check("\(name) beside Wi-Fi: this network's address, \(expected) under it (\(show(c)))", c == C(primary: home, secondary: expected))
}
check("NordVPN beside Wi-Fi on port 7456: both with :7456",
      window([wifi, nord], primary: "utun6", port: 7456) == C(primary: "\(home):7456", secondary: "10.5.0.2:7456"), show(window([wifi, nord], primary: "utun6", port: 7456)))
check("a VPN with only an IPv6 beside Wi-Fi: this network's address, the IPv6 under it in brackets",
      window([wifi, v6VPN]) == C(primary: home, secondary: "[fd99::2]"), show(window([wifi, v6VPN])))
check("NordVPN and no LAN address: its IPv4 alone, as before", window([nord], primary: "utun6") == C(primary: "10.5.0.2", secondary: nil), show(window([nord], primary: "utun6")))
check("two other VPNs: the first IPv4 in dial order under this network's address (Acme's, by name)",
      window([wifi, wgMesh, work]) == C(primary: home, secondary: "10.200.1.5"), show(window([wifi, wgMesh, work])))
for (name, vpnService) in [("Mullvad", mullvad), ("Cloudflare WARP", warp), ("a work VPN (Acme)", work), ("NordVPN", nord)] {
    let c = window([wifi, vpnService, tailscale])
    check("Tailscale without its name beside \(name), whose name sorts first: Tailscale's IPv4 alone (\(show(c)))",
          c == C(primary: "100.88.123.45", secondary: nil))
}
check("Tailscale with its name beside Mullvad: the name, Tailscale's IPv4 under it",
      window([wifi, mullvad, tailscale], names: ["ts": magic]) == C(primary: magic, secondary: "100.88.123.45"))
check("open-source tailscaled (an unnamed utun, no service, no name): its IPv4 alone",
      window([wifi], tunnels: [AddressList.Tunnel(interface: "utun4", ipv4: ["100.88.123.45"])]) == C(primary: "100.88.123.45", secondary: nil),
      show(window([wifi], tunnels: [AddressList.Tunnel(interface: "utun4", ipv4: ["100.88.123.45"])])))
check("open-source tailscaled beside NordVPN: its IPv4 alone",
      window([wifi, nord], tunnels: [AddressList.Tunnel(interface: "utun4", ipv4: ["100.88.123.45"])]) == C(primary: "100.88.123.45", secondary: nil))
check("a Tailscale exit node on this Mac (its tunnel the primary): the name, its IPv4 under it",
      window([wifi, tailscale], primary: "utun4", names: ["ts": magic]) == C(primary: magic, secondary: "100.88.123.45"))
var tailscaleV6 = tailscale; tailscaleV6.ipv4 = []
check("Tailscale IPv6 only, no name, beside WireGuard's IPv4: Tailscale's IPv6 alone",
      window([wifi, wgMesh, tailscaleV6]) == C(primary: "[fd7a:115c:a1e0::abcd:ef01]", secondary: nil), show(window([wifi, wgMesh, tailscaleV6])))

// MARK: Tailscale's ranges, by the parsed address
func vpnAt(_ host: String, via: String = "X") -> C { choose([MacAddress(host: host, kind: "vpn", via: via)], lan: home) }
for (host, shown) in [("100.64.0.0", "100.64.0.0"), ("100.127.255.255", "100.127.255.255"), ("100.101.102.103", "100.101.102.103"),
                      ("fd7a:115c:a1e0::", "[fd7a:115c:a1e0::]"), ("fd7a:115c:a1e0:ffff:ffff:ffff:ffff:ffff", "[fd7a:115c:a1e0:ffff:ffff:ffff:ffff:ffff]"),
                      ("FD7A:115C:A1E0:0:0:0:0:1", "[fd7a:115c:a1e0::1]"), ("::ffff:100.88.123.45", "100.88.123.45")] {
    check("\(host) is Tailscale's: alone (\(show(vpnAt(host))))", vpnAt(host) == C(primary: shown, secondary: nil))
}
for (host, shown) in [("100.63.255.255", "100.63.255.255"), ("100.128.0.0", "100.128.0.0"), ("10.100.64.1", "10.100.64.1"),
                      ("fd7a:115c:a1e1::1", "[fd7a:115c:a1e1::1]"), ("fd7a:115c:a1df:ffff::1", "[fd7a:115c:a1df:ffff::1]"),
                      ("fd7a::1", "[fd7a::1]"), ("fd7b:115c:a1e0::1", "[fd7b:115c:a1e0::1]")] {
    check("\(host) is not Tailscale's: under this network's address (\(show(vpnAt(host))))", vpnAt(host) == C(primary: home, secondary: shown))
}
check("by range, not by the service's name: 10.1.2.3 via \"Tailscale\" goes under this network's address",
      vpnAt("10.1.2.3", via: "Tailscale") == C(primary: home, secondary: "10.1.2.3"))
check("…and 100.100.1.1 via \"NordVPN\" is taken for Tailscale's", vpnAt("100.100.1.1", via: "NordVPN") == C(primary: "100.100.1.1", secondary: nil))
check("100.64/10 of kind lan (carrier NAT) is no VPN: this network's address alone",
      choose([MacAddress(host: "100.72.14.3", kind: "lan", via: "Wi-Fi")], lan: home) == C(primary: home, secondary: nil))
check("100.64/10 of kind internet is no VPN: this network's address alone",
      choose([MacAddress(host: "100.72.14.3", kind: "internet", via: "Router")], lan: home) == C(primary: home, secondary: nil))
check("a Tailscale IPv4 wherever it is listed",
      choose([MacAddress(host: "10.99.0.2", kind: "vpn", via: "A"), MacAddress(host: "fd99::2", kind: "vpn", via: "A"),
              MacAddress(host: "100.101.102.103", kind: "vpn", via: "B")], lan: home) == C(primary: "100.101.102.103", secondary: nil))
check("a Tailscale IPv4 before a Tailscale IPv6, whatever the order",
      choose([MacAddress(host: "fd7a:115c:a1e0::1", kind: "vpn", via: "T"), MacAddress(host: "100.101.102.103", kind: "vpn", via: "T")], lan: home)
        == C(primary: "100.101.102.103", secondary: nil))
check("a Tailscale IPv6 before another VPN's IPv4",
      choose([MacAddress(host: "10.99.0.2", kind: "vpn", via: "W"), MacAddress(host: "fd7a:115c:a1e0::1", kind: "vpn", via: "T")], lan: home)
        == C(primary: "[fd7a:115c:a1e0::1]", secondary: nil))
check("isTailscale reads addresses only: a name, even Tailscale's, is in no range",
      !PairingWindowAddress.isTailscale(ParsedAddress(host: magic, port: nil, kind: .name))
      && !PairingWindowAddress.isTailscale(ParsedAddress(host: "100.64.0.1.example", port: nil, kind: .name)))
check("a Tailscale IP keeps the door's port", choose([MacAddress(host: "100.101.102.103", kind: "vpn", via: "T")], lan: home, port: 7456)
        == C(primary: "100.101.102.103:7456", secondary: nil))

// MARK: By kind, never by text
check("an IPv4 is preferred to an IPv6 whatever the order",
      choose([MacAddress(host: "fd7a::1", kind: "vpn", via: "X"), MacAddress(host: "10.99.0.2", kind: "vpn", via: "Y")], lan: nil)
        == C(primary: "10.99.0.2", secondary: nil))
check("a name of kind lan is not a VPN name",
      choose([MacAddress(host: "mac.example.net", kind: "lan", via: "Wi-Fi"), MacAddress(host: "100.88.123.45", kind: "vpn", via: "Tailscale")], lan: "10.128.0.34")
        == C(primary: "100.88.123.45", secondary: nil))
check("an internet address name is not a VPN name",
      choose([MacAddress(host: "100.88.123.45", kind: "vpn", via: "Tailscale"), MacAddress(host: "home.example.net", port: 17455, kind: "internet", via: "Address name")], lan: "10.128.0.34")
        == C(primary: "100.88.123.45", secondary: nil))
check("an unknown kind is not a VPN",
      choose([MacAddress(host: "x.tail9.ts.net", kind: "future", via: "Tailscale"), MacAddress(host: "100.88.123.45", kind: "vpn", via: "Tailscale")], lan: nil)
        == C(primary: "100.88.123.45", secondary: nil))
check("a VPN IP that looks like a name is not one: a ts.net-looking host of kind lan is skipped, 100.x of kind vpn taken",
      choose([MacAddress(host: "lab-macbook-pro.tail5678.ts.net", kind: "lan", via: "Wi-Fi"), MacAddress(host: "100.88.123.45", kind: "vpn", via: "Tailscale")], lan: nil)
        == C(primary: "100.88.123.45", secondary: nil))
check("a VPN host the parser refuses is never shown",
      choose([MacAddress(host: "bad host", kind: "vpn", via: "X"), MacAddress(host: "1.2.3", kind: "vpn", via: "X"), MacAddress(host: "100.88.123.45", kind: "vpn", via: "X")], lan: nil)
        == C(primary: "100.88.123.45", secondary: nil))
check("under this network's address, another VPN's IPv4 before its IPv6, whatever the order",
      choose([MacAddress(host: "fd99::2", kind: "vpn", via: "W"), MacAddress(host: "10.99.0.2", kind: "vpn", via: "W")], lan: home)
        == C(primary: home, secondary: "10.99.0.2"))
check("no line under this network's address that says it again",
      choose([MacAddress(host: home, kind: "vpn", via: "X")], lan: home) == C(primary: home, secondary: nil))
check("another VPN before an internet address name listed first, with no LAN address",
      choose([MacAddress(host: "home.example.net", port: 17455, kind: "internet", via: "Address name"), MacAddress(host: "10.5.0.2", kind: "vpn", via: "NordVPN")], lan: nil)
        == C(primary: "10.5.0.2", secondary: nil))
check("a VPN name's own port wins over the door's",
      choose([MacAddress(host: "m.example.net", port: 9000, kind: "vpn", via: "X"), MacAddress(host: "10.1.1.1", kind: "vpn", via: "X")], lan: nil, port: 7456)
        == C(primary: "m.example.net:9000", secondary: "10.1.1.1:7456"))

// MARK: Fallbacks after the LAN, as before
var internetOnly = AddressList.Input(services: [], primaryInterface: nil)
internetOnly.internet = true; internetOnly.addressName = ParsedAddress(host: "home.example.net", port: 17455, kind: .name); internetOnly.routerIPv4 = "203.0.113.9"
check("no VPN and no LAN, the internet switch on: the first address listed, with its own port",
      choose(AddressList.build(internetOnly), lan: nil) == C(primary: "home.example.net:17455", secondary: nil), show(choose(AddressList.build(internetOnly), lan: nil)))
var testHost = lanOnlyInput; testHost.testLoopback = true
check("a test host (127.0.0.1 listed first): this network's address still wins",
      choose(AddressList.build(testHost), lan: "10.128.0.34") == C(primary: "10.128.0.34", secondary: nil))
check("a test host with no LAN: 127.0.0.1",
      choose([MacAddress(host: "127.0.0.1", kind: "lan", via: "This Mac")], lan: nil) == C(primary: "127.0.0.1", secondary: nil))
check("a LAN value the parser refuses is shown as it is (as before)", choose([], lan: "not an address").primary == "not an address")

// MARK: Random runs: properties, and the window before wherever it had it right
/// cb0ec55's PairDeviceView.address, verbatim but for its inputs: what the window showed before
/// Noah's decision.
func before(_ addresses: [MacAddress], lan: String?, port: Int) -> String {
    let host = lan
        ?? addresses.first { $0.kind == MacAddress.vpn }?.host
        ?? addresses.first?.host
        ?? "this Mac’s address"
    guard case .success(var parsed) = AddressParser.parse(host) else { return host }
    if port != D { parsed.port = port }
    return parsed.text
}
func typed(_ host: String, own: Int?, port: Int) -> String {
    guard case .success(var p) = AddressParser.parse(host) else { return host }
    p.port = own ?? (port != D ? port : nil)
    return p.text
}
/// Tailscale's ranges, restated apart from the implementation: the octets by range, the IPv6 by the
/// parser's compressed lowercase text, whose first three groups are never compressed in this /48.
func tailnet(_ p: ParsedAddress) -> Bool {
    switch p.kind {
    case .ipv4: let o = p.host.split(separator: ".").map { Int($0)! }; return o[0] == 100 && (64...127).contains(o[1])
    case .ipv6: return p.host.hasPrefix("fd7a:115c:a1e0:")
    case .name: return false
    }
}
struct RNG { var s: UInt64; mutating func next(_ n: Int) -> Int { s = s &* 6364136223846793005 &+ 1442695040888963407; return Int((s >> 33) % UInt64(n)) } }
var rng = RNG(s: 20260925)
let hosts = ["lab-macbook-pro.tail5678.ts.net", "mac-mini.tail1234.ts.net", "100.88.123.45", "100.101.102.103", "10.99.0.2",
             "fd7a:115c:a1e0::abcd:ef01", "fd99::2", "10.128.0.34", "192.168.1.20", "127.0.0.1", "home.example.net", "203.0.113.9",
             "2001:db8::20", "bad host", "1.2.3", "Mixed.Case.Example", "10.5.0.2", "172.16.0.2", "100.63.255.255", "100.128.0.1",
             "fd7a:115c:a1e1::1", "FD7A:115C:A1E0::9", "::ffff:100.88.123.45", "10.8.0.6"]
let kinds = ["vpn", "vpn", "lan", "internet", "future"]
let vias = ["Tailscale", "Home WireGuard", "VPN (utun9)", "Wi-Fi", "Router", "Address name", "NordVPN"]
let ports = [7455, 7455, 7456, 17455, 65535]
var runs = 0, parity = 0, lanParity = 0, underLAN = 0, bad: [String] = []
for _ in 0..<5_000 {
    runs += 1
    let n = rng.next(7)
    var list: [MacAddress] = []
    for _ in 0..<n {
        let own = rng.next(6) == 0 ? 9000 + rng.next(3) : nil
        list.append(MacAddress(host: hosts[rng.next(hosts.count)], port: own, kind: kinds[rng.next(kinds.count)], via: vias[rng.next(vias.count)]))
    }
    let lanValue: String? = [nil, nil, "10.128.0.34", "192.168.1.20", "bad host"][rng.next(5)]
    let port = ports[rng.next(ports.count)]
    let c = choose(list, lan: lanValue, port: port)
    let parsed = list.filter { $0.kind == MacAddress.vpn }.compactMap { a -> (MacAddress, ParsedAddress)? in
        if case .success(let p) = AddressParser.parse(a.host) { return (a, p) }; return nil
    }
    func fail(_ why: String) { if bad.count < 5 { bad.append("\(why): \(list.map { "\($0.host)\($0.port.map { ":\($0)" } ?? "")/\($0.kind)/\($0.via)" }) lan \(lanValue ?? "nil") port \(port) → \(show(c))") } }
    if c.secondary != nil && c.secondary == c.primary { fail("P9 the line under says the address again") }
    if let name = parsed.first(where: { $0.1.kind == .name }) {
        if c.primary != typed(name.0.host, own: name.0.port, port: port) { fail("P1 the first VPN name") }
        let v4 = parsed.first { $0.0.via == name.0.via && $0.1.kind == .ipv4 }
        if c.secondary != v4.map({ typed($0.0.host, own: $0.0.port, port: port) }) { fail("P2 the named VPN's own IPv4") }
    } else if let ts = parsed.first(where: { $0.1.kind == .ipv4 && tailnet($0.1) }) ?? parsed.first(where: { $0.1.kind == .ipv6 && tailnet($0.1) }) {
        if c.primary != typed(ts.0.host, own: ts.0.port, port: port) { fail("P3 no name: the first Tailscale IPv4, else IPv6") }
        if c.secondary != nil { fail("P3 no name: a Tailscale IP alone") }
    } else {
        // Any VPN address left is another VPN's: it never hides this network's address.
        let other = (parsed.first(where: { $0.1.kind == .ipv4 }) ?? parsed.first(where: { $0.1.kind == .ipv6 }))
            .map { typed($0.0.host, own: $0.0.port, port: port) }
        if let lanValue {
            let shown = typed(lanValue, own: nil, port: port)
            if c.primary != shown { fail("P7 another VPN: this network's address first") }
            if c.secondary != (other == shown ? nil : other) { fail("P7 another VPN: its first IPv4, else IPv6, under this network's address") }
            if c.secondary != nil { underLAN += 1 }
            // The window before showed exactly this network's address here.
            lanParity += 1
            if c.primary != before(list, lan: lanValue, port: port) { fail("P8 no Tailscale, a LAN address: the primary as before (\(before(list, lan: lanValue, port: port)))") }
        } else if let other {
            if c.primary != other || c.secondary != nil { fail("P3 no LAN address: another VPN's first IPv4, else IPv6, alone") }
        } else {
            // No VPN to show and no LAN address: the first address listed with its own port, else the placeholder.
            let expected = list.first.map { typed($0.host, own: $0.port, port: port) } ?? "this Mac’s address"
            if c.primary != expected || c.secondary != nil { fail("P5 no VPN to show, no LAN: first address, placeholder (\(expected))") }
        }
        // With no VPN entry at all, exactly what the window showed before, but for an address's
        // own port, which it ignored.
        if !list.contains(where: { $0.kind == MacAddress.vpn }) && (lanValue != nil || list.first?.port == nil) {
            parity += 1
            if c.primary != before(list, lan: lanValue, port: port) || c.secondary != nil { fail("P4 no VPN: as before (\(before(list, lan: lanValue, port: port)))") }
        }
    }
    if !parsed.isEmpty || lanValue != nil {
        for a in list where a.kind == MacAddress.internet {
            let t = typed(a.host, own: a.port, port: port)
            let shown = c.primary == t || c.secondary == t
            // The same address listed again (a LAN value, or another kind, maybe in another form:
            // ::ffff:100.88.123.45 is 100.88.123.45) may be shown for that entry.
            let alsoOtherwise = lanValue.map { typed($0, own: nil, port: port) } == t
                || list.contains { $0.kind != MacAddress.internet && typed($0.host, own: $0.port, port: port) == t }
            if shown && !alsoOtherwise { fail("P6 an internet address shown although a VPN or the LAN was there") }
        }
    }
}
check("5,000 random runs: the properties hold (\(parity) without a VPN and \(lanParity) with a LAN address and no Tailscale, each equal to the window before; \(underLAN) with another VPN under this network's address)",
      bad.isEmpty, bad.joined(separator: "\n     "))

print(fails == 0 ? "ALL PASS (\(passes) checks)" : "\(fails) FAILED of \(passes + fails)")
exit(fails == 0 ? 0 : 1)
