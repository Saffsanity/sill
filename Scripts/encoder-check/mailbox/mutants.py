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
    ("every frame let in (no mailbox: a second frame inside)",
     "if inside == nil { return .goesIn(id: letIn(now: now)) }", "return .goesIn(id: letIn(now: now))"),
    ("the waiting frame goes in without the place (a decrement on the pending path)",
     "return .next(frame, id: letIn(now: now))", "lastID += 1; return .next(frame, id: lastID)"),
    ("the place not freed (a frame back stays inside)",
     "        inside = nil\n", ""),
    ("no duplicate guard (a second notice frees again)",
     "guard inside?.id == id else { return .duplicate }", ""),
    ("late output forwarded after the watchdog",
     "guard !dead else { return .late }", ""),
    ("the older waiting frame kept (the newer one dropped)",
     "        waiting = frame\n", "        if waiting == nil { waiting = frame }\n"),
    ("the waiting frame never taken on a return",
     "guard let frame = waiting else { return .freed }", "guard let frame = waiting, false else { return .freed }"),
    ("a dead session drained at teardown",
     "guard dead else { return .drain }", "return .drain"),
    ("a frame that never went in reported stalled at teardown",
     "return inside.handed ? .stalled(since: inside.since) : .idle", "return .stalled(since: inside.since)"),
    ("a dead session with the frame inside torn down idle",
     "return inside.handed ? .stalled(since: inside.since) : .idle", "return .idle"),
    ("a live session with a frame on encodeQueue not drained",
     "guard dead else { return .drain }", "guard dead else { return inside.handed ? .drain : .idle }"),
    ("timestamps not made monotonic",
     "if lastPTS.isValid, CMTimeCompare(pts, lastPTS) <= 0 {", "if false {"),
    ("equal timestamps let through",
     "CMTimeCompare(pts, lastPTS) <= 0", "CMTimeCompare(pts, lastPTS) < 0"),
    ("keyframe request never cleared",
     "        let keyframe = keyframeRequested\n        keyframeRequested = false\n", "        let keyframe = keyframeRequested\n"),
    ("hand-over after death",
     "guard !dead else { return nil }", ""),
    ("admission after death",
     "guard !dead else { return .dropped }", ""),
    ("watchdog at twice hangAfter",
     "now - inside.since > after", "now - inside.since > after * 2"),
    ("the watchdog fires again on a dead session",
     "guard !dead, let inside, now - inside.since > after", "guard let inside, now - inside.since > after"),
    ("giveUp keeps the waiting frame",
     "dead = true; waiting = nil", "dead = true"),
    ("giveUp true for a frame still on encodeQueue",
     "return inside?.handed == true", "return inside != nil"),
    ("giveUp false with the frame inside",
     "return inside?.handed == true", "return false"),
    ("clock not restarted at the hand-over",
     "if inside?.id == id { inside = Inside(id: id, since: now, handed: true) }", "if inside?.id == id { inside?.handed = true }"),
    ("the hand-over never recorded",
     "if inside?.id == id { inside = Inside(id: id, since: now, handed: true) }", "if inside?.id == id { inside?.since = now }"),
    ("a frame let in counted as handed over at once",
     "inside = Inside(id: lastID, since: now, handed: false)", "inside = Inside(id: lastID, since: now, handed: true)"),
    ("a frame waiting in the mailbox not counted as on its way",
     "var frameOnItsWay: Bool { waiting != nil || inside?.handed == false }", "var frameOnItsWay: Bool { inside?.handed == false }"),
    ("a frame on encodeQueue not counted as on its way",
     "var frameOnItsWay: Bool { waiting != nil || inside?.handed == false }", "var frameOnItsWay: Bool { waiting != nil }"),
    ("a frame always taken to be on its way (a request never looked at again)",
     "var frameOnItsWay: Bool { waiting != nil || inside?.handed == false }", "var frameOnItsWay: Bool { true }"),
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
