#!/bin/bash
# ConnectionInfo (iOSClient), the Settings panel's Connection Information rows and the text Copy gives:
# every row's words, a second without samples as a dash (never as zero), the UTC time.
#   Tests/checks/connection-info/run.sh             compile and run the check
#   Tests/checks/connection-info/run.sh --mutants   one-line mutants of ConnectionInfo.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
swiftc -O iOSClient/ConnectionInfo.swift "$here/main.swift" -o "$out/check"
"$out/check"
