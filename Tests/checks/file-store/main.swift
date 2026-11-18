import Foundation
import CryptoKit

// FileStore on a scratch folder of its own (.build/checks/file-store/scratch-<pid>), never ~/Downloads: the
// destination and its hidden staging folder, parts written and hashed, a wrong hash and a short file refused, a
// collision with a file and with a link, the quarantine and Where from read back, mode 0644, links refused,
// leftovers cleaned, the free space, errno's meaning.
var failures = 0
var checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
let fm = FileManager.default
let scratch = URL(fileURLWithPath: fm.currentDirectoryPath).appendingPathComponent(".build/checks/file-store/scratch-\(getpid())", isDirectory: true)
try? fm.removeItem(at: scratch)
try! fm.createDirectory(at: scratch, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: scratch) }
func sha(_ d: Data) -> String { Base64URL.encode(Data(SHA256.hash(data: d))) }
func mode(_ url: URL) -> mode_t { var st = stat(); return lstat(url.path, &st) == 0 ? st.st_mode & 0o7777 : 0 }
func xattr(_ url: URL, _ name: String) -> Data? {
    let n = getxattr(url.path, name, nil, 0, 0, XATTR_NOFOLLOW)
    guard n >= 0 else { return nil }
    var d = Data(count: n)
    let got = d.withUnsafeMutableBytes { getxattr(url.path, name, $0.baseAddress, n, 0, XATTR_NOFOLLOW) }
    return got == n ? d : nil
}
func listing(_ url: URL) -> [String] { ((try? fm.contentsOfDirectory(atPath: url.path)) ?? []).sorted() }
func throwsFailure(_ want: FileStore.Failure, _ f: () throws -> Void) -> Bool {
    do { try f(); return false } catch let e as FileStore.Failure { return e == want } catch { return false }
}

let dest = scratch.appendingPathComponent("Downloads/Sill", isDirectory: true)
let store = FileStore(destination: dest, agentBundleID: "me.saffer.sill.check")
check(FileStore.stagingName == ".Sill Incoming", "the staging folder: .Sill Incoming (hidden)")
check(FileStore.stagingFileName(transfer: 0xABC, file: 7) == "00000abc-00000007.part", "a staging file is named by Sill, never by the sender")
do { try store.prepare() } catch { check(false, "prepare: \(error)") }
var st = stat()
check(lstat(dest.path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR && mode(dest) == 0o755, "the destination made, 0755 (made with its Downloads)")
check(lstat(store.staging.path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR && mode(store.staging) == 0o700, "the staging folder made, 0700")
check(store.staging.deletingLastPathComponent().standardizedFileURL == dest.standardizedFileURL, "inside the destination (one volume: the move is atomic)")

// A file in parts.
let content = Data((0..<300_000).map { UInt8($0 % 251) })
var s = try! store.open(transfer: 1, file: 2)
check(listing(store.staging) == ["00000001-00000002.part"], "one staging file while it is on its way")
check(mode(s.url) == 0o600, "the staging file is 0600")
check(listing(dest) == [".Sill Incoming"], "nothing under its name before it is whole")
for start in stride(from: 0, to: content.count, by: 65_536) {
    try! store.write(content.subdata(in: start..<min(start + 65_536, content.count)), to: s)
}
check(s.written == 300_000, "300,000 bytes written")
var kept = ""
do { kept = try store.finish(s, size: 300_000, sha256: sha(content), name: "../report:final.pdf", device: "iPad\n(iPad14,1)") }
catch { check(false, "finish: \(error)") }
check(kept == "File..-report-final.pdf", "kept under its cleaned name: \(kept)")
let keptURL = dest.appendingPathComponent(kept)
check((try? Data(contentsOf: keptURL)) == content, "byte for byte")
check(mode(keptURL) == 0o644, "0644, as a download")
check(listing(store.staging).isEmpty, "nothing left in the staging folder")
if let q = xattr(keptURL, "com.apple.quarantine").flatMap({ String(data: $0, encoding: .utf8) }) {
    let parts = q.split(separator: ";", omittingEmptySubsequences: false)
    // LaunchServices keeps the agent with the event its UUID names, so the agent is read through it below.
    check(parts.count >= 2 && UInt32(parts[0], radix: 16).map { $0 & 0x40 == 0 } == true,
          "quarantined, and not yet approved, so Gatekeeper checks it before it opens: \(q)")
} else { check(false, "no com.apple.quarantine") }
var values = try? keptURL.resourceValues(forKeys: [.quarantinePropertiesKey])
check((values?.quarantineProperties?["LSQuarantineAgentName"] as? String) == "Sill", "LaunchServices reads Sill as the agent")
check((values?.quarantineProperties?["LSQuarantineType"] as? String) == "LSQuarantineTypeOtherDownload", "an ordinary download")
if let w = xattr(keptURL, "com.apple.metadata:kMDItemWhereFroms"),
   let list = try? PropertyListSerialization.propertyList(from: w, format: nil) as? [String] {
    check(list == ["iPad (iPad14,1), through Sill"], "Where from: the device's cleaned name, through Sill: \(list)")
} else { check(false, "no Where from") }

// The same name again: a number. A link where the name is: the next number, the link untouched.
func keep(_ name: String, _ bytes: Data, transfer: UInt32, file: UInt32) -> String? {
    guard let x = try? store.open(transfer: transfer, file: file) else { return nil }
    try? store.write(bytes, to: x)
    return try? store.finish(x, size: UInt64(bytes.count), sha256: sha(bytes), name: name, device: "iPad")
}
check(keep("../report:final.pdf", Data("two".utf8), transfer: 2, file: 1) == "File..-report-final 2.pdf", "the same name: a number")
symlink("/nonexistent/target", dest.appendingPathComponent("b.pdf").path)
check(keep("b.pdf", Data("b".utf8), transfer: 3, file: 1) == "b 2.pdf", "a link to nothing at the name: the next number")
var linkSt = stat()
check(lstat(dest.appendingPathComponent("b.pdf").path, &linkSt) == 0 && (linkSt.st_mode & S_IFMT) == S_IFLNK, "the link untouched")
fm.createFile(atPath: dest.appendingPathComponent("Probe-X").path, contents: Data())
let ignoresCase = fm.fileExists(atPath: dest.appendingPathComponent("probe-x").path)
try? fm.removeItem(at: dest.appendingPathComponent("Probe-X"))
fm.createFile(atPath: dest.appendingPathComponent("Case.txt").path, contents: Data("old".utf8))
let other = keep("case.txt", Data("new".utf8), transfer: 4, file: 1)
check(ignoresCase ? other == "case 2.txt" : other == "case.txt", "a name that differs only in case: \(other ?? "nil") (this volume ignores case: \(ignoresCase))")
check((try? Data(contentsOf: dest.appendingPathComponent("Case.txt"))) == Data("old".utf8), "the other file untouched")
check(keep("empty", Data(), transfer: 5, file: 1) == "empty", "a 0-byte file kept")

// Refusals: a wrong hash, a short file, a closed file; nothing kept, nothing left.
var before = listing(dest)
s = try! store.open(transfer: 6, file: 1)
try! store.write(Data("abc".utf8), to: s)
check(throwsFailure(.damaged) { _ = try store.finish(s, size: 3, sha256: sha(Data("abd".utf8)), name: "x", device: "iPad") }, "a wrong hash: damaged")
check(listing(dest) == before && listing(store.staging).isEmpty, "nothing kept, nothing left")
s = try! store.open(transfer: 6, file: 2)
try! store.write(Data("ab".utf8), to: s)
check(throwsFailure(.damaged) { _ = try store.finish(s, size: 3, sha256: sha(Data("ab".utf8)), name: "x", device: "iPad") }, "a short file: damaged")
check(listing(dest) == before && listing(store.staging).isEmpty, "nothing kept, nothing left")
check((try? store.write(Data("z".utf8), to: s)) == nil, "no write after it is over")
s = try! store.open(transfer: 6, file: 3)
check((try? store.open(transfer: 6, file: 3)) == nil, "a staging file is created new: a second open of the same fails")
store.discard(s)
check(listing(store.staging).isEmpty, "discard deletes it")
symlink(dest.appendingPathComponent("b 2.pdf").path, store.staging.appendingPathComponent(FileStore.stagingFileName(transfer: 7, file: 1)).path)
check((try? store.open(transfer: 7, file: 1)) == nil, "a link at the staging name: never written through")
check((try? Data(contentsOf: dest.appendingPathComponent("b 2.pdf"))) == Data("b".utf8), "what it pointed at untouched")
unlink(store.staging.appendingPathComponent(FileStore.stagingFileName(transfer: 7, file: 1)).path)

// Leftovers.
for f in [10, 11] { _ = try! store.open(transfer: 9, file: UInt32(f)) }
before = listing(dest)
check(store.cleanLeftovers() == 2 && listing(store.staging).isEmpty, "leftovers deleted at launch and quit")
check(listing(dest) == before, "the destination's own files untouched")

// Links refused: a destination that is a link, a staging folder that is a link.
let real = scratch.appendingPathComponent("real", isDirectory: true)
try! fm.createDirectory(at: real, withIntermediateDirectories: true)
let linked = scratch.appendingPathComponent("linked")
symlink(real.path, linked.path)
check(throwsFailure(.cantSave("linked is not a folder")) { try FileStore(destination: linked).prepare() }, "a destination that is a link: refused")
let dest2 = scratch.appendingPathComponent("two", isDirectory: true)
try! fm.createDirectory(at: dest2, withIntermediateDirectories: true)
symlink(real.path, dest2.appendingPathComponent(FileStore.stagingName).path)
check((try? FileStore(destination: dest2).prepare()) == nil, "a staging folder that is a link: refused")
check(listing(real).isEmpty, "nothing written through either")

// A folder the Mac's person chooses in Settings (Other Folder…): a folder, not a link to one, writable.
check(FileStore.refusal(forFolder: real) == nil, "a writable folder: taken")
check(FileStore.refusal(forFolder: linked) == "Choose the folder itself, not an alias or a link to it.", "a link to a folder: refused")
let plainFile = scratch.appendingPathComponent("plain.txt")
fm.createFile(atPath: plainFile.path, contents: Data("x".utf8))
check(FileStore.refusal(forFolder: plainFile) == "Choose a folder.", "a file: refused")
check(FileStore.refusal(forFolder: scratch.appendingPathComponent("missing")) == "That folder can’t be found.", "a folder that is gone: refused")
let readOnly = scratch.appendingPathComponent("read-only", isDirectory: true)
try! fm.createDirectory(at: readOnly, withIntermediateDirectories: true)
chmod(readOnly.path, 0o555)
check(FileStore.refusal(forFolder: readOnly) == "Sill can’t save files in that folder.", "a folder Sill cannot write: refused")
chmod(readOnly.path, 0o755)

// The free space, errno's meaning, the reasons.
check((store.freeSpace() ?? 0) > 0, "the free space reads")
check(FileStore.failure(ENOSPC) == .noRoom && FileStore.failure(EDQUOT) == .noRoom, "a full volume or quota: noRoom")
check(FileStore.failure(EACCES) != .noRoom && FileStore.failure(EACCES).reason == .cantSave, "anything else: cantSave")
check(FileStore.Failure.damaged.reason == .damaged && FileStore.Failure.noRoom.reason == .noRoom, "each failure's reason")
check(FileStore.defaultDestination.lastPathComponent == "Sill" && FileStore.defaultDestination.deletingLastPathComponent().lastPathComponent == "Downloads",
      "Downloads › Sill by default")

print("file-store: \(checks - failures)/\(checks) checks passed")
exit(failures == 0 ? 0 : 1)
