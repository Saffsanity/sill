"""H3 mutants of the menus check: each changes one file it compiles in one place, and must make the
check fail. usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]
HERE = os.path.dirname(os.path.abspath(__file__))
PATHS = {
    "StreamMessage.swift": "Sources/StreamProtocol/StreamMessage.swift",
    "MacMenu.swift": "Sources/StreamProtocol/MacMenu.swift",
    "MenuFormat.swift": "Sources/SillHost/MenuFormat.swift",
    "MenuPolicy.swift": "Sources/SillHost/MenuPolicy.swift",
}
MUTANTS = [
    # The wire (MacMenu.swift, StreamMessage.swift)
    ("the fetch at 28", "StreamMessage.swift", "case fetchMenu = 27", "case fetchMenu = 28"),
    ("stale set from pressed", "MacMenu.swift", "self.pressed = pressed; self.stale = stale", "self.pressed = pressed; self.stale = pressed"),
    ("a press's token dropped", "MacMenu.swift", "own titles.\n    public var title: String?\n    public var token: Int?\n\n    public init(version: Int? = nil, id: String? = nil, title: String? = nil, token: Int? = nil) {\n        self.version = version; self.id = id; self.title = title; self.token = token",
     "own titles.\n    public var title: String?\n    public var token: Int?\n\n    public init(version: Int? = nil, id: String? = nil, title: String? = nil, token: Int? = nil) {\n        self.version = version; self.id = id; self.title = title; self.token = nil"),
    ("a fetch's title dropped", "MacMenu.swift", "without an id.\n    public var title: String?\n    public var token: Int?\n\n    public init(version: Int? = nil, id: String? = nil, title: String? = nil, token: Int? = nil) {\n        self.version = version; self.id = id; self.title = title; self.token = token",
     "without an id.\n    public var title: String?\n    public var token: Int?\n\n    public init(version: Int? = nil, id: String? = nil, title: String? = nil, token: Int? = nil) {\n        self.version = version; self.id = id; self.title = nil; self.token = token"),
    # The shortcut (MenuFormat.swift)
    ("⌘ shown with no-Command", "MenuFormat.swift", 'if m & 8 == 0 { text += "⌘" }', 'text += "⌘"'),
    ("⌥ before ⌃", "MenuFormat.swift", 'if m & 4 != 0 { text += "⌃" }\n        if m & 2 != 0 { text += "⌥" }',
     'if m & 2 != 0 { text += "⌥" }\n        if m & 4 != 0 { text += "⌃" }'),
    ("fn dropped", "MenuFormat.swift", 'if m & 16 != 0 { text += "fn " }', 'if m & 16 != 0 { text += "" }'),
    ("the character over the glyph", "MenuFormat.swift", "if let glyph, let name = glyphs[glyph] {", "if char == nil, let glyph, let name = glyphs[glyph] {"),
    ("the virtual key over the character", "MenuFormat.swift", "if key == nil, let virtualKey, let name = virtualKeys[virtualKey] { key = name }",
     "if let virtualKey, let name = virtualKeys[virtualKey] { key = name }"),
    ("F-keys off by one (character)", "MenuFormat.swift", 'key = "F\\(scalar.value - 0xF704 + 1)"', 'key = "F\\(scalar.value - 0xF704)"'),
    ("F-keys off by one (glyph)", "MenuFormat.swift", 'for n in 1...12 { g[110 + n] = "F\\(n)" }', 'for n in 1...12 { g[111 + n] = "F\\(n)" }'),
    ("the 16-character limit off by one", "MenuFormat.swift", "return text.count <= keyLimit ? text : nil", "return text.count < keyLimit ? text : nil"),
    # The item (MenuFormat.swift)
    ("separators without the disabled test", "MenuFormat.swift", 'if raw.title == "", raw.enabled == false, raw.childCount == 0',
     'if raw.title == "", raw.childCount == 0'),
    ("custom views as submenus", "MenuFormat.swift", 'guard raw.firstChildRole == "AXMenu" else { return nil }', "guard raw.childCount > 0 else { return nil }"),
    ("the description for an empty title", "MenuFormat.swift", 'SafeText.label(title ?? description ?? "", limit: titleLimit)',
     'SafeText.label((title?.isEmpty == false ? title : description) ?? "", limit: titleLimit)'),
    ("the mark not cleaned", "MenuFormat.swift", 'let mark = SafeText.label(raw.mark ?? "", limit: 1)', 'let mark = String((raw.mark ?? "").prefix(1))'),
    # Ids (MenuFormat.swift)
    ("the Apple menu allowed", "MenuFormat.swift", "guard indexes[0] >= 1 else { return nil }", "guard indexes[0] >= 0 else { return nil }"),
    ("9 levels", "MenuFormat.swift", "package static let maxDepth = 8", "package static let maxDepth = 9"),
    ("leading zeros", "MenuFormat.swift", 'part == "0" || part.first != "0",', "true,"),
    # The policy (MenuPolicy.swift)
    ("<= for the cache's <", "MenuPolicy.swift", "now - e.at < Self.lifetime,\n              e.appWasFrontmost", "now - e.at <= Self.lifetime,\n              e.appWasFrontmost"),
    ("the inactive entry served to a frontmost app", "MenuPolicy.swift",
     "e.appWasFrontmost || !frontmostNow else { return nil }\n        return e", "true else { return nil }\n        return e"),
    ("an inactive read never answered", "MenuPolicy.swift",
     "e.appWasFrontmost || !frontmostNow else { return nil }\n        return e", "e.appWasFrontmost else { return nil }\n        return e"),
    ("the cache answering another title", "MenuPolicy.swift", "guard let e = entries[id], ShownTitle.matches(now: e.title, shown: title), now",
     "guard let e = entries[id], now"),
    ("no wait after an inactive read", "MenuPolicy.swift", "guard let e = entries[id], !e.appWasFrontmost, now - e.at < Self.revalidation else { return 0 }",
     "guard let e = entries[id], e.appWasFrontmost, now - e.at < Self.revalidation else { return 0 }"),
    ("the wait ending at 1.0 s", "MenuPolicy.swift", "guard let e = entries[id], !e.appWasFrontmost, now - e.at < Self.revalidation else { return 0 }",
     "guard let e = entries[id], !e.appWasFrontmost, now - e.at < Self.lifetime else { return 0 }"),
    ("revalidation at 1.0 s", "MenuPolicy.swift", "package static let revalidation = 1.05", "package static let revalidation = 1.0"),
    ("the 21st request allowed", "MenuPolicy.swift", "guard arrivals.count < limit else { return false }", "guard arrivals.count <= limit else { return false }"),
    ("an ignored line every time", "MenuPolicy.swift", "if let last = lastIgnoredLine, now - last < 1 { return false }",
     "if let last = lastIgnoredLine, now - last < 0 { return false }"),
    ("the kept element's title not compared", "MenuPolicy.swift", "guard ShownTitle.matches(now: current, shown: shown) else { return .refuse(.changed) }",
     "guard elementValid || ShownTitle.matches(now: current, shown: shown) else { return .refuse(.changed) }"),
    ("an empty title matching", "MenuPolicy.swift", "guard let now, !now.isEmpty else { return false }", "guard let now else { return false }"),
    ("an item with children pressed", "MenuPolicy.swift", "if hasChildren { return .refuse(.changed) }", "_ = hasChildren"),
    ("a disabled item pressed", "MenuPolicy.swift", "if enabled == false { return .refuse(.disabled) }", "_ = enabled"),
    ("disabled judged before the title", "MenuPolicy.swift", "guard ShownTitle.matches(now: current, shown: shown) else { return .refuse(.changed) }",
     "if enabled == false { return .refuse(.disabled) }\n        guard ShownTitle.matches(now: current, shown: shown) else { return .refuse(.changed) }"),
    # The device's wait (MenuPolicy.swift)
    ("the device's wait not stretched by a slow link", "MenuPolicy.swift", "max(deviceWait, 4 * seconds(rttMs))", "deviceWait"),
    ("the answer due at the device's whole wait", "MenuPolicy.swift", "wait(rttMs: rttMs) - seconds(rttMs) - margin", "wait(rttMs: rttMs) - margin"),
    ("a request expired a moment late", "MenuPolicy.swift", "waited >= answerBy(rttMs: rttMs)", "waited > answerBy(rttMs: rttMs)"),
    # The submenus of a version (MenuPolicy.swift)
    ("leaves recorded", "MenuPolicy.swift", "for f in found where f.submenu && now[f.index] == nil", "for f in found where now[f.index] == nil"),
    ("a submenu retitled in place accepted", "MenuPolicy.swift", "where index < examined && now[index] != title { return false }",
     "where index < examined && now[index] == nil { return false }"),
    ("places past the read judged", "MenuPolicy.swift", "where index < examined && now[index] != title { return false }", "where now[index] != title { return false }"),
    ("one place past the limit", "MenuPolicy.swift", "guard count + added <= Self.limit else { return false }", "guard count + added <= Self.limit + 1 else { return false }"),
    ("title(of:) from the menu above", "MenuPolicy.swift", "return byMenu[String(id[..<dot])]?[index]", "return byMenu[id]?[index]"),
    ("an item found again taken for the kept one", "MenuPolicy.swift", "return elementValid ? .press : .pressFound", "return .press"),
    ("the log's app not cleaned", "MenuPolicy.swift", "var parts = [SafeText.label(app)]", "var parts = [app]"),
]
caught = 0
for name, file, old, new in MUTANTS:
    text = open(os.path.join(WT, PATHS[file])).read()
    if text.count(old) != 1:
        print(f"NOT APPLIED {name}: pattern found {text.count(old)} times"); continue
    with tempfile.TemporaryDirectory() as t:
        path = os.path.join(t, file)
        open(path, "w").write(text.replace(old, new))
        exe = os.path.join(t, "check")
        b = subprocess.run([os.path.join(HERE, "build.sh"), WT, exe, f"{file}={path}"], capture_output=True, text=True)
        if not os.path.exists(exe):
            print(f"DOES NOT COMPILE {name}\n{(b.stdout + b.stderr)[:600]}"); continue
        r = subprocess.run([exe], capture_output=True, text=True, timeout=300)
        failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        ok = r.returncode != 0 and bool(failed)
        caught += ok
        print(f"{'caught' if ok else 'MISSED'} {name}: {len(failed)} failing, e.g. {[f[:90] for f in failed[:2]]}")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
