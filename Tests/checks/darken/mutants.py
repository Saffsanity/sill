"""DarkenPolicy mutants (Sources/SillHost/DarkenPolicy.swift; docs/privacy-mode-plan.md, part 2): each changes the rule
in one place, must compile and make darken/main.swift fail. usage: mutants.py ROOT

The last five change part 1's PrivacyPolicy (Sources/SillHost/PrivacyPolicy.swift, compiled into this check): its
switches (Lock this Mac when the last device leaves, Only after a device away from home, Turn off its display too) and
a session's route, as the cases of both rules together see them (the review of PR #400, follow-up 2). The privacy
check has its own mutants of that rule; these prove this check runs it beside darkening, switches and routes included.

Left out as equivalent (each a second guard behind one that already holds): the `!quitting` guards of `sessions`,
`switched`, `reading`, `local`, `called` and `tick` (a quit has cleared the wait, the hold and the lock asked and taken
the windows down, so nothing after it can raise, lift or lock); `screens`' guard that only a change across zero acts
(any other change settles to the same); `tick`'s `lockFollows = false` at a wait's end (read only at a wait's end, and
set again at the next one's start); `lockHolds` dropped from the hold's start (`if lockFollows, lockHolds`: a hold
started while the lock holds nothing ends in the same tick, at the hold's own end test); `levelFits`' first two
clauses (above everything G0 saw hidden, above the screen saver's level: the assistive level, 1500, is above both, so
the third clause decides for them; they name what G0 measured)."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import module
F = "Sources/SillHost/DarkenPolicy.swift"
P = "Sources/SillHost/PrivacyPolicy.swift"
M = [
    # Rule 14: only Sill.app itself darkens, the lock's rule (the review of PR #400, follow-up 1).
    ("the bare binary and the CLI darken for real (--synthetic alone decides)", F,
     "PrivacyPolicy.locksForReal(synthetic: synthetic, bundled: bundled)", "!synthetic"),
    ("Sill.app with --synthetic darkens for real", F, "PrivacyPolicy.locksForReal(synthetic: synthetic, bundled: bundled)", "bundled"),
    ("everything darkens for real", F, "PrivacyPolicy.locksForReal(synthetic: synthetic, bundled: bundled)", "true"),
    ("the dry run's raise says test host", F, '"Privacy (dry run): would darken \\(displays(screens)); nothing is drawn."',
     '"Privacy (test host): would darken \\(displays(screens)); nothing is drawn."'),
    ("the start line hides the dry run", F, '+ (dry ? " A dry run here', '+ (false ? " A dry run here'),
    ("the start line's scopes swapped", F, 'scope == .away ? "while a device away from home is connected"', 'scope == .any ? "while a device away from home is connected"'),
    ("the start line's keys swapped", F, '(keysLock ? "; a key or click on this Mac locks it."', '(!keysLock ? "; a key or click on this Mac locks it."'),
    # The constants.
    ("the dark's wait is not the lock's", F, "package static let grace: Double = PrivacyPolicy.grace", "package static let grace: Double = 20"),
    ("the device's window 5 s", F, "package static let remoteUnlockWindow: Double = 10", "package static let remoteUnlockWindow: Double = 5"),
    ("the hint 5 s", F, "package static let hintFor: Double = 10", "package static let hintFor: Double = 5"),
    ("no tag", F, "package static let eventTag: Int64 = 0x5349_4C4C_5052_5631", "package static let eventTag: Int64 = 0"),
    ("the hold's slack under two ticks", F, "static let holdSlack: Double = 1", "static let holdSlack: Double = 0.25"),
    ("the fallback taken though G0 found a level under the lock screen", F, "package static let staysUnderLockScreen = true", "package static let staysUnderLockScreen = false"),
    # The probe G0: the black windows' level and opacity.
    ("the black at the screen saver's level (#184's)", F, "package static let windowLevel = 1501", "package static let windowLevel = 1000"),
    ("the black at the assistive level", F, "package static let windowLevel = 1501", "package static let windowLevel = 1500"),
    ("the black over the lock screen (the shielding level)", F, "package static let windowLevel = 1501", "package static let windowLevel = 2_147_483_628"),
    ("the black at the lock screen's level", F, "package static let windowLevel = 1501", "package static let windowLevel = 2001"),
    ("not opaque", F, "package static let windowOpaque = true", "package static let windowOpaque = false"),
    ("a level the lock screen covers fits", F, "\n            && probeLockScreen.allSatisfy { level < $0 }", ""),
    ("the assistive level fits", F, "level > probeSameLevel && level > assistiveLevel", "level > probeSameLevel && level >= assistiveLevel"),
    ("the lock screen's own level fits", F, "probeLockScreen.allSatisfy { level < $0 }", "probeLockScreen.allSatisfy { level <= $0 }"),
    # Rule 7: which events count, and which are Sill's own (G0's step 4).
    ("a key is only a move", F, "        case 10: return .key", "        case 10: return .move"),
    ("a modifier alone is a key", F, "        case 10: return .key", "        case 10, 12: return .key"),
    ("a key's up is a key too", F, "        case 10: return .key", "        case 10, 11: return .key"),
    ("a right click is nothing", F, "        case 1, 3, 25: return .click", "        case 1, 25: return .click"),
    ("a click's up is a click too", F, "        case 1, 3, 25: return .click", "        case 1, 2, 3, 25: return .click"),
    ("a scroll is nothing", F, "        case 5, 6, 7, 27, 22: return .move", "        case 5, 6, 7, 27: return .move"),
    ("a drag is nothing", F, "        case 5, 6, 7, 27, 22: return .move", "        case 5, 22: return .move"),
    ("the observer misses scrolls", F, "static let watchedEventTypes = [10, 1, 3, 25, 5, 6, 7, 27, 22]", "static let watchedEventTypes = [10, 1, 3, 25, 5, 6, 7, 27]"),
    ("the observer asks for key ups", F, "static let watchedEventTypes = [10, 1, 3, 25, 5, 6, 7, 27, 22]", "static let watchedEventTypes = [10, 11, 1, 3, 25, 5, 6, 7, 27, 22]"),
    ("Sill's own events known by the tag alone", F, "userData == eventTag || sourcePID == ownPID", "userData == eventTag"),
    ("Sill's own events known by the process alone", F, "userData == eventTag || sourcePID == ownPID", "sourcePID == ownPID"),
    ("a person's hardware counted Sill's", F, "userData == eventTag || sourcePID == ownPID", "userData == eventTag || sourcePID == ownPID || sourcePID == 0"),
    ("any tag counted Sill's", F, "userData == eventTag || sourcePID == ownPID", "userData != 0 || sourcePID == ownPID"),
    # Settings › Devices: the two switches as the scope.
    ("on whatever the switch says", F, "        guard on else { return .off }\n", ""),
    ("only away the wrong way round", F, "return onlyAway ? .away : .any", "return onlyAway ? .any : .away"),
    # Rule 13: the screens.
    ("Sill's Desktop display and the stand-in covered", F, "madeByStage: $0.madeByStage) == .screen", "madeByStage: $0.madeByStage) != .stage"),
    ("a display the stage made that has gone covered", F, "madeByStage: $0.madeByStage) == .screen", "madeByStage: false) == .screen"),
    ("a zero-width display covered", F, "&& $0.width > 0 && $0.height > 0", "&& $0.height > 0"),
    # Rule 2: which sessions darken.
    ("off darkens", F, "        case .off: return false", "        case .off: return true"),
    ("only away darkens a device at home", F, "        case .away: return away", "        case .away: return true"),
    ("whenever darkens only a device away", F, "        case .any: return true", "        case .any: return away"),
    # Rule 3: dark.
    ("dark with no screen", F, "scope != .off && screens > 0 && !quitting && !takenBack", "scope != .off && !quitting && !takenBack"),
    ("dark though taken back", F, "scope != .off && screens > 0 && !quitting && !takenBack", "scope != .off && screens > 0 && !quitting"),
    ("the wait does not hold the dark", F, "(counting > 0 || waitingSince != nil || holdingSince != nil", "(counting > 0 || holdingSince != nil"),
    ("the hold does not hold the dark", F, "waitingSince != nil || holdingSince != nil || askedAt != nil)\n",
     "waitingSince != nil || askedAt != nil)\n"),
    ("a lock asked at a key does not hold the dark", F, "waitingSince != nil || holdingSince != nil || askedAt != nil)\n",
     "waitingSince != nil || holdingSince != nil)\n"),
    # Rule 4.
    ("the fallback keeps the black over the lock screen", F, "var shouldBeUp: Bool { wantsDark && (underLockScreen || mac == .unlocked) }",
     "var shouldBeUp: Bool { wantsDark }"),
    ("the fallback keeps the black off console", F, "var shouldBeUp: Bool { wantsDark && (underLockScreen || mac == .unlocked) }",
     "var shouldBeUp: Bool { wantsDark && (underLockScreen || mac != .screenLocked) }"),
    ("the fallback lifts without its line", F, "                if up, !underLockScreen { out.append(.line(Words.lockScreenShows)) }\n", ""),
    # Rules 3 and 5: up before anything, with its line and the hint.
    ("the line before the raise", F, "if want { return [.raise, .line(Words.dark(scope, screens: screens))] + showHint(at: now) }",
     "if want { return [.line(Words.dark(scope, screens: screens)), .raise] + showHint(at: now) }"),
    ("no hint as it darkens", F, "if want { return [.raise, .line(Words.dark(scope, screens: screens))] + showHint(at: now) }",
     "if want { return [.raise, .line(Words.dark(scope, screens: screens))] }"),
    # Rule 6: the wait.
    ("a wait while taken back", F, "            } else if countingBefore > 0, darkBefore {", "            } else if countingBefore > 0 {"),
    ("a lock follows with a session left", F, "lockFollows = lockAfterSession && sessions == 0", "lockFollows = lockAfterSession"),
    ("the wait's line says 30 s whatever the wait", F, "out.append(.line(Words.lastLeft(grace)))", "out.append(.line(Words.lastLeft(DarkenPolicy.grace)))"),
    ("a return says nothing", F, "                    out.append(.line(Words.cameBack(grace)))\n", ""),
    ("a return keeps the hold", F, "                    waitingSince = nil\n                    holdingSince = nil\n                    lockFollows = false\n                    out.append(.line(Words.cameBack",
     "                    waitingSince = nil\n                    lockFollows = false\n                    out.append(.line(Words.cameBack"),
    ("a session at home joining leaves the lock following", F,
     "                // A session that does not darken joined while the wait runs: the lock's wait ended with it.\n                lockFollows = false\n",
     "                // A session that does not darken joined while the wait runs: the lock's wait ended with it.\n"),
    ("the wait ends after its time", F, "if let since = waitingSince, now - since >= grace {", "if let since = waitingSince, now - since > grace {"),
    ("the wait ends a second early", F, "if let since = waitingSince, now - since >= grace {", "if let since = waitingSince, now - since >= grace - 1 {"),
    ("the hold for any lock", F, "                if lockFollows, lockHolds { holdingSince = since }", "                if lockHolds { holdingSince = since }"),
    ("the hold outlasts the lock", F, "if let since = holdingSince, !lockHolds || now - since >=", "if let since = holdingSince, now - since >="),
    ("the hold has no bound", F, "!lockHolds || now - since >= grace + lockConfirm + DarkenPolicy.holdSlack {", "!lockHolds {"),
    ("the hold's bound 10 s later", F, "now - since >= grace + lockConfirm + DarkenPolicy.holdSlack {", "now - since >= grace + lockConfirm + 10 {"),
    ("the wait's end lifts without its line", F, "            if up, !shouldBeUp { out.append(.line(Words.lit)) }\n            return out + settle(at: now)",
     "            return out + settle(at: now)"),
    # Rule 7: someone at the Mac.
    ("Sill's own key counts", F, "guard !tagged, !quitting, up, mac == .unlocked else { return [] }", "guard !quitting, up, mac == .unlocked else { return [] }"),
    ("a key at the locked Mac counts", F, "guard !tagged, !quitting, up, mac == .unlocked else { return [] }", "guard !tagged, !quitting, up else { return [] }"),
    ("a key with nothing dark counts", F, "guard !tagged, !quitting, up, mac == .unlocked else { return [] }", "guard !tagged, !quitting, mac == .unlocked else { return [] }"),
    ("the pointer locks", F, "if kind != .move, keysLock, !keysPass,", "if keysLock, !keysPass,"),
    ("keys lock with the switch off", F, "if kind != .move, keysLock, !keysPass,", "if kind != .move, !keysPass,"),
    ("keys lock again after a failed lock", F, "if kind != .move, keysLock, !keysPass,", "if kind != .move, keysLock,"),
    ("a lock at every key", F, "lastAsk.map({ now - $0 >= lockConfirm }) ?? true", "true"),
    ("a lock every second", F, "lastAsk.map({ now - $0 >= lockConfirm }) ?? true", "lastAsk.map({ now - $0 >= 1 }) ?? true"),
    ("the lock asked without its line", F, "return [.line(Words.locking), .lock] + showHint(at: now)", "return [.lock] + showHint(at: now)"),
    ("the lock's time never kept", F, "                lastAsk = now\n                askedAt = now\n", "                askedAt = now\n"),
    ("the lock never confirmed", F, "                lastAsk = now\n                askedAt = now\n", "                lastAsk = now\n"),
    ("the hint at every move", F, "if let until = hintUntil, until - now > hintFor - 1 { return [] }", "if let until = hintUntil, until - now > hintFor { return [] }"),
    ("the hint never renewed while shown", F, "if let until = hintUntil, until - now > hintFor - 1 { return [] }", "if let until = hintUntil, until - now > 0 { return [] }"),
    ("an unavailable call answered twice", F, "guard case .unavailable(let why) = call, askedAt != nil, !quitting else { return [] }",
     "guard case .unavailable(let why) = call, !quitting else { return [] }"),
    ("an unavailable call leaves keys locking", F, "            askedAt = nil\n            keysPass = true\n            var out", "            askedAt = nil\n            var out"),
    ("the confirmation runs out late", F, "                if now - asked >= lockConfirm {", "                if now - asked > lockConfirm {"),
    ("no look while confirming", F, "                } else {\n                    out.append(.look)\n                }", "                } else {\n                }"),
    ("an unconfirmed lock leaves keys locking", F, "                    keysPass = true\n                    out.append(.line(Words.couldNotLock(Words.stillUnlocked)))",
     "                    out.append(.line(Words.couldNotLock(Words.stillUnlocked)))"),
    ("a lock that shows stays unconfirmed", F, "                askedAt = nil\n                keysPass = false\n                if up, !underLockScreen",
     "                keysPass = false\n                if up, !underLockScreen"),
    ("a lock that shows leaves keys passing", F, "                askedAt = nil\n                keysPass = false\n                if up, !underLockScreen",
     "                askedAt = nil\n                if up, !underLockScreen"),
    # Rule 8: taken back.
    ("an unlock while not dark is taken back", F, "if new == .unlocked, was == .screenLocked || was == .offConsole, wantsDark {",
     "if new == .unlocked, was == .screenLocked || was == .offConsole {"),
    ("a return to the console is no unlock", F, "if new == .unlocked, was == .screenLocked || was == .offConsole, wantsDark {",
     "if new == .unlocked, was == .screenLocked, wantsDark {"),
    ("a return to the console can be the device's", F, "if was == .screenLocked, let at = deviceInputAt, now - at <= remoteUnlockWindow {",
     "if let at = deviceInputAt, now - at <= remoteUnlockWindow {"),
    ("the window's edge is the Mac's", F, "now - at <= remoteUnlockWindow {", "now - at < remoteUnlockWindow {"),
    ("the window 5 s longer", F, "now - at <= remoteUnlockWindow {", "now - at <= remoteUnlockWindow + 5 {"),
    ("taken back keeps the wait", F, "                    takenBack = true\n                    waitingSince = nil\n", "                    takenBack = true\n"),
    ("a device's input counts twice", F, "            if new == .unlocked { deviceInputAt = nil; deviceName = nil }\n", ""),
    ("input while unlocked is a witness", F, "            guard mac == .screenLocked else { return }\n            deviceInputAt = now", "            deviceInputAt = now"),
    ("taken back for good", F, "            if sessions == 0 { takenBack = false }\n", ""),
    ("taken back ends when no session darkens", F, "            if sessions == 0 { takenBack = false }\n", "            if counting == 0 { takenBack = false }\n"),
    # Rule 9: the switches.
    ("a switch keeps taken back", F, "            takenBack = false\n            keysPass = false\n            guard !quitting", "            keysPass = false\n            guard !quitting"),
    ("a switch keeps keys passing", F, "            takenBack = false\n            keysPass = false\n            guard !quitting", "            takenBack = false\n            guard !quitting"),
    ("the lock's switch alone clears taken back", F, "            guard darkening else { return [] }\n", ""),
    ("a change of scope keeps the wait", F, "            if scopeChanged {\n", "            if false {\n"),
    ("off says the scope's line", F, "out.append(.line(scope == .off ? Words.switchedOff : Words.noneCounts))", "out.append(.line(scope != .off ? Words.switchedOff : Words.noneCounts))"),
    ("a new wording waits for the next hint", F, "            if up, hint != hintBefore, !out.contains(.raise) { out += showHint(at: now) }\n", ""),
    ("the lock's switch off leaves it following", F, "            if !lockAfterSession { lockFollows = false }\n", ""),
    # Both rules together: part 1's switches as the dark keeps them (the review of PR #400, follow-up 2).
    ("the dark never learns the lock's switch", F,
     "            self.lockAfterSession = lockAfterSession\n            if !lockAfterSession { lockFollows = false }\n",
     "            if !lockAfterSession { lockFollows = false }\n"),
    ("the dark follows a lock that is off", F, "lockFollows = lockAfterSession && sessions == 0", "lockFollows = sessions == 0"),
    # Rule 13's count, and rule 11, a quit.
    ("no screen lifts without its line", F, "            if screens == 0, up { out.append(.line(Words.noScreen)) }\n", ""),
    ("a quit says so with nothing dark", F, "            guard up else { return [] }\n            up = false", "            up = false"),
    ("a quit's line before the lift", F, "return [.lift, .line(Words.quitting)]", "return [.line(Words.quitting), .lift]"),
    ("a quit that goes on", F, "            quitting = true\n            waitingSince = nil\n", "            waitingSince = nil\n"),
    # Rule 12: a hung Sill.
    ("the watchdog while not dark", F, "dark && now - lastBeat >= hangLimit", "now - lastBeat >= hangLimit"),
    ("the watchdog late", F, "dark && now - lastBeat >= hangLimit", "dark && now - lastBeat > hangLimit"),
    ("never reopened at first", F, "guard let lastReopen else { return true }", "guard let lastReopen else { return false }"),
    ("reopened late", F, "now - lastReopen >= relaunchSpacing || now < lastReopen", "now - lastReopen > relaunchSpacing || now < lastReopen"),
    ("a clock gone back stops it", F, "now - lastReopen >= relaunchSpacing || now < lastReopen", "now - lastReopen >= relaunchSpacing"),
    ("no record is a reopening", F, "        guard let record else { return false }", "        guard let record else { return true }"),
    ("any later launch is the reopening", F, "return now >= record && now - record <= reopenedWithin", "return now >= record"),
    ("a record from the future is a reopening", F, "return now >= record && now - record <= reopenedWithin", "return now - record <= reopenedWithin"),
    ("the reopening's minute 10 s", F, "static let reopenedWithin: Double = 60", "static let reopenedWithin: Double = 10"),
    ("the bare binary reopened", F, '        guard bundlePath.hasSuffix(".app") else { return nil }\n', ""),
    ("the reopening not a new instance", F, '["/usr/bin/open", "-n", "-g", bundlePath]', '["/usr/bin/open", "-g", bundlePath]'),
    ("the reopening in front", F, '["/usr/bin/open", "-n", "-g", bundlePath]', '["/usr/bin/open", "-n", bundlePath]'),
    # The TEST ONLY hooks.
    ("any host takes the hooks", F, "        guard testHost else { return h }\n        if let path", "        if let path"),
    ("a relative input file taken", F, "            if path.hasPrefix(\"/\") {", "            if !path.isEmpty {"),
    ("any value stamps the lines", F, 'if env["SILL_TEST_PRIVACY_LOG"] == "1" {', 'if env["SILL_TEST_PRIVACY_LOG"] != nil {'),
    ("three words taken", F, "guard let first = parts.first, parts.count <= 2 else { return nil }", "guard let first = parts.first, parts.count <= 3 else { return nil }"),
    ("a stall of any length", F, "if let s = Double(raw), s >= 1, s <= 30 {", "if let s = Double(raw) {"),
    ("a stall shorter than a second", F, "if let s = Double(raw), s >= 1, s <= 30 {", "if let s = Double(raw), s > 0, s <= 30 {"),
    ("any second word is tagged", F, '        if tagged, parts[1] != "tagged" { return nil }\n', ""),
    # Every word.
    ("the scopes' words swapped", F, 'scope == .away ? "a device away from home is connected" : "a device is connected"',
     'scope == .any ? "a device away from home is connected" : "a device is connected"'),
    ("zero displays singular", F, 'package static func displays(_ n: Int) -> String { "\\(n) display\\(n == 1 ? "" : "s")" }',
     'package static func displays(_ n: Int) -> String { "\\(n) display\\(n > 1 ? "s" : "")" }'),
    ("a device's name not cleaned", F, "let n = SafeText.label(name ?? \"\")", "let n = name ?? \"\""),
    ("no name, an empty one", F, 'return "Privacy: unlocked from \\(n.isEmpty ? "a device" : n);', 'return "Privacy: unlocked from \\(n);'),
    ("the hint's lines swapped", F, 'hint == .lock ? "Press any key or click to lock it." : "To use it here', 'hint == .pass ? "Press any key or click to lock it." : "To use it here'),
    ("the hint says nothing of a click", F, '"Press any key or click to lock it."', '"Press any key to lock it."'),
    ("the footnote's scopes swapped", F, "            (onlyAway\n                ? \"This Mac", "            (!onlyAway\n                ? \"This Mac"),
    ("the footnote's keys swapped", F, "                + (keysLock\n", "                + (!keysLock\n"),
    ("the footnote's wait always 30 s", F, '" They come back \\(PrivacyPolicy.Words.seconds(grace)) after the last one leaves."',
     '" They come back 30 seconds after the last one leaves."'),
    # Part 1's switches and a session's route, beside the dark (the review of PR #400, follow-up 2).
    ("the lock waits with its switch off", P, "guard on, !onlyAway || awaySeen else {", "guard !onlyAway || awaySeen else {"),
    ("the lock's only away ignored at the departure", P, "guard on, !onlyAway || awaySeen else {", "guard on else {"),
    ("the lock takes a session's route the wrong way round", P, "if away { awaySeen = true }", "if !away { awaySeen = true }"),
    ("only away turned on keeps a visit at home's wait", P, "            waitingSince = nil\n            return [.line(Words.nowOnlyAway)]",
     "            return [.line(Words.nowOnlyAway)]"),
    ("the display sleeps whatever its switch says", P, "                    if !sleeps {\n", "                    if false {\n"),
]
sys.exit(0 if module.mutate("darken", M, sys.argv[1]) else 1)
