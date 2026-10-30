"""Mutants of PinchRouting.swift (iOSClient): each changes it in one place and must make the check
(main.swift) fail. usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "pinch-routing")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/PinchRouting.swift")
orig = open(SRC).read()
TOUCH = "        if !fingersOnGlass { return macTakesPinch ? .mac : .none }\n"
FINGERS = "        return zoomApp && macTakesPinch ? .mac : .picture\n"
MUTANTS = [
    ("M1 a trackpad's pinch for a Mac that cannot take it is the Mac's", TOUCH,
     "        if !fingersOnGlass { return .mac }\n"),
    ("M2 a trackpad's pinch for a Mac that takes it is nobody's", TOUCH,
     "        if !fingersOnGlass { return .none }\n"),
    ("M3 a trackpad's pinch is the picture's", TOUCH,
     "        if !fingersOnGlass { return macTakesPinch ? .picture : .none }\n"),
    ("M4 a trackpad's pinch follows the stored choice", TOUCH,
     "        if !fingersOnGlass { return zoomApp && macTakesPinch ? .mac : .none }\n"),
    ("M5 Zoom App ignored for fingers: always the picture", FINGERS,
     "        return .picture\n"),
    ("M6 fingers always the Mac's", FINGERS,
     "        return .mac\n"),
    ("M7 Zoom Stream sends fingers to the Mac", FINGERS,
     "        return macTakesPinch ? .mac : .picture\n"),
    ("M8 a kept Zoom App takes the picture's zoom from a Mac that cannot take the pinch", FINGERS,
     "        return zoomApp ? .mac : .picture\n"),
    ("M9 the Mac's choice judged by the choice alone, picture otherwise lost", FINGERS,
     "        return zoomApp && macTakesPinch ? .mac : .none\n"),
    ("M10 the two answers swapped for fingers", FINGERS,
     "        return zoomApp && macTakesPinch ? .picture : .mac\n"),
]
caught = 0
for name, old, new in MUTANTS:
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    src = os.path.join(OUT, "PinchRouting.swift")
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
        print(f"{name}: caught ({len(failed)} FAIL lines; first: {failed[0][:160] if failed else ''})")
    else:
        print(f"{name}: SURVIVED")
print(f"{caught} of {len(MUTANTS)} mutants caught")
