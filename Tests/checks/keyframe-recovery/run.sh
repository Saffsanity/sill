#!/bin/bash
# KeyframeRecovery (iOSClient), when the device re-picks its source for a fresh keyframe after its
# display layer was interrupted: only while something streams, at most once per 2 s.
#   Tests/checks/keyframe-recovery/run.sh             compile and run the check
#   Tests/checks/keyframe-recovery/run.sh --mutants   one-line mutants of KeyframeRecovery.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
swiftc -O iOSClient/KeyframeRecovery.swift "$here/main.swift" -o "$out/check"
"$out/check"
