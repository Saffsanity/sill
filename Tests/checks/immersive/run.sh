#!/bin/bash
# ImmersivePolicy (iOSClient/ImmersivePolicy.swift) on its own: when the iPad's Immersive mode applies,
# which of its three states the stream screen is in (off, immersed, revealed), what the shortcut, the
# top edge's swipe, a holder opening and closing and the auto-hide timer do, then 20,000 random
# sessions against the invariants (docs/immersive-plan.md).
#   Tests/checks/immersive/run.sh             compile and run the check
#   Tests/checks/immersive/run.sh --mutants   one-line mutants of ImmersivePolicy.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/ImmersivePolicy.swift "$here/main.swift" -o "$out/check"
"$out/check"
