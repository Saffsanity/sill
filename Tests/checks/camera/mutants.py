"""CameraPolicy mutants (iOSClient/CameraPolicy.swift): each must compile and make camera/main.swift fail.
usage: mutants.py ROOT"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import module
F = "iOSClient/CameraPolicy.swift"
M = [
    # The row.
    ("the row on a locked Mac", F, "        if locked { return .hidden }\n", ""),
    ("an older Sill.app hidden", F, "return hostVersion == nil ? .hidden : .updateMac", "return .hidden"),
    ("camera 0 the switch", F, "return camera >= CameraCodec.generation ? .enabled : .disabled", "return .enabled"),
    # Offering, capturing, the pause.
    ("offers with the switch off", F, "        switchOn && connected && (hostCamera ?? 0) >= CameraCodec.generation", "        connected && (hostCamera ?? 0) >= CameraCodec.generation"),
    ("offers to a Mac that says 0", F, "(hostCamera ?? 0) >= CameraCodec.generation\n    }\n\n    /// The capture", "(hostCamera ?? -1) >= 0\n    }\n\n    /// The capture"),
    ("captures without being wanted", F, "        offering && state?.wanted == true && pause(state: state, device: device) == nil", "        offering && pause(state: state, device: device) == nil"),
    ("captures in the background", F, "        if !d.front { return CameraFormat.background }\n", ""),
    ("captures while multitasking", F, "        if d.multitasking { return CameraFormat.multitasking }\n", ""),
    ("captures at shutdown pressure", F, "        if d.pressure == .shutdown { return CameraFormat.thermal }\n", ""),
    ("the scanner before multitasking", F, "        if d.multitasking { return CameraFormat.multitasking }\n        if d.scanner { return CameraFormat.scanner }",
     "        if d.scanner { return CameraFormat.scanner }\n        if d.multitasking { return CameraFormat.multitasking }"),
    ("busy said as waiting", F, "        if d.busy { return CameraFormat.busy }\n", ""),
    # The format and the heat.
    ("away at 1080p", F, "        let capped = away || pressure >= .critical", "        let capped = pressure >= .critical"),
    ("60 fps", F, "        var fps = min(demand?.fps ?? 30, CameraCodec.rates.upperBound)", "        var fps = demand?.fps ?? 30"),
    ("upright ignored", F, "        return upright ? (h, w, fps) : (w, h, fps)", "        return (w, h, fps)"),
    ("an unsupported size kept", F, "        if !supports(w, h, fps) { (w, h) = (1280, 720) }\n", ""),
    ("serious at 30", F, "        case .serious: return 20", "        case .serious: return 30"),
    # The bitrate.
    ("away at the home bitrate", F, "        if away { rate = min(rate, 1_200_000) }\n", ""),
    ("the demand's ceiling ignored", F, "        if let ceiling, ceiling > 0 { rate = min(rate, Double(ceiling)) }\n", ""),
    ("a drop steps down a half", F, "                current = max(floor, current * 2 / 3)", "                current = max(floor, current / 2)"),
    ("no floor", F, "            let floor = max(300_000, target / 5)", "            let floor = 300_000"),
    ("steps up every second", F, "        static let upEvery: Double = 5", "        static let upEvery: Double = 1"),
    ("steps up past the target", F, "                current = min(target, current + max(1, target / 10))", "                current = current + max(1, target / 10)"),
    # Keyframes, the chip.
    ("a demand's keyframe every time", F, "        return now - (lastDemandedAt ?? -.infinity) >= 1", "        return true"),
    ("a periodic keyframe", F, "        guard demanded else { return false }", "        guard demanded else { return true }"),
    ("the chip while only offering", F, "        guard offering, state?.wanted == true else { return .none }", "        guard offering else { return .none }"),
    ("the chip on while paused", F, "        return capturing ? .on(app: state?.app) : .paused", "        return .on(app: state?.app)"),
    # The words.
    ("an unknown state read as off in the words", F, "            if row == .disabled || state?.state == CameraState.off {", "            if row == .disabled || state?.knownState == CameraState.off {"),
    ("another unnamed as itself", F, "let holder = state?.holder.flatMap { $0.isEmpty ? nil : $0 } ?? \"Another device\"", "let holder = state?.holder ?? \"Another device\""),
    ("Devices instead of Streaming", F, "In Sill’s Settings there, Streaming shows what it needs.", "In Sill’s Settings there, Devices shows what it needs."),
    # The send budget.
    ("no minimum budget", F, "        max(minimumBudget, Int(Double(takenLastSecond) * budgetSeconds))", "        Int(Double(takenLastSecond) * budgetSeconds)"),
    ("encodes under a fence", F, "        if fenced || unsent > Self.budget(takenLastSecond: takenLastSecond) { skipped += 1; return false }",
     "        if unsent > Self.budget(takenLastSecond: takenLastSecond) { skipped += 1; return false }"),
    ("encodes over the budget", F, "        if fenced || unsent > Self.budget(takenLastSecond: takenLastSecond) { skipped += 1; return false }",
     "        if fenced { skipped += 1; return false }"),
    ("a frame after a drop before a keyframe", F, "        if fenced || (needsKeyframe && !keyframe) { dropped += 1; needsKeyframe = true; return false }",
     "        if fenced { dropped += 1; needsKeyframe = true; return false }"),
    ("a skip forces a keyframe", F, "{ skipped += 1; return false }", "{ skipped += 1; needsKeyframe = true; return false }"),
]
sys.exit(0 if module.mutate("camera", M, sys.argv[1]) else 1)
