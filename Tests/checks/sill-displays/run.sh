#!/bin/bash
# Every display Sill makes goes through SillDisplays (docs/virtual-desktop-plan.md §9 as revised 2026-11-18, phase 2b):
# the roles' identities (SillDisplayRole: macOS remembers a display by them, and DesktopDisplays.role tells Sill's two
# displays apart by them; the guard's marker names the role) and the wiring, read as text: no display made anywhere else
# in the host but its self test, each role's display made, waited for, listed, lost and removed there, the guard's
# marker around each make, the stage's IDs given to the catalog. Nothing here makes a display.
#   Tests/checks/sill-displays/run.sh             compile and run the check
#   Tests/checks/sill-displays/run.sh --mutants   one-line mutants of SillDisplayRole.swift and of the wiring; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
"$here/build.sh" "$root" "$out/check"
[ -x "$out/check" ] || { echo "$name: did not compile" >&2; exit 1; }
"$out/check" "$root"
