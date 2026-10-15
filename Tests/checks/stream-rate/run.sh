#!/bin/bash
# StreamRate (Sources/SillHost/StreamRate.swift) on its own: the frame rate a hardware stream asks of
# the encoder at its size.
#   Tests/checks/stream-rate/run.sh             compile and run the check
#   Tests/checks/stream-rate/run.sh --mutants   one-line mutants of StreamRate.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O Sources/SillHost/StreamRate.swift "$here/main.swift" -o "$out/check"
"$out/check"
