#!/bin/bash
# DesktopDisplays (Sources/StreamProtocol/DesktopDisplays.swift) on its own: which of the Mac's displays
# the Desktop streams when it has more than one, and the Desktop button that steps to the next (issue
# #91): the candidates (never Sill's virtual display; left to right), the chosen one by its UUID, the
# next, the button's words and tap, the pointer after a switch; 5,000 random arrangements.
#   Tests/checks/desktop-displays/run.sh             compile and run the check
#   Tests/checks/desktop-displays/run.sh --mutants   one-line mutants of DesktopDisplays.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
rm -f "$out/check"
swiftc -O Sources/StreamProtocol/DesktopDisplays.swift "$here/main.swift" -o "$out/check"
"$out/check"
