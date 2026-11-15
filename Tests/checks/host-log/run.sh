#!/bin/bash
# The log file (Sources/SillHost/HostLog.swift) written by two Sills at once, as at an update's hand-over, where
# the new copy starts while the old one still runs (docs/one-click-update-plan.md), and at a second launch that
# waits and leaves: each line whole, at the file's end, in the order written; a file one of them moved aside at
# 10 MB followed by the other, the moved one kept whole; a deleted file written again at its path; a file at
# 10 MB at launch moved aside first. The writers are the check's own binary run twice, each with its own HostLog.
#   Tests/checks/host-log/run.sh             compile and run the check
#   Tests/checks/host-log/run.sh --mutants   one-line mutants of HostLog.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O -package-name sill Sources/SillHost/HostLog.swift "$here/main.swift" -o "$out/check"
"$out/check"
