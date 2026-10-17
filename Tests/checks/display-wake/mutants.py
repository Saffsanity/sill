"""Mutants of DisplayWakePolicy.swift (docs/display-wake-plan.md): each changes it in one place, is
compiled with the check by build.sh and must make it fail. usage: mutants.py ROOT"""
import os, subprocess, sys, tempfile
ROOT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
F = os.path.join(ROOT, "Sources/SillHost/DisplayWakePolicy.swift")
MUTANTS = [
    ("a longer interval", "static let interval: TimeInterval = 10", "static let interval: TimeInterval = 60"),
    ("a shorter interval", "static let interval: TimeInterval = 10", "static let interval: TimeInterval = 5"),
    ("the interval's edge refused", "now - last < Self.interval", "now - last <= Self.interval"),
    ("a clock going back silences it", "now - last < Self.interval, now >= last", "now - last < Self.interval"),
    ("a connect rate-limited like activity", "case .connected:\n            break", "case .connected:\n            if let last = lastDeclared, now - last < Self.interval { return false }"),
    ("activity never rate-limited", "if let last = lastDeclared, now - last < Self.interval, now >= last { return false }", "break"),
    ("a declaration not noted", "        lastDeclared = now\n        return true", "        return true"),
    ("allLeft forgets nothing", "        lastDeclared = nil\n    }", "    }"),
    ("a refusal declares", "now >= last { return false }", "now >= last { return true }"),
]
caught = 0
for name, old, new in MUTANTS:
    src = open(F).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        mf = os.path.join(t, "DisplayWakePolicy.swift"); open(mf, "w").write(src.replace(old, new, 1))
        exe = os.path.join(t, "c")
        subprocess.run([os.path.join(HERE, "build.sh"), ROOT, exe, mf], capture_output=True, text=True)
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
