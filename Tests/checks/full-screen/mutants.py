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
    # EdgeFlick: the band, the travel, the duration, the direction, the speed, the edge.
    "F1 the band's edge left out": ("if x > Self.band { verdict = .notAFlick(.outsideBand) }", "if x >= Self.band { verdict = .notAFlick(.outsideBand) }"),
    "F2 no band": ("        if x > Self.band { verdict = .notAFlick(.outsideBand) }\n", ""),
    "F3 the travel's edge left out": ("if left < travel { return .notAFlick(.tooShort) }", "if left <= travel { return .notAFlick(.tooShort) }"),
    "F4 no travel": ("        if left < travel { return .notAFlick(.tooShort) }\n", ""),
    "F5 the duration's edge at the lift left out": ("if last.t - first.t > duration { return .notAFlick(.tooLong) }",
                                                    "if last.t - first.t >= duration { return .notAFlick(.tooLong) }"),
    "F6 no duration at the lift": ("        if last.t - first.t > duration { return .notAFlick(.tooLong) }\n", ""),
    "F7 the right slop's edge let through": ("if dx >= rightSlop { return .movedRight }", "if dx > rightSlop { return .movedRight }"),
    "F8 no right test before the lift": ("        if dx >= rightSlop { return .movedRight }\n", ""),
    "F9 steeper allowed": ("static let steepness: Double = 1.2", "static let steepness: Double = 2.0"),
    "F10 direction judged from the first point": ("if hypot(dx, dy) >= judgeAfter, abs(dy) > steepness", "if abs(dy) > steepness"),
    "F11 no steepness at the lift": ("        if abs(dy) > steepness * left { return .notAFlick(.steep) }\n", ""),
    "F12 the speed's edge left out": ("if v < speed { return .notAFlick(.tooSlow) }", "if v <= speed { return .notAFlick(.tooSlow) }"),
    "F13 no speed test": ("        if v < speed { return .notAFlick(.tooSlow) }\n", ""),
    "F14 the reach's edge left out": ("if last.x <= reach || last.x - v * projection <= 0 { return .hide }",
                                      "if last.x < reach || last.x - v * projection <= 0 { return .hide }"),
    "F15 no projection": ("if last.x <= reach || last.x - v * projection <= 0 { return .hide }", "if last.x <= reach { return .hide }"),
    "F16 the projection backwards": ("|| last.x - v * projection <= 0 {", "|| last.x + v * projection <= 0 {"),
    "F17 the speed over the whole stroke": ("        if first.t >= since {\n", "        if true {\n"),
    "F17b the window from the sample before it (a rest reads slow)": (
        "        let x = span > 0 ? before.x + (after.x - before.x) * ((since - before.t) / span) : before.x\n        return (x - last.x) / speedWindow",
        "        return (before.x - last.x) / (last.t - before.t)"),
    "F17c the window from the sample after it": (
        "        let x = span > 0 ? before.x + (after.x - before.x) * ((since - before.t) / span) : before.x",
        "        let x = after.x"),
    "F18 a second finger ignored": ("        if verdict == .undecided { verdict = .notAFlick(.secondTouch) }\n", ""),
    "F19 a cancel ignored": ("        if verdict == .undecided { verdict = .notAFlick(.cancelled) }\n", ""),
    "F20 a still finger never let go": ("if verdict == .undecided, let first = samples.first, t - first.t > Self.duration {",
                                        "if verdict == .undecided, let first = samples.first, t - first.t > 10 * Self.duration {"),
    "F21 a verdict can change at the lift": ("    mutating func ended(x: Double, y: Double, t: Double) -> Verdict {\n        guard verdict == .undecided, let first",
                                             "    mutating func ended(x: Double, y: Double, t: Double) -> Verdict {\n        guard let first"),
    "F22 a hide before the lift": ("        } else if let why = Self.wrongWay(from: first, to: Sample(x: x, y: y, t: t)) {\n            verdict = .notAFlick(why)\n        }",
                                   "        } else if let why = Self.wrongWay(from: first, to: Sample(x: x, y: y, t: t)) {\n            verdict = .notAFlick(why)\n        } else if x <= Self.reach, first.x - x >= Self.travel {\n            verdict = .hide\n        }"),
    "F23 the moves' clock ignored": ("        if t - first.t > Self.duration {\n            verdict = .notAFlick(.tooLong)\n        } else if let why",
                                     "        if false {\n            verdict = .notAFlick(.tooLong)\n        } else if let why"),
    # EdgeFlickGate.
    "G1 a Pencil judged": ("direct && alreadyDown == 0", "alreadyDown == 0"),
    "G2 beside another finger": ("direct && alreadyDown == 0", "direct"),
    # EdgeReveal.
    "R1 half the width, not a third": ("static let share: Double = 1.0 / 3", "static let share: Double = 1.0 / 2"),
    "R2 no coast": ("return translation + coast * max(velocity, 0) >= share * width", "return translation >= share * width"),
    "R3 no flick in": ("        if velocity >= flickSpeed, translation >= flickTravel { return true }\n", ""),
    "R4 the back speed's edge left out": ("if velocity <= -backSpeed { return false }", "if velocity < -backSpeed { return false }"),
    "R5 no back speed": ("        if velocity <= -backSpeed { return false }\n", ""),
    "R6 progress below nothing": ("return min(max(translation / width, 0), 1)", "return min(translation / width, 1)"),
    "R7 progress past the whole": ("return min(max(translation / width, 0), 1)", "return max(translation / width, 0)"),
    "R8 the flick's travel left out": ("if velocity >= flickSpeed, translation >= flickTravel { return true }", "if velocity >= flickSpeed { return true }"),
    # EdgeDwell.
    "D1 a Pencil counts": ("guard !pencil, x <= Self.edge else {", "guard x <= Self.edge else {"),
    "D2 the dwell's edge left out": ("guard let since, !fired, t - since >= Self.dwell else { return false }",
                                     "guard let since, !fired, t - since > Self.dwell else { return false }"),
    "D3 more than once a stay": ("guard let since, !fired, t - since >= Self.dwell else { return false }",
                                 "guard let since, t - since >= Self.dwell else { return false }"),
    "D4 a wider edge": ("static let edge: Double = 1", "static let edge: Double = 2"),
    "D5 the end forgets nothing": ("    mutating func ended() {\n        since = nil\n        fired = false\n    }", "    mutating func ended() {\n    }"),
    # When, where.
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
    "P9 the flick under VoiceOver": ("level == .shown && !voiceOver && hideAllowed(s)", "level == .shown && hideAllowed(s)"),
    "P10 the flick while hidden": ("level == .shown && !voiceOver && hideAllowed(s)", "!voiceOver && hideAllowed(s)"),
    "P11 the hint four times": ("static let hintTimes = 3", "static let hintTimes = 4"),
    "P12 the hint never forced": ("forced || shownBefore < hintTimes", "shownBefore < hintTimes"),
    "P13 clear of the home indicator too": ("            top = insets.top; left = insets.left; right = insets.right\n        case .safeArea:",
                                            "            top = insets.top; left = insets.left; right = insets.right; bottom = insets.bottom\n        case .safeArea:"),
    "P14 the fold ignored": ("        if let foldTop, foldTop > rect.minY, foldTop < rect.maxY {\n            rect.size.height = foldTop - rect.minY\n        }\n", ""),
    "P15 a room below nothing": ("width: max(0, size.width - left - right), height: max(0, size.height - top - bottom)",
                                 "width: size.width - left - right, height: size.height - top - bottom"),
    "P16 the screen choice clear of the housing": ("        case .screen: break\n", "        case .screen: top = insets.top; left = insets.left; right = insets.right\n"),
    "P17 the status bar's inset counted": ("        if topIsStatusBar { top = 0 }\n", ""),
    "L1 a flick leads nowhere": ("var afterFlick: ChromeLevel { .hidden }", "var afterFlick: ChromeLevel { .shown }"),
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
