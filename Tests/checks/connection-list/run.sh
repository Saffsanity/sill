#!/bin/bash
# ConnectionList (iOSClient), the connect screen's list/tiles style, per-Mac groups and sections,
# preview JPEG filenames and pruning, and tile columns.
#   Tests/checks/connection-list/run.sh             compile and run the check
#   Tests/checks/connection-list/run.sh --mutants   one-line mutants of ConnectionList.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
swiftc -O iOSClient/ConnectionList.swift "$here/main.swift" -o "$out/check"
"$out/check"
