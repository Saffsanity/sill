#!/bin/bash
# Reach from Anywhere (docs/relay-plan.md): kinds 60 and 61 and MacInfo.relay on the wire (an older
# reader unchanged, a Mac without it signing the same bytes), RelayPolicy (who asks, who gets a key,
# which key a device takes), the device's dial order with the relay's forwarder, and the relay
# door's origin under DoorPolicy (away, never this Mac itself).
# Compiled with the files in module.txt as one module (../module.py drops their `import StreamProtocol`).
#   Tests/checks/relay/run.sh             compile and run the check
#   Tests/checks/relay/run.sh --mutants   one-line mutants of Relay.swift, Remote.swift and RemoteDialPolicy.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
python3 "$here/../module.py" "$name" "$root" "$out/check"
