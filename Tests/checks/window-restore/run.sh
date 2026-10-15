#!/bin/bash
# WindowRestore (Sources/SillHost/WindowRestore.swift; docs/restore-window-frames-plan.md, issue #57):
# a window Sill sized for a device goes back when it stops streaming. The rule at its edges (`keep`,
# `fitted` and `movedSince`, `decide` for every outcome, `homeForStage`, the ledger, the lines), the
# sequences that fit a window and put it back (`fit`, `stop`, `stageHome`, `Ledger.restore`,
# `keepsStreaming`, `coversDisplay`) against a stand-in window that logs every call, then a stand-in
# Mac answering the real sequences, with a copy of the coordinator's glue around them: 5,000 random
# sessions of picks, viewports, restarts, the catalog's looks, the person at the Mac moving, resizing
# (from any edge or corner), closing and full-screening windows (off the list on the way), apps that
# clamp, snap, apply a size late, answer late or fail a read-back, the virtual display on and off, the
# last device leaving and Quit. Compiled alone with swiftc (Foundation and CoreGraphics).
#   Tests/checks/window-restore/run.sh             compile and run the check
#   Tests/checks/window-restore/run.sh --mutants   one-line mutants of WindowRestore.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
"$here/build.sh" "$root" "$out/check"
[ -x "$out/check" ] || { echo "$name: did not compile" >&2; exit 1; }
"$out/check"
