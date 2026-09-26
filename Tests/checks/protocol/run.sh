#!/bin/bash
# Sources/StreamProtocol compiled as one module with the check: the address parser, SafeText, pairing
# codes and proofs, recognition tags, the Mac ID, the hand-built certificate, kind 18's signature,
# message framing, and TLS 1.3 with pinned keys, live on loopback. crosscheck.py then checks what it
# wrote (the certificate and a signed kind 18) with Python and the system's openssl (/usr/bin).
#   Tests/checks/protocol/run.sh             compile and run the check, then the cross-check
#   Tests/checks/protocol/run.sh --mutants   one-line mutants of StreamProtocol; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
swiftc -O Sources/StreamProtocol/*.swift "$here/main.swift" -o "$out/check"
rm -rf "$out/data"
mkdir -p "$out/data"
"$out/check" "$out/data"
python3 "$here/crosscheck.py" "$out/data"
