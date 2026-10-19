"""Mutants of InstalledApps.swift (#76): each changes it in one place, is compiled with the check and
must make it fail. A link to a folder is refused by contentsOfDirectory(at:) itself (ENOTDIR), so
dropping the isDirectory test changes nothing and is no mutant here. The unsorted mutant counts on
APFS listing a folder in its own order (by a hash of each name), which puts the fixture's "right"
before "left"; a file system that lists names sorted would miss it. usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
F = os.path.join(WT, "Sources/SillHost/InstalledApps.swift")
MUTANTS = [
    ("one level down only (the rule before #135's depth)",
     "            level = next\n", "            level = level == [dir] ? next : []\n"),
    ("no folder searched (the bug of #76)",
     "            level = next\n", "            level = []\n"),
    ("hidden-flagged names skipped (Safari's link)",
     "includingPropertiesForKeys: keys, options: [])", "includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])"),
    ("a package of another kind searched",
     "values.isDirectory == true, values.isPackage != true", "values.isDirectory == true"),
    ("a framework searched (a bundle that is no package)",
     'url.pathExtension != "framework", ', ""),
    ("dot names kept",
     'entries.filter { !$0.lastPathComponent.hasPrefix(".") }', "entries.filter { _ in true }"),
    ("the deeper bundle wins",
     "        return found\n", "        return found.reversed()\n"),
    ("each folder's entries left unsorted (APFS lists \"right\" before \"left\")",
     ".sorted { $0.lastPathComponent < $1.lastPathComponent }", ""),
    ("the next level walked backwards",
     "            level = next\n", "            level = next.reversed()\n"),
    ("a folder given as a link not followed",
     "URL(fileURLWithPath: dir).resolvingSymlinksInPath()", "URL(fileURLWithPath: dir)"),
    ("two bundles with one ID both listed",
     ", !seen.contains(id) else", " else"),
    ("sorted backwards",
     "== .orderedAscending }\n    }", "== .orderedDescending }\n    }"),
]
caught = 0
for name, old, new in MUTANTS:
    src = open(F).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        mf = os.path.join(t, "InstalledApps.swift"); open(mf, "w").write(src.replace(old, new, 1))
        exe = os.path.join(t, "c")
        subprocess.run(["swiftc", "-O", mf, os.path.join(HERE, "main.swift"), "-o", exe], capture_output=True, text=True)
        if not os.path.exists(exe):
            print(f"{name}: did not compile (caught)"); caught += 1; continue
        try:
            r = subprocess.run([exe], capture_output=True, text=True, timeout=60)
            code, out = r.returncode, r.stdout
        except subprocess.TimeoutExpired:
            code, out = -1, "FAIL timed out"
        if code != 0:
            caught += 1
            failed = [l for l in out.splitlines() if l.startswith("FAIL")]
            print(f"{name}: caught ({failed[0][:90] if failed else f'exit {code}'})")
        else:
            print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
