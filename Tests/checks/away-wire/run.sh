#!/bin/bash
# Kind 16's two new fields (docs/remote-bundle-plan.md §4, H6): AwayQuality and LinkReport under their
# wire names, what decodes and what does not, an older host's state and an older device's decoder, and
# QualityPreset's name(forBitrate:) and shortTitle(bitrate:captureScale:).
#   Tests/checks/away-wire/run.sh             compile and run the check
#   Tests/checks/away-wire/run.sh --mutants   one-line mutants of HostSettings.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O Sources/StreamProtocol/HostSettings.swift "$here/main.swift" -o "$out/check"
"$out/check"
