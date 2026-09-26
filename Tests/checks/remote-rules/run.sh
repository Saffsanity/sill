#!/bin/bash
# The device's remote-access rules, compiled with StreamProtocol's sources as one module (build.sh
# strips `import StreamProtocol`): DiscoveryPolicy's Remote rows and automatic remote dial,
# RemoteDialPolicy (the order a saved Mac's addresses are tried in, what a failure means, scans)
# and SavedMacs.
#   Tests/checks/remote-rules/run.sh             compile and run the check
#   Tests/checks/remote-rules/run.sh --mutants   one-line mutants of the three files; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
"$here/build.sh" "$root" "$out/check"
[ -x "$out/check" ] || { echo "$name: did not compile" >&2; exit 1; }
"$out/check"
