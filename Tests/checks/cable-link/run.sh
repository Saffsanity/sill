#!/bin/bash
# CableLink (Sources/SillHost), what counts as the USB cable to an iPhone or iPad: this Mac's own IOKit
# readings with an iPad mini on the cable, the device ID, the test stand-in (docs/home-pairing-plan.md
# §4.3).
# Compiled with the files in module.txt as one module (../module.py drops their `import StreamProtocol`).
#   Tests/checks/cable-link/run.sh             compile and run the check
#   Tests/checks/cable-link/run.sh --mutants   one-line mutants of CableLink.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
python3 "$here/../module.py" "$name" "$root" "$out/check"
