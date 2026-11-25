"""Mutants of iOSClient/SoftNewlines.swift and the softNewlines paths in iOSClient/TextComposition.swift."""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import module

S = "iOSClient/SoftNewlines.swift"
T = "iOSClient/TextComposition.swift"

MUTANTS = [
    ("defaultOn flipped to true upstream", S,
     "static let defaultOn = false", "static let defaultOn = true"),
    ("isEnabled ignores launch-argument string via as? Bool", S,
     "return defaults.bool(forKey: switchKey)",
     "return (defaults.object(forKey: switchKey) as? Bool) ?? defaultOn"),
    ("actions(soft: false) expands newlines anyway", S,
     "guard soft else {\n                    result.append(.text(s))\n                    continue\n                }",
     "if false {}"),
    ("actions misses CRLF grapheme cluster", S,
     'if ch == "\\n" || ch == "\\r" || ch == "\\r\\n" {',
     'if ch == "\\n" || ch == "\\r" {'),
    ("actions misses CR", S,
     'if ch == "\\n" || ch == "\\r" || ch == "\\r\\n" {',
     'if ch == "\\n" || ch == "\\r\\n" {'),
    ("actions drops consecutive or leading soft newlines", S,
     "result.append(.softNewline)",
     "if !run.isEmpty { result.append(.softNewline) }"),
    ("actions turns literal U+2028 into softNewline", S,
     'if ch == "\\n" || ch == "\\r" || ch == "\\r\\n" {',
     'if ch == "\\n" || ch == "\\r" || ch == "\\r\\n" || ch == "\\u{2028}" {'),
    ("settlePending promotes expired Return after coalesceWindow", S,
     "if enabled && now - armedAt <= SoftNewlines.coalesceWindow {",
     "if enabled {"),
    ("settlePending never promotes pending Return on follow-up token", S,
     "if enabled && now - armedAt <= SoftNewlines.coalesceWindow {",
     "if false {"),
    ("replace consumes pending Return before checking refusal", S,
     "guard composition.refusal(range, with: text, taken: taken) == nil else { return [] }",
     "if false {}"),
    ("willSelect drops pending Return instead of settling it before selection", S,
     "mutating func willSelect(in composition: inout TextComposition) -> [Action] {\n            flushPendingAsHard(in: &composition)\n        }",
     "mutating func willSelect(in composition: inout TextComposition) -> [Action] {\n            pendingReturnAt = nil; return []\n        }"),
    ("deleteBackward fails to cancel pending Return", S,
     "if pendingReturnAt != nil {\n                pendingReturnAt = nil\n                return []\n            }",
     "if false {}"),
    ("flushPendingAsHard sends softNewline instead of hard Return", S,
     'return SoftNewlines.actions(for: composition.insert("\\n", softNewlines: false), soft: false)',
     'return SoftNewlines.actions(for: composition.insert("\\n", softNewlines: true), soft: true)'),
    ("unmark sends hard Return for multi-line marked text", S,
     "let soft = enabled && !(composition.marked.map(SoftNewlines.isSingleNewline) ?? true)",
     "let soft = false"),
    ("TextComposition.insert advances fence on multi-line soft insert", T,
     "return commit(sent + rest, softNewlines: softNewlines)",
     "return commit(sent + rest, softNewlines: false)"),
    ("TextComposition.replace advances fence on soft multi-line rewrite", T,
     "return commit(replacing(range, with: text), softNewlines: softNewlines)",
     "return commit(replacing(range, with: text), softNewlines: false)"),
    ("TextInputRules.endOfReturnOrTab ignores Tab when softNewlines is true", T,
     'if scalar == "\\t" || (!softNewlines && (scalar == "\\n" || scalar == "\\r")) { end = offset }',
     'if !softNewlines && (scalar == "\\n" || scalar == "\\r" || scalar == "\\t") { end = offset }'),
]

sys.exit(0 if module.mutate("soft-newlines", MUTANTS, sys.argv[1]) else 1)
