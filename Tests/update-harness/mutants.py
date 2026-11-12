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
    ("no check right before the swap", "        switch check(staged, manifest: manifest, running: running, runningRequirement: runningRequirement, runningBuild: runningBuild) {\n        case .success(let c) where c == expected: break\n", "        switch Result<Policy.Checked, Failure>.success(expected) {\n        case .success(let c) where c == expected: break\n"),
    ("the note after the swap", "        if let leftoverNote { Self.noteLeftover(staged.deletingLastPathComponent(), in: leftoverNote) }\n        afterNote?()\n        switch check(staged, manifest: manifest, running: running, runningRequirement: runningRequirement, runningBuild: runningBuild) {\n        case .success(let c) where c == expected: break\n        case .failure(.bundle(let p)): return .failure(.bundle(p))\n        default: return .failure(.bundle(.codeChanged))\n        }\n        beforeSwap?()\n        guard renamex_np(staged.path, installed.path, UInt32(RENAME_SWAP)) == 0 else { return .failure(.swapFailed(Self.errnoText())) }\n", "        switch check(staged, manifest: manifest, running: running, runningRequirement: runningRequirement, runningBuild: runningBuild) {\n        case .success(let c) where c == expected: break\n        case .failure(.bundle(let p)): return .failure(.bundle(p))\n        default: return .failure(.bundle(.codeChanged))\n        }\n        beforeSwap?()\n        guard renamex_np(staged.path, installed.path, UInt32(RENAME_SWAP)) == 0 else { return .failure(.swapFailed(Self.errnoText())) }\n        if let leftoverNote { Self.noteLeftover(staged.deletingLastPathComponent(), in: leftoverNote) }\n        afterNote?()\n"),
    # The second security pass: R3, W1, W2.
    ("R3: the note between the last check and the swap", "        if let leftoverNote { Self.noteLeftover(staged.deletingLastPathComponent(), in: leftoverNote) }\n        afterNote?()\n        switch check(staged, manifest: manifest, running: running, runningRequirement: runningRequirement, runningBuild: runningBuild) {\n        case .success(let c) where c == expected: break\n        case .failure(.bundle(let p)): return .failure(.bundle(p))\n        default: return .failure(.bundle(.codeChanged))\n        }\n", "        switch check(staged, manifest: manifest, running: running, runningRequirement: runningRequirement, runningBuild: runningBuild) {\n        case .success(let c) where c == expected: break\n        case .failure(.bundle(let p)): return .failure(.bundle(p))\n        default: return .failure(.bundle(.codeChanged))\n        }\n        if let leftoverNote { Self.noteLeftover(staged.deletingLastPathComponent(), in: leftoverNote) }\n        afterNote?()\n"),
    ("hard links taken", "            case S_IFREG: if e.st_nlink != 1 { return \"\\(rel) has another name (a hard link)\" }\n", "            case S_IFREG: break\n"),
    ("a link for the signature's file", "            if let t = type(base + \"/\" + path), t != S_IFREG { return \"\\(path) is not a file\" }\n", ""),
    ("any Sill waited for", "        pids.filter { process($0, satisfies: requirement) }\n", "        pids\n"),
    ("no check after the swap", "        switch check(installed, manifest: manifest, running: running, runningRequirement: runningRequirement, runningBuild: runningBuild) {\n        case .success(let c) where c == expected: return .success(())", "        switch Result<Policy.Checked, Failure>.success(expected) {\n        case .success(let c) where c == expected: return .success(())"),
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
    ("a stop ignored", "                    return .failure(.stopped(tag: release.tag))\n", "                    _ = stop\n"),
    ("a stop taken unsigned", "            case .failure(let p):\n                return .failure(.stopUnreadable(p))\n", "            case .failure:\n                break\n"),
    # The watcher (review 3, the automatic update's point 6).
    ("the watcher puts back a changed old copy", "whole \"$old\" || exit 3\n", ""),
    ("the watcher ignores the started note", "proved() { [ -f \"$started\" ]", "proved() { false && [ -f \"$started\" ]"),
    ("W2: a link at the started note taken", "proved() { [ -f \"$started\" ] && [ ! -L \"$started\" ]; }", "proved() { [ -f \"$started\" ]; }"),
    ("W1: the watcher starts what it didn't check", "if ! whole \"$app\"; then\n    /bin/mv \"$app\" \"$dir/failed its check.app\" || exit 7\n", "if false; then\n    /bin/mv \"$app\" \"$dir/failed its check.app\" || exit 7\n"),
    ("W1: the restored note written through a link", "note=$(/usr/bin/mktemp \"$restored.XXXXXX\") && /usr/bin/printf '%s\n%s\n' \"$token\" \"$why\" 1<>\"$note\" && /bin/mv -f -h \"$note\" \"$restored\"\n", "/usr/bin/printf '%s\n%s\n' \"$token\" \"$why\" > \"$restored\"\n"),
    ("W1: a link taken for the old copy", "    [ -d \"$1\" ] && [ ! -L \"$1\" ] || return 1\n", ""),
    ("W2: notes read with Data(contentsOf:)", "        guard let data = readSmallFile(url), let text = String(data: data, encoding: .utf8) else { return nil }", "        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) else { return nil }"),
    ("W2: a link where a note goes followed", "O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC", "O_RDONLY | O_NONBLOCK | O_CLOEXEC"),
    # Use nightly builds (plan §16): each channel with its own keys, the pair, the offer read again, the order.
    ("N: the nightly read with the update keys too", "        switch UpdateManifest.verify(manifestBody.data, keys: trust.nightlyKeys, channel: .nightly) {\n", "        switch UpdateManifest.verify(manifestBody.data, keys: trust.updateKeys + trust.nightlyKeys, channel: .nightly) {\n"),
    ("N: a release read with the nightly keys too", "        let keys = trust.updateKeys\n", "        let keys = trust.updateKeys + trust.nightlyKeys\n"),
    ("N: a half-published pair taken", "            if let f = Policy.nightlyMatches(m, listing: listing, endpoints: endpoints) { return .failure(f) }\n", ""),
    ("N: a nightly that moved on since the offer taken", "                guard n.manifest.version == offeredVersion, n.manifest.build == String(offeredBuild) else {\n", "                guard true else {\n"),
    ("N: an older nightly prepared", "                guard Policy.isNewer(n.manifest.version, build: offeredBuild, than: running, runningBuild: runningBuild, byBuild: true) else {\n", "                guard true else {\n"),
    # The third security pass's W3 and N10 l.
    ("W3: Sill's path left empty when the last check fails", "    if [ -e \"$app\" ] || [ -L \"$app\" ] || ! /bin/mv \"$parked\" \"$app\"; then exit 7; fi\n", ""),
    ("W3: a file with two names taken", "    [ -z \"$many\" ] || return 1\n", ""),
    ("N10 l: a stop by its tag's text", "                if Policy.stopNames(stopTag: stop.tag, stopSHA256: stop.sha256, release: release, manifestSHA256: manifest.sha256) {\n", "                if stop.tag == release.tag, stop.sha256 == manifest.sha256 {\n"),
    ("CL1: GitHub's clock never read", "        serverDate = http.value(forHTTPHeaderField: \"Date\").flatMap(UpdateInstallPolicy.httpDate)\n", ""),
    ("CL1: GitHub's clock left off the release", "        release.answeredAt = api.serverDate\n", ""),
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
