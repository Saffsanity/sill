#!/bin/bash
# ViewerCamera (iOSClient/ViewerCamera.swift) on its own: where the Full-Screen Viewer puts the Mac's
# picture on an iPhone (docs/iphone-viewer-plan.md): fit, fill, the edge push, the pinch, a frame
# arriving or a rotation while zoomed, and seeded random sessions checked after every step.
#   Tests/checks/viewer-camera/run.sh             compile and run the check
#   Tests/checks/viewer-camera/run.sh --mutants   one-line mutants of ViewerCamera.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/ViewerCamera.swift "$here/main.swift" -o "$out/check"
"$out/check"
