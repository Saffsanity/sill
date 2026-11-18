#!/bin/bash
# Sill's own Desktop display (PR #200 finished, phase 2a of docs/virtual-desktop-plan.md): its size and rate by
# default the device's (VirtualDesktopSize: the plan's table both ways, 20,000 random panels against the invariants,
# the rate, whose viewport, the rate the Desktop is held to, the creation line) and the guard for #380
# (DisplayMakeGuard: the count, the trip at two, the reset, the lines; its Store in a folder of its own under
# .build/checks/virtual-desktop, never Sill.app's; 2,000 random lives against a model).
#   Tests/checks/virtual-desktop/run.sh             compile and run the check
#   Tests/checks/virtual-desktop/run.sh --mutants   one-line mutants of both files; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
rm -f "$out/check"
swiftc -O Sources/SillHost/VirtualDesktopSize.swift Sources/SillHost/DisplayMakeGuard.swift "$here/main.swift" -o "$out/check"
"$out/check" "$out"
