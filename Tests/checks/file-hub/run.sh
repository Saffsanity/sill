#!/bin/bash
# FileHub (Sources/SillHost/FileHub.swift; docs/files-plan.md §7) with FileStore, LockPolicy and the ledgers, fed a
# device's kinds 34 and 49 as the server hands them on, on a scratch folder of its own under .build/checks/file-hub
# (never ~/Downloads), with no network, no host and no encoder: what it answers, what it keeps, what it deletes.
# Compiled with the files in module.txt as one module.
#   Tests/checks/file-hub/run.sh             compile and run the check
#   Tests/checks/file-hub/run.sh --mutants   one-line mutants of FileHub.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
python3 "$here/../module.py" "$name" "$root" "$out/check"
