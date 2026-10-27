#!/bin/bash
# SpotlightMacs (iOSClient), saved Macs in Spotlight: their identifiers, which are indexed, and which
# row a Spotlight tap dials (the network row at once, a Remote row only after the network's 3 s).
#   Tests/checks/spotlight-macs/run.sh             compile and run the check
#   Tests/checks/spotlight-macs/run.sh --mutants   one-line mutants of SpotlightMacs.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
swiftc -O iOSClient/SpotlightMacs.swift "$here/main.swift" -o "$out/check"
"$out/check"
