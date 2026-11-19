#!/bin/bash
# Sill Camera's rules (CameraFeedPolicy, docs/camera-plan.md §6.4): the formats and rates, the state Sill for Mac writes
# and the demand it reads, who may feed Sill Camera, the placeholder's words, frames, ticks, formats and apps; then
# 20,000 random lives against the invariants. Compiled with the files in module.txt as one module (../module.py).
#   Tests/checks/camera-feed/run.sh             compile and run the check
#   Tests/checks/camera-feed/run.sh --mutants   one-line mutants of CameraFeedPolicy.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
python3 "$here/../module.py" "$name" "$root" "$out/check"
