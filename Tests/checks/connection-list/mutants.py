"""Mutants of ConnectionList.swift: each changes it in one place, is compiled with the check and must
make it fail. usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
F = os.path.join(WT, "iOSClient/ConnectionList.swift")
MUTANTS = [
    ("default style is tiles", "raw == Style.tiles.rawValue ? .tiles : .list", ".tiles"),
    ("toggled stays the same", "self == .list ? .tiles : .list", "self"),
    ("no group length cap", "return String(joined.prefix(maxGroupLength))", "return joined"),
    ("blank group kept", "guard !words.isEmpty else { return nil }", ""),
    ("decode ignores empty macID check", "where !macID.isEmpty && macID.count <= 128", "where macID.count <= 128"),
    ("setting nil does not remove", "        } else {\n            next.removeValue(forKey: macID)", "        } else {"),
    ("custom groups dropped", "return presetGroups + custom", "return presetGroups"),
    ("empty items returns a section", "guard !items.isEmpty else { return [] }", ""),
    ("ungrouped list titled Other even with no groups", "guard !order.isEmpty else { return [Section(title: nil, items: items)] }", "guard !order.isEmpty else { return [Section(title: \"Other\", items: items)] }"),
    ("ungrouped rows dropped when groups exist", "if !ungrouped.isEmpty { out.append(Section(title: \"Other\", items: ungrouped)) }", ""),
    ("path traversal allowed in previewFileName", "macID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == \"-\" || $0 == \"_\") })", "true"),
    ("previewFileName length uncapped", "macID.count <= 128,", ""),
    ("stalePreviewFiles deletes non-jpg", "guard file.hasSuffix(\".jpg\") else { return false }", "if !file.hasSuffix(\".jpg\") { return true }"),
    ("stalePreviewFiles deletes kept Macs", "return !keepingMacIDs.contains(id)", "return keepingMacIDs.contains(id)"),
    ("columns ignores accessibleText", "(!accessibleText && width >= twoColumnMinWidth) ? 2 : 1", "width >= twoColumnMinWidth ? 2 : 1"),
    ("columns boundary off by one", "width >= twoColumnMinWidth", "width > twoColumnMinWidth"),
]
caught = 0
for name, old, new in MUTANTS:
    src = open(F).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        mf = os.path.join(t, "ConnectionList.swift"); open(mf, "w").write(src.replace(old, new, 1))
        exe = os.path.join(t, "c")
        subprocess.run(["swiftc", "-O", mf, os.path.join(HERE, "main.swift"), "-o", exe], capture_output=True, text=True)
        if not os.path.exists(exe): print(f"{name}: did not compile"); continue
        r = subprocess.run([exe], capture_output=True, text=True, timeout=60)
        failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        if r.returncode != 0:
            caught += 1
            print(f"{name}: caught ({failed[0][:90] if failed else f'exit status {r.returncode}'})")
        else:
            print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
