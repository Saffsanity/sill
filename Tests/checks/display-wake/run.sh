#!/bin/bash
# DisplayWake (Sources/SillHost/DisplayWake.swift) with the wire's message kinds and input events
# (StreamMessage.swift, Input.swift): when the host declares user activity on the Mac for a device, as
# a key press would (issue #134): which of a device's messages are a person at it (a connect, kinds 7,
# 8, 15, 25 and 28; never a pick, nor a bare pointer move just after the host's own stream restart),
# at most once every 5 s but a connect, a test host counting instead, what DisplayActivity says after
# its second look, the TEST ONLY user type, then random sessions against the invariants. Pure:
# nothing is declared.
#   Tests/checks/display-wake/run.sh             compile and run the check
#   Tests/checks/display-wake/run.sh --mutants   one-line mutants of DisplayWake.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
"$here/build.sh" "$root" "$out/check"
[ -x "$out/check" ] || { echo "$name: did not compile" >&2; exit 1; }
"$out/check"
