"""Mutants of CaptureScale.swift (Sources/SillHost): each changes it in one place, is compiled with the
check (main.swift) and must make it fail. A mutant that does not compile is not counted as caught.
usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "capture-scale")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "Sources/SillHost/CaptureScale.swift")
orig = open(SRC).read()
HOLD = "        return min(knob, d)\n"
USABLE = "        guard let s, s.isFinite, s > 0 else { return nil }\n"
PIXEL = "        1 / (usable(displayScale) ?? 1)\n"
LAND = ("        return CGPoint(x: max(rect.minX, min(px, rect.maxX - pixel)),\n"
        "                       y: max(rect.minY, min(py, rect.maxY - pixel)))\n")
UNIT = "        v.isNaN ? 0 : min(max(v, 0), 1)\n"
WORDS = "        return e < knob ? base + \", the display's own (\\(times(knob)) asked)\" : base\n"
MUTANTS = [
    # The capture's pixel scale.
    ("C1 the knob never held to the display (the bug: a window on a 1x display in the top-left quarter)", HOLD,
     "        return knob\n"),
    ("C2 the display's scale whatever the knob (Standard on a 2x display at 2x)", HOLD, "        return d\n"),
    ("C3 the larger of the two (upscaled)", HOLD, "        return max(knob, d)\n"),
    ("C4 a zero or negative scale taken", USABLE, "        guard let s, s.isFinite else { return nil }\n"),
    ("C5 an infinite scale taken", USABLE, "        guard let s, s > 0 else { return nil }\n"),
    ("C6 Sill's virtual display at 1x (a staged window's capture held down)",
     "    static let virtualDisplay: CGFloat = 2\n", "    static let virtualDisplay: CGFloat = 1\n"),
    # The capture line's words.
    ("C7 the words never say what was asked", WORDS, "        return base\n"),
    ("C8 the words say it was asked when nothing was held down", WORDS,
     "        return e <= knob ? base + \", the display's own (\\(times(knob)) asked)\" : base\n"),
    ("C9 a scale of 1.5 written as a whole number", "        s.isFinite && s == s.rounded() && abs(s) < 1_000 ? ",
     "        s.isFinite && abs(s) < 1_000 ? "),
    # One pixel, and where a position lands.
    ("L1 a pixel is always a point (a 2x display's last row a point up)", PIXEL, "        CGFloat(1)\n"),
    ("L2 no scale: half a point", PIXEL, "        1 / (usable(displayScale) ?? 2)\n"),
    ("L3 the row past the last (the bottom edge off the display, as before)", LAND,
     "        return CGPoint(x: max(rect.minX, min(px, rect.maxX - pixel)),\n"
     "                       y: max(rect.minY, min(py, rect.maxY)))\n"),
    ("L4 the column past the last", LAND,
     "        return CGPoint(x: max(rect.minX, min(px, rect.maxX)),\n"
     "                       y: max(rect.minY, min(py, rect.maxY - pixel)))\n"),
    ("L5 a pixel short of the last row", LAND,
     "        return CGPoint(x: max(rect.minX, min(px, rect.maxX - pixel)),\n"
     "                       y: max(rect.minY, min(py, rect.maxY - 2 * pixel)))\n"),
    ("L6 a rectangle narrower than a pixel lands above it", LAND,
     "        return CGPoint(x: max(rect.minX, min(px, rect.maxX - pixel)),\n"
     "                       y: min(py, rect.maxY - pixel))\n"),
    ("L7 x and y swapped at the edge", LAND,
     "        return CGPoint(x: max(rect.minX, min(px, rect.maxY - pixel)),\n"
     "                       y: max(rect.minY, min(py, rect.maxX - pixel)))\n"),
    ("L8 a fraction below 0 lands outside", UNIT, "        v.isNaN ? 0 : min(v, 1)\n"),
    ("L9 NaN lands at the far edge", UNIT, "        v.isNaN ? 1 : min(max(v, 0), 1)\n"),
    ("L10 the fraction of the wrong side", "        let py = rect.minY + CGFloat(unit(y)) * rect.height\n",
     "        let py = rect.minY + CGFloat(unit(y)) * rect.width\n"),
]
caught = 0
for name, old, new in MUTANTS:
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    src = os.path.join(OUT, "CaptureScale.swift")
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
os.remove(os.path.join(OUT, "CaptureScale.swift"))
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
