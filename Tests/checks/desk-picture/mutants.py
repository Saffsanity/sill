"""Mutants of DeskPicture.swift: each changes it in one place, is compiled with the check and must
make it fail. usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
F = os.path.join(WT, "Sources/SillHost/DeskPicture.swift")
MUTANTS = [
    ("the mean, not the middle cell", "return diffs[diffs.count / 2] > cellTolerance", "return diffs.reduce(0, +) / diffs.count > cellTolerance"),
    ("the largest cell", "return diffs[diffs.count / 2] > cellTolerance", "return diffs[diffs.count - 1] > cellTolerance"),
    ("at the tolerance", "return diffs[diffs.count / 2] > cellTolerance", "return diffs[diffs.count / 2] >= cellTolerance"),
    ("a looser tolerance", "static let cellTolerance = 48", "static let cellTolerance = 96"),
    ("unsorted", ".map { abs(Int($0) - Int($1)) }.sorted()", ".map { abs(Int($0) - Int($1)) }"),
    ("cells of another count compared", "guard frame.count == window.count, !frame.isEmpty else { return false }", "guard !frame.isEmpty, !window.isEmpty else { return false }"),
    ("the frame's rows bottom first", "out[r * columns + c] = UInt8(sum / max(n, 1))", "out[(rows - 1 - r) * columns + c] = UInt8(sum / max(n, 1))"),
    ("the frame's columns right first", "out[r * columns + c] = UInt8(sum / max(n, 1))", "out[r * columns + (columns - 1 - c)] = UInt8(sum / max(n, 1))"),
    ("any frame size", "guard w >= columns, h >= rows, let base", "guard let base"),
]
caught = 0
for name, old, new in MUTANTS:
    src = open(F).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        mf = os.path.join(t, "DeskPicture.swift"); open(mf, "w").write(src.replace(old, new, 1))
        exe = os.path.join(t, "c")
        subprocess.run(["xcrun", "swiftc", "-O", "-package-name", "sill", mf, os.path.join(HERE, "main.swift"), "-o", exe], capture_output=True, text=True)
        if not os.path.exists(exe): print(f"{name}: did not compile"); continue
        r = subprocess.run([exe], capture_output=True, text=True, timeout=120)
        failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        if r.returncode != 0:
            caught += 1
            print(f"{name}: caught ({failed[0][:90] if failed else f'exit status {r.returncode}'})")
        else:
            print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
