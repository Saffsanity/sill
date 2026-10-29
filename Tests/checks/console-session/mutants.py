"""Mutants of Sources/SillHost/ConsoleSession.swift: each must compile and fail the console-session
check (main.swift). usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))
OUT = os.path.join(ROOT, ".build", "checks", "console-session")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "Sources/SillHost/ConsoleSession.swift")
orig = open(SRC).read()
MUTANTS = {
    "C1 the key without its S": [('static let onConsoleKey = "kCGSSessionOnConsoleKey"', 'static let onConsoleKey = "kCGSessionOnConsoleKey"')],
    "C2 no dictionary counts as off the console": [("guard let value = dictionary?[onConsoleKey] as? NSNumber else { return nil }", "guard let value = dictionary?[onConsoleKey] as? NSNumber else { return false }")],
    "C3 the field sent on the console too": [("static func wire(onConsole: Bool) -> Bool? { onConsole ? nil : false }", "static func wire(onConsole: Bool) -> Bool? { onConsole }")],
    "C4 the field never false": [("static func wire(onConsole: Bool) -> Bool? { onConsole ? nil : false }", "static func wire(onConsole: Bool) -> Bool? { nil }")],
    "C5 a read that says nothing counts as back": [("guard let read, read != current else { return nil }", "let read = read ?? true\n        guard read != current else { return nil }")],
    "C6 a line at every look": [("guard let read, read != current else { return nil }", "guard let read else { return nil }")],
    "C7 the lines swapped": [("return (read, read ? backLine : awayLine)", "return (read, read ? awayLine : backLine)")],
    "C8 the hook on any host": [('        guard synthetic else { return (nil, "SILL_TEST_CONSOLE_FILE ignored: only a --synthetic host takes it.") }\n', "")],
    "C9 an empty variable taken": [('guard let path = env["SILL_TEST_CONSOLE_FILE"], !path.isEmpty else { return (nil, nil) }', 'guard let path = env["SILL_TEST_CONSOLE_FILE"] else { return (nil, nil) }')],
    "C10 the file's newline kept": [('contents?.trimmingCharacters(in: .whitespacesAndNewlines) != "off"', 'contents != "off"')],
    "C11 no file counts as off": [('contents?.trimmingCharacters(in: .whitespacesAndNewlines) != "off"', '(contents ?? "off").trimmingCharacters(in: .whitespacesAndNewlines) != "off"')],
    "C12 a look every five seconds": [("static let lookInterval = 1.0", "static let lookInterval = 5.0")],
}
caught = 0
for name, edits in MUTANTS.items():
    src = orig
    for old, new in edits:
        n = src.count(old)
        if n != 1:
            print(f"{name}: NOT APPLIED (pattern found {n} times)"); src = None; break
        src = src.replace(old, new)
    if src is None: continue
    path = os.path.join(OUT, "ConsoleSession.swift")
    open(path, "w").write(src)
    b = subprocess.run(["swiftc", "-O", path, os.path.join(SP, "main.swift"), "-o", os.path.join(OUT, "mutant")],
                       capture_output=True, text=True)
    if b.returncode != 0:
        print(f"{name}: DOES NOT COMPILE\n{b.stderr[:600]}"); continue
    r = subprocess.run([os.path.join(OUT, "mutant")], capture_output=True, text=True, timeout=120)
    failed = [l[5:] for l in r.stdout.splitlines() if l.startswith("FAIL")]
    ok = r.returncode != 0
    caught += ok
    print(f"{'caught' if ok else 'MISSED'} {name}: {len(failed)} failing, e.g. {failed[:1]}")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
