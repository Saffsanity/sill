#!/bin/bash
# PairingWindowAddress (Sources/SillMenuBar), compiled with AddressList, OriginPolicy and
# StreamProtocol's sources as one module (build.sh): the address the pairing window gives to type,
# Tailscale's name and IPv4 first, any other VPN's address under this network's, with random runs.
#   Tests/checks/pairing-address/run.sh             compile and run the check
#   Tests/checks/pairing-address/run.sh --mutants   one-line mutants of the file; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
"$here/build.sh" "$root" "$out/check"
[ -x "$out/check" ] || { echo "$name: did not compile" >&2; exit 1; }
"$out/check"
