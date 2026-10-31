#!/bin/bash
# LockPolicy (Sources/SillHost/LockPolicy.swift; docs/locked-mac-plan.md): a locked Mac. The three readings
# and every combination of the witnesses (unknown counts as locked); what each notification sets; the settle
# before an unlock (the flap of a return to the console; random witness sequences); when SessionLock reads;
# what each reading allows; what the server's gate withholds by kind and picture; each request at each
# reading, paired and not, judged at the more restrictive of its arrival and now; the window list
# (`locked`, `offConsole`) and its JSON both ways; the placeholder's size; `reconciles`; the window that comes
# back (`Restore`); the TEST ONLY hooks' words; the lines; LockGate; the device's words and cover
# (StreamProtocol's LockedMac); and a copy of the coordinator's glue run through directed and random
# sessions against the rule's invariants.
# Compiled with the files in module.txt as one module (../module.py drops their `import StreamProtocol`).
#   Tests/checks/lock-policy/run.sh             compile and run the check
#   Tests/checks/lock-policy/run.sh --mutants   one-line mutants of LockPolicy.swift and LockedMac; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
python3 "$here/../module.py" "$name" "$root" "$out/check"
