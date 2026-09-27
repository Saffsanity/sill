#!/bin/bash
# TrackpadGestures (iOSClient/TrackpadGestures.swift) on its own: which three- and four-finger stroke
# on the device's glass arms, how long it stays silent, and what it decides at the first lift (a swipe
# each way, the flick, the axis, pinch, spread), then 5,000 random strokes against a model
# (docs/trackpad-gestures-plan.md §6.1, §9.1).
#   Tests/checks/gestures/run.sh             compile and run the check
#   Tests/checks/gestures/run.sh --mutants   one-line mutants of TrackpadGestures.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/TrackpadGestures.swift "$here/main.swift" -o "$out/check"
"$out/check"
