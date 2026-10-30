"""Mutants of TextComposition.swift (iOSClient): each changes it in one place, is compiled with the check
(main.swift) and StreamProtocol's Input.swift, and must make the check fail. usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "text-composition")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/TextComposition.swift")
INPUT = os.path.join(ROOT, "Sources/StreamProtocol/Input.swift")
orig = open(SRC).read()
MUTANTS = [
    # The composition stays on the device until it is committed
    ("T1 a typed candidate keeps the composition before it (sent twice)", "        return commit(sent + rest)\n", "        return commit(document + rest)\n"),
    ("T2 an empty composition stays one", "guard let text, !text.isEmpty else {", "guard let text else {"),
    ("T3 the input method's caret unclamped", "let location = min(max(selected.location, 0), count)", "let location = max(selected.location, 0)"),
    ("T4 the selection's length unclamped", "length: min(max(selected.length, 0), count - location))", "length: max(selected.length, 0))"),
    ("T5 unmark drops the composition", "        guard let marked else { return [] }\n        retype = \"\"\n        return commit(sent + marked)",
     "        guard marked != nil else { return [] }\n        retype = \"\"\n        return commit(sent)"),
    ("T6 a backspace in a composition also reaches the Mac", "            setMarked(text, selected: NSRange(location: text.utf16.count, length: 0))\n            return []",
     "            setMarked(text, selected: NSRange(location: text.utf16.count, length: 0))\n            return [.backspaces(1)]"),
    ("T7 a backspace with nothing remembered never reaches the Mac", "guard !sent.isEmpty else { return [.backspaces(1)] }", "guard !sent.isEmpty else { return [] }"),
    ("T8 the marked range at the document's start", "marked.map { NSRange(location: sent.utf16.count, length: $0.utf16.count) }",
     "marked.map { NSRange(location: 0, length: $0.utf16.count) }"),
    ("T9 the caret ignores the input method's selection", "return NSRange(location: sent.utf16.count + markedSelection.location, length: markedSelection.length)",
     "return NSRange(location: length, length: 0)"),
    ("T10 the length leaves out the composition", "var length: Int { sent.utf16.count + (marked?.utf16.count ?? 0) }", "var length: Int { sent.utf16.count }"),
    # Corrections
    ("T11 a correction taken before a forget is typed at the end (the PR's clamp: sent twice)",
     "        guard range.location <= length else { return .pastEnd }\n", ""),
    ("T12 a correction only at the very end is stale too", "guard range.location <= length else { return .pastEnd }", "guard range.location < length else { return .pastEnd }"),
    ("T13 a range past the end is not cut there", "let end = min(max(range.location + range.length, start), utf16.count)",
     "let end = max(range.location + range.length, start)"),
    ("T14 a correction leaves out what follows its range", "        return before + text + after\n", "        return before + text\n"),
    ("T15 a forget drops what is composed, unsent", "        let out = unmark()\n        sent = \"\"\n",
     "        marked = nil\n        let out: [Output] = []\n        sent = \"\"\n"),
    ("T16 a forget forgets nothing", "        let out = unmark()\n        sent = \"\"\n", "        let out = unmark()\n"),
    ("T47 a forget keeps what is composed on the device (the PR's: dropped by the input method at the next key)",
     "        let out = unmark()\n", "        let out: [Output] = []\n"),
    # The tail
    ("T17 what was sent trimmed to 200 characters in every edit (the PR's cut)", "        sent = new\n", "        sent = String(new.suffix(200))\n"),
    ("T18 a trim while an input method composes", "var wantsTrim: Bool { marked == nil && sent.count > Self.limit }", "var wantsTrim: Bool { sent.count > Self.limit }"),
    ("T19 a trim at the limit itself", "var wantsTrim: Bool { marked == nil && sent.count > Self.limit }", "var wantsTrim: Bool { marked == nil && sent.count >= Self.limit }"),
    ("T20 a trim keeps one character less", "let kept = String(sent.suffix(Self.keep))", "let kept = String(sent.suffix(Self.keep - 1))"),
    ("T21 a trim keeps the front", "let kept = String(sent.suffix(Self.keep))", "let kept = String(sent.prefix(Self.keep))"),
    ("T22 a trim whenever asked", "        guard wantsTrim else { return }\n        let kept", "        let kept"),
    ("T23 a smaller limit", "static let limit = 4_000", "static let limit = 200"),
    # Backspaces and retyping
    ("T24 one backspace too many", "if old.count > common { out.append(.backspaces(old.count - common)) }", "if old.count > common { out.append(.backspaces(old.count - common + 1)) }"),
    ("T25 backspaces counted in code points, not characters",
     "        let old = Array(String(utf16CodeUnits: Array(units[from...]), count: units.count - from))\n"
     "        let now = Array(String(utf16CodeUnits: Array(newUnits[from...]), count: newUnits.count - from))\n",
     "        let old = String(utf16CodeUnits: Array(units[from...]), count: units.count - from).unicodeScalars.map(Character.init)\n"
     "        let now = String(utf16CodeUnits: Array(newUnits[from...]), count: newUnits.count - from).unicodeScalars.map(Character.init)\n"),
    ("T26 the first difference one character late", "while common < old.count, common < now.count, old[common] == now[common] { common += 1 }",
     "while common < old.count, common < now.count, old[common] == now[common] { common += 1 }\n        if common < old.count, common < now.count { common += 1 }"),
    ("T27 a commit keeps the composition", "        marked = nil\n        markedSelection = NSRange(location: 0, length: 0)\n        let from",
     "        markedSelection = NSRange(location: 0, length: 0)\n        let from"),
    # Which input moves the Mac's caret
    ("T28 a right click moves no caret", "return action == .leftDown || action == .rightDown", "return action == .leftDown"),
    ("T29 a button's up moves the caret", "return action == .leftDown || action == .rightDown", "return action != .move"),
    ("T30 a key's up moves the caret", "case .key(_, let down, _): return down", "case .key: return true"),
    ("T31 a key moves no caret", "case .key(_, let down, _): return down", "case .key: return false"),
    ("T32 typing moves the caret (nothing is ever revised)", "case .text, .scroll, .scrollGesture: return false",
     "case .text: return true\n        case .scroll, .scrollGesture: return false"),
    ("T33 a scroll moves the caret", "case .text, .scroll, .scrollGesture: return false",
     "case .text, .scrollGesture: return false\n        case .scroll: return true"),
    # A Return or a Tab typed as text: where it ends, and the fence after it
    ("T48 a Return or a Tab typed as text forgets what was typed (b1012a17's: dictation's new line said mid-utterance typed the corrected phrase again, a second message)",
     "case .text, .scroll, .scrollGesture: return false",
     "case .text(let text): return carriesReturnOrTab(text)\n        case .scroll, .scrollGesture: return false"),
    ("T49 a Tab typed as text makes nothing final (backspaces into the next field)",
     "if scalar == \"\\n\" || scalar == \"\\r\" || scalar == \"\\t\" { end = offset }",
     "if scalar == \"\\n\" || scalar == \"\\r\" { end = offset }"),
    ("T50 only a lone Return or Tab counts, not one among other text (dictation's new line in a phrase)",
     "        for scalar in text.unicodeScalars {\n", "        for scalar in text.unicodeScalars where text.unicodeScalars.count == 1 {\n"),
    ("T51 a Return found by Character, not by scalar (a CRLF missed)",
     "        for scalar in text.unicodeScalars {\n", "        for scalar in text {\n"),
    ("T52 every blank counts as a Return (a space makes a phrase final: no correction of it)",
     "if scalar == \"\\n\" || scalar == \"\\r\" || scalar == \"\\t\" { end = offset }",
     "if CharacterSet.whitespacesAndNewlines.contains(scalar) { end = offset }"),
    ("F1 the fence never set (2dc6c75's: a correction backspaced over the Return and typed the line again)",
     "            fence = newUnits.count - typed.utf16.count + end\n", "            _ = end\n"),
    ("F2 the fence at the start of the text that carries the Return or the Tab, not after it",
     "fence = newUnits.count - typed.utf16.count + end", "fence = newUnits.count - typed.utf16.count + 0 * end"),
    ("F3 the fence at the end of the text, not just after its last Return or Tab (the words after it in the same text never corrected)",
     "fence = newUnits.count - typed.utf16.count + end", "fence = newUnits.count + 0 * end"),
    ("F4 the fence just before the Return or the Tab, not after it (a correction replaces the Return)",
     "{ end = offset }", "{ end = offset - scalar.utf16.count }"),
    ("F5 the fence after the first Return or Tab of a text, not its last",
     "if scalar == \"\\n\" || scalar == \"\\r\" || scalar == \"\\t\" { end = offset }",
     "if end == nil, scalar == \"\\n\" || scalar == \"\\r\" || scalar == \"\\t\" { end = offset }"),
    ("F6 a correction that would change what is final goes (backspaces over the Return)",
     "        guard keepsFinal(replacing(range, with: text)) else { return .final }\n", ""),
    ("F7 a correction judged by where its range starts, not by what it changes (an utterance sent again from its start loses its new words)",
     "guard keepsFinal(replacing(range, with: text)) else { return .final }", "guard range.location >= fence else { return .final }"),
    ("F8 what is final judged by its length alone, not by its text",
     "new.utf16.starts(with: sent.utf16.prefix(fence))", "new.utf16.count >= fence"),
    ("F9 a selection wholly before the fence kept (the person's backspace right after a Return deletes nothing)",
     "selection = end > start && end > fence ?", "selection = end > start ?"),
    ("F10 the difference looked for from the start, not after the fence (a CR, then an LF: a backspace over the CR)",
     "let from = keepsFinal(new) ? fence : 0", "let from = 0"),
    ("F11 the person's backspace across the fence leaves it past what is left",
     "        fence = min(fence, newUnits.count)\n", ""),
    ("F12 a forget keeps the fence", "        fence = 0\n        retype = \"\"\n", "        retype = \"\"\n"),
    ("F13 a trim leaves the fence where it was", "        fence = max(fence - (sent.utf16.count - kept.utf16.count), 0)\n", ""),
    ("F14 a trim drops the fence", "        fence = max(fence - (sent.utf16.count - kept.utf16.count), 0)\n", "        fence = 0\n"),
    # A selection that reaches back across the fence (Korean's rebuild right after a Return)
    ("J1 a selection that reaches back across the fence not kept (Korean after a Return: a second Return at each letter)",
     "selection = end > start && end > fence ?", "selection = end > start && start >= fence ?"),
    ("J2 such a selection deleted whole (the Return deleted on the Mac)",
     "        guard selection.location < fence else { return commit(sentReplacing(selection, with: \"\")) }\n",
     "        guard selection.location < 0 else { return commit(sentReplacing(selection, with: \"\")) }\n"),
    ("J3 what such a deletion left typed again", "        guard !pending.isEmpty else { return text }\n", "        return text\n"),
    ("J4 text in place of what such a deletion left goes (it changes what is final)",
     "        if pending.hasPrefix(text) { retype = String(pending.dropFirst(text.count)); return \"\" }\n        return nil\n",
     "        if pending.hasPrefix(text) { retype = String(pending.dropFirst(text.count)); return \"\" }\n        return text\n"),
    ("J5 text typed over such a selection goes though it changes what is final",
     "            guard keepsFinal(new) else { self.selection = nil; return [] }\n", ""),
    ("J6 a new selection keeps what a deletion left", "        if selection != nil { retype = \"\" }\n", ""),
    ("J7 what such a deletion left forgotten at once", "        retype = kept\n", ""),
    ("J8 what such a deletion left, typed again in pieces, forgotten after the first",
     "if pending.hasPrefix(text) { retype = String(pending.dropFirst(text.count)); return \"\" }",
     "if pending.hasPrefix(text) { return \"\" }"),
    # Keyboards and ⌃Space
    ("T34 Emoji is a keyboard", "language != \"emoji\" && language != \"dictation\"", "language != \"dictation\""),
    ("T35 dictation is a keyboard", "language != \"emoji\" && language != \"dictation\"", "language != \"emoji\""),
    ("T36 ⌃Space is iPadOS's with one keyboard (the PR's: always)", "return Set(languages().filter(isKeyboard)).count >= 2", "return true"),
    ("T37 ⌃Space is iPadOS's with one keyboard and Emoji", "return Set(languages().filter(isKeyboard)).count >= 2", "return Set(languages()).count >= 2"),
    ("T38 a keyboard in the same language counted twice", "return Set(languages().filter(isKeyboard)).count >= 2", "return languages().filter(isKeyboard).count >= 2"),
    ("T39 ⌃⇧Space is iPadOS's too", "modifiers & (shift | control | option | command) == control", "modifiers & (control | option | command) == control"),
    ("T40 any key with ⌃ is the switch", "guard usage == space, modifiers", "guard modifiers"),
    ("T42 the keyboards asked for at every key", "        guard usage == space, modifiers & (shift | control | option | command) == control else { return false }\n        return Set(languages().filter(isKeyboard)).count >= 2",
     "        let asked = Set(languages().filter(isKeyboard))\n        guard usage == space, modifiers & (shift | control | option | command) == control else { return false }\n        return asked.count >= 2"),
    ("T41 caps lock makes ⌃Space the Mac's", "modifiers & (shift | control | option | command) == control", "modifiers == control"),
    # The document a correction's range was taken in
    ("T43 a forget keeps the document (a correction taken before it lands in what was typed since)",
     "        sent = \"\"\n        generation += 1\n", "        sent = \"\"\n"),
    ("T44 a trim keeps the document", "        sent = kept\n        generation += 1\n", "        sent = kept\n"),
    ("T45 the document a correction was taken in ignored", "        if let taken, taken != generation { return .forgotten }\n", ""),
    ("T46 every edit starts a new document", "        sent = new\n        fence", "        sent = new\n        generation += 1\n        fence"),
    # What the text system selects, for its next edit
    ("S1 text typed over a selection is added after it (Korean's syllables twice)",
     "        if marked == nil, let selection {\n            let new = sentReplacing(selection, with: text)\n"
     "            guard keepsFinal(new) else { self.selection = nil; return [] }\n            return commit(new)\n        }\n", ""),
    ("S2 a backspace over a selection deletes one character", "        if let selection { return deleteSelection(selection) }\n", ""),
    ("S3 an empty selection kept (typing goes where the caret moved)",
     "selection = end > start && end > fence ? NSRange(location: start, length: end - start) : nil",
     "selection = end > fence ? NSRange(location: start, length: end - start) : nil"),
    ("S4 a selection kept while an input method composes", "    mutating func select(_ range: NSRange) {\n        guard marked == nil else { return }\n",
     "    mutating func select(_ range: NSRange) {\n"),
    ("S5 a selection not cut at the end", "let end = min(max(range.location + range.length, start), count)", "let end = max(range.location + range.length, start)"),
    ("S6 an edit keeps the selection", "        selection = nil\n        marked = nil\n", "        marked = nil\n"),
    ("S7 a forget keeps the selection", "        selection = nil\n        fence = 0\n", "        fence = 0\n"),
    ("S8 a trim keeps the selection", "        generation += 1\n        selection = nil\n        retype = \"\"\n    }\n",
     "        generation += 1\n        retype = \"\"\n    }\n"),
    ("S9 a composition over a selection keeps the selected text",
     "        if marked == nil, let selection { out = deleteSelection(selection) }\n", ""),
    ("S10 the selection never reported to the text system", "guard marked != nil else { return selection ?? NSRange(location: length, length: 0) }",
     "guard marked != nil else { return NSRange(location: length, length: 0) }"),
    ("S11 a selection's edit leaves out what follows it", "            + String(utf16CodeUnits: Array(units[upper...]), count: units.count - upper)", "            + \"\""),
    ("S12 a selection one unit short at its start", "let lower = min(range.location, units.count), upper", "let lower = min(range.location + 1, units.count), upper"),
    ("S13 an empty composition drops a selection", "guard let text, !text.isEmpty else { marked = nil; markedSelection = NSRange(location: 0, length: 0); return [] }",
     "guard let text, !text.isEmpty else { marked = nil; markedSelection = NSRange(location: 0, length: 0); selection = nil; return [] }"),
    # Who types a hardware keyboard's characters (KeyTyping, #162's letters)
    ("K1 marked text ignored: keys reach the Mac mid-composition", "        if composing { return .composing }\n", ""),
    ("K2 the latch ignored: a latched ⌘ and a hardware S are a plain S", "if !macRepeats || latched { return .text }", "if !macRepeats { return .text }"),
    ("K3 the latch and the Mac's word before marked text", "        if composing { return .composing }\n        if !macRepeats || latched { return .text }\n",
     "        if !macRepeats || latched { return .text }\n        if composing { return .composing }\n"),
    ("K13 the Mac's word ignored: keys to a Mac that repeats none (Delete and Space lose iPadOS's repeat)", "if !macRepeats || latched { return .text }",
     "if latched { return .text }"),
    ("K4 every keyboard with a script types on the Mac (Russian, Chinese)", 'return lang.script?.identifier == "Latn" && !composingLatin',
     'return lang.script != nil && !composingLatin'),
    ("K5 Vietnamese types on the Mac (its Telex and VNI never compose)", 'static let composingLatin: Set<String> = ["vi", "haw"]',
     'static let composingLatin: Set<String> = ["haw"]'),
    ("K14 Hawaiian types on the Mac (its input method never composes)", 'static let composingLatin: Set<String> = ["vi", "haw"]',
     'static let composingLatin: Set<String> = ["vi"]'),
    ("K15 the Latin alphabet's input methods ignored: Vietnamese and Hawaiian on the Mac",
     ' && !composingLatin.contains(lang.languageCode?.identifier ?? "")', ''),
    ("K6 no keyboard types on the Mac (as before: held letters never repeat)", "if let inputMode { return typesOnMac(inputMode) ? .keys : .text }",
     "if let inputMode { return typesOnMac(inputMode) ? .text : .text }"),
    ("K7 none selected: the Mac types whatever is set up", "return !set.isEmpty && set.allSatisfy(typesOnMac) ? .keys : .text", "return .keys"),
    ("K8 none selected: iPadOS types whatever is set up", "return !set.isEmpty && set.allSatisfy(typesOnMac) ? .keys : .text", "return .text"),
    ("K9 none selected: one Latin keyboard among others is enough", "return !set.isEmpty && set.allSatisfy(typesOnMac) ? .keys : .text",
     "return set.contains(where: typesOnMac) ? .keys : .text"),
    ("K10 none selected and none set up: the Mac types", "return !set.isEmpty && set.allSatisfy(typesOnMac) ? .keys : .text",
     "return set.allSatisfy(typesOnMac) ? .keys : .text"),
    ("K11 Emoji and dictation counted as keyboards set up", "let set = keyboards().filter(TextInputRules.isKeyboard)", "let set = keyboards()"),
    ("K12 the keyboards set up asked for every key", "        if let inputMode { return typesOnMac(inputMode) ? .keys : .text }\n        let set = keyboards()",
     "        let all = keyboards()\n        if let inputMode { return typesOnMac(inputMode) ? .keys : .text }\n        let set = all"),
    ("K16 only keyRepeat 1 counts: a later generation's Mac gets no keys", "static func macRepeats(keyRepeat: Int?) -> Bool { (keyRepeat ?? 0) >= 1 }",
     "static func macRepeats(keyRepeat: Int?) -> Bool { keyRepeat == 1 }"),
    ("K17 a Mac that says nothing counted as repeating", "static func macRepeats(keyRepeat: Int?) -> Bool { (keyRepeat ?? 0) >= 1 }",
     "static func macRepeats(keyRepeat: Int?) -> Bool { (keyRepeat ?? 1) >= 1 }"),
    ("K18 keyRepeat 0 counted as repeating", "static func macRepeats(keyRepeat: Int?) -> Bool { (keyRepeat ?? 0) >= 1 }",
     "static func macRepeats(keyRepeat: Int?) -> Bool { (keyRepeat ?? -1) >= 0 }"),
]
caught = 0
for name, old, new in MUTANTS:
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    src = os.path.join(OUT, "TextComposition.swift")
    open(src, "w").write(orig.replace(old, new, 1))
    exe = os.path.join(OUT, "mutant")
    if os.path.exists(exe): os.remove(exe)
    c = subprocess.run(["swiftc", "-O", src, INPUT, os.path.join(SP, "main.swift"), "-o", exe], capture_output=True, text=True)
    if c.returncode != 0:
        print(f"{name}: did not compile: {c.stderr.strip().splitlines()[0] if c.stderr.strip() else ''}"); continue
    try:
        r = subprocess.run([exe], capture_output=True, text=True, timeout=600)
    except subprocess.TimeoutExpired:
        print(f"{name}: SURVIVED (timed out)"); continue
    failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
    if r.returncode != 0:
        caught += 1
        print(f"{name}: caught ({len(failed)} FAIL lines; first: {failed[0][:160] if failed else 'exit status ' + str(r.returncode)})")
    else:
        print(f"{name}: SURVIVED")
print(f"{caught} of {len(MUTANTS)} mutants caught")
