#!/bin/bash
# PhoneKeyRow (iOSClient/PhoneKeyRow.swift), compiled with PhonePortraitLayout, whose row 3 it lays the caps
# across: the key row of a phone held upright and its switch, Arrow Keys (issue #287, PR #315): off by
# default, offered on an iPhone alone; on, the four arrows after shift in a row that scrolls, every cap at
# least 44 pt wide at every width a phone's arrangement has, the fades, VoiceOver's action, the words;
# 20,000 random rows against the invariants.
#   Tests/checks/phone-key-row/run.sh             compile and run the check
#   Tests/checks/phone-key-row/run.sh --mutants   one-line mutants of PhoneKeyRow.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/PhoneKeyRow.swift iOSClient/PhonePortraitLayout.swift "$here/main.swift" -o "$out/check"
"$out/check"
