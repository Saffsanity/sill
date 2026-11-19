#!/bin/bash
# The device's rules for Share Camera (CameraPolicy, CameraPacing; docs/camera-plan.md §6.1, §6.2): the row,
# offering and capturing over every combination, the pause's order, the format, the heat, the bitrate and its
# steps, the keyframes, the chip, every word, and the send budget on a virtual clock (1 to 100 Mbit/s).
# Compiled with the files in module.txt as one module (../module.py drops their `import StreamProtocol`).
#   Tests/checks/camera/run.sh             compile and run the check
#   Tests/checks/camera/run.sh --mutants   one-line mutants of CameraPolicy.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
python3 "$here/../module.py" "$name" "$root" "$out/check"
