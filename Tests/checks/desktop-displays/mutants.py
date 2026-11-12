"""Mutants of DesktopDisplays.swift (Sources/StreamProtocol): each changes it in one place, is compiled with the
check (main.swift) and must make it fail. A mutant that does not compile is not counted as caught.
usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "desktop-displays")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "Sources/StreamProtocol/DesktopDisplays.swift")
orig = open(SRC).read()
SHOWN_FILTER = "        let shown = displays.filter { !$0.isSills && !$0.isStandIn }\n"
MIRROR = "            return primary.mirrors == d.id\n"
SORT = "        let sorted = stops.sorted { ($0.frame.minX, $0.frame.minY, $0.id) < ($1.frame.minX, $1.frame.minY, $1.id) }\n"
TURN = "        guard let i = mainStop else { return sorted }\n        return Array(sorted[i...] + sorted[..<i])\n"
MAIN_MIRROR = "            ?? displays.first { $0.id == main }?.mirrors.flatMap { m in sorted.firstIndex { $0.id == m } }\n"
CHOSEN = "        if !mainOnly, let chosen, let d = candidates.first(where: { $0.uuid == chosen }) { return d }\n"
RESOLVE_FIRST = "        return candidates.first\n    }\n\n    /// How long"
KEEP = "        return now >= leftAt && now - leftAt < choiceGrace\n"
FEW = "        guard candidates.count > 1 else { return nil }\n"
AT = "        guard let i = candidates.firstIndex(where: { $0.id == current }) else { return candidates[0] }\n"
STEP = "        return candidates[(i + 1) % candidates.count]\n"
RATE = "        return min(wanted, max(24, Int(hz.rounded())))\n"
RATE_GUARD = "        guard let hz = refreshHz, hz > 0, hz < 1000 else { return wanted }    // NaN is not > 0\n"
DOTS = "        let dots = desktopStreams && count <= maxDots ? count : 0\n"
COUNTER = "                      counter: desktopStreams && count > maxDots ? \"\\(n)/\\(count)\" : nil,\n"
HINT = "                      accessibilityHint: desktopStreams ? \"Shows the next display.\" : \"Shows the Mac’s desktop.\",\n"
VALUE = "        return name.isEmpty ? \"Display \\(n) of \\(count)\" : \"Display \\(n) of \\(count), \\(name)\"\n"
NAME = "        let name = names.flatMap { $0.count == count && (1...count).contains(n) ? $0[n - 1] : nil }?\n"
SHOWN = "        guard let displays, displays > 1, let current, (1...displays).contains(current) else { return nil }\n"
ON = "        if let pointer, frame.contains(pointer) { return nil }\n"
MUTANTS = [
    # The stops
    ("D1 Sill's own display a stop", SHOWN_FILTER, "        let shown = displays.filter { !$0.isStandIn }\n"),
    ("D2 macOS's stand-in a stop", SHOWN_FILTER, "        let shown = displays.filter { !$0.isSills }\n"),
    ("D3 a mirror set as many stops as displays", MIRROR, "            return true\n"),
    ("D4 two displays mirroring each other both lost", MIRROR, "            return false\n"),
    ("D5 macOS's own order kept", SORT, "        let sorted = stops\n"),
    ("D6 top to bottom first", SORT, "        let sorted = stops.sorted { ($0.frame.minY, $0.frame.minX, $0.id) < ($1.frame.minY, $1.frame.minX, $1.id) }\n"),
    ("D7 right to left", SORT, "        let sorted = stops.sorted { ($0.frame.minX, $0.frame.minY, $0.id) > ($1.frame.minX, $1.frame.minY, $1.id) }\n"),
    ("D8 by ID", SORT, "        let sorted = stops.sorted { $0.id < $1.id }\n"),
    ("D9 no tie by ID", SORT, "        let sorted = stops.sorted { ($0.frame.minX, $0.frame.minY) < ($1.frame.minX, $1.frame.minY) }\n"),
    ("D10 not turned to the main display (#173's leftmost first)", TURN, "        return sorted\n"),
    ("D11 the main display last", TURN, "        guard let i = mainStop else { return sorted }\n        return Array(sorted[(i + 1)...] + sorted[...i])\n"),
    ("D12 the main display, then the rest left to right", TURN,
     "        guard let i = mainStop else { return sorted }\n        return [sorted[i]] + sorted.enumerated().filter { $0.offset != i }.map(\\.element)\n"),
    ("D13 a main display that mirrors another not followed", MAIN_MIRROR, ""),
    # The stop the Desktop shows
    ("D14 locked, the chosen stop all the same", CHOSEN, "        if let chosen, let d = candidates.first(where: { $0.uuid == chosen }) { return d }\n"),
    ("D15 the choice ignored", CHOSEN, ""),
    ("D16 the choice by ID, not UUID", CHOSEN, "        if !mainOnly, let chosen, let d = candidates.first(where: { String($0.id) == chosen }) { return d }\n"),
    ("D17 nothing chosen: the last stop", RESOLVE_FIRST, "        return candidates.last\n    }\n\n    /// How long"),
    # The choice's span
    ("D18 a span of 300 s", "    public static let choiceGrace: Double = 30\n", "    public static let choiceGrace: Double = 300\n"),
    ("D19 no span", "    public static let choiceGrace: Double = 30\n", "    public static let choiceGrace: Double = 0\n"),
    ("D20 a connected device does not keep it", "        if devices > 0 { return true }\n", ""),
    ("D21 a clock set back keeps it", KEEP, "        return now - leftAt < choiceGrace\n"),
    ("D22 kept at exactly 30 s", KEEP, "        return now >= leftAt && now - leftAt <= choiceGrace\n"),
    ("D23 none left yet: gone", "        guard let leftAt else { return true }\n", "        guard let leftAt else { return false }\n"),
    # The next stop
    ("D24 a next with one stop", FEW, "        guard !candidates.isEmpty else { return nil }\n"),
    ("D25 no next with two", FEW, "        guard candidates.count > 2 else { return nil }\n"),
    ("D26 a display not listed: none", AT, "        guard let i = candidates.firstIndex(where: { $0.id == current }) else { return nil }\n"),
    ("D27 no wrap", STEP, "        return candidates[min(i + 1, candidates.count - 1)]\n"),
    ("D28 the same stop again", STEP, "        return candidates[i]\n"),
    ("D29 backwards", STEP, "        return candidates[(i + candidates.count - 1) % candidates.count]\n"),
    # After a step, its number, where input lands
    ("D30 a stop that never streams kept", "        streamed ? stepped : previous\n", "        stepped\n"),
    ("D31 a stop that streams dropped", "        streamed ? stepped : previous\n", "        previous\n"),
    ("D32 counting from 0", "        candidates.firstIndex { $0.id == current }.map { $0 + 1 }\n", "        candidates.firstIndex { $0.id == current }\n"),
    ("D33 input lands on the first stop, whatever streams", "        candidates.first { $0.id == id }?.frame\n", "        candidates.first?.frame\n"),
    ("D34 input never lands on the streamed stop", "        candidates.first { $0.id == id }?.frame\n", "        nil\n"),
    # The pointer after a step
    ("D35 the pointer always moved", ON, ""),
    ("D36 the pointer never moved", ON, "        return nil\n"),
    ("D37 the display's origin, not its centre", "        return CGPoint(x: frame.midX, y: frame.midY)\n", "        return frame.origin\n"),
    # The rate
    ("D38 the stop's rate ignored", RATE, "        return wanted\n"),
    ("D39 the stop's rate whatever the devices ask", RATE, "        return max(24, Int(hz.rounded()))\n"),
    ("D40 no floor of 24", RATE, "        return min(wanted, Int(hz.rounded()))\n"),
    ("D41 truncated, not rounded", RATE, "        return min(wanted, max(24, Int(hz)))\n"),
    ("D42 a rate of 0 held to", RATE_GUARD, "        guard let hz = refreshHz, hz >= 0, hz < 1000 else { return wanted }\n"),
    ("D43 no ceiling on a reported rate (a trap)", RATE_GUARD, "        guard let hz = refreshHz, hz > 0 else { return wanted }\n"),
    # The device's button
    ("D44 seven dots", "    public static let maxDots = 6\n", "    public static let maxDots = 7\n"),
    ("D45 today's VoiceOver label lost", "    public static let todaysLabel = \"Show the full Mac desktop\"\n", "    public static let todaysLabel = \"Desktop\"\n"),
    ("D46 dots while a window streams", DOTS, "        let dots = count <= maxDots ? count : 0\n"),
    ("D47 the first dot always filled", "        return Button(label: label(displays: count, current: n), dots: dots, lit: dots > 0 ? n : 0,\n",
     "        return Button(label: label(displays: count, current: n), dots: dots, lit: dots > 0 ? 1 : 0,\n"),
    ("D48 3/7 while a window streams", COUNTER, "                      counter: count > maxDots ? \"\\(n)/\\(count)\" : nil,\n"),
    ("D49 the counter without the count", COUNTER, "                      counter: desktopStreams && count > maxDots ? \"\\(n)\" : nil,\n"),
    ("D50 the hint always the next display", HINT, "                      accessibilityHint: \"Shows the next display.\",\n"),
    ("D51 a tap steps while a window streams", "                      steps: desktopStreams)\n", "                      steps: true)\n"),
    ("D52 today's VoiceOver label with two stops", "                      accessibilityLabel: \"Desktop\", accessibilityValue: value(n, of: count, names: names),\n",
     "                      accessibilityLabel: todaysLabel, accessibilityValue: value(n, of: count, names: names),\n"),
    ("D53 VoiceOver's value without the name", VALUE, "        return \"Display \\(n) of \\(count)\"\n"),
    ("D54 names not one per stop taken", NAME, "        let name = names.flatMap { (1...$0.count).contains(n) ? $0[n - 1] : nil }?\n"),
    ("D55 a name not trimmed", "            .trimmingCharacters(in: .whitespacesAndNewlines) ?? \"\"\n", " ?? \"\"\n"),
    ("D56 a number with one stop", SHOWN, "        guard let displays, displays > 0, let current, (1...displays).contains(current) else { return nil }\n"),
    ("D57 a number past the count", SHOWN, "        guard let displays, displays > 1, let current, current >= 1 else { return nil }\n"),
    ("D58 a number of 0", SHOWN, "        guard let displays, displays > 1, let current, current <= displays else { return nil }\n"),
    ("D59 the label without its number", "        return \"Desktop \\(n)\"\n", "        return \"Desktop\"\n"),
    ("D60 a tap steps whatever the stops", "        button(displays: displays, current: current, names: nil, desktopStreams: desktopStreams).steps\n",
     "        desktopStreams\n"),
]
caught = 0
for name, old, new in MUTANTS:
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    src = os.path.join(OUT, "DesktopDisplays.swift")
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
os.remove(os.path.join(OUT, "DesktopDisplays.swift"))
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
