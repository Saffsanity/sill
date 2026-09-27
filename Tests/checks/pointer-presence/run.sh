#!/bin/bash
# PointerPresence (iOSClient/PointerPresence.swift) on its own: what the device's one pointer sprite
# shows, row by row of docs/pointer-visibility-plan.md's "What the device draws" (the Mac's pointer,
# the portrait trackpad's, never the Pencil's by default, both flips); when a report from the Mac
# (kind 26) is fresh; the network queue's feed (who has the pointer, the anchor's newest-wins,
# re-seeds, a hand-over's carry-over and its restatements); and the portrait pad's cursor (a
# stroke's start, the re-seed after the Mac took the pointer or moved it on under a resting finger).
#   Tests/checks/pointer-presence/run.sh             compile and run the check
#   Tests/checks/pointer-presence/run.sh --mutants   one-line mutants of PointerPresence.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
swiftc -O iOSClient/PointerPresence.swift "$here/main.swift" -o "$out/check"
"$out/check"
