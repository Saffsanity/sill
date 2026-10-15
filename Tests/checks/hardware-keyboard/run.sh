#!/bin/bash
# HardwareKeyboardPolicy (iOSClient/HardwareKeyboardPolicy.swift) on its own: when the stream's input
# view holds the keyboard for a hardware keyboard and when the person's own keyboard is up, event by
# event (a view joining, a keyboard coming and going, what is open, the Keyboard button, a restore,
# another responder, UIKit giving it back), then 20,000 random sessions against the invariants
# (docs/hardware-keyboard-plan.md §2).
#   Tests/checks/hardware-keyboard/run.sh             compile and run the check
#   Tests/checks/hardware-keyboard/run.sh --mutants   one-line mutants of HardwareKeyboardPolicy.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/HardwareKeyboardPolicy.swift "$here/main.swift" -o "$out/check"
"$out/check"
