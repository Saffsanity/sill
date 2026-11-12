import Compression
import CryptoKit
import Foundation

// Update Now (docs/one-click-update-plan.md §4): UpdateInstallPolicy, UpdateManifest and UpdateArchive,
// compiled with StreamProtocol and UpdatePolicy as one module, and the app's sources read as text
// (argv[1], Sources/SillMenuBar or a mutant's copy). Every key here is made for this run and dropped.
var failures = 0, checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
typealias P = UpdateInstallPolicy
typealias M = UpdateManifest
typealias A = UpdateArchive
let v030 = SillVersion("0.3.0")!, v040 = SillVersion("0.4.0")!, v041 = SillVersion("0.4.1")!

// MARK: The two constants Sill.app uses

let pinned = "anchor apple generic and identifier \"me.saffer.sill.mac\" and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = \"9B2KKVM937\""
let release = P.Trust.release
check(P.pinnedRequirement == pinned, "the pinned requirement: \(P.pinnedRequirement)")
check(release.signer == pinned, "release signs with the pinned requirement")
check(release.notarized && release.stapledTicket && release.hardenedRuntime && release.runningRequirement, "release: notarized, stapled, runtime, the running requirement")
check(release.identifier == "me.saffer.sill.mac" && release.teamID == "9B2KKVM937", "release: identifier and team")
check(release.bundleName == "Sill.app" && release.executable == "Sill", "release: Sill.app/Contents/MacOS/Sill")
check(release.entitlements == [.string(key: "com.apple.application-identifier", value: "9B2KKVM937.me.saffer.sill.mac"),
                               .string(key: "com.apple.developer.team-identifier", value: "9B2KKVM937"),
                               .arrayContaining(key: "keychain-access-groups", value: "9B2KKVM937.me.saffer.sill.mac")],
      "release: the three entitlements")
check(release.updateKeys == M.releaseKeys, "release: the compiled-in update keys")
for key in M.releaseKeys { check(M.usableKey(key) != nil, "a compiled-in update key is not usable: \(key)") }
let gh = P.Endpoints.github
check(gh.latestRelease == UpdatePolicy.feed, "the release request is the check's feed")
check(gh.latestRelease.absoluteString == "https://api.github.com/repos/Saffsanity/sill/releases/latest", "the feed")
check(gh.apiOrigins == ["https://api.github.com"], "api origins: \(gh.apiOrigins)")
check(gh.downloadPrefix == "https://github.com/Saffsanity/sill/releases/download/", "download prefix")
check(gh.assetName == "Sill.zip" && gh.manifestName == "Sill.zip.manifest", "asset names")
check(gh.redirectOrigins == ["https://release-assets.githubusercontent.com", "https://objects.githubusercontent.com"], "redirect origins")
check(gh.redirectPathPrefix == "/github-production-release-asset", "redirect path")
check(gh.maxRedirects == 3 && gh.minAssetBytes == 1024 && gh.maxAssetBytes == 64 << 20, "limits")
check(P.maxReleaseBytes == 1 << 20 && P.launchWait == 30 && P.spaceMargin == 64 << 20, "the other limits")

// MARK: Origins and redirects

func u(_ s: String) -> URL { URL(string: s)! }
check(P.origin(u("https://GitHub.com/x")) == "https://github.com", "origin lowercased")
check(P.origin(u("https://github.com:443/x")) == "https://github.com:443", "an explicit port is part of the origin")
check(P.origin(u("https://me:pw@github.com/x")) == nil, "credentials in a URL")
check(P.origin(u("https://me@github.com/x")) == nil, "a user in a URL")
check(P.origin(u("file:///tmp/x")) == nil, "no host")
let assetPath = "https://release-assets.githubusercontent.com/github-production-release-asset/1381093165/3ce2?sp=r&sig=x"
check(P.downloadRedirectAllowed(u(assetPath), endpoints: gh), "GitHub's asset host")
check(P.downloadRedirectAllowed(u("https://objects.githubusercontent.com/github-production-release-asset-2e65be/1/2"), endpoints: gh), "the older host")
check(!P.downloadRedirectAllowed(u(assetPath.replacingOccurrences(of: "https:", with: "http:")), endpoints: gh), "http")
check(!P.downloadRedirectAllowed(u("https://release-assets.githubusercontent.com/other/1"), endpoints: gh), "another path")
check(!P.downloadRedirectAllowed(u("https://release-assets.githubusercontent.com.evil.example/github-production-release-asset/1"), endpoints: gh), "a host under another domain")
check(!P.downloadRedirectAllowed(u("https://evilrelease-assets.githubusercontent.com/github-production-release-asset/1"), endpoints: gh), "a look-alike host")
check(!P.downloadRedirectAllowed(u("https://release-assets.githubusercontent.com:8443/github-production-release-asset/1"), endpoints: gh), "a port")
check(!P.downloadRedirectAllowed(u("https://x@release-assets.githubusercontent.com/github-production-release-asset/1"), endpoints: gh), "a user")
check(!P.downloadRedirectAllowed(u("https://github.com/Saffsanity/sill/releases/download/v0.4.0/Sill.zip"), endpoints: gh), "github.com is no redirect target")
check(!P.downloadRedirectAllowed(u("https://api.github.com/github-production-release-asset/1"), endpoints: gh), "the API host")
check(P.apiRedirectAllowed(u("https://api.github.com/repositories/1381093165/releases/latest"), endpoints: gh), "a renamed repository")
check(!P.apiRedirectAllowed(u("http://api.github.com/x"), endpoints: gh), "the API over http")
check(!P.apiRedirectAllowed(u("https://github.com/x"), endpoints: gh), "another host for the API")

// MARK: Versions and tags

for (text, ok) in [("0.6.2", true), ("1", true), ("1.2.3.4.5.6.7.8", true), ("1.2.3.4.5.6.7.8.9", false), ("0.6.2-rc", false),
                   ("0.6..2", false), (".6", false), ("6.", false), ("", false), (" 0.6", false), ("0.6 ", false),
                   ("1234567890", false), ("123456789", true), ("٣.٢", false), ("0x6", false), ("v0.6", false)] {
    check((P.strictVersion(text) != nil) == ok, "strictVersion(\(text)) should be \(ok)")
}
for (tag, ok) in [("v0.6.2", true), ("V0.6.2", false), ("0.6.2", false), ("v0.6.2/../x", false), ("v", false), ("vv0.6", false),
                  ("v0.6.2%2F", false), ("v0.6.2 ", false)] {
    check((P.strictTag(tag) != nil) == ok, "strictTag(\(tag)) should be \(ok)")
}
check(P.strictTag("v0.4.0") == v040, "v0.4.0 is 0.4")
check(P.assetURL(tag: "v0.4.0", name: "Sill.zip", endpoints: gh)?.absoluteString == "https://github.com/Saffsanity/sill/releases/download/v0.4.0/Sill.zip", "the zip's URL")
check(P.assetURL(tag: "v0.4.0", name: "Sill.zip.manifest", endpoints: gh)?.absoluteString == "https://github.com/Saffsanity/sill/releases/download/v0.4.0/Sill.zip.manifest", "the manifest's URL")
check(P.assetURL(tag: "v0.4.0", name: "Sill.dmg", endpoints: gh) == nil, "another asset")
check(P.assetURL(tag: "../v0.4.0", name: "Sill.zip", endpoints: gh) == nil, "a tag that is a path")

// MARK: Refusals

let fine = P.Situation(runningIsRelease: true, testFeed: false, bundlePath: "/Applications/Sill.app", bundleIsLink: false,
                       translocated: false, volumeName: "Macintosh HD", readOnlyVolume: false, networkVolume: false, diskImage: false,
                       folderWritable: true, bundleWritable: true, ownedByUser: true, runningIsInstalled: true, otherAccounts: [],
                       otherInstances: 0, freeBytes: 10 << 30, neededBytes: P.neededBytes(assetBytes: 8 << 20))
check(P.refusal(fine) == nil, "a release in Applications, alone, with room: no refusal")
check(P.neededBytes(assetBytes: 8 << 20) == 32 << 20 + 64 << 20, "the space needed")
func with(_ change: (inout P.Situation) -> Void) -> P.Situation { var s = fine; change(&s); return s }
let refusalCases: [(P.Situation, P.Refusal)] = [
    (with { $0.runningIsRelease = false }, .notRelease),
    (with { $0.testFeed = true }, .testFeed),
    (with { $0.translocated = true; $0.readOnlyVolume = true }, .translocated),
    (with { $0.diskImage = true; $0.readOnlyVolume = true }, .diskImage),
    (with { $0.readOnlyVolume = true }, .readOnlyVolume("Macintosh HD")),
    (with { $0.networkVolume = true }, .networkVolume("Macintosh HD")),
    (with { $0.bundleIsLink = true }, .link("/Applications/Sill.app")),
    (with { $0.folderWritable = false }, .notWritable("/Applications")),
    (with { $0.bundleWritable = false }, .notWritable("/Applications")),
    (with { $0.ownedByUser = false }, .notWritable("/Applications")),
    (with { $0.runningIsInstalled = false }, .changedSinceStart("/Applications/Sill.app")),
    (with { $0.otherAccounts = ["Alex Example", "Zed"] }, .otherAccount("Alex Example")),
    (with { $0.otherInstances = 1 }, .otherInstance),
    (with { $0.freeBytes = 50 << 20 }, .lowSpace(volume: "Macintosh HD", neededMB: 96)),
]
for (s, expected) in refusalCases { check(P.refusal(s) == expected, "refusal: \(String(describing: P.refusal(s))) instead of \(expected)") }
// First match wins, in the plan's order.
check(P.refusal(with { $0.runningIsRelease = false; $0.testFeed = true; $0.otherInstances = 2 }) == .notRelease, "notRelease first")
check(P.refusal(with { $0.testFeed = true; $0.translocated = true }) == .testFeed, "testFeed before translocated")
check(P.refusal(with { $0.otherAccounts = ["A"]; $0.otherInstances = 1; $0.freeBytes = 0 }) == .otherAccount("A"), "another account before the rest")
check(P.refusal(with { $0.runningIsInstalled = false; $0.otherAccounts = ["A"] }) == .changedSinceStart("/Applications/Sill.app"), "changed before accounts")
check(P.refusal(with { $0.freeBytes = nil }) == nil, "free space unknown: no refusal (the unpacking checks it again)")
check(P.refusal(with { $0.freeBytes = 96 << 20 }) == nil, "exactly the space needed")
check(P.words(.notRelease) == "This copy of Sill isn’t a notarized release, so it can’t update itself.", "words: notRelease")
check(P.words(.otherAccount("Alex Example")) == "Sill is open in another account on this Mac (Alex Example). Quit it there first, then update.", "words: otherAccount")
check(P.words(.notWritable("/Applications")) == "Sill is in a folder this account can’t change (/Applications).", "words: notWritable")
check(P.words(.translocated).hasPrefix("macOS is running Sill from a temporary copy."), "words: translocated")
check(P.words(.lowSpace(volume: "X", neededMB: 96)) == "Not enough free space on X: about 96 MB are needed.", "words: lowSpace")

// MARK: The release

let zipURL = "https://github.com/Saffsanity/sill/releases/download/v0.4.0/Sill.zip"
let manURL = "https://github.com/Saffsanity/sill/releases/download/v0.4.0/Sill.zip.manifest"
let sha = String(repeating: "ab", count: 32)
func asset(_ name: String, _ url: String, size: Any = 5_920_002, state: Any = "uploaded", digest: Any? = "sha256:" + String(repeating: "ab", count: 32)) -> [String: Any] {
    var a: [String: Any] = ["name": name, "browser_download_url": url, "size": size, "state": state]
    if let digest { a["digest"] = digest }
    return a
}
func body(tag: Any = "v0.4.0", draft: Any = false, prerelease: Any = false, assets: Any? = nil) -> Data {
    let defaultAssets: [[String: Any]] = [asset("Sill.zip", zipURL), asset("Sill.zip.manifest", manURL, size: 700, digest: nil),
                                          asset("Sill.dmg", zipURL.replacingOccurrences(of: ".zip", with: ".dmg"))]
    let d: [String: Any] = ["tag_name": tag, "draft": draft, "prerelease": prerelease, "assets": assets ?? defaultAssets,
                            "html_url": "https://github.com/Saffsanity/sill/releases/tag/v0.4.0"]
    return try! JSONSerialization.data(withJSONObject: d)
}
func rel(_ b: Data, offered: String = "v0.4.0", running: SillVersion = v030) -> Result<P.Release, P.Failure> {
    P.releaseToInstall(b, offeredTag: offered, running: running, endpoints: gh)
}
if case .success(let r) = rel(body()) {
    check(r.tag == "v0.4.0" && r.version == v040, "the release's tag")
    check(r.zip == P.Asset(name: "Sill.zip", url: u(zipURL), size: 5_920_002, digest: sha), "the zip: \(r.zip)")
    check(r.manifest == P.Asset(name: "Sill.zip.manifest", url: u(manURL), size: 700, digest: nil), "the manifest: \(r.manifest)")
} else { check(false, "a good release: \(rel(body()))") }
func failure(_ r: Result<P.Release, P.Failure>) -> P.Failure? { if case .failure(let f) = r { return f }; return nil }
check(failure(rel(body(tag: "v0.4.1"))) == .releaseChanged(tag: "v0.4.1"), "another tag than offered")
check(failure(rel(body(tag: "v0.4.0-rc1"), offered: "v0.4.0-rc1")) == .releaseUnreadable("the tag is not v and a version"), "a tag that is not strict")
check(failure(rel(body(draft: true))) == .releaseUnreadable("a draft or a prerelease"), "a draft")
check(failure(rel(body(prerelease: true))) == .releaseUnreadable("a draft or a prerelease"), "a prerelease")
check(failure(rel(body(), running: v040)) == .releaseNotNewer, "the same version")
check(failure(rel(body(), running: v041)) == .releaseNotNewer, "an older version")
check(failure(rel(body(assets: [asset("Sill.zip.manifest", manURL, size: 700, digest: nil)]))) == .releaseUnreadable("no Sill.zip"), "no zip")
check(failure(rel(body(assets: [asset("Sill.zip", zipURL)]))) == .notSigned, "no manifest: not signed yet")
check(failure(rel(body(assets: [asset("Sill.zip", zipURL), asset("Sill.zip", zipURL), asset("Sill.zip.manifest", manURL, size: 700, digest: nil)]))) == .releaseUnreadable("two assets named Sill.zip"), "two zips")
check(failure(rel(body(assets: [asset("Sill.zip", zipURL, state: "starter"), asset("Sill.zip.manifest", manURL, size: 700, digest: nil)]))) == .releaseUnreadable("Sill.zip is not uploaded"), "an upload not finished")
check(failure(rel(body(assets: [asset("Sill.zip", zipURL, size: 65 << 20), asset("Sill.zip.manifest", manURL, size: 700, digest: nil)]))) == .releaseUnreadable("Sill.zip’s size"), "a zip too large")
check(failure(rel(body(assets: [asset("Sill.zip", zipURL, size: 1000), asset("Sill.zip.manifest", manURL, size: 700, digest: nil)]))) == .releaseUnreadable("Sill.zip’s size"), "a zip too small")
check(failure(rel(body(assets: [asset("Sill.zip", zipURL, size: "5920002"), asset("Sill.zip.manifest", manURL, size: 700, digest: nil)]))) == .releaseUnreadable("Sill.zip’s size"), "a size that is a string")
check(failure(rel(body(assets: [asset("Sill.zip", zipURL), asset("Sill.zip.manifest", manURL, size: 5000, digest: nil)]))) == .releaseUnreadable("Sill.zip.manifest’s size"), "a manifest too large")
for bad in ["https://github.com/Evil/sill/releases/download/v0.4.0/Sill.zip", "http://github.com/Saffsanity/sill/releases/download/v0.4.0/Sill.zip",
            "https://github.com/Saffsanity/sill/releases/download/v0.3.0/Sill.zip", "https://evil.example/Sill.zip"] {
    check(failure(rel(body(assets: [asset("Sill.zip", bad), asset("Sill.zip.manifest", manURL, size: 700, digest: nil)]))) == .releaseUnreadable("Sill.zip’s URL"), "a zip URL elsewhere: \(bad)")
}
check(failure(rel(body(assets: [asset("Sill.zip", zipURL, digest: "md5:abc"), asset("Sill.zip.manifest", manURL, size: 700, digest: nil)]))) == .releaseUnreadable("Sill.zip’s digest"), "a digest of another kind")
if case .success(let r) = rel(body(assets: [asset("Sill.zip", zipURL, digest: "sha256:" + sha.uppercased()), asset("Sill.zip.manifest", manURL, size: 700, digest: nil)])) {
    check(r.zip.digest == sha, "an uppercase digest is read lowercase")
} else { check(false, "an uppercase digest") }
check(failure(P.releaseToInstall(Data("[1]".utf8), offeredTag: "v0.4.0", running: v030, endpoints: gh)) == .releaseUnreadable("not a JSON object"), "not an object")
check(failure(P.releaseToInstall(Data(count: (1 << 20) + 1), offeredTag: "v0.4.0", running: v030, endpoints: gh)) == .releaseUnreadable("not a JSON object"), "more than 1 MB")

// MARK: The manifest

let testKey = Curve25519.Signing.PrivateKey()
let otherKey = Curve25519.Signing.PrivateKey()
let testPublic = testKey.publicKey.rawRepresentation.base64EncodedString()
let otherPublic = otherKey.publicKey.rawRepresentation.base64EncodedString()
let cd: [String: String] = ["arm64": String(repeating: "1", count: 40), "x86_64": String(repeating: "2", count: 40)]
func signedManifest(tag: String = "v0.4.0", build: String = "120", asset: String = "Sill.zip", size: Int64 = 5_920_002,
                    sha256: String = sha, cdhashes: [String: String] = cd, key: Curve25519.Signing.PrivateKey = testKey) -> String {
    let text = M.signedText(tag: tag, build: build, asset: asset, size: size, sha256: sha256, cdhashes: cdhashes,
                            keyID: M.keyID(key.publicKey.rawRepresentation))
    return M.document(signedText: text, signature: try! key.signature(for: Data(text.utf8)))
}
let good = signedManifest()
check(good.hasPrefix("Sill update 1\ntag v0.4.0\nversion 0.4.0\nbuild 120\nasset Sill.zip\nsize 5920002\nsha256 \(sha)\ncdhash arm64 \(cd["arm64"]!)\ncdhash x86_64 \(cd["x86_64"]!)\nkey "), "the format: \(good)")
switch M.verify(Data(good.utf8), keys: [testPublic]) {
case .success(let m):
    check(m.tag == "v0.4.0" && m.version == v040 && m.build == "120" && m.asset == "Sill.zip" && m.size == 5_920_002 && m.sha256 == sha
          && m.cdhashes == cd && m.keyID == M.keyID(testKey.publicKey.rawRepresentation), "the manifest read back: \(m)")
case .failure(let p): check(false, "a good manifest: \(p)")
}
func verdictOf(_ text: String, keys: [String] = [testPublic]) -> M.Problem? {
    if case .failure(let p) = M.verify(Data(text.utf8), keys: keys) { return p }
    return nil
}
check(verdictOf(good, keys: [otherPublic, testPublic]) == nil, "a second key beside it (a rotation)")
check(verdictOf(good, keys: []) == .noKey, "no key compiled in")
check(verdictOf(good, keys: [otherPublic]) == .unknownKey(M.keyID(testKey.publicKey.rawRepresentation)), "signed with a key this Sill doesn't have")
check(verdictOf(signedManifest(key: otherKey)) == .unknownKey(M.keyID(otherKey.publicKey.rawRepresentation)), "another key's manifest")
check(verdictOf(good, keys: ["not base64"]) == .badKey, "a key that is not base64")
check(verdictOf(good, keys: [Data(count: 31).base64EncodedString()]) == .badKey, "a key of 31 bytes")
for bad in M.smallOrder {
    check(M.usableKey(Data(bad).base64EncodedString()) == nil, "a small-order key: \(bad.prefix(4))")
    var signed = bad; signed[31] |= 0x80
    check(M.usableKey(Data(signed).base64EncodedString()) == nil, "a small-order key with the sign bit")
    check(verdictOf(good, keys: [testPublic, Data(bad).base64EncodedString()]) == .badKey, "one bad key spoils the list")
}
check(M.usableKey(testPublic) != nil, "a real key is usable")
check(M.usableKey(testPublic.replacingOccurrences(of: "=", with: "")) == nil, "a key in unpadded base64")
// A changed byte anywhere in what is signed.
for (old, new) in [("size 5920002", "size 5920003"), ("build 120", "build 121"), (sha, String(repeating: "cd", count: 32)),
                   (cd["arm64"]!, String(repeating: "3", count: 40))] {
    check(verdictOf(good.replacingOccurrences(of: old, with: new)) == .badSignature, "a changed \(old.prefix(12))")
}
let sigLine = good.components(separatedBy: "\n").filter { $0.hasPrefix("signature ") }.first!
var sigBytes = [UInt8](Data(base64Encoded: String(sigLine.dropFirst(10)))!)
sigBytes[5] ^= 1
check(verdictOf(good.replacingOccurrences(of: sigLine, with: "signature " + Data(sigBytes).base64EncodedString())) == .badSignature, "a changed signature")
// The same signature in base64 that is not how base64 writes it (padding bits set): refused as a format.
let canonical = String(sigLine.dropFirst(10))
let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/")
var nonCanonical = Array(canonical)
if let v = alphabet.firstIndex(of: nonCanonical[85]) {
    nonCanonical[85] = alphabet[v ^ 1]
    let text = String(nonCanonical)
    if Data(base64Encoded: text) == Data(base64Encoded: canonical) {
        check(verdictOf(good.replacingOccurrences(of: canonical, with: text)) == .format("signature"), "a signature in non-canonical base64")
    } else {
        print("note: Foundation refuses base64 with padding bits set, so the canonical check is a second guard")
    }
}
// The format, strictly.
let formatCases: [(String, M.Problem)] = [
    (good.replacingOccurrences(of: "Sill update 1", with: "Sill update 2"), .format("first")),
    (good.replacingOccurrences(of: "tag v0.4.0", with: "tag v0.4.0-rc"), .format("tag")),
    (good.replacingOccurrences(of: "version 0.4.0", with: "version 0.4.1"), .format("version")),
    (good.replacingOccurrences(of: "version 0.4.0", with: "version 0.4"), .format("version")),
    (good.replacingOccurrences(of: "build 120", with: "build 12a"), .format("build")),
    (good.replacingOccurrences(of: "asset Sill.zip", with: "asset ../Sill.zip"), .format("asset")),
    (good.replacingOccurrences(of: "size 5920002", with: "size 0"), .format("size")),
    (good.replacingOccurrences(of: "size 5920002", with: "size -1"), .format("size")),
    (good.replacingOccurrences(of: "sha256 \(sha)", with: "sha256 \(sha.uppercased())"), .format("sha256")),
    (good.replacingOccurrences(of: "cdhash arm64", with: "cdhash arm64e"), .format("cdhash")),
    (good.replacingOccurrences(of: "cdhash x86_64 \(cd["x86_64"]!)\n", with: "cdhash x86_64 \(cd["x86_64"]!)\ncdhash x86_64 \(cd["x86_64"]!)\n"), .format("cdhash")),
    (good.replacingOccurrences(of: "cdhash arm64 \(cd["arm64"]!)\ncdhash x86_64 \(cd["x86_64"]!)\n", with: "cdhash x86_64 \(cd["x86_64"]!)\ncdhash arm64 \(cd["arm64"]!)\n"), .format("cdhash")),
    (good.replacingOccurrences(of: "cdhash arm64 \(cd["arm64"]!)\ncdhash x86_64 \(cd["x86_64"]!)\n", with: ""), .format("cdhash")),
    (good.replacingOccurrences(of: "\nkey ", with: "\nkey  "), .format("key")),
    (good + "extra\n", .format("last")),
    (good.replacingOccurrences(of: "\n", with: "\r\n"), .notText),
    (String(good.dropLast()), .notText),
    (good.replacingOccurrences(of: "build 120", with: "build\t120"), .notText),
    (good.replacingOccurrences(of: sigLine, with: sigLine.replacingOccurrences(of: "=", with: "")), .format("signature")),
    (good + String(repeating: "x", count: 4096), .tooLarge),
]
for (text, expected) in formatCases { check(verdictOf(text) == expected, "format: \(String(describing: verdictOf(text))) instead of \(expected)") }
// One architecture alone is a manifest too (a build for one).
check(verdictOf(signedManifest(cdhashes: ["arm64": cd["arm64"]!])) == nil, "arm64 alone")
// Every field of another release: the signature holds, the release does not match.
func parsed(_ text: String) -> M { if case .success(let m) = M.verify(Data(text.utf8), keys: [testPublic]) { return m }; fatalError("parse \(text)") }
if case .success(let r) = rel(body()) {
    check(P.manifestMatches(parsed(good), release: r, endpoints: gh) == nil, "the manifest matches its release")
    check(P.manifestMatches(parsed(signedManifest(tag: "v0.4.1")), release: r, endpoints: gh) == .manifestMismatch("tag"), "another tag's manifest")
    check(P.manifestMatches(parsed(signedManifest(asset: "Sill.dmg")), release: r, endpoints: gh) == .manifestMismatch("asset"), "another asset's manifest")
    check(P.manifestMatches(parsed(signedManifest(size: 5_920_003)), release: r, endpoints: gh) == .manifestMismatch("size"), "another size")
    check(P.manifestMatches(parsed(signedManifest(sha256: String(repeating: "cd", count: 32))), release: r, endpoints: gh) == .manifestMismatch("sha256"), "another digest than GitHub's")
}

// MARK: The bundle

let manifest = parsed(good)
var base = P.BundleFacts()
base.tree = nil
base.signatureStatus = 0
base.signer = true
base.notarized = true
base.stapledTicket = true
base.runningRequirement = true
base.identifier = "me.saffer.sill.mac"
base.teamID = "9B2KKVM937"
base.flags = 0x10000
base.entitlements = ["com.apple.application-identifier": .string("9B2KKVM937.me.saffer.sill.mac"),
                     "com.apple.developer.team-identifier": .string("9B2KKVM937"),
                     "keychain-access-groups": .strings(["9B2KKVM937.me.saffer.sill.mac"])]
base.plist = ["CFBundleIdentifier": "me.saffer.sill.mac", "CFBundleExecutable": "Sill", "CFBundleShortVersionString": "0.4.0",
              "CFBundleVersion": "120", "LSMinimumSystemVersion": "14.0"]
base.cdhashes = cd
let macOS = OperatingSystemVersion(majorVersion: 27, minorVersion: 2, patchVersion: 0)
func verdict(_ change: (inout P.BundleFacts) -> Void = { _ in }, trust: P.Trust = release, running: SillVersion = v030,
             arch: P.Architecture = .arm64, os: OperatingSystemVersion = macOS) -> Result<P.Checked, P.BundleProblem> {
    var f = base
    change(&f)
    return P.verdict(f, trust: trust, manifest: manifest, running: running, arch: arch, macOS: os)
}
check(verdict() == .success(P.Checked(version: v040, build: "120", cdhashes: cd)), "a good bundle: \(verdict())")
func problem(_ r: Result<P.Checked, P.BundleProblem>) -> P.BundleProblem? { if case .failure(let p) = r { return p }; return nil }
let bundleCases: [((inout P.BundleFacts) -> Void, P.BundleProblem)] = [
    ({ $0.tree = "no executable" }, .notABundle("no executable")),
    ({ $0.signatureStatus = -67061 }, .invalidSignature(-67061)),
    ({ $0.signer = false }, .wrongSigner),
    ({ $0.notarized = false }, .notNotarized),
    ({ $0.stapledTicket = false }, .noStapledTicket),
    ({ $0.runningRequirement = false }, .wouldLosePermissions),
    ({ $0.runningRequirement = nil }, .wouldLosePermissions),
    ({ $0.identifier = "me.saffer.sill.other" }, .wrongIdentity),
    ({ $0.teamID = "ABCDE12345" }, .wrongIdentity),
    ({ $0.teamID = nil }, .wrongIdentity),
    ({ $0.flags = 0 }, .noHardenedRuntime),
    ({ $0.entitlements["com.apple.application-identifier"] = nil }, .entitlement("com.apple.application-identifier")),
    ({ $0.entitlements["com.apple.developer.team-identifier"] = .string("ABCDE12345") }, .entitlement("com.apple.developer.team-identifier")),
    ({ $0.entitlements["keychain-access-groups"] = .strings(["9B2KKVM937.other"]) }, .entitlement("keychain-access-groups")),
    ({ $0.entitlements["keychain-access-groups"] = .string("9B2KKVM937.me.saffer.sill.mac") }, .entitlement("keychain-access-groups")),
    ({ $0.entitlements["com.apple.security.get-task-allow"] = .bool(true) }, .debuggable),
    ({ $0.plist["CFBundleIdentifier"] = "me.saffer.sill.other" }, .info("CFBundleIdentifier")),
    ({ $0.plist["CFBundleExecutable"] = "Other" }, .info("CFBundleExecutable")),
    ({ $0.plist["CFBundleShortVersionString"] = "0.4.0-beta" }, .info("CFBundleShortVersionString")),
    ({ $0.plist["CFBundleShortVersionString"] = nil }, .info("CFBundleShortVersionString")),
    ({ $0.plist["CFBundleVersion"] = "120a" }, .info("CFBundleVersion")),
    ({ $0.plist["CFBundleShortVersionString"] = "0.3.0" }, .notNewer("0.3.0")),
    ({ $0.plist["CFBundleShortVersionString"] = "0.2.9" }, .notNewer("0.2.9")),
    ({ $0.plist["CFBundleShortVersionString"] = "0.4.1" }, .notManifest("version")),
    ({ $0.plist["CFBundleVersion"] = "121" }, .notManifest("build")),
    ({ $0.plist["LSMinimumSystemVersion"] = "27.3" }, .needsNewerMacOS("27.3")),
    ({ $0.plist["LSMinimumSystemVersion"] = "28" }, .needsNewerMacOS("28")),
    ({ $0.plist["LSMinimumSystemVersion"] = "fourteen" }, .info("LSMinimumSystemVersion")),
    ({ $0.cdhashes = ["x86_64": cd["x86_64"]!] }, .noSliceForThisMac),
    ({ $0.cdhashes["x86_64"] = String(repeating: "9", count: 40) }, .notManifest("code")),
    ({ $0.cdhashes["arm64"] = String(repeating: "9", count: 40) }, .notManifest("code")),
]
for (change, expected) in bundleCases { check(problem(verdict(change)) == expected, "bundle: \(String(describing: problem(verdict(change)))) instead of \(expected)") }
check(problem(verdict(running: v040)) == .notNewer("0.4.0"), "the same version running")
check(problem(verdict(arch: .x86_64)) == nil, "an Intel Mac takes the x86_64 slice")
check(problem(verdict({ $0.plist["LSMinimumSystemVersion"] = nil })) == nil, "no minimum macOS")
check(problem(verdict({ $0.plist["LSMinimumSystemVersion"] = "27.2" })) == nil, "this macOS exactly")
check(problem(verdict({ $0.entitlements["keychain-access-groups"] = .strings(["X.other", "9B2KKVM937.me.saffer.sill.mac"]) })) == nil, "a second keychain group beside Sill's")
check(problem(verdict({ $0.entitlements["com.apple.security.get-task-allow"] = .bool(false) })) == nil, "get-task-allow false")
// Order: an invalid signature is said before what the plist says.
check(problem(verdict({ $0.signatureStatus = -1; $0.plist = [:] })) == .invalidSignature(-1), "the signature before the plist")
check(problem(verdict({ $0.signer = false; $0.notarized = false })) == .wrongSigner, "the signer before notarization")
// A test trust (the harness's): no team, no notarization, no keys from the release.
let testTrust = P.Trust(signer: "identifier \"x\"", notarized: false, bundleName: "UpdTest.app", executable: "UpdTest", identifier: "x",
                        teamID: nil, stapledTicket: false, hardenedRuntime: false, runningRequirement: false, entitlements: [],
                        updateKeys: [testPublic])
check(problem(verdict({ $0.identifier = "x"; $0.teamID = nil; $0.notarized = false; $0.stapledTicket = false; $0.flags = 0
                        $0.runningRequirement = nil; $0.entitlements = [:]; $0.plist["CFBundleIdentifier"] = "x"
                        $0.plist["CFBundleExecutable"] = "UpdTest" }, trust: testTrust)) == nil, "the harness's trust")

// MARK: Failures and words

check(P.Failure.didNotStart("x", putBack: false).cleanUp == false && P.Failure.checkAfterSwap(.codeChanged, putBack: false).cleanUp == false,
      "a copy not put back keeps the staging folder")
check(P.Failure.didNotStart("x", putBack: true).cleanUp && P.Failure.hashMismatch.cleanUp && P.Failure.cancelled.cleanUp, "anything else cleans up")
check(P.line(.hashMismatch, running: v030, offered: v040, keptAt: nil) == "Couldn’t update: the download didn’t match the release. Sill 0.3 is unchanged.", "line: hash")
check(P.line(.bundle(.wrongSigner), running: v030, offered: v040, keptAt: nil) == "Couldn’t update: the downloaded app isn’t signed by Sill’s developer. Sill 0.3 is unchanged.", "line: signer")
check(P.line(.didNotStart("x", putBack: true), running: v030, offered: v040, keptAt: nil) == "Sill 0.4 didn’t start, so Sill 0.3 is back.", "line: put back")
check(P.line(.didNotStart("x", putBack: false), running: v030, offered: v040, keptAt: "/tmp/k/Sill.app") == "Sill couldn’t put 0.3 back in place. It is at /tmp/k/Sill.app: quit Sill and move it to your Applications folder.", "line: lost")
check(P.line(.notSigned, running: v030, offered: v040, keptAt: nil) == "Sill 0.4 isn’t ready for Update Now yet. Try again later, or open its release page.", "line: not signed")
check(P.line(.cancelled, running: v030, offered: v040, keptAt: nil) == "Update cancelled. Sill 0.3 is unchanged.", "line: cancelled")
check(P.logText(.checkAfterSwap(.codeChanged, putBack: false)).hasSuffix("NOT put back"), "the log says when nothing was put back")
check(P.names(["iPad"]) == "iPad" && P.names(["iPad", "iPhone"]) == "iPad and iPhone" && P.names(["a", "b", "c", "d"]) == "a, b and 2 more", "names")
check(P.megabytes(5_920_002) == "5.9", "megabytes")

// MARK: The state machine

typealias S = P.State
func step(_ s: S, _ e: P.Event) -> (P.Phase, [P.Effect]) { let (n, effects) = P.next(s, e); return (n.phase, effects) }
let idle = S()
check(step(idle, .updateNow(devices: [])) == (.fetching, [.fetch]), "Update Now with no device: fetch")
check(step(idle, .updateNow(devices: ["iPad"])) == (.confirming(devices: ["iPad"]), []), "Update Now with a device: ask")
let confirming = P.next(idle, .updateNow(devices: ["iPad"])).0
check(P.next(confirming, .confirm).0 == S(phase: .fetching, consented: ["iPad"]), "yes: fetch, the iPad agreed to")
check(step(confirming, .cancel) == (.idle, []), "no: idle, nothing to clean")
let fetching = S(phase: .fetching, consented: [])
check(step(fetching, .fetched(nil)) == (.downloading(received: 0, total: 0), [.download]), "fetched: download")
check(step(fetching, .fetched(.notSigned)) == (.failed(.notSigned), [.cleanUp]), "not signed: failed, clean up")
check(step(fetching, .cancel) == (.idle, [.cleanUp]), "cancel while fetching")
let downloading = S(phase: .downloading(received: 0, total: 0), consented: [])
check(step(downloading, .progress(received: 5, total: 10)) == (.downloading(received: 5, total: 10), []), "progress")
check(step(downloading, .downloaded(nil)) == (.unpacking, [.unpack]), "downloaded: unpack")
check(step(downloading, .downloaded(.hashMismatch)) == (.failed(.hashMismatch), [.cleanUp]), "a bad download")
check(step(downloading, .cancel) == (.idle, [.cleanUp]), "cancel while downloading")
check(step(S(phase: .unpacking), .unpacked(nil)) == (.checking, [.check]), "unpacked: check")
check(step(S(phase: .unpacking), .unpacked(.archive(.zip64))) == (.failed(.archive(.zip64)), [.cleanUp]), "a bad archive")
check(step(S(phase: .checking, consented: []), .checked(nil, devices: [])) == (.installing, [.install]), "checked, nobody connected: install")
check(step(S(phase: .checking, consented: ["iPad"]), .checked(nil, devices: ["iPad"])) == (.installing, [.install]), "the iPad agreed: install")
check(step(S(phase: .checking, consented: ["iPad"]), .checked(nil, devices: ["iPad", "iPhone"])) == (.ready(devices: ["iPad", "iPhone"]), []), "an iPhone joined: ask again")
check(step(S(phase: .checking, consented: []), .checked(nil, devices: ["iPad"])) == (.ready(devices: ["iPad"]), []), "a device joined: ask")
check(step(S(phase: .checking), .checked(.bundle(.wrongSigner), devices: [])) == (.failed(.bundle(.wrongSigner)), [.cleanUp]), "a bad bundle")
check(P.next(S(phase: .ready(devices: ["iPad"])), .confirm).0 == S(phase: .installing, consented: ["iPad"]), "ready, yes: install")
check(step(S(phase: .ready(devices: ["iPad"])), .cancel) == (.idle, [.cleanUp]), "ready, no: clean up")
check(step(S(phase: .installing), .installed(nil)) == (.restarting, [.launch]), "installed: launch")
check(step(S(phase: .installing), .installed(.checkAfterSwap(.codeChanged, putBack: true))) == (.failed(.checkAfterSwap(.codeChanged, putBack: true)), [.cleanUp]), "put back: clean up")
check(step(S(phase: .installing), .installed(.checkAfterSwap(.codeChanged, putBack: false))) == (.failed(.checkAfterSwap(.codeChanged, putBack: false)), []), "not put back: keep the staging folder")
check(step(S(phase: .installing), .cancel) == (.installing, []), "no cancel once installing")
check(step(S(phase: .restarting), .launched(nil)) == (.restarting, [.quit]), "launched: quit")
check(step(S(phase: .restarting), .launched(.didNotStart("x", putBack: true))) == (.failed(.didNotStart("x", putBack: true)), [.cleanUp]), "didn't start, put back")
check(step(S(phase: .restarting), .launched(.didNotStart("x", putBack: false))) == (.failed(.didNotStart("x", putBack: false)), []), "didn't start, not put back")
check(step(S(phase: .restarting), .cancel) == (.restarting, []), "no cancel while restarting")
check(step(S(phase: .failed(.hashMismatch)), .updateNow(devices: [])) == (.fetching, [.fetch]), "try again")
check(P.next(S(phase: .failed(.hashMismatch), consented: ["iPad"]), .updateNow(devices: [])).0.consented == [], "a new attempt forgets the old consent")
// Events a phase does not take change nothing.
let busy: [S] = [fetching, downloading, S(phase: .unpacking), S(phase: .checking), S(phase: .installing), S(phase: .restarting)]
for s in busy {
    check(step(s, .updateNow(devices: [])) == (s.phase, []), "no second update while \(s.phase)")
    check(step(s, .confirm) == (s.phase, []), "no confirm while \(s.phase)")
}
check(step(idle, .fetched(nil)) == (.idle, []), "a late answer in idle")
check(step(idle, .launched(nil)) == (.idle, []), "a late launch in idle")
check(step(fetching, .downloaded(nil)) == (.fetching, []), "an answer of another step")
check(!P.Phase.idle.busy && !P.Phase.failed(.cancelled).busy && !P.Phase.ready(devices: []).busy && !P.Phase.confirming(devices: []).busy
      && P.Phase.fetching.busy && P.Phase.installing.busy && P.Phase.restarting.busy, "busy")

// MARK: Settings and the menu

func pane(_ phase: P.Phase, available: Bool = true, refusal: P.Refusal? = nil, offered: SillVersion? = v040, keptAt: String? = nil) -> P.Pane {
    P.pane(S(phase: phase), offered: offered, running: v030, available: available, refusal: refusal, keptAt: keptAt)
}
check(pane(.idle, available: false) == P.Pane(), "no key: nothing of Update Now")
check(pane(.idle, offered: nil) == P.Pane(announce: nil), "nothing offered: no button")
let available = pane(.idle)
check(available.updateNow && available.updateNowEnabled && available.updateNowTitle == "Update Now" && available.line == nil && available.note == nil, "offered: Update Now")
let refused = pane(.idle, refusal: .otherInstance)
check(refused.updateNow && !refused.updateNowEnabled && refused.note == P.words(.otherInstance), "refused: disabled, with why")
let asking = pane(.confirming(devices: ["iPad"]))
check(!asking.updateNow && asking.question == "Updating restarts Sill and disconnects iPad." && asking.confirmTitle == "Update and Disconnect" && asking.cancel, "the question")
check(asking.announce == asking.question, "VoiceOver hears the question")
let dl = pane(.downloading(received: 2_960_001, total: 5_920_002))
check(dl.line == "Downloading Sill 0.4… 3.0 of 5.9 MB" && dl.progress == 0.5 && dl.cancel && dl.busy && !dl.updateNow, "downloading: \(dl)")
check(pane(.fetching).line == "Getting Sill 0.4 from GitHub…" && pane(.fetching).spinning, "fetching")
check(pane(.checking).line == "Checking Sill 0.4…" && pane(.unpacking).line == "Checking Sill 0.4…", "checking")
let ready = pane(.ready(devices: ["iPad", "iPhone"]))
check(ready.line == "Sill 0.4 is ready." && ready.question == "Installing it restarts Sill and disconnects iPad and iPhone." && ready.confirmTitle == "Install and Disconnect", "ready")
check(pane(.installing).line == "Installing Sill 0.4…" && !pane(.installing).cancel, "installing: no cancel")
check(pane(.restarting).line == "Restarting Sill…" && pane(.restarting).busy, "restarting")
let failed = pane(.failed(.hashMismatch))
check(failed.failed && failed.updateNow && failed.updateNowEnabled && failed.updateNowTitle == "Try Again", "failed: try again")
let lost = pane(.failed(.didNotStart("x", putBack: false)), keptAt: "/k/Sill.app")
check(lost.line?.contains("/k/Sill.app") == true && !lost.updateNowEnabled, "lost: the path, no try again")
check(!pane(.failed(.hashMismatch), refusal: .otherInstance).updateNowEnabled, "failed and now refused")
let menuOld = P.menuItem(.idle, offered: v040, running: v030, available: false, refusal: nil)
check(menuOld.title == UpdatePolicy.menuTitle(UpdatePolicy.Offer(version: v040, tag: "v0.4.0", url: u("https://github.com/Saffsanity/sill/releases/tag/v0.4.0")))
      && menuOld.subtitle == UpdatePolicy.menuSubtitle(running: v030) && !menuOld.opensSettings, "without Update Now: the item as before")
let menuNew = P.menuItem(.idle, offered: v040, running: v030, available: true, refusal: nil)
check(menuNew == ("Sill 0.4 Is Available…", "You have 0.3; update it in Settings", true), "with Update Now: Settings")
check(P.menuItem(.idle, offered: v040, running: v030, available: true, refusal: .otherInstance).opensSettings == false, "refused: the release page")
check(P.menuItem(.downloading(received: 1, total: 4), offered: v040, running: v030, available: true, refusal: nil) == ("Updating to Sill 0.4…", "Downloading, 25%", true), "downloading in the menu")
check(P.menuItem(.installing, offered: v040, running: v030, available: true, refusal: nil).subtitle == "Installing", "installing in the menu")
check(P.footnote.contains("Update Now downloads the new version from GitHub") && P.footnote.contains("notarized by Apple"), "the footnote")

// MARK: Archives

struct Z {
    var name: String
    var data: [UInt8] = []
    var mode: UInt32 = 0o100644
    var method: UInt16 = 8
    var madeBy: UInt16 = 0x0315
    var flags: UInt16 = 0
    var descriptor = false
    var localName: String?
    var localMethod: UInt16?
    var crc: UInt32?
    var size: Int?
    var localSize: Int?
    /// This entry's central record points at entry `reuse`'s local header, and it writes none of its own.
    var reuse: Int?
}
func deflate(_ bytes: [UInt8]) -> [UInt8] {
    var out = [UInt8](repeating: 0, count: bytes.count + 1024)
    let n = compression_encode_buffer(&out, out.count, bytes, bytes.count, nil, COMPRESSION_ZLIB)
    return Array(out[0..<n])
}
func crc(_ bytes: [UInt8]) -> UInt32 { bytes.withUnsafeBytes { A.crc32($0) } }
func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF)] }
func le32(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 24 & 0xFF)] }
func zip(_ entries: [Z], comment: String = "", zip64Locator: Bool = false, prefix: [UInt8] = []) -> Data {
    var out = prefix
    var central: [UInt8] = []
    var offsets: [Int] = []
    for e in entries {
        let isDir = e.name.hasSuffix("/")
        let method = isDir ? 0 : e.method
        let stored = method == 0 ? e.data : deflate(e.data)
        let c = e.crc ?? crc(e.data)
        let size = e.size ?? e.data.count
        let flags = e.flags | (e.descriptor ? 8 : 0)
        let offset = e.reuse.map { offsets[$0] } ?? out.count
        offsets.append(offset)
        let name = Array(e.name.utf8), localName = Array((e.localName ?? e.name).utf8)
        if e.reuse == nil {
            out += le32(0x0403_4B50) + le16(20) + le16(Int(flags)) + le16(Int(e.localMethod ?? method)) + le16(0) + le16(0)
            out += e.descriptor ? le32(0) + le32(0) + le32(0) : le32(Int(c)) + le32(stored.count) + le32(e.localSize ?? size)
            out += le16(localName.count) + le16(0) + localName + stored
            if e.descriptor { out += le32(0x0807_4B50) + le32(Int(c)) + le32(stored.count) + le32(size) }
        }
        central += le32(0x0201_4B50) + le16(Int(e.madeBy)) + le16(20) + le16(Int(flags)) + le16(Int(method)) + le16(0) + le16(0)
        central += le32(Int(c)) + le32(stored.count) + le32(size) + le16(name.count) + le16(0) + le16(0) + le16(0) + le16(0)
        central += le32(Int(e.mode) << 16) + le32(offset) + name
    }
    let cdOffset = out.count
    out += central
    if zip64Locator { out += le32(0x0706_4B50) + le32(0) + le32(0) + le32(0) + le32(1) }
    let commentBytes = Array(comment.utf8)
    out += le32(0x0605_4B50) + le16(0) + le16(0) + le16(entries.count) + le16(entries.count) + le32(central.count) + le32(cdOffset)
    out += le16(commentBytes.count) + commentBytes
    return Data(out)
}
let exe = [UInt8](repeating: 0x41, count: 5000) + Array("the executable".utf8)
let plist = Array("<?xml version=\"1.0\"?><plist><dict/></plist>".utf8)
func app(_ extra: [Z] = [], top: String = "Sill.app") -> [Z] {
    [Z(name: "\(top)/", mode: 0o040755), Z(name: "\(top)/Contents/", mode: 0o040755),
     Z(name: "\(top)/Contents/Info.plist", data: plist, method: 0),
     Z(name: "\(top)/Contents/MacOS/", mode: 0o040755),
     Z(name: "\(top)/Contents/MacOS/Sill", data: exe, mode: 0o100755, descriptor: true)] + extra
}
func read(_ d: Data, limits: A.Limits = A.Limits()) -> Result<A.Listing, A.Problem> { A.read(d, top: "Sill.app", limits: limits) }
func archiveProblem(_ d: Data, limits: A.Limits = A.Limits()) -> A.Problem? { if case .failure(let p) = read(d, limits: limits) { return p }; return nil }
switch read(zip(app([Z(name: "Sill.app/Contents/Frameworks/", mode: 0o040755),
                     Z(name: "Sill.app/Contents/Frameworks/Current", data: Array("../MacOS".utf8), mode: 0o120755, method: 0),
                     Z(name: "Sill.app/Contents/._Info.plist", data: [1, 2, 3]),
                     Z(name: "__MACOSX/Sill.app/._Contents", data: [4, 5])]), comment: "a comment")) {
case .success(let l):
    check(l.entries.count == 7 && l.skipped == 2, "a good app: \(l.entries.map(\.path)), skipped \(l.skipped)")
    check(l.entries.map(\.path) == ["Sill.app", "Sill.app/Contents", "Sill.app/Contents/Info.plist", "Sill.app/Contents/MacOS",
                                    "Sill.app/Contents/MacOS/Sill", "Sill.app/Contents/Frameworks", "Sill.app/Contents/Frameworks/Current"], "the order")
    check(l.entries[4].kind == .file(executable: true) && l.entries[2].kind == .file(executable: false), "executable bits")
    check(l.entries[6].kind == .link(target: "../MacOS"), "the link")
    check(l.totalBytes == Int64(exe.count + plist.count + 8), "total \(l.totalBytes)")
    // Each entry unpacks to its bytes and CRC.
    let d = zip(app())
    if case .success(let l2) = read(d) {
        for e in l2.entries {
            guard case .file = e.kind else { continue }
            var made: [UInt8] = []
            d.withUnsafeBytes { all in
                let input = UnsafeRawBufferPointer(rebasing: all[e.dataOffset..<(e.dataOffset + e.compressedSize)])
                if e.method == 0 {
                    made = Array(input)
                } else if case .success(let c) = A.inflate(input, size: e.size, name: e.path, write: { made += Array($0); return true }) {
                    check(c == e.crc32, "the CRC of \(e.path)")
                } else { check(false, "inflate \(e.path)") }
            }
            check(made == (e.path.hasSuffix("Sill") ? exe : plist), "the bytes of \(e.path)")
        }
    }
case .failure(let p): check(false, "a good app: \(p)")
}
check("123456789".utf8.withContiguousStorageIfAvailable { A.crc32(UnsafeRawBufferPointer($0)) } == 0xCBF4_3926, "CRC-32 of 123456789")
let archiveCases: [(Data, A.Problem)] = [
    (Data("not a zip at all, just words".utf8), .notAZip),
    (Data(), .notAZip),
    (zip(app(), zip64Locator: true), .zip64),
    (zip(app([Z(name: "Sill.app/../evil", data: [1])])), .badName("Sill.app/../evil")),
    (zip(app([Z(name: "Sill.app/./x", data: [1])])), .badName("Sill.app/./x")),
    (zip(app([Z(name: "Sill.app//x", data: [1])])), .badName("Sill.app//x")),
    (zip(app([Z(name: "/etc/evil", data: [1])])), .badName("/etc/evil")),
    (zip(app([Z(name: "Sill.app/a\\b", data: [1])])), .badName("a name with a byte outside printable ASCII")),
    (zip(app([Z(name: "Sill.app/caf\u{e9}", data: [1])])), .badName("a name with a byte outside printable ASCII")),
    (zip(app([Z(name: "Other.app/x", data: [1])])), .notUnderTop("Other.app/x")),
    (zip(app([Z(name: "evil", data: [1])])), .notUnderTop("evil")),
    (zip(app([Z(name: "Sill.app/Contents/info.plist", data: [1])])), .duplicate("Sill.app/Contents/info.plist")),
    (zip(app([Z(name: "Sill.app/Contents/MacOS/Sill", data: [1])])), .duplicate("Sill.app/Contents/MacOS/Sill")),
    (zip(app([Z(name: "Sill.app/x", data: [1], madeBy: 0x0014)])), .notUnix("Sill.app/x")),
    (zip(app([Z(name: "Sill.app/x", data: [1], mode: 0o104755)])), .badMode("Sill.app/x", 0o104755)),
    (zip(app([Z(name: "Sill.app/x", data: [1], mode: 0o102755)])), .badMode("Sill.app/x", 0o102755)),
    (zip(app([Z(name: "Sill.app/x", data: [1], mode: 0o010644)])), .badMode("Sill.app/x", 0o010644)),
    (zip(app([Z(name: "Sill.app/x", data: [1], mode: 0o040755)])), .badMode("Sill.app/x", 0o040755)),
    (zip(app([Z(name: "Sill.app/x", data: [1], flags: 1)])), .encrypted("Sill.app/x")),
    (zip(app([Z(name: "Sill.app/x", data: [1], method: 12)])), .method("Sill.app/x", 12)),
    (zip(app([Z(name: "Sill.app/x", data: [1, 2, 3], localName: "Sill.app/y")])), .localMismatch("Sill.app/x")),
    (zip(app([Z(name: "Sill.app/x", data: [1, 2, 3], localMethod: 0)])), .localMismatch("Sill.app/x")),
    (zip(app([Z(name: "Sill.app/x", data: [1, 2, 3], method: 0, localSize: 2)])), .localMismatch("Sill.app/x")),
    (zip(app([Z(name: "Sill.app/x", data: [1, 2, 3], method: 0, size: 2)])), .badSizes("Sill.app/x")),
    (zip(app([Z(name: "Sill.app/link", data: Array("../../evil".utf8), mode: 0o120755, method: 0)])), .badLink("Sill.app/link")),
    (zip(app([Z(name: "Sill.app/link", data: Array("/etc".utf8), mode: 0o120755, method: 0)])), .badLink("Sill.app/link")),
    (zip(app([Z(name: "Sill.app/link", data: Array("Contents/missing".utf8), mode: 0o120755, method: 0)])), .badLink("Sill.app/link")),
    (zip(app([Z(name: "Sill.app/link", data: Array("..".utf8), mode: 0o120755, method: 0)])), .badLink("Sill.app/link")),
    (zip(app([Z(name: "Sill.app/link", data: Array("Contents".utf8), mode: 0o120755)])), .badLink("Sill.app/link")),
    (zip(app([Z(name: "Sill.app/link", data: Array("Contents".utf8), mode: 0o120755, method: 0),
              Z(name: "Sill.app/link/escape", data: [1])])), .throughLink("Sill.app/link/escape")),
    (zip(app([Z(name: "Sill.app/a", data: Array("Contents".utf8), mode: 0o120755, method: 0),
              Z(name: "Sill.app/b", data: Array("a".utf8), mode: 0o120755, method: 0)])), .throughLink("Sill.app/b")),
    (zip(app([Z(name: "Sill.app/Contents/Info.plist/x", data: [1])])), .underFile("Sill.app/Contents/Info.plist/x")),
    (zip([Z(name: "Sill.app", data: [1])]), .topNotFolder),
    (zip([Z(name: "Sill.app", data: Array("/Applications".utf8), mode: 0o120755, method: 0)]), .topNotFolder),
    (zip([Z(name: "Sill.app/", mode: 0o040755)]), .noTop),
    (zip(app([Z(name: "Sill.app/x", data: [1, 2, 3]), Z(name: "Sill.app/x", data: [1, 2, 3], reuse: 5)])), .overlap("Sill.app/x")),
    (zip(app([Z(name: "Sill.app/y", data: [1, 2, 3], reuse: 2)])), .localMismatch("Sill.app/y")),
]
for (d, expected) in archiveCases { check(archiveProblem(d) == expected, "archive: \(String(describing: archiveProblem(d))) instead of \(expected)") }
check(archiveProblem(zip(app([Z(name: "Sill.app/big", data: [UInt8](repeating: 0, count: 2_000_000))])), limits: A.Limits(totalBytes: 1_000_000)) == .tooLarge, "over the total")
check(archiveProblem(zip(app()), limits: A.Limits(entries: 3)) == .tooManyEntries(5), "too many entries")
// A bomb that lies: it says 100 bytes and inflates to two megabytes.
let bomb = zip(app([Z(name: "Sill.app/bomb", data: [UInt8](repeating: 0, count: 2_000_000), size: 100)]))
check(archiveProblem(bomb) == .badSizes("Sill.app/bomb") || archiveProblem(bomb) == nil, "a lying bomb: \(String(describing: archiveProblem(bomb)))")
if case .success(let l) = read(bomb), let e = l.entries.first(where: { $0.path == "Sill.app/bomb" }) {
    var made = 0
    let r = bomb.withUnsafeBytes { all in
        A.inflate(UnsafeRawBufferPointer(rebasing: all[e.dataOffset..<(e.dataOffset + e.compressedSize)]), size: e.size, name: e.path,
                  write: { made += $0.count; return true })
    }
    check(r == .failure(.inflate("Sill.app/bomb")) && made <= 100 + 65536, "inflating the lying bomb stops at its size: \(r), \(made)")
}
// An honest bomb over the ratio (a limit of 10 to 1 here; the real one is deflate's own, 1,100).
check(archiveProblem(zip(app([Z(name: "Sill.app/zeros", data: [UInt8](repeating: 0, count: 100_000))])), limits: A.Limits(ratio: 10)) == .badSizes("Sill.app/zeros"), "the ratio")
// A truncated deflate stream ends short of its size.
let short = deflate([UInt8](repeating: 7, count: 100_000)).dropLast(20)
let truncated: Result<UInt32, A.Problem> = Array(short).withUnsafeBytes { A.inflate($0, size: 100_000, name: "t", write: { _ in true }) }
check(truncated == .failure(.inflate("t")), "a truncated stream: \(truncated)")
let writeRefused: Result<UInt32, A.Problem> = deflate([1, 2, 3]).withUnsafeBytes { A.inflate($0, size: 3, name: "w", write: { _ in false }) }
check(writeRefused == .failure(.writeFailed("w")), "a refused write")
check(A.resolve("../MacOS", from: ["Sill.app", "Contents", "Frameworks"]) == ["Sill.app", "Contents", "MacOS"], "resolve")
check(A.resolve("../../../..", from: ["Sill.app", "Contents"]) == nil, "resolve above the root")
check(A.components(of: "a/b/", isDirectory: true) == ["a", "b"] && A.components(of: "a/b/", isDirectory: false) == nil, "components")

// MARK: The app's sources, as text (T21)

let sources = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Sources/SillMenuBar"
let files = ((try? FileManager.default.contentsOfDirectory(atPath: sources)) ?? []).filter { $0.hasSuffix(".swift") }
check(files.count > 10, "the app's sources at \(sources)")
func text(_ name: String) -> String { (try? String(contentsOfFile: sources + "/" + name, encoding: .utf8)) ?? "" }
func count(_ pattern: String, in s: String) -> Int {
    (try! NSRegularExpression(pattern: pattern)).numberOfMatches(in: s, range: NSRange(s.startIndex..., in: s))
}
for file in files {
    let s = text(file)
    let trusts = count("\\bTrust\\s*\\(", in: s), endpoints = count("\\bEndpoints\\s*\\(", in: s)
    if file == "UpdateInstallPolicy.swift" {
        check(trusts == 1 && endpoints == 1, "\(file) makes only Trust.release and Endpoints.github (\(trusts), \(endpoints))")
    } else {
        check(trusts == 0 && endpoints == 0, "\(file) makes a Trust or Endpoints of its own")
    }
    if file != "UpdateInstaller.swift" {
        check(count("\\bUpdateInstaller\\s*\\(", in: s) == (file == "AppUpdater.swift" ? 1 : 0), "\(file) makes an UpdateInstaller")
    }
}
let updater = text("AppUpdater.swift")
check(updater.contains("let trust = Policy.Trust.release") && updater.contains("UpdateInstaller(trust: trust, endpoints: .github,"),
      "AppUpdater gives the installer the two constants")
for file in ["UpdateInstallPolicy.swift", "UpdateManifest.swift", "UpdateArchive.swift", "UpdateInstaller.swift", "AppUpdater.swift"] {
    // Code only: a whole-line comment may name what the code never reads.
    let s = text(file).components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }.joined(separator: "\n")
    check(!s.isEmpty, "\(file) is there")
    for forbidden in ["UserDefaults", "NSUserDefaults", ".environment", ".arguments", "CommandLine", "getenv", "-Sill", "SILL_"] {
        check(!s.contains(forbidden), "\(file) reads \(forbidden)")
    }
}
check(text("UpdateManifest.swift").contains("static let releaseKeys: [String] = ["), "the key list is one literal")

print("update-install: \(checks - failures) of \(checks) checks passed")
exit(failures == 0 ? 0 : 1)
