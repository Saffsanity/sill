#!/bin/bash
# WindowOrder (Sources/StreamProtocol): where a window's thumbnail goes in the bar. The host's
# first-seen order puts a window first the first time it is listed and gives one that leaves and
# comes back (minimized, on another Space) its old place; a device's arrangement takes windows it
# has never seen this session at its start, and nothing on the session's first list.
# Compiled with Sources/StreamProtocol as one module.
#   Tests/checks/window-order/run.sh             compile and run the check
#   Tests/checks/window-order/run.sh --mutants   one-line mutants of WindowOrder.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
swiftc -O Sources/StreamProtocol/*.swift "$here/main.swift" -o "$out/check"
"$out/check"
