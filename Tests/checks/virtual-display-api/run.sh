#!/bin/bash
# VirtualDisplay's private API surface and how the runtime's type encodings are matched against it
# (Runtime.method's own decision, asked about classes the check makes at run time; #87, #62): every
# encoding measured on Apple silicon or reported from Intel machines passes for its method, a BOOL
# return passes spelled "B" or "c" and nothing else does, and applySettings: reads a YES and a NO
# either way. Compiled with Sources/SillHost/VirtualDisplay.swift whole; nothing here looks up a
# private class or makes a display.
#   Tests/checks/virtual-display-api/run.sh             compile and run the check
#   Tests/checks/virtual-display-api/run.sh --mutants   one-line mutants of VirtualDisplay.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
"$here/build.sh" "$root" "$out/check"
[ -x "$out/check" ] || { echo "$name: did not compile" >&2; exit 1; }
"$out/check"
