"""Mutants of PictureInPicturePolicy.swift (iOSClient, issue #291): each changes it in one place and must
make the check (main.swift) fail. usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "picture-in-picture")
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/PictureInPicturePolicy.swift")
orig = open(SRC).read()
Q = "s.switchOn && s.supported && s.connected && s.streaming && s.pictureCame && !s.covered"
TIE = "if (w.lastUsedAt ?? -.infinity) > (b.lastUsedAt ?? -.infinity) { best = w }"
STOPS = "case .sessionEnded, .backInFront, .deviceLocked: return pip.active"
MUTANTS = [
    # The constants.
    ("M1 on by default", "static let defaultOn = false", "static let defaultOn = true"),
    ("M2 a pause stops it after 5 minutes", "static let pausedLimit: Double = 600", "static let pausedLimit: Double = 300"),
    # Offered.
    ("M3 offered with the switch off", Q, "s.supported && s.connected && s.streaming && s.pictureCame && !s.covered"),
    ("M4 offered where iOS has no Picture in Picture", Q, "s.switchOn && s.connected && s.streaming && s.pictureCame && !s.covered"),
    ("M5 offered on the connect screen", Q, "s.switchOn && s.supported && s.streaming && s.pictureCame && !s.covered"),
    ("M6 offered with nothing streaming", Q, "s.switchOn && s.supported && s.connected && s.pictureCame && !s.covered"),
    ("M7 offered before the picture came", Q, "s.switchOn && s.supported && s.connected && s.streaming && !s.covered"),
    ("M8 offered under a locked Mac's cover", Q, "s.switchOn && s.supported && s.connected && s.streaming && s.pictureCame"),
    ("M9 offered for a window not chosen", "static func offered(_ s: Session, chosen: Bool) -> Bool { chosen && qualifies(s) }",
        "static func offered(_ s: Session, chosen: Bool) -> Bool { qualifies(s) }"),
    # Chosen.
    ("M10 leaving takes the choice away", "            return previous\n", "            return nil\n"),
    ("M11 a closed window stays chosen", "guard let previous, windows.contains(where: { $0.id == previous }) else { return nil }",
        "guard let previous else { return nil }"),
    ("M12 a window in the background chosen", "for w in windows where w.foregroundActive && w.qualifies {", "for w in windows where w.qualifies {"),
    ("M13 a window that does not qualify chosen", "for w in windows where w.foregroundActive && w.qualifies {",
        "for w in windows where w.foregroundActive {"),
    ("M14 the window used first", TIE, "if (w.lastUsedAt ?? -.infinity) < (b.lastUsedAt ?? -.infinity) { best = w }"),
    ("M15 the last listed among equals", TIE, "if (w.lastUsedAt ?? -.infinity) >= (b.lastUsedAt ?? -.infinity) { best = w }"),
    ("M16 a window never used counts as used last", TIE, "if (w.lastUsedAt ?? .infinity) > (b.lastUsedAt ?? .infinity) { best = w }"),
    # While it shows.
    ("M17 watched while paused", "sceneForegroundActive || (pip.active && !pip.paused)", "sceneForegroundActive || pip.active"),
    ("M18 heard with this window's scene away", "(appForeground && sceneForeground) || (pip.active && !pip.paused)",
        "appForeground || (pip.active && !pip.paused)"),
    ("M19 heard while paused", "(appForeground && sceneForeground) || (pip.active && !pip.paused)",
        "(appForeground && sceneForeground) || pip.active"),
    ("M20 not running while paused", "static func running(appForeground: Bool, pip: State) -> Bool { appForeground || pip.active }",
        "static func running(appForeground: Bool, pip: State) -> Bool { appForeground || (pip.active && !pip.paused) }"),
    ("M21 never running in Picture in Picture", "static func running(appForeground: Bool, pip: State) -> Bool { appForeground || pip.active }",
        "static func running(appForeground: Bool, pip: State) -> Bool { appForeground }"),
    ("M22 frozen by a pause flag alone", "static func frozen(_ pip: State) -> Bool { pip.active && pip.paused }",
        "static func frozen(_ pip: State) -> Bool { pip.paused }"),
    ("M23 a pause ends only after its limit", "return now - pausedAt >= pausedLimit", "return now - pausedAt > pausedLimit"),
    ("M24 the device's own input held back in front", "pip.active && !sceneForegroundActive", "pip.active"),
    ("M25 the device's own input never held", "pip.active && !sceneForegroundActive", "false"),
    # What ends it.
    ("M26 back in front does not stop it", STOPS, "case .sessionEnded, .deviceLocked: return pip.active\n        case .backInFront: return false"),
    ("M27 the device's lock does not stop it", STOPS, "case .sessionEnded, .backInFront: return pip.active\n        case .deviceLocked: return false"),
    ("M28 the session's end does not stop it", STOPS, "case .backInFront, .deviceLocked: return pip.active\n        case .sessionEnded: return false"),
    ("M29 the pause's ending stops it while playing", "case .pausedTooLong: return frozen(pip)", "case .pausedTooLong: return pip.active"),
    # The Lifecycle.
    ("M30 it starts paused", "state = State(active: true, paused: false)", "state = State(active: true, paused: true)"),
    ("M31 didStop keeps the pause time", "state = .off\n            pausedAt = nil", "state = .off"),
    ("M32 a play or pause acts while off", "guard state.active else { return .none }\n            var effects = Effects(invalidate: true)",
        "var effects = Effects(invalidate: true)"),
    ("M33 a second pause moves the pause time", "} else if !state.paused {", "} else {"),
    ("M34 AVKit never told of a play or pause", "var effects = Effects(invalidate: true)", "var effects = Effects()"),
    ("M35 a play keeps the pause time", "state.paused = false\n                pausedAt = nil", "state.paused = false"),
    ("M36 a pause never looked at again", "if let pausedAt { effects.lookAt = pausedAt + PictureInPicturePolicy.pausedLimit }", ""),
    ("M37 a pause at its limit not stopped", "return ending(.pausedTooLong)", "return .none"),
    ("M38 a look before the limit owes none", "return Effects(lookAt: pausedAt + PictureInPicturePolicy.pausedLimit)", "return .none"),
    ("M39 every ending stops it", "Effects(stop: PictureInPicturePolicy.stops(ending, pip: state))", "Effects(stop: true)"),
    ("M40 a second willStart starts it afresh", "guard !state.active else { return .none }\n            state = State(active: true, paused: false)",
        "state = State(active: true, paused: false)"),
    # The words.
    ("M41 the footnote without iOS's own switch",
        "\"iOS starts it only while Start PiP Automatically is on, in Settings › General › Picture in Picture.\"", "\"\""),
]
caught = 0
for name, old, new in MUTANTS:
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    src = os.path.join(OUT, "PictureInPicturePolicy.swift")
    open(src, "w").write(orig.replace(old, new, 1))
    exe = os.path.join(OUT, "mutant")
    if os.path.exists(exe): os.remove(exe)
    c = subprocess.run(["swiftc", "-O", src, os.path.join(SP, "main.swift"), "-o", exe], capture_output=True, text=True)
    if c.returncode != 0:
        print(f"{name}: did not compile: {c.stderr.strip().splitlines()[0] if c.stderr.strip() else ''}"); continue
    r = subprocess.run([exe], capture_output=True, text=True, timeout=600)
    failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
    if r.returncode != 0:
        caught += 1
        print(f"{name}: caught ({len(failed)} FAIL lines; first: {failed[0][:160] if failed else ''})")
    else:
        print(f"{name}: SURVIVED")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
