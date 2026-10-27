"""H3 (docs/update-notice-plan.md) mutants of GoodbyePolicy.swift, and (issue #105) of HostGoodbye.swift and
Remote.swift's goodbyes: each changes one of them in one place, is compiled with the check by build.sh
(the mutant in place of its file) and must make it fail. usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]; HERE = os.path.dirname(os.path.abspath(__file__))
FILES = {"GoodbyePolicy.swift": "iOSClient/GoodbyePolicy.swift", "HostGoodbye.swift": "Sources/SillHost/HostGoodbye.swift",
         "Remote.swift": "Sources/StreamProtocol/Remote.swift"}
MUTANTS = [
    ("an unknown reason reconnects unless told not to", "GoodbyePolicy.swift", "let reconnect = goodbye.reconnect == true", "let reconnect = goodbye.reconnect != false"),
    ("the host's message ignored", "GoodbyePolicy.swift", "return Outcome(text: message(goodbye) ?? own, reconnect: reconnect, remoteAllowed: saved, isNotice: true)", "return Outcome(text: own, reconnect: reconnect, remoteAllowed: saved, isNotice: true)"),
    ("the message not cleaned", "GoodbyePolicy.swift", "let text = SafeText.label(goodbye.message ?? \"\", limit: messageLimit)", "let text = goodbye.message ?? \"\""),
    ("an empty message shown", "GoodbyePolicy.swift", "return text.isEmpty ? nil : text", "return text"),
    ("no length limit", "GoodbyePolicy.swift", "static let messageLimit = 300", "static let messageLimit = 1000"),
    ("removed reconnects", "GoodbyePolicy.swift", "reconnect: false, remoteAllowed: false, isNotice: false)\n        case Goodbye.remoteOff:", "reconnect: true, remoteAllowed: false, isNotice: false)\n        case Goodbye.remoteOff:"),
    ("remoteOff allows the remote door", "GoodbyePolicy.swift", "return Outcome(text: \"\\(mac) turned off Remote Access.\", reconnect: true, remoteAllowed: false, isNotice: false)", "return Outcome(text: \"\\(mac) turned off Remote Access.\", reconnect: true, remoteAllowed: saved, isNotice: false)"),
    ("an unreadable goodbye is not a notice", "GoodbyePolicy.swift", "Goodbye.busy,\n                                            Goodbye.pairingRequired]", "Goodbye.busy,\n                                            Goodbye.pairingRequired, \"\"]"),
    ("pairingRequired is a notice", "GoodbyePolicy.swift", "Goodbye.busy,\n                                            Goodbye.pairingRequired]", "Goodbye.busy]"),
    ("sleep is not a notice", "GoodbyePolicy.swift", "Goodbye.busy,\n                                            Goodbye.pairingRequired]", "Goodbye.busy,\n                                            Goodbye.pairingRequired, Goodbye.sleep]"),
    ("restart is not a notice", "GoodbyePolicy.swift", "Goodbye.busy,\n                                            Goodbye.pairingRequired]", "Goodbye.busy,\n                                            Goodbye.pairingRequired, Goodbye.restart]"),
    ("sleep's outcome not a notice", "GoodbyePolicy.swift", "reconnects when it wakes.\",\n                           reconnect: true, remoteAllowed: saved && remote, isNotice: true", "reconnects when it wakes.\",\n                           reconnect: true, remoteAllowed: saved && remote, isNotice: false"),
    ("sleep: the remote door at home too", "GoodbyePolicy.swift", "remoteAllowed: saved && remote, isNotice: true, went: .asleep)", "remoteAllowed: saved, isNotice: true, went: .asleep)"),
    ("sleep: never the remote door", "GoodbyePolicy.swift", "remoteAllowed: saved && remote, isNotice: true, went: .asleep)", "remoteAllowed: false, isNotice: true, went: .asleep)"),
    ("sleep: the remote door for an unsaved Mac", "GoodbyePolicy.swift", "remoteAllowed: saved && remote, isNotice: true, went: .asleep)", "remoteAllowed: remote, isNotice: true, went: .asleep)"),
    ("sleep: no wait (went lost)", "GoodbyePolicy.swift", "isNotice: true, went: .asleep)", "isNotice: true)"),
    ("sleep: held as a Mac going down", "GoodbyePolicy.swift", "isNotice: true, went: .asleep)", "isNotice: true, went: .off)"),
    ("sleep without a reconnect", "GoodbyePolicy.swift", "reconnects when it wakes.\",\n                           reconnect: true", "reconnects when it wakes.\",\n                           reconnect: false"),
    ("sleep's words without the device", "GoodbyePolicy.swift", "went to sleep. This \\(device) reconnects when it wakes.", "went to sleep. Sill reconnects when it wakes."),
    ("shutdown: the remote door at home too", "GoodbyePolicy.swift", "reconnects when it’s back.\",\n                           reconnect: true, remoteAllowed: saved && remote, isNotice: true, went: .off)\n        case Goodbye.restart:", "reconnects when it’s back.\",\n                           reconnect: true, remoteAllowed: saved, isNotice: true, went: .off)\n        case Goodbye.restart:"),
    ("shutdown counted as asleep", "GoodbyePolicy.swift", "remoteAllowed: saved && remote, isNotice: true, went: .off)\n        case Goodbye.restart:", "remoteAllowed: saved && remote, isNotice: true, went: .asleep)\n        case Goodbye.restart:"),
    ("shutdown without a reconnect", "GoodbyePolicy.swift", "is shutting down or restarting. This \\(device) reconnects when it’s back.\",\n                           reconnect: true", "is shutting down or restarting. This \\(device) reconnects when it’s back.\",\n                           reconnect: false"),
    ("shutdown says restarting", "GoodbyePolicy.swift", "\"\\(mac) is shutting down or restarting. This", "\"\\(mac) is restarting. This"),
    ("shutdown says only shutting down (a restart's willPowerOff)", "GoodbyePolicy.swift", "\"\\(mac) is shutting down or restarting. This", "\"\\(mac) is shutting down. This"),
    ("restart says shutting down", "GoodbyePolicy.swift", "\"\\(mac) is restarting. This", "\"\\(mac) is shutting down. This"),
    ("restart: the remote door for an unsaved Mac", "GoodbyePolicy.swift", "remoteAllowed: saved && remote, isNotice: true, went: .off)\n        case Goodbye.removed:", "remoteAllowed: remote, isNotice: true, went: .off)\n        case Goodbye.removed:"),
    ("restart: no wait (went lost)", "GoodbyePolicy.swift", "isNotice: true, went: .off)\n        case Goodbye.removed:", "isNotice: true)\n        case Goodbye.removed:"),
    ("restart read as an unknown reason", "GoodbyePolicy.swift", "        case Goodbye.restart:\n", "        case \"restarting\":\n"),
    ("sleep left for the Mac to close", "GoodbyePolicy.swift", "[Goodbye.sleep, Goodbye.shutdown, Goodbye.restart].contains(goodbye.reason)", "[Goodbye.shutdown, Goodbye.restart].contains(goodbye.reason)"),
    ("restart left for the Mac to close", "GoodbyePolicy.swift", "[Goodbye.sleep, Goodbye.shutdown, Goodbye.restart].contains(goodbye.reason)", "[Goodbye.sleep, Goodbye.shutdown].contains(goodbye.reason)"),
    ("every goodbye closed at once", "GoodbyePolicy.swift", "[Goodbye.sleep, Goodbye.shutdown, Goodbye.restart].contains(goodbye.reason)", "!goodbye.reason.isEmpty"),
    ("pairingRequired reconnects", "GoodbyePolicy.swift", "Tap it to pair this \\(device).\",\n                           reconnect: false", "Tap it to pair this \\(device).\",\n                           reconnect: true"),
    ("notices inverted", "GoodbyePolicy.swift", "!knownReasons.contains(goodbye.reason)", "knownReasons.contains(goodbye.reason)"),
    ("quit allows the remote door for an unsaved Mac", "GoodbyePolicy.swift", "reconnect: true, remoteAllowed: saved, isNotice: false, went: .quit)", "reconnect: true, remoteAllowed: true, isNotice: false, went: .quit)"),
    ("quit: no wait for its row (went lost)", "GoodbyePolicy.swift", "isNotice: false, went: .quit)", "isNotice: false)"),
    ("busy: a wait as after a quit", "GoodbyePolicy.swift", "is already serving 8 devices.\", reconnect: true, remoteAllowed: saved, isNotice: false)", "is already serving 8 devices.\", reconnect: true, remoteAllowed: saved, isNotice: false, went: .quit)"),
    ("saved and unsaved words swapped", "GoodbyePolicy.swift", "return Outcome(text: saved ? \"\\(mac) disconnected. Sill will reconnect when it can reach it.\"", "return Outcome(text: !saved ? \"\\(mac) disconnected. Sill will reconnect when it can reach it.\""),
    ("update reconnects unless told not to", "GoodbyePolicy.swift", "reconnect: goodbye.reconnect == true, remoteAllowed: saved,\n                           storeLink: true, isNotice: true)", "reconnect: goodbye.reconnect != false, remoteAllowed: saved,\n                           storeLink: true, isNotice: true)"),
    ("update without the App Store link", "GoodbyePolicy.swift", "reconnect: goodbye.reconnect == true, remoteAllowed: saved,\n                           storeLink: true, isNotice: true)", "reconnect: goodbye.reconnect == true, remoteAllowed: saved,\n                           storeLink: false, isNotice: true)"),
    ("minimumVersion shown as sent", "GoodbyePolicy.swift", "if let floor = goodbye.minimumVersion.flatMap({ SillVersion($0) }) { own += \" It needs version \\(floor) or later.\" }", "if let floor = goodbye.minimumVersion { own += \" It needs version \\(floor) or later.\" }"),
    ("update ignores the host's message", "GoodbyePolicy.swift", "return Outcome(text: message(goodbye) ?? own, reconnect: goodbye.reconnect == true", "return Outcome(text: own, reconnect: goodbye.reconnect == true"),
    ("update's own words without the device", "GoodbyePolicy.swift", "var own = \"Update Sill on this \\(device) to keep using \\(mac).\"", "var own = \"Update Sill to keep using \\(mac).\""),
    # What the Mac sends (Remote.swift): the words a device from before these reasons shows, and the reconnect it follows.
    ("the sleep message in the old words", "Remote.swift", "message: \"\\(mac) is going to sleep.\"", "message: \"\\(mac) went to sleep. Sill reconnects when it wakes.\""),
    ("the sleep goodbye without a reconnect", "Remote.swift", "message: \"\\(mac) is going to sleep.\", reconnect: true)", "message: \"\\(mac) is going to sleep.\")"),
    ("the shutdown goodbye says restarting", "Remote.swift", "message: \"\\(mac) is shutting down.\"", "message: \"\\(mac) is restarting.\""),
    ("the restart goodbye sent as a shutdown", "Remote.swift", "Goodbye(reason: restart, message:", "Goodbye(reason: shutdown, message:"),
    ("the restart goodbye without a reconnect", "Remote.swift", "message: \"\\(mac) is restarting.\", reconnect: true)", "message: \"\\(mac) is restarting.\", reconnect: false)"),
    ("restart's reason on the wire renamed", "Remote.swift", "shutdown = \"shutdown\", restart = \"restart\"", "shutdown = \"shutdown\", restart = \"reboot\""),
    ("willPowerOff's goodbye says only shutting down", "Remote.swift", "message: \"\\(mac) is shutting down or restarting.\"", "message: \"\\(mac) is shutting down.\""),
    ("willPowerOff's goodbye sent as a restart", "Remote.swift", "Goodbye(reason: shutdown, message: \"\\(mac) is shutting down or restarting.\"", "Goodbye(reason: restart, message: \"\\(mac) is shutting down or restarting.\""),
    ("willPowerOff's goodbye without a reconnect", "Remote.swift", "is shutting down or restarting.\", reconnect: true)", "is shutting down or restarting.\", reconnect: false)"),
    # The host's choice (HostGoodbye.swift).
    ("a restart code mistyped", "HostGoodbye.swift", "[0x7265_7374, 0x7272_7374]", "[0x7265_7375, 0x7272_7374]"),
    ("the restart dialog's code left out", "HostGoodbye.swift", "[0x7265_7374, 0x7272_7374]", "[0x7265_7374]"),
    ("a shut down code mistyped", "HostGoodbye.swift", "[0x7368_7574, 0x7273_646E]", "[0x7368_7574, 0x7273_646F]"),
    ("a log out code mistyped", "HostGoodbye.swift", "[0x726C_676F, 0x6C6F_676F]", "[0x726C_676F, 0x6C6F_676E]"),
    ("the quit reason's keyword mistyped", "HostGoodbye.swift", "quitReasonKeyword: UInt32 = 0x7768_793F", "quitReasonKeyword: UInt32 = 0x7768_7940"),
    ("a shut down read as a restart", "HostGoodbye.swift", "if shutdownReasons.contains(reason) { return .shutDown }", "if shutdownReasons.contains(reason) { return .restart }"),
    ("a restart read as a quit", "HostGoodbye.swift", "            if restartReasons.contains(reason) { return .restart }\n", ""),
    ("a log out read as a shut down", "HostGoodbye.swift", "if logOutReasons.contains(reason) { return .quit }", "if logOutReasons.contains(reason) { return .shutDown }"),
    ("a log out after willPowerOff read as the power-off goodbye", "HostGoodbye.swift", "            if logOutReasons.contains(reason) { return .quit }\n", ""),
    ("willPowerOff ignored (a SIGTERM after it says quit)", "HostGoodbye.swift", "return poweringOff && !byMenu ? .powerOff : .quit", "return .quit"),
    ("every reasonless end a power off", "HostGoodbye.swift", "return poweringOff && !byMenu ? .powerOff : .quit", "return .powerOff"),
    ("the menu's Quit after willPowerOff a power off too", "HostGoodbye.swift", "return poweringOff && !byMenu ? .powerOff : .quit", "return poweringOff ? .powerOff : .quit"),
    ("the menu's Quit a power off without willPowerOff", "HostGoodbye.swift", "return poweringOff && !byMenu ? .powerOff : .quit", "return poweringOff || byMenu ? .powerOff : .quit"),
    ("willPowerOff counts for good", "HostGoodbye.swift", "return now >= since && now - since < powerOffStands", "return now >= since"),
    ("willPowerOff counts at its ten minutes too", "HostGoodbye.swift", "return now >= since && now - since < powerOffStands", "return now >= since && now - since <= powerOffStands"),
    ("a time before willPowerOff counts", "HostGoodbye.swift", "return now >= since && now - since < powerOffStands", "return now - since < powerOffStands"),
    ("willPowerOff counts one minute", "HostGoodbye.swift", "package static let powerOffStands: Double = 600", "package static let powerOffStands: Double = 60"),
    ("no willPowerOff counts as one", "HostGoodbye.swift", "        guard let since else { return false }\n        return now >= since && now - since < powerOffStands", "        guard let since else { return true }\n        return now >= since && now - since < powerOffStands"),
    ("the quit's goodbye with words", "HostGoodbye.swift", "case .quit: return Goodbye(reason: Goodbye.quit)", "case .quit: return Goodbye(reason: Goodbye.quit, message: \"\\(mac) quit Sill.\")"),
    ("the sleep's goodbye as a shut down", "HostGoodbye.swift", "case .sleep: return Goodbye.asleep(mac: mac)", "case .sleep: return Goodbye.shuttingDown(mac: mac)"),
    ("a shut down's goodbye as a restart", "HostGoodbye.swift", "case .shutDown: return Goodbye.shuttingDown(mac: mac)", "case .shutDown: return Goodbye.restarting(mac: mac)"),
    ("the power-off goodbye as a shut down", "HostGoodbye.swift", "case .powerOff: return Goodbye.shuttingDownOrRestarting(mac: mac)", "case .powerOff: return Goodbye.shuttingDown(mac: mac)"),
    ("the power-off goodbye as a restart", "HostGoodbye.swift", "case .powerOff: return Goodbye.shuttingDownOrRestarting(mac: mac)", "case .powerOff: return Goodbye.restarting(mac: mac)"),
    ("only the attribute read", "HostGoodbye.swift", "event.paramDescriptor(forKeyword: keyword) ?? event.attributeDescriptor(forKeyword: keyword)", "event.attributeDescriptor(forKeyword: keyword)"),
    ("only the parameter read", "HostGoodbye.swift", "event.paramDescriptor(forKeyword: keyword) ?? event.attributeDescriptor(forKeyword: keyword)", "event.paramDescriptor(forKeyword: keyword)"),
    ("the attribute before the parameter", "HostGoodbye.swift", "event.paramDescriptor(forKeyword: keyword) ?? event.attributeDescriptor(forKeyword: keyword)", "event.attributeDescriptor(forKeyword: keyword) ?? event.paramDescriptor(forKeyword: keyword)"),
    ("any Apple event's reason", "HostGoodbye.swift", "guard let event, event.eventClass == coreEventClass, event.eventID == quitApplication else { return nil }", "guard let event else { return nil }"),
    ("any event class's quit", "HostGoodbye.swift", "guard let event, event.eventClass == coreEventClass, event.eventID == quitApplication else { return nil }", "guard let event, event.eventID == quitApplication else { return nil }"),
    ("a zero reason counted", "HostGoodbye.swift", "return code == 0 ? nil : code", "return code"),
    ("a line with no device connected", "HostGoodbye.swift", "        guard devices > 0 else { return nil }\n", ""),
    ("the count's plural backwards", "HostGoodbye.swift", "\\(devices == 1 ? \"\" : \"s\") told.", "\\(devices > 1 ? \"\" : \"s\") told."),
    ("a line for a quit too", "HostGoodbye.swift", "        case .quit: return nil\n", "        case .quit: return \"Sill quit: \\(told)\"\n"),
    ("the shut down's line says restarting", "HostGoodbye.swift", "case .shutDown: return \"The Mac is shutting down: \\(told)\"", "case .shutDown: return \"The Mac is restarting: \\(told)\""),
    ("the power-off line says shutting down", "HostGoodbye.swift", "case .powerOff: return \"The Mac is shutting down or restarting: \\(told)\"", "case .powerOff: return \"The Mac is shutting down: \\(told)\""),
    ("willPowerOff's own line says a shut down", "HostGoodbye.swift", "about to log out, restart or shut down.\"", "about to shut down.\""),
    ("the quit's reason never logged", "HostGoodbye.swift", "        guard let reason else { return nil }\n        if restartReasons", "        guard let reason, reason == 0 else { return nil }\n        if restartReasons"),
    ("a log out logged as a shut down", "HostGoodbye.swift", "if logOutReasons.contains(reason) { return \"Quit: macOS asked Sill to quit for a log out.\" }", "if logOutReasons.contains(reason) { return \"Quit: macOS asked Sill to quit for a shut down.\" }"),
    ("an unprintable code printed as characters", "HostGoodbye.swift", "(0x20...0x7E).contains($0)", "(0x00...0xFF).contains($0)"),
    # The Mac between its sleep goodbye and its wake (SleepWindow, the review of PR #100 of 2026-10-26).
    ("the sleep window never opens", "HostGoodbye.swift", "package mutating func willSleep(at now: Double) { since = now }", "package mutating func willSleep(at now: Double) { }"),
    ("a willSleep again keeps the first window", "HostGoodbye.swift", "package mutating func willSleep(at now: Double) { since = now }", "package mutating func willSleep(at now: Double) { since = since ?? now }"),
    ("didWake leaves the doors shut", "HostGoodbye.swift", "package mutating func didWake() { since = nil }", "package mutating func didWake() { }"),
    ("no limit: a lost didWake shuts the doors for good", "HostGoodbye.swift", "return now >= since && now - since < Self.limit", "return now >= since"),
    ("a clock before willSleep counts as asleep", "HostGoodbye.swift", "return now >= since && now - since < Self.limit", "return now - since < Self.limit"),
    ("asleep at exactly the limit", "HostGoodbye.swift", "return now >= since && now - since < Self.limit", "return now >= since && now - since <= Self.limit"),
    ("the limit one minute", "HostGoodbye.swift", "package static let limit: Double = 600", "package static let limit: Double = 60"),
    ("lapsed while still asleep", "HostGoodbye.swift", "package func lapsed(at now: Double) -> Bool { since != nil && !asleep(at: now) }", "package func lapsed(at now: Double) -> Bool { since != nil }"),
    ("never lapsed", "HostGoodbye.swift", "package func lapsed(at now: Double) -> Bool { since != nil && !asleep(at: now) }", "package func lapsed(at now: Double) -> Bool { false }"),
    ("the refusal a quit goodbye", "HostGoodbye.swift", "asleep(at: now) ? HostGoodbye.goodbye(.sleep, mac: mac) : nil", "asleep(at: now) ? HostGoodbye.goodbye(.quit, mac: mac) : nil"),
    ("the refusal a shut down's (the device would hold 10 minutes)", "HostGoodbye.swift", "asleep(at: now) ? HostGoodbye.goodbye(.sleep, mac: mac) : nil", "asleep(at: now) ? HostGoodbye.goodbye(.restart, mac: mac) : nil"),
    ("every session refused", "HostGoodbye.swift", "asleep(at: now) ? HostGoodbye.goodbye(.sleep, mac: mac) : nil", "HostGoodbye.goodbye(.sleep, mac: mac)"),
    ("no session refused", "HostGoodbye.swift", "asleep(at: now) ? HostGoodbye.goodbye(.sleep, mac: mac) : nil", "nil"),
    ("the wake's line without the count", "HostGoodbye.swift", "(refused > 0 ? \" (\\(refused) session\\(refused == 1 ? \"\" : \"s\") refused while it slept).\" : \".\")", "\".\""),
    ("the refused count's plural backwards", "HostGoodbye.swift", "session\\(n == 1 ? \"\" : \"s\") from", "session\\(n != 1 ? \"\" : \"s\") from"),
    ("the lapsed line in seconds", "HostGoodbye.swift", "\\(Int(limit / 60)) minutes ago", "\\(Int(limit)) minutes ago"),
    ("the refusal's line names no endpoint", "HostGoodbye.swift", "refused a session from \\(endpoint) with the same goodbye.", "refused a session with the same goodbye."),
]
caught = 0
for name, file, old, new in MUTANTS:
    src = open(os.path.join(WT, FILES[file])).read()
    if src.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {src.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        mf = os.path.join(t, file); open(mf, "w").write(src.replace(old, new, 1))
        exe = os.path.join(t, "c")
        subprocess.run([os.path.join(HERE, "build.sh"), WT, exe, mf], capture_output=True, text=True)
        if not os.path.exists(exe): print(f"{name}: did not compile"); continue
        r = subprocess.run([exe], capture_output=True, text=True, timeout=300)
        failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        if r.returncode != 0:
            caught += 1
            print(f"{name}: caught ({failed[0][:90] if failed else f'exit status {r.returncode}'})")
        else:
            print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
