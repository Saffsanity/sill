#!/bin/bash
# ThumbnailHold (iOSClient/ThumbnailHold.swift) on its own: how long a window's thumbnail is held before
# its lights show and it can be dragged (issue #113; Noah, 2026-10-29: 0.2 to 3 s in tenths, 0.5 s unless
# changed): the constants, every length on the grid of tenths, the ends, halfway values, the stepper's
# + and −, a stored value (numbers, strings, junk, UserDefaults' registration and the launch argument
# in a child run), every word, the title's three lines (the narrowest it may be beside the stepper, by
# CoreText's widths), and a grid of hundredths from -4 to 10 s.
#   Tests/checks/thumbnail-hold/run.sh             compile and run the check
#   Tests/checks/thumbnail-hold/run.sh --mutants   one-line mutants of ThumbnailHold.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/ThumbnailHold.swift "$here/main.swift" -o "$out/check"
"$out/check"
