"""Mutants of Sources/SillHost/TypedText.swift."""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import module

F = "Sources/SillHost/TypedText.swift"

MUTANTS = [
    ("CRLF and CR missed (only LF matched, the original bug)", F,
     'case "\\n", "\\r", "\\r\\n":', 'case "\\n":'),
    ("CRLF missed", F,
     'case "\\n", "\\r", "\\r\\n":', 'case "\\n", "\\r":'),
    ("CR missed", F,
     'case "\\n", "\\r", "\\r\\n":', 'case "\\n", "\\r\\n":'),
    ("LF missed", F,
     'case "\\n", "\\r", "\\r\\n":', 'case "\\r", "\\r\\n":'),
    ("return mapped to tab", F,
     "return .returnKey", "return .tabKey"),
    ("tab mapped to return", F,
     "return .tabKey", "return .returnKey"),
    ("tab matched as space", F,
     'case "\\t":', 'case " ":'),
    ("backspace mapped to return", F,
     "return .backspaceKey", "return .returnKey"),
    ("backspace matched as DEL", F,
     'case "\\u{8}":', 'case "\\u{7F}":'),
    ("steps iterates unicodeScalars and splits CRLF and emoji", F,
     "string.map(step(for:))", "string.unicodeScalars.map { step(for: Character($0)) }"),
    ("truncating UTF-16 code units drops surrogate pairs and skin tones", F,
     "Array(character.utf16)", "Array(character.utf16.prefix(1))"),
]

sys.exit(0 if module.mutate("typed-text", MUTANTS, sys.argv[1]) else 1)
