"""Mutants of VersionLabel.swift (iOSClient): each changes it in one place and must make the check (main.swift)
fail. usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "version-label")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/VersionLabel.swift")
orig = open(SRC).read()
MUTANTS = [
    # The words shown.
    ("T1 the build without its parentheses (Sill 0.6.2 1400)", 'if let build { words += " (\\(build))" }', 'if let build { words += " \\(build)" }'),
    ("T2 the name left out (0.6.2 (1400))", 'var words = "Sill"\n        if let version { words += " \\(version)" }',
     'var words = ""\n        if let version { words += "\\(version)" }'),
    ("T3 the version and the build the other way round", 'if let version { words += " \\(version)" }\n        if let build { words += " (\\(build))" }',
     'if let build { words += " \\(build)" }\n        if let version { words += " (\\(version))" }'),
    ("T4 the word build shown (Sill 0.6.2 (build 1400))", 'if let build { words += " (\\(build))" }', 'if let build { words += " (build \\(build))" }'),
    ("T5 a missing build shown as ()", 'if let build { words += " (\\(build))" }', 'words += " (\\(build ?? ""))"'),
    ("T6 the version with a v (Sill v0.6.2 (1400))", 'if let version { words += " \\(version)" }', 'if let version { words += " v\\(version)" }'),
    # The words spoken.
    ("S1 spoken without \"version\" (Sill 0.6.2, build 1400)", 'if let version { words += " version \\(version)" }', 'if let version { words += " \\(version)" }'),
    ("S2 spoken without the comma (Sill version 0.6.2 build 1400)", 'if let build { words += ", build \\(build)" }', 'if let build { words += " build \\(build)" }'),
    ("S3 spoken as shown (the parentheses read out)", 'var spoken: String {\n        var words = "Sill"\n        if let version { words += " version \\(version)" }\n        if let build { words += ", build \\(build)" }\n        return words\n    }',
     'var spoken: String { text }'),
    ("S4 spoken without the name (version 0.6.2, build 1400)", 'var words = "Sill"\n        if let version { words += " version \\(version)" }',
     'var words = ""\n        if let version { words += "version \\(version)" }'),
    # A label at all.
    ("I1 a label without either value (a lone \"Sill\")", "guard v != nil || b != nil else { return nil }", "guard true else { return nil }"),
    ("I2 a label only with both (no label without a build)", "guard v != nil || b != nil else { return nil }", "guard v != nil && b != nil else { return nil }"),
    ("I3 the Info.plist's keys the other way round", 'self.init(version: info?["CFBundleShortVersionString"], build: info?["CFBundleVersion"])',
     'self.init(version: info?["CFBundleVersion"], build: info?["CFBundleShortVersionString"])'),
    ("I4 the build from CFBundleName", 'build: info?["CFBundleVersion"])', 'build: info?["CFBundleName"])'),
    ("I5 the values kept as given, not cleaned", "self.version = v\n        self.build = b", "self.version = version as? String\n        self.build = build as? String"),
    # The cleaning.
    ("C1 no number taken (an Int where a string belongs is none)", "case let n as NSNumber where CFGetTypeID(n) != CFBooleanGetTypeID(): raw = n.stringValue\n", ""),
    ("C2 a Boolean taken as 1 or 0", "case let n as NSNumber where CFGetTypeID(n) != CFBooleanGetTypeID(): raw = n.stringValue",
     "case let n as NSNumber: raw = n.stringValue"),
    ("C3 anything taken as its description (an array, data, a date)", "default: return nil", 'default: raw = value.map { "\\($0)" } ?? ""'),
    ("C4 control and format characters kept", ".filter { $0.properties.isWhitespace || ![.control, .format].contains($0.properties.generalCategory) }",
     ".filter { _ in true }"),
    ("C5 format characters kept (control ones go)", "![.control, .format].contains($0.properties.generalCategory)",
     "![.control].contains($0.properties.generalCategory)"),
    ("C6 Foundation's white space, as the first draft had it (a zero-width space becomes a space)",
     ".filter { $0.properties.isWhitespace || ![.control, .format].contains($0.properties.generalCategory) }\n            .split(whereSeparator: { $0.properties.isWhitespace })",
     ".filter { CharacterSet.whitespacesAndNewlines.contains($0) || ![.control, .format].contains($0.properties.generalCategory) }\n            .split(whereSeparator: { CharacterSet.whitespacesAndNewlines.contains($0) })"),
    ("C7 only spaces split words (tabs, newlines, no-break spaces kept)", ".split(whereSeparator: { $0.properties.isWhitespace })",
     '.split(whereSeparator: { $0 == " " })'),
    ("C8 white space inside dropped, not one space (0.6 .2 → 0.6.2)", 'words.joined(separator: " ")', 'words.joined(separator: "")'),
    ("C9 runs of white space kept whole (no collapsing)", ".split(whereSeparator: { $0.properties.isWhitespace })",
     ".split(omittingEmptySubsequences: false, whereSeparator: { $0.properties.isWhitespace })"),
    ("C10 a blank value kept as an empty one", "return words.isEmpty ? nil : words.joined(separator: \" \")", "return words.joined(separator: \" \")"),
    ("C11 a long value cut at 40 characters", "return words.isEmpty ? nil : words.joined(separator: \" \")",
     "return words.isEmpty ? nil : String(words.joined(separator: \" \").prefix(40))"),
]
caught = 0
for name, old, new in MUTANTS:
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    src = os.path.join(OUT, "VersionLabel.swift")
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
        print(f"{name}: caught ({len(failed)} FAIL lines; first: {failed[0][:150] if failed else 'exit ' + str(r.returncode)})")
    else:
        print(f"{name}: SURVIVED")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
