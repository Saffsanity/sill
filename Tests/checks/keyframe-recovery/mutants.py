"""Mutants of KeyframeRecovery.swift: each changes it in one place, is compiled with the check and must
make it fail. usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
F = os.path.join(WT, "iOSClient/KeyframeRecovery.swift")
MUTANTS = [
    ("asks with nothing streaming", "guard streaming else { return false }", "_ = streaming"),
    ("spacing off by its edge", "now - last < Self.spacing", "now - last <= Self.spacing"),
    ("no spacing", "now - last < Self.spacing", "false"),
    ("a refused ask counts", "guard streaming else { return false }", "guard streaming else { lastAsked = now; return false }"),
    ("an ask not remembered", "lastAsked = now\n        return true", "return true"),
    ("a clock gone back holds it", "if let last = lastAsked, now >= last,", "if let last = lastAsked,"),
    ("spacing of 1 s", "static let spacing: TimeInterval = 2", "static let spacing: TimeInterval = 1"),
]
caught = 0
for name, old, new in MUTANTS:
    src = open(F).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        mf = os.path.join(t, "KeyframeRecovery.swift"); open(mf, "w").write(src.replace(old, new, 1))
        exe = os.path.join(t, "c")
        subprocess.run(["swiftc", "-O", mf, os.path.join(HERE, "main.swift"), "-o", exe], capture_output=True, text=True)
        if not os.path.exists(exe): print(f"{name}: did not compile"); continue
        r = subprocess.run([exe], capture_output=True, text=True, timeout=60)
        failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        if r.returncode != 0:
            caught += 1
            print(f"{name}: caught ({failed[0][:90] if failed else f'exit status {r.returncode}'})")
        else:
            print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
