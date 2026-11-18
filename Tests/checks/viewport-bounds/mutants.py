"""Mutants of Viewport.swift (Sources/StreamProtocol; ViewportBounds, ClientStats.lateSince): each changes
it in one place, is compiled with StreamMessage.swift and the check (main.swift) and must make it fail. A
mutant that does not compile is not counted as caught; one that traps (whole() as Int() was, the late
count's plain +) fails the check, so it is.
usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "viewport-bounds")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "Sources/StreamProtocol/Viewport.swift")
MESSAGE = os.path.join(ROOT, "Sources/StreamProtocol/StreamMessage.swift")
orig = open(SRC).read()
SIDES = "    public static let sides: ClosedRange<Double> = 1...16384\n"
SCALES = "    public static let scales: ClosedRange<Double> = 0.25...4\n"
WIDTH = '        if !sides.contains(v.width) { why.append("width \\(number(v.width)) \\(points)") }\n'
HEIGHT = '        if !sides.contains(v.height) { why.append("height \\(number(v.height)) \\(points)") }\n'
SCALE = '        if let s = v.scale, !scales.contains(s) {\n'
GUARD = "        guard v.width.isFinite, v.height.isFinite, v.width > 0, v.height > 0 else { return nil }\n"
HELD_W = "        held.width = min(max(v.width, sides.lowerBound), sides.upperBound)\n"
HELD_S = "        held.scale = v.scale.flatMap { $0.isFinite && $0 > 0 ? min(max($0, scales.lowerBound), scales.upperBound) : nil }\n"
WHOLE = ("        if let i = Int(exactly: x.rounded(.towardZero)) { return String(i) }\n"
         "        return \"\\(x)\"\n")
NUMBER = "        if x == x.rounded(), let i = Int(exactly: x) { return String(i) }\n"
LATE_MORE = "        let more = max(0, late ?? 0)\n"
LATE_SUM = "        return count > Int.max - more ? Int.max : count + more\n"
MUTANTS = [
    # The bounds a host takes.
    ("B1 the old rule: any side above 0 taken (the bug: 1e300 points reached the fit)", SIDES,
     "    public static let sides: ClosedRange<Double> = Double.leastNonzeroMagnitude...Double.greatestFiniteMagnitude\n"),
    ("B2 no ceiling on a side", SIDES, "    public static let sides: ClosedRange<Double> = 1...Double.greatestFiniteMagnitude\n"),
    ("B3 a side of 0 taken", SIDES, "    public static let sides: ClosedRange<Double> = 0...16384\n"),
    ("B4 a side's ceiling one too low (an iPad's own panels at the edge)", SIDES, "    public static let sides: ClosedRange<Double> = 1...16383\n"),
    ("B5 any scale above 0 taken (the bug: a scale of 1e-300 made a side infinite)", SCALES,
     "    public static let scales: ClosedRange<Double> = Double.leastNonzeroMagnitude...Double.greatestFiniteMagnitude\n"),
    ("B6 the slider's own 0.5 to 1.5 (0.25 and 4 refused)", SCALES, "    public static let scales: ClosedRange<Double> = 0.5...1.5\n"),
    ("B7 the width never looked at", WIDTH, ""),
    ("B8 the height never looked at", HEIGHT, ""),
    ("B9 the scale never looked at", SCALE, "        if let s = v.scale, false, !scales.contains(s) {\n"),
    ("B10 no scale (Aa never touched) refused", SCALE, "        if let s = Optional(v.scale ?? 0), !scales.contains(s) {\n"),
    ("B11 the height's bounds the scale's", HEIGHT,
     '        if !scales.contains(v.height) { why.append("height \\(number(v.height)) \\(points)") }\n'),
    ("B12 the line without the value", WIDTH, '        if !sides.contains(v.width) { why.append("width \\(points)") }\n'),
    ("B14 the line without the bounds", "        let points = \"(\\(number(sides.lowerBound)) to \\(number(sides.upperBound)) points)\"\n",
     "        let points = \"\"\n"),
    ("B13 every field out of range but the first unnamed",
     '        return why.isEmpty ? nil : why.joined(separator: ", ")\n', '        return why.isEmpty ? nil : why[0]\n'),
    # What a device sends.
    ("H1 a panel not measured yet sent", GUARD, "        guard v.width.isFinite, v.height.isFinite else { return nil }\n"),
    ("H2 a NaN panel sent", GUARD, "        guard v.width > 0, v.height > 0 else { return nil }\n"),
    ("H3 a side over the ceiling sent as it is", HELD_W, "        held.width = max(v.width, sides.lowerBound)\n"),
    ("H4 a side under a point sent as it is", HELD_W, "        held.width = min(v.width, sides.upperBound)\n"),
    ("H5 a scale of 0 sent as the floor, not as none", HELD_S,
     "        held.scale = v.scale.flatMap { $0.isFinite ? min(max($0, scales.lowerBound), scales.upperBound) : nil }\n"),
    ("H6 a scale sent as it is", HELD_S, "        held.scale = v.scale\n"),
    ("H7 every scale sent as none", HELD_S, "        held.scale = nil\n"),
    # The numbers in the host's lines.
    ("W1 whole as Int() was (traps on 1e300)", WHOLE, "        return String(Int(x))\n"),
    ("W2 whole to the nearest, not toward zero (1512.7 printed 1513)", WHOLE,
     "        if let i = Int(exactly: x.rounded()) { return String(i) }\n        return \"\\(x)\"\n"),
    ("W3 whole prints the Double (1117.0)", WHOLE, "        return \"\\(x)\"\n"),
    ("N1 number rounded (a scale of 0.1 printed 0)", NUMBER, "        if let i = Int(exactly: x.rounded()) { return String(i) }\n"),
    ("N2 number with .0 (-1.0)", NUMBER, ""),
    # A device's late-sound count (ClientStats.lateSince), found in the review.
    ("L1 a plain + (the bug: two reports of Int.max trapped)", LATE_SUM, "        return count + more\n"),
    ("L2 a negative count subtracted", LATE_MORE, "        let more = late ?? 0\n"),
    ("L3 the sum stops one short of Int.max", LATE_SUM, "        return count > Int.max - more ? Int.max - 1 : count + more\n"),
    ("L4 the sum wraps around", LATE_SUM, "        return count &+ more\n"),
]
caught = 0
for name, old, new in MUTANTS:
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    src = os.path.join(OUT, "Viewport.swift")
    open(src, "w").write(orig.replace(old, new, 1))
    exe = os.path.join(OUT, "mutant")
    if os.path.exists(exe): os.remove(exe)
    c = subprocess.run(["swiftc", "-O", src, MESSAGE, os.path.join(SP, "main.swift"), "-o", exe], capture_output=True, text=True)
    if c.returncode != 0:
        print(f"{name}: did not compile: {c.stderr.strip().splitlines()[0] if c.stderr.strip() else ''}"); continue
    r = subprocess.run([exe], capture_output=True, text=True, timeout=600)
    failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
    if r.returncode != 0:
        caught += 1
        print(f"{name}: caught ({failed[0][:110] if failed else f'exit {r.returncode}: it trapped'})")
    else:
        print(f"{name}: NOT CAUGHT")
os.remove(os.path.join(OUT, "Viewport.swift"))
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
