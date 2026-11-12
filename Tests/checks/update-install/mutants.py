"""Update Now's mutants (docs/one-click-update-plan.md §11, G1): each changes one of the app's update files
in one place, in a copy of Sources/SillMenuBar; build.sh compiles the check from the copy and the check
reads the copy's sources, and it must fail. usage: mutants.py WORKTREE [NAME…] (only the mutants named)"""
import os, shutil, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(WT, "Sources/SillMenuBar")
POL, MAN, ARC, INS, APP = "UpdateInstallPolicy.swift", "UpdateManifest.swift", "UpdateArchive.swift", "UpdateInstaller.swift", "AppUpdater.swift"
MUTANTS = [
    # The version rule and the release.
    ("the same version installed", POL, "guard version > running else { return .failure(.notNewer(versionText)) }", "guard version >= running else { return .failure(.notNewer(versionText)) }"),
    ("the same release fetched", POL, "guard version > running else { return .failure(.releaseNotNewer) }", "guard version >= running else { return .failure(.releaseNotNewer) }"),
    ("loose versions", MAN, "parts.allSatisfy({ (1...9).contains($0.utf8.count) && $0.utf8.allSatisfy { $0 >= 0x30 && $0 <= 0x39 } })", "parts.allSatisfy({ (1...9).contains($0.utf8.count) })"),
    ("drafts and prereleases", POL, "if object[\"draft\"] as? Bool == true || object[\"prerelease\"] as? Bool == true {", "if false {"),
    ("GitHub's URL for an asset", POL, "a[\"browser_download_url\"] as? String == url.absoluteString else {", "true else {"),
    ("an upload not finished", POL, "guard a[\"state\"] as? String == \"uploaded\" else {", "guard true else {"),
    ("two zips", POL, "guard matches.count == 1 else {", "guard true else {"),
    ("no manifest read as unreadable", POL, "            return .failure(.notSigned)\n", "            return .failure(.releaseUnreadable(\"no manifest\"))\n"),
    ("the manifest's size unchecked", POL, "guard m.size == r.zip.size else { return .manifestMismatch(\"size\") }", ""),
    ("GitHub's digest unchecked", POL, "if let digest = r.zip.digest, digest != m.sha256 { return .manifestMismatch(\"sha256\") }", ""),
    # Where downloads may go.
    ("credentials in an origin", POL, "url.user == nil, url.password == nil else { return nil }", "true else { return nil }"),
    ("any path on the asset host", POL, "return url.path.hasPrefix(endpoints.redirectPathPrefix)", "return true"),
    ("http to the asset host", POL, "redirectOrigins: [\"https://release-assets.githubusercontent.com\",", "redirectOrigins: [\"http://release-assets.githubusercontent.com\","),
    ("github.com as a redirect target", POL, "\"https://objects.githubusercontent.com\"],", "\"https://objects.githubusercontent.com\", \"https://github.com\"],"),
    # The trust.
    ("no team in the requirement", POL, " and certificate leaf[subject.OU] = \\\"9B2KKVM937\\\"\"", "\""),
    ("notarization not asked", POL, "signer: UpdateInstallPolicy.pinnedRequirement, notarized: true,", "signer: UpdateInstallPolicy.pinnedRequirement, notarized: false,"),
    ("no stapled ticket asked", POL, "teamID: \"9B2KKVM937\", stapledTicket: true,", "teamID: \"9B2KKVM937\", stapledTicket: false,"),
    ("the running requirement not asked", POL, "        runningRequirement: true,\n", "        runningRequirement: false,\n"),
    ("notarization ignored", POL, "if trust.notarized, !f.notarized { return .failure(.notNotarized) }", ""),
    ("any team", POL, "guard f.identifier == trust.identifier, trust.teamID == nil || f.teamID == trust.teamID else", "guard f.identifier == trust.identifier else"),
    ("the keychain group unchecked", POL, "guard case .strings(let values)? = f.entitlements[key], values.contains(value) else", "guard true else"),
    ("a debuggable build", POL, "if f.entitlements[\"com.apple.security.get-task-allow\"] == .bool(true) { return .failure(.debuggable) }", ""),
    ("any build number", POL, "guard build == manifest.build else { return .failure(.notManifest(\"build\")) }", ""),
    ("any code", POL, "guard f.cdhashes == manifest.cdhashes else { return .failure(.notManifest(\"code\")) }", ""),
    ("any macOS", POL, "guard needed <= have else { return .failure(.needsNewerMacOS(minimum)) }", ""),
    # Refusals.
    ("translocation ignored", POL, "if s.translocated { return .translocated }", ""),
    ("another account ignored", POL, "if let other = s.otherAccounts.first { return .otherAccount(other) }", ""),
    ("another owner's copy", POL, "        if !s.ownedByUser { return .otherOwner(s.ownerName) }\n", ""),
    ("no room needed to the byte", POL, "if let free = s.freeBytes, free < s.neededBytes {", "if let free = s.freeBytes, free <= s.neededBytes {"),
    # The state machine.
    ("a device joining never asked about", POL, "if Set(devices.map(\\.key)).isSubset(of: Set(s.consented)) { n.phase = .installing; return (n, [.install]) }", "n.phase = .installing; return (n, [.install])"),
    ("consent by name", POL, "        case (.confirming(let devices), .confirm):\n            n.consented = devices.map(\\.key)", "        case (.confirming(let devices), .confirm):\n            n.consented = devices.map(\\.name)"),
    ("the old copy deleted when not put back", POL, "return (n, f.cleanUp ? [.cleanUp] : [])", "return (n, [.cleanUp])"),
    ("cancel while installing", POL, "case (.ready, .cancel), (.fetching, .cancel),", "case (.ready, .cancel), (.installing, .cancel), (.fetching, .cancel),"),
    ("a copy not put back cleaned up", POL, "case .checkAfterSwap(_, let putBack), .didNotStart(_, let putBack): return putBack", "case .checkAfterSwap, .didNotStart: return true"),
    ("Update Now enabled when refused", POL, "p.updateNowEnabled = refusal == nil\n", "p.updateNowEnabled = true\n"),
    ("the menu opens Settings when refused", POL, "if available, refusal == nil {", "if available {"),
    # The manifest.
    ("any signature", MAN, "for candidate in candidates where candidate.key.isValidSignature(parsed.signature, for: parsed.signed) {", "for _ in candidates {"),
    ("no key as an unknown key", MAN, "guard !keys.isEmpty else { return .failure(.noKey) }", ""),
    ("carriage returns", MAN, "bytes.allSatisfy({ $0 == 0x0A || (0x20...0x7E).contains($0) })", "bytes.allSatisfy({ $0 == 0x0A || $0 == 0x0D || (0x20...0x7E).contains($0) })"),
    ("a version that is not the tag's", MAN, "guard let versionText = field(\"version\"), versionText == String(tag.dropFirst()),", "guard let versionText = field(\"version\"),"),
    ("the key line left unsigned", MAN, "let signedEnd = lines[0..<i].reduce(0)", "let signedEnd = lines[0..<(i - 1)].reduce(0)"),
    ("small-order keys", MAN, "if smallOrder.contains(where: { Array($0[0..<31]) == Array(bytes[0..<31]) && $0[31] == bytes[31] & 0x7F }) { return nil }", ""),
    ("non-canonical base64", MAN, "signature.base64EncodedString() == signatureText else { return .failure(.format(\"signature\")) }", "true else { return .failure(.format(\"signature\")) }"),
    ("a shorter key ID", MAN, "SHA256.hash(data: raw).prefix(4)", "SHA256.hash(data: raw).prefix(3)"),
    # The archive.
    ("non-ASCII names", ARC, "nameBytes.allSatisfy({ (0x20...0x7E).contains($0) && $0 != 0x5C }) else {", "true else {"),
    ("dot-dot", ARC, "parts.allSatisfy({ !$0.isEmpty && $0 != \".\" && $0 != \"..\" })", "parts.allSatisfy({ !$0.isEmpty })"),
    ("case-sensitive duplicates", ARC, "let key = r.components.joined(separator: \"/\").lowercased()", "let key = r.components.joined(separator: \"/\")"),
    ("writing through a link", ARC, "                case .link?: return .failure(.throughLink(e.path))\n                default: break\n                }\n            }\n            guard case .link", "                default: break\n                }\n            }\n            guard case .link"),
    ("shared bytes", ARC, "guard end <= next, i == 0 || spans[i - 1].headerOffset < r.headerOffset else { return .failure(.overlap(r.name)) }", ""),
    ("the local name unchecked", ARC, "Array(b[(headerOffset + 30)..<(headerOffset + 30 + nameLength)]) == nameBytes,", ""),
    ("encryption", ARC, "if flags & 0x0041 != 0 { return .failure(.encrypted(name)) }", ""),
    ("setuid", ARC, "guard type == 0o040000 || type == 0o100000 || type == 0o120000, mode & 0o7000 == 0 else {", "guard type == 0o040000 || type == 0o100000 || type == 0o120000 else {"),
    ("no total", ARC, "guard totalBytes <= limits.totalBytes else { return .failure(.tooLarge) }", ""),
    ("no ratio", ARC, "if method == 8 { guard compressed > 0, size <= compressed * limits.ratio else { return .failure(.badSizes(name)) } }", ""),
    ("inflate past the size", ARC, "guard produced <= size else { return .failure(.inflate(name)) }", ""),
    ("a walk through a link", ARC, "                if case .link? = kinds[walked.joined(separator: \"/\").lowercased()] { return .failure(.throughLink(e.path)) }\n", ""),
    ("links at the signature's paths", ARC, "if lower.count >= 3, lower[1] == \"contents\", lower[2] == \"_codesignature\" || (lower.count == 3 && lower[2] == \"coderesources\") {", "if false {"),
    ("16 digits of the SHA-256 in the prompt", MAN, "        var rest = Substring(hex)\n", "        var rest = Substring(hex.prefix(16))\n"),
    ("links outside", ARC, "guard let resolved = resolve(target, from: Array(e.components.dropLast())), resolved.count > 1,", "guard let resolved = Optional(Array(e.components)), resolved.count > 1,"),
    # Sill.app's sources (T21): read by the check, not compiled by it.
    ("a default read by the installer", INS, "    let userAgent: String\n", "    let userAgent: String\n    let host = UserDefaults.standard.string(forKey: \"SillUpdateHost\")\n"),
    ("the environment read by the updater", APP, "    let available: Bool\n", "    let available: Bool\n    let override = ProcessInfo.processInfo.environment[\"SILL_UPDATE\"]\n"),
    ("endpoints of the app's own", APP, "installer = UpdateInstaller(trust: trust, endpoints: .github,", "installer = UpdateInstaller(trust: trust, endpoints: Policy.Endpoints(local),"),
    ("a trust of the app's own", APP, "let trust = Policy.Trust.release", "let trust = Policy.Trust(signer: \"anchor apple\", notarized: false)"),
]
caught = 0
ONLY = sys.argv[2:]
if ONLY: MUTANTS = [m for m in MUTANTS if m[0] in ONLY]
for name, file, old, new in MUTANTS:
    src = open(os.path.join(SRC, file)).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        copy = os.path.join(t, "SillMenuBar")
        shutil.copytree(SRC, copy)
        open(os.path.join(copy, file), "w").write(src.replace(old, new, 1))
        exe = os.path.join(t, "c")
        subprocess.run([os.path.join(HERE, "build.sh"), WT, exe, copy], capture_output=True, text=True)
        if not os.path.exists(exe): print(f"{name}: did not compile"); continue
        r = subprocess.run([exe, copy, os.path.join(WT, "Sources")], capture_output=True, text=True, timeout=300)
        failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        if r.returncode != 0:
            caught += 1
            print(f"{name}: caught ({failed[0][:100] if failed else f'exit status {r.returncode}'})")
        else:
            print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
