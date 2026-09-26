"""Mutants of PointerWatch.swift (Sources/SillHost), the host's shell around PointerControl
(docs/pointer-visibility-plan.md §4.2, §4.10): each changes the file in one place, is compiled with the
check by build.sh and must make it fail. usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
WATCH = "Sources/SillHost/PointerWatch.swift"
MUTANTS = [
    # What is read
    ("a synthetic host reads the real pointer", "        if synthetic {\n            read = path == nil ? nil : scriptedPointer(now: now)\n",
     "        if false {\n            read = path == nil ? nil : scriptedPointer(now: now)\n"),
    ("a path kept on a real host", "self.path = synthetic ? path : nil", "self.path = path"),
    ("a sample without a geometry reads", "        lock.lock()\n        guard let geometry else { lock.unlock(); return nil }\n",
     "        lock.lock()\n        if !synthetic { _ = readLocation() }\n        guard let geometry else { lock.unlock(); return nil }\n"),
    # The report
    ("the driving device is sent the pointer too", "            guard controller != .client(client) else { return nil }\n", ""),
    ("x and y sent while outside", "MacPointer(inside: false, seen: seen)", "MacPointer(x: x, y: y, inside: false, seen: seen)"),
    ("inside ignores the window being off screen", "inside: f.inside && onScreen", "inside: f.inside"),
    # Sill's own motion
    ("sillMoved opens no settle", "        control.sillMoved(now: now)\n", ""),
    # The window's re-read
    ("a re-read at every sample", "if !rereading, (moved && since >= rereadAfterMove) || since >= rereadAnyway {", "if !rereading {"),
    ("no re-read after a move", "(moved && since >= rereadAfterMove) || since >= rereadAnyway", "since >= rereadAnyway"),
    ("no re-read while the pointer is still", "(moved && since >= rereadAfterMove) || since >= rereadAnyway", "(moved && since >= rereadAfterMove)"),
    ("a re-read after a move without the gap", "(moved && since >= rereadAfterMove)", "(moved)"),
    ("a second re-read while one runs", "        if rereading { rereadOwed = true; return nil }\n", ""),
    ("no owed re-read", "            if rereadOwed, let w = window { again = startRereadLocked(w.id) }\n", ""),
    ("an answer for another window kept", "            if let w = window, w.id == id {\n                // Gone", "            if let w = window {\n                // Gone"),
    ("a window gone from the list stays on screen", "state ?? WindowState(bounds: w.state.bounds, onScreen: false)",
     "state ?? WindowState(bounds: w.state.bounds, onScreen: true)"),
    ("the same window again counts as on screen", "window = (id, WindowState(bounds: rect, onScreen: w.state.onScreen))",
     "window = (id, WindowState(bounds: rect, onScreen: true))"),
    ("the re-read's bounds never used", "if let w = window, w.id == id { rect = w.state.bounds; onScreen = w.state.onScreen }",
     "if let w = window, w.id == id { onScreen = w.state.onScreen }"),
    ("no re-read when a window geometry is set", "            reread = startRereadLocked(id)\n        } else {\n            window = nil",
     "            reread = nil\n        } else {\n            window = nil"),
    # The frame interval
    ("a rate of 0 kept", "self.fps = max(1, fps)", "self.fps = fps"),
    # The scripted pointer
    ("a step always wins over a newer move", "            if at >= testPointAt {", "            if true {"),
    ("a dry run's move moves nothing", "        if let p, path != nil {\n            testPoint = p\n", "        if let p, path != nil {\n"),
    ("the path's clock restarts at every sample", "        let start = pathStart ?? now\n", "        let start = now\n"),
    ("a step is due only after its time", "start + steps[nextStep].t <= now", "start + steps[nextStep].t < now"),
    # The file
    ("a negative time taken", "numbers.allSatisfy({ $0.isFinite }), numbers[0] >= 0 else", "numbers.allSatisfy({ $0.isFinite }) else"),
    ("a time that goes back taken", "            if let last = steps.last, numbers[0] < last.t { return .failure(.goesBack(line: i + 1)) }\n", ""),
    ("10,000 steps refused", "guard steps.count < maxSteps else", "guard steps.count < maxSteps - 1 else"),
    ("a file of exactly 1 MiB refused", "guard data.count <= maxBytes else", "guard data.count < maxBytes else"),
    ("a line with a fourth field taken", "guard fields.count == 3, numbers.count == 3,", "guard fields.count >= 3, numbers.count >= 3,"),
    ("CRLF not a line end", "whereSeparator: \\.isNewline", "whereSeparator: { $0 == \"\\n\" }"),
    # The hooks
    ("a real host takes the scripted pointer", "        guard synthetic else { return (nil, \"SILL_TEST_POINTER_PATH=", "        guard true else { return (nil, \"SILL_TEST_POINTER_PATH="),
    ("a real host takes the software encoder", "        guard synthetic else { return (false, \"SILL_TEST_SOFTWARE_ENCODER ignored",
     "        guard true else { return (false, \"SILL_TEST_SOFTWARE_ENCODER ignored"),
    ("any value turns the software encoder on", "        guard value == \"1\" else {", "        guard !value.isEmpty else {"),
    ("\"steps\" for one step", "step\\(n == 1 ? \"\" : \"s\")", "steps"),
]
caught = 0
for name, old, new in MUTANTS:
    src = open(os.path.join(WT, WATCH)).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        exe = os.path.join(t, "c")
        mf = os.path.join(t, "PointerWatch.swift"); open(mf, "w").write(src.replace(old, new, 1))
        subprocess.run([os.path.join(HERE, "build.sh"), WT, exe, mf], capture_output=True, text=True)
        if not os.path.exists(exe): print(f"{name}: did not compile"); continue
        try:
            r = subprocess.run([exe], capture_output=True, text=True, timeout=120)
            failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
            code = r.returncode
        except subprocess.TimeoutExpired:
            failed, code = ["timed out"], -1
        if code != 0:
            caught += 1
            print(f"{name}: caught ({failed[0][:100] if failed else f'exit status {code}'})")
        else:
            print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
