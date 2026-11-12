"""Each mutant changes iOSClient/FullScreenPolicy.swift in one place and must fail the check (main.swift).
usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))
OUT = os.path.join(ROOT, ".build", "checks", "full-screen")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/FullScreenPolicy.swift")
orig = open(SRC).read()
MUTANTS = {
    # EdgeSwipe: the band, the judging distance, the direction, the clock, a second finger, the lift.
    "S1 the band's edge left out": ("else if x > band { verdict = .notASwipe(.outsideBand) }", "else if x >= band { verdict = .notASwipe(.outsideBand) }"),
    "S2 no band": ("else if x > band { verdict = .notASwipe(.outsideBand) }", "else if false { verdict = .notASwipe(.outsideBand) }"),
    "S3 a narrower band": ("    static let band: Double = 24\n", "    static let band: Double = 16\n"),
    "S4 the left inset ignored": ("static func reach(leftInset: Double) -> Double { max(band, leftInset) }", "static func reach(leftInset: Double) -> Double { band }"),
    "S5 beside another finger": ("if !alone { verdict = .notASwipe(.secondTouch) } else if", "if false { verdict = .notASwipe(.secondTouch) } else if"),
    "S6 judged sooner": ("    static let judgeAfter: Double = 8\n", "    static let judgeAfter: Double = 4\n"),
    "S7 judged later": ("    static let judgeAfter: Double = 8\n", "    static let judgeAfter: Double = 12\n"),
    "S8 the judging edge left out": ("guard max(abs(dx), abs(dy)) >= Self.judgeAfter else { return verdict }", "guard max(abs(dx), abs(dy)) > Self.judgeAfter else { return verdict }"),
    "S9 judged by x alone": ("guard max(abs(dx), abs(dy)) >= Self.judgeAfter else { return verdict }", "guard abs(dx) >= Self.judgeAfter else { return verdict }"),
    "S10 leftward taken": ("if dx <= 0 { verdict = .notASwipe(.notRightward) } else if", "if false { verdict = .notASwipe(.notRightward) } else if"),
    "S11 steeper taken": ("else if abs(dy) > dx { verdict = .notASwipe(.steep) }", "else if abs(dy) > 2 * dx { verdict = .notASwipe(.steep) }"),
    "S12 45 degrees let go": ("else if abs(dy) > dx { verdict = .notASwipe(.steep) }", "else if abs(dy) >= dx { verdict = .notASwipe(.steep) }"),
    "S13 no clock while moving": ("if t - landing.t > Self.decideWithin { verdict = .notASwipe(.tooLong); return verdict }", "if false { verdict = .notASwipe(.tooLong); return verdict }"),
    "S14 a still finger held for good": ("if verdict == .undecided, let landing, t - landing.t > Self.decideWithin { verdict = .notASwipe(.tooLong) }",
                                         "if verdict == .undecided, let landing, t - landing.t > 10 * Self.decideWithin { verdict = .notASwipe(.tooLong) }"),
    "S15 held past a long press": ("    static let decideWithin: Double = 0.3\n", "    static let decideWithin: Double = 0.5\n"),
    "S16 a second finger ignored": ("        if verdict == .undecided { verdict = .notASwipe(.secondTouch) }\n", ""),
    "S17 a cancel ignored": ("        if verdict == .undecided { verdict = .notASwipe(.cancelled) }\n", ""),
    "S18 a lift kept undecided": ("        last = (x, y, t)\n        verdict = .notASwipe(.lifted)\n", "        last = (x, y, t)\n"),
    "S19 a verdict can change": ("    mutating func moved(x: Double, y: Double, t: Double) -> Verdict {\n        guard verdict == .undecided, let landing",
                                 "    mutating func moved(x: Double, y: Double, t: Double) -> Verdict {\n        guard let landing"),
    # EdgeReveal: the distance, the coast, the flick in, moving back, the progress.
    "R1 a third of the width again": ("static func distance(width: Double) -> Double { min(share * width, pull) }", "static func distance(width: Double) -> Double { share * width }"),
    "R2 a longer pull": ("    static let pull: Double = 80\n", "    static let pull: Double = 120\n"),
    "R3 no coast": ("return translation + coast * max(velocity, 0) >= distance(width: width)", "return translation >= distance(width: width)"),
    "R4 no flick in": ("        if velocity >= flickSpeed, translation >= flickTravel { return true }\n", ""),
    "R5 the flick in at 400 again": ("    static let flickSpeed: Double = 300\n", "    static let flickSpeed: Double = 400\n"),
    "R6 the flick's travel left out": ("if velocity >= flickSpeed, translation >= flickTravel { return true }", "if velocity >= flickSpeed { return true }"),
    "R7 the back speed's edge left out": ("if velocity <= -backSpeed { return false }", "if velocity < -backSpeed { return false }"),
    "R8 no back speed": ("        if velocity <= -backSpeed { return false }\n", ""),
    "R9 progress below nothing": ("return min(max(translation / width, 0), 1)", "return min(translation / width, 1)"),
    "R10 progress past the whole": ("return min(max(translation / width, 0), 1)", "return max(translation / width, 0)"),
    # RevealCut: the margin, the rim, each side.
    "C1 a black strip under the bar": ("static func landscape(barHeight: CGFloat) -> Place { .under(barHeight) }",
                                       "static func landscape(barHeight: CGFloat) -> Place { .under(barHeight + 6) }"),
    "C2 the laptop pose's fold left black": ("static func halves(_ split: DuoPosture.PortraitSplit) -> Place { .over(split.controls) }",
                                             "static func halves(_ split: DuoPosture.PortraitSplit) -> Place { .over(split.picture) }"),
    "C3 the halves' pane margin left": ("static func halves(_ split: DuoPosture.PortraitSplit) -> Place { .over(split.controls) }",
                                       "static func halves(_ split: DuoPosture.PortraitSplit) -> Place { .over(split.controls - DuoPosture.paneInset) }"),
    "C4 no black above a phone's row 1": ("static func phone(_ layout: PhonePortraitLayout) -> Place { .over(layout.picture.maxY) }",
                                          "static func phone(_ layout: PhonePortraitLayout) -> Place { .over(layout.row1.minY) }"),
    "C5 the hole sized from the video": ("static func phone(_ layout: PhonePortraitLayout) -> Place { .over(layout.picture.maxY) }",
                                         "static func phone(_ layout: PhonePortraitLayout) -> Place { .over(layout.pane(video: CGSize(width: 3440, height: 1440)).maxY) }"),
    "C6 the cut short of the left edge": ("return CGRect(x: 0, y: top, width: size.width, height: size.height - top)",
                                          "return CGRect(x: 8, y: top, width: size.width - 8, height: size.height - top)"),
    "C7 the cut short of the right edge": ("return CGRect(x: 0, y: 0, width: size.width, height: bottom)",
                                           "return CGRect(x: 0, y: 0, width: size.width - 8, height: bottom)"),
    "C8 a bar's line past the preview kept": ("let top = min(max(line, 0), size.height)", "let top = max(line, 0)"),
    "C9 a line above the preview kept": ("let bottom = min(max(line, 0), size.height)", "let bottom = min(line, size.height)"),
    "C10 a preview with no height cut": ("        guard size.width > 0, size.height > 0 else { return .zero }\n        switch place {\n        case .under(let line):",
                                         "        guard size.width > 0 else { return .zero }\n        switch place {\n        case .under(let line):"),
    "C11 the bar's band short of the cut": ("case .under: return CGRect(x: 0, y: 0, width: size.width, height: cut.minY)",
                                            "case .under: return CGRect(x: 0, y: 0, width: size.width, height: cut.minY - 2)"),
    "C12 the controls' band from the top": ("case .over: return CGRect(x: 0, y: cut.maxY, width: size.width, height: size.height - cut.maxY)",
                                            "case .over: return CGRect(x: 0, y: 0, width: size.width, height: size.height)"),
    # EdgeDwell.
    "D1 a Pencil counts": ("guard !pencil, x <= Self.edge else {", "guard x <= Self.edge else {"),
    "D2 the dwell's edge left out": ("guard let since, !fired, t - since >= Self.dwell else { return false }",
                                     "guard let since, !fired, t - since > Self.dwell else { return false }"),
    "D3 more than once a stay": ("guard let since, !fired, t - since >= Self.dwell else { return false }",
                                 "guard let since, t - since >= Self.dwell else { return false }"),
    "D4 a wider edge": ("static let edge: Double = 1", "static let edge: Double = 2"),
    "D5 the end forgets nothing": ("    mutating func ended() {\n        since = nil\n        fired = false\n    }", "    mutating func ended() {\n    }"),
    # When, where, the shake and the rows.
    "P1 offered within no tolerance": ("abs(window.minX - screen.minX) <= 0.5 && abs(window.minY - screen.minY) <= 0.5",
                                       "abs(window.minX - screen.minX) <= 0 && abs(window.minY - screen.minY) <= 0"),
    "P2 offered by the far corner alone": ("return abs(window.minX - screen.minX) <= 0.5 && abs(window.minY - screen.minY) <= 0.5\n            && ",
                                           "return "),
    "P3 the tour no reason": ("        if s.tour { return .tour }\n", ""),
    "P4 the window no reason": ("        if !s.coversScreen { return .window }\n", ""),
    "P5 nothing streaming no reason": ("        if !s.streaming { return .nothingStreams }\n", ""),
    "P6 the Mac's cover no reason": ("        if s.lockCover { return .locked }\n", ""),
    "P7 the order turned": ("        if s.tour { return .tour }\n        if s.pairing { return .pairing }\n",
                            "        if s.pairing { return .pairing }\n        if s.tour { return .tour }\n"),
    "P8 a hide over something open": ("mustShow(s) == nil && !s.somethingOpen", "mustShow(s) == nil"),
    "P9 a shake with the switch off": ("static func shakeShows(_ level: ChromeLevel, switchOn: Bool) -> Bool { level != .shown && switchOn }",
                                       "static func shakeShows(_ level: ChromeLevel, switchOn: Bool) -> Bool { level != .shown }"),
    "P10 a shake while shown": ("static func shakeShows(_ level: ChromeLevel, switchOn: Bool) -> Bool { level != .shown && switchOn }",
                                "static func shakeShows(_ level: ChromeLevel, switchOn: Bool) -> Bool { switchOn }"),
    "P11 Shake to Undo off for good": ("static func shakeToUndoOff(_ level: ChromeLevel, switchOn: Bool) -> Bool { shakeShows(level, switchOn: switchOn) }",
                                       "static func shakeToUndoOff(_ level: ChromeLevel, switchOn: Bool) -> Bool { true }"),
    "P12 the rows always in This iPad": ("macSettingsShown ? .afterFrameRate : .thisDevice", ".thisDevice"),
    "P13 the hint four times": ("static let hintTimes = 3", "static let hintTimes = 4"),
    "P14 the hint never forced": ("forced || shownBefore < hintTimes", "shownBefore < hintTimes"),
    "P15 clear of the home indicator too": ("            top = insets.top; left = insets.left; right = insets.right\n        case .safeArea:",
                                            "            top = insets.top; left = insets.left; right = insets.right; bottom = insets.bottom\n        case .safeArea:"),
    "P16 the fold ignored": ("        if let foldTop, foldTop > rect.minY, foldTop < rect.maxY {\n            rect.size.height = foldTop - rect.minY\n        }\n", ""),
    "P17 a room below nothing": ("width: max(0, size.width - left - right), height: max(0, size.height - top - bottom)",
                                 "width: size.width - left - right, height: size.height - top - bottom"),
    "P18 the screen choice clear of the housing": ("        case .screen: break\n", "        case .screen: top = insets.top; left = insets.left; right = insets.right\n"),
    "P19 the status bar's inset counted": ("        if topIsStatusBar { top = 0 }\n", ""),
    "W1 the shake's words without the device": ('static func shakeFootnote(device: String) -> String { "Shaking your \\(device) brings the controls back too." }',
                                                'static func shakeFootnote(device: String) -> String { "Shaking your device brings the controls back too." }'),
    "L1 Full Screen leads nowhere": ("var afterHide: ChromeLevel { .hidden }", "var afterHide: ChromeLevel { .shown }"),
}
caught = 0
for name, (old, new) in MUTANTS.items():
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    path = os.path.join(OUT, "mutant.swift")
    open(path, "w").write(orig.replace(old, new))
    b = subprocess.run(["swiftc", "-O", path, os.path.join(ROOT, "iOSClient/DuoPosture.swift"),
                        os.path.join(ROOT, "iOSClient/PhonePortraitLayout.swift"), os.path.join(SP, "main.swift"),
                        "-o", os.path.join(OUT, "mutant")],
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
