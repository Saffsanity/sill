// H3 (protocol parts) and part of H21: Sources/StreamProtocol compiled as one module with this file.
//
//   swiftc -O Sources/StreamProtocol/*.swift Tests/checks/protocol/main.swift -o .build/checks/protocol/check && .build/checks/protocol/check OUTDIR
//
// OUTDIR receives cert.der and signed-macinfo.json for the Python/openssl cross-checks
// (crosscheck.py). Every check prints ok/FAIL; the exit status is the number of failures.
import Foundation
import Network
import Security
import CryptoKit

setvbuf(stdout, nil, _IOLBF, 0)
var fails = 0
var passes = 0
func check(_ name: String, _ ok: Bool) {
    if ok { passes += 1; print("ok   \(name)") } else { fails += 1; print("FAIL \(name)") }
}
func hex(_ d: Data) -> String { d.map { String(format: "%02x", $0) }.joined() }
func unhex(_ s: String) -> Data { Data(stride(from: 0, to: s.count, by: 2).map { i -> UInt8 in
    let a = s.index(s.startIndex, offsetBy: i); return UInt8(s[a..<s.index(a, offsetBy: 2)], radix: 16)! }) }
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

// MARK: - Address parser (§7.9): at least 40 cases, every rule

typealias F = AddressParser.Failure
func addr(_ input: String, _ want: Result<(String, Int?, ParsedAddress.Kind), F>, _ note: String = "") {
    let got = AddressParser.parse(input)
    let ok: Bool
    switch (got, want) {
    case (.success(let a), .success(let w)): ok = a.host == w.0 && a.port == w.1 && a.kind == w.2
    case (.failure(let a), .failure(let w)): ok = a == w
    default: ok = false
    }
    let shown: String
    switch got { case .success(let a): shown = "\(a.kind) \(a.host) port \(a.port.map(String.init) ?? "nil")"; case .failure(let f): shown = "\(f)" }
    check("address \(input.debugDescription) → \(shown)\(note.isEmpty ? "" : " (\(note))")", ok)
}
// trimming and whitespace
addr(" 100.1.1.1 ", .success(("100.1.1.1", nil, .ipv4)), "ends trimmed")
addr("\t100.101.102.103\n", .success(("100.101.102.103", nil, .ipv4)), "ends trimmed")
addr("100.1 .1.1", .failure(.malformed), "space inside")
addr("mac mini.local", .failure(.malformed), "space inside a name")
addr("mac\tmini", .failure(.malformed), "tab inside")
addr("", .failure(.empty))
addr("   ", .failure(.empty))
// IPv6 in brackets, with and without a port
addr("[fd7a:115c:a1e0::1234]", .success(("fd7a:115c:a1e0::1234", nil, .ipv6)))
addr("[fd7a:115c:a1e0::1234]:7455", .success(("fd7a:115c:a1e0::1234", 7455, .ipv6)))
addr("[FD7A:115C:A1E0:0:0:0:0:1234]:17455", .success(("fd7a:115c:a1e0::1234", 17455, .ipv6)), "compressed, lowercase")
addr("[::1]:51234", .success(("::1", 51234, .ipv6)), "-SillConnect's [::1]:P")
addr("[1.2.3.4]", .failure(.ipv6), "brackets around IPv4")
addr("[::1", .failure(.ipv6), "unclosed bracket")
addr("[::1]x", .failure(.malformed))
addr("[::1]:", .failure(.port))
addr("[::1]:99999", .failure(.port))
// two or more colons without brackets: a bare IPv6 address, never address + port
addr("fd7a::1:7455", .success(("fd7a::1:7455", nil, .ipv6)), "the address fd7a::1:7455")
addr("::1", .success(("::1", nil, .ipv6)))
addr("2001:db8::20", .success(("2001:db8::20", nil, .ipv6)))
addr("2001:db8:::20", .failure(.ipv6), "not an IPv6 address")
addr("gg::1", .failure(.ipv6))
// zones refused
addr("fe80::1%en0", .failure(.zone))
addr("[fe80::1%en0]:7455", .failure(.zone))
addr("fe80::1%25en0", .failure(.zone))
// IPv4-mapped IPv6 is IPv4
addr("::ffff:1.2.3.4", .success(("1.2.3.4", nil, .ipv4)))
addr("[::ffff:100.101.102.103]:7455", .success(("100.101.102.103", 7455, .ipv4)))
addr("::ffff:0102:0304", .success(("1.2.3.4", nil, .ipv4)))
// IPv4: exactly four decimal octets 0–255, no leading zeros
addr("100.101.102.103", .success(("100.101.102.103", nil, .ipv4)))
addr("100.101.102.103:7455", .success(("100.101.102.103", 7455, .ipv4)))
addr("0.0.0.0", .success(("0.0.0.0", nil, .ipv4)))
addr("255.255.255.255", .success(("255.255.255.255", nil, .ipv4)))
addr("1.2.3", .failure(.ipv4), "NWEndpoint would dial 1.2.0.3")
addr("100.1", .failure(.ipv4), "NWEndpoint would dial 100.0.0.1")
addr("0x64.0x65.1.2", .failure(.ipv4), "NWEndpoint would dial 100.101.1.2")
addr("0x7f000001", .failure(.ipv4), "a hex number")
addr("4294967295", .failure(.ipv4), "a single number")
addr("256.1.1.1", .failure(.ipv4))
addr("01.2.3.4", .failure(.ipv4), "leading zero")
addr("017.0.0.1", .failure(.ipv4), "octal")
addr("1.2.3.4.5", .failure(.ipv4))
addr("1.2.3.4.", .failure(.ipv4), "trailing dot on a number")
addr("1.2.3.4:0", .failure(.port))
// names (RFC 1123)
addr("mac-mini.tail1234.ts.net", .success(("mac-mini.tail1234.ts.net", nil, .name)))
addr("home.example.net:17455", .success(("home.example.net", 17455, .name)))
addr("localhost", .success(("localhost", nil, .name)), "single label")
addr("mac-mini", .success(("mac-mini", nil, .name)), "MagicDNS short name")
addr("home.example.net.", .success(("home.example.net.", nil, .name)), "trailing dot")
addr("1e100.net", .success(("1e100.net", nil, .name)))
addr("123.example", .success(("123.example", nil, .name)), "a numeric label among others")
addr("-bad.example", .failure(.name))
addr("bad-.example", .failure(.name))
addr("a..b", .failure(.name))
addr("under_score.example", .failure(.name))
addr("exämple.com", .failure(.name), "non-ASCII")
addr(String(repeating: "a", count: 63) + ".net", .success((String(repeating: "a", count: 63) + ".net", nil, .name)), "63-character label")
addr(String(repeating: "a", count: 64) + ".net", .failure(.name), "64-character label")
let long253 = (0..<63).map { _ in "abc" }.joined(separator: ".") + ".d"   // 63*3 + 62 + 2 = 253
addr(long253, .success((long253, nil, .name)), "253 characters")
addr(long253 + "e", .failure(.name), "254 characters")
// ports
addr("host:1", .success(("host", 1, .name)))
addr("host:65535", .success(("host", 65535, .name)))
addr("host:0", .failure(.port))
addr("host:65536", .failure(.port))
addr("host:+80", .failure(.port))
addr("host:80a", .failure(.port))
addr("host:", .failure(.port))
addr(":7455", .failure(.malformed))
addr("http://1.2.3.4", .failure(.port))
// pairing links are handed to PairLink
addr("sill://pair?v=1", .failure(.pairingLink))
addr("SILL://PAIR?v=1", .failure(.pairingLink))
check("ParsedAddress.text: [v6]:port", ParsedAddress(host: "fd7a::1", port: 7455, kind: .ipv6).text == "[fd7a::1]:7455")
check("ParsedAddress.text: v4 without port", ParsedAddress(host: "100.1.2.3", port: nil, kind: .ipv4).text == "100.1.2.3")
check("ParsedAddress.text round-trips through the parser",
      ["[fd7a:115c:a1e0::1234]:7455", "100.101.102.103", "home.example.net:17455", "[::1]"].allSatisfy {
          if case .success(let a) = AddressParser.parse($0) { return a.text == $0 } else { return false } })

// MARK: - PairingCode (Damm)

let example = [4, 8, 2, 9, 1, 3, 5, 5, 7, 2, 0]
check("Damm: the plan's example 4829 1355 720 gets check digit 8", PairingCode.checkDigit(example) == 8)
var rng = SystemRandomNumberGenerator()
var undetectedSub = 0, undetectedTr = 0, codes = 0
for _ in 0..<20_000 {
    let d = (0..<11).map { _ in Int.random(in: 0...9, using: &rng) }
    let c = d + [PairingCode.checkDigit(d)]
    codes += 1
    if PairingCode.checkDigit(c) != 0 { undetectedSub += 1_000_000 }   // a valid code must validate
    for p in 0..<12 { for v in 0...9 where v != c[p] { var e = c; e[p] = v; if PairingCode.checkDigit(e) == 0 { undetectedSub += 1 } } }
    for p in 0..<11 where c[p] != c[p + 1] { var e = c; e.swapAt(p, p + 1); if PairingCode.checkDigit(e) == 0 { undetectedTr += 1 } }
}
check("Damm over \(codes) random codes: every single-digit substitution caught (\(undetectedSub) missed)", undetectedSub == 0)
check("Damm over \(codes) random codes: every adjacent transposition caught (\(undetectedTr) missed)", undetectedTr == 0)
var counts = [Int](repeating: 0, count: 10)
var allValid = true
for _ in 0..<5000 {
    guard let c = PairingCode.generate(), c.count == 12, case .success = PairingCode.check(c) else { allValid = false; continue }
    for ch in c.prefix(11) { counts[ch.wholeNumberValue!] += 1 }
}
let expected = 5000.0 * 11 / 10
let chi = counts.reduce(0.0) { $0 + pow(Double($1) - expected, 2) / expected }
check("generate: 5000 codes, all 12 digits and valid", allValid)
check("generate: digits uniform (chi² \(String(format: "%.1f", chi)) < 27.9, 9 df, p 0.001)", chi < 27.9)
check("check: grouped with spaces", PairingCode.check("4829 1355 7208") == .success("482913557208"))
check("check: hyphens", PairingCode.check("4829-1355-7208") == .success("482913557208"))
check("check: no-break spaces", PairingCode.check("4829\u{00A0}1355\u{00A0}7208") == .success("482913557208"))
check("check: 11 digits → length", PairingCode.check("4829 1355 720") == .failure(.length))
check("check: 13 digits → length", PairingCode.check("4829 1355 72080") == .failure(.length))
check("check: a letter → length", PairingCode.check("4829 1355 72O8") == .failure(.length))
check("check: Arabic-Indic digits → length", PairingCode.check("٤٨٢٩١٣٥٥٧٢٠٨") == .failure(.length))
check("check: one digit changed → typo", PairingCode.check("4829 1355 7209") == .failure(.typo))
check("check: two neighbours swapped → typo", PairingCode.check("4829 1355 7280") == .failure(.typo))
check("grouped: 4829 1355 7208", PairingCode.grouped("482913557208") == "4829 1355 7208")

// MARK: - PairingProof (§3.6 vectors, computed in Python)

let fpMac = Data(SHA256.hash(data: Data("mac".utf8)))
let fpDev = Data(SHA256.hash(data: Data("device".utf8)))
check("vector fp_mac", hex(fpMac) == "348a629f5ceed032c3e8706ec47d9bfafb00fb4250b018dd965435ca50cb836e")
check("vector fp_device", hex(fpDev) == "263a4dbe41488fb87214b0032339dbb9f0c8da14c16dfcf13084bf3c2552eca5")
let t0 = CFAbsoluteTimeGetCurrent()
let K = PairingProof.codeKey(code: "482913557208", macFingerprint: fpMac)!
let pbkdfMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
check("vector code K (PBKDF2 600,000 rounds in \(Int(pbkdfMs)) ms)",
      K.withUnsafeBytes { hex(Data($0)) } == "e9baf879a1cc4ac8b21554df480b6c1621671319107c91e7cb05d154f649d31d")
let codeD = PairingProof.deviceProof(key: K, deviceFingerprint: fpDev, macFingerprint: fpMac)
let codeM = PairingProof.macProof(key: K, macFingerprint: fpMac, deviceFingerprint: fpDev)
check("vector code proof_D", Base64URL.encode(codeD) == "dk7PZj4vHsAxj--1u9Vg7ehSn8a1tWc0RCG46YpFVO8")
check("vector code proof_M", Base64URL.encode(codeM) == "6BmGWC9XT8J8OY8phhq9bASgoSnoWpRxBeqZtvRrWmk")
let qr = PairingProof.qrKey(secret: Data(repeating: 0x22, count: 16))
let qrD = PairingProof.deviceProof(key: qr, deviceFingerprint: fpDev, macFingerprint: fpMac)
let qrM = PairingProof.macProof(key: qr, macFingerprint: fpMac, deviceFingerprint: fpDev)
check("vector qr proof_D", Base64URL.encode(qrD) == "AyZAJqNTU5nSKEaHx6RZOf0K5dOeygR_8JSrCV_gNOo")
check("vector qr proof_M", Base64URL.encode(qrM) == "XAX-uZPsq_Ax8fvI_sV7Ex0a-ROi19rI-FW-ykPh9TE")
check("the labels differ: proof_D ≠ proof_M under one key", qrD != qrM && codeD != codeM)
check("swapped fingerprints change proof_D",
      PairingProof.deviceProof(key: qr, deviceFingerprint: fpMac, macFingerprint: fpDev) != qrD)
check("swapped fingerprints change proof_M",
      PairingProof.macProof(key: qr, macFingerprint: fpDev, deviceFingerprint: fpMac) != qrM)
check("a relay's key in place of the Mac's changes proof_D",
      PairingProof.deviceProof(key: qr, deviceFingerprint: fpDev, macFingerprint: Data(SHA256.hash(data: Data("relay".utf8)))) != qrD)
check("isValidDeviceProof accepts proof_D", PairingProof.isValidDeviceProof(qrD, key: qr, deviceFingerprint: fpDev, macFingerprint: fpMac))
var flipped = qrD; flipped[5] ^= 0x01
check("isValidDeviceProof refuses a flipped bit", !PairingProof.isValidDeviceProof(flipped, key: qr, deviceFingerprint: fpDev, macFingerprint: fpMac))
check("isValidDeviceProof refuses proof_M in its place", !PairingProof.isValidDeviceProof(qrM, key: qr, deviceFingerprint: fpDev, macFingerprint: fpMac))
check("isValidMacProof accepts proof_M", PairingProof.isValidMacProof(codeM, key: K, macFingerprint: fpMac, deviceFingerprint: fpDev))
check("isValidMacProof refuses under another code's key",
      !PairingProof.isValidMacProof(codeM, key: PairingProof.codeKey(code: "482913557217", macFingerprint: fpMac)!, macFingerprint: fpMac, deviceFingerprint: fpDev))
check("codeKey refuses 11 digits", PairingProof.codeKey(code: "48291355720", macFingerprint: fpMac) == nil)

// MARK: - Certificate, fingerprint, Mac ID

check("Mac ID vector: fp[0..<10] = 50d858e0985ecc7f6041 → A3C5HR4RBV67YR21",
      MacID.make(fingerprint: unhex("50d858e0985ecc7f6041") + Data(count: 22)) == "A3C5HR4RBV67YR21")
check("Mac ID of SHA-256(\"example\") (the vector's source)", MacID.make(fingerprint: Data(SHA256.hash(data: Data("example".utf8)))) == "A3C5HR4RBV67YR21")
check("Mac ID: all zeros", MacID.make(fingerprint: Data(count: 32)) == "0000000000000000")
check("Mac ID: all ones", MacID.make(fingerprint: Data(repeating: 0xFF, count: 32)) == "ZZZZZZZZZZZZZZZZ")
check("Mac ID: well-formed check", MacID.isWellFormed("A3C5HR4RBV67YR21") && !MacID.isWellFormed("A3C5HR4RBV67YR2I") && !MacID.isWellFormed("a3c5hr4rbv67yr21"))
let key = RemoteKey.generate()!
let der = SelfSignedCertificate.make(key: key)!
let cert = SecCertificateCreateWithData(nil, der as CFData)
check("certificate: \(der.count) bytes, SecCertificateCreateWithData accepts it", cert != nil)
check("certificate: its key's fingerprint equals the private key's", cert.flatMap { SPKI.fingerprint(of: $0) } == SPKI.fingerprint(of: key))
let summary = cert.flatMap { SecCertificateCopySubjectSummary($0) as String? } ?? ""
check("certificate: the CN is 16 hex characters (\(summary))", summary.count == 16 && summary.allSatisfy { $0.isHexDigit })
let der2 = SelfSignedCertificate.make(key: key)!
check("certificate: rebuilt from the same key, a new serial and CN, the same fingerprint",
      der2 != der && SPKI.fingerprint(of: SecCertificateCreateWithData(nil, der2 as CFData)!) == SPKI.fingerprint(of: key))
let identity = RemoteIdentity(privateKey: key)
check("RemoteIdentity: SecIdentityCreate and sec_identity_create accept it", identity != nil)
check("RemoteIdentity: fingerprint is the SPKI hash of the public point",
      identity?.fingerprint == SPKI.fingerprint(point: RemoteKey.publicPoint(key)!))
check("SPKI DER is 91 bytes", SPKI.der(point: RemoteKey.publicPoint(key)!).count == 91)
let exported = RemoteKey.export(key)!
check("RemoteKey: export/import round trip keeps the fingerprint", RemoteKey.importPrivate(exported).flatMap { SPKI.fingerprint(of: $0) } == SPKI.fingerprint(of: key))
let rsa = SecKeyCreateRandomKey([kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits as String: 2048] as CFDictionary, nil)!
check("SPKI.fingerprint refuses a non-P-256 key", SPKI.fingerprint(of: rsa) == nil)
try! der.write(to: out.appendingPathComponent("cert.der"))
try! Base64URL.encode(identity!.fingerprint).write(to: out.appendingPathComponent("cert.fp"), atomically: true, encoding: .utf8)

// MARK: - Base64URL

check("base64url: 32 bytes → 43 characters", Base64URL.encode(Data(count: 32)).count == 43)
check("base64url: 16 bytes → 22 characters", Base64URL.encode(Data(count: 16)).count == 22)
check("base64url: round trip of 1–40 random bytes", (1...40).allSatisfy { n in
    var b = [UInt8](repeating: 0, count: n); _ = SecRandomCopyBytes(kSecRandomDefault, n, &b)
    return Base64URL.decode(Base64URL.encode(Data(b))) == Data(b) })
check("base64url: refuses padding, +, / and a bad length",
      Base64URL.decode("AAAA=") == nil && Base64URL.decode("ab+c") == nil && Base64URL.decode("ab/c") == nil && Base64URL.decode("abcde") == nil)
check("base64url: refuses non-canonical trailing bits", Base64URL.decode("AB") == nil)

// MARK: - RecognitionTag

let rk = Data(repeating: 0x11, count: 32)
let vectorTag = RecognitionTag.make(recognitionKey: rk, nonce: unhex("a1a2a3a4a5a6"))
check("tag vector: key 0x11×32, p a1a2a3a4a5a6 → oaKjpKWmL4V47Ctm (\(vectorTag ?? "nil"))", vectorTag == "oaKjpKWmL4V47Ctm")
check("tag vector matches its key", RecognitionTag.matches("oaKjpKWmL4V47Ctm", recognitionKey: rk))
var wrong = 0
for _ in 0..<10_000 {
    var k = [UInt8](repeating: 0, count: 32); _ = SecRandomCopyBytes(kSecRandomDefault, 32, &k)
    if RecognitionTag.matches("oaKjpKWmL4V47Ctm", recognitionKey: Data(k)) { wrong += 1 }
}
check("tag: 10,000 wrong keys never match (\(wrong))", wrong == 0)
let fresh = (0..<100).compactMap { _ in RecognitionTag.make(recognitionKey: rk) }
check("tag: 100 fresh tags, all 16 characters, all different, all matching", Set(fresh).count == 100 && fresh.allSatisfy { $0.count == 16 && RecognitionTag.matches($0, recognitionKey: rk) })
check("tag: malformed input never matches", !RecognitionTag.matches("", recognitionKey: rk) && !RecognitionTag.matches("oaKjpKWmL4V47Ct", recognitionKey: rk)
      && !RecognitionTag.matches("oaKjpKWmL4V47Ctn", recognitionKey: rk) && !RecognitionTag.matches("oaKjpKWmL4V47Ctm=", recognitionKey: rk))

// MARK: - SafeText

check("SafeText: plain name unchanged", SafeText.label("iPad (iPad14,1)") == "iPad (iPad14,1)")
check("SafeText: newline and tab become one space", SafeText.label("iPad\n\tPro") == "iPad Pro")
check("SafeText: a lone newline becomes a space, not nothing", SafeText.label("iPad\nPro") == "iPad Pro" && SafeText.label("iPad\u{2028}mini") == "iPad mini")
check("SafeText: a forged log line stays on one line", !SafeText.label("iPad\nClient connected: 1.2.3.4").contains("\n"))
check("SafeText: bidi override U+202E removed", SafeText.label("iPad\u{202E}dáPi") == "iPaddáPi")
check("SafeText: bidi isolates U+2066–2069 and embeddings U+202A–202D removed",
      SafeText.label("a\u{2066}b\u{2067}c\u{2068}d\u{2069}e\u{202A}f\u{202B}g\u{202C}h\u{202D}i") == "abcdefghi")
check("SafeText: zero-width space and BOM removed", SafeText.label("i\u{200B}Pa\u{FEFF}d") == "iPad")
check("SafeText: C0 and C1 controls removed", SafeText.label("i\u{0007}P\u{001B}[31ma\u{0085}d\u{009B}") == "iP[31ma d")
check("SafeText: whitespace runs collapse, ends trimmed", SafeText.label("  iPad \u{00A0}\u{3000}  mini  ") == "iPad mini")
let long = String(repeating: "x", count: 500)
check("SafeText: 500 characters → 64", SafeText.label(long).count == 64)
check("SafeText: emoji and accents survive, cut at 64 characters", SafeText.label(String(repeating: "é", count: 70)).count == 64
      && SafeText.label("Noah’s iPad 🍎") == "Noah’s iPad 🍎")
check("SafeText: nothing printable → empty", SafeText.label("\u{202E}\u{0000}\n ") == "")
check("SafeText: private use removed", SafeText.label("i\u{E000}Pad") == "iPad")

// MARK: - PairLink

let secret = Data((0..<16).map { UInt8($0) })
let v6 = ParsedAddress(host: "fd7a:115c:a1e0::1234", port: nil, kind: .ipv6)
let links: [ParsedAddress] = [ParsedAddress(host: "mac-mini.tail1234.ts.net", port: nil, kind: .name),
                              ParsedAddress(host: "100.101.102.103", port: nil, kind: .ipv4), v6,
                              ParsedAddress(host: "192.168.1.20", port: nil, kind: .ipv4),
                              ParsedAddress(host: "home.example.net", port: 17455, kind: .name)]
let macFP = identity!.fingerprint
let link = PairLink(fingerprint: macFP, secret: secret, name: "Tom & Jerry’s Mac=mini?", port: 7455, addresses: links)
let url = link.url
print("     link (\(url.utf8.count) bytes): \(url)")
check("PairLink: \(url.utf8.count) bytes, under 300", url.utf8.count < 300)
if case .success(let back) = PairLink.parse(url) {
    check("PairLink: round trip (name with & = ?, IPv6 in brackets, a port)", back == link)
    check("PairLink: the IPv6 address came back as IPv6", back.addresses[2] == v6)
    check("PairLink: macID is MacID(k)", back.macID == MacID.make(fingerprint: macFP))
} else { check("PairLink: round trip", false) }
func linkWith(_ transform: (inout [(String, String)]) -> Void) -> String {
    var items: [(String, String)] = [("v", "1"), ("m", MacID.make(fingerprint: macFP)), ("k", Base64URL.encode(macFP)),
                                     ("s", Base64URL.encode(secret)), ("n", "Mac mini"), ("p", "7455"), ("a", "100.101.102.103")]
    transform(&items)
    return "sill://pair?" + items.map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-._~:")))!)" }.joined(separator: "&")
}
func refused(_ name: String, _ text: String, _ want: PairLink.Failure) {
    let r = PairLink.parse(text)
    if case .failure(let f) = r { check("PairLink refuses \(name) (\(f))", f == want) } else { check("PairLink refuses \(name)", false) }
}
check("PairLink: the baseline test link parses", { if case .success = PairLink.parse(linkWith { _ in }) { return true }; return false }())
refused("v=2", linkWith { $0[0].1 = "2" }, .version)
refused("no v", linkWith { $0.remove(at: 0) }, .version)
refused("no m", linkWith { $0.remove(at: 1) }, .field("m"))
refused("m of another key", linkWith { $0[1].1 = "A3C5HR4RBV67YR21" }, .macIDMismatch)
refused("m lower case", linkWith { $0[1].1 = $0[1].1.lowercased() }, .field("m"))
refused("no k", linkWith { $0.remove(at: 2) }, .field("k"))
refused("k of 31 bytes", linkWith { $0[2].1 = Base64URL.encode(macFP.prefix(31)) }, .field("k"))
refused("two k", linkWith { $0.append(("k", Base64URL.encode(macFP))) }, .field("k"))
refused("no s", linkWith { $0.remove(at: 3) }, .field("s"))
refused("s of 15 bytes", linkWith { $0[3].1 = Base64URL.encode(secret.prefix(15)) }, .field("s"))
refused("no p", linkWith { $0.remove(at: 5) }, .field("p"))
refused("p=0", linkWith { $0[5].1 = "0" }, .field("p"))
refused("p=65536", linkWith { $0[5].1 = "65536" }, .field("p"))
refused("an address the parser refuses (1.2.3)", linkWith { $0.append(("a", "1.2.3")) }, .address("1.2.3"))
refused("a zone", linkWith { $0.append(("a", "fe80::1%en0")) }, .address("fe80::1%en0"))
refused("http scheme", "http://pair?v=1", .notALink)
refused("another host", linkWith { _ in }.replacingOccurrences(of: "sill://pair", with: "sill://evil"), .notALink)
if case .success(let l) = PairLink.parse(linkWith { $0.append(("x", "ignored")); $0.append(("zz", "")) }) {
    check("PairLink: unknown parameters ignored", l.addresses.count == 1)
} else { check("PairLink: unknown parameters ignored", false) }
if case .success(let l) = PairLink.parse(linkWith { for i in 1...7 { $0.append(("a", "10.0.0.\(i)")) } }) {
    check("PairLink: 8 addresses → the first 5 kept", l.addresses.count == 5 && l.addresses[0].host == "100.101.102.103")
} else { check("PairLink: 8 addresses", false) }
if case .success(let l) = PairLink.parse(linkWith { $0[4].1 = String(repeating: "M", count: 100) + "\u{202E}" }) {
    check("PairLink: n cleaned and capped at 64", l.name.count == 64 && !l.name.unicodeScalars.contains("\u{202E}"))
} else { check("PairLink: n capped", false) }
if case .success(let l) = PairLink.parse(linkWith { $0.remove(at: 4) }) {
    check("PairLink: no n → \"Mac\"", l.name == "Mac")
} else { check("PairLink: no n", false) }

// MARK: - Kind 18 signing

let info = MacInfo(macID: MacID.make(fingerprint: macFP), name: "Mac mini", issuedAt: 1790265600.5, remoteAccess: true, remotePort: 7455,
                   internet: false, addresses: [MacAddress(host: "100.101.102.103", kind: "vpn", via: "Tailscale"),
                                                MacAddress(host: "home.example.net", port: 17455, kind: "internet", via: "Address name")])
let signed = SignedMacInfo.signing(info, with: key)!
if let (got, fp) = signed.verified() {
    check("kind 18: verifies, and gives the signer's fingerprint", got == info && fp == macFP)
} else { check("kind 18: verifies", false) }
var infoBytes = Data(base64Encoded: signed.info)!
infoBytes[10] ^= 0x01
check("kind 18: one flipped byte in info fails", SignedMacInfo(info: infoBytes.base64EncodedString(), key: signed.key, sig: signed.sig).verified() == nil)
var sigBytes = Data(base64Encoded: signed.sig)!
sigBytes[sigBytes.count - 3] ^= 0x01
check("kind 18: one flipped byte in sig fails", SignedMacInfo(info: signed.info, key: signed.key, sig: sigBytes.base64EncodedString()).verified() == nil)
let other = RemoteKey.generate()!
check("kind 18: another key in `key` fails",
      SignedMacInfo(info: signed.info, key: RemoteKey.publicPoint(other)!.base64EncodedString(), sig: signed.sig).verified() == nil)
check("kind 18: signed by another key (its own key field) fails the macID binding",
      SignedMacInfo.signing(info, with: other)!.verified() == nil)
check("kind 18: unverifiedInfo decodes for display", signed.unverifiedInfo() == info)
let wireJSON = String(data: Wire.encode(signed), encoding: .utf8)!
try! wireJSON.write(to: out.appendingPathComponent("signed-macinfo.json"), atomically: true, encoding: .utf8)
check("kind 18: the example addresses encode as the plan shows (port only where set)",
      String(data: Wire.encode(info.addresses[0]), encoding: .utf8)!.contains("\"port\"") == false)

// MARK: - Wire kinds and caps

func header(_ kind: UInt8) -> StreamHeader? {
    var d = Data([kind]); d.append(Data(count: 8)); d.append(0); d.append(contentsOf: [0, 0, 0, 0])
    return StreamMessage.parseHeader(d)
}
check("kinds 18–22 parse as macInfo, pairRequest, pairResult, pairingWanted, goodbye",
      [header(18)?.kind, header(19)?.kind, header(20)?.kind, header(21)?.kind, header(22)?.kind] == [.macInfo, .pairRequest, .pairResult, .pairingWanted, .goodbye])
check("kind 23 is hello (update-notice); 24, 25 and 27 the Mac's menus; 26 the Mac's pointer",
      header(23)?.kind == .hello && header(24)?.kind == .macMenu && header(25)?.kind == .pressMenuItem
      && header(27)?.kind == .fetchMenu && header(26)?.kind == .macPointer)
check("kind 28 is gesture (trackpad gestures), 29 unknown (skipped)", header(28)?.kind == .gesture && header(29)?.kind == .unknown)
check("kinds 16 and 17 unchanged", header(16)?.kind == .hostSettings && header(17)?.kind == .changeSettings)
check("caps: 1 MiB client, 4 KiB pairing, 32 MiB frames, 4 MiB other",
      StreamMessage.maxClientPayload == 1_048_576 && StreamMessage.maxPairingPayload == 4096
      && StreamMessage.maxFramePayload == 33_554_432 && StreamMessage.maxOtherHostPayload == 4_194_304)
let pr = PairResult(ok: false, reason: PairResult.code, triesLeft: 4)
check("kind 20 JSON leaves out nil fields", String(data: Wire.encode(pr), encoding: .utf8) == #"{"ok":false,"reason":"code","triesLeft":4}"#
      || (Wire.decode(PairResult.self, from: Wire.encode(pr))?.triesLeft == 4 && !String(data: Wire.encode(pr), encoding: .utf8)!.contains("proof")))
check("kind 19 decodes the plan's example",
      Wire.decode(PairRequest.self, from: Data(#"{"v":1,"method":"qr","proof":"AyZAJqNTU5nSKEaHx6RZOf0K5dOeygR_8JSrCV_gNOo","name":"iPad","model":"iPad14,1"}"#.utf8))?.model == "iPad14,1")
check("kind 22 decodes an unknown reason as a string", Wire.decode(Goodbye.self, from: Data(#"{"reason":"later","x":1}"#.utf8))?.reason == "later")

// MARK: - RemoteTLS, live on loopback: the shared builder on both ends

let q = DispatchQueue(label: "tls")
let mac = RemoteIdentity(privateKey: RemoteKey.generate()!)!
let dev = RemoteIdentity(privateKey: RemoteKey.generate()!)!
let stranger = RemoteIdentity(privateKey: RemoteKey.generate()!)!
final class Box: @unchecked Sendable { var lines: [String] = []; var serverALPNSeen: [String?] = [] }
func handshake(_ client: RemoteIdentity, alpn: String, pin: Data, paired: Set<Data>, pairingOpen: Bool) -> (clientReady: Bool, echo: Bool, serverALPN: String?, serverPeer: Data?, clientPeer: Data?, box: Box) {
    let box = Box()
    let server = RemoteTLS.options(identity: mac.tls, role: .server, queue: q) { fp, a in
        box.serverALPNSeen.append(a)
        guard let fp else { return false }
        return a == RemoteTLS.sessionALPN ? paired.contains(fp) : (a == RemoteTLS.pairingALPN && pairingOpen)
    }
    let params = RemoteTLS.parameters(tls: server, dialing: false)
    params.requiredInterfaceType = .loopback
    let l = try! NWListener(using: params)
    var serverALPN: String?, serverPeer: Data?, clientPeer: Data?, ready = false, echo = false
    var accepted: [NWConnection] = []
    let done = DispatchSemaphore(value: 0)
    l.newConnectionHandler = { c in
        accepted.append(c)
        c.stateUpdateHandler = { st in
            if case .ready = st {
                serverALPN = RemoteTLS.negotiatedALPN(c); serverPeer = RemoteTLS.peerFingerprint(c)
                c.receive(minimumIncompleteLength: 4, maximumLength: 4) { d, _, _, _ in if let d { c.send(content: d, completion: .contentProcessed { _ in }) } }
            }
        }
        c.start(queue: q)
    }
    l.stateUpdateHandler = { st in
        guard case .ready = st, let port = l.port else { return }
        let cp = RemoteTLS.parameters(tls: RemoteTLS.options(identity: client.tls, role: .client(alpn: alpn), verify: { $0 == pin }, queue: q), dialing: true)
        let c = NWConnection(to: .hostPort(host: "127.0.0.1", port: port), using: cp)
        var finished = false
        func finish() { if !finished { finished = true; c.cancel(); done.signal() } }
        c.stateUpdateHandler = { st in
            switch st {
            case .ready:
                ready = true; clientPeer = RemoteTLS.peerFingerprint(c)
                c.send(content: Data("sill".utf8), completion: .contentProcessed { _ in })
                c.receive(minimumIncompleteLength: 4, maximumLength: 4) { d, _, _, e in
                    echo = d == Data("sill".utf8)
                    if let e { box.lines.append("client read: \(e)") }
                    finish()
                }
            case .failed(let e): box.lines.append("client failed: \(e)"); finish()
            case .waiting(let e): box.lines.append("client waiting: \(e)"); finish()
            default: break
            }
        }
        c.start(queue: q)
        q.asyncAfter(deadline: .now() + 3) { finish() }
    }
    l.start(queue: q)
    _ = done.wait(timeout: .now() + 5)
    q.sync { accepted.forEach { $0.cancel() }; l.cancel() }
    return (ready, echo, serverALPN, serverPeer, clientPeer, box)
}
var r = handshake(dev, alpn: RemoteTLS.sessionALPN, pin: mac.fingerprint, paired: [dev.fingerprint], pairingOpen: false)
check("TLS: a paired key on sill/1 — ready, echo, both ALPNs sill/1, both peers pinned",
      r.clientReady && r.echo && r.serverALPN == "sill/1" && r.serverPeer == dev.fingerprint && r.clientPeer == mac.fingerprint)
check("TLS: the server's verify block saw the ALPN (\(r.box.serverALPNSeen))", r.box.serverALPNSeen == ["sill/1"])
r = handshake(stranger, alpn: RemoteTLS.sessionALPN, pin: mac.fingerprint, paired: [dev.fingerprint], pairingOpen: true)
check("TLS: an unpaired key on sill/1 while pairing is open — refused in the handshake (\(r.box.lines.joined(separator: "; ")))",
      !r.echo && r.box.lines.contains { $0.contains("-9825") })
r = handshake(stranger, alpn: RemoteTLS.pairingALPN, pin: mac.fingerprint, paired: [dev.fingerprint], pairingOpen: true)
check("TLS: an unpaired key on sill-pair/1 while pairing is open — admitted (ALPN \(r.serverALPN ?? "nil"))", r.echo && r.serverALPN == "sill-pair/1")
r = handshake(stranger, alpn: RemoteTLS.pairingALPN, pin: mac.fingerprint, paired: [dev.fingerprint], pairingOpen: false)
check("TLS: sill-pair/1 with no pairing window — refused (\(r.box.lines.joined(separator: "; ")))", !r.echo)
r = handshake(dev, alpn: RemoteTLS.sessionALPN, pin: stranger.fingerprint, paired: [dev.fingerprint], pairingOpen: false)
check("TLS: the client's pin does not match — waiting -9808, never ready (\(r.box.lines.joined(separator: "; ")))",
      !r.clientReady && r.box.lines.contains { $0.contains("-9808") })
r = handshake(dev, alpn: "sill/2", pin: mac.fingerprint, paired: [dev.fingerprint], pairingOpen: false)
check("TLS: an ALPN the host does not offer — refused (\(r.box.lines.joined(separator: "; ")))", !r.clientReady && !r.echo)
// The floor (CLAUDE.md): a host offers sill/1 and sill-pair/1 for good, and a later generation only
// ever adds to them. A 1.0 device offers exactly one of the two and hears kind 22 "update" only
// inside a sill/1 session: a host without sill/1 would leave it a failed handshake (-9838, as the
// sill/2 case above shows from the other side) and a redial for ever.
check("floor: every host offers sill/1 and sill-pair/1 (\(RemoteTLS.serverALPNs))",
      RemoteTLS.serverALPNs.contains("sill/1") && RemoteTLS.serverALPNs.contains("sill-pair/1"))
check("floor: the two names never change", RemoteTLS.sessionALPN == "sill/1" && RemoteTLS.pairingALPN == "sill-pair/1")

print(fails == 0 ? "ALL PASS (\(passes) checks)" : "\(fails) FAILED of \(passes + fails)")
exit(Int32(min(fails, 100)))
