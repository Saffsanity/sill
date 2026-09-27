// H3 (step 1): CableLink, pure, compiled with StreamProtocol's sources and OriginPolicy as one
// module. Fixtures from this Mac's own IOKit read with Noah's iPad mini on the cable (2026-09-25,
// the plan's table and H0's P2) and the plan's H3 list; the deviceID vectors are Python's
// (hashlib, base64), not this file's.
import Foundation
var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) { if ok { passes += 1; print("ok   \(name)") } else { fails += 1; print("FAIL \(name)") }; fflush(stdout) }
typealias C = CableLink
typealias A = CableLink.Ancestry
func ip(_ s: String) -> [UInt8] { IPBytes.parse(s)! }

let serial = "00008110001A2B3C4D5E6F70"                 // an iPad's USB Serial Number: 24 characters, like the UDID
let iPad = A(ncm: true, vendor: 0x05AC, productName: "iPad", serial: serial, session: 4854277126715)
let iPhone = A(ncm: true, vendor: 0x05AC, productName: "iPhone", serial: "00008101000C11E2D3F4A5B6", session: 77)
let realtek = A(ncm: false, vendor: 0x0BDA, productName: "USB 10/100/1000 LAN", serial: "000001", session: 5)
let realtekNCM = A(ncm: true, vendor: 0x0BDA, productName: "USB 10/100/1G/2.5G LAN", serial: "000002", session: 6)
let appleAdapter = A(ncm: false, vendor: 0x05AC, productName: "Apple USB Ethernet Adapter", serial: "A1277", session: 7)
let appleAdapterNCM = A(ncm: true, vendor: 0x05AC, productName: "Apple USB Ethernet Adapter", serial: "A1277", session: 7)
let otherMac = A(ncm: true, vendor: 0x05AC, productName: "Mac", serial: "C02X1234", session: 8)
let otherMacBook = A(ncm: true, vendor: 0x05AC, productName: "MacBook Pro", serial: "C02X5678", session: 9)
let noName = A(ncm: true, vendor: 0x05AC, productName: nil, serial: serial, session: 10)
let noNCM = A(ncm: false, vendor: 0x05AC, productName: "iPad", serial: serial, session: 11)      // the iPad's PTP-only configuration
let noSerial = A(ncm: true, vendor: 0x05AC, productName: "iPad", serial: nil, session: 12)
let emptySerial = A(ncm: true, vendor: 0x05AC, productName: "iPad", serial: "", session: 13)
let lookalike = A(ncm: true, vendor: 0x05AC, productName: "iPhone Lightning Adapter", serial: "X", session: 14)
let lowercase = A(ncm: true, vendor: 0x05AC, productName: "ipad", serial: serial, session: 15)
let noVendor = A(ncm: true, vendor: nil, productName: "iPad", serial: serial, session: 16)

// MARK: What counts as the cable to an iPhone or iPad

check("en14 and anri0 (the iPad over NCM) are the cable", C.isPhoneOrPadCable(iPad))
check("an iPhone (0x05AC, \"iPhone\") is the cable", C.isPhoneOrPadCable(iPhone))
check("no ancestry (anpi0 and en4 in device mode, en1 on Thunderbolt, en0 on PCIe Wi-Fi, bridge0) is not", !C.isPhoneOrPadCable(nil))
check("a Realtek USB Ethernet adapter (0x0BDA) is not, with or without NCM", !C.isPhoneOrPadCable(realtek) && !C.isPhoneOrPadCable(realtekNCM))
check("Apple's USB Ethernet Adapter (0x05AC) is not, with or without NCM", !C.isPhoneOrPadCable(appleAdapter) && !C.isPhoneOrPadCable(appleAdapterNCM))
check("another Mac in device mode is not", !C.isPhoneOrPadCable(otherMac) && !C.isPhoneOrPadCable(otherMacBook))
check("no product name is not", !C.isPhoneOrPadCable(noName))
check("no NCM interface is not", !C.isPhoneOrPadCable(noNCM))
check("no vendor is not", !C.isPhoneOrPadCable(noVendor))
check("the product name must be exactly iPhone or iPad", !C.isPhoneOrPadCable(lookalike) && !C.isPhoneOrPadCable(lowercase))
check("the constants: Apple's vendor 0x05AC, products iPhone and iPad", C.appleVendor == 0x05AC && C.products == ["iPhone", "iPad"])

// MARK: A connection's device

// This Mac's interfaces as the IOKit read would give them, and its own addresses (the owner table
// keeps link-local ones with the embedded scope cleared; one is stored with it, as getifaddrs
// gives it, so both sides are compared without it).
let cables: [String: A] = ["en14": iPad, "anri0": iPad, "en7": realtek, "en8": appleAdapter, "en9": otherMac, "en10": iPhone,
                           "en11": noSerial, "en12": emptySerial, "en13": noName, "": iPad]
var ownEn14 = ip("fe80::1c8e:5aff:fe00:e14"); ownEn14[2] = 0; ownEn14[3] = 0x0e           // embedded scope 14
let own: Set<[UInt8]> = [ip("10.128.0.34"), ip("fe80::47b:5945:e0aa:d0ac"), ip("169.254.222.62"), ip("169.254.178.234"),
                         ownEn14, ip("fe80::aa:bb:cc:dd"), ip("2601:600:1:2::34")]
func dev(_ source: String, _ scope: String?, standIn: String? = nil) -> A? {
    C.device(source: ip(source), scope: scope, ownAddresses: own, cables: cables, standIn: standIn)
}
check("the iPad's neighbour on anri0 (fe80::18fe:abff:febb:459f%anri0) is the iPad", dev("fe80::18fe:abff:febb:459f", "anri0") == iPad)
check("the iPad's neighbour on en14 (fe80::18c2:af60:ec0d:47ea%en14) is the iPad", dev("fe80::18c2:af60:ec0d:47ea", "en14") == iPad)
check("an iPhone's link-local source on its NCM interface is the iPhone", dev("fe80::1", "en10") == iPhone)
check("a routed source on a cable interface is not (a global, a ULA)", dev("2601:600:1:2::41", "en14") == nil && dev("fd00::41", "en14") == nil)
check("any IPv4 source is not, 169.254/16 included (the iPad's hotspot clients, a routed one)",
      dev("169.254.1.2", "en14") == nil && dev("172.20.10.2", "en14") == nil && dev("10.128.0.41", "en14") == nil)
check("an IPv4-mapped IPv6 source is not", C.device(source: [0,0,0,0,0,0,0,0,0,0,0xFF,0xFF,169,254,1,2], scope: "en14", ownAddresses: own, cables: cables) == nil)
check("a source that is this Mac's own on en14: fe80 (stored with its embedded scope) is not", dev("fe80::1c8e:5aff:fe00:e14", "en14") == nil)
check("a source that is this Mac's own on en14: 169.254 (the Simulator's, 2026-09-24) is not", dev("169.254.178.234", "en14") == nil
      && dev("169.254.222.62", "en14") == nil)
check("a source that is one of this Mac's own addresses on another interface is not", dev("fe80::47b:5945:e0aa:d0ac", "en14") == nil
      && dev("fe80::aa:bb:cc:dd", "anri0") == nil)
check("an own address given with its embedded scope matches one stored without", C.device(source: ownEn14, scope: "en14", ownAddresses: [ip("fe80::1c8e:5aff:fe00:e14")], cables: cables) == nil)
check("no scope, an empty scope, or an interface IOKit did not read is not", dev("fe80::5", nil) == nil && dev("fe80::5", "") == nil && dev("fe80::5", "en99") == nil)
check("device mode, Thunderbolt, Wi-Fi, a bridge (no ancestry) are not", ["anpi0", "en4", "en1", "en0", "bridge0", "bridge100"].allSatisfy { dev("fe80::5", $0) == nil })
check("an Ethernet adapter (Realtek, Apple's) and another Mac are not", dev("fe80::5", "en7") == nil && dev("fe80::5", "en8") == nil && dev("fe80::5", "en9") == nil)
check("no serial, an empty serial, or no product name are not", dev("fe80::5", "en11") == nil && dev("fe80::5", "en12") == nil && dev("fe80::5", "en13") == nil)
check("a malformed source is not", C.device(source: [], scope: "en14", ownAddresses: own, cables: cables) == nil
      && C.device(source: [0xFE, 0x80], scope: "en14", ownAddresses: own, cables: cables) == nil)

// MARK: The stand-in (SILL_TEST_CABLE_INTERFACE)

check("stand-in: this Mac's own fe80 on en0 counts as the cable to an iPad (rule 2 skipped)",
      dev("fe80::47b:5945:e0aa:d0ac", "en0", standIn: "en0") == C.testAncestry)
check("stand-in: the device is an \"iPad\" with serial TEST, plug-in 1",
      C.testAncestry == A(ncm: true, vendor: 0x05AC, productName: "iPad", serial: "TEST", session: 1) && C.isPhoneOrPadCable(C.testAncestry))
check("stand-in: still IPv6 link-local only (127.0.0.1, 169.254 on en0, a global on en0 are not)",
      dev("127.0.0.1", nil, standIn: "en0") == nil && dev("169.254.9.9", "en0", standIn: "en0") == nil && dev("2601:600:1:2::34", "en0", standIn: "en0") == nil)
check("stand-in: another interface keeps the real rule (the iPad on anri0 is the iPad; this Mac's own on en14 is not)",
      dev("fe80::18fe:abff:febb:459f", "anri0", standIn: "en0") == iPad && dev("169.254.178.234", "en14", standIn: "en0") == nil
      && dev("fe80::1c8e:5aff:fe00:e14", "en14", standIn: "en0") == nil)
check("without the stand-in this Mac's own fe80 on en0 is not", dev("fe80::47b:5945:e0aa:d0ac", "en0") == nil)
let env = ["SILL_TEST_CABLE_INTERFACE": "en0"]
check("SILL_TEST_CABLE_INTERFACE=en0 on a test host", C.testInterface(testHost: true, environment: env) == "en0")
check("SILL_TEST_CABLE_INTERFACE ignored by a host that is not a test host (the bundle)", C.testInterface(testHost: false, environment: env) == nil)
check("SILL_TEST_CABLE_INTERFACE: an interface name only",
      ["", "0en", "en0;x", "en 0", "en0\n", "é1", "abcdefghijklmnop", "-en0"].allSatisfy { C.testInterface(testHost: true, environment: ["SILL_TEST_CABLE_INTERFACE": $0]) == nil }
      && C.testInterface(testHost: true, environment: [:]) == nil && C.testInterface(testHost: true, environment: ["SILL_TEST_CABLE_INTERFACE": "abcdefghijklmno"]) == "abcdefghijklmno")

// MARK: deviceID

let id = C.deviceID(serial: serial)
check("deviceID: Python's vector (base64url of SHA-256(\"sill-cable-v1\" ‖ serial)[0..<16])", id == "9thvTr8MQMHWVzL83q51yQ")
check("deviceID: TEST's and another serial's vectors", C.deviceID(serial: "TEST") == "70kQI5Y9AuFqHO6z_HnZaw"
      && C.deviceID(serial: "00008101000C11E2D3F4A5B6") == "66oGHS3VzNEVYNxKyrBBrg")
check("deviceID: stable", C.deviceID(serial: serial) == id)
check("deviceID: 22 characters, base64url without padding", id.count == 22 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
check("deviceID: never the serial, nor any 6 characters of it", !id.contains(serial) && !(0...(serial.count - 6)).contains { i in
    id.contains(String(serial.dropFirst(i).prefix(6))) })
check("deviceID: two serials, two IDs", C.deviceID(serial: serial) != C.deviceID(serial: serial + "0"))

print(fails == 0 ? "ALL PASS (\(passes))" : "\(fails) FAIL, \(passes) pass")
if fails > 0 { exit(1) }
