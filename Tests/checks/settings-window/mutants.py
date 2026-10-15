"""Mutants of SettingsWindowFit.swift (issue #59, docs/settings-window-plan.md): each changes it in one
place, is compiled with the check by build.sh and must make it fail. usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
F = os.path.join(WT, "Sources/SillMenuBar/SettingsWindowFit.swift")
MUTANTS = [
    # The margin and the least a pane gets.
    ("no margin", "static let margin: CGFloat = 12", "static let margin: CGFloat = 0"),
    ("no least height", "static let minimumContent: CGFloat = 200", "static let minimumContent: CGFloat = 0"),
    # The limit.
    ("the margin kept only once", "(visible.height - chrome - 2 * margin)", "(visible.height - chrome - margin)"),
    ("the chrome forgotten", "(visible.height - chrome - 2 * margin)", "(visible.height - 2 * margin)"),
    ("the chrome counted twice", "(visible.height - chrome - 2 * margin)", "(visible.height - 2 * chrome - 2 * margin)"),
    ("rounded up", ".rounded(.down))", ".rounded(.up))"),
    ("not rounded", "(visible.height - chrome - 2 * margin).rounded(.down))", "(visible.height - chrome - 2 * margin))"),
    ("the least height ignored", "max(minimumContent, (visible.height", "min(.greatestFiniteMagnitude, (visible.height"),
    # The screen.
    ("the virtual display taken when the window is on it",
     "if let i = windowOn, screens.indices.contains(i), !screens[i].sillVirtual { return i }",
     "if let i = windowOn, screens.indices.contains(i) { return i }"),
    ("the window's own screen ignored",
     "if let i = windowOn, screens.indices.contains(i), !screens[i].sillVirtual { return i }",
     "if let i = windowOn, screens.indices.contains(i), !screens[i].sillVirtual { _ = i }"),
    ("an index no screen has taken (crashes)",
     "if let i = windowOn, screens.indices.contains(i), !screens[i].sillVirtual { return i }",
     "if let i = windowOn, i >= 0, !screens[i].sillVirtual { return i }"),
    ("the fallback may be the virtual display",
     "return screens.firstIndex { !$0.sillVirtual }", "return screens.indices.first"),
    ("the fallback is the last real screen",
     "return screens.firstIndex { !$0.sillVirtual }", "return screens.lastIndex { !$0.sillVirtual }"),
    # The test height.
    ("the test height at the bottom", "CGRect(x: real.minX, y: real.maxY - h,", "CGRect(x: real.minX, y: real.minY,"),
    ("a test height taller than the screen taken", "guard let h = testHeight, h > 0, h < real.height else",
     "guard let h = testHeight, h > 0 else"),
    ("a test height of 0 or less taken", "guard let h = testHeight, h > 0, h < real.height else",
     "guard let h = testHeight, h < real.height else"),
    # The move.
    ("taller than the screen: its bottom at the bottom", "y = visible.maxY - frame.height\n        } else if",
     "y = visible.minY\n        } else if"),
    ("taller than the screen: left where it is", "y = visible.maxY - frame.height\n        } else if",
     "y = frame.minY\n        } else if"),
    ("moved up without the margin", "y = min(visible.minY + margin, visible.maxY - frame.height)",
     "y = min(visible.minY, visible.maxY - frame.height)"),
    ("moved up past the top", "y = min(visible.minY + margin, visible.maxY - frame.height)", "y = visible.minY + margin"),
    ("moved down without the margin", "y = max(visible.maxY - margin - frame.height, visible.minY)",
     "y = max(visible.maxY - frame.height, visible.minY)"),
    ("moved down past the bottom", "y = max(visible.maxY - margin - frame.height, visible.minY)",
     "y = visible.maxY - margin - frame.height"),
    ("a window inside, within the margin of the bottom, moved",
     "} else if frame.minY < visible.minY {", "} else if frame.minY < visible.minY + margin {"),
    ("a window inside, within the margin of the top, moved",
     "} else if frame.maxY > visible.maxY {", "} else if frame.maxY > visible.maxY - margin {"),
    ("a window below the screen left there", "} else if frame.minY < visible.minY {", "} else if frame.minY < visible.minY - 10_000 {"),
    ("a window above the screen left there", "} else if frame.maxY > visible.maxY {", "} else if frame.maxY > visible.maxY + 10_000 {"),
    ("moved sideways onto the screen", "return CGRect(x: frame.minX, y: y,", "return CGRect(x: max(frame.minX, visible.minX), y: y,"),
]
caught = 0
for name, old, new in MUTANTS:
    src = open(F).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        mf = os.path.join(t, "SettingsWindowFit.swift"); open(mf, "w").write(src.replace(old, new, 1))
        exe = os.path.join(t, "c")
        subprocess.run([os.path.join(HERE, "build.sh"), WT, exe, mf], capture_output=True, text=True)
        if not os.path.exists(exe):
            print(f"{name}: did not compile (caught)"); caught += 1; continue
        r = subprocess.run([exe], capture_output=True, text=True, timeout=300)
        if r.returncode != 0:
            caught += 1
            failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
            print(f"{name}: caught ({failed[0][:100] if failed else f'exit {r.returncode}'})")
        else:
            print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
