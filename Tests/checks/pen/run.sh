#!/bin/bash
# PenTablet (Sources/SillHost): an Apple Pencil's messages (kind 45) as what the Mac posts for them
# (docs/pencil-pressure-plan.md §4.1): the pen coming into range before its first point and leaving
# at each of its causes (the device's leave, a second after an up with no hover since, the device
# leaving, the host's end), never for mouse input nor for a hover held still, as Sidecar's Pencil;
# the tip as the left button, the pen's own (a down it posted gets exactly one up), each sample's
# pressure and tilt as macOS wants them, the pointer event a message amounts to for kind 8's rules,
# and what still goes with nowhere to land.
# Scenarios with the exact posts, and random sessions of two devices' pens and mouse input against
# a model and its invariants.
# PenStrokes (iOSClient): what the device sends: whether a stroke goes as a pen's or the mouse's,
# fixed as the tip lands; a touch's force and angles as the wire's samples, every reading of a
# callback in messages of 32 at most; the leave, only when a Pencil that can hover is neither
# touching nor hovering a moment later; and the fingers that say nothing while the tip is on the
# glass (a resting palm). Then a Pencil's session through both: what the device sends, as the Mac
# posts it. Compiled with StreamProtocol's sources as one module (build.sh).
#   Tests/checks/pen/run.sh             compile and run the check
#   Tests/checks/pen/run.sh --mutants   one-line mutants of PenTablet.swift and PenStrokes.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
"$here/build.sh" "$root" "$out/check"
[ -x "$out/check" ] || { echo "$name: did not compile" >&2; exit 1; }
"$out/check"
