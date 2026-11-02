"""Mutants of CaptureScale.swift (Sources/SillHost; CaptureScale, VirtualDisplaySize with the window's size on
the virtual display, InputLanding): each changes it in one place, is compiled with the check (main.swift) and
must make it fail. A mutant that does not compile is not counted as caught.
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
GUARD = "        guard let d = usable(displayScale), e == d else { return evenPixels(points * e) }\n"
UP = "        let whole = Int((points * e - 0.001).rounded(.up))\n"
EVENUP = "        return whole + (whole & 1)\n"
WANT = "        let want = windowSize(points, knob: knob, displayScale: displayScale)\n"
CMP = "        return want.width != encoder.width || want.height != encoder.height\n"
SIDES = ("        (windowPixels(points.width, knob: knob, displayScale: displayScale),\n"
         "         windowPixels(points.height, knob: knob, displayScale: displayScale))\n")
EVEN = "func evenPixels(_ v: CGFloat) -> Int { Int(v.rounded(.down)) & ~1 }\n"
STAGE = ("        return CGSize(width: min(max((panel.width / s).rounded(), 1), maxWindowSide),\n"
         "                      height: min(max((panel.height / s).rounded(), 1), maxWindowSide))\n")
STAGE_GUARD = ("        guard let panel, panel.width.isFinite, panel.height.isFinite, panel.width > 0, panel.height > 0 "
               "else { return own }\n")
STAGE_SCALE = "        let s = scale.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 1\n"
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
    # A window's capture size: an odd side up to even where it is drawn 1:1, and the restart rule.
    ("W1 a window's odd side down to even (the blur: 1117 columns shrunk into 1116)", EVENUP,
     "        return evenPixels(points * e)\n"),
    ("W2 an even side up by two (a black column for nothing)", EVENUP, "        return whole + 2 - (whole & 1)\n"),
    ("W3 up to even whatever the scale (Standard on a 2x display too)", GUARD,
     "        guard let d = usable(displayScale), e <= d else { return evenPixels(points * e) }\n"),
    ("W4 no display scale taken for 1:1", GUARD,
     "        guard e == (usable(displayScale) ?? knob) else { return evenPixels(points * e) }\n"),
    ("W5 no tolerance (a black column for a product's rounding)", UP, "        let whole = Int((points * e).rounded(.up))\n"),
    ("W6 to the nearest pixel, not up (a window cut)", UP, "        let whole = Int((points * e).rounded())\n"),
    ("W7 the restart rule rounds as before (a restart at every poll)", WANT,
     "        let want = (width: evenPixels(points.width * effective(knob: knob, displayScale: displayScale)),\n"
     "                    height: evenPixels(points.height * effective(knob: knob, displayScale: displayScale)))\n"),
    ("W8 the restart rule never restarts", CMP, "        return false\n"),
    ("W9 the restart rule looks only at the width", CMP, "        return want.width != encoder.width\n"),
    ("W10 a window's sides swapped", SIDES,
     "        (windowPixels(points.height, knob: knob, displayScale: displayScale),\n"
     "         windowPixels(points.width, knob: knob, displayScale: displayScale))\n"),
    ("E1 evenPixels not even (the test pattern 1512×949 at Standard)", EVEN,
     "func evenPixels(_ v: CGFloat) -> Int { Int(v.rounded(.down)) }\n"),
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
    # Sill's virtual display: no side under 800 points (an iPhone's 754×784 display came up at 1x).
    ("V1 the old floor, 320 (an iPhone upright's 754×784 display at 1x)", "    static let minSide: CGFloat = 800\n",
     "    static let minSide: CGFloat = 320\n"),
    ("V2 only the width held to the floor", "height: min(max(s.height, minSide), maxSide))",
     "height: min(s.height, maxSide))"),
    ("V3 only the height held to the floor", "CGSize(width: min(max(s.width, minSide), maxSide), ",
     "CGSize(width: min(s.width, maxSide), "),
    ("V4 the envelope from the panel's shorter edge", "        let side = ceil(max(panel.width, panel.height) / 0.5)\n",
     "        let side = ceil(min(panel.width, panel.height) / 0.5)\n"),
    ("V5 the envelope without Aa's smallest step", "        let side = ceil(max(panel.width, panel.height) / 0.5)\n",
     "        let side = ceil(max(panel.width, panel.height))\n"),
    ("V6 a fraction of a point not rounded up", "        let side = ceil(max(panel.width, panel.height) / 0.5)\n",
     "        let side = max(panel.width, panel.height) / 0.5\n"),
    ("V7 no panel: the window's own size not held", "panel.height > 0 else { return clamp(windowSize) }",
     "panel.height > 0 else { return windowSize }"),
    ("V8 a panel with no width counted", "        guard let panel, panel.width > 0, panel.height > 0 else",
     "        guard let panel, panel.height > 0 else"),
    ("V9 the ceiling raised past VirtualDisplay's 8192 pixels at 2x", "    static let maxSide: CGFloat = 4096\n",
     "    static let maxSide: CGFloat = 8192\n"),
    # The window's size on the virtual display: held to 1…65536 points (security scan, finding 4; the review).
    ("S1 the window's size unheld (the bug: 1e300 points, the \"insists on\" line's Int() trapped)", STAGE,
     "        return CGSize(width: (panel.width / s).rounded(),\n"
     "                      height: (panel.height / s).rounded())\n"),
    ("S2 only the width held", STAGE,
     "        return CGSize(width: min(max((panel.width / s).rounded(), 1), maxWindowSide),\n"
     "                      height: (panel.height / s).rounded())\n"),
    ("S3 no floor of a point (a quarter point asked 0×0)", STAGE,
     "        return CGSize(width: min((panel.width / s).rounded(), maxWindowSide),\n"
     "                      height: min((panel.height / s).rounded(), maxWindowSide))\n"),
    ("S4 the envelope's floor, 800, for the window too", STAGE,
     "        return CGSize(width: min(max((panel.width / s).rounded(), minSide), maxWindowSide),\n"
     "                      height: min(max((panel.height / s).rounded(), minSide), maxWindowSide))\n"),
    ("S5 a panel that is not a number taken", STAGE_GUARD,
     "        guard let panel, panel.width > 0, panel.height > 0 else { return own }\n"),
    ("S6 a scale of 0 divides", STAGE_SCALE, "        let s = scale.flatMap { $0.isFinite ? $0 : nil } ?? 1\n"),
    ("S7 an infinite scale divides", STAGE_SCALE, "        let s = scale.flatMap { $0 > 0 ? $0 : nil } ?? 1\n"),
    ("S8 the scale ignored", STAGE_SCALE, "        let s: CGFloat = 1\n"),
    ("S9 the sides swapped", STAGE,
     "        return CGSize(width: min(max((panel.height / s).rounded(), 1), maxWindowSide),\n"
     "                      height: min(max((panel.width / s).rounded(), 1), maxWindowSide))\n"),
    ("S10 the window held to the display's 4096 (the review: a full-screen crop lost the panel's shape)", STAGE,
     "        return CGSize(width: min(max((panel.width / s).rounded(), 1), maxSide),\n"
     "                      height: min(max((panel.height / s).rounded(), 1), maxSide))\n"),
    ("S11 the window's ceiling under the largest viewport a host takes", "    static let maxWindowSide: CGFloat = 65536\n",
     "    static let maxWindowSide: CGFloat = 65535\n"),
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
