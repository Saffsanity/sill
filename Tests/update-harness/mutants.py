"""Update Now's mechanism mutants (docs/one-click-update-plan.md §11, G2): each changes UpdateInstaller.swift in
one place where nothing else stands behind it, in a copy of Sources/SillMenuBar; run.sh then builds and runs the
harness on the copy (SILL_HARNESS_SOURCES), and it must fail. Several minutes a mutant: each builds the harness
and its test apps again. usage: python3 -I mutants.py [NAME…] (only the mutants named)"""
import os, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
SRC = os.path.join(ROOT, "Sources/SillMenuBar")
F = "UpdateInstaller.swift"
MUTANTS = [
    ("any redirect followed", "guard let url = request.url, redirects <= maxRedirects, allowed(url) else {", "guard let url = request.url else {"),
    ("no check right before the swap", "        switch check(staged, manifest: manifest, running: running, runningRequirement: runningRequirement) {\n        case .success(let c) where c == expected: break\n", "        switch Result<Policy.Checked, Failure>.success(expected) {\n        case .success(let c) where c == expected: break\n"),
    ("the note after the swap", "        if let leftoverNote { Self.noteLeftover(staged.deletingLastPathComponent(), in: leftoverNote) }\n        beforeSwap?()\n        guard renamex_np(staged.path, installed.path, UInt32(RENAME_SWAP)) == 0 else { return .failure(.swapFailed(Self.errnoText())) }\n", "        beforeSwap?()\n        guard renamex_np(staged.path, installed.path, UInt32(RENAME_SWAP)) == 0 else { return .failure(.swapFailed(Self.errnoText())) }\n        if let leftoverNote { Self.noteLeftover(staged.deletingLastPathComponent(), in: leftoverNote) }\n"),
    ("hard links taken", "            case S_IFREG: if e.st_nlink != 1 { return \"\\(rel) has another name (a hard link)\" }\n", "            case S_IFREG: break\n"),
    ("a link for the signature's file", "            if let t = type(base + \"/\" + path), t != S_IFREG { return \"\\(path) is not a file\" }\n", ""),
    ("any Sill waited for", "        pids.filter { process($0, satisfies: requirement) }\n", "        pids\n"),
    ("no check after the swap", "        switch check(installed, manifest: manifest, running: running, runningRequirement: runningRequirement) {\n        case .success(let c) where c == expected: return .success(())", "        switch Result<Policy.Checked, Failure>.success(expected) {\n        case .success(let c) where c == expected: return .success(())"),
    ("the copy at the path not compared with the running one", "        guard Self.cdhash(of: installed, arch: .current) == runningCDHash else { return .failure(.changedSinceStart) }\n", ""),
    ("anything in staging put back", "        guard isTheOldCopy(staged, old: old) else { return .notTheOldCopy }\n", ""),
    ("a cdhash alone taken for the old copy", "        return SecStaticCodeCheckValidityWithErrors(code, Self.strictFlags, requirement, nil) == errSecSuccess\n", "        return true\n"),
    ("a copy that failed its check left in place", "        if back != .done { Self.moveAside(installed, into: staged.deletingLastPathComponent()) }\n", ""),
    ("a set-aside folder left named NSIRD_", "        let folder = renamex_np(staging.path, named.path, UInt32(RENAME_EXCL)) == 0 ? named : staging\n", "        let folder = staging\n"),
    ("a Content-Length that disagrees taken", "            if let exactSize, length != exactSize { failure = .sizeMismatch; completionHandler(.cancel); return }\n", ""),
    ("no process found running from the app", "            guard same || text.hasPrefix(prefix) else { continue }", "            guard false else { continue }"),
    ("a link to the app not seen", "            if lstat(walk.path, &l) == 0, l.st_mode & S_IFMT == S_IFLNK { link = true; break }", "            if false { link = true; break }"),
    ("a kept copy cleaned up", "        return lstat(url.appendingPathComponent(keptMarker).path, &marker) != 0\n", "        return true\n"),
    ("a noted folder anywhere removed", "        guard url.deletingLastPathComponent().path == parent.path,\n", "        guard true,\n"),
    # The stop (review 3, the automatic update's point 1).
    ("a stop ignored", "                if stop.tag == release.tag, stop.sha256 == manifest.sha256 { return .failure(.stopped(tag: release.tag)) }\n", ""),
    ("a stop taken unsigned", "            case .failure(let p):\n                return .failure(.stopUnreadable(p))\n", "            case .failure:\n                break\n"),
    # The watcher (review 3, the automatic update's point 6).
    ("the watcher puts back a changed old copy", "/usr/bin/codesign --verify --deep --strict \"-R=$req\" \"$old\" >/dev/null 2>&1 || exit 3\n", ""),
    ("the watcher ignores the started note", "proved() { [ -f \"$started\" ]", "proved() { false && [ -f \"$started\" ]"),
    ("any note proves the new copy", " && [ \"$(/usr/bin/head -n 1 \"$started\" 2>/dev/null)\" = \"$token\" ]", ""),
    ("the watcher stops any process", "if running; then\n    why=", "if true; then\n    why="),
    ("the watcher never puts back", "/bin/mv \"$app\" \"$parked\" || exit 5\n", "exit 5\n"),
    ("the watcher doesn't start the old copy", "\"$launcher\" \"$app\"\nexit 0\n", "exit 0\n"),
]
caught = 0
ONLY = sys.argv[1:]
if ONLY: MUTANTS = [m for m in MUTANTS if m[0] in ONLY]
for name, old, new in MUTANTS:
    src = open(os.path.join(SRC, F)).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)", flush=True); continue
    with tempfile.TemporaryDirectory() as t:
        copy = os.path.join(t, "SillMenuBar")
        shutil.copytree(SRC, copy)
        open(os.path.join(copy, F), "w").write(src.replace(old, new, 1))
        r = subprocess.run([os.path.join(HERE, "run.sh")], capture_output=True, text=True, timeout=1800,
                           env=dict(os.environ, SILL_HARNESS_SOURCES=copy))
        failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        if r.returncode != 0 and failed:
            caught += 1
            print(f"{name}: caught ({failed[0][:110]})", flush=True)
        elif r.returncode != 0:
            print(f"{name}: did not run (exit {r.returncode}): {(r.stderr or r.stdout)[-300:]}", flush=True)
        else:
            print(f"{name}: NOT CAUGHT", flush=True)
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
