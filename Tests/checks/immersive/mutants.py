"""Mutants of ImmersivePolicy.swift (iOSClient): each changes it in one place and must make the check
(main.swift) fail. usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "immersive")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/ImmersivePolicy.swift")
orig = open(SRC).read()
APPLIES = "switchOn && keyboardAttached && landscape && streaming && !voiceOver && fillsScreen"
MUTANTS = [
    ("M1 applies with the switch off", APPLIES, "keyboardAttached && landscape && streaming && !voiceOver && fillsScreen"),
    ("M2 applies with no keyboard", APPLIES, "switchOn && landscape && streaming && !voiceOver && fillsScreen"),
    ("M3 applies upright", APPLIES, "switchOn && keyboardAttached && streaming && !voiceOver && fillsScreen"),
    ("M4 applies with nothing streaming", APPLIES, "switchOn && keyboardAttached && landscape && !voiceOver && fillsScreen"),
    ("M5 applies with VoiceOver", APPLIES, "switchOn && keyboardAttached && landscape && streaming && fillsScreen"),
    ("M6 applies in a Stage Manager window", APPLIES, "switchOn && keyboardAttached && landscape && streaming && !voiceOver"),
    ("M7 fills only one way round", "            || (close(size.width, screen.height) && close(size.height, screen.width))\n", "\n"),
    ("M8 fills with no tolerance", "abs(a - b) <= 1", "a == b"),
    ("M9 fills with a loose tolerance", "abs(a - b) <= 1", "abs(a - b) <= 4"),
    ("M10 held does not show the bar", "return revealed || held ? .revealed : .immersed", "return revealed ? .revealed : .immersed"),
    ("M12 entering keeps an old reveal", "        if !wasApplying {\n            revealed = false\n", "        if !wasApplying {\n"),
    ("M13 leaving leaves the timer running", "guard nowApplies else { return .stop }", "guard nowApplies else { return .keep }"),
    ("M14 held leaves the timer running", "        if nowHeld { return .stop }", "        if nowHeld { return .keep }"),
    ("M15 the last holder closing snatches the bar", "        if wasHeld {\n            revealed = true\n", "        if wasHeld {\n            revealed = false\n"),
    ("M16 the last holder closing starts no timer", "            revealed = true\n            return .start\n        }\n        return .keep", "            revealed = true\n            return .keep\n        }\n        return .keep"),
    ("M17 the shortcut taken while off", "guard applies else { return (false, .keep) }", "guard applies else { return (true, .keep) }"),
    ("M18 the shortcut acts while off", "guard applies else { return (false, .keep) }", ""),
    ("M19 the shortcut hides a held bar", "        guard !held else { return (true, .keep) }\n", ""),
    ("M20 the shortcut given up while held", "guard !held else { return (true, .keep) }", "guard !held else { return (false, .keep) }"),
    ("M21 a reveal starts no timer", "return (true, revealed ? .start : .stop)", "return (true, revealed ? .keep : .stop)"),
    ("M22 a hide leaves the timer running", "return (true, revealed ? .start : .stop)", "return (true, revealed ? .start : .keep)"),
    ("M23 the edge acts while off", "guard applies, !held else { return .keep }\n        revealed = true", "guard !held else { return .keep }\n        revealed = true"),
    ("M24 the edge restarts the timer while held", "guard applies, !held else { return .keep }\n        revealed = true", "guard applies else { return .keep }\n        revealed = true"),
    ("M25 a touch while hidden starts the timer", "applies && revealed && !held ? .start : .keep", "applies && !held ? .start : .keep"),
    ("M26 a touch while held starts the timer", "applies && revealed && !held ? .start : .keep", "applies && revealed ? .start : .keep"),
    ("M27 the timer hides nothing", "    mutating func timerFired() {\n        revealed = false\n", "    mutating func timerFired() {\n"),
    ("M29 the chord ignores shift", "(1 << 17) | (1 << 18) | (1 << 19) | (1 << 20)", "(1 << 18) | (1 << 19) | (1 << 20)"),
    ("M30 the chord without option", "static let toggleModifiers: UInt64 = (1 << 18) | (1 << 19) | (1 << 20)", "static let toggleModifiers: UInt64 = (1 << 18) | (1 << 20)"),
    ("M31 the chord any key", "usage == toggleUsage && modifiers & chordMask == toggleModifiers", "modifiers & chordMask == toggleModifiers"),
    ("M32 the chord counts caps lock", "modifiers & chordMask == toggleModifiers", "modifiers == toggleModifiers"),
    ("M33 the edge any height", "startY >= 0 && startY <= edgeZone && dy > 0 && dy > abs(dx)", "startY >= 0 && dy > 0 && dy > abs(dx)"),
    ("M34 the edge sideways too", "startY >= 0 && startY <= edgeZone && dy > 0 && dy > abs(dx)", "startY >= 0 && startY <= edgeZone && dy > 0"),
    ("M35 the edge upward too", "startY >= 0 && startY <= edgeZone && dy > 0 && dy > abs(dx)", "startY >= 0 && startY <= edgeZone && abs(dy) > abs(dx)"),
    ("M36 the edge zone 40 pt", "static let edgeZone: Double = 20", "static let edgeZone: Double = 40"),
    ("M37 auto-hide after 2 s", "static let autoHide: Double = 4", "static let autoHide: Double = 2"),
    ("M38 the bar shown while immersed", "static func barShown(_ state: State) -> Bool { state != .immersed }", "static func barShown(_ state: State) -> Bool { true }"),
    ("M39 revealed does not fill the screen", "static func fillsScreen(_ state: State) -> Bool { state != .off }", "static func fillsScreen(_ state: State) -> Bool { state == .immersed }"),
]
caught = 0
for name, old, new in MUTANTS:
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    src = os.path.join(OUT, "ImmersivePolicy.swift")
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
