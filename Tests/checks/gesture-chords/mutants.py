"""H4 (docs/trackpad-gestures-plan.md §9.1): each mutant changes GestureChords.swift in one place and must fail
the check (main.swift). usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "gesture-chords")   # the mutants' sources and binaries
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "Sources/SillHost/GestureChords.swift")
orig = open(SRC).read()
MUTANTS = {
    "M1 32 before 108": (".missionControl: [108, 32],", ".missionControl: [32, 108],"),
    "M2 a shortcut that is off still used": ("guard let key = table[id], key.enabled, key.keyCode != HotKey.unbound else { continue }",
                                             "guard let key = table[id], key.keyCode != HotKey.unbound else { continue }"),
    "M3 an unbound shortcut still used": ("guard let key = table[id], key.enabled, key.keyCode != HotKey.unbound else { continue }",
                                         "guard let key = table[id], key.enabled else { continue }"),
    "M4 the stored modifiers unmasked": ("keyCode: key.keyCode, flags: key.modifiers & deviceIndependentBits)",
                                        "keyCode: key.keyCode, flags: key.modifiers)"),
    "M5 fn dropped from the mask": ("package static let deviceIndependentBits: UInt64 = 0x00FF_0000",
                                    "package static let deviceIndependentBits: UInt64 = 0x007F_0000"),
    "M6 Mission Control closed by its own swipe": ('.missionControl: "swipeDown", .appExpose: "swipeUp"', '.missionControl: "swipeUp", .appExpose: "swipeUp"'),
    "M7 a close that forgets nothing": ("if case .chord = outcome { self.open = nil }", "if case .chord = outcome { }"),
    "M8 the same gesture again posts again": ("        if let open, open == base {\n            return .nothing(base, reason: \"\\(base.title) is already open\")\n        }\n", ""),
    "M9 a Space remembered as a view": ("if case .chord = outcome, base.isView { open = base }", "if case .chord = outcome { open = base }"),
    "M10 other input forgets nothing": ("    package mutating func otherInput() {\n        open = nil\n    }", "    package mutating func otherInput() {\n    }"),
    "M11 left and right swapped": ('case "swipeLeft": return .nextSpace\n        case "swipeRight": return .previousSpace',
                                   'case "swipeLeft": return .previousSpace\n        case "swipeRight": return .nextSpace'),
    "M12 pinch and spread swapped": ('case "pinch": return .apps\n        case "spread": return .showDesktop',
                                     'case "pinch": return .showDesktop\n        case "spread": return .apps'),
    "M13 another action's shortcut when none is on": ('return .nothing(action, reason: "no shortcut for \\(action.settingName) is on in Keyboard Shortcuts")',
                                                      'return action == .missionControl ? .nothing(action, reason: "") : chord(for: .missionControl, table: table)'),
    "M14 a view remembered though nothing was posted": ("if case .chord = outcome, base.isView { open = base }", "if base.isView { open = base }"),
    "M15 the Mission Control key's default code": ("108: HotKey(enabled: true, keyCode: 160, modifiers: 0x800000),", "108: HotKey(enabled: true, keyCode: 161, modifiers: 0x800000),"),
    "M16 a close that does not say so": ("let closes = action.isView && Self.action(for: gesture) != action", "let closes = false"),
    "M17 a test host that does not say it posted nothing": ('+ (dryRun ? " (not posted: a test host)" : "")', '+ ""'),
    "M18 a TEST ONLY entry with more than one =": ("guard parts.count == 2, let id = Int(parts[0]), id >= 0 else { return nil }",
                                                  "guard parts.count >= 2, let id = Int(parts[0]), id >= 0 else { return nil }"),
    "M19 an unknown name printed as sent": ("if (0x30...0x39).contains(v) || (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v) { kept.append(s) }",
                                           "kept.append(s)"),
    "M20 the Spaces counted as views": ("package var isView: Bool { self != .nextSpace && self != .previousSpace }", "package var isView: Bool { true }"),
    "M21 a close of a view that could not close forgets it": ("            let outcome = Self.chord(for: open, table: table)\n            if case .chord = outcome { self.open = nil }",
                                                               "            let outcome = Self.chord(for: open, table: table)\n            self.open = nil"),
}
caught = 0
for name, (old, new) in MUTANTS.items():
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    path = os.path.join(OUT, "mutant.swift")
    open(path, "w").write(orig.replace(old, new))
    b = subprocess.run(["swiftc", "-O", "-package-name", "sill", path, os.path.join(SP, "main.swift"), "-o", os.path.join(OUT, "mutant")],
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
