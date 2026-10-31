"""LockPolicy mutants (Sources/SillHost/LockPolicy.swift, and StreamProtocol's LockedMac): each must compile
and make lock-policy/main.swift fail. usage: mutants.py ROOT"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import module
F = "Sources/SillHost/LockPolicy.swift"
S = "Sources/StreamProtocol/Switcher.swift"
M = [
    # decide: the table.
    ("decide: the lock weighs nothing", F, "        guard locked else { return .take }\n        switch request {",
     "        guard true else { return .take }\n        return .take\n        switch request {"),
    ("decide: refuses everything unlocked", F, "        guard locked else { return .take }\n        switch request {",
     "        guard locked else { return .refuse(.pick) }\n        switch request {"),
    ("decide: a window picked while locked is taken", F, "case .pick(.window): return .refuse(.pick)", "case .pick(.window): return .take"),
    ("decide: the Desktop picked while locked is refused", F, "case .pick: return .take ", "case .pick: return .refuse(.pick) "),
    ("decide: a launch while locked is taken", F, "case .launch: return .refuse(.launch)", "case .launch: return .take"),
    ("decide: a window's buttons while locked are taken", F, "case .windowCommand: return .refuse(.windowCommand)", "case .windowCommand: return .take"),
    ("decide: a menu while locked is taken", F, "case .menuRequest: return .refuse(.menus)", "case .menuRequest: return .take"),
    ("decide: a menu refused as a pick", F, "case .menuRequest: return .refuse(.menus)", "case .menuRequest: return .refuse(.pick)"),
    ("decide: a gesture while locked is taken", F, "case .gesture: return .refuse(.gesture)", "case .gesture: return .take"),
    ("decide: a clipboard text while locked is written", F, "case .clipboardText: return .refuse(.clipboard)", "case .clipboardText: return .take"),
    ("decide: input from anyone while locked", F, "case .input(let letsGo): return paired ? .take : (letsGo ? .letGo : .refuse(.input))",
     "case .input: return .take"),
    ("decide: a paired session's input refused while locked", F, "case .input(let letsGo): return paired ? .take : (letsGo ? .letGo : .refuse(.input))",
     "case .input(let letsGo): return letsGo ? .letGo : .refuse(.input)"),
    ("decide: an unpaired session's up taken whole", F, "case .input(let letsGo): return paired ? .take : (letsGo ? .letGo : .refuse(.input))",
     "case .input(let letsGo): return paired || letsGo ? .take : .refuse(.input)"),
    ("decide: an unpaired session's up dropped too", F, "case .input(let letsGo): return paired ? .take : (letsGo ? .letGo : .refuse(.input))",
     "case .input: return paired ? .take : .refuse(.input)"),
    ("decide: the subscriptions refused while locked", F, "case .menuSubscription, .clipboardSubscription, .other: return .take",
     "case .menuSubscription, .clipboardSubscription: return .refuse(.menus)\n        case .other: return .take"),
    ("decide: settings and the rest refused while locked", F, "case .menuSubscription, .clipboardSubscription, .other: return .take",
     "case .menuSubscription, .clipboardSubscription: return .take\n        case .other: return .refuse(.pick)"),
    # shown.
    ("shown: thumbnails while locked", F, "Shown(thumbnails: !locked,", "Shown(thumbnails: true,"),
    ("shown: icons and apps while locked", F, "appsAndIcons: !locked,", "appsAndIcons: true,"),
    ("shown: menus while locked", F, "menus: !locked,", "menus: true,"),
    ("shown: sound while locked", F, "sound: !locked,", "sound: true,"),
    ("shown: the clipboard while locked", F, "clipboard: !locked)", "clipboard: true)"),
    ("shown: nothing unlocked", F, "Shown(thumbnails: !locked,", "Shown(thumbnails: false,"),
    # list.
    ("list: unlocked lists change too", F, "        guard locked else { return list }\n        var l = list", "        var l = list"),
    ("list: windows kept while locked", F, "        l.windows = []\n", ""),
    ("list: clipboard kept while locked", F, "        l.clipboard = nil\n", ""),
    ("list: no `locked` while locked", F, "        l.locked = true\n", ""),
    ("list: `locked` false while locked", F, "        l.locked = true\n", "        l.locked = false\n"),
    # State.read.
    ("read: every reading a change", F, "            guard now != locked else { return nil }\n", ""),
    ("read: the state never moves", F, "            locked = now\n            return now ? .locked : .unlocked", "            return now ? .locked : .unlocked"),
    ("read: the change named backwards", F, "            return now ? .locked : .unlocked", "            return now ? .unlocked : .locked"),
    # State.select.
    ("select: a pick after the unlock keeps what comes back", F, "                if pick { comesBack = nil }\n", ""),
    ("select: a restart forgets what comes back", F, "                if pick { comesBack = nil }\n", "                comesBack = nil\n"),
    ("select: a window streams while locked", F, "            guard case .window(let id) = source else { return .proceed }\n            comesBack = id\n            return active == .desktop ? .stay : .desktop",
     "            guard case .window(let id) = source else { return .proceed }\n            comesBack = id\n            return .proceed"),
    ("select: the window not remembered", F, "            comesBack = id\n            return active == .desktop", "            return active == .desktop"),
    ("select: the Desktop always restarted", F, "            return active == .desktop ? .stay : .desktop", "            return .desktop"),
    ("select: nothing ever restarted for the lock", F, "            return active == .desktop ? .stay : .desktop", "            return .stay"),
    ("select: the gate unlocked", F, "            guard locked else {\n                if pick", "            guard !locked else {\n                if pick"),
    # State.afterUnlock and devicesLeft.
    ("afterUnlock: a window no longer listed comes back", F, "let id = comesBack, listed.contains(id), active == .desktop, devices > 0",
     "let id = comesBack, active == .desktop, devices > 0"),
    ("afterUnlock: over another pick's source", F, "let id = comesBack, listed.contains(id), active == .desktop, devices > 0",
     "let id = comesBack, listed.contains(id), devices > 0"),
    ("afterUnlock: with nobody connected", F, "let id = comesBack, listed.contains(id), active == .desktop, devices > 0",
     "let id = comesBack, listed.contains(id), active == .desktop"),
    ("afterUnlock: while locked again", F, "            guard !locked, let id = comesBack,", "            guard let id = comesBack,"),
    ("afterUnlock: comes back twice", F, "            defer { if !locked { comesBack = nil } }\n", ""),
    ("afterUnlock: forgotten when locked again", F, "            defer { if !locked { comesBack = nil } }", "            defer { comesBack = nil }"),
    ("devicesLeft: remembered for the next device", F, "        mutating func devicesLeft() { comesBack = nil }", "        mutating func devicesLeft() {}"),
    # The test file, the poll.
    ("the file: any text says locked", F, "contents?.trimmingCharacters(in: .whitespacesAndNewlines) == \"1\"", "contents != nil"),
    ("the file: white space not trimmed", F, "contents?.trimmingCharacters(in: .whitespacesAndNewlines) == \"1\"", "contents == \"1\""),
    ("the poll: every 5 s", F, "static let pollInterval: Double = 1", "static let pollInterval: Double = 5"),
    # The lines.
    ("the lock's line", F, "devices see the lock screen until it is unlocked.\"", "devices see the lock screen.\""),
    ("the unlock's line", F, "devices see its windows again.\"", "devices see it again.\""),
    ("the menus' note", F, "static let menuNote = \"The Mac is locked.\"", "static let menuNote = \"The menus changed. Open the menu again.\""),
    ("a count of none reads as none", F, "        let n = max(1, count)", "        let n = count"),
    ("picks counted as one", F, "case .pick: what = n == 1 ? \"a window pick\" : \"\\(n) window picks\"", "case .pick: what = \"a window pick\""),
    ("launches' words", F, "\"\\(n) app launches\"", "\"\\(n) app launchs\""),
    ("input's words", F, "\" from unpaired devices\"", "\" from devices\""),
    ("the clipboard's words", F, "\"; the clipboard waits for this Mac to be unlocked.\"", "\".\""),
    # The device's line.
    ("LockedMac: no name for an empty one", S, "\"\\(mac.isEmpty ? \"The Mac\" : mac) is locked.", "\"\\(mac) is locked."),
    ("LockedMac: the words", S, "is locked. Unlock it to see its windows.\"", "is locked.\""),
]
sys.exit(0 if module.mutate("lock-policy", M, sys.argv[1]) else 1)
