#!/bin/bash
# ConnectionList (iOSClient), the connect screen's list/tiles style, when a session's end keeps a
# picture for a tile, the picture's size and black test, when a decoded picture lands, when Disconnect
# asks for a fresh keyframe, per-Mac groups and sections, preview JPEG filenames and pruning, and tile
# columns. With KeyframeRecovery.swift (its spacing).
#   Tests/checks/connection-list/run.sh             compile and run the check
#   Tests/checks/connection-list/run.sh --mutants   one-line mutants of ConnectionList.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
swiftc -O iOSClient/ConnectionList.swift iOSClient/KeyframeRecovery.swift "$here/main.swift" -o "$out/check"
"$out/check"
