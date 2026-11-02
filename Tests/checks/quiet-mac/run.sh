#!/bin/bash
# QuietMac (Sources/SillHost/QuietMac.swift) on its own: whether the Mac's sound goes through a Core Audio
# process tap that silences it on the Mac while devices play it, or through ScreenCaptureKit as before.
#   Tests/checks/quiet-mac/run.sh             compile and run the check
#   Tests/checks/quiet-mac/run.sh --mutants   one-line mutants of QuietMac.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
rm -f "$out/check"
swiftc -O Sources/SillHost/QuietMac.swift "$here/main.swift" -o "$out/check"
"$out/check"
