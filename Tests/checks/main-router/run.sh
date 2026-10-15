#!/bin/bash
# The Mac client's MainRouter (Sources/MacClient/MainRouter.swift): the main stream's frames go to
# the window they belong to across focus changes. The old stream's keep going to the old window until
# the new stream's parameter sets come (differing from the old, or after the host said it switched),
# a window's first picture is its own keyframe, and a window the main stream draws into (or is about
# to) is reported so its side frames stay out.
#   Tests/checks/main-router/run.sh             compile and run the check
#   Tests/checks/main-router/run.sh --mutants   one-line mutants of MainRouter.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
"$here/build.sh" "$root" "$out/check"
[ -x "$out/check" ] || { echo "$name: did not compile" >&2; exit 1; }
"$out/check"
