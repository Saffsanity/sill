#!/bin/bash
# SettingsWindowFit (Sources/SillMenuBar), how tall Sill's Settings window may be on a screen and
# where it goes when Sill changes its size (issue #59, docs/settings-window-plan.md): the cases the
# issue raises, then seeded random screens, chromes and frames. Compiled on its own with swiftc
# (CoreGraphics only).
#   Tests/checks/settings-window/run.sh             compile and run the check
#   Tests/checks/settings-window/run.sh --mutants   one-line mutants of SettingsWindowFit.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
"$here/build.sh" "$root" "$out/check"
[ -x "$out/check" ] || { echo "$name: did not compile" >&2; exit 1; }
"$out/check"
