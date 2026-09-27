#!/bin/bash
# AskLimits (Sources/SillHost/PairingWindow.swift), the limits on a device's asks to pair at home: 10
# minutes of quiet by key and by address, 3 device-opened windows in any 10 minutes, the test
# override (docs/home-pairing-plan.md §4.2, §4.7).
# Compiled with the files in module.txt as one module (../module.py drops their `import StreamProtocol`).
#   Tests/checks/ask-limits/run.sh             compile and run the check
#   Tests/checks/ask-limits/run.sh --mutants   one-line mutants of PairingWindow.swift's AskLimits; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
python3 "$here/../module.py" "$name" "$root" "$out/check"
