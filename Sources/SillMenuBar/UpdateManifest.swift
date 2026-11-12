import CryptoKit
import Foundation
import StreamProtocol

/// The second factor of Update Now (docs/one-click-update-plan.md §4.3 and T4): a small text, published
/// beside `Sill.zip` as `Sill.zip.manifest`, that names exactly one release's zip (its tag, version,
/// build, size, SHA-256) and its code (the cdhash of each architecture's slice), signed with an Ed25519
/// key that Noah keeps off GitHub. GitHub Actions holds the Developer ID identity (the `nightly`
/// environment signs and notarizes every night with no reviewer), so a Developer ID signature proves
/// only "built by Sill's CI"; this signature proves "Noah released this build". Update Now verifies it
/// before the zip is even downloaded, and then holds the zip and the unpacked app to it.
///
/// Pure: Foundation, CryptoKit and StreamProtocol's SillVersion, and nothing else of Sill, so the signer
/// (Scripts/update-manifest.swift) compiles from this file, SillVersion's Compatibility.swift and its own
/// main: the three files Noah reads before he installs it. The app and the signer share this one definition
/// of the format, the version rules and the architectures. Checked by Tests/checks/update-install.
///
/// The format, ASCII, one field a line, each line ending in "\n", no other whitespace, at most 4 KB:
///
///     Sill update 1
///     tag v0.6.2
///     version 0.6.2
///     build 1400
///     asset Sill.zip
///     size 5920002
///     sha256 a50c5fd38958db5d3f9aea4ef569705effa3462b2d522b73c12baea0a1fc9926
///     cdhash arm64 d5feca97b4d531345aefab17bb8b588358f2975f
///     cdhash x86_64 0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c
///     signed 2026-11-12T03:00:00Z
///     key 1a2b3c4d
///     signature <88 characters of base64: Ed25519 over every byte before this line>
///
/// `signed` is when Noah signed it, UTC, by the signer's clock: a date GitHub can't change (its own
/// published_at is not signed). The automatic update waits until a release has been signed for a while
/// and never installs one signed long ago (UpdateAutoPolicy; review 3, the automatic update's point 1 and F7).
///
/// A release Noah wants no Sill to install (one signed with a key that leaked, a bad build) gets a stop
/// beside it, `Sill.zip.stop`, signed with an update key too (`Stop`): it names the release's tag and its
/// zip's SHA-256, and a Sill that reads it installs that release neither by Update Now nor by itself.
struct UpdateManifest: Equatable, Sendable {
    /// The Ed25519 public keys (raw 32 bytes, base64) whose signature Update Now accepts. EMPTY ON
    /// PURPOSE: no key exists yet (Noah makes it: plan §10, Q1, and Scripts/sign-update.sh --new-key),
    /// and with none Update Now is not offered at all (UpdateInstallPolicy.Trust.release). Setting it is
    /// one line here; a second key beside the first is how the key is rotated (plan §4.3).
    static let releaseKeys: [String] = []

    static let firstLine = "Sill update 1"
    static let maxBytes = 4096

    let tag: String
    let version: SillVersion
    /// The bundle's CFBundleVersion: digits.
    let build: String
    let asset: String
    let size: Int64
    /// 64 lowercase hex digits.
    let sha256: String
    /// "arm64" and/or "x86_64" → the slice's cdhash, 40 lowercase hex digits.
    let cdhashes: [String: String]
    /// When it was signed (whole seconds, UTC).
    let signedAt: Date
    /// The first 8 hex digits of the SHA-256 of the signing key's raw bytes.
    let keyID: String

    enum Problem: Error, Equatable, Sendable {
        case tooLarge
        /// A byte that is not printable ASCII or "\n", or no "\n" at the end.
        case notText
        /// A line missing, out of order, extra, or not of its form; the line's field.
        case format(String)
        /// No key is compiled in.
        case noKey
        /// Signed with a key this Sill does not have (its key ID).
        case unknownKey(String)
        /// A compiled-in key that is not a usable Ed25519 public key.
        case badKey
        case badSignature

        var text: String {
            switch self {
            case .tooLarge: return "it is larger than 4 KB"
            case .notText: return "it is not plain text"
            case .format(let field): return "its \(field) line is not as the format says"
            case .noKey: return "this Sill has no key to check it with"
            case .unknownKey(let id): return "it is signed with a key this Sill doesn’t have (\(id))"
            case .badKey: return "this Sill’s key is not usable"
            case .badSignature: return "its signature is not valid"
            }
        }
    }

    // MARK: Reading

    /// The manifest, the bytes its signature covers, and the signature, if `data` is exactly of the
    /// format. Nothing is verified here.
    static func parse(_ data: Data) -> Result<(manifest: UpdateManifest, signed: Data, signature: Data), Problem> {
        guard data.count <= maxBytes else { return .failure(.tooLarge) }
        let bytes = [UInt8](data)
        guard let last = bytes.last, last == 0x0A,
              bytes.allSatisfy({ $0 == 0x0A || (0x20...0x7E).contains($0) }) else { return .failure(.notText) }
        // Every line ends in "\n": the last split piece is the empty string after the final "\n".
        var lines = String(decoding: bytes, as: UTF8.self).components(separatedBy: "\n")
        lines.removeLast()
        var i = 0
        func field(_ key: String) -> String? {
            guard i < lines.count, lines[i].hasPrefix(key + " ") else { return nil }
            defer { i += 1 }
            return String(lines[i].dropFirst(key.count + 1))
        }
        guard lines.first == firstLine else { return .failure(.format("first")) }
        i = 1
        guard let tag = field("tag"), let tagVersion = strictTag(tag) else { return .failure(.format("tag")) }
        guard let versionText = field("version"), versionText == String(tag.dropFirst()),
              let version = strictVersion(versionText), version == tagVersion else { return .failure(.format("version")) }
        guard let build = field("build"), isDigits(build, 1...9) else { return .failure(.format("build")) }
        guard let asset = field("asset"), isAssetName(asset) else { return .failure(.format("asset")) }
        guard let sizeText = field("size"), isDigits(sizeText, 1...12), let size = Int64(sizeText), size > 0 else { return .failure(.format("size")) }
        guard let sha256 = field("sha256"), isHex(sha256, count: 64) else { return .failure(.format("sha256")) }
        var cdhashes: [String: String] = [:]
        var order: [String] = []
        while i < lines.count, lines[i].hasPrefix("cdhash ") {
            let parts = lines[i].split(separator: " ", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3, Architecture(rawValue: parts[1]) != nil, isHex(parts[2], count: 40),
                  cdhashes[parts[1]] == nil else { return .failure(.format("cdhash")) }
            cdhashes[parts[1]] = parts[2]
            order.append(parts[1])
            i += 1
        }
        // One or both architectures, arm64 first.
        guard !order.isEmpty, order == order.sorted() else { return .failure(.format("cdhash")) }
        guard let signedText = field("signed"), let signedAt = date(signedText) else { return .failure(.format("signed")) }
        guard let keyID = field("key"), isHex(keyID, count: 8) else { return .failure(.format("key")) }
        let signedEnd = lines[0..<i].reduce(0) { $0 + $1.utf8.count + 1 }
        guard let signatureText = field("signature"), signatureText.count == 88,
              let signature = Data(base64Encoded: signatureText), signature.count == 64,
              signature.base64EncodedString() == signatureText else { return .failure(.format("signature")) }
        guard i == lines.count else { return .failure(.format("last")) }
        let manifest = UpdateManifest(tag: tag, version: version, build: build, asset: asset, size: size, sha256: sha256,
                                      cdhashes: cdhashes, signedAt: signedAt, keyID: keyID)
        return .success((manifest, Data(bytes[0..<signedEnd]), signature))
    }

    /// The manifest, if `data` is of the format and signed by one of `keys` (the one its key line
    /// names). Every key in the list must be usable, or none is trusted.
    static func verify(_ data: Data, keys: [String]) -> Result<UpdateManifest, Problem> {
        switch parse(data) {
        case .failure(let problem):
            return keys.isEmpty ? .failure(.noKey) : .failure(problem)
        case .success(let parsed):
            if let problem = check(parsed.signed, parsed.signature, keyID: parsed.manifest.keyID, keys: keys) { return .failure(problem) }
            return .success(parsed.manifest)
        }
    }

    /// Nil when `signature` over `signed` is one of `keys`' (the one `keyID` names); every key in the list
    /// must be usable, or none is trusted.
    static func check(_ signed: Data, _ signature: Data, keyID wanted: String, keys: [String]) -> Problem? {
        guard !keys.isEmpty else { return .noKey }
        var publicKeys: [(id: String, key: Curve25519.Signing.PublicKey)] = []
        for text in keys {
            guard let raw = usableKey(text), let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else { return .badKey }
            publicKeys.append((keyID(raw), key))
        }
        let candidates = publicKeys.filter { $0.id == wanted }
        guard !candidates.isEmpty else { return .unknownKey(wanted) }
        for candidate in candidates where candidate.key.isValidSignature(signature, for: signed) { return nil }
        return .badSignature
    }

    // MARK: Writing (the signer's)

    /// The lines a signature covers, as the signer writes them (each ending in "\n").
    static func signedText(tag: String, build: String, asset: String, size: Int64, sha256: String,
                           cdhashes: [String: String], signedAt: Date, keyID: String) -> String {
        var text = "\(firstLine)\ntag \(tag)\nversion \(tag.dropFirst())\nbuild \(build)\nasset \(asset)\nsize \(size)\nsha256 \(sha256)\n"
        for arch in cdhashes.keys.sorted() { text += "cdhash \(arch) \(cdhashes[arch]!)\n" }
        return text + "signed \(dateText(signedAt))\nkey \(keyID)\n"
    }

    /// The whole manifest: the signed lines and the signature line.
    static func document(signedText: String, signature: Data) -> String {
        signedText + "signature \(signature.base64EncodedString())\n"
    }

    // MARK: Keys

    /// The first 8 hex digits of SHA-256 over the raw public key.
    static func keyID(_ raw: Data) -> String {
        SHA256.hash(data: raw).prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    /// The raw 32 bytes of a base64 Ed25519 public key that is safe to trust, else nil: it decodes to
    /// exactly 32 bytes, CryptoKit takes it, and it is none of the points of small order (whose
    /// signatures can be forged for some messages: libsodium refuses the same list), whatever the
    /// sign bit says.
    static func usableKey(_ base64: String) -> Data? {
        guard let raw = Data(base64Encoded: base64), raw.count == 32, raw.base64EncodedString() == base64,
              (try? Curve25519.Signing.PublicKey(rawRepresentation: raw)) != nil else { return nil }
        let bytes = [UInt8](raw)
        if smallOrder.contains(where: { Array($0[0..<31]) == Array(bytes[0..<31]) && $0[31] == bytes[31] & 0x7F }) { return nil }
        return raw
    }

    /// The y-coordinates (sign bit clear) of the Edwards points of order 1, 2, 4 and 8, and the
    /// non-canonical encodings of 0, 1 and p − 1 (libsodium's blocklist).
    static let smallOrder: [[UInt8]] = [
        [UInt8](repeating: 0, count: 32),
        [1] + [UInt8](repeating: 0, count: 31),
        [0x26, 0xe8, 0x95, 0x8f, 0xc2, 0xb2, 0x27, 0xb0, 0x45, 0xc3, 0xf4, 0x89, 0xf2, 0xef, 0x98, 0xf0,
         0xd5, 0xdf, 0xac, 0x05, 0xd3, 0xc6, 0x33, 0x39, 0xb1, 0x38, 0x02, 0x88, 0x6d, 0x53, 0xfc, 0x05],
        [0xc7, 0x17, 0x6a, 0x70, 0x3d, 0x4d, 0xd8, 0x4f, 0xba, 0x3c, 0x0b, 0x76, 0x0d, 0x10, 0x67, 0x0f,
         0x2a, 0x20, 0x53, 0xfa, 0x2c, 0x39, 0xcc, 0xc6, 0x4e, 0xc7, 0xfd, 0x77, 0x92, 0xac, 0x03, 0x7a],
        [0xec] + [UInt8](repeating: 0xff, count: 30) + [0x7f],
        [0xed] + [UInt8](repeating: 0xff, count: 30) + [0x7f],
        [0xee] + [UInt8](repeating: 0xff, count: 30) + [0x7f],
    ]

    // MARK: Fields

    static func isDigits(_ s: String, _ count: ClosedRange<Int>) -> Bool {
        count.contains(s.utf8.count) && s.utf8.allSatisfy { $0 >= 0x30 && $0 <= 0x39 }
    }

    /// Lowercase hex, exactly `count` digits.
    static func isHex(_ s: String, count: Int) -> Bool {
        s.utf8.count == count && s.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66) }
    }

    /// An asset's name: 1 to 64 of letters, digits, ".", "-" and "_", not starting with ".".
    static func isAssetName(_ s: String) -> Bool {
        (1...64).contains(s.utf8.count) && s.utf8.first != 0x2E
            && s.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) || $0 == 0x2E || $0 == 0x2D || $0 == 0x5F }
    }
}

// MARK: Dates

extension UpdateManifest {
    /// "2026-11-12T03:00:00Z": UTC, whole seconds, exactly 20 characters, a real date of the years 2000 to
    /// 2999; nil for anything else (another zone, fractions, a 30 February).
    static func date(_ text: String) -> Date? {
        let b = Array(text.utf8)
        guard b.count == 20, b[4] == 0x2D, b[7] == 0x2D, b[10] == 0x54, b[13] == 0x3A, b[16] == 0x3A, b[19] == 0x5A else { return nil }
        func number(_ r: Range<Int>) -> Int? {
            b[r].allSatisfy { $0 >= 0x30 && $0 <= 0x39 } ? Int(String(decoding: b[r], as: UTF8.self)) : nil
        }
        guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10), let hour = number(11..<13),
              let minute = number(14..<16), let second = number(17..<19), (2000...2999).contains(year) else { return nil }
        guard let date = utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)),
              dateText(date) == text else { return nil }
        return date
    }

    /// `date`'s form of a moment (its fraction of a second dropped).
    static func dateText(_ date: Date) -> String {
        let c = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02dZ", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    private static let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()
}

// MARK: A stop

extension UpdateManifest {
    /// Noah's word that one release must not be installed, `Sill.zip.stop` beside it, signed as a manifest
    /// is (its own first line, so neither can stand for the other):
    ///
    ///     Sill stop 1
    ///     tag v0.6.3
    ///     sha256 <the release's zip, as its manifest names it>
    ///     signed 2026-11-13T09:00:00Z
    ///     key 1a2b3c4d
    ///     signature <88 characters of base64: Ed25519 over every byte before this line>
    struct Stop: Equatable, Sendable {
        static let firstLine = "Sill stop 1"
        let tag: String
        let sha256: String
        let signedAt: Date
        let keyID: String
    }

    /// The lines a stop's signature covers.
    static func stopText(tag: String, sha256: String, signedAt: Date, keyID: String) -> String {
        "\(Stop.firstLine)\ntag \(tag)\nsha256 \(sha256)\nsigned \(dateText(signedAt))\nkey \(keyID)\n"
    }

    /// The stop, if `data` is exactly of its form and signed by one of `keys`.
    static func verifyStop(_ data: Data, keys: [String]) -> Result<Stop, Problem> {
        guard data.count <= maxBytes else { return .failure(.tooLarge) }
        let bytes = [UInt8](data)
        guard let last = bytes.last, last == 0x0A, bytes.allSatisfy({ $0 == 0x0A || (0x20...0x7E).contains($0) }) else {
            return .failure(.notText)
        }
        var lines = String(decoding: bytes, as: UTF8.self).components(separatedBy: "\n")
        lines.removeLast()
        guard lines.count == 6, lines[0] == Stop.firstLine else { return .failure(.format("first")) }
        func value(_ i: Int, _ key: String) -> String? { lines[i].hasPrefix(key + " ") ? String(lines[i].dropFirst(key.count + 1)) : nil }
        guard let tag = value(1, "tag"), strictTag(tag) != nil else { return .failure(.format("tag")) }
        guard let sha256 = value(2, "sha256"), isHex(sha256, count: 64) else { return .failure(.format("sha256")) }
        guard let signedText = value(3, "signed"), let signedAt = date(signedText) else { return .failure(.format("signed")) }
        guard let keyID = value(4, "key"), isHex(keyID, count: 8) else { return .failure(.format("key")) }
        guard let signatureText = value(5, "signature"), signatureText.count == 88, let signature = Data(base64Encoded: signatureText),
              signature.count == 64, signature.base64EncodedString() == signatureText else { return .failure(.format("signature")) }
        let signedEnd = lines[0..<5].reduce(0) { $0 + $1.utf8.count + 1 }
        if let problem = check(Data(bytes[0..<signedEnd]), signature, keyID: keyID, keys: keys) { return .failure(problem) }
        return .success(Stop(tag: tag, sha256: sha256, signedAt: signedAt, keyID: keyID))
    }

    /// What the signer asks in person before it signs a stop.
    static func stoppingReason(tag: String, sha256: String) -> String {
        "stop every Sill from installing Sill \(tag) (SHA-256 \(grouped(sha256)))"
    }

    /// 64 hex digits in groups of eight.
    static func grouped(_ hex: String) -> String {
        var groups: [String] = []
        var rest = Substring(hex)
        while !rest.isEmpty {
            groups.append(String(rest.prefix(8)))
            rest = rest.dropFirst(8)
        }
        return groups.joined(separator: " ")
    }
}

// MARK: The signer's prompt

extension UpdateManifest {
    /// What the signer asks Noah in person before the keychain's key signs (LocalAuthentication shows
    /// "update-manifest is trying to ‹this›"): the tag, the asset, its size and its whole SHA-256 in groups of
    /// eight, to compare with what release.sh printed. The whole of it: with 16 digits a zip that looks the
    /// same was a 2^64 search away (review 3, F4).
    static func signingReason(tag: String, asset: String, size: Int64, sha256: String) -> String {
        "sign Sill \(tag) for Update Now: \(asset), \(size) bytes, SHA-256 \(grouped(sha256))"
    }
}

// MARK: Versions and architectures (Update Now's, here so the signer needs this file alone)

extension UpdateManifest {
    /// A version of digits and dots only: 1 to 8 parts of 1 to 9 digits ("0.6.2"). SillVersion reads
    /// the digits-and-dots prefix of anything ("0.6.2-rc" is 0.6.2); Update Now takes only this.
    static func strictVersion(_ text: String) -> SillVersion? {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...8).contains(parts.count),
              parts.allSatisfy({ (1...9).contains($0.utf8.count) && $0.utf8.allSatisfy { $0 >= 0x30 && $0 <= 0x39 } }) else { return nil }
        return SillVersion(text)
    }

    /// A tag: "v" and a strict version.
    static func strictTag(_ tag: String) -> SillVersion? {
        guard tag.hasPrefix("v") else { return nil }
        return strictVersion(String(tag.dropFirst()))
    }

    /// The slices a release may have.
    enum Architecture: String, CaseIterable, Sendable {
        case arm64, x86_64

        /// The slice this process runs (Rosetta runs x86_64).
        static var current: Architecture {
            #if arch(arm64)
            return .arm64
            #else
            return .x86_64
            #endif
        }
    }
}
