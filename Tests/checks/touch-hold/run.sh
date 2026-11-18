#!/bin/bash
# TouchHold (iOSClient/TouchHold.swift) on its own: the picture's touch and hold in Direct Touch (issue
# #178): lifted where it was pressed, a right click at the lift; moved past the slop, a left drag from where
# it was pressed; a cancel lets the button up and clicks nothing; then 20,000 random holds against a model.
#   Tests/checks/touch-hold/run.sh             compile and run the check
#   Tests/checks/touch-hold/run.sh --mutants   one-line mutants of TouchHold.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/TouchHold.swift "$here/main.swift" -o "$out/check"
"$out/check"
