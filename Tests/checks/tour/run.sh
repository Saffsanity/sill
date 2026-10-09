#!/bin/bash
# TourPolicy (iOSClient/TourPolicy.swift), the first-run tour's rules on their own: the steps and
# targets per layout, what is owed, when the tour shows by itself (the beat, a touch or input since
# the picture, a turn), memory and runs, a rotation mid-run, the crease, the card's width and place
# (pinned at the Duo's four sizes and the iPhone SE's two, an oracle, and a grid of properties), and
# every string (docs/first-run-walkthrough-plan.md, H2). A phone held upright is placed with
# PhonePortraitLayout's own rects, compiled in; the iPhone Duo's real sizes with its fold as iOS 27.1
# reports it, with DuoPosture.swift (docs/iphone-duo-plan.md).
#   Tests/checks/tour/run.sh             compile and run the check
#   Tests/checks/tour/run.sh --mutants   one-line mutants of TourPolicy.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
swiftc -O iOSClient/TourPolicy.swift iOSClient/PhonePortraitLayout.swift iOSClient/DuoPosture.swift "$here/main.swift" -o "$out/check"
"$out/check"
