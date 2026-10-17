#!/bin/bash
# DisplayWakePolicy (docs/display-wake-plan.md, #134): when the host declares a user active, so the
# Mac's display wakes for a device and stays on while it is used.
#   Tests/checks/display-wake/run.sh             compile and run the check
#   Tests/checks/display-wake/run.sh --mutants   one-line mutants of DisplayWakePolicy.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
"$here/build.sh" "$root" "$out/check"
[ -x "$out/check" ] || { echo "$name: did not compile" >&2; exit 1; }
"$out/check"
