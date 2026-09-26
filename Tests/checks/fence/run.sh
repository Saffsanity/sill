#!/bin/bash
# SessionLink (iOSClient/SessionLink.swift, with StreamProtocol's StreamMessage.swift) against a
# stand-in Mac on loopback: the moves' fenced hand-overs, the hold of a move off a lost path, adopt,
# unhold, and a new session dropping a hand-over. Each mode sends 600 numbered inputs from two
# threads and checks that they arrive complete and in order; nofence reproduces the hazard the fence
# is for (inversions), so the stand-in is known to catch it. About a second a mode on an M-series Mac;
# no mode's result depends on how fast the machine runs it, so a slower or busier one only takes
# longer (main.swift's header).
#   Tests/checks/fence/run.sh [MODE...]   compile, then run every mode (or the ones named)
#   Tests/checks/fence/run.sh --mutants   one-line mutants of SessionLink.swift; each must fail a mode
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/SessionLink.swift Sources/StreamProtocol/StreamMessage.swift "$here/main.swift" -o "$out/check"
modes=(ok nofence timeout oldcloses hold holdclosed unhold adoptfence twofences twomoves holdfence holdadopt newsession newsessionhold)
if [ $# -gt 0 ]; then modes=("$@"); fi
failed=()
for mode in "${modes[@]}"; do
    "$out/check" "$mode" || failed+=("$mode")
done
if [ ${#failed[@]} -gt 0 ]; then
    echo "fence: FAILED in ${failed[*]}" >&2
    exit 1
fi
echo "fence: all ${#modes[@]} modes passed"
