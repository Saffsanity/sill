"""Mutants of KeyStrokes.swift (Sources/SillHost): each changes it in one place, is compiled with the
check by build.sh and must make the check fail. usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
STROKES = "Sources/SillHost/KeyStrokes.swift"
UP = "        } else {\n            down[usage] = nil\n            flags = heldFlags\n        }\n"
MOD = "            down[usage] = isDown ? device : nil\n            flags = heldFlags\n"
MUTANTS = [
    # A key's up
    ("a key's up carries the device's modifiers (the Spotlight key's stuck command)", STROKES, UP, UP.replace("flags = heldFlags", "flags = said")),
    ("a key's up carries nothing, even with a modifier key down", STROKES, UP, UP.replace("flags = heldFlags", "flags = 0")),
    ("a key's up from another connection leaves it down", STROKES, UP, UP.replace("down[usage] = nil", "if down[usage] == device { down[usage] = nil }")),
    # A key's down
    ("a key's down carries only the device's modifiers", STROKES, "flags = said | heldFlags", "flags = said"),
    ("a key's down carries only what modifier keys hold", STROKES, "flags = said | heldFlags", "flags = heldFlags"),
    # Modifier keys
    ("a modifier key carries the device's modifiers", STROKES, MOD, MOD.replace("flags = heldFlags", "flags = said")),
    ("a modifier key carries the flags from before it changes", STROKES, MOD,
     "            flags = heldFlags\n            down[usage] = isDown ? device : nil\n"),
    ("a second press keeps the first device", STROKES, MOD,
     "            if isDown { if down[usage] == nil { down[usage] = device } } else { down[usage] = nil }\n            flags = heldFlags\n"),
    ("a modifier key's up from another connection leaves it down", STROKES, MOD,
     "            if isDown { down[usage] = device } else if down[usage] == device { down[usage] = nil }\n            flags = heldFlags\n"),
    ("the right-hand keys hold nothing", STROKES, "down.keys.reduce(0) { $0 | (Self.modifierKeys[$1] ?? 0) }",
     "down.keys.reduce(0) { $0 | ($1 < 0xE4 ? Self.modifierKeys[$1] ?? 0 : 0) }"),
    # A device's word on what it holds
    ("a key lets go of nothing the device no longer says", STROKES, "var strokes = letGo(of: device, keeping: said, except: usage)",
     "var strokes: [KeyStroke] = []"),
    ("a key lets go of its own modifier key too", STROKES, "var strokes = letGo(of: device, keeping: said, except: usage)",
     "var strokes = letGo(of: device, keeping: said, except: nil)"),
    ("letting go of every device's keys", STROKES, "where usage != except && down[usage] == device {", "where usage != except {"),
    ("letting go whatever the device said", STROKES, "guard let flag = Self.modifierKeys[usage], keeping & flag == 0 else { continue }",
     "guard let flag = Self.modifierKeys[usage], flag != 0 else { continue }"),
    ("letting go from 0xE0 up", STROKES, "for usage in down.keys.sorted(by: >) where usage != except", "for usage in down.keys.sorted() where usage != except"),
    ("text lets go of nothing", STROKES, "    package mutating func text(from device: Device) -> [KeyStroke] {\n        letGo(of: device, keeping: 0, except: nil)\n",
     "    package mutating func text(from device: Device) -> [KeyStroke] {\n        []\n"),
    # Leaving, and the host going
    ("a leaving device's other keys stay down", STROKES, "for usage in down.keys.sorted() where Self.modifierKeys[usage] == nil {",
     "for usage in down.keys.sorted() where false {"),
    ("a leaving device lets go of every device's other keys", STROKES,
     "for usage in down.keys.sorted() where Self.modifierKeys[usage] == nil {\n            guard let who = down[usage], owner(who) else { continue }",
     "for usage in down.keys.sorted() where Self.modifierKeys[usage] == nil {\n            guard down[usage] != nil else { continue }"),
    ("a leaving device's other keys go up with nothing held", STROKES,
     "            strokes.append(KeyStroke(virtualKey: Self.virtualKeys[usage] ?? 0, down: false, flags: heldFlags))\n        }\n        for usage in down.keys.sorted(by: >) where Self.modifierKeys[usage] != nil {",
     "            strokes.append(KeyStroke(virtualKey: Self.virtualKeys[usage] ?? 0, down: false, flags: 0))\n        }\n        for usage in down.keys.sorted(by: >) where Self.modifierKeys[usage] != nil {"),
    ("a leaving device's modifier keys stay down", STROKES, "for usage in down.keys.sorted(by: >) where Self.modifierKeys[usage] != nil {",
     "for usage in down.keys.sorted(by: >) where false {"),
    ("a leaving device lets go of every device's modifier keys", STROKES,
     "for usage in down.keys.sorted(by: >) where Self.modifierKeys[usage] != nil {\n            guard let who = down[usage], owner(who) else { continue }",
     "for usage in down.keys.sorted(by: >) where Self.modifierKeys[usage] != nil {\n            guard down[usage] != nil else { continue }"),
    ("a leaving device's modifier keys go up from 0xE0", STROKES, "for usage in down.keys.sorted(by: >) where Self.modifierKeys[usage] != nil {",
     "for usage in down.keys.sorted() where Self.modifierKeys[usage] != nil {"),
    ("the host going lets go of nothing", STROKES, "package mutating func releaseAll() -> [KeyStroke] { letGoOfKeys { _ in true } }",
     "package mutating func releaseAll() -> [KeyStroke] { [] }"),
    ("the host going lets go of no one's", STROKES, "package mutating func releaseAll() -> [KeyStroke] { letGoOfKeys { _ in true } }",
     "package mutating func releaseAll() -> [KeyStroke] { letGoOfKeys { _ in false } }"),
    # What is down, and the tables
    ("nothing is ever down", STROKES, "package func isDown(_ usage: UInt16) -> Bool { down[usage] != nil }",
     "package func isDown(_ usage: UInt16) -> Bool { false }"),
    ("an unknown key is typed as A", STROKES, "guard let virtualKey = Self.virtualKeys[usage] else { return nil }",
     "guard let virtualKey = Self.virtualKeys[usage] ?? Self.virtualKeys[0x04] else { return nil }"),
    ("every device bit reaches the Mac", STROKES, "        if modifiers & (1 << 20) != 0 { flags |= command }\n        return flags\n",
     "        if modifiers & (1 << 20) != 0 { flags |= command }\n        return modifiers\n"),
    ("caps lock dropped", STROKES, "        if modifiers & (1 << 16) != 0 { flags |= capsLock }\n", ""),
    ("command read from option's bit", STROKES, "if modifiers & (1 << 20) != 0 { flags |= command }", "if modifiers & (1 << 19) != 0 { flags |= command }"),
    ("the right command key holds control", STROKES, "0xE4: control, 0xE5: shift, 0xE6: option, 0xE7: command,",
     "0xE4: control, 0xE5: shift, 0xE6: option, 0xE7: control,"),
    ("the left command key is the right one's keycode", STROKES, "0xE3: 55,   // Left Command", "0xE3: 54,   // Left Command"),
    ("the names out of the Mac's order", STROKES, '(capsLock, "caps lock"), (control, "control"), (option, "option"),\n                                         (shift, "shift"), (command, "command")]',
     '(capsLock, "caps lock"), (shift, "shift"), (control, "control"),\n                                         (option, "option"), (command, "command")]'),
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
