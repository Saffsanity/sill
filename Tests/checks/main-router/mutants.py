"""Mutants of the Mac client's MainRouter.swift: each changes it in one place, is compiled with the
check by build.sh and must make it fail. usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
F = os.path.join(WT, "Sources/MacClient/MainRouter.swift")
MUTANTS = [
    ("a closed window keeps its side claim", "            sideOwned.remove(ObjectIdentifier(old))   // a new window's feed can take the closed one's address\n", ""),
    ("side frames on any sets", "let mine = feed !== target && sideOwned.contains(ObjectIdentifier(feed))", "let mine = feed !== target"),
    ("side sets into the main stream's window", "        let mine = feed !== target\n        if mine { sideOwned", "        let mine = true\n        if mine { sideOwned"),
    ("the main stream's sets leave the side's claim", "        if let t = target { sideOwned.remove(ObjectIdentifier(t)) }\n", ""),
    ("the stream never follows the list", "        target = listedSource.flatMap { feeds[$0] }\n", ""),
    ("a late window never takes the stream", "        target = listedSource.flatMap { feeds[$0] }\n", "        if target == nil && !begun { target = listedSource.flatMap { feeds[$0] } }\n"),
    ("a list never marks the switch", "        listedSource = active\n        begun = false", "        listedSource = active"),
    ("no replay into a window opened late", "        for (data, key) in frames { feed.enqueue(data, isKeyframe: key) }\n", ""),
    ("an old stream replayed into a new window", "guard let feed, source == listedSource, begun, target == nil", "guard let feed, source == listedSource, target == nil"),
    ("a window for another source takes the stream", "guard let feed, source == listedSource, begun, target == nil", "guard let feed, begun, target == nil"),
    ("a closed window keeps drawing", "            if old === target { target = nil }\n", ""),
    ("the group kept across keyframes", "        if isKeyframe { gop = []; gopBytes = 0 }\n", ""),
    ("no limit to the group", "if gopBytes > Self.gopLimit {", "if false {"),
    ("reset keeps the windows", "        feeds = [:]; sideOwned", "        sideOwned"),
    ("reset keeps the target", "sideOwned = []; target = nil;", "sideOwned = [];"),
]
caught = 0
for name, old, new in MUTANTS:
    src = open(F).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        mf = os.path.join(t, "MainRouter.swift"); open(mf, "w").write(src.replace(old, new, 1))
        exe = os.path.join(t, "c")
        subprocess.run([os.path.join(HERE, "build.sh"), WT, exe, f"MainRouter.swift={mf}"], capture_output=True, text=True)
        if not os.path.exists(exe): print(f"{name}: did not compile"); continue
        r = subprocess.run([exe], capture_output=True, text=True, timeout=300)
        failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        if r.returncode != 0:
            caught += 1
            print(f"{name}: caught ({failed[0][:90] if failed else f'exit status {r.returncode}'})")
        else:
            print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
