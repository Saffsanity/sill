#!/bin/bash
# DiscoveryPolicy (iOSClient/DiscoveryPolicy.swift) on its own: when the device looks nearby, its
# rows and the word each ends in, the session's route word, the wired dial, when a reconnect may take
# a Direct row, the move from AWDL to the network, a live session following the best path (the cable,
# Wi-Fi, Direct; pathPlan, upWait) and the remote rule, with grids and models of plugs and pulls; a
# remote session's move home (moveHome; moveHomeTrust: pinned TLS only; moveHomeRow and HomeRows: the row,
# chosen and refused by row; with a model of the glue);
# and pairing at home's session rules (home.swift: the pin, the trust a dial starts, how a session at
# home ends, the ask's answer, the words).
#   Tests/checks/policy/run.sh             compile and run the check
#   Tests/checks/policy/run.sh --mutants   one-line mutants of DiscoveryPolicy.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/DiscoveryPolicy.swift "$here/main.swift" "$here/home.swift" -o "$out/check"
"$out/check"
