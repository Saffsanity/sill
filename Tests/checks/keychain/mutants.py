"""Mutants of IdentityStorePlan.swift (docs/keychain-plan.md §4): each changes it in one place, is
compiled with the check by build.sh and must make it fail. usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
F = os.path.join(WT, "Sources/SillMenuBar/IdentityStorePlan.swift")
MUTANTS = [
    ("bare binary reaches the real-app branch",
     "if synthetic || !bundled {", "if synthetic && !bundled {"),
    ("Sill.app --synthetic takes the file store",
     "if synthetic, !bundled, let dir = testRemoteDir, !dir.isEmpty { return .testDirectory(dir) }",
     "if !bundled, let dir = testRemoteDir, !dir.isEmpty { return .testDirectory(dir) }"),
    ("a non-synthetic bare binary takes the file store",
     "if synthetic, !bundled, let dir = testRemoteDir, !dir.isEmpty { return .testDirectory(dir) }",
     "if synthetic || !bundled, let dir = testRemoteDir, !dir.isEmpty { return .testDirectory(dir) }"),
    ("entitled real app falls to legacy",
     "if let group = entitledAccessGroup, !group.isEmpty { return .dataProtection(accessGroup: group) }",
     "if let group = entitledAccessGroup, !group.isEmpty { _ = group; return .legacy }"),
    ("an empty entitlement counts as one",
     "if let group = entitledAccessGroup, !group.isEmpty { return .dataProtection(accessGroup: group) }",
     "if let group = entitledAccessGroup { return .dataProtection(accessGroup: group) }"),
    ("unentitled real app goes to data-protection with an empty group",
     "return .legacy\n    }", "return .dataProtection(accessGroup: entitledAccessGroup ?? \"\")\n    }"),
    ("a test host uses the legacy keychain",
     "return .memory\n        }", "return .legacy\n        }"),
]
caught = 0
for name, old, new in MUTANTS:
    src = open(F).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        mf = os.path.join(t, "IdentityStorePlan.swift"); open(mf, "w").write(src.replace(old, new, 1))
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
