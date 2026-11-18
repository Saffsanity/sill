"""Mutants of ThumbnailHold.swift (iOSClient): each changes it in one place and must make the check (main.swift)
fail. usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "thumbnail-hold")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/ThumbnailHold.swift")
orig = open(SRC).read()
MUTANTS = [
    # The constants.
    ("T1 1 s unless changed", "static let standard = 0.5", "static let standard = 1.0"),
    ("T2 1.5 s unless changed (as before)", "static let standard = 0.5", "static let standard = 1.5"),
    ("T3 the floor a tenth (0.1 s)", "static let tenthsRange: ClosedRange<Int> = 2...20", "static let tenthsRange: ClosedRange<Int> = 1...30"),
    ("T4 the ceiling 5 s", "static let tenthsRange: ClosedRange<Int> = 2...20", "static let tenthsRange: ClosedRange<Int> = 2...50"),
    ("T5 the range in seconds up to 5 s", "static let range: ClosedRange<Double> = 0.2...2.0", "static let range: ClosedRange<Double> = 0.2...5.0"),
    ("T6 a step of half a second", "static let step = 0.1", "static let step = 0.5"),
    ("T7 the key renamed", "static let key = \"Sill.thumbnailHold\"", "static let key = \"Sill.thumbnailHoldSeconds\""),
    # The lengths.
    ("L1 rounded down (a value between steps truncated)", "(kept * 10).rounded(.toNearestOrAwayFromZero)", "(kept * 10).rounded(.down)"),
    ("L2 halves to even (0.25 to 0.2)", "(kept * 10).rounded(.toNearestOrAwayFromZero)", "(kept * 10).rounded(.toNearestOrEven)"),
    ("L3 not kept in the range before the Int (a huge value overflows)", "let kept = min(max(seconds, range.lowerBound), range.upperBound)", "let kept = seconds"),
    ("L4 nothing usable the longest hold", "guard seconds.isFinite else { return Int((standard * 10).rounded()) }", "guard seconds.isFinite else { return tenthsRange.upperBound }"),
    ("L5 tenths not kept in the range", "Double(min(max(tenths, tenthsRange.lowerBound), tenthsRange.upperBound)) / 10", "Double(tenths) / 10"),
    ("L6 seconds off the grid (the value as it came, kept in the range)", "static func seconds(_ value: Double) -> Double { seconds(tenths: tenths(value)) }",
     "static func seconds(_ value: Double) -> Double { value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : standard }"),
    ("L7 + and − two tenths", "seconds(tenths: tenths(value) + (up ? 1 : -1))", "seconds(tenths: tenths(value) + (up ? 2 : -2))"),
    ("L8 + and − swapped", "seconds(tenths: tenths(value) + (up ? 1 : -1))", "seconds(tenths: tenths(value) + (up ? -1 : 1))"),
    ("L9 a step from the value as it came, in seconds (drift off the grid)", "seconds(tenths: tenths(value) + (up ? 1 : -1))",
     "min(max(value + (up ? step : -step), range.lowerBound), range.upperBound)"),
    # A stored value.
    ("S1 a number stored is the standard", "case let n as NSNumber: return seconds(n.doubleValue)", "case let n as NSNumber: _ = n; return standard"),
    ("S2 a launch argument's string is the standard", "guard let d = Double(s.trimmingCharacters(in: .whitespacesAndNewlines)) else { return standard }\n            return seconds(d)",
     "_ = s; return standard"),
    ("S3 a string not trimmed", "Double(s.trimmingCharacters(in: .whitespacesAndNewlines))", "Double(s)"),
    ("S4 junk the shortest hold", "default: return standard", "default: return range.lowerBound"),
    # The words.
    ("W1 the value with two decimals (0.50 s)", "String(format: \"%.1f s\", seconds(value))", "String(format: \"%.2f s\", seconds(value))"),
    ("W2 the value without a tenth's digit for whole seconds (1 s)", "String(format: \"%.1f s\", seconds(value))", "String(format: \"%g s\", seconds(value))"),
    ("W3 spoken always \"seconds\" (1 seconds)", "\"\\(number) \\(t == 10 ? \"second\" : \"seconds\")\"", "\"\\(number) seconds\""),
    ("W4 spoken with \"point zero\" (1.0 second)", "let number = t % 10 == 0 ? String(t / 10) : String(format: \"%.1f\", seconds(tenths: t))",
     "let number = String(format: \"%.1f\", seconds(tenths: t))"),
    ("W5 spoken from the value as it came, not its length (9 s spoken as \"9 seconds\"; nan traps)", "        let t = tenths(value)\n        let number",
     "        let t = Int((value * 10).rounded())\n        let number"),
    ("W6 the title in sentence case", "static let title = \"Hold to Show Window Controls\"", "static let title = \"Hold to show window controls\""),
    ("W7 VoiceOver's label in title case", "static let spokenTitle = \"Hold to show window controls\"", "static let spokenTitle = \"Hold to Show Window Controls\""),
    ("W8 the footnote without the drag", ", and before it can be dragged to another place.", "."),
    ("W9 the console's line without its prefix", "\"thumbnails: hold \\(valueText(value))\"", "\"hold \\(valueText(value))\""),
    # The title's lines beside the stepper (the review, 2026-10-29).
    ("W10 the title's lines two (the row stacks sooner)", "static let titleLines = [\"Hold to Show\", \"Window\", \"Controls\"]",
     "static let titleLines = [\"Hold to Show\", \"Window Controls\"]"),
    ("W11 a wider split of three (Show Window on one line)", "static let titleLines = [\"Hold to Show\", \"Window\", \"Controls\"]",
     "static let titleLines = [\"Hold to\", \"Show Window\", \"Controls\"]"),
    ("W12 a word broken (Win-dow)", "static let titleLines = [\"Hold to Show\", \"Window\", \"Controls\"]",
     "static let titleLines = [\"Hold to Show Win\", \"dow\", \"Controls\"]"),
]
caught = 0
for name, old, new in MUTANTS:
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    src = os.path.join(OUT, "ThumbnailHold.swift")
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
