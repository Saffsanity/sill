"""Each mutant changes iOSClient/PictureZoom.swift in one place and must fail the check (main.swift).
usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "picture-zoom")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/PictureZoom.swift")
orig = open(SRC).read()
MUTANTS = {
    "Z1 never stops at an edge": ("return min(boundsMin, max(boundsMin + boundsLength - length, centred))", "return centred"),
    "Z2 stops only at the near edge": ("return min(boundsMin, max(boundsMin + boundsLength - length, centred))", "return min(boundsMin, centred)"),
    "Z3 a short axis not centred": ("guard length > boundsLength else { return boundsMin + (boundsLength - length) / 2 }",
                                   "guard length > boundsLength else { return boundsMin }"),
    "Z4 the axes' focus swapped": ("boundsLength: bounds.height, fraction: focus.y", "boundsLength: bounds.height, fraction: focus.x"),
    "Z5 zoom applies where it is not offered": ("        guard allowed else { return 1 }\n", ""),
    "Z6 one arrangement's leaving withdraws it": ("func withdrawn() { offering = max(0, offering - 1); settleTouches() }", "func withdrawn() { offering = 0; settleTouches() }"),
    "Z7 withdrawals below zero": ("func withdrawn() { offering = max(0, offering - 1); settleTouches() }", "func withdrawn() { offering -= 1; settleTouches() }"),
    "Z8 follows under a finger": ("if touching > 0 { pendingFocus = clamped; return }", ""),
    "Z9 the held focus forgotten": ("        lastLift = -.infinity\n        follow(p)", "        lastLift = -.infinity"),
    "Z10 not clamped": ("let clamped = CGPoint(x: min(max(p.x, 0), 1), y: min(max(p.y, 0), 1))", "let clamped = p"),
    "Z11 never animated": ("onChange?(jump)", "onChange?(false)"),
    "Z12 the touch count runs negative": ("touching = max(0, touching - count)", "touching -= count"),
    "Z13 toggle forgets the last zoom": ("if scale > 1 { last = scale }; ", ""),
    "Z14 the magnified size wrong": ("let width = video.width * scale, height = video.height * scale",
                                    "let width = video.width * scale, height = video.height"),
    "Z15 fill never grows": ("return (fill ? fillScale : 1) * (scale > 1 ? CGFloat(scale) : 1)", "return (scale > 1 ? CGFloat(scale) : 1)"),
    "Z16 fill to the width only": ("return max(1, bounds.width / video.width, bounds.height / video.height)", "return max(1, bounds.width / video.width)"),
    "Z17 a source forgets its zoom": ("        perSource[sourceKey] = scale\n", ""),
    "Z18 the focus kept across sources": ("        focus = CGPoint(x: 0.5, y: 0.5)\n        let next", "        let next"),
    "Z19 a click answered after the lift followed at once": ("        if touchFollowDelay > 0, sinceLift < touchFollowDelay {", "        if false, sinceLift < touchFollowDelay {"),
    "Z21 a lost touch keeps holding": ("    func offered() { offering += 1; settleTouches() }", "    func offered() { offering += 1 }"),
    "Z22 a lost touch kept when the old arrangement goes": ("    func withdrawn() { offering = max(0, offering - 1); settleTouches() }", "    func withdrawn() { offering = max(0, offering - 1) }"),
    "Z23 never against the top": ("        if alignTop, drawn.height < bounds.height { drawn.origin.y = bounds.minY }\n", ""),
    "Z24 auto never steps down": ("static func next(after scale: Double) -> Double? { steps.first { $0 < scale - 0.001 } }", "static func next(after scale: Double) -> Double? { nil }"),
    "Z25 auto judges the width alone": ("return window.width <= room.width / scale + 4 && window.height <= room.height / scale + 4", "return window.width <= room.width / scale + 4"),
    "Z26 auto with no slack": ("window.width <= room.width / scale + 4 &&", "window.width <= room.width / scale &&"),
}
caught = 0
for name, (old, new) in MUTANTS.items():
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    path = os.path.join(OUT, "mutant.swift")
    open(path, "w").write(orig.replace(old, new))
    b = subprocess.run(["swiftc", "-O", path, os.path.join(SP, "main.swift"), "-o", os.path.join(OUT, "mutant")],
                       capture_output=True, text=True)
    if b.returncode != 0:
        print(f"{name}: DOES NOT COMPILE\n{b.stderr[:600]}"); continue
    r = subprocess.run([os.path.join(OUT, "mutant")], capture_output=True, text=True, timeout=300)
    failed = [l[5:] for l in r.stdout.splitlines() if l.startswith("FAIL")]
    ok = r.returncode != 0
    caught += ok
    print(f"{'caught' if ok else 'MISSED'} {name}: {len(failed)} failing, e.g. {[f[:100] for f in failed[:2]]}")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
