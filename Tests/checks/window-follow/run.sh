#!/bin/bash
# WindowFollow (Sources/SillHost), when the stream follows a window the streamed app opens by itself
# (regular mode), and where it goes back to when that window closes.
# Compiled with StreamProtocol's sources as one module (build.sh strips `import StreamProtocol`).
#   Tests/checks/window-follow/run.sh             compile and run the check
#   Tests/checks/window-follow/run.sh --mutants   one-line mutants of WindowFollow.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
"$here/build.sh" "$root" "$out/check"
[ -x "$out/check" ] || { echo "$name: did not compile" >&2; exit 1; }
"$out/check"
