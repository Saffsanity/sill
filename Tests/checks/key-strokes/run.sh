#!/bin/bash
# KeyStrokes (Sources/SillHost): the keyboard events the Mac is sent for a device's keys, and what
# they leave in its HID state table, which every click and scroll after them starts from (CLAUDE.md,
# "The stuck command after Spotlight"): a key's up leaves only the modifiers still held down, a
# modifier's own key goes up without its flag, a device's own word on its modifiers lets go of the
# keys it no longer holds, and a device that leaves, or the host that goes, lets go of its keys; and the
# check after every key's up (KeyUpCheck), which reports what an up left set on a Mac that keeps its
# table through some ups.
# KeyChords (iOSClient): what the device sends, a shortcut with its modifiers' own keys around it and
# a hardware key's up after its down, which leaves nothing held on this Mac or on one from before.
# Scenarios with the exact events, and random sessions against the model's invariant and the check's.
# Compiled with StreamProtocol's sources as one module (build.sh).
#   Tests/checks/key-strokes/run.sh             compile and run the check
#   Tests/checks/key-strokes/run.sh --mutants   one-line mutants of KeyStrokes.swift and KeyChords.swift;
#                                               each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
"$here/build.sh" "$root" "$out/check"
[ -x "$out/check" ] || { echo "$name: did not compile" >&2; exit 1; }
"$out/check"
