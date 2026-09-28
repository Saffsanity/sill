#!/bin/bash
# IdentityStorePlan (Sources/SillMenuBar), which identity store the menu-bar host uses at launch
# (docs/keychain-plan.md §4): the data-protection keychain only for an entitled real Sill.app and
# never the legacy one beside it, the legacy login keychain for an unentitled real Sill.app, and no
# keychain at all for a test host. Compiled on its own with swiftc (Foundation only).
#   Tests/checks/keychain/run.sh             compile and run the check
#   Tests/checks/keychain/run.sh --mutants   one-line mutants of IdentityStorePlan.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
"$here/build.sh" "$root" "$out/check"
[ -x "$out/check" ] || { echo "$name: did not compile" >&2; exit 1; }
"$out/check"
