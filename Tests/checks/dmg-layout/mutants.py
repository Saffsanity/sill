"""Mutants of Scripts/dmg-layout (DSStore.swift, FinderAlias.swift, DMGLayout.swift) and of what
make-dmg.sh and design/DMGBackground.svg give it: each changes one file in one place, in a copy of the
five, and is run through the check (main.swift, with the layout arguments the copy of make-dmg.sh
gives), which must fail. usage: mutants.py"""
import os, shutil, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))       # the repository
OUT = os.path.join(ROOT, ".build", "checks", "dmg-layout", "mutants")
SWIFT = ["Scripts/dmg-layout/DSStore.swift", "Scripts/dmg-layout/FinderAlias.swift", "Scripts/dmg-layout/DMGLayout.swift"]
FILES = SWIFT + ["Scripts/make-dmg.sh", "design/DMGBackground.svg"]
D, A, L = "Scripts/dmg-layout/DSStore.swift", "Scripts/dmg-layout/FinderAlias.swift", "Scripts/dmg-layout/DMGLayout.swift"
MUTANTS = [
    # the window
    (L, "a 28-point title bar (the picture's bottom 4 points hidden on macOS 27)", "static let titleBar = 32", "static let titleBar = 28"),
    (L, "the content's height alone", "{\\(width), \\(height + Self.titleBar)}}", "{\\(width), \\(height)}}"),
    (L, "the window at the screen's corner", '"{{\\(left), \\(top)}, {', '"{{0, 0}, {'),
    (L, "the toolbar shown", '"ShowToolbar": false,', '"ShowToolbar": true,'),
    (L, "the sidebar shown", '"ShowSidebar": false,', '"ShowSidebar": true,'),
    (L, "list view", 'value: .type("icnv")', 'value: .type("Nlsv")'),
    (L, "no vSrn", '            DSRecord(name: ".", code: "vSrn", value: .long(1)),\n', ""),
    (L, "a colour, not the picture", '"backgroundType": 2,', '"backgroundType": 1,'),
    (L, "red and blue swapped", '"backgroundColorBlue": Double(backgroundColor.blue) / 255,', '"backgroundColorBlue": Double(backgroundColor.red) / 255,'),
    (L, "names beside the icons", '"labelOnBottom": true,', '"labelOnBottom": false,'),
    (L, "icons arranged on a grid", '"arrangeBy": "none",', '"arrangeBy": "grid",'),
    (L, "the icon size as a whole number", '"iconSize": Double(iconSize),', '"iconSize": iconSize,'),
    (L, "the hidden items inside the window", "y: height + iconSize * 2)", "y: height / 2)"),
    (L, "the hidden items left for Finder to place", "            records.append(DSRecord(name: name, code: \"Iloc\", value: .blob(Self.location(x: place.x, y: place.y))))\n", ""),
    (L, "an icon's place without Finder's eight bytes", "[0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0, 0]", "[0, 0, 0, 0, 0, 0, 0, 0]"),
    (L, "the custom-icon flag's bit", "static let hasCustomIcon: UInt16 = 0x0400", "static let hasCustomIcon: UInt16 = 0x4000"),
    (L, "the folder's other Finder info dropped", "        var info = finderInfo(path)\n", "        var info = [UInt8](repeating: 0, count: 32)\n"),
    # the file
    (D, "names sorted with case", "let an = Array(a.name.lowercased().utf16), bn = Array(b.name.lowercased().utf16)",
     "let an = Array(a.name.utf16), bn = Array(b.name.utf16)"),
    (D, "free lists from 2^30", "visit(0, 31)", "visit(0, 30)"),
    (D, "the header's 00 00 10 0c", "[0, 0, 0x10, 0x0c]", "[0, 0, 0, 0]"),
    (D, "no page size in DSDB", "master.appendWord(UInt32(pageSize))", "master.appendWord(0)"),
    (D, "one record too many counted", "leaf.appendWord(UInt32(sorted.count))", "leaf.appendWord(UInt32(sorted.count + 1))"),
    (D, "the blocks numbered in another order", "let blocks = [(rootAddress, rootSize), (masterAddress, masterSize), (leafAddress, pageSize)]",
     "let blocks = [(masterAddress, masterSize), (rootAddress, rootSize), (leafAddress, pageSize)]"),
    (D, "shor in two bytes", 'case .shor(let v): append(contentsOf: Array("shor".utf8)); appendWord(UInt32(v))',
     'case .shor(let v): append(contentsOf: Array("shor".utf8)); append(UInt8(v >> 8)); append(UInt8(v & 0xff))'),
    (D, "ustr counted in bytes", 'appendWord(UInt32(v.utf16.count)); appendUTF16(v)', 'appendWord(UInt32(v.utf8.count)); appendUTF16(v)'),
    (D, "duplicates let through", 'for (a, b) in zip(sorted, sorted.dropFirst()) where !precedes(a, b) {', 'for (a, b) in zip(sorted, sorted.dropFirst()) where false && !precedes(a, b) {'),
    (D, "decode: a separator before its child", "                if last != 0 { try walk(children[index]) }\n                records.append(record)\n",
     "                records.append(record)\n                if last != 0 { try walk(children[index]) }\n"),
    # the alias
    (A, "the 4-byte dates in UTC", " + Int64(timeZone.secondsFromGMT(for: date))", ""),
    (A, "tag 2 without its NUL", 'carbon.joined(separator: ":\\0")', 'carbon.joined(separator: ":")'),
    (A, "the mount point where it was made", 'mountPoint: "/Volumes/" + name)', "mountPoint: root)"),
    (A, "the folder IDs from the root down", "for depth in stride(from: components.count - 1, through: 1, by: -1) {", "for depth in 1..<components.count {"),
    (A, "no dates in tags 16 and 17", "        tag(16, long(UInt64(Self.hfsSeconds(volumeCreated)) << 16))\n        tag(17, long(UInt64(Self.hfsSeconds(fileCreated)) << 16))\n", ""),
    (A, "tag 18 after 19", "        tag(18, Data(path.utf8))\n        tag(19, Data(mountPoint.utf8))\n", "        tag(19, Data(mountPoint.utf8))\n        tag(18, Data(path.utf8))\n"),
    (A, "odd values not padded", "            if value.count % 2 == 1 { record.append(0) }\n", ""),
    (A, "the volume attributes zero", "record.appendWord(0x0d02)", "record.appendWord(0)"),
    (A, "a fixed disk", "record.append(half(5))", "record.append(half(0))"),
    (A, "the length left at zero", "        record.replace(at: 4, with: half(Int16(record.count)))\n", ""),
    (A, "a colon kept in the Pascal names", 'let bytes = Array(string.replacingOccurrences(of: ":", with: "/").utf8)', "let bytes = Array(string.utf8)"),
    (A, "a name of 28 bytes let in", "bytes.count < size else {", "bytes.count <= size else {"),
    # what make-dmg.sh and the picture give it
    ("Scripts/make-dmg.sh", "the icons swapped", "--item Sill.app=170,180 --item Applications=490,180", "--item Sill.app=490,180 --item Applications=170,180"),
    ("Scripts/make-dmg.sh", "the old grey edge", "edge=ffffff", "edge=f2f3f5"),
    ("design/DMGBackground.svg", "a picture 4 points taller", 'width="660" height="400" viewBox="0 0 660 400"', 'width="660" height="404" viewBox="0 0 660 404"'),
    ("design/DMGBackground.svg", "a gradient to the edges again", '<rect x="0" y="0" width="660" height="400" fill="#ffffff">', '<rect x="0" y="0" width="660" height="400" fill="url(#d-bg)">'),
]

caught = 0
for path, name, old, new in MUTANTS:
    source = open(os.path.join(ROOT, path)).read()
    if source.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {source.count(old)} times in {path})")
        continue
    tree = os.path.join(OUT, "tree")
    shutil.rmtree(tree, ignore_errors=True)
    for f in FILES:
        os.makedirs(os.path.dirname(os.path.join(tree, f)), exist_ok=True)
        shutil.copy(os.path.join(ROOT, f), os.path.join(tree, f))
    open(os.path.join(tree, path), "w").write(source.replace(old, new))
    layout = subprocess.run(["/bin/bash", "-c", 'source Scripts/make-dmg.sh && printf "%s\\n" "${layout[@]}"'],
                            cwd=tree, capture_output=True, text=True)
    open(os.path.join(tree, "layout.txt"), "w").write(layout.stdout)
    exe = os.path.join(tree, "check")
    build = subprocess.run(["swiftc", "-O"] + [os.path.join(tree, f) for f in SWIFT] + [os.path.join(HERE, "main.swift"), "-o", exe],
                           capture_output=True, text=True)
    if build.returncode != 0:
        print(f"{name}: DOES NOT COMPILE\n{build.stderr[:600]}")
        continue
    work = os.path.join(tree, "out")
    os.makedirs(work, exist_ok=True)
    run = subprocess.run([exe, work, os.path.join(tree, "layout.txt"), os.path.join(tree, "design/DMGBackground.svg")],
                         capture_output=True, text=True, timeout=120)
    failed = [l[5:] for l in run.stdout.splitlines() if l.startswith("FAIL")]
    if run.returncode != 0:
        caught += 1
        print(f"caught {name}: {len(failed)} failing, e.g. {failed[0][:110] if failed else f'exit status {run.returncode}'}", flush=True)
    else:
        print(f"NOT CAUGHT {name}", flush=True)
shutil.rmtree(os.path.join(OUT, "tree"), ignore_errors=True)
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
