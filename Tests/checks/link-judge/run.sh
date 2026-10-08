#!/bin/bash
# LinkJudge (docs/remote-bundle-plan.md §6, H10): a device's link judged each second (fine, behind,
# stalled), the carried rate, the suggestion and the host's lines.
#   Tests/checks/link-judge/run.sh             compile and run the check
#   Tests/checks/link-judge/run.sh --mutants   one-line mutants of LinkJudge.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
"$here/build.sh" "$root" "$out/check"
[ -x "$out/check" ] || { echo "$name: did not compile" >&2; exit 1; }
"$out/check"
