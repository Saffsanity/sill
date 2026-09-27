#!/bin/bash
# KeyStrokes (Sources/SillHost): the keyboard events the Mac is sent for a device's keys, and what
# they leave in its HID state table, which every click and scroll after them starts from (CLAUDE.md,
# "The stuck command after Spotlight"): a key's up leaves only the modifiers still held down, a
# modifier's own key goes up without its flag, a device's own report of its modifiers lets go of the
# keys it no longer holds, and a device that leaves has its keys let go. Scenarios with the exact
# events, and random sessions of two devices against the model's invariant.
# Compiled with StreamProtocol's sources as one module (build.sh).
#   Tests/checks/key-strokes/run.sh             compile and run the check
#   Tests/checks/key-strokes/run.sh --mutants   one-line mutants of KeyStrokes.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
"$here/build.sh" "$root" "$out/check"
[ -x "$out/check" ] || { echo "$name: did not compile" >&2; exit 1; }
"$out/check"
