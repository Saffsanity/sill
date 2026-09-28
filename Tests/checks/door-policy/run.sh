#!/bin/bash
# DoorPolicy (Sources/SillHost), who each door admits: both doors, each origin, each ALPN, Require
# pairing on and off, paired or not, a window or not; the ask rule's six steps in order; what the
# device gate's hold is judged by again (afterGate); which hosts take the test hooks
# (docs/home-pairing-plan.md §4.2).
# Compiled with the files in module.txt as one module (../module.py drops their `import StreamProtocol`).
#   Tests/checks/door-policy/run.sh             compile and run the check
#   Tests/checks/door-policy/run.sh --mutants   one-line mutants of DoorPolicy.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
python3 "$here/../module.py" "$name" "$root" "$out/check"
