#!/bin/bash
# FramePacing (docs/steps/2026-11-24-home-backlog.md): the frames each device is sent at home and away, the keyframes
# asked for on its behalf, who is dropped, and a model of a connection in virtual time.
#   Tests/checks/frame-pacing/run.sh             compile and run the check
#   Tests/checks/frame-pacing/run.sh --mutants   one-line mutants of FramePacing.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
"$here/build.sh" "$root" "$out/check"
[ -x "$out/check" ] || { echo "$name: did not compile" >&2; exit 1; }
"$out/check"
