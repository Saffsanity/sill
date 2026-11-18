"""PrivacyPolicy mutants (Sources/SillHost/PrivacyPolicy.swift; docs/privacy-mode-plan.md, part 1): each changes the
rule in one place, must compile and make privacy/main.swift fail. usage: mutants.py ROOT"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import module
F = "Sources/SillHost/PrivacyPolicy.swift"
M = [
    # Which departures count, and the wait.
    ("the wait with the switch off", F, "            guard was > 0, on else { return [] }\n", "            guard was > 0 else { return [] }\n"),
    ("one of two devices leaving starts the wait", F, "            if sessions > 0 {\n                guard waitingSince", "            if sessions > 1 {\n                guard waitingSince"),
    ("zero again restarts the wait (and a launch starts one)", F, "            guard was > 0, on else { return [] }\n", "            guard on else { return [] }\n"),
    ("a count below zero kept", F, "            sessions = max(0, count)\n", "            sessions = count\n"),
    ("a device back keeps the wait", F, "                waitingSince = nil\n                return [.line(Words.cameBack(grace))]",
     "                return [.line(Words.cameBack(grace))]"),
    ("a device back ends the wait silently", F, "                return [.line(Words.cameBack(grace))]", "                waitingSince = nil\n                return []"),
    ("the switch off keeps the wait", F, "            waitingSince = nil\n            return [.line(Words.switchedOff)]", "            return [.line(Words.switchedOff)]"),
    ("the switch on starts a wait with no device", F, "            self.on = on\n            guard !on, waitingSince",
     "            self.on = on\n            if on, sessions == 0 { waitingSince = now }\n            guard !on, waitingSince"),
    ("the switch off ends the wait silently", F, "            waitingSince = nil\n            return [.line(Words.switchedOff)]", "            waitingSince = nil\n            return []"),
    ("the wait ends a second early", F, "guard let since = waitingSince, now - since >= grace else { return out }",
     "guard let since = waitingSince, now - since >= grace - 1 else { return out }"),
    ("the wait ends after its time", F, "guard let since = waitingSince, now - since >= grace else { return out }",
     "guard let since = waitingSince, now - since > grace else { return out }"),
    ("the wait's line says 30 s whatever the wait", F, "            return [.line(Words.lastLeft(grace))]", "            return [.line(Words.lastLeft(PrivacyPolicy.grace))]"),
    # Its end.
    ("a Mac locked already is locked again", F, "            switch mac {\n            case .screenLocked:",
     "            switch mac == .screenLocked ? .unlocked : mac {\n            case .screenLocked:"),
    ("another user's screen is locked", F, "            switch mac {\n            case .screenLocked:",
     "            switch mac == .offConsole ? .unlocked : mac {\n            case .screenLocked:"),
    ("a reading not established is locked", F, "            switch mac {\n            case .screenLocked:",
     "            switch mac == .unknown ? .unlocked : mac {\n            case .screenLocked:"),
    ("no display to type at: locked anyway (#298)", F, "                guard display() else {", "                guard display() || true else {"),
    ("the displays looked at at every tick", F, "            guard !quitting else { return [] }\n            var out: [Action] = []\n",
     "            guard !quitting else { return [] }\n            _ = display()\n            var out: [Action] = []\n"),
    ("a second lock while one is unconfirmed", F, "                guard confirmingSince == nil else {", "                guard true else {"),
    ("a wait's end under a lock unconfirmed says nothing", F, "                    out.append(.line(Words.lockUnderWay(grace)))\n                    break",
     "                    break"),
    ("the lock without its line", F, "                out += [.line(Words.locking(grace)), .lock]", "                out += [.lock]"),
    ("the line without the lock", F, "                out += [.line(Words.locking(grace)), .lock]", "                out += [.line(Words.locking(grace))]"),
    ("the lock's confirmation never started", F, "                confirmingSince = now\n                out +=", "                out +="),
    # The confirmation.
    ("off console does not confirm the lock", F, "                if mac == .screenLocked || mac == .offConsole {", "                if mac == .screenLocked {"),
    ("any reading confirms the lock", F, "                if mac == .screenLocked || mac == .offConsole {", "                if mac != .unknown {"),
    ("the displays sleep with a device back", F,
     "                    out += sessions == 0 ? [.line(Words.lockedAndSleeps), .sleepDisplays] : [.line(Words.lockedDeviceBack)]",
     "                    out += [.line(Words.lockedAndSleeps), .sleepDisplays]"),
    ("no display sleep after the lock (#275)", F, "[.line(Words.lockedAndSleeps), .sleepDisplays]", "[.line(Words.lockedAndSleeps)]"),
    ("the confirmation never runs out", F, "                } else if now - since >= PrivacyPolicy.lockConfirm {", "                } else if false {"),
    ("the confirmation runs out at once", F, "                } else if now - since >= PrivacyPolicy.lockConfirm {", "                } else if now - since >= 0 {"),
    ("no display sleep after an unconfirmed lock", F,
     "                    if sessions == 0 { out.append(.sleepDisplays) }\n                } else {", "                } else {"),
    ("no look while the lock is confirmed", F, "                } else {\n                    out.append(.look)\n                }", "                } else {\n                }"),
    ("an unavailable call ignored", F, "guard case .unavailable(let why) = call, confirmingSince != nil, !quitting else { return [] }",
     "guard case .unavailable(let why) = call, confirmingSince != nil, !quitting, why.isEmpty else { return [] }"),
    ("an unavailable call answered twice", F, "guard case .unavailable(let why) = call, confirmingSince != nil, !quitting else { return [] }",
     "guard case .unavailable(let why) = call, !quitting else { return [] }"),
    ("no display sleep after an unavailable call", F, "            if sessions == 0 { out.append(.sleepDisplays) }\n            return out",
     "            return out"),
    ("the unconfirmed lock kept as unavailable", F, "                    failure = Words.stillUnlockedReason\n", "                    failure = Words.unavailableReason\n"),
    ("an unavailable call leaves no failure", F, "            failure = Words.unavailableReason\n", "            failure = nil\n"),
    ("a lock leaves the last failure", F, "                    last = .locked\n                    failure = nil\n", "                    last = .locked\n"),
    # A quit.
    # (tick's own `guard !quitting` is kept as a second guard: a quit clears the wait and the confirmation, so removing it
    # changes nothing, an equivalent mutant left out.)
    ("a quit keeps the lock's confirmation", F, "            waitingSince = nil\n            confirmingSince = nil\n            return waited",
     "            waitingSince = nil\n            return waited"),
    ("a quit keeps the wait", F, "            let waited = waitingSince != nil\n            waitingSince = nil\n", "            let waited = waitingSince != nil\n"),
    ("a quit says nothing of the wait", F, "            return waited ? [.line(Words.quitting)] : []", "            return []"),
    ("a quit says so with no wait", F, "            return waited ? [.line(Words.quitting)] : []", "            return [.line(Words.quitting)]"),
    ("the devices leaving at a quit start a wait", F, "            sessions = max(0, count)\n            guard !quitting else { return [] }\n",
     "            sessions = max(0, count)\n"),
    # Rule 10's displays.
    ("any display counts", F, "roles.contains(.screen) }", "!roles.isEmpty }"),
    ("Sill's Desktop display counts before #200", F, "roles.contains(.screen) }", "roles.contains(.screen) || roles.contains(.sillDesktop) }"),
    ("macOS's stand-in counts (#298's Mac)", F, "roles.contains(.screen) }", "roles.contains(.screen) || roles.contains(.standIn) }"),
    # Settings' warning.
    ("the warning with the switch off", F, "        guard on else { return nil }\n        if noDisplay", "        if noDisplay"),
    ("a failure wins over no display", F, "        if noDisplay { return Words.noDisplayWarning }\n        return failure.map(Words.failedWarning)",
     "        if let failure { return Words.failedWarning(failure) }\n        return noDisplay ? Words.noDisplayWarning : nil"),
    # The TEST ONLY hooks.
    ("any host takes the hooks", F, "        guard testHost else { return h }", "        guard testHost || true else { return h }"),
    ("a wait under half a second taken", F, "if let s = Double(raw), s >= 0.5, s <= 600 {", "if let s = Double(raw), s > 0, s <= 600 {"),
    ("a wait over 600 s taken", F, "if let s = Double(raw), s >= 0.5, s <= 600 {", "if let s = Double(raw), s >= 0.5 {"),
    ("17 displays taken", F, "if let n = Int(raw), (0...16).contains(n) {", "if let n = Int(raw), (0...17).contains(n) {"),
    ("any value turns the call off", F, 'if env["SILL_TEST_PRIVACY_NO_SYMBOL"] == "1" {', 'if env["SILL_TEST_PRIVACY_NO_SYMBOL"] != nil {'),
    # Words.
    ("the footnote in seconds as a number", F, '"This Mac locks \\(seconds(grace)) after', '"This Mac locks \\(number(grace)) s after'),
    ("seconds always plural", F, 'package static func seconds(_ s: Double) -> String { "\\(number(s)) second\\(s == 1 ? "" : "s")" }',
     'package static func seconds(_ s: Double) -> String { "\\(number(s)) seconds" }'),
    ("the failure's display sleep said with a device back", F, '(sleeps ? "; its display sleeps instead." : ".")', '"; its display sleeps instead."'),
    ("rule 10's line without #298", F, "it has no display to type its password at (issue #298).", "it has no display to type its password at."),
]
sys.exit(0 if module.mutate("privacy", M, sys.argv[1]) else 1)
