"""Mutants of SpotlightMacs.swift: each changes it in one place, is compiled with the check and must
make it fail. usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
F = os.path.join(WT, "iOSClient/SpotlightMacs.swift")
MUTANTS = [
    ("any prefix read", 'guard identifier.hasPrefix("mac:") else { return nil }', ""),
    ("an empty Mac ID read", "guard !id.isEmpty, id.count <= 128,", "guard id.count <= 128,"),
    ("no length cap", "id.count <= 128, ", ""),
    ("a colon allowed", ', !id.contains(":") else', " else"),
    ("a removed Mac indexed", "macs.filter { !$0.revoked }", "macs"),
    ("a nameless Mac unnamed", '$0.name.isEmpty ? "Mac" : $0.name', "$0.name"),
    ("Direct before the network", "for route in [Route.network, .direct]", "for route in [Route.direct, .network]"),
    ("a Remote row at once", "guard waited else { return .wait }", ""),
    ("any Mac's row", "$0.route == route && $0.macID == macID", "$0.route == route"),
    ("never the saved dial", "return .dialSaved\n", "return .wait\n"),
    ("two writes at once", "if running { again = true; return false }", "if running { again = true }"),
    ("a waiting write dropped", "if running { again = true; return false }", "if running { return false }"),
    ("no rerun after a wait", "guard again else { running = false; return false }\n            again = false\n            return true", "running = false; again = false; return false"),
    ("rerun for ever", "guard again else { running = false; return false }\n            again = false", "guard again else { running = false; return false }"),
    ("stuck running", "guard again else { running = false; return false }", "guard again else { return false }"),
]
caught = 0
for name, old, new in MUTANTS:
    src = open(F).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        mf = os.path.join(t, "SpotlightMacs.swift"); open(mf, "w").write(src.replace(old, new, 1))
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
