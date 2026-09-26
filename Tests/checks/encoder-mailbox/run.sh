#!/bin/bash
# EncoderMailbox (Sources/SillHost/EncoderMailbox.swift) on its own: HEVCEncoder's frames on their way
# into VideoToolbox (one inside, the one-slot mailbox, the watchdog's clock, timestamps, keyframe
# requests, abandon and the teardown) through a copy of HEVCEncoder's glue around a stand-in for
# VideoToolbox, in virtual time. A binary that links VideoToolbox is refused before it runs.
#   Tests/checks/encoder-mailbox/run.sh             compile and run the check
#   Tests/checks/encoder-mailbox/run.sh --mutants   one-line mutants of EncoderMailbox.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O Sources/SillHost/EncoderMailbox.swift "$here/main.swift" -o "$out/check"
if otool -L "$out/check" | grep -q VideoToolbox; then echo "REFUSED: $out/check links VideoToolbox"; exit 1; fi
"$out/check"
