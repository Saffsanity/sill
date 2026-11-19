#!/bin/bash
# Kind 48, the device's microphone on the Mac (Microphone.swift, docs/microphone-plan.md §4), and both ends'
# rules (MicrophonePolicy.swift): Sources/StreamProtocol compiled as one module with the check. The wire's
# three types, caps and bounds; kind 16's MicrophoneState and the list's field; the device's rule over every
# combination of its inputs, its link's messages, its window and its words; the Mac's reducer at each edge;
# then 3,000 random sessions of devices and a Mac together against the invariants.
#   Tests/checks/microphone/run.sh             compile and run the check
#   Tests/checks/microphone/run.sh --mutants   one-line mutants of StreamProtocol; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
swiftc -O Sources/StreamProtocol/*.swift "$here/main.swift" -o "$out/check"
"$out/check"
