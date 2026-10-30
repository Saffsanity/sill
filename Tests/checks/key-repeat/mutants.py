"""Mutants of KeyRepeat.swift (Sources/SillHost): each changes it in one place, is compiled with the
check by build.sh and must make the check fail.
usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
R = "Sources/SillHost/KeyRepeat.swift"
MUTANTS = [
    # The Mac's settings
    ("Off repeats (no ceiling on the delay)", R, "guard delay > 0, interval > 0, delay < off, interval < off", "guard delay > 0, interval > 0, interval < off"),
    ("a huge interval still repeats", R, "guard delay > 0, interval > 0, delay < off, interval < off", "guard delay > 0, interval > 0, delay < off"),
    ("not a number taken", R, "guard delay > 0, interval > 0, delay < off, interval < off",
     "guard !(delay <= 0), !(interval <= 0), !(delay >= off), !(interval >= off)"),
    ("a zero delay taken", R, "guard delay > 0, interval > 0, delay < off", "guard delay >= 0, interval > 0, delay < off"),
    ("no floor on the delay", R, "Timing(delay: max(delay, shortestDelay), interval:", "Timing(delay: delay, interval:"),
    ("no floor on the interval", R, "interval: max(interval, shortestInterval))", "interval: interval)"),
    ("the delay floor at 0.2 s", R, "package static let shortestDelay = 0.1", "package static let shortestDelay = 0.2"),
    # Which keys repeat
    ("modifiers repeat", R, "package static let neverRepeat: Set<UInt16> = Set(modifierKeys.keys).union([57, 63, 72, 73, 74])",
     "package static let neverRepeat: Set<UInt16> = Set<UInt16>([57, 63, 72, 73, 74])"),
    ("Caps Lock repeats", R, ".union([57, 63, 72, 73, 74])", ".union([63, 72, 73, 74])"),
    ("the media keys repeat", R, ".union([57, 63, 72, 73, 74])", ".union([57, 63])"),
    ("the right command key is not a modifier", R, "54: 0x10_0000, 55: 0x10_0000,", "55: 0x10_0000,"),
    ("right option holds control", R, "58: 0x08_0000, 61: 0x08_0000,", "58: 0x08_0000, 61: 0x04_0000,"),
    # What a posted event does
    ("a modifier's up leaves what the repeats carry", R, "            if !down { held?.carried &= ~flag }\n", ""),
    ("a modifier's down stops the repeat", R, "            if !down { held?.carried &= ~flag }\n            return\n",
     "            if !down { held?.carried &= ~flag } else { held = nil }\n            return\n"),
    ("a modifier's down repeats", R, "        if let flag = Self.modifierKeys[virtualKey] {\n            if !down { held?.carried &= ~flag }\n            return\n        }\n",
     "        if let flag = Self.modifierKeys[virtualKey], !down {\n            held?.carried &= ~flag\n            return\n        }\n"),
    ("any key's up stops the repeat", R, "            if held?.virtualKey == virtualKey { held = nil }", "            held = nil"),
    ("its own up does not stop it", R, "            if held?.virtualKey == virtualKey { held = nil }", "            if held?.virtualKey == virtualKey + 1000 { held = nil }"),
    ("a key that never repeats leaves the one before", R,
     "guard let device, let timing, Self.repeats(virtualKey: virtualKey) else { held = nil; return }",
     "guard let device, let timing, Self.repeats(virtualKey: virtualKey) else { return }"),
    ("a key that never repeats repeats", R,
     "guard let device, let timing, Self.repeats(virtualKey: virtualKey) else { held = nil; return }",
     "guard let device, let timing else { held = nil; return }"),
    ("no wait before the first repeat", R, "                    due: now + timing.delay, quietSince: nil, firstAfter:", "                    due: now + timing.interval, quietSince: nil, firstAfter:"),
    ("the down's flags not carried", R, "carried: flags, timing: timing, pressedAt: now,", "carried: 0, timing: timing, pressedAt: now,"),
    ("a second down keeps the first's time", R, "        held = Held(virtualKey: virtualKey, device: device,",
     "        if held?.virtualKey == virtualKey { return }\n        held = Held(virtualKey: virtualKey, device: device,"),
    # The step
    ("nowhere to land waits instead of stopping", R, "        if landing == .nowhere { held = nil; return .idle }\n", ""),
    ("input held for an activation is overtaken", R, "        if landing == .held { return .wait(until: look) }\n", ""),
    ("the repeat before it is due", R, "        if now < h.due { return .wait(until: h.due) }\n", ""),
    ("no silence rule", R, "        guard let heard, now - heard <= Self.silence else {", "        guard let heard, now - heard <= 1e9 else {"),
    ("a silence of 2 s", R, "    package static let silence = 0.5", "    package static let silence = 2.0"),
    ("heard again: no wait for the delay", R, "            h.quietSince = nil\n            h.due = now + h.timing.delay\n", "            h.quietSince = nil\n            h.due = now\n"),
    ("heard again: never resumes", R, "guard let heard, heard > quiet else { return .wait(until: look) }", "guard let heard, heard > quiet + 1e9 else { return .wait(until: look) }"),
    ("quiet forgotten at once", R, "            h.quietSince = heard ?? -Double.greatestFiniteMagnitude\n            held = h\n            return .wait(until: look)",
     "            return .wait(until: look)"),
    ("a burst to catch up", R, "        h.due = max(h.due + h.timing.interval, now + h.timing.interval / 2)", "        h.due += h.timing.interval"),
    ("the cadence lost (every interval from the step)", R, "        h.due = max(h.due + h.timing.interval, now + h.timing.interval / 2)", "        h.due = now + h.timing.interval * 1.02"),
    ("the repeats carry only what is held", R, "return .post(virtualKey: h.virtualKey, flags: h.carried | holding, next: h.due)",
     "return .post(virtualKey: h.virtualKey, flags: holding, next: h.due)"),
    ("the repeats carry only the down's", R, "return .post(virtualKey: h.virtualKey, flags: h.carried | holding, next: h.due)",
     "return .post(virtualKey: h.virtualKey, flags: h.carried, next: h.due)"),
    ("looking again only at the interval", R, "        let look = now + min(h.timing.interval, Self.lookAgain)", "        let look = now + h.timing.interval"),
    ("stop leaves the key repeating", R, "    package mutating func stop() { held = nil }", "    package mutating func stop() {}"),
    # The first repeat's word (the review of #162's letters: a letter typed, its up held back by a stalled link)
    ("the first repeat needs no word (a stalled up repeats a letter typed)", R,
     "        if let after = h.firstAfter, heard <= after { return .wait(until: look) }\n", ""),
    ("any word since the press will do, whatever the delay", R,
     "firstAfter: now + max(0, timing.delay - Self.firstWord))", "firstAfter: now)"),
    ("the press itself is the word", R, "if let after = h.firstAfter, heard <= after {", "if let after = h.firstAfter, heard < after {"),
    ("no word after a quiet spell", R, "            h.firstAfter = now + max(0, h.timing.delay - Self.firstWord)\n", ""),
    ("the word a ping too late (firstWord 0.15 s)", R, "    package static let firstWord = 0.3", "    package static let firstWord = 0.15"),
    ("the window lists say a later generation", R, "package static let generation = 1", "package static let generation = 2"),
]
caught = 0
for name, rel, old, new in MUTANTS:
    src = open(os.path.join(WT, rel)).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        exe = os.path.join(t, "c")
        mf = os.path.join(t, os.path.basename(rel)); open(mf, "w").write(src.replace(old, new, 1))
        subprocess.run([os.path.join(HERE, "build.sh"), WT, exe, f"{os.path.basename(rel)}={mf}"], capture_output=True, text=True)
        if not os.path.exists(exe): print(f"{name}: did not compile"); continue
        r = subprocess.run([exe], capture_output=True, text=True, timeout=600)
        failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        if r.returncode != 0:
            caught += 1
            print(f"{name}: caught ({len(failed)} FAIL lines; first: {failed[0][:150] if failed else r.stdout.strip()[-150:]})")
        else:
            print(f"{name}: SURVIVED")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
