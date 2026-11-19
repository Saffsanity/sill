"""Mutants of MicrophoneTestHook (Sources/SillHost/MicrophoneTestHook.swift): each must compile and make the check
fail. usage: mutants.py ROOT"""
import os, subprocess, sys, tempfile
ROOT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ROOT, "Sources/SillHost/MicrophoneTestHook.swift")
MUTANTS = [
    ("a real host takes it", "        guard testHost else {", "        guard testHost || true else {"),
    ("any value a sink", "        guard raw.hasPrefix(\"file:\") else { return nil }", "        guard raw.hasPrefix(\"file\") else { return nil }"),
    ("an empty path taken", "        guard !p.isEmpty, p.utf8.count <= 1024 else { return nil }", "        guard p.utf8.count <= 1024 else { return nil }"),
    ("the app file's 0 counts as one", "        return c != \"0\" && !c.isEmpty", "        return !c.isEmpty"),
    ("a missing app file counts as one", "        guard let c = contents?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }",
     "        guard let c = contents?.trimmingCharacters(in: .whitespacesAndNewlines) else { return true }"),
    ("notloaded set up", "        return c != \"missing\" && c != \"notloaded\"", "        return c != \"missing\""),
    ("the log with any value", "log: environment[logVariable] == \"1\"", "log: environment[logVariable] != nil"),
    ("two channels in the header", "u16(3); u16(1); u32(UInt32(sampleRate))", "u16(3); u16(2); u32(UInt32(sampleRate))"),
    ("PCM in the header", "u16(3); u16(1);", "u16(1); u16(1);"),
    ("the RIFF size without the header", "u32(36 &+ dataBytes)", "u32(dataBytes)"),
    ("a lone variable without its line", "                return (nil, \"\\(v) ignored: it needs \\(sinkVariable).\")", "                return (nil, nil)"),
]
caught = 0
orig = open(SRC).read()
for name, old, new in MUTANTS:
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        src = os.path.join(t, "MicrophoneTestHook.swift"); open(src, "w").write(orig.replace(old, new, 1))
        exe = os.path.join(t, "check")
        c = subprocess.run(["swiftc", "-O", src, os.path.join(HERE, "main.swift"), "-o", exe], capture_output=True, text=True)
        if c.returncode != 0:
            print(f"{name}: did not compile\n{c.stderr[:300]}"); continue
        r = subprocess.run([exe], capture_output=True, text=True, timeout=120)
        failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        if r.returncode != 0:
            caught += 1; print(f"{name}: caught ({failed[0][:100] if failed else r.returncode})")
        else:
            print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
