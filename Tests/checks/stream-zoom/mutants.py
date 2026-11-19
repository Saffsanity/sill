"""Mutants of StreamZoom.swift (iOSClient): each changes it in one place and must make the check (main.swift)
fail. Z1-Z7 are the pull request's own (#196, addhumal), on the zoom's arithmetic. usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "stream-zoom")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/StreamZoom.swift")
orig = open(SRC).read()
MUTANTS = [
    # The zoom.
    ("Z1 at most 4× instead of 5×", "static let maxScale: CGFloat = 5", "static let maxScale: CGFloat = 4"),
    ("Z2 a slight pinch out snaps back to the whole picture (under 1.6×)", "if nextScale <= Self.minScale + 0.001 {", "if nextScale <= 1.6 {"),
    ("Z3 a pinch step ignores the midpoint (no anchor)", "let rawX = (to.x - cx) - (from.x - cx - offset.width) * ratio",
     "let rawX = offset.width * ratio"),
    ("Z4 the offset not kept inside the pane across", "width: min(maxX, max(-maxX, rawX)),", "width: rawX,"),
    ("Z5 the offset not kept inside the pane down", "height: min(maxY, max(-maxY, rawY))\n        )", "height: rawY\n        )"),
    ("Z6 a touch mapped back without the offset", "x: cx + (point.x - cx - offset.width) / s,", "x: cx + (point.x - cx) / s,"),
    ("Z7 a scroll's movement multiplied by the zoom", "CGPoint(x: delta.x / s, y: delta.y / s)", "CGPoint(x: delta.x * s, y: delta.y * s)"),
    ("Z8 zoomedPoint without the offset", "return CGPoint(x: cx + (point.x - cx) * scale + offset.width,", "return CGPoint(x: cx + (point.x - cx) * scale,"),
    ("Z9 reaching 1× keeps the offset (the whole picture off-centre)", "    mutating func reset() {\n        scale = Self.minScale\n        offset = .zero\n    }",
     "    mutating func reset() {\n        scale = Self.minScale\n    }"),
    ("Z10 the lift's settle always gives the whole picture", "if scale < Self.wholeBelow { reset() }", "reset()"),
    ("Z11 the lift's settle never does", "if scale < Self.wholeBelow { reset() }", "_ = scale"),
    ("Z12 the settle's band 1.2 (a slight pinch out from 1.15× snaps)", "static let wholeBelow: CGFloat = 1.02", "static let wholeBelow: CGFloat = 1.2"),
    ("Z13 another pane resets the zoom", "        guard isZoomed, pane.width > 0, pane.height > 0, pane != size else { return }\n",
     "        guard isZoomed, pane.width > 0, pane.height > 0, pane != size else { return }\n        reset(); return\n"),
    ("Z14 another pane keeps the offset as it was (another point at the middle)", "offset.width * size.width / pane.width", "offset.width"),
    ("Z15 the visible part as big as the pane", "return CGRect(x: origin.x, y: origin.y, width: size.width / s, height: size.height / s)",
     "return CGRect(x: origin.x, y: origin.y, width: size.width, height: size.height)"),
    # The stroke.
    ("S1 two fingers on a zoomed picture not the picture's at once", "            if owner == .undecided, self.target == .picture, zoom.isZoomed { owner = .picture }\n", ""),
    ("S2 the pan's start always the Mac's (a pinch whose midpoint moved scrolls)",
     "                if pinched > travel {\n                    owner = target == .picture ? .picture : .macPinch\n                    if owner == .macPinch { macStep(to: [a, b]) }\n                    return\n                }\n", ""),
    ("S3 a pinch judged by its spacing alone (a drifting scroll zooms)", "guard pinched >= Self.pinchTravel, pinched > travel else { return false }",
     "guard pinched >= Self.pinchTravel else { return false }"),
    ("S4 every two-finger move a pinch (no travel to make one)", "static let pinchTravel: CGFloat = 12", "static let pinchTravel: CGFloat = 0"),
    ("S5 no catch-up from where the fingers landed", "owner = target == .picture ? .picture : .macPinch   // a pinch: caught up from where the pair landed (pairLast == pairFrom)",
     "owner = target == .picture ? .picture : .macPinch; pairLast = [a, b]; return false"),
    ("S6 a pinch's finger lifting gives the stroke back (the other one can scroll the Mac)",
     "                pairLast = []\n                if owner == .picture, at.count == 2 { formPair() }",
     "                pairLast = []\n                owner = .undecided"),
    ("S7 three fingers leave the zoom a pinch made", "            zoom = before\n            return true", "            return false"),
    ("S8 three fingers put back a zoom something else changed", "guard was == .picture, let before, let made, zoom == made, before != zoom else { return false }",
     "guard was == .picture, let before, before != zoom else { return false }"),
    ("S9 a stroke never ends (the next starts with its owner)", "            let ended = owner\n            self = Stroke()\n",
     "            let ended = owner\n"),
    ("S10 no settle at a picture stroke's end", "            let before = zoom\n            zoom.settle()\n            return zoom != before",
     "            return false"),
    ("S11 the picture's stroke scrolls the Mac too", "var scrollsMac: Bool { owner == .mac || owner == .none }", "var scrollsMac: Bool { owner != .gesture }"),
    ("S12 a pan with no finger seen leaves the Mac's owner behind", "            guard owner == .undecided else { return }\n            if pair.count == 2",
     "            guard owner == .undecided || owner == .none else { return }\n            if pair.count == 2"),
    ("S13 a tie at the pan's start the picture's", "                if pinched > travel {", "                if pinched >= travel {"),
    ("S14 a Mac's stroke joined by a second finger makes the pair (a scroll that spreads zooms)",
     "guard owner == .undecided || owner == .picture || owner == .macPinch, pair.count < 2, at.count == 2 else { return }",
     "guard pair.count < 2, at.count == 2 else { return }; if owner == .mac { owner = .picture }"),
    ("S15 one of a pair lifting and another landing: no new pair", "                if owner == .picture, at.count == 2 { formPair() }\n", ""),
    # The stroke under Zoom on ‹Mac› (PR #261; Stroke.Target, the Mac's own pinch and turn).
    ("M1 the turn never decides a stroke (Rotate on turns nothing until the fingers spread)",
     "                let pinched = max(spacing, target.turns ? Self.turnTravel(from: pairFrom, to: [a, b]) : 0)\n                guard pinched",
     "                let pinched = spacing\n                guard pinched"),
    ("M2 the turn decides a stroke with Rotate off too",
     "                let pinched = max(spacing, target.turns ? Self.turnTravel(from: pairFrom, to: [a, b]) : 0)\n                guard pinched",
     "                let pinched = max(spacing, Self.turnTravel(from: pairFrom, to: [a, b]))\n                guard pinched"),
    ("M3 the Mac's pinch zooms the picture instead", "owner = target == .picture ? .picture : .macPinch   // a pinch:", "owner = .picture   // a pinch:"),
    ("M4 the Mac's pinch never opens", "} else if landed >= Self.minSpacing, abs(spacing - landed) >= Self.pinchTravel {", "} else if false {"),
    ("M5 the Mac's pinch opens at once (no travel to make one)", "abs(spacing - landed) >= Self.pinchTravel {", "abs(spacing - landed) >= 0 {"),
    ("M6 no catch-up for the Mac's pinch", "                macSteps.append(.magnify(.changed, amount: Double(spacing / landed - 1)))\n", ""),
    ("M7 the Mac's turn the wrong way round", "static func macDegrees(_ turn: CGFloat) -> Double { -Double(turn) * 180 / .pi }",
     "static func macDegrees(_ turn: CGFloat) -> Double { Double(turn) * 180 / .pi }"),
    ("M8 the Mac's turn in radians", "static func macDegrees(_ turn: CGFloat) -> Double { -Double(turn) * 180 / .pi }",
     "static func macDegrees(_ turn: CGFloat) -> Double { -Double(turn) }"),
    ("M9 the Mac's gestures left open when the pair breaks", "if owner == .macPinch { closeMac(); if at.count == 2 { formPair() } }",
     "if owner == .macPinch, at.count == 2 { formPair() }"),
    ("M10 three fingers leave the Mac's pinch open", "            if was == .macPinch { closeMac() }\n", ""),
    ("M12 the place where the pair is now, not where it landed",
     "                if macAt == nil { macAt = Self.midpoint(pairFrom[0], pairFrom[1]) }\n                macSteps.append(.magnify(.began",
     "                macAt = Self.midpoint(now[0], now[1])\n                macSteps.append(.magnify(.began"),
    ("M13 the turn's arc at the whole spacing, not half", "return abs(turned(from: angle(from[0], from[1]), to: angle(to[0], to[1]))) * distance(to[0], to[1]) / 2",
     "return abs(turned(from: angle(from[0], from[1]), to: angle(to[0], to[1]))) * distance(to[0], to[1])"),
    ("M14 the Mac's pinch scrolls too", "var scrollsMac: Bool { owner == .mac || owner == .none }", "var scrollsMac: Bool { owner == .mac || owner == .none || owner == .macPinch }"),
    ("M15 a turn across ±180° the long way round", "            while d > .pi { d -= 2 * .pi }\n", ""),
    ("M16 the turn sent with Rotate off", "            guard target.turns else { return }\n", ""),
    ("M17 the turn's catch-up lost", "macSteps.append(.rotate(.changed, degrees: Self.macDegrees(Self.turned(from: Self.angle(pairFrom[0], pairFrom[1]), to: angle))))",
     "macSteps.append(.rotate(.changed, degrees: 0))"),
    ("M18 a re-formed pair under the Mac's pinch never pinches", "guard owner == .undecided || owner == .picture || owner == .macPinch, pair.count < 2",
     "guard owner == .undecided || owner == .picture, pair.count < 2"),
    ("M19 the target never taken (always the picture's)", "                self.target = target\n", ""),
    ("M20 the pan's start never the Mac's pinch's turn", "                let pinched = max(spacing, target.turns ? Self.turnTravel(from: pairFrom, to: [a, b]) : 0)\n                if pinched",
     "                let pinched = spacing\n                if pinched"),
]
caught = 0
for name, old, new in MUTANTS:
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    src = os.path.join(OUT, "StreamZoom.swift")
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
        print(f"{name}: caught ({len(failed)} FAIL lines; first: {failed[0][:150] if failed else ''})")
    else:
        print(f"{name}: SURVIVED")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
