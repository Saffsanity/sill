#!/bin/bash
# The clipboard (kind 32; docs/clipboard-plan.md): Sources/StreamProtocol compiled as one module with
# the check. Kind 32 and Clipboard's JSON, the caps, ClipboardPolicy's rules for both ends (what a
# device's message asks of the host, which change of the Mac's pasteboard the host sends, who a
# device's text goes to, the rate, the device's subscription, which text from the Mac it writes, the
# chip, the words), and two random models: the device's subscription against the host's view of it,
# and a host with three devices against what each must receive.
#   Tests/checks/clipboard/run.sh             compile and run the check
#   Tests/checks/clipboard/run.sh --mutants   one-line mutants of StreamProtocol; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
swiftc -O Sources/StreamProtocol/*.swift "$here/main.swift" -o "$out/check"
"$out/check"
