#!/bin/bash
# DeviceIdlePolicy (iOSClient/DeviceIdlePolicy.swift) on its own: when Sill holds the device's own
# auto-lock off (PR #230, towards issue #134): while one of its windows the person can see streams,
# until 10 minutes after the person last used it; then 20,000 random sets of windows against the
# invariants.
#   Tests/checks/device-idle/run.sh             compile and run the check
#   Tests/checks/device-idle/run.sh --mutants   one-line mutants of DeviceIdlePolicy.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/DeviceIdlePolicy.swift "$here/main.swift" -o "$out/check"
"$out/check"
