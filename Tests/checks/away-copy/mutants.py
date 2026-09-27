"""Mutants of iOSClient/AwayCopy.swift: each must compile and fail the away-copy check (main.swift).
usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))
OUT = os.path.join(ROOT, ".build", "checks", "away-copy")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/AwayCopy.swift")
orig = open(SRC).read()
MUTANTS = {
    "AC1 the header line at home too": [("guard let a = away, a.thisConnectionAway else { return nil }\n        if a.awayRunning {", "guard let a = away else { return nil }\n        if a.awayRunning {")],
    "AC2 running and not swapped": [("        if a.awayRunning {\n            return (\"Away: ", "        if !a.awayRunning {\n            return (\"Away: ")],
    "AC3 the at-home footnote whatever Remote Access says": [("        guard remoteAccessOn else { return nil }\n", "")],
    "AC4 the suggestion before the home quality's callout": [("        if let a = away, a.thisConnectionAway, !a.awayRunning {\n            return Callout(", "        if let a = away, a.thisConnectionAway, !a.awayRunning, link.suggestedBitrate == nil {\n            return Callout(")],
    "AC5 stalled shown": [("        guard let link, link.isBehind else { return nil }", "        guard let link else { return nil }")],
    "AC6 the button drops the resolution": [("let change = HostSettingsChange(bitrate: bitrate, captureScale: link.suggestedCaptureScale)", "let change = HostSettingsChange(bitrate: bitrate)")],
    "AC7 the round-trip callout beside the Mac's own judgement": [("away == nil && remote && slowLink", "remote && slowLink")],
    "AC8 the line offers Settings whenever there is a suggestion": [("        if c.button != nil { return", "        if link.suggestedBitrate != nil { return")],
    "AC9 no linger": [("    static let linger = 2.0", "    static let linger = 0.0")],
    "AC10 announced on every update": [("guard visible, !announced, let t = text else { return nil }", "guard visible, let t = text else { return nil }")],
    "AC11 a flip back does not restart the linger": [("            text = report\n            clearedAt = nil\n", "            text = report\n")],
    "AC12 shown and announced while something is open": [("visible = text != nil && allowed", "visible = text != nil")],
    "AC13 the reason left out of the spoken home line": [(", because a device at home is connected\")", "\")")],
    "AC14 the running footnote names the away quality as home": [("let home = whole(title(a.homeBitrate, a.homeCaptureScale))", "let home = whole(title(a.awayBitrate, a.awayCaptureScale))")],
    "AC16 the footnote's qualities that may wrap": [("let home = whole(title(a.homeBitrate, a.homeCaptureScale))", "let home = title(a.homeBitrate, a.homeCaptureScale)")],
    "AC15 titles that may wrap": [('text.replacingOccurrences(of: " ", with: "\\u{00A0}")', "text")],
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
    path = os.path.join(OUT, "AwayCopy.swift")
    open(path, "w").write(src)
    b = subprocess.run(["swiftc", "-O", path, os.path.join(ROOT, "Sources/StreamProtocol/HostSettings.swift"), os.path.join(SP, "main.swift"),
                        "-o", os.path.join(OUT, "mutant")], capture_output=True, text=True)
    if b.returncode != 0:
        print(f"{name}: DOES NOT COMPILE\n{b.stderr[:600]}"); continue
    r = subprocess.run([os.path.join(OUT, "mutant")], capture_output=True, text=True, timeout=120)
    failed = [l[5:] for l in r.stdout.splitlines() if l.startswith("FAIL")]
    ok = r.returncode != 0
    caught += ok
    print(f"{'caught' if ok else 'MISSED'} {name}: {len(failed)} failing, e.g. {failed[:1]}")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
