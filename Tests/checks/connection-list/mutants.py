"""Mutants of ConnectionList.swift: each changes it in one place, is compiled with the check and must
make it fail. usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
F = os.path.join(WT, "iOSClient/ConnectionList.swift")
MUTANTS = [
    ("default style is tiles", "raw == Style.tiles.rawValue ? .tiles : .list", ".tiles"),
    ("toggled stays the same", "self == .list ? .tiles : .list", "self"),
    # When a session's end keeps a picture (Noah on #116: tiles are a choice; the list keeps none).
    ("a picture with the list too", "style == .tiles && sceneActive && saved", "sceneActive && saved"),
    ("a picture from a window behind", "style == .tiles && sceneActive && saved", "style == .tiles && saved"),
    ("a picture of a Mac not saved", "style == .tiles && sceneActive && saved", "style == .tiles && sceneActive"),
    ("a picture when any condition holds", "style == .tiles && sceneActive && saved", "style == .tiles || sceneActive || saved"),
    ("a picture only with the list", "style == .tiles && sceneActive && saved", "style == .list && sceneActive && saved"),
    # Group names.
    ("no group length cap", 'String(words.joined(separator: " ").prefix(maxGroupLength))', 'String(words.joined(separator: " "))'),
    ("a name cut at the cap keeps its space", ").trimmingCharacters(in: .whitespaces)", ")"),
    ("blank group kept", "guard !words.isEmpty else { return nil }", ""),
    ("Other is a group", "if name.caseInsensitiveCompare(otherTitle) == .orderedSame { return nil }", ""),
    ("only Other itself, not other", "if name.caseInsensitiveCompare(otherTitle) == .orderedSame { return nil }",
     "if name == otherTitle { return nil }"),
    ("a preset in another case is another group",
     "return presetGroups.first { $0.caseInsensitiveCompare(name) == .orderedSame } ?? name", "return name"),
    ("decode ignores empty macID check", "where !macID.isEmpty && macID.count <= 128", "where macID.count <= 128"),
    ("setting nil does not remove", "        } else {\n            next.removeValue(forKey: macID)", "        } else {"),
    ("a name in another case makes a second group",
     "next[macID] = groups.values.filter { $0.caseInsensitiveCompare(clean) == .orderedSame }.min() ?? clean",
     "next[macID] = clean"),
    # A superseded record's group.
    ("the successor's own group replaced", "if next[new] == nil { next[new] = group }", "next[new] = group"),
    ("the group not carried", "if next[new] == nil { next[new] = group }", ""),
    ("the retired record keeps its group", "next.removeValue(forKey: old)", ""),
    # The order of groups and sections.
    ("custom groups dropped", "ordered(Set(presetGroups).union(groups.values.compactMap(cleanGroup)))", "ordered(Set(presetGroups))"),
    ("presets sorted with the rest", "presetGroups.filter(names.contains) + names.subtracting(presetGroups).sorted {",
     "names.sorted {"),
    ("other names in reverse", "return order == .orderedSame ? a < b : order == .orderedAscending",
     "return order == .orderedSame ? a < b : order == .orderedDescending"),
    ("other names in plain code order", "let order = a.localizedStandardCompare(b)", "let order = a.compare(b)"),
    ("sections sorted without the presets first", "var out = ordered(Set(byGroup.keys)).compactMap",
     "var out = byGroup.keys.sorted().compactMap"),
    ("empty items returns a section", "guard !items.isEmpty else { return [] }", ""),
    ("ungrouped list titled Other even with no groups", "guard !byGroup.isEmpty else { return [Section(title: nil, items: items)] }",
     "guard !byGroup.isEmpty else { return [Section(title: otherTitle, items: items)] }"),
    ("ungrouped rows dropped when groups exist", "if !ungrouped.isEmpty { out.append(Section(title: otherTitle, items: ungrouped)) }", ""),
    # Pictures' files.
    ("path traversal allowed in previewFileName", "macID.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == \"-\" || $0 == \"_\") })", "true"),
    ("previewFileName length uncapped", "macID.count <= 128,", ""),
    ("stalePreviewFiles deletes non-jpg", "guard file.hasSuffix(\".jpg\") else { return false }", "if !file.hasSuffix(\".jpg\") { return true }"),
    ("stalePreviewFiles deletes kept Macs", "return !keepingMacIDs.contains(id)", "return keepingMacIDs.contains(id)"),
    # Tiles' columns.
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
