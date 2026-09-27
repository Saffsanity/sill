// H3 (step 3): AddressList and PairingWindow, pure, compiled with StreamProtocol's sources and
// OriginPolicy (for IPBytes) as one module (build.sh strips `import StreamProtocol`).
import Foundation
import CryptoKit
var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) { if ok { passes += 1; print("ok   \(name)") } else { fails += 1; print("FAIL \(name)") } }
typealias S = AddressList.Service
typealias V6 = AddressList.IPv6Entry
func hosts(_ list: [MacAddress]) -> [String] { list.map { "\($0.host)\($0.port.map { ":\($0)" } ?? "")/\($0.kind)/\($0.via)" } }

// Noah's store, as the probe and scutil showed it, Tailscale's name and addresses made up: utun0–3
// link-local and nameless, Tailscale on utun4, the CoreDevice tunnel's ULA on utun5 (nameless), en0
// private plus a deprecated ULA.
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
var input = AddressList.Input(services: noah, primaryInterface: "en0", tunnels: [], magicDNS: [:])
check("Noah's store: exactly Tailscale v4, Tailscale v6, Wi-Fi v4 (\(hosts(AddressList.build(input))))",
      hosts(AddressList.build(input)) == ["100.88.123.45/vpn/Tailscale", "fd7a:115c:a1e0::abcd:ef01/vpn/Tailscale", "10.128.0.34/lan/Wi-Fi"])
check("MagicDNS candidate from LocalHostName and the ts.net match domain",
      AddressList.magicDNSCandidate(localHostName: "Lab-MacBook-Pro", service: noah[4]) == "lab-macbook-pro.tail5678.ts.net")
check("no MagicDNS candidate without a ts.net domain, or on a LAN service",
      AddressList.magicDNSCandidate(localHostName: "Mac", service: noah[6]) == nil
      && AddressList.magicDNSCandidate(localHostName: "Mac", service: S(id: "x", name: "VPN", interface: "utun9", ipv4: [], ipv6: [], matchDomains: ["corp.example."])) == nil)
input.magicDNS = ["ts": "lab-macbook-pro.tail5678.ts.net"]
check("with the resolver's answer: the MagicDNS name first",
      hosts(AddressList.build(input)) == ["lab-macbook-pro.tail5678.ts.net/vpn/Tailscale", "100.88.123.45/vpn/Tailscale",
                                          "fd7a:115c:a1e0::abcd:ef01/vpn/Tailscale", "10.128.0.34/lan/Wi-Fi"])
var t = input; t.testLoopback = true
check("a test host lists 127.0.0.1 first (This Mac)", hosts(AddressList.build(t)).first == "127.0.0.1/lan/This Mac")
// A WireGuard service, a non-NE point-to-point tunnel, Ethernet beside Wi-Fi.
var more = noah
more.append(S(id: "wg", name: "Home WireGuard", interface: "utun7", ipv4: ["10.99.0.2"], ipv6: [V6(address: "fd99::2", flags: 0)]))
more.append(S(id: "eth", name: "Ethernet", interface: "en7", ipv4: ["192.168.1.30"], ipv6: []))
var input2 = AddressList.Input(services: more, primaryInterface: "en0", tunnels: [AddressList.Tunnel(interface: "utun9", ipv4: ["10.8.0.6"]),
                                                                                AddressList.Tunnel(interface: "utun4", ipv4: ["100.88.123.45"])])
let l2 = hosts(AddressList.build(input2))
check("WireGuard (its own name) and a point-to-point tunnel (VPN (utun9)); a service's tunnel not twice (\(l2))",
      l2 == ["10.99.0.2/vpn/Home WireGuard", "100.88.123.45/vpn/Tailscale", "10.8.0.6/vpn/VPN (utun9)",
             "fd99::2/vpn/Home WireGuard", "fd7a:115c:a1e0::abcd:ef01/vpn/Tailscale", "10.128.0.34/lan/Wi-Fi"])
input2.primaryInterface = "en7"
check("Wi-Fi and Ethernet: only the primary one's IPv4 (Ethernet primary)", hosts(AddressList.build(input2)).last == "192.168.1.30/lan/Ethernet")
input2.primaryInterface = "utun4"
check("a VPN exit node as primary: the LAN is still listed", hosts(AddressList.build(input2)).contains { $0.hasSuffix("/lan/Wi-Fi") || $0.hasSuffix("/lan/Ethernet") })
check("the router is asked on the primary non-tunnel interface", AddressList.routerInterface(input2) == "en0" || AddressList.routerInterface(input2) == "en7")
// IPv6 rules
let v6svc = [S(id: "wifi", name: "Wi-Fi", interface: "en0", ipv4: ["192.168.1.20"],
               ipv6: [V6(address: "2001:db8::aa", flags: 0x80 | 0x400), V6(address: "2001:db8::bb", flags: 0x10), V6(address: "2001:db8::20", flags: 0x400),
                      V6(address: "fd4e::20", flags: 0x400)])]
var input3 = AddressList.Input(services: v6svc, primaryInterface: "en0")
check("global IPv6 not listed while the internet switch is off", !hosts(AddressList.build(input3)).contains { $0.contains("2001:db8") })
input3.internet = true
let l3 = hosts(AddressList.build(input3))
check("with the switch: one stable global IPv6 (not temporary, not deprecated, not the LAN ULA) (\(l3))",
      l3 == ["192.168.1.20/lan/Wi-Fi", "2001:db8::20/internet/IPv6"])
input3.addressName = ParsedAddress(host: "home.example.net", port: 17455, kind: .name)
input3.routerIPv4 = "203.0.113.9"
let l4 = hosts(AddressList.build(input3))
check("with the switch: address name (its port), router IPv4, IPv6, in that order (\(l4))",
      l4 == ["192.168.1.20/lan/Wi-Fi", "home.example.net:17455/internet/Address name", "203.0.113.9/internet/Router", "2001:db8::20/internet/IPv6"])
input3.internet = false
check("the switch off hides the address name and router too", hosts(AddressList.build(input3)) == ["192.168.1.20/lan/Wi-Fi"])
// 100.64/10 only on a tunnel; awdl/llw never; loopback and link-local never
let cg = [S(id: "wifi", name: "Wi-Fi", interface: "en0", ipv4: ["100.72.1.5"], ipv6: []),
          S(id: "awdl", name: "AWDL", interface: "awdl0", ipv4: ["10.0.0.1"], ipv6: [V6(address: "fe80::1", flags: 0)]),
          S(id: "ll", name: "USB", interface: "en14", ipv4: ["169.254.172.122"], ipv6: [])]
check("100.64/10 on en0 is hidden (carrier NAT), awdl and link-local hidden", AddressList.build(AddressList.Input(services: cg, primaryInterface: "en0")).isEmpty)
check("lanAddress is the primary LAN IPv4", AddressList.lanAddress(input) == "10.128.0.34")
// vpnDown
check("vpnDown: a set-up VPN with no address", AddressList.vpnDown(setupVPNs: ["Tailscale", "Office"], services: noah) == ["Office"])
check("vpnDown: Tailscale down when it has no address", AddressList.vpnDown(setupVPNs: ["Tailscale"], services: Array(noah.filter { $0.id != "ts" })) == ["Tailscale"])
// the cap
var many: [S] = [S(id: "wifi", name: "Wi-Fi", interface: "en0", ipv4: ["192.168.1.20"], ipv6: [])]
for i in 0..<20 { many.append(S(id: "v\(i)", name: "VPN \(i)", interface: "utun\(10 + i)", ipv4: ["10.50.\(i).1"], ipv6: [])) }
check("at most 12", AddressList.build(AddressList.Input(services: many, primaryInterface: "en0")).count == 12)

// MARK: PairingWindow
let fpMac = Data(SHA256.hash(data: Data("mac".utf8))), fpDev = Data(SHA256.hash(data: Data("device".utf8)))
let secret = Data(repeating: 0x22, count: 16)
let qrD = PairingProof.deviceProof(key: PairingProof.qrKey(secret: secret), deviceFingerprint: fpDev, macFingerprint: fpMac)
let wrong = Data(repeating: 7, count: 32)
var w = PairingWindow()
check("closed before opening", w.tryProof(method: "qr", proof: qrD, fpDevice: fpDev, fpMac: fpMac, source: "a", now: 0) == .closed(.none))
w.open(secret: secret, code: "482913557208", now: 100, requestedBy: nil)
if case .accept(let m) = w.tryProof(method: "qr", proof: qrD, fpDevice: fpDev, fpMac: fpMac, source: "a", now: 101) {
    check("QR: accepted, proof_M is the vector", Base64URL.encode(m) == "XAX-uZPsq_Ax8fvI_sV7Ex0a-ROi19rI-FW-ykPh9TE")
} else { check("QR: accepted", false) }
check("single use: closed(used) afterwards", w.tryProof(method: "qr", proof: qrD, fpDevice: fpDev, fpMac: fpMac, source: "b", now: 102) == .closed(.used))
w.open(secret: secret, code: "482913557208", now: 200, requestedBy: "iPad")
check("a proof bound to another Mac key is wrong", w.tryProof(method: "qr", proof: qrD, fpDevice: fpDev, fpMac: wrong, source: "a", now: 200) == .reject(triesLeft: 4))
check("spacing: 0.5 s after a wrong one → busy", { if case .busy(let r) = w.tryProof(method: "qr", proof: qrD, fpDevice: fpDev, fpMac: fpMac, source: "b", now: 200.5) { return abs(r - 0.5) < 1e-9 }; return false }())
check("per source: the same source 3 s later → busy (5 s rule)", { if case .busy = w.tryProof(method: "qr", proof: wrong, fpDevice: fpDev, fpMac: fpMac, source: "a", now: 203) { return true }; return false }())
check("another source after 1 s: judged (wrong: 3 left)", w.tryProof(method: "qr", proof: wrong, fpDevice: fpDev, fpMac: fpMac, source: "b", now: 201.1) == .reject(triesLeft: 3))
check("after the 2nd wrong: 2 s spacing", { if case .busy = w.tryProof(method: "qr", proof: wrong, fpDevice: fpDev, fpMac: fpMac, source: "c", now: 202.9) { return true }; return false }())
check("3rd wrong at +2 s: 2 left", w.tryProof(method: "qr", proof: wrong, fpDevice: fpDev, fpMac: fpMac, source: "c", now: 203.2) == .reject(triesLeft: 2))
check("after the 3rd: 4 s spacing", { if case .busy = w.tryProof(method: "qr", proof: wrong, fpDevice: fpDev, fpMac: fpMac, source: "d", now: 207.0) { return true }; return false }())
check("4th wrong at +4 s: 1 left", w.tryProof(method: "qr", proof: wrong, fpDevice: fpDev, fpMac: fpMac, source: "d", now: 207.3) == .reject(triesLeft: 1))
check("after the 4th: 8 s spacing", { if case .busy = w.tryProof(method: "qr", proof: wrong, fpDevice: fpDev, fpMac: fpMac, source: "e", now: 215.0) { return true }; return false }())
check("the 5th wrong: stopped", w.tryProof(method: "qr", proof: wrong, fpDevice: fpDev, fpMac: fpMac, source: "e", now: 215.4) == .closed(.stopped))
check("the right proof after stopped: closed(stopped), never accepted", w.tryProof(method: "qr", proof: qrD, fpDevice: fpDev, fpMac: fpMac, source: "f", now: 230) == .closed(.stopped))
w.open(secret: secret, code: "482913557208", now: 300, lifetime: 5, requestedBy: nil)
check("expiry: a correct proof after the lifetime → expired", w.tryProof(method: "qr", proof: qrD, fpDevice: fpDev, fpMac: fpMac, source: "a", now: 305.01) == .closed(.expired))
w.open(secret: secret, code: "482913557208", now: 400, requestedBy: nil)
check("expireIfDue: not before", !w.expireIfDue(now: 699.9) && w.isOpen)
check("expireIfDue: at 300 s", w.expireIfDue(now: 700) && !w.isOpen)
// typed code: busy before K, then accepted
w.open(secret: secret, code: "482913557208", now: 800, requestedBy: nil)
let K = PairingProof.codeKey(code: "482913557208", macFingerprint: fpMac)!
let codeD = PairingProof.deviceProof(key: K, deviceFingerprint: fpDev, macFingerprint: fpMac)
check("a code proof before K is ready → busy(1)", w.tryProof(method: "code", proof: codeD, fpDevice: fpDev, fpMac: fpMac, source: "a", now: 800.05) == .busy(retryAfter: 1))
w.setCodeKey(K, code: "000000000000")
check("K for another code is ignored", w.tryProof(method: "code", proof: codeD, fpDevice: fpDev, fpMac: fpMac, source: "a", now: 800.1) == .busy(retryAfter: 1))
w.setCodeKey(K, code: "482913557208")
if case .accept(let m) = w.tryProof(method: "code", proof: codeD, fpDevice: fpDev, fpMac: fpMac, source: "a", now: 800.2) {
    check("typed code: accepted once K is ready, proof_M is the vector", Base64URL.encode(m) == "6BmGWC9XT8J8OY8phhq9bASgoSnoWpRxBeqZtvRrWmk")
} else { check("typed code accepted", false) }
w.open(secret: secret, code: "482913557208", now: 900, requestedBy: nil)
check("an unknown method is a wrong proof", w.tryProof(method: "icloud", proof: qrD, fpDevice: fpDev, fpMac: fpMac, source: "a", now: 900) == .reject(triesLeft: 4))
w.close(.cancelled)
check("cancel closes it", w.closeReason == .cancelled)
check("a QR proof sent as a code proof is wrong (other key)", { var x = PairingWindow(); x.open(secret: secret, code: "482913557208", now: 0, requestedBy: nil); x.setCodeKey(K, code: "482913557208")
    return x.tryProof(method: "code", proof: qrD, fpDevice: fpDev, fpMac: fpMac, source: "a", now: 0) == .reject(triesLeft: 4) }())
print(fails == 0 ? "ALL PASS (\(passes) checks)" : "\(fails) FAILED of \(passes + fails)")
exit(Int32(min(fails, 100)))
