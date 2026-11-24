"""Mutants of iOSClient/SettingsPane.swift (docs/settings-pane-plan.md): each changes it in one place and must
fail the check (main.swift), compiled with DuoPosture.swift as the check is. usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "settings-pane")  # the mutants' sources and binaries
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/SettingsPane.swift")
DUO = os.path.join(ROOT, "iOSClient/DuoPosture.swift")
orig = open(SRC).read()
MUTANTS = {
    # The numbers.
    "M1 margins of 8": ("static let margin: CGFloat = 16", "static let margin: CGFloat = 8"),
    "M3 a book page's column from 280": ("static let minColumn: CGFloat = 300", "static let minColumn: CGFloat = 280"),
    "M6 one column at the full width": ("let column = min(SettingsPane.maxColumn, max(0, W - 2 * m))", "let column = max(0, W - 2 * m)"),
    "M7 pages of 150": ("static let minPage: CGFloat = 200", "static let minPage: CGFloat = 150"),
    # The laptop pose.
    "M8 the laptop pose ignored": ("if let across = fold.horizontalBand, across.minY >= SettingsPane.minPage,",
                                   "if let across = fold.horizontalBand, across.minY >= SettingsPane.minPage, false,"),
    "M9 the lower page's least without the home indicator": ("H - across.maxY - max(0, bottomInset) >= SettingsPane.minPage {",
                                                             "H - across.maxY >= SettingsPane.minPage {"),
    "M10 the upper page onto the fold": ("mac = CGRect(x: centred, y: 0, width: column, height: across.minY)",
                                         "mac = CGRect(x: centred, y: 0, width: column, height: across.maxY)"),
    "M11 the lower page from the fold's top": ("device = CGRect(x: centred, y: across.maxY, width: column, height: max(0, H - across.maxY))",
                                               "device = CGRect(x: centred, y: across.minY, width: column, height: max(0, H - across.minY))"),
    # The book pose.
    "M12 the book pose ignored": ("if let down = fold.verticalBand {", "if let down = fold.verticalBand, false {"),
    "M13 the fold not mirrored right to left": ("rightToLeft ? CGRect(x: width - r.maxX, y: r.minY, width: r.width, height: r.height) : r",
                                                "r"),
    "M14 the leading column against the fold": ("mac = CGRect(x: (leadingPage - first) / 2, y: 0, width: first, height: H)",
                                                "mac = CGRect(x: leadingPage - m - first, y: 0, width: first, height: H)"),
    "M15 the trailing column from the fold's edge": ("device = CGRect(x: b.maxX + (trailingPage - second) / 2, y: 0, width: second, height: H)",
                                                     "device = CGRect(x: b.maxX, y: 0, width: second, height: H)"),
    "M16 the pages' columns without their margins": ("let first = min(SettingsPane.maxColumn, leadingPage - 2 * m)",
                                                     "let first = min(SettingsPane.maxColumn, leadingPage)"),
    "M17 narrow pages kept to": ("if first >= SettingsPane.minColumn, second >= SettingsPane.minColumn {", "if first > 0, second > 0 {"),
    "M18 the trailing page as wide as the leading": ("let leadingPage = b.minX, trailingPage = W - b.maxX", "let leadingPage = b.minX, trailingPage = b.minX"),
    # One column wherever no fold is kept to (Noah, 2026-11-23: "Settings should not be 2 columns, please make
    # it 1 column"): two columns brought back without a fold must fail the check.
    "M21 one column at the leading edge": ("mac = CGRect(x: centred, y: 0, width: column, height: H)\n            device = mac",
                                           "mac = CGRect(x: m, y: 0, width: column, height: H)\n            device = mac"),
    "M35 two columns again on a screen held sideways": ("arrangement = .oneColumn", "arrangement = W > H ? .twoColumns : .oneColumn"),
    "M36 a fold made up down the middle of every screen": ("if let down = fold.verticalBand {",
                                                          "if let down = fold.verticalBand ?? Optional(CGRect(x: W / 2 - 10, y: 0, width: 20, height: H)) {"),
    # Each scroll view across its page, the whole screen in one column, out to the screen's edges through the safe area
    # beside it (Noah, 2026-11-23: "on iPad in landscape, you have to touch the middle 3rd of the display to scroll
    # instead of anywhere on the screen"): a scroll view narrowed back to its column, short of the screen's edge, or on
    # the fold, must fail the check.
    "M37 one column's scroll view narrowed back to its column": ("macScroll = CGRect(x: -L, y: 0, width: W + L + T, height: H)",
                                                                 "macScroll = mac"),
    "M38 one column's device part in a scroll view of its own, at the column": ("deviceScroll = macScroll", "deviceScroll = device"),
    "M39 the book pose's leading scroll view narrowed to its column": ("macScroll = CGRect(x: -L, y: 0, width: leadingPage + L, height: H)",
                                                                       "macScroll = mac"),
    "M40 the book pose's trailing scroll view narrowed to its column":
        ("deviceScroll = CGRect(x: b.maxX, y: 0, width: trailingPage + T, height: H)", "deviceScroll = device"),
    "M41 the book pose's leading scroll view across the fold's band": ("macScroll = CGRect(x: -L, y: 0, width: leadingPage + L, height: H)",
                                                                       "macScroll = CGRect(x: -L, y: 0, width: b.maxX + L, height: H)"),
    "M42 the laptop pose's upper scroll view narrowed to its column":
        ("macScroll = CGRect(x: -L, y: 0, width: W + L + T, height: across.minY)", "macScroll = mac"),
    "M43 the laptop pose's lower scroll view narrowed to its column":
        ("deviceScroll = CGRect(x: -L, y: across.maxY, width: W + L + T, height: max(0, H - across.maxY))", "deviceScroll = device"),
    "M44 the laptop pose's upper scroll view onto the fold": ("macScroll = CGRect(x: -L, y: 0, width: W + L + T, height: across.minY)",
                                                              "macScroll = CGRect(x: -L, y: 0, width: W + L + T, height: across.maxY)"),
    "M45 one column's scroll view short of the safe area beside the screen":
        ("macScroll = CGRect(x: -L, y: 0, width: W + L + T, height: H)", "macScroll = CGRect(x: 0, y: 0, width: W, height: H)"),
    "M46 the leading and trailing strips swapped": ("let L = max(0, leadingInset), T = max(0, trailingInset)",
                                                    "let L = max(0, trailingInset), T = max(0, leadingInset)"),
    "M47 the book pose's trailing page's scroll view short of its strip":
        ("deviceScroll = CGRect(x: b.maxX, y: 0, width: trailingPage + T, height: H)",
         "deviceScroll = CGRect(x: b.maxX, y: 0, width: trailingPage, height: H)"),
    "M48 a page laid out in the safe area beside the screen": ("let from = max(0, scroll.minX), to = min(max(0, size.width), scroll.maxX)",
                                                                "let from = scroll.minX, to = scroll.maxX"),
    # The header.
    "M23 the header over the Mac's column only": ("arrangement == .twoColumns ? (mac.minX, device.maxX - mac.minX) : (mac.minX, mac.width)",
                                                   "(mac.minX, mac.width)"),
    "M24 the header's words across both columns": ("arrangement == .twoColumns ? max(0, mac.width - 2 * Self.headerInset) : nil",
                                                    "arrangement == .twoColumns ? max(0, device.maxX - mac.minX) : nil"),
    "M25 the header's words without its insets": ("arrangement == .twoColumns ? max(0, mac.width - 2 * Self.headerInset) : nil",
                                                   "arrangement == .twoColumns ? mac.width : nil"),
    # The bottom.
    "M26 the home indicator forgotten": ("self.bottom = max(0, bottomInset)", "self.bottom = 0"),
    "M32 Disconnect in the home indicator's room": ("arrangement == .twoPages ? SettingsPane.foldGap : max(bottom, SettingsPane.footGap)",
                                                     "arrangement == .twoPages ? SettingsPane.foldGap : SettingsPane.footGap"),
    "M33 the laptop page's Disconnect as at the screen's foot": ("arrangement == .twoPages ? SettingsPane.foldGap : max(bottom, SettingsPane.footGap)",
                                                                 "max(bottom, SettingsPane.footGap)"),
    "M34 Disconnect at the very foot without a home indicator": ("static let footGap: CGFloat = 16", "static let footGap: CGFloat = 0"),
    # iOS's own scroll edge effect off every edge of both scroll views, on every screen (2026-11-24: left on, it blurred
    # all but the last rows of the 13-inch iPad's sideways harness photos): left on, or off only where the photo showed
    # it, must fail the check.
    "M49 the system's edge effect left on": ("var systemEdgeEffectHidden: SettingsPane.Edges { .all }",
                                             "var systemEdgeEffectHidden: SettingsPane.Edges { [] }"),
    "M50 the system's edge effect off at the top alone": ("var systemEdgeEffectHidden: SettingsPane.Edges { .all }",
                                                          "var systemEdgeEffectHidden: SettingsPane.Edges { .top }"),
    "M51 the system's edge effect off on screens held sideways alone": (
        "var systemEdgeEffectHidden: SettingsPane.Edges { .all }",
        "var systemEdgeEffectHidden: SettingsPane.Edges { size.width > size.height ? .all : [] }"),
    "M52 the system's edge effect off in one column alone, not around the fold": (
        "var systemEdgeEffectHidden: SettingsPane.Edges { .all }",
        "var systemEdgeEffectHidden: SettingsPane.Edges { arrangement == .oneColumn ? .all : [] }"),
    "M53 every edge without the sides": ("static let all: Edges = [.top, .leading, .bottom, .trailing]",
                                         "static let all: Edges = [.top, .bottom]"),
    # The rows' column in its scroll view from a whole pixel (2026-11-24: half a pixel off the grid, Full Screen's footnote
    # broke a line early): off the grid, a pixel past the column's place, or the trailing margin the column's own, must fail.
    "M54 the rows' column in its scroll view off the pixel grid": (
        "let leading = scale > 0 ? (abs(pixels - pixels.rounded()) < 0.001 ? pixels.rounded() : pixels.rounded(.down)) / scale : exact",
        "let leading = exact"),
    "M55 the rows' column rounded up, past its place": ("pixels.rounded(.down)) / scale", "pixels.rounded(.up)) / scale"),
    "M56 the trailing margin from the column's own place": ("return (leading, max(0, scroll.width - leading - column.width))",
                                                            "return (leading, max(0, scroll.maxX - column.maxX))"),
    # Closing.
    "M27 the overlay puts the keyboard back":("var backToStream: Bool { self == .done || self == .harness }",
                                               "var backToStream: Bool { self == .done || self == .harness || self == .overlay }"),
    "M28 the harness's close keeps it down": ("var backToStream: Bool { self == .done || self == .harness }", "var backToStream: Bool { self == .done }"),
    "M29 the tour under the closing pane": ("var waitsForClose: Bool { self == .tour || self == .fullScreen }", "var waitsForClose: Bool { self == .fullScreen }"),
    "M30 the overlay waits": ("var waitsForClose: Bool { self == .tour || self == .fullScreen }",
                              "var waitsForClose: Bool { self == .tour || self == .fullScreen || self == .overlay }"),
    "M31 a slower close": ("static let closeSeconds: Double = 0.25", "static let closeSeconds: Double = 0.4"),
}
caught = 0
for name, (old, new) in MUTANTS.items():
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    path = os.path.join(OUT, "mutant.swift")
    open(path, "w").write(orig.replace(old, new))
    b = subprocess.run(["swiftc", "-O", path, DUO, os.path.join(SP, "main.swift"), "-o", os.path.join(OUT, "mutant")],
                       capture_output=True, text=True)
    if b.returncode != 0:
        print(f"{name}: DOES NOT COMPILE\n{b.stderr[:600]}"); continue
    r = subprocess.run([os.path.join(OUT, "mutant")], capture_output=True, text=True, timeout=600)
    failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
    ok = r.returncode != 0
    caught += ok
    print(f"{'caught' if ok else 'MISSED'} {name}: {len(failed)} failing, e.g. {[f[:110] for f in failed[:2]]}")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
