"""Mutants of Sill.app's side of Sill Camera: CameraExtensionPolicy (Sources/SillMenuBar/CameraExtensionState.swift) and
CameraSinkPolicy (Sources/CameraFeed/CameraSinkPolicy.swift). Each must compile and make camera-app/main.swift fail.
usage: mutants.py ROOT"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import module
X = "Sources/SillMenuBar/CameraExtensionState.swift"
S = "Sources/CameraFeed/CameraSinkPolicy.swift"
M = [
    # Who may ask.
    ("the dry run refused as a real Sill", X, "        guard f.real else { return nil }\n", ""),
    ("no install entitlement needed", X, "        if !f.extensionInside || !f.entitled { return .unsupportedBuild }", "        if !f.extensionInside { return .unsupportedBuild }"),
    ("any folder will do", X, "        if !f.inApplications { return .needsApplications }\n", ""),
    # The switch.
    ("asked again while on", X, "            guard on != m.switchOn else { return [] }\n", ""),
    ("off forgets nothing", X, "            default: m.request = .none\n", "            default: break\n"),
    ("Try Again while off", X, "        case .tryAgain:\n            guard m.switchOn else { return [] }\n", "        case .tryAgain:\n"),
    ("a refusal asks anyway", X, "        if let r = refusal(m.facts) {\n            m.request = .none\n            return",
     "        if let r = refusal(m.facts), false {\n            m.request = .none\n            return"),
    ("an install for the one installed", X, "        let kind: Activating = m.facts.installedBuild == nil ? .install :", "        let kind: Activating = true ? .install :"),
    ("a start for any build installed", X, "(m.facts.installedBuild == m.facts.build ? .start : .update)", "(.start)"),
    # Removal.
    ("Remove keeps the switch on", X, "        case .remove:\n            m.switchOn = false\n", "        case .remove:\n"),
    ("nothing to remove read as a failure", X, "            if f == .systemExtension(4) {\n                m.request = .removed", "            if false {\n                m.request = .removed"),
    ("a removal forgets nothing", X, "            m.request = .removed\n            m.facts.installedBuild = nil\n            return [.remember(nil), .line(\"Camera extension: removed.\")]",
     "            m.request = .removed\n            return [.line(\"Camera extension: removed.\")]"),
    # macOS's answers.
    ("a replacement outside an activation", X, "        case .replacing(let from, let to):\n            guard case .activating = m.request else { return [] }\n",
     "        case .replacing(let from, let to):\n"),
    ("an approval outside an activation", X, "        case .needsApproval:\n            guard case .activating = m.request else { return [] }\n", "        case .needsApproval:\n"),
    ("an approval after off not remembered", X, "            m.request = m.switchOn ? .activated : .none\n            m.disabledInSettings = false\n",
     "            guard m.switchOn else { return [] }\n            m.request = .activated\n            m.disabledInSettings = false\n"),
    ("superseded read as a failure", X, "            if f == .systemExtension(12) { return [] }\n", ""),
    ("System Settings' switch read backwards", X, "            m.disabledInSettings = !on\n", "            m.disabledInSettings = on\n"),
    # What the section shows.
    ("the feed does not win", X, "        if sink == .feeding { return use.map { .inUse(app: $0.app, device: $0.device) } ?? .ready }\n", ""),
    ("off shows the feed", X, "        guard m.switchOn else {\n            switch m.request {", "        guard m.switchOn || sink == .feeding else {\n            switch m.request {"),
    ("camera access denied not said", X, "        if sink == .cameraDenied { return .cameraDenied }\n", ""),
    ("turned off in System Settings not said", X, "        if m.disabledInSettings { return .disabledInSettings }\n", ""),
    ("a refused Sill shows its request", X, "        if let r = refusal(m.facts) { return r }\n        switch m.request {", "        switch m.request {"),
    ("not in Applications read as a failure", X, "            case 3: return .needsApplications\n", ""),
    ("forbidden read as a failure", X, "            case 10: return .forbidden\n", ""),
    ("an unfed Sill Camera starting for ever", X, "        case .activated: return sink == .refused ? .notFed : .starting", "        case .activated: return .starting"),
    ("the use never named", X, "use.map { .inUse(app: $0.app, device: $0.device) } ?? .ready", "use.map { .inUse(app: nil, device: $0.device) } ?? .ready"),
    # The words.
    ("macOS 14 told of Login Items", X, "        let loginItems = macOS >= 15\n", "        let loginItems = macOS >= 14\n"),
    ("ready without Remove", X, "            return Words(line: \"Ready. Apps on this Mac can choose “Sill Camera”.\", attention: false, button: nil, remove: true)",
     "            return Words(line: \"Ready. Apps on this Mac can choose “Sill Camera”.\", attention: false, button: nil, remove: false)"),
    ("off and installed without Remove", X, "attention: false, button: nil, remove: true)\n                : Words(line: nil", "attention: false, button: nil, remove: false)\n                : Words(line: nil"),
    ("a failure without Try Again", X, "attention: true, button: .tryAgain, remove: false)", "attention: true, button: nil, remove: false)"),
    ("two reasons the same", X, "        case 9: return \"macOS couldn’t validate it\"", "        case 9: return \"its signature isn’t valid\""),
    ("the app unnamed as empty", X, "\"In use by \\(app.flatMap { $0.isEmpty ? nil : $0 } ?? \"an app\")", "\"In use by \\(app ?? \"an app\")"),
    # The dry run's script.
    ("the script in the order written", X, "        return steps.enumerated().sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }.map(\\.element)",
     "        return steps"),
    ("fail:0 read", X, "w.hasPrefix(\"fail:\"), let n = Int(w.dropFirst(5)), (1...99).contains(n)", "w.hasPrefix(\"fail:\"), let n = Int(w.dropFirst(5)), (0...99).contains(n)"),
    ("any number of steps", X, "        guard !steps.isEmpty, steps.count <= 16 else { return nil }", "        guard !steps.isEmpty else { return nil }"),
    # The sink.
    ("a pause shown live", S, "        case .device(let name, let pause): return .device(name: name, paused: pause != nil)",
     "        case .device(let name, _): return .device(name: name, paused: false)"),
    ("an app named twice", S, "            if !clean.isEmpty, !names.contains(clean) { names.append(clean) }", "            if !clean.isEmpty { names.append(clean) }"),
    ("two apps as one and more", S, "        case 2: joined = \"\\(first) and \\(names[1])\"\n", ""),
    ("no cap on two names", S, "        return joined.count > CameraFeedPolicy.nameCap ? CameraFeedPolicy.cleanName(String(joined.prefix(CameraFeedPolicy.nameCap))) : joined",
     "        return joined"),
    ("an app gone unnamed", S, "            let raw = name(app.pid) ?? app.id.map(lastPart) ?? \"\"", "            let raw = name(app.pid) ?? \"\""),
    ("a use while nothing runs", S, "        guard let text = demandText, let d = CameraFeedPolicy.decodeDemand(text), d.running else { return nil }",
     "        guard let text = demandText, let d = CameraFeedPolicy.decodeDemand(text) else { return nil }"),
    ("an identifier whole", S, "        identifier.split(separator: \".\").last.map(String.init) ?? identifier", "        identifier"),
    ("a third frame in the queue", S, "        guard count >= max(1, capacity) else {", "        guard count > max(1, capacity) else {"),
    ("the older frame keeps its wait", S, "            let had = pendingSince != nil\n            pendingSince = now\n",
     "            let had = pendingSince != nil\n            if !had { pendingSince = now }\n"),
    ("room keeps the older frame waiting", S, "                // Room: an older pending frame would be older than this one, so it goes (never two in a row out of order).\n                pendingSince = nil\n",
     ""),
    ("a stale frame goes in", S, "            return now - since < CameraFeedPolicy.frameLifetime", "            return true"),
    ("a full queue takes the frame waiting", S, "            guard count < max(1, capacity) else { return false }\n", ""),
]
sys.exit(0 if module.mutate("camera-app", M, sys.argv[1]) else 1)
