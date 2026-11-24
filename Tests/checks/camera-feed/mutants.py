"""CameraFeedPolicy mutants (Sources/CameraFeed/CameraFeedPolicy.swift): each must compile and make
camera-feed/main.swift fail. usage: mutants.py ROOT"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import module
F = "Sources/CameraFeed/CameraFeedPolicy.swift"
M = [
    # The formats and rates.
    ("1920×1080 first", F, "    package static let formats = [Format(width: 1280, height: 720), Format(width: 1920, height: 1080)]",
     "    package static let formats = [Format(width: 1920, height: 1080), Format(width: 1280, height: 720)]"),
    ("full range NV12", F, "    package static let pixelFormat: UInt32 = 0x3432_3076", "    package static let pixelFormat: UInt32 = 0x3432_3066"),
    ("up to 60 fps", F, "    package static let fpsRange = 15...30", "    package static let fpsRange = 15...60"),
    ("a rate truncated, not rounded", F, "        let rate = (1 / seconds).rounded()", "        let rate = (1 / seconds).rounded(.down)"),
    ("a negative duration read as a rate", F, "        guard seconds.isFinite, seconds > 0 else { return defaultFps }",
     "        guard seconds.isFinite, seconds != 0 else { return defaultFps }"),
    ("a frame stands three seconds", F, "    package static let frameLifetime: Double = 1", "    package static let frameLifetime: Double = 3"),
    # The state.
    ("no cap on the state", F, "        guard text.utf8.count <= stateCap, let data = text.data(using: .utf8),\n              let j = try? JSONDecoder().decode(ShowJSON.self, from: data) else { return nil }",
     "        guard let data = text.data(using: .utf8),\n              let j = try? JSONDecoder().decode(ShowJSON.self, from: data) else { return nil }"),
    ("names of 64 characters", F, "    package static let nameCap = 40", "    package static let nameCap = 64"),
    ("line breaks kept in a name", F, "                CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0)\n                    || $0.properties.generalCategory == .format",
     "                $0.properties.generalCategory == .format"),
    # No mutant drops cleanName's format clause: CharacterSet.controlCharacters already holds Cf, so nothing changes.
    ("an empty name taken", F, "            return name.isEmpty ? nil : .device(name: name, paused: j.paused ?? false)",
     "            return .device(name: name, paused: j.paused ?? false)"),
    ("an unknown word read as waiting", F, "        default: return nil", "        default: return .waiting"),
    ("paused left out read as paused", F, "            return name.isEmpty ? nil : .device(name: name, paused: j.paused ?? false)",
     "            return name.isEmpty ? nil : .device(name: name, paused: j.paused ?? true)"),
    # The demand.
    ("any size in a demand", F, "              formats.contains(Format(width: d.width, height: d.height)), fpsRange.contains(d.fps),",
     "              fpsRange.contains(d.fps),"),
    ("any rate in a demand", F, "              formats.contains(Format(width: d.width, height: d.height)), fpsRange.contains(d.fps),",
     "              formats.contains(Format(width: d.width, height: d.height)),"),
    ("an app's identifier as it came", F, "            self.id = id.map { String($0.unicodeScalars.filter { $0.isASCII && $0.value > 0x20 && $0.value < 0x7F }.prefix(CameraFeedPolicy.appIDCap)) }",
     "            self.id = id"),
    ("apps in the demand while nothing runs", F, "fps: fps, apps: running ? apps : [])", "fps: fps, apps: apps)"),
    ("a stopped stream keeps its apps", F, "        if starts == 0 { apps = []; lastSentAt = nil; placeholderSent = nil }", "        if starts == 0 { lastSentAt = nil; placeholderSent = nil }"),
    ("the first stop ends the run", F, "        starts = max(0, starts - 1)", "        starts = 0"),
    ("stops below none", F, "        starts = max(0, starts - 1)", "        starts -= 1"),
    ("no cap on the apps", F, "        let list = Array(now.prefix(Self.appsCap))", "        let list = now"),
    ("an app that left stays", F, "        apps.removeAll { $0.pid == pid }\n", ""),
    # The feeder.
    ("any app feeds it", F, "        guard id == sillIdentifier else { return .notSill }\n", ""),
    ("a foreign signature feeds it", F, "        if signatureValid == false { return .signature }\n", ""),
    ("an unchecked signature refused", F, "        if signatureValid == false { return .signature }", "        if signatureValid != true { return .signature }"),
    ("a second Sill takes over", F, "        if let f = feeder, f != client { return .busy }\n", ""),
    ("a stop by anyone ends the feed", F, "        guard feeder == client else { return }\n        feeder = nil", "        feeder = nil"),
    ("what Sill said outlives it", F, "        feeder = nil\n        show = nil\n", "        feeder = nil\n"),
    ("its frame outlives it", F, "        feeder = nil\n        show = nil\n        frameAt = nil\n", "        feeder = nil\n        show = nil\n"),
    ("a state taken while nothing feeds", F, "        guard feeder != nil, let s = Self.decode(text) else { return false }",
     "        guard let s = Self.decode(text) else { return false }"),
    ("a state never retires the frame", F, "        if !keep {\n            frameAt = nil", "        if false {\n            frameAt = nil"),
    ("the same device live retires it", F, "        if case .device(let name, false) = s, case .device(let before, false)? = show { keep = name == before }",
     "        if case .device(let name, false) = s, case .device(let before, false)? = show { keep = name != before }"),
    ("a pause keeps the frame", F, "        if case .device(let name, false) = s, case .device(let before, false)? = show { keep = name == before }",
     "        if case .device(let name, _) = s, case .device(let before, false)? = show { keep = name == before }"),
    # Frames.
    ("anyone's frames", F, "        guard client == feeder else { return .notFeeder }\n", ""),
    ("frames while not live", F, "        guard case .device(_, false)? = show else { return .notLive }\n", ""),
    ("frames while paused", F, "        guard case .device(_, false)? = show else { return .notLive }", "        guard case .device? = show else { return .notLive }"),
    ("any pixel format", F, "        guard pixelFormat == Self.pixelFormat else { return .wrongFormat }\n", ""),
    ("any size", F, "        guard width == format.width, height == format.height else { return .wrongSize }\n", ""),
    ("a frame with more behind it sent", F, "        guard running, !more else {", "        guard running else {"),
    ("a frame sent while nothing runs", F, "        guard running, !more else {", "        guard !more else {"),
    ("a new size keeps the frame", F, "            formatIndex = index\n            frameAt = nil\n", "            formatIndex = index\n"),
    ("a format out of range taken", F, "        guard Self.formats.indices.contains(index) else { return false }", "        guard index >= 0, index <= Self.formats.count else { return false }"),
    # The timer and the words.
    ("ticks while nothing runs", F, "        guard running else { return nil }\n        let due", "        let due"),
    ("no slack", F, "now - $0 >= 1 / Double(fps) - Self.tickInterval / 2 }", "now - $0 >= 1 / Double(fps) }"),
    ("the frame again at every tick", F, "            guard !frameSent || due else { return nil }\n", ""),
    ("an old frame for ever", F, "        if feeder != nil, let at = frameAt, now - at < Self.frameLifetime {", "        if feeder != nil, let at = frameAt, now - at < .infinity {"),
    ("new words wait for the frame duration", F, "        guard due || p != placeholderSent else { return nil }", "        guard due else { return nil }"),
    ("the placeholder at every tick", F, "        guard due || p != placeholderSent else { return nil }\n", ""),
    ("nothing said read as waiting", F, "            case .none, .unavailable: line = Copy.unavailable\n            case .off: line = Copy.off\n            case .waiting: line = Copy.waiting",
     "            case .unavailable: line = Copy.unavailable\n            case .off: line = Copy.off\n            case .none, .waiting: line = Copy.waiting"),
    ("paused and starting swapped", F, "line = paused ? Copy.paused(name) : Copy.starting(name)", "line = paused ? Copy.starting(name) : Copy.paused(name)"),
    ("off read as unavailable", F, "            case .off: line = Copy.off\n", "            case .off: line = Copy.unavailable\n"),
]
sys.exit(0 if module.mutate("camera-feed", M, sys.argv[1]) else 1)
