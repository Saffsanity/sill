import CryptoKit
import Darwin
import Foundation
import Security

// Tests/update-harness (docs/one-click-update-plan.md §11, G2): UpdateInstaller driven for real, against
// the scratch layout run.sh made in argv[1] (apps/, zips/, srv/ with the stand-in's control.json, port,
// genuine/). The trust and endpoints here are the harness's own (a test identifier, 127.0.0.1, this run's
// update key); the genuine cases use Trust.release's every field but its keys. Every install target is
// under argv[1]: the harness refuses any other.
typealias P = UpdateInstallPolicy
typealias M = UpdateManifest
let out = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
let port = try! String(contentsOf: out.appendingPathComponent("port"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
let base = "http://127.0.0.1:\(port)"
var failures = 0, checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
func say(_ s: String) { print(s); fflush(stdout) }

let key = Curve25519.Signing.PrivateKey()
let otherKey = Curve25519.Signing.PrivateKey()
let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
let testTrust = P.Trust(signer: "identifier \"me.saffer.sill.updater-test\"", notarized: false, bundleName: "UpdTest.app", executable: "UpdTest",
                        identifier: "me.saffer.sill.updater-test", teamID: nil, stapledTicket: false, hardenedRuntime: true,
                        runningRequirement: false, entitlements: [], updateKeys: [publicKey])
func endpoints(asset: String) -> P.Endpoints {
    P.Endpoints(latestRelease: URL(string: base + "/repos/test/releases/latest")!, apiOrigins: [base], downloadPrefix: base + "/download/",
                assetName: asset, manifestName: asset + ".manifest", redirectOrigins: [base], redirectPathPrefix: "/assets/",
                maxRedirects: 3, minAssetBytes: 1024, maxAssetBytes: 64 << 20)
}
let testEndpoints = endpoints(asset: "UpdTest.zip")
let installer = UpdateInstaller(trust: testTrust, endpoints: testEndpoints, userAgent: "Sill/test")

// MARK: The stand-in's control, the release and its manifest

func sha256(_ url: URL) -> String { SHA256.hash(data: try! Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined() }
func cdhashes(_ app: URL) -> [String: String] {
    var d: [String: String] = [:]
    for arch in P.Architecture.allCases { if let h = UpdateInstaller.cdhash(of: app, arch: arch) { d[arch.rawValue] = h } }
    return d
}
struct Release {
    var tag = "v1.1"
    var zip: URL
    var asset = "UpdTest.zip"
    var app: URL                       // the app whose code the manifest names
    var build = "11"
    var manifestTag: String?           // another tag in the manifest
    var manifestSHA: String?           // another SHA-256 in the manifest
    var manifestSize: Int64?
    var apiDigest: String??            // nil: the zip's; .some(nil): none; .some(x): x
    var signer = key
    var tamperManifest = false
    var withManifest = true
    var modes: [String: String] = [:]
    var releaseStatus = 200
}
func publish(_ r: Release) {
    let fm = FileManager.default
    let assets = out.appendingPathComponent("srv/assets")
    try? fm.removeItem(at: assets)
    try! fm.createDirectory(at: assets, withIntermediateDirectories: true)
    try! fm.copyItem(at: r.zip, to: assets.appendingPathComponent(r.asset))
    let size = Int64(try! Data(contentsOf: r.zip).count)
    let sha = sha256(r.zip)
    let tag = r.manifestTag ?? r.tag
    let signedText = M.signedText(tag: tag, build: r.build, asset: r.asset, size: r.manifestSize ?? size, sha256: r.manifestSHA ?? sha,
                                  cdhashes: cdhashes(r.app), keyID: M.keyID(r.signer.publicKey.rawRepresentation))
    var manifest = M.document(signedText: signedText, signature: try! r.signer.signature(for: Data(signedText.utf8)))
    if r.tamperManifest { manifest = manifest.replacingOccurrences(of: "build \(r.build)", with: "build 99") }
    let manifestName = r.asset + ".manifest"
    try! Data(manifest.utf8).write(to: assets.appendingPathComponent(manifestName))
    var list: [[String: Any]] = [["name": r.asset, "size": size, "state": "uploaded",
                                  "browser_download_url": "\(base)/download/\(r.tag)/\(r.asset)"]]
    switch r.apiDigest {
    case nil: list[0]["digest"] = "sha256:" + sha
    case .some(let d?): list[0]["digest"] = d
    case .some(nil): break
    }
    if r.withManifest {
        list.append(["name": manifestName, "size": manifest.utf8.count, "state": "uploaded",
                     "browser_download_url": "\(base)/download/\(r.tag)/\(manifestName)"])
    }
    let control: [String: Any] = ["release": ["tag_name": r.tag, "draft": false, "prerelease": false, "assets": list,
                                              "html_url": "\(base)/releases/tag/\(r.tag)"],
                                  "releaseStatus": r.releaseStatus, "modes": r.modes]
    try! JSONSerialization.data(withJSONObject: control).write(to: out.appendingPathComponent("srv/control.json"))
}

// MARK: One update, as AppUpdater runs it

func treeHash(_ url: URL) -> String {
    let fm = FileManager.default
    var lines: [String] = []
    if let e = fm.enumerator(atPath: url.path) {
        for case let rel as String in e {
            let path = url.path + "/" + rel
            var s = stat()
            lstat(path, &s)
            var line = "\(rel) \(s.st_mode) \(s.st_size)"
            if s.st_mode & S_IFMT == S_IFREG, let d = fm.contents(atPath: path) { line += " " + SHA256.hash(data: d).description }
            lines.append(line)
        }
    }
    return SHA256.hash(data: Data(lines.sorted().joined(separator: "\n").utf8)).description
}
func version(of app: URL) -> String? {
    (NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) as? [String: Any])?["CFBundleShortVersionString"] as? String
}
/// A fresh "installed" copy for a case: apps/installed (1.0) or a genuine variant, under cases/<name>/Applications.
func installedCopy(_ name: String, from source: URL) -> URL {
    let dir = out.appendingPathComponent("cases/\(name)/Applications")
    try? FileManager.default.removeItem(at: dir)
    try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let dest = dir.appendingPathComponent(source.lastPathComponent)
    let rc = Process.runTool("/usr/bin/ditto", [source.path, dest.path])
    precondition(rc == 0 && dest.path.hasPrefix(out.path + "/"), "the installed copy is the harness's")
    return dest
}
extension Process {
    static func runTool(_ tool: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        try! p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }
}

struct Outcome {
    var failure: P.Failure?
    var installed: URL
    var staging: URL?
    var staged: URL?
}
enum Tamper { case none, stagedResource, wrongRunningCDHash }

/// prepare, staging, download, unpack, check, install: the first failure, or none (the new copy in place).
func update(_ name: String, using ins: UpdateInstaller = installer, installedFrom: URL? = nil, offeredTag: String = "v1.1",
            running: SillVersion = SillVersion("1.0")!, runningRequirement: SecRequirement? = nil, tamper: Tamper = .none,
            holdBundle: Bool = false) async -> Outcome {
    let installed = installedCopy(name, from: installedFrom ?? out.appendingPathComponent("apps/installed/UpdTest.app"))
    var o = Outcome(failure: nil, installed: installed)
    // In Sill.app, Bundle.main is the installed copy, its Info.plist read long before the swap. With holdBundle an
    // NSBundle and a CFBundle for the path, each with its Info.plist read, live across the swap, so a check after it
    // that read a cached bundle would see the old version and fail.
    let heldBundle = holdBundle ? Bundle(url: installed) : nil
    let heldCF = holdBundle ? CFBundleCreate(nil, installed as CFURL) : nil
    if holdBundle {
        check((heldBundle?.infoDictionary?["CFBundleShortVersionString"] as? String) != nil, "\(name): the held NSBundle read its Info.plist")
        check(heldCF.flatMap { CFBundleGetInfoDictionary($0) } != nil, "\(name): the held CFBundle read its Info.plist")
    }
    defer {
        if holdBundle {
            let nsVersion = heldBundle?.infoDictionary?["CFBundleShortVersionString"] as? String ?? "none"
            let cfVersion = heldCF.flatMap { (CFBundleGetInfoDictionary($0) as? [String: Any])?["CFBundleShortVersionString"] as? String } ?? "none"
            say("\(name): after the swap the held NSBundle says \(nsVersion), the held CFBundle \(cfVersion), Security's read \(ins.facts(of: installed, runningRequirement: nil).plist["CFBundleShortVersionString"] ?? "none")")
        }
    }
    let cancel = UpdateInstaller.Cancel()
    let prepared: (release: P.Release, manifest: UpdateManifest)
    switch await ins.prepare(offeredTag: offeredTag, running: running, cancel: cancel) {
    case .failure(let f): o.failure = f; return o
    case .success(let p): prepared = p
    }
    let staging: URL
    switch UpdateInstaller.makeStaging(for: installed) {
    case .failure(let f): o.failure = f; return o
    case .success(let s): staging = s
    }
    o.staging = staging
    let zip: URL
    switch await ins.download(prepared.release, manifest: prepared.manifest, into: staging, progress: { _, _ in }, cancel: cancel) {
    case .failure(let f): o.failure = f; return o
    case .success(let z): zip = z
    }
    let staged: URL
    switch ins.unpack(zip, manifest: prepared.manifest, into: staging, cancel: cancel) {
    case .failure(let f): o.failure = f; return o
    case .success(let a): staged = a
    }
    o.staged = staged
    let checked: P.Checked
    switch ins.check(staged, manifest: prepared.manifest, running: running, runningRequirement: runningRequirement) {
    case .failure(let f): o.failure = f; return o
    case .success(let c): checked = c
    }
    if tamper == .stagedResource {
        let note = ["Contents/Resources/note.txt", "Contents/Resources/AppIcon.icns"].map { staged.appendingPathComponent($0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }!
        let h = try! FileHandle(forWritingTo: note); h.seekToEndOfFile(); h.write(Data("changed between the check and the swap".utf8)); h.closeFile()
    }
    let runningCDHash = tamper == .wrongRunningCDHash ? String(repeating: "0", count: 40) : (UpdateInstaller.cdhash(of: installed, arch: .current) ?? "")
    switch ins.install(staged: staged, installed: installed, runningCDHash: runningCDHash, expected: checked, manifest: prepared.manifest,
                       running: running, runningRequirement: runningRequirement) {
    case .failure(let f): o.failure = f
    case .success: break
    }
    return o
}

/// A case that must be refused for `expected`, the installed copy unchanged and nothing left outside.
func refused(_ name: String, _ r: Release, offeredTag: String = "v1.1", running: SillVersion = SillVersion("1.0")!,
             using ins: UpdateInstaller = installer, installedFrom: URL? = nil, runningRequirement: SecRequirement? = nil,
             tamper: Tamper = .none, _ expected: (P.Failure) -> Bool) async {
    publish(r)
    let source = installedFrom ?? out.appendingPathComponent("apps/installed/UpdTest.app")
    let before = treeHash(source)
    let o = await update(name, using: ins, installedFrom: installedFrom, offeredTag: offeredTag, running: running,
                         runningRequirement: runningRequirement, tamper: tamper)
    check(o.failure.map(expected) == true, "\(name): \(o.failure.map { P.logText($0) } ?? "installed") — not the expected refusal")
    check(treeHash(o.installed) == before, "\(name): the installed copy changed")
    say("\(name): refused (\(o.failure.map { P.logText($0) } ?? "nothing")), the installed copy unchanged")
    if let s = o.staging { UpdateInstaller.remove(s) }
}

/// A case that must install: the new version at the path, its code the manifest's, the old copy whole in staging.
func installs(_ name: String, _ r: Release, expectVersion: String = "1.1", using ins: UpdateInstaller = installer,
              installedFrom: URL? = nil, offeredTag: String = "v1.1", running: SillVersion = SillVersion("1.0")!,
              runningRequirement: SecRequirement? = nil, keepStaging: Bool = false, holdBundle: Bool = false) async -> Outcome {
    publish(r)
    let before = treeHash(installedFrom ?? out.appendingPathComponent("apps/installed/UpdTest.app"))
    let o = await update(name, using: ins, installedFrom: installedFrom, offeredTag: offeredTag, running: running,
                         runningRequirement: runningRequirement, holdBundle: holdBundle)
    check(o.failure == nil, "\(name): \(o.failure.map { P.logText($0) } ?? "")")
    check(version(of: o.installed) == expectVersion, "\(name): the installed version is \(version(of: o.installed) ?? "none")")
    check(cdhashes(o.installed) == cdhashes(r.app), "\(name): the installed code is the manifest's")
    if let staged = o.staged {
        check(treeHash(staged) == before, "\(name): the old copy is in staging, whole")
    }
    say("\(name): installed \(version(of: o.installed) ?? "?")")
    if !keepStaging, let s = o.staging { UpdateInstaller.remove(s) }
    return o
}

func zip(_ label: String) -> URL { out.appendingPathComponent("zips/\(label).zip") }
func app(_ label: String) -> URL { out.appendingPathComponent("apps/\(label)/UpdTest.app") }
let v11 = Release(zip: zip("v1.1"), app: app("v1.1"))

// MARK: The cases

say("== installs")
var o = await installs("ditto zip (AppleDouble beside its files)", v11, keepStaging: true)
// The old copy can be put back by the same exchange.
let oldCode = UpdateInstaller.cdhash(of: app("installed"), arch: .current)!
if let staged = o.staged {
    check(!installer.putBack(staged: staged, installed: o.installed, old: String(repeating: "0", count: 40)) && version(of: o.installed) == "1.1",
          "no put back when the copy in staging is not the old code")
    check(installer.putBack(staged: staged, installed: o.installed, old: oldCode) && version(of: o.installed) == "1.0", "put back: 1.0 at the path again")
    UpdateInstaller.remove(o.staging!)
}
// What waits in staging was replaced (by anything of this user) after the swap: never carried into place.
o = await installs("a swap, then the old copy replaced in staging", v11, keepStaging: true)
if let staged = o.staged {
    try? FileManager.default.removeItem(at: staged)
    _ = Process.runTool("/usr/bin/ditto", [app("other").path, staged.path])
    check(!installer.putBack(staged: staged, installed: o.installed, old: oldCode) && version(of: o.installed) == "1.1",
          "another bundle in staging is not put back: the checked new copy stays")
    UpdateInstaller.remove(o.staging!)
}
o = await installs("zipfile zip", Release(zip: zip("hostile-plain"), app: app("v1.1")))
o = await installs("AppleDouble entries skipped", Release(zip: zip("hostile-appledouble"), app: app("v1.1")), keepStaging: true)
let leftovers = (FileManager.default.enumerator(atPath: o.installed.path)?.allObjects as? [String] ?? []).filter { $0.contains("._") || $0.contains("__MACOSX") }
check(leftovers.isEmpty, "no AppleDouble file written: \(leftovers)")
if let s = o.staging { UpdateInstaller.remove(s) }
o = await installs("a redirect to the asset host", { var r = v11; r.modes = ["UpdTest.zip": "redirect-same", "UpdTest.zip.manifest": "redirect-same"]; return r }())
o = await installs("no digest from GitHub (the manifest's alone)", { var r = v11; r.apiDigest = .some(nil); return r }())
o = await installs("a bundle held for the path across the swap (Bundle.main)", v11, holdBundle: true)

say("== refused: the release and its manifest")
await refused("missing manifest", { var r = v11; r.withManifest = false; return r }()) { $0 == .notSigned }
await refused("manifest by another key", { var r = v11; r.signer = otherKey; return r }()) { if case .manifest(.unknownKey) = $0 { return true }; return false }
await refused("manifest changed after signing", { var r = v11; r.tamperManifest = true; return r }()) { $0 == .manifest(.badSignature) }
await refused("manifest of another tag", { var r = v11; r.manifestTag = "v1.2"; return r }()) { $0 == .manifestMismatch("tag") }
await refused("GitHub's digest not the manifest's", { var r = v11; r.apiDigest = .some("sha256:" + String(repeating: "0", count: 64)); return r }()) { $0 == .manifestMismatch("sha256") }
await refused("the manifest's SHA-256 not the zip's", { var r = v11; r.manifestSHA = String(repeating: "1", count: 64); r.apiDigest = .some(nil); return r }()) { $0 == .hashMismatch }
await refused("a lower version", Release(tag: "v0.9", zip: zip("v0.9"), app: app("v0.9"), build: "9"), offeredTag: "v0.9") { $0 == .releaseNotNewer }
await refused("the same version", Release(tag: "v1.0", zip: zip("v1.1"), app: app("v1.1"), build: "11"), offeredTag: "v1.0") { $0 == .releaseNotNewer }
await refused("another release than offered", v11, offeredTag: "v1.2") { $0 == .releaseChanged(tag: "v1.1") }
await refused("the release request answered 404", { var r = v11; r.releaseStatus = 404; return r }()) { $0 == .github(404) }

say("== refused: the download")
await refused("a redirect to another host", { var r = v11; r.modes = ["UpdTest.zip": "redirect-other"]; return r }()) { $0 == .redirectRefused("http://localhost:\(port)") }
await refused("a redirect to another path", { var r = v11; r.modes = ["UpdTest.zip": "redirect-path"]; return r }()) { $0 == .redirectRefused(base) }
await refused("redirects without end", { var r = v11; r.modes = ["UpdTest.zip": "redirect-loop"]; return r }()) { $0 == .redirectRefused(base) }
await refused("a truncated download", { var r = v11; r.modes = ["UpdTest.zip": "truncate"]; return r }()) { if case .download = $0 { return true }; return $0 == .sizeMismatch }
await refused("a Content-Length too large", { var r = v11; r.modes = ["UpdTest.zip": "oversize"]; return r }()) { $0 == .sizeMismatch }
await refused("more bytes than the manifest says", { var r = v11; r.modes = ["UpdTest.zip": "nolength"]; return r }()) { $0 == .tooLarge }
await refused("the zip answered 500", { var r = v11; r.modes = ["UpdTest.zip": "status:500"]; return r }()) { $0 == .github(500) }
await refused("a server asking for a password", { var r = v11; r.modes = ["UpdTest.zip": "auth"]; return r }()) {
    $0 == .download("the server asked for a credential, which Sill never sends") || $0 == .github(401)
}

say("== refused: the archive")
await refused("a name under ../", Release(zip: zip("hostile-traversal"), app: app("v1.1"))) { if case .archive(.badName) = $0 { return true }; return false }
await refused("an absolute name", Release(zip: zip("hostile-absolute"), app: app("v1.1"))) { if case .archive(.badName) = $0 { return true }; return false }
await refused("a link out of the app, written through", Release(zip: zip("hostile-link-escape"), app: app("v1.1"))) {
    if case .archive(.badLink) = $0 { return true }; if case .archive(.throughLink) = $0 { return true }; return false
}
await refused("Info.plist and info.plist", Release(zip: zip("hostile-case-duplicate"), app: app("v1.1"))) { if case .archive(.duplicate) = $0 { return true }; return false }
await refused("a setuid executable", Release(zip: zip("hostile-setuid"), app: app("v1.1"))) { if case .archive(.badMode) = $0 { return true }; return false }
await refused("UpdTest.app is a file", Release(zip: zip("hostile-not-a-bundle"), app: app("v1.1"))) { $0 == .archive(.topNotFolder) }
await refused("a second top-level folder", Release(zip: zip("hostile-second-top"), app: app("v1.1"))) { if case .archive(.notUnderTop) = $0 { return true }; return false }
for path in ["escaped.txt", "cases/escaped.txt", "outside", "cases/outside"] {
    check(!FileManager.default.fileExists(atPath: out.appendingPathComponent(path).path), "nothing written outside: \(path)")
}
check(!FileManager.default.fileExists(atPath: "/tmp/update-harness-absolute.txt"), "nothing written at /tmp")

say("== refused: the bundle")
await refused("another identifier", Release(zip: zip("other"), app: app("other"))) { $0 == .bundle(.wrongSigner) }
await refused("a resource changed after signing", Release(zip: zip("tampered-resource"), app: app("tampered-resource"))) {
    if case .bundle(.invalidSignature) = $0 { return true }; return false
}
await refused("the executable changed after signing", Release(zip: zip("tampered-executable"), app: app("v1.1"))) {
    if case .bundle(.invalidSignature) = $0 { return true }; return false
}
await refused("a version that is not the tag's", Release(zip: zip("v1.2"), app: app("v1.2"), build: "12")) { $0 == .bundle(.notManifest("version")) }
await refused("code the manifest doesn't name", Release(zip: zip("v1.1b"), app: app("v1.1"))) { $0 == .bundle(.notManifest("code")) }

say("== refused: the swap")
await refused("changed between the check and the swap", v11, tamper: .stagedResource) {
    if case .checkAfterSwap(.invalidSignature, putBack: true) = $0 { return true }; return false
}
await refused("the copy at the path is not the running one", v11, tamper: .wrongRunningCDHash) { $0 == .changedSinceStart }

say("== the requests GitHub would have seen")
let log = (try? String(contentsOf: out.appendingPathComponent("srv/requests.log"), encoding: .utf8)) ?? ""
let requests = log.split(separator: "\n")
check(!requests.isEmpty, "requests were made")
check(requests.allSatisfy { $0.contains("ua=Sill/test") }, "every request carries Sill's User-Agent")
check(requests.allSatisfy { $0.contains("auth=no") && $0.contains("cookie=no") }, "no credential and no cookie, ever (a 401 asked for one)")
check(requests.filter { $0.contains("/download/v1.1/UpdTest.zip") }.count >= 1, "the zip was asked for")
check(!requests.contains { $0.contains("host=localhost") }, "no request followed the redirect to another host")
check(!requests.contains { $0.contains("/elsewhere/") }, "no request followed the redirect to another path")
say("\(requests.count) requests, every one with Sill/test, none with a credential or a cookie")

say("== a running copy's code (the launch check)")
let running = installedCopy("running", from: app("installed"))
let child = Process()
child.executableURL = running.appendingPathComponent("Contents/MacOS/UpdTest")
child.arguments = ["sleep", "20"]
try! child.run()
let childHash = UpdateInstaller.cdhash(of: running, arch: .current)!
var ready = false
for _ in 0..<50 where !ready {
    ready = UpdateInstaller.process(child.processIdentifier, satisfies: "identifier \"me.saffer.sill.updater-test\" and cdhash H\"\(childHash)\"")
    if !ready { usleep(100_000) }
}
check(ready, "the running process satisfies its identifier and cdhash")
check(!UpdateInstaller.process(child.processIdentifier, satisfies: "identifier \"me.saffer.sill.updater-test\" and cdhash H\"\(String(repeating: "0", count: 40))\""), "another cdhash")
check(!UpdateInstaller.process(child.processIdentifier, satisfies: P.pinnedRequirement), "the test app is not Sill")

say("== where an app runs (the refusals' facts)")
var s = UpdateInstaller.situation(bundle: running, executable: "UpdTest", runningIsRelease: true, testFeed: false, runningIsInstalled: true, neededBytes: 1 << 20)
check(!s.bundleIsLink && !s.translocated && !s.readOnlyVolume && !s.networkVolume && !s.diskImage && s.folderWritable && s.bundleWritable && s.ownedByUser,
      "a scratch copy: writable, local, owned: \(s)")
check(s.otherInstances == 1 && s.otherAccounts.isEmpty, "a process running from it: \(s.otherInstances), \(s.otherAccounts)")
check(P.refusal(s) == .otherInstance, "refused while it runs")
child.terminate()
child.waitUntilExit()
s = UpdateInstaller.situation(bundle: running, executable: "UpdTest", runningIsRelease: true, testFeed: false, runningIsInstalled: true, neededBytes: 1 << 20)
check(s.otherInstances == 0 && P.refusal(s) == nil, "nothing running from it: no refusal")
let folder = running.deletingLastPathComponent()
chmod(folder.path, 0o555)
s = UpdateInstaller.situation(bundle: running, executable: "UpdTest", runningIsRelease: true, testFeed: false, runningIsInstalled: true, neededBytes: 1 << 20)
check(!s.folderWritable && P.refusal(s) == .notWritable(folder.path), "a folder this account can't change")
chmod(folder.path, 0o755)
let link = folder.appendingPathComponent("Link.app")
try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: running)
s = UpdateInstaller.situation(bundle: link, executable: "UpdTest", runningIsRelease: true, testFeed: false, runningIsInstalled: true, neededBytes: 1 << 20)
check(s.bundleIsLink && P.refusal(s) == .link(link.path), "a link to the app")
s = UpdateInstaller.situation(bundle: running, executable: "UpdTest", runningIsRelease: true, testFeed: false, runningIsInstalled: true, neededBytes: Int64.max)
check(P.refusal(s).map { if case .lowSpace = $0 { return true }; return false } == true, "not enough space")
// A disk image, writable then read-only (hdiutil, in the scratch folder, never browsable).
let image = out.appendingPathComponent("image.dmg"), mount = out.appendingPathComponent("mnt-image")
try? FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
if Process.runTool("/usr/bin/hdiutil", ["create", "-quiet", "-size", "16m", "-fs", "APFS", "-volname", "UpdHarness", image.path]) == 0 {
    for readOnly in [false, true] {
        var args = ["attach", "-quiet", "-nobrowse", "-noverify", "-mountpoint", mount.path, image.path]
        if readOnly { args.insert("-readonly", at: 1) }
        guard Process.runTool("/usr/bin/hdiutil", args) == 0 else { check(false, "hdiutil attach"); continue }
        let onImage = mount.appendingPathComponent("UpdTest.app")
        if !readOnly { _ = Process.runTool("/usr/bin/ditto", [app("installed").path, onImage.path]) }
        let t = UpdateInstaller.situation(bundle: onImage, executable: "UpdTest", runningIsRelease: true, testFeed: false, runningIsInstalled: true, neededBytes: 1 << 20)
        check(t.diskImage, "a disk image is seen as one (read-only \(readOnly))")
        check(t.readOnlyVolume == readOnly, "read-only: \(t.readOnlyVolume)")
        check(P.refusal(t) == .diskImage, "refused on a disk image")
        say("disk image, read-only \(readOnly): \(t.diskImage ? "seen" : "NOT seen"), refusal \(String(describing: P.refusal(t)))")
        _ = Process.runTool("/usr/bin/hdiutil", ["detach", "-quiet", mount.path])
    }
} else {
    say("note: hdiutil could not make a disk image here; the disk image facts were not tried")
}

say("== staging")
let probe = installedCopy("staging", from: app("installed"))
var made: [URL] = []
for _ in 0..<3 { if case .success(let d) = UpdateInstaller.makeStaging(for: probe) { made.append(d) } }
check(made.count == 3 && Set(made.map(\.path)).count == 3, "three staging folders, each new")
for d in made {
    var st = stat()
    lstat(d.path, &st)
    check(st.st_mode & 0o777 == 0o700 && st.st_uid == getuid(), "0700 and this user's: \(String(st.st_mode & 0o777, radix: 8))")
}
UpdateInstaller.markKept(made[1], path: made[1].appendingPathComponent("UpdTest.app").path)
let removed = UpdateInstaller.cleanUpStaging(for: probe, keep: made[0])
check(Set(removed) == Set([made[2].path]), "only the unmarked other removed: \(removed)")
check(FileManager.default.fileExists(atPath: made[0].path) && FileManager.default.fileExists(atPath: made[1].path),
      "the kept one and the one holding a copy not put back are there")
UpdateInstaller.remove(made[0])
UpdateInstaller.remove(made[1])

// MARK: The genuine Sill 0.6.1 under Trust.release (with this run's key)

let g = out.appendingPathComponent("genuine")
if FileManager.default.fileExists(atPath: g.appendingPathComponent("plain.zip").path) {
    say("== the genuine v0.6.1, under Trust.release's every rule (this run's update key)")
    let r = P.Trust.release
    func releaseTrust(signer: String = P.pinnedRequirement) -> P.Trust {
        P.Trust(signer: signer, notarized: r.notarized, bundleName: r.bundleName, executable: r.executable, identifier: r.identifier,
                teamID: r.teamID, stapledTicket: r.stapledTicket, hardenedRuntime: r.hardenedRuntime, runningRequirement: r.runningRequirement,
                entitlements: r.entitlements, updateKeys: [publicKey])
    }
    let sillEndpoints = endpoints(asset: "Sill.zip")
    let real = UpdateInstaller(trust: releaseTrust(), endpoints: sillEndpoints, userAgent: "Sill/test")
    var sillDR: SecRequirement?
    SecRequirementCreateWithString("identifier \"me.saffer.sill.mac\" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = \"9B2KKVM937\"" as CFString, [], &sillDR)
    var appleOnly: SecRequirement?
    SecRequirementCreateWithString("identifier \"me.saffer.sill.mac\" and anchor apple" as CFString, [], &appleOnly)
    let plainApp = g.appendingPathComponent("plain/Sill.app"), installedSill = g.appendingPathComponent("installed/Sill.app")
    let codes = cdhashes(plainApp)
    check(codes.keys.sorted() == ["arm64", "x86_64"], "the release is universal: \(codes)")
    // The signer reads each slice's cdhash with codesign; Update Now with Security: the same values.
    for (arch, hash) in codes {
        let p = Process(), pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        p.arguments = ["-dvvv", "--arch", arch, plainApp.path]
        p.standardError = pipe
        p.standardOutput = pipe
        try! p.run()
        p.waitUntilExit()
        let text = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        check(text.contains("CDHash=\(hash)\n"), "codesign's CDHash for \(arch) is Update Now's \(hash)")
    }
    say("genuine cdhashes: \(codes)")
    let genuine = Release(tag: "v0.6.1", zip: g.appendingPathComponent("plain.zip"), asset: "Sill.zip", app: plainApp, build: "1388")
    _ = await installs("genuine 0.6.1 over 0.6.0", genuine, expectVersion: "0.6.1", using: real, installedFrom: installedSill, offeredTag: "v0.6.1",
                       running: SillVersion("0.6.0")!, runningRequirement: sillDR, holdBundle: true)
    await refused("genuine, the same version running", genuine, offeredTag: "v0.6.1", running: SillVersion("0.6.1")!, using: real,
                  installedFrom: installedSill, runningRequirement: sillDR) { $0 == .releaseNotNewer }
    await refused("genuine, tagged v0.6.2", { var x = genuine; x.tag = "v0.6.2"; return x }(), offeredTag: "v0.6.2", running: SillVersion("0.6.0")!,
                  using: real, installedFrom: installedSill, runningRequirement: sillDR) { $0 == .bundle(.notManifest("version")) }
    let otherTeam = UpdateInstaller(trust: releaseTrust(signer: P.pinnedRequirement.replacingOccurrences(of: "9B2KKVM937", with: "ABCDE12345")),
                                    endpoints: sillEndpoints, userAgent: "Sill/test")
    await refused("genuine, another team pinned", genuine, offeredTag: "v0.6.1", running: SillVersion("0.6.0")!, using: otherTeam,
                  installedFrom: installedSill, runningRequirement: sillDR) { $0 == .bundle(.wrongSigner) }
    await refused("genuine, the running requirement Apple's own", genuine, offeredTag: "v0.6.1", running: SillVersion("0.6.0")!, using: real,
                  installedFrom: installedSill, runningRequirement: appleOnly) { $0 == .bundle(.wouldLosePermissions) }
    for (variant, expected) in [("tampered", "invalidSignature"), ("adhoc", "wrongSigner"), ("unstapled", "noStapledTicket")] {
        let x = Release(tag: "v0.6.1", zip: g.appendingPathComponent("\(variant).zip"), asset: "Sill.zip",
                        app: g.appendingPathComponent("\(variant)/Sill.app"), build: "1388")
        await refused("genuine, \(variant)", x, offeredTag: "v0.6.1", running: SillVersion("0.6.0")!, using: real, installedFrom: installedSill,
                      runningRequirement: sillDR) {
            switch ($0, expected) {
            case (.bundle(.invalidSignature), "invalidSignature"), (.bundle(.wrongSigner), "wrongSigner"), (.bundle(.noStapledTicket), "noStapledTicket"): return true
            default: return false
            }
        }
    }
    let wrongCode = Release(tag: "v0.6.1", zip: g.appendingPathComponent("plain.zip"), asset: "Sill.zip", app: g.appendingPathComponent("adhoc/Sill.app"), build: "1388")
    await refused("genuine, a manifest naming other code", wrongCode, offeredTag: "v0.6.1", running: SillVersion("0.6.0")!, using: real,
                  installedFrom: installedSill, runningRequirement: sillDR) { $0 == .bundle(.notManifest("code")) }
} else {
    say("note: no genuine v0.6.1 zip in .build/updater-scratch; the genuine cases were not run")
}

say("update-harness: \(checks - failures) of \(checks) checks passed")
exit(failures == 0 ? 0 : 1)
