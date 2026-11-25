#!/bin/bash
# HomePacing (Sources/SillHost/HomePacing.swift): frame pacing and recovery keyframe requests for
# clients at home (Wi-Fi, Personal Hotspot over link-local, Ethernet, peer-to-peer, USB, loopback).
#   Tests/checks/home-pacing/run.sh             compile and run the check
#   Tests/checks/home-pacing/run.sh --mutants   one-line mutants of HomePacing.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
python3 "$here/../module.py" "$name" "$root" "$out/check"
