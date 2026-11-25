# `typed-text`

**Checks:** how `TypedText.step(for:)` and `TypedText.steps(for:)` decompose `.text` payloads into the keyboard events `InputInjector` posts on the Mac: `"\n"`, `"\r"` (sent by third-party iOS keyboards such as Rime and Hamster) and `"\r\n"` (a single Swift `Character` grapheme cluster) each produce one `.returnKey` step matching `TextInputRules.endOfReturnOrTab`, `"\t"` produces `.tabKey`, `"\u{8}"` produces `.backspaceKey`, consecutive and mixed line breaks (`"\n\n"`, `"\r\n\r\n"`, `"\n\r"`) produce the exact count of Returns without splitting `"\r\n"` into two, `"\u{2028}"` stays Unicode rather than Return, and ASCII, CJK, combining marks (`"e\u{301}"`), skin-tone emoji (`"👋🏽"`) and ZWJ sequences (`"👨‍👩‍👧‍👦"`) stay intact as one `.unicode([UInt16])` step per extended grapheme cluster across fixed scenarios and 2,000 seeded random strings.

**Compiles:** `Sources/SillHost/TypedText.swift` (`module.py`, `-package-name sill`)
