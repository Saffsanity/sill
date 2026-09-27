"""H3 (docs/trackpad-gestures-plan.md §9.1): each mutant changes TrackpadGestures.swift in one place and must fail
the check (main.swift). usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "gestures")   # the mutants' sources and binaries
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/TrackpadGestures.swift")
orig = open(SRC).read()
GATE = "guard fingersDown.count >= 3, !travelled, !holding else"
ARM = "if !done, !cancelledEarly, let first = three.first, time - first.value.landedAt <= chordWindow {"
SILENCE = "        if !silent {\n            silent = true\n            output = .silenced\n        }\n"
TOGETHER = "let together = armedBy.allSatisfy { share(armedAt[$0]!, now[$0]!) >= swipeShare * along }\n                    && movers.values.allSatisfy { share($0.start, $0.now) > -swipeShare * along }"
MUTANTS = {
    "M1 the window's edge left out": (ARM, ARM.replace("<= chordWindow", "< chordWindow")),
    "M2 the travel's edge let through": ("if distance(point, finger.landed) >= chordTravel { travelled = true }",
                                         "if distance(point, finger.landed) > chordTravel { travelled = true }"),
    "M3 the swipe's distance edge left out": ("if travel >= swipeDistance || (travel >= flickDistance", "if travel > swipeDistance || (travel >= flickDistance"),
    "M4 no flick": ("if travel >= swipeDistance || (travel >= flickDistance && speed(to: end, at: time) >= flickSpeed) {", "if travel >= swipeDistance {"),
    "M5 the flick's distance edge left out": ("|| (travel >= flickDistance && speed", "|| (travel > flickDistance && speed"),
    "M6 the axis's edge left out": ("if major >= axisRatio * minor {", "if major > axisRatio * minor {"),
    "M7 the pinch's edge left out": ("if change <= 1 - pinchRatio { return (.pinch, fingers) }", "if change < 1 - pinchRatio { return (.pinch, fingers) }"),
    "M8 the spread's edge left out": ("if change >= 1 + pinchRatio { return (.spread, fingers) }", "if change > 1 + pinchRatio { return (.spread, fingers) }"),
    "M9 no window": (ARM, ARM.replace(", time - first.value.landedAt <= chordWindow", "")),
    "M10 no travel condition": (GATE, GATE.replace(" !travelled,", "")),
    "M11 no button condition": (GATE, GATE.replace(", !holding else", " else")),
    "M12 any finger's lift decides (the review's F3)": ("if armed, !done, armedBy.contains(id) {", "if armed, !done {"),
    "M13 left and right swapped": ("(dx < 0 ? .swipeLeft : .swipeRight)", "(dx < 0 ? .swipeRight : .swipeLeft)"),
    "M14 pinch and spread swapped": ("if change <= 1 - pinchRatio { return (.pinch, fingers) }\n        if change >= 1 + pinchRatio { return (.spread, fingers) }",
                                     "if change <= 1 - pinchRatio { return (.spread, fingers) }\n        if change >= 1 + pinchRatio { return (.pinch, fingers) }"),
    "M15 measured from where the fingers landed": ("for id in armedBy { armedAt[id] = fingersDown[id]!.now }", "for id in armedBy { armedAt[id] = fingersDown[id]!.landed }"),
    "M16 silence ends at the last lift": ("        fingersDown[id] = nil\n        return output", "        fingersDown[id] = nil\n        if fingersDown.isEmpty { silent = false }\n        return output"),
    "M17 a cancel ignored after arming": ("if armed { done = true } else { cancelledEarly = true }", "if !armed { cancelledEarly = true }"),
    "M18 a fourth finger re-bases the stroke": ("            others[id] = (point, point)\n",
                                                "            others[id] = (point, point)\n            for id in armedBy { armedAt[id] = fingersDown[id]?.now ?? armedAt[id] }\n"),
    "M19 always three fingers": ("let fingers = min(3 + movers.count, 4)", "let fingers = 3"),
    "M20 a fifth finger ignored": ("if fingersDown.count >= 5 { done = true }", "if fingersDown.count >= 6 { done = true }"),
    "M21 the flick's speed from arming": ("        for sample in track where sample.time <= time - flickWindow { from = sample }\n", ""),
    "M22 no silence": (SILENCE, "        if !silent {\n            output = .silenced\n        }\n"),
    "M23 the centroid of every finger down": ("for id in armedBy { out[id] = fingersDown[id]?.now ?? armedAt[id] }",
                                              "for (id, f) in fingersDown { out[id] = f.now }"),
    "M24 a cancel before arming ignored": ("if armed { done = true } else { cancelledEarly = true }", "if armed { done = true }"),
    "M25 up and down swapped": ("(dy < 0 ? .swipeUp : .swipeDown)", "(dy < 0 ? .swipeDown : .swipeUp)"),
    "M26 only the one generation": ("guard switchOn, connected, let takes = hostGestures, takes >= generation else",
                                    "guard switchOn, connected, let takes = hostGestures, takes == generation else"),
    "M27 sent with the switch off": ("guard switchOn, connected, let takes", "guard connected, let takes"),
    "M28 the Desktop never first": ("return (true, windowStreams)", "return (true, false)"),
    "M29 an older Mac sent to": ("guard switchOn, connected, let takes = hostGestures, takes >= generation else { return (false, false) }",
                                 "guard switchOn, connected, (hostGestures ?? generation) >= generation else { return (false, false) }"),
    "M30 a Pencil never ends the silence": ("        if fingersDown.isEmpty { silent = false }\n    }", "    }"),
    "M31 a Pencil ends a gesture's silence mid-stroke": ("        if fingersDown.isEmpty { silent = false }\n    }", "        silent = false\n    }"),
    "M32 the first three to land arm (a resting thumb among them; the review's F1)": ("let three = byLanding.suffix(3)", "let three = byLanding.prefix(3)"),
    "M34 the three need not move together (the review's F2)": ("let together = armedBy.allSatisfy { share(armedAt[$0]!, now[$0]!) >= swipeShare * along }\n                    &&",
                                                               "let together = true\n                    &&"),
    "M35 the together test's edge left out": (">= swipeShare * along }", "> swipeShare * along }"),
    "M36 another finger may go against the swipe": (TOGETHER, TOGETHER.split("\n")[0]),
    "M37 the against test's edge let through": ("> -swipeShare * along }", ">= -swipeShare * along }"),
    "M38 the other fingers left out of the pinch": ("        for (id, other) in movers { before[id] = other.start; after[id] = other.now }\n", ""),
    "M39 every other finger took part (a resting thumb counted)": ("let movers = others.filter { distance($0.value.start, $0.value.now) >= chordTravel }", "let movers = others"),
    "M40 the edge of taking part left out": ("distance($0.value.start, $0.value.now) >= chordTravel }", "distance($0.value.start, $0.value.now) > chordTravel }"),
    "M41 a cancel keeps a stroke from going silent": (GATE, GATE.replace(", !holding else", ", !holding, !cancelledEarly else")),
    "M42 another finger's lift position ignored": ("        fingersDown[id] = finger\n        if others[id] != nil { others[id]!.now = point }\n        var output",
                                                   "        fingersDown[id] = finger\n        var output"),
    "M43 another finger's moves ignored": ("        if others[id] != nil { others[id]!.now = point }\n        if !done, armedBy.contains(id)",
                                           "        if !done, armedBy.contains(id)"),
    "M44 fingers counted as every finger down (a resting thumb counted)": ("let fingers = min(3 + movers.count, 4)", "let fingers = min(fingersDown.count, 4)"),
    "M45 two fingers go silent": (GATE, GATE.replace("count >= 3", "count >= 2")),
}
# M33: silence only once the stroke arms, as before the review (the review's F1): the silence moves into the
# arming branch, so three fingers placed slowly, or beside a resting thumb, are not silent.
ARMED = "            armedBy = three.map(\\.key).sorted()\n"
_i = orig.find(SILENCE); _j = orig.find(ARMED) + len(ARMED)
_span = orig[_i:_j] if _i >= 0 and _j > _i else "M33 pattern missing"
MUTANTS["M33 silent only once armed (the review's F1)"] = (
    _span, _span.replace(SILENCE, "").replace(ARMED, "            if !silent { silent = true; output = .silenced }\n" + ARMED))
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
    r = subprocess.run([os.path.join(OUT, "mutant")], capture_output=True, text=True, timeout=300)
    failed = [l[5:] for l in r.stdout.splitlines() if l.startswith("FAIL")]
    ok = r.returncode != 0
    caught += ok
    print(f"{'caught' if ok else 'MISSED'} {name}: {len(failed)} failing, e.g. {[f[:100] for f in failed[:2]]}")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
