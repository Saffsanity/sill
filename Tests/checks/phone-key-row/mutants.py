"""Mutants of PhoneKeyRow.swift (iOSClient, issue #287, PR #315): each changes it in one place and must make
the check (main.swift, compiled with PhonePortraitLayout.swift as it is) fail. usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "phone-key-row")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/PhoneKeyRow.swift")
LAYOUT = os.path.join(ROOT, "iOSClient/PhonePortraitLayout.swift")
orig = open(SRC).read()
WIDTH = "max(0, (rowWidth - CGFloat(whole) * gap) / (CGFloat(whole) + PhoneKeyRow.peek))"
LOOP = "while whole > 1, Self.capWidth(whole: whole, rowWidth: rowWidth, gap: gap) < PhoneKeyRow.minCapWidth {"
CONTENT = "var content: CGFloat { CGFloat(count) * capWidth + CGFloat(max(0, count - 1)) * gap }"
MUTANTS = [
    # K1 the switch.
    ("M1 Arrow Keys on by default", "static let arrowKeysDefault = false", "static let arrowKeysDefault = true"),
    ("M2 the switch under another key", "static let arrowKeysKey = \"Sill.arrowKeys\"", "static let arrowKeysKey = \"Sill.arrowKey\""),
    ("M3 offered on an iPad", "static func offered(phoneArrangement: Bool) -> Bool { phoneArrangement }",
        "static func offered(phoneArrangement: Bool) -> Bool { true }"),
    # K2 the caps.
    ("M4 five caps that name a key", "static let named = 6", "static let named = 5"),
    ("M5 two arrows", "static let arrows = 4", "static let arrows = 2"),
    ("M6 the arrows whatever the switch", "static func capCount(arrowKeys: Bool) -> Int { arrowKeys ? named + arrows : named }",
        "static func capCount(arrowKeys: Bool) -> Int { named + arrows }"),
    ("M7 the arrows only with the switch off", "static func capCount(arrowKeys: Bool) -> Int { arrowKeys ? named + arrows : named }",
        "static func capCount(arrowKeys: Bool) -> Int { arrowKeys ? named : named + arrows }"),
    ("M8 the row scrolls with the switch off", "static func scrolls(arrowKeys: Bool) -> Bool { arrowKeys }",
        "static func scrolls(arrowKeys: Bool) -> Bool { true }"),
    ("M9 the arrows start at shift", "static var firstArrow: Int { named }", "static var firstArrow: Int { named - 1 }"),
    # K3 the row that scrolls.
    ("M10 caps down to 40 pt", "static let minCapWidth: CGFloat = 44", "static let minCapWidth: CGFloat = 40"),
    ("M11 seven whole at most", "static let maxWhole = 6", "static let maxWhole = 7"),
    ("M12 five whole at most", "static let maxWhole = 6", "static let maxWhole = 5"),
    ("M13 half of the next cap shows", "static let peek: CGFloat = 0.6", "static let peek: CGFloat = 0.5"),
    ("M14 a gap short in the row", WIDTH, "max(0, (rowWidth - CGFloat(whole - 1) * gap) / (CGFloat(whole) + PhoneKeyRow.peek))"),
    ("M15 no peek in the row", WIDTH, "max(0, (rowWidth - CGFloat(whole) * gap) / CGFloat(whole))"),
    ("M16 never fewer whole (the old 37 pt caps at 320 pt)", LOOP,
        "while whole > 1, Self.capWidth(whole: whole, rowWidth: rowWidth, gap: gap) < 0 {"),
    ("M17 a cap of exactly 44 pt dropped", LOOP,
        "while whole > 1, Self.capWidth(whole: whole, rowWidth: rowWidth, gap: gap) <= PhoneKeyRow.minCapWidth {"),
    ("M18 two fewer at a time", "                whole -= 1\n", "                whole -= 2\n"),
    # K4 its ends.
    ("M19 the content without its gaps", CONTENT, "var content: CGFloat { CGFloat(count) * capWidth }"),
    ("M20 a gap too many in the content", CONTENT, "var content: CGFloat { CGFloat(count) * capWidth + CGFloat(count) * gap }"),
    ("M21 it scrolls a cap past its end", "var maxScroll: CGFloat { max(0, content - rowWidth) }",
        "var maxScroll: CGFloat { max(0, content - rowWidth + capWidth) }"),
    ("M22 a cap's place without the gaps", "CGFloat(index) * (capWidth + gap) - scrolled", "CGFloat(index) * capWidth - scrolled"),
    # K5 the fades.
    ("M23 the fade without the gap", "var fadeWidth: CGFloat { PhoneKeyRow.peek * capWidth + gap }",
        "var fadeWidth: CGFloat { PhoneKeyRow.peek * capWidth }"),
    ("M24 the fade past half the row", "rowWidth > 0 ? min(0.5, fadeWidth / rowWidth) : 0", "rowWidth > 0 ? fadeWidth / rowWidth : 0"),
    ("M25 a fade on a row of no width", "rowWidth > 0 ? min(0.5, fadeWidth / rowWidth) : 0", "min(0.5, fadeWidth / rowWidth)"),
    ("M26 the leading edge fades at rest", "func fadesLeading(scrolled: CGFloat) -> Bool { scrolled > 0.5 }",
        "func fadesLeading(scrolled: CGFloat) -> Bool { scrolled >= 0 }"),
    ("M27 the leading edge fades late", "func fadesLeading(scrolled: CGFloat) -> Bool { scrolled > 0.5 }",
        "func fadesLeading(scrolled: CGFloat) -> Bool { scrolled > 1.5 }"),
    ("M28 the trailing edge fades at the end", "func fadesTrailing(scrolled: CGFloat) -> Bool { scrolled < maxScroll - 0.5 }",
        "func fadesTrailing(scrolled: CGFloat) -> Bool { scrolled <= maxScroll }"),
    ("M29 the trailing edge never fades", "func fadesTrailing(scrolled: CGFloat) -> Bool { scrolled < maxScroll - 0.5 }",
        "func fadesTrailing(scrolled: CGFloat) -> Bool { scrolled < 0 }"),
    ("M30 the end where the trailing edge fades", "func atEnd(scrolled: CGFloat) -> Bool { !fadesTrailing(scrolled: scrolled) }",
        "func atEnd(scrolled: CGFloat) -> Bool { fadesTrailing(scrolled: scrolled) }"),
    ("M31 the end once scrolled at all", "func atEnd(scrolled: CGFloat) -> Bool { !fadesTrailing(scrolled: scrolled) }",
        "func atEnd(scrolled: CGFloat) -> Bool { fadesLeading(scrolled: scrolled) }"),
    # K6 VoiceOver.
    ("M32 back to tab", "static func voiceOverFocus(atEnd: Bool) -> Int { atEnd ? 0 : firstArrow }",
        "static func voiceOverFocus(atEnd: Bool) -> Int { atEnd ? 1 : firstArrow }"),
    ("M33 on to the right arrow", "static func voiceOverFocus(atEnd: Bool) -> Int { atEnd ? 0 : firstArrow }",
        "static func voiceOverFocus(atEnd: Bool) -> Int { atEnd ? 0 : firstArrow + arrows - 1 }"),
    ("M34 the action's words swapped", "static func scrollAction(atEnd: Bool) -> String { atEnd ? showModifiers : showArrows }",
        "static func scrollAction(atEnd: Bool) -> String { atEnd ? showArrows : showModifiers }"),
    ("M35 the action's words changed", "static let showArrows = \"Show the arrow keys\"", "static let showArrows = \"Show arrows\""),
    # K7 the words.
    ("M36 the switch named otherwise", "static let title = \"Arrow Keys\"", "static let title = \"Arrows\""),
    ("M37 the group named otherwise", "static let group = \"Keys\"", "static let group = \"Key Row\""),
    ("M38 the footnote without the swipe", " Swipe the row to reach them.\"", "\""),
]
# The check must pass on the rule as it is first: a check that fails anyway catches every mutant for nothing.
base = os.path.join(OUT, "unmutated")
c = subprocess.run(["swiftc", "-O", SRC, LAYOUT, os.path.join(SP, "main.swift"), "-o", base], capture_output=True, text=True)
if c.returncode != 0 or subprocess.run([base], capture_output=True, text=True, timeout=600).returncode != 0:
    print("the check fails on the rule as it is: no mutant can be judged"); print(f"0 of {len(MUTANTS)} mutants caught"); sys.exit(1)
caught = 0
for name, old, new in MUTANTS:
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    src = os.path.join(OUT, "PhoneKeyRow.swift")
    open(src, "w").write(orig.replace(old, new, 1))
    exe = os.path.join(OUT, "mutant")
    if os.path.exists(exe): os.remove(exe)
    c = subprocess.run(["swiftc", "-O", src, LAYOUT, os.path.join(SP, "main.swift"), "-o", exe], capture_output=True, text=True)
    if c.returncode != 0:
        print(f"{name}: did not compile: {c.stderr.strip().splitlines()[0] if c.stderr.strip() else ''}"); continue
    r = subprocess.run([exe], capture_output=True, text=True, timeout=600)
    failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
    if r.returncode != 0:
        caught += 1
        print(f"{name}: caught ({len(failed)} FAIL lines; first: {failed[0][:160] if failed else ''})")
    else:
        print(f"{name}: SURVIVED")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
