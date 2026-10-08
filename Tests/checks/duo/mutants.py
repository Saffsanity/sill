"""Mutants of iOSClient/DuoPosture.swift (docs/iphone-duo-plan.md): each changes it in one place and must
fail the check (main.swift). usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "duo")          # the mutants' sources and binaries
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/DuoPosture.swift")
orig = open(SRC).read()
MUTANTS = {
    # The posture.
    "M1 the fold in the way open flat too": ("var foldActive: Bool { hinge == .partiallyOpen && fold != nil }",
                                             "var foldActive: Bool { hinge != .closed && fold != nil }"),
    "M2 known without a hinge": ("guard hinge != .unknown else { return .inferred }", "guard hinge != .closed else { return .inferred }"),
    "M3 the band not clipped": ("let band = fold.intersection(CGRect(origin: .zero, size: size))", "let band = fold"),
    "M4 a fold off the screen kept": ("return .known(band.isNull || band.isEmpty ? nil : band)", "return .known(band.isNull ? nil : band)"),
    "M5 the book pose upright": ("case .partiallyOpen: return sideways ? .book : .laptop", "case .partiallyOpen: return sideways ? .laptop : .book"),
    "M6 the cover's poses swapped": ("case .closed: return sideways ? .closedSide : .closedUpright", "case .closed: return sideways ? .closedUpright : .closedSide"),
    "M7 the status bar hidden on the cover": ("pose == .laptop || pose == .flatPortrait\n    }",
                                              "pose == .laptop || pose == .flatPortrait || pose == .closedUpright\n    }"),
    "M7b the status bar hidden sideways too": ("pose == .laptop || pose == .flatPortrait\n    }",
                                               "pose == .laptop || pose == .flatPortrait || pose == .book\n    }"),
    "M7c the status bar shown open flat upright": ("pose == .laptop || pose == .flatPortrait\n    }", "pose == .laptop\n    }"),
    "M7d the inner display closed": ("var onInnerDisplay: Bool { hinge == .partiallyOpen || hinge == .fullyOpen }",
                                     "var onInnerDisplay: Bool { hinge != .unknown }"),
    "M7e no fold before the first report": ("guard reported == .unknown, let regionActive else { return reported }",
                                            "guard reported == .unknown, let regionActive, false else { return reported }"),
    "M7f the fold over a report": ("guard reported == .unknown, let regionActive else { return reported }",
                                   "guard let regionActive else { return reported }"),
    "M7g an active fold read as flat": ("return regionActive ? .partiallyOpen : .fullyOpen", "return regionActive ? .fullyOpen : .partiallyOpen"),
    "M8 a vertical fold read as across": ("guard let band, band.width >= band.height else { return nil }", "guard let band else { return nil }"),
    "M9 a fold across read as vertical": ("guard let band, band.height > band.width else { return nil }", "guard let band, band.height >= band.width else { return nil }"),
    # The crease, as before iOS 27.1, and the laptop pose's.
    "M10 the inferred crease to 750 pt wide": ("size.width >= 600, size.width < 740, size.height < 1100", "size.width >= 600, size.width < 750, size.height < 1100"),
    "M11 the inferred crease rounded": ("return (size.height / 2, size.height / 2)", "return ((size.height / 2).rounded(), (size.height / 2).rounded())"),
    "M12 the laptop pose's crease at the fold's middle": ("return (band.minY, band.maxY)", "return (band.midY, band.midY)"),
    # The halves' split.
    "M13 the inferred halves unrounded": ("let half = (size.height / 2).rounded()", "let half = size.height / 2"),
    "M14 the laptop pose split at the middle": ("if let band = fold.horizontalBand {\n                let top", "if let band = fold.horizontalBand, false {\n                let top"),
    "M15 the picture rounded into the fold": ("let top = max(0, band.minY.rounded(.down))", "let top = max(0, band.minY.rounded(.up))"),
    "M16 the controls on the fold": ("let bottom = min(size.height, band.maxY.rounded(.up))", "let bottom = min(size.height, band.minY.rounded(.up))"),
    "M17 the flat pane without its inset": ("let natural = (pictureWidth / max(aspect, 0.1)).rounded() + 2 * paneInset",
                                            "let natural = (pictureWidth / max(aspect, 0.1)).rounded()"),
    "M18 the flat pane past the trackpad's least": ("let most = max(0, size.height - controls - minimumTrackpad)", "let most = max(0, size.height - controls)"),
    "M19 no least pane": ("let least = min(minimumPane, most)", "let least: CGFloat = 0"),
    "M20 the picture's width without the inset": ("let pictureWidth = max(0, size.width - 2 * paneInset)", "let pictureWidth = max(0, size.width)"),
    "M21 the flat pane unrounded": ("(pictureWidth / max(aspect, 0.1)).rounded()", "(pictureWidth / max(aspect, 0.1))"),
    "M22 the least trackpad 100": ("static let minimumTrackpad: CGFloat = 200", "static let minimumTrackpad: CGFloat = 100"),
    "M23 16:9 for no picture": ("static let defaultAspect: CGFloat = 1.6", "static let defaultAspect: CGFloat = 16.0 / 9.0"),
    "M24 the pane follows a fitted window": ("guard !fitsWindowToPane, video.width > 0", "guard video.width > 0"),
    "M25 the picture's shape upside down": ("return video.width / video.height", "return video.height / video.width"),
    # The connect screen's room above the laptop pose's fold.
    "M45b the inferred crease bounds the column": ("guard case .known = fold, let crease = crease(size, fold) else { return nil }",
                                                   "guard let crease = crease(size, fold) else { return nil }"),
    "M45c the room to the fold's bottom": ("        return max(0, crease.top)\n", "        return max(0, crease.bottom)\n"),
    # The book pose's bar.
    "M26 no compact step": ("if start(button, g) < band.maxX { button = min(button, compactButtonWidth) }", "if false { button = min(button, compactButtonWidth) }"),
    "M27 the compact step always": ("if start(button, g) < band.maxX { button = min(button, compactButtonWidth) }", "button = min(button, compactButtonWidth)"),
    "M28 no smaller gaps": ("g = max(minimumGap, min(g, room))", "g = max(minimumGap, g)"),
    "M29 gaps below the least": ("g = max(minimumGap, min(g, room))", "g = min(g, room)"),
    "M30 the gap rounded up": ("/ (count - 1)).rounded(.down)", "/ (count - 1)).rounded(.up)"),
    "M31 the strip onto the fold": ("let strip = max(0, band.minX - g - stripStart)", "let strip = max(0, band.maxX - g - stripStart)"),
    "M32 the strip from the bar's edge": ("let stripStart = padding + button + g          // after Apps", "let stripStart = padding"),
    "M33 the panel onto the fold": ("let panel = min(panelWidth, max(0, width - padding - band.maxX))", "let panel = panelWidth"),
    "M34 clears always": ("clears: start(button, g) >= band.maxX)", "clears: true)"),
    "M35 a fold at the bar's end taken": ("band.minX > padding, band.maxX < width - padding else { return unchanged }",
                                          "band.maxX < width - padding else { return unchanged }"),
    "M36 a fold across taken for the book's": ("guard let band = fold.verticalBand, buttons > 0,", "guard let band = fold.band, buttons > 0,"),
    # One page.
    "M37 a card left across the fold": ("guard let band = fold.verticalBand, x < band.maxX, x + width > band.minX else { return x }",
                                        "guard let band = fold.verticalBand, false, x < band.maxX else { return x }"),
    "M38 the leading page ignores the margin": ("let leadingFits = width <= band.minX - margin", "let leadingFits = width <= band.minX"),
    "M39 the trailing page left across": ("let leading = band.minX - width, trailing = band.maxX", "let leading = band.minX - width, trailing = x"),
    "M39b the leading page with a margin from the fold": ("let leading = band.minX - width, trailing = band.maxX", "let leading = band.minX - width - margin, trailing = band.maxX"),
    "M40 a tie to the trailing page": ("if x + width / 2 <= band.midX {", "if x + width / 2 < band.midX {"),
    "M41 the other page never tried": ("            if trailingFits { return trailing }\n        } else {", "        } else {"),
    "M42 the page as wide as the screen": ("return max(0, max(band.minX - margin, screenWidth - margin - band.maxX))", "return max(0, screenWidth - 2 * margin)"),
    "M43 the column on a page without its margins": ("guard let band = fold.verticalBand, columnWidth + 32 <= band.minX else { return centred }",
                                                      "guard let band = fold.verticalBand, columnWidth <= band.minX else { return centred }"),
    "M44 the column at the page's edge": ("return max(16, (band.minX - columnWidth) / 2)", "return 16"),
    "M45 the leading page for a fold across": ("fold.verticalBand.map { max(0, $0.minX) }", "fold.band.map { max(0, $0.minX) }"),
    # The window lights' menu.
    "M50 the lights left on the laptop pose's fold": ("if !down, let band = fold.horizontalBand, rect(below: false).intersects(band) { down = true }",
                                                      "if false, let band = fold.horizontalBand, rect(below: false).intersects(band) { down = true }"),
    "M51 the lights flipped wherever a fold is": ("if !down, let band = fold.horizontalBand, rect(below: false).intersects(band) { down = true }",
                                                  "if !down, fold.horizontalBand != nil { down = true }"),
    "M52 the lights left across the book pose's fold": ("let left = offTheFold(x: x - size.width / 2, width: size.width, screenWidth: screenWidth, margin: 8, fold: fold)",
                                                        "let left = x - size.width / 2"),
    "M53 the lights' gap dropped": ("y: below ? thumbnail.maxY + gap : thumbnail.minY - gap - size.height,", "y: below ? thumbnail.maxY : thumbnail.minY - gap - size.height,"),
    # The harness.
    "M46 half for flat": ('case "flat"?: return .fullyOpen', 'case "flat"?: return .partiallyOpen'),
    "M47 the stand-in 30 pt": ("CGRect(x: size.width / 2 - 20, y: 0, width: 40, height: size.height)", "CGRect(x: size.width / 2 - 15, y: 0, width: 30, height: size.height)"),
    "M48 the cover's strip on the right on its side": ("case (678, 466): return (0, 84, 34, 0)", "case (678, 466): return (0, 0, 34, 84)"),
    "M49 the inner display's status bar at the top sideways": ("case (951, 669): return statusBarHidden ? (0, 0, 34, 0) : (0, 0, 34, 84)",
                                                               "case (951, 669): return statusBarHidden ? (0, 0, 34, 0) : (84, 0, 34, 0)"),
    "M49b the status bar never hidden upright": ("case (669, 951): return statusBarHidden ? (0, 0, 34, 0) : (82, 0, 34, 0)",
                                                 "case (669, 951): return (82, 0, 34, 0)"),
    "M49c the cover's strip gone with the status bar": ("case (466, 678): return (0, 0, 34, 84)", "case (466, 678): return statusBarHidden ? (0, 0, 34, 0) : (0, 0, 34, 84)"),
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
    failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
    ok = r.returncode != 0
    caught += ok
    print(f"{'caught' if ok else 'MISSED'} {name}: {len(failed)} failing, e.g. {[f[:110] for f in failed[:2]]}")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
