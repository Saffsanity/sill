#!/bin/bash
# The Mac's menus on the device (docs/menu-bar-plan.md): kinds 24, 25 and 27 and their JSON
# (Sources/StreamProtocol/MacMenu.swift), and the host's pure parts (Sources/SillHost/MenuFormat.swift:
# an item and its shortcut as the Mac draws them, ids; MenuPolicy.swift: the 1 s cache, the request
# rates, the top level's comparison, the press decision, the refusals' words and the log's path).
# Compiled with StreamProtocol's sources as one module (build.sh strips the host files'
# `import StreamProtocol`), with -package-name sill for their `package` access.
#   Tests/checks/menus/run.sh             compile and run the check
#   Tests/checks/menus/run.sh --mutants   one-line mutants of the files it checks; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
"$here/build.sh" "$root" "$out/check"
[ -x "$out/check" ] || { echo "$name: did not compile" >&2; exit 1; }
"$out/check"
