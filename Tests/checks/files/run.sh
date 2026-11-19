#!/bin/bash
# Files and photos between a device and the Mac (docs/files-plan.md §5, §6 and §10): kind 34 (#66's FileChunk) and
# kind 49 (FileTransfer) on the wire, the window list's and the hello's `files`, FilePolicy's rules at each edge and in
# their order, FileNames on hostile names and 20,000 random ones, FileFlow's windows, the two ledgers (FileReceiver,
# FileSender) case by case and against each other through a model of the connection, 5,000 transfers each way, and
# every word (FilesCopy). Compiled with the files in module.txt as one module.
#   Tests/checks/files/run.sh             compile and run the check
#   Tests/checks/files/run.sh --mutants   one-line mutants of Files.swift, FilePolicy.swift and the fields; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
python3 "$here/../module.py" "$name" "$root" "$out/check"
