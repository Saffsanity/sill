#!/bin/bash
# GestureChords (Sources/SillHost/GestureChords.swift) on its own: a trackpad gesture from a device
# (kind 28) as the Mac's own shortcut for its action, the reversal, unknown names, the log line and
# the TEST ONLY table, then 5,000 random sequences against a model (docs/trackpad-gestures-plan.md
# §7, §9.1). Pure: nothing is posted. Its `package` access needs -package-name.
#   Tests/checks/gesture-chords/run.sh             compile and run the check
#   Tests/checks/gesture-chords/run.sh --mutants   one-line mutants of GestureChords.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O -package-name sill Sources/SillHost/GestureChords.swift "$here/main.swift" -o "$out/check"
"$out/check"
