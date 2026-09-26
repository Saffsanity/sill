#!/bin/bash
# EncoderSlowState (Sources/SillHost/EncoderSlowState.swift) on its own: when a hardware stream's
# session has settled in the encoder's slow state and gets a new one, and how the new one is judged:
# the rule at its edges by hand, and streams in virtual time through a stand-in for HEVCEncoder's
# glue against a scripted engine. A binary that links VideoToolbox is refused before it runs.
#   Tests/checks/encoder-slowstate/run.sh             compile and run the check
#   Tests/checks/encoder-slowstate/run.sh --mutants   one-line mutants of EncoderSlowState.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O Sources/SillHost/EncoderSlowState.swift "$here/main.swift" -o "$out/check"
if otool -L "$out/check" | grep -q VideoToolbox; then echo "REFUSED: $out/check links VideoToolbox"; exit 1; fi
"$out/check"
