"""Mutants of InstalledApps.swift (#76, #370): each changes it in one place, is compiled with the check
and must make it fail. A file that is no folder is refused by contentsOfDirectory(at:) itself
(ENOTDIR), and a link never reaches that test (the alias branch takes it first), so dropping the
isDirectory test changes nothing and is no mutant here; nor are an alias's resolution options (no UI,
no mounting: nothing in a temporary folder needs either) or a link's text standardized (URL's path
already drops its "..": no change). The I/O Registry's roles and the mount table's flags are checked
on the real table (/ read-only, /System/Volumes/Data the Data volume, not shown in Finder). The unsorted mutant counts on APFS
listing a folder in its own order (by a hash of each name), which puts the fixture's "right" before
"left"; a file system that lists names sorted would miss it. usage: mutants.py WORKTREE"""
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
    # #370: links and aliases, and the reach of each look.
    ("links and aliases not followed (Finder's aliases never listed, as before #370)",
     "if values?.isAliasFile == true {", "if false {"),
    ("links and aliases followed onto any volume",
     "guard InstalledApps.inside(path, volumesRoot) else { return true }", "return true"),
    ("the second look follows them onto no volume",
     "return volumes?.contains { InstalledApps.inside(path, $0) } == true", "return false"),
    ("where a link or an alias points not read before it is resolved",
     "pointsAt(link), reach.allows(named),", "pointsAt(link),"),
    ("where it resolves to not looked at",
     ' && reach.allows(target.path) ? target', " ? target"),
    ("an alias to a bundle that is no app listed",
     'target.pathExtension == "app" && ', ""),
    ("/private/var and /var counted as two folders",
     'path.hasPrefix("/private/") ? String(path.dropFirst("/private".count)) : path', "path"),
    ("the first look reads a folder given that leads into the volumes",
     "if reach.volumes == nil && !reach.allows(folder.path) { continue }", ""),
    # #370: which volumes, and which of their folders.
    ("a network share read",
     "volume.local && ", ""),
    ("a read-only volume read (an installer's disk image)",
     "!volume.readOnly && ", ""),
    ("a volume Finder does not show read (Recovery)",
     "volume.browsable && ", ""),
    ("a volume with an APFS role read (another Mac's data, a backup)",
     "volume.roles.isEmpty", "true"),
    ("a volume with a dot name read",
     ' && !mount.lastPathComponent.hasPrefix(".")', ""),
    ("a volume mounted anywhere read",
     "plain(mount.deletingLastPathComponent().path) == plain(root) && ", ""),
    ("a volume mounted deeper in /Volumes read",
     "plain(mount.deletingLastPathComponent().path) == plain(root)", "plain(mount.deletingLastPathComponent().path).hasPrefix(plain(root))"),
    ("the volumes left in the table's order",
     "}.map(\\.path).sorted()", "}.map(\\.path)"),
    ("a link at a volume's top read as its Applications folder",
     "lstat(folder, &info)", "stat(folder, &info)"),
    ("an older Mac's disk read (its macOS's Applications)",
     '!FileManager.default.fileExists(atPath: volume + "/System/Library/CoreServices/SystemVersion.plist")', "true"),
    ("the mount table's local flag misread",
     "local: entry.f_flags & UInt32(MNT_LOCAL) != 0", "local: entry.f_flags & UInt32(MNT_LOCAL) == 0"),
    # Review of #405: the second look follows a device, never a login.
    ("the second look at launch, with no device (macOS asks then)",
     "        devices > 0 && own != asked\n", "        own != asked\n"),
    ("the second look once only, never again when the volumes change",
     "        devices > 0 && own != asked\n", "        devices > 0 && asked == nil\n"),
    ("a second look at every device and every mount",
     "        devices > 0 && own != asked\n", "        devices > 0\n"),
    ("no second look while no volume of one's own was ever there",
     "        devices > 0 && own != asked\n", "        devices > 0 && own != (asked ?? [])\n"),
    # Review of #405: the first look stays out of the home folder but its Applications folder.
    ("the first look follows links and aliases anywhere in the home folder (Downloads: macOS asks at launch)",
     "            if volumes == nil && InstalledApps.inside(path, home) && !InstalledApps.inside(path, home + \"/Applications\") { return false }\n", ""),
    ("the first look stays out of the home folder's Applications folder too",
     " && !InstalledApps.inside(path, home + \"/Applications\")", ""),
    ("the second look stays out of the home folder too",
     "if volumes == nil && InstalledApps.inside(path, home) &&", "if InstalledApps.inside(path, home) &&"),
    ("the first look reads a folder given that leads into the home folder (the volumes alone left to the second)",
     "if reach.volumes == nil && !reach.allows(folder.path) { continue }",
     "if reach.volumes == nil && inside(folder.path, reach.volumesRoot) { continue }"),
    # Review of #405: rules the check did not reach.
    ("a relative link's text read against the current folder, not its own",
     "relativeTo: link.deletingLastPathComponent())", "relativeTo: nil)"),
    ("a volume counted inside another whose name begins its own (/Volumes/Old Mac - Data in /Volumes/Old Mac)",
     'p.hasPrefix(f.hasSuffix("/") ? f : f + "/")', "p.hasPrefix(f)"),
    ("the mount table's read-only flag misread",
     "readOnly: entry.f_flags & UInt32(MNT_RDONLY) != 0", "readOnly: entry.f_flags & UInt32(MNT_RDONLY) == 0"),
    ("the mount table's don't-browse flag misread",
     "browsable: entry.f_flags & UInt32(MNT_DONTBROWSE) == 0", "browsable: entry.f_flags & UInt32(MNT_DONTBROWSE) != 0"),
    ("the I/O Registry asked for a property that is not there (no volume has a role)",
     '"Role" as CFString', '"Roles" as CFString'),
    ("the I/O Registry asked by the device's path, not its BSD name",
     'roles(of: String(from.dropFirst("/dev/".count)))', "roles(of: from)"),
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
