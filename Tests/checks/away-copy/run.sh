#!/bin/bash
# AwayCopy (iOSClient/AwayCopy.swift, docs/remote-bundle-plan.md §5.8, §6.7 and §8): the Settings
# panel's away line, footnote and link callout with its button, the stream screen's line and when it
# shows (LinkLine), compiled with StreamProtocol's HostSettings.swift.
#   Tests/checks/away-copy/run.sh             compile and run the check
#   Tests/checks/away-copy/run.sh --mutants   one-line mutants of AwayCopy.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/AwayCopy.swift Sources/StreamProtocol/HostSettings.swift "$here/main.swift" -o "$out/check"
"$out/check"
