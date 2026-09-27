#!/bin/bash
# PointerControl (Sources/SillHost), who moves the Mac's pointer (docs/pointer-visibility-plan.md
# §4.1): the settle that absorbs Sill's own input, posts and warps; a real move measured from the last
# position that counted (jitter never hands over, a slow drift adds up); keys handing the pointer back
# without the settle; one controller among two devices, and a leaving driver; a read after a gap
# starting afresh; when the pointer counts as moving (the frame-rate sampling, Q4); which inputs open
# the settle; the fraction kind 26 carries. Also kind 26 itself (StreamProtocol's Pointer.swift and
# StreamMessage.swift): MacPointer's JSON and the kind table, every earlier kind unchanged.
# Compiled with StreamProtocol's sources as one module (build.sh strips `import StreamProtocol`).
#   Tests/checks/pointer-control/run.sh             compile and run the check
#   Tests/checks/pointer-control/run.sh --mutants   one-line mutants of PointerControl.swift and
#                                                   Pointer.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
"$here/build.sh" "$root" "$out/check"
[ -x "$out/check" ] || { echo "$name: did not compile" >&2; exit 1; }
"$out/check"
