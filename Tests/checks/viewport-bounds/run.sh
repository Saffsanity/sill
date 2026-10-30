#!/bin/bash
# ViewportBounds (Sources/StreamProtocol/Viewport.swift) on its own, with the Data helpers it uses
# (StreamMessage.swift): what a host takes from a device's viewport (kind 9), each side 1 to 16384 points
# and a text scale 0.25 to 4, any other refused whole (security scan, finding 4: a side of 1e300 points, or
# a scale of 1e-300, reached the Mac window's fit and the virtual display's window size, whose lines'
# Int() trapped and the host died); the bug before it in a copy of the host's arithmetic; what JSON can
# carry; what a device sends (`held`) and the numbers the host's lines print (`whole`, `number`); then
# 200,000 random viewports, real and hostile, against the rule's properties; and a device's late-sound
# count (ClientStats.lateSince), which the host's stats line adds up without trapping past Int.max.
#   Tests/checks/viewport-bounds/run.sh             compile and run the check
#   Tests/checks/viewport-bounds/run.sh --mutants   one-line mutants of Viewport.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
rm -f "$out/check"
swiftc -O Sources/StreamProtocol/Viewport.swift Sources/StreamProtocol/StreamMessage.swift "$here/main.swift" -o "$out/check"
"$out/check"
