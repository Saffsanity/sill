#!/bin/bash
# DeviceFiles (iOSClient/DeviceFiles.swift; docs/files-plan.md §8) and SessionLink's uplink ledger, a device's
# transfers into the Mac's own FileHub over loopback (a stand-in Mac that reads its connections as StreamServer
# does), on a scratch folder of its own under .build/checks/device-files (never ~/Downloads): files whole and
# hashed, never more than the window unacknowledged, a cancel, a hold, a lost connection, the Mac's refusals and
# stops, a folder, a file that cannot be read or shrinks, Sill's own copies deleted; and the ledger's rules.
# Compiled with the files in module.txt as one module.
#   Tests/checks/device-files/run.sh             compile and run the check
#   Tests/checks/device-files/run.sh --mutants   one-line mutants of DeviceFiles.swift and the ledger; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
python3 "$here/../module.py" "$name" "$root" "$out/check"
