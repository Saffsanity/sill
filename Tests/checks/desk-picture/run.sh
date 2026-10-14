#!/bin/bash
# The desk's picture check (Sources/SillHost/DeskPicture.swift): a hidden display's picture of a
# window against the window alone, cell by cell: a sheet over part of it is the window, black or
# another picture is not, and a frame and a screenshot put the same picture in the same cells.
#   Tests/checks/desk-picture/run.sh             compile and run the check
#   Tests/checks/desk-picture/run.sh --mutants   one-line mutants of DeskPicture.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
xcrun swiftc -O -package-name sill Sources/SillHost/DeskPicture.swift "$here/main.swift" -o "$out/check"
"$out/check"
