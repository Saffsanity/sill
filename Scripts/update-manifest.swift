import CryptoKit
import Foundation
import Security

// The update manifest's tool (docs/one-click-update-plan.md §4.3), for Scripts/sign-update.sh: compiled
// by it with Sources/SillMenuBar's UpdateManifest, UpdateInstallPolicy, UpdatePolicy and UpdateInstaller
// and StreamProtocol, so the manifest it writes and the cdhashes it reads are the app's own definitions.
//
//   update-manifest new-key [--key-file PATH]     make the update key: in the login keychain (service
//                                                 me.saffer.sill.update-signing, account ed25519, never
//                                                 synced), or a new file of mode 0600; prints the public key
//   update-manifest public-key [--key-file PATH]  the stored key's public key and key ID
//   update-manifest cdhashes APP                  each slice's cdhash, as Update Now reads them
//   update-manifest sign --tag T --build B --asset NAME --size N --sha256 HEX --cdhash ARCH=HEX...
//                        --out FILE [--key-file PATH]
//   update-manifest verify FILE --key BASE64...   the manifest's fields, if one of the keys signed it
//
// The private key is read from the keychain (which asks before giving it to this tool) or from the file
// given; it is never printed, never written anywhere else, and never sent anywhere.

let service = "me.saffer.sill.update-signing", account = "ed25519"
var args = Array(CommandLine.arguments.dropFirst())
func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("update-manifest: \(message)\n".utf8))
    exit(1)
}
func option(_ name: String) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    let value = args[i + 1]
    args.removeSubrange(i...(i + 1))
    return value
}
func options(_ name: String) -> [String] {
    var values: [String] = []
    while let v = option(name) { values.append(v) }
    return values
}

func storedKey(_ file: String?) -> Curve25519.Signing.PrivateKey {
    let raw: Data
    if let file {
        guard let text = try? String(contentsOfFile: file, encoding: .utf8),
              let d = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { fail("can’t read the key in \(file)") }
        raw = d
    } else {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let d = item as? Data, let text = String(data: d, encoding: .utf8),
              let decoded = Data(base64Encoded: text) else { fail("no update key in the login keychain (\(status)); make one with new-key") }
        raw = decoded
    }
    guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else { fail("the stored key is not an Ed25519 private key") }
    return key
}

func describe(_ key: Curve25519.Signing.PrivateKey) -> String {
    let pub = key.publicKey.rawRepresentation
    return "public key \(pub.base64EncodedString()) (key ID \(UpdateManifest.keyID(pub)))"
}

guard let command = args.first else { fail("a command: new-key, public-key, cdhashes, sign or verify") }
args.removeFirst()
switch command {
case "new-key":
    let file = option("--key-file")
    let key = Curve25519.Signing.PrivateKey()
    let secret = Data(key.rawRepresentation.base64EncodedString().utf8)
    if let file {
        let fd = open(file, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { fail("\(file) exists or can’t be made (\(String(cString: strerror(errno))))") }
        _ = secret.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        close(fd)
    } else {
        let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                  kSecAttrAccount as String: account, kSecAttrLabel as String: "Sill update signing key",
                                  kSecAttrSynchronizable as String: false, kSecValueData as String: secret]
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else {
            fail(status == errSecDuplicateItem ? "an update key is in the keychain already; never make a second one by accident" : "the keychain refused it (\(status))")
        }
    }
    print(describe(key))
    print("Put the public key in Sources/SillMenuBar/UpdateManifest.swift's releaseKeys, and keep a copy of the private key off this Mac (docs/release-checklist.md, Update Now's key).")
case "public-key":
    print(describe(storedKey(option("--key-file"))))
case "cdhashes":
    guard let path = args.first else { fail("cdhashes APP") }
    for arch in UpdateInstallPolicy.Architecture.allCases {
        if let h = UpdateInstaller.cdhash(of: URL(fileURLWithPath: path), arch: arch) { print("\(arch.rawValue)=\(h)") }
    }
case "sign":
    guard let tag = option("--tag"), let build = option("--build"), let asset = option("--asset"),
          let sizeText = option("--size"), let size = Int64(sizeText), let sha = option("--sha256"), let out = option("--out") else {
        fail("sign needs --tag, --build, --asset, --size, --sha256, --cdhash ARCH=HEX and --out")
    }
    var cdhashes: [String: String] = [:]
    for pair in options("--cdhash") {
        let parts = pair.split(separator: "=").map(String.init)
        guard parts.count == 2 else { fail("--cdhash ARCH=HEX: \(pair)") }
        cdhashes[parts[0]] = parts[1]
    }
    let key = storedKey(option("--key-file"))
    let text = UpdateManifest.signedText(tag: tag, build: build, asset: asset, size: size, sha256: sha, cdhashes: cdhashes,
                                         keyID: UpdateManifest.keyID(key.publicKey.rawRepresentation))
    guard let signature = try? key.signature(for: Data(text.utf8)) else { fail("signing failed") }
    let document = Data(UpdateManifest.document(signedText: text, signature: signature).utf8)
    // Read back as the app reads it, with this key, before it is written.
    guard case .success = UpdateManifest.verify(document, keys: [key.publicKey.rawRepresentation.base64EncodedString()]) else {
        fail("the manifest does not read back (a field is not of the format: \(text))")
    }
    guard FileManager.default.createFile(atPath: out, contents: document) else { fail("can’t write \(out)") }
    print("Signed \(tag) (\(asset), \(size) bytes) with \(describe(key)): \(out)")
case "verify":
    guard let file = args.first, let data = FileManager.default.contents(atPath: file) else { fail("verify FILE --key BASE64") }
    args.removeFirst()
    switch UpdateManifest.verify(data, keys: options("--key")) {
    case .success(let m):
        print("tag \(m.tag), version \(m.version), build \(m.build), \(m.asset) \(m.size) bytes, SHA-256 \(m.sha256), key \(m.keyID)")
        for (arch, h) in m.cdhashes.sorted(by: { $0.key < $1.key }) { print("cdhash \(arch) \(h)") }
    case .failure(let p):
        fail("not verified: \(p.text)")
    }
default:
    fail("unknown command \(command)")
}
