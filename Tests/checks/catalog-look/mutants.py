"""Mutants of CatalogLook.swift (Sources/SillHost): each changes it in one place, is compiled with the check
(main.swift) and must make it fail. A mutant that does not compile is not counted as caught.
usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "catalog-look")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "Sources/SillHost/CatalogLook.swift")
orig = open(SRC).read()
GONE = "            if !displaysNow.contains(display) { return .displayGone(display) }\n"
NONE = "            guard let display else { return .noDisplay }\n"
EMPTY = "        if !displaysNow.isEmpty {\n"
AGE = "        return age > staleAfterPolls * pollInterval ? .old(age) : nil\n"
NEVER = "        guard let age else { return .never }\n"
MUTANTS = [
    # The rule
    ("C1 the display never judged (the rule before 2026-10-28's fix, its age alone)", GONE, ""),
    ("C2 a missing display never judged", NONE, "            guard let display else { return nil }\n"),
    ("C3 an empty list of displays makes every display gone", EMPTY, "        if true {\n"),
    ("C4 the display judged only when the look is old", EMPTY, "        if !displaysNow.isEmpty, let a = age, a > staleAfterPolls * pollInterval {\n"),
    ("C5 a gone display reported as the first active one", GONE, "            if !displaysNow.contains(display) { return .displayGone(displaysNow[0]) }\n"),
    ("C6 the age never judged", AGE, "        return nil\n"),
    ("C7 every look stale", AGE, "        return .old(age)\n"),
    ("C8 two poll intervals to the dot stale", AGE, "        return age >= staleAfterPolls * pollInterval ? .old(age) : nil\n"),
    ("C9 one poll interval, not two", "    static let staleAfterPolls: Double = 2\n", "    static let staleAfterPolls: Double = 1\n"),
    ("C10 ten poll intervals", "    static let staleAfterPolls: Double = 2\n", "    static let staleAfterPolls: Double = 10\n"),
    ("C11 the poll interval ignored (a fixed 4 s)", AGE, "        return age > 4 ? .old(age) : nil\n"),
    ("C12 no look yet will do", NEVER, "        guard let age else { return nil }\n"),
    ("C13 the age before the display", "        if !displaysNow.isEmpty {\n            guard let display else { return .noDisplay }\n            if !displaysNow.contains(display) { return .displayGone(display) }\n        }\n        guard let age else { return .never }\n        return age > staleAfterPolls * pollInterval ? .old(age) : nil\n",
     "        if let age, age > staleAfterPolls * pollInterval { return .old(age) }\n        if !displaysNow.isEmpty {\n            guard let display else { return .noDisplay }\n            if !displaysNow.contains(display) { return .displayGone(display) }\n        }\n        guard age != nil else { return .never }\n        return nil\n"),
    # The lines
    ("C14 a line for the same display", "        guard let was, let now, was != now else { return nil }\n", "        guard let was, let now else { return nil }\n"),
    ("C15 the line's arrow the other way", "        return \"Desktop: display \\(was) → \\(now) (\\(since)).\"\n", "        return \"Desktop: display \\(now) → \\(was) (\\(since)).\"\n"),
    ("C16 the line without the age", "        let since = age.map { \"the displays changed since the last look, \\(ageWords($0)) ago\" } ?? \"the displays changed since the last look\"\n",
     "        let since = \"the displays changed since the last look\"\n"),
    ("C17 the retry line names no display", "        let next = display.map { \"Looked at the displays again: trying once more on display \\($0).\" } ?? \"Trying once more.\"\n",
     "        let next = \"Trying once more.\"\n"),
    ("C18 the retry line drops the error", "        return \"Could not start streaming \\(source): \\(error). \\(next)\"\n", "        return \"Could not start streaming \\(source). \\(next)\"\n"),
    # The age's words
    ("C19 tenths rounded to nearest", "        if s < 10 { return \"\\((s * 10).rounded(.down) / 10) s\" }\n", "        if s < 10 { return \"\\((s * 10).rounded() / 10) s\" }\n"),
    ("C20 whole seconds under 10 s", "        if s < 10 { return \"\\((s * 10).rounded(.down) / 10) s\" }\n", ""),
    ("C21 minutes from 30 s", "        if s < 60 { return \"\\(Int(s)) s\" }\n", "        if s < 30 { return \"\\(Int(s)) s\" }\n"),
    ("C22 hours past an hour as minutes", "        if s < 3600 { return \"\\(Int(s / 60)) min\" }\n", "        if s < 7200 { return \"\\(Int(s / 60)) min\" }\n"),
    ("C23 days from a day", "        if s < 48 * 3600 { return \"\\(Int(s / 3600)) h\" }\n", "        if s < 24 * 3600 { return \"\\(Int(s / 3600)) h\" }\n"),
    ("C24 a negative age kept", "        let s = max(0, seconds)\n", "        let s = seconds\n"),
    ("C25 attoseconds dropped", "        Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18\n", "        Double(d.components.seconds)\n"),
]
caught = 0
for name, old, new in MUTANTS:
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    src = os.path.join(OUT, "CatalogLook.swift")
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
        print(f"{name}: caught ({failed[0][:110] if failed else f'exit {r.returncode}'})")
    else:
        print(f"{name}: NOT CAUGHT")
os.remove(os.path.join(OUT, "CatalogLook.swift"))
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
