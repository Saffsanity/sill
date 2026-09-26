#!/bin/bash
# DeviceGate (Sources/SillHost), the host's device floor: which hello the floor admits, the refusal's
# words ("Update Sill on your iPad to keep using Mac mini. It needs version 1.2 or later."), the
# Refused, count and hello log lines, and that the shipped floor parses and is "0"
# (docs/update-notice-plan.md, section 4).
# Compiled with StreamProtocol's sources as one module (build.sh strips `import StreamProtocol`).
#   Tests/checks/device-gate/run.sh             compile and run the check
#   Tests/checks/device-gate/run.sh --mutants   one-line mutants of DeviceGate.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
"$here/build.sh" "$root" "$out/check"
[ -x "$out/check" ] || { echo "$name: did not compile" >&2; exit 1; }
"$out/check"
