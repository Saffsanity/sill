"""Each mutant changes DisplayWake.swift (issue #134, PR #151) in one place, is compiled with the check by
build.sh and must make it fail (main.swift). usage: mutants.py WORKTREE"""
import os, subprocess, sys
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(WT, ".build", "checks", "display-wake")   # the mutants' sources and binaries
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(WT, "Sources/SillHost/DisplayWake.swift")
orig = open(SRC).read()
HELD = "if activity != .connect, let last = lastDeclared, now >= last, now - last < Self.interval {"
WINDOW = "if case .pointer(.move, _, _) = input, let changed = streamChangedAt, now >= changed,\n                   now - changed < Self.recentre {"
LAUNCH = "            case .launchApp: return .launch\n"
WOKE = "if look.wasAsleep, !asleepNow, look.wakesBefore == wakesSaid {"
MINUTE = "if let last = lastLineAt, now >= last, now - last < DisplayWake.declaredLineInterval { return nil }"
MUTANTS = {
    # The interval
    "M1 the connect held off like the rest": (HELD, "if let last = lastDeclared, now >= last, now - last < Self.interval {"),
    "M2 the interval 10 s": ("static let interval: TimeInterval = 5", "static let interval: TimeInterval = 10"),
    "M3 the interval 2 s": ("static let interval: TimeInterval = 5", "static let interval: TimeInterval = 2"),
    "M4 nothing at exactly 5 s": (HELD, HELD.replace("now - last < Self.interval", "now - last <= Self.interval")),
    "M5 a declaration that does not restart the interval": ("        lastDeclared = now\n        return testHost", "        return testHost"),
    "M6 what was held off restarts it too": ("        guard let activity = activity(event, at: now) else { return .nothing }\n",
                                             "        guard let activity = activity(event, at: now) else { return .nothing }\n        defer { lastDeclared = now }\n"),
    "M7 what is not a person's restarts it": ("        guard let activity = activity(event, at: now) else { return .nothing }\n",
                                              "        guard let activity = activity(event, at: now) else { lastDeclared = now; return .nothing }\n"),
    "M8 a clock set back holds declarations off": (HELD, HELD.replace("now >= last, ", "")),
    "M9 a test host declares": ("return testHost ? .count : .declare(activity)", "return .declare(activity)"),
    "M10 a real host only counts": ("return testHost ? .count : .declare(activity)", "return .count"),
    "M11 every declaration said as input": ("return testHost ? .count : .declare(activity)", "return testHost ? .count : .declare(.input)"),
    # Whose each message is
    "M12 a pick counts (the device's own Desktop request wakes the display)": (LAUNCH, "            case .selectSource: return .input\n" + LAUNCH),
    "M13 an app opened does not count": (LAUNCH, ""),
    "M14 a window's button does not count": ("            case .windowCommand: return .windowButton\n", ""),
    "M15 a menu item chosen does not count": ("            case .pressMenuItem: return .menuItem\n", ""),
    "M16 a gesture does not count": ("            case .gesture: return .gesture\n", ""),
    "M17 the viewport counts": (LAUNCH, "            case .viewport: return .input\n" + LAUNCH),
    "M18 a settings change counts": (LAUNCH, "            case .changeSettings: return .input\n" + LAUNCH),
    "M19 a menu fetched counts": (LAUNCH, "            case .fetchMenu: return .menuItem\n" + LAUNCH),
    "M20 the clipboard counts": (LAUNCH, "            case .clipboard: return .input\n" + LAUNCH),
    "M21 show your pairing code counts": (LAUNCH, "            case .pairingWanted: return .input\n" + LAUNCH),
    "M61 the Mac's sound counts (only a host sends it)": (LAUNCH, "            case .audio: return .input\n" + LAUNCH),
    "M21b a keyframe request counts": (LAUNCH, "            case .keyframeRequest: return .input\n" + LAUNCH),
    "M22 every other kind counts": ("            default: return nil", "            default: return .input"),
    "M23 input that does not decode counts": ("guard let input else { return nil }", "guard let input else { return .input }"),
    "M24 a gesture said as a menu item": ("            case .gesture: return .gesture\n", "            case .gesture: return .menuItem\n"),
    # The device's own move after a stream change
    "M25 no window: the re-centre counts": (WINDOW, WINDOW.replace("now - changed < Self.recentre", "now - changed < 0")),
    "M26 the window 1 s": ("static let recentre: TimeInterval = 2", "static let recentre: TimeInterval = 1"),
    "M27 the window 3 s": ("static let recentre: TimeInterval = 2", "static let recentre: TimeInterval = 3"),
    "M28 the window's end inside it": (WINDOW, WINDOW.replace("now - changed < Self.recentre", "now - changed <= Self.recentre")),
    "M29 every input in the window is the device's": (WINDOW, WINDOW.replace("if case .pointer(.move, _, _) = input, let changed", "if let changed")),
    "M30 every pointer event in the window is the device's": (WINDOW, WINDOW.replace("if case .pointer(.move, _, _) = input", "if case .pointer = input")),
    "M31 a clock set back keeps a move in the window": (WINDOW, WINDOW.replace("now >= changed,\n", "\n")),
    "M32 the first stream change kept, not the latest": ("mutating func streamChanged(at now: TimeInterval) { streamChangedAt = now }",
                                                         "mutating func streamChanged(at now: TimeInterval) { if streamChangedAt == nil { streamChangedAt = now } }"),
    "M33 a stream change forgotten": ("mutating func streamChanged(at now: TimeInterval) { streamChangedAt = now }",
                                      "mutating func streamChanged(at now: TimeInterval) { }"),
    # The lines
    "M34 the woke line without the device": ('"Woke the display for \\(device), which \\(why(activity))."', '"Woke the display, which \\(why(activity))."'),
    "M35 a connect said as input": ('case .connect: return "connected"', 'case .connect: return "sent input"'),
    "M36 an app opened said as a connect": ('case .launch: return "opened an app"', 'case .launch: return "connected"'),
    "M37 the declaration's line without the asleep note": ('(asleepNow ? ", but the display read asleep \\(secondLook) s later." : ".")', '"."'),
    "M38 the refusal's code in decimal": ("String(UInt32(bitPattern: result), radix: 16)", "String(result)"),
    # What DisplayActivity says
    "M39 a woke line without the second look": (WOKE, "if look.wasAsleep, look.wakesBefore == wakesSaid {"),
    "M40 a woke line for a display that was on": (WOKE, "if !asleepNow, look.wakesBefore == wakesSaid {"),
    "M41 two woke lines for one wake": (WOKE, "if look.wasAsleep, !asleepNow {"),
    "M42 a woke line not counted": ("                wakesSaid += 1\n", ""),
    "M43 a declaration's wakes taken at its look": ("wakesBefore: wakesSaid))", "wakesBefore: 0))"),
    "M44 a woke line not this minute's": ("                wakesSaid += 1\n                lastLineAt = now\n", "                wakesSaid += 1\n"),
    "M45 a declaration's line every time": (MINUTE + "\n", ""),
    "M46 the minute 30 s": ("static let declaredLineInterval: TimeInterval = 60", "static let declaredLineInterval: TimeInterval = 30"),
    "M47 a clock set back holds the line off": (MINUTE, MINUTE.replace("now >= last, ", "")),
    "M48 the second look at 1 s": ("static let secondLook: TimeInterval = 0.5", "static let secondLook: TimeInterval = 1"),
    "M49 a refusal taken for a success": ("guard result == DisplayWake.success else {", "guard result == DisplayWake.success || result != 0 else {"),
    "M50 a refusal said every time": ("                if saidFailure { return (nil, nil) }\n", ""),
    "M51 a refusal never said again after a success": ("            saidFailure = false\n            return (nil, Look(", "            return (nil, Look("),
    "M52 a refusal looked at again": ("return (DisplayWake.failedLine(result), nil)",
                                      "return (DisplayWake.failedLine(result), Look(device: device, activity: activity, wasAsleep: wasAsleep, wakesBefore: wakesSaid))"),
    # The constants
    "M53 the assertion's name": ('static let assertionName = "Sill: a device is using this Mac"', 'static let assertionName = "Sill is streaming a Mac screen"'),
    "M54 the declaration's stats key": ('static let declaredKey = "disp.wake"', 'static let declaredKey = "in.wake"'),
    "M55 the test host's stats key": ('static let dryKey = "disp.wakeDry"', 'static let dryKey = "disp.wake"'),
    "M56 success is not 0": ("static let success: Int32 = 0", "static let success: Int32 = 1"),
    # The TEST ONLY user type
    "M57 remote ignored": ('        case "remote":\n            return (true,', '        case "remote":\n            return (false,'),
    "M58 a test host takes remote": ("        guard !testHost else {", "        guard testHost || !testHost else {"),
    "M59 another value echoed": ('return (false, "\\(userActiveVariable) ignored: it takes local or remote; user activity is declared as local.")',
                                 'return (false, "\\(userActiveVariable)=\\(value) ignored: it takes local or remote; user activity is declared as local.")'),
    "M60 the variable's name": ('static let userActiveVariable = "SILL_TEST_USER_ACTIVE"', 'static let userActiveVariable = "SILL_TEST_USERACTIVE"'),
}
caught = 0
for name, (old, new) in MUTANTS.items():
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    path = os.path.join(OUT, "DisplayWake.mutant.swift")
    binary = os.path.join(OUT, "mutant")
    open(path, "w").write(orig.replace(old, new))
    if os.path.exists(binary): os.remove(binary)
    b = subprocess.run([os.path.join(HERE, "build.sh"), WT, binary, path], capture_output=True, text=True)
    if not os.path.exists(binary):
        print(f"{name}: DOES NOT COMPILE\n{(b.stdout + b.stderr)[:600]}"); continue
    r = subprocess.run([binary], capture_output=True, text=True, timeout=300)
    failed = [l[5:] for l in r.stdout.splitlines() if l.startswith("FAIL")]
    ok = r.returncode != 0
    caught += ok
    print(f"{'caught' if ok else 'MISSED'} {name}: {len(failed)} failing, e.g. {[f[:100] for f in failed[:2]]}")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
