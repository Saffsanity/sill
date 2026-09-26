#!/bin/bash
# AddressList and PairingWindow (Sources/SillHost), compiled with OriginPolicy and StreamProtocol's
# sources as one module (build.sh strips `import StreamProtocol`): the addresses the Mac offers for
# remote access, from its network services and tunnels, and the pairing window's codes and tries.
#   Tests/checks/addresses/run.sh             compile and run the check
#   Tests/checks/addresses/run.sh --mutants   one-line mutants of the two files; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
rm -f "$out/check"
"$here/build.sh" "$root" "$out/check"
[ -x "$out/check" ] || { echo "$name: did not compile" >&2; exit 1; }
"$out/check"
