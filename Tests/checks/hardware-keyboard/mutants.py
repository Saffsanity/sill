"""Mutants of HardwareKeyboardPolicy.swift (iOSClient): each changes it in one place and must make the check
(main.swift) fail. usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "hardware-keyboard")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/HardwareKeyboardPolicy.swift")
orig = open(SRC).read()
MUTANTS = [
    ("M1 a keyboard's hold with something open", "var wantsAutomatic: Bool { onScreen && attached && takers.isEmpty }",
     "var wantsAutomatic: Bool { onScreen && attached }"),
    ("M2 a keyboard's hold with no keyboard", "var wantsAutomatic: Bool { onScreen && attached && takers.isEmpty }",
     "var wantsAutomatic: Bool { onScreen && takers.isEmpty }"),
    ("M3 a keyboard's hold with no view in a window", "var wantsAutomatic: Bool { onScreen && attached && takers.isEmpty }",
     "var wantsAutomatic: Bool { attached && takers.isEmpty }"),
    ("M4 taking it whoever holds it", "private var takeIfWanted: [Action] { hold == .none && wantsAutomatic ? [.take(automatic: true)] : [] }",
     "private var takeIfWanted: [Action] { wantsAutomatic ? [.take(automatic: true)] : [] }"),
    ("M5 a joining view keeps the old one's hold", "        onScreen = true\n        hold = .none\n        lastHeld = .none\n",
     "        onScreen = true\n        lastHeld = .none\n"),
    ("M6 a joining view keeps the old one's last hold", "        onScreen = true\n        hold = .none\n        lastHeld = .none\n",
     "        onScreen = true\n        hold = .none\n"),
    ("M7 a joining view takes nothing", "        lastHeld = .none\n        return takeIfWanted\n", "        lastHeld = .none\n        return []\n"),
    ("M8 a leaving view still counts as on screen", "        onScreen = false\n        hold = .none\n    }", "        hold = .none\n    }"),
    ("M9 a repeated attach acts (it fights another responder)", "        guard now != attached else { return [] }\n", ""),
    ("M10 an attach takes nothing", "        if now { return takeIfWanted }", "        if now { return [] }"),
    ("M11 a detach keeps the keyboard's hold", "        return hold == .automatic ? [.letGo] : []\n    }\n\n    /// What is open changed.",
     "        return []\n    }\n\n    /// What is open changed."),
    ("M12 a detach lets the person's go too", "        return hold == .automatic ? [.letGo] : []\n    }\n\n    /// What is open changed.",
     "        return hold != .none ? [.letGo] : []\n    }\n\n    /// What is open changed."),
    ("M13 a taker opening keeps the keyboard's hold", "        if !now.isEmpty { return hold == .automatic ? [.letGo] : [] }",
     "        if !now.isEmpty { return [] }"),
    ("M14 a taker opening lets the person's go too (the drawer and Menus did not)", "        if !now.isEmpty { return hold == .automatic ? [.letGo] : [] }",
     "        if !now.isEmpty { return hold != .none ? [.letGo] : [] }"),
    ("M15 the last taker closing takes nothing", "        return was.isEmpty ? [] : takeIfWanted", "        return []"),
    ("M16 nothing open again takes it on every repeat (it fights)", "        return was.isEmpty ? [] : takeIfWanted", "        return takeIfWanted"),
    ("M17 the button over nothing takes it for the keyboard", "        case .none: return onScreen ? [.take(automatic: false)] : []\n        case .automatic:\n            hold = .own\n            return [.makeOwn]\n        case .own:\n            guard",
     "        case .none: return onScreen ? [.take(automatic: true)] : []\n        case .automatic:\n            hold = .own\n            return [.makeOwn]\n        case .own:\n            guard"),
    ("M18 the button over nothing with no view asks anyway", "        case .none: return onScreen ? [.take(automatic: false)] : []\n        case .automatic:\n            hold = .own\n            return [.makeOwn]\n        case .own:\n            guard",
     "        case .none: return [.take(automatic: false)]\n        case .automatic:\n            hold = .own\n            return [.makeOwn]\n        case .own:\n            guard"),
    ("M19 the button over the keyboard's hold lets go", "        case .automatic:\n            hold = .own\n            return [.makeOwn]\n        case .own:\n            guard",
     "        case .automatic:\n            return [.letGo]\n        case .own:\n            guard"),
    ("M20 the button over the keyboard's hold lights nothing", "        case .automatic:\n            hold = .own\n            return [.makeOwn]\n        case .own:\n            guard",
     "        case .automatic:\n            return [.makeOwn]\n        case .own:\n            guard"),
    ("M21 the button over the person's always lets go (keys stop with a keyboard attached)", "            guard wantsAutomatic else { return [.letGo] }\n",
     "            return [.letGo]\n"),
    ("M22 the button over the person's keeps it theirs", "            hold = .automatic\n            return [.makeAutomatic]",
     "            return [.makeAutomatic]"),
    ("M23 a restore over the keyboard's hold keeps it the keyboard's", "        case .automatic:\n            hold = .own\n            return [.makeOwn]\n        case .own: return []",
     "        case .automatic: return []\n        case .own: return []"),
    ("M24 taking it down lets go of nothing", "        guard show else { return hold == .none ? [] : [.letGo] }", "        guard show else { return [] }"),
    ("M25 a restore takes it for the keyboard", "        case .none: return onScreen ? [.take(automatic: false)] : []\n        case .automatic:\n            hold = .own\n            return [.makeOwn]\n        case .own: return []",
     "        case .none: return onScreen ? [.take(automatic: true)] : []\n        case .automatic:\n            hold = .own\n            return [.makeOwn]\n        case .own: return []"),
    ("M26 given back: the keyboard's whenever it is wanted", "        if lastHeld != .none { return lastHeld }\n        return wantsAutomatic ? .automatic : .own",
     "        if wantsAutomatic { return .automatic }\n        return lastHeld != .none ? lastHeld : .own"),
    ("M27 given back: always the person's", "            hold = unpromptedKind", "            hold = .own"),
    ("M28 a keyboard's hold given back with something open is kept", "        return hold == .automatic && !wantsAutomatic ? [.letGo] : []", "        return []"),
    ("M29 what was asked ignored: always the keyboard's", "            hold = automatic ? .automatic : .own", "            hold = .automatic"),
    ("M30 a resignation forgets what was held", "        if hold != .none { lastHeld = hold }\n", ""),
    ("M31 a resignation keeps the hold", "        if hold != .none { lastHeld = hold }\n        hold = .none\n", "        if hold != .none { lastHeld = hold }\n"),
]
caught = 0
for name, old, new in MUTANTS:
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    src = os.path.join(OUT, "HardwareKeyboardPolicy.swift")
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
