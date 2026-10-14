"""Mutants of ConnectionInfo.swift: each changes it in one place, is compiled with the check and must
make it fail. usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
F = os.path.join(WT, "iOSClient/ConnectionInfo.swift")
MUTANTS = [
    ("an empty name kept", 'value: f.mac.isEmpty ? "–" : f.mac', "value: f.mac"),
    ("no route reads as Wi-Fi", 'value: f.route ?? "–"', 'value: f.route ?? "Wi-Fi"'),
    ("no frames read as zero", 'f.received.map { "\\($0) fps" } ?? "–"', 'f.received.map { "\\($0) fps" } ?? "0 fps"'),
    ("no sample reads as zero", 'guard let s else { return "–" }', 'guard let s else { return "0 ms" }'),
    ("worst always said", "s.max > s.median ?", "s.max >= s.median ?"),
    ("worst never said", "s.max > s.median ?", "false ?"),
    ("protocol dropped", 'f.hostProtocol.map { "\\(v), protocol \\($0)" } ?? v', "v"),
    ("rows out of order", 'Row(label: "Round trip", value: ms(f.rtt)),\n            Row(label: "Frame age", value: ms(f.frameAge)),',
     'Row(label: "Frame age", value: ms(f.frameAge)),\n            Row(label: "Round trip", value: ms(f.rtt)),'),
    ("frame age shows the rtt", 'Row(label: "Frame age", value: ms(f.frameAge))', 'Row(label: "Frame age", value: ms(f.rtt))'),
    ("no header line", '"Sill connection information, \\(stamp)\\n" + ', ""),
    ("non-breaking hyphens pasted", 'replacingOccurrences(of: "\\u{2011}", with: "-")', 'replacingOccurrences(of: "\\u{2011}", with: "\\u{2011}")'),
    ("lines without the label", '"\\($0.label): \\($0.value)\\n"', '"\\($0.value)\\n"'),
]
caught = 0
for name, old, new in MUTANTS:
    src = open(F).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        mf = os.path.join(t, "ConnectionInfo.swift"); open(mf, "w").write(src.replace(old, new, 1))
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
