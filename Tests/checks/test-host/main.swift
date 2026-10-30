import Foundation
import Security

// Checks AppIdentity (Sources/SillMenuBar/AppIdentity.swift): which launches are Sill.app itself, and
// so take no test hook, and which are the bare SillMenuBar binary (the security scan of 2026-10-18,
// finding 1; fixed 2026-10-29). With IdentityStorePlan, what that means for the finding's own path:
// the test directory's trust list (SILL_TEST_REMOTE_DIR) read by a renamed copy of Sill.app.
//
// 1. The rule: Sill.app as built, released and copied in every way the scan and the fix found
//    (renamed Sill.bin, flat, through a hard link or a symlink, re-signed), the bare binary as
//    `swift build` makes it on Apple silicon and on Intel, near misses, then every combination of the
//    four facts against an oracle written apart from the rule.
// 2. The note line Sill.app prints from a folder that is not a .app.
// 3. The reader, run for real: this check's own binary is what .build/release/SillMenuBar is (linker
//    signed ad hoc, no Info.plist), and copies of it are made here as the scan's attacker would make
//    copies of Sill.app: signed again as Sill, in a Sill.bin bundle that says it is Sill, started
//    through a hard link and a symlink to a bundle's executable, and replaced on disk after it started
//    (the kernel's identifier stands). Each copy is started with --facts under sandbox-exec with the
//    network denied, reads its own facts and prints them; nothing else runs. The signature reader
//    also reads files: an Apple app (a certificate), this binary (ad hoc), an unsigned copy; and its
//    mapping, pure, every answer (the two that fail closed, which no file here gives, among them).
//
// `--facts` and `--facts-wait` are the copies' modes: print this process's facts on one line (after a
// line on stdin, for --facts-wait) and exit.

func factsLine(_ f: AppIdentity.Facts) -> String {
    [f.signingIdentifier ?? "-", "\(f.signature)", f.bundleIdentifier ?? "-", f.bundlePath,
     AppIdentity.isSillApp(f) ? "sill" : "test"].joined(separator: "\t")
}
if CommandLine.arguments.contains("--facts-wait") {
    print("ready"); fflush(stdout)
    _ = readLine()
    print(factsLine(.current())); exit(0)
}
if CommandLine.arguments.contains("--facts") { print(factsLine(.current())); exit(0) }

var failures = 0, passed = 0
func check(_ desc: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    if ok { passed += 1; return }
    failures += 1
    let d = detail()
    print("FAIL: \(desc)\(d.isEmpty ? "" : ": \(d)")")
}

typealias F = AppIdentity.Facts
let sill = "me.saffer.sill.mac"
let build = "/Users/x/sill/.build/arm64-apple-macosx/release"
func facts(_ id: String?, _ sig: AppIdentity.Signature, _ bundle: String?, _ path: String) -> F {
    F(signingIdentifier: id, signature: sig, bundleIdentifier: bundle, bundlePath: path)
}

// MARK: 1. The rule

// The bundle identifier make-app.sh puts in Sill.app (run.sh and the mutants run from the repository).
let packaged = (NSDictionary(contentsOfFile: "Packaging/Info.plist")?["CFBundleIdentifier"] as? String) ?? "unread"
check("Sill's identifier is Packaging/Info.plist's", AppIdentity.sill == packaged && packaged == sill, packaged)
let cases: [(String, F, Bool)] = [
    // The bare binary: the one test host.
    ("the bare binary as swift build makes it (Apple silicon: the linker's ad hoc signature)",
     facts("SillMenuBar", .adHoc, nil, build), false),
    ("the bare binary on Intel (x86_64: no signature)",
     facts(nil, .unsigned, nil, "/Users/x/sill/.build/x86_64-apple-macosx/release"), false),
    ("the bare binary built by Xcode (Sign to Run Locally)",
     facts("SillMenuBar", .adHoc, nil, "/Users/x/Library/Developer/Xcode/DerivedData/Sill-abc/Build/Products/Release"), false),
    // Sill.app where it belongs.
    ("Sill.app as make-app.sh builds it (Apple Development)", facts(sill, .certificate, sill, "/Applications/Sill.app"), true),
    ("Sill.app's Developer ID release", facts(sill, .certificate, sill, "/Applications/Sill.app"), true),
    ("Sill.app signed ad hoc (no Apple Development identity; CI's verify job)", facts(sill, .adHoc, sill, "/Users/x/sill/.build/Sill.app"), true),
    // The scan's copy, and the other ways to start Sill.app's code where the folder says nothing.
    ("the scan's copy: Sill.app renamed Sill.bin", facts(sill, .certificate, sill, "/Users/x/x/Sill.bin"), true),
    ("Sill.app's executable through a symlink (Foundation finds no bundle around it)", facts(sill, .certificate, nil, "/tmp/x"), true),
    ("Sill.app's executable through a hard link", facts(sill, .certificate, nil, "/tmp/x"), true),
    ("a flat copy of Sill.app's executable", facts(sill, .certificate, nil, "/Users/x/x"), true),
    ("Sill.app copied without its Info.plist", facts(sill, .certificate, nil, "/Users/x/x/Sill.bin"), true),
    ("Sill.app copied to a folder with no extension", facts(sill, .certificate, sill, "/Users/x/x/Sill"), true),
    ("an ad hoc Sill.app renamed (its grants are its cdhash, which a copy keeps)", facts(sill, .adHoc, sill, "/tmp/Sill.bin"), true),
    ("an ad hoc Sill.app's executable through a link", facts(sill, .adHoc, nil, "/tmp"), true),
    ("Sill's code signed again under another identifier, in its renamed bundle (its bundle still says Sill)",
     facts("other", .adHoc, sill, "/tmp/Sill.bin"), true),
    ("Sill's code signed again ad hoc under another identifier, alone (no grant left, nothing says Sill)",
     facts("other", .adHoc, nil, "/tmp"), false),
    // The bare binary where Sill.app's facts are.
    ("the bare binary in a bundle that says it is Sill (Sill's Info.plist)", facts("SillMenuBar", .adHoc, sill, "/tmp/Sill.bin"), true),
    ("the bare binary in a .app of another ID (the rule before 2026-10-29)", facts("SillMenuBar", .adHoc, "me.saffer.sill.test", "/tmp/Test.app"), true),
    ("the bare binary in a bundle of another ID that is not a .app", facts("SillMenuBar", .adHoc, "me.saffer.sill.test", "/tmp/Test.bin"), false),
    ("the bare binary signed with a certificate (a developer's own)", facts("SillMenuBar", .certificate, nil, build), true),
    ("the bare binary on Intel in a .app (the rule before)", facts(nil, .unsigned, "me.saffer.sill.test", "/tmp/Test.app"), true),
    ("a signature that could not be read", facts(nil, .unreadable, nil, build), true),
    ("an identifier that could not be read, ad hoc", facts(nil, .adHoc, nil, build), false),
    // In any case.
    ("Sill's identifier in capitals", facts("ME.SAFFER.SILL.MAC", .adHoc, nil, "/tmp"), true),
    ("Sill's bundle identifier in mixed case", facts("SillMenuBar", .adHoc, "Me.Saffer.Sill.Mac", "/tmp/Sill.bin"), true),
    ("a .APP folder", facts("SillMenuBar", .adHoc, nil, "/tmp/Sill.APP"), true),
    // Near misses.
    ("an identifier that only starts with Sill's", facts("me.saffer.sill.mac.helper", .adHoc, nil, build), false),
    ("an identifier Sill's starts with", facts("me.saffer.sill", .adHoc, nil, build), false),
    ("a bundle identifier that only starts with Sill's", facts("SillMenuBar", .adHoc, "me.saffer.sill.mac2", "/tmp/Sill.bin"), false),
    ("an empty bundle identifier", facts("SillMenuBar", .adHoc, "", "/tmp/Sill.bin"), false),
    ("a folder named app", facts("SillMenuBar", .adHoc, nil, "/tmp/app"), false),
    ("a .apps folder", facts("SillMenuBar", .adHoc, nil, "/tmp/x.apps"), false),
    ("a .app folder above the binary's folder", facts("SillMenuBar", .adHoc, nil, "/tmp/x.app/release"), false),
]
for (desc, f, want) in cases {
    check("rule: \(desc) → \(want ? "Sill.app" : "a test host")", AppIdentity.isSillApp(f) == want, factsLine(f))
}

// Every combination of the facts against an oracle written apart from the rule: a test host is
// unsigned or ad hoc, signed under another identifier, in no bundle that says Sill, not in a .app.
let identifiers: [String?] = [nil, "", "SillMenuBar", sill, "ME.saffer.SILL.mac", "me.saffer.sill.mac.helper", "other"]
let signatures: [AppIdentity.Signature] = [.unsigned, .adHoc, .certificate, .unreadable]
let bundles: [String?] = [nil, "", sill, "Me.Saffer.Sill.Mac", "me.saffer.sill.test", "me.saffer.sill.mac2"]
let paths = [build, "/Applications/Sill.app", "/tmp/Sill.APP", "/tmp/Sill.bin", "/tmp/Sill", "/tmp/x.apps", "/tmp/app", "/"]
func oracleTestHost(_ f: F) -> Bool {
    let signedAsSill = f.signingIdentifier.map { $0.caseInsensitiveCompare(sill) == .orderedSame } ?? false
    let bundleSill = f.bundleIdentifier.map { $0.caseInsensitiveCompare(sill) == .orderedSame } ?? false
    let appFolder = URL(fileURLWithPath: f.bundlePath).pathExtension.caseInsensitiveCompare("app") == .orderedSame
    let noCertificate = f.signature == .unsigned || f.signature == .adHoc
    return noCertificate && !signedAsSill && !bundleSill && !appFolder
}
var grid = 0, gridWrong = 0
for id in identifiers { for sig in signatures { for b in bundles { for p in paths {
    let f = facts(id, sig, b, p)
    grid += 1
    if AppIdentity.isSillApp(f) == oracleTestHost(f) {
        gridWrong += 1
        if gridWrong <= 5 { check("grid: \(factsLine(f)) against the oracle", false) }
    }
}}}}
check("grid: \(grid) combinations agree with the oracle", gridWrong == 0, "\(gridWrong) disagree")

// The finding's path: a renamed copy started with --synthetic and SILL_TEST_REMOTE_DIR would have
// trusted a paired.json its caller wrote. Sill.app's code never takes the test directory, whatever
// it is started with; the bare binary still does.
let trustDir = "/tmp/attacker/trust"
for (desc, f, want) in cases where want {
    for synthetic in [true, false] {
        let choice = IdentityStorePlan.choose(bundled: AppIdentity.isSillApp(f), synthetic: synthetic,
                                              entitledAccessGroup: nil, testRemoteDir: trustDir)
        check("store: \(desc), synthetic \(synthetic): never the test directory", choice != .testDirectory(trustDir), "\(choice)")
    }
}
check("store: the scan's copy with --synthetic keeps its identity in memory, pairing required",
      IdentityStorePlan.choose(bundled: AppIdentity.isSillApp(facts(sill, .certificate, sill, "/Users/x/x/Sill.bin")), synthetic: true,
                               entitledAccessGroup: nil, testRemoteDir: trustDir) == .memory)
check("store: the bare binary with --synthetic still takes the test directory",
      IdentityStorePlan.choose(bundled: AppIdentity.isSillApp(facts("SillMenuBar", .adHoc, nil, build)), synthetic: true,
                               entitledAccessGroup: nil, testRemoteDir: trustDir) == .testDirectory(trustDir))

// MARK: 2. The note

func note(_ f: F) -> String? { AppIdentity.note(f) }
check("note: none for Sill.app in its .app", note(facts(sill, .certificate, sill, "/Applications/Sill.app")) == nil)
check("note: none for the bare binary", note(facts("SillMenuBar", .adHoc, nil, build)) == nil)
check("note: none for the bare binary in a .app of another ID (as before)", note(facts("SillMenuBar", .adHoc, "me.saffer.sill.test", "/tmp/Test.app")) == nil)
check("note: none for a .APP folder", note(facts(sill, .certificate, sill, "/tmp/Sill.APP")) == nil)
check("note: the scan's copy",
      note(facts(sill, .certificate, sill, "/Users/x/x/Sill.bin"))
        == "Running from /Users/x/x/Sill.bin, which is not a .app, as Sill.app itself (signed me.saffer.sill.mac): it takes no test hook.",
      note(facts(sill, .certificate, sill, "/Users/x/x/Sill.bin")) ?? "nil")
check("note: a link to Sill.app's executable",
      note(facts(sill, .certificate, nil, "/tmp/x"))
        == "Running from /tmp/x, which is not a .app, as Sill.app itself (signed me.saffer.sill.mac): it takes no test hook.")
check("note: a certificate alone",
      note(facts("SillMenuBar", .certificate, nil, build))
        == "Running from \(build), which is not a .app, as Sill.app itself (signed with a certificate): it takes no test hook.")
check("note: an unreadable signature",
      note(facts(nil, .unreadable, nil, build))
        == "Running from \(build), which is not a .app, as Sill.app itself (its signature could not be read): it takes no test hook.")
check("note: a bundle that says Sill alone",
      note(facts("SillMenuBar", .adHoc, "Me.Saffer.Sill.Mac", "/tmp/Sill.bin"))
        == "Running from /tmp/Sill.bin, which is not a .app, as Sill.app itself (its bundle says Me.Saffer.Sill.Mac): it takes no test hook.")
for (desc, f, want) in cases {
    let n = note(f)
    let folderSaysApp = URL(fileURLWithPath: f.bundlePath).pathExtension.lowercased() == "app"
    check("note: \(desc): a line exactly for Sill.app's code where the folder does not say so", (n != nil) == (want && !folderSaysApp), n ?? "nil")
}

// MARK: 3. The reader, for real

let fm = FileManager.default
guard let me = Bundle.main.executablePath else { print("FAIL: no executable path"); exit(1) }
let scratch = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("sill-test-host-\(getpid())")
try? fm.removeItem(at: scratch)
try! fm.createDirectory(at: scratch, withIntermediateDirectories: true)
func path(_ name: String) -> String { scratch.appendingPathComponent(name).path }

@discardableResult
func run(_ tool: String, _ args: [String], input: String? = nil) -> (status: Int32, out: String) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: tool)
    p.arguments = args
    let out = Pipe(); p.standardOutput = out; p.standardError = out
    let inp = Pipe(); p.standardInput = inp
    do { try p.run() } catch { return (-1, "\(error)") }
    if let input { inp.fileHandleForWriting.write(Data(input.utf8)) }
    try? inp.fileHandleForWriting.close()
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (p.terminationStatus, String(decoding: data, as: UTF8.self))
}
func codesign(_ args: [String]) -> Bool {
    let r = run("/usr/bin/codesign", args)
    if r.status != 0 { print("FAIL: codesign \(args.joined(separator: " ")): \(r.out)"); failures += 1 }
    return r.status == 0
}
func copy(_ from: String, _ to: String) {
    try? fm.createDirectory(atPath: (to as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    do { try fm.copyItem(atPath: from, toPath: to) } catch { print("FAIL: copy to \(to): \(error)"); failures += 1 }
}
func bundle(_ folder: String, id: String) -> String {
    let exe = "\(folder)/Contents/MacOS/check"
    copy(me, exe)
    let plist: [String: Any] = ["CFBundleIdentifier": id, "CFBundleExecutable": "check", "CFBundleInfoDictionaryVersion": "6.0"]
    try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        .write(to: URL(fileURLWithPath: "\(folder)/Contents/Info.plist"))
    return exe
}

// The copies start under sandbox-exec with the network denied (nothing else changes for them); where
// sandbox-exec can't apply (a sandbox already around this check), they start as they are, and say so.
let profile = "(version 1)(allow default)(deny network*)"
let sandboxed = run("/usr/bin/sandbox-exec", ["-p", profile, "/usr/bin/true"]).status == 0
if !sandboxed { print("note: sandbox-exec could not apply here; the copies start without it (they read their own identity, nothing else)") }
func start(_ exe: String, _ args: [String] = ["--facts"]) -> (tool: String, args: [String]) {
    sandboxed ? ("/usr/bin/sandbox-exec", ["-p", profile, exe] + args) : (exe, args)
}
struct Read: CustomStringConvertible {
    var id, signature, bundle, path, verdict: String
    var description: String { [id, signature, bundle, path, verdict].joined(separator: " | ") }
}
func readFacts(_ exe: String) -> Read? {
    let s = start(exe)
    let r = run(s.tool, s.args)
    let fields = r.out.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\t")
    guard r.status == 0, fields.count == 5 else { print("FAIL: \(exe) --facts: exit \(r.status): \(r.out)"); failures += 1; return nil }
    return Read(id: fields[0], signature: fields[1], bundle: fields[2], path: fields[3], verdict: fields[4])
}
func expect(_ desc: String, _ exe: String, id: String? = nil, signature: String, bundle: String, pathSuffix: String, verdict: String) {
    guard let r = readFacts(exe) else { return }
    let idOK = id.map { r.id == $0 } ?? (r.id != "-" && r.id.lowercased() != sill)
    check("reader: \(desc)", idOK && r.signature == signature && r.bundle == bundle && r.path.hasSuffix(pathSuffix) && r.verdict == verdict, "\(r)")
}

// The bare binary: this check itself, as the linker leaves it: signed ad hoc on Apple silicon, not at
// all in an x86_64 build.
#if arch(x86_64)
let linkerSignature = AppIdentity.Signature.unsigned
#else
let linkerSignature = AppIdentity.Signature.adHoc
#endif
let selfFacts = AppIdentity.Facts.current()
check("reader: this check, read in place, is the bare binary's kind: the linker's signature, no bundle, a test host",
      selfFacts.signature == linkerSignature && selfFacts.bundleIdentifier == nil
        && (selfFacts.signingIdentifier != nil) == (linkerSignature == .adHoc)
        && selfFacts.signingIdentifier?.lowercased() != sill && !AppIdentity.isSillApp(selfFacts), factsLine(selfFacts))
expect("this check as a process: a test host", me, id: selfFacts.signingIdentifier ?? "-", signature: "\(linkerSignature)", bundle: "-",
       pathSuffix: (me as NSString).deletingLastPathComponent, verdict: "test")

// A flat copy signed again as Sill: the signing identifier alone says Sill.
copy(me, path("flat-sill"))
if codesign(["-s", "-", "-f", "-i", sill, path("flat-sill")]) {
    expect("a flat copy signed ad hoc as Sill: Sill.app by its signing identifier", path("flat-sill"),
           id: sill, signature: "adHoc", bundle: "-", pathSuffix: scratch.lastPathComponent, verdict: "sill")
}
// The scan's folder: Sill.bin, whose Info.plist says Sill, the executable keeping the linker's signature.
let sillBin = bundle(path("Sill.bin"), id: sill)
expect("a Sill.bin bundle that says it is Sill: Sill.app by its bundle identifier, whatever the folder's name", sillBin,
       signature: "adHoc", bundle: sill, pathSuffix: "/Sill.bin", verdict: "sill")
// The same with another bundle identifier: the reader does not say yes to any bundle.
let otherBin = bundle(path("Other.bin"), id: "me.saffer.sill.test-host")
expect("a bundle of another identifier, not a .app: a test host", otherBin,
       signature: "adHoc", bundle: "me.saffer.sill.test-host", pathSuffix: "/Other.bin", verdict: "test")
// A bundle signed as a whole, as make-app.sh signs Sill.app (ad hoc here), then its executable started
// from outside it: through a hard link and a symlink Foundation finds no bundle, the signature stands.
let signedExe = bundle(path("Signed.bin"), id: sill)
if codesign(["-s", "-", "-f", path("Signed.bin")]) {
    expect("a bundle signed as Sill: both say so", signedExe, id: sill, signature: "adHoc", bundle: sill, pathSuffix: "/Signed.bin", verdict: "sill")
    do {
        try fm.linkItem(atPath: signedExe, toPath: path("hardlink"))
        expect("its executable through a hard link: no bundle, Sill.app by its signing identifier", path("hardlink"),
               id: sill, signature: "adHoc", bundle: "-", pathSuffix: scratch.lastPathComponent, verdict: "sill")
    } catch { print("FAIL: hard link: \(error)"); failures += 1 }
    do {
        try fm.createSymbolicLink(atPath: path("symlink"), withDestinationPath: signedExe)
        expect("its executable through a symlink: no bundle, Sill.app by its signing identifier", path("symlink"),
               id: sill, signature: "adHoc", bundle: "-", pathSuffix: scratch.lastPathComponent, verdict: "sill")
    } catch { print("FAIL: symlink: \(error)"); failures += 1 }
}
// Replaced on disk once started: the identifier is the kernel's, read from the running code.
copy(me, path("swap")); copy(me, path("swap-other"))
if codesign(["-s", "-", "-f", "-i", sill, path("swap")]), codesign(["-s", "-", "-f", "-i", "me.saffer.sill.test-other", path("swap-other")]) {
    let s = start(path("swap"), ["--facts-wait"])
    let p = Process()
    p.executableURL = URL(fileURLWithPath: s.tool); p.arguments = s.args
    let out = Pipe(), inp = Pipe()
    p.standardOutput = out; p.standardError = out; p.standardInput = inp
    do {
        try p.run()
        var got = Data()
        while !String(decoding: got, as: UTF8.self).contains("ready\n") {
            let chunk = out.fileHandleForReading.availableData
            if chunk.isEmpty { break }
            got.append(chunk)
        }
        _ = rename(path("swap-other"), path("swap"))
        inp.fileHandleForWriting.write(Data("\n".utf8)); try? inp.fileHandleForWriting.close()
        got.append(out.fileHandleForReading.readDataToEndOfFile())
        p.waitUntilExit()
        let line = String(decoding: got, as: UTF8.self).components(separatedBy: "\n").first { $0.contains("\t") } ?? ""
        let fields = line.components(separatedBy: "\t")
        check("reader: replaced on disk after it started, it still reads Sill's identifier (the kernel's) and is Sill.app",
              fields.count == 5 && fields[0] == sill && fields[4] == "sill", line.isEmpty ? String(decoding: got, as: UTF8.self) : line)
        let now = run("/usr/bin/codesign", ["-dv", path("swap")]).out
        check("reader: the file on disk is now the other one", now.contains("Identifier=me.saffer.sill.test-other"), now)
    } catch { print("FAIL: swap: \(error)"); failures += 1 }
}

// The signature reader on files.
func signatureOf(_ file: String) -> (identifier: String?, signature: AppIdentity.Signature)? {
    var code: SecStaticCode?
    guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: file) as CFURL, [], &code) == errSecSuccess, let code else { return nil }
    return AppIdentity.signature(of: code)
}
let apple = ["/System/Applications/Calculator.app", "/System/Applications/TextEdit.app", "/System/Library/CoreServices/Finder.app"]
    .first { fm.fileExists(atPath: $0) }
if let apple, let s = signatureOf(apple) {
    check("signature: \(apple) is signed with a certificate", s.signature == .certificate && s.identifier?.hasPrefix("com.apple.") == true, "\(s)")
} else {
    print("FAIL: no Apple app to read"); failures += 1
}
if let s = signatureOf(me) {
    check("signature: this check carries the linker's signature (ad hoc on Apple silicon, none on x86_64)",
          s.signature == linkerSignature && (s.identifier != nil) == (linkerSignature == .adHoc) && s.identifier != sill, "\(s)")
}
copy(me, path("unsigned"))
if linkerSignature == .unsigned || codesign(["--remove-signature", path("unsigned")]), let s = signatureOf(path("unsigned")) {
    check("signature: a copy with no signature (as an x86_64 build) is unsigned, with no identifier", s.signature == .unsigned && s.identifier == nil, "\(s)")
}
if let s = signatureOf(path("flat-sill")) {
    check("signature: the flat copy signed as Sill is ad hoc under Sill's identifier", s.signature == .adHoc && s.identifier == sill, "\(s)")
}

// The signature's information, pure (`signature(read:)`): every answer, the two that fail closed
// too, which no file on this Mac gives (Security read a copy with a damaged signature, and one deleted
// once opened, without an error).
let idKey = kSecCodeInfoIdentifier as String, certKey = kSecCodeInfoCertificates as String, flagsKey = kSecCodeInfoFlags as String
let adhocFlag = SecCodeSignatureFlags.adhoc.rawValue
let linkerFlags = NSNumber(value: adhocFlag | 0x20000)   // flags=0x20002(adhoc,linker-signed), the bare binary's
func pureSig(_ d: [String: Any]?) -> String {
    let r = AppIdentity.signature(read: d)
    return "\(r.identifier ?? "-") \(r.signature)"
}
let pure: [(String, [String: Any]?, String)] = [
    ("no information at all (the read failed): unreadable", nil, "- unreadable"),
    ("information without an identifier: unsigned", [:], "- unsigned"),
    ("information without an identifier, the ad hoc flag and all: unsigned", [flagsKey: linkerFlags], "- unsigned"),
    ("the linker's signature (adhoc, linker-signed): ad hoc", [idKey: "SillMenuBar", flagsKey: linkerFlags], "SillMenuBar adHoc"),
    ("codesign -s - (adhoc): ad hoc", [idKey: sill, flagsKey: NSNumber(value: adhocFlag)], "\(sill) adHoc"),
    ("ad hoc with an empty certificate list: ad hoc", [idKey: "x", certKey: [Any](), flagsKey: linkerFlags], "x adHoc"),
    ("a certificate chain, the hardened runtime: certificate", [idKey: sill, certKey: ["leaf", "intermediate", "root"], flagsKey: NSNumber(value: 0x10000)], "\(sill) certificate"),
    ("a certificate and the ad hoc flag: certificate (any chain at all)", [idKey: "x", certKey: ["leaf"], flagsKey: linkerFlags], "x certificate"),
    ("an identifier with no certificate and no flags: unreadable", [idKey: "x"], "x unreadable"),
    ("an identifier with no certificate, only the hardened runtime: unreadable", [idKey: "x", flagsKey: NSNumber(value: 0x10000)], "x unreadable"),
]
for (desc, d, want) in pure { check("signature, pure: \(desc)", pureSig(d) == want, pureSig(d)) }
check("signature, pure: a read that failed makes Sill.app, never a test host (the bare binary's identifier and path)",
      AppIdentity.isSillApp(facts("SillMenuBar", AppIdentity.signature(read: nil).signature, nil, build)))
check("signature, pure: an identifier with neither a certificate nor the ad hoc flag makes Sill.app",
      AppIdentity.isSillApp(facts("SillMenuBar", AppIdentity.signature(read: [idKey: "SillMenuBar"]).signature, nil, build)))

try? fm.removeItem(at: scratch)
if failures == 0 {
    print("test-host: every case passed (\(passed) checks: AppIdentity's rule, \(grid) combinations, the note, IdentityStorePlan, the reader \(sandboxed ? "under sandbox-exec" : "without sandbox-exec"))")
    exit(0)
} else {
    print("test-host: \(failures) FAILED (\(passed) passed)")
    exit(1)
}
