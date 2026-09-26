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
     "            guard Double(inputs(after: now - half, through: now)) >= need,\n                  Double(inputs(after: now - Self.window, through: now - half)) >= need,\n",
     "            guard Double(inputs(after: now - half, through: now)) >= need,\n"),
    ("input counted in the window's first second only",
     "            guard Double(inputs(after: now - half, through: now)) >= need,\n                  Double(inputs(after: now - Self.window, through: now - half)) >= need,\n",
     "            guard Double(inputs(after: now - Self.window, through: now - half)) >= need,\n"),
    ("input counted over the whole window against the half-window's need",
     "Double(inputs(after: now - half, through: now)) >= need,", "Double(inputs(after: now - Self.window, through: now)) >= need,"),
    ("a median of exactly 25 ms not slow",
     "guard median >= max(Self.slowTurnaround, Self.slowFactor * fastest) else { return nil }",
     "guard median > max(Self.slowTurnaround, Self.slowFactor * fastest) else { return nil }"),
    ("no median: the frame just back decides",
     "guard median >= max(Self.slowTurnaround, Self.slowFactor * fastest) else { return nil }", "guard median >= 0 else { return nil }"),
    ("no factor over the session's fastest frame (a fixed 25 ms)",
     "guard median >= max(Self.slowTurnaround, Self.slowFactor * fastest) else { return nil }",
     "guard median >= Self.slowTurnaround else { return nil }"),
    ("a factor of 2 over the session's fastest frame",
     "static let slowFactor = 1.5", "static let slowFactor = 2.0"),
    ("the decision on any frame back, fast or slow",
     "guard !gaveUp, fastest < Self.slowTurnaround, turnaround >= Self.slowTurnaround,", "guard !gaveUp, fastest < Self.slowTurnaround,"),
    ("a session that never ran fast replaced",
     "guard !gaveUp, fastest < Self.slowTurnaround, turnaround >= Self.slowTurnaround,", "guard !gaveUp, turnaround >= Self.slowTurnaround,"),
    ("no giving up after a new session no faster",
     "if report.noFaster { gaveUp = true }", ""),
    ("a stream that gave up replaced again",
     "guard !gaveUp, fastest < Self.slowTurnaround, turnaround >= Self.slowTurnaround,", "guard fastest < Self.slowTurnaround, turnaround >= Self.slowTurnaround,"),
    ("no faster by a fixed 25 ms, not against the session replaced",
     "turnaround.map { $0 >= EncoderSlowState.noFasterFraction * slow.turnaround } ?? false",
     "turnaround.map { $0 >= EncoderSlowState.slowTurnaround } ?? false"),
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
     "guard j.turnarounds.count >= Self.judgeFrames || j.motionEnded ||", "guard j.turnarounds.count >= Self.judgeFrames - 1 || j.motionEnded ||"),
    ("never judged by time",
     "guard j.turnarounds.count >= Self.judgeFrames || j.motionEnded || now - j.swapAt >= Self.judgeWithin else {",
     "guard j.turnarounds.count >= Self.judgeFrames || j.motionEnded else {"),
    ("a verdict on too few frames",
     "turnaround: j.turnarounds.count >= Self.minJudged ? Self.median(j.turnarounds) : nil,", "turnaround: j.turnarounds.isEmpty ? nil : Self.median(j.turnarounds),"),
    ("frames after the motion ended timed too",
     "if inMotion(handedOverAt: now - turnaround) { j.turnarounds.append(turnaround) } else { j.motionEnded = true }",
     "j.turnarounds.append(turnaround)"),
    ("frames without motion skipped, but the timing goes on",
     "if inMotion(handedOverAt: now - turnaround) { j.turnarounds.append(turnaround) } else { j.motionEnded = true }",
     "if inMotion(handedOverAt: now - turnaround) { j.turnarounds.append(turnaround) }"),
    ("the verdict waits for judgeWithin after the motion ended",
     "guard j.turnarounds.count >= Self.judgeFrames || j.motionEnded || now - j.swapAt >= Self.judgeWithin else {",
     "guard j.turnarounds.count >= Self.judgeFrames || now - j.swapAt >= Self.judgeWithin else {"),
    ("motion by the count alone (no gap test)",
     "guard let k = captures.lastIndex(where: { $0 <= h }), k > 0, captures[k] - captures[k - 1] < Self.motionGap else { return false }",
     "guard captures.contains(where: { $0 <= h }) else { return false }"),
    ("motion by the gap alone (no count)",
     "return inputs(after: h - 1, through: h) >= Self.minInputFPS", "return true"),
    ("the gap from the old session's last frame back",
     "phase = .judging(Judging(slow: slow, swapAt: now, lastOldReturn: lastReturnAt))", "phase = .judging(Judging(slow: slow, swapAt: now, lastOldReturn: now))"),
    ("the fastest frame kept across a swap",
     "        lastAttempt = now\n        fastest = .infinity\n", "        lastAttempt = now\n"),
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
