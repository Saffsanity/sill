#!/bin/bash
# Full screen's rules (iOSClient/FullScreenPolicy.swift; docs/full-screen-plan.md) on their own: the hide's
# touch rule at the left edge (EdgeFlick) by cases and over 30,000 random strokes against a model, the swipe
# in (EdgeReveal), the pointer at the edge (EdgeDwell), when it is offered, armed and must show, the hint,
# the room and the levels; with EdgeFlickGate, the recognizer's choice of which touches are judged.
#   Tests/checks/full-screen/run.sh             compile and run the check
#   Tests/checks/full-screen/run.sh --mutants   one-line mutants of FullScreenPolicy.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/FullScreenPolicy.swift "$here/main.swift" -o "$out/check"
"$out/check"
