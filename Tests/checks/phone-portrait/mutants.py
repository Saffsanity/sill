"""H2 (docs/iphone-portrait-plan.md): each mutant changes PhonePortraitLayout.swift in one place and must fail
the check (main.swift). usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "phone-portrait")   # the mutants' sources and binaries
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/PhonePortraitLayout.swift")
orig = open(SRC).read()
MUTANTS = {
    "M1 16:9 for 16:10": ("static let aspect: CGFloat = 1.6", "static let aspect: CGFloat = 16.0 / 9.0"),
    "M2 the picture's height rounded up": ("(pictureWidth / Self.aspect).rounded(.down)", "(pictureWidth / Self.aspect).rounded(.up)"),
    "M3 no minimum trackpad": ("let pictureHeight = min(natural, max(0, height - Self.fixedHeight - Self.minTrackpad))",
                               "let pictureHeight = natural"),
    "M4 the margin under the picture dropped": ("y: picture.maxY + Self.margin + Self.underPicture", "y: picture.maxY + Self.underPicture"),
    "M5 the strip above row 1": ("strip = CGRect(x: Self.side - Self.stripInset, y: row1.maxY + Self.band + Self.rowGap,",
                                 "strip = CGRect(x: Self.side - Self.stripInset, y: row1.minY - Self.rowGap - Self.stripHeight,"),
    "M6 row 1's width without its gaps": ("buttons = Self.split(row1, count: Button.allCases.count, gap: Self.gap)",
                                          "buttons = Self.split(row1, count: Button.allCases.count, gap: 0)"),
    "M7 one gap too many in a row": ("(row.width - CGFloat(count - 1) * gap)", "(row.width - CGFloat(count) * gap)"),
    "M8 the caps' gap 10": ("caps = Self.split(keys, count: Self.capCount, gap: Self.gap)", "caps = Self.split(keys, count: Self.capCount, gap: 10)"),
    "M9 seven caps": ("static let capCount = 6", "static let capCount = 7"),
    "M10 the trackpad to the edge": ("height: max(0, height - Self.bottom - padTop))", "height: max(0, height - padTop))"),
    "M11 the span as the pad's height": ("trackpadSpan = trackpad.width / Self.aspect", "trackpadSpan = trackpad.height"),
    "M12 the ruler's step never reduced": ("rulerStep = max(0, min(Self.maxRulerStep, room / Self.rulerSpans))", "rulerStep = Self.maxRulerStep"),
    "M13 the ruler on Keyboard": ("let aa = buttons[Button.textSize.rawValue]", "let aa = buttons[Button.keyboard.rawValue]"),
    "M14 the drawer over row 1": ("drawer = CGRect(x: Self.side, y: panelTop,", "drawer = CGRect(x: Self.side, y: row1.minY,"),
    "M15 the panel 360 wide at the trailing edge": ("settings = CGRect(x: Self.side, y: panelTop, width: rowWidth,",
                                                    "settings = CGRect(x: width - Self.side - min(360, rowWidth), y: panelTop, width: min(360, rowWidth),"),
    "M16 one dim over row 1": ("dim = [CGRect(x: 0, y: 0, width: width, height: row1.minY),", "dim = [CGRect(x: 0, y: 0, width: width, height: row1.maxY),"),
    "M17 the anchor from row 1's top": ("y: height > 0 ? settings.minY / height : 0)", "y: height > 0 ? row1.minY / height : 0)"),
    "M18 the strip not widened": ("strip = CGRect(x: Self.side - Self.stripInset,", "strip = CGRect(x: Self.side,"),
    "M19 the panels without their gap": ("let panelTop = row1.maxY + Self.panelGap", "let panelTop = row1.maxY"),
    "M20 the drawer 380 wide": ("drawer = CGRect(x: Self.side, y: panelTop, width: rowWidth,",
                                "drawer = CGRect(x: Self.side, y: panelTop, width: min(380, rowWidth),"),
    "M21 the picture at the top edge": ("picture = CGRect(x: Self.margin, y: Self.margin,", "picture = CGRect(x: Self.margin, y: 0,"),
    "M22 the rows 8 pt from the sides": ("static let side: CGFloat = 14", "static let side: CGFloat = 8"),
    "M23 row 3 without its gap": ("keys = CGRect(x: Self.side, y: strip.maxY + Self.rowGap,", "keys = CGRect(x: Self.side, y: strip.maxY,"),
    "M24 the trackpad's least height 100": ("static let minTrackpad: CGFloat = 120", "static let minTrackpad: CGFloat = 100"),
    "M25 row 1 without its band above": ("y: picture.maxY + Self.margin + Self.underPicture + Self.band,",
                                         "y: picture.maxY + Self.margin + Self.underPicture,"),
    "M26 the strip without row 1's band under it": ("y: row1.maxY + Self.band + Self.rowGap,", "y: row1.maxY + Self.rowGap,"),
    "M27 the fixed height without the band": ("margin + margin + underPicture + band + buttonHeight + band + rowGap",
                                              "margin + margin + underPicture + buttonHeight + rowGap"),
    "M28 the band 4 pt": ("static let band: CGFloat = 6", "static let band: CGFloat = 4"),
}
caught = 0
for name, (old, new) in MUTANTS.items():
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    path = os.path.join(OUT, "mutant.swift")
    open(path, "w").write(orig.replace(old, new))
    b = subprocess.run(["swiftc", "-O", path, os.path.join(SP, "main.swift"), "-o", os.path.join(OUT, "mutant")],
                       capture_output=True, text=True)
    if b.returncode != 0:
        print(f"{name}: DOES NOT COMPILE\n{b.stderr[:600]}"); continue
    r = subprocess.run([os.path.join(OUT, "mutant")], capture_output=True, text=True, timeout=300)
    failed = [l[5:] for l in r.stdout.splitlines() if l.startswith("FAIL")]
    ok = r.returncode != 0
    caught += ok
    print(f"{'caught' if ok else 'MISSED'} {name}: {len(failed)} failing, e.g. {[f[:100] for f in failed[:2]]}")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
