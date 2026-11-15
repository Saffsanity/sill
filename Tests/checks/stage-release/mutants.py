"""Mutants of StageRelease.swift (Sources/SillHost) and of the way out's wiring (VirtualStage.swift, StreamCoordinator.swift):
each changes one file in one place, is compiled with the check (main.swift) and must make it fail. A mutant that does not
compile is not counted as caught. The wiring's mutants change the source the check reads as text, and are put back after.
usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "stage-release")
os.makedirs(OUT, exist_ok=True)
RULE = "Sources/SillHost/StageRelease.swift"
STAGE = "Sources/SillHost/VirtualStage.swift"
COORD = "Sources/SillHost/StreamCoordinator.swift"
LEFT_NIL = "        guard let listed else { return true }\n        if same(listed, home) { return true }\n"
OVERLAP = "        return overlap.isNull || overlap.width <= 0 || overlap.height <= 0\n"
DECIDE = "        if leftStage(listed: listed, home: home, stage: stage) { return .remove(left: true) }\n        return elapsed >= commitDeadline ? .remove(left: false) : .wait\n"
AFTER = "        guard let listed else { return .gone }\n        return same(listed, settled ?? home) ? .stay : .putBack\n"
MUTANTS = [
    # The rule
    (RULE, "S1 the display removed at once (the order before 2026-11-12)", "    static let commitDeadline: Double = 1.0\n", "    static let commitDeadline: Double = 0\n"),
    (RULE, "S2 a 5 s deadline", "    static let commitDeadline: Double = 1.0\n", "    static let commitDeadline: Double = 5\n"),
    (RULE, "S3 the list read every 50 ms", "    static let pollInterval: Double = 0.01\n", "    static let pollInterval: Double = 0.05\n"),
    (RULE, "S4 a closed window waited for", LEFT_NIL, "        guard let listed else { return false }\n        if same(listed, home) { return true }\n"),
    (RULE, "S5 home not enough when the home reaches over the display", LEFT_NIL, "        guard let listed else { return true }\n"),
    (RULE, "S6 an edge touching the display counted as on it", OVERLAP, "        return overlap.isNull\n"),
    (RULE, "S7 any frame but home counted as on the display", OVERLAP, "        return false\n"),
    (RULE, "S8 the window never waited for (removed whatever it shows)", DECIDE, "        return .remove(left: leftStage(listed: listed, home: home, stage: stage))\n"),
    (RULE, "S9 the deadline always waited out", DECIDE, "        return elapsed >= commitDeadline ? .remove(left: leftStage(listed: listed, home: home, stage: stage)) : .wait\n"),
    (RULE, "S10 the deadline taken for the window's leaving", DECIDE,
     "        if leftStage(listed: listed, home: home, stage: stage) { return .remove(left: true) }\n        return elapsed >= commitDeadline ? .remove(left: true) : .wait\n"),
    (RULE, "S11 a deadline missed by a hair", DECIDE,
     "        if leftStage(listed: listed, home: home, stage: stage) { return .remove(left: true) }\n        return elapsed > commitDeadline ? .remove(left: false) : .wait\n"),
    (RULE, "S12 a closed window after the removal watched on", AFTER, "        guard let listed else { return .stay }\n        return same(listed, settled ?? home) ? .stay : .putBack\n"),
    (RULE, "S13 expected at its home even when kept elsewhere", AFTER, "        guard let listed else { return .gone }\n        return same(listed, home) ? .stay : .putBack\n"),
    (RULE, "S14 never put back", AFTER, "        guard let listed else { return .gone }\n        return .stay\n"),
    (RULE, "S15 always put back", AFTER, "        guard let listed else { return .gone }\n        return .putBack\n"),
    (RULE, "S16 no look after the removal", "    static let afterLook: Double = 1.5\n", "    static let afterLook: Double = 0\n"),
    (RULE, "S17 a 10 s look after", "    static let afterLook: Double = 1.5\n", "    static let afterLook: Double = 10\n"),
    (RULE, "S18 exact frames only", "    static let tolerance: CGFloat = 2\n", "    static let tolerance: CGFloat = 0\n"),
    (RULE, "S19 a 3 pt tolerance", "    static let tolerance: CGFloat = 2\n", "    static let tolerance: CGFloat = 3\n"),
    (RULE, "S20 height ignored in the same place", "            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance\n",
     "            && abs(a.width - b.width) <= tolerance\n"),
    # The wiring
    (COORD, "W1 select's Desktop back to removing at once", "                await stage.leaveFullScreenIfNeeded()\n                await stage.releaseHome()\n            }",
     "                await stage.leaveFullScreenIfNeeded()\n                stage.release()\n            }"),
    (COORD, "W2 Virtual Display off back to removing at once", "await stage.leaveFullScreenIfNeeded(); await stage.releaseHome()\n                if case .window = source",
     "await stage.leaveFullScreenIfNeeded(); stage.release()\n                if case .window = source"),
    (COORD, "W3 Quit waits", "        restoreFits(keeping: nil)\n        stage.release()\n", "        restoreFits(keeping: nil)\n        Task { await stage.releaseHome() }\n"),
    (COORD, "W4 a pick of another window removes the display", "                    await stage.leaveFullScreenIfNeeded()\n                    stage.releaseWindow()\n                }",
     "                    await stage.leaveFullScreenIfNeeded()\n                    await stage.releaseHome()\n                }"),
    (STAGE, "W5 releaseWindow forgets the display it left", "            homeward = (p, display?.displayID)", "            homeward = (p, nil)"),
]
caught = 0
originals = {}
for path, name, old, new in MUTANTS:
    full = os.path.join(ROOT, path)
    orig = originals.setdefault(path, open(full).read())
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    exe = os.path.join(OUT, "mutant")
    if os.path.exists(exe): os.remove(exe)
    rule = os.path.join(ROOT, RULE)
    try:
        if path == RULE:
            src = os.path.join(OUT, "StageRelease.swift")
            open(src, "w").write(orig.replace(old, new, 1))
        else:
            src = rule
            open(full, "w").write(orig.replace(old, new, 1))
        c = subprocess.run(["swiftc", "-O", src, os.path.join(SP, "main.swift"), "-o", exe], capture_output=True, text=True)
        if c.returncode != 0:
            print(f"{name}: did not compile: {c.stderr.strip().splitlines()[0] if c.stderr.strip() else ''}"); continue
        r = subprocess.run([exe], capture_output=True, text=True, timeout=600)
    finally:
        if path != RULE: open(full, "w").write(orig)
    failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
    if r.returncode != 0:
        caught += 1
        print(f"{name}: caught ({failed[0][:110] if failed else f'exit {r.returncode}'})")
    else:
        print(f"{name}: NOT CAUGHT")
if os.path.exists(os.path.join(OUT, "StageRelease.swift")): os.remove(os.path.join(OUT, "StageRelease.swift"))
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
