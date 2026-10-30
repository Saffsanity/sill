"""Mutants of AppIdentity.swift (the security scan's finding 1): each changes it in one place (a
witness of the rule dropped or loosened, the rule before the fix, the note, the reader), is compiled
with the check by build.sh and must make it fail. usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
F = os.path.join(WT, "Sources/SillMenuBar/AppIdentity.swift")
SIGNED = "if let id = f.signingIdentifier, id.lowercased() == sill { return true }"
SWITCH = "        case .certificate, .unreadable: return true\n        case .adHoc, .unsigned: break\n"
BUNDLE = "if let id = f.bundleIdentifier, id.lowercased() == sill { return true }"
FOLDER = "return (f.bundlePath as NSString).pathExtension.lowercased() == \"app\""
NOTE = "guard isSillApp(f), (f.bundlePath as NSString).pathExtension.lowercased() != \"app\" else { return nil }"
MUTANTS = [
    # The rule.
    ("Sill's identifier mistyped", "static let sill = \"me.saffer.sill.mac\"", "static let sill = \"me.saffer.sill.app\""),
    ("the rule before the fix: the folder's extension alone",
     "        " + SIGNED + "\n        switch f.signature {",
     "        return (f.bundlePath as NSString).pathExtension == \"app\"\n        switch f.signature {"),
    ("the signing identifier is no witness", "        " + SIGNED + "\n", ""),
    ("the signing identifier compared in its own case", SIGNED, SIGNED.replace("id.lowercased() == sill", "id == sill")),
    ("a certificate is no witness", SWITCH, "        case .unreadable: return true\n        case .certificate, .adHoc, .unsigned: break\n"),
    ("an unreadable signature is no witness", SWITCH, "        case .certificate: return true\n        case .unreadable, .adHoc, .unsigned: break\n"),
    ("ad hoc counts as a certificate", SWITCH, "        case .certificate, .unreadable, .adHoc: return true\n        case .unsigned: break\n"),
    ("no signature counts as a certificate", SWITCH, "        case .certificate, .unreadable, .unsigned: return true\n        case .adHoc: break\n"),
    ("the bundle identifier is no witness", "        " + BUNDLE + "\n", ""),
    ("the bundle identifier compared in its own case", BUNDLE, BUNDLE.replace("id.lowercased() == sill", "id == sill")),
    ("any bundle identifier counts", BUNDLE, "if let id = f.bundleIdentifier, !id.isEmpty { return true }"),
    ("the .app folder is no witness", "        " + FOLDER + "\n    }", "        return false\n    }"),
    ("the .app folder in its own case", FOLDER, "return (f.bundlePath as NSString).pathExtension == \"app\""),
    # The note.
    ("a note for Sill.app in its .app too", NOTE, "guard isSillApp(f) else { return nil }"),
    ("a note for the bare binary too", NOTE, "guard (f.bundlePath as NSString).pathExtension.lowercased() != \"app\" else { return nil }"),
    ("the note's reasons out of order: a certificate before Sill's identifier",
     "        if let id = f.signingIdentifier, id.lowercased() == sill {\n            why = \"signed \\(id)\"\n        } else if f.signature == .certificate {\n            why = \"signed with a certificate\"\n",
     "        if f.signature == .certificate {\n            why = \"signed with a certificate\"\n        } else if let id = f.signingIdentifier, id.lowercased() == sill {\n            why = \"signed \\(id)\"\n"),
    # The reader.
    ("the kernel's identifier unread: the file on disk's", "signingIdentifier: kernel ?? signed.identifier", "signingIdentifier: signed.identifier"),
    ("the running code's signature unread", "            signed = AppIdentity.signature(of: onDisk)\n", "            _ = onDisk\n"),
    ("a certificate chain unread",
     "        if let chain = d[kSecCodeInfoCertificates as String] as? [Any], !chain.isEmpty { return (id, .certificate) }\n", ""),
    ("the ad hoc flag unread", "        if flags & SecCodeSignatureFlags.adhoc.rawValue != 0 { return (id, .adHoc) }\n", ""),
    ("a signature that could not be read is ad hoc (a test host)",
     "guard let d else { return (nil, .unreadable) }", "guard let d else { return (nil, .adHoc) }"),
    ("an identifier with neither a certificate nor the ad hoc flag is ad hoc (a test host)",
     "        return (id, .unreadable)\n", "        return (id, .adHoc)\n"),
    ("no signature read as unreadable",
     "guard let id = d[kSecCodeInfoIdentifier as String] as? String else { return (nil, .unsigned) }",
     "guard let id = d[kSecCodeInfoIdentifier as String] as? String else { return (nil, .unreadable) }"),
    ("the bundle's identifier unread", "bundleIdentifier: Bundle.main.bundleIdentifier", "bundleIdentifier: nil"),
]
caught = 0
for name, old, new in MUTANTS:
    src = open(F).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        mf = os.path.join(t, "AppIdentity.swift"); open(mf, "w").write(src.replace(old, new, 1))
        exe = os.path.join(t, "c")
        subprocess.run([os.path.join(HERE, "build.sh"), WT, exe, mf], capture_output=True, text=True)
        if not os.path.exists(exe):
            print(f"{name}: did not compile (caught)"); caught += 1; continue
        r = subprocess.run([exe], capture_output=True, text=True, timeout=300)
        if r.returncode != 0:
            caught += 1
            failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
            print(f"{name}: caught ({failed[0][:90] if failed else f'exit {r.returncode}'})")
        else:
            print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
