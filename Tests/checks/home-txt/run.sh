#!/bin/bash
# Pairing at home's wire values (Sources/StreamProtocol): HomeDoorTXT (the TXT record's `p`), kinds
# 19, 20 and 22 as docs/home-pairing-plan.md §3.1 shows them on the wire, and the RemoteTLS
# parameters overload for the home door.
# Compiled with the files in module.txt as one module (../module.py drops their `import StreamProtocol`).
#   Tests/checks/home-txt/run.sh             compile and run the check
#   Tests/checks/home-txt/run.sh --mutants   one-line mutants of Pairing.swift, Remote.swift and RemoteTLS.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
python3 "$here/../module.py" "$name" "$root" "$out/check"
