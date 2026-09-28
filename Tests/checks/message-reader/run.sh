#!/bin/bash
# MessageReader (iOSClient/MessageReader.swift, with StreamProtocol's StreamMessage.swift) against a
# stand-in Mac on loopback: the session's reader takes a payload in pieces of at most 256 KB and
# reports each, so liveness counts bytes (docs/remote-bundle-plan.md §3.4, H5). About 10 s.
#   Tests/checks/message-reader/run.sh [CASE...]   compile, then run every case (or the ones named)
#   Tests/checks/message-reader/run.sh --mutants   one-line mutants of MessageReader.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/MessageReader.swift Sources/StreamProtocol/StreamMessage.swift "$here/main.swift" -o "$out/check"
"$out/check" "$@"
