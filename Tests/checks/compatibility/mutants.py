"""H3 (docs/update-notice-plan.md) mutants of SillVersion and the payloads: each copies
Sources/StreamProtocol, applies one mutation, compiles it with the check and expects it to fail.
usage: mutants.py WORKTREE"""
import os, shutil, subprocess, sys, tempfile
WT = sys.argv[1]
HERE = os.path.dirname(os.path.abspath(__file__))
MUTANTS = [
    ("no leading v dropped", "Compatibility.swift", "if let first = scalars.first, first == \"v\" || first == \"V\" { scalars.removeFirst() }", ""),
    ("only a lowercase v dropped", "Compatibility.swift", "first == \"v\" || first == \"V\"", "first == \"v\""),
    ("trailing dots kept", "Compatibility.swift", "while prefix.last == \".\" { prefix.removeLast() }", ""),
    ("nine parts allowed", "Compatibility.swift", "guard parts.count <= 8 else", "guard parts.count <= 9 else"),
    ("ten-digit parts allowed", "Compatibility.swift", "(1...9).contains(part.count)", "(1...10).contains(part.count)"),
    ("order reversed", "Compatibility.swift", "if x != y { return x < y }", "if x != y { return x > y }"),
    ("trailing zeros kept", "Compatibility.swift", "while c.last == 0 { c.removeLast() }\n        self.components = c", "self.components = c"),
    ("shown with three parts", "Compatibility.swift", "while c.count < 2 { c.append(0) }", "while c.count < 3 { c.append(0) }"),
    ("any Unicode digit", "Compatibility.swift", "func isDigit(_ s: Unicode.Scalar) -> Bool { s.value >= 0x30 && s.value <= 0x39 }", "func isDigit(_ s: Unicode.Scalar) -> Bool { s.properties.numericType != nil }"),
    ("compared over the shorter only", "Compatibility.swift", "for i in 0..<max(a.components.count, b.components.count) {", "for i in 0..<min(a.components.count, b.components.count) {"),
    ("reconnect false by default (old goodbyes change)", "Remote.swift", "reconnect: Bool? = nil) {", "reconnect: Bool? = false) {"),
    ("protocol 1 by default", "Switcher.swift", "hostVersion: String? = nil, protocol: Int? = nil, gestures", "hostVersion: String? = nil, protocol: Int? = 1, gestures"),
    ("gestures 1 by default", "Switcher.swift", "protocol: Int? = nil, gestures: Int? = nil, clipboard: Int? = nil,", "protocol: Int? = nil, gestures: Int? = 1, clipboard: Int? = nil,"),
    ("clipboard 1 by default", "Switcher.swift", "gestures: Int? = nil, clipboard: Int? = nil,", "gestures: Int? = nil, clipboard: Int? = 1,"),
    ("clipboard never stored", "Switcher.swift", "        self.clipboard = clipboard\n", "        self.clipboard = nil\n"),
    ("kind 32 as 31", "StreamMessage.swift", "case clipboard = 32", "case clipboard = 31"),
    ("gestures never stored", "Switcher.swift", "self.protocol = `protocol`; self.gestures = gestures", "self.protocol = `protocol`; self.gestures = nil"),
    ("fingers 3 by default", "Gesture.swift", "public init(gesture: String, fingers: Int? = nil) {", "public init(gesture: String, fingers: Int? = 3) {"),
    ("a name misspelt", "Gesture.swift", 'public static let swipeLeft = "swipeLeft"', 'public static let swipeLeft = "swipeleft"'),
    ("spread left out of the names", "Gesture.swift", "public static let names = [swipeUp, swipeDown, swipeLeft, swipeRight, pinch, spread]", "public static let names = [swipeUp, swipeDown, swipeLeft, swipeRight, pinch]"),
    ("kind 28 as 250", "StreamMessage.swift", "case gesture = 28", "case gesture = 250"),
    ("pencil 1 by default", "Switcher.swift", "clipboard: Int? = nil,\n                pencil: Int? = nil) {", "clipboard: Int? = nil,\n                pencil: Int? = 1) {"),
    ("pencil never stored", "Switcher.swift", "self.pencil = pencil", "self.pencil = nil"),
    ("kind 45 as 47", "StreamMessage.swift", "case pen = 45", "case pen = 47"),
    ("kind 46 as 47", "StreamMessage.swift", "case cursorKind = 46", "case cursorKind = 47"),
    ("the cursor's kind under another name", "Viewport.swift", "    public var standard: Bool?\n    public init(standard: Bool?) { self.standard = standard }",
     "    public var isStandard: Bool?\n    public init(standard: Bool?) { self.isStandard = standard }"),
    ("a phase misspelt", "Pen.swift", 'public static let cancel = "cancel"', 'public static let cancel = "cancelled"'),
    ("leave left out of the phases", "Pen.swift", "public static let phases = [hover, down, move, up, cancel, leave]", "public static let phases = [hover, down, move, up, cancel]"),
    ("33 samples taken", "Pen.swift", "guard given.count <= Self.maxSamples else { return nil }", "guard given.count <= Self.maxSamples + 1 else { return nil }"),
    ("an unknown phase taken", "Pen.swift", "guard Self.phases.contains(phase) else { return nil }", ""),
    ("a leave keeps its samples", "Pen.swift", "if phase == Self.leave { return PenInput(phase: phase) }", "if phase == Self.leave { return self }"),
    ("a move without samples taken", "Pen.swift", "case Self.move: guard cleaned.count >= 1 else { return nil }", "case Self.move: break"),
    ("a cancel with two samples taken", "Pen.swift", "case Self.cancel: guard cleaned.count <= 1 else { return nil }", "case Self.cancel: break"),
    ("a down with two samples taken", "Pen.swift", "default: guard cleaned.count == 1 else { return nil }", "default: guard cleaned.count >= 1 else { return nil }"),
    ("a bad sample dropped, the rest taken", "Pen.swift", "guard let ok = sample.checked() else { return nil }", "guard let ok = sample.checked() else { continue }"),
    ("a position at 4 places", "Pen.swift", "self.x = Self.rounded(x, places: 100_000)", "self.x = Self.rounded(x, places: 10_000)"),
    ("pressure not rounded", "Pen.swift", "self.p = p.map { Self.rounded($0, places: 10_000) }", "self.p = p"),
    ("pressure not clamped", "Pen.swift", "sample.p = p.map { min(max($0, 0), 1) }", "sample.p = p"),
    ("altitude clamped to π", "Pen.swift", "sample.alt = alt.map { min(max($0, 0), .pi / 2) }", "sample.alt = alt.map { min(max($0, 0), .pi) }"),
    ("a negative time kept", "Pen.swift", "sample.t = t.map { max($0, 0) }", "sample.t = t"),
    ("a non-finite pressure let through", "Pen.swift", "guard x.isFinite, y.isFinite, [p, alt, az, t].allSatisfy({ $0?.isFinite ?? true }) else { return nil }", "guard x.isFinite, y.isFinite else { return nil }"),
    ("a non-finite position let through", "Pen.swift", "guard x.isFinite, y.isFinite, [p, alt, az, t]", "guard [p, alt, az, t]"),
    ("device never nil", "Compatibility.swift", "self.appVersion = appVersion; self.build = build; self.protocol = `protocol`; self.device = device", "self.appVersion = appVersion; self.build = build; self.protocol = `protocol`; self.device = device ?? \"\""),
    # The Mac's sound (docs/audio-plan.md §3.4): the hello's codecs, the host's pick, Send Audio, the note, the stats.
    ("the hello's codecs never kept", "Compatibility.swift", "        self.audio = audio\n", "        self.audio = nil\n"),
    ("the pick takes the host's order", "Audio.swift", "return offered.first { makes.contains($0) }", "return makes.first { offered.contains($0) }"),
    ("the pick takes the device's last", "Audio.swift", "return offered.first { makes.contains($0) }", "return offered.last { makes.contains($0) }"),
    ("the pick ignores what the host makes", "Audio.swift", "return offered.first { makes.contains($0) }", "return offered.first"),
    ("the pick folds case", "Audio.swift", "return offered.first { makes.contains($0) }", "return offered.first { c in makes.contains { $0 == c.lowercased() } }"),
    ("Send Audio never kept in the settings", "HostSettings.swift", "        self.sendAudio = sendAudio\n    }\n}\n\n/// The pipeline", "        self.sendAudio = nil\n    }\n}\n\n/// The pipeline"),
    ("Send Audio left out of isEmpty", "HostSettings.swift", "&& directWireless == nil && sendAudio == nil", "&& directWireless == nil"),
    ("Send Audio left out of applied(to:)", "HostSettings.swift", "        if let v = sendAudio { r.sendAudio = v }\n", ""),
    ("a change's Send Audio never kept", "HostSettings.swift", "        self.directWireless = directWireless\n        self.sendAudio = sendAudio\n    }\n\n    /// All setting", "        self.directWireless = directWireless\n        self.sendAudio = nil\n    }\n\n    /// All setting"),
    ("the audio note never kept", "HostSettings.swift", "self.audioNote = audioNote", "self.audioNote = nil"),
    # Kind 16's sessionPaired (2026-10-29, the security scan's finding 8).
    ("sessionPaired never kept", "HostSettings.swift", "        self.sessionPaired = sessionPaired\n", "        self.sessionPaired = nil\n"),
    ("sessionPaired false by default", "HostSettings.swift", "                sessionPaired: Bool? = nil) {", "                sessionPaired: Bool? = false) {"),
    ("the late count never kept", "Viewport.swift", "self.audioBehindMs = audioBehindMs; self.audioLate = audioLate", "self.audioBehindMs = audioBehindMs; self.audioLate = nil"),
    ("kind 43 as 253", "StreamMessage.swift", "    case audio = 43 ", "    case audio = 253 "),
]
caught = 0
for name, file, old, new in MUTANTS:
    with tempfile.TemporaryDirectory() as t:
        src = os.path.join(t, "StreamProtocol"); shutil.copytree(os.path.join(WT, "Sources/StreamProtocol"), src)
        path = os.path.join(src, file); text = open(path).read()
        if text.count(old) != 1:
            print(f"{name}: NOT APPLIED (pattern found {text.count(old)} times)"); continue
        open(path, "w").write(text.replace(old, new, 1))
        files = [os.path.join(src, f) for f in sorted(os.listdir(src)) if f.endswith(".swift")]
        exe = os.path.join(t, "check")
        c = subprocess.run(["swiftc", "-O", *files, os.path.join(HERE, "main.swift"), "-o", exe], capture_output=True, text=True)
        if c.returncode != 0:
            print(f"{name}: did not compile\n{c.stderr[:400]}"); continue
        r = subprocess.run([exe], capture_output=True, text=True, timeout=300)
        failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        if r.returncode != 0:
            caught += 1
            print(f"{name}: caught ({failed[0][:90] if failed else f'exit status {r.returncode}'})")
        else:
            print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
