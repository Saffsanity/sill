#!/bin/bash
# The device's camera stream (CameraStream; docs/camera-plan.md §6.1 points 4 to 8, §6.2): encoders and epochs, the
# format before an epoch's first frame, keyframes, the send budget's skips and drops, the frame's cap, the bitrate's
# steps and a second's numbers, case by case and over 20,000 random lives against their invariants. Compiled with the
# files in module.txt as one module (../module.py drops their `import StreamProtocol`).
#   Tests/checks/camera-stream/run.sh             compile and run the check
#   Tests/checks/camera-stream/run.sh --mutants   one-line mutants of CameraStream.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
python3 "$here/../module.py" "$name" "$root" "$out/check"
