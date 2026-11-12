"""Mutants of DesktopDisplays.swift (Sources/StreamProtocol): each changes it in one place, is compiled with the
check (main.swift) and must make it fail. A mutant that does not compile is not counted as caught.
usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "desktop-displays")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "Sources/StreamProtocol/DesktopDisplays.swift")
orig = open(SRC).read()
CANDS = "        displays.filter { !$0.isSills }.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }\n"
CHOSEN = "        if let chosen, let d = candidates.first(where: { $0.uuid == chosen }) { return d }\n"
FALLBACK = "        return candidates.first { $0.id == fallback } ?? candidates.first\n"
FEW = "        guard candidates.count > 1 else { return nil }\n"
AT = "        guard let i = candidates.firstIndex(where: { $0.id == current }) else { return candidates[0] }\n"
STEP = "        return candidates[(i + 1) % candidates.count]\n"
SHOWN = "        guard let displays, displays > 1, let current, (1...displays).contains(current) else { return nil }\n"
TAP = "        desktopStreams && (displays ?? 0) > 1\n"
ON = "        if let pointer, frame.contains(pointer) { return nil }\n"
MUTANTS = [
    # The candidates
    ("D1 Sill's own display a candidate", CANDS, "        displays.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }\n"),
    ("D2 macOS's own order kept", CANDS, "        displays.filter { !$0.isSills }\n"),
    ("D3 top to bottom first", CANDS, "        displays.filter { !$0.isSills }.sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }\n"),
    ("D4 right to left", CANDS, "        displays.filter { !$0.isSills }.sorted { ($0.frame.minX, $0.frame.minY) > ($1.frame.minX, $1.frame.minY) }\n"),
    ("D5 by ID", CANDS, "        displays.filter { !$0.isSills }.sorted { $0.id < $1.id }\n"),
    # The display the Desktop streams
    ("D6 the choice by ID, not UUID", CHOSEN, "        if let chosen, let d = candidates.first(where: { String($0.id) == chosen }) { return d }\n"),
    ("D7 the choice ignored", CHOSEN, ""),
    ("D8 the fallback ignored", FALLBACK, "        return candidates.first\n"),
    ("D9 no first when the fallback is not a candidate", FALLBACK, "        return candidates.first { $0.id == fallback }\n"),
    # The next display
    ("D10 a next with one display", FEW, "        guard !candidates.isEmpty else { return nil }\n"),
    ("D11 no next with two", FEW, "        guard candidates.count > 2 else { return nil }\n"),
    ("D12 a display not listed: none", AT, "        guard let i = candidates.firstIndex(where: { $0.id == current }) else { return nil }\n"),
    ("D13 no wrap", STEP, "        return candidates[min(i + 1, candidates.count - 1)]\n"),
    ("D14 the same display again", STEP, "        return candidates[i]\n"),
    ("D15 backwards", STEP, "        return candidates[(i + candidates.count - 1) % candidates.count]\n"),
    # Its number
    ("D16 counting from 0", "        candidates.firstIndex { $0.id == current }.map { $0 + 1 }\n", "        candidates.firstIndex { $0.id == current }\n"),
    # After a step
    ("D30 a display that never streams kept", "        streamed ? stepped : previous\n", "        stepped\n"),
    ("D31 a display that streams dropped", "        streamed ? stepped : previous\n", "        previous\n"),
    # Where input lands
    ("D28 input lands on the first display, whatever streams", "        candidates.first { $0.id == id }?.frame\n", "        candidates.first?.frame\n"),
    ("D29 input never lands on the streamed display", "        candidates.first { $0.id == id }?.frame\n", "        nil\n"),
    # The device's button
    ("D17 a number with one display", SHOWN, "        guard let displays, displays > 0, let current, (1...displays).contains(current) else { return nil }\n"),
    ("D18 a number past the count", SHOWN, "        guard let displays, displays > 1, let current, current >= 1 else { return nil }\n"),
    ("D19 a number of 0", SHOWN, "        guard let displays, displays > 1, let current, current <= displays else { return nil }\n"),
    ("D20 the label without its number", "        return \"Desktop \\(n)\"\n", "        return \"Desktop\"\n"),
    ("D21 VoiceOver's value without the count", "        return \"Display \\(n) of \\(displays)\"\n", "        return \"Display \\(n)\"\n"),
    ("D22 a tap asks for the next whatever streams", TAP, "        (displays ?? 0) > 1\n"),
    ("D23 a tap asks for the next with one display", TAP, "        desktopStreams && (displays ?? 0) > 0\n"),
    ("D24 a tap never asks for the next", TAP, "        false\n"),
    # The pointer after a switch
    ("D25 the pointer always moved", ON, ""),
    ("D26 the pointer never moved", ON, "        return nil\n"),
    ("D27 the display's origin, not its centre", "        return CGPoint(x: frame.midX, y: frame.midY)\n", "        return frame.origin\n"),
]
caught = 0
for name, old, new in MUTANTS:
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    src = os.path.join(OUT, "DesktopDisplays.swift")
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
        print(f"{name}: caught ({failed[0][:110] if failed else f'exit {r.returncode}'})")
    else:
        print(f"{name}: NOT CAUGHT")
os.remove(os.path.join(OUT, "DesktopDisplays.swift"))
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
