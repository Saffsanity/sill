#!/bin/bash
# The device's settings ledger (iOSClient/HostSettingsLedger.swift) and the wire types
# (Sources/StreamProtocol/HostSettings.swift) as one module: scenarios, then random runs of a model
# host with up to three devices and the Mac's menu, every message through real JSON.
#   Tests/checks/ledger/run.sh [RUNS]   compile and run (RUNS random runs, 5,000 by default)
#   Tests/checks/ledger/run.sh --mutants   one-line mutants of the ledger and the merge it uses; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O Sources/StreamProtocol/HostSettings.swift iOSClient/HostSettingsLedger.swift "$here/main.swift" -o "$out/check"
"$out/check" "$@"
