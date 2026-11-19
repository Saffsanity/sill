#!/bin/bash
# PinchRouting (iOSClient/PinchRouting.swift) on its own: who a two-finger pinch belongs to (the picture's zoom,
# the Mac's own pinch, or nobody), from fingers on the picture, a trackpad of Sill's own or one connected to an
# iPad, with Pinch at Zoom Picture or Zoom on ‹Mac› and a Mac that takes the pinch or not; the turn (Rotate on
# ‹Mac›); the two switches as UserDefaults holds them; the Settings panel's rows and words. Every combination,
# then the properties the callers rely on (a choice kept for a Mac that cannot take it never costs the picture
# its zoom; Zoom Picture as before).
#   Tests/checks/pinch-routing/run.sh             compile and run the check
#   Tests/checks/pinch-routing/run.sh --mutants   one-line mutants of PinchRouting.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/PinchRouting.swift "$here/main.swift" -o "$out/check"
"$out/check"
