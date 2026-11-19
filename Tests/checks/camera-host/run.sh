#!/bin/bash
# The Mac's rules for the devices' cameras (CameraHostPolicy, docs/camera-plan.md §6.3): who may, the one
# holder and its claims, the grace of a move or a return, the lock, the demand and its keyframes, the
# epochs and the rates, every line; then 20,000 random lives against the invariants.
# Compiled with the files in module.txt as one module (../module.py drops their `import StreamProtocol`).
#   Tests/checks/camera-host/run.sh             compile and run the check
#   Tests/checks/camera-host/run.sh --mutants   one-line mutants of CameraHostPolicy.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
python3 "$here/../module.py" "$name" "$root" "$out/check"
