#!/bin/bash
# PhoneKeyboardLift (iOSClient/PhoneKeyboardLift.swift) with PhonePortraitLayout: a phone held upright's rows
# placed from the software keyboard's real top, whatever its height: the phones with Apple's keyboards,
# taller ones, the iPhone Duo's cover, Larger Picture, Hide Thumbnails While Typing, the lift's ceiling, the
# frame and the viewport, the switch and its words, and a grid of every width from 300 to 599 pt.
#   Tests/checks/phone-keyboard-lift/run.sh             compile and run the check
#   Tests/checks/phone-keyboard-lift/run.sh --mutants   one-line mutants of PhoneKeyboardLift.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/PhonePortraitLayout.swift iOSClient/PhoneKeyboardLift.swift "$here/main.swift" -o "$out/check"
"$out/check"
