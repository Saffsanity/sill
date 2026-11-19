#!/bin/bash
# VersionLabel (iOSClient/VersionLabel.swift) on its own: the app's version and build as the connect screen's
# footer and the Settings panel's last line show them (Noah, 2026-11-11; docs/version-label-plan.md): the
# words shown and copied ("Sill 0.6.2 (1400)") and spoken ("Sill version 0.6.2, build 1400"), from the two
# Info.plist keys, a missing one, white space, control and format characters, numbers, Booleans and other
# types, and 20,000 seeded random values against the invariants.
#   Tests/checks/version-label/run.sh             compile and run the check
#   Tests/checks/version-label/run.sh --mutants   one-line mutants of VersionLabel.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/VersionLabel.swift "$here/main.swift" -o "$out/check"
"$out/check"
