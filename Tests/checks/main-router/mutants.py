"""Mutants of the Mac client's MainRouter.swift: each changes it in one place, is compiled with the
check by build.sh and must make it fail. usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
F = os.path.join(WT, "Sources/MacClient/MainRouter.swift")
MUTANTS = [
    ("switch on any sets", "if let n = next, encoded != lastSets || switched {", "if let n = next {"),
    ("never switch on the host's word", "if let n = next, encoded != lastSets || switched {", "if let n = next, encoded != lastSets {"),
    ("an old host word counts", "        next = feed\n        switched = false", "        next = feed"),
    ("follow never at once", "if let began = newStreamAt, now() - began < Self.followWindow, let ps = lastPS, let frames = gop {", "if false, let began = newStreamAt, now() - began < Self.followWindow, let ps = lastPS, let frames = gop {"),
    ("follow at once whatever the age", "if let began = newStreamAt, now() - began < Self.followWindow, let ps = lastPS, let frames = gop {", "if let began = newStreamAt, now() - began < 1e9, let ps = lastPS, let frames = gop {"),
    ("follow waits without the host's word", "            next = feed\n            switched = true\n", "            next = feed\n"),
    ("the group kept across keyframes", "        if isKeyframe { gop = []; gopBytes = 0 }\n", ""),
    ("reset keeps the old sets", "target = nil; next = nil; switched = false; lastSets = nil", "target = nil; next = nil; switched = false"),
    ("the expected window is not drawn into", "return feed === target || feed === next", "return feed === target"),
    ("the sets not remembered", "        lastSets = encoded\n", ""),
]
caught = 0
for name, old, new in MUTANTS:
    src = open(F).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        mf = os.path.join(t, "MainRouter.swift"); open(mf, "w").write(src.replace(old, new, 1))
        exe = os.path.join(t, "c")
        subprocess.run([os.path.join(HERE, "build.sh"), WT, exe, f"MainRouter.swift={mf}"], capture_output=True, text=True)
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
