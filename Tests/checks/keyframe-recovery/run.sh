#!/bin/bash
# KeyframeRecovery (iOSClient/KeyframeRecovery.swift) on its own: when the device asks the Mac for a
# keyframe after its picture was interrupted (issue #101): one ask per interruption while its keyframe
# is due, again when none came within its wait (4 s, or four round trips; a Mac that never answers is
# asked after 4, 8 and 16 s, then every 32 s), only while Sill is active and something streams, at
# least 2 s apart, longer for a picture that keeps failing (4, 8, 16, then 32 s), a trip to the
# background or 10 s of calm starting it afresh; then 20,000 random sessions against a model of the
# event history.
#   Tests/checks/keyframe-recovery/run.sh             compile and run the check
#   Tests/checks/keyframe-recovery/run.sh --mutants   one-line mutants of KeyframeRecovery.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
rm -f "$out/check"
swiftc -O iOSClient/KeyframeRecovery.swift "$here/main.swift" -o "$out/check"
"$out/check"
