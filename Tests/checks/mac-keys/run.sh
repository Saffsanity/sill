#!/bin/bash
# The Mac client's keys (Sources/MacClient/MacKeyMap.swift) against the host's (KeyStrokes): every
# keycode the client sends is a HID usage the host posts as that same keycode, every key the host
# can post is one the client sends, a modifier key's flag is the one the host holds for it, and the
# modifier bits on the wire are the host's flags with nothing else (fn, the numeric pad).
#   Tests/checks/mac-keys/run.sh             compile and run the check
#   Tests/checks/mac-keys/run.sh --mutants   one-line mutants of MacKeyMap.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
"$here/build.sh" "$root" "$out/check"
[ -x "$out/check" ] || { echo "$name: did not compile" >&2; exit 1; }
"$out/check"
