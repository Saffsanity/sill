"""Mutants of the Mac client's MacKeyMap.swift: each changes it in one place, is compiled with the
check by build.sh and must make it fail. usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
F = os.path.join(WT, "Sources/MacClient/MacKeyMap.swift")
MUTANTS = [
    ("C sent as V", "8: 0x06,", "8: 0x19,"),
    ("a key left out", "        98: 0x40, 100: 0x41,", "        100: 0x41,"),
    ("left and right command swapped", "55: 0xE3,   // Left Command", "55: 0xE7,   // Left Command"),
    ("right option read as command", "58: .option, 61: .option,", "58: .option, 61: .command,"),
    ("fn sent", "kept = flags.intersection([.capsLock, .shift, .control, .option, .command])", "kept = flags.intersection([.capsLock, .shift, .control, .option, .command, .function])"),
    ("caps lock dropped", "kept = flags.intersection([.capsLock, .shift, .control, .option, .command])", "kept = flags.intersection([.shift, .control, .option, .command])"),
    ("forward delete as delete", "117: 0x4C,", "117: 0x2A,"),
]
caught = 0
for name, old, new in MUTANTS:
    src = open(F).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        mf = os.path.join(t, "MacKeyMap.swift"); open(mf, "w").write(src.replace(old, new, 1))
        exe = os.path.join(t, "c")
        subprocess.run([os.path.join(HERE, "build.sh"), WT, exe, f"MacKeyMap.swift={mf}"], capture_output=True, text=True)
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
