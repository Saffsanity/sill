#!/bin/bash
# MacMenuState (iOSClient), one connection's view of the Mac's menus on the device
# (docs/menu-bar-plan.md §7.2): the top level, fetches joined, answered, refused, timed out and
# settled exactly once, choices and their refusals, stale menus, a bar menu built from an older top
# level asking by its title, a move's hand-over, the rows and sections a menu shows, and a random
# model of a session's events.
# Compiled with StreamProtocol's sources as one module (build.sh strips `import StreamProtocol`).
#   Tests/checks/menu-state/run.sh             compile and run the check
#   Tests/checks/menu-state/run.sh --mutants   one-line mutants of MacMenuState.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
"$here/build.sh" "$root" "$out/check"
[ -x "$out/check" ] || { echo "$name: did not compile" >&2; exit 1; }
"$out/check"
