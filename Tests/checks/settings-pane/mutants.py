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
    # Each scroll view across its page, the whole screen in one column (Noah, 2026-11-23: "on iPad in landscape, you
    # have to touch the middle 3rd of the display to scroll instead of anywhere on the screen"): a scroll view
    # narrowed back to its column, or one onto the fold, must fail the check.
    "M37 one column's scroll view narrowed back to its column": ("macScroll = CGRect(x: 0, y: 0, width: W, height: H)", "macScroll = mac"),
    "M38 one column's device part in a scroll view of its own, at the column": ("deviceScroll = macScroll", "deviceScroll = device"),
    "M39 the book pose's leading scroll view narrowed to its column": ("macScroll = CGRect(x: 0, y: 0, width: leadingPage, height: H)",
                                                                       "macScroll = mac"),
    "M40 the book pose's trailing scroll view narrowed to its column": ("deviceScroll = CGRect(x: b.maxX, y: 0, width: trailingPage, height: H)",
                                                                        "deviceScroll = device"),
    "M41 the book pose's leading scroll view across the fold's band": ("macScroll = CGRect(x: 0, y: 0, width: leadingPage, height: H)",
                                                                       "macScroll = CGRect(x: 0, y: 0, width: b.maxX, height: H)"),
    "M42 the laptop pose's upper scroll view narrowed to its column": ("macScroll = CGRect(x: 0, y: 0, width: W, height: across.minY)",
                                                                       "macScroll = mac"),
    "M43 the laptop pose's lower scroll view narrowed to its column":
        ("deviceScroll = CGRect(x: 0, y: across.maxY, width: W, height: max(0, H - across.maxY))", "deviceScroll = device"),
    "M44 the laptop pose's upper scroll view onto the fold": ("macScroll = CGRect(x: 0, y: 0, width: W, height: across.minY)",
                                                              "macScroll = CGRect(x: 0, y: 0, width: W, height: across.maxY)"),
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
    # Closing.
    "M27 the overlay puts the keyboard back": ("var backToStream: Bool { self == .done || self == .harness }",
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
