#!/bin/bash
# Sill.app's side of Sill Camera (docs/camera-plan.md §6.5, §7, §11, step 8): CameraExtensionPolicy (what Sill asks macOS
# for and when, macOS's answers, Settings › Streaming's camera section, its words, the dry run's script) and
# CameraSinkPolicy (the state Sill writes into Sill Camera, the app its demand names, the sink's two frames); then
# 20,000 random lives of each against their invariants. Compiled with the files in module.txt as one module (../module.py).
#   Tests/checks/camera-app/run.sh             compile and run the check
#   Tests/checks/camera-app/run.sh --mutants   one-line mutants of CameraExtensionState.swift and CameraSinkPolicy.swift;
#                                              each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
python3 "$here/../module.py" "$name" "$root" "$out/check"
