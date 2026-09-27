#!/bin/bash
# PhonePortraitLayout (iOSClient/PhonePortraitLayout.swift) on its own: where everything goes on a
# phone held upright (docs/iphone-portrait-plan.md): the plan's layout and keyboard tables phone by
# phone, 320 pt wide, and every width from 300 to 599 pt at every height to 1,400 (the picture 16:10,
# the rows and their gaps, the equal buttons and caps, the trackpad and its span, the ruler, the
# drawer, the panel and the dim).
#   Tests/checks/phone-portrait/run.sh             compile and run the check
#   Tests/checks/phone-portrait/run.sh --mutants   one-line mutants of PhonePortraitLayout.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/PhonePortraitLayout.swift "$here/main.swift" -o "$out/check"
"$out/check"
