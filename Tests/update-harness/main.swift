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
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())"); fflush(stdout) }
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
                assetName: asset, manifestName: asset + ".manifest", stopName: asset + ".stop", redirectOrigins: [base], redirectPathPrefix: "/assets/",
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
    var signedAt = Date()
    var tamperManifest = false
    var withManifest = true
    var modes: [String: String] = [:]
    var releaseStatus = 200
    /// A stop beside the release (review 3, the automatic update's point 1): naming it, naming another
    /// release, signed with a key the Sill doesn't know, or not a stop at all.
    var stop: StopKind?
}
enum StopKind { case this, otherRelease, otherKey, garbage }
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
                                  cdhashes: cdhashes(r.app), signedAt: r.signedAt, keyID: M.keyID(r.signer.publicKey.rawRepresentation))
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
    if let kind = r.stop {
        let stopName = r.asset + ".stop"
        let signer = kind == .otherKey ? otherKey : r.signer
        let text = M.stopText(tag: kind == .otherRelease ? "v1.0.9" : tag, sha256: sha, signedAt: Date(),
                              keyID: M.keyID(signer.publicKey.rawRepresentation))
        let doc = kind == .garbage ? "not a stop\n" : M.document(signedText: text, signature: try! signer.signature(for: Data(text.utf8)))
        try! Data(doc.utf8).write(to: assets.appendingPathComponent(stopName))
        list.append(["name": stopName, "size": doc.utf8.count, "state": "uploaded",
                     "browser_download_url": "\(base)/download/\(r.tag)/\(stopName)"])
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
/// stagedResource: the checked new copy changed in staging after the check, before install (the check right
/// before the swap refuses it). raced: changed between that last check and the swap (`beforeSwap`, the race
/// review 3's F5 names): the check after the swap catches it and the old copy goes back. both: raced, and the
/// installed (old) copy's resource changed before too, so it is not the old copy whole once it waits in
/// staging. hardLink: a file of the new copy given a second name before the check (N4). signatureLink: its
/// CodeResources made a link before the check (F6). swapFails: the swap itself fails (the folder made
/// read-only at the last moment), the leftover note already written (N5). wrongRunningCDHash: the copy at the
/// path is not the running one. atNote: changed the moment the leftover note is written (the second security
/// pass's R3: the note comes before the last check, so a change it sets off is caught there, before the swap).
enum Tamper { case none, stagedResource, raced, both, hardLink, signatureLink, swapFails, wrongRunningCDHash, atNote }

/// prepare, staging, download, unpack, check, install: the first failure, or none (the new copy in place).
func update(_ name: String, using ins: UpdateInstaller = installer, installedFrom: URL? = nil, offeredTag: String = "v1.1",
            running: SillVersion = SillVersion("1.0")!, runningRequirement: SecRequirement? = nil, tamper: Tamper = .none,
            holdBundle: Bool = false, leftoverNote: URL? = nil) async -> Outcome {
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
    func resource(_ bundle: URL) -> URL {
        ["Contents/Resources/note.txt", "Contents/Resources/AppIcon.icns"].map { bundle.appendingPathComponent($0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }!
    }
    func append(_ bundle: URL, _ text: String) {
        let h = try! FileHandle(forWritingTo: resource(bundle)); h.seekToEndOfFile(); h.write(Data(text.utf8)); h.closeFile()
    }
    if tamper == .hardLink {
        let other = out.appendingPathComponent("cases/\(name)/other-name")
        try? FileManager.default.removeItem(at: other)
        precondition(Darwin.link(resource(staged).path, other.path) == 0, "a hard link")
    }
    if tamper == .signatureLink {
        let resources = staged.appendingPathComponent("Contents/_CodeSignature/CodeResources")
        precondition(FileManager.default.fileExists(atPath: resources.path), "the test app has a CodeResources")
        try! FileManager.default.removeItem(at: resources)
        try! FileManager.default.createSymbolicLink(atPath: resources.path, withDestinationPath: "../Info.plist")
    }
    let checked: P.Checked
    switch ins.check(staged, manifest: prepared.manifest, running: running, runningRequirement: runningRequirement) {
    case .failure(let f): o.failure = f; return o
    case .success(let c): checked = c
    }
    if tamper == .stagedResource { append(staged, "changed after the check, before install") }
    // A resource changes nothing of the cdhash (it is read from the executable's signature): the copy at the
    // path still reads as the running code, and only validation tells it isn't whole.
    if tamper == .both { append(installed, "the old copy changed before the swap") }
    let folder = installed.deletingLastPathComponent()
    let race: (() -> Void)? = switch tamper {
    case .raced, .both: { append(staged, "changed between the last check and the swap") }
    case .swapFails: { chmod(folder.path, 0o555) }
    default: nil
    }
    let runningCDHash = tamper == .wrongRunningCDHash ? String(repeating: "0", count: 40) : (UpdateInstaller.cdhash(of: installed, arch: .current) ?? "")
    let atNote: (() -> Void)? = tamper == .atNote ? { append(staged, "changed when the leftover note appeared") } : nil
    switch ins.install(staged: staged, installed: installed, runningCDHash: runningCDHash, expected: checked, manifest: prepared.manifest,
                       running: running, runningRequirement: runningRequirement, leftoverNote: leftoverNote, afterNote: atNote, beforeSwap: race) {
    case .failure(let f): o.failure = f
    case .success: break
    }
    if tamper == .swapFails { chmod(folder.path, 0o755) }
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
    check(installer.putBack(staged: staged, installed: o.installed, old: String(repeating: "0", count: 40)) == .notTheOldCopy
          && version(of: o.installed) == "1.1", "no put back when the copy in staging is not the old code")
    check(installer.putBack(staged: staged, installed: o.installed, old: oldCode) == .done && version(of: o.installed) == "1.0",
          "put back: 1.0 at the path again")
    UpdateInstaller.remove(o.staging!)
}
// What waits in staging was replaced (by anything of this user) after the swap: never carried into place.
o = await installs("a swap, then the old copy replaced in staging", v11, keepStaging: true)
if let staged = o.staged {
    try? FileManager.default.removeItem(at: staged)
    _ = Process.runTool("/usr/bin/ditto", [app("other").path, staged.path])
    check(installer.putBack(staged: staged, installed: o.installed, old: oldCode) == .notTheOldCopy && version(of: o.installed) == "1.1",
          "another bundle in staging is not put back: the checked new copy stays")
    UpdateInstaller.remove(o.staging!)
}
// The old copy changed in staging where its cdhash can't tell (a resource): not whole, so not put back.
o = await installs("a swap, then a resource of the old copy changed in staging", v11, keepStaging: true)
if let staged = o.staged {
    let note = staged.appendingPathComponent("Contents/Resources/note.txt")
    let h = try! FileHandle(forWritingTo: note); h.seekToEndOfFile(); h.write(Data("changed in staging".utf8)); h.closeFile()
    check(UpdateInstaller.cdhash(of: staged, arch: .current) == oldCode, "a resource leaves the cdhash as it was")
    check(installer.putBack(staged: staged, installed: o.installed, old: oldCode) == .notTheOldCopy && version(of: o.installed) == "1.1",
          "the old copy with a changed resource is not put back: the checked new copy stays")
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
// A stop (review 3): read before the download, by Update Now and the automatic update alike.
await refused("a stop signed with the update key names the release", { var r = v11; r.stop = .this; return r }()) { $0 == .stopped(tag: "v1.1") }
await refused("a stop signed with another key", { var r = v11; r.stop = .otherKey; return r }()) { if case .stopUnreadable(.unknownKey) = $0 { return true }; return false }
await refused("a stop that isn't one", { var r = v11; r.stop = .garbage; return r }()) { if case .stopUnreadable = $0 { return true }; return false }
_ = await installs("a stop for another release", { var r = v11; r.stop = .otherRelease; return r }())

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
await refused("a link through a link, out of the app (review 3, F6)", Release(zip: zip("hostile-link-through-link"), app: app("v1.1"))) {
    if case .archive(.throughLink) = $0 { return true }; return false
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
await refused("changed after the check, before install (the check right before the swap)", v11, tamper: .stagedResource) {
    if case .bundle(.invalidSignature) = $0 { return true }; return false
}
await refused("a file of the new copy given a second name (a hard link)", v11, tamper: .hardLink) {
    if case .bundle(.notABundle(let why)) = $0 { return why.contains("another name") }; return false
}
await refused("the new copy's CodeResources a link", v11, tamper: .signatureLink) {
    if case .bundle(.notABundle(let why)) = $0 { return why.contains("_CodeSignature/CodeResources is not a file") }; return false
}
await refused("changed between the last check and the swap (caught after it, put back)", v11, tamper: .raced) {
    if case .checkAfterSwap(.invalidSignature, putBack: true) = $0 { return true }; return false
}
await refused("the copy at the path is not the running one", v11, tamper: .wrongRunningCDHash) { $0 == .changedSinceStart }
// R3: the leftover note is written before the last check, so a change it sets off is refused there, before the swap.
publish(v11)
let atNoteFile = out.appendingPathComponent("cases/atnote/Update Now leftover.txt")
let atNoteBefore = treeHash(out.appendingPathComponent("apps/installed/UpdTest.app"))
let atNoteCase = await update("changed when the leftover note appears", tamper: .atNote, leftoverNote: atNoteFile)
if case .bundle(.invalidSignature)? = atNoteCase.failure { check(true, "") } else {
    check(false, "R3: a change at the note is refused before the swap: \(atNoteCase.failure.map { P.logText($0) } ?? "installed")")
}
check(treeHash(atNoteCase.installed) == atNoteBefore, "R3: the copy at the path untouched")
say("changed when the leftover note appears: \(atNoteCase.failure.map { P.logText($0) } ?? "installed"), before the swap")
if let s = atNoteCase.staging { UpdateInstaller.remove(s) }
// Both changed: the new copy fails its check at the final path and the old one, in staging, is not whole.
// Neither is left where Sill starts from: the failing copy goes to the staging folder.
publish(v11)
let both = await update("both copies changed", tamper: .both)
if case .checkAfterSwap(.invalidSignature, putBack: false)? = both.failure { check(true, "") } else {
    check(false, "both copies changed: \(both.failure.map { P.logText($0) } ?? "installed")")
}
check(!FileManager.default.fileExists(atPath: both.installed.path), "both copies changed: nothing left at the app's path")
check(both.staging.map { FileManager.default.fileExists(atPath: $0.appendingPathComponent("UpdTest (failed its check).app").path) } == true,
      "both copies changed: the failing copy moved into the staging folder")
say("both copies changed: \(both.failure.map { P.logText($0) } ?? "installed"); the path empty, the failing copy in staging")
if let s = both.staging { UpdateInstaller.remove(s) }
// The leftover note is written before the swap (N5): a swap that fails at the last moment (the folder made
// read-only) leaves the note naming the staging folder, and the copy at the path as it was.
publish(v11)
let noteFile = out.appendingPathComponent("cases/note/Update Now leftover.txt")
let failedSwap = await update("the swap fails", tamper: .swapFails, leftoverNote: noteFile)
if case .swapFailed? = failedSwap.failure { check(true, "") } else {
    check(false, "the swap fails: \(failedSwap.failure.map { P.logText($0) } ?? "installed")")
}
let noted = (try? String(contentsOf: noteFile, encoding: .utf8))?.trimmingCharacters(in: .newlines)
check(noted != nil && noted == failedSwap.staging?.path, "the note written before the swap: \(noted ?? "none")")
check(version(of: failedSwap.installed) == "1.0", "the swap fails: the copy at the path as it was")
say("the swap fails: \(failedSwap.failure.map { P.logText($0) } ?? "installed"); the note was written before it")
if let s = failedSwap.staging { UpdateInstaller.remove(s) }

say("== the notes between two Sills: read as small regular files, never waiting (the second security pass's W2)")
do {
    let dir = out.appendingPathComponent("cases/notes")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let fifo = dir.appendingPathComponent("fifo.txt"), link = dir.appendingPathComponent("link.txt"), plain = dir.appendingPathComponent("plain.txt"),
        big = dir.appendingPathComponent("big.txt")
    precondition(mkfifo(fifo.path, 0o600) == 0, "a FIFO")
    UpdateInstaller.writeNote(plain, lines: ["TOKEN", "0.4", "manual"])
    try! FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: plain.path)
    try! Data(repeating: 0x41, count: 5000).write(to: big)
    func timed(_ url: URL) -> (lines: [String]?, seconds: Double) {
        let start = Date(), done = DispatchSemaphore(value: 0)
        final class Box: @unchecked Sendable { var lines: [String]?; var finished = false }
        let box = Box()
        Thread.detachNewThread { box.lines = UpdateInstaller.readNote(url); box.finished = true; done.signal() }
        _ = done.wait(timeout: .now() + 2)
        return (box.finished ? box.lines : ["still waiting"], Date().timeIntervalSince(start))
    }
    let f = timed(fifo)
    check(f.lines == nil && f.seconds < 1, "W2: a FIFO where a note goes is refused at once (\(f.seconds) s, \(f.lines ?? []))")
    check(timed(link).lines == nil, "W2: a link where a note goes is never followed")
    check(timed(big).lines == nil, "a note over 4 KiB is none")
    check(timed(plain).lines == ["TOKEN", "0.4", "manual"], "a note Sill wrote reads back")
    // A FIFO the test opened must not keep the harness alive: open its other end once to release anything still waiting.
    let release = open(fifo.path, O_WRONLY | O_NONBLOCK); if release >= 0 { close(release) }
}

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
// A Sill worth waiting for at launch is a genuine one (N7): the test app is, for its own identifier, and is
// not Sill for the pinned requirement.
check(UpdateInstaller.genuine([child.processIdentifier], requirement: "identifier \"me.saffer.sill.updater-test\"") == [child.processIdentifier]
      && UpdateInstaller.genuine([child.processIdentifier], requirement: P.pinnedRequirement).isEmpty, "genuine Sills: by the requirement")

say("== where an app runs (the refusals' facts)")
var s = UpdateInstaller.situation(bundle: running, executable: "UpdTest", runningIsRelease: true, testFeed: false, runningIsInstalled: true, neededBytes: 1 << 20)
// Seen once (2026-11-12 01:23): macOS's system policy put the freshly started ad hoc test app into provenance
// tracking ("ASP: Security policy would not allow process", syspolicyd "Putting process into provenance
// tracking"), and while it ran its bundle read as not writable to the harness. Sill, notarized, is not
// tracked; here the look is taken again for up to 5 s before it counts.
var held = 0.0
while !s.bundleWritable && held < 5 {
    usleep(500_000)
    held += 0.5
    s = UpdateInstaller.situation(bundle: running, executable: "UpdTest", runningIsRelease: true, testFeed: false, runningIsInstalled: true, neededBytes: 1 << 20)
}
let direct = access(running.path, W_OK) == 0 ? "writable" : "not writable (\(String(cString: strerror(errno))))"
say("the running copy, to the harness while a process runs from it: \(direct)\(held > 0 ? " after \(held) s held by macOS's system policy" : "")")
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
for _ in 0..<5 { if case .success(let d) = UpdateInstaller.makeStaging(for: probe) { made.append(d) } }
check(made.count == 5 && Set(made.map(\.path)).count == 5, "five staging folders, each new")
for d in made {
    var st = stat()
    lstat(d.path, &st)
    check(st.st_mode & 0o777 == 0o700 && st.st_uid == getuid(), "0700 and this user's: \(String(st.st_mode & 0o777, radix: 8))")
}
func exists(_ u: URL) -> Bool { FileManager.default.fileExists(atPath: u.path) }
// made[1] holds an old copy not put back: set aside (renamed out of NSIRD_, a note inside). made[3]: only the
// note, as when the rename failed. made[0] is the one in use.
let aside = UpdateInstaller.setAside(made[1])
check(aside.lastPathComponent.hasPrefix(UpdateInstaller.setAsidePrefix) && !exists(made[1]), "set aside: renamed \(aside.lastPathComponent)")
check(exists(aside.appendingPathComponent(UpdateInstaller.keptMarker)), "set aside: its note")
FileManager.default.createFile(atPath: made[3].appendingPathComponent(UpdateInstaller.keptMarker).path, contents: Data("kept".utf8))
// The next Sill removes the folder an update noted (it can't list the temporary-items folder), and only a
// leftover: never the one in use, one holding a copy not put back, the set-aside one, or anything elsewhere.
let note = out.appendingPathComponent("leftover/Update Now leftover.txt")
UpdateInstaller.noteLeftover(made[2], in: note)
check(UpdateInstaller.removeLeftover(noted: note, for: probe, keep: made[0]) == made[2].path && !exists(made[2]) && !exists(note),
      "the noted leftover removed, and its note")
let elsewhere = out.appendingPathComponent("elsewhere/NSIRD_updharness_planted")
try? FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
for (target, why) in [(made[0], "the one in use"), (made[3], "one holding a copy not put back"), (aside, "the set-aside one"),
                      (elsewhere, "a folder of the right name elsewhere"), (out.appendingPathComponent("cases"), "the harness's own cases")] {
    UpdateInstaller.noteLeftover(target, in: note)
    check(UpdateInstaller.removeLeftover(noted: note, for: probe, keep: made[0]) == nil && exists(target) && !exists(note),
          "a note naming \(why): nothing removed, the note gone")
}
// Listing is best effort: macOS denies reading the temporary-items folder to most processes (Sill.app too).
let removed = UpdateInstaller.cleanUpStaging(for: probe, keep: made[0])
check(!removed.contains(made[0].path) && !removed.contains(made[3].path) && !removed.contains(aside.path),
      "listing never removes the one in use, a noted-kept one or the set-aside one: \(removed)")
say("staging: the noted leftover removed; listing the temporary-items folder \(removed.isEmpty ? "removed nothing (denied here, as to Sill.app)" : "removed \(removed.count)")")
for u in [made[0], made[3], made[4], aside] { UpdateInstaller.remove(u) }

// MARK: The genuine Sill 0.6.1 under Trust.release (with this run's key)

// MARK: The watcher (review 3, the automatic update's point 6)

say("== the watcher: a new copy that doesn't start is put back by itself")
/// One update installed (1.1 over 1.0), then a process standing in for the new Sill (`newCopy`'s arguments to the
/// installed UpdTest, or nil for a process that isn't it), and the watcher as Sill starts it, with the harness's
/// launcher (the put-back copy's executable, never Launch Services). Waits for the watcher to end. The started
/// note is a file whose name carries the token (STARTED; STARTED_OTHER another name). `plant` (the second security
/// pass's W1 and W2): a link at the restored note into the copy at Sill's path; the restored note inside that
/// copy (so the watcher's note lands in it after its move, which its check then catches); the old copy moved and
/// a link left in its place; a FIFO at the started note.
enum Plant { case none, linkAtRestored, restoredInsideApp, oldIsLink, fifoAtStarted, linkAtStarted }
func watched(_ name: String, newCopy: [String]?, seconds: Int = 6, changeOld: Bool = false, plant: Plant = .none,
             expectRestored: Bool, expectWhy: String? = nil, expectSetAside: Bool = false) async {
    publish(v11)
    let before = treeHash(out.appendingPathComponent("apps/installed/UpdTest.app"))
    let oldCDHash = UpdateInstaller.cdhash(of: out.appendingPathComponent("apps/installed/UpdTest.app"), arch: .current) ?? ""
    let o = await update(name)
    guard o.failure == nil, let old = o.staged else { check(false, "\(name): the update: \(o.failure.map { P.logText($0) } ?? "")"); return }
    if changeOld {
        let h = try! FileHandle(forWritingTo: old.appendingPathComponent("Contents/Resources/note.txt")); h.seekToEndOfFile(); h.write(Data("changed while it waited\n".utf8)); h.closeFile()
    }
    let dir = out.appendingPathComponent("cases/\(name)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let token = UUID().uuidString
    let started = dir.appendingPathComponent("started \(token).txt"), other = dir.appendingPathComponent("started other.txt")
    let restored = plant == .restoredInsideApp ? o.installed.appendingPathComponent("Contents/Resources/restored.txt")
        : dir.appendingPathComponent("restored.txt")
    let launched = o.installed.deletingLastPathComponent().appendingPathComponent("launched.txt")
    switch plant {
    case .linkAtRestored:
        try! FileManager.default.createSymbolicLink(atPath: restored.path, withDestinationPath: o.installed.appendingPathComponent("Contents/Resources/note.txt").path)
    case .oldIsLink:
        let moved = dir.appendingPathComponent("old elsewhere.app")
        try! FileManager.default.moveItem(at: old, to: moved)
        try! FileManager.default.createSymbolicLink(atPath: old.path, withDestinationPath: moved.path)
    case .fifoAtStarted:
        precondition(mkfifo(started.path, 0o600) == 0, "a FIFO")
    case .linkAtStarted:
        try! Data("\(token)\n".utf8).write(to: other)
        try! FileManager.default.createSymbolicLink(atPath: started.path, withDestinationPath: other.path)
    case .none, .restoredInsideApp: break
    }
    let p = Process()
    if let args = newCopy {
        p.executableURL = o.installed.appendingPathComponent("Contents/MacOS/UpdTest")
        p.arguments = args.map { $0 == "STARTED" ? started.path : $0 == "STARTED_OTHER" ? other.path : $0 == "TOKEN" ? token : $0 }
    } else {
        p.executableURL = URL(fileURLWithPath: "/bin/sleep")
        p.arguments = ["30"]
    }
    p.standardOutput = FileHandle.nullDevice
    try! p.run()
    let w = UpdateInstaller.Watch(pid: p.processIdentifier, installed: o.installed, executable: "UpdTest", oldCopy: old, oldCDHash: oldCDHash,
                                  requirement: testTrust.signer, startedNote: started, token: token, restoredNote: restored, seconds: seconds,
                                  launcher: out.appendingPathComponent("launch.sh").path)
    check(UpdateInstaller.startWatcher(w), "\(name): the watcher started")
    // It ends by itself: the note seen, or the put-back done (or refused), at most `seconds` + 8 s.
    let deadline = Date().addingTimeInterval(Double(seconds) + 12)
    while Date() < deadline {
        let busy = Process.runTool("/usr/bin/pgrep", ["-q", "-f", "sill-update-watcher " + String(p.processIdentifier)]) == 0
        if !busy { break }
        try? await Task.sleep(for: .milliseconds(250))
    }
    try? await Task.sleep(for: .milliseconds(500))
    if expectSetAside {
        check(!FileManager.default.fileExists(atPath: o.installed.path), "\(name): nothing left at Sill's path")
        check(version(of: old.deletingLastPathComponent().appendingPathComponent("failed its check.app")) == "1.0",
              "\(name): the put-back copy that failed its check moved aside")
        check(!FileManager.default.fileExists(atPath: launched.path), "\(name): nothing started")
    } else if expectRestored {
        check(version(of: o.installed) == "1.0", "\(name): the old copy is back at the path (\(version(of: o.installed) ?? "none"))")
        check(treeHash(o.installed) == before, "\(name): the old copy back is the old copy, whole")
        check(version(of: old.deletingLastPathComponent().appendingPathComponent("did not start.app")) == "1.1", "\(name): the new copy parked beside it")
        let note = UpdateInstaller.readNote(restored)
        check(note?.first == token && (expectWhy.map { note?.dropFirst().first?.hasPrefix($0) == true } ?? true),
              "\(name): the restored note: \(note ?? [])")
        var link = stat()
        check(lstat(restored.path, &link) == 0 && link.st_mode & S_IFMT == S_IFREG, "\(name): the restored note a file of its own, never written through a link")
        check((try? String(contentsOf: launched, encoding: .utf8)) == "launched 1.0\n", "\(name): the old copy was started")
    } else {
        check(version(of: o.installed) == "1.1", "\(name): the new copy stays (\(version(of: o.installed) ?? "none"))")
        check(!FileManager.default.fileExists(atPath: restored.path) && !FileManager.default.fileExists(atPath: launched.path),
              "\(name): nothing put back, nothing started")
    }
    if newCopy == nil {
        check(p.isRunning, "\(name): a process that isn't the new Sill is never stopped")
        p.terminate()
    }
    // Not waitUntilExit: from a task, after a hop to another thread, it can wait for good.
    let end = Date().addingTimeInterval(10)
    while p.isRunning, Date() < end { try? await Task.sleep(for: .milliseconds(100)) }
    if p.isRunning { kill(p.processIdentifier, SIGKILL) }
    if let s = o.staging { UpdateInstaller.remove(s) }
    say("\(name): \(version(of: o.installed) ?? "?") at the path")
}
await watched("the new copy proves itself", newCopy: ["started", "STARTED", "TOKEN", "1"], expectRestored: false)
await watched("the new copy quits at once", newCopy: ["crash"], expectRestored: true, expectWhy: "it quit before it had run")
await watched("the new copy never proves itself", newCopy: ["sleep", "30"], seconds: 3, expectRestored: true, expectWhy: "it hadn't run for long enough")
await watched("another token in the note", newCopy: ["started", "STARTED_OTHER", "TOKEN", "1"], seconds: 3, expectRestored: true)
// The second security pass's W1 and W2.
await watched("a link planted at the restored note", newCopy: ["crash"], plant: .linkAtRestored, expectRestored: true, expectWhy: "it quit before it had run")
await watched("the note lands in the put-back copy", newCopy: ["crash"], plant: .restoredInsideApp, expectRestored: false, expectSetAside: true)
await watched("the old copy replaced by a link", newCopy: ["crash"], plant: .oldIsLink, expectRestored: false)
await watched("a FIFO at the started note", newCopy: ["sleep", "30"], seconds: 3, plant: .fifoAtStarted, expectRestored: true, expectWhy: "it hadn't run for long enough")
await watched("a link at the started note", newCopy: ["sleep", "30"], seconds: 3, plant: .linkAtStarted, expectRestored: true, expectWhy: "it hadn't run for long enough")
await watched("the old copy changed while it waited", newCopy: ["crash"], changeOld: true, expectRestored: false)
await watched("the pid isn't the new Sill's", newCopy: nil, seconds: 3, expectRestored: true)

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
