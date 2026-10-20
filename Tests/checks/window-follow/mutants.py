"""Mutants of WindowFollow.swift: each changes it in one place, is compiled with the check by build.sh
and must make it fail. usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
F = os.path.join(WT, "Sources/SillHost/WindowFollow.swift")
MUTANTS = [
    ("the first catalog follows", "guard let previous, let topmost, topmost != activeID else { return nil }", "guard let topmost, topmost != activeID else { return nil }\n        let previous = previous ?? []"),
    ("old windows count as new", "guard !seen.contains(topmost), !previous.contains(where: { $0.id == topmost }),\n", "guard true,\n"),
    ("a window back from the Dock counts as new", "guard !seen.contains(topmost), !previous", "guard !previous"),
    ("only the earlier catalogs judge newness, not the last", "!seen.contains(topmost), !previous.contains(where: { $0.id == topmost }),", "!seen.contains(topmost),"),
    ("another app's window followed", "guard !app.isEmpty, new.bundleID == app else { return nil }", "guard !app.isEmpty else { return nil }"),
    ("empty bundle IDs match", "guard !app.isEmpty, new.bundleID == app else { return nil }", "guard new.bundleID == app else { return nil }"),
    ("app only from the current catalog", "(current.first { $0.id == activeID } ?? previous.first { $0.id == activeID })?.bundleID", "current.first { $0.id == activeID }?.bundleID"),
    ("an unlisted window followed", "let new = current.first(where: { $0.id == topmost }) else { return nil }", "let new = (current + previous).first(where: { $0.id == topmost }) ?? current.first else { return nil }"),
    ("back to the oldest, not the latest", "while let last = rest.popLast() {", "while !rest.isEmpty { let last = rest.removeFirst()"),
    ("back to a closed window", "if current.contains(where: { $0.id == last }) { return (last, rest) }", "return (last, rest)"),
    ("another defaults key", "package static let defaultsKey = \"followNewWindows\"", "package static let defaultsKey = \"followWindows\""),
]
caught = 0
for name, old, new in MUTANTS:
    src = open(F).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        mf = os.path.join(t, "WindowFollow.swift"); open(mf, "w").write(src.replace(old, new, 1))
        exe = os.path.join(t, "c")
        subprocess.run([os.path.join(HERE, "build.sh"), WT, exe, mf], capture_output=True, text=True)
        if not os.path.exists(exe): print(f"{name}: did not compile"); continue
        r = subprocess.run([exe], capture_output=True, text=True, timeout=300)
        failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        if r.returncode != 0:
            caught += 1
            print(f"{name}: caught ({failed[0][:90] if failed else f'exit status {r.returncode}'})")
        else:
            print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
