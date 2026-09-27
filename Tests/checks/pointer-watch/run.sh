#!/bin/bash
# PointerWatch (Sources/SillHost), the host's shell around PointerControl
# (docs/pointer-visibility-plan.md §4.2, §4.10): a sample reads nothing without a geometry, and a
# synthetic host never reads the real pointer; the fraction and inside per geometry, a regular-mode
# window's bounds and on-screen flag re-read off the sampling thread (after a move, at most every
# 0.1 s, and every 2 s anyway), never waited for, a stale answer dropped and an owed one run; the
# kind 26 each device is sent (nothing to the one driving); Sill's own motion noted before it lands;
# the TEST ONLY scripted pointer (SILL_TEST_POINTER_PATH: its file, its clock, a dry run's move
# against its steps) and SILL_TEST_SOFTWARE_ENCODER, with their lines.
# Compiled with PointerControl.swift, Stats.swift and StreamProtocol's sources as one module
# (build.sh strips `import StreamProtocol`).
#   Tests/checks/pointer-watch/run.sh             compile and run the check
#   Tests/checks/pointer-watch/run.sh --mutants   one-line mutants of PointerWatch.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
"$here/build.sh" "$root" "$out/check"
[ -x "$out/check" ] || { echo "$name: did not compile" >&2; exit 1; }
"$out/check"
