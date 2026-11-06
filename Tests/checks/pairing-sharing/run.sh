#!/bin/bash
# PairingWindowSharing (Sources/SillMenuBar), whether screen sharing shows the pairing window (issue
# #108): Settings › Devices' "Show the pairing window to screen sharing" alone decides it, whoever
# opened the window; the window's NSWindow.SharingType for each answer; and the Log's lines for it.
# Compiled on its own with swiftc (Foundation, and AppKit for that enum alone: no window, no screen).
#   Tests/checks/pairing-sharing/run.sh             compile and run the check
#   Tests/checks/pairing-sharing/run.sh --mutants   mutants of PairingWindowSharing.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
"$here/build.sh" "$root" "$out/check"
[ -x "$out/check" ] || { echo "$name: did not compile" >&2; exit 1; }
"$out/check"
