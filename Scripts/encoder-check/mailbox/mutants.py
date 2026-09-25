#!/usr/bin/env python3
# Each mutant changes Sources/SillHost/EncoderMailbox.swift in one place (in a copy under
# .build/encoder-check/mutants/, never the file itself); the mailbox check (main.swift here) must
# fail on every one. Encoder-free: the check links no VideoToolbox.
# usage: Scripts/encoder-check/mailbox/mutants.py [path to EncoderMailbox.swift]
import subprocess, sys, os
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.abspath(os.path.join(here, '..', '..', '..'))
src_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, 'Sources', 'SillHost', 'EncoderMailbox.swift')
out = os.path.join(root, '.build', 'encoder-check', 'mutants')
src = open(src_path).read()
mutants = [
    ("the limit asked for ignored (always one)",
     "self.limit = max(1, limit)", "self.limit = 1"),
    ("no floor under the limit",
     "self.limit = max(1, limit)", "self.limit = limit"),
    ("a second frame let in before the session let go of one",
     "if inside.count < places {", "if inside.count < limit {"),
    ("the session never counted as having let go of a frame",
     "        anyReturned = true\n", ""),
    ("watchdog on the newest frame inside",
     "var oldest: CFTimeInterval? { inside.values.min() }", "var oldest: CFTimeInterval? { inside.values.max() }"),
    ("decrement on the pending path (the waiting frame goes in without a place)",
     "return .next(frame, id: letIn(now: now))", "lastID += 1; return .next(frame, id: lastID)"),
    ("set not cleared (a frame back stays inside)",
     "guard inside.removeValue(forKey: id) != nil else { return .duplicate }", "guard inside[id] != nil else { return .duplicate }"),
    ("no duplicate guard (a second notice frees again)",
     "guard inside.removeValue(forKey: id) != nil else { return .duplicate }", "_ = inside.removeValue(forKey: id)"),
    ("late output forwarded after the watchdog",
     "guard !dead else { return .late }", ""),
    ("the older waiting frame kept (the newer one dropped)",
     "        waiting = frame\n", "        if waiting == nil { waiting = frame }\n"),
    ("a dead session drained at teardown",
     "return dead ? .stalled(since: oldest) : .drain", "return .drain"),
    ("timestamps not made monotonic",
     "if lastPTS.isValid, CMTimeCompare(pts, lastPTS) <= 0 {", "if false {"),
    ("keyframe request never cleared",
     "        let keyframe = keyframeRequested\n        keyframeRequested = false\n", "        let keyframe = keyframeRequested\n"),
    ("hand-over after death",
     "guard !dead else { return nil }", ""),
    ("admission after death",
     "guard !dead else { return .dropped }", ""),
    ("watchdog at twice hangAfter",
     "now - oldest > after", "now - oldest > after * 2"),
    ("giveUp keeps the waiting frame",
     "dead = true; waiting = nil", "dead = true"),
    ("the waiting frame never taken on a return",
     "guard let frame = waiting else { return .freed }", "guard let frame = waiting, false else { return .freed }"),
    ("clock not restarted at the hand-over",
     "if inside[id] != nil { inside[id] = now }", ""),
    ("the clock of a waiting frame taken from its return, not now",
     "        lastID += 1\n        inside[lastID] = now\n", "        lastID += 1\n        inside[lastID] = inside.values.min() ?? now\n"),
]
os.makedirs(out, exist_ok=True)
caught = 0
for i, (name, old, new) in enumerate(mutants, 1):
    n = src.count(old)
    if n != 1:
        print(f"M{i:02d} {name}: the text to change occurs {n} times; not applied"); continue
    d = os.path.join(out, f'm{i:02d}'); os.makedirs(d, exist_ok=True)
    open(os.path.join(d, 'EncoderMailbox.swift'), 'w').write(src.replace(old, new))
    c = subprocess.run(['swiftc', '-O', os.path.join(d, 'EncoderMailbox.swift'), os.path.join(here, 'main.swift'), '-o', os.path.join(d, 'check')],
                       capture_output=True, text=True)
    if c.returncode != 0:
        print(f"M{i:02d} {name}: does not compile: {c.stderr.strip().splitlines()[0] if c.stderr else ''}"); continue
    try:
        r = subprocess.run([os.path.join(d, 'check')], capture_output=True, text=True, timeout=120)
        stdout = r.stdout; code = r.returncode
    except subprocess.TimeoutExpired:
        stdout = 'timed out'; code = 124
    fails = [l.strip() for l in stdout.splitlines() if 'FAIL [' in l]
    if code != 0:
        caught += 1
        print(f"M{i:02d} CAUGHT   {name}: {len(fails)} failures, first: {fails[0][:150] if fails else stdout.splitlines()[-1]}")
    else:
        print(f"M{i:02d} SURVIVED {name}")
print(f"{caught} of {len(mutants)} mutants caught")
sys.exit(0 if caught == len(mutants) else 1)
