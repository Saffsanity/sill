"""H3 (docs/update-notice-plan.md) mutants of UpdatePolicy.swift: each changes it in one place, is compiled
with the check by build.sh and must make it fail. usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
F = os.path.join(WT, "Sources/SillMenuBar/UpdatePolicy.swift")
MUTANTS = [
    ("the same version offered", "UpdatePolicy.swift", "return (r.version > running ? .newer", "return (r.version >= running ? .newer"),
    ("404 keeps the stored release", "UpdatePolicy.swift", "next.etag = nil; next.latestTag = nil; next.latestURL = nil", "next.etag = nil"),
    ("a 200 without an ETag keeps the old one", "UpdatePolicy.swift", "next.etag = etag      // a 200 without one clears it", "next.etag = etag ?? stored.etag      // a 200 without one clears it"),
    ("drafts accepted", "UpdatePolicy.swift", "if object[\"draft\"] as? Bool == true { return .failure(.draft) }", ""),
    ("prereleases accepted", "UpdatePolicy.swift", "if object[\"prerelease\"] as? Bool == true { return .failure(.prerelease) }", ""),
    ("http release pages", "UpdatePolicy.swift", "return scheme == \"https\" && host.lowercased() == \"github.com\" ? url : nil", "return (scheme == \"https\" || scheme == \"http\") && host.lowercased() == \"github.com\" ? url : nil"),
    ("github.com as a prefix", "UpdatePolicy.swift", "return scheme == \"https\" && host.lowercased() == \"github.com\" ? url : nil", "return scheme == \"https\" && host.lowercased().hasPrefix(\"github.com\") ? url : nil"),
    ("a clock that went back is never due", "UpdatePolicy.swift", "return now.timeIntervalSince(lastCheck) >= period || lastCheck > now", "return now.timeIntervalSince(lastCheck) >= period"),
    ("loosely local feeds", "UpdatePolicy.swift", "return host == \"127.0.0.1\" || host == \"::1\" || host == \"[::1]\" || host == \"localhost\"", "return host.hasPrefix(\"127.\") || host == \"::1\" || host == \"[::1]\" || host.hasPrefix(\"localhost\")"),
    ("a timeout read as no connection", "UpdatePolicy.swift", "if code == -1001 { return (.timeout, stored) }", "if code == -1001 { return (.noConnection(code: code, description: description), stored) }"),
    ("up to date logged by automatic checks", "UpdatePolicy.swift", "return manual ? \"Update check: up to date", "return true ? \"Update check: up to date"),
    ("a retry that fell due asleep runs at once", "UpdatePolicy.swift", "if let retryAt { return max(retryAt, now.addingTimeInterval(delay)) }", "if let retryAt { return retryAt }"),
    ("no jitter", "UpdatePolicy.swift", "return lastCheck!.addingTimeInterval(period + jitter)", "return lastCheck!.addingTimeInterval(period)"),
    ("a stored page offered unchecked", "UpdatePolicy.swift", "guard let running, let tag = stored.latestTag, let version = SillVersion(tag), version > running,\n              let text = stored.latestURL, let url = releasePage(text, anyReleaseURL: anyReleaseURL) else { return nil }", "guard let running, let tag = stored.latestTag, let version = SillVersion(tag), version > running,\n              let text = stored.latestURL, let url = URL(string: text) else { return nil }"),
    ("fewer no-connection codes", "UpdatePolicy.swift", "static let noConnectionCodes: Set<Int> = [-1009, -1005, -1004, -1003, -1006, -1020, -1018]", "static let noConnectionCodes: Set<Int> = [-1009, -1005, -1004, -1003]"),
    ("TLS failures read as offline", "UpdatePolicy.swift", "return (tlsCodes.contains(code) ? \"Couldn’t check: \\(description)\" : \"Couldn’t check: this Mac isn’t connected to the internet.\", true)", "return (\"Couldn’t check: this Mac isn’t connected to the internet.\", true)"),
    ("Check Now enabled in test pattern mode", "UpdatePolicy.swift", "let canCheck = hasVersion && !testPatternOnly", "let canCheck = hasVersion"),
    ("Check Now enabled while checking", "UpdatePolicy.swift", "var p = Pane(line: notCheckedLine, releasePage: offer?.url, canCheck: canCheck && !checking, resultID: resultID)", "var p = Pane(line: notCheckedLine, releasePage: offer?.url, canCheck: canCheck, resultID: resultID)"),
]
caught = 0
for name, _, old, new in MUTANTS:
    src = open(F).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        mf = os.path.join(t, "UpdatePolicy.swift"); open(mf, "w").write(src.replace(old, new, 1))
        exe = os.path.join(t, "c")
        subprocess.run([os.path.join(HERE, "build.sh"), WT, exe, mf], capture_output=True, text=True)
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
