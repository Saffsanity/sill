"""Mutants of KeyframeRecovery.swift (iOSClient): each changes it in one place, is compiled with the check
(main.swift) and must make it fail. usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "keyframe-recovery")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/KeyframeRecovery.swift")
orig = open(SRC).read()
GUARD = "        guard open, active, streaming else { return .nothing }"
OUTSTANDING = "        if asked {\n"
DUE = "            if let last = lastAsk, now >= last, now < last + wait { return .keyframeDue(last + wait) }"
UNANSWERED = "            asked = false\n            repeats += 1\n"
HELD = "        if let last = lastAsk, now >= last, now < last + spacingNow { return .askAt(last + spacingNow) }"
REPEAT = "        if !wentAway, let back = backAt, now >= back, now - back < Self.calm {"
STREAK = "            repeats += 1\n        } else {\n            repeats = 0\n        }"
AWAY = "        wentAway = true\n        asked = false\n        repeats = 0\n"
WAIT = "        max(shortestWait, 4 * Double(worstRttMs ?? 0) / 1000)"
MUTANTS = [
    ("K1 an ask out never waited for", DUE, "            if let last = lastAsk, false { return .keyframeDue(last + wait) }"),
    ("K2 an ask while Sill is not active", GUARD, "        guard open, streaming else { return .nothing }"),
    ("K3 an ask while nothing streams", GUARD, "        guard open, active else { return .nothing }"),
    ("K4 an ask with no interruption", GUARD, "        guard active, streaming else { return .nothing }"),
    ("K5 no spacing", HELD, "        if let last = lastAsk, false { return .askAt(last + spacingNow) }"),
    ("K6 the spacing off by its edge", HELD,
     "        if let last = lastAsk, now >= last, now <= last + spacingNow { return .askAt(last + spacingNow) }"),
    ("K7 the spacing's rounding (held again when it is due)", HELD,
     "        if let last = lastAsk, now >= last, now - last < spacingNow { return .askAt(last + spacingNow) }"),
    ("K8 a clock gone back holds the ask", HELD,
     "        if let last = lastAsk, now < last + spacingNow { return .askAt(last + spacingNow) }"),
    ("K9 a repeat held back by the base spacing only", HELD,
     "        if let last = lastAsk, now >= last, now < last + Self.spacing { return .askAt(last + Self.spacing) }"),
    ("K10 the ask not counted", "        asked = true\n        lastAsk = now\n", "        lastAsk = now\n"),
    ("K11 the ask's time not kept", "        asked = true\n        lastAsk = now\n", "        asked = true\n"),
    ("K12 a spacing of 1 s", "    static let spacing: TimeInterval = 2", "    static let spacing: TimeInterval = 1"),
    ("K13 no longer spacing for repeats", STREAK, "            repeats = 0\n        } else {\n            repeats = 0\n        }"),
    ("K14 no cap on the spacing",
     "    var spacingNow: TimeInterval { min(Self.spacing * pow(2, Double(repeats)), Self.longestSpacing) }",
     "    var spacingNow: TimeInterval { Self.spacing * pow(2, Double(repeats)) }"),
    ("K15 the cap at 16 s", "    static let longestSpacing: TimeInterval = 32", "    static let longestSpacing: TimeInterval = 16"),
    ("K16 calm by its edge", REPEAT, "        if !wentAway, let back = backAt, now >= back, now - back <= Self.calm {"),
    ("K17 never calm", REPEAT, "        if !wentAway, let back = backAt, now >= back {"),
    ("K18 a calm of 5 s", "    static let calm: TimeInterval = 10", "    static let calm: TimeInterval = 5"),
    ("K19 a trip away keeps the streak of the next interruption", REPEAT, "        if let back = backAt, now >= back, now - back < Self.calm {"),
    ("K20 the picture back in front keeps an old trip away", "        if active { wentAway = false }\n", ""),
    ("K21 a trip away marks nothing", AWAY, "        asked = false\n        repeats = 0\n"),
    ("K22 a trip away does not owe the ask again", AWAY, "        wentAway = true\n        repeats = 0\n"),
    ("K23 a stray keyframe moves when the picture came back",
     "    mutating func pictureBack(now: TimeInterval, active: Bool) {\n        guard open else { return }\n",
     "    mutating func pictureBack(now: TimeInterval, active: Bool) {\n"),
    ("K24 the layer read again opens a new interruption",
     "    mutating func interrupted(now: TimeInterval) {\n        guard !open else { return }\n",
     "    mutating func interrupted(now: TimeInterval) {\n"),
    ("K25 the picture back does not close it", "        guard open else { return }\n        open = false\n", "        guard open else { return }\n"),
    ("K26 a new interruption keeps the last one's ask", "        open = true\n        asked = false\n", "        open = true\n"),
    ("K27 a streak starts at one", STREAK, "            repeats += 1\n        } else {\n            repeats = 1\n        }"),
    ("K28 a picture back before the clock counts", REPEAT, "        if !wentAway, let back = backAt, now - back < Self.calm {"),
    # The verifier's findings on 09549b3, each put back:
    ("K29 an ask out is never asked again (09549b3: a keyframe lost, an older Mac)", OUTSTANDING,
     "        if asked { return .nothing }\n        if asked {\n"),
    ("K30 a trip away keeps the spacing (09549b3)", AWAY, "        wentAway = true\n        asked = false\n"),
    ("K31 the picture back while away ends the trip (09549b3)", "        if active { wentAway = false }\n",
     "        wentAway = false\n"),
    # The ask's wait:
    ("K32 an unanswered ask is no repeat", UNANSWERED, "            asked = false\n"),
    ("K33 an unanswered ask not owed again", UNANSWERED, "            repeats += 1\n"),
    ("K34 the wait off by its edge", DUE,
     "            if let last = lastAsk, now >= last, now <= last + wait { return .keyframeDue(last + wait) }"),
    ("K35 a clock gone back waits for the ask out", DUE,
     "            if let last = lastAsk, now < last + wait { return .keyframeDue(last + wait) }"),
    ("K36 the wait of the spacing, not of the link", DUE,
     "            if let last = lastAsk, now >= last, now < last + Self.spacing { return .keyframeDue(last + Self.spacing) }"),
    ("K37 the wait without its floor", WAIT, "        4 * Double(worstRttMs ?? 0) / 1000"),
    ("K38 the wait two round trips", WAIT, "        max(shortestWait, 2 * Double(worstRttMs ?? 0) / 1000)"),
    ("K39 the wait's floor at 2 s", "    static let shortestWait: TimeInterval = 4", "    static let shortestWait: TimeInterval = 2"),
]
caught = 0
for name, old, new in MUTANTS:
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    src = os.path.join(OUT, "KeyframeRecovery.swift")
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
