#!/usr/bin/env python3
# Each mutant changes Sources/SillHost/EncoderSlowState.swift in one place (in a copy under
# .build/encoder-check/mutants-slowstate/, never the file itself); the slow-state check (main.swift
# here) must fail on every one. Encoder-free: the check links no VideoToolbox.
# usage: Scripts/encoder-check/slowstate/mutants.py [path to EncoderSlowState.swift]
import subprocess, sys, os
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.abspath(os.path.join(here, '..', '..', '..'))
src_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(root, 'Sources', 'SillHost', 'EncoderSlowState.swift')
out = os.path.join(root, '.build', 'encoder-check', 'mutants-slowstate')
src = open(src_path).read()
mutants = [
    ("input counted in the window's last second only",
     "guard recent >= Self.minInputFPS, captures.count - recent >= Self.minInputFPS,", "guard recent >= Self.minInputFPS,"),
    ("input counted in the window's first second only",
     "guard recent >= Self.minInputFPS, captures.count - recent >= Self.minInputFPS,", "guard captures.count - recent >= Self.minInputFPS,"),
    ("a median of exactly 25 ms not slow",
     "guard median >= Self.slowTurnaround else { return nil }", "guard median > Self.slowTurnaround else { return nil }"),
    ("no median: the frame just back decides",
     "guard median >= Self.slowTurnaround else { return nil }", "guard median >= 0 else { return nil }"),
    ("the decision on any frame back, fast or slow",
     "guard !gaveUp, ranFast, turnaround >= Self.slowTurnaround,", "guard !gaveUp, ranFast,"),
    ("a session that never ran fast replaced",
     "guard !gaveUp, ranFast, turnaround >= Self.slowTurnaround,", "guard !gaveUp, turnaround >= Self.slowTurnaround,"),
    ("no giving up after a new session no faster",
     "if report.noFaster { gaveUp = true }", ""),
    ("a stream that gave up replaced again",
     "guard !gaveUp, ranFast, turnaround >= Self.slowTurnaround,", "guard ranFast, turnaround >= Self.slowTurnaround,"),
    ("no spacing between new sessions",
     "now - watchingSince >= Self.window, now - lastAttempt >= Self.minSpacing else { return nil }", "now - watchingSince >= Self.window else { return nil }"),
    ("no evidence window: decided as soon as the stream starts",
     "now - watchingSince >= Self.window, now - lastAttempt >= Self.minSpacing else { return nil }", "now - lastAttempt >= Self.minSpacing else { return nil }"),
    ("too few frames back decide",
     "returns.count >= Self.minReturns else { return nil }", "returns.count >= 1 else { return nil }"),
    ("old captures kept",
     "if let k = captures.firstIndex(where: { $0 > edge }) { captures.removeFirst(k) } else { captures.removeAll(keepingCapacity: true) }", ""),
    ("old frames back kept",
     "if let k = returns.firstIndex(where: { $0.at > edge }) { returns.removeFirst(k) } else { returns.removeAll(keepingCapacity: true) }", ""),
    ("judged on 29 frames after the keyframe",
     "guard j.turnarounds.count >= Self.judgeFrames || now - j.swapAt >= Self.judgeWithin else {", "guard j.turnarounds.count >= Self.judgeFrames - 1 || now - j.swapAt >= Self.judgeWithin else {"),
    ("never judged by time",
     "guard j.turnarounds.count >= Self.judgeFrames || now - j.swapAt >= Self.judgeWithin else {", "guard j.turnarounds.count >= Self.judgeFrames else {"),
    ("a verdict on too few frames",
     "turnaround: j.turnarounds.count >= Self.minJudged ? Self.median(j.turnarounds) : nil,", "turnaround: Self.median(j.turnarounds),"),
    ("the gap timed from the swap",
     "phase = .judging(Judging(slow: slow, swapAt: now, lastOldReturn: lastReturnAt))", "phase = .judging(Judging(slow: slow, swapAt: now, lastOldReturn: now))"),
    ("ranFast kept across a swap",
     "        lastAttempt = now\n        ranFast = false\n", "        lastAttempt = now\n"),
    ("a failed new session retried at once",
     "        phase = .watching\n        lastAttempt = now\n    }", "        phase = .watching\n    }"),
    ("a swap while watching taken",
     "        guard case .making(let slow) = phase else { return }", "        let slow = Slow(turnaround: 0, inputFPS: 0, outputFPS: 0)"),
]
ok = True
caught = 0
for i, (name, old, new) in enumerate(mutants, 1):
    if src.count(old) != 1:
        print(f"M{i:02} BAD      {name}: the text to change is found {src.count(old)} times"); ok = False; continue
    d = os.path.join(out, f"m{i:02}"); os.makedirs(d, exist_ok=True)
    open(os.path.join(d, "EncoderSlowState.swift"), "w").write(src.replace(old, new))
    b = subprocess.run(["swiftc", "-O", os.path.join(d, "EncoderSlowState.swift"), os.path.join(here, "main.swift"), "-o", os.path.join(d, "check")],
                       capture_output=True, text=True)
    if b.returncode != 0:
        print(f"M{i:02} NOBUILD  {name}: {b.stderr.strip().splitlines()[0] if b.stderr.strip() else '?'}"); ok = False; continue
    r = subprocess.run([os.path.join(d, "check")], capture_output=True, text=True, timeout=120)
    fails = [l for l in r.stdout.splitlines() if "FAIL" in l]
    if r.returncode != 0:
        caught += 1
        print(f"M{i:02} CAUGHT   {name}: {len(fails) - 1} failures, first: {fails[0].strip() if fails else '?'}")
    else:
        ok = False
        print(f"M{i:02} MISSED   {name}")
print(f"{caught} of {len(mutants)} mutants caught")
sys.exit(0 if ok and caught == len(mutants) else 1)
