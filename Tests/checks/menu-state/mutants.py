"""H3 (docs/menu-bar-plan.md) mutants of MacMenuState.swift: each changes it in one place, is compiled
with the check by build.sh and must make it fail. usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
F = os.path.join(WT, "iOSClient/MacMenuState.swift")
MUTANTS = [
    ("stale not disabling the rows", "enabled: item.enabled != false && !stale && item.id != nil,", "enabled: item.enabled != false && item.id != nil,"),
    ("separators kept doubled", "if !section.isEmpty { out.append(section) }\n                section = []", "out.append(section)\n                section = []"),
    ("the answer's version ignored (rule 5)", "if m.version != w.version {", "if m.version != w.version && false {"),
    ("> for >= in the timeout", "guard now - w.sentAt >= timeout else { return false }", "guard now - w.sentAt > timeout else { return false }"),
    ("a joined fetch sending twice", "if let i = waiting.firstIndex(where: { $0.id == id && $0.version == current }) {", "if let i = waiting.firstIndex(where: { $0.id == id && $0.version == current && false }) {"),
    ("reset missing a joined completion", "let done = waitingKeys.map { Done(key: $0, content: .message(Self.notConnected)) }", "let done = waiting.map { Done(key: $0.keys[0], content: .message(Self.notConnected)) }"),
    ("\"-\" as on", "return m == \"-\" || m == \"–\" ? .mixed : .on", "return m == \"–\" ? .mixed : .on"),
    ("a press for a disabled row", "guard version != nil, row.kind == .item, row.enabled, let id = row.id", "guard version != nil, row.kind == .item, let id = row.id"),
    ("a new top level keeping the older fetches (rule 2)", "guard w.version != version else { return false }", "guard w.version != version && false else { return false }"),
    ("any answer settling the oldest fetch (rule 4)", "if let i = waiting.firstIndex(where: { $0.token == token }) {", "if let i = waiting.indices.first {"),
    ("a stale menu asked anyway (rule 7)", "if stale {\n            return .settled(", "if stale && false {\n            return .settled("),
    ("before a top level: the menus changed (rule 1)", "guard let current = version else { return .settled(.message(Self.notConnected)) }", "guard let current = version else { return .settled(.message(Self.changedNote)) }"),
    ("a bar menu asking by its old id (rule 11)", "return menus.first { $0.title == title }?.id", "return menus.first { $0.id == builtID }?.id"),
    ("no row for what the Mac left out", "if more > 0 { out.append([.note(moreOnTheMac(more))]) }", "if more > 99_999 { out.append([.note(moreOnTheMac(more))]) }"),
    ("No items under a note", "if out.isEmpty { out = [[.note(noItems)]] }", "if out.count <= 1 { out.append([.note(noItems)]) }"),
    ("two menus with one id", "guard let id = item.id, isTopID(id), !ids.contains(id),", "guard let id = item.id, isTopID(id),"),
    ("a leading zero allowed", "guard (1...4).contains(id.count), id.first != \"0\" else { return false }", "guard (1...4).contains(id.count) else { return false }"),
    ("more than 32 menus", "for item in items where rows.count < maxMenus {", "for item in items where rows.count < maxMenus + 8 {"),
    ("a choice sent while stale", "if stale { return .refused(", "if stale && false { return .refused("),
    ("reset keeping the top level", "        self = MacMenuState()\n", "        waiting = []\n        choices = []\n"),
    ("the hand-over keeping the fetches", "        waiting = []\n        choices = []\n        return done", "        choices = []\n        return done"),
    ("a choice sent with the current version", "return .send(PressMenuItem(version: v, id: id,", "return .send(PressMenuItem(version: version, id: id,"),
    ("titles not cleaned", "guard let title = clean(item.title, limit: titleLimit) else { continue }", "guard let title = item.title, !title.isEmpty else { continue }"),
    ("a shortcut on a submenu", "key: kind == .item ? clean(item.key, limit: keyLimit) : nil,", "key: clean(item.key, limit: keyLimit),"),
    ("a refusal's note left empty", "let note = Self.clean(m.note, limit: Self.noteLimit) ?? Self.changedNote", "let note = Self.clean(m.note, limit: Self.noteLimit) ?? \"\""),
    ("the top's change not reported", "return (done, top != before, nil)", "return (done, false, nil)"),
]
caught = 0
for name, old, new in MUTANTS:
    src = open(F).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        mf = os.path.join(t, "MacMenuState.swift"); open(mf, "w").write(src.replace(old, new, 1))
        exe = os.path.join(t, "c")
        subprocess.run([os.path.join(HERE, "build.sh"), WT, exe, mf], capture_output=True, text=True)
        if not os.path.exists(exe): print(f"{name}: did not compile"); continue
        r = subprocess.run([exe], capture_output=True, text=True, timeout=600)
        failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        if r.returncode != 0:
            caught += 1
            print(f"{name}: caught ({failed[0][:90] if failed else f'exit status {r.returncode}'})")
        else:
            print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
