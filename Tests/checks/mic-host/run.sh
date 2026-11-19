#!/bin/bash
# MicrophoneTestHook (Sources/SillHost/MicrophoneTestHook.swift; docs/microphone-plan.md §10.2): a test host's Sill
# Microphone, TEST ONLY: its variables, when it refuses them and its words, what its files say, the WAV header.
#   Tests/checks/mic-host/run.sh             compile and run the check
#   Tests/checks/mic-host/run.sh --mutants   one-line mutants of MicrophoneTestHook.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
swiftc -O Sources/SillHost/MicrophoneTestHook.swift "$here/main.swift" -o "$out/check"
"$out/check"
