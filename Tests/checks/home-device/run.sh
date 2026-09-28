#!/bin/bash
# DiscoveryPolicy's home rules on their own (iOSClient/DiscoveryPolicy.swift): every row's word
# (§7.3) and what a tap dials (§7.4), DEBUG and Release, homeTLS and revoked; the device's cable check
# (§7.5); the rows' VoiceOver labels and hints (docs/home-pairing-plan.md).
# Compiled with the files in module.txt as one module (../module.py drops their `import StreamProtocol`).
#   Tests/checks/home-device/run.sh             compile and run the check
#   Tests/checks/home-device/run.sh --mutants   one-line mutants of DiscoveryPolicy.swift's home rules; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
python3 "$here/../module.py" "$name" "$root" "$out/check"
