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
    ("kind 28 as 29", "StreamMessage.swift", "case gesture = 28", "case gesture = 29"),
    ("device never nil", "Compatibility.swift", "self.appVersion = appVersion; self.build = build; self.protocol = `protocol`; self.device = device", "self.appVersion = appVersion; self.build = build; self.protocol = `protocol`; self.device = device ?? \"\""),
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
