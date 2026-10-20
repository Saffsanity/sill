"""Mutants of PrivacyModePolicy.swift (issues #133 and #141): each changes it in one place, is
compiled with the check by build.sh and must make it fail. usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
F = os.path.join(WT, "Sources/SillMenuBar/PrivacyModePolicy.swift")
MUTANTS = [
    ("virtual display gets a shield",
     "!$0.sillVirtual && $0.frame.width > 0 && $0.frame.height > 0",
     "$0.frame.width > 0 && $0.frame.height > 0"),
    ("zero-width screen gets a shield",
     "!$0.sillVirtual && $0.frame.width > 0 && $0.frame.height > 0",
     "!$0.sillVirtual && $0.frame.width >= 0 && $0.frame.height > 0"),
    ("zero-height screen gets a shield",
     "!$0.sillVirtual && $0.frame.width > 0 && $0.frame.height > 0",
     "!$0.sillVirtual && $0.frame.width > 0 && $0.frame.height >= 0"),
    ("shield activates with 0 connected devices",
     "let wantShield = privacyMode && connectedDevices > 0 && physicalScreens > 0 && !shuttingDown",
     "let wantShield = privacyMode && connectedDevices >= 0 && physicalScreens > 0 && !shuttingDown"),
    ("shield activates with 0 physical screens",
     "let wantShield = privacyMode && connectedDevices > 0 && physicalScreens > 0 && !shuttingDown",
     "let wantShield = privacyMode && connectedDevices > 0 && physicalScreens >= 0 && !shuttingDown"),
    ("shield stays active during shutdown",
     "let wantShield = privacyMode && connectedDevices > 0 && physicalScreens > 0 && !shuttingDown",
     "let wantShield = privacyMode && connectedDevices > 0 && physicalScreens > 0"),
    ("plural log line used for 1 display",
     "physicalScreens == 1 ? \"the display\" : \"\\(physicalScreens) displays\"",
     "\"\\(physicalScreens) displays\""),
    ("locks when a non-last device disconnects",
     "let lastDisconnected = hadConnectedDevices && connectedDevices == 0",
     "let lastDisconnected = hadConnectedDevices && connectedDevices <= 1"),
    ("locks when 0 devices were connected before",
     "let lastDisconnected = hadConnectedDevices && connectedDevices == 0",
     "let lastDisconnected = connectedDevices == 0"),
    ("locks even when lockOnDisconnect is off",
     "let shouldLock = lastDisconnected && lockOnDisconnect && consoleUnlocked && !shuttingDown",
     "let shouldLock = lastDisconnected && consoleUnlocked && !shuttingDown"),
    ("locks even when console is already locked",
     "let shouldLock = lastDisconnected && lockOnDisconnect && consoleUnlocked && !shuttingDown",
     "let shouldLock = lastDisconnected && lockOnDisconnect && !shuttingDown"),
    ("locks on app shutdown",
     "let shouldLock = lastDisconnected && lockOnDisconnect && consoleUnlocked && !shuttingDown",
     "let shouldLock = lastDisconnected && lockOnDisconnect && consoleUnlocked"),
]
caught = 0
for name, old, new in MUTANTS:
    src = open(F).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        mf = os.path.join(t, "PrivacyModePolicy.swift"); open(mf, "w").write(src.replace(old, new, 1))
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
