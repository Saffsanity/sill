#!/bin/bash
# GoodbyePolicy (iOSClient), how a session ends after the Mac's goodbye: every row of the plan's
# section 7.3 (today's five reasons, "update" and a reason the device does not know), the cleaning
# of the Mac's message, and when the device reconnects (docs/update-notice-plan.md).
# Compiled with StreamProtocol's sources as one module (build.sh strips `import StreamProtocol`).
#   Tests/checks/goodbye/run.sh             compile and run the check
#   Tests/checks/goodbye/run.sh --mutants   one-line mutants of GoodbyePolicy.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
"$here/build.sh" "$root" "$out/check"
[ -x "$out/check" ] || { echo "$name: did not compile" >&2; exit 1; }
"$out/check"
