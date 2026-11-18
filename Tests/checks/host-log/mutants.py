"""Mutants of HostLog.swift (Sources/SillHost): each changes the log file's writer in one place and must make
the check (main.swift) fail. usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "host-log")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "Sources/SillHost/HostLog.swift")
orig = open(SRC).read()
MUTANTS = [
    ("A1 the file not opened for appending (each Sill writes at a place of its own, as before 2026-11-14)",
     "O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC", "O_WRONLY | O_CREAT | O_CLOEXEC"),
    ("A2 a file another Sill moved aside, or a deleted one, not noticed",
     "if let handle, !Self.same(handle.fileDescriptor, url.path) {", "if let handle, handle.fileDescriptor < 0 {"),
    ("A3 the same file judged by its volume alone",
     "return open.st_dev == named.st_dev && open.st_ino == named.st_ino", "return open.st_dev == named.st_dev"),
    ("A4 the file's length counted from this Sill's lines alone",
     "size = (try? handle.offset()) ?? size + UInt64(data.count)", "size += UInt64(data.count)"),
    ("R1 a file past 10 MB never moved aside while running",
     "        handle = nil\n        moveAside()\n        reopen()", "        handle = nil\n        reopen()"),
    ("R2 a file at 10 MB at launch moved aside only at the first line",
     "if existing >= Self.rotateAt { moveAside() }", "if existing > Self.rotateAt { moveAside() }"),
    ("R3 the file moved aside one line late (once a line has passed 10 MB)",
     "} else if size + UInt64(data.count) > Self.rotateAt {", "} else if size > Self.rotateAt {"),
]
caught = 0
for name, old, new in MUTANTS:
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    src = os.path.join(OUT, "HostLog.swift")
    open(src, "w").write(orig.replace(old, new, 1))
    exe = os.path.join(OUT, "mutant")
    if os.path.exists(exe): os.remove(exe)
    c = subprocess.run(["swiftc", "-O", "-package-name", "sill", src, os.path.join(SP, "main.swift"), "-o", exe], capture_output=True, text=True)
    if c.returncode != 0:
        errors = [l for l in c.stderr.splitlines() if "error:" in l]
        print(f"{name}: did not compile: {errors[0] if errors else ''}"); continue
    try:
        r = subprocess.run([exe], capture_output=True, text=True, timeout=300)
    except subprocess.TimeoutExpired:
        caught += 1
        print(f"{name}: caught (the check did not end in 300 s)"); continue
    failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
    if r.returncode != 0:
        caught += 1
        print(f"{name}: caught ({len(failed)} FAIL lines; first: {failed[0][:170] if failed else 'exit ' + str(r.returncode)})")
    else:
        print(f"{name}: SURVIVED")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
