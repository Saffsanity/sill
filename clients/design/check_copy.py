#!/usr/bin/env python3
"""Every word the core's Copy and PanelCopy objects hold is still the iOS app's.

Each string literal in those objects is split at its interpolations ($x, ${...}), and every piece
of six characters or more must appear in the iOS sources, whose own interpolations (\\(...)) and
escapes (\\u{00A0}) are read the same way. A word changed on one side and not the other fails here.

    check_copy.py IOS_DIR KOTLIN_UI_DIR
"""
import os
import re
import sys

ios, kt = sys.argv[1], sys.argv[2]
swift = ""
for d in (ios, os.path.join(os.path.dirname(os.path.abspath(ios)), "Sources", "StreamProtocol")):
    for f in sorted(os.listdir(d)):
        if f.endswith(".swift"):
            swift += open(os.path.join(d, f), encoding="utf-8").read() + "\n"
swift = re.sub(r"\\u\{([0-9A-Fa-f]+)\}", lambda m: chr(int(m.group(1), 16)), swift)
swift = re.sub(r"\\\([^()]*(\([^()]*\)[^()]*)*\)", "\x00", swift)
swift = swift.replace("\\\"", "\"")

failures, checked = [], 0
for f in sorted(os.listdir(kt)):
    if f not in ("Copy.kt", "SettingsPanel.kt"):
        continue
    text = open(os.path.join(kt, f), encoding="utf-8").read()
    if f == "SettingsPanel.kt":
        text = text[text.index("object PanelCopy"):]
    if "object PlatformCopy" in text:
        text = text[:text.index("object PlatformCopy")]   # the platform's own words, by design
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"//[^\n]*", "", text)
    for m in re.finditer(r'"((?:[^"\\$]|\\.|\$\{[^}]*\}|\$\w+)*)"', text):
        lit = m.group(1)
        lit = re.sub(r"\\u([0-9A-Fa-f]{4})", lambda u: chr(int(u.group(1), 16)), lit)
        lit = re.sub(r"\$\{[^}]*\}|\$\w+", "\x00", lit).replace('\\"', '"')
        for piece in lit.split("\x00"):
            piece = piece.strip()
            if len(piece) < 6:
                continue
            checked += 1
            if piece not in swift:
                failures.append(f"{f}: {piece!r}")
if failures:
    print("check_copy: not in the iOS app any more (change both sides together):", file=sys.stderr)
    for x in failures:
        print("  " + x, file=sys.stderr)
    sys.exit(1)
print(f"check_copy: {checked} pieces of the core's words found in the iOS app")
