#!/bin/bash
# FileStore (Sources/SillHost/FileStore.swift; docs/files-plan.md §7.1, §7.3 and §11) on a scratch folder of its own
# under .build/checks/file-store, never ~/Downloads: the destination and its hidden staging folder, parts written and
# hashed, a wrong hash and a short file refused, a collision with a file and with a link, the quarantine and Where from
# read back, mode 0644, links refused, leftovers cleaned, the free space, errno's meaning.
# Compiled with the files in module.txt as one module.
#   Tests/checks/file-store/run.sh             compile and run the check
#   Tests/checks/file-store/run.sh --mutants   one-line mutants of FileStore.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
python3 "$here/../module.py" "$name" "$root" "$out/check"
