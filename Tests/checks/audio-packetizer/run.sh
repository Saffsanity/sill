#!/bin/bash
# AudioPacketizer (Sources/SillHost/AudioPacketizer.swift) on its own: how the Mac's sound becomes
# packet-sized blocks with their stamps (docs/audio-plan.md §4.3, H3): the packet size from the first
# chunk, the stamps against each chunk's anchor, the continuity tolerance, gaps that end a segment
# with nothing flushed or filled, a format change; AudioSourceRule's table; PCMLayout's conversions to
# interleaved stereo; the first minute's tally of the capture's time stamps.
#   Tests/checks/audio-packetizer/run.sh             compile and run the check
#   Tests/checks/audio-packetizer/run.sh --mutants   one-line mutants of AudioPacketizer.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
swiftc -O Sources/SillHost/AudioPacketizer.swift "$here/main.swift" -o "$out/check"
"$out/check"
