"""Mutants of Sources/SillHost/FramePacing.swift: each changes it in one place, is compiled with the check by build.sh
and must make it fail. usage: mutants.py ROOT"""
import os, subprocess, sys, tempfile
ROOT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
F = os.path.join(ROOT, "Sources/SillHost/FramePacing.swift")
MUTANTS = [
    # The numbers.
    ("FP1 late after 2 s at home", "static let homeLate: TimeInterval = 1", "static let homeLate: TimeInterval = 2"),
    ("FP2 a delta dropped at four messages", "static let homeDeltaMessages = 2", "static let homeDeltaMessages = 3"),
    ("FP3 calm after 1 s", "static let homeCalmAfter: TimeInterval = 2", "static let homeCalmAfter: TimeInterval = 1"),
    ("FP4 idle at 32 KB", "static let idleBytes = 16 * 1024", "static let idleBytes = 32 * 1024"),
    ("FP5 the away budget 320 KB", "static let remoteBacklogBudget = 256 * 1024", "static let remoteBacklogBudget = 320 * 1024"),
    ("FP6 the away slack 96 KB", "static let remoteBacklogSlack = 128 * 1024", "static let remoteBacklogSlack = 96 * 1024"),
    ("FP7 the hold cap 640 KB", "static let remoteHoldCap = 512 * 1024", "static let remoteHoldCap = 640 * 1024"),
    ("FP8 requests 1 s apart", "static let keyframeSpacing: TimeInterval = 2", "static let keyframeSpacing: TimeInterval = 1"),
    ("FP9 beside, 2 s", "static let keyframeSpacingBeside: TimeInterval = 4", "static let keyframeSpacingBeside: TimeInterval = 2"),
    ("FP10 not draining after 6 s at home", "static let deadAfter: TimeInterval = 4", "static let deadAfter: TimeInterval = 6"),
    ("FP11 a 4 s grace at home", "static let graceAfterConnect: TimeInterval = 8", "static let graceAfterConnect: TimeInterval = 4"),
    ("FP12 not draining after 10 s away", "static let remoteDeadAfter: TimeInterval = 15", "static let remoteDeadAfter: TimeInterval = 10"),
    ("FP13 an 8 s grace away", "static let remoteGrace: TimeInterval = 15", "static let remoteGrace: TimeInterval = 8"),
    ("FP14 the ceiling 128 MiB", "static let ceilingBytes = 64 << 20", "static let ceilingBytes = 128 << 20"),
    ("FP15 the home wait ceiling 20 s", "static let ceilingWait: TimeInterval = 10", "static let ceilingWait: TimeInterval = 20"),
    ("FP16 the away wait ceiling 60 s", "static let remoteCeilingWait: TimeInterval = 30", "static let remoteCeilingWait: TimeInterval = 60"),
    # At home.
    ("FP17 late at exactly homeLate", "let late = q.oldestFrameWait > homeLate", "let late = q.oldestFrameWait >= homeLate"),
    ("FP18 the keyframe it waits for goes however late", "if s.awaitingFirstKeyframe || !late {", "if true {"),
    ("FP19 its first keyframe waits while late", "if s.awaitingFirstKeyframe || !late {", "if !late {"),
    ("FP20 a late keyframe withheld but not wanted again",
     "                s.lastLossAt = now\n                s.keyframeWanted = true\n                return Outcome(verdict: .waiting, withheld: true)",
     "                s.lastLossAt = now\n                return Outcome(verdict: .waiting, withheld: true)"),
    ("FP21 a wait not a loss", "            if counted { s.lastLossAt = now }\n", ""),
    ("FP22 a request while it waits for its first", "if s.keyframeWanted, !s.awaitingFirstKeyframe, q.bytes <= idleBytes, due() {",
     "if s.keyframeWanted, q.bytes <= idleBytes, due() {"),
    ("FP23 a request before the queue drains", "if s.keyframeWanted, !s.awaitingFirstKeyframe, q.bytes <= idleBytes, due() {",
     "if s.keyframeWanted, !s.awaitingFirstKeyframe, due() {"),
    ("FP24 a request before one is due", "if s.keyframeWanted, !s.awaitingFirstKeyframe, q.bytes <= idleBytes, due() {",
     "if s.keyframeWanted, !s.awaitingFirstKeyframe, q.bytes <= idleBytes {"),
    ("FP25 a late frame queued anyway", "guard late || (!keyframe && q.messages > homeDeltaMessages) else",
     "guard (!keyframe && q.messages > homeDeltaMessages) else"),
    ("FP26 a keyframe dropped by the count", "guard late || (!keyframe && q.messages > homeDeltaMessages) else",
     "guard late || q.messages > homeDeltaMessages else"),
    ("FP27 a late loss asks at once", "let oneOff = !late && calm(s, now: now)", "let oneOff = calm(s, now: now)"),
    ("FP28 every loss asks at once, as before", "let oneOff = !late && calm(s, now: now)", "let oneOff = !late"),
    ("FP29 a lagging loss wants nothing", "s.keyframeWanted = !oneOff", "s.keyframeWanted = false"),
    ("FP30 calm only after more than 2 s", "s.lastLossAt.map { now - $0 >= homeCalmAfter } ?? true", "s.lastLossAt.map { now - $0 > homeCalmAfter } ?? true"),
    ("FP31 a drop's time not kept", "        s.needsKeyframe = true\n        s.lastLossAt = now\n        s.keyframeWanted = !oneOff",
     "        s.needsKeyframe = true\n        s.keyframeWanted = !oneOff"),
    ("FP32 the wait for the first counted", "let counted = !s.awaitingFirstKeyframe", "let counted = true"),
    # Away.
    ("FP33 the floor not followed down", "        s.backlogFloor = min(s.backlogFloor, q.bytes)\n", ""),
    ("FP34 away, a request before the queue drains", "if s.keyframeWanted, q.bytes <= idleBytes, due() {", "if s.keyframeWanted, due() {"),
    ("FP35 away, the first keyframe waits for the budget", "guard s.awaitingFirstKeyframe || q.bytes <= remoteBacklogBudget, parameterSets else {",
     "guard q.bytes <= remoteBacklogBudget, parameterSets else {"),
    ("FP36 the hold cap counts the keyframes", "let tooMuch = q.keyframesTaking > 0 ? q.bytes - q.keyframeBytesTaking > remoteHoldCap",
     "let tooMuch = q.keyframesTaking > 0 ? q.bytes > remoteHoldCap"),
    ("FP37 no floor, no slack", ": q.bytes > max(remoteBacklogBudget, s.backlogFloor + remoteBacklogSlack)", ": q.bytes > remoteBacklogBudget"),
    ("FP38 away, the wait for the first counted", "return Outcome(verdict: .waiting, withheld: !s.awaitingFirstKeyframe, ask: ask)",
     "return Outcome(verdict: .waiting, withheld: true, ask: ask)"),
    # The spacing and the sweep.
    ("FP39 beside, the last keyframe ignored", "return now - lastRequest >= keyframeSpacingBeside && now - lastKeyframeAt >= keyframeSpacingBeside",
     "return now - lastRequest >= keyframeSpacingBeside"),
    ("FP40 beside ignored", "guard beside else { return now - lastRequest >= keyframeSpacing }", "guard false else { return now - lastRequest >= keyframeSpacing }"),
    ("FP41 the sweep asks while it waits for its first", "s.needsKeyframe && s.keyframeWanted && !s.awaitingFirstKeyframe && q.bytes <= idleBytes",
     "s.needsKeyframe && s.keyframeWanted && q.bytes <= idleBytes"),
    # Too far behind.
    ("FP42 the byte ceiling only after the grace",
     "        if q.bytes > ceilingBytes { return .tooFarBehind(bytes: q.bytes, wait: q.oldestFrameWait) }\n        guard connectedFor > (away ? remoteGrace : graceAfterConnect) else { return nil }\n",
     "        guard connectedFor > (away ? remoteGrace : graceAfterConnect) else { return nil }\n        if q.bytes > ceilingBytes { return .tooFarBehind(bytes: q.bytes, wait: q.oldestFrameWait) }\n"),
    ("FP43 the grace ends at its last instant", "guard connectedFor > (away ? remoteGrace : graceAfterConnect) else", "guard connectedFor >= (away ? remoteGrace : graceAfterConnect) else"),
    ("FP44 not draining at exactly the backstop", "quiet > (away ? remoteDeadAfter : deadAfter)", "quiet >= (away ? remoteDeadAfter : deadAfter)"),
    ("FP45 no wait ceiling", "        if q.oldestFrameWait > (away ? remoteCeilingWait : ceilingWait) { return .tooFarBehind(bytes: q.bytes, wait: q.oldestFrameWait) }\n", ""),
    ("FP46 away's wait ceiling at home", "(away ? remoteCeilingWait : ceilingWait)", "(remoteCeilingWait)"),
    ("FP47 the old line reworded", "return \"Client not draining for \\(seconds) s, dropping: \\(endpoint)\"",
     "return \"Client not draining (\\(seconds) s), dropping: \\(endpoint)\""),
    ("FP48 megabytes as MiB", "let tenths = Int((Double(n) / 100_000).rounded())", "let tenths = Int((Double(n) / 104_857.6).rounded())"),
    # FrameTimes.
    ("FP49 the newest frame's wait", "head < times.count ? max(0, now - times[head]) : 0", "head < times.count ? max(0, now - times[times.count - 1]) : 0"),
    ("FP50 a compaction that keeps one", "                times.removeFirst(head)\n", "                times.removeFirst(head - 1)\n"),
    ("FP51 a take past the last", "            guard head < times.count else { return }\n", ""),
]
caught = 0
for name, old, new in MUTANTS:
    src = open(F).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        mf = os.path.join(t, "FramePacing.swift"); open(mf, "w").write(src.replace(old, new, 1))
        exe = os.path.join(t, "c")
        subprocess.run([os.path.join(HERE, "build.sh"), ROOT, exe, mf], capture_output=True, text=True)
        if not os.path.exists(exe): print(f"{name}: did not compile"); continue
        try:
            r = subprocess.run([exe], capture_output=True, text=True, timeout=300)
            status, out = r.returncode, r.stdout
        except subprocess.TimeoutExpired:
            status, out = -1, "FAIL timed out after 300 s"
        failed = [l for l in out.splitlines() if l.startswith("FAIL")]
        if status != 0:
            caught += 1
            print(f"{name}: caught ({failed[0][:110] if failed else f'exit status {status}'})")
        else:
            print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
