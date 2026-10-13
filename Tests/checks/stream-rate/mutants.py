#!/usr/bin/env python3
# Each mutant changes Sources/SillHost/StreamRate.swift in one place (in a copy under
# .build/checks/stream-rate/, never the file itself); the check (main.swift here) must fail on every one.
import subprocess, sys, os
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.abspath(os.path.join(here, '..', '..', '..'))
src = open(os.path.join(root, 'Sources', 'SillHost', 'StreamRate.swift')).read()
out = os.path.join(root, '.build', 'checks', 'stream-rate')
mutants = [
    ("the software encoder capped too", "guard !software, pixels > 0 else { return wanted }", "guard pixels > 0 else { return wanted }"),
    ("a rate exactly at the budget stepped down", "if Double(wanted) <= fits { return wanted }", "if Double(wanted) < fits { return wanted }"),
    ("no floor: 30 replaced by what fits", "?? min(wanted, rates.last!)", "?? max(1, Int(fits))"),
    ("the floor above what was asked", "?? min(wanted, rates.last!)", "?? rates.last!"),
    ("no 90 step", "static let rates = [120, 90, 60, 48, 30]", "static let rates = [120, 60, 48, 30]"),
    ("a budget of 650 MP/s", "static let hardwareBudget: Double = 520_000_000", "static let hardwareBudget: Double = 650_000_000"),
    ("a budget of 400 MP/s", "static let hardwareBudget: Double = 520_000_000", "static let hardwareBudget: Double = 400_000_000"),
]
caught = 0; ok = True
for i, (name, old, new) in enumerate(mutants, 1):
    if src.count(old) != 1:
        print(f"M{i:02} BAD      {name}: the text to change is found {src.count(old)} times"); ok = False; continue
    d = os.path.join(out, f"m{i:02}"); os.makedirs(d, exist_ok=True)
    open(os.path.join(d, "StreamRate.swift"), "w").write(src.replace(old, new))
    b = subprocess.run(["swiftc", "-O", os.path.join(d, "StreamRate.swift"), os.path.join(here, "main.swift"), "-o", os.path.join(d, "check")],
                       capture_output=True, text=True)
    if b.returncode != 0:
        print(f"M{i:02} NOBUILD  {name}"); ok = False; continue
    r = subprocess.run([os.path.join(d, "check")], capture_output=True, text=True, timeout=60)
    if r.returncode != 0:
        caught += 1; print(f"M{i:02} CAUGHT   {name}")
    else:
        ok = False; print(f"M{i:02} MISSED   {name}")
print(f"{caught} of {len(mutants)} mutants caught")
sys.exit(0 if ok and caught == len(mutants) else 1)
