#!/bin/bash
# AudioPlayout (iOSClient/AudioPlayout.swift), the device's playout of the Mac's sound, on a simulated
# clock (docs/audio-plan.md §7.2, H3): the floor, the need and its cover, the picture's lag and the guard,
# placement and the packet in hand, late packets, duplicates, gaps and joins, drift by single frames,
# jumps and steps, fades; scenarios, then 5,000 random runs against the invariants.
#   Tests/checks/audio-playout/run.sh [RUNS]      compile and run (RUNS random runs, 5,000 by default)
#   Tests/checks/audio-playout/run.sh --mutants   one-line mutants of AudioPlayout.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/AudioPlayout.swift "$here/main.swift" -o "$out/check"
"$out/check" "$@"
