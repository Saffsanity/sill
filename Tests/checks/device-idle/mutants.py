"""Mutants of DeviceIdlePolicy.swift (iOSClient, PR #230): each changes it in one place and must make the
check (main.swift) fail. usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "device-idle")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/DeviceIdlePolicy.swift")
orig = open(SRC).read()
GUARD = "guard w.foregroundActive, w.streaming, let used = w.lastUsedAt else { return nil }"
MUTANTS = [
    ("M1 a window in the background holds", GUARD, "guard w.streaming, let used = w.lastUsedAt else { return nil }"),
    ("M2 a window that does not stream holds", GUARD, "guard w.foregroundActive, let used = w.lastUsedAt else { return nil }"),
    ("M3 no limit: held for as long as it streams", "return used + limit", "return .infinity"),
    ("M4 the limit 5 minutes", "static let idleLimit: Double = 600", "static let idleLimit: Double = 300"),
    ("M5 held at exactly the limit", "guard let end = ends.max(), end > now else { return nil }", "guard let end = ends.max(), end >= now else { return nil }"),
    ("M6 the earliest end, not the latest", "guard let end = ends.max(), end > now else { return nil }", "guard let end = ends.min(), end > now else { return nil }"),
    ("M7 an end in the past still held", "guard let end = ends.max(), end > now else { return nil }", "guard let end = ends.max() else { return nil }"),
    ("M8 the limit given for one run ignored", "return used + limit", "return used + idleLimit"),
    ("M9 a window never used holds from now", GUARD, "guard w.foregroundActive, w.streaming else { return nil }; let used = w.lastUsedAt ?? .infinity"),
]
caught = 0
for name, old, new in MUTANTS:
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    src = os.path.join(OUT, "DeviceIdlePolicy.swift")
    open(src, "w").write(orig.replace(old, new, 1))
    exe = os.path.join(OUT, "mutant")
    if os.path.exists(exe): os.remove(exe)
    c = subprocess.run(["swiftc", "-O", src, os.path.join(SP, "main.swift"), "-o", exe], capture_output=True, text=True)
    if c.returncode != 0:
        print(f"{name}: did not compile: {c.stderr.strip().splitlines()[0] if c.stderr.strip() else ''}"); continue
    r = subprocess.run([exe], capture_output=True, text=True, timeout=600)
    failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
    if r.returncode != 0:
        caught += 1
        print(f"{name}: caught ({len(failed)} FAIL lines; first: {failed[0][:160] if failed else ''})")
    else:
        print(f"{name}: SURVIVED")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
