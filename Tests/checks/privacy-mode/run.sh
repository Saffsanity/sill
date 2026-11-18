#!/bin/bash
# PrivacyModePolicy (Sources/SillMenuBar), when Sill blanks the Mac's physical displays during an
# active session and when it locks the Mac after the last device disconnects (issues #133 and #141):
# physical vs virtual display filtering, state transitions across connect/disconnect/settings/quit,
# and log lines. Compiled on its own with swiftc (CoreGraphics and Foundation only).
#   Tests/checks/privacy-mode/run.sh             compile and run the check
#   Tests/checks/privacy-mode/run.sh --mutants   one-line mutants of PrivacyModePolicy.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
"$here/build.sh" "$root" "$out/check"
[ -x "$out/check" ] || { echo "$name: did not compile" >&2; exit 1; }
"$out/check"
