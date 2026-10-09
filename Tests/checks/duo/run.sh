#!/bin/bash
# DuoPosture (iOSClient/DuoPosture.swift) on its own: the iPhone Duo's posture and the layout rules
# that follow from it (docs/iphone-duo-plan.md): the poses as the iOS 27.1 simulator reported them,
# the fold's band, the laptop pose's split at the real fold and open flat's at the picture's shape,
# the book pose's bar clear of the fold, one page for a card, the connect column and the pairing
# overlay, the inferred rules as before iOS 27.1 over a grid of sizes, and the harness's stand-in.
#   Tests/checks/duo/run.sh             compile and run the check
#   Tests/checks/duo/run.sh --mutants   one-line mutants of DuoPosture.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/DuoPosture.swift "$here/main.swift" -o "$out/check"
"$out/check"
