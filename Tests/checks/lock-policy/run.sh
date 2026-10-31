#!/bin/bash
# LockPolicy (Sources/SillHost/LockPolicy.swift; docs/locked-mac-plan.md): what a locked Mac shows and what
# a device may do at it. Each request locked and unlocked, paired and not; the window list (no windows, no
# clipboard, `locked`) and its JSON both ways; what else is shown; the TEST ONLY file's words; the State's
# readings, the select gate, the window that comes back at the unlock; the lines; the device's line
# (StreamProtocol's LockedMac); and a copy of the coordinator's glue run through directed and random
# sessions against the rule's invariants.
# Compiled with the files in module.txt as one module (../module.py drops their `import StreamProtocol`).
#   Tests/checks/lock-policy/run.sh             compile and run the check
#   Tests/checks/lock-policy/run.sh --mutants   one-line mutants of LockPolicy.swift and LockedMac; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
python3 "$here/../module.py" "$name" "$root" "$out/check"
