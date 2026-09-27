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
    ("gestures 1 by default", "Switcher.swift", "hostVersion: String? = nil, protocol: Int? = nil, gestures: Int? = nil) {", "hostVersion: String? = nil, protocol: Int? = nil, gestures: Int? = 1) {"),
    ("gestures never stored", "Switcher.swift", "self.protocol = `protocol`; self.gestures = gestures", "self.protocol = `protocol`; self.gestures = nil"),
    ("fingers 3 by default", "Gesture.swift", "public init(gesture: String, fingers: Int? = nil) {", "public init(gesture: String, fingers: Int? = 3) {"),
    ("a name misspelt", "Gesture.swift", 'public static let swipeLeft = "swipeLeft"', 'public static let swipeLeft = "swipeleft"'),
    ("spread left out of the names", "Gesture.swift", "public static let names = [swipeUp, swipeDown, swipeLeft, swipeRight, pinch, spread]", "public static let names = [swipeUp, swipeDown, swipeLeft, swipeRight, pinch]"),
    ("kind 28 as 250", "StreamMessage.swift", "case gesture = 28", "case gesture = 250"),
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
    ("the late count never kept", "Viewport.swift", "self.audioBehindMs = audioBehindMs; self.audioLate = audioLate", "self.audioBehindMs = audioBehindMs; self.audioLate = nil"),
    ("kind 29 as 253", "StreamMessage.swift", "    case audio = 29 ", "    case audio = 253 "),
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
