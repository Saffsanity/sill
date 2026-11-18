#!/bin/bash
# StreamZoom (iOSClient/StreamZoom.swift) on its own: the picture's pinch zoom (issue #65) and who a
# stroke on the picture belongs to, the Mac's scroll or the picture's zoom: the scale's range, the
# anchor under the fingers, the cover of the pane, the whole picture only all the way out (and at a lift
# within 2 % of it), a pane of another size, the mapping a touch and a scroll go through and its inverse;
# one finger, two at 1×, two on a zoomed picture, three, and odd orders; then 20,000 random strokes.
#   Tests/checks/stream-zoom/run.sh             compile and run the check
#   Tests/checks/stream-zoom/run.sh --mutants   one-line mutants of StreamZoom.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/StreamZoom.swift "$here/main.swift" -o "$out/check"
"$out/check"
