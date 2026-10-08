// H3 (step 1): the new record fields. PairedDevice (the Mac's trust list, HostIdentity.swift):
// `cableDevice` and "cable"; SavedMac (the device's saved Macs, SavedMacs.swift): `homeTLS` and
// `revoked`. Records without them decode, lists without them encode byte for byte as before, and
// an older reader (a mirror of each type as it was at 1f3072a) reads the new records. Compiled with
// StreamProtocol's sources as one module, `-package-name sill`.
import Foundation
var fails = 0, passes = 0
func check(_ name: String, _ ok: Bool) { if ok { passes += 1; print("ok   \(name)") } else { fails += 1; print("FAIL \(name)") }; fflush(stdout) }

// The types as they were at 1f3072a (HostIdentity.swift, SavedMacs.swift), field for field.
struct OldPairedDevice: Codable, Equatable {
    var fingerprint: String; var name: String; var model: String?; var pairedAt: Double; var method: String
}
struct OldSavedMac: Codable, Equatable {
    var macID: String; var fingerprint: String; var name: String; var recognitionKey: String; var remotePort: Int
    var addresses: [MacAddress]; var typedAddresses: [MacAddress]?; var infoIssuedAt: Double; var bonjourName: String?
    var lastWorked: String?; var pairedAt: Date; var method: String; var lastConnectedAt: Date?; var lastRoute: String?
}
func sorted<T: Encodable>(_ v: T, pretty: Bool = false) -> String {
    let e = JSONEncoder(); e.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
    return String(data: try! e.encode(v), encoding: .utf8)!
}

// MARK: PairedDevice

let fpA = Base64URL.encode(Data(repeating: 0xA1, count: 32)), fpB = Base64URL.encode(Data(repeating: 0xB2, count: 32))
let oldList = [OldPairedDevice(fingerprint: fpA, name: "iPad", model: "iPad14,1", pairedAt: 1_790_000_000, method: "qr"),
               OldPairedDevice(fingerprint: fpB, name: "iPhone", model: nil, pairedAt: 1_790_000_100.5, method: "code")]
let oldJSON = sorted(oldList)
let decoded = try? JSONDecoder().decode([PairedDevice].self, from: Data(oldJSON.utf8))
check("trust list: a list from before cableDevice decodes", decoded?.count == 2 && decoded?.allSatisfy { $0.cableDevice == nil } == true
      && decoded?[0].method == "qr" && decoded?[1].model == nil)
check("trust list: re-encoded as the keychain store does (sorted keys), byte for byte the same", decoded.map { sorted($0) } == oldJSON)
check("trust list: re-encoded as the test directory does (pretty, sorted), byte for byte the same", decoded.map { sorted($0, pretty: true) } == sorted(oldList, pretty: true))
let cableID = CableLink.deviceID(serial: "00008110001A2B3C4D5E6F70")
let viaCable = PairedDevice(fingerprint: fpA, name: "iPad", model: "iPad14,1", pairedAt: 1_790_000_200, method: PairResult.cable, cableDevice: cableID)
let viaCableJSON = sorted([viaCable])
check("trust list: a key paired over the cable keeps method \"cable\" and its cableDevice (never the serial)",
      viaCableJSON.contains("\"cableDevice\":\"\(cableID)\"") && viaCableJSON.contains("\"method\":\"cable\"") && !viaCableJSON.contains("00008110001A2B3C4D5E6F70"))
check("trust list: round trip", (try? JSONDecoder().decode([PairedDevice].self, from: Data(viaCableJSON.utf8))) == [viaCable])
let olderReads = try? JSONDecoder().decode([OldPairedDevice].self, from: Data(viaCableJSON.utf8))
check("trust list: an older Sill.app reads the new list (the unknown key ignored, not \"damaged\")",
      olderReads == [OldPairedDevice(fingerprint: fpA, name: "iPad", model: "iPad14,1", pairedAt: 1_790_000_200, method: "cable")])
let plain = PairedDevice(fingerprint: fpB, name: "iPhone", model: nil, pairedAt: 1, method: PairRequest.code)
check("trust list: the old init still makes a record without cableDevice", plain.cableDevice == nil && !sorted(plain).contains("cableDevice"))
check("displayMethod: with the QR code, with a code, over the USB cable",
      PairedDevice(fingerprint: fpA, name: "", model: nil, pairedAt: 0, method: "qr").displayMethod == "with the QR code"
      && plain.displayMethod == "with a code" && viaCable.displayMethod == "over the USB cable")
check("displayMethod: a method this build does not know names none", PairedDevice(fingerprint: fpA, name: "", model: nil, pairedAt: 0, method: "icloud").displayMethod == nil)
check("the method strings: qr, code, cable", PairRequest.qr == "qr" && PairRequest.code == "code" && PairResult.cable == "cable")

// MARK: SavedMac

let fp = Data((0..<32).map { UInt8($0) })
let macID = MacID.make(fingerprint: fp)
let rk = Base64URL.encode(Data(repeating: 0x11, count: 32))
let old = OldSavedMac(macID: macID, fingerprint: Base64URL.encode(fp), name: "Mac mini", recognitionKey: rk, remotePort: 7455,
                      addresses: [MacAddress(host: "100.101.102.103", kind: MacAddress.vpn, via: "Tailscale")], typedAddresses: nil,
                      infoIssuedAt: 1_790_000_000, bonjourName: "Mac mini", lastWorked: "100.101.102.103|7455",
                      pairedAt: Date(timeIntervalSince1970: 1_790_000_000), method: "qr",
                      lastConnectedAt: Date(timeIntervalSince1970: 1_790_000_500), lastRoute: "Tailscale")
let enc = JSONEncoder(); enc.dateEncodingStrategy = .secondsSince1970; enc.outputFormatting = [.sortedKeys]
let oldText = String(data: try! enc.encode([old]), encoding: .utf8)!
let macs = SavedMacs.decode(oldText)
check("saved Macs: a record from before homeTLS and revoked decodes", macs.count == 1 && macs[0].homeTLS == nil && macs[0].revoked == nil && macs[0].name == "Mac mini")
check("saved Macs: re-encoded, byte for byte the same (nil fields left out)", SavedMacs.encode(macs) == oldText)
var seen = macs[0]
seen.homeTLS = true
seen.revoked = true
let newText = SavedMacs.encode([seen])
check("saved Macs: homeTLS and revoked round-trip", SavedMacs.decode(newText).first?.homeTLS == true && SavedMacs.decode(newText).first?.revoked == true
      && newText.contains("\"homeTLS\":true") && newText.contains("\"revoked\":true"))
let dec = JSONDecoder(); dec.dateDecodingStrategy = .secondsSince1970
check("saved Macs: an older build reads the new record", (try? dec.decode([OldSavedMac].self, from: Data(newText.utf8))) == [old])

// A new pairing replaces the record: homeTLS stays (no downgrade), revoked goes.
var fresh = macs[0]
fresh.pairedAt = Date(timeIntervalSince1970: 1_790_100_000)
fresh.method = "code"
let afterRemoved = SavedMacs.adding(fresh, to: [seen])
check("adding: a new pairing with a Mac seen over TLS keeps homeTLS", afterRemoved.count == 1 && afterRemoved[0].homeTLS == true)
check("adding: a new pairing clears revoked", afterRemoved[0].revoked == nil && afterRemoved[0].method == "code")
var freshTLS = fresh; freshTLS.homeTLS = true
check("adding: a new record's own homeTLS stays", SavedMacs.adding(freshTLS, to: [macs[0]])[0].homeTLS == true)
check("adding: nothing seen, nothing kept", SavedMacs.adding(fresh, to: [macs[0]])[0].homeTLS == nil)
var notTLS = seen; notTLS.homeTLS = false
check("adding: homeTLS false stays as the new record has it", SavedMacs.adding(fresh, to: [notTLS])[0].homeTLS == nil)
let otherFP = Data((0..<32).map { UInt8(255 - $0) })
var other = macs[0]
other.macID = MacID.make(fingerprint: otherFP); other.fingerprint = Base64URL.encode(otherFP); other.homeTLS = true
let two = SavedMacs.adding(fresh, to: [other])
check("adding: another Mac's homeTLS is not carried over", two.count == 2 && two.first { $0.macID == macID }?.homeTLS == nil
      && two.first { $0.macID == other.macID }?.homeTLS == true)


// MARK: Step 4: what the device learns of a saved Mac at home (§7.3, §7.6, §7.9)

let listTwo = [macs[0], other]          // macs[0]: homeTLS nil; other: homeTLS true
let marked = SavedMacs.seenOverTLS([macID], in: listTwo)
check("seenOverTLS: marks the Mac seen with p, and only it", marked?.count == 2 && marked?.first { $0.macID == macID }?.homeTLS == true
      && marked?.first { $0.macID == other.macID } == other)
let thirdFP = Data((0..<32).map { UInt8(($0 * 7) & 0xFF) })
var third = macs[0]
third.macID = MacID.make(fingerprint: thirdFP); third.fingerprint = Base64URL.encode(thirdFP)
check("seenOverTLS: a third Mac never seen with p stays unmarked", SavedMacs.seenOverTLS([macID], in: [macs[0], third])?.first { $0.macID == third.macID }?.homeTLS == nil)
check("seenOverTLS: nil when nothing changes (a Mac already marked; one not saved; none)",
      SavedMacs.seenOverTLS([other.macID], in: listTwo) == nil && SavedMacs.seenOverTLS(["NOTSAVED00000000"], in: listTwo) == nil
      && SavedMacs.seenOverTLS([], in: listTwo) == nil)
// A record's JSON without its homeTLS, to compare every other field without assigning the field.
func sansTLS(_ m: SavedMac) -> String { SavedMacs.encode([m]).replacingOccurrences(of: "\"homeTLS\":true,", with: "") }
check("seenOverTLS: keeps every other field and the order", marked.map { $0.map(\.macID) } == listTwo.map(\.macID)
      && sansTLS(marked![0]) == SavedMacs.encode([macs[0]]))
var falseTLS = macs[0]; falseTLS.homeTLS = false
check("seenOverTLS: a false homeTLS counts as not seen", SavedMacs.seenOverTLS([macID], in: [falseTLS])?.first?.homeTLS == true)
let revokedList = SavedMacs.revoking(macID, in: listTwo)
check("revoking: marks that Mac revoked, and only it", revokedList?.first { $0.macID == macID }?.revoked == true
      && revokedList?.first { $0.macID == other.macID }?.revoked == nil && revokedList?.count == 2)
check("revoking: nil for a Mac not saved or already revoked", SavedMacs.revoking("NOTSAVED00000000", in: listTwo) == nil
      && SavedMacs.revoking(macID, in: revokedList!) == nil)
check("revoking: a revoked record survives encoding, and the next pairing clears it",
      SavedMacs.decode(SavedMacs.encode(revokedList!)).first { $0.macID == macID }?.revoked == true
      && SavedMacs.adding(fresh, to: revokedList!).first { $0.macID == macID }?.revoked == nil)
let forgotten = SavedMacs.forgettingHomeTLS(SavedMacs.seenOverTLS([macID], in: listTwo)!)
check("forgettingHomeTLS (-SillForgetHomeTLS 1): every homeTLS cleared, nothing else", forgotten.allSatisfy { $0.homeTLS == nil }
      && forgotten.count == 2 && SavedMacs.encode([forgotten[1]]) == sansTLS(other) && forgotten[0] == macs[0])
check("forgettingHomeTLS: the record encodes as from before homeTLS", SavedMacs.encode([forgotten[0]]) == oldText)

// MARK: Require pairing's stored record (the security review, 2026-09-27)

// Off only with this Mac's own signature: a record another process of this user wrote first (the
// keychain item did not exist, and it listed Sill as allowed to read it) cannot turn pairing off.
if let keyM = RemoteKey.generate(), let mac = HostIdentity(privateKey: keyM, recognitionKey: Data(repeating: 7, count: 32)),
   let keyX = RemoteKey.generate(), let other = HostIdentity(privateKey: keyX, recognitionKey: Data(repeating: 8, count: 32)) {
    func read(_ record: Data?, as m: HostIdentity = mac) -> Bool {
        guard let record else { return true }
        return RequirePairingValue.decode(record, macID: m.macID, verify: { m.verifyRecord($0, signature: $1) })
    }
    let off = RequirePairingValue.encode(false, macID: mac.macID, sign: { mac.signRecord($0) })
    let onRecord = RequirePairingValue.encode(true, macID: mac.macID, sign: { mac.signRecord($0) })
    check("require pairing: on is \"1\" and reads on; nothing saved reads on", onRecord == Data("1".utf8) && read(onRecord) && read(nil))
    check("require pairing: off, signed by this Mac's key, reads off (and is \"0.\" and the signature)",
          off.map { String(decoding: $0, as: UTF8.self).hasPrefix("0.") } == true && !read(off))
    check("require pairing: a plain \"0\" (as written before the review, or by another app) reads on", read(Data("0".utf8)))
    let otherOff = RequirePairingValue.encode(false, macID: mac.macID, sign: { other.signRecord($0) })
    check("require pairing: off signed by another key reads on", otherOff != nil && read(otherOff))
    check("require pairing: this Mac's off record read as another Mac's reads on", read(off, as: other))
    check("require pairing: another Mac's own off record reads on here",
          read(RequirePairingValue.encode(false, macID: other.macID, sign: { other.signRecord($0) })))
    let garbled = ["", "0.", "0.!!!!", "0 ", "off", "0.AAAA", "1.xyz", "\u{0}"].map { Data($0.utf8) }
    check("require pairing: anything else reads on", garbled.allSatisfy { read($0) })
    check("require pairing: a key that cannot sign saves nothing", RequirePairingValue.encode(false, macID: mac.macID, sign: { _ in nil }) == nil
          && RequirePairingValue.encode(false, macID: mac.macID, sign: { _ in Data() }) == nil)
    check("require pairing: the signed message names the purpose and the Mac",
          String(decoding: RequirePairingValue.offMessage(macID: mac.macID), as: UTF8.self) == "sill-require-pairing-off-v1\n\(mac.macID)")
} else {
    check("require pairing: two P-256 keys and their identities", false)
}

print(fails == 0 ? "ALL PASS (\(passes))" : "\(fails) FAIL, \(passes) pass")
if fails > 0 { exit(1) }
