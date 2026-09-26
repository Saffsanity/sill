#!/bin/bash
# UpdatePolicy (Sources/SillMenuBar), Sill.app's update check: what each answer from GitHub's
# releases feed means (every row of the plan's section 6.4), the offer, the schedule, the feeds and
# pages it accepts, and every text (docs/update-notice-plan.md, section 6).
# Compiled with StreamProtocol's sources as one module (build.sh strips `import StreamProtocol`).
#   Tests/checks/update-policy/run.sh             compile and run the check
#   Tests/checks/update-policy/run.sh --mutants   one-line mutants of UpdatePolicy.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
"$here/build.sh" "$root" "$out/check"
[ -x "$out/check" ] || { echo "$name: did not compile" >&2; exit 1; }
"$out/check"
