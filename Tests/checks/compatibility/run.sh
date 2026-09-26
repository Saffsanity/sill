#!/bin/bash
# Sources/StreamProtocol compiled as one module with the check: SillVersion (how tags, bundles and the
# wire write a version, and their order), SillProtocol, and the update notice's payloads: kind 23's
# Hello, kind 22's new fields with the five goodbyes of before byte for byte, and the window list's
# hostVersion and protocol (docs/update-notice-plan.md, section 3).
#   Tests/checks/compatibility/run.sh             compile and run the check
#   Tests/checks/compatibility/run.sh --mutants   one-line mutants of StreamProtocol; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
swiftc -O Sources/StreamProtocol/*.swift "$here/main.swift" -o "$out/check"
"$out/check"
