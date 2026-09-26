// Sources/SillHost/ClientLink.swift on its own (no awdl0 or USB cable headless): PR #6's checks of
// runsPeerToPeer, unchanged, then the route each device's row on the menu card ends in.
//   swiftc -O -package-name sill Sources/SillHost/ClientLink.swift Tests/checks/clientlink/main.swift -o .build/checks/clientlink/check && .build/checks/clientlink/check
import Foundation
typealias L = ClientLink
typealias I = ClientLink.Interface
var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) { if ok { passes += 1; print("ok  ", name) } else { fails += 1; print("FAIL", name) } }

// The endpoints Sill.log printed on 2026-09-24, verbatim, and the local probe's.
let awdl = "fe80::8425:bdff:fe62:8930%awdl0.63101"      // 15:37:25, the iPad over AWDL
let wifi = "fe80::47b:5945:e0aa:d0ac%en0.55690"         // 15:34:05, the iPad over Wi-Fi
let usb  = "fe80::18fe:abff:febb:459f%anri0.61390"      // 15:33:01, the iPad over the USB cable
let v4   = "127.0.0.1:64431"                            // probe: a loopback client
let v6lo = "::1.64433"                                  // probe: IPv6 loopback

// MARK: PR #6 (runsPeerToPeer and its parts), unchanged

check("scope: %awdl0 → awdl0", L.scope(ofEndpoint: awdl) == "awdl0")
check("scope: %en0 → en0", L.scope(ofEndpoint: wifi) == "en0")
check("scope: %anri0 → anri0", L.scope(ofEndpoint: usb) == "anri0")
check("scope: %llw0 → llw0", L.scope(ofEndpoint: "fe80::1%llw0.52397") == "llw0")
check("scope: bracketed [fe80::1%awdl0]:52397 → awdl0", L.scope(ofEndpoint: "[fe80::1%awdl0]:52397") == "awdl0")
check("scope: a bare scoped address without a port → awdl0", L.scope(ofEndpoint: "fe80::1%awdl0") == "awdl0")
check("scope: bridge100 keeps its digits", L.scope(ofEndpoint: "fe80::1%bridge100.9") == "bridge100")
check("scope: IPv4 has none", L.scope(ofEndpoint: v4) == nil)
check("scope: IPv6 loopback has none", L.scope(ofEndpoint: v6lo) == nil)
check("scope: a global IPv6 address has none", L.scope(ofEndpoint: "fd4e:4f6b:37dc:4a0f:1083:aa29:4357:c7a9.5000") == nil)
check("scope: a numeric scope names no interface", L.scope(ofEndpoint: "fe80::1%16.52397") == nil)
check("scope: an empty scope is none", L.scope(ofEndpoint: "fe80::1%.52397") == nil && L.scope(ofEndpoint: "fe80::1%") == nil)
for name in ["awdl0", "awdl1", "llw0"] { check("isPeerToPeer: \(name) yes", L.isPeerToPeer(interface: name)) }
for name in ["en0", "en14", "anri0", "anpi0", "utun3", "lo0", "bridge100", "ap1", "nan0", ""] {
    check("isPeerToPeer: \(name.isEmpty ? "(empty)" : name) no", !L.isPeerToPeer(interface: name))
}
check("runs: the iPad over AWDL (15:37:25) is direct", L.runsPeerToPeer(endpoint: awdl, pathInterfaces: []))
check("runs: the iPad over Wi-Fi (15:34:05) is not", !L.runsPeerToPeer(endpoint: wifi, pathInterfaces: []))
check("runs: the iPad over the USB cable (15:33:01) is not", !L.runsPeerToPeer(endpoint: usb, pathInterfaces: []))
check("runs: llw0 is direct", L.runsPeerToPeer(endpoint: "fe80::1%llw0.1", pathInterfaces: []))
check("runs: loopback clients are not", !L.runsPeerToPeer(endpoint: v4, pathInterfaces: ["lo0"]) && !L.runsPeerToPeer(endpoint: v6lo, pathInterfaces: ["lo0"]))
check("runs: a scope of en0 is not direct whatever the path lists", !L.runsPeerToPeer(endpoint: wifi, pathInterfaces: ["awdl0"]))
check("runs: a scope of awdl0 is direct whatever the path lists", L.runsPeerToPeer(endpoint: awdl, pathInterfaces: ["en0", "lo0"]))
check("runs: no scope, a path of awdl0 alone is direct", L.runsPeerToPeer(endpoint: "10.0.0.2:5000", pathInterfaces: ["awdl0"]))
check("runs: no scope, a mixed path is not (the probe saw en0 + lo0 for one connection)", !L.runsPeerToPeer(endpoint: "10.0.0.2:5000", pathInterfaces: ["awdl0", "lo0"]))
check("runs: no scope, no path is not", !L.runsPeerToPeer(endpoint: "10.0.0.2:5000", pathInterfaces: []))
check("runs: no scope, an en0 path is not", !L.runsPeerToPeer(endpoint: "10.0.0.2:5000", pathInterfaces: ["en0"]))
check("runs: a numeric scope falls back to the path", L.runsPeerToPeer(endpoint: "fe80::1%16.1", pathInterfaces: ["awdl0"])
      && !L.runsPeerToPeer(endpoint: "fe80::1%16.1", pathInterfaces: ["en0"]))
let standIn: (String) -> Bool = { L.isPeerToPeer(interface: $0) || $0 == "en0" }
check("stand-in: en0 counts on a test host", L.runsPeerToPeer(endpoint: wifi, pathInterfaces: [], peerToPeer: standIn))
check("stand-in: awdl0 still counts", L.runsPeerToPeer(endpoint: awdl, pathInterfaces: [], peerToPeer: standIn))
check("stand-in: anri0 and loopback still do not", !L.runsPeerToPeer(endpoint: usb, pathInterfaces: [], peerToPeer: standIn)
      && !L.runsPeerToPeer(endpoint: v4, pathInterfaces: ["lo0"], peerToPeer: standIn))

// MARK: One interface's route

let en0wifi = I(name: "en0", type: .wifi), lo0 = I(name: "lo0", type: .loopback)
let awdl0 = I(name: "awdl0", type: .wifi), llw0 = I(name: "llw0", type: .wifi)
let anri0 = I(name: "anri0", type: .other), en7wired = I(name: "en7", type: .wiredEthernet)
check("one: awdl0 (.wifi) is Direct", L.route(name: "awdl0", type: .wifi) == .direct)
check("one: llw0 (.wifi) is Direct", L.route(name: "llw0", type: .wifi) == .direct)
check("one: awdl0 of unknown type is Direct, by name", L.route(name: "awdl0", type: nil) == .direct)
check("one: peer-to-peer by name comes first, whatever the type says", L.route(name: "awdl0", type: .wiredEthernet) == .direct)
check("one: anri0 of unknown type is Wired (the USB cable)", L.route(name: "anri0", type: nil) == .wired)
check("one: anri0 typed .other is Wired", L.route(name: "anri0", type: .other) == .wired)
check("one: anri0 typed .wiredEthernet is Wired", L.route(name: "anri0", type: .wiredEthernet) == .wired)
check("one: anri1 is Wired too", L.route(name: "anri1", type: nil) == .wired)
check("one: en0 typed .wifi is Wi-Fi", L.route(name: "en0", type: .wifi) == .wifi)
check("one: en1 typed .wifi (a desktop Mac's Wi-Fi) is Wi-Fi", L.route(name: "en1", type: .wifi) == .wifi)
check("one: en0 typed .wiredEthernet (a desktop Mac's port) is Wired", L.route(name: "en0", type: .wiredEthernet) == .wired)
check("one: en7 typed .wiredEthernet (USB Ethernet, the cable as enN) is Wired", L.route(name: "en7", type: .wiredEthernet) == .wired)
check("one: en0 of unknown type has no word (the name alone says nothing)", L.route(name: "en0", type: nil) == nil)
for (name, type) in [("lo0", I.Kind.loopback), ("utun3", .other), ("pdp_ip0", .cellular), ("anpi0", .other),
                     ("bridge0", .other), ("ap1", .other), ("nan0", .other), ("", .other)] {
    check("one: \(name.isEmpty ? "(empty)" : name) (\(type)) has no word", L.route(name: name, type: type) == nil)
}
check("one: the stand-in makes en0 Direct on a test host", L.route(name: "en0", type: .wifi, peerToPeer: standIn) == .direct)

// MARK: A device's route

check("route: the iPad over AWDL (15:37:25) is Direct", L.route(endpoint: awdl, interfaces: [awdl0]) == .direct)
check("route: …and by its scope's name alone", L.route(endpoint: awdl, interfaces: []) == .direct)
check("route: the iPad over Wi-Fi (15:34:05) is Wi-Fi", L.route(endpoint: wifi, interfaces: [en0wifi]) == .wifi)
check("route: the iPad over the USB cable (15:33:01) is Wired", L.route(endpoint: usb, interfaces: [anri0]) == .wired)
check("route: …and by its scope's name alone", L.route(endpoint: usb, interfaces: []) == .wired)
check("route: a scope of en0 whose type nothing reports has no word", L.route(endpoint: wifi, interfaces: []) == nil)
check("route: the scope decides over the path (en0 scope, AWDL and Wi-Fi listed)",
      L.route(endpoint: wifi, interfaces: [en0wifi, awdl0]) == .wifi)
check("route: the scope decides over the path (anri0 scope, a Wi-Fi path)", L.route(endpoint: usb, interfaces: [en0wifi, lo0]) == .wired)
check("route: the scope decides over the path (awdl0 scope, a mixed path)", L.route(endpoint: awdl, interfaces: [en0wifi, lo0]) == .direct)
check("route: the scope's type is its own entry's, not the first one's",
      L.route(endpoint: wifi, interfaces: [lo0, en0wifi]) == .wifi && L.route(endpoint: wifi, interfaces: [en7wired, en0wifi]) == .wifi)
check("route: a desktop Mac's en0 scope typed .wiredEthernet is Wired",
      L.route(endpoint: "fe80::1%en0.5000", interfaces: [I(name: "en0", type: .wiredEthernet)]) == .wired)
check("route: a loopback client has no word (IPv4 and IPv6)",
      L.route(endpoint: v4, interfaces: [lo0]) == nil && L.route(endpoint: v6lo, interfaces: [lo0]) == nil)
check("route: the probe's connection to this Mac's own address (en0 + lo0) has no word",
      L.route(endpoint: "10.128.0.34:54983", interfaces: [en0wifi, lo0]) == nil
      && L.route(endpoint: "fd4e:4f6b:37dc:4a0f:1083:aa29:4357:c7a9.54985", interfaces: [en0wifi, lo0]) == nil)
check("route: no scope, a Wi-Fi path is Wi-Fi (a device over IPv4)", L.route(endpoint: "192.168.1.23:52344", interfaces: [en0wifi]) == .wifi)
check("route: no scope, a wired path is Wired", L.route(endpoint: "192.168.1.23:52344", interfaces: [en7wired]) == .wired)
check("route: no scope, the same interface twice still agrees", L.route(endpoint: "192.168.1.23:52344", interfaces: [en0wifi, en0wifi]) == .wifi)
check("route: no scope, Wi-Fi and wired disagree: no word", L.route(endpoint: "192.168.1.23:52344", interfaces: [en0wifi, en7wired]) == nil)
check("route: no scope, no path: no word", L.route(endpoint: "10.0.0.2:5000", interfaces: []) == nil)
check("route: no scope, a VPN path: no word", L.route(endpoint: "10.8.0.2:5000", interfaces: [I(name: "utun3", type: .other)]) == nil)
check("route: no scope, awdl0 alone is Direct", L.route(endpoint: "10.0.0.2:5000", interfaces: [awdl0]) == .direct)
check("route: no scope, awdl0 and llw0 agree on Direct", L.route(endpoint: "10.0.0.2:5000", interfaces: [awdl0, llw0]) == .direct)
check("route: no scope, awdl0 beside lo0: no word", L.route(endpoint: "10.0.0.2:5000", interfaces: [awdl0, lo0]) == nil)
check("route: a numeric scope falls back to the path",
      L.route(endpoint: "fe80::1%16.1", interfaces: [awdl0]) == .direct && L.route(endpoint: "fe80::1%16.1", interfaces: [en0wifi]) == .wifi)
check("route: a global IPv6 address goes by the path", L.route(endpoint: "fd4e::1.5000", interfaces: [en0wifi]) == .wifi)
check("route: the stand-in makes an en0 client Direct on a test host", L.route(endpoint: wifi, interfaces: [en0wifi], peerToPeer: standIn) == .direct)
check("route: the stand-in leaves the cable Wired and loopback wordless",
      L.route(endpoint: usb, interfaces: [anri0], peerToPeer: standIn) == .wired
      && L.route(endpoint: v4, interfaces: [lo0], peerToPeer: standIn) == nil)

// MARK: Direct exactly when Direct Wireless off would disconnect it

// Every endpoint against every interface list, with and without the stand-in: the card says Direct
// for a device if and only if runsPeerToPeer (what turning the setting off acts on) says so.
let endpoints = [awdl, wifi, usb, v4, v6lo, "10.0.0.2:5000", "fe80::1%16.1", "fe80::1%llw0.1", "fd4e::1.5000"]
let lists: [[I]] = [[], [awdl0], [en0wifi], [awdl0, lo0], [en0wifi, lo0], [llw0], [anri0], [lo0], [awdl0, llw0], [en7wired], [en0wifi, awdl0]]
var agreeing = 0, total = 0
for rule in [L.isPeerToPeer(interface:), standIn] {
    for e in endpoints {
        for list in lists {
            total += 1
            // What StreamServer passes each: the scoped address's own interface first when it has
            // one (here: the list), and the path's names for runsPeerToPeer.
            if (L.route(endpoint: e, interfaces: list, peerToPeer: rule) == .direct) == L.runsPeerToPeer(endpoint: e, pathInterfaces: list.map(\.name), peerToPeer: rule) { agreeing += 1 }
        }
    }
}
check("Direct ⇔ runsPeerToPeer over \(total) combinations (\(agreeing) agree)", agreeing == total)

print(fails == 0 ? "ALL PASS (\(passes))" : "\(fails) FAIL, \(passes) pass")
if fails > 0 { exit(1) }
