from pathlib import Path
root = Path(__file__).resolve().parents[3]
prefs = (root / "visionOSClient/VisionToolbarPreferences.swift").read_text()
screen = (root / "iOSClient/StreamScreen.swift").read_text()
assert prefs.count(".hoverEffectPhaseOverride(") == 1, "Only one override definition"
assert screen.count(".modifier(VisionToolbarReset(") == 1, "Only one override owner per StreamScreen"
assert ".hoverEffectDisabled(true)" in prefs, "Reset owner must not activate a new zone"
assert screen.count(".ornament(attachmentAnchor:") == 2, "Keep ordinary top/left ornaments"
assert ".ornament(" not in prefs, "Do not reintroduce build35 hover-presented ornaments"
assert 'delay(active ? 0.65 : 1.0)' in prefs, "Keep dwell and exit grace"
assert 'fill(.black.opacity(0.50))' in prefs, "Keep accepted pill appearance"
assert ".hoverEffectGroup(" not in screen, "Do not inherit reveal grouping into native button highlights"
assert ".hoverEffect(.highlight, in:" not in prefs, "Pill highlight must be local"
assert prefs.count(".hoverEffect(in: group) { effect, active, _ in") == 2, "Both fades retain explicit shared group"
print("vision-toolbar-hover: single-owner, local-highlight and presentation invariants passed")
