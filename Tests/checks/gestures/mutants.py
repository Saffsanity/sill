"""H3 (docs/trackpad-gestures-plan.md §9.1): each mutant changes TrackpadGestures.swift in one place and must fail
the check (main.swift). usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "gestures")   # the mutants' sources and binaries
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/TrackpadGestures.swift")
orig = open(SRC).read()
ARM = "guard fingersDown.count == 3, time - firstAt <= chordWindow, !travelled, !cancelledEarly, !holding else {"
MUTANTS = {
    "M1 the window's edge left out": (ARM, ARM.replace("time - firstAt <= chordWindow", "time - firstAt < chordWindow")),
    "M2 the travel's edge let through": ("if distance(point, finger.landed) >= chordTravel { travelled = true }",
                                         "if distance(point, finger.landed) > chordTravel { travelled = true }"),
    "M3 the swipe's distance edge left out": ("if travel >= swipeDistance || (travel >= flickDistance", "if travel > swipeDistance || (travel >= flickDistance"),
    "M4 no flick": ("if travel >= swipeDistance || (travel >= flickDistance && speed(to: end, at: time) >= flickSpeed) {", "if travel >= swipeDistance {"),
    "M5 the flick's distance edge left out": ("|| (travel >= flickDistance && speed", "|| (travel > flickDistance && speed"),
    "M6 the axis's edge left out": ("if major >= axisRatio * minor {", "if major > axisRatio * minor {"),
    "M7 the pinch's edge left out": ("if change <= 1 - pinchRatio { return .pinch }", "if change < 1 - pinchRatio { return .pinch }"),
    "M8 the spread's edge left out": ("if change >= 1 + pinchRatio { return .spread }", "if change > 1 + pinchRatio { return .spread }"),
    "M9 no window": (ARM, ARM.replace(" time - firstAt <= chordWindow,", "")),
    "M10 no travel condition": (ARM, ARM.replace(" !travelled,", "")),
    "M11 no button condition": (ARM, ARM.replace(", !holding else {", " else {")),
    "M12 a decision at every lift": ("        if armed, !done {\n            done = true\n", "        if armed {\n            done = true\n"),
    "M13 left and right swapped": ("return dx < 0 ? .swipeLeft : .swipeRight", "return dx < 0 ? .swipeRight : .swipeLeft"),
    "M14 pinch and spread swapped": ("if change <= 1 - pinchRatio { return .pinch }\n        if change >= 1 + pinchRatio { return .spread }",
                                     "if change <= 1 - pinchRatio { return .spread }\n        if change >= 1 + pinchRatio { return .pinch }"),
    "M15 measured from where the fingers landed": ("for id in armedBy { armedAt[id] = fingersDown[id]!.now }", "for id in armedBy { armedAt[id] = fingersDown[id]!.landed }"),
    "M16 silence ends at the last lift": ("        fingersDown[id] = nil\n        return output", "        fingersDown[id] = nil\n        if fingersDown.isEmpty { silent = false }\n        return output"),
    "M17 a cancel ignored after arming": ("if armed { done = true } else { cancelledEarly = true }", "if !armed { cancelledEarly = true }"),
    "M18 a fourth finger re-bases the stroke": ("            fingerCount = max(fingerCount, fingersDown.count)\n",
                                                "            fingerCount = max(fingerCount, fingersDown.count)\n            for id in armedBy { armedAt[id] = fingersDown[id]?.now ?? armedAt[id] }\n"),
    "M19 always three fingers": ("output = .gesture(gesture, fingers: min(fingerCount, 4))", "output = .gesture(gesture, fingers: 3)"),
    "M20 a fifth finger ignored": ("if fingersDown.count >= 5 { done = true }", "if fingersDown.count >= 6 { done = true }"),
    "M21 the flick's speed from arming": ("for sample in track where sample.time <= time - flickWindow { from = sample }", ""),
    "M22 no silence": ("        fingerCount = 3\n        silent = true\n", "        fingerCount = 3\n"),
    "M23 the centroid of every finger down": ("for id in armedBy { out[id] = fingersDown[id]?.now ?? armedAt[id] }",
                                              "for (id, f) in fingersDown { out[id] = f.now }"),
    "M24 a cancel before arming ignored": ("if armed { done = true } else { cancelledEarly = true }", "if armed { done = true }"),
    "M25 up and down swapped": ("return dy < 0 ? .swipeUp : .swipeDown", "return dy < 0 ? .swipeDown : .swipeUp"),
    "M26 only the one generation": ("guard switchOn, connected, let takes = hostGestures, takes >= generation else",
                                    "guard switchOn, connected, let takes = hostGestures, takes == generation else"),
    "M27 sent with the switch off": ("guard switchOn, connected, let takes", "guard connected, let takes"),
    "M28 the Desktop never first": ("return (true, windowStreams)", "return (true, false)"),
    "M30 a Pencil never ends the silence": ("        if fingersDown.isEmpty { silent = false }\n    }", "    }"),
    "M31 a Pencil ends a gesture's silence mid-stroke": ("        if fingersDown.isEmpty { silent = false }\n    }", "        silent = false\n    }"),
    "M29 an older Mac sent to": ("guard switchOn, connected, let takes = hostGestures, takes >= generation else { return (false, false) }",
                                 "guard switchOn, connected, (hostGestures ?? generation) >= generation else { return (false, false) }"),
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
    r = subprocess.run([os.path.join(OUT, "mutant")], capture_output=True, text=True, timeout=300)
    failed = [l[5:] for l in r.stdout.splitlines() if l.startswith("FAIL")]
    ok = r.returncode != 0
    caught += ok
    print(f"{'caught' if ok else 'MISSED'} {name}: {len(failed)} failing, e.g. {[f[:100] for f in failed[:2]]}")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
