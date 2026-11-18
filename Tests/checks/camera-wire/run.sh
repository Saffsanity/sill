#!/bin/bash
# Kind 46, the device's camera on the Mac (Camera.swift, docs/camera-plan.md §5): Sources/StreamProtocol
# compiled as one module with the check. The three types, their caps and generation 1's bounds at their
# edges, refusal rather than truncation, unknown types and keys skipped, kind 16's CameraState, then
# 20,000 random and mutated payloads.
#   Tests/checks/camera-wire/run.sh             compile and run the check
#   Tests/checks/camera-wire/run.sh --mutants   one-line mutants of StreamProtocol; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
swiftc -O Sources/StreamProtocol/*.swift "$here/main.swift" -o "$out/check"
"$out/check"
