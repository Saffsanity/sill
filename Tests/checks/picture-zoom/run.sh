#!/bin/bash
# PictureZoom (iOSClient/PictureZoom.swift) on its own: where the magnified frame is drawn (the focus in
# the middle, stopping at the frame's edges, centred along an axis it does not fill), that a touch maps
# back to the point it is over, and the follow, the hold under a finger, the toggle and `allowed`.
#   Tests/checks/picture-zoom/run.sh             compile and run the check
#   Tests/checks/picture-zoom/run.sh --mutants   one-line mutants of PictureZoom.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/PictureZoom.swift "$here/main.swift" -o "$out/check"
"$out/check"
