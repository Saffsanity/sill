#!/bin/bash
# The records pairing at home adds to: PairedDevice's `cableDevice` and "cable" (the Mac's trust list,
# Sources/SillHost/HostIdentity.swift) and SavedMac's `homeTLS` and `revoked` (the device's saved Macs,
# iOSClient/SavedMacs.swift). Older records decode, lists encode byte for byte as before, and an
# older reader reads the new records (docs/home-pairing-plan.md §3.4).
# Compiled with the files in module.txt as one module (../module.py drops their `import StreamProtocol`).
#   Tests/checks/home-records/run.sh             compile and run the check
#   Tests/checks/home-records/run.sh --mutants   one-line mutants of HostIdentity.swift and SavedMacs.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
python3 "$here/../module.py" "$name" "$root" "$out/check"
