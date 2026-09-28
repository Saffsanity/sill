"""Mutants of KeyStrokes.swift (Sources/SillHost) and KeyChords.swift (iOSClient): each changes one
file in one place, is compiled with the check by build.sh and must make the check fail.
usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
STROKES = "Sources/SillHost/KeyStrokes.swift"
CHORDS = "iOSClient/KeyChords.swift"
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
    # A trackpad gesture's shortcut
    ("a gesture's up carries its own flags (before PR #38's fix)", STROKES,
     "KeyStroke(virtualKey: virtualKey, down: false, flags: before)", "KeyStroke(virtualKey: virtualKey, down: false, flags: flags)"),
    ("a gesture's up carries nothing", STROKES,
     "KeyStroke(virtualKey: virtualKey, down: false, flags: before)", "KeyStroke(virtualKey: virtualKey, down: false, flags: 0)"),
    ("a gesture's down carries what the table held too", STROKES,
     "[KeyStroke(virtualKey: virtualKey, down: true, flags: flags),", "[KeyStroke(virtualKey: virtualKey, down: true, flags: flags | before),"),
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
    # The check after a key's up (KeyUpCheck)
    ("a modifier's own key is not checked (only a shortcut's key, as before the review)", STROKES,
     "        if stroke.down {\n            let unreadFlags", "        if stroke.down {\n            if (54...62).contains(stroke.virtualKey) { return nil }\n            let unreadFlags"),
    ("an up is checked for what it still carries (Space's up while ⌘ is down)", STROKES,
     "let cleared = down.carried & ~stroke.flags & ~down.outside", "let cleared = down.carried & ~down.outside"),
    ("the Mac's own keyboard checked too", STROKES,
     "let cleared = down.carried & ~stroke.flags & ~down.outside", "let cleared = down.carried & ~stroke.flags"),
    ("the Mac's own read as the whole table", STROKES,
     "table & ~posted & ~unreadFlags & Self.modifiers", "table & Self.modifiers"),
    ("an unread check's modifiers taken for the Mac's own", STROKES,
     "table & ~posted & ~unreadFlags & Self.modifiers", "table & ~posted & Self.modifiers"),
    ("a down's entry kept after its up", STROKES,
     "guard let down = downs.removeValue(forKey: stroke.virtualKey) else { return nil }", "guard let down = downs[stroke.virtualKey] else { return nil }"),
    ("a read check kept", STROKES,
     "guard let cleared = unread.removeValue(forKey: id) else { return 0 }", "guard let cleared = unread[id] else { return 0 }"),
    ("caps lock checked too", STROKES,
     "package static let modifiers = KeyStrokes.shift | KeyStrokes.control", "package static let modifiers = KeyStrokes.capsLock | KeyStrokes.shift | KeyStrokes.control"),
    ("the read counts a modifier pressed again since", STROKES, "table & cleared & ~posted & ~held", "table & cleared & ~held"),
    ("the read counts a modifier key down", STROKES, "table & cleared & ~posted & ~held", "table & cleared & ~posted"),
    ("the read reports whatever the table holds", STROKES, "table & cleared & ~posted & ~held", "table & ~posted & ~held"),
    # Input with nowhere to land (DroppedInput)
    ("a button's up with nowhere to land is dropped (before the review)", STROKES,
     "        case .pointer(.leftUp, _, _): return leftDown\n        case .pointer(.rightUp, _, _): return rightDown\n", ""),
    ("the right button's up judged by the left", STROKES, "case .pointer(.rightUp, _, _): return rightDown", "case .pointer(.rightUp, _, _): return leftDown"),
    ("a button's up goes whether or not it is down", STROKES, "case .pointer(.leftUp, _, _): return leftDown", "case .pointer(.leftUp, _, _): return true"),
    ("a key's up goes whether or not its key is down", STROKES, "case .key(let usage, false, _): return keyDown(usage)", "case .key(_, false, _): return true"),
    ("every key event goes, downs too", STROKES, "case .key(let usage, false, _): return keyDown(usage)", "case .key: return true"),
    ("a key's up never goes (before this branch)", STROKES, "case .key(let usage, false, _): return keyDown(usage)", "case .key: return false"),
    ("everything goes", STROKES, "        default: return false\n        }\n    }\n}", "        default: return true\n        }\n    }\n}"),
    # The device: its shortcuts
    ("a shortcut without its modifiers' keys going down", CHORDS, "        modifiersDown(modifiers)\n            + [.key(", "        [.key("),
    ("a shortcut without its modifiers' keys coming up", CHORDS, "\n            + modifiersUp(modifiers)\n", "\n"),
    ("the Spotlight key sends ⌘Space as one key down and up (as before)", CHORDS,
     "static let spotlight: [InputEvent] = press(0x2C, with: .command)",
     "static let spotlight: [InputEvent] = [.key(hidUsage: 0x2C, down: true, modifiers: KeyModifiers.command.rawValue), .key(hidUsage: 0x2C, down: false, modifiers: KeyModifiers.command.rawValue)]"),
    ("the Spotlight key is ⌥Space", CHORDS, "press(0x2C, with: .command)", "press(0x2C, with: .option)"),
    ("a modifier's key goes down with the flags from before it", CHORDS,
     "            held.insert(key.flag)\n            return .key(hidUsage: key.usage, down: true, modifiers: held.rawValue)",
     "            let before = held\n            held.insert(key.flag)\n            return .key(hidUsage: key.usage, down: true, modifiers: before.rawValue)"),
    ("the modifiers' keys come up in the order they went down", CHORDS, "return modifiers.keys.reversed().map { key in", "return modifiers.keys.map { key in"),
    ("a modifier's key comes up with its own flag", CHORDS,
     "            held.remove(key.flag)\n            return .key(hidUsage: key.usage, down: false, modifiers: held.rawValue)",
     "            let before = held\n            held.remove(key.flag)\n            return .key(hidUsage: key.usage, down: false, modifiers: before.rawValue)"),
    ("the right command key is no modifier", CHORDS, "case 0xE3, 0xE7: return .command", "case 0xE3: return .command"),
    ("the shift keys are control", CHORDS, "case 0xE1, 0xE5: return .shift", "case 0xE1, 0xE5: return .control"),
    # The device: its hardware keyboard
    ("an up whose down the text system had goes to the Mac", CHORDS,
     "        guard let i = down.firstIndex(of: usage) else { return nil }\n        down.remove(at: i)",
     "        guard let i = down.firstIndex(of: usage) else { return .key(hidUsage: usage, down: false, modifiers: held) }\n        down.remove(at: i)"),
    ("a key's up carries the modifier keys from before it", CHORDS,
     "        down.remove(at: i)\n        return .key(hidUsage: usage, down: false, modifiers: held)",
     "        let before = held\n        down.remove(at: i)\n        return .key(hidUsage: usage, down: false, modifiers: before)"),
    ("a modifier's own key carries what UIKit says", CHORDS, "modifiers: isModifier ? held : modifiers)", "modifiers: modifiers)"),
    ("a key's down carries only the modifier keys down on the Mac", CHORDS, "modifiers: isModifier ? held : modifiers)", "modifiers: held)"),
    ("⌘, ⌃ and ⌥ go to the text system on their own", CHORDS,
     "        0xE0, 0xE2, 0xE3, 0xE4, 0xE6, 0xE7,                                       // control, option, command, left and right\n", ""),
    ("escape goes to the text system", CHORDS, "        0x29, 0x4C,", "        0x4C,"),
    ("shift makes shortcuts", CHORDS, "modifiers & KeyModifiers.shortcutMakers.rawValue != 0",
     "modifiers & (KeyModifiers.shortcutMakers.rawValue | KeyModifiers.shift.rawValue) != 0"),
    ("letting go of the keys sends nothing", CHORDS, "        while let usage = down.last, let up = ended(usage) { ups.append(up) }\n", ""),
    ("letting go of the keys, the first pressed first", CHORDS, "while let usage = down.last, let up", "while let usage = down.first, let up"),
    ("the right-hand keys hold nothing on the device", CHORDS,
     "private var held: UInt64 { down.reduce(0) { $0 | (KeyModifiers.flag(forKey: $1)?.rawValue ?? 0) } }",
     "private var held: UInt64 { down.reduce(0) { $0 | ($1 < 0xE4 ? KeyModifiers.flag(forKey: $1)?.rawValue ?? 0 : 0) } }"),
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
