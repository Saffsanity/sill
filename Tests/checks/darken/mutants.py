"""DarkenPolicy mutants (Sources/SillHost/DarkenPolicy.swift; docs/privacy-mode-plan.md, part 2): each changes the rule
in one place, must compile and make darken/main.swift fail. usage: mutants.py ROOT

Left out as equivalent (each a second guard behind one that already holds): the `!quitting` guards of `sessions`,
`switched`, `reading`, `local`, `called` and `tick` (a quit has cleared the wait, the hold and the lock asked and taken
the windows down, so nothing after it can raise, lift or lock); `screens`' guard that only a change across zero acts
(any other change settles to the same); `tick`'s `lockFollows = false` at a wait's end (read only at a wait's end, and
set again at the next one's start)."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import module
F = "Sources/SillHost/DarkenPolicy.swift"
M = [
    # The constants.
    ("the dark's wait is not the lock's", F, "package static let grace: Double = PrivacyPolicy.grace", "package static let grace: Double = 20"),
    ("the device's window 5 s", F, "package static let remoteUnlockWindow: Double = 10", "package static let remoteUnlockWindow: Double = 5"),
    ("the hint 5 s", F, "package static let hintFor: Double = 10", "package static let hintFor: Double = 5"),
    ("no tag", F, "package static let eventTag: Int64 = 0x5349_4C4C_5052_5631", "package static let eventTag: Int64 = 0"),
    ("the hold's slack under two ticks", F, "static let holdSlack: Double = 1", "static let holdSlack: Double = 0.25"),
    ("above the lock screen before G0", F, "package static let staysUnderLockScreen = true", "package static let staysUnderLockScreen = false"),
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
    ("the hold whatever the lock says", F, "                if lockFollows, lockHolds { holdingSince = since }", "                if lockFollows { holdingSince = since }"),
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
    # The TEST ONLY hooks.
    ("any host takes the hooks", F, "        guard testHost else { return h }\n        if let path", "        if let path"),
    ("a relative input file taken", F, "            if path.hasPrefix(\"/\") {", "            if !path.isEmpty {"),
    ("any value stamps the lines", F, 'if env["SILL_TEST_PRIVACY_LOG"] == "1" {', 'if env["SILL_TEST_PRIVACY_LOG"] != nil {'),
    ("three words taken", F, "guard let first = parts.first, parts.count <= 2 else { return nil }", "guard let first = parts.first, parts.count <= 3 else { return nil }"),
    ("any second word is tagged", F, '            if tagged, parts[1] != "tagged" { return nil }\n', ""),
    # Every word.
    ("the scopes' words swapped", F, 'scope == .away ? "a device away from home is connected" : "a device is connected"',
     'scope == .any ? "a device away from home is connected" : "a device is connected"'),
    ("zero displays singular", F, 'package static func displays(_ n: Int) -> String { "\\(n) display\\(n == 1 ? "" : "s")" }',
     'package static func displays(_ n: Int) -> String { "\\(n) display\\(n > 1 ? "s" : "")" }'),
    ("a device's name not cleaned", F, "let n = SafeText.label(name ?? \"\")", "let n = name ?? \"\""),
    ("no name, an empty one", F, 'return "Privacy: unlocked from \\(n.isEmpty ? "a device" : n);', 'return "Privacy: unlocked from \\(n);'),
    ("the hint's lines swapped", F, 'hint == .lock ? "Press any key to lock it." : "To use it here', 'hint == .pass ? "Press any key to lock it." : "To use it here'),
]
sys.exit(0 if module.mutate("darken", M, sys.argv[1]) else 1)
