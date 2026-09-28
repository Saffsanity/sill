#!/bin/bash
# The device's home model against StreamProtocol's own values (the wire's strings, a real kind 20, a
# real TXT tag), then pairing at home walked end to end through the pure rules as StreamClient chains
# them: a row, a tap, the ask and its answer, the record saved, the pinned session, a removal, a new
# pairing, an older Sill.app, an open door, a look-alike (docs/home-pairing-plan.md §7.2–7.7).
# Compiled with the files in module.txt as one module (../module.py drops their `import StreamProtocol`).
#   Tests/checks/home-model/run.sh             compile and run the check
#   Tests/checks/home-model/run.sh --mutants   one-line mutants of DiscoveryPolicy.swift and SavedMacs.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
python3 "$here/../module.py" "$name" "$root" "$out/check"
