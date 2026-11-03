"""Mutants of TouchHold.swift (iOSClient): each changes it in one place and must make the check (main.swift)
fail. usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "touch-hold")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/TouchHold.swift")
orig = open(SRC).read()
MUTANTS = [
    # The constants.
    ("C1 the hold iOS's own half second", "static let press: TimeInterval = 0.45", "static let press: TimeInterval = 0.5"),
    ("C2 no slop (any move drags)", "static let slop: CGFloat = 8", "static let slop: CGFloat = 0"),
    ("C3 a wider slop", "static let slop: CGFloat = 8", "static let slop: CGFloat = 12"),
    # The slop.
    ("S1 at the slop drags", "> Self.slop else", ">= Self.slop else"),
    ("S2 each axis, not the distance", "hypot(point.x - start.x, point.y - start.y)", "max(abs(point.x - start.x), abs(point.y - start.y))"),
    ("S3 measured from the last move, not the start", "hypot(point.x - start.x, point.y - start.y)", "hypot(point.x - last.x, point.y - last.y) + 0 * start.x"),
    # The drag.
    ("D1 the button down where the finger is, not where it was pressed", "return [.leftDown(start), .move(point)]", "return [.leftDown(point), .move(point)]"),
    ("D2 no move with the button down", "return [.leftDown(start), .move(point)]", "return [.leftDown(start)]"),
    ("D3 never dragging (each move past the slop a button down)", "        isDragging = true\n        return [.leftDown", "        return [.leftDown"),
    ("D4 a drag's moves dropped", "if isDragging { return [.move(point)] }", "if isDragging { return [] }"),
    ("D5 the last point not kept", "        last = point\n        if isDragging", "        if isDragging"),
    # The lift.
    ("L1 a drag's lift a right click", "return isDragging ? [.leftUp(point)] : [.rightClick(start)]", "return [.rightClick(start)]"),
    ("L2 a drag's button up where it was last moved", "return isDragging ? [.leftUp(point)] : [.rightClick(start)]", "return isDragging ? [.leftUp(last)] : [.rightClick(start)]"),
    ("L3 the right click where it lifted", "return isDragging ? [.leftUp(point)] : [.rightClick(start)]", "return isDragging ? [.leftUp(point)] : [.rightClick(point)]"),
    ("L4 no right click", "return isDragging ? [.leftUp(point)] : [.rightClick(start)]", "return isDragging ? [.leftUp(point)] : []"),
    ("L5 the lift not resetting", "        defer { reset() }\n        return isDragging ? [.leftUp(point)]", "        return isDragging ? [.leftUp(point)]"),
    # The cancel.
    ("X1 a cancelled drag's button left down", "return isDragging ? [.leftUp(last)] : []", "return []"),
    ("X2 a cancel right-clicks", "return isDragging ? [.leftUp(last)] : []", "return isDragging ? [.leftUp(last)] : [.rightClick(last)]"),
    ("X3 the cancel not resetting", "        defer { reset() }\n        return isDragging ? [.leftUp(last)]", "        return isDragging ? [.leftUp(last)]"),
    # The state.
    ("R1 reset keeps the drag", "        start = nil\n        isDragging = false\n    }", "        start = nil\n    }"),
    ("R2 reset keeps the hold", "        start = nil\n        isDragging = false\n    }", "        isDragging = false\n    }"),
]
caught = 0
for name, old, new in MUTANTS:
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    src = os.path.join(OUT, "TouchHold.swift")
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
        print(f"{name}: caught ({len(failed)} FAIL lines; first: {failed[0][:150] if failed else 'exit ' + str(r.returncode)})")
    else:
        print(f"{name}: SURVIVED")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
