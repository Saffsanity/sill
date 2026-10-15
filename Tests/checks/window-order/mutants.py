"""Mutants of WindowOrder.swift: each changes it in one place, is compiled with the check and
StreamProtocol's other sources, and must make the check fail. usage: mutants.py ROOT"""
import glob, os, shutil, subprocess, sys, tempfile
ROOT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
F = os.path.join(ROOT, "Sources/StreamProtocol/WindowOrder.swift")
MUTANTS = [
    ("newcomers last", "var order = listed.filter { !known.contains($0) } + seen", "var order = seen + listed.filter { !known.contains($0) }"),
    ("gone windows forgotten at once", "var order = listed.filter { !known.contains($0) } + seen", "var order = listed.filter { !known.contains($0) } + seen.filter { listed.contains($0) }"),
    ("no cap", "guard order.count > cap else { return order }", "return order"),
    ("the cap forgets listed windows", "guard excess > 0, !now.contains(id) else { return true }", "guard excess > 0 else { return true }"),
    ("the cap forgets the newest", "order = Array(order.reversed().filter { id in", "order = Array(order.filter { id in"),
    ("the first list counts as new", "guard !order.isEmpty, !seen.isEmpty else { return nil }", "guard !order.isEmpty else { return nil }"),
    ("an unarranged bar reordered", "guard !order.isEmpty, !seen.isEmpty else { return nil }", "guard !seen.isEmpty else { return nil }"),
    ("a returning window counts as new", "listed.filter { !seen.contains($0) && !held.contains($0) }", "listed.filter { !held.contains($0) }"),
    ("an arranged window counts as new", "listed.filter { !seen.contains($0) && !held.contains($0) }", "listed.filter { !seen.contains($0) }"),
    ("new windows last on the device", "return fresh.isEmpty ? nil : fresh + order", "return fresh.isEmpty ? nil : order + fresh"),
]
caught = 0
for name, old, new in MUTANTS:
    src = open(F).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        for f in glob.glob(os.path.join(ROOT, "Sources/StreamProtocol/*.swift")):
            shutil.copy(f, t)
        open(os.path.join(t, "WindowOrder.swift"), "w").write(src.replace(old, new, 1))
        exe = os.path.join(t, "c")
        subprocess.run(["swiftc", "-O"] + glob.glob(os.path.join(t, "*.swift")) + [os.path.join(HERE, "main.swift"), "-o", exe],
                       capture_output=True, text=True)
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
