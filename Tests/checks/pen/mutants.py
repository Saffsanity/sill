"""Mutants of PenTablet.swift (Sources/SillHost) and PenStrokes.swift (iOSClient): each changes one
file in one place, is compiled with the check by build.sh and must make the check fail.
usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
TABLET = "Sources/SillHost/PenTablet.swift"
STROKES = "iOSClient/PenStrokes.swift"
MODE = "guard switchOn, connected, let takes = hostPencil else { return false }"
FORCE = "guard maximum > 0, force.isFinite, maximum.isFinite else { return 0 }"
LEAVE = "guard stroke == nil, !hovering, canHover, told else { return false }"
UP = "            guard tipDown else { return [] }\n            tipDown = false\n            posts.append(.up(samples.first.map(Self.place),"
MOVES = "        return !(checked.samples ?? []).isEmpty"
CURSOR = "Sources/SillHost/CursorClass.swift"
MUTANTS = [
    # The Mac's cursor
    ("no table: every cursor an app's own but CoreCursor's", CURSOR, "        if standards.contains(fingerprint) { return true }\n", ""),
    ("any cursor with four images standard", CURSOR, "        return Double(widest) >= 9.5 * pointWidth", "        return true"),
    ("three images enough", CURSOR, "bitmapWidths.count >= 4", "bitmapWidths.count >= 3"),
    ("5× enough", CURSOR, ">= 9.5 * pointWidth", ">= 4.5 * pointWidth"),
    ("no point size counts", CURSOR, "guard pointWidth > 0, bitmapWidths.count >= 4", "guard bitmapWidths.count >= 4"),
    # The pointer's settle
    ("every pen message moves the pointer", TABLET, MOVES, "        return true"),
    ("unchecked messages move the pointer", TABLET, "        guard let checked = input.checked() else { return false }",
     "        let checked = input"),
    # Coming into range
    ("no enter before a hover", TABLET, "                enter(&posts)\n                posts.append(.move(Self.place(sample), Self.point(sample, tipDown: false)))",
     "                posts.append(.move(Self.place(sample), Self.point(sample, tipDown: false)))"),
    ("no enter before a down", TABLET, "            enter(&posts)\n            tipDown = true", "            tipDown = true"),
    ("no enter before a move", TABLET, "            enter(&posts)\n            for sample in samples", "            for sample in samples"),
    ("an enter with every message", TABLET, "if !inProximity { inProximity = true; posts.append(.enter) }", "inProximity = true; posts.append(.enter)"),
    # The tip
    ("a down with the tip down posts again", TABLET, "guard let sample = samples.first, !tipDown else { return [] }",
     "guard let sample = samples.first else { return [] }"),
    ("a down never puts the tip down", TABLET, "            tipDown = true\n            posts.append(.down(", "            posts.append(.down("),
    ("an up without a down posts", TABLET, UP, UP.replace("            guard tipDown else { return [] }\n", "")),
    ("an up leaves the tip down", TABLET, UP, UP.replace("            tipDown = false\n", "")),
    ("a cancel's sample ignored", TABLET, "posts.append(.up(samples.first.map(Self.place), samples.first.map", "posts.append(.up(nil, samples.first.map"),
    ("a hover with the tip down only moves", TABLET, "            if tipDown {\n                // A hover with the tip down", "            if false {\n                // A hover with the tip down"),
    ("a move's samples reversed", TABLET, "for sample in samples { posts.append(.move(", "for sample in samples.reversed() { posts.append(.move("),
    ("a move's tip always down", TABLET, "posts.append(.move(Self.place(sample), Self.point(sample, tipDown: tipDown))) }",
     "posts.append(.move(Self.place(sample), Self.point(sample, tipDown: true))) }"),
    # Leaving
    ("a leave leaves the button down", TABLET, "if tipDown { tipDown = false; posts.append(.up(nil, Self.lifted)) }", "tipDown = false"),
    ("a leave keeps the pen in range", TABLET, "        if inProximity { inProximity = false; posts.append(.leave) }\n        owner = nil\n        hovering = false\n        return posts", "        owner = nil\n        hovering = false\n        return posts"),
    ("a leave posted when out of range", TABLET, "        if inProximity { inProximity = false; posts.append(.leave) }\n        owner = nil\n        hovering = false\n        return posts",
     "        inProximity = false; posts.append(.leave)\n        owner = nil\n        hovering = false\n        return posts"),
    # Devices
    ("another device's pen draws over the stroke", TABLET, "        if tipDown, let owner, owner != device { return [] }\n", ""),
    ("another device's leave lets go", TABLET, "            guard owner == nil || owner == device else { return [] }   // another device's pen is still here\n", ""),
    ("any device leaving lets go", TABLET, "        guard owner == device else { return [] }\n        return letGo()", "        return letGo()"),
    ("the host's end lets go of nothing", TABLET, "package mutating func releaseAll() -> [Post] { letGo() }", "package mutating func releaseAll() -> [Post] { [] }"),
    # Leaving by itself
    ("leaves by itself with the tip down", TABLET, "guard inProximity, !tipDown, !hovering else { return nil }", "guard inProximity, !hovering else { return nil }"),
    ("a hovering pen leaves by itself", TABLET, "guard inProximity, !tipDown, !hovering else { return nil }", "guard inProximity, !tipDown else { return nil }"),
    ("a down keeps the hover", TABLET, "            owner = device\n            hovering = false\n            enter(&posts)\n            tipDown = true", "            owner = device\n            enter(&posts)\n            tipDown = true"),
    ("a move keeps the hover", TABLET, "        case PenInput.move:\n            owner = device\n            hovering = false\n", "        case PenInput.move:\n            owner = device\n"),
    ("a leave keeps the hover", TABLET, "        owner = nil\n        hovering = false\n        return posts", "        owner = nil\n        return posts"),
    ("leaves after half a second", TABLET, "package static let idleLeave = 1.0", "package static let idleLeave = 0.5"),
    ("a wait that goes negative", TABLET, "return max(0, lastPenAt + Self.idleLeave - now)", "return lastPenAt + Self.idleLeave - now"),
    ("leaves at the first look", TABLET, "guard let wait = leavesIn(now: now), wait <= 0 else { return [] }", "guard leavesIn(now: now) != nil else { return [] }"),
    ("a message does not move the time it leaves at", TABLET, "        lastPenAt = now\n", ""),
    ("a message that is not usable moves it", TABLET, "        guard let input = input.checked() else { return [] }\n", "        lastPenAt = now\n        guard let input = input.checked() else { return [] }\n"),
    ("a message that is not usable is taken", TABLET, "        guard let input = input.checked() else { return [] }\n", ""),
    # Pressure
    ("no pressure floor", TABLET, "tipDown ? max(sample.p ?? 1, pressureFloor) : 0", "tipDown ? (sample.p ?? 1) : 0"),
    ("no pressure sent reads as none", TABLET, "max(sample.p ?? 1, pressureFloor)", "max(sample.p ?? 0, pressureFloor)"),
    ("pressure while hovering", TABLET, "pressure: tipDown ? max(sample.p ?? 1, pressureFloor) : 0", "pressure: max(sample.p ?? 1, pressureFloor)"),
    ("a floor of a tenth", TABLET, "package static let pressureFloor = 0.01", "package static let pressureFloor = 0.1"),
    ("a point's pressure not clamped", TABLET, "self.pressure = min(max(pressure, 0), 1)", "self.pressure = pressure"),
    ("a point's tilt not clamped", TABLET, "self.tiltX = min(max(tiltX, -1), 1)", "self.tiltX = tiltX"),
    # Tilt
    ("tilt y along the frame's y", TABLET, "-lean * sin(azimuth) + 0)", "lean * sin(azimuth) + 0)"),
    ("tilt x against the frame's x", TABLET, "(lean * cos(azimuth) + 0,", "(-lean * cos(azimuth) + 0,"),
    ("tilt's axes swapped", TABLET, "(lean * cos(azimuth) + 0, -lean * sin(azimuth) + 0)", "(-lean * sin(azimuth) + 0, lean * cos(azimuth) + 0)"),
    ("tilt from the altitude, not the lean", TABLET, "sin(.pi / 2 - min(max(altitude, 0), .pi / 2))", "sin(min(max(altitude, 0), .pi / 2))"),
    ("the lean itself, not its sine", TABLET, "let lean = sin(.pi / 2 - min(max(altitude, 0), .pi / 2))", "let lean = (.pi / 2 - min(max(altitude, 0), .pi / 2)) / (.pi / 2)"),
    ("an altitude out of range not clamped", TABLET, "sin(.pi / 2 - min(max(altitude, 0), .pi / 2))", "sin(.pi / 2 - altitude)"),
    ("tilt with the altitude alone", TABLET, "guard let altitude, let azimuth else { return (0, 0) }", "guard let altitude else { return (0, 0) }\n        let azimuth = azimuth ?? 0"),
    ("a hover without its tilt", TABLET, "let tilt = tilt(altitude: sample.alt, azimuth: sample.az)", "let tilt = tipDown ? tilt(altitude: sample.alt, azimuth: sample.az) : (x: 0.0, y: 0.0)"),
    # For kind 8's rules, and with nowhere to land
    ("a move amounts to its first sample", TABLET, "let last = input.samples?.last", "let last = input.samples?.first"),
    ("a down amounts to a move", TABLET, "case PenInput.down: return last.map { .pointer(.leftDown,", "case PenInput.down: return last.map { .pointer(.move,"),
    ("an up amounts to a move", TABLET, "return .pointer(.leftUp, x: last?.x ?? 0, y: last?.y ?? 0)", "return .pointer(.move, x: last?.x ?? 0, y: last?.y ?? 0)"),
    ("a cancel amounts to nothing", TABLET, "case PenInput.up, PenInput.cancel: return .pointer(.leftUp,", "case PenInput.up: return .pointer(.leftUp,"),
    ("a leave amounts to a move", TABLET, "case PenInput.hover, PenInput.move: return last.map { .pointer(.move, x: $0.x, y: $0.y) }",
     "case PenInput.hover, PenInput.move: return last.map { .pointer(.move, x: $0.x, y: $0.y) }\n        case PenInput.leave: return .pointer(.move, x: 0, y: 0)"),
    ("an up with nowhere to land always goes", TABLET, "case PenInput.up, PenInput.cancel: return tipDown", "case PenInput.up, PenInput.cancel: return true"),
    ("a cancel with nowhere to land is dropped", TABLET, "case PenInput.up, PenInput.cancel: return tipDown", "case PenInput.up: return tipDown"),
    ("a leave with nowhere to land is dropped", TABLET, "case PenInput.leave: return true", "case PenInput.leave: return false"),
    ("everything with nowhere to land goes", TABLET, "        default: return false\n        }\n    }\n}", "        default: return true\n        }\n    }\n}"),
    # The device: a pen's stroke or the mouse's
    ("as a pen with the switch off", STROKES, MODE, "guard connected, let takes = hostPencil else { return false }"),
    ("as a pen when not connected", STROKES, MODE, "guard switchOn, let takes = hostPencil else { return false }"),
    ("as a pen to a Mac that says 0", STROKES, "return takes >= generation", "return takes >= 0"),
    ("as a pen only to this build's generation", STROKES, "return takes >= generation", "return takes == generation"),
    ("a mouse's stroke tells the Mac of a pen", STROKES, "if mode == .pen { told = true }", "told = true"),
    ("a stroke's end forgets its mode", STROKES, "        let mode = stroke\n        stroke = nil\n", "        stroke = nil\n        let mode = stroke\n"),
    ("a stroke never ends", STROKES, "        let mode = stroke\n        stroke = nil\n", "        let mode = stroke\n"),
    ("a hover while the tip is down falls through to the mouse's move (the line back to the start)", STROKES,
     "        guard stroke == nil else { return .ignore }\n        guard isPencil else { return .mouse }\n        hovering = true\n        canHover = true\n        guard penMode else { return .mouse }\n",
     "        guard isPencil else { return .mouse }\n        hovering = true\n        canHover = true\n        guard penMode, stroke == nil else { return .mouse }\n"),
    ("a hover while the tip is down still counts as hovering", STROKES,
     "        guard stroke == nil else { return .ignore }\n        guard isPencil else { return .mouse }\n        hovering = true\n",
     "        if stroke != nil { hovering = true; return .ignore }\n        guard isPencil else { return .mouse }\n        hovering = true\n"),
    ("a hover in mouse mode goes as a pen's", STROKES, "        guard penMode else { return .mouse }\n        told = true\n        return .pen", "        told = true\n        return .pen"),
    ("the iPad's own pointer counts as the Pencil hovering", STROKES, "        guard isPencil else { return .mouse }\n", ""),
    # The device: readings
    ("a force not over its maximum", STROKES, "return min(max(force / maximum, 0), 1)", "return min(max(force, 0), 1)"),
    ("a pressure not clamped", STROKES, "return min(max(force / maximum, 0), 1)", "return force / maximum"),
    ("no maximum reads as full", STROKES, FORCE, "guard maximum > 0, force.isFinite, maximum.isFinite else { return 1 }"),
    ("a maximum of 0 divided by", STROKES, FORCE, "guard force.isFinite, maximum.isFinite else { return 0 }"),
    ("34 samples a message", STROKES, "min(start + PenInput.maxSamples, readings.count)]", "min(start + PenInput.maxSamples + 2, readings.count)]"),
    ("readings after the 32nd dropped", STROKES, "while start < readings.count {", "if start < readings.count {"),
    ("times from the callback's last reading", STROKES, "let last = chunk[chunk.endIndex - 1].time", "let last = readings[readings.count - 1].time"),
    ("times in seconds", STROKES, "let ms = (last - reading.time) * 1000", "let ms = (last - reading.time)"),
    ("the last sample carries a time", STROKES, "t: ms > 0.05 ? ms : nil)", "t: ms)"),
    ("a move's readings reversed", STROKES, "chunk.map { sample($0, before: last) }", "chunk.reversed().map { sample($0, before: last) }"),
    # The device: the leave
    ("a leave while touching", STROKES, LEAVE, "guard !hovering, canHover, told else { return false }"),
    ("a leave while hovering", STROKES, LEAVE, "guard stroke == nil, canHover, told else { return false }"),
    ("a leave from a Pencil that cannot hover", STROKES, LEAVE, "guard stroke == nil, !hovering, told else { return false }"),
    ("a leave the Mac was told nothing of", STROKES, LEAVE, "guard stroke == nil, !hovering, canHover else { return false }"),
    ("a leave at once", STROKES, "guard let at = checkAt, now >= at else { return false }", "guard checkAt != nil else { return false }"),
    ("a leave leaves the Mac told", STROKES, LEAVE + "\n        told = false\n", LEAVE + "\n"),
    ("no wait before a leave", STROKES, "static let leaveDelay = 0.1", "static let leaveDelay = 0.0"),
    ("a hover's end checks nothing", STROKES, "        hovering = false\n        checkAt = now + Self.leaveDelay\n", "        hovering = false\n"),
    ("a stroke's end checks nothing", STROKES, "        stroke = nil\n        checkAt = now + Self.leaveDelay\n", "        stroke = nil\n"),
    ("the surface going tells of nothing", STROKES, "told = false; checkAt = nil }\n        return told", "told = false; checkAt = nil }\n        return false"),
    ("the surface going keeps the Mac told", STROKES, "defer { stroke = nil; hovering = false; told = false; checkAt = nil }", "defer { stroke = nil; hovering = false; checkAt = nil }"),
    # The device: a resting palm
    ("fingers speak while the tip is down", STROKES, "            if touching { return true }\n", ""),
    ("a finger from before the lift speaks after it", STROKES, "return began <= last + PenStrokes.palmLinger", "return began >= last && began <= last + PenStrokes.palmLinger"),
    ("no quiet after the lift", STROKES, "return began <= last + PenStrokes.palmLinger", "return began <= last"),
    ("a second of quiet", STROKES, "static let palmLinger = 0.5", "static let palmLinger = 1.0"),
    ("the lift's time not kept", STROKES, "            self.touching = touching\n            lastTouchedAt = time\n", "            self.touching = touching\n            if touching { lastTouchedAt = time }\n"),
]
caught = 0
for name, rel, old, new in MUTANTS:
    src = open(os.path.join(WT, rel)).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        exe = os.path.join(t, "c")
        mf = os.path.join(t, os.path.basename(rel)); open(mf, "w").write(src.replace(old, new, 1))
        subprocess.run([os.path.join(HERE, "build.sh"), WT, exe, f"{os.path.basename(rel)}={mf}"], capture_output=True, text=True)
        if not os.path.exists(exe): print(f"{name}: did not compile"); continue
        r = subprocess.run([exe], capture_output=True, text=True, timeout=600)
        failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        if r.returncode != 0:
            caught += 1
            print(f"{name}: caught ({len(failed)} FAIL lines; first: {failed[0][:150] if failed else r.stdout.strip()[-150:]})")
        else:
            print(f"{name}: SURVIVED")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
