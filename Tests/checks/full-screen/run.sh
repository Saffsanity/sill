#!/bin/bash
# Full screen's rules (iOSClient/FullScreenPolicy.swift; docs/full-screen-plan.md) on their own: the swipe in's
# start at the left edge (EdgeSwipe) by cases and over 30,000 random strokes against a model, the rest of the swipe
# in (EdgeReveal), the preview's cut over each layout's picture's place (RevealCut, with DuoPosture.swift and
# PhonePortraitLayout.swift), the pointer at the edge (EdgeDwell), when it is
# offered and must show, the shake, the Settings rows' place, the hint, the room and the levels.
#   Tests/checks/full-screen/run.sh             compile and run the check
#   Tests/checks/full-screen/run.sh --mutants   one-line mutants of FullScreenPolicy.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/FullScreenPolicy.swift iOSClient/DuoPosture.swift iOSClient/PhonePortraitLayout.swift "$here/main.swift" -o "$out/check"
"$out/check"
