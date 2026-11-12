#!/bin/bash
# StageRelease (Sources/SillHost/StageRelease.swift) on its own: when Sill's display for a picked window (the stage,
# Virtual Display) may go after the window was sent home, and the look after it, at their edges; a model of a window
# server and an app that commits the move late (0 to 2,000 ms, and never), through the order before 2026-11-12 (the
# display removed at once: the window dumped on the main display) and the new one (removed once the window has left, or
# at the deadline and put back after); the way out's wiring in VirtualStage.swift and StreamCoordinator.swift.
#   Tests/checks/stage-release/run.sh             compile and run the check
#   Tests/checks/stage-release/run.sh --mutants   one-line mutants of StageRelease.swift and the wiring; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
rm -f "$out/check"
swiftc -O Sources/SillHost/StageRelease.swift "$here/main.swift" -o "$out/check"
"$out/check"
