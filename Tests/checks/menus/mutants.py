"""H3 mutants of the menus check: each changes one file it compiles in one place, and must make the
check fail. usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]
HERE = os.path.dirname(os.path.abspath(__file__))
PATHS = {
    "StreamMessage.swift": "Sources/StreamProtocol/StreamMessage.swift",
    "MacMenu.swift": "Sources/StreamProtocol/MacMenu.swift",
}
MUTANTS = [
    # The wire (MacMenu.swift, StreamMessage.swift)
    ("the fetch takes the pointer's 26", "StreamMessage.swift", "case fetchMenu = 27", "case fetchMenu = 26"),
    ("stale set from pressed", "MacMenu.swift", "self.pressed = pressed; self.stale = stale", "self.pressed = pressed; self.stale = pressed"),
    ("a press's token dropped", "MacMenu.swift", "self.title = title; self.token = token", "self.title = title; self.token = nil"),
]
caught = 0
for name, file, old, new in MUTANTS:
    text = open(os.path.join(WT, PATHS[file])).read()
    if text.count(old) != 1:
        print(f"NOT APPLIED {name}: pattern found {text.count(old)} times"); continue
    with tempfile.TemporaryDirectory() as t:
        path = os.path.join(t, file)
        open(path, "w").write(text.replace(old, new))
        exe = os.path.join(t, "check")
        b = subprocess.run([os.path.join(HERE, "build.sh"), WT, exe, f"{file}={path}"], capture_output=True, text=True)
        if not os.path.exists(exe):
            print(f"DOES NOT COMPILE {name}\n{(b.stdout + b.stderr)[:600]}"); continue
        r = subprocess.run([exe], capture_output=True, text=True, timeout=300)
        failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        ok = r.returncode != 0 and bool(failed)
        caught += ok
        print(f"{'caught' if ok else 'MISSED'} {name}: {len(failed)} failing, e.g. {[f[:90] for f in failed[:2]]}")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
