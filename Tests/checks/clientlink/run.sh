#!/bin/bash
# ClientLink (Sources/SillHost/ClientLink.swift) on its own: which route a client came by, from its
# endpoint's scope and its path's interfaces (runsPeerToPeer), and the menu card's word for it:
# Wired, Wi-Fi, Direct or none. Its `package` access needs -package-name.
#   Tests/checks/clientlink/run.sh             compile and run the check
#   Tests/checks/clientlink/run.sh --mutants   one-line mutants of ClientLink.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O -package-name sill Sources/SillHost/ClientLink.swift "$here/main.swift" -o "$out/check"
"$out/check"
