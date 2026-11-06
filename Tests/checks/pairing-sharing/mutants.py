"""Mutants of PairingWindowSharing.swift (issue #108): each changes it in one place (the rule, the
window's sharing type for each answer, the Log's lines), is compiled with the check by build.sh and
must make it fail. usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
F = os.path.join(WT, "Sources/SillMenuBar/PairingWindowSharing.swift")
RULE = "        switchOn ? .shown : .hidden\n"
ON = "on ? \"Pairing window: shown to screen sharing"
HIDDEN = "        case .hidden: .none\n"
SHOWN = "        case .shown: .readOnly\n"
MUTANTS = [
    ("the switch ignored: always hidden", RULE, "        .hidden\n"),
    ("the switch ignored: always shown", RULE, "        .shown\n"),
    ("the switch inverted", RULE, "        switchOn ? .hidden : .shown\n"),
    ("a window a device's ask opened stays hidden", RULE, "        switchOn && !byDevice ? .shown : .hidden\n"),
    ("only a window a device's ask opened is shown", RULE, "        switchOn && byDevice ? .shown : .hidden\n"),
    ("a device's window shown even with the switch off", RULE, "        switchOn || byDevice ? .shown : .hidden\n"),
    ("the two lines swapped", ON, "!" + ON),
    ("the on line without its warning",
     "; anyone who can see this Mac’s screen remotely can read its code.\"", ".\""),
    # What the window server is told (windowSharingType, under #if canImport(AppKit)).
    ("the window's sharing types swapped", HIDDEN + SHOWN,
     "        case .hidden: .readOnly\n        case .shown: .none\n"),
    ("hidden told .readOnly: never left out", HIDDEN, "        case .hidden: .readOnly\n"),
    ("shown told .none: never shown", SHOWN, "        case .shown: .none\n"),
]
caught = 0
for name, old, new in MUTANTS:
    src = open(F).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        mf = os.path.join(t, "PairingWindowSharing.swift"); open(mf, "w").write(src.replace(old, new, 1))
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
