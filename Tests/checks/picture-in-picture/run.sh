#!/bin/bash
# PictureInPicturePolicy (iOSClient/PictureInPicturePolicy.swift) on its own: when Sill lets iOS take a
# window's picture into Picture in Picture as the person leaves (issue #291), what counts as watched, heard
# and running while it shows, the pause and what ends it; 20,000 random sets of windows and 20,000 random
# lives of one window against the invariants.
#   Tests/checks/picture-in-picture/run.sh             compile and run the check
#   Tests/checks/picture-in-picture/run.sh --mutants   one-line mutants of PictureInPicturePolicy.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/PictureInPicturePolicy.swift "$here/main.swift" -o "$out/check"
"$out/check"
