"""Mutants of Sources/SillHost/LinkJudge.swift (docs/remote-bundle-plan.md H10): each changes it in one
place, is compiled with the check by build.sh and must make it fail. usage: mutants.py ROOT
(The plan's "the first-keyframe wait counted" is StreamServer's rule, not the judge's: the pacing
harness's slowkfB case catches it, H11.)"""
import os, subprocess, sys, tempfile
ROOT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
F = os.path.join(ROOT, "Sources/SillHost/LinkJudge.swift")
MUTANTS = [
    ("LJ1 behind at 2 short of 5", "static let window = 5, shortToBehind = 3,", "static let window = 5, shortToBehind = 2,"),
    ("LJ2 fine after 4 clean", "cleanToFine = 5, stallSeconds = 3", "cleanToFine = 4, stallSeconds = 3"),
    ("LJ3 still seconds as short", "s.withheld >= 3 && 10 * s.withheld >= s.sent + s.withheld", "(s.withheld >= 3 || s.sent == 0) && 10 * s.withheld >= s.sent + s.withheld"),
    ("LJ4 > for >=", "s.withheld >= 3 && 10 * s.withheld >= s.sent + s.withheld", "s.withheld >= 3 && 10 * s.withheld > s.sent + s.withheld"),
    ("LJ5 0.8 for 0.7", "static let headroom = 0.7", "static let headroom = 0.8"),
    ("LJ6 fps ignored", "pick = lower.last { Double($0) * Double(max(fps, 1)) / 60 <= budget } ?? lower[0]", "pick = lower.last { Double($0) <= budget } ?? lower[0]"),
    ("LJ7 Standard never suggested", "return (pick, pick == QualityPreset.low.rawValue && retina ? 1 : nil)", "return (pick, nil)"),
    ("LJ8 stalled without the silence", "let dead = s.taken == 0 && s.waiting > 0 && !s.heard", "let dead = s.taken == 0 && s.waiting > 0"),
    ("LJ9 the median for the mean", "let mean = Double(measured.reduce(0) { $0 + $1.taken }) / Double(measured.count)", "let mean = Double(measured.map(\\.taken).sorted()[measured.count / 2])"),
    ("LJ10 a stall ends only when bytes are taken", "            if !dead { state = shorts >= Self.shortToBehind ? .behind : .fine }", "            if s.taken > 0 { state = shorts >= Self.shortToBehind ? .behind : .fine }"),
    ("LJ11 stalled after 2 s", "cleanToFine = 5, stallSeconds = 3", "cleanToFine = 5, stallSeconds = 2"),
    ("LJ12 the carried rate from 2 seconds", "static let measureWaiting = 16 * 1024, measureNeeded = 3", "static let measureWaiting = 16 * 1024, measureNeeded = 2"),
    ("LJ13 a second with exactly 16 KB waiting not measured", "recent.filter { $0.waiting >= Self.measureWaiting }", "recent.filter { $0.waiting > Self.measureWaiting }"),
    ("LJ14 a reset not marked", "Verdict(state: .fine, withheld: 0, offered: 0, carriedKbps: nil, waiting: 0, reset: true)", "Verdict(state: .fine, withheld: 0, offered: 0, carriedKbps: nil, waiting: 0, reset: false)"),
    ("LJ15 no report when the rate is first measured", "        if let now = carried, reportedCarried.map({ Double(abs(now - $0)) >= Self.carriedMove * Double($0) }) ?? true {\n            reportedCarried = now\n            return verdict\n        }\n", ""),
    ("LJ16 a stall always ends behind", "            if !dead { state = shorts >= Self.shortToBehind ? .behind : .fine }", "            if !dead { state = .behind }"),
    ("LJ17 a suggestion at the running bitrate", ".filter { $0 < bitrate }.sorted()", ".filter { $0 <= bitrate }.sorted()"),
    ("LJ18 nothing below Low from Retina either", "guard let oneDown = lower.last else { return retina ? (bitrate, 1) : nil }", "guard let oneDown = lower.last else { return nil }"),
    ("LJ19 the window never trimmed", "        if recent.count > Self.window { recent.removeFirst(recent.count - Self.window) }\n", ""),
    ("LJ20 a report every second of a spell", "reportedCarried.map({ Double(abs(now - $0)) >= Self.carriedMove * Double($0) }) ?? true", "true"),
    ("LJ21 a rate reported once a spell, never as it moves", "reportedCarried.map({ Double(abs(now - $0)) >= Self.carriedMove * Double($0) }) ?? true", "reportedCarried.map({ _ in false }) ?? true"),
    ("LJ22 a rate reported at any move", "static let carriedMove = 0.25", "static let carriedMove = 0.05"),
    # A restart's judgement (the review of 2026-09-27): judged afresh only at another quality, or none.
    ("LJ23 every restart judged afresh", "static func judgedAfresh(from old: Quality?, to new: Quality?) -> Bool {\n        new != old", "static func judgedAfresh(from old: Quality?, to new: Quality?) -> Bool {\n        true"),
    ("LJ24 only the bitrate compared", "static func judgedAfresh(from old: Quality?, to new: Quality?) -> Bool {\n        new != old", "static func judgedAfresh(from old: Quality?, to new: Quality?) -> Bool {\n        new?.bitrate != old?.bitrate"),
    ("LJ25 a stop keeps the judgement", "static func judgedAfresh(from old: Quality?, to new: Quality?) -> Bool {\n        new != old", "static func judgedAfresh(from old: Quality?, to new: Quality?) -> Bool {\n        new != nil && new != old"),
    ("LJ26 the resolution ignored", "static func judgedAfresh(from old: Quality?, to new: Quality?) -> Bool {\n        new != old", "static func judgedAfresh(from old: Quality?, to new: Quality?) -> Bool {\n        new?.bitrate != old?.bitrate || new?.fps != old?.fps"),
]
caught = 0
for name, old, new in MUTANTS:
    src = open(F).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        mf = os.path.join(t, "LinkJudge.swift"); open(mf, "w").write(src.replace(old, new, 1))
        exe = os.path.join(t, "c")
        subprocess.run([os.path.join(HERE, "build.sh"), ROOT, exe, mf], capture_output=True, text=True)
        if not os.path.exists(exe): print(f"{name}: did not compile"); continue
        r = subprocess.run([exe], capture_output=True, text=True, timeout=300)
        failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        if r.returncode != 0:
            caught += 1
            print(f"{name}: caught ({failed[0][:100] if failed else f'exit status {r.returncode}'})")
        else:
            print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
