#!/bin/bash
# Sill's own Desktop display (PR #200 finished, phase 2a of docs/virtual-desktop-plan.md): its size and rate by
# default the device's (VirtualDesktopSize: the plan's table both ways, 20,000 random panels against the invariants,
# the rate, whose viewport, the rate the Desktop is held to, the creation line) and the guard for #380
# (DisplayMakeGuard: the count, the trip at two, the reset, the lines; its Store in a folder of its own under
# .build/checks/virtual-desktop, never Sill.app's; 2,000 random lives against a model). Phase 2b: following the device
# (VirtualDesktopSize.Follow and followStep, the backing, InPlace against the display as probes P2b and P2c measured it,
# 2,000 random follows), when the Virtual Desktop exists (VirtualDesktopLife,
# 5,000 random sessions against the plan's invariants) and its windows out and back (DesktopWindowLedger, over a
# stand-in Mac; WindowRestore.swift compiled for its tolerance and Access). The coordinator's (commit 8): a test host's grace
# and its TEST ONLY hook, the make's line, and VirtualDesktopWords' note (why this Mac cannot make it now; StreamProtocol's,
# with DesktopDisplays.swift for the stop's name). Part B (2026-11-25): a size the person types and each device's budget
# (VirtualDesktopBudget; CaptureScale.swift compiled for #295's EncoderLimit).
#   Tests/checks/virtual-desktop/run.sh             compile and run the check
#   Tests/checks/virtual-desktop/run.sh --mutants   one-line mutants of the five files; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
rm -f "$out/check"
swiftc -O -package-name sill Sources/SillHost/VirtualDesktopSize.swift Sources/SillHost/DisplayMakeGuard.swift Sources/SillHost/VirtualDesktopLife.swift \
    Sources/SillHost/DesktopWindowLedger.swift Sources/SillHost/WindowRestore.swift Sources/StreamProtocol/VirtualDesktopWords.swift \
    Sources/StreamProtocol/DesktopDisplays.swift Sources/SillHost/VirtualDesktopBudget.swift Sources/SillHost/CaptureScale.swift \
    "$here/main.swift" -o "$out/check"
"$out/check" "$out"
