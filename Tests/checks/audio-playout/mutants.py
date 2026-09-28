"""H3 (docs/audio-plan.md §7.2, §11): each mutant changes iOSClient/AudioPlayout.swift in one place and must
fail the check (main.swift, with 1,000 random runs, which catch what the scenarios do not). The plan's
list first (the floor, the dedupe, the guard, the late test, the jump, the steps, the fades, the need
rising at once, the output latency in the need, the IO buffer in the late test, a segment's priming, a
packet after a gap, a hand-over's dedupe, a duplicate counted), then the rest of the rules.
usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "audio-playout")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/AudioPlayout.swift")
orig = open(SRC).read()
MUTANTS = {
    # The plan's.
    "M1 the floor the largest, not the smallest": (
        "var floor: Double? { buckets.isEmpty ? floorKept : buckets.map(\\.min).min() }",
        "var floor: Double? { buckets.isEmpty ? floorKept : buckets.map(\\.min).max() }"),
    "M2 no dedupe": ("        if recentSet.contains(key) {", "        if false {"),
    "M3 no guard": ("        return max(need(now: now), guardDelay)", "        return need(now: now)"),
    "M4 the late test's sign": ("            if time(ofSample: start) - now < ioBuffer + Self.margin {",
                                "            if time(ofSample: start) - now > ioBuffer + Self.margin {"),
    "M5 the jump at 400 ms": ("    static let jumpOver = 0.040", "    static let jumpOver = 0.400"),
    "M6 no step below": ("            if raw < floor - Self.stepBelow {", "            if false {"),
    "M7 no step above": ("            if raw - floor > max(Self.stepAbove, 2 * (rttMedian ?? 0)) {", "            if false {"),
    "M8 no fades": ("        guard n > 0 else { return }\n        for i in 0..<n {", "        guard n < 0 else { return }\n        for i in 0..<n {"),
    "M9 the need not rising at once (the cover waits for its second to end)": (
        "              let top = buckets.compactMap(\\.max).max() else { return start }",
        "              let top = buckets.dropLast().compactMap(\\.max).max() else { return start }"),
    "M10 the output latency left out of the need": (
        "cover(now: now) + Double(framesPerPacket) / Self.rate + ioBuffer + outputLatency + Self.margin",
        "cover(now: now) + Double(framesPerPacket) / Self.rate + ioBuffer + Self.margin"),
    "M11 the late test without the IO buffer": ("            if time(ofSample: start) - now < ioBuffer + Self.margin {",
                                                "            if time(ofSample: start) - now < Self.margin {"),
    "M12 a segment's first packet placed without its priming": (
        "stamp: stamp + Double(drop) / Self.rate, frames: kept,", "stamp: stamp, frames: kept,"),
    "M13 the packet after a seq gap played": ("        let continuous = !segmentStart && expectedSeq == seq",
                                              "        let continuous = !segmentStart"),
    "M14 a hand-over's format resetting the dedupe": (
        "           self.primingFrames == primingFrames { return false }",
        "           self.primingFrames == primingFrames { recentSet = []; recentKeys = []; recentNext = 0; return false }"),
    "M15 a duplicate counted before it is dropped": (
        "        let key = Int64(epoch & 0xFFFF) << 32 | Int64(seq)\n",
        "        record(raw: arrival - stamp, arrival: arrival)\n        let key = Int64(epoch & 0xFFFF) << 32 | Int64(seq)\n"),
    # The rest.
    "M16 the tail not faded when the next does not follow": (
        "        if let h = hand { out.schedules.append(h.tail(fadeOut: !p.contiguous,",
        "        if let h = hand { out.schedules.append(h.tail(fadeOut: false,"),
    "M17 no jump for a large error": ("            if ear >= picture, abs(decision.error) <= Self.jumpOver {",
                                      "            if ear >= picture {"),
    "M18 frames the wrong way": ("        } else if error > Self.correctFrom {\n            correcting = 1",
                                 "        } else if error > Self.correctFrom {\n            correcting = -1"),
    "M19 two frames a packet": ("? correction(decision.error) : 0", "? 2 * correction(decision.error) : 0"),
    "M20 the session's first 2 s counted in the cover": (
        "        guard let begun = sessionStart, arrival - begun >= Self.coverGrace else { return nil }",
        "        guard let begun = sessionStart, arrival - begun >= 0 else { return nil }"),
    "M21 the cover's start at home 20 ms": ("    static let coverStartHome = 0.040", "    static let coverStartHome = 0.020"),
    "M22 home's bounds away": ("        let bounds = away ? Self.coverAway : Self.coverHome", "        let bounds = Self.coverHome"),
    "M23 the tail's deadline without the IO buffer": ("        return time(ofSample: h.tailStart) - ioBuffer - Self.margin",
                                                      "        return time(ofSample: h.tailStart) - Self.margin"),
    "M24 the picture's lag without its refreshes": (
        "$0 - floor + Self.pictureRefreshes * refresh + Self.pictureExtra", "$0 - floor + Self.pictureExtra"),
    "M25 the frames' mean for their median": ("            raw = Self.median(sortedRaws)",
                                              "            raw = sortedRaws.reduce(0, +) / Double(sortedRaws.count)"),
    "M26 what waited for the engine never placed": ("        for a in list { out.add(place(a, now: now)) }",
                                                    "        for a in list { out.discards.append(a.id) }"),
    "M27 the step's threshold without the rtt": ("            if raw - floor > max(Self.stepAbove, 2 * (rttMedian ?? 0)) {",
                                                 "            if raw - floor > Self.stepAbove {"),
    "M28 a new segment decoded on the old state": ("            // Rule 9: a clean start.\n            plan.resetFirst = true",
                                                   "            // Rule 9: a clean start.\n            plan.resetFirst = false"),
    "M29 a join decoded without a reset": ("            plan.resetFirst = true\n            plan.dropFront = framesPerPacket",
                                           "            plan.resetFirst = false\n            plan.dropFront = framesPerPacket"),
    "M30 the floor's window 1 s": ("    static let floorSeconds = 10", "    static let floorSeconds = 1"),
    "M31 no body: the whole packet held": ("            guard bodyCount > 0 else { return nil }", "            guard bodyCount < 0 else { return nil }"),
    "M32 the hand's deadline from the packet's start (no headroom)": (
        "        return time(ofSample: h.tailStart) - ioBuffer - Self.margin",
        "        return time(ofSample: h.start) - ioBuffer - Self.margin"),
    "M33 the picture's window kept at a step": ("        above = nil\n        frameArrivals = []\n        frameRaws = []\n        frameHead = 0\n        sortedRaws = []\n        lastPictureRaw = nil\n        owe()",
                                                "        above = nil\n        owe()"),
    "M34 a jump drops even within half a packet": ("                if jumpOwed, chain - start > Double(framesPerPacket) / 2 {",
                                                   "                if jumpOwed {"),
    "M35 a jump owed forgotten after a late packet": (
        "            jumpOwed = false\n            correcting = 0\n            let ear = time(ofSample: start) + outputLatency",
        "            correcting = 0\n            let ear = time(ofSample: start) + outputLatency"),
    "M36 a step's second without a count": ("                if arrival - run.since >= 1, run.count >= Self.stepPackets {",
                                            "                if arrival - run.since >= 0.2 {"),
}
caught = 0
for name, (old, new) in MUTANTS.items():
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    path = os.path.join(OUT, "mutant.swift")
    open(path, "w").write(orig.replace(old, new))
    b = subprocess.run(["swiftc", "-O", path, os.path.join(SP, "main.swift"), "-o", os.path.join(OUT, "mutant")],
                       capture_output=True, text=True)
    if b.returncode != 0:
        print(f"{name}: DOES NOT COMPILE\n{b.stderr[:600]}"); continue
    try:
        r = subprocess.run([os.path.join(OUT, "mutant"), "1000"], capture_output=True, text=True, timeout=600)
        out, code = r.stdout, r.returncode
    except subprocess.TimeoutExpired:
        out, code = "FAIL (timed out)", 1
    failed = [l[5:] for l in out.splitlines() if l.startswith("FAIL")]
    ok = code != 0
    caught += ok
    print(f"{'caught' if ok else 'MISSED'} {name}: {len(failed)} failing, e.g. {[f[:110] for f in failed[:2]]}")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
