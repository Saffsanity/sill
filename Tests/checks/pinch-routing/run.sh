#!/bin/bash
# PinchRouting (iOSClient/PinchRouting.swift) on its own: who a two-finger pinch on the stream's picture
# belongs to (the picture's zoom, the Mac's own pinch, or nobody), from fingers or the iPad's trackpad,
# the stored Pinch Behavior (Zoom Stream or Zoom App) and whether the Mac takes the pinch. Every
# combination, then the properties the three callers rely on (a choice kept for a Mac that cannot take
# it never costs the picture its zoom).
#   Tests/checks/pinch-routing/run.sh             compile and run the check
#   Tests/checks/pinch-routing/run.sh --mutants   one-line mutants of PinchRouting.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/PinchRouting.swift "$here/main.swift" -o "$out/check"
"$out/check"
