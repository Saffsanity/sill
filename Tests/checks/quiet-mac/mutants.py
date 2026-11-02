"""Mutants of QuietMac.swift (Sources/SillHost): each changes it in one place, is compiled with the check
(main.swift) and must make it fail. A mutant that does not compile is not counted as caught.
usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "quiet-mac")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "Sources/SillHost/QuietMac.swift")
orig = open(SRC).read()
RULE = "        (macOS.major, macOS.minor) >= (14, 2) && declared && !synthetic && permission != .denied && !playOnMac\n"
MUTANTS = [
    ("Q1 granted read as declined", "        case 0: return .granted\n", "        case 0: return .denied\n"),
    ("Q2 declined read as granted", "        case 1: return .denied\n", "        case 1: return .granted\n"),
    ("Q3 not asked read as declined", "        default: return .unknown\n", "        default: return .denied\n"),
    ("Q11 not asked: the tap first (a prompt left unanswered leaves no sound)", "        case .unknown: return .screenWhileAsking\n", "        case .unknown: return .tap\n"),
    ("Q12 not asked: never asked", "        case .unknown: return .screenWhileAsking\n", "        case .unknown: return .screen\n"),
    ("Q13 granted: ScreenCaptureKit", "        case .granted: return .tap\n", "        case .granted: return .screen\n"),
    ("Q4 macOS 14.0 taps", RULE, "        (macOS.major, macOS.minor) >= (14, 0) && declared && !synthetic && permission != .denied && !playOnMac\n"),
    ("Q5 macOS 14.2 does not tap", RULE, "        (macOS.major, macOS.minor) > (14, 2) && declared && !synthetic && permission != .denied && !playOnMac\n"),
    ("Q6 the minor version ignored", RULE, "        macOS.major >= 14 && declared && !synthetic && permission != .denied && !playOnMac\n"),
    ("Q7 no usage string taps", RULE, "        (macOS.major, macOS.minor) >= (14, 2) && !synthetic && permission != .denied && !playOnMac\n"),
    ("Q8 a synthetic host taps", RULE, "        (macOS.major, macOS.minor) >= (14, 2) && declared && permission != .denied && !playOnMac\n"),
    ("Q9 declined still taps", RULE, "        (macOS.major, macOS.minor) >= (14, 2) && declared && !synthetic && !playOnMac\n"),
    ("Q10 not asked does not tap", RULE, "        (macOS.major, macOS.minor) >= (14, 2) && declared && !synthetic && permission == .granted && !playOnMac\n"),
    ("Q14 Play on the Mac too ignored", RULE, "        (macOS.major, macOS.minor) >= (14, 2) && declared && !synthetic && permission != .denied\n"),
]
caught = 0
for name, old, new in MUTANTS:
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    src = os.path.join(OUT, "QuietMac.swift")
    open(src, "w").write(orig.replace(old, new, 1))
    exe = os.path.join(OUT, "mutant")
    if os.path.exists(exe): os.remove(exe)
    c = subprocess.run(["swiftc", "-O", src, os.path.join(SP, "main.swift"), "-o", exe], capture_output=True, text=True)
    if c.returncode != 0:
        print(f"{name}: did not compile: {c.stderr.strip().splitlines()[0] if c.stderr.strip() else ''}"); continue
    r = subprocess.run([exe], capture_output=True, text=True, timeout=600)
    failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
    if r.returncode != 0:
        caught += 1
        print(f"{name}: caught ({failed[0][:110] if failed else f'exit {r.returncode}'})")
    else:
        print(f"{name}: NOT CAUGHT")
os.remove(os.path.join(OUT, "QuietMac.swift"))
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
